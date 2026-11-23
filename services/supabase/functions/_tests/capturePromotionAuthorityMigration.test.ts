import { assert, assertEquals } from "@std/assert";
import { MEDIA_BUDGETS } from "../_shared/mediaBudgets.ts";

Deno.test("prepared promotion SQL limits agree with storage media budgets and retain separate cleanup", async () => {
  const source = await Deno.readTextFile(
    new URL(
      "../../migrations/20261120084313_prepare_capture_promotion_authority.sql",
      import.meta.url,
    ),
  );
  for (
    const limit of [
      MEDIA_BUDGETS.maxImageRawBytes,
      MEDIA_BUDGETS.maxAudioRawBytes,
      MEDIA_BUDGETS.maxVideoRawBytes,
    ]
  ) {
    assert(source.includes(`byte_count <= ${limit}`));
  }
  assert(/UNIQUE \(backend_sha256, source_key\)/.test(source));
  assert(/UNIQUE \(backend_sha256, destination_key\)/.test(source));
  assert(
    /AFTER UPDATE OF retired_at ON internal\.capture_object_authorities/.test(
      source,
    ),
  );
  assert(
    !/ON DELETE CASCADE|cron\.schedule|net\.http_post|complete_scan_ingestion_finalization\(/i
      .test(source),
  );
  assert(
    /IF saved\.write_authorized_at IS NOT NULL THEN RETURN FALSE/.test(source),
  );
});

Deno.test("validator volatility repair preserves constant normalization and private contract", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261120100002_correct_capture_validator_volatility.sql",
      import.meta.url,
    ),
  );
  const literal = sql.match(/after_fragment TEXT := \$after\$'([^']+)'::JSONB/);
  assert(literal);
  assertEquals(JSON.parse(literal[1]), {
    version: 1,
    generation: {
      temperature: 0.1,
      seed: null,
      top_k: null,
      max_output_tokens: 8192,
      thinking_budget: null,
    },
  });
  assert(sql.includes("capture validator volatility source drift"));
  assert(
    sql.includes(
      "ALTER FUNCTION internal.initial_evidence_contract(JSONB,TEXT,TEXT) STABLE;",
    ),
  );
  assert(
    !/ALTER FUNCTION internal\.identification_provenance_is_valid|GRANT|DISABLE|UPDATE public\./
      .test(sql),
  );
});
