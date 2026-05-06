//go:build !linux

package main

import (
	"fmt"
	"net"
)

func findPrefix(_ string, _ net.IPNet) (*net.IPNet, error) {
	return nil, fmt.Errorf("netlink: not supported on this platform")
}

func applyNetlink(_ *Params, _ *config, _ *net.IPNet) error {
	return fmt.Errorf("netlink: not supported on this platform")
}

func rollbackNetlink(_ *Params, _ *config, _ *net.IPNet) error {
	return fmt.Errorf("netlink: not supported on this platform")
}

func teardownTunnel(_ *config) error {
	return fmt.Errorf("netlink: not supported on this platform")
}
