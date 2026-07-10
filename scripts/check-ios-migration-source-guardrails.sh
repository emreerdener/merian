#!/usr/bin/env bash
set -euo pipefail

schema_file="apps/ios/Merian/Models/SchemaVersions.swift"
active_queue_file="apps/ios/Merian/Models/ActiveSchema/OfflineQueuedScan.swift"
test_file="apps/ios/MerianTests/Models/MigrationPlanTests.swift"
recovery_file="apps/ios/Merian/Core/Data/StoreRecovery/ModelStoreRecoveryCoordinator.swift"
recovery_test_file="apps/ios/MerianTests/App/ModelStoreRecoveryCoordinatorTests.swift"
app_file="apps/ios/Merian/App/MerianApp.swift"

if [ ! -f "$schema_file" ]; then
  echo "Missing $schema_file" >&2
  exit 1
fi

if [ ! -f "$active_queue_file" ]; then
  echo "Missing $active_queue_file" >&2
  exit 1
fi

if [ ! -f "$test_file" ]; then
  echo "Missing $test_file" >&2
  exit 1
fi

if [ ! -f "$recovery_file" ]; then
  echo "Missing $recovery_file" >&2
  exit 1
fi

if [ ! -f "$recovery_test_file" ]; then
  echo "Missing $recovery_test_file" >&2
  exit 1
fi

if [ ! -f "$app_file" ]; then
  echo "Missing $app_file" >&2
  exit 1
fi

fail() {
  echo "iOS migration source guardrail failed: $*" >&2
  exit 1
}

contains() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file"
}

not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq "$needle" "$file"; then
    fail "$file must not contain: $needle"
  fi
}

extract_block() {
  local start="$1"
  local stop="$2"
  awk -v start="$start" -v stop="$stop" '
    index($0, start) { printing = 1 }
    printing { print }
    printing && index($0, stop) { exit }
  ' "$schema_file"
}

migration_plan_schemas="$(
  awk '
    /enum MerianMigrationPlan/ { in_plan = 1 }
    in_plan && /static var schemas/ { in_schemas = 1 }
    in_schemas { print }
    in_schemas && /static var stages/ { exit }
  ' "$schema_file"
)"

migration_plan_stages="$(
  awk '
    /enum MerianMigrationPlan/ { in_plan = 1 }
    in_plan && /static var stages/ { in_stages = 1 }
    in_stages { print }
    in_stages && /private static func initializeV49OfflineQueueRecords/ { exit }
  ' "$schema_file"
)"

printf '%s\n' "$migration_plan_schemas" | grep -Fq "MerianSchemaV43.self" \
  || fail "MerianMigrationPlan.schemas must include MerianSchemaV43.self."
printf '%s\n' "$migration_plan_schemas" | grep -Fq "MerianSchemaV47.self" \
  || fail "MerianMigrationPlan.schemas must include MerianSchemaV47.self."
printf '%s\n' "$migration_plan_schemas" | grep -Fq "MerianSchemaV48.self" \
  || fail "MerianMigrationPlan.schemas must include MerianSchemaV48.self."
printf '%s\n' "$migration_plan_schemas" | grep -Fq "MerianSchemaV49.self" \
  || fail "MerianMigrationPlan.schemas must include MerianSchemaV49.self."

for retired_recent_schema in MerianSchemaV44.self MerianSchemaV45.self MerianSchemaV46.self; do
  if printf '%s\n' "$migration_plan_schemas" | grep -Fq "$retired_recent_schema"; then
    fail "MerianMigrationPlan.schemas must omit duplicate-prone $retired_recent_schema."
  fi
done

printf '%s\n' "$migration_plan_stages" | grep -Fq "migrateV43toV49" \
  || fail "MerianMigrationPlan.stages must jump from V43 to V49."
printf '%s\n' "$migration_plan_stages" | grep -Fq "migrateV42toV49" \
  || fail "MerianMigrationPlan.stages must jump from V42 to V49."
printf '%s\n' "$migration_plan_stages" | grep -Fq "migrateV48toV49" \
  || fail "MerianMigrationPlan.stages must advance V48 to the V49 startup repair schema."
if printf '%s\n' "$migration_plan_stages" | grep -Fq "migrateV47toV49"; then
  fail "MerianMigrationPlan.stages must not route historical stores through V47."
fi

for source_isolated_stage in migrateV42toV43 migrateV44toV49 migrateV45toV49 migrateV46toV49 migrateV43toV47 migrateV44toV47 migrateV45toV47 migrateV46toV47 migrateV45toV46; do
  if printf '%s\n' "$migration_plan_stages" | grep -Fq "$source_isolated_stage"; then
    fail "MerianMigrationPlan.stages must not include source-isolated or duplicate recent stage $source_isolated_stage."
  fi
done

contains "$schema_file" "static let migrateV42toV49 = MigrationStage.custom" \
  || fail "Missing full-plan V42 to V49 migration."
contains "$schema_file" "fromVersion: MerianSchemaV42.self" \
  || fail "V42 to V49 migration must use MerianSchemaV42 as the source."
contains "$schema_file" "try initializeV49OfflineQueueRecords(in: context, stage: \"V42->V49 didMigrate\")" \
  || fail "V42 to V49 migration must use the durable V49 queue repair."
contains "$schema_file" "static let migrateV43toV49 = MigrationStage.custom" \
  || fail "Missing full-plan V43 to V49 migration."
contains "$schema_file" "fromVersion: MerianSchemaV43.self" \
  || fail "V43 to V49 migration must use MerianSchemaV43 as the source."
contains "$schema_file" "try initializeV49OfflineQueueRecords(in: context, stage: \"V43->V49 didMigrate\")" \
  || fail "V43 to V49 migration must use the durable V49 queue repair."
contains "$schema_file" "static let migrateV44toV49 = MigrationStage.custom" \
  || fail "Missing source-isolated V44 to V49 migration."
contains "$schema_file" "fromVersion: MerianSchemaV44.self" \
  || fail "V44 to V49 migration must use MerianSchemaV44 as the source."
contains "$schema_file" "try initializeV49OfflineQueueRecords(in: context, stage: \"V44->V49 didMigrate\")" \
  || fail "V44 to V49 migration must use the durable V49 queue repair."
contains "$schema_file" "static let migrateV45toV49 = MigrationStage.custom" \
  || fail "Missing source-isolated V45 to V49 migration."
contains "$schema_file" "fromVersion: MerianSchemaV45.self" \
  || fail "V45 to V49 migration must use MerianSchemaV45 as the source."
contains "$schema_file" "static let migrateV46toV49 = MigrationStage.custom" \
  || fail "Missing source-isolated V46 to V49 migration."
contains "$schema_file" "fromVersion: MerianSchemaV46.self" \
  || fail "V46 to V49 migration must use MerianSchemaV46 as the source."
contains "$schema_file" "try initializeV49OfflineQueueRecords(in: context, stage: \"V45->V49 didMigrate\")" \
  || fail "V45 to V49 migration must use the durable V49 queue repair."
contains "$schema_file" "try initializeV49OfflineQueueRecords(in: context, stage: \"V46->V49 didMigrate\")" \
  || fail "V46 to V49 migration must use the durable V49 queue repair."
contains "$schema_file" "enum MerianSchemaV48OptionalQueue: VersionedSchema" \
  || fail "Missing accidental optional-queue V48 source schema."
contains "$schema_file" "enum MerianSchemaV49: VersionedSchema" \
  || fail "Missing V49 startup repair schema."
contains "$schema_file" "static let migrateV48toV49 = MigrationStage.custom" \
  || fail "Missing known-good V48 to V49 migration."
contains "$schema_file" "private static func snapshotV48QueuedScansForV49(in context: ModelContext) throws" \
  || fail "Known-good V48 to V49 migration must snapshot queued scans before target validation."
contains "$schema_file" "try snapshotV48QueuedScansForV49(in: context)" \
  || fail "Known-good V48 to V49 migration must call the V48 queued-scan snapshot helper."
contains "$schema_file" "static let migrateOptionalQueueV48toV49 = MigrationStage.custom" \
  || fail "Missing optional-queue V48 to V49 recovery migration."
contains "$schema_file" "private static func snapshotOptionalQueueV48QueuedScansForV49(in context: ModelContext) throws" \
  || fail "Optional-queue V48 recovery migration must snapshot queued scans before target validation."
contains "$schema_file" "try snapshotOptionalQueueV48QueuedScansForV49(in: context)" \
  || fail "Optional-queue V48 recovery migration must call its queued-scan snapshot helper."
contains "$schema_file" "let snapshots = namespacedSnapshots.isEmpty ? _v49QueuedScanBackfill.allValues() : namespacedSnapshots" \
  || fail "V49 queued-scan repair must tolerate SwiftData will/did namespace drift."
contains "$schema_file" "enum MerianRecentV42MigrationPlan" \
  || fail "Missing source-isolated V42 recovery plan."
contains "$schema_file" "enum MerianRecentV43MigrationPlan" \
  || fail "Missing source-isolated V43 recovery plan."
not_contains "$schema_file" "static let migrateV43toV47"
not_contains "$schema_file" "static let migrateV44toV47"
not_contains "$schema_file" "static let migrateV45toV47"
not_contains "$schema_file" "static let migrateV46toV47"

contains "$active_queue_file" "@Attribute public var queueAttemptCount: Int = 0" \
  || fail "Active V49 OfflineQueuedScan.queueAttemptCount must remain non-optional to preserve already-current store compatibility."
contains "$active_queue_file" "@Attribute public var queueUpdatedAt: Date = Date()" \
  || fail "Active V49 OfflineQueuedScan.queueUpdatedAt must remain non-optional to preserve already-current store compatibility."
contains "$active_queue_file" "@Attribute public var queueNeedsAttention: Bool = false" \
  || fail "Active V49 OfflineQueuedScan.queueNeedsAttention must remain non-optional to preserve already-current store compatibility."
contains "$active_queue_file" "@Attribute public var queueSchemaRepairGeneration: Int = 1" \
  || fail "Active V49 OfflineQueuedScan.queueSchemaRepairGeneration must mark the startup repair schema."
not_contains "$active_queue_file" "queueAttemptCount: Int?"
not_contains "$active_queue_file" "queueUpdatedAt: Date?"
not_contains "$active_queue_file" "queueNeedsAttention: Bool?"
not_contains "$active_queue_file" "queueSchemaRepairGeneration: Int?"

recent_v42_plan="$(extract_block "enum MerianRecentV42MigrationPlan" "enum MerianRecentV43MigrationPlan")"
recent_v43_plan="$(extract_block "enum MerianRecentV43MigrationPlan" "enum MerianRecentV44MigrationPlan")"
recent_v44_plan="$(extract_block "enum MerianRecentV44MigrationPlan" "enum MerianRecentV45MigrationPlan")"
recent_v45_plan="$(extract_block "enum MerianRecentV45MigrationPlan" "enum MerianRecentV46MigrationPlan")"
recent_v46_plan="$(extract_block "enum MerianRecentV46MigrationPlan" "enum MerianRecentV47MigrationPlan")"
recent_v47_plan="$(extract_block "enum MerianRecentV47MigrationPlan" "enum MerianRecentV48MigrationPlan")"
recent_v48_plan="$(extract_block "enum MerianRecentV48MigrationPlan" "enum MerianOptionalQueueV48RecoveryPlan")"
optional_v48_plan="$(extract_block "enum MerianOptionalQueueV48RecoveryPlan" "__MERIAN_STOP__")"

printf '%s\n' "$recent_v42_plan" | grep -Fq "MerianSchemaV42.self" \
  || fail "Recent V42 plan must include MerianSchemaV42."
printf '%s\n' "$recent_v42_plan" | grep -Fq "MerianSchemaV49.self" \
  || fail "Recent V42 plan must target V49."
printf '%s\n' "$recent_v42_plan" | grep -Fq "MerianMigrationPlan.migrateV42toV49" \
  || fail "Recent V42 plan must run migrateV42toV49."
if printf '%s\n' "$recent_v42_plan" | grep -Fq "MerianSchemaV43.self"; then
  fail "Recent V42 plan must skip V43."
fi
if printf '%s\n' "$recent_v42_plan" | grep -Fq "migrateV42toV43"; then
  fail "Recent V42 plan must not run migrateV42toV43."
fi
if printf '%s\n' "$recent_v42_plan" | grep -Fq "migrateV43toV49"; then
  fail "Recent V42 plan must not depend on migrateV43toV49."
fi

printf '%s\n' "$recent_v43_plan" | grep -Fq "MerianSchemaV43.self" \
  || fail "Recent V43 plan must include MerianSchemaV43."
printf '%s\n' "$recent_v43_plan" | grep -Fq "MerianSchemaV49.self" \
  || fail "Recent V43 plan must target V49."
printf '%s\n' "$recent_v43_plan" | grep -Fq "MerianMigrationPlan.migrateV43toV49" \
  || fail "Recent V43 plan must run migrateV43toV49."

printf '%s\n' "$recent_v44_plan" | grep -Fq "MerianSchemaV44.self" \
  || fail "Recent V44 plan must include MerianSchemaV44."
printf '%s\n' "$recent_v44_plan" | grep -Fq "MerianSchemaV49.self" \
  || fail "Recent V44 plan must target V49."
printf '%s\n' "$recent_v44_plan" | grep -Fq "MerianMigrationPlan.migrateV44toV49" \
  || fail "Recent V44 plan must run migrateV44toV49."
if printf '%s\n' "$recent_v44_plan" | grep -Fq "MerianSchemaV47.self"; then
  fail "Recent V44 plan must skip V47."
fi

printf '%s\n' "$recent_v45_plan" | grep -Fq "MerianSchemaV45.self" \
  || fail "Recent V45 plan must include MerianSchemaV45."
printf '%s\n' "$recent_v45_plan" | grep -Fq "MerianSchemaV49.self" \
  || fail "Recent V45 plan must target V49."
printf '%s\n' "$recent_v45_plan" | grep -Fq "MerianMigrationPlan.migrateV45toV49" \
  || fail "Recent V45 plan must run migrateV45toV49."
if printf '%s\n' "$recent_v45_plan" | grep -Fq "MerianSchemaV47.self"; then
  fail "Recent V45 plan must skip V47."
fi

printf '%s\n' "$recent_v46_plan" | grep -Fq "MerianSchemaV46.self" \
  || fail "Recent V46 plan must include MerianSchemaV46."
printf '%s\n' "$recent_v46_plan" | grep -Fq "MerianSchemaV49.self" \
  || fail "Recent V46 plan must target V49."
printf '%s\n' "$recent_v46_plan" | grep -Fq "MerianMigrationPlan.migrateV46toV49" \
  || fail "Recent V46 plan must run migrateV46toV49."
if printf '%s\n' "$recent_v46_plan" | grep -Fq "MerianSchemaV45.self"; then
  fail "Recent V46 plan must not use the V45 source representative."
fi

printf '%s\n' "$recent_v47_plan" | grep -Fq "MerianSchemaV47.self" \
  || fail "Recent V47 plan must include MerianSchemaV47."
printf '%s\n' "$recent_v47_plan" | grep -Fq "MerianSchemaV49.self" \
  || fail "Recent V47 plan must target V49."
printf '%s\n' "$recent_v47_plan" | grep -Fq "MerianMigrationPlan.migrateV47toV49" \
  || fail "Recent V47 plan must run migrateV47toV49."

printf '%s\n' "$recent_v48_plan" | grep -Fq "MerianSchemaV48.self" \
  || fail "Recent V48 plan must include the known-good V48 source."
printf '%s\n' "$recent_v48_plan" | grep -Fq "MerianSchemaV49.self" \
  || fail "Recent V48 plan must target V49."
printf '%s\n' "$recent_v48_plan" | grep -Fq "MerianMigrationPlan.migrateV48toV49" \
  || fail "Recent V48 plan must run migrateV48toV49."
if printf '%s\n' "$recent_v48_plan" | grep -Fq "MerianSchemaV48OptionalQueue.self"; then
  fail "Recent V48 known-good plan must not mix in the optional-queue source."
fi

printf '%s\n' "$optional_v48_plan" | grep -Fq "MerianSchemaV48OptionalQueue.self" \
  || fail "Optional-queue V48 plan must include the bad V48 source."
printf '%s\n' "$optional_v48_plan" | grep -Fq "MerianSchemaV49.self" \
  || fail "Optional-queue V48 plan must target V49."
printf '%s\n' "$optional_v48_plan" | grep -Fq "MerianMigrationPlan.migrateOptionalQueueV48toV49" \
  || fail "Optional-queue V48 plan must run migrateOptionalQueueV48toV49."

not_contains "$test_file" "removeSQLiteStore"
not_contains "$test_file" "URL.cachesDirectory"
not_contains "$test_file" "FileManager.default.removeItem(at: url)"
not_contains "$test_file" "Duplicate version checksums across stages detected"
contains "$test_file" "keepSQLiteStoreForProcessLifetime" \
  || fail "MigrationPlanTests must keep disk-backed migration stores alive for the process lifetime."
contains "$test_file" "activeOfflineQueuedScanKeepsDurableRetryFieldsNonOptional" \
  || fail "MigrationPlanTests must guard active V49 queue retry fields against optionality changes."
contains "$test_file" "migrationFromOptionalQueueV48ToCurrentSchemaRecoversRetryFields" \
  || fail "MigrationPlanTests must cover the accidental optional-queue V48 recovery fixture."
contains "$test_file" "migrationFromV42ToCurrentSchemaUsesSourceIsolatedPlan" \
  || fail "MigrationPlanTests must cover the V42 source-isolated recovery fixture from startup diagnostics."
contains "$recovery_file" "shouldRescueStoreAfterMigrationFailure" \
  || fail "Store recovery must keep the legacy migration rescue decision."
contains "$recovery_file" "store-rescue" \
  || fail "Store recovery must archive unrecoverable legacy stores under store-rescue."
contains "$recovery_file" "legacy_migration_rescue" \
  || fail "Store recovery manifests must distinguish legacy migration rescue from corruption quarantine."
contains "$recovery_file" "schemaVersion: Int = 2" \
  || fail "Store recovery manifests/diagnostics must use the current schema version."
contains "$app_file" "legacy_store_rescued" \
  || fail "MerianApp must recover legacy migration failures with legacy_store_rescued telemetry."
contains "$app_file" "post-migration-rescue-current-store" \
  || fail "MerianApp must reopen a fresh persistent store after legacy migration rescue."
contains "$recovery_test_file" "testRescuesLegacyMigrationFailuresEvenWhenSwiftDataErrorIsGeneric" \
  || fail "ModelStoreRecoveryCoordinatorTests must cover generic SwiftDataError legacy rescue."
contains "$recovery_test_file" "testRescueArchivesStoreArtifacts" \
  || fail "ModelStoreRecoveryCoordinatorTests must cover store-rescue archive manifests."

echo "iOS migration source guardrails passed."
