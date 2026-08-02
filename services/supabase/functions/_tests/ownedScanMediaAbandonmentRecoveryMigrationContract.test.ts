import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260729200000_harden_media_abandoned_scan_recovery_proof.sql",
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
      "ALTER TABLE public.failed_scan_ingestions ADD COLUMN IF NOT EXISTS quota_reservation_id UUID, ADD COLUMN IF NOT EXISTS quota_request_id UUID, ADD COLUMN IF NOT EXISTS failure_kind TEXT, ADD COLUMN IF NOT EXISTS provider_result_validated BOOLEAN, ADD COLUMN IF NOT EXISTS identify_safety_evaluation_completed BOOLEAN",
      "failed_scan_ingestions_structured_recovery_evidence_check",
      "failure_kind = 'post_result_scan_durability_failure'",
      "failed_scan_ingestions_recovery_proof_idx ON public.failed_scan_ingestions (user_id, scan_id, failed_at DESC)",
      "DROP INDEX IF EXISTS public.failed_scan_ingestions_user_scan_idx",
      "CREATE TABLE IF NOT EXISTS internal.scan_recovery_evidence_control",
      "legacy_unstructured_before TIMESTAMPTZ NOT NULL",
      "ALTER TABLE internal.scan_recovery_evidence_control ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.scan_recovery_evidence_control FROM PUBLIC, anon, authenticated, service_role",
      "CREATE TABLE IF NOT EXISTS internal.scan_recovery_legacy_dead_letters",
      "failed_scan_ingestion_id UUID PRIMARY KEY REFERENCES public.failed_scan_ingestions(id) ON DELETE CASCADE",
      "ALTER TABLE internal.scan_recovery_legacy_dead_letters ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.scan_recovery_legacy_dead_letters FROM PUBLIC, anon, authenticated, service_role",
      "WITH inserted_control AS ( INSERT INTO internal.scan_recovery_evidence_control",
      "VALUES (TRUE, pg_catalog.CLOCK_TIMESTAMP()) ON CONFLICT (singleton) DO NOTHING",
      "RETURNING legacy_unstructured_before ) INSERT INTO internal.scan_recovery_legacy_dead_letters",
      "CROSS JOIN public.failed_scan_ingestions AS failures",
      "CREATE OR REPLACE FUNCTION internal.derive_ai_quota_request_id",
      "pg_catalog.SHA256( pg_catalog.CONVERT_TO( pg_catalog.LOWER(p_parent_request_id::TEXT) || ':' || p_discriminator, 'UTF8' ) )",
      "pg_catalog.GET_BYTE(digest_bytes.value, 6) & 15 ) | 128",
      "pg_catalog.GET_BYTE(digest_bytes.value, 8) & 63 ) | 128",
      "REVOKE ALL ON FUNCTION internal.derive_ai_quota_request_id(UUID, TEXT) FROM PUBLIC, anon, authenticated, service_role",
      "CREATE OR REPLACE FUNCTION internal.media_abandoned_scan_has_recovery_proof",
      "FROM public.scan_ingestion_intents AS intents WHERE intents.scan_id = p_scan_id::TEXT AND intents.user_id = p_user_id",
      "'scan-ingestion-replay:' || attempts.attempt::TEXT",
      "FROM pg_catalog.GENERATE_SERIES(1, 10) AS attempts(attempt)",
      "intent_state.replay_attempt_count <= 10",
      "reservations.operation = 'scan_identification'",
      "exact_reservations.state IN ('failed', 'committed')",
      "ORDER BY exact_reservations.authority_at DESC NULLS FIRST",
      "jobs.status = 'failed_terminal'",
      "jobs.endpoint = 'identify-multimodal'",
      "jobs.terminal_reason_code = 'media_reconciliation_abandoned'",
      "failures.failed_at >= latest_authority.authority_at",
      "failures.quota_reservation_id = latest_authority.id",
      "failures.quota_request_id = latest_authority.request_id",
      "failures.identify_safety_evaluation_completed IS TRUE",
      "FROM internal.scan_recovery_legacy_dead_letters AS legacy_failures WHERE legacy_failures.failed_scan_ingestion_id = failures.id",
      "failures.failed_at < evidence_control.legacy_unstructured_before",
      "failures.error_message IS NOT NULL",
      "pg_catalog.LOWER(failures.error_message) NOT LIKE 'failed to ensure scan user exists:%'",
      "pg_catalog.LOWER(failures.error_message) NOT LIKE '%moderation%'",
      "latest_authority.state = 'failed'",
      "latest_authority.state = 'committed'",
      "latest_authority.attempt = 0",
      "latest_authority.attempt_count = 1",
      "replay_authority.attempt > 0",
      "exact_reservations.state = 'reserved'",
      "exact_reservations.committed_at < exact_reservations.reserved_at",
      "exact_reservations.failed_at < exact_reservations.committed_at",
      "assets.failure_reason IN ( 'moderation_rejected', 'moderation_pipeline_error' )",
      "CREATE OR REPLACE FUNCTION internal.prune_ai_quota_state()",
      "WITH protected_reservations AS MATERIALIZED",
      "candidates.operation = 'scan_identification'",
      "candidates.state IN ('failed', 'committed')",
      "jobs.terminal_reason_code = 'media_reconciliation_abandoned'",
      "pg_catalog.GENERATE_SERIES( 0, 10 )",
      "WHEN jobs.scan_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN CASE",
      "ELSE NULL END AS request_id",
      "protected.request_id = candidates.request_id",
      "REVOKE ALL ON FUNCTION internal.prune_ai_quota_state() FROM PUBLIC, anon, authenticated, service_role",
      "CREATE OR REPLACE FUNCTION public.get_media_abandoned_scan_recovery_proofs",
      "PERFORM internal.require_service_role()",
      "pg_catalog.CARDINALITY(p_scan_ids) NOT BETWEEN 1 AND 20",
      "internal.media_abandoned_scan_has_recovery_proof( requested.scan_id, p_user_id )",
      "REVOKE ALL ON FUNCTION public.get_media_abandoned_scan_recovery_proofs(UUID, UUID[]) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.get_media_abandoned_scan_recovery_proofs(UUID, UUID[]) TO service_role",
      "INSERT INTO internal.privileged_routine_grants",
      "'public.get_media_abandoned_scan_recovery_proofs(uuid,uuid[])'",
      "CREATE OR REPLACE FUNCTION public.recover_missing_owned_scan",
      "SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s'",
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
      "ingestion_job.status = 'failed_terminal' AND ( ingestion_job.terminal_reason_code = 'replay_exhausted' OR ( ingestion_job.terminal_reason_code = 'media_reconciliation_abandoned' AND internal.media_abandoned_scan_has_recovery_proof( p_scan_id, p_user_id ) ) )",
      "INSERT INTO public.scans",
      "recovered.geoprivacy::public.geoprivacy_enum, recovered.weather_condition, recovered.weather_temperature_f, recovered.ai_confidence_score, recovered.ecology_type::public.ecology_type_enum",
      "ON CONFLICT (id) DO NOTHING",
      "'merian.scan_ingestion_completion_fence'",
      "INSERT INTO public.scan_ingestion_jobs AS existing_job",
      "'client_recovery_complete'",
      "RETURN 'recovered'",
      "REVOKE ALL ON FUNCTION public.recover_missing_owned_scan(UUID, UUID, JSONB) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.recover_missing_owned_scan( UUID, UUID, JSONB ) TO service_role",
      "NOTIFY pgrst, 'reload schema'",
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
    "'legacy post-result scan finalization failed before owner row commit'",
  );
  assertStringIncludes(
    fixture,
    "explicit media-abandonment owner recovery did not complete atomically",
  );
  assertStringIncludes(
    fixture,
    "unsafe or unproven terminal reason recovered scan %",
  );
  assertStringIncludes(
    fixture,
    "older post-result failure preceded a permanent provider decision",
  );
  assertStringIncludes(
    fixture,
    "older post-result failure preceded a moderation decision",
  );
  assertStringIncludes(
    fixture,
    "older post-result failure preceded a replay policy decision",
  );
  assertStringIncludes(
    fixture,
    "'structured post-result durability failure'",
  );
  assertStringIncludes(
    fixture,
    "'legacy moderation infrastructure failure'",
  );
  assertStringIncludes(
    fixture,
    "'unstructured evidence inserted after rollout with backdated transaction timestamp'",
  );
  assertStringIncludes(
    fixture,
    "INSERT INTO internal.scan_recovery_legacy_dead_letters",
  );
  assertStringIncludes(
    fixture,
    "failures.scan_id <> post_cutoff_unstructured_scan_id::TEXT",
  );
  assertStringIncludes(
    fixture,
    "'Failed to ensure scan user exists: post-result prerequisite unavailable'",
  );
  assertStringIncludes(
    fixture,
    "'structured durability failure before required safety completed'",
  );
  assertStringIncludes(
    fixture,
    "'Multimodal moderation pipeline failed.'",
  );
  assertStringIncludes(
    fixture,
    "'legacy compatibility producer failed after provider result'",
  );
  assertStringIncludes(
    fixture,
    "'legacy durability failure while later replay remains active'",
  );
  assertStringIncludes(
    fixture,
    "'legacy durability failure with corrupt quota chronology'",
  );
  assertStringIncludes(fixture, "'legacy-malformed-scan-id'");
  assertStringIncludes(
    fixture,
    "'5bd14510-252c-85f2-adbb-7ae15e071de5'::UUID",
  );
  assertStringIncludes(
    fixture,
    "restore signer proof lookup admitted unsafe media abandonment",
  );
  assertStringIncludes(
    fixture,
    "quota pruning lost recovery proof, policy, or active authority",
  );
  assertStringIncludes(fixture, ") <> 15 THEN");
  assertStringIncludes(
    fixture,
    "'scan-ingestion-replay:2' ), 'refunded'",
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
      '.rpc( "get_media_abandoned_scan_recovery_proofs", { p_user_id: userId, p_scan_ids: mediaAbandonmentRestoreScanIds, }, )',
      "recoveryProofData != null && !Array.isArray(recoveryProofData)",
      'typeof row?.scan_id === "string"',
      "scanId.toLowerCase() === proofScanId.toLowerCase()",
      "isValidScanShareRestoreInput(requestedInput)",
      'const NON_REACTIVATABLE_SCAN_MEDIA_FAILURE_REASONS = new Set([ "moderation_rejected", "moderation_pipeline_error", ])',
      "NON_REACTIVATABLE_SCAN_MEDIA_FAILURE_REASONS.has(row.failure_reason)",
    ]
  ) {
    assertStringIncludes(source, fragment);
  }
});

Deno.test("Edge owner recovery proves the hardening boundary before the recovery routine", async () => {
  const source = compact(
    await Deno.readTextFile(
      new URL("../_shared/scanRecovery.ts", import.meta.url),
    ),
  );
  const proofIndex = source.indexOf(
    '.rpc( "get_media_abandoned_scan_recovery_proofs"',
  );
  const recoveryIndex = source.indexOf('.rpc( "recover_missing_owned_scan"');

  assert(
    proofIndex >= 0 && recoveryIndex > proofIndex,
    "The proof RPC must fence the separately committed baseline definition before owner recovery can run.",
  );
  for (
    const fragment of [
      "p_user_id: recoveryScan.user_id",
      "p_scan_ids: [recoveryScan.id]",
      "hardened recovery boundary unavailable",
      "!Array.isArray(boundaryData)",
      'typeof row?.scan_id !== "string"',
      "row.scan_id.toLowerCase() !== recoveryScan.id.toLowerCase()",
      "invalid hardened recovery boundary response",
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
      "const requiresIdentifySafetyEvaluation = imageBase64s.length > 0 || r2ObjectKeys.length > 0",
      "let identifySafetyEvaluationCompleted = !requiresIdentifySafetyEvaluation",
      "identifySafetyEvaluationCompleted = true",
      'const { error: deadLetterError } = await supabaseAdmin .from("failed_scan_ingestions") .insert({ scan_id: generatedScanId, user_id: user.id, error_message: errorMsg, quota_reservation_id: quotaLease.reservation.id, quota_request_id: quotaLease.reservation.requestId, failure_kind: "post_result_scan_durability_failure", provider_result_validated: true, identify_safety_evaluation_completed: identifySafetyEvaluationCompleted, })',
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
