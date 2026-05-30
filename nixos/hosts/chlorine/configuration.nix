{
  config,
  lib,
  pkgs,
  mapeTool,
  ...
}:

let
  nixosDeployScript = pkgs.writeShellScriptBin "nixos-deploy" ''
    exec /run/current-system/sw/bin/nixos-rebuild switch \
      --flake github:rokoucha/chlorinate#chlorine \
      --refresh
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
      "command=\"sudo /run/current-system/sw/bin/nixos-deploy\",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP1Bjc5BT+NhkVF0z+Cz7abnTOf3VmRUyzKokN4ToY0b chlorinate-cd"
    ];
  };

  users.groups.deploy = { };

  security.sudo.extraRules = [
    {
      users = [ "deploy" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-deploy";
          options = [ "NOPASSWD" ];
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
