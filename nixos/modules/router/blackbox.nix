{ pkgs, routerConst, ... }:
let
  inherit (routerConst) itscomV4;
in
{
  services.prometheus.exporters.blackbox = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9115;
    configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON {
      modules = {
        icmp_v4 = {
          prober = "icmp";
          timeout = "5s";
          icmp.preferred_ip_protocol = "ip4";
        };
        icmp_v4_itscom = {
          prober = "icmp";
          timeout = "5s";
          icmp = {
            preferred_ip_protocol = "ip4";
            source_ip_address = itscomV4;
          };
        };
        icmp_v6 = {
          prober = "icmp";
          timeout = "5s";
          icmp.preferred_ip_protocol = "ip6";
        };
        icmp_v6_br = {
          prober = "icmp";
          timeout = "5s";
          icmp.preferred_ip_protocol = "ip6";
        };
        http_v6 = {
          prober = "http";
          timeout = "10s";
          http = {
            method = "GET";
            preferred_ip_protocol = "ip6";
            ip_protocol_fallback = false;
          };
        };
      };
    });
  };
}
