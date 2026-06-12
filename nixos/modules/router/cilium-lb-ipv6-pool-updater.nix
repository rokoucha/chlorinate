{
  ciliumLbIpv6PoolUpdater,
  routerConst,
  ...
}:
let
  inherit (routerConst) materiaLanIf;
in
{
  systemd.services.cilium-lb-ipv6-pool-updater = {
    description = "Update Cilium LoadBalancer IPv6 pool from router interface";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    partOf = [ "networkd-prefix-changed.target" ];
    wantedBy = [ "networkd-prefix-changed.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        ${ciliumLbIpv6PoolUpdater}/bin/cilium-lb-ipv6-pool-updater \
          --iface ${materiaLanIf} \
          --pool-name materia-public-ipv6 \
          --pool-prefix-len 112 \
          --pool-suffix ffff \
          --kubeconfig /var/lib/cilium-lb-ipv6-pool-updater/kubeconfig
      '';
      User = "root";
      Group = "root";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/cilium-lb-ipv6-pool-updater" ];
      PrivateTmp = true;
    };
  };

  systemd.timers.cilium-lb-ipv6-pool-updater = {
    description = "Periodically update Cilium LoadBalancer IPv6 pool";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      AccuracySec = "30s";
      Persistent = true;
    };
  };
}
