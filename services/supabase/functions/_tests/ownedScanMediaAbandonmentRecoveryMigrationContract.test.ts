import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260729173000_recover_media_abandoned_owned_scans.sql",
  import.meta.url,
);

function compact(source: string): string {
  return source.replaceAll(/--.*$/gm, "").replaceAll(/\s+/g, " ").trim();
}

Deno.test("media-abandoned owner recovery retains the full service-only safety boundary", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "SET lock_timeout = '10s'",
      "SET statement_timeout = '2min'",
      "CREATE INDEX IF NOT EXISTS failed_scan_ingestions_user_scan_idx ON public.failed_scan_ingestions (user_id, scan_id)",
      "CREATE OR REPLACE FUNCTION public.recover_missing_owned_scan",
      "SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s'",
      "PERFORM internal.require_service_role()",
      "pg_catalog.JSONB_TYPEOF(p_recovery_scan) <> 'object'",
      "pg_catalog.OCTET_LENGTH(p_recovery_scan::TEXT) > 65536",
      "recovered.id IS DISTINCT FROM p_scan_id",
      "recovered.user_id IS DISTINCT FROM p_user_id",
      "recovered.image_storage_urls IS DISTINCT FROM '{}'::TEXT[]",
      "'merian-scan-ingestion:' || p_scan_id::TEXT",
      "FROM internal.scan_deletion_tombstones AS tombstones",
      "WHERE scans.id = p_scan_id AND scans.user_id = p_user_id",
      "WHERE scans.id = p_scan_id AND scans.user_id IS DISTINCT FROM p_user_id",
      "FROM public.scan_ingestion_jobs AS jobs WHERE jobs.scan_id = p_scan_id::TEXT AND jobs.user_id = p_user_id FOR UPDATE",
      "ingestion_job.status = 'failed_terminal' AND ( ingestion_job.terminal_reason_code = 'replay_exhausted' OR ( ingestion_job.terminal_reason_code = 'media_reconciliation_abandoned' AND EXISTS ( SELECT 1 FROM public.failed_scan_ingestions AS failures WHERE failures.scan_id = p_scan_id::TEXT AND failures.user_id = p_user_id ) ) )",
      "INSERT INTO public.scans",
      "recovered.geoprivacy::public.geoprivacy_enum, recovered.weather_condition, recovered.weather_temperature_f, recovered.ai_confidence_score, recovered.ecology_type::public.ecology_type_enum",
      "ON CONFLICT (id) DO NOTHING",
      "'merian.scan_ingestion_completion_fence'",
      "INSERT INTO public.scan_ingestion_jobs AS existing_job",
      "'client_recovery_complete'",
      "RETURN 'recovered'",
      "REVOKE ALL ON FUNCTION public.recover_missing_owned_scan(UUID, UUID, JSONB) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.recover_missing_owned_scan( UUID, UUID, JSONB ) TO service_role",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assert(
    !sql.includes(
      "recovered.weather_condition, recovered.weather_condition",
    ),
    "Owner recovery must preserve the exact scans column/value alignment.",
  );

  for (
    const forbiddenReason of [
      "content_policy_rejected",
      "provider_policy_rejected",
      "legacy_terminal_unknown",
    ]
  ) {
    assert(
      !sql.includes(`'${forbiddenReason}'`),
      `Recovery migration must not allow ${forbiddenReason}.`,
    );
  }
});

Deno.test("final catalog fixture exercises allowlisted and blocked terminal recovery", async () => {
  const fixture = compact(
    await Deno.readTextFile(
      new URL(
        "../../tests/dwca_download_and_scan_finalization_security.sql",
        import.meta.url,
      ),
    ),
  );

  assertStringIncludes(
    fixture,
    "'media_reconciliation_abandoned', 'media_reconciliation_abandoned'",
  );
  assertStringIncludes(
    fixture,
    "'moderation_rejected', 'content_policy_rejected'",
  );
  assertStringIncludes(
    fixture,
    "'legacy_terminal_failure', 'legacy_terminal_unknown'",
  );
  assertStringIncludes(
    fixture,
    "'post-result scan finalization failed before owner row commit'",
  );
  assertStringIncludes(
    fixture,
    "explicit media-abandonment owner recovery did not complete atomically",
  );
  assertStringIncludes(
    fixture,
    "unallowlisted or unproven terminal reason recovered scan %",
  );

  assertEquals(
    fixture.match(
      /SELECT public[.]recover_missing_owned_scan[(]/g,
    )?.length,
    8,
    "Every reviewed recovery branch must remain in the final catalog fixture.",
  );
});

Deno.test("restore signing uses the same exact terminal-reason allowlist", async () => {
  const source = compact(
    await Deno.readTextFile(
      new URL("../_shared/scanMediaAssets.ts", import.meta.url),
    ),
  );

  for (
    const fragment of [
      'const RECOVERABLE_SCAN_SHARE_RESTORE_TERMINAL_REASONS = new Set([ "replay_exhausted", "media_reconciliation_abandoned", ])',
      '.select("scan_id,status,stage,terminal_reason_code")',
      'job.status !== "failed_terminal"',
      "RECOVERABLE_SCAN_SHARE_RESTORE_TERMINAL_REASONS.has( job.terminal_reason_code, )",
      'job.terminal_reason_code !== "media_reconciliation_abandoned" || provenMediaAbandonmentScanIds.has(scanId)',
      '.from("failed_scan_ingestions")',
      '.select("scan_id,user_id")',
      '.eq("user_id", userId)',
      '.in("scan_id", mediaAbandonmentRestoreScanIds)',
      "isValidScanShareRestoreInput(requestedInput)",
      'row.failure_reason === "moderation_rejected"',
    ]
  ) {
    assertStringIncludes(source, fragment);
  }
});

Deno.test("multimodal producer reports a rejected post-result proof write", async () => {
  const source = compact(
    await Deno.readTextFile(
      new URL("../identify-multimodal/index.ts", import.meta.url),
    ),
  );

  for (
    const fragment of [
      'const { error: deadLetterError } = await supabaseAdmin .from("failed_scan_ingestions") .insert({ scan_id: generatedScanId, user_id: user.id, error_message: errorMsg, })',
      "if (deadLetterError)",
      'logStructuredError("multimodal/dead_letter_write_failed"',
      "error: deadLetterError.message",
    ]
  ) {
    assertStringIncludes(source, fragment);
  }
});

Deno.test("media reconciliation cannot overwrite an existing terminal policy decision", async () => {
  const [worker, db] = await Promise.all([
    Deno.readTextFile(
      new URL("../reconcile-scan-media-assets/worker.ts", import.meta.url),
    ),
    Deno.readTextFile(
      new URL("../reconcile-scan-media-assets/db.ts", import.meta.url),
    ),
  ]);

  assertStringIncludes(
    compact(worker),
    'job.status !== "complete" && job.status !== "failed_terminal"',
  );
  assertStringIncludes(
    compact(db),
    '.not("status", "in", "(complete,failed_terminal)")',
  );
});
