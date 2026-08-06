#!/usr/bin/env python3
import plistlib
import sys
from pathlib import Path


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


if len(sys.argv) != 4 or sys.argv[1] != "-c":
    fail("usage: test-plistbuddy.py -c 'Print :key:path' PLIST")

command = sys.argv[2]
if not command.startswith("Print :"):
    fail("test plist reader supports only PlistBuddy Print commands")

try:
    with Path(sys.argv[3]).open("rb") as plist_file:
        value = plistlib.load(plist_file)
    for component in command.removeprefix("Print :").split(":"):
        if isinstance(value, dict):
            value = value[component]
        elif isinstance(value, list):
            value = value[int(component)]
        else:
            fail(f"cannot traverse {component} in a scalar plist value")
except (OSError, KeyError, IndexError, ValueError, TypeError, plistlib.InvalidFileException) as error:
    fail(str(error))

if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (str, int, float)):
    print(value)
else:
    fail("test plist reader supports only scalar Print results")
