{ cloudflareDdns, routerConst, ... }:
let
  inherit (routerConst) serverLanIf;
in
{
  systemd.services.cloudflare-ddns = {
    description = "Cloudflare DDNS update for chlorine.dns.gg";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    partOf = [ "networkd-prefix-changed.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${cloudflareDdns}/bin/cloudflare-ddns --suffix dns --interface ${serverLanIf} ggrel.net";
      EnvironmentFile = "/var/lib/cloudflare-ddns/api-token";
    };
    wantedBy = [ "networkd-prefix-changed.target" ];
  };

  systemd.timers.cloudflare-ddns = {
    description = "Cloudflare DDNS update timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "5min";
    };
  };
}
