#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$repo_root/scripts/check-ios-project-source-membership.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-ios-source-membership.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

fixture_root="$tmp_dir/fixture"
fixture_project="$fixture_root/Fixture.xcodeproj"
fixture_spec="$fixture_root/project.yml"
mkdir -p "$fixture_root/Sources" "$fixture_root/Other"

printf '%s\n' \
  'name: Fixture' \
  'targets:' \
  '  App:' \
  '    type: application' \
  '    platform: iOS' \
  '    sources:' \
  '      - Sources' > "$fixture_spec"
printf 'struct Included {}\n' > "$fixture_root/Sources/Included.swift"

ruby -rxcodeproj - \
  "$fixture_project" \
  "$fixture_root/Sources/Included.swift" <<'RUBY'
project = Xcodeproj::Project.new(ARGV.fetch(0))
target = project.new_target(:application, "App", :ios, "17.2")
sources = project.main_group.new_group("Sources", "Sources")
reference = sources.new_file(ARGV.fetch(1))
target.add_file_references([reference])
project.save
RUBY

run_validator() {
  env \
    IOS_SOURCE_MEMBERSHIP_ROOT="$fixture_root" \
    IOS_SOURCE_MEMBERSHIP_PROJECT="$fixture_project" \
    IOS_SOURCE_MEMBERSHIP_SPEC="$fixture_spec" \
    bash "$validator"
}

run_validator >/dev/null \
  || fail "A matching generated project was rejected."

printf 'struct Missing {}\n' > "$fixture_root/Sources/Missing.swift"
missing_output="$tmp_dir/missing-output.txt"
if run_validator >"$missing_output" 2>&1; then
  fail "A project that omitted a project.yml source was accepted."
fi
grep -Fq "Sources/Missing.swift" "$missing_output" \
  || fail "Missing-source diagnostics did not identify the omitted file."
rm "$fixture_root/Sources/Missing.swift"

printf 'struct Unexpected {}\n' > "$fixture_root/Other/Unexpected.swift"
ruby -rxcodeproj - \
  "$fixture_project" \
  "$fixture_root/Other/Unexpected.swift" <<'RUBY'
project = Xcodeproj::Project.open(ARGV.fetch(0))
target = project.targets.find { |candidate| candidate.name == "App" }
other = project.main_group.new_group("Other", "Other")
reference = other.new_file(ARGV.fetch(1))
target.add_file_references([reference])
project.save
RUBY

unexpected_output="$tmp_dir/unexpected-output.txt"
if run_validator >"$unexpected_output" 2>&1; then
  fail "A project with an out-of-spec compiled source was accepted."
fi
grep -Fq "Other/Unexpected.swift" "$unexpected_output" \
  || fail "Unexpected-source diagnostics did not identify the extra file."

orphan_root="$tmp_dir/orphan-fixture"
mkdir -p "$orphan_root/Sources" "$orphan_root/apps/ios/NewFeature"
cp "$fixture_spec" "$orphan_root/project.yml"
printf 'struct Included {}\n' > "$orphan_root/Sources/Included.swift"
printf 'struct Orphan {}\n' > "$orphan_root/apps/ios/NewFeature/Orphan.swift"
ruby -rxcodeproj - \
  "$orphan_root/Fixture.xcodeproj" \
  "$orphan_root/Sources/Included.swift" <<'RUBY'
project = Xcodeproj::Project.new(ARGV.fetch(0))
target = project.new_target(:application, "App", :ios, "17.2")
sources = project.main_group.new_group("Sources", "Sources")
reference = sources.new_file(ARGV.fetch(1))
target.add_file_references([reference])
project.save
RUBY

orphan_output="$tmp_dir/orphan-output.txt"
if env \
  IOS_SOURCE_MEMBERSHIP_ROOT="$orphan_root" \
  IOS_SOURCE_MEMBERSHIP_PROJECT="$orphan_root/Fixture.xcodeproj" \
  IOS_SOURCE_MEMBERSHIP_SPEC="$orphan_root/project.yml" \
  bash "$validator" >"$orphan_output" 2>&1; then
  fail "An iOS source outside every project.yml target was accepted."
fi
grep -Fq "apps/ios/NewFeature/Orphan.swift" "$orphan_output" \
  || fail "Orphan-source diagnostics did not identify the unowned file."

echo "iOS generated-project source membership tests passed."
