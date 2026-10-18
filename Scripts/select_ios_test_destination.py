#!/usr/bin/env python3
"""Select an available iPhone on an ephemeral GitHub-hosted CI runner."""
import json
import re
import subprocess
import uuid


def select_destination(inventory):
    if not isinstance(inventory, dict) or not isinstance(inventory.get("runtimes"), list) or not isinstance(inventory.get("devices"), dict):
        raise ValueError("Expected a simctl runtime and device inventory")
    runtimes = []
    for runtime in inventory.get("runtimes", []):
        if not isinstance(runtime, dict):
            continue
        identifier = runtime.get("identifier", "")
        version = runtime.get("version", "")
        if (runtime.get("isAvailable") is True
                and isinstance(identifier, str) and isinstance(version, str)
                and identifier.startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
                and re.fullmatch(r"\d+(?:\.\d+){0,2}", version)):
            runtimes.append((tuple(map(int, version.split("."))), identifier))
    for _, identifier in sorted(runtimes, reverse=True):
        devices = inventory.get("devices", {}).get(identifier, [])
        if not isinstance(devices, list):
            continue
        phones = sorted((device for device in devices if isinstance(device, dict)
                         and device.get("isAvailable") is True and isinstance(device.get("name"), str)
                         and device["name"].startswith("iPhone")), key=lambda d: d["name"])
        for device in phones:
            try:
                identifier = str(uuid.UUID(device.get("udid", ""))).upper()
            except (ValueError, AttributeError, TypeError):
                continue
            return "platform=iOS Simulator,id=" + identifier
    raise ValueError("No available iPhone simulator exists on this CI runner")


if __name__ == "__main__":
    inventory = subprocess.check_output(["xcrun", "simctl", "list", "--json"], text=True, timeout=60)
    print(select_destination(json.loads(inventory)))
