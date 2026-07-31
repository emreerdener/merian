#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-project-resource-tests.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

fixture_project() {
  local name="$1"
  local fixture="$tmp_dir/${name}.pbxproj"
  cp "$repo_root/merian.xcodeproj/project.pbxproj" "$fixture"
  printf '%s\n' "$fixture"
}

run_check() {
  local project_spec="${2:-$repo_root/project.yml}"
  (
    cd "$repo_root"
    bash scripts/check-ios-project-resources.sh "$1" "$project_spec"
  )
}

assert_fails_with() {
  local expected="$1"
  local fixture="$2"
  local project_spec="${3:-$repo_root/project.yml}"
  local output
  if output="$(run_check "$fixture" "$project_spec" 2>&1)"; then
    fail "Expected project guardrail to reject ${fixture}"
  fi
  if ! grep -Fq "$expected" <<<"$output"; then
    fail "Expected rejection to contain '${expected}', got: ${output}"
  fi
}

baseline_fixture="$(fixture_project baseline)"
run_check "$baseline_fixture"

distribution_identity_fixture="$(fixture_project distribution-identity)"
perl -0pi -e '
  my $count = s{
    (\n[ \t]+)(CODE_SIGN_STYLE[ \t]=[ \t]Automatic;)
  }{$1CODE_SIGN_IDENTITY = "Apple Distribution";$1$2}x;
  die "expected one automatic signing setting\n" unless $count == 1;
' "$distribution_identity_fixture"
assert_fails_with \
  "Automatic signing must not force a code-signing identity" \
  "$distribution_identity_fixture"

distribution_identity_spec="$tmp_dir/distribution-identity-project.yml"
cp "$repo_root/project.yml" "$distribution_identity_spec"
perl -0pi -e '
  my $count = s{
    ([ \t]+CODE_SIGN_STYLE:[ \t]Automatic\n)
  }{$1    CODE_SIGN_IDENTITY: "Apple Distribution"\n}x;
  die "expected one automatic signing setting\n" unless $count == 1;
' "$distribution_identity_spec"
assert_fails_with \
  "Automatic signing must not force a code-signing identity" \
  "$baseline_fixture" \
  "$distribution_identity_spec"

detached_provenance_fixture="$(fixture_project detached-provenance)"
perl -0pi -e '
  my $count = s{
    \n[ \t]+[A-F0-9]+[ \t]+/\*[ \t]Embed[ \t]Build[ \t]Provenance[ \t]\*/,[ \t]*
  }{}x;
  die "expected one provenance target reference\n" unless $count == 1;
' "$detached_provenance_fixture"
assert_fails_with \
  "Embed Build Provenance must be attached exactly once and only to the Merian target." \
  "$detached_provenance_fixture"

duplicate_provenance_fixture="$(fixture_project duplicate-provenance)"
perl -0pi -e '
  my $count = s{
    (\n[ \t]+[A-F0-9]+[ \t]+/\*[ \t]Embed[ \t]Build[ \t]Provenance[ \t]\*/,[ \t]*)
  }{$1$1}x;
  die "expected one provenance target reference\n" unless $count == 1;
' "$duplicate_provenance_fixture"
assert_fails_with \
  "Embed Build Provenance must be attached exactly once and only to the Merian target." \
  "$duplicate_provenance_fixture"

early_provenance_fixture="$(fixture_project early-provenance)"
perl -0pi -e '
  my $count = s{
    (/\*[ \t]Merian[ \t]\*/[ \t]=[ \t]\{\n[ \t]+isa[ \t]=[ \t]PBXNativeTarget;\n.*?buildPhases[ \t]=[ \t]\(\n)
    (.*?)
    (\n[ \t]+[A-F0-9]+[ \t]+/\*[ \t]Resources[ \t]\*/,)
    (.*?)
    (\n[ \t]+[A-F0-9]+[ \t]+/\*[ \t]Embed[ \t]Build[ \t]Provenance[ \t]\*/,)
  }{${1}${2}${5}${3}${4}}xs;
  die "expected Merian resources/provenance sequence\n" unless $count == 1;
' "$early_provenance_fixture"
assert_fails_with \
  "Embed Build Provenance must run after Merian Resources." \
  "$early_provenance_fixture"

detached_preflight_fixture="$(fixture_project detached-preflight)"
perl -0pi -e '
  my $count = s{
    \n[ \t]+[A-F0-9]+[ \t]+/\*[ \t]Release[ \t]Versioning[ \t]Preflight[ \t]\*/,[ \t]*
  }{}x;
  die "expected one preflight target reference\n" unless $count == 1;
' "$detached_preflight_fixture"
assert_fails_with \
  "Release Versioning Preflight must be attached exactly once and only to the Merian target." \
  "$detached_preflight_fixture"

late_preflight_fixture="$(fixture_project late-preflight)"
perl -0pi -e '
  my $count = s{
    (/\*[ \t]Merian[ \t]\*/[ \t]=[ \t]\{\n[ \t]+isa[ \t]=[ \t]PBXNativeTarget;\n.*?buildPhases[ \t]=[ \t]\(\n)
    ([ \t]+[A-F0-9]+[ \t]+/\*[ \t]Release[ \t]Versioning[ \t]Preflight[ \t]\*/,\n)
    ([ \t]+[A-F0-9]+[ \t]+/\*[ \t]Sources[ \t]\*/,\n)
  }{${1}${3}${2}}xs;
  die "expected Merian preflight/sources sequence\n" unless $count == 1;
' "$late_preflight_fixture"
assert_fails_with \
  "Release Versioning Preflight must be the first Merian build phase." \
  "$late_preflight_fixture"

wrong_provenance_command_fixture="$(fixture_project wrong-provenance-command)"
perl -0pi -e '
  my $count = s{
    scripts/embed-ios-build-provenance[.]sh
  }{scripts/not-the-provenance-embedder.sh}x;
  die "expected one provenance command\n" unless $count == 1;
' "$wrong_provenance_command_fixture"
assert_fails_with \
  "Embed Build Provenance must remain always-out-of-date and invoke only scripts/embed-ios-build-provenance.sh." \
  "$wrong_provenance_command_fixture"

provenance_after_lint_fixture="$(fixture_project provenance-after-lint)"
perl -0pi -e '
  my $count = s{
    (/\*[ \t]Merian[ \t]\*/[ \t]=[ \t]\{\n[ \t]+isa[ \t]=[ \t]PBXNativeTarget;\n.*?buildPhases[ \t]=[ \t]\(\n.*?)
    ([ \t]+[A-F0-9]+[ \t]+/\*[ \t]Embed[ \t]Build[ \t]Provenance[ \t]\*/,\n)
    ([ \t]+[A-F0-9]+[ \t]+/\*[ \t]SwiftLint[ \t]Validation[ \t]\*/,\n)
  }{${1}${3}${2}}xs;
  die "expected Merian provenance/lint sequence\n" unless $count == 1;
' "$provenance_after_lint_fixture"
assert_fails_with \
  "Embed Build Provenance must be the final product-mutating Merian phase, immediately before SwiftLint Validation." \
  "$provenance_after_lint_fixture"

echo "iOS generated-project resource guardrail tests passed."
