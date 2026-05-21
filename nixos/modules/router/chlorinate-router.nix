{
  lib,
  pkgs,
  mape,
  ...
}:

let
  wanIf = "enp5s0f0";
  lanTrunkIf = "enp5s0f1";
  mgmtLanIf = lanTrunkIf;
  homeLanIf = "enp5s0f1.10";
  serverLanIf = "enp5s0f1.20";
  itscomIf = "enp5s0f1.200";
  mapeIf = "mape0";

  itscomV4 = "172.16.254.10";
  itscomPublicV4 = "175.177.69.46";
  staticNaptServerV4 = "172.16.2.21";

  lanDhcpServerConfig = router: {
    PoolOffset = 100;
    PoolSize = 151;
    DefaultLeaseTimeSec = "12h";
    EmitRouter = true;
    Router = router;
    EmitDNS = true;
    DNS = router;
  };
in
{
  networking = {
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
    nftables = {
      enable = true;
      ruleset = ''
        define WAN = ${wanIf}
        define MGMT_LAN = ${mgmtLanIf}
        define LAN = ${homeLanIf}
        define TUN = ${mapeIf}

        define SRV_LAN = ${serverLanIf}
        define ITSCOM = ${itscomIf}
        define ITSCOM_V4 = ${itscomV4}
        define ITSCOM_PUBLIC_V4 = ${itscomPublicV4}
        define STATIC_NAPT_SERVER_V4 = ${staticNaptServerV4}

        table inet filter {
            chain input {
                type filter hook input priority filter; policy drop;

                iifname lo accept
                ct state established,related accept

                # WAN control plane required for IPv6, DHCPv6-PD, and PMTU.
                iifname $WAN meta nfproto ipv6 meta l4proto ipv6-icmp accept
                iifname $WAN udp sport 547 udp dport 546 accept

                # LAN-side management and infrastructure services.
                iifname $MGMT_LAN meta l4proto ipv6-icmp accept
                iifname $LAN meta l4proto ipv6-icmp accept
                iifname $SRV_LAN meta l4proto ipv6-icmp accept

                iifname $MGMT_LAN ip protocol icmp accept
                iifname $LAN ip protocol icmp accept
                iifname $SRV_LAN ip protocol icmp accept

                iifname $MGMT_LAN tcp dport 22 ct state new accept
                iifname $LAN tcp dport 22 ct state new accept
                iifname $SRV_LAN tcp dport 22 ct state new accept

                iifname $MGMT_LAN udp dport { 53, 67 } accept
                iifname $LAN udp dport { 53, 67 } accept
                iifname $SRV_LAN udp dport { 53, 67 } accept

                iifname $MGMT_LAN tcp dport 53 ct state new accept
                iifname $LAN tcp dport 53 ct state new accept
                iifname $SRV_LAN tcp dport 53 ct state new accept
            }

            chain forward {
                type filter hook forward priority filter; policy drop;

                # MAP-E carries IPv4 inside IPv6, so clamp LAN TCP SYNs before
                # they can be accepted by the forwarding rules below.
                oifname $TUN tcp flags syn tcp option maxseg size set rt mtu
                oifname $ITSCOM tcp flags syn tcp option maxseg size set rt mtu

                ct state established,related accept

                iifname $LAN oifname $SRV_LAN ct state new accept

                iifname $LAN oifname $TUN ct state new accept
                iifname $SRV_LAN oifname $ITSCOM ct state new accept
                iifname $SRV_LAN oifname $SRV_LAN ip daddr $STATIC_NAPT_SERVER_V4 ct state new accept
                iifname $ITSCOM oifname $SRV_LAN ip daddr $STATIC_NAPT_SERVER_V4 ct state new accept
                iifname $WAN oifname $SRV_LAN meta nfproto ipv6 ct state new accept
                iifname $LAN oifname $WAN meta nfproto ipv6 ct state new accept
                iifname $SRV_LAN oifname $WAN meta nfproto ipv6 ct state new accept
            }
        }

        table ip nat {
            chain prerouting {
                type nat hook prerouting priority dstnat; policy accept;

                # iTSCOM static NAPT -> server LAN
                iifname $ITSCOM ip daddr { $ITSCOM_V4, $ITSCOM_PUBLIC_V4 } dnat to $STATIC_NAPT_SERVER_V4
                iifname { $MGMT_LAN, $LAN } ip daddr $ITSCOM_PUBLIC_V4 dnat to $STATIC_NAPT_SERVER_V4
                iifname $SRV_LAN ip daddr { $ITSCOM_V4, $ITSCOM_PUBLIC_V4 } dnat to $STATIC_NAPT_SERVER_V4
            }

            chain postrouting {
                type nat hook postrouting priority srcnat; policy accept;

                # Server LAN -> iTSCOM
                oifname $ITSCOM ip saddr 172.16.2.0/24 snat to $ITSCOM_V4
                oifname $SRV_LAN ip saddr { 172.16.0.0/24, 172.16.1.0/24 } ip daddr $STATIC_NAPT_SERVER_V4 snat to 172.16.2.1
                oifname $SRV_LAN ip saddr 172.16.2.0/24 ip daddr $STATIC_NAPT_SERVER_V4 snat to 172.16.2.1
            }
        }
      '';
    };
  };

  services.dnsmasq = {
    enable = true;
    settings = {
      domain-needed = true;
      bogus-priv = true;
      bind-dynamic = true;
      no-resolv = true;
      server = [
        "127.0.0.53"
      ];
      interface = [
        mgmtLanIf
        homeLanIf
        serverLanIf
      ];
    };
  };

  boot = {
    kernelModules = [
      "ip6_tunnel"
      "ip6_udp_tunnel"
      "nf_conntrack"
      "nf_nat"
    ];

    kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv6.conf.${wanIf}.accept_ra" = 2;
      "net.netfilter.nf_conntrack_max" = 524288;
      "net.netfilter.nf_conntrack_tcp_timeout_established" = 3600;
      "net.netfilter.nf_conntrack_udp_timeout" = 60;
      "net.core.fb_tunnels_only_for_init_net" = 2;
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
      "net.ipv4.conf.${serverLanIf}.rp_filter" = 0;
      "net.ipv4.conf.${itscomIf}.rp_filter" = 0;
      # Allow traffic hairpinned from the MAP-E address to the iTSCOM NAPT path.
      "net.ipv4.conf.${serverLanIf}.accept_local" = 1;
      "net.ipv4.conf.${itscomIf}.accept_local" = 1;
    };
  };

  services.networkd-dispatcher = {
    enable = true;
    rules."50-mape" = {
      onState = [ "routable" ];
      script = ''
        #!/bin/sh
        [ "$IFACE" = "${wanIf}" ] || exit 0
        exec systemctl restart mape-config
      '';
    };
  };

  systemd.services.mape-config = {
    description = "MAP-E tunnel and nftables configuration";
    after = [
      "sys-subsystem-net-devices-${wanIf}.device"
      "network-online.target"
      "nftables.service"
      "systemd-networkd.service"
    ];
    wants = [ "network-online.target" ];
    partOf = [ "systemd-networkd.service" ];
    path = [
      pkgs.nftables
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${mape}/bin/mape apply";
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

  systemd.network = {
    enable = true;
    wait-online.enable = false;

    netdevs = {
      "20-lan-vlan" = {
        netdevConfig = {
          Name = homeLanIf;
          Kind = "vlan";
        };
        vlanConfig.Id = 10;
      };

      "20-${serverLanIf}" = {
        netdevConfig = {
          Name = serverLanIf;
          Kind = "vlan";
        };
        vlanConfig.Id = 20;
      };

      "20-${itscomIf}" = {
        netdevConfig = {
          Name = itscomIf;
          Kind = "vlan";
        };
        vlanConfig.Id = 200;
      };

    };

    networks = {
      "10-wan" = {
        matchConfig.Name = wanIf;
        extraConfig = ''
          [Network]
          DHCP=ipv6
          IPv6Forwarding=yes
          IPv6AcceptRA=yes
          IPv6PrivacyExtensions=no
          DHCPPrefixDelegation=yes

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

      "20-lan" = {
        matchConfig.Name = lanTrunkIf;
        vlan = [
          homeLanIf
          serverLanIf
          itscomIf
        ];
        networkConfig = {
          Address = "172.16.0.1/24";
          DHCPServer = true;
          IPv4Forwarding = true;
        };
        dhcpServerConfig = lanDhcpServerConfig "172.16.0.1";
      };

      "21-lan-vlan" = {
        matchConfig.Name = homeLanIf;
        networkConfig = {
          Address = "172.16.1.1/24";
          DHCPServer = true;
          IPv6SendRA = true;
          DHCPPrefixDelegation = true;
          IPv4Forwarding = true;
          IPv6Forwarding = true;
        };
        dhcpServerConfig = lanDhcpServerConfig "172.16.1.1";
        extraConfig = ''
          [IPv6SendRA]
          RouterLifetimeSec=1800
          EmitDNS=yes
          DNS=_link_local

          [DHCPPrefixDelegation]
          UplinkInterface=${wanIf}
          SubnetId=1
          Announce=yes
          Assign=yes
          Token=eui64
        '';
      };

      "20-${serverLanIf}" = {
        matchConfig.Name = serverLanIf;
        networkConfig = {
          Address = "172.16.2.1/24";
          DHCPServer = true;
          IPv6SendRA = true;
          DHCPPrefixDelegation = true;
          IPv4Forwarding = true;
          IPv6Forwarding = true;
        };
        dhcpServerConfig = lanDhcpServerConfig "172.16.2.1";
        extraConfig = ''
          [RoutingPolicyRule]
          To=172.16.0.0/16
          Table=254
          Priority=100

          [RoutingPolicyRule]
          From=172.16.2.0/24
          Table=200
          Priority=200

          [IPv6SendRA]
          RouterLifetimeSec=1800
          EmitDNS=yes
          DNS=_link_local

          [DHCPPrefixDelegation]
          UplinkInterface=${wanIf}
          SubnetId=2
          Announce=yes
          Assign=yes
          Token=eui64
        '';
      };

      "20-${itscomIf}" = {
        matchConfig.Name = itscomIf;
        extraConfig = ''
          [Network]
          Address=${itscomV4}/29

          [Route]
          Gateway=172.16.254.9
          Table=200
          GatewayOnLink=yes
        '';
      };

    };
  };
}
