#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-versioning-tests.XXXXXX")"
valid_revenuecat_key="appl_1234567890abcdef1234567890abcdef"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

write_project_yml() {
  local version="$1"
  local build="$2"
  local file="$tmp_dir/project.yml"

  {
    printf 'name: Merian\n'
    printf 'settings:\n'
    printf '  base:\n'
    printf '    CODE_SIGN_STYLE: Automatic\n'
    printf '    MARKETING_VERSION: %s\n' "$version"
    printf '    CURRENT_PROJECT_VERSION: %s\n' "$build"
    printf '    VERSIONING_SYSTEM: apple-generic\n'
  } > "$file"
}

run_prepare() {
  env \
    -u ASC_APP_ID \
    -u ASC_ISSUER_ID \
    -u ASC_KEY_ID \
    -u ASC_PRIVATE_KEY_PATH \
    REVENUECAT_API_KEY="${REVENUECAT_API_KEY:-$valid_revenuecat_key}" \
    PROJECT_YML="$tmp_dir/project.yml" \
    PROJECT_FILE="$tmp_dir/Merian.xcodeproj/project.pbxproj" \
    CONFIG_XCCONFIG="$tmp_dir/Config.xcconfig" \
    LOCAL_CONFIG_FILE="$tmp_dir/Config.local.xcconfig" \
    IOS_RELEASE_PREP_MARKER="$tmp_dir/build/ios-release-prep.json" \
    MERIAN_PROJECT_ROOT="$tmp_dir" \
    RUN_XCODEGEN=0 \
    "$repo_root/scripts/prepare-ios-release.sh"
}

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -Fq -- "$needle" "$file" || fail "Expected $file to contain: $needle"
}

assert_fails() {
  if "$@" >/dev/null 2>&1; then
    fail "Expected command to fail: $*"
  fi
}

assert_fails_with() {
  local expected="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    fail "Expected command to fail: $*"
  fi
  if ! grep -q -- "$expected" <<<"$output"; then
    fail "Expected failing command output to contain: $expected. Actual output: $output"
  fi
}

assert_succeeds_with() {
  local expected="$1"
  shift
  local output
  if ! output="$("$@" 2>&1)"; then
    fail "Expected command to succeed: $*. Actual output: $output"
  fi
  if ! grep -q -- "$expected" <<<"$output"; then
    fail "Expected command output to contain: $expected"
  fi
}

set_marker_value() {
  local key="$1"
  local type="$2"
  local value="$3"
  local file="$4"

  ruby -rjson -e '
    key, type, raw_value, path = ARGV
    document = JSON.parse(File.binread(path))
    abort("marker root must be an object") unless document.is_a?(Hash)

    value = case type
            when "string"
              raw_value
            when "bool"
              abort("invalid bool fixture value") unless %w[true false].include?(raw_value)
              raw_value == "true"
            else
              abort("unsupported fixture type")
            end
    document[key] = value
    File.binwrite(path, JSON.pretty_generate(document) + "\n")
  ' "$key" "$type" "$value" "$file"
}

remove_marker_key() {
  local key="$1"
  local file="$2"

  ruby -rjson -e '
    key, path = ARGV
    document = JSON.parse(File.binread(path))
    abort("marker root must be an object") unless document.is_a?(Hash)
    abort("marker key is missing") unless document.delete(key)
    File.binwrite(path, JSON.pretty_generate(document) + "\n")
  ' "$key" "$file"
}

write_ipa_fixture() {
  local ipa_path="$1"
  local app_bundle_name="$2"
  local bundle_id="$3"
  local version="$4"
  local build="$5"
  local source_revision="$6"
  local source_fingerprint="$7"
  local source_state="$8"
  local component_build="${9:-$build}"
  local topology="${10:-normal}"

  mkdir -p "$(dirname "$ipa_path")"
  python3 - \
    "$ipa_path" \
    "$app_bundle_name" \
    "$bundle_id" \
    "$version" \
    "$build" \
    "$source_revision" \
    "$source_fingerprint" \
    "$source_state" \
    "$component_build" \
    "$topology" <<'PYTHON'
import plistlib
import sys
import warnings
import zipfile

(
    ipa_path,
    app_bundle_name,
    bundle_id,
    version,
    build,
    source_revision,
    source_fingerprint,
    source_state,
    component_build,
    topology,
) = sys.argv[1:]

root_info = {
    "CFBundleIdentifier": bundle_id,
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": build,
    "MERIAN_SOURCE_REVISION": source_revision,
    "MERIAN_SOURCE_FINGERPRINT": source_fingerprint,
    "MERIAN_SOURCE_STATE": source_state,
}
if topology == "missing-fingerprint":
    del root_info["MERIAN_SOURCE_FINGERPRINT"]

component_info = {
    "CFBundleIdentifier": f"{bundle_id}.fixture",
    "CFBundlePackageType": "XPC!",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": component_build,
}
watch_info = {
    "CFBundleIdentifier": f"{bundle_id}.watchkitapp",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": component_build,
}

root_entry = f"Payload/{app_bundle_name}/Info.plist"
warnings.simplefilter("ignore", UserWarning)
with zipfile.ZipFile(ipa_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    archive.writestr(root_entry, plistlib.dumps(root_info))
    archive.writestr(
        f"Payload/{app_bundle_name}/PlugIns/Fixture.appex/Info.plist",
        plistlib.dumps(component_info),
    )
    archive.writestr(
        f"Payload/{app_bundle_name}/Watch/FixtureWatch.app/Info.plist",
        plistlib.dumps(watch_info),
    )
    if topology == "duplicate-root":
        archive.writestr(root_entry, plistlib.dumps(root_info))
    elif topology == "extra-root":
        archive.writestr(
            "Payload/Other.app/Info.plist",
            plistlib.dumps(
                {
                    "CFBundleIdentifier": "invalid.other",
                    "CFBundlePackageType": "APPL",
                    "CFBundleShortVersionString": version,
                    "CFBundleVersion": build,
                }
            ),
        )
PYTHON
}

write_export_archive_fixture() {
  local archive_path="$1"
  local version="$2"
  local build="$3"
  local source_revision="$4"
  local source_fingerprint="$5"

  mkdir -p "$archive_path/Products/Applications/Merian.app"
  python3 - \
    "$archive_path/Info.plist" \
    "$archive_path/Products/Applications/Merian.app/Info.plist" \
    "$version" \
    "$build" \
    "$source_revision" \
    "$source_fingerprint" <<'PYTHON'
import plistlib
import sys

archive_info_path, app_info_path, version, build, revision, fingerprint = sys.argv[1:]

archive_info = {
    "ApplicationProperties": {
        "ApplicationPath": "Applications/Merian.app",
        "Team": "TA8S64ST9W",
    }
}
app_info = {
    "CFBundleIdentifier": "app.merian.Merian",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": build,
    "MERIAN_SOURCE_REVISION": revision,
    "MERIAN_SOURCE_FINGERPRINT": fingerprint,
    "MERIAN_SOURCE_STATE": "clean",
}

with open(archive_info_path, "wb") as handle:
    plistlib.dump(archive_info, handle)
with open(app_info_path, "wb") as handle:
    plistlib.dump(app_info, handle)
PYTHON
}

run_exported_ipa_validator() {
  env \
    MERIAN_PLISTBUDDY_COMMAND="$tmp_dir/fake-bin/PlistBuddy" \
    MERIAN_UNZIP_COMMAND="$(command -v unzip)" \
    MERIAN_SHASUM_COMMAND="$(command -v shasum)" \
    bash "$repo_root/scripts/validate-ios-exported-ipa.sh" \
    "$@"
}

commit_fixture_source() {
  git -C "$tmp_dir" add -A
  git -C "$tmp_dir" commit --allow-empty -q -m "fixture source"
}

git -C "$tmp_dir" init -q
git -C "$tmp_dir" config user.name "Merian Tests"
git -C "$tmp_dir" config user.email "merian-tests@example.invalid"
{
  printf 'build/\n'
  printf 'Config.local.xcconfig\n'
  printf 'xcuserdata/\n'
} > "$tmp_dir/.gitignore"
printf 'let fixture = true\n' > "$tmp_dir/source.swift"
mkdir -p "$tmp_dir/scripts"
cp "$repo_root/scripts/ios-release-source-fingerprint.sh" \
  "$tmp_dir/scripts/ios-release-source-fingerprint.sh"
mkdir -p "$tmp_dir/fake-bin"
{
  printf '#!/usr/bin/env bash\n'
  printf 'if [[ "${1:-}" == "--version" ]]; then\n'
  printf '  printf "Version: 9.9.9\\\\n"\n'
  printf '  exit 0\n'
  printf 'fi\n'
  printf 'exit 99\n'
} > "$tmp_dir/fake-bin/xcodegen"
chmod +x "$tmp_dir/fake-bin/xcodegen"
{
  printf '#!/usr/bin/env bash\n'
  printf 'set -euo pipefail\n'
  printf 'output=""\n'
  printf 'printf "%%s\\n" "$@" >> "${FAKE_ASC_CURL_LOG:?}"\n'
  printf 'while (( $# > 0 )); do\n'
  printf '  case "$1" in\n'
  printf '    -o)\n'
  printf '      output="$2"\n'
  printf '      shift 2\n'
  printf '      ;;\n'
  printf '    *)\n'
  printf '      shift\n'
  printf '      ;;\n'
  printf '  esac\n'
  printf 'done\n'
  printf 'if [[ "${FAKE_ASC_CURL_STATUS:-0}" != "0" ]]; then\n'
  printf '  exit "$FAKE_ASC_CURL_STATUS"\n'
  printf 'fi\n'
  printf 'cp "${FAKE_ASC_RESPONSE:?}" "$output"\n'
  printf 'printf "%%s" "${FAKE_ASC_HTTP_CODE:-200}"\n'
} > "$tmp_dir/fake-bin/curl"
chmod +x "$tmp_dir/fake-bin/curl"
command -v python3 >/dev/null 2>&1 || fail "python3 is required for the portable plist fixture"
{
  printf '#!/usr/bin/env python3\n'
  printf 'import plistlib\n'
  printf 'import shlex\n'
  printf 'import sys\n'
  printf '\n'
  printf 'if len(sys.argv) != 4 or sys.argv[1] != "-c":\n'
  printf '    sys.exit(2)\n'
  printf 'command = shlex.split(sys.argv[2])\n'
  printf 'path = sys.argv[3]\n'
  printf 'with open(path, "rb") as handle:\n'
  printf '    document = plistlib.load(handle)\n'
  printf 'operation = command[0] if command else ""\n'
  printf 'keys = command[1].lstrip(":").split(":") if len(command) > 1 else []\n'
  printf 'container = document\n'
  printf 'for key in keys[:-1]:\n'
  printf '    if not isinstance(container, dict) or key not in container:\n'
  printf '        sys.exit(1)\n'
  printf '    container = container[key]\n'
  printf 'key = keys[-1] if keys else ""\n'
  printf 'if operation == "Print" and len(command) == 2:\n'
  printf '    if not isinstance(container, dict) or key not in container:\n'
  printf '        sys.exit(1)\n'
  printf '    print(container[key])\n'
  printf '    sys.exit(0)\n'
  printf 'if operation == "Set" and len(command) >= 3:\n'
  printf '    if not isinstance(container, dict) or key not in container:\n'
  printf '        sys.exit(1)\n'
  printf '    value = " ".join(command[2:])\n'
  printf 'elif operation == "Add" and len(command) >= 4 and command[2] == "string":\n'
  printf '    if not isinstance(container, dict) or key in container:\n'
  printf '        sys.exit(1)\n'
  printf '    value = " ".join(command[3:])\n'
  printf 'else:\n'
  printf '    sys.exit(2)\n'
  printf 'container[key] = value\n'
  printf 'with open(path, "wb") as handle:\n'
  printf '    plistlib.dump(document, handle, fmt=plistlib.FMT_XML, sort_keys=True)\n'
} > "$tmp_dir/fake-bin/PlistBuddy"
chmod +x "$tmp_dir/fake-bin/PlistBuddy"
write_project_yml "1.0.0" "39"
commit_fixture_source

bash -n "$repo_root/scripts/prepare-ios-release.sh"
bash -n "$repo_root/scripts/check-ios-release-prep.sh"
bash -n "$repo_root/scripts/validate-ios-versioning.sh"
bash -n "$repo_root/scripts/export-ios-release.sh"
bash -n "$repo_root/scripts/validate-ios-exported-ipa.sh"
bash -n "$repo_root/scripts/ios-release-source-fingerprint.sh"
bash -n "$repo_root/scripts/embed-ios-build-provenance.sh"

git -C "$tmp_dir" update-index --assume-unchanged source.swift
assert_fails_with "tracked source uses assume-unchanged or skip-worktree index state" \
  env MERIAN_PROJECT_ROOT="$tmp_dir" \
  "$repo_root/scripts/ios-release-source-fingerprint.sh"
git -C "$tmp_dir" update-index --no-assume-unchanged source.swift

git -C "$tmp_dir" update-index --skip-worktree source.swift
assert_fails_with "tracked source uses assume-unchanged or skip-worktree index state" \
  env MERIAN_PROJECT_ROOT="$tmp_dir" \
  "$repo_root/scripts/ios-release-source-fingerprint.sh"
git -C "$tmp_dir" update-index --no-skip-worktree source.swift

tracked_xcode_user_state="$tmp_dir/Merian.xcodeproj/xcuserdata/fixture.xcuserdatad/xcschemes/xcschememanagement.plist"
mkdir -p "$(dirname "$tracked_xcode_user_state")"
printf '<plist/>\n' > "$tracked_xcode_user_state"
git -C "$tmp_dir" add -f "$tracked_xcode_user_state"
commit_fixture_source
assert_fails_with "tracked Xcode user state is nondeterministic release source" \
  env MERIAN_PROJECT_ROOT="$tmp_dir" \
  "$repo_root/scripts/ios-release-source-fingerprint.sh"
git -C "$tmp_dir" rm -q "$tracked_xcode_user_state"
commit_fixture_source

mkdir -p "$(dirname "$tracked_xcode_user_state")"
printf '<plist><integer>1</integer></plist>\n' > "$tracked_xcode_user_state"
ignored_user_state_fingerprint_before="$(
  MERIAN_PROJECT_ROOT="$tmp_dir" \
    "$repo_root/scripts/ios-release-source-fingerprint.sh"
)"
printf '<plist><integer>2</integer></plist>\n' > "$tracked_xcode_user_state"
ignored_user_state_fingerprint_after="$(
  MERIAN_PROJECT_ROOT="$tmp_dir" \
    "$repo_root/scripts/ios-release-source-fingerprint.sh"
)"
[[ "$ignored_user_state_fingerprint_before" == "$ignored_user_state_fingerprint_after" ]] \
  || fail "Ignored Xcode user state changed the release-source fingerprint"

assert_fails_with "expected revision" \
  env MERIAN_PROJECT_ROOT="$tmp_dir" \
  MERIAN_EXPECTED_SOURCE_REVISION=0000000000000000000000000000000000000000 \
  "$repo_root/scripts/embed-ios-build-provenance.sh"
assert_fails_with "INFOPLIST_PATH contains a traversal component" \
  env MERIAN_PROJECT_ROOT="$tmp_dir" \
  TARGET_BUILD_DIR="$tmp_dir" \
  INFOPLIST_PATH="../outside.plist" \
  "$repo_root/scripts/embed-ios-build-provenance.sh"

provenance_product_dir="$tmp_dir/build/provenance-product"
provenance_relative_plist="Merian.app/Info.plist"
provenance_product_plist="$provenance_product_dir/$provenance_relative_plist"
provenance_outside_plist="$tmp_dir/build/provenance-outside.plist"
mkdir -p "$(dirname "$provenance_product_plist")"
{
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
  printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"'
  printf '%s\n' '  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  printf '%s\n' '<plist version="1.0"><dict/></plist>'
} > "$provenance_outside_plist"

ln -s "$provenance_outside_plist" "$provenance_product_plist"
assert_fails_with "product Info.plist must not be a symbolic link" \
  env MERIAN_PROJECT_ROOT="$tmp_dir" \
  TARGET_BUILD_DIR="$provenance_product_dir" \
  INFOPLIST_PATH="$provenance_relative_plist" \
  "$repo_root/scripts/embed-ios-build-provenance.sh"

rm -f "$provenance_product_plist"
ln "$provenance_outside_plist" "$provenance_product_plist"
assert_fails_with "product Info.plist must not have multiple hard links" \
  env MERIAN_PROJECT_ROOT="$tmp_dir" \
  TARGET_BUILD_DIR="$provenance_product_dir" \
  INFOPLIST_PATH="$provenance_relative_plist" \
  "$repo_root/scripts/embed-ios-build-provenance.sh"

rm -f "$provenance_product_plist"
cp "$provenance_outside_plist" "$provenance_product_plist"
assert_fails_with "PlistBuddy command must be an absolute path" \
  env MERIAN_PROJECT_ROOT="$tmp_dir" \
  MERIAN_PLISTBUDDY_COMMAND="fake-bin/PlistBuddy" \
  TARGET_BUILD_DIR="$provenance_product_dir" \
  INFOPLIST_PATH="$provenance_relative_plist" \
  "$repo_root/scripts/embed-ios-build-provenance.sh"
assert_succeeds_with "Embedded iOS build provenance" \
  env MERIAN_PROJECT_ROOT="$tmp_dir" \
  MERIAN_PLISTBUDDY_COMMAND="$tmp_dir/fake-bin/PlistBuddy" \
  TARGET_BUILD_DIR="$provenance_product_dir" \
  INFOPLIST_PATH="$provenance_relative_plist" \
  "$repo_root/scripts/embed-ios-build-provenance.sh"
assert_contains "MERIAN_SOURCE_REVISION" "$provenance_product_plist"
assert_contains "MERIAN_SOURCE_FINGERPRINT" "$provenance_product_plist"
assert_contains "MERIAN_SOURCE_STATE" "$provenance_product_plist"

if [[ -x /usr/libexec/PlistBuddy ]]; then
  real_provenance_dir="$tmp_dir/build/real-provenance-product"
  real_provenance_plist="$real_provenance_dir/$provenance_relative_plist"
  mkdir -p "$(dirname "$real_provenance_plist")"
  cp "$provenance_outside_plist" "$real_provenance_plist"
  assert_succeeds_with "Embedded iOS build provenance" \
    env MERIAN_PROJECT_ROOT="$tmp_dir" \
    TARGET_BUILD_DIR="$real_provenance_dir" \
    INFOPLIST_PATH="$provenance_relative_plist" \
    "$repo_root/scripts/embed-ios-build-provenance.sh"
  assert_contains "MERIAN_SOURCE_REVISION" "$real_provenance_plist"
  assert_contains "MERIAN_SOURCE_FINGERPRINT" "$real_provenance_plist"
  assert_contains "MERIAN_SOURCE_STATE" "$real_provenance_plist"
fi

ipa_fixture_root="$tmp_dir/build/ipa-fixtures"
fixture_ipa_revision="1111111111111111111111111111111111111111"
fixture_ipa_fingerprint="2222222222222222222222222222222222222222222222222222222222222222"
good_ipa="$ipa_fixture_root/good.ipa"
write_ipa_fixture \
  "$good_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint" \
  "clean"
assert_succeeds_with "Exported IPA metadata verified for app.merian.Merian 1.0.2 (236)" \
  run_exported_ipa_validator \
  "$good_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint"
good_ipa_sha256="$(shasum -a 256 -- "$good_ipa" | awk 'NR == 1 { print $1 }')"
assert_succeeds_with "^ipa_sha256=${good_ipa_sha256}$" \
  run_exported_ipa_validator \
  "$good_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint"

renumbered_ipa="$ipa_fixture_root/renumbered.ipa"
write_ipa_fixture \
  "$renumbered_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "272" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint" \
  "clean"
assert_fails_with "main app build 272 does not match expected build 236" \
  run_exported_ipa_validator \
  "$renumbered_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint"

assert_fails_with "main app source revision does not match the exported archive" \
  run_exported_ipa_validator \
  "$good_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "3333333333333333333333333333333333333333" \
  "$fixture_ipa_fingerprint"

dirty_ipa="$ipa_fixture_root/dirty.ipa"
write_ipa_fixture \
  "$dirty_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint" \
  "dirty"
assert_fails_with "main app source state is dirty; expected clean" \
  run_exported_ipa_validator \
  "$dirty_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint"

component_mismatch_ipa="$ipa_fixture_root/component-mismatch.ipa"
write_ipa_fixture \
  "$component_mismatch_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint" \
  "clean" \
  "235"
assert_fails_with "Fixture.appex/Info.plist build 235 does not match expected build 236" \
  run_exported_ipa_validator \
  "$component_mismatch_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint"

duplicate_root_ipa="$ipa_fixture_root/duplicate-root.ipa"
write_ipa_fixture \
  "$duplicate_root_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint" \
  "clean" \
  "236" \
  "duplicate-root"
assert_fails_with "IPA contains a duplicate archive entry" \
  run_exported_ipa_validator \
  "$duplicate_root_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint"

extra_root_ipa="$ipa_fixture_root/extra-root.ipa"
write_ipa_fixture \
  "$extra_root_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint" \
  "clean" \
  "236" \
  "extra-root"
assert_fails_with "IPA must contain exactly one root application Info.plist; found 2" \
  run_exported_ipa_validator \
  "$extra_root_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint"

missing_fingerprint_ipa="$ipa_fixture_root/missing-fingerprint.ipa"
write_ipa_fixture \
  "$missing_fingerprint_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint" \
  "clean" \
  "236" \
  "missing-fingerprint"
assert_fails_with "main-Info.plist is missing a readable MERIAN_SOURCE_FINGERPRINT" \
  run_exported_ipa_validator \
  "$missing_fingerprint_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.2" \
  "236" \
  "$fixture_ipa_revision" \
  "$fixture_ipa_fingerprint"

assert_fails_with "EXPORT_PATH must be a child of" \
  env MERIAN_PROJECT_ROOT="$tmp_dir" \
  MERIAN_PLISTBUDDY_COMMAND="$tmp_dir/fake-bin/PlistBuddy" \
  PROJECT_YML="$tmp_dir/project.yml" \
  IOS_EXPORT_SKIP_PREP_CHECK=1 \
  EXPORT_PATH="$tmp_dir/outside-export" \
  "$repo_root/scripts/export-ios-release.sh"
assert_fails_with "EXPORT_OPTIONS_PLIST must be inside EXPORT_PATH" \
  env MERIAN_PROJECT_ROOT="$tmp_dir" \
  MERIAN_PLISTBUDDY_COMMAND="$tmp_dir/fake-bin/PlistBuddy" \
  PROJECT_YML="$tmp_dir/project.yml" \
  IOS_EXPORT_SKIP_PREP_CHECK=1 \
  EXPORT_PATH="$tmp_dir/build/export" \
  EXPORT_OPTIONS_PLIST="$tmp_dir/outside.plist" \
  "$repo_root/scripts/export-ios-release.sh"
assert_fails_with "EXPORT_PATH must not contain . or .. path components" \
  env MERIAN_PROJECT_ROOT="$tmp_dir" \
  MERIAN_PLISTBUDDY_COMMAND="$tmp_dir/fake-bin/PlistBuddy" \
  PROJECT_YML="$tmp_dir/project.yml" \
  IOS_EXPORT_SKIP_PREP_CHECK=1 \
  EXPORT_PATH="$tmp_dir/build/missing/../../outside-export" \
  "$repo_root/scripts/export-ios-release.sh"
assert_fails_with "EXPORT_OPTIONS_PLIST must not contain . or .. path components" \
  env MERIAN_PROJECT_ROOT="$tmp_dir" \
  MERIAN_PLISTBUDDY_COMMAND="$tmp_dir/fake-bin/PlistBuddy" \
  PROJECT_YML="$tmp_dir/project.yml" \
  IOS_EXPORT_SKIP_PREP_CHECK=1 \
  EXPORT_PATH="$tmp_dir/build/export" \
  EXPORT_OPTIONS_PLIST="$tmp_dir/build/export/missing/../../outside-options.plist" \
  "$repo_root/scripts/export-ios-release.sh"

fake_export_bin="$tmp_dir/build/fake-export-bin"
fake_xcodebuild_log="$tmp_dir/build/fake-xcodebuild.log"
mkdir -p "$fake_export_bin"
{
  printf '#!/usr/bin/env bash\n'
  printf 'set -euo pipefail\n'
  printf 'export_path=""\n'
  printf 'printf "%%s\\n" "$@" > "${FAKE_XCODEBUILD_LOG:?}"\n'
  printf 'while (( $# > 0 )); do\n'
  printf '  case "$1" in\n'
  printf '    -exportPath)\n'
  printf '      export_path="$2"\n'
  printf '      shift 2\n'
  printf '      ;;\n'
  printf '    *)\n'
  printf '      shift\n'
  printf '      ;;\n'
  printf '  esac\n'
  printf 'done\n'
  printf '[[ -n "$export_path" ]]\n'
  printf 'mkdir -p "$export_path"\n'
  printf 'cp "${FAKE_IPA_SOURCE:?}" "$export_path/Merian.ipa"\n'
  printf 'printf "Fake App Store Connect export completed.\\n"\n'
} > "$fake_export_bin/xcodebuild"
chmod +x "$fake_export_bin/xcodebuild"

fixture_export_revision="$(git -C "$tmp_dir" rev-parse HEAD)"
fixture_export_fingerprint="$(
  MERIAN_PROJECT_ROOT="$tmp_dir" \
    "$repo_root/scripts/ios-release-source-fingerprint.sh"
)"
fixture_archive="$tmp_dir/build/Merian.xcarchive"
write_export_archive_fixture \
  "$fixture_archive" \
  "1.0.0" \
  "39" \
  "$fixture_export_revision" \
  "$fixture_export_fingerprint"

valid_export_source_ipa="$tmp_dir/build/valid-export-source.ipa"
write_ipa_fixture \
  "$valid_export_source_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.0" \
  "39" \
  "$fixture_export_revision" \
  "$fixture_export_fingerprint" \
  "clean"

run_export_fixture() {
  local ipa_source="$1"

  env \
    PATH="$fake_export_bin:$PATH" \
    FAKE_IPA_SOURCE="$ipa_source" \
    FAKE_XCODEBUILD_LOG="$fake_xcodebuild_log" \
    MERIAN_PLISTBUDDY_COMMAND="$tmp_dir/fake-bin/PlistBuddy" \
    MERIAN_UNZIP_COMMAND="$(command -v unzip)" \
    MERIAN_PROJECT_ROOT="$tmp_dir" \
    PROJECT_YML="$tmp_dir/project.yml" \
    IOS_EXPORT_SKIP_PREP_CHECK=1 \
    ARCHIVE_PATH="$fixture_archive" \
    EXPORT_PATH="$tmp_dir/build/export-integration" \
    "$repo_root/scripts/export-ios-release.sh"
}

assert_succeeds_with "Exported TestFlight-ready IPA" \
  run_export_fixture "$valid_export_source_ipa"
assert_contains "manageAppVersionAndBuildNumber" \
  "$tmp_dir/build/export-integration/exportOptions.plist"
managed_build_value="$(
  "$tmp_dir/fake-bin/PlistBuddy" \
    -c "Print :manageAppVersionAndBuildNumber" \
    "$tmp_dir/build/export-integration/exportOptions.plist"
)"
[[ "$managed_build_value" == "False" ]] \
  || fail "App Store Connect export must set manageAppVersionAndBuildNumber=false"
assert_contains "-exportArchive" "$fake_xcodebuild_log"

renumbered_export_source_ipa="$tmp_dir/build/renumbered-export-source.ipa"
write_ipa_fixture \
  "$renumbered_export_source_ipa" \
  "Merian.app" \
  "app.merian.Merian" \
  "1.0.0" \
  "272" \
  "$fixture_export_revision" \
  "$fixture_export_fingerprint" \
  "clean"
assert_fails_with "main app build 272 does not match expected build 39" \
  run_export_fixture "$renumbered_export_source_ipa"

assert_fails_with "xcodegen 2.45.4 is required for reproducible release generation; found 9.9.9" \
  env VERSION=1.2.3 BUILD=40 \
  PROJECT_YML="$tmp_dir/project.yml" \
  MERIAN_PROJECT_ROOT="$tmp_dir" \
  XCODEGEN_COMMAND="$tmp_dir/fake-bin/xcodegen" \
  "$repo_root/scripts/prepare-ios-release.sh"
assert_contains "MARKETING_VERSION: 1.0.0" "$tmp_dir/project.yml"
assert_contains "CURRENT_PROJECT_VERSION: 39" "$tmp_dir/project.yml"

asc_private_key="$tmp_dir/build/asc-private-key.p8"
asc_response="$tmp_dir/build/asc-response.json"
asc_curl_log="$tmp_dir/build/asc-curl.log"
mkdir -p "$tmp_dir/build"
openssl ecparam -name prime256v1 -genkey -noout -out "$asc_private_key" 2>/dev/null

run_prepare_with_fake_asc() {
  local http_code="${1:-200}"
  local curl_status="${2:-0}"

  env \
    FAKE_ASC_RESPONSE="$asc_response" \
    FAKE_ASC_CURL_LOG="$asc_curl_log" \
    FAKE_ASC_HTTP_CODE="$http_code" \
    FAKE_ASC_CURL_STATUS="$curl_status" \
    PATH="$tmp_dir/fake-bin:$PATH" \
    VERSION=1.2.3 \
    REVENUECAT_API_KEY="$valid_revenuecat_key" \
    PROJECT_YML="$tmp_dir/project.yml" \
    PROJECT_FILE="$tmp_dir/Merian.xcodeproj/project.pbxproj" \
    CONFIG_XCCONFIG="$tmp_dir/Config.xcconfig" \
    LOCAL_CONFIG_FILE="$tmp_dir/Config.local.xcconfig" \
    IOS_RELEASE_PREP_MARKER="$tmp_dir/build/ios-release-prep.json" \
    MERIAN_PROJECT_ROOT="$tmp_dir" \
    RUN_XCODEGEN=0 \
    ASC_APP_ID=1234567890 \
    ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 \
    ASC_KEY_ID=ABC123DEFG \
    ASC_PRIVATE_KEY_PATH="$asc_private_key" \
    "$repo_root/scripts/prepare-ios-release.sh"
}

printf '%s\n' \
  '{"data":[{"type":"builds","id":"fixture-build","attributes":{"version":"909"}}]}' \
  > "$asc_response"
write_project_yml "1.0.0" "39"
run_prepare_with_fake_asc >/dev/null
assert_contains "CURRENT_PROJECT_VERSION: 910" "$tmp_dir/project.yml"
assert_contains '--get' "$asc_curl_log"
assert_contains 'filter[app]=1234567890' "$asc_curl_log"
assert_contains 'limit=1' "$asc_curl_log"
assert_contains 'sort=-version' "$asc_curl_log"
assert_contains 'fields[builds]=version' "$asc_curl_log"
assert_contains '--connect-timeout' "$asc_curl_log"
assert_contains '--max-time' "$asc_curl_log"
assert_contains '--retry-all-errors' "$asc_curl_log"
assert_contains '--max-filesize' "$asc_curl_log"

printf '%s\n' '{"unexpected":"success-shape"}' > "$asc_response"
write_project_yml "1.0.0" "39"
assert_fails_with "App Store Connect returned a malformed build-list response" \
  run_prepare_with_fake_asc
assert_contains "CURRENT_PROJECT_VERSION: 39" "$tmp_dir/project.yml"

printf '%s\n' '{"errors":[{"status":"503"}]}' > "$asc_response"
write_project_yml "1.0.0" "39"
assert_fails_with "App Store Connect build lookup failed with HTTP 503" \
  run_prepare_with_fake_asc 503
assert_contains "CURRENT_PROJECT_VERSION: 39" "$tmp_dir/project.yml"

write_project_yml "1.0.0" "39"
assert_fails_with "App Store Connect build lookup transport failed (curl 28)" \
  run_prepare_with_fake_asc 200 28
assert_contains "CURRENT_PROJECT_VERSION: 39" "$tmp_dir/project.yml"

write_project_yml "1.0.0" "39"
VERSION=1.2.3 LATEST_ASC_BUILD=41 run_prepare >/dev/null
assert_contains "MARKETING_VERSION: 1.2.3" "$tmp_dir/project.yml"
assert_contains "CURRENT_PROJECT_VERSION: 42" "$tmp_dir/project.yml"
assert_contains '"build": 42' "$tmp_dir/build/ios-release-prep.json"
assert_contains '"anchor_build": 41' "$tmp_dir/build/ios-release-prep.json"
assert_contains '"source_fingerprint": "' "$tmp_dir/build/ios-release-prep.json"
assert_contains '"prepared_from_sha": "' "$tmp_dir/build/ios-release-prep.json"
assert_contains "REVENUECAT_API_KEY = $valid_revenuecat_key" "$tmp_dir/Config.local.xcconfig"

write_project_yml "1.0.0" "39"
VERSION=1.2.4 BUILD=50 run_prepare >/dev/null
assert_contains "MARKETING_VERSION: 1.2.4" "$tmp_dir/project.yml"
assert_contains "CURRENT_PROJECT_VERSION: 50" "$tmp_dir/project.yml"

write_project_yml "1.0.0" "39"
assert_fails env VERSION=1.2 LATEST_ASC_BUILD=41 PROJECT_YML="$tmp_dir/project.yml" RUN_XCODEGEN=0 "$repo_root/scripts/prepare-ios-release.sh"

write_project_yml "1.0.0" "39"
assert_fails env -u ASC_APP_ID -u ASC_ISSUER_ID -u ASC_KEY_ID -u ASC_PRIVATE_KEY_PATH VERSION=1.2.3 PROJECT_YML="$tmp_dir/project.yml" RUN_XCODEGEN=0 "$repo_root/scripts/prepare-ios-release.sh"

write_project_yml "1.0.0" "39"
assert_fails env VERSION=1.2.3 BUILD=39 PROJECT_YML="$tmp_dir/project.yml" RUN_XCODEGEN=0 "$repo_root/scripts/prepare-ios-release.sh"

write_project_yml "1.0.2" "39"
assert_fails_with "VERSION 1.0.1 must not be lower than repo version 1.0.2" \
  env VERSION=1.0.1 BUILD=40 PROJECT_YML="$tmp_dir/project.yml" RUN_XCODEGEN=0 "$repo_root/scripts/prepare-ios-release.sh"

write_project_yml "1.0.0" "39"
mv "$tmp_dir/source.swift" "$tmp_dir/renamed-source.swift"
printf 'let newlyAddedFixture = true\n' > "$tmp_dir/new-source.swift"
VERSION=1.2.5 LATEST_ASC_BUILD=41 run_prepare >/dev/null
commit_fixture_source
MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh" >/dev/null
CONFIGURATION=Release REVENUECAT_API_KEY="$valid_revenuecat_key" MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh" >/dev/null

local_marker="$tmp_dir/build/ios-release-prep.json"
local_marker_backup="$tmp_dir/build/ios-release-prep.local.json"
cp "$local_marker" "$local_marker_backup"
current_fixture_sha="$(git -C "$tmp_dir" rev-parse HEAD)"
current_fixture_tree="$(git -C "$tmp_dir" write-tree)"

set_marker_value build string "42" "$local_marker"
assert_fails_with "release prep marker has no integer build" \
  env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

cp "$local_marker_backup" "$local_marker"
remove_marker_key source_fingerprint "$local_marker"
assert_fails_with "predates release-source fingerprint binding" \
  env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

cp "$local_marker_backup" "$local_marker"
set_marker_value source_fingerprint bool false "$local_marker"
assert_fails_with "must be a JSON string" \
  env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

cp "$local_marker_backup" "$local_marker"
set_marker_value ci_validation_only string "true" "$local_marker"
assert_fails_with "release prep marker has a malformed ci_validation_only flag" \
  env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

printf '[]\n' > "$local_marker"
assert_fails_with "release prep marker is not a valid JSON object" \
  env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

cp "$local_marker_backup" "$local_marker"
unrelated_fixture_sha="$(
  printf 'unrelated preparation base\n' \
    | git -C "$tmp_dir" commit-tree "$current_fixture_tree"
)"
set_marker_value prepared_from_sha string "$unrelated_fixture_sha" "$local_marker"
assert_fails_with "does not descend from preparation base" \
  env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

cp "$local_marker_backup" "$local_marker"
set_marker_value prepared_from_sha string "not-a-revision" "$local_marker"
assert_fails_with "local release marker has no valid preparation-base revision" \
  env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

cp "$local_marker_backup" "$local_marker"
remove_marker_key prepared_from_sha "$local_marker"
set_marker_value source_sha string "$current_fixture_sha" "$local_marker"
set_marker_value ci_validation_only bool true "$local_marker"
MERIAN_FORCE_RELEASE_PREP_CHECK=1 \
  MERIAN_PROJECT_ROOT="$tmp_dir" \
  "$repo_root/scripts/check-ios-release-prep.sh" \
  >/dev/null

set_marker_value \
  source_sha \
  string \
  "0000000000000000000000000000000000000000" \
  "$local_marker"
assert_fails_with "CI release marker source" \
  env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

set_marker_value source_sha string "not-a-revision" "$local_marker"
assert_fails_with "CI validation marker has no valid exact source revision" \
  env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

cp "$local_marker_backup" "$local_marker"
assert_succeeds_with "warning: Release archive is using non-production RevenueCat config: REVENUECAT_API_KEY is a RevenueCat Test Store key" \
  env CONFIGURATION=Release REVENUECAT_API_KEY=test_store_key MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"
assert_succeeds_with "warning: Release archive is using non-production RevenueCat config: REVENUECAT_API_KEY should be a RevenueCat iOS production key" \
  env CONFIGURATION=Release REVENUECAT_API_KEY=rc_unknown_key MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"
assert_fails_with "error: Release archive blocked: REVENUECAT_API_KEY is a RevenueCat Test Store key" \
  env CONFIGURATION=Release REVENUECAT_API_KEY=test_store_key MERIAN_REQUIRE_PRODUCTION_REVENUECAT_KEY=1 MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

printf 'let changedFixture = true\n' >> "$tmp_dir/source.swift"
assert_fails_with "source checkout is dirty" \
  env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"
commit_fixture_source
assert_fails_with "tracked source changed after release prep" \
  env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

rm -f "$tmp_dir/Config.local.xcconfig"
printf 'REVENUECAT_API_KEY = test_store_key\n' > "$tmp_dir/Config.xcconfig"
assert_succeeds_with "warning: Release REVENUECAT_API_KEY resolves to a RevenueCat Test Store key" \
  env VERSION=1.2.6 BUILD=44 MERIAN_PROJECT_ROOT="$tmp_dir" PROJECT_YML="$tmp_dir/project.yml" PROJECT_FILE="$tmp_dir/Merian.xcodeproj/project.pbxproj" CONFIG_XCCONFIG="$tmp_dir/Config.xcconfig" LOCAL_CONFIG_FILE="$tmp_dir/Config.local.xcconfig" IOS_RELEASE_PREP_MARKER="$tmp_dir/build/ios-release-prep.json" RUN_XCODEGEN=0 "$repo_root/scripts/prepare-ios-release.sh"
assert_fails_with "Release REVENUECAT_API_KEY resolves to a RevenueCat Test Store key" \
  env VERSION=1.2.7 BUILD=45 MERIAN_REQUIRE_PRODUCTION_REVENUECAT_KEY=1 MERIAN_PROJECT_ROOT="$tmp_dir" PROJECT_YML="$tmp_dir/project.yml" PROJECT_FILE="$tmp_dir/Merian.xcodeproj/project.pbxproj" CONFIG_XCCONFIG="$tmp_dir/Config.xcconfig" LOCAL_CONFIG_FILE="$tmp_dir/Config.local.xcconfig" IOS_RELEASE_PREP_MARKER="$tmp_dir/build/ios-release-prep.json" RUN_XCODEGEN=0 "$repo_root/scripts/prepare-ios-release.sh"
assert_fails_with "Release REVENUECAT_API_KEY from REVENUECAT_API_KEY must be a RevenueCat iOS production key" \
  env VERSION=1.2.6 BUILD=45 REVENUECAT_API_KEY=rc_unknown_key MERIAN_PROJECT_ROOT="$tmp_dir" PROJECT_YML="$tmp_dir/project.yml" PROJECT_FILE="$tmp_dir/Merian.xcodeproj/project.pbxproj" CONFIG_XCCONFIG="$tmp_dir/Config.xcconfig" LOCAL_CONFIG_FILE="$tmp_dir/Config.local.xcconfig" IOS_RELEASE_PREP_MARKER="$tmp_dir/build/ios-release-prep.json" RUN_XCODEGEN=0 "$repo_root/scripts/prepare-ios-release.sh"
assert_fails_with "Release REVENUECAT_API_KEY from REVENUECAT_API_KEY is still a placeholder" \
  env VERSION=1.2.6 BUILD=45 REVENUECAT_API_KEY=appl_... MERIAN_PROJECT_ROOT="$tmp_dir" PROJECT_YML="$tmp_dir/project.yml" PROJECT_FILE="$tmp_dir/Merian.xcodeproj/project.pbxproj" CONFIG_XCCONFIG="$tmp_dir/Config.xcconfig" LOCAL_CONFIG_FILE="$tmp_dir/Config.local.xcconfig" IOS_RELEASE_PREP_MARKER="$tmp_dir/build/ios-release-prep.json" RUN_XCODEGEN=0 "$repo_root/scripts/prepare-ios-release.sh"

write_project_yml "1.2.5" "43"
assert_fails env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

rm -f "$tmp_dir/build/ios-release-prep.json"
assert_fails_with "error: Release archive blocked: missing release prep marker" \
  env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

echo "iOS versioning script tests passed."
