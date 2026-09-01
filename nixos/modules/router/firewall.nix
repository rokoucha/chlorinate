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
    warpTapIf
    itscomV4
    itscomPublicV4
    staticNaptServerV4
    teamspeakLbV4
    ingressLbV4
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
        define WARP = ${warpTapIf}

        define SRV_LAN = ${serverLanIf}
        define MATERIA_LAN = ${materiaLanIf}
        define ITSCOM = ${itscomIf}
        define ITSCOM_V4 = ${itscomV4}
        define ITSCOM_PUBLIC_V4 = ${itscomPublicV4}
        define STATIC_NAPT_SERVER_V4 = ${staticNaptServerV4}
        define TEAMSPEAK_LB_V4 = ${teamspeakLbV4}
        define INGRESS_LB_V4 = ${ingressLbV4}
        table inet filter {
            # Named counters are the only thing nftables counts, and
            # nftables-metrics.nix exports them to node_exporter.
            counter input_drop { }
            counter input_invalid { }
            counter forward_drop { }
            counter forward_invalid { }

            # dnsmasq populates these sets with A and AAAA answers for the
            # configured WARP domains.
            set warp_targets_v4 {
                type ipv4_addr
            }

            set warp_targets_v6 {
                type ipv6_addr
            }

            # Empty while the WARP data path is unhealthy. The health-check
            # service atomically replaces these contents without disturbing
            # dnsmasq's dynamically learned targets.
            set warp_enabled_v4 {
                type ipv4_addr
                flags interval
            }

            set warp_enabled_v6 {
                type ipv6_addr
                flags interval
            }

            chain warp_egress_mark {
                type filter hook prerouting priority mangle; policy accept;
                iifname $LAN ip daddr @warp_targets_v4 ip daddr @warp_enabled_v4 meta mark set 13335
                iifname $LAN ip6 daddr @warp_targets_v6 ip6 daddr @warp_enabled_v6 meta mark set 13335
            }

            chain input {
                type filter hook input priority filter; policy drop;

                iifname lo accept

                # Count only, no verdict: invalid ICMPv6 must stay acceptable.
                ct state invalid counter name "input_invalid"

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

                # WARP MicroVM point-to-point control traffic.
                iifname $WARP meta l4proto ipv6-icmp accept
                iifname $WARP ip protocol icmp accept

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

                # Same verdict as the chain policy, but counted.
                counter name "input_drop" drop
            }

            chain forward {
                type filter hook forward priority filter; policy drop;

                # MAP-E carries IPv4 inside IPv6, so clamp LAN TCP SYNs before
                # they can be accepted by the forwarding rules below.
                oifname $TUN tcp flags syn tcp option maxseg size set rt mtu
                oifname $ITSCOM tcp flags syn tcp option maxseg size set rt mtu

                ct state invalid counter name "forward_invalid"

                ct state established,related accept

                iifname $LAN oifname $SRV_LAN ct state new accept
                iifname { $LAN, $SRV_LAN } oifname $MATERIA_LAN ct state new accept
                iifname $MATERIA_LAN oifname $SRV_LAN ct state new accept

                iifname $LAN oifname $TUN ct state new accept
                iifname $LAN oifname $WARP meta mark 13335 ct state new accept
                iifname $WARP oifname $LAN ct state new accept
                iifname $WARP oifname $TUN meta nfproto ipv4 ct state new accept
                iifname $WARP oifname $WAN meta nfproto ipv6 ct state new accept
                iifname $TS oifname $LAN ip daddr 172.16.1.0/24 ct state new accept
                iifname $TS oifname $TUN meta nfproto ipv4 ct state new accept
                iifname $SRV_LAN oifname $ITSCOM ct state new accept
                iifname $MATERIA_LAN oifname $ITSCOM ct state new accept
                iifname { $MGMT_LAN, $LAN, $SRV_LAN, $MATERIA_LAN, $ITSCOM } oifname $MATERIA_LAN ip daddr $TEAMSPEAK_LB_V4 udp dport 9987 ct state new accept
                iifname { $MGMT_LAN, $LAN, $SRV_LAN, $MATERIA_LAN, $ITSCOM } oifname $MATERIA_LAN ip daddr $TEAMSPEAK_LB_V4 tcp dport { 10011, 30033 } ct state new accept
                iifname { $MGMT_LAN, $LAN, $SRV_LAN, $MATERIA_LAN, $ITSCOM } oifname $MATERIA_LAN ip daddr $INGRESS_LB_V4 tcp dport { 80, 443 } ct state new accept
                iifname { $MGMT_LAN, $LAN, $SRV_LAN, $MATERIA_LAN, $ITSCOM } oifname $MATERIA_LAN ip daddr $INGRESS_LB_V4 udp dport 443 ct state new accept
                iifname $SRV_LAN oifname $SRV_LAN ip daddr $STATIC_NAPT_SERVER_V4 ct state new accept
                iifname $ITSCOM oifname $SRV_LAN ip daddr $STATIC_NAPT_SERVER_V4 ct state new accept
                iifname $WAN oifname $SRV_LAN meta nfproto ipv6 ct state new accept
                iifname $WAN oifname $MATERIA_LAN meta nfproto ipv6 tcp dport { 80, 443 } ct state new accept
                iifname $WAN oifname $MATERIA_LAN meta nfproto ipv6 udp dport 443 ct state new accept
                iifname $WAN oifname $MATERIA_LAN meta nfproto ipv6 udp dport 9987 ct state new accept
                iifname $WAN oifname $MATERIA_LAN meta nfproto ipv6 tcp dport { 10011, 30033 } ct state new accept
                iifname $LAN oifname $WAN meta nfproto ipv6 ct state new accept
                iifname $SRV_LAN oifname $WAN meta nfproto ipv6 ct state new accept
                iifname $MATERIA_LAN oifname $WAN meta nfproto ipv6 ct state new accept

                counter name "forward_drop" drop
            }
        }

        table ip nat {
            chain prerouting {
                type nat hook prerouting priority dstnat; policy accept;

                # iTSCOM static NAPT -> server LAN
                iifname $ITSCOM ip daddr { $ITSCOM_V4, $ITSCOM_PUBLIC_V4 } tcp dport { 80, 443 } dnat to $INGRESS_LB_V4
                iifname $ITSCOM ip daddr { $ITSCOM_V4, $ITSCOM_PUBLIC_V4 } udp dport 443 dnat to $INGRESS_LB_V4
                iifname { $MGMT_LAN, $LAN, $SRV_LAN, $MATERIA_LAN } ip daddr $ITSCOM_PUBLIC_V4 tcp dport { 80, 443 } dnat to $INGRESS_LB_V4
                iifname { $MGMT_LAN, $LAN, $SRV_LAN, $MATERIA_LAN } ip daddr $ITSCOM_PUBLIC_V4 udp dport 443 dnat to $INGRESS_LB_V4
                iifname $ITSCOM ip daddr { $ITSCOM_V4, $ITSCOM_PUBLIC_V4 } udp dport 9987 dnat to $TEAMSPEAK_LB_V4
                iifname $ITSCOM ip daddr { $ITSCOM_V4, $ITSCOM_PUBLIC_V4 } tcp dport { 10011, 30033 } dnat to $TEAMSPEAK_LB_V4
                iifname { $MGMT_LAN, $LAN, $SRV_LAN, $MATERIA_LAN } ip daddr $ITSCOM_PUBLIC_V4 udp dport 9987 dnat to $TEAMSPEAK_LB_V4
                iifname { $MGMT_LAN, $LAN, $SRV_LAN, $MATERIA_LAN } ip daddr $ITSCOM_PUBLIC_V4 tcp dport { 10011, 30033 } dnat to $TEAMSPEAK_LB_V4
                iifname $ITSCOM ip daddr { $ITSCOM_V4, $ITSCOM_PUBLIC_V4 } dnat to $STATIC_NAPT_SERVER_V4
                iifname { $MGMT_LAN, $LAN } ip daddr $ITSCOM_PUBLIC_V4 dnat to $STATIC_NAPT_SERVER_V4
                iifname $SRV_LAN ip daddr { $ITSCOM_V4, $ITSCOM_PUBLIC_V4 } dnat to $STATIC_NAPT_SERVER_V4
            }

            chain postrouting {
                type nat hook postrouting priority srcnat; policy accept;

                # The MAP-E service owns SNAT on $TUN, including traffic from
                # the WARP MicroVM, because it must select an allowed port set.
                oifname $ITSCOM ip saddr 172.16.2.0/24 snat to $ITSCOM_V4
                oifname $ITSCOM ip saddr 172.16.3.0/24 snat to $ITSCOM_V4
                iifname $MATERIA_LAN oifname $MATERIA_LAN ip daddr $TEAMSPEAK_LB_V4 udp dport 9987 snat to 172.16.3.1
                iifname $MATERIA_LAN oifname $MATERIA_LAN ip daddr $TEAMSPEAK_LB_V4 tcp dport { 10011, 30033 } snat to 172.16.3.1
                iifname $MATERIA_LAN oifname $MATERIA_LAN ip daddr $INGRESS_LB_V4 tcp dport { 80, 443 } snat to 172.16.3.1
                iifname $MATERIA_LAN oifname $MATERIA_LAN ip daddr $INGRESS_LB_V4 udp dport 443 snat to 172.16.3.1
                oifname $LAN ip saddr ${tailnetV4} snat to 172.16.1.1
                oifname $SRV_LAN ip saddr { 172.16.0.0/24, 172.16.1.0/24 } ip daddr $STATIC_NAPT_SERVER_V4 snat to 172.16.2.1
                oifname $SRV_LAN ip saddr 172.16.2.0/24 ip daddr $STATIC_NAPT_SERVER_V4 snat to 172.16.2.1
            }
        }
      '';
    };
  };
}
