{
  pkgs,
  routerConst,
  ...
}:
let
  inherit (routerConst) warpTapIf warpHostV4 warpGuestV4;
  warpMac = "02:00:00:01:33:35";
  guestIf = "ens3";
  # Match warp-router's endpoint selection: carry the WARP tunnel over IPv6
  # instead of letting warp-svc prefer an IPv4 MASQUE endpoint.
  warpEndpoint = "[2606:4700:100::a29f:c101]:2408";
in
{
  networking.hostName = "warp-gateway";
  system.stateVersion = "26.05";

  microvm = {
    hypervisor = "cloud-hypervisor";
    registerWithMachined = true;
    vsock = {
      cid = 13335;
      ssh.enable = true;
    };
    vcpu = 1;
    mem = 512;
    interfaces = [
      {
        type = "tap";
        id = warpTapIf;
        mac = warpMac;
      }
    ];
    shares = [
      {
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        tag = "ro-store";
        proto = "virtiofs";
      }
      {
        source = "/var/lib/microvms/warp-gateway-ssh/public";
        mountPoint = "/run/host-ssh";
        tag = "host-ssh";
        proto = "virtiofs";
      }
    ];
    volumes = [
      {
        image = "cloudflare-warp-state.img";
        mountPoint = "/var/lib/cloudflare-warp";
        size = 512;
      }
    ];
  };

  services.cloudflare-warp = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.cloudflare-warp-ipv6-endpoint = {
    description = "Pin the Cloudflare WARP tunnel to an IPv6 endpoint";
    wantedBy = [ "multi-user.target" ];
    after = [
      "cloudflare-warp.service"
      "network-online.target"
    ];
    requires = [ "cloudflare-warp.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.cloudflare-warp ];
    script = ''
      for attempt in $(seq 1 30); do
        if warp-cli --accept-tos tunnel endpoint set '${warpEndpoint}'; then
          exit 0
        fi
        sleep 1
      done
      echo "Failed to configure the WARP IPv6 endpoint" >&2
      exit 1
    '';
  };

  # warp-svc 2026.3 cannot parse NixOS systemd's `260.2` version string when
  # selecting its systemd-resolved backend. Keep connector DNS file-based;
  # the guest does not provide DNS to any other machine.
  services.resolved.enable = false;

  # cloud-hypervisor cannot provide a PTY through `machinectl shell`. Use the
  # host-only vsock SSH transport with its dedicated host-generated key. TCP/22
  # remains blocked by the guest firewall below.
  users.users.root.hashedPassword = "!";
  services.openssh.settings = {
    AuthorizedKeysFile = "/run/host-ssh/authorized_keys";
    PermitRootLogin = "prohibit-password";
    PasswordAuthentication = false;
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.all.accept_ra" = 2;
  };

  networking = {
    useDHCP = false;
    useNetworkd = true;
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
    ];
    firewall.enable = false;
    nftables = {
      enable = true;
      ruleset = ''
        table inet warp_gateway {
          chain input {
            type filter hook input priority filter; policy drop;
            iifname lo accept
            ct state established,related accept
            iifname "${guestIf}" meta l4proto { icmp, ipv6-icmp } accept
          }

          chain forward {
            type filter hook forward priority filter; policy drop;
            ct state established,related accept
            iifname "${guestIf}" oifname "CloudflareWARP" accept
          }
        }

        table ip warp_gateway_nat {
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            oifname "CloudflareWARP" masquerade
          }
        }
      '';
    };
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;
    networks."10-warp-host" = {
      matchConfig.MACAddress = warpMac;
      address = [ "${warpGuestV4}/30" ];
      networkConfig = {
        DNS = [ "1.1.1.1" "2606:4700:4700::1111" ];
        IPv6AcceptRA = true;
        IPv4Forwarding = true;
        IPv6Forwarding = true;
      };
      routes = [
        {
          Destination = "0.0.0.0/0";
          Gateway = warpHostV4;
          GatewayOnLink = true;
        }
      ];
      linkConfig.RequiredForOnline = "routable";
    };
  };

  # The connector token is deliberately not part of the Nix configuration.
  # Enrol once after deployment with:
  #   warp-cli connector new <token>
  #   warp-cli connect
}
