import ipaddress
import json
from pathlib import Path
import re
import subprocess
import sys
import time


def hosts(link, now, subnet="172.16.1.0/24"):
    records = []
    for lease in link.get("DHCPServer", {}).get("Leases", []):
        name = lease.get("Hostname", "").split(".")[0].lower()
        if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", name):
            continue
        if lease.get("ExpirationUSec", 0) <= now:
            continue
        if lease.get("HardwareAddressType") != 1 or lease.get("HardwareAddressLength") != 6:
            continue
        mac = bytes(lease["HardwareAddress"][:6]).hex()
        address = ipaddress.IPv4Address(bytes(lease["Address"]))
        if address not in ipaddress.IPv4Network(subnet):
            continue
        records.append(f"{address} {name}.home.arpa mac-{mac}.devices.home.arpa\n")
    return "".join(sorted(records))


def main():
    now = time.clock_gettime(time.CLOCK_BOOTTIME) * 1_000_000
    records = []
    for interface, subnet in zip(sys.argv[1::2], sys.argv[2::2], strict=True):
        link = json.loads(subprocess.check_output(
            ["networkctl", "--json=short", "status", interface], timeout=10
        ))
        records.append(hosts(link, now, subnet))
    content = "".join(records)
    target = Path("/run/networkd-dns/hosts")
    if content != target.read_text():
        temporary = target.with_suffix(".new")
        temporary.write_text(content)
        temporary.replace(target)
        subprocess.run(["systemctl", "kill", "--kill-whom=main", "--signal=HUP", "dnsmasq.service"], check=True)


if __name__ == "__main__":
    main()
