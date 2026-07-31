#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-versioning-tests.XXXXXX")"
fixture_repo="$test_root/repository"
fixture_remote="$test_root/remote.git"
tool_bin="$test_root/tools"
trap 'rm -rf "$test_root"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_fails_with() {
  local expected="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    fail "expected command to fail: $*"
  fi
  grep -q -- "$expected" <<<"$output" \
    || fail "expected failure to contain '$expected'; actual: $output"
}

assert_succeeds_with() {
  local expected="$1"
  shift
  local output
  if ! output="$("$@" 2>&1)"; then
    fail "expected command to succeed: $*; actual: $output"
  fi
  grep -q -- "$expected" <<<"$output" \
    || fail "expected success to contain '$expected'; actual: $output"
}

json_value() {
  local path="$1"
  local expression="$2"
  ruby -rjson -e 'document = JSON.parse(File.binread(ARGV[0])); value = eval("document" + ARGV[1]); puts value' "$path" "$expression"
}

write_project_yml() {
  local version="$1"
  local build="$2"
  printf '%s\n' \
    'name: Merian' \
    'settings:' \
    '  base:' \
    '    CODE_SIGN_STYLE: Automatic' \
    "    MARKETING_VERSION: $version" \
    "    CURRENT_PROJECT_VERSION: $build" \
    '    VERSIONING_SYSTEM: apple-generic' > "$fixture_repo/project.yml"
}

commit_fixture() {
  git -C "$fixture_repo" add -A
  git -C "$fixture_repo" commit --allow-empty -q -m "fixture state"
}

write_ipa_fixture() {
  local ipa_path="$1"
  local version="$2"
  local build="$3"
  local revision="$4"
  local fingerprint="$5"
  local source_state="${6:-clean}"
  local component_build="${7:-$build}"
  local topology="${8:-normal}"

  mkdir -p "$(dirname "$ipa_path")"
  python3 - "$ipa_path" "$version" "$build" "$revision" "$fingerprint" "$source_state" "$component_build" "$topology" <<'PYTHON'
import plistlib
import sys
import warnings
import zipfile

ipa_path, version, build, revision, fingerprint, source_state, component_build, topology = sys.argv[1:]
root = {
    "CFBundleIdentifier": "app.merian.Merian",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": build,
    "MERIAN_SOURCE_REVISION": revision,
    "MERIAN_SOURCE_FINGERPRINT": fingerprint,
    "MERIAN_SOURCE_STATE": source_state,
}
component = {
    "CFBundleIdentifier": "app.merian.Merian.fixture",
    "CFBundlePackageType": "XPC!",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": component_build,
}
watch = dict(component)
watch["CFBundlePackageType"] = "APPL"
root_entry = "Payload/Merian.app/Info.plist"
warnings.simplefilter("ignore", UserWarning)
with zipfile.ZipFile(ipa_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    archive.writestr(root_entry, plistlib.dumps(root))
    archive.writestr("Payload/Merian.app/PlugIns/MerianExploreWidget.appex/Info.plist", plistlib.dumps(component))
    archive.writestr("Payload/Merian.app/PlugIns/MerianMessagesExtension.appex/Info.plist", plistlib.dumps(component))
    if topology != "missing-watch":
        archive.writestr("Payload/Merian.app/Watch/MerianWatch.app/Info.plist", plistlib.dumps(watch))
    if topology == "duplicate-root":
        archive.writestr(root_entry, plistlib.dumps(root))
    elif topology == "extra-root":
        archive.writestr("Payload/Other.app/Info.plist", plistlib.dumps(root))
PYTHON
}

write_archive_fixture() {
  local archive_path="$1"
  local version="$2"
  local build="$3"
  local revision="$4"
  local fingerprint="$5"
  local component_build="${6:-$build}"

  local app_path="$archive_path/Products/Applications/Merian.app"
  mkdir -p \
    "$app_path/PlugIns/MerianExploreWidget.appex" \
    "$app_path/PlugIns/MerianMessagesExtension.appex" \
    "$app_path/Watch/MerianWatch.app"
  python3 - "$archive_path/Info.plist" "$app_path" "$version" "$build" "$revision" "$fingerprint" "$component_build" <<'PYTHON'
import os
import plistlib
import sys

archive_info_path, app_path, version, build, revision, fingerprint, component_build = sys.argv[1:]
archive_info = {
    "ApplicationProperties": {
        "ApplicationPath": "Applications/Merian.app",
        "Team": "TA8S64ST9W",
    }
}
main = {
    "CFBundleIdentifier": "app.merian.Merian",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": build,
    "MERIAN_SOURCE_REVISION": revision,
    "MERIAN_SOURCE_FINGERPRINT": fingerprint,
    "MERIAN_SOURCE_STATE": "clean",
}
extension = {
    "CFBundleIdentifier": "app.merian.Merian.fixture",
    "CFBundlePackageType": "XPC!",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": component_build,
}
watch = dict(extension)
watch["CFBundlePackageType"] = "APPL"
documents = {
    archive_info_path: archive_info,
    os.path.join(app_path, "Info.plist"): main,
    os.path.join(app_path, "PlugIns/MerianExploreWidget.appex/Info.plist"): extension,
    os.path.join(app_path, "PlugIns/MerianMessagesExtension.appex/Info.plist"): extension,
    os.path.join(app_path, "Watch/MerianWatch.app/Info.plist"): watch,
}
for path, document in documents.items():
    with open(path, "wb") as handle:
        plistlib.dump(document, handle)
with open(os.path.join(app_path, "Merian"), "wb") as handle:
    handle.write(b"fixture executable\n")
PYTHON
}

run_ipa_validator() {
  MERIAN_PLISTBUDDY_COMMAND="$tool_bin/PlistBuddy" \
  MERIAN_UNZIP_COMMAND="$(command -v unzip)" \
  MERIAN_SHASUM_COMMAND="$(command -v shasum)" \
    bash "$repo_root/scripts/validate-ios-exported-ipa.sh" "$@"
}

mkdir -p "$fixture_repo/scripts" "$fixture_repo/Merian.xcodeproj" "$tool_bin"
git -C "$fixture_repo" init -q
git -C "$fixture_repo" config user.name "Merian Release Tests"
git -C "$fixture_repo" config user.email "release-tests@example.invalid"
printf '%s\n' 'build/' 'Config.local.xcconfig' 'xcuserdata/' > "$fixture_repo/.gitignore"
printf '%s\n' 'let fixtureSource = true' > "$fixture_repo/source.swift"
printf '%s\n' '// generated project fixture' > "$fixture_repo/Merian.xcodeproj/project.pbxproj"
cp "$repo_root/scripts/ios-release-source-fingerprint.sh" "$fixture_repo/scripts/ios-release-source-fingerprint.sh"
write_project_yml "1.0.3" "39"
commit_fixture
git init --bare -q "$fixture_remote"
git -C "$fixture_repo" remote add origin "$fixture_remote"
git -C "$fixture_repo" push -q origin HEAD:refs/heads/main

cat > "$tool_bin/PlistBuddy" <<'PYTHON'
#!/usr/bin/env python3
import plistlib
import shlex
import sys

if len(sys.argv) != 4 or sys.argv[1] != "-c":
    sys.exit(2)
command = shlex.split(sys.argv[2])
path = sys.argv[3]
with open(path, "rb") as handle:
    document = plistlib.load(handle)
operation = command[0] if command else ""
keys = command[1].lstrip(":").split(":") if len(command) > 1 else []
container = document
for key in keys[:-1]:
    if not isinstance(container, dict) or key not in container:
        sys.exit(1)
    container = container[key]
key = keys[-1] if keys else ""
if operation == "Print" and len(command) == 2:
    if not isinstance(container, dict) or key not in container:
        sys.exit(1)
    print(container[key])
    sys.exit(0)
if operation == "Set" and len(command) >= 3:
    if not isinstance(container, dict) or key not in container:
        sys.exit(1)
    value = " ".join(command[2:])
elif operation == "Add" and len(command) >= 4 and command[2] == "string":
    if not isinstance(container, dict) or key in container:
        sys.exit(1)
    value = " ".join(command[3:])
else:
    sys.exit(2)
container[key] = value
with open(path, "wb") as handle:
    plistlib.dump(document, handle, fmt=plistlib.FMT_XML, sort_keys=True)
PYTHON
chmod +x "$tool_bin/PlistBuddy"

cat > "$tool_bin/xcodegen" <<'SHELL'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  printf '%s\n' 'Version: 2.45.4'
  exit 0
fi
exit 99
SHELL
chmod +x "$tool_bin/xcodegen"

for script in \
  publish-ios-beta.sh \
  check-ios-release-prep.sh \
  export-ios-release.sh \
  validate-ios-archive.sh \
  validate-ios-exported-ipa.sh \
  hash-ios-archive.sh \
  ios-release-source-fingerprint.sh \
  embed-ios-build-provenance.sh; do
  bash -n "$repo_root/scripts/$script"
done

# Fingerprinting rejects hidden index state and tracked Xcode user data.
git -C "$fixture_repo" update-index --assume-unchanged source.swift
assert_fails_with "tracked source uses assume-unchanged or skip-worktree index state" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" bash "$repo_root/scripts/ios-release-source-fingerprint.sh"
git -C "$fixture_repo" update-index --no-assume-unchanged source.swift
git -C "$fixture_repo" update-index --skip-worktree source.swift
assert_fails_with "tracked source uses assume-unchanged or skip-worktree index state" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" bash "$repo_root/scripts/ios-release-source-fingerprint.sh"
git -C "$fixture_repo" update-index --no-skip-worktree source.swift

tracked_user_state="$fixture_repo/Merian.xcodeproj/xcuserdata/test.xcuserdatad/xcschemes/state.plist"
mkdir -p "$(dirname "$tracked_user_state")"
printf '%s\n' '<plist/>' > "$tracked_user_state"
git -C "$fixture_repo" add -f "$tracked_user_state"
commit_fixture
assert_fails_with "tracked Xcode user state is nondeterministic release source" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" bash "$repo_root/scripts/ios-release-source-fingerprint.sh"
git -C "$fixture_repo" rm -q "$tracked_user_state"
commit_fixture

fixture_revision="$(git -C "$fixture_repo" rev-parse HEAD)"
fixture_fingerprint="$(MERIAN_PROJECT_ROOT="$fixture_repo" bash "$repo_root/scripts/ios-release-source-fingerprint.sh")"

# Product provenance refuses path escapes and link redirection, then embeds the
# exact clean source identity in an ordinary processed product plist.
product_dir="$fixture_repo/build/product"
product_plist="$product_dir/Merian.app/Info.plist"
outside_plist="$fixture_repo/build/outside.plist"
mkdir -p "$(dirname "$product_plist")"
python3 - "$outside_plist" <<'PYTHON'
import plistlib
import sys
with open(sys.argv[1], "wb") as handle:
    plistlib.dump({}, handle)
PYTHON
assert_fails_with "INFOPLIST_PATH contains a traversal component" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" TARGET_BUILD_DIR="$product_dir" INFOPLIST_PATH="../outside.plist" \
  bash "$repo_root/scripts/embed-ios-build-provenance.sh"
ln -s "$outside_plist" "$product_plist"
assert_fails_with "product Info.plist must not be a symbolic link" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" TARGET_BUILD_DIR="$product_dir" INFOPLIST_PATH="Merian.app/Info.plist" \
  bash "$repo_root/scripts/embed-ios-build-provenance.sh"
rm -f "$product_plist"
ln "$outside_plist" "$product_plist"
assert_fails_with "product Info.plist must not have multiple hard links" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" TARGET_BUILD_DIR="$product_dir" INFOPLIST_PATH="Merian.app/Info.plist" \
  bash "$repo_root/scripts/embed-ios-build-provenance.sh"
rm -f "$product_plist"
cp "$outside_plist" "$product_plist"
assert_succeeds_with "Embedded iOS build provenance" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_PLISTBUDDY_COMMAND="$tool_bin/PlistBuddy" \
  TARGET_BUILD_DIR="$product_dir" INFOPLIST_PATH="Merian.app/Info.plist" \
  bash "$repo_root/scripts/embed-ios-build-provenance.sh"
assert_contains "MERIAN_SOURCE_REVISION" "$product_plist"
assert_contains "MERIAN_SOURCE_FINGERPRINT" "$product_plist"
assert_contains "MERIAN_SOURCE_STATE" "$product_plist"

# IPA verification covers the app and every shipped embedded component.
ipa_root="$fixture_repo/build/ipa-fixtures"
good_ipa="$ipa_root/good.ipa"
write_ipa_fixture "$good_ipa" "1.0.3" "40" "$fixture_revision" "$fixture_fingerprint"
assert_succeeds_with "Exported IPA metadata verified for app.merian.Merian 1.0.3 (40)" \
  run_ipa_validator "$good_ipa" Merian.app app.merian.Merian 1.0.3 40 "$fixture_revision" "$fixture_fingerprint"
good_sha="$(shasum -a 256 -- "$good_ipa" | awk '{ print $1 }')"
assert_succeeds_with "^ipa_sha256=${good_sha}$" \
  run_ipa_validator "$good_ipa" Merian.app app.merian.Merian 1.0.3 40 "$fixture_revision" "$fixture_fingerprint"

renumbered_ipa="$ipa_root/renumbered.ipa"
write_ipa_fixture "$renumbered_ipa" "1.0.3" "272" "$fixture_revision" "$fixture_fingerprint"
assert_fails_with "main app build 272 does not match expected build 40" \
  run_ipa_validator "$renumbered_ipa" Merian.app app.merian.Merian 1.0.3 40 "$fixture_revision" "$fixture_fingerprint"
component_mismatch_ipa="$ipa_root/component-mismatch.ipa"
write_ipa_fixture "$component_mismatch_ipa" "1.0.3" "40" "$fixture_revision" "$fixture_fingerprint" clean 39
assert_fails_with "MerianExploreWidget.appex/Info.plist build 39 does not match expected build 40" \
  run_ipa_validator "$component_mismatch_ipa" Merian.app app.merian.Merian 1.0.3 40 "$fixture_revision" "$fixture_fingerprint"
dirty_ipa="$ipa_root/dirty.ipa"
write_ipa_fixture "$dirty_ipa" "1.0.3" "40" "$fixture_revision" "$fixture_fingerprint" dirty
assert_fails_with "main app source state is dirty; expected clean" \
  run_ipa_validator "$dirty_ipa" Merian.app app.merian.Merian 1.0.3 40 "$fixture_revision" "$fixture_fingerprint"
duplicate_ipa="$ipa_root/duplicate.ipa"
write_ipa_fixture "$duplicate_ipa" "1.0.3" "40" "$fixture_revision" "$fixture_fingerprint" clean 40 duplicate-root
assert_fails_with "IPA contains a duplicate archive entry" \
  run_ipa_validator "$duplicate_ipa" Merian.app app.merian.Merian 1.0.3 40 "$fixture_revision" "$fixture_fingerprint"
missing_watch_ipa="$ipa_root/missing-watch.ipa"
write_ipa_fixture "$missing_watch_ipa" "1.0.3" "40" "$fixture_revision" "$fixture_fingerprint" clean 40 missing-watch
assert_fails_with "IPA is missing required embedded component: .*MerianWatch.app/Info.plist" \
  run_ipa_validator "$missing_watch_ipa" Merian.app app.merian.Merian 1.0.3 40 "$fixture_revision" "$fixture_fingerprint"

# Archive verification has the same all-target identity contract and a stable
# content identity that changes with any archive byte.
archive_fixture="$fixture_repo/build/archive-fixture.xcarchive"
write_archive_fixture "$archive_fixture" "1.0.3" "40" "$fixture_revision" "$fixture_fingerprint"
archive_output="$(MERIAN_PLISTBUDDY_COMMAND="$tool_bin/PlistBuddy" bash "$repo_root/scripts/validate-ios-archive.sh" "$archive_fixture" app.merian.Merian 1.0.3 40 "$fixture_revision" "$fixture_fingerprint")"
archive_identity="$(awk -F= '$1 == "archive_identity" { print $2 }' <<<"$archive_output")"
[[ "$archive_identity" =~ ^[0-9a-f]{64}$ ]] || fail "archive validation returned no identity"
printf '%s\n' 'mutation' >> "$archive_fixture/Products/Applications/Merian.app/Merian"
mutated_identity="$(bash "$repo_root/scripts/hash-ios-archive.sh" "$archive_fixture")"
[[ "$mutated_identity" != "$archive_identity" ]] || fail "archive identity ignored a content change"
bad_archive="$fixture_repo/build/bad-component.xcarchive"
write_archive_fixture "$bad_archive" "1.0.3" "40" "$fixture_revision" "$fixture_fingerprint" 39
assert_fails_with "Explore widget build 39 does not match 40" \
  env MERIAN_PLISTBUDDY_COMMAND="$tool_bin/PlistBuddy" \
  bash "$repo_root/scripts/validate-ios-archive.sh" "$bad_archive" app.merian.Merian 1.0.3 40 "$fixture_revision" "$fixture_fingerprint"

# Release preflight has disjoint validation and serialized publisher modes.
assert_succeeds_with "no build number was allocated" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_FORCE_RELEASE_PREP_CHECK=1 \
  MERIAN_IOS_VALIDATION_ARCHIVE=1 MERIAN_EXPECTED_SOURCE_REVISION="$fixture_revision" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' \
  MARKETING_VERSION=1.0.3 CURRENT_PROJECT_VERSION=39 \
  bash "$repo_root/scripts/check-ios-release-prep.sh"
assert_fails_with "validation archive changed or allocated CURRENT_PROJECT_VERSION" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_FORCE_RELEASE_PREP_CHECK=1 \
  MERIAN_IOS_VALIDATION_ARCHIVE=1 MERIAN_EXPECTED_SOURCE_REVISION="$fixture_revision" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' \
  MARKETING_VERSION=1.0.3 CURRENT_PROJECT_VERSION=40 \
  bash "$repo_root/scripts/check-ios-release-prep.sh"
assert_fails_with "validation archive mode is restricted to unsigned archives" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_FORCE_RELEASE_PREP_CHECK=1 \
  MERIAN_IOS_VALIDATION_ARCHIVE=1 MERIAN_EXPECTED_SOURCE_REVISION="$fixture_revision" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES MARKETING_VERSION=1.0.3 CURRENT_PROJECT_VERSION=39 \
  bash "$repo_root/scripts/check-ios-release-prep.sh"
assert_fails_with "manual Organizer and ad-hoc xcodebuild archives are unsupported" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_FORCE_RELEASE_PREP_CHECK=1 \
  MERIAN_EXPECTED_SOURCE_REVISION="$fixture_revision" \
  bash "$repo_root/scripts/check-ios-release-prep.sh"
assert_succeeds_with "Serialized publisher Release archive authorized" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_FORCE_RELEASE_PREP_CHECK=1 \
  MERIAN_RELEASE_PUBLISHER=1 MERIAN_PUBLISHER_SERIALIZED=1 \
  MERIAN_EXPECTED_MARKETING_VERSION=1.0.3 MERIAN_EXPECTED_BUILD_NUMBER=40 \
  MERIAN_EXPECTED_SOURCE_REVISION="$fixture_revision" MERIAN_EXPECTED_SOURCE_FINGERPRINT="$fixture_fingerprint" \
  MARKETING_VERSION=1.0.3 CURRENT_PROJECT_VERSION=40 REVENUECAT_API_KEY=appl_fixtureproductionkey \
  bash "$repo_root/scripts/check-ios-release-prep.sh"
assert_fails_with "allocated build 39 is not higher than tracked baseline 39" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_FORCE_RELEASE_PREP_CHECK=1 \
  MERIAN_RELEASE_PUBLISHER=1 MERIAN_PUBLISHER_SERIALIZED=1 \
  MERIAN_EXPECTED_MARKETING_VERSION=1.0.3 MERIAN_EXPECTED_BUILD_NUMBER=39 \
  MERIAN_EXPECTED_SOURCE_REVISION="$fixture_revision" MERIAN_EXPECTED_SOURCE_FINGERPRINT="$fixture_fingerprint" \
  MARKETING_VERSION=1.0.3 CURRENT_PROJECT_VERSION=39 REVENUECAT_API_KEY=appl_fixtureproductionkey \
  bash "$repo_root/scripts/check-ios-release-prep.sh"

# Dry-run allocation uses both tracked and durable repository baselines without
# reserving a tag or modifying project.yml.
git -C "$fixture_repo" tag ios-build-allocations/44 "$fixture_revision"
remote_main_revision="$(git --git-dir="$fixture_remote" rev-parse refs/heads/main)"
git --git-dir="$fixture_remote" update-ref refs/tags/ios-build-allocations/nested/46 "$remote_main_revision"
assert_fails_with "remote contains a malformed iOS allocation tag" \
  env LATEST_ASC_BUILD=41 PUBLISHER_PLAN_PATH="$fixture_repo/build/malformed-remote-tag-plan.json" \
  MERIAN_PROJECT_ROOT="$fixture_repo" \
  bash "$repo_root/scripts/publish-ios-beta.sh" --dry-run
git --git-dir="$fixture_remote" update-ref -d refs/tags/ios-build-allocations/nested/46
project_before="$(shasum -a 256 "$fixture_repo/project.yml" | awk '{ print $1 }')"
plan_path="$fixture_repo/build/plan-45.json"
LATEST_ASC_BUILD=41 \
PUBLISHER_PLAN_PATH="$plan_path" \
MERIAN_PROJECT_ROOT="$fixture_repo" \
  bash "$repo_root/scripts/publish-ios-beta.sh" --dry-run >/dev/null
[[ "$(json_value "$plan_path" '["build"]')" == "45" ]] || fail "dry run did not use allocation tag baseline"
[[ "$(json_value "$plan_path" '["allocation"]["repository_baseline"]')" == "44" ]] || fail "repository baseline is wrong"
[[ "$(json_value "$plan_path" '["export"]["manageAppVersionAndBuildNumber"]')" == "false" ]] || fail "plan enabled Xcode renumbering"
[[ "$(json_value "$plan_path" '["upload"]["planned"]')" == "true" ]] || fail "dry run did not demonstrate the allocation-to-upload path"
[[ "$(json_value "$plan_path" '["upload"]["authorized"]')" == "false" ]] || fail "dry run authorized an upload"
[[ "$(json_value "$plan_path" '["upload"]["will_execute"]')" == "false" ]] || fail "dry run would execute an upload"
[[ "$(json_value "$plan_path" '["upload"]["rebuild"]')" == "false" ]] || fail "dry run planned a promotion rebuild"
[[ "$(json_value "$plan_path" '["upload"]["promotion_policy"]')" == *"internal TestFlight, external TestFlight, and App Review"* ]] \
  || fail "dry run lost the same-binary promotion policy"
git -C "$fixture_repo" show-ref --verify --quiet refs/tags/ios-build-allocations/45 \
  && fail "dry run reserved a build"
project_after="$(shasum -a 256 "$fixture_repo/project.yml" | awk '{ print $1 }')"
[[ "$project_before" == "$project_after" ]] || fail "dry run edited tracked version settings"
assert_fails_with "publisher plan does not authorize this exact export" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_RELEASE_PUBLISHER=1 MERIAN_PUBLISHER_SERIALIZED=1 \
  IOS_PUBLISHER_PLAN="$plan_path" ARCHIVE_PATH="$archive_fixture" \
  EXPORT_PATH="$fixture_repo/build/dry-run-plan-export" TEAM_ID=TA8S64ST9W \
  MERIAN_EXPECTED_MARKETING_VERSION=1.0.3 MERIAN_EXPECTED_BUILD_NUMBER=45 \
  MERIAN_EXPECTED_SOURCE_REVISION="$fixture_revision" MERIAN_EXPECTED_SOURCE_FINGERPRINT="$fixture_fingerprint" \
  XCODEBUILD_COMMAND="$tool_bin/xcodebuild" MERIAN_PLISTBUDDY_COMMAND="$tool_bin/PlistBuddy" \
  bash "$repo_root/scripts/export-ios-release.sh"
git -C "$fixture_repo" tag -d ios-build-allocations/44 >/dev/null

assert_fails_with "prepare-ios-release is retired" bash "$repo_root/scripts/prepare-ios-release.sh"
assert_contains "CURRENT_PROJECT_VERSION: 39" "$fixture_repo/project.yml"

# API allocation fails closed on malformed payloads and uses the global sorted
# app build endpoint in read-only plan mode.
mkdir -p "$test_root/secrets"
asc_key="$test_root/secrets/AuthKey_FIXTURE123.p8"
openssl ecparam -name prime256v1 -genkey -noout -out "$asc_key" 2>/dev/null
asc_response="$test_root/asc-response.json"
asc_log="$test_root/asc-curl.log"
asc_header_log="$test_root/asc-header.log"
asc_tmp="$test_root/asc-tmp"
mkdir "$asc_tmp"
printf '%s\n' '{"data":[{"type":"builds","attributes":{"version":"52"}}]}' > "$asc_response"
cat > "$tool_bin/curl" <<'SHELL'
#!/usr/bin/env bash
set -euo pipefail
output=""
printf '%s\n' "$@" >> "${FAKE_ASC_LOG:?}"
while (( $# > 0 )); do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    -H)
      [[ "$2" == @* ]]
      printf '%s\n' "$(<"${2#@}")" > "${FAKE_ASC_HEADER_LOG:?}"
      shift 2
      ;;
    *) shift ;;
  esac
done
cp "${FAKE_ASC_RESPONSE:?}" "$output"
printf '%s' "${FAKE_ASC_HTTP_CODE:-200}"
SHELL
chmod +x "$tool_bin/curl"
asc_plan="$fixture_repo/build/asc-plan.json"
ASC_APP_ID=1234567890 \
ASC_KEY_ID=FIXTURE123 \
ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 \
ASC_PRIVATE_KEY_PATH="$asc_key" \
TMPDIR="$asc_tmp" \
CURL_COMMAND="$tool_bin/curl" \
FAKE_ASC_LOG="$asc_log" \
FAKE_ASC_HEADER_LOG="$asc_header_log" \
FAKE_ASC_RESPONSE="$asc_response" \
PUBLISHER_PLAN_PATH="$asc_plan" \
MERIAN_PROJECT_ROOT="$fixture_repo" \
  bash "$repo_root/scripts/publish-ios-beta.sh" --dry-run >/dev/null
[[ "$(json_value "$asc_plan" '["build"]')" == "53" ]] || fail "ASC allocation did not select 52 + 1"
assert_contains "filter[app]=1234567890" "$asc_log"
assert_contains "sort=-version" "$asc_log"
assert_contains "limit=1" "$asc_log"
grep -Fq -- 'Authorization: Bearer ' "$asc_log" \
  && fail "App Store Connect JWT was exposed on the curl command line"
assert_contains "merian-asc-auth." "$asc_log"
asc_jwt="$(awk '/^Authorization: Bearer / { print $3; exit }' "$asc_header_log")"
ruby -rbase64 -ropenssl -e '
  token, key_path = ARGV
  encoded_header, encoded_payload, encoded_signature = token.split(".", 3)
  abort("invalid JWT shape") unless encoded_signature
  padding = "=" * ((4 - encoded_signature.length % 4) % 4)
  signature = Base64.urlsafe_decode64(encoded_signature + padding)
  abort("invalid ES256 signature width") unless signature.bytesize == 64
  r = OpenSSL::BN.new(signature.byteslice(0, 32), 2)
  s = OpenSSL::BN.new(signature.byteslice(32, 32), 2)
  der_signature = OpenSSL::ASN1::Sequence([
    OpenSSL::ASN1::Integer(r),
    OpenSSL::ASN1::Integer(s)
  ]).to_der
  signing_input = "#{encoded_header}.#{encoded_payload}"
  key = OpenSSL::PKey.read(File.binread(key_path))
  abort("JWT signature verification failed") unless key.verify(OpenSSL::Digest::SHA256.new, der_signature, signing_input)
' "$asc_jwt" "$asc_key" || fail "publisher generated an invalid App Store Connect JWT"
printf '%s\n' '{"data":"unknown"}' > "$asc_response"
assert_fails_with "malformed build-list response" \
  env ASC_APP_ID=1234567890 ASC_KEY_ID=FIXTURE123 \
  ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_PRIVATE_KEY_PATH="$asc_key" \
  TMPDIR="$asc_tmp" \
  CURL_COMMAND="$tool_bin/curl" FAKE_ASC_LOG="$asc_log" FAKE_ASC_HEADER_LOG="$asc_header_log" FAKE_ASC_RESPONSE="$asc_response" \
  PUBLISHER_PLAN_PATH="$fixture_repo/build/malformed-plan.json" \
  MERIAN_PROJECT_ROOT="$fixture_repo" bash "$repo_root/scripts/publish-ios-beta.sh" --dry-run
asc_secret_remainder="$(find "$asc_tmp" \( -name 'merian-asc-auth.*' -o -name 'merian-asc-builds.*' \) -type f -print -quit)"
[[ -z "$asc_secret_remainder" ]] || fail "App Store Connect lookup left a JWT header or response file: $asc_secret_remainder"

# A failed sole archive burns build 40. The next run allocates 41, archives
# once, exports without renumbering, and publishes one-to-one evidence.
fake_xcodebuild_log="$test_root/xcodebuild.log"
cat > "$tool_bin/xcodebuild" <<'SHELL'
#!/usr/bin/env bash
set -euo pipefail
[[ -z "${PUBLISHER_GITHUB_TOKEN:-}" ]] || exit 86
printf 'COMMAND:%s\n' "${1:-}" >> "${FAKE_XCODEBUILD_LOG:?}"
if [[ "${1:-}" == "archive" ]]; then
  if [[ "${FAKE_ARCHIVE_FAIL:-0}" == "1" ]]; then
    exit 65
  fi
  archive_path=""
  while (( $# > 0 )); do
    case "$1" in
      -archivePath) archive_path="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "$archive_path" ]]
  cp -R "${FAKE_ARCHIVE_TEMPLATE:?}" "$archive_path"
  exit 0
fi
if [[ "${1:-}" == "-exportArchive" ]]; then
  export_path=""
  while (( $# > 0 )); do
    case "$1" in
      -exportPath) export_path="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "$export_path" ]]
  cp "${FAKE_IPA_SOURCE:?}" "$export_path/Merian.ipa"
  exit 0
fi
exit 99
SHELL
chmod +x "$tool_bin/xcodebuild"

run_candidate() {
  env \
    MERIAN_PROJECT_ROOT="$fixture_repo" \
    PROJECT_YML="$fixture_repo/project.yml" \
    MERIAN_PUBLISHER_TESTING=1 \
    PUBLISHER_SKIP_REPOSITORY_GATES=1 \
    MERIAN_PUBLISHER_SERIALIZED=1 \
    MERIAN_GREEN_SHA="$fixture_revision" \
    MERIAN_GREEN_RUN_ID=117 \
    LATEST_ASC_BUILD=39 \
    ASC_APP_ID=1234567890 \
    ASC_TEAM_ID=TA8S64ST9W \
    ASC_KEY_ID=FIXTURE123 \
    ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 \
    ASC_PRIVATE_KEY_PATH="$asc_key" \
    PUBLISHER_GITHUB_TOKEN=fixture_workflow_token \
    XCODEBUILD_COMMAND="$tool_bin/xcodebuild" \
    XCODEGEN_COMMAND="$tool_bin/xcodegen" \
    MERIAN_PLISTBUDDY_COMMAND="$tool_bin/PlistBuddy" \
    FAKE_XCODEBUILD_LOG="$fake_xcodebuild_log" \
    FAKE_ARCHIVE_FAIL="${FAKE_ARCHIVE_FAIL:-0}" \
    FAKE_ARCHIVE_TEMPLATE="${FAKE_ARCHIVE_TEMPLATE:-$fixture_repo/build/not-yet-created.xcarchive}" \
    FAKE_IPA_SOURCE="${FAKE_IPA_SOURCE:-$fixture_repo/build/not-yet-created.ipa}" \
    bash "$repo_root/scripts/publish-ios-beta.sh" --candidate --confirm-external-state
}

mkdir "$fixture_repo/build/.ios-publisher.lock"
assert_fails_with "another local publisher holds" run_candidate
git -C "$fixture_repo" show-ref --verify --quiet refs/tags/ios-build-allocations/40 \
  && fail "contended publisher reserved build 40 before acquiring the local lock"
rmdir "$fixture_repo/build/.ios-publisher.lock"

FAKE_ARCHIVE_FAIL=1 assert_fails_with "sole archive invocation failed" run_candidate
git -C "$fixture_repo" show-ref --verify --quiet refs/tags/ios-build-allocations/40 \
  || fail "failed archive did not preserve build 40 reservation"

successful_archive_template="$fixture_repo/build/success-template.xcarchive"
successful_ipa="$fixture_repo/build/success.ipa"
write_archive_fixture "$successful_archive_template" "1.0.3" "41" "$fixture_revision" "$fixture_fingerprint"
write_ipa_fixture "$successful_ipa" "1.0.3" "41" "$fixture_revision" "$fixture_fingerprint"
FAKE_ARCHIVE_TEMPLATE="$successful_archive_template" \
FAKE_IPA_SOURCE="$successful_ipa" \
assert_succeeds_with "Beta candidate created without upload" run_candidate

evidence_path="$(find "$fixture_repo/build/ios-publisher" -path '*-41-*' -name evidence.json -type f)"
[[ -f "$evidence_path" ]] || fail "successful publisher did not create evidence.json"
[[ "$(json_value "$evidence_path" '["build"]')" == "41" ]] || fail "candidate reused failed build 40"
[[ "$(json_value "$evidence_path" '["archive_invocations"]')" == "1" ]] || fail "evidence did not retain sole archive count"
[[ "$(json_value "$evidence_path" '["source_revision"]')" == "$fixture_revision" ]] || fail "evidence source SHA mismatch"
[[ "$(json_value "$evidence_path" '["source_fingerprint"]')" == "$fixture_fingerprint" ]] || fail "evidence source fingerprint mismatch"
[[ "$(json_value "$evidence_path" '["manageAppVersionAndBuildNumber"]')" == "false" ]] || fail "candidate evidence enabled renumbering"
[[ "$(json_value "$evidence_path" '["promotion_policy"]')" == "same_uploaded_binary_only" ]] \
  || fail "candidate evidence lost the same-binary promotion policy"
[[ "$(json_value "$evidence_path" '["retry_policy"]["identical_ipa_after_definitive_failed_upload"]')" == "allowed" ]] \
  || fail "candidate evidence lost the identical-IPA retry policy"
[[ "$(json_value "$evidence_path" '["retry_policy"]["rebuild_or_source_or_configuration_change"]')" == "allocate_new_build" ]] \
  || fail "candidate evidence allowed a changed rebuild to reuse its build"
evidence_archive_identity="$(json_value "$evidence_path" '["archive_identity"]')"
evidence_ipa_sha="$(json_value "$evidence_path" '["ipa_sha256"]')"
[[ "$evidence_archive_identity" =~ ^[0-9a-f]{64}$ && "$evidence_ipa_sha" =~ ^[0-9a-f]{64}$ ]] \
  || fail "candidate evidence lacks artifact identities"
git -C "$fixture_repo" show-ref --verify --quiet refs/tags/ios-build-allocations/41 \
  || fail "candidate allocation tag is missing"
git -C "$fixture_repo" show-ref --verify --quiet refs/tags/ios-builds/1.0.3-41 \
  || fail "immutable evidence tag is missing"
[[ "$(grep -c '^COMMAND:archive$' "$fake_xcodebuild_log")" == "2" ]] \
  || fail "each of the failed and successful allocations must have exactly one archive invocation"
[[ "$(grep -c '^COMMAND:-exportArchive$' "$fake_xcodebuild_log")" == "1" ]] \
  || fail "successful candidate must export exactly once"

export_options="$(find "$fixture_repo/build/ios-publisher" -path '*-41-*' -name exportOptions.plist -type f)"
managed_value="$($tool_bin/PlistBuddy -c 'Print :manageAppVersionAndBuildNumber' "$export_options")"
[[ "$managed_value" == "False" ]] || fail "export options did not disable Xcode renumbering"

# A post-signing renumber is rejected by the same evidence-bound exporter.
publisher_plan="$(find "$fixture_repo/build/ios-publisher" -path '*-41-*' -name plan.json -type f)"
publisher_archive="$(json_value "$evidence_path" '["archive_path"]')"
write_ipa_fixture "$fixture_repo/build/post-signing-renumber.ipa" "1.0.3" "272" "$fixture_revision" "$fixture_fingerprint"
assert_fails_with "main app build 272 does not match expected build 41" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_RELEASE_PUBLISHER=1 MERIAN_PUBLISHER_SERIALIZED=1 \
  IOS_PUBLISHER_PLAN="$publisher_plan" ARCHIVE_PATH="$publisher_archive" \
  EXPORT_PATH="$fixture_repo/build/renumber-export" TEAM_ID=TA8S64ST9W \
  MERIAN_EXPECTED_MARKETING_VERSION=1.0.3 MERIAN_EXPECTED_BUILD_NUMBER=41 \
  MERIAN_EXPECTED_SOURCE_REVISION="$fixture_revision" MERIAN_EXPECTED_SOURCE_FINGERPRINT="$fixture_fingerprint" \
  XCODEBUILD_COMMAND="$tool_bin/xcodebuild" MERIAN_PLISTBUDDY_COMMAND="$tool_bin/PlistBuddy" \
  FAKE_XCODEBUILD_LOG="$fake_xcodebuild_log" FAKE_IPA_SOURCE="$fixture_repo/build/post-signing-renumber.ipa" \
  bash "$repo_root/scripts/export-ios-release.sh"
assert_fails_with "standalone Organizer/manual export is unsupported" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" bash "$repo_root/scripts/export-ios-release.sh"

# Existing-candidate upload revalidates the exact bytes, does no archive/export,
# and records a durable upload receipt. Retry needs an independent definitive
# Failed confirmation.
assert_fails_with "retry requires --confirm-failed-upload" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_PUBLISHER_SERIALIZED=1 \
  bash "$repo_root/scripts/publish-ios-beta.sh" --retry-upload "$evidence_path" --confirm-upload

xcrun_log="$test_root/xcrun.log"
upload_tmp="$test_root/upload-tmp"
mkdir "$upload_tmp"
cat > "$tool_bin/xcrun" <<'SHELL'
#!/usr/bin/env bash
set -euo pipefail
[[ -z "${PUBLISHER_GITHUB_TOKEN:-}" ]] || exit 86
printf '%s\n' "$@" >> "${FAKE_XCRUN_LOG:?}"
asset_file=""
arguments=("$@")
for (( argument_index = 0; argument_index < ${#arguments[@]}; argument_index += 1 )); do
  if [[ "${arguments[$argument_index]}" == "-assetFile" ]]; then
    asset_file="${arguments[$((argument_index + 1))]}"
    break
  fi
done
if [[ "${FAKE_XCRUN_MUTATE_ASSET:-0}" == "1" ]]; then
  [[ -n "$asset_file" ]]
  printf '%s\n' 'mutated-during-upload' >> "$asset_file"
fi
printf '%s\n' 'UPLOAD SUCCEEDED'
SHELL
chmod +x "$tool_bin/xcrun"
commands_before_upload="$(wc -l < "$fake_xcodebuild_log" | tr -d '[:space:]')"
assert_succeeds_with "exact IPA .* is ready for same-binary promotion" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_PUBLISHER_SERIALIZED=1 \
  PUBLISHER_GITHUB_TOKEN=fixture_workflow_token \
  ASC_APP_ID=1234567890 ASC_TEAM_ID=TA8S64ST9W ASC_KEY_ID=FIXTURE123 \
  ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_PRIVATE_KEY_PATH="$asc_key" \
  TMPDIR="$upload_tmp" XCRUN_COMMAND="$tool_bin/xcrun" FAKE_XCRUN_LOG="$xcrun_log" MERIAN_PLISTBUDDY_COMMAND="$tool_bin/PlistBuddy" \
  bash "$repo_root/scripts/publish-ios-beta.sh" --upload-existing "$evidence_path" --confirm-upload
commands_after_upload="$(wc -l < "$fake_xcodebuild_log" | tr -d '[:space:]')"
[[ "$commands_before_upload" == "$commands_after_upload" ]] || fail "existing upload rebuilt or re-exported the candidate"
assert_contains "iTMSTransporter" "$xcrun_log"
[[ "$(json_value "$evidence_path" '["status"]')" == "uploaded" ]] || fail "upload did not update receipt evidence"
git -C "$fixture_repo" show-ref --verify --quiet refs/tags/ios-uploads/1.0.3-41 \
  || fail "upload receipt tag is missing"
assert_fails_with "first upload requires untouched candidate evidence" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_PUBLISHER_SERIALIZED=1 \
  PUBLISHER_GITHUB_TOKEN=fixture_workflow_token \
  MERIAN_PLISTBUDDY_COMMAND="$tool_bin/PlistBuddy" \
  bash "$repo_root/scripts/publish-ios-beta.sh" --upload-existing "$evidence_path" --confirm-upload
assert_succeeds_with "exact IPA .* is ready for same-binary promotion" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_PUBLISHER_SERIALIZED=1 \
  PUBLISHER_GITHUB_TOKEN=fixture_workflow_token \
  ASC_APP_ID=1234567890 ASC_TEAM_ID=TA8S64ST9W ASC_KEY_ID=FIXTURE123 \
  ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_PRIVATE_KEY_PATH="$asc_key" \
  TMPDIR="$upload_tmp" XCRUN_COMMAND="$tool_bin/xcrun" FAKE_XCRUN_LOG="$xcrun_log" MERIAN_PLISTBUDDY_COMMAND="$tool_bin/PlistBuddy" \
  bash "$repo_root/scripts/publish-ios-beta.sh" --retry-upload "$evidence_path" --confirm-upload --confirm-failed-upload
commands_after_retry="$(wc -l < "$fake_xcodebuild_log" | tr -d '[:space:]')"
[[ "$commands_after_upload" == "$commands_after_retry" ]] || fail "retry rebuilt or re-exported the candidate"
[[ "$(grep -c '^iTMSTransporter$' "$xcrun_log")" == "2" ]] || fail "fixture did not make exactly one initial and one retry upload attempt"
[[ "$(json_value "$evidence_path" '["ipa_sha256"]')" == "$evidence_ipa_sha" ]] || fail "retry changed the immutable IPA identity"
upload_secret_remainder="$(find "$upload_tmp" \( -name 'merian-ios-upload.*' -o -name 'AuthKey_*.p8' \) -print -quit)"
[[ -z "$upload_secret_remainder" ]] || fail "upload credential workspace was not cleaned: $upload_secret_remainder"
assert_fails_with "IPA hash does not match immutable evidence" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_PUBLISHER_SERIALIZED=1 \
  ASC_APP_ID=1234567890 ASC_TEAM_ID=TA8S64ST9W ASC_KEY_ID=FIXTURE123 \
  ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_PRIVATE_KEY_PATH="$asc_key" \
  TMPDIR="$upload_tmp" XCRUN_COMMAND="$tool_bin/xcrun" FAKE_XCRUN_LOG="$xcrun_log" FAKE_XCRUN_MUTATE_ASSET=1 \
  MERIAN_PLISTBUDDY_COMMAND="$tool_bin/PlistBuddy" \
  bash "$repo_root/scripts/publish-ios-beta.sh" --retry-upload "$evidence_path" --confirm-upload --confirm-failed-upload
upload_secret_remainder="$(find "$upload_tmp" \( -name 'merian-ios-upload.*' -o -name 'AuthKey_*.p8' \) -print -quit)"
[[ -z "$upload_secret_remainder" ]] || fail "failed upload left credential or IPA copies behind: $upload_secret_remainder"

tampered_ipa="$fixture_repo/build/tampered.ipa"
cp "$(json_value "$evidence_path" '["ipa_path"]')" "$tampered_ipa"
printf '%s\n' 'tamper' >> "$tampered_ipa"
assert_fails_with "IPA hash does not match immutable evidence" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" MERIAN_PUBLISHER_SERIALIZED=1 \
  bash "$repo_root/scripts/publish-ios-beta.sh" --upload-existing "$evidence_path" --ipa "$tampered_ipa" --confirm-upload

# Once 41 is reserved, another plan receives 42 even if ASC still reports 39.
next_plan="$fixture_repo/build/next-plan.json"
LATEST_ASC_BUILD=39 PUBLISHER_PLAN_PATH="$next_plan" MERIAN_PROJECT_ROOT="$fixture_repo" \
  bash "$repo_root/scripts/publish-ios-beta.sh" --dry-run >/dev/null
[[ "$(json_value "$next_plan" '["build"]')" == "42" ]] || fail "publisher attempted to reuse a reserved build"

echo "iOS versioning and publisher regression tests passed."
