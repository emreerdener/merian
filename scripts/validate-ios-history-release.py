#!/usr/bin/env python3
"""Validate the bundled primary-app History capability before distribution.

This checks metadata, not compiler provenance, signing, or functional acceptance.
The generated-project tests and exact Release build establish compiled behavior.
"""
import plistlib
import sys
from pathlib import Path
from urllib.parse import urlsplit


def main() -> None:
    if len(sys.argv) != 2:
        raise ValueError("usage: validate-ios-history-release.py INFO_PLIST")
    path = Path(sys.argv[1])
    if path.is_symlink() or not path.is_file():
        raise ValueError("Info.plist must be a regular, non-symbolic-link file")
    with path.open("rb") as stream:
        info = plistlib.load(stream)
    expected = {
        "CFBundleIdentifier": "app.merian.Merian",
        "MERIAN_HISTORY_NORMAL_OAUTH": "1",
        "MERIAN_HISTORY_QUALIFICATION": "0",
        "MERIAN_AUTH_NAMESPACE": "",
        "MERIAN_APP_GROUP_IDENTIFIER": "group.app.merian.shared",
        "MERIAN_KEYCHAIN_NAMESPACE": "app.merian.shared",
    }
    if not isinstance(info, dict):
        raise ValueError("Info.plist root must be a dictionary")
    for key, value in expected.items():
        if info.get(key) != value or not isinstance(info.get(key), str):
            raise ValueError(f"{key} does not match the enabled primary History release contract")
    raw_url = info.get("SUPABASE_URL")
    if not isinstance(raw_url, str):
        raise ValueError("SUPABASE_URL must identify the approved History backend")
    raw_url = raw_url.strip()
    if any(ord(character) < 33 for character in raw_url):
        raise ValueError("SUPABASE_URL must identify the approved History backend")
    url = urlsplit(raw_url)
    # Exact authority also excludes credentials, explicit ports and host aliases.
    # Empty query/fragment delimiters are rejected, matching Foundation's nil check.
    if (url.scheme != "https" or url.netloc != "qlarqavoqhkuwzmevrmf.supabase.co"
            or url.path not in ("", "/") or "?" in raw_url or "#" in raw_url):
        raise ValueError("SUPABASE_URL must identify the approved History backend")
    print("History release metadata verified: enabled; normal OAuth; primary namespaces.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        print(f"error: History release validation failed: {error}", file=sys.stderr)
        raise SystemExit(1) from None
