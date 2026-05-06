package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/spf13/cobra"
)

type applyFlags struct {
	bmrFlags
	tunIf  string
	tunMTU int
	runDir string
	dryRun bool
}

type config struct {
	bmrConfig
	tunIf  string
	tunMTU int
	runDir string
}

func newApplyCmd() *cobra.Command {
	f := &applyFlags{}
	cmd := &cobra.Command{
		Use:   "apply",
		Short: "Apply MAP-E tunnel configuration",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runApply(f)
		},
	}
	addBMRFlags(cmd, &f.bmrFlags)
	cmd.Flags().StringVar(&f.tunIf, "tun-if", "mape0", "tunnel interface name")
	cmd.Flags().IntVar(&f.tunMTU, "tun-mtu", 1460, "tunnel MTU")
	cmd.Flags().StringVar(&f.runDir, "run-dir", "/run/mape", "directory for mape.nft")
	cmd.Flags().BoolVar(&f.dryRun, "dry-run", false, "print what would be done without applying")
	return cmd
}

func buildConfig(f *applyFlags) (*config, error) {
	bmr, err := buildBMRConfig(&f.bmrFlags)
	if err != nil {
		return nil, err
	}
	return &config{
		bmrConfig: *bmr,
		tunIf:     f.tunIf,
		tunMTU:    f.tunMTU,
		runDir:    f.runDir,
	}, nil
}

func runApply(f *applyFlags) error {
	cfg, err := buildConfig(f)
	if err != nil {
		return err
	}

	prefix, err := findPrefix(cfg.wanIf, cfg.ruleIPv6)
	if err != nil {
		return fmt.Errorf("find prefix on %s: %w", cfg.wanIf, err)
	}

	params, err := Derive(*prefix, BMR{
		IPv6Prefix: cfg.ruleIPv6,
		IPv4Prefix: cfg.ruleIPv4,
		EABits:     cfg.eaBits,
		PSIDBits:   cfg.psidBits,
		PSIDOffset: cfg.psidOffset,
		BRAddr:     cfg.brAddr,
	})
	if err != nil {
		return err
	}

	printParams(prefix, params, cfg.wanIf)

	if f.dryRun {
		fmt.Println("--- nftables ruleset (dry-run) ---")
		fmt.Print(nftablesRuleset(params, cfg.tunIf))
		return nil
	}

	nftFile, err := writeNftables(params, cfg)
	if err != nil {
		return fmt.Errorf("write nftables: %w", err)
	}

	return applyOps(
		func() error {
			if err := applyNetlink(params, cfg, prefix); err != nil {
				return fmt.Errorf("apply netlink: %w", err)
			}
			return nil
		},
		func() error {
			if err := applyNftables(nftFile); err != nil {
				return fmt.Errorf("apply nftables: %w", err)
			}
			return nil
		},
		func() error {
			if err := rollbackNetlink(params, cfg, prefix); err != nil {
				return fmt.Errorf("rollback: %w", err)
			}
			return nil
		},
	)
}

func writeNftables(p *Params, cfg *config) (string, error) {
	if err := os.MkdirAll(cfg.runDir, 0o755); err != nil {
		return "", fmt.Errorf("mkdir %s: %w", cfg.runDir, err)
	}

	nftFile := filepath.Join(cfg.runDir, "mape.nft")
	if err := os.WriteFile(nftFile, []byte(nftablesRuleset(p, cfg.tunIf)), 0o644); err != nil {
		return "", fmt.Errorf("write %s: %w", nftFile, err)
	}

	fmt.Printf("Wrote %s\n", nftFile)
	return nftFile, nil
}

func applyNftables(nftFile string) error {
	cmd := exec.Command("nft", "-f", nftFile)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("nft -f %s: %w", nftFile, err)
	}
	fmt.Println("Applied nftables rules")
	return nil
}
