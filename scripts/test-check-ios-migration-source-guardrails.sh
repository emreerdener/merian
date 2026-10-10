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

# Schema and migration fixtures are copied for mutation; other checker
# dependencies remain read-only repository links.
fixture="$tmp_dir/fixture"
mkdir -p "$fixture/apps/ios/Merian/Models"
for path in .github scripts apps/ios/Merian/App \
  apps/ios/Merian/Models/Aliases.swift apps/ios/Merian/Models/ActiveSchema; do
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

cp -R "$repo_root/apps/ios/Merian/Models/Schema" "$fixture/apps/ios/Merian/Models/Schema"

prepare_fixture() {
  python3 - "$repo_root" "$fixture" "$1" <<'PY'
from pathlib import Path
import sys

repo, fixture, mode = sys.argv[1:]
for suffix in ["ScanSnapshots", "QueueSnapshots"]:
    snapshot = Path("apps/ios/Merian/Models/Schema/SchemaV57" + suffix + ".swift")
    original = (Path(repo) / snapshot).read_bytes()
    (Path(fixture) / snapshot).write_bytes(original + (b"\n// mutation\n" if mode == "changed-v57-" + suffix else b""))

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
if mode == "missing-v57-full-tail":
    source = source.replace("migrateV56toV57", "removedV57Stage", 1)
elif mode == "missing-v58-full-tail":
    source = source.replace("migrateV57toV58", "removedV58Stage", 1)
elif mode == "missing-v57-plan":
    source = source[:source.index("enum MerianRecentV57MigrationPlan")]
elif mode == "missing-v56-plan":
    source = source[:source.index("enum MerianRecentV56MigrationPlan")]
elif mode == "missing-v56-full-tail":
    source = source.replace("migrateV55toV56", "removedV56Stage", 1)
elif mode == "missing-v55-plan":
    source = source[:source.index("enum MerianRecentV55MigrationPlan")]
elif mode == "missing-v55-full-tail":
    source = source.replace("            migrateV54toV55", "            removedV55Stage", 1)
elif mode == "missing-v54-plan":
    source = source[:source.index("enum MerianRecentV54MigrationPlan")]
elif mode == "missing-v53-full-tail":
    source = source.replace("            migrateV52toV53", "            removedV53Stage", 1)
elif mode == "missing-v52-plan":
    source = source[:source.index("enum MerianRecentV52MigrationPlan")]
elif mode == "missing-v52-full-tail":
    source = source.replace("            migrateV51toV52", "            removedV52Stage", 1)
elif mode == "missing-v52-recent-tail":
    start = source.index("enum MerianRecentV50MigrationPlan")
    end = source.index("enum MerianReleasedActiveV50MigrationPlan", start)
    plan = source[start:end].replace("MerianMigrationPlan.migrateV51toV52", "removedV52Stage", 1)
    source = source[:start] + plan + source[end:]
elif mode == "reordered-v52-schema":
    source = source.replace("MerianSchemaV51.self,\n            MerianSchemaV52.self", "MerianSchemaV52.self,\n            MerianSchemaV51.self", 1)
elif mode == "missing-v51-plan":
    source = source[:source.index("enum MerianRecentV51MigrationPlan")]
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
if mode == "missing-v51-dispatch":
    factory_source = factory_source.replace("case .v51:", "case .removedV51:", 1)
(Path(fixture) / factory_path).write_text(factory_source)
models_path = Path("apps/ios/Merian/Core/Data/StoreRecovery/Models/StoreMigrationModels.swift")
models_source = (Path(repo) / models_path).read_text()
if mode == "missing-v51-source":
    models_source = models_source.replace("case v51 = 51", "case removedV51 = 51", 1)
(Path(fixture) / models_path).write_text(models_source)


recovery_path = Path(
    "apps/ios/Merian/Core/Data/StoreRecovery/Services/StoreRecoveryMetadataService.swift"
)
recovery_source = (Path(repo) / recovery_path).read_text()
if mode == "reconstructed-store-path":
    recovery_source += '\nlet storeURL = URL.applicationSupportDirectory.appending(path: "default.store")\n'
(Path(fixture) / recovery_path).write_text(recovery_source)

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
assert_rejected reconstructed-store-path "Store recovery must not reconstruct the SwiftData store under Application Support."

assert_rejected missing-v52-full-tail "Full migration plan must finish with the shared V51 through V58 stages."
assert_rejected missing-v52-recent-tail "Recent V50 plan must finish with the shared V51 through V58 stages."
assert_rejected reordered-v52-schema "Full migration plan must end its schemas with frozen V51 through V57 then active V58."
assert_rejected missing-v51-plan "Recent V51 plan must end its schemas with frozen V51 through V57 then active V58."
assert_rejected missing-v51-source "RecentSourceSchema must include V51."
assert_rejected missing-v51-dispatch "ModelContainerFactory recent-source dispatch must handle V51 explicitly."

assert_rejected missing-v53-full-tail "Full migration plan must finish with the shared V51 through V58 stages."
assert_rejected missing-v52-plan "Missing V52 source-isolated plan."
echo "iOS migration source guardrail tests passed."

assert_rejected missing-v55-full-tail "Full migration plan must finish with the shared V51 through V58 stages."
assert_rejected missing-v54-plan "Missing V54 source-isolated plan."

assert_rejected missing-v56-full-tail "Full migration plan must finish with the shared V51 through V58 stages."
assert_rejected missing-v55-plan "Missing V55 source-isolated plan."

assert_rejected missing-v57-full-tail "Full migration plan must finish with the shared V51 through V58 stages."
assert_rejected changed-v57-ScanSnapshots "V57 frozen snapshot changed: ScanSnapshots"
assert_rejected changed-v57-QueueSnapshots "V57 frozen snapshot changed: QueueSnapshots"
assert_rejected missing-v58-full-tail "Full migration plan must finish with the shared V51 through V58 stages."
assert_rejected missing-v57-plan "Missing V57 source-isolated plan."
assert_rejected missing-v56-plan "Missing V56 source-isolated plan."
