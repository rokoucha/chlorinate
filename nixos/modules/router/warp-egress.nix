{
  lib,
  pkgs,
  routerConst,
  ...
}:
let
  inherit (routerConst)
    wanIf
    mapeIf
    warpTapIf
    warpHostV4
    warpGuestV4
    ;

  cloudflareV4 = [
    "173.245.48.0/20"
    "103.21.244.0/22"
    "103.22.200.0/22"
    "103.31.4.0/22"
    "141.101.64.0/18"
    "108.162.192.0/18"
    "190.93.240.0/20"
    "188.114.96.0/20"
    "197.234.240.0/22"
    "198.41.128.0/17"
    "162.158.0.0/15"
    "104.16.0.0/13"
    "104.24.0.0/14"
    "172.64.0.0/13"
    "131.0.72.0/22"
  ];

  enableWarpEgress = pkgs.writeText "warp-egress-enable.nft" ''
    flush set inet filter warp_egress_v4
    add element inet filter warp_egress_v4 { ${lib.concatStringsSep ", " cloudflareV4} }
  '';
  disableWarpEgress = pkgs.writeText "warp-egress-disable.nft" ''
    flush set inet filter warp_egress_v4
  '';
in
{
  microvm.vms.warp-gateway = {
    autostart = true;
    # Restarting the VM and its virtiofsd backends in the same switch transaction
    # can race: cloud-hypervisor sees the socket before virtiofsd accepts clients.
    # Keep deployments reliable and apply guest changes with an explicit restart.
    restartIfChanged = false;
    specialArgs = { inherit routerConst; };
    config = {
      imports = [ ./warp-gateway.nix ];
    };
  };

  systemd.services.warp-gateway-ssh-key = {
    description = "Create the host-only SSH key for the WARP MicroVM";
    requiredBy = [ "microvm@warp-gateway.service" ];
    before = [
      "microvm-virtiofsd@warp-gateway.service"
      "microvm@warp-gateway.service"
    ];
    path = [ pkgs.openssh ];
    serviceConfig.Type = "oneshot";
    script = ''
      install -d -m 0700 /var/lib/microvms/warp-gateway-ssh
      install -d -m 0755 /var/lib/microvms/warp-gateway-ssh/public
      if [ ! -s /var/lib/microvms/warp-gateway-ssh/id_ed25519 ]; then
        ssh-keygen \
          -q \
          -t ed25519 \
          -N "" \
          -C warp-gateway-host \
          -f /var/lib/microvms/warp-gateway-ssh/id_ed25519
      fi
      install \
        -m 0644 \
        /var/lib/microvms/warp-gateway-ssh/id_ed25519.pub \
        /var/lib/microvms/warp-gateway-ssh/public/authorized_keys
    '';
  };

  systemd.network.networks."15-${warpTapIf}" = {
    matchConfig.Name = warpTapIf;
    address = [ "${warpHostV4}/30" ];
    networkConfig = {
      IPv4Forwarding = true;
      IPv6Forwarding = true;
      IPv6SendRA = true;
      DHCPPrefixDelegation = true;
    };
    extraConfig = ''
      [IPv6SendRA]
      RouterLifetimeSec=1800
      EmitDNS=no

      [DHCPPrefixDelegation]
      UplinkInterface=${wanIf}
      SubnetId=4
      Announce=yes
      Assign=yes
      Token=eui64

      ${lib.concatMapStringsSep "\n" (prefix: ''
        [Route]
        Destination=${prefix}
        Gateway=${warpGuestV4}
        GatewayOnLink=yes
        Table=13335
      '') cloudflareV4}

      [RoutingPolicyRule]
      FirewallMark=13335
      Table=13335
      Priority=110

      [RoutingPolicyRule]
      From=${warpHostV4}/32
      Table=13335
      Priority=120
    '';
  };

  systemd.services.warp-egress-health = {
    description = "Enable Cloudflare WARP egress while its data path is healthy";
    after = [
      "microvm@warp-gateway.service"
      "nftables.service"
      "systemd-networkd.service"
    ];
    wants = [ "microvm@warp-gateway.service" ];
    path = [
      pkgs.curl
      pkgs.gnugrep
      pkgs.nftables
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      if curl \
        --interface ${warpHostV4} \
        --connect-timeout 3 \
        --max-time 8 \
        --fail \
        --silent \
        https://1.1.1.1/cdn-cgi/trace \
          | grep -q '^warp=on$'; then
        nft -f ${enableWarpEgress}
      else
        nft -f ${disableWarpEgress}
        echo "WARP data path is unavailable; using the existing uplink." >&2
      fi
    '';
  };

  systemd.timers.warp-egress-health = {
    description = "Periodically check the Cloudflare WARP egress path";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "15s";
      Unit = "warp-egress-health.service";
    };
  };
}
