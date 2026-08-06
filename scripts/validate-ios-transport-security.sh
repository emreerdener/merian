#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "error: iOS transport-security validation failed: $*" >&2
  exit 1
}

(( $# == 1 || $# == 2 )) \
  || fail "usage: $0 INFO_PLIST [--allow-build-settings]"

plist="$1"
allow_build_settings="false"
if (( $# == 2 )); then
  [[ "$2" == "--allow-build-settings" ]] \
    || fail "the only supported option is --allow-build-settings."
  allow_build_settings="true"
fi

[[ -f "$plist" && ! -L "$plist" ]] \
  || fail "Info.plist must be a regular, non-symbolic-link file: $plist"
command -v python3 >/dev/null 2>&1 \
  || fail "python3 is required to inspect Info.plist."

python3 - "$plist" "$allow_build_settings" <<'PY'
import plistlib
import sys
from pathlib import Path
from urllib.parse import urlsplit


def fail(message: str) -> None:
    print(f"error: iOS transport-security validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


path = Path(sys.argv[1])
allow_build_settings = sys.argv[2] == "true"
try:
    with path.open("rb") as plist_file:
        info = plistlib.load(plist_file)
except (OSError, plistlib.InvalidFileException) as error:
    fail(f"{path} could not be parsed: {error}")

if not isinstance(info, dict):
    fail(f"{path} root must be a dictionary.")

ats = info.get("NSAppTransportSecurity", {})
if not isinstance(ats, dict):
    fail("NSAppTransportSecurity must be a dictionary when present.")

for key in (
    "NSAllowsArbitraryLoads",
    "NSAllowsArbitraryLoadsForMedia",
    "NSAllowsArbitraryLoadsInWebContent",
    "NSAllowsLocalNetworking",
):
    value = ats.get(key)
    if value is not None and not isinstance(value, bool):
        fail(f"{key} must be Boolean when present.")
    if value is True:
        fail(f"{key} must not enable a transport-security exception.")

if "NSExceptionDomains" in ats:
    fail("NSExceptionDomains is not approved for the main app target.")

supabase_url = info.get("SUPABASE_URL")
if supabase_url is not None:
    if not isinstance(supabase_url, str) or not supabase_url.strip():
        fail("SUPABASE_URL must be a non-empty string when present.")
    supabase_url = supabase_url.strip()
    if supabase_url.startswith("$(") and supabase_url.endswith(")"):
        if not allow_build_settings:
            fail("an archived SUPABASE_URL cannot contain an unresolved build setting.")
    else:
        parsed = urlsplit(supabase_url)
        if (
            parsed.scheme.lower() != "https"
            or not parsed.hostname
            or parsed.username is not None
            or parsed.password is not None
        ):
            fail("SUPABASE_URL must be a credential-free HTTPS URL.")

print(
    "iOS transport security verified: ATS defaults enforced; "
    "domainExceptions=0; configuredRemoteOrigins=https-only."
)
PY
