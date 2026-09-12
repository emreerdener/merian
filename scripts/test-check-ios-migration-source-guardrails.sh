#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$repo_root/scripts/check-ios-migration-source-guardrails.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-migration-guardrail-tests.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

# Only SchemaVersions.swift is mutated; all other checker inputs are read-only
# links to the repository so frozen snapshot digests remain authoritative.
fixture="$tmp_dir/fixture"
mkdir -p "$fixture/apps/ios/Merian/Models"
for path in .github scripts apps/ios/MerianTests apps/ios/Merian/App apps/ios/Merian/Core \
  apps/ios/Merian/Models/Aliases.swift apps/ios/Merian/Models/ActiveSchema apps/ios/Merian/Models/Schema; do
  ln -s "$repo_root/$path" "$fixture/$path"
done

prepare_fixture() {
  python3 - "$repo_root" "$fixture" "$1" <<'PY'
from pathlib import Path
import sys

repo, fixture, mode = sys.argv[1:]
path = Path("apps/ios/Merian/Models/SchemaVersions.swift")
source = (Path(repo) / path).read_text()
start = source.index("enum MerianRecentV47MigrationPlan")
end = source.index("enum MerianRecentV48MigrationPlan", start)
plan = source[start:end]
if mode != "baseline":
    # Exceed pipe capacity after the first source match. An early-exiting grep
    # must not turn a valid plan into a SIGPIPE failure from its producer.
    plan = plan.replace("MerianSchemaV47.self,", "MerianSchemaV47.self,\n// " + "padding " * 131072 + "\n", 1)
if mode == "missing-source":
    plan = plan.replace("MerianSchemaV47.self,", "", 1)
elif mode == "missing-stage":
    plan = plan.replace("MerianMigrationPlan.migrateV47toV49,", "", 1)
source = source[:start] + plan + source[end:]
if mode == "forbidden-source":
    start = source.index("enum MerianRecentV46MigrationPlan")
    end = source.index("enum MerianRecentV47MigrationPlan", start)
    plan = source[start:end].replace(
        "MerianSchemaV46.self,",
        "MerianSchemaV46.self,\nMerianSchemaV45.self,\n// " + "padding " * 131072 + "\n",
        1,
    )
    source = source[:start] + plan + source[end:]
(Path(fixture) / path).write_text(source)
PY
}

run_check() {
  (cd "$fixture" && bash "$checker")
}

assert_rejected() {
  local mode="$1"
  local expected="$2"
  local output
  prepare_fixture "$mode"
  if output="$(run_check 2>&1)"; then
    fail "Expected migration guardrail to reject $mode"
  fi
  grep -Fq -- "$expected" <<< "$output" \
    || fail "Expected '$expected', got: $output"
}

bash -n "$checker"
prepare_fixture baseline
run_check
prepare_fixture padded
run_check
assert_rejected missing-source "Recent V47 plan must include MerianSchemaV47."
assert_rejected missing-stage "Recent V47 plan must run migrateV47toV49."
assert_rejected forbidden-source "Recent V46 plan must not use the V45 source representative."

echo "iOS migration source guardrail tests passed."
