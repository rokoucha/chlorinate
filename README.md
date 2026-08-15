# chlorinate

自家製ルーター

## spec

- CPU: Intel(R) Core(TM) i3-N300
- Memory: 8GiB DDR5
- Storage: Intel Corporation SSD DC P4101/Pro 7600p/760p/E 6100p Series 128GiB
- NIC1: Intel Corporation Ethernet Controller I226-V(3 ports)
- NIC2: Intel Corporation 82599ES(2 ports)

## Cloudflare WARP egress

Cloudflare IPv4 traffic from the home LAN can use a dedicated NixOS MicroVM as
an optional egress gateway. Tailscale, cloudflared, MAP-E, and the existing
policy routing remain on the host; only `warp-svc` runs in the MicroVM.

The host and guest use a point-to-point TAP network:

- host: `172.31.133.1/30` (`vm-warp`)
- guest: `172.31.133.2/30`
- routing table and packet mark: `13335`

The `warp_egress_v4` nftables set starts empty. Every 15 seconds,
`warp-egress-health.service` requests Cloudflare's trace endpoint through the
guest. It populates the set only when the response reports `warp=on`; otherwise
home LAN traffic continues to use MAP-E.

### First enrollment

After deploying the host configuration, create a Mesh node in the Cloudflare
dashboard and copy its one-time connector token. Keep the token out of this
repository and the Nix store.

Set the Mesh node's matching Cloudflare device profile to use the `WireGuard`
tunnel protocol. Mesh rejects a local protocol override, so this centrally
managed setting is required before the guest can use the pinned IPv6 UDP/2408
endpoint.

Enter the MicroVM over its host-only vsock SSH transport and enroll it:

```console
$ sudo microvm -s warp-gateway -- \
    -i /var/lib/microvms/warp-gateway-ssh/id_ed25519
# warp-cli connector new <token>
# warp-cli connect
# warp-cli status
```

The registration is retained in the MicroVM's persistent
`/var/lib/cloudflare-warp` volume. Verify the data path and dynamic route set on
the host:

```console
$ systemctl status microvm@warp-gateway.service
$ systemctl status warp-egress-health.service
$ sudo nft list set inet filter warp_egress_v4
$ curl --interface 172.31.133.1 https://1.1.1.1/cdn-cgi/trace
```

The guest pins its WARP tunnel to Cloudflare's IPv6 endpoint. Confirm that the
outer tunnel is using IPv6 from the host while generating WARP traffic:

```console
$ sudo tcpdump -ni vm-warp 'ip6 and udp port 2408'
```

The MicroVM is not restarted automatically during `nixos-rebuild switch`, to
avoid racing its virtiofsd backends. After a deployment that changes the guest
configuration, restart it explicitly:

```console
$ sudo systemctl restart microvm@warp-gateway.service
```

Only the home LAN and Cloudflare's published IPv4 ranges are opted in. Server,
Materia, Tailscale, IPv6, and host-originated traffic keep their existing paths.
