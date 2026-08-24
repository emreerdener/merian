#!/usr/bin/env bash
set -euo pipefail

schema_file="apps/ios/Merian/Models/SchemaVersions.swift"
alias_file="apps/ios/Merian/Models/Aliases.swift"
active_queue_file="apps/ios/Merian/Models/ActiveSchema/OfflineQueuedScan.swift"
test_file="apps/ios/MerianTests/Models/MigrationPlanTests.swift"
recovery_file="apps/ios/Merian/Core/Data/StoreRecovery/ModelStoreRecoveryCoordinator.swift"
recovery_test_file="apps/ios/MerianTests/App/ModelStoreRecoveryCoordinatorTests.swift"
app_file="apps/ios/Merian/App/MerianApp.swift"

if [ ! -f "$schema_file" ]; then
  echo "Missing $schema_file" >&2
  exit 1
fi

if [ ! -f "$alias_file" ]; then
  echo "Missing $alias_file" >&2
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
printf '%s\n' "$migration_plan_schemas" | grep -Fq "MerianSchemaV50.self" \
  || fail "MerianMigrationPlan.schemas must include the current MerianSchemaV50.self."

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
printf '%s\n' "$migration_plan_stages" | grep -Fq "migrateV49toV50" \
  || fail "MerianMigrationPlan.stages must advance V49 to the current V50 schema."
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
contains "$schema_file" "enum MerianSchemaV50: VersionedSchema" \
  || fail "Missing current V50 schema."
contains "$alias_file" "typealias CurrentSchema = MerianSchemaV50" \
  || fail "CurrentSchema must remain aligned with the V49 to V50 migration target."
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
contains "$schema_file" "scan.queueAttemptCount = 0" \
  || fail "V49 queued-scan repair must normalize missing retry count defaults on just-migrated rows."
contains "$schema_file" "scan.queueUpdatedAt = now" \
  || fail "V49 queued-scan repair must normalize missing retry timestamp defaults on just-migrated rows."
contains "$schema_file" "scan.queueNeedsAttention = false" \
  || fail "V49 queued-scan repair must normalize missing needs-attention defaults on just-migrated rows."
contains "$schema_file" "Do not save here. V48 stores can materialize target rows" \
  || fail "Known-good V48 willMigrate must not save before V49 retry fields are repaired."
contains "$schema_file" "Do not save here. Optional-queue V48 rows intentionally have nil" \
  || fail "Optional-queue V48 willMigrate must not save before V49 retry fields are repaired."
contains "$schema_file" "enum MerianRecentV42MigrationPlan" \
  || fail "Missing source-isolated V42 recovery plan."
contains "$schema_file" "enum MerianRecentV43MigrationPlan" \
  || fail "Missing source-isolated V43 recovery plan."
contains "$schema_file" "enum MerianRecentV49MigrationPlan" \
  || fail "Missing source-isolated V49 to V50 migration plan."
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
optional_v48_plan="$(extract_block "enum MerianOptionalQueueV48RecoveryPlan" "enum MerianRecentV49MigrationPlan")"
recent_v49_plan="$(extract_block "enum MerianRecentV49MigrationPlan" "__MERIAN_STOP__")"

require_v50_tail() {
  local plan_text="$1"
  local plan_name="$2"

  printf '%s\n' "$plan_text" | grep -Fq "MerianSchemaV50.self" \
    || fail "$plan_name must include the current V50 target."
  printf '%s\n' "$plan_text" | grep -Fq "MerianMigrationPlan.migrateV49toV50" \
    || fail "$plan_name must finish with the shared V49 to V50 stage."
}

require_v50_tail "$recent_v42_plan" "Recent V42 plan"
require_v50_tail "$recent_v43_plan" "Recent V43 plan"
require_v50_tail "$recent_v44_plan" "Recent V44 plan"
require_v50_tail "$recent_v45_plan" "Recent V45 plan"
require_v50_tail "$recent_v46_plan" "Recent V46 plan"
require_v50_tail "$recent_v47_plan" "Recent V47 plan"
require_v50_tail "$recent_v48_plan" "Recent V48 plan"
require_v50_tail "$optional_v48_plan" "Optional-queue V48 plan"
require_v50_tail "$recent_v49_plan" "Recent V49 plan"

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

printf '%s\n' "$recent_v49_plan" | grep -Fq "MerianSchemaV49.self" \
  || fail "Recent V49 plan must include the released V49 source."
if printf '%s\n' "$recent_v49_plan" | grep -Eq "MerianSchemaV(4[2-8]|48OptionalQueue)[.]self"; then
  fail "Recent V49 plan must not validate an earlier source schema."
fi
if [ "$(printf '%s\n' "$recent_v49_plan" | grep -Fc "MerianMigrationPlan.migrateV49toV50")" -ne 1 ]; then
  fail "Recent V49 plan must contain exactly one V49 to V50 stage reference."
fi

not_contains "$test_file" "removeSQLiteStore"
not_contains "$test_file" "URL.cachesDirectory"
not_contains "$test_file" "FileManager.default.removeItem(at: url)"
not_contains "$test_file" "Duplicate version checksums across stages detected"
contains "$test_file" "keepSQLiteStoreForProcessLifetime" \
  || fail "MigrationPlanTests must keep disk-backed migration stores alive for the process lifetime."
contains "$test_file" "activeOfflineQueuedScanKeepsDurableRetryFieldsNonOptional" \
  || fail "MigrationPlanTests must guard active V49 queue retry fields against optionality changes."
contains "$test_file" "knownGoodV48RequiredValueFailureUsesLegacyRescue" \
  || fail "MigrationPlanTests must cover the known-good V48 legacy rescue fixture."
contains "$test_file" "optionalQueueV48RequiredValueFailureUsesLegacyRescue" \
  || fail "MigrationPlanTests must cover the accidental optional-queue V48 legacy rescue fixture."
contains "$test_file" "migrationFromV42ToCurrentSchemaUsesSourceIsolatedPlan" \
  || fail "MigrationPlanTests must cover the V42 source-isolated recovery fixture from startup diagnostics."
contains "$test_file" "recentV49MigrationPlanOnlyRunsLightweightV49ToV50Hop" \
  || fail "MigrationPlanTests must lock the source-isolated V49 plan shape."
contains "$test_file" "migrationFromV49UsesDiskMetadataSelectionAndPreservesQueueData" \
  || fail "MigrationPlanTests must exercise a disk-backed V49 to V50 migration."
contains "$test_file" "let decision = ModelStoreRecoveryCoordinator.migrationDecision(" \
  || fail "The V49 disk fixture must exercise production metadata-based plan selection."
contains "$test_file" "#expect(decision.storedSchemaMajorVersion == 49)" \
  || fail "The V49 disk fixture must verify the emitted on-disk schema major."
contains "$test_file" "#expect(decision.hint == .recentSource(.v49))" \
  || fail "The V49 disk fixture must select the source-isolated V49 startup path."
contains "$test_file" "migrationPlan: MerianRecentV49MigrationPlan.self" \
  || fail "The V49 disk fixture must open with the production V49 migration plan."
contains "$recovery_file" "enum RecentSourceSchema: Int, CaseIterable, Equatable" \
  || fail "Store recovery must model recent source schemas as an exhaustive enum."
for recent_major in $(seq 42 49); do
  contains "$recovery_file" "case v${recent_major} = ${recent_major}" \
    || fail "RecentSourceSchema must include V${recent_major}."
done
contains "$recovery_file" "RecentSourceSchema(rawValue: storedSchemaMajorVersion)" \
  || fail "Store recovery must classify metadata through the exhaustive recent-source enum."
contains "$recovery_test_file" "testSourceIsolatedSchemasAreConsecutiveAndEndAtCurrentPredecessor" \
  || fail "Store recovery tests must fail when a future schema bump omits its immediate-predecessor plan."
contains "$recovery_test_file" "testStoreMigrationHintUsesRecentV49PlanForV50Upgrade" \
  || fail "Store recovery tests must route V49 to the source-isolated V49 plan."
contains "$app_file" "private static func makePersistentContainerForRecentSource(" \
  || fail "MerianApp must dispatch recent sources through an exhaustive plan selector."
recent_source_dispatch="$(
  awk '
    /private static func makePersistentContainerForRecentSource\(/ { printing = 1 }
    printing { print }
    printing && /forStoreMigrationHint hint:/ { exit }
  ' "$app_file"
)"
for recent_major in $(seq 42 49); do
  printf '%s\n' "$recent_source_dispatch" | grep -Fq "case .v${recent_major}:" \
    || fail "MerianApp recent-source dispatch must handle V${recent_major} explicitly."
done
if printf '%s\n' "$recent_source_dispatch" | grep -Eq '^[[:space:]]*(@unknown[[:space:]]+)?default:'; then
  fail "MerianApp recent-source dispatch must remain compiler-exhaustive without a default branch."
fi
not_contains "$app_file" "recent-fallback-full"
contains "$app_file" "named: \"recent-v49\"" \
  || fail "MerianApp must record the selected recent-v49 startup attempt."
contains "$app_file" "named: \"checksum-recent-v49\"" \
  || fail "The checksum retry ladder must try the V49 plan before older sources."
checksum_retry_dispatch="$(
  awk '
    /private static func makePersistentContainerRetryingChecksumRepresentative\(/ { printing = 1 }
    printing { print }
    printing && /private static func makePersistentContainerForV48Source\(/ { exit }
  ' "$app_file"
)"
checksum_retry_markers=(
  'named: "checksum-current-store"'
  'named: "checksum-recent-v49"'
  'let recovered = try makePersistentContainerForV48Source'
  'named: "checksum-recent-v47"'
  'named: "checksum-recent-v46"'
  'named: "checksum-recent-v45"'
  'named: "checksum-recent-v44"'
  'named: "checksum-recent-v43"'
  'named: "checksum-recent-v42"'
)
previous_retry_line=0
for marker in "${checksum_retry_markers[@]}"; do
  retry_line="$(
    awk -v marker="$marker" 'index($0, marker) { print NR; exit }' \
      <<< "$checksum_retry_dispatch"
  )"
  if [ -z "$retry_line" ]; then
    fail "The checksum retry ladder is missing ordered marker: $marker"
  fi
  if [ "$retry_line" -le "$previous_retry_line" ]; then
    fail "The checksum retry ladder must stay ordered current, then V49 through V42."
  fi
  previous_retry_line="$retry_line"
done
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
