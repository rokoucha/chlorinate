"""Smoke-test the evaluated sFlow service config on a disposable loopback agent."""
from pathlib import Path
import shlex
import subprocess
import tempfile


command = shlex.split(subprocess.check_output([
    "nix", "eval", "--raw",
    ".#nixosConfigurations.chlorine.config.systemd.services.hsflowd.serviceConfig.ExecStart",
], text=True))
with tempfile.TemporaryDirectory() as directory:
    directory = Path(directory)
    directory.chmod(0o755)
    source = Path(command[command.index("-f") + 1]).read_text()
    source = source.replace("enp5s0f1.10", "lo").replace("enp5s0f1", "lo").replace("172.16.3.12", "127.0.0.1")
    config = directory / "hsflowd.conf"
    config.write_text(source)
    for flag, path in [("-f", config), ("-p", directory / "pid"), ("-o", directory / "auto")]:
        command[command.index(flag) + 1] = str(path)
    result = subprocess.run(["sudo", "timeout", "3", *command])
    if result.returncode != 124:
        raise SystemExit(f"Exporter exited before the startup deadline: {result.returncode}")
print("sFlow config parsed and exporter stayed running")
