{ routerConst, ... }:
let
  inherit (routerConst)
    wanIf
    tailscaleIf
    serverLanIf
    itscomIf
    ;
in
{
  boot = {
    kernelModules = [
      "ip6_tunnel"
      "ip6_udp_tunnel"
      "nf_conntrack"
      "nf_nat"
    ];

    kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv6.conf.${wanIf}.accept_ra" = 2;
      "net.netfilter.nf_conntrack_max" = 524288;
      "net.netfilter.nf_conntrack_tcp_timeout_established" = 3600;
      "net.netfilter.nf_conntrack_udp_timeout" = 60;
      "net.core.fb_tunnels_only_for_init_net" = 2;
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
      "net.ipv4.conf.${tailscaleIf}.rp_filter" = 0;
      "net.ipv4.conf.${serverLanIf}.rp_filter" = 0;
      "net.ipv4.conf.${itscomIf}.rp_filter" = 0;
      # Allow traffic hairpinned from the MAP-E address to the iTSCOM NAPT path.
      "net.ipv4.conf.${serverLanIf}.accept_local" = 1;
      "net.ipv4.conf.${itscomIf}.accept_local" = 1;
    };
  };
}
