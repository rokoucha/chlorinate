{ routerConst, ... }:
let
  inherit (routerConst)
    wanIf
    mgmtLanIf
    homeLanIf
    serverLanIf
    materiaLanIf
    itscomIf
    mapeIf
    tailscaleIf
    itscomV4
    itscomPublicV4
    staticNaptServerV4
    tailnetV4
    ;
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
        define TS = ${tailscaleIf}

        define SRV_LAN = ${serverLanIf}
        define MATERIA_LAN = ${materiaLanIf}
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
                iifname { $WAN, $TUN } udp dport 41641 accept

                # Tailnet-side management and infrastructure services.
                iifname $TS meta l4proto ipv6-icmp accept
                iifname $TS ip protocol icmp accept
                iifname $TS tcp dport 22 ct state new accept
                iifname $TS udp dport 53 accept
                iifname $TS tcp dport 53 ct state new accept

                # LAN-side management and infrastructure services.
                iifname $MGMT_LAN meta l4proto ipv6-icmp accept
                iifname $LAN meta l4proto ipv6-icmp accept
                iifname $SRV_LAN meta l4proto ipv6-icmp accept
                iifname $MATERIA_LAN meta l4proto ipv6-icmp accept

                iifname $MGMT_LAN ip protocol icmp accept
                iifname $LAN ip protocol icmp accept
                iifname $SRV_LAN ip protocol icmp accept
                iifname $MATERIA_LAN ip protocol icmp accept

                iifname $MGMT_LAN tcp dport 22 ct state new accept
                iifname $LAN tcp dport 22 ct state new accept
                iifname $SRV_LAN tcp dport 22 ct state new accept
                iifname $SRV_LAN tcp dport 3551 ct state new accept

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
                iifname { $LAN, $SRV_LAN } oifname $MATERIA_LAN ct state new accept

                iifname $LAN oifname $TUN ct state new accept
                iifname $TS oifname $LAN ip daddr 172.16.1.0/24 ct state new accept
                iifname $TS oifname $TUN meta nfproto ipv4 ct state new accept
                iifname $SRV_LAN oifname $ITSCOM ct state new accept
                iifname $SRV_LAN oifname $SRV_LAN ip daddr $STATIC_NAPT_SERVER_V4 ct state new accept
                iifname $ITSCOM oifname $SRV_LAN ip daddr $STATIC_NAPT_SERVER_V4 ct state new accept
                iifname $WAN oifname $SRV_LAN meta nfproto ipv6 ct state new accept
                iifname $WAN oifname $MATERIA_LAN meta nfproto ipv6 tcp dport { 80, 443 } ct state new accept
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
                oifname $LAN ip saddr ${tailnetV4} snat to 172.16.1.1
                oifname $SRV_LAN ip saddr { 172.16.0.0/24, 172.16.1.0/24 } ip daddr $STATIC_NAPT_SERVER_V4 snat to 172.16.2.1
                oifname $SRV_LAN ip saddr 172.16.2.0/24 ip daddr $STATIC_NAPT_SERVER_V4 snat to 172.16.2.1
            }
        }
      '';
    };
  };
}
