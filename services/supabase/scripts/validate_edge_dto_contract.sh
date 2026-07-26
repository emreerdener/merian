#!/usr/bin/env bash
set -euo pipefail

dto_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dto_repository_root="$(cd -- "$dto_script_dir/../../.." && pwd)"
cd "$dto_repository_root"

# The compiler package can inspect process environment while resolving its local
# standard-library files. Keep that access explicit and separate from the Edge
# Function runtime dependency graph.
dto_validator_env_allowlist="TSC_WATCHFILE,TSC_NONPOLLING_WATCHER,TSC_WATCHDIRECTORY,NODE_INSPECTOR_IPC,VSCODE_INSPECTOR_OPTIONS,TSC_WATCH_POLLINGINTERVAL_LOW,TSC_WATCH_POLLINGINTERVAL_MEDIUM,TSC_WATCH_POLLINGINTERVAL_HIGH,TSC_WATCH_POLLINGCHUNKSIZE_LOW,TSC_WATCH_POLLINGCHUNKSIZE_MEDIUM,TSC_WATCH_POLLINGCHUNKSIZE_HIGH,TSC_WATCH_UNCHANGEDPOLLTHRESHOLDS_LOW,TSC_WATCH_UNCHANGEDPOLLTHRESHOLDS_MEDIUM,TSC_WATCH_UNCHANGEDPOLLTHRESHOLDS_HIGH,NODE_ENV"

# The schema and complete production Swift source graph are the only repository
# inputs. The graph-wide read is required to catch custom decoder/CodingKeys
# declarations placed in extensions outside InferenceEdgeDTOs.swift.
dto_validator_read_allowlist="services/supabase/functions/_shared/identify/schema.ts,apps/ios/Merian"

deno test --frozen \
  --config services/supabase/scripts/validate_edge_dtos.deno.json \
  --allow-env="$dto_validator_env_allowlist" \
  --allow-read="$dto_validator_read_allowlist" \
  services/supabase/scripts/validate_edge_dtos_test.ts

deno run --frozen \
  --config services/supabase/scripts/validate_edge_dtos.deno.json \
  --allow-env="$dto_validator_env_allowlist" \
  --allow-read="$dto_validator_read_allowlist" \
  services/supabase/scripts/validate_edge_dtos.ts
