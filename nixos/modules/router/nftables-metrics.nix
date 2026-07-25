{ pkgs, ... }:
let
  textfileDir = "/var/lib/node-exporter/textfile";

  # node_exporter has no nftables collector, so scrape the named counters
  # declared in firewall.nix and hand them over via the textfile collector.
  writer = pkgs.writeShellScript "nftables-metrics" ''
    set -euo pipefail

    out="${textfileDir}/nftables.prom"
    tmp="$out.$$"

    {
      echo '# HELP nftables_counter_packets_total Packets matched by a named nftables counter.'
      echo '# TYPE nftables_counter_packets_total counter'
      echo '# HELP nftables_counter_bytes_total Bytes matched by a named nftables counter.'
      echo '# TYPE nftables_counter_bytes_total counter'
      nft -j list counters | jq -r '
        .nftables[] | select(has("counter")) | .counter |
        "nftables_counter_packets_total{family=\"\(.family)\",table=\"\(.table)\",name=\"\(.name)\"} \(.packets)",
        "nftables_counter_bytes_total{family=\"\(.family)\",table=\"\(.table)\",name=\"\(.name)\"} \(.bytes)"
      '
    } > "$tmp"

    chmod 0644 "$tmp"
    # The textfile collector reads whole files, so swap it in atomically.
    mv "$tmp" "$out"
  '';
in
{
  services.prometheus.exporters.node.extraFlags = [
    "--collector.textfile.directory=${textfileDir}"
  ];

  systemd.tmpfiles.rules = [
    "d ${textfileDir} 0755 root root -"
  ];

  systemd.services.nftables-metrics = {
    description = "Export nftables named counters for node_exporter";
    path = [
      pkgs.nftables
      pkgs.jq
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = writer;
      # Reading counters needs CAP_NET_ADMIN, so this stays root.
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ textfileDir ];
    };
  };

  systemd.timers.nftables-metrics = {
    description = "Refresh nftables counter metrics";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";
      # otelcol scrapes node_exporter every 30s.
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
      Unit = "nftables-metrics.service";
    };
  };
}
