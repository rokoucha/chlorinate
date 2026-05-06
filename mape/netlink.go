//go:build linux

package main

import (
	"fmt"
	"net"
	"syscall"

	"github.com/vishvananda/netlink"
)

// findPrefix scans the WAN interface's IPv6 addresses and returns the first
// one contained within ruleIPv6 as a /64 prefix network.
func findPrefix(wanIf string, ruleIPv6 net.IPNet) (*net.IPNet, error) {
	link, err := netlink.LinkByName(wanIf)
	if err != nil {
		return nil, fmt.Errorf("lookup %s: %w", wanIf, err)
	}

	addrs, err := netlink.AddrList(link, netlink.FAMILY_V6)
	if err != nil {
		return nil, fmt.Errorf("list addrs on %s: %w", wanIf, err)
	}

	for _, a := range addrs {
		if ruleIPv6.Contains(a.IP) {
			masked := a.IP.Mask(net.CIDRMask(64, 128))
			return &net.IPNet{IP: masked, Mask: net.CIDRMask(64, 128)}, nil
		}
	}

	return nil, fmt.Errorf("no IPv6 address on %s within %s", wanIf, ruleIPv6.String())
}

// buildCEIPv6 combines the top 64 bits of prefix with the bottom 64 bits of
// the token interface ID (e.g. "::6a:483f:6c00:d400") to form the CE IPv6 address.
func buildCEIPv6(prefix *net.IPNet, token string) (net.IP, error) {
	tokenIP := net.ParseIP(token)
	if tokenIP == nil {
		return nil, fmt.Errorf("parse token %q as IPv6", token)
	}
	tokenIP = tokenIP.To16()

	pfx := prefix.IP.To16()
	if pfx == nil {
		return nil, fmt.Errorf("prefix IP is not IPv6")
	}

	addr := make(net.IP, 16)
	copy(addr[0:8], pfx[0:8])
	copy(addr[8:16], tokenIP[8:16])
	return addr, nil
}

func applyNetlink(params *Params, cfg *config, prefix *net.IPNet) error {
	ceAddr, err := buildCEIPv6(prefix, params.Token)
	if err != nil {
		return fmt.Errorf("compute CE IPv6: %w", err)
	}

	return netlinkApplyOrder(
		func() error {
			if err := assignWANAddr(cfg, ceAddr, prefix.Mask); err != nil {
				return fmt.Errorf("assign CE IPv6 to %s: %w", cfg.wanIf, err)
			}
			return nil
		},
		func() error {
			if err := setupTunnel(params, cfg, ceAddr); err != nil {
				return fmt.Errorf("setup tunnel %s: %w", cfg.tunIf, err)
			}
			return nil
		},
	)
}

// rollbackNetlink removes the CE IPv6 address from the WAN interface and
// deletes the tunnel. Both are attempted regardless of individual errors.
func rollbackNetlink(params *Params, cfg *config, prefix *net.IPNet) error {
	ceAddr, err := buildCEIPv6(prefix, params.Token)
	if err != nil {
		return fmt.Errorf("rollback: compute CE IPv6: %w", err)
	}
	return netlinkRollbackOrder(
		func() error { return removeWANAddr(cfg, ceAddr) },
		func() error { return teardownTunnel(cfg) },
	)
}

// removeWANAddr removes the CE IPv6 address from the WAN interface if present.
func removeWANAddr(cfg *config, ceAddr net.IP) error {
	wanLink, err := netlink.LinkByName(cfg.wanIf)
	if err != nil {
		return fmt.Errorf("lookup %s: %w", cfg.wanIf, err)
	}
	existing, err := netlink.AddrList(wanLink, netlink.FAMILY_V6)
	if err != nil {
		return fmt.Errorf("list addrs on %s: %w", cfg.wanIf, err)
	}
	for _, a := range existing {
		if a.IP.Equal(ceAddr) {
			if err := netlink.AddrDel(wanLink, &a); err != nil {
				return fmt.Errorf("remove %s from %s: %w", ceAddr, cfg.wanIf, err)
			}
			fmt.Printf("Removed CE IPv6 %s from %s\n", ceAddr, cfg.wanIf)
			return nil
		}
	}
	return nil // already gone
}

// teardownTunnel deletes the MAP-E tunnel interface. Used as rollback when
// applyNftables fails after applyNetlink succeeded.
func teardownTunnel(cfg *config) error {
	existing, err := netlink.LinkByName(cfg.tunIf)
	if err != nil {
		return nil // already gone
	}
	if err := netlink.LinkDel(existing); err != nil {
		return fmt.Errorf("delete %s during rollback: %w", cfg.tunIf, err)
	}
	fmt.Printf("Rolled back: deleted %s\n", cfg.tunIf)
	return nil
}

// tunnelUnchanged returns true when the existing link is an ip6tnl tunnel
// whose parameters match what we would create: same local/remote addresses,
// IPIP proto, ignore-encap-limit flag, and MTU.
func tunnelUnchanged(existing netlink.Link, ceAddr net.IP, cfg *config) bool {
	tun, ok := existing.(*netlink.Ip6tnl)
	if !ok {
		return false
	}
	return tun.Local.Equal(ceAddr) &&
		tun.Remote.Equal(cfg.brAddr.To16()) &&
		tun.Proto == syscall.IPPROTO_IPIP &&
		tun.Flags == 0x1 && // IP6_TNL_F_IGN_ENCAP_LIMIT
		existing.Attrs().MTU == cfg.tunMTU
}

// setupTunnel creates (or recreates) the ip6tnl tunnel device, assigns
// CE IPv4/32, and adds the default link-scoped route.
func setupTunnel(params *Params, cfg *config, ceAddr net.IP) error {
	if existing, err := netlink.LinkByName(cfg.tunIf); err == nil {
		if tunnelUnchanged(existing, ceAddr, cfg) {
			fmt.Printf("Tunnel %s unchanged, skipping recreation\n", cfg.tunIf)
			return ensureCEAddr(existing, params.CeIPv4)
		}
		if err := netlink.LinkDel(existing); err != nil {
			return fmt.Errorf("delete existing %s: %w", cfg.tunIf, err)
		}
		fmt.Printf("Deleted existing %s (parameters changed)\n", cfg.tunIf)
	}

	// Proto=IPPROTO_IPIP(4): IPv4-in-IPv6 (ipip6 mode)
	// Flags=0x1: IP6_TNL_F_IGN_ENCAP_LIMIT (EncapsulationLimit=none)
	tun := &netlink.Ip6tnl{
		LinkAttrs: netlink.LinkAttrs{
			Name: cfg.tunIf,
			MTU:  cfg.tunMTU,
		},
		Local:  ceAddr,
		Remote: cfg.brAddr.To16(),
		Proto:  syscall.IPPROTO_IPIP,
		Flags:  0x1,
	}

	if err := netlink.LinkAdd(tun); err != nil {
		return fmt.Errorf("create ip6tnl %s: %w", cfg.tunIf, err)
	}
	fmt.Printf("Created ip6tnl %s (local=%s remote=%s)\n", cfg.tunIf, ceAddr, cfg.brAddr)

	link, err := netlink.LinkByName(cfg.tunIf)
	if err != nil {
		return fmt.Errorf("lookup %s after create: %w", cfg.tunIf, err)
	}

	if err := netlink.LinkSetUp(link); err != nil {
		return fmt.Errorf("set %s up: %w", cfg.tunIf, err)
	}

	v4Addr := &netlink.Addr{
		IPNet: &net.IPNet{
			IP:   params.CeIPv4.To4(),
			Mask: net.CIDRMask(32, 32),
		},
	}
	if err := netlink.AddrAdd(link, v4Addr); err != nil {
		return fmt.Errorf("add %s/32 to %s: %w", params.CeIPv4, cfg.tunIf, err)
	}
	fmt.Printf("Added %s/32 to %s\n", params.CeIPv4, cfg.tunIf)

	_, defaultDst, _ := net.ParseCIDR("0.0.0.0/0")
	route := &netlink.Route{
		LinkIndex: link.Attrs().Index,
		Dst:       defaultDst,
		Scope:     netlink.SCOPE_LINK,
	}
	if err := netlink.RouteAdd(route); err != nil {
		return fmt.Errorf("add default route on %s: %w", cfg.tunIf, err)
	}
	fmt.Printf("Added 0.0.0.0/0 scope link via %s\n", cfg.tunIf)

	return nil
}

// ensureCEAddr checks that CE IPv4/32 is already on the tunnel and adds it if
// missing. Used when the tunnel is reused without recreation.
func ensureCEAddr(link netlink.Link, ceIPv4 net.IP) error {
	addrs, err := netlink.AddrList(link, netlink.FAMILY_V4)
	if err != nil {
		return fmt.Errorf("list addrs on %s: %w", link.Attrs().Name, err)
	}
	for _, a := range addrs {
		if a.IP.Equal(ceIPv4.To4()) {
			fmt.Printf("CE IPv4 %s already on %s, skipping\n", ceIPv4, link.Attrs().Name)
			return nil
		}
	}
	addr := &netlink.Addr{
		IPNet: &net.IPNet{IP: ceIPv4.To4(), Mask: net.CIDRMask(32, 32)},
	}
	if err := netlink.AddrAdd(link, addr); err != nil {
		return fmt.Errorf("add %s/32 to %s: %w", ceIPv4, link.Attrs().Name, err)
	}
	fmt.Printf("Added %s/32 to %s\n", ceIPv4, link.Attrs().Name)
	return nil
}

// assignWANAddr adds the CE IPv6 address to the WAN interface, skipping if
// already present.
func assignWANAddr(cfg *config, ceAddr net.IP, mask net.IPMask) error {
	wanLink, err := netlink.LinkByName(cfg.wanIf)
	if err != nil {
		return fmt.Errorf("lookup %s: %w", cfg.wanIf, err)
	}

	existing, err := netlink.AddrList(wanLink, netlink.FAMILY_V6)
	if err != nil {
		return fmt.Errorf("list addrs on %s: %w", cfg.wanIf, err)
	}
	for _, a := range existing {
		if a.IP.Equal(ceAddr) {
			fmt.Printf("CE IPv6 %s already on %s, skipping\n", ceAddr, cfg.wanIf)
			return nil
		}
	}

	addr := &netlink.Addr{
		IPNet: &net.IPNet{IP: ceAddr, Mask: mask},
	}
	if err := netlink.AddrAdd(wanLink, addr); err != nil {
		return fmt.Errorf("add %s to %s: %w", addr.IPNet, cfg.wanIf, err)
	}
	fmt.Printf("Added %s to %s\n", addr.IPNet, cfg.wanIf)
	return nil
}
