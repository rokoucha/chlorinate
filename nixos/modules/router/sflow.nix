{ pkgs, routerConst, ... }:
let
  hostSflow = pkgs.callPackage ../../../pkgs/host-sflow.nix { };
  configFile = pkgs.writeText "hsflowd.conf" ''
    sflow {
      agent = ${routerConst.homeLanIf}
      polling = 30
      sampling.bps_ratio = 0
      sampling = 100
      headerBytes = 128
      collector { ip = 172.16.3.12 udpport = 6343 }
      pcap { dev = ${routerConst.homeLanIf} }
    }
  '';
in
{
  systemd.services.hsflowd = {
    description = "Sample home LAN traffic for materia flow accounting";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${hostSflow}/bin/hsflowd -d -f ${configFile} -l ${hostSflow}/lib/hsflowd -p /run/hsflowd/hsflowd.pid -o /run/hsflowd/hsflowd.auto";
      Restart = "on-failure";
      RestartSec = "5s";
      RuntimeDirectory = "hsflowd";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      CapabilityBoundingSet = [ "CAP_NET_RAW" "CAP_NET_ADMIN" "CAP_SETUID" "CAP_SETGID" ];
      MemoryMax = "128M";
      CPUQuota = "25%";
    };
  };
}
