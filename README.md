# chlorinate

自家製ルーター

## spec

- CPU: Intel(R) Core(TM) i3-N300
- Memory: 8GiB DDR5
- Storage: Intel Corporation SSD DC P4101/Pro 7600p/760p/E 6100p Series 128GiB
- NIC1: Intel Corporation Ethernet Controller I226-V(3 ports)
- NIC2: Intel Corporation 82599ES(2 ports)

## IoT network

- VLAN 40 on `enp5s0f1`, bridged with the USB WLAN on `br-iot`.
- SSID `WLAN-212355-2G`: 2.4 GHz, channel 6, 20 MHz, WPA2-CCMP.
- Gateway `172.16.4.1/24`, DHCP `172.16.4.100`–`172.16.4.250`, DNS on the gateway.
- IPv6 uses DHCP-PD subnet ID 4 (`…:04::/64`); WARP uses subnet ID 5.
- The password is generated once in `/var/lib/hostapd/iot-password` (root only).
  Read it with `sudo cat /var/lib/hostapd/iot-password` on chlorine.
- Configure the switch uplink to carry tagged VLAN 40 and wired IoT ports as
  untagged VLAN 40 with PVID 40. No switch configuration is managed here.
- IoT can reach the Internet over MAP-E (IPv4) and native IPv6. New connections
  to existing LANs and router management are blocked. Trusted LANs can initiate
  ESPHome API (TCP 6053), OTA (TCP 3232), and diagnostic ICMP to IoT.
- mDNS is not relayed. Register ESPHome by IP/hostname; add DHCP reservations
  and a destination-specific MQTT rule when the devices and broker are assigned.
  Home Assistant's Cilium egress policy must also permit its ESPHome connections.

When migrating WARP from subnet ID 4, remove its old global IPv6 addresses and
routes before assigning that prefix to `br-iot`, and renew the guest's IPv6
configuration. After networkd settles, restart `mape-tool.service` to restore
its CE address if networkd removed it. Verify WARP health after the switch.
