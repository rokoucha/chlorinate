package main

import (
	"fmt"
	"strings"
)

// nftablesRuleset generates a complete nftables ruleset for the MAP-E SNAT table.
// It uses a dedicated "ip mape" table so it can be atomically replaced without
// touching the existing "ip nat" table that handles other SNAT/DNAT rules.
func nftablesRuleset(p *Params, tunIf string) string {
	n := len(p.PortBlocks)
	ceV4 := p.CeIPv4.String()

	var sb strings.Builder

	sb.WriteString("add table ip mape\n")
	sb.WriteString("flush table ip mape\n")
	sb.WriteString("table ip mape {\n")
	sb.WriteString("    chain postrouting {\n")
	sb.WriteString("        type nat hook postrouting priority srcnat + 10; policy accept;\n")
	sb.WriteString("\n")

	// TCP
	fmt.Fprintf(&sb, "        oifname %q meta l4proto tcp meta mark set jhash ip saddr . tcp sport mod %d\n", tunIf, n)
	for i, b := range p.PortBlocks {
		fmt.Fprintf(&sb, "        oifname %q meta l4proto tcp meta mark %d snat to %s:%d-%d persistent\n",
			tunIf, i, ceV4, b.Start, b.End)
	}
	sb.WriteString("\n")

	// UDP
	fmt.Fprintf(&sb, "        oifname %q meta l4proto udp meta mark set jhash ip saddr . udp sport mod %d\n", tunIf, n)
	for i, b := range p.PortBlocks {
		fmt.Fprintf(&sb, "        oifname %q meta l4proto udp meta mark %d snat to %s:%d-%d persistent\n",
			tunIf, i, ceV4, b.Start, b.End)
	}
	sb.WriteString("\n")

	// ICMP echo-request
	fmt.Fprintf(&sb, "        oifname %q ip protocol icmp icmp type echo-request meta mark set jhash ip saddr . icmp id mod %d\n", tunIf, n)
	for i, b := range p.PortBlocks {
		fmt.Fprintf(&sb, "        oifname %q ip protocol icmp icmp type echo-request meta mark %d snat to %s:%d-%d persistent\n",
			tunIf, i, ceV4, b.Start, b.End)
	}

	sb.WriteString("    }\n")
	sb.WriteString("}\n")

	return sb.String()
}
