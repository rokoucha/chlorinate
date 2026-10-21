import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("dhcp_dns", Path(__file__).parents[1] / "nixos/modules/router/dhcp-dns.py")
dns = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dns)


class DhcpDnsTests(unittest.TestCase):
    def test_live_leases_only_and_mac_alias(self):
        lease = dict(Hostname="Laptop.example", Address=[172, 16, 1, 100],
                     HardwareAddressType=1, HardwareAddressLength=6,
                     HardwareAddress=[2, 0, 0, 0, 0, 1] + [0] * 10, ExpirationUSec=200)
        invalid = [dict(lease, Hostname="bad\nname"), dict(lease, ExpirationUSec=100),
                   dict(lease, Hostname=""), dict(lease, Address=[172, 16, 2, 100]),
                   dict(lease, HardwareAddressType=0)]
        self.assertEqual(dns.hosts({"DHCPServer": {"Leases": [lease, *invalid]}}, 100),
                         "172.16.1.100 laptop.home.arpa mac-020000000001.devices.home.arpa\n")

    def test_removed_leases_remove_records(self):
        self.assertEqual(dns.hosts({}, 100), "")
