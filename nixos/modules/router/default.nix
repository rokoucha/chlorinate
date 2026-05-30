{ ... }:
{
  imports = [
    ./firewall.nix
    ./kernel.nix
    ./wan.nix
    ./mgmt.nix
    ./home.nix
    ./server.nix
    ./cloudflared.nix
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
    itscomIf = "enp5s0f1.200";
    mapeIf = "mape0";
    tailscaleIf = "tailscale0";
    itscomV4 = "172.16.254.10";
    itscomPublicV4 = "175.177.69.46";
    staticNaptServerV4 = "172.16.2.21";
    tailnetV4 = "100.64.0.0/10";
    materiaRouterASN = 64512;
    materiaClusterASN = 64513;
    materiaBgpPeerV4 = "172.16.2.21";
    materiaBgpPeerV6 = "240b:10:3f6d:1402:da9e:f3ff:fe9d:854e";
    materiaLbIPv4Pool = "172.16.2.64/27";
    materiaLbIPv6Pool = "2404:9200:225:103::/112";
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
