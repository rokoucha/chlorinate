{ pkgs, routerConst, ... }:
let
  inherit (routerConst) wanIf homeLanIf lanDhcpServerConfig;
in
{
  services.tailscale = {
    enable = true;
    disableTaildrop = true;
    openFirewall = false;
    extraSetFlags = [
      "--advertise-exit-node"
      "--advertise-routes=172.16.1.0/24"
      "--accept-dns=false"
      "--netfilter-mode=off"
    ];
    useRoutingFeatures = "server";
  };

  environment.systemPackages = [ pkgs.tailscale ];

  systemd.network.networks."21-lan-vlan" = {
    matchConfig.Name = homeLanIf;
    networkConfig = {
      Address = "172.16.1.1/24";
      DHCPServer = true;
      IPv6SendRA = true;
      DHCPPrefixDelegation = true;
      IPv4Forwarding = true;
      IPv6Forwarding = true;
    };
    dhcpServerConfig = lanDhcpServerConfig "172.16.1.1";
    extraConfig = ''
      [IPv6SendRA]
      RouterLifetimeSec=1800
      EmitDNS=yes
      DNS=_link_local

      [DHCPPrefixDelegation]
      UplinkInterface=${wanIf}
      SubnetId=1
      Announce=yes
      Assign=yes
      Token=eui64
    '';
  };
}
