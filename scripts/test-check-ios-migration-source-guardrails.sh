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

# Only SchemaVersions.swift, ModelContainerFactory.swift, and
# MigrationPlanTests.swift are copied for mutation; frozen snapshot inputs and
# other checker dependencies remain read-only repository links.
fixture="$tmp_dir/fixture"
mkdir -p "$fixture/apps/ios/Merian/Models"
for path in .github scripts apps/ios/Merian/App \
  apps/ios/Merian/Models/Aliases.swift apps/ios/Merian/Models/ActiveSchema apps/ios/Merian/Models/Schema; do
  ln -s "$repo_root/$path" "$fixture/$path"
done
mkdir -p \
  "$fixture/apps/ios/MerianTests/Core/Data" \
  "$fixture/apps/ios/MerianTests/Models"
ln -s \
  "$repo_root/apps/ios/MerianTests/Core/Data/StoreRecovery" \
  "$fixture/apps/ios/MerianTests/Core/Data/StoreRecovery"
ln -s \
  "$repo_root/apps/ios/MerianTests/Core/Data/Images" \
  "$fixture/apps/ios/MerianTests/Core/Data/Images"
cp \
  "$repo_root/apps/ios/MerianTests/Models/MigrationPlanTests.swift" \
  "$fixture/apps/ios/MerianTests/Models/MigrationPlanTests.swift"
cp -R "$repo_root/apps/ios/Merian/Core" "$fixture/apps/ios/Merian/Core"

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
if mode in {"padded", "missing-source", "missing-stage", "forbidden-source"}:
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

factory_path = Path(
    "apps/ios/Merian/Core/Data/StoreRecovery/Services/ModelContainerFactory.swift"
)
factory_source = (Path(repo) / factory_path).read_text()
if mode == "safe-mode-plan":
    start = factory_source.index(
        "private static func makeInMemoryContainerUnchecked()"
    )
    end = factory_source.index(
        "static func makeContainerCatchingObjectiveCExceptions(", start
    )
    function = factory_source[start:end]
    function = function.replace(
        "return try ModelContainer(for: schema, configurations: [config])",
        "return try ModelContainer(\n"
        "            for: schema,\n"
        "            migrationPlan: MerianMigrationPlan.self,\n"
        "            configurations: [config]\n"
        "        )",
        1,
    )
    factory_source = factory_source[:start] + function + factory_source[end:]
(Path(fixture) / factory_path).write_text(factory_source)

test_path = Path("apps/ios/MerianTests/Models/MigrationPlanTests.swift")
test_source = (Path(repo) / test_path).read_text()
if mode == "weakened-full-plan-test":
    start = test_source.index(
        "@Test func migrationPlanContainerInitializesWithoutCrash()"
    )
    end = test_source.index(
        "@Test func currentSchemaFreshDiskStoreOpensWithoutMigrationPlan()", start
    )
    function = test_source[start:end]
    function = function.replace(
        "migrationPlan: MerianMigrationPlan.self",
        "migrationPlan: MerianRecentV49MigrationPlan.self",
        1,
    )
    test_source = test_source[:start] + function + test_source[end:]
(Path(fixture) / test_path).write_text(test_source)
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
assert_rejected safe-mode-plan "The empty current-schema safe-mode container must not validate the historical migration plan."
assert_rejected weakened-full-plan-test "MigrationPlanTests must validate the full historical plan independently from safe mode."

echo "iOS migration source guardrail tests passed."
