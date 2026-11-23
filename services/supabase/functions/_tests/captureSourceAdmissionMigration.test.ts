import { assert, assertEquals } from "@std/assert";
import { MEDIA_BUDGETS } from "../_shared/mediaBudgets.ts";

const path = new URL(
  "../../migrations/20261120173631_seal_capture_source_admission.sql",
  import.meta.url,
);

Deno.test("source admission retains identity independently and erases private recovery", async () => {
  const sql = await Deno.readTextFile(path);
  assert(
    !/REFERENCES|ON DELETE CASCADE|cron\.schedule|GRANT\s+SELECT/i.test(sql),
  );
  assert(sql.includes("CHECK ((recovery IS NULL) = (retired_at IS NOT NULL))"));
  assert(sql.includes("AFTER INSERT ON internal.account_deletion_jobs"));
  assert(sql.includes("AFTER INSERT ON internal.scan_deletion_tombstones"));
  assert(sql.includes("BEFORE DELETE ON public.users"));
  assert(
    sql.includes(
      "internal.prepare_scan_ingestions_for_identity_merge(uuid,uuid)",
    ),
  );
  assert(sql.includes("transaction_id=pg_current_xact_id()"));
  assert(sql.includes("identity IS DISTINCT FROM saved.recovery->'identity'"));
  assert(sql.includes("RETURN saved.recovery->'intent'"));
});

Deno.test("source admission limits agree with retained collector and preserves writer lock order", async () => {
  const sql = await Deno.readTextFile(path);
  assert(
    sql.includes(`total NOT BETWEEN 1 AND ${MEDIA_BUDGETS.maxStagingFiles}`),
  );
  assert(
    sql.includes(
      `WHEN 'image' THEN ${MEDIA_BUDGETS.maxImageCount} WHEN 'audio' THEN ${MEDIA_BUDGETS.maxStagedAudioFiles} ELSE ${MEDIA_BUDGETS.maxStagedVideoFiles} END`,
    ),
  );
  assert(sql.includes("mime NOT IN ('audio/wav','audio/mp4')"));
  const guard =
    sql.split("CREATE FUNCTION internal.guard_capture_source_admission()")[1]
      .split("CREATE TRIGGER c_guard_capture_source_admission")[0];
  assertEquals((guard.match(/FOR UPDATE/g) ?? []).length, 1);
  assert(guard.includes("IF TG_OP='INSERT' THEN"));
  assert(guard.includes("WHERE scan_id=scan FOR SHARE"));
  assert(!guard.includes("UPDATE internal.capture_source_admissions"));
  assert(guard.includes("internal.capture_source_admission_stops"));
  assert(sql.includes("capture_source_begin_normalization_drift"));
  assert(sql.includes("capture_source_inline_recovery_drift"));
  assert(sql.includes("capture_source_merge_drift"));
});
