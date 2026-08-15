{
  routerConst,
  ...
}:
let
  inherit (routerConst) warpTapIf warpHostV4 warpGuestV4;
  warpMac = "02:00:00:01:33:35";
in
{
  networking.hostName = "warp-gateway";
  system.stateVersion = "26.05";

  microvm = {
    hypervisor = "cloud-hypervisor";
    registerWithMachined = true;
    vsock.cid = 13335;
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

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.all.accept_ra" = 2;
  };

  networking = {
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
    nftables = {
      enable = true;
      ruleset = ''
        table inet warp_gateway {
          chain input {
            type filter hook input priority filter; policy drop;
            iifname lo accept
            ct state established,related accept
            iifname "${warpTapIf}" meta l4proto { icmp, ipv6-icmp } accept
          }

          chain forward {
            type filter hook forward priority filter; policy drop;
            ct state established,related accept
            iifname "${warpTapIf}" oifname "CloudflareWARP" accept
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
