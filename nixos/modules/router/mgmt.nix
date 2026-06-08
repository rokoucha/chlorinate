{ routerConst, ... }:
let
  inherit (routerConst)
    lanTrunkIf
    mgmtLanIf
    homeLanIf
    serverLanIf
    itscomIf
    lanDhcpServerConfig
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
      interface = [
        mgmtLanIf
        homeLanIf
        serverLanIf
      ];
    };
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
