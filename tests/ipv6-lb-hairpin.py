#!/usr/bin/env python3
"""Exercise the router's actual hairpin rules with asymmetric IPv6 replies."""
import importlib.util
import os
from pathlib import Path
import subprocess
import time

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("pd", root / "nixos/modules/router/pd-reconcile.py")
pd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pd)


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs)


names = {name: f"hairpin-{os.getpid()}-{name}" for name in ("client", "router", "server")}
server = None
try:
    for name in names.values():
        run("ip", "netns", "add", name)
        run("ip", "-n", name, "link", "set", "lo", "up")
    for number, (left, right, left_if, right_if, left_ip, right_ip) in enumerate([
        ("client", "router", "router", "client", "fd42:1::2", "fd42:1::1"),
        ("router", "server", "server", "router", "fd42:2::1", "fd42:2::2"),
        ("server", "client", "direct", "direct", "fd42:4::1", "fd42:4::2"),
    ]):
        a, b = f"hp{os.getpid()}a{number}", f"hp{os.getpid()}b{number}"
        run("ip", "link", "add", a, "type", "veth", "peer", "name", b)
        for device, node, interface, address in ((a, left, left_if, left_ip), (b, right, right_if, right_ip)):
            run("ip", "link", "set", device, "netns", names[node])
            run("ip", "-n", names[node], "link", "set", device, "name", interface)
            run("ip", "-n", names[node], "-6", "addr", "add", address + "/64", "dev", interface, "nodad")
            run("ip", "-n", names[node], "link", "set", interface, "up")
    run("ip", "netns", "exec", names["router"], "sysctl", "-qw", "net.ipv6.conf.all.forwarding=1")
    run("ip", "-n", names["server"], "-6", "addr", "add", "fd42:3::2/128", "dev", "lo", "nodad")
    for node, destination, gateway in [
        ("client", "fd42:3::/64", "fd42:1::1"),
        ("router", "fd42:3::/64", "fd42:2::2"),
        ("server", "fd42:1::2/128", "fd42:4::2"),
        ("server", "fd42:1::1/128", "fd42:2::1"),
    ]:
        run("ip", "-n", names[node], "-6", "route", "add", destination, "via", gateway)
    # Without SNAT, SYN-ACK bypasses the router, so the client's ACK is invalid there.
    rules = '''table inet filter {
      set pd_node_lans { type ipv6_addr; flags interval; }
      set pd_pods { type ipv6_addr; flags interval; }
      set pd_lbs { type ipv6_addr; flags interval; }
      chain forward { type filter hook forward priority filter; policy drop;
        meta l4proto ipv6-icmp accept
        ct state established,related accept
        iifname "client" oifname "server" ct state new accept
      }
    }'''
    firewall = (root / "nixos/modules/router/firewall.nix").read_text()
    hairpin = firewall[firewall.index("            map pd_lb_hairpin_snat"):firewall.index("            chain forward {")]
    hairpin = hairpin.replace("$SRV_LAN", '"client"').replace("$MATERIA_LAN", '"server"')
    router_nft = ["ip", "netns", "exec", names["router"], "nft", "-f", "-"]
    run(*router_nft, input=rules[:-1] + hairpin + "}")
    server_code = '''import http.server,socket
http.server.ThreadingHTTPServer.address_family=socket.AF_INET6
http.server.ThreadingHTTPServer(("fd42:3::2",8080),http.server.BaseHTTPRequestHandler).serve_forever()
'''
    server = subprocess.Popen(["ip", "netns", "exec", names["server"], "python3", "-c", server_code], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)
    curl = ["ip", "netns", "exec", names["client"], "curl", "--noproxy", "*", "-g", "-sS", "--max-time", "2", "-o", "/dev/null", "-w", "%{http_code}", "http://[fd42:3::2]:8080/"]
    before = subprocess.run(curl, text=True, capture_output=True)
    assert before.returncode == 28, (before.returncode, before.stdout, before.stderr)
    # Populate the real reconciler's atomic boundary/map update with the test prefix.
    def nft_run(*args, stdin=None):
        assert args == ("nft", "-f", "-")
        return run(*router_nft, input=stdin).stdout
    pd.run = nft_run
    pd.sync_boundary([{"nodeCIDR": "fd42:1::/64", "podCIDR": "fd42:5::/64", "lbCIDR": "fd42:3::/64"}], "fd42:1::1")
    after = run(*curl)
    assert after.stdout == "501", after.stdout
    print("IPv6 asymmetric path reproduced; actual IaC SNAT rules restore TCP/HTTP.")
finally:
    if server:
        server.terminate()
        server.wait(timeout=5)
    for name in reversed(list(names.values())):
        subprocess.run(["ip", "netns", "del", name], capture_output=True)
