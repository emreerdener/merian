#!/usr/bin/env bash
set -euo pipefail

dto_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dto_repository_root="$(cd -- "$dto_script_dir/../../.." && pwd)"
cd "$dto_repository_root"

# The executable contract is imported as code. Runtime filesystem access is
# limited to the complete iOS graph so every current and future production
# source root under apps/ios is included in generated-DTO ownership checks.
dto_validator_read_allowlist="apps/ios"

deno test --frozen \
  --config services/supabase/scripts/validate_edge_dtos.deno.json \
  --allow-read="$dto_validator_read_allowlist" \
  services/supabase/scripts/validate_edge_dtos_test.ts

deno run --frozen \
  --config services/supabase/scripts/validate_edge_dtos.deno.json \
  --allow-read="$dto_validator_read_allowlist" \
  services/supabase/scripts/validate_edge_dtos.ts

# Exercise the deployed runtime parser and the actual provider-schema export
# under the same frozen dependency graph used by Edge Functions.
deno test --frozen \
  --config services/supabase/functions/deno.json \
  services/supabase/functions/_shared/identify/contract_test.ts
