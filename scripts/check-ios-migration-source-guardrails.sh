#!/usr/bin/env bash
set -euo pipefail

schema_file="apps/ios/Merian/Models/SchemaVersions.swift"
v49_snapshot_file="apps/ios/Merian/Models/Schema/SchemaV49Snapshots.swift"
v49_snapshot_sha256="869fee4639038df74d158fc776b9eed6ccef423ee31aa85a23159162753ad6be"
v50_snapshot_file="apps/ios/Merian/Models/Schema/SchemaV50Snapshots.swift"
v50_snapshot_sha256="17f0f51b01a52a16a72abd2282862fee44adcda6c2166c9349d1560fe1470562"
v50_released_active_snapshot_file="apps/ios/Merian/Models/Schema/SchemaV50ReleasedActiveSnapshots.swift"
v50_released_active_snapshot_sha256="08529c923aba8ce11a4e3ecd2a8b92f9513876f0203bc4cfec1aa2a28423d219"
alias_file="apps/ios/Merian/Models/Aliases.swift"
active_queue_file="apps/ios/Merian/Models/ActiveSchema/OfflineQueuedScan.swift"
active_collection_file="apps/ios/Merian/Models/ActiveSchema/ScanCollection.swift"
active_preference_file="apps/ios/Merian/Models/ActiveSchema/UserSpeciesPreference.swift"
schema_v35_file="apps/ios/Merian/Models/Schema/SchemaV35.swift"
schema_v37_file="apps/ios/Merian/Models/Schema/SchemaV37.swift"
schema_v38_file="apps/ios/Merian/Models/Schema/SchemaV38.swift"
schema_v39_file="apps/ios/Merian/Models/Schema/SchemaV39.swift"
collection_sync_database_file="apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+CollectionSync.swift"
collection_sync_snapshot_file="apps/ios/Merian/Core/Data/OfflineSync/Models/CollectionSyncSnapshot.swift"
collection_sync_endpoint_file="apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+Collections.swift"
test_file="apps/ios/MerianTests/Models/MigrationPlanTests.swift"
recovery_root="apps/ios/Merian/Core/Data/StoreRecovery"
recovery_file="$recovery_root/ModelStoreRecoveryCoordinator.swift"
recovery_models_file="$recovery_root/Models/StoreMigrationModels.swift"
recovery_diagnostic_file="$recovery_root/Models/StartupStoreDiagnostic.swift"
recovery_coding_file="$recovery_root/Models/StoreRecoveryJSONCoding.swift"
recovery_policy_file="$recovery_root/Policies/ModelStoreRecoveryPolicy.swift"
recovery_privacy_file="$recovery_root/Policies/StoreRecoveryPrivacyPolicy.swift"
recovery_manifest_file="$recovery_root/Models/StoreRecoveryManifest.swift"
recovery_archive_file="$recovery_root/Services/StoreRecoveryArtifactArchiver.swift"
recovery_metadata_file="$recovery_root/Services/StoreRecoveryMetadataService.swift"
recovery_test_root="apps/ios/MerianTests/Core/Data/StoreRecovery"
recovery_test_file="$recovery_test_root/ModelStoreRecoveryCoordinatorTests.swift"
recovery_diagnostic_test_file="$recovery_test_root/StartupStoreDiagnosticTests.swift"
recovery_archive_test_file="$recovery_test_root/StoreRecoveryArtifactArchiverTests.swift"
recovery_architecture_test_file="$recovery_test_root/StoreRecoveryArchitectureTests.swift"
recovery_test_support_file="$recovery_test_root/StoreRecoveryTestSupport.swift"
image_recovery_file="apps/ios/Merian/Core/Data/Images/Recovery/LegacyScanMediaRecoveryIndex.swift"
image_test_file="apps/ios/MerianTests/Core/Data/Images/LocalImageLoaderTests.swift"
app_file="apps/ios/Merian/App/MerianApp.swift"
startup_workflow_file=".github/workflows/ios-startup-safety.yml"

if [ ! -f "$schema_file" ]; then
  echo "Missing $schema_file" >&2
  exit 1
fi

if [ ! -f "$v49_snapshot_file" ]; then
  echo "Missing $v49_snapshot_file" >&2
  exit 1
fi

if [ ! -f "$v50_snapshot_file" ]; then
  echo "Missing $v50_snapshot_file" >&2
  exit 1
fi

if [ ! -f "$v50_released_active_snapshot_file" ]; then
  echo "Missing $v50_released_active_snapshot_file" >&2
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

if [ ! -f "$active_collection_file" ]; then
  echo "Missing $active_collection_file" >&2
  exit 1
fi

if [ ! -f "$active_preference_file" ]; then
  echo "Missing $active_preference_file" >&2
  exit 1
fi

for frozen_preference_schema_file in \
  "$schema_v35_file" \
  "$schema_v37_file" \
  "$schema_v38_file" \
  "$schema_v39_file"; do
  if [ ! -f "$frozen_preference_schema_file" ]; then
    echo "Missing $frozen_preference_schema_file" >&2
    exit 1
  fi
done

for collection_sync_file in \
  "$collection_sync_database_file" \
  "$collection_sync_snapshot_file" \
  "$collection_sync_endpoint_file"; do
  if [ ! -f "$collection_sync_file" ]; then
    echo "Missing $collection_sync_file" >&2
    exit 1
  fi
done

if [ ! -f "$test_file" ]; then
  echo "Missing $test_file" >&2
  exit 1
fi

for recovery_source_file in \
  "$recovery_file" \
  "$recovery_models_file" \
  "$recovery_diagnostic_file" \
  "$recovery_coding_file" \
  "$recovery_policy_file" \
  "$recovery_privacy_file" \
  "$recovery_manifest_file" \
  "$recovery_archive_file" \
  "$recovery_metadata_file"; do
  if [ ! -f "$recovery_source_file" ]; then
    echo "Missing $recovery_source_file" >&2
    exit 1
  fi
done

for recovery_test_source_file in \
  "$recovery_test_file" \
  "$recovery_diagnostic_test_file" \
  "$recovery_archive_test_file" \
  "$recovery_architecture_test_file" \
  "$recovery_test_support_file"; do
  if [ ! -f "$recovery_test_source_file" ]; then
    echo "Missing $recovery_test_source_file" >&2
    exit 1
  fi
done

if [ ! -f "$app_file" ]; then
  echo "Missing $app_file" >&2
  exit 1
fi

fail() {
  echo "iOS migration source guardrail failed: $*" >&2
  exit 1
}

actual_v49_snapshot_sha256="$(shasum -a 256 "$v49_snapshot_file" | awk '{print $1}')"
if [ "$actual_v49_snapshot_sha256" != "$v49_snapshot_sha256" ]; then
  fail "V49 frozen snapshot bytes changed. Reconstruct and review the complete released V49 persisted shape before updating its pinned digest."
fi

actual_v50_snapshot_sha256="$(shasum -a 256 "$v50_snapshot_file" | awk '{print $1}')"
if [ "$actual_v50_snapshot_sha256" != "$v50_snapshot_sha256" ]; then
  fail "V50 frozen snapshot bytes changed. Reconstruct and review the complete released V50 persisted shape before updating its pinned digest."
fi

actual_v50_released_active_snapshot_sha256="$(shasum -a 256 "$v50_released_active_snapshot_file" | awk '{print $1}')"
if [ "$actual_v50_released_active_snapshot_sha256" != "$v50_released_active_snapshot_sha256" ]; then
  fail "Released-active V50 frozen snapshot bytes changed. Reconstruct and review the exact processed V50 persisted shape before updating its pinned digest."
fi

contains() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$file"
}

not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
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

printf '%s\n' "$migration_plan_schemas" | grep -Fq "MerianSchemaV49.self" \
  || fail "MerianMigrationPlan.schemas must include MerianSchemaV49.self."
printf '%s\n' "$migration_plan_schemas" | grep -Fq "MerianActiveSchemaV50.self" \
  || fail "MerianMigrationPlan.schemas must include the frozen V50 bridge."
printf '%s\n' "$migration_plan_schemas" | grep -Fq "MerianSchemaV51.self" \
  || fail "MerianMigrationPlan.schemas must finish with the account-scoped V51 schema."
if printf '%s\n' "$migration_plan_schemas" | grep -Fq "MerianSchemaV50.self"; then
  fail "MerianMigrationPlan.schemas must not include the checksum-identical released V50 fixture beside active V50."
fi

for retired_recent_schema in MerianSchemaV43.self MerianSchemaV44.self MerianSchemaV45.self MerianSchemaV46.self MerianSchemaV47.self MerianSchemaV48.self; do
  if printf '%s\n' "$migration_plan_schemas" | grep -Fq "$retired_recent_schema"; then
    fail "MerianMigrationPlan.schemas must omit source-isolated recent schema $retired_recent_schema and remain linear through V42 to V49."
  fi
done

printf '%s\n' "$migration_plan_stages" | grep -Fq "migrateV42toV49" \
  || fail "MerianMigrationPlan.stages must jump from V42 to V49."
printf '%s\n' "$migration_plan_stages" | grep -Fq "migrateV49toV50" \
  || fail "MerianMigrationPlan.stages must advance V49 to the frozen V50 bridge."
printf '%s\n' "$migration_plan_stages" | grep -Fq "migrateV50toV51" \
  || fail "MerianMigrationPlan.stages must discard unowned V50 preferences while advancing to V51."
if printf '%s\n' "$migration_plan_stages" | grep -Fq "migrateV47toV49"; then
  fail "MerianMigrationPlan.stages must not route historical stores through V47."
fi

for source_isolated_stage in migrateV42toV43 migrateV43toV49 migrateV44toV49 migrateV45toV49 migrateV46toV49 migrateV48toV49 migrateV43toV47 migrateV44toV47 migrateV45toV47 migrateV46toV47 migrateV45toV46; do
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
  || fail "Missing original V50 schema."
contains "$schema_file" "enum MerianReleasedActiveSchemaV50: VersionedSchema" \
  || fail "Missing processed-release V50 schema."
contains "$schema_file" "enum MerianActiveSchemaV50: VersionedSchema" \
  || fail "Missing original frozen V50 bridge."
contains "$schema_file" "enum MerianSchemaV51: VersionedSchema" \
  || fail "Missing account-scoped V51 schema."

v49_schema="$(extract_block "enum MerianSchemaV49: VersionedSchema" "enum MerianSchemaV50: VersionedSchema")"
for frozen_model in LocalScanRecord OfflineQueuedScan CapturedMediaEntry ScanCollection PendingCloudDeletionTask UserSpeciesPreference OfflineJobRecord OfflineQueueEvent; do
  printf '%s\n' "$v49_schema" | grep -Fq "MerianSchemaV49.$frozen_model.self" \
    || fail "V49 must reference its frozen MerianSchemaV49.$frozen_model snapshot."
  contains "$v49_snapshot_file" "final class $frozen_model" \
    || fail "V49 snapshot file must define $frozen_model."
done
if printf '%s\n' "$v49_schema" | grep -Fq "MerianSchemaV49Offline"; then
  fail "V49 must not alias an active model through a top-level bridge."
fi
not_contains "$v49_snapshot_file" "typealias"
contains "$v49_snapshot_file" "[MerianSchemaV49.CapturedMediaEntry]?" \
  || fail "V49 relationship endpoints must use the frozen captured-media type."
contains "$v49_snapshot_file" "[MerianSchemaV49.ScanCollection]?" \
  || fail "V49 LocalScanRecord.collections must use the frozen collection type."
contains "$v49_snapshot_file" "inverse: \\MerianSchemaV49.LocalScanRecord.collections" \
  || fail "V49 ScanCollection must use the frozen inverse relationship endpoint."

v50_schema="$(extract_block "enum MerianSchemaV50: VersionedSchema" "enum MerianReleasedActiveSchemaV50: VersionedSchema")"
for frozen_model in LocalScanRecord OfflineQueuedScan CapturedMediaEntry ScanCollection PendingCloudDeletionTask UserSpeciesPreference OfflineJobRecord OfflineQueueEvent; do
  printf '%s\n' "$v50_schema" | grep -Fq "MerianSchemaV50.$frozen_model.self" \
    || fail "V50 must reference its frozen MerianSchemaV50.$frozen_model snapshot."
  contains "$v50_snapshot_file" "final class $frozen_model" \
    || fail "V50 snapshot file must define $frozen_model."
done
not_contains "$v50_snapshot_file" "typealias"
contains "$v50_snapshot_file" "[MerianSchemaV50.CapturedMediaEntry]?" \
  || fail "V50 relationship endpoints must use the frozen captured-media type."
contains "$v50_snapshot_file" "[MerianSchemaV50.ScanCollection]?" \
  || fail "V50 LocalScanRecord.collections must use the frozen collection type."
contains "$v50_snapshot_file" "inverse: \\MerianSchemaV50.LocalScanRecord.collections" \
  || fail "V50 ScanCollection must use the frozen inverse relationship endpoint."
contains "$v50_snapshot_file" "var isDeleted: Bool" \
  || fail "V50 must retain its historical ScanCollection.isDeleted persisted property."
not_contains "$v50_snapshot_file" "isPendingDeletion"

released_active_v50_schema="$(extract_block "enum MerianReleasedActiveSchemaV50: VersionedSchema" "enum MerianActiveSchemaV50: VersionedSchema")"
for frozen_model in LocalScanRecord OfflineQueuedScan CapturedMediaEntry ScanCollection PendingCloudDeletionTask UserSpeciesPreference OfflineJobRecord OfflineQueueEvent; do
  printf '%s\n' "$released_active_v50_schema" | grep -Fq "MerianReleasedActiveSchemaV50.$frozen_model.self" \
    || fail "Released-active V50 must reference its frozen MerianReleasedActiveSchemaV50.$frozen_model snapshot."
  contains "$v50_released_active_snapshot_file" "final class $frozen_model" \
    || fail "Released-active V50 snapshot file must define $frozen_model."
done
printf '%s\n' "$released_active_v50_schema" | grep -Fq "MerianReleasedActiveSchemaV50.OfflineQueuedScanGoalHint.self" \
  || fail "Released-active V50 must reference its frozen goal-hint snapshot."
not_contains "$v50_released_active_snapshot_file" "typealias"
contains "$v50_released_active_snapshot_file" "[MerianReleasedActiveSchemaV50.CapturedMediaEntry]?" \
  || fail "Released-active V50 relationship endpoints must use its frozen captured-media type."
contains "$v50_released_active_snapshot_file" "[MerianReleasedActiveSchemaV50.ScanCollection]?" \
  || fail "Released-active V50 LocalScanRecord.collections must use its frozen collection type."
contains "$v50_released_active_snapshot_file" "inverse: \\MerianReleasedActiveSchemaV50.LocalScanRecord.collections" \
  || fail "Released-active V50 ScanCollection must use its frozen inverse relationship endpoint."
contains "$v50_released_active_snapshot_file" "@Attribute(originalName: \"isDeleted\")" \
  || fail "Released-active V50 must preserve the processed release's collection rename mapping."
contains "$v50_released_active_snapshot_file" "var isPendingDeletion: Bool" \
  || fail "Released-active V50 must retain its processed Swift collection tombstone name."
not_contains "$v50_released_active_snapshot_file" "var isDeleted: Bool"

active_v50_schema="$(extract_block "enum MerianActiveSchemaV50: VersionedSchema" "enum MerianSchemaV51: VersionedSchema")"
for frozen_model in LocalScanRecord OfflineQueuedScan CapturedMediaEntry ScanCollection PendingCloudDeletionTask UserSpeciesPreference OfflineJobRecord OfflineQueueEvent; do
  printf '%s\n' "$active_v50_schema" | grep -Fq "MerianSchemaV50.$frozen_model.self" \
    || fail "The V50 bridge must reference frozen MerianSchemaV50.$frozen_model."
done
printf '%s\n' "$active_v50_schema" | grep -Fq "MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self" \
  || fail "The V50 bridge must preserve its released goal-hint model owner."
contains "$schema_file" "MerianSchemaV49.CapturedMediaEntry.makeEntries(" \
  || fail "V49 queue repair must create frozen V49 captured-media rows."
contains "$test_file" "MerianSchemaV49.OfflineQueuedScan(id: queuedId)" \
  || fail "V49 disk fixtures must be created with the frozen V49 queue model."
contains "$alias_file" "typealias CurrentSchema = MerianSchemaV51" \
  || fail "CurrentSchema must remain aligned with V51."
contains "$alias_file" "typealias ActiveOfflineQueuedScanGoalHint = MerianActiveSchemaV50.OfflineQueuedScanGoalHint" \
  || fail "The active goal-hint alias must remain aligned with active V50."
contains "$schema_file" "static let migrateV50toV51 = MigrationStage.custom" \
  || fail "Missing V50 to V51 account-partition migration."
contains "$schema_file" "static let migrateReleasedActiveV50toV51 = MigrationStage.custom" \
  || fail "Missing released-active V50 to V51 account-partition migration."
contains "$schema_file" "FetchDescriptor<MerianReleasedActiveSchemaV50.UserSpeciesPreference>" \
  || fail "Released-active V50 to V51 must delete its frozen unowned preference rows."
contains "$schema_file" "FetchDescriptor<MerianSchemaV51UserSpeciesPreference>" \
  || fail "V50 to V51 must fetch the version-pinned V51 preference model."
contains "$schema_file" 'predicate: #Predicate { $0.ownerUserId == "" }' \
  || fail "V50 to V51 must select only unowned legacy preference rows."
contains "$schema_file" "context.delete(preference)" \
  || fail "V50 to V51 must discard unowned legacy preference rows."
contains "$active_preference_file" "@Attribute(.unique) public var id: String" \
  || fail "V51 preferences must use an account-qualified unique identifier."
contains "$active_preference_file" "public var ownerUserId: String" \
  || fail "V51 preferences must persist their account owner."
not_contains "$active_preference_file" "@Attribute(.unique) public var scientificName"

# V35 through V48 shipped the original three-field preference model. Keep
# every historical schema on that immutable alias chain so later active-model
# changes cannot rewrite a released source checksum.
contains "$schema_v35_file" "MerianSchemaV35.UserSpeciesPreference.self" \
  || fail "V35 must resolve its preference model through the frozen schema alias."
contains "$schema_v37_file" "typealias UserSpeciesPreference = MerianSchemaV36.UserSpeciesPreference" \
  || fail "V37 must retain the frozen preference model."
contains "$schema_v38_file" "typealias UserSpeciesPreference = MerianSchemaV37.UserSpeciesPreference" \
  || fail "V38 must retain the frozen preference model."
contains "$schema_v39_file" "typealias UserSpeciesPreference = MerianSchemaV38.UserSpeciesPreference" \
  || fail "V39 must retain the frozen preference model."
for frozen_preference_alias in \
  "typealias UserSpeciesPreference = MerianSchemaV39.UserSpeciesPreference" \
  "typealias UserSpeciesPreference = MerianSchemaV40.UserSpeciesPreference" \
  "typealias UserSpeciesPreference = MerianSchemaV41.UserSpeciesPreference" \
  "typealias UserSpeciesPreference = MerianSchemaV42.UserSpeciesPreference" \
  "typealias UserSpeciesPreference = MerianSchemaV43.UserSpeciesPreference" \
  "typealias UserSpeciesPreference = MerianSchemaV44.UserSpeciesPreference" \
  "typealias UserSpeciesPreference = MerianSchemaV45.UserSpeciesPreference" \
  "typealias UserSpeciesPreference = MerianSchemaV46.UserSpeciesPreference" \
  "typealias UserSpeciesPreference = MerianSchemaV47.UserSpeciesPreference" \
  "typealias UserSpeciesPreference = MerianSchemaV48.UserSpeciesPreference"; do
  contains "$schema_file" "$frozen_preference_alias" \
    || fail "Missing historical frozen preference alias: $frozen_preference_alias"
done
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
  || fail "Missing source-isolated V49 to V51 migration plan."
contains "$schema_file" "enum MerianRecentV50MigrationPlan" \
  || fail "Missing source-isolated V50 to V51 migration plan."
contains "$schema_file" "enum MerianReleasedActiveV50MigrationPlan" \
  || fail "Missing source-isolated released-active V50 to V51 migration plan."
not_contains "$schema_file" "static let migrateV43toV47"
not_contains "$schema_file" "static let migrateV44toV47"
not_contains "$schema_file" "static let migrateV45toV47"
not_contains "$schema_file" "static let migrateV46toV47"

contains "$active_queue_file" "@Attribute public var queueAttemptCount: Int = 0" \
  || fail "Active V51 OfflineQueuedScan.queueAttemptCount must remain non-optional to preserve current-store compatibility."
contains "$active_queue_file" "@Attribute public var queueUpdatedAt: Date = Date()" \
  || fail "Active V51 OfflineQueuedScan.queueUpdatedAt must remain non-optional to preserve current-store compatibility."
contains "$active_queue_file" "@Attribute public var queueNeedsAttention: Bool = false" \
  || fail "Active V51 OfflineQueuedScan.queueNeedsAttention must remain non-optional to preserve current-store compatibility."
contains "$active_queue_file" "@Attribute public var queueSchemaRepairGeneration: Int = 1" \
  || fail "Active V51 OfflineQueuedScan.queueSchemaRepairGeneration must retain the released compatibility field."
not_contains "$active_queue_file" "queueAttemptCount: Int?"
not_contains "$active_queue_file" "queueUpdatedAt: Date?"
not_contains "$active_queue_file" "queueNeedsAttention: Bool?"
not_contains "$active_queue_file" "queueSchemaRepairGeneration: Int?"

contains "$active_collection_file" "@Attribute(originalName: \"isDeleted\")" \
  || fail "Active V51 ScanCollection.isPendingDeletion must preserve the released V50 isDeleted column mapping."
contains "$active_collection_file" "public var isPendingDeletion: Bool = false" \
  || fail "Active V51 ScanCollection must expose an unambiguous persistent tombstone property."
not_contains "$active_collection_file" "public var isDeleted: Bool"
contains "$collection_sync_database_file" "isPendingDeletion: collection.isPendingDeletion" \
  || fail "Collection synchronization must project the active V50 tombstone into its immutable snapshot."
contains "$collection_sync_snapshot_file" "let isPendingDeletion: Bool" \
  || fail "CollectionSyncSnapshot must preserve the active V50 tombstone value across the persistence boundary."
contains "$collection_sync_endpoint_file" "case isDeleted = \"is_deleted\"" \
  || fail "Collection synchronization must preserve the is_deleted wire key."
contains "$collection_sync_endpoint_file" "isDeleted: snapshot.isPendingDeletion" \
  || fail "Collection synchronization must map the V50 tombstone snapshot to the is_deleted wire value."

recent_v42_plan="$(extract_block "enum MerianRecentV42MigrationPlan" "enum MerianRecentV43MigrationPlan")"
recent_v43_plan="$(extract_block "enum MerianRecentV43MigrationPlan" "enum MerianRecentV44MigrationPlan")"
recent_v44_plan="$(extract_block "enum MerianRecentV44MigrationPlan" "enum MerianRecentV45MigrationPlan")"
recent_v45_plan="$(extract_block "enum MerianRecentV45MigrationPlan" "enum MerianRecentV46MigrationPlan")"
recent_v46_plan="$(extract_block "enum MerianRecentV46MigrationPlan" "enum MerianRecentV47MigrationPlan")"
recent_v47_plan="$(extract_block "enum MerianRecentV47MigrationPlan" "enum MerianRecentV48MigrationPlan")"
recent_v48_plan="$(extract_block "enum MerianRecentV48MigrationPlan" "enum MerianOptionalQueueV48RecoveryPlan")"
optional_v48_plan="$(extract_block "enum MerianOptionalQueueV48RecoveryPlan" "enum MerianRecentV49MigrationPlan")"
recent_v49_plan="$(extract_block "enum MerianRecentV49MigrationPlan" "enum MerianRecentV50MigrationPlan")"
recent_v50_plan="$(extract_block "enum MerianRecentV50MigrationPlan" "enum MerianReleasedActiveV50MigrationPlan")"
released_active_v50_plan="$(extract_block "enum MerianReleasedActiveV50MigrationPlan" "__MERIAN_STOP__")"

require_v51_tail() {
  local plan_text="$1"
  local plan_name="$2"

  printf '%s\n' "$plan_text" | grep -Fq "MerianActiveSchemaV50.self" \
    || fail "$plan_name must include the frozen V50 bridge."
  printf '%s\n' "$plan_text" | grep -Fq "MerianSchemaV51.self" \
    || fail "$plan_name must include the V51 target."
  printf '%s\n' "$plan_text" | grep -Fq "MerianMigrationPlan.migrateV49toV50" \
    || fail "$plan_name must include the shared V49 to V50 stage."
  printf '%s\n' "$plan_text" | grep -Fq "MerianMigrationPlan.migrateV50toV51" \
    || fail "$plan_name must include the shared V50 to V51 stage."
}

require_v51_tail "$recent_v42_plan" "Recent V42 plan"
require_v51_tail "$recent_v43_plan" "Recent V43 plan"
require_v51_tail "$recent_v44_plan" "Recent V44 plan"
require_v51_tail "$recent_v45_plan" "Recent V45 plan"
require_v51_tail "$recent_v46_plan" "Recent V46 plan"
require_v51_tail "$recent_v47_plan" "Recent V47 plan"
require_v51_tail "$recent_v48_plan" "Recent V48 plan"
require_v51_tail "$optional_v48_plan" "Optional-queue V48 plan"
require_v51_tail "$recent_v49_plan" "Recent V49 plan"

printf '%s\n' "$recent_v50_plan" | grep -Fq "MerianActiveSchemaV50.self" \
  || fail "Recent V50 plan must include the frozen V50 source bridge."
printf '%s\n' "$recent_v50_plan" | grep -Fq "MerianSchemaV51.self" \
  || fail "Recent V50 plan must target V51."
printf '%s\n' "$recent_v50_plan" | grep -Fq "MerianMigrationPlan.migrateV50toV51" \
  || fail "Recent V50 plan must run exactly the account-partition migration."
if printf '%s\n' "$recent_v50_plan" | grep -Fq "migrateV49toV50"; then
  fail "Recent V50 plan must not validate the V49 source."
fi

printf '%s\n' "$released_active_v50_plan" | grep -Fq "MerianReleasedActiveSchemaV50.self" \
  || fail "Released-active V50 plan must include its exact frozen source graph."
printf '%s\n' "$released_active_v50_plan" | grep -Fq "MerianSchemaV51.self" \
  || fail "Released-active V50 plan must target V51."
printf '%s\n' "$released_active_v50_plan" | grep -Fq "MerianMigrationPlan.migrateReleasedActiveV50toV51" \
  || fail "Released-active V50 plan must run exactly its account-partition migration."
if printf '%s\n' "$released_active_v50_plan" | grep -Fq "migrateV49toV50"; then
  fail "Released-active V50 plan must not validate the V49 source."
fi

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
if printf '%s\n' "$recent_v49_plan" | grep -Fq "MerianSchemaV50.self"; then
  fail "Recent V49 plan must not pair the checksum-identical released and active V50 schemas."
fi

not_contains "$test_file" "removeSQLiteStore"
not_contains "$test_file" "URL.cachesDirectory"
not_contains "$test_file" "FileManager.default.removeItem(at: url)"
not_contains "$test_file" "Duplicate version checksums across stages detected"
contains "$test_file" "keepSQLiteStoreForProcessLifetime" \
  || fail "MigrationPlanTests must keep disk-backed migration stores alive for the process lifetime."
contains "$test_file" "activeOfflineQueuedScanKeepsDurableRetryFieldsNonOptional" \
  || fail "MigrationPlanTests must guard active queue retry fields against optionality changes."
contains "$test_file" "knownGoodV48RequiredValueFailureUsesLegacyRescue" \
  || fail "MigrationPlanTests must cover the known-good V48 legacy rescue fixture."
contains "$test_file" "optionalQueueV48RequiredValueFailureUsesLegacyRescue" \
  || fail "MigrationPlanTests must cover the accidental optional-queue V48 legacy rescue fixture."
contains "$test_file" "migrationFromV42ToCurrentSchemaUsesSourceIsolatedPlan" \
  || fail "MigrationPlanTests must cover the V42 source-isolated recovery fixture from startup diagnostics."
contains "$test_file" "recentV49MigrationPlanRunsOnlyRequiredForwardHops" \
  || fail "MigrationPlanTests must lock the source-isolated V49 to V51 plan shape."
contains "$test_file" "recentV50MigrationPlanOnlyRunsAccountPartitionMigration" \
  || fail "MigrationPlanTests must lock the source-isolated V50 to V51 plan shape."
contains "$test_file" "releasedActiveV50MigrationPlanOnlyRunsAccountPartitionMigration" \
  || fail "MigrationPlanTests must lock the released-active V50 to V51 plan shape."
contains "$test_file" "migrationFromV49UsesDiskMetadataSelectionAndPreservesQueueData" \
  || fail "MigrationPlanTests must exercise a disk-backed V49 to V51 migration."
contains "$test_file" "let decision = ModelStoreRecoveryCoordinator.migrationDecision(" \
  || fail "The V49 disk fixture must exercise production metadata-based plan selection."
contains "$test_file" "#expect(decision.storedSchemaMajorVersion == 49)" \
  || fail "The V49 disk fixture must verify the emitted on-disk schema major."
contains "$test_file" "#expect(decision.hint == .recentSource(.v49))" \
  || fail "The V49 disk fixture must select the source-isolated V49 startup path."
contains "$test_file" "migrationPlan: MerianRecentV49MigrationPlan.self" \
  || fail "The V49 disk fixture must open with the production V49 migration plan."
contains "$test_file" "releasedActiveV50StoreMatchesDeviceSignatureAndMigratesLosslessly" \
  || fail "MigrationPlanTests must migrate the processed-release V50 fixture without rebuilding the library."
contains "$test_file" "frozenV50StoreMigratesAndDiscardsUnownedPreferences" \
  || fail "MigrationPlanTests must retain coverage for the original frozen V50 graph."
contains "$test_file" "MerianReleasedActiveSchemaV50.ScanCollection(" \
  || fail "The processed-release V50 disk fixture must use its exact frozen collection model."
contains "$test_file" "MerianSchemaV50.ScanCollection(" \
  || fail "The original V50 disk fixture must create collections with the frozen V50 model."
contains "$test_file" "#expect(decision.storedSchemaMajorVersion == 50)" \
  || fail "The V50 disk fixture must verify the emitted on-disk schema major."
contains "$test_file" "#expect(decision.hint == .recentSource(.v50))" \
  || fail "The released V50 fixture must select the source-isolated V50 startup path."
contains "$test_file" "migrationPlan: MerianRecentV50MigrationPlan.self" \
  || fail "The original V50 fixture must use its source-isolated migration plan."
contains "$test_file" "migrationPlan: MerianReleasedActiveV50MigrationPlan.self" \
  || fail "The processed-release V50 fixture must use its source-isolated migration plan."
contains "$test_file" "#expect(deletedCollection.isPendingDeletion)" \
  || fail "The V50 disk fixture must verify that true tombstones survive the Swift property rename."
contains "$recovery_models_file" "enum RecentSourceSchema: Int, CaseIterable, Equatable" \
  || fail "Store recovery must model recent source schemas as an exhaustive enum."
for recent_major in $(seq 42 50); do
  contains "$recovery_models_file" "case v${recent_major} = ${recent_major}" \
    || fail "RecentSourceSchema must include V${recent_major}."
done
contains "$recovery_policy_file" "RecentSourceSchema(rawValue: storedSchemaMajorVersion)" \
  || fail "Store recovery must classify metadata through the exhaustive recent-source enum."
contains "$recovery_metadata_file" "releasedActiveV50ChecksumFingerprint =" \
  && contains "$recovery_metadata_file" "\"9a0841f675241b21f5ad5c10\"" \
  || fail "Store recovery must recognize the processed-release V50 checksum from device diagnostics."
contains "$recovery_metadata_file" "frozenSnapshotV50ChecksumFingerprint =" \
  && contains "$recovery_metadata_file" "\"b9fa43ac9095301ecdce20e5\"" \
  || fail "Store recovery must recognize the original frozen V50 checksum."
contains "$recovery_test_file" "testRecognizesReleasedActiveV50ModelChecksum" \
  || fail "Store recovery tests must lock processed-release V50 checksum classification."
contains "$recovery_test_file" "testSourceIsolatedSchemasAreConsecutiveAndEndAtCurrentPredecessor" \
  || fail "Store recovery tests must fail when a future schema bump omits its immediate-predecessor plan."
contains "$app_file" "private static func makePersistentContainerForRecentSource(" \
  || fail "MerianApp must dispatch recent sources through an exhaustive plan selector."
recent_source_dispatch="$(
  awk '
    /private static func makePersistentContainerForRecentSource\(/ { printing = 1 }
    printing { print }
    printing && /forStoreMigrationHint hint:/ { exit }
  ' "$app_file"
)"
for recent_major in $(seq 42 50); do
  printf '%s\n' "$recent_source_dispatch" | grep -Fq "case .v${recent_major}:" \
    || fail "MerianApp recent-source dispatch must handle V${recent_major} explicitly."
done
if printf '%s\n' "$recent_source_dispatch" | grep -Eq '^[[:space:]]*(@unknown[[:space:]]+)?default:'; then
  fail "MerianApp recent-source dispatch must remain compiler-exhaustive without a default branch."
fi
not_contains "$app_file" "recent-fallback-full"
contains "$app_file" "named: \"recent-v49\"" \
  || fail "MerianApp must record the selected recent-v49 startup attempt."
contains "$app_file" "named: \"recent-v50-released-active\"" \
  || fail "MerianApp must record the selected processed-release V50 startup attempt."
contains "$app_file" "named: \"recent-v50-frozen-snapshot\"" \
  || fail "MerianApp must record the selected original V50 startup attempt."
contains "$app_file" "named: \"checksum-recent-v49\"" \
  || fail "The checksum retry ladder must try the V49 plan before older sources."
contains "$app_file" "named: \"checksum-recent-v50-released-active\"" \
  || fail "The checksum retry ladder must try the processed-release V50 plan before V49."
contains "$app_file" "named: \"checksum-recent-v50-frozen-snapshot\"" \
  || fail "The checksum retry ladder must try the original V50 plan before V49."
checksum_retry_dispatch="$(
  awk '
    /private static func makePersistentContainerRetryingChecksumRepresentative\(/ { printing = 1 }
    printing { print }
    printing && /private static func makePersistentContainerForV48Source\(/ { exit }
  ' "$app_file"
)"
checksum_retry_markers=(
  'named: "checksum-current-store"'
  'named: "checksum-recent-v50-released-active"'
  'named: "checksum-recent-v50-frozen-snapshot"'
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
    fail "The checksum retry ladder must stay ordered current, both V50 graphs, then V49 through V42."
  fi
  previous_retry_line="$retry_line"
done
contains "$recovery_policy_file" "shouldRescueStoreAfterMigrationFailure" \
  || fail "Store recovery must keep the legacy migration rescue decision."
contains "$recovery_file" "groupContainer: .automatic" \
  || fail "Store recovery must resolve the persistent URL through SwiftData's automatic App Group configuration."
if rg -Fq -- 'URL.applicationSupportDirectory.appending(path: "default.store")' "$recovery_root"; then
  fail "Store recovery must not reconstruct the SwiftData store under Application Support."
fi
contains "$app_file" "ModelStoreRecoveryCoordinator.productionStoreConfiguration(for: schema)" \
  || fail "MerianApp and recovery must share one production SwiftData configuration factory."
contains "$app_file" "let storeURL = ModelStoreRecoveryCoordinator.defaultStoreURL()" \
  || fail "MerianApp must inspect the exact SwiftData-configured store URL before migration selection."
contains "$recovery_archive_file" "store-rescue" \
  || fail "Store recovery must archive unrecoverable legacy stores under store-rescue."
contains "$recovery_archive_file" "legacy_migration_rescue" \
  || fail "Store recovery manifests must distinguish legacy migration rescue from corruption quarantine."
contains "$recovery_archive_file" "StoreRecoveryPrivacyPolicy.sanitizedErrorText" \
  || fail "Store recovery manifests must sanitize error descriptions before writing them."
contains "$recovery_archive_file" "StoreRecoveryPrivacyPolicy.sanitizedErrorDomain" \
  || fail "Store recovery manifests must sanitize non-allowlisted error domains before writing them."
contains "$recovery_archive_file" "try writeManifest(" \
  || fail "Store recovery must not report archive success before the manifest is durably written."
contains "$recovery_archive_file" "rollback(" \
  || fail "Store recovery must roll moved artifacts back after an incomplete archive."
contains "$recovery_privacy_file" "static func sanitizedErrorText" \
  || fail "Store recovery privacy policy must retain the manifest-error sanitizer."
contains "$recovery_metadata_file" "StoreRecoveryPrivacyPolicy.sanitizedMetadataString" \
  || fail "Startup diagnostics must fingerprint arbitrary Core Data metadata strings."
contains "$recovery_manifest_file" "schemaVersion: Int = 2" \
  || fail "Store recovery manifests must use the current schema version."
contains "$recovery_diagnostic_file" "schemaVersion: Int = 2" \
  || fail "Startup store diagnostics must use the current schema version."
contains "$app_file" "legacy_store_rescued" \
  || fail "MerianApp must recover legacy migration failures with legacy_store_rescued telemetry."
contains "$app_file" "post-migration-rescue-current-store" \
  || fail "MerianApp must reopen a fresh persistent store after legacy migration rescue."
contains "$recovery_test_file" "testRescuesLegacyMigrationFailuresEvenWhenSwiftDataErrorIsGeneric" \
  || fail "ModelStoreRecoveryCoordinatorTests must cover generic SwiftDataError legacy rescue."
contains "$recovery_archive_test_file" "testRescueArchivesStoreArtifacts" \
  || fail "StoreRecoveryArtifactArchiverTests must cover store-rescue archive manifests."
contains "$recovery_archive_test_file" "testQuarantineWritesPIISafeRecoveryManifest" \
  || fail "Store recovery tests must prove manifest error text is privacy-safe."
contains "$recovery_archive_test_file" "testArchiveRollsBackAllArtifactsWhenMoveFailsAfterMutation" \
  || fail "Store recovery tests must cover rollback after a partially completed move."
contains "$recovery_archive_test_file" "testArchiveRollsBackAllArtifactsWhenManifestWriteFails" \
  || fail "Store recovery tests must cover rollback after a failed manifest write."
contains "$recovery_architecture_test_file" "testStoreRecoveryTestsUseMirroredOwnership" \
  || fail "Store recovery architecture tests must freeze mirrored test ownership."
contains "$recovery_test_file" "testRecoveryStoreURLMatchesSwiftDataAutomaticConfiguration" \
  || fail "ModelStoreRecoveryCoordinatorTests must keep recovery aligned with SwiftData's configured store URL."
contains "$recovery_diagnostic_test_file" "testFreshStoreDiagnosticDoesNotReportMetadataReadFailure" \
  || fail "Fresh-store diagnostics must not report the expected absence of metadata as an error."
contains "$recovery_diagnostic_test_file" "testStoreMetadataStringsAreFingerprintedBeforeDiagnosticsPersist" \
  || fail "Startup diagnostics must prove arbitrary metadata strings cannot reach persistence or telemetry."
contains "$test_file" "currentSchemaFreshDiskStoreOpensWithoutMigrationPlan" \
  || fail "MigrationPlanTests must prove a fresh current-schema disk store can reopen without a migration plan."
contains "$image_recovery_file" "LegacyScanMediaRecoveryStoreLocator.storeURLs" \
  || fail "Rescue-media lookup must use the configured and legacy store locator."
contains "$image_test_file" "legacyRecoveryStoreLocatorPrefersConfiguredRootAndNewestArchives" \
  || fail "LocalImageLoaderTests must keep configured-root rescue archives ahead of legacy archives."
contains "$startup_workflow_file" "-only-testing:merianTests/LocalImageLoaderTests" \
  || fail "Startup Safety must execute the rescue-store locator regression suite."
contains "$startup_workflow_file" "apps/ios/Merian/Models/Schema/SchemaV50ReleasedActiveSnapshots.swift" \
  || fail "Startup Safety path filters must include the processed-release V50 snapshot."

echo "iOS migration source guardrails passed."
