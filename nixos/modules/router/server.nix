{ routerConst, ... }:
let
  inherit (routerConst)
    wanIf
    serverLanIf
    materiaLanIf
    itscomIf
    itscomV4
    lanDhcpServerConfig
    ;
in
{
  systemd.network.networks = {
    "20-${serverLanIf}" = {
      matchConfig.Name = serverLanIf;
      networkConfig = {
        Address = "172.16.2.1/24";
        DHCPServer = true;
        IPv6SendRA = true;
        DHCPPrefixDelegation = true;
        IPv4Forwarding = true;
        IPv6Forwarding = true;
      };
      dhcpServerConfig = lanDhcpServerConfig "172.16.2.1";
      extraConfig = ''
        [RoutingPolicyRule]
        To=172.16.0.0/16
        Table=254
        Priority=100

        [RoutingPolicyRule]
        From=172.16.2.0/24
        Table=200
        Priority=200

        [IPv6SendRA]
        RouterLifetimeSec=1800
        EmitDNS=yes
        DNS=_link_local

        [DHCPPrefixDelegation]
        UplinkInterface=${wanIf}
        SubnetId=2
        Announce=yes
        Assign=yes
        Token=eui64
      '';
    };

    "20-${materiaLanIf}" = {
      matchConfig.Name = materiaLanIf;
      networkConfig = {
        Address = "172.16.3.1/24";
        IPv6SendRA = true;
        DHCPPrefixDelegation = true;
        IPv4Forwarding = true;
        IPv6Forwarding = true;
      };
      extraConfig = ''
        [IPv6SendRA]
        RouterLifetimeSec=1800
        EmitDNS=no

        [DHCPPrefixDelegation]
        UplinkInterface=${wanIf}
        SubnetId=3
        Announce=no
        Assign=yes
        Token=eui64
      '';
    };

    "20-${itscomIf}" = {
      matchConfig.Name = itscomIf;
      extraConfig = ''
        [Network]
        Address=${itscomV4}/29

        [Route]
        Gateway=172.16.254.9
        Table=200
        GatewayOnLink=yes
      '';
    };
  };
}
