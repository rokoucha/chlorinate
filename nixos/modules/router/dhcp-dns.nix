{ pkgs, routerConst, ... }:
{
  services.dnsmasq.settings = {
    addn-hosts = [ "/run/networkd-dns/hosts" ];
    local = [ "/home.arpa/" ];
    local-ttl = 60;
  };
  systemd.tmpfiles.rules = [
    "d /run/networkd-dns 0755 root root -"
    "f /run/networkd-dns/hosts 0644 root root -"
  ];
  systemd.services.networkd-dns = {
    description = "Publish home DHCP hostnames in dnsmasq";
    after = [ "systemd-networkd.service" "dnsmasq.service" ];
    requires = [ "dnsmasq.service" ];
    path = [ pkgs.systemd ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${./dhcp-dns.py} ${routerConst.homeLanIf}";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/run/networkd-dns" ];
      PrivateTmp = true;
    };
  };
  systemd.timers.networkd-dns = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "30s";
    };
  };
}
