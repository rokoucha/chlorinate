{
  config,
  lib,
  pkgs,
  mapeTool,
  ...
}:

let
  deployUnit = "nixos-deploy.service";

  nixosDeployScript = pkgs.writeShellScriptBin "nixos-deploy" ''
    set -euo pipefail

    unit=${deployUnit}
    systemctl=${pkgs.systemd}/bin/systemctl
    journalctl=${pkgs.systemd}/bin/journalctl
    systemd_run=${pkgs.systemd}/bin/systemd-run

    prop() {
      "$systemctl" show "$unit" --property="$1" --value 2>/dev/null || true
    }

    start() {
      case "$(prop ActiveState)" in
      activating | deactivating | reloading)
        echo "nixos-deploy: a switch is already running; leaving it alone." >&2
        return 0
        ;;
      esac

      "$systemctl" stop "$unit" >/dev/null 2>&1 || true
      "$systemctl" reset-failed "$unit" >/dev/null 2>&1 || true
      for _ in $(seq 1 10); do
        if [ "$(prop LoadState)" = "not-found" ]; then break; fi
        sleep 1
      done

      "$systemd_run" \
        --unit="$unit" \
        --description="nixos-rebuild switch (chlorinate CD)" \
        --service-type=oneshot \
        --property=RemainAfterExit=yes \
        --property=TimeoutStartSec=infinity \
        --setenv=PATH=/run/wrappers/bin:/run/current-system/sw/bin \
        --setenv=HOME=/root \
        --no-block \
        -- /run/current-system/sw/bin/nixos-rebuild switch \
        --flake github:rokoucha/chlorinate#chlorine \
        --refresh

      for _ in $(seq 1 30); do
        if [ "$(prop ActiveState)" != "inactive" ]; then break; fi
        sleep 1
      done

      echo "nixos-deploy: started $unit (invocation $(prop InvocationID))" >&2
    }

    follow() {
      journal_pid=""
      invocation="$(prop InvocationID)"

      if [ -n "$invocation" ]; then
        "$journalctl" --follow --lines=all --no-pager --output=cat \
          "_SYSTEMD_INVOCATION_ID=$invocation" &
        journal_pid=$!
      fi

      while :; do
        case "$(prop ActiveState)" in
        activating | deactivating | reloading) sleep 2 ;;
        *) break ;;
        esac
      done

      sleep 2
      if [ -n "$journal_pid" ]; then
        kill "$journal_pid" 2>/dev/null || true
        wait "$journal_pid" 2>/dev/null || true
      fi

      case "$(prop ActiveState)" in
      active)
        echo "nixos-deploy: switch finished successfully." >&2
        return 0
        ;;
      failed)
        echo "nixos-deploy: switch failed (result $(prop Result), exit status $(prop ExecMainStatus))." >&2
        return 1
        ;;
      *)
        echo "nixos-deploy: nothing to wait for ($unit is $(prop LoadState)/$(prop ActiveState))." >&2
        return 69
        ;;
      esac
    }

    case "''${SSH_ORIGINAL_COMMAND:-deploy}" in
    deploy)
      start
      follow
      ;;
    start)
      start
      ;;
    wait)
      follow
      ;;
    status)
      "$systemctl" status "$unit" --no-pager || true
      ;;
    *)
      echo "nixos-deploy: unknown command: ''${SSH_ORIGINAL_COMMAND:-}" >&2
      echo "nixos-deploy: expected one of deploy, start, wait, status" >&2
      exit 64
      ;;
    esac
  '';
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/router
  ];

  networking.hostName = "chlorine";

  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "en_GB.UTF-8";

  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/etc/ssh/ssh_host_ecdsa_key";
        type = "ecdsa";
        bits = 256;
      }
    ];
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      PubkeyAcceptedAlgorithms = "ssh-ed25519,ecdsa-sha2-nistp256";
      HostKeyAlgorithms = "ssh-ed25519,ecdsa-sha2-nistp256";
    };
  };

  services.mackerel-agent = {
    enable = true;
    # Keep API key outside of Nix store.
    apiKeyFile = "/var/lib/mackerel-agent/conf.d/api-key.conf";
  };

  security.sudo.wheelNeedsPassword = false;

  users.users.root.hashedPassword = "!";

  users.users.rokoucha = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "systemd-network"
      "tss"
    ];
    openssh.authorizedKeys.keys = [
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBKfz/Xt552eET1ALcAGLPiF+7ecxUgDaFb2Wpoj2dwJNbMTMgSbf/uSO2Gf92WlKnrBHqq3wlpkKmj44Y1NWkBg= helium"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCpFZuDSmD3fYdkiC//bMx26LZqLc7/vyvGtraUf/CHzfPrMLTxCO+PDm0+ziJLWpJU2EpDEjnGzfsvAUj8/mIo= silicon"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFro2O+EEcgDG5+hTMZmW/nI4kVOEast52pXFsjjpvhh iPhone-16"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ2PgdZn8exGGP9omKddBRtu6QmHXGbEWv837YajSWY2 iPad-Air-M3"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBIHkGX9fHNiK8VWV8g2yzkkVG0rT676JVkRwOKgpOnn Pixel-9-Pro-Fold"
    ];
  };

  environment.systemPackages = with pkgs; [
    conntrack-tools
    ethtool
    git
    iperf3
    nftables
    pciutils
    sbctl
    sysstat
    tcpdump
    tpm2-tools
    tree
    vim
    wget
    mapeTool
    nixosDeployScript
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  users.users.deploy = {
    isSystemUser = true;
    group = "deploy";
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      "command=\"sudo --preserve-env=SSH_ORIGINAL_COMMAND /run/current-system/sw/bin/nixos-deploy\",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP1Bjc5BT+NhkVF0z+Cz7abnTOf3VmRUyzKokN4ToY0b chlorinate-cd"
    ];
  };

  users.groups.deploy = { };

  security.sudo.extraRules = [
    {
      users = [ "deploy" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-deploy";
          options = [
            "NOPASSWD"
            "SETENV"
          ];
        }
      ];
    }
  ];

  boot = {
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = lib.mkForce false;
    };

    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };

    initrd = {
      availableKernelModules = [
        "tpm_tis"
        "tpm_crb"
      ];
      systemd = {
        enable = true;
        tpm2.enable = true;
      };
    };
  };

  security.tpm2 = {
    enable = true;
    tctiEnvironment.enable = true;
  };

  system.stateVersion = "25.11";
}
