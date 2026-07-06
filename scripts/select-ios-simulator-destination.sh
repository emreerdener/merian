#!/usr/bin/env bash
set -euo pipefail

preferred_prefix="${IOS_SIMULATOR_DEVICE_PREFIX:-iPhone}"
if [ -z "${SIMCTL_DEVICES_JSON:-}" ]; then
  SIMCTL_DEVICES_JSON="$(xcrun simctl list devices available -j)"
fi
export SIMCTL_DEVICES_JSON

python3 - "$preferred_prefix" <<'PY'
import json
import os
import re
import sys

preferred_prefix = sys.argv[1]
data = json.loads(os.environ["SIMCTL_DEVICES_JSON"])


def runtime_version(runtime_id):
    numbers = re.findall(r"\d+", runtime_id)
    return tuple(int(number) for number in numbers)


def device_rank(name):
    if name.startswith(preferred_prefix):
        return 0
    return 1


candidates = []
ordinal = 0
for runtime_id, devices in data.get("devices", {}).items():
    if "iOS" not in runtime_id:
        continue

    version = runtime_version(runtime_id)
    for device in devices:
        if not device.get("isAvailable", False):
            continue

        name = device.get("name", "")
        udid = device.get("udid")
        if not udid:
            continue

        candidates.append((device_rank(name), tuple(-part for part in version), ordinal, name, udid))
        ordinal += 1

if not candidates:
    print("No available iOS simulators found.", file=sys.stderr)
    sys.exit(1)

candidates.sort()
_, _, _, _, udid = candidates[0]
print(f"platform=iOS Simulator,id={udid}")
PY
