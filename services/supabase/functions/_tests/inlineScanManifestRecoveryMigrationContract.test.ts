import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260728230000_recover_inline_scan_ingestion_completions.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

function assertBefore(
  sql: string,
  earlier: string,
  later: string,
  message: string,
): void {
  const earlierIndex = sql.indexOf(earlier);
  const laterIndex = sql.indexOf(later);
  assert(earlierIndex >= 0, `Missing expected SQL fragment: ${earlier}`);
  assert(laterIndex >= 0, `Missing expected SQL fragment: ${later}`);
  assert(earlierIndex < laterIndex, message);
}

Deno.test("stranded scan completion recovery is narrow, atomic, and service-only", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.recover_inline_scan_ingestion_completion",
      "SECURITY DEFINER SET search_path = '' SET statement_timeout = '15s'",
      "PERFORM internal.require_service_role()",
      "'merian-scan-ingestion:' || p_scan_id::TEXT",
      "FROM internal.scan_deletion_tombstones",
      "jobs.user_id = p_user_id FOR UPDATE",
      "intents.user_id = p_user_id FOR UPDATE",
      "scans.user_id",
      "scan_owner IS DISTINCT FROM p_user_id",
      "job_row.status <> 'failed_retryable'",
      "'background_ingestion_failed', 'media_finalization_failed'",
      "has_inline_media := uses_inline_images OR inline_audio_count > 0",
      "intent_row.inline_media_redacted IS DISTINCT FROM has_inline_media",
      "intent_row.resumable IS DISTINCT FROM (NOT has_inline_media)",
      "intent_row.media_object_keys IS DISTINCT FROM job_row.media_object_keys",
      "intent_row.media_counts IS DISTINCT FROM job_row.media_counts",
      "intent_row.upload_session_ids IS DISTINCT FROM job_row.upload_session_ids",
      "intent_row.manifest_checksum IS DISTINCT FROM job_row.manifest_checksum",
      "{media,audioR2ObjectKeys}",
      "{media,videoR2ObjectKeys}",
      "{media,audioMediaItems}",
      "intent_row.request_payload -> 'mediaCounts' IS DISTINCT FROM job_row.media_counts",
      "intent_row.request_payload -> 'uploadSessionIds' IS DISTINCT FROM pg_catalog.TO_JSONB",
      "intent_row.request_payload ->> 'clientScanId' IS DISTINCT FROM p_scan_id::TEXT",
      "image_base64_count",
      "audio_base64_count",
      "job_row.media_counts -> 'image_count'",
      "job_row.media_counts -> 'audio_count'",
      "job_row.media_counts -> 'video_count'",
      "job_row.media_counts -> 'required_video_count'",
      "job_row.media_counts -> 'video_inference_frame_count'",
      "uses_inline_images := inline_image_count > 0",
      "uses_inline_images AND image_key_count > inline_image_count",
      "job_row.endpoint = 'identify'",
      "job_row.endpoint = 'identify-multimodal'",
      "THEN inline_image_count + image_key_count",
      "inline_audio_count + audio_key_count",
      "scan_video_storage_urls",
      "scan_audio_storage_urls",
      "'(free|pro)/' || p_user_id::TEXT",
      "COUNT(DISTINCT media_urls.url)",
      "COUNT(DISTINCT image_keys.storage_key)",
      "REGEXP_REPLACE( image_keys.storage_key, '^.*/', '' )",
      "assets.source = 'capture_upload'",
      "WHERE NOT uses_inline_images",
      "expected.kind IN ('image', 'video')",
      "'superseded_staging_registration'",
      "expected.kind = 'audio' AND assets.status IN ( 'staged', 'promoted', 'deleted' )",
      "audio_items.item ->> 'kind' = 'video_audio'",
      "INTO STRICT preserved_storage_keys",
      "INTO STRICT resolved_upload_session_ids",
      "resolved_upload_session_ids IS DISTINCT FROM job_row.upload_session_ids",
      "INTO STRICT recovered_promotions",
      "INTO STRICT recovered_deletions",
      "RETURN 'not_applicable'",
      "PERFORM public.begin_scan_ingestion(",
      "normalized_media_object_keys",
      "preserved_storage_keys",
      "finalization_result := public.complete_scan_ingestion_finalization(",
      "recovered_promotions, recovered_deletions",
      "REVOKE ALL ON FUNCTION public.recover_inline_scan_ingestion_completion",
      "FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.recover_inline_scan_ingestion_completion",
      "TO service_role",
      "INSERT INTO internal.privileged_routine_grants",
      "'public.recover_inline_scan_ingestion_completion(uuid,uuid)'",
      "ON CONFLICT (role_name, routine_signature) DO UPDATE",
      "NOTIFY pgrst, 'reload schema'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assertBefore(
    sql,
    "PERFORM public.begin_scan_ingestion(",
    "finalization_result := public.complete_scan_ingestion_finalization(",
    "The normalized ledgers must be written before canonical finalization.",
  );
  assertBefore(
    sql,
    "finalization_result := public.complete_scan_ingestion_finalization(",
    "RETURN finalization_result",
    "Recovery may report success only after canonical finalization.",
  );
  assertBefore(
    sql,
    "GRANT EXECUTE ON FUNCTION public.recover_inline_scan_ingestion_completion",
    "'public.recover_inline_scan_ingestion_completion(uuid,uuid)'",
    "The reviewed grant must exist before its allowlist entry.",
  );
});

Deno.test("scan recovery separates JSON type validation from unsafe operations", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));
  const typeGate = sql.indexOf(
    "JSONB_TYPEOF( intent_row.redacted_media_counts -> 'image_base64_count' ) IS DISTINCT FROM 'number'",
  );
  const arrayOperation = sql.indexOf(
    "image_key_count := pg_catalog.JSONB_ARRAY_LENGTH( job_row.media_object_keys -> 'image' )",
  );
  const boundedNumberGate = sql.indexOf("!~ '^(0|[1-9]|1[0-6])$'");
  const numericCast = sql.indexOf(
    "intent_row.redacted_media_counts ->> 'image_base64_count' )::INTEGER",
  );

  assert(typeGate >= 0, "The JSON type gate must remain explicit.");
  assert(
    arrayOperation > typeGate,
    "Array operations must follow type gating.",
  );
  assert(
    boundedNumberGate > arrayOperation,
    "The bounded numeric pattern must follow safe array checks.",
  );
  assert(
    numericCast > boundedNumberGate,
    "The integer cast must follow bounded numeric validation.",
  );
});
