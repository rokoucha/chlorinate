{ config, pkgs, routerConst, mapeTool, ... }:
let
  inherit (routerConst) wanIf lanTrunkIf;
in
{
  services.networkd-dispatcher = {
    enable = true;
    rules."50-mape" = {
      onState = [ "routable" ];
      script = ''
        #!/bin/sh
        [ "$IFACE" = "${wanIf}" ] || exit 0
        exec systemctl restart mape-tool
      '';
    };
  };

  systemd.services.mape-tool = {
    description = "MAP-E tunnel and nftables configuration";
    after = [
      "sys-subsystem-net-devices-${wanIf}.device"
      "network-online.target"
      "nftables.service"
      "systemd-networkd.service"
    ];
    wants = [ "network-online.target" ];
    partOf = [ "systemd-networkd.service" "nftables.service" ];
    restartTriggers = [ (pkgs.writeText "nftables-ruleset" config.networking.nftables.ruleset) ];
    path = [ pkgs.nftables ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${mapeTool}/bin/mape-tool apply";
      Restart = "on-failure";
      RestartSec = "5s";
      StartLimitIntervalSec = 0;
    };
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.tune-router-nic-rings = {
    description = "Tune router NIC ring buffers";
    after = [
      "sys-subsystem-net-devices-${wanIf}.device"
      "sys-subsystem-net-devices-${lanTrunkIf}.device"
    ];
    bindsTo = [
      "sys-subsystem-net-devices-${wanIf}.device"
      "sys-subsystem-net-devices-${lanTrunkIf}.device"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.ethtool}/bin/ethtool -G ${wanIf} rx 4096 tx 4096
      ${pkgs.ethtool}/bin/ethtool -G ${lanTrunkIf} rx 4096 tx 4096
    '';
  };

  systemd.network.networks."10-wan" = {
    matchConfig.Name = wanIf;
    extraConfig = ''
      [Network]
      DHCP=ipv6
      IPv6Forwarding=yes
      IPv6AcceptRA=yes
      IPv6PrivacyExtensions=no
      DHCPPrefixDelegation=yes
      Domains=~.

      [DHCPv6]
      DUIDType=link-layer
      IAID=0
      SendHostname=no
      UseDNS=yes
      UseNTP=yes

      [DHCPPrefixDelegation]
      UplinkInterface=:self
      SubnetId=0
      Announce=no
      Assign=yes
      Token=eui64
    '';
  };
}
