{ routerConst, ... }:
let
  inherit (routerConst)
    wanIf
    serverLanIf
    itscomIf
    itscomV4
    materiaRouterASN
    materiaClusterASN
    materiaBgpPeerV4
    materiaBgpPeerV6
    materiaLbIPv4Pool
    materiaLbIPv6Pool
    lanDhcpServerConfig
    ;
in
{
  services.frr = {
    bgpd.enable = true;
    config = ''
      ip prefix-list MATERIA-LB-V4 seq 10 permit ${materiaLbIPv4Pool} ge 32 le 32
      ipv6 prefix-list MATERIA-LB-V6 seq 10 permit ${materiaLbIPv6Pool} ge 128 le 128

      route-map MATERIA-LB-V4-IN permit 10
       match ip address prefix-list MATERIA-LB-V4
      exit
      route-map MATERIA-LB-V4-IN deny 100
      exit

      route-map MATERIA-LB-V6-IN permit 10
       match ipv6 address prefix-list MATERIA-LB-V6
      exit
      route-map MATERIA-LB-V6-IN deny 100
      exit

      route-map MATERIA-LB-OUT deny 100
      exit

      router bgp ${toString materiaRouterASN}
       bgp router-id 172.16.2.1
       neighbor ${materiaBgpPeerV4} remote-as ${toString materiaClusterASN}
       neighbor ${materiaBgpPeerV4} description materia-srv-lan
       neighbor ${materiaBgpPeerV4} update-source 172.16.2.1
       neighbor ${materiaBgpPeerV6} remote-as ${toString materiaClusterASN}
       neighbor ${materiaBgpPeerV6} description materia-srv-lan-v6
       !
       address-family ipv4 unicast
        neighbor ${materiaBgpPeerV4} activate
        neighbor ${materiaBgpPeerV4} route-map MATERIA-LB-V4-IN in
        neighbor ${materiaBgpPeerV4} route-map MATERIA-LB-OUT out
       exit-address-family
       !
       address-family ipv6 unicast
        neighbor ${materiaBgpPeerV6} activate
        neighbor ${materiaBgpPeerV6} route-map MATERIA-LB-V6-IN in
        neighbor ${materiaBgpPeerV6} route-map MATERIA-LB-OUT out
       exit-address-family
    '';
  };

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
