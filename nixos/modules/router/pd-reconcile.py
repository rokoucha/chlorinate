#!/usr/bin/env python3
"""Reconcile DHCP-PD, Cilium pools, boundary rules and actual node allocations."""
import argparse
import ipaddress
import json
import os
import socket
import subprocess
import time
import urllib.parse

LABEL = "pd.materia.rokoucha.com/managed"
PROTOCOL = "186"


def run(*args, stdin=None):
    return subprocess.run(args, input=stdin, text=True, check=True, capture_output=True).stdout


def ranges(prefix):
    pd = ipaddress.ip_network(prefix)
    if pd.version != 6 or pd.prefixlen != 56 or not pd.is_global:
        raise ValueError("exactly one global /56 delegation is required")
    base = int(pd.network_address) + (3 << 64)
    return {"pool": "pd-" + pd.network_address.packed.hex(),
            "reservedCIDR": str(ipaddress.IPv6Network((base, 64))),
            "nodeCIDR": str(ipaddress.IPv6Network((base - (1 << 64), 64))),
            "podCIDR": str(ipaddress.IPv6Network((base + (0x1000 << 48), 108))),
            "lbCIDR": str(ipaddress.IPv6Network((base + (0xffff << 48), 112)))}


def lease_delegation(link, now):
    prefixes = link.get("DHCPv6Client", {}).get("Prefixes", [])
    preferred = {p["PrefixString"] + "/56" for p in prefixes
                 if p.get("PrefixLength") == 56 and p.get("PreferredLifetimeUSec", 0) > now
                 and p.get("ValidLifetimeUSec", 0) > now}
    if len(preferred) != 1:
        raise ValueError("a unique preferred live /56 lease is required")
    selected = ipaddress.ip_network(preferred.pop())
    # networkd can keep a valid lease without a covering unreachable route.
    return ranges(str(selected))


class Kube:
    def __init__(self, config):
        self.args = ["kubectl", "--kubeconfig", config, "--request-timeout=30s"]
        view = json.loads(run(*self.args, "config", "view", "--minify", "-o", "json"))
        host = urllib.parse.urlparse(view["clusters"][0]["cluster"]["server"]).hostname
        if ipaddress.ip_address(host).version != 4:
            raise ValueError("kubeconfig must use an IPv4 API endpoint")

    def get(self, kind, name=None, ns=None, optional=False):
        args = ["get", kind] + ([name] if name else []) + (["-n", ns] if ns else ["-A"])
        if optional:
            args += ["--ignore-not-found"]
        value = run(*self.args, *args, "-o", "json")
        return json.loads(value) if value.strip() else None

    def apply(self, obj):
        manager = "cilium-lb-ipv6-pool-updater" if obj["kind"] == "CiliumLoadBalancerIPPool" else "pd-router"
        run(*self.args, "apply", "--server-side", "--field-manager=" + manager, "-f", "-", stdin=json.dumps(obj))

    def cm(self, name, data):
        self.apply({"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": name, "namespace": "kube-system"}, "data": data})


def pod_pool(generation):
    return {"apiVersion": "cilium.io/v2alpha1", "kind": "CiliumPodIPPool",
            "metadata": {"name": generation["pool"], "labels": {LABEL: "true"}},
            "spec": {"allowFirstIP": False, "allowLastIP": False,
                     "ipv6": {"cidrs": [generation["podCIDR"]], "maskSize": 120}}}


def desired_routes(nodes, gateways, pod_cidrs, lb_cidrs, lan, lb_lan):
    routes = {cidr: (None, lb_lan) for cidr in lb_cidrs}
    for node in nodes:
        name = node["metadata"]["name"]
        gateway = gateways[name]  # Missing nodes must block deletion of existing routes.
        if not ipaddress.ip_address(gateway).is_link_local:
            raise ValueError("node gateway must be link-local")
        for pool in node["spec"]["ipam"].get("pools", {}).get("allocated", []):
            for raw in pool["cidrs"]:
                cidr = ipaddress.ip_network(raw)
                if cidr.version != 6 or not any(cidr.subnet_of(parent) for parent in pod_cidrs):
                    continue
                if cidr.prefixlen != 120:
                    raise ValueError("unexpected per-node CIDR " + raw)
                if raw in routes and routes[raw] != (gateway, lan):
                    raise ValueError("overlapping node allocation " + raw)
                routes[raw] = (gateway, lan)
    return routes


def sync_routes(desired):
    existing = json.loads(run("ip", "-j", "-6", "route", "show", "proto", PROTOCOL))
    existing = {r["dst"]: (r.get("gateway"), r["dev"]) for r in existing}
    for cidr, (gateway, dev) in desired.items():
        if existing.get(cidr) == (gateway, dev):
            continue
        args = ["ip", "-6", "route", "replace", cidr, "dev", dev, "proto", PROTOCOL]
        if gateway:
            args += ["via", gateway]
        run(*args)
    for cidr in existing.keys() - desired.keys():
        run("ip", "-6", "route", "del", cidr, "proto", PROTOCOL)


def sync_boundary(generations):
    generations = list(generations)
    sets = {"pd_node_lans": sorted({g["nodeCIDR"] for g in generations}),
            "pd_pods": sorted({g["podCIDR"] for g in generations}),
            "pd_lbs": sorted({g["lbCIDR"] for g in generations})}
    commands = []
    for name, values in sets.items():
        commands.append("flush set inet filter " + name)
        if values:
            commands.append("add element inet filter " + name + " { " + ", ".join(values) + " }")
    run("nft", "-f", "-", stdin="\n".join(commands) + "\n")


def lb_pool(generation):
    return {"apiVersion": "cilium.io/v2", "kind": "CiliumLoadBalancerIPPool",
            "metadata": {"name": "materia-public-ipv6"},
            "spec": {"blocks": [{"cidr": generation["lbCIDR"]}],
                     "serviceSelector": {"matchLabels": {"chlorinate.rokoucha.com/lb": "public"}}}}


def public_ready(kube, generation):
    cidr = ipaddress.ip_network(generation["lbCIDR"])
    services = [s for s in kube.get("services")["items"]
                if s["metadata"].get("labels", {}).get("chlorinate.rokoucha.com/lb") == "public"
                and "IPv6" in s["spec"].get("ipFamilies", [])]
    if not services:
        return False
    ingress_ips = set()
    for service in services:
        allocated = {i["ip"] for i in service.get("status", {}).get("loadBalancer", {}).get("ingress", []) if "ip" in i}
        v6 = {a for a in allocated if ipaddress.ip_address(a).version == 6}
        if not v6 or not all(ipaddress.ip_address(a) in cidr for a in v6):
            return False
        if service["metadata"].get("labels", {}).get("external-dns.rokoucha.com/scope") == "ingress-lb-v6":
            ingress_ips |= v6
        names = [v for k, v in service["metadata"].get("annotations", {}).items() if k.endswith("external-dns.alpha.kubernetes.io/hostname")]
        for nameset in names:
            for name in nameset.split(","):
                answers = {a[4][0] for a in socket.getaddrinfo(name.strip(), None, socket.AF_INET6)}
                if answers != v6:
                    return False
    # This exercises NDP and the LB datapath from the router. An independent
    # external check is still required for initial production acceptance.
    if not ingress_ips:
        return False
    for address in ingress_ips:
        run("curl", "-6", "--fail", "--silent", "--max-time", "20", "--output", "/dev/null",
            "--resolve", "ggrel.net:443:[" + address + "]", "https://ggrel.net/")
    return True


def reconcile(kube, gateways, lan, lb_lan, wan):
    link = json.loads(run("networkctl", "--json=short", "status", wan))
    current = lease_delegation(link, time.clock_gettime(getattr(time, "CLOCK_BOOTTIME", time.CLOCK_MONOTONIC)) * 1_000_000)
    # Pools encode previous generations; a restart cannot lose retention state.
    pools = kube.get("ciliumpodippools")["items"]
    generations = {current["pool"]: current}
    managed = []
    for pool in pools:
        if pool["metadata"].get("labels", {}).get(LABEL) != "true":
            continue
        name = pool["metadata"]["name"]
        pd = ipaddress.IPv6Network((int(name.removeprefix("pd-"), 16), 56))
        generation = ranges(str(pd))
        if pool["spec"] != pod_pool(generation)["spec"]:
            raise ValueError("managed pool spec differs: " + name)
        generations[name] = generation
        managed.append(pool)
    kube.apply(pod_pool(current))
    nodes = kube.get("ciliumnodes")["items"]
    # Validate the complete route plan before changing the firewall or routes.
    route_plan = desired_routes(nodes, gateways,
                                [ipaddress.ip_network(g["podCIDR"]) for g in generations.values()],
                                [g["lbCIDR"] for g in generations.values()], lan, lb_lan)
    sync_boundary(generations.values())
    sync_routes(route_plan)
    kube.cm("pd-desired", current)
    status = kube.get("configmap", "pd-migration-status", "kube-system", optional=True)
    data = status.get("data", {}) if status else {}
    if data.get("generation") != current["pool"] or data.get("phase") != "pods-ready":
        print("waiting for pod migration", flush=True)
        return
    kube.apply(lb_pool(current))
    if not public_ready(kube, current) or data.get("egressVerified") != current["pool"]:
        print("waiting for LB/DNS/IPv6 egress verification", flush=True)
        return
    used = {a["pool"] for n in nodes for a in n["spec"]["ipam"].get("pools", {}).get("allocated", [])}
    used |= {a["pool"] for n in nodes for a in n["spec"]["ipam"].get("pools", {}).get("requested", [])}
    endpoints = kube.get("ciliumendpoints")["items"]
    for pool in managed:
        name = pool["metadata"]["name"]
        if name == current["pool"] or name in used:
            continue
        old = ipaddress.ip_network(generations[name]["podCIDR"])
        if any(ipaddress.ip_address(a["ipv6"]) in old for e in endpoints
               for a in e.get("status", {}).get("networking", {}).get("addressing", []) if a.get("ipv6")):
            continue
        run(*kube.args, "delete", "ciliumpodippool", name, "--wait=false")
    # Next pass recomputes the boundary/routes from remaining live allocations.
    print("verified generation " + current["pool"], flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--kubeconfig", required=True)
    parser.add_argument("--gateways", required=True)
    parser.add_argument("--lan", required=True)
    parser.add_argument("--lb-lan", required=True)
    parser.add_argument("--wan", required=True)
    args = parser.parse_args()
    with open(args.gateways) as f:
        gateways = json.load(f)
    reconcile(Kube(args.kubeconfig), gateways, args.lan, args.lb_lan, args.wan)
