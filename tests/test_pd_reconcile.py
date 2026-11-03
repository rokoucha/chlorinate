import importlib.util
import ipaddress
import json
from pathlib import Path
import unittest
from unittest.mock import patch

source = Path(__file__).parents[1] / "nixos/modules/router/pd-reconcile.py"
spec = importlib.util.spec_from_file_location("pd", source)
pd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pd)


class PDTests(unittest.TestCase):
    def test_layout_and_pd_change(self):
        for prefix in ("240b:10:3f6d:1400::/56", "240b:10:1234:5600::/56"):
            g = pd.ranges(prefix)
            site = ipaddress.ip_network(prefix)
            for key in ("podCIDR", "lbCIDR", "nodeCIDR", "reservedCIDR"):
                self.assertTrue(ipaddress.ip_network(g[key]).subnet_of(site))
            self.assertFalse(ipaddress.ip_network(g["podCIDR"]).overlaps(ipaddress.ip_network(g["lbCIDR"])))
        g = pd.ranges("240b:10:3f6d:1400::/56")
        self.assertEqual(g["podCIDR"], "240b:10:3f6d:1403:1000::/108")
        self.assertEqual(g["lbCIDR"], "240b:10:3f6d:1403:ffff::/112")

    def test_ambiguous_pd_blocks(self):
        routes = [{"type": "unreachable", "dst": p} for p in ("240b:10:3f6d:1400::/56", "240b:10:1234:5600::/56")]
        for candidates in ([], routes):
            with self.assertRaises(ValueError):
                pd.lease_delegation({"DHCPv6Client": {"Prefixes": [{"PrefixString": r["dst"].split("/")[0], "PrefixLength": 56, "PreferredLifetimeUSec": 200, "ValidLifetimeUSec": 200} for r in candidates]}}, 100)

    def test_deprecated_lease_does_not_block_new_pd(self):
        prefixes = [{"PrefixString": "240b:10:3f6d:1400::", "PrefixLength": 56,
                     "PreferredLifetimeUSec": 99, "ValidLifetimeUSec": 200},
                    {"PrefixString": "240b:10:1234:5600::", "PrefixLength": 56,
                     "PreferredLifetimeUSec": 150, "ValidLifetimeUSec": 200}]
        routes = [{"type": "unreachable", "dst": p["PrefixString"] + "/56"} for p in prefixes]
        result = pd.lease_delegation({"DHCPv6Client": {"Prefixes": prefixes}}, 100)
        self.assertEqual(result["pool"], pd.ranges("240b:10:1234:5600::/56")["pool"])
        self.assertEqual(pd.lease_delegation({"DHCPv6Client": {"Prefixes": prefixes}}, 100), result)

    def test_hairpin_source_tracks_preferred_pd(self):
        addresses = [{"addr_info": [
            {},
            {"local": "240b:10:3f6d:1402::1", "preferred_life_time": 0},
            {"local": "240b:10:1234:5602::1", "preferred_life_time": 1800},
            {"local": "240b:10:1234:5602::2", "preferred_life_time": 1800, "tentative": True},
            {"local": "240b:10:1234:5602::4", "preferred_life_time": 1800, "flags": ["temporary"]},
        ]}]
        with patch.object(pd, "run", return_value=json.dumps(addresses)):
            self.assertEqual(pd.router_address("lan", "240b:10:1234:5602::/64"), "240b:10:1234:5602::1")
            with self.assertRaises(ValueError):
                pd.router_address("lan", "240b:10:3f6d:1402::/64")
        addresses[0]["addr_info"].append({"local": "240b:10:1234:5602::3", "preferred_life_time": 1800})
        with patch.object(pd, "run", return_value=json.dumps(addresses)):
            with self.assertRaises(ValueError):
                pd.router_address("lan", "240b:10:1234:5602::/64")

    def test_hairpin_map_retains_lb_generations_atomically(self):
        old = pd.ranges("240b:10:3f6d:1400::/56")
        new = pd.ranges("240b:10:1234:5600::/56")
        with patch.object(pd, "run") as run:
            pd.sync_boundary([old, new], "240b:10:1234:5602::1")
        run.assert_called_once()
        commands = run.call_args.kwargs["stdin"]
        self.assertIn("flush map inet filter pd_lb_hairpin_snat", commands)
        for generation in (old, new):
            self.assertIn(generation["lbCIDR"] + " : 240b:10:1234:5602::1", commands)

    def test_actual_allocations_only(self):
        cidr = "240b:10:3f6d:1403:1000::100/120"
        node = {"metadata": {"name": "node"}, "spec": {"ipam": {"pools": {"allocated": [
            {"pool": "old", "cidrs": ["fd00::/120"]}, {"pool": "new", "cidrs": [cidr]}]}}}}
        routes = pd.desired_routes([node], {"node": "fe80::1"},
                                  [ipaddress.ip_network("240b:10:3f6d:1403:1000::/108")], [], "vlan20", "vlan30")
        self.assertEqual(routes, {cidr: ("fe80::1", "vlan20")})
        with self.assertRaises(KeyError):
            pd.desired_routes([node], {}, [], [], "vlan20", "vlan30")

    def test_route_failure_does_not_publish_new_generation(self):
        writes = []
        class Kube:
            def get(self, kind, *args, **kwargs):
                return {"items": []}
            def apply(self, obj):
                writes.append(obj["kind"])
            def cm(self, *args):
                writes.append("desired")
        routes = '[{"type":"unreachable","dst":"240b:10:3f6d:1400::/56"}]'
        with patch.object(pd, "run", return_value=routes), patch.object(pd, "lease_delegation", return_value=pd.ranges("240b:10:3f6d:1400::/56")), patch.object(pd, "sync_boundary"), patch.object(pd, "router_address", return_value="240b:10:3f6d:1402::1"), patch.object(pd, "sync_routes", side_effect=RuntimeError("interrupted")):
            with self.assertRaises(RuntimeError):
                pd.reconcile(Kube(), {}, "vlan20", "vlan30", "wan")
        self.assertEqual(writes, ["CiliumPodIPPool"])

    def test_restart_retains_old_generation_until_verified(self):
        old = pd.ranges("240b:10:3f6d:1400::/56")
        new = pd.ranges("240b:10:1234:5600::/56")
        writes, boundaries = [], []
        class Kube:
            def get(self, kind, *args, **kwargs):
                if kind == "ciliumpodippools":
                    return {"items": [pd.pod_pool(old)]}
                if kind == "configmap":
                    return {"data": {"generation": new["pool"], "phase": "migrating"}}
                return {"items": []}
            def apply(self, obj):
                writes.append(obj["kind"])
            def cm(self, *args):
                writes.append("desired")
        routes = '[{"type":"unreachable","dst":"240b:10:1234:5600::/56"}]'
        with patch.object(pd, "run", return_value=routes), patch.object(pd, "lease_delegation", return_value=new), patch.object(pd, "sync_routes"), patch.object(pd, "router_address", return_value="240b:10:1234:5602::1"), patch.object(pd, "sync_boundary", side_effect=lambda g, source: boundaries.extend(g)):
            pd.reconcile(Kube(), {}, "vlan20", "vlan30", "wan")
        self.assertEqual({g["pool"] for g in boundaries}, {old["pool"], new["pool"]})
        self.assertEqual(writes, ["CiliumPodIPPool", "desired"])


if __name__ == "__main__":
    unittest.main()
