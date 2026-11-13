#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive_validator="$repo_root/scripts/validate-ios-archive.sh"
privacy_manifest="$repo_root/apps/ios/Merian/Configuration/PrivacyInfo.xcprivacy"
plistbuddy_fixture="$repo_root/scripts/test-plistbuddy.py"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-archive-validation-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

expected_revision="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
expected_fingerprint="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
archive_path="$test_root/Merian.xcarchive"
app_path="$archive_path/Products/Applications/Merian.app"
bundled_privacy_manifest="$app_path/PrivacyInfo.xcprivacy"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_fails_with() {
  local expected="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    fail "expected command to fail: $*"
  fi
  grep -Fq -- "$expected" <<<"$output" \
    || fail "expected failure to contain '$expected'; actual: $output"
}

mkdir -p \
  "$app_path/PlugIns/MerianExploreWidget.appex" \
  "$app_path/PlugIns/MerianMessagesExtension.appex" \
  "$app_path/Watch/MerianWatch.app"

python3 - \
  "$archive_path" \
  "$app_path" \
  "$expected_revision" \
  "$expected_fingerprint" <<'PY'
import plistlib
import sys
from pathlib import Path

archive_path = Path(sys.argv[1])
app_path = Path(sys.argv[2])
source_revision = sys.argv[3]
source_fingerprint = sys.argv[4]


def write_plist(path, value):
    with path.open("wb") as plist_file:
        plistlib.dump(value, plist_file, sort_keys=False)


write_plist(
    archive_path / "Info.plist",
    {"ApplicationProperties": {"ApplicationPath": "Applications/Merian.app"}},
)
write_plist(
    app_path / "Info.plist",
    {
        "CFBundleIdentifier": "app.merian.Merian",
        "MERIAN_HISTORY_NORMAL_OAUTH": "1",
        "MERIAN_HISTORY_QUALIFICATION": "0",
        "MERIAN_AUTH_NAMESPACE": "",
        "MERIAN_APP_GROUP_IDENTIFIER": "group.app.merian.shared",
        "MERIAN_KEYCHAIN_NAMESPACE": "app.merian.shared",
        "CFBundleShortVersionString": "1.0.3",
        "CFBundleVersion": "275",
        "MERIAN_SOURCE_REVISION": source_revision,
        "MERIAN_SOURCE_FINGERPRINT": source_fingerprint,
        "MERIAN_SOURCE_STATE": "clean",
        "SUPABASE_URL": "https://qlarqavoqhkuwzmevrmf.supabase.co",
    },
)

component_info = {
    "CFBundleShortVersionString": "1.0.3",
    "CFBundleVersion": "275",
}
for relative_path in (
    "PlugIns/MerianExploreWidget.appex/Info.plist",
    "PlugIns/MerianMessagesExtension.appex/Info.plist",
    "Watch/MerianWatch.app/Info.plist",
):
    write_plist(app_path / relative_path, component_info)
PY

cp "$privacy_manifest" "$bundled_privacy_manifest"

validation_command=(
  env MERIAN_PLISTBUDDY_COMMAND="$plistbuddy_fixture"
  bash "$archive_validator"
  "$archive_path"
  app.merian.Merian
  1.0.3
  275
  "$expected_revision"
  "$expected_fingerprint"
)

output="$("${validation_command[@]}")" \
  || fail "archive fixture with a valid privacy manifest must pass"
grep -Fq "privacyManifest=valid" <<<"$output" \
  || fail "archive validation did not report a valid privacy manifest"
grep -Fq "transportSecurity=ats-default" <<<"$output" \
  || fail "archive validation did not report ATS-default transport security"

# A final regular plist must not hide an external app behind a parent symlink.
mv "$app_path" "$test_root/external.app"
ln -s "$test_root/external.app" "$app_path"
assert_fails_with "path contains a symbolic link" "${validation_command[@]}"
rm "$app_path"
mv "$test_root/external.app" "$app_path"

for case_name in disabled qualification namespace missing boolean appgroup keychain host credentials port path query fragment emptyquery emptyfragment; do
  python3 - "$app_path/Info.plist" "$case_name" <<'PYCASE'
import plistlib, sys
from pathlib import Path
p = Path(sys.argv[1])
x = plistlib.loads(p.read_bytes())
x.update(MERIAN_HISTORY_NORMAL_OAUTH="1", MERIAN_HISTORY_QUALIFICATION="0", MERIAN_AUTH_NAMESPACE="", MERIAN_APP_GROUP_IDENTIFIER="group.app.merian.shared", MERIAN_KEYCHAIN_NAMESPACE="app.merian.shared", SUPABASE_URL="https://qlarqavoqhkuwzmevrmf.supabase.co")
case = sys.argv[2]
if case == "disabled": x["MERIAN_HISTORY_NORMAL_OAUTH"] = "0"
if case == "qualification": x["MERIAN_HISTORY_QUALIFICATION"] = "1"
if case == "namespace": x["MERIAN_AUTH_NAMESPACE"] = "synthetic-other"
if case == "missing": del x["MERIAN_HISTORY_NORMAL_OAUTH"]
if case == "boolean": x["MERIAN_HISTORY_NORMAL_OAUTH"] = True
if case == "appgroup": x["MERIAN_APP_GROUP_IDENTIFIER"] = "group.synthetic.other"
if case == "keychain": x["MERIAN_KEYCHAIN_NAMESPACE"] = "synthetic.other"
invalid_urls = {
    "host": "https://project.supabase.co",
    "credentials": "https://synthetic@qlarqavoqhkuwzmevrmf.supabase.co",
    "port": "https://qlarqavoqhkuwzmevrmf.supabase.co:443",
    "path": "https://qlarqavoqhkuwzmevrmf.supabase.co/rest/v1",
    "query": "https://qlarqavoqhkuwzmevrmf.supabase.co?synthetic=1",
    "fragment": "https://qlarqavoqhkuwzmevrmf.supabase.co#synthetic",
    "emptyquery": "https://qlarqavoqhkuwzmevrmf.supabase.co?",
    "emptyfragment": "https://qlarqavoqhkuwzmevrmf.supabase.co#",
}
if case in invalid_urls: x["SUPABASE_URL"] = invalid_urls[case]
p.write_bytes(plistlib.dumps(x))
PYCASE
  assert_fails_with "History release validation failed" "${validation_command[@]}"
done
python3 - "$app_path/Info.plist" <<'PYRESTORE'
import plistlib, sys
from pathlib import Path
p = Path(sys.argv[1]); x = plistlib.loads(p.read_bytes())
x.update(MERIAN_HISTORY_NORMAL_OAUTH="1", MERIAN_HISTORY_QUALIFICATION="0", MERIAN_AUTH_NAMESPACE="", MERIAN_APP_GROUP_IDENTIFIER="group.app.merian.shared", MERIAN_KEYCHAIN_NAMESPACE="app.merian.shared", SUPABASE_URL="https://qlarqavoqhkuwzmevrmf.supabase.co")
p.write_bytes(plistlib.dumps(x))
PYRESTORE

rm "$bundled_privacy_manifest"
assert_fails_with \
  "manifest must be a regular, non-symbolic-link file" \
  "${validation_command[@]}"

cp "$privacy_manifest" "$bundled_privacy_manifest"
python3 - "$bundled_privacy_manifest" <<'PY'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
with path.open("rb") as manifest_file:
    manifest = plistlib.load(manifest_file)
manifest["NSPrivacyTracking"] = True
with path.open("wb") as manifest_file:
    plistlib.dump(manifest, manifest_file, sort_keys=False)
PY
assert_fails_with \
  "NSPrivacyTracking must be false" \
  "${validation_command[@]}"

cp "$privacy_manifest" "$bundled_privacy_manifest"
python3 - "$app_path/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
with path.open("rb") as plist_file:
    info = plistlib.load(plist_file)
info["NSAppTransportSecurity"] = {"NSAllowsArbitraryLoads": True}
with path.open("wb") as plist_file:
    plistlib.dump(info, plist_file, sort_keys=False)
PY
assert_fails_with \
  "NSAllowsArbitraryLoads must not enable" \
  "${validation_command[@]}"

echo "iOS Release archive privacy-manifest and transport-security tests passed."
