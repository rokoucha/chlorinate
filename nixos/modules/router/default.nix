{ ... }:
{
  imports = [
    ./firewall.nix
    ./kernel.nix
    ./wan.nix
    ./warp-egress.nix
    ./mgmt.nix
    ./home.nix
    ./server.nix
    ./cloudflared.nix
    ./cloudflare-ddns.nix
    ./cilium-lb-ipv6-pool-updater.nix
    ./blackbox.nix
    ./node-exporter.nix
    ./nftables-metrics.nix
    ./otelcol.nix
  ];

  systemd.network = {
    enable = true;
    wait-online.enable = false;
  };

  _module.args.routerConst = {
    wanIf = "enp5s0f0";
    lanTrunkIf = "enp5s0f1";
    mgmtLanIf = "enp5s0f1";
    homeLanIf = "enp5s0f1.10";
    serverLanIf = "enp5s0f1.20";
    materiaLanIf = "enp5s0f1.30";
    itscomIf = "enp5s0f1.200";
    mapeIf = "mape0";
    delegatedPrefixLen = 56;
    tailscaleIf = "tailscale0";
    warpTapIf = "vm-warp";
    warpHostV4 = "172.31.133.1";
    warpGuestV4 = "172.31.133.2";
    # Derived from warp-gateway's fixed 02:00:00:01:33:35 MAC address.
    warpGuestLinkLocalV6 = "fe80::ff:fe01:3335";
    # Add the parent site and its API hostnames here as well as the challenge
    # platform so that a complete Turnstile flow keeps one egress identity.
    warpDomains = [
      "challenges.cloudflare.com"
    ];
    itscomV4 = "172.16.254.10";
    itscomPublicV4 = "175.177.69.46";
    staticNaptServerV4 = "172.16.2.21";
    teamspeakLbV4 = "172.16.3.10";
    tailnetV4 = "100.64.0.0/10";
    lanDhcpServerConfig = router: {
      PoolOffset = 100;
      PoolSize = 151;
      DefaultLeaseTimeSec = "12h";
      EmitRouter = true;
      Router = router;
      EmitDNS = true;
      DNS = router;
    };
  };
}
