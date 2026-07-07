#!/usr/bin/env bash
set -euo pipefail

schema_file="apps/ios/Merian/Models/SchemaVersions.swift"
test_file="apps/ios/MerianTests/Models/MigrationPlanTests.swift"

if [ ! -f "$schema_file" ]; then
  echo "Missing $schema_file" >&2
  exit 1
fi

if [ ! -f "$test_file" ]; then
  echo "Missing $test_file" >&2
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
    in_stages && /private static func initializeV48OfflineQueueRecords/ { exit }
  ' "$schema_file"
)"

printf '%s\n' "$migration_plan_schemas" | grep -Fq "MerianSchemaV43.self" \
  || fail "MerianMigrationPlan.schemas must include MerianSchemaV43.self."
printf '%s\n' "$migration_plan_schemas" | grep -Fq "MerianSchemaV47.self" \
  || fail "MerianMigrationPlan.schemas must include MerianSchemaV47.self."
printf '%s\n' "$migration_plan_schemas" | grep -Fq "MerianSchemaV48.self" \
  || fail "MerianMigrationPlan.schemas must include MerianSchemaV48.self."

for retired_recent_schema in MerianSchemaV44.self MerianSchemaV45.self MerianSchemaV46.self; do
  if printf '%s\n' "$migration_plan_schemas" | grep -Fq "$retired_recent_schema"; then
    fail "MerianMigrationPlan.schemas must omit duplicate-prone $retired_recent_schema."
  fi
done

printf '%s\n' "$migration_plan_stages" | grep -Fq "migrateV43toV47" \
  || fail "MerianMigrationPlan.stages must jump from V43 to V47."
printf '%s\n' "$migration_plan_stages" | grep -Fq "migrateV47toV48" \
  || fail "MerianMigrationPlan.stages must finish with V47 to V48."

for source_isolated_stage in migrateV45toV48 migrateV46toV48 migrateV45toV47 migrateV46toV47 migrateV45toV46; do
  if printf '%s\n' "$migration_plan_stages" | grep -Fq "$source_isolated_stage"; then
    fail "MerianMigrationPlan.stages must not include source-isolated or duplicate recent stage $source_isolated_stage."
  fi
done

contains "$schema_file" "static let migrateV45toV48 = MigrationStage.custom" \
  || fail "Missing source-isolated V45 to V48 migration."
contains "$schema_file" "fromVersion: MerianSchemaV45.self" \
  || fail "V45 to V48 migration must use MerianSchemaV45 as the source."
contains "$schema_file" "static let migrateV46toV48 = MigrationStage.custom" \
  || fail "Missing source-isolated V46 to V48 migration."
contains "$schema_file" "fromVersion: MerianSchemaV46.self" \
  || fail "V46 to V48 migration must use MerianSchemaV46 as the source."
contains "$schema_file" "try initializeV48OfflineQueueRecords(in: context, stage: \"V45->V48 didMigrate\")" \
  || fail "V45 to V48 migration must use the durable V48 queue backfill."
contains "$schema_file" "try initializeV48OfflineQueueRecords(in: context, stage: \"V46->V48 didMigrate\")" \
  || fail "V46 to V48 migration must use the durable V48 queue backfill."
not_contains "$schema_file" "static let migrateV45toV47"
not_contains "$schema_file" "static let migrateV46toV47"

recent_v45_plan="$(extract_block "enum MerianRecentV45MigrationPlan" "enum MerianRecentV46MigrationPlan")"
recent_v46_plan="$(extract_block "enum MerianRecentV46MigrationPlan" "enum MerianRecentV47MigrationPlan")"
recent_v47_plan="$(extract_block "enum MerianRecentV47MigrationPlan" "__MERIAN_STOP__")"

printf '%s\n' "$recent_v45_plan" | grep -Fq "MerianSchemaV45.self" \
  || fail "Recent V45 plan must include MerianSchemaV45."
printf '%s\n' "$recent_v45_plan" | grep -Fq "MerianSchemaV48.self" \
  || fail "Recent V45 plan must target V48."
printf '%s\n' "$recent_v45_plan" | grep -Fq "MerianMigrationPlan.migrateV45toV48" \
  || fail "Recent V45 plan must run migrateV45toV48."
if printf '%s\n' "$recent_v45_plan" | grep -Fq "MerianSchemaV47.self"; then
  fail "Recent V45 plan must skip V47."
fi

printf '%s\n' "$recent_v46_plan" | grep -Fq "MerianSchemaV46.self" \
  || fail "Recent V46 plan must include MerianSchemaV46."
printf '%s\n' "$recent_v46_plan" | grep -Fq "MerianSchemaV48.self" \
  || fail "Recent V46 plan must target V48."
printf '%s\n' "$recent_v46_plan" | grep -Fq "MerianMigrationPlan.migrateV46toV48" \
  || fail "Recent V46 plan must run migrateV46toV48."
if printf '%s\n' "$recent_v46_plan" | grep -Fq "MerianSchemaV45.self"; then
  fail "Recent V46 plan must not use the V45 source representative."
fi

printf '%s\n' "$recent_v47_plan" | grep -Fq "MerianSchemaV47.self" \
  || fail "Recent V47 plan must include MerianSchemaV47."
printf '%s\n' "$recent_v47_plan" | grep -Fq "MerianMigrationPlan.migrateV47toV48" \
  || fail "Recent V47 plan must run migrateV47toV48."

not_contains "$test_file" "removeSQLiteStore"
not_contains "$test_file" "URL.cachesDirectory"
not_contains "$test_file" "FileManager.default.removeItem(at: url)"
not_contains "$test_file" "Duplicate version checksums across stages detected"
contains "$test_file" "keepSQLiteStoreForProcessLifetime" \
  || fail "MigrationPlanTests must keep disk-backed migration stores alive for the process lifetime."

echo "iOS migration source guardrails passed."
