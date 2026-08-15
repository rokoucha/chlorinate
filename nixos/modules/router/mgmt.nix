{ lib, routerConst, ... }:
let
  inherit (routerConst)
    lanTrunkIf
    mgmtLanIf
    homeLanIf
    serverLanIf
    materiaLanIf
    itscomIf
    lanDhcpServerConfig
    warpDomains
    ;
in
{
  services.dnsmasq = {
    enable = true;
    settings = {
      domain-needed = true;
      bogus-priv = true;
      bind-dynamic = true;
      no-resolv = true;
      server = [
        "127.0.0.53"
      ];
      # Populate routing targets from DNS answers. Both the original site and
      # challenges.cloudflare.com must use the same WARP egress.
      nftset = [
        "/${lib.concatStringsSep "/" warpDomains}/4#inet#filter#warp_targets_v4,6#inet#filter#warp_targets_v6"
      ];
      interface = [
        mgmtLanIf
        homeLanIf
        serverLanIf
      ];
    };
  };

  systemd.services.dnsmasq = {
    after = [ "nftables.service" ];
    requires = [ "nftables.service" ];
  };

  systemd.network = {
    netdevs = {
      "20-lan-vlan" = {
        netdevConfig = {
          Name = homeLanIf;
          Kind = "vlan";
        };
        vlanConfig.Id = 10;
      };

      "20-${serverLanIf}" = {
        netdevConfig = {
          Name = serverLanIf;
          Kind = "vlan";
        };
        vlanConfig.Id = 20;
      };

      "20-${materiaLanIf}" = {
        netdevConfig = {
          Name = materiaLanIf;
          Kind = "vlan";
        };
        vlanConfig.Id = 30;
      };

      "20-${itscomIf}" = {
        netdevConfig = {
          Name = itscomIf;
          Kind = "vlan";
        };
        vlanConfig.Id = 200;
      };
    };

    networks."20-lan" = {
      matchConfig.Name = lanTrunkIf;
      vlan = [
        homeLanIf
        serverLanIf
        materiaLanIf
        itscomIf
      ];
      networkConfig = {
        Address = "172.16.0.1/24";
        DHCPServer = true;
        IPv4Forwarding = true;
      };
      dhcpServerConfig = lanDhcpServerConfig "172.16.0.1";
    };
  };
}
