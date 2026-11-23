import { assert, assertEquals } from "@std/assert";
import { MEDIA_BUDGETS } from "../_shared/mediaBudgets.ts";

Deno.test("promotion cohort has bounded complete inventory without mutable job lifetime ownership", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261120124518_bind_capture_promotion_cohorts.sql",
      import.meta.url,
    ),
  );
  assert(
    sql.includes(`total NOT BETWEEN 1 AND ${MEDIA_BUDGETS.maxStagingFiles}`),
  );
  assert(
    sql.includes(
      `WHEN 'image' THEN ${MEDIA_BUDGETS.maxImageCount} WHEN 'audio' THEN ${MEDIA_BUDGETS.maxStagedAudioFiles} ELSE ${MEDIA_BUDGETS.maxStagedVideoFiles} END`,
    ),
  );
  assert(sql.includes("UNIQUE (owner_id, scan_id, consumer)"));
  assert(
    sql.includes(
      "'intentId',i.id,'payloadSchemaVersion',i.payload_schema_version",
    ),
  );
  assert(sql.includes("NOT existing AND o.write_authorized_at IS NOT NULL"));
  assert(
    sql.includes("saved.ingestion_projection IS DISTINCT FROM projection"),
  );
  assert(
    !/ON DELETE CASCADE|cron\.schedule|net\.http_post|initial_evidence_generation/i
      .test(sql),
  );
  const projection = sql.split(
    "CREATE FUNCTION internal.capture_promotion_ingestion_projection",
  )[1].split("CREATE FUNCTION public.register_capture_promotion_cohort")[0];
  assert(!/FOR UPDATE/i.test(projection));
  assertEquals(
    (sql.match(
      /PERFORM internal\.require_capture_promotion_cohort_current\(saved\.operation_id\)/g,
    ) ?? []).length,
    1,
  );
});

Deno.test("cohort initializer repair is guarded and keeps authority unchanged", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261120125324_type_capture_promotion_cohort_initializers.sql",
      import.meta.url,
    ),
  );
  assert(sql.includes("capture cohort initializer source drift"));
  assertEquals((sql.match(/::JSONB\$b\$/g) ?? []).length, 3);
  assert(sql.includes("'{}'::UUID[]"));
  assert(
    !/GRANT|ALTER TABLE|UPDATE public\.|initial_evidence_generation/.test(sql),
  );
});
