{
  config,
  lib,
  pkgs,
  routerConst,
  ...
}:
let
  cfg = config.services.materia-pd;
  inherit (routerConst) serverLanIf materiaLanIf wanIf;
  script = ./pd-reconcile.py;
  gateways = pkgs.writeText "materia-node-gateways.json" (
    builtins.toJSON {
      hydrogen = "fe80::da9e:f3ff:fe9d:854e";
      lithium = "fe80::6e4b:90ff:feef:5391";
      phosphorus = "fe80::1e69:7aff:fea4:f698";
    }
  );
in
{
  options.services.materia-pd.enable = lib.mkEnableOption "materia DHCP-PD reconciliation";
  config = lib.mkIf cfg.enable {
    systemd.services.cilium-lb-ipv6-pool-updater.enable = false;
    systemd.timers.cilium-lb-ipv6-pool-updater.enable = false;
    systemd.services.materia-pd = {
      description = "Reconcile materia IPv6 pools, boundary and routes from DHCP-PD";
      after = [
        "network-online.target"
        "nftables.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [
        "multi-user.target"
        "networkd-prefix-changed.target"
        "nftables.service"
      ];
      partOf = [
        "networkd-prefix-changed.target"
        "nftables.service"
      ];
      restartTriggers = [ (pkgs.writeText "pd-boundary-rules" config.networking.nftables.ruleset) ];
      path = [
        pkgs.iproute2
        pkgs.nftables
        pkgs.kubectl
        pkgs.systemd
        pkgs.curl
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${script} --kubeconfig /var/lib/cilium-lb-ipv6-pool-updater/kubeconfig --gateways ${gateways} --lan ${serverLanIf} --lb-lan ${materiaLanIf} --wan ${wanIf}";
        TimeoutStartSec = "2min";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        Environment = [
          "HOME=/run/materia-pd"
          "PYTHONDONTWRITEBYTECODE=1"
        ];
        RuntimeDirectory = "materia-pd";
        CapabilityBoundingSet = [
          "CAP_NET_ADMIN"
          "CAP_DAC_READ_SEARCH"
        ];
      };
    };
    systemd.timers.materia-pd = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitInactiveSec = "15s";
        AccuracySec = "1s";
      };
    };
    systemd.services.materia-pd-events = {
      description = "Trigger materia reconciliation on DHCP-PD route changes";
      after = [ "systemd-networkd.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.iproute2
        pkgs.systemd
        pkgs.gnugrep
      ];
      script = ''
        ip -6 monitor route | while IFS= read -r event; do
          if echo "$event" | grep -q 'unreachable .*proto dhcp'; then
            systemctl --no-block start materia-pd.service
          fi
        done
      '';
      serviceConfig.Restart = "always";
      serviceConfig.RestartSec = "5s";
    };
  };
}
