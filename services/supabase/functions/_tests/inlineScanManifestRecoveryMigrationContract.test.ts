import { assert, assertStringIncludes, assertThrows } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260728230000_recover_inline_scan_ingestion_completions.sql",
  import.meta.url,
);
const securityFixtureUrl = new URL(
  "../../tests/inline_scan_manifest_recovery_security.sql",
  import.meta.url,
);
const videoFinalizationMigrationUrl = new URL(
  "../../migrations/20260729012153_fix_video_scan_canonical_finalization.sql",
  import.meta.url,
);
const strictFinalizationMigrationUrl = new URL(
  "../../migrations/20260728035237_harden_dwca_downloads_and_scan_finalization.sql",
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

function structuralSql(sql: string): string {
  let result = "";
  let state: "normal" | "single" | "double" | "line" | "block" = "normal";

  for (let index = 0; index < sql.length; index++) {
    const character = sql[index];
    const next = sql[index + 1];

    if (state === "normal") {
      if (character === "-" && next === "-") {
        result += "  ";
        state = "line";
        index++;
      } else if (character === "/" && next === "*") {
        result += "  ";
        state = "block";
        index++;
      } else if (character === "'") {
        result += " ";
        state = "single";
      } else if (character === '"') {
        result += " ";
        state = "double";
      } else {
        result += character;
      }
    } else if (state === "line") {
      result += character === "\n" ? "\n" : " ";
      if (character === "\n") state = "normal";
    } else if (state === "block") {
      result += " ";
      if (character === "*" && next === "/") {
        result += " ";
        state = "normal";
        index++;
      }
    } else {
      result += " ";
      const quote = state === "single" ? "'" : '"';
      if (character === quote && next === quote) {
        result += " ";
        index++;
      } else if (character === quote) {
        state = "normal";
      }
    }
  }

  assert(state === "normal", `Unterminated SQL literal or comment (${state}).`);
  return result;
}

function assertStructurallyBalancedRoutine(name: string, sql: string): void {
  const body = structuralSql(sql);
  let parenthesisDepth = 0;

  for (const character of body) {
    if (character === "(") parenthesisDepth++;
    if (character === ")") parenthesisDepth--;
    assert(
      parenthesisDepth >= 0,
      `${name} closes a parenthesis before opening it.`,
    );
  }
  assert(
    parenthesisDepth === 0,
    `${name} has ${parenthesisDepth} unmatched parentheses.`,
  );

  const blocks: Array<{ kind: "if" | "case"; elseSeen: boolean }> = [];
  const controlToken =
    /\bEND\s+IF\b|\bEND\s+CASE\b|\bELSIF\b|\bIF\b|\bCASE\b|\bELSE\b|\bEND\b/gi;

  for (const match of body.matchAll(controlToken)) {
    const token = match[0].toUpperCase().replaceAll(/\s+/g, " ");
    if (token === "IF") {
      blocks.push({ kind: "if", elseSeen: false });
    } else if (token === "CASE") {
      blocks.push({ kind: "case", elseSeen: false });
    } else if (token === "ELSIF") {
      const block = blocks.at(-1);
      assert(
        block?.kind === "if" && !block.elseSeen,
        `${name} has ELSIF outside an open IF or after ELSE.`,
      );
    } else if (token === "ELSE") {
      const block = blocks.at(-1);
      assert(block, `${name} has ELSE outside an open IF or CASE.`);
      assert(!block.elseSeen, `${name} repeats ELSE in one control block.`);
      block.elseSeen = true;
    } else if (token === "END IF") {
      assert(
        blocks.pop()?.kind === "if",
        `${name} has END IF without a matching IF.`,
      );
    } else if (token === "END CASE") {
      assert(
        blocks.pop()?.kind === "case",
        `${name} has END CASE without a matching CASE.`,
      );
    } else if (blocks.at(-1)?.kind === "case") {
      blocks.pop();
    } else {
      assert(
        blocks.length === 0,
        `${name} has bare END inside an open ${blocks.at(-1)?.kind}.`,
      );
    }
  }

  assert(blocks.length === 0, `${name} has an unterminated control block.`);
}

Deno.test("stranded scan completion recovery is narrow, atomic, and service-only", async () => {
  const [sql, securityFixture] = await Promise.all([
    Deno.readTextFile(migrationUrl).then(normalized),
    Deno.readTextFile(securityFixtureUrl).then(normalized),
  ]);

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.inline_scan_recovery_ledger_matches",
      "CREATE OR REPLACE FUNCTION internal.inline_scan_recovery_scan_media_match",
      "CREATE OR REPLACE FUNCTION internal.inline_scan_recovery_staged_assets_match",
      "IMMUTABLE SECURITY INVOKER SET search_path = ''",
      "STABLE SECURITY INVOKER SET search_path = ''",
      "REVOKE ALL ON FUNCTION internal.inline_scan_recovery_ledger_matches",
      "REVOKE ALL ON FUNCTION internal.inline_scan_recovery_scan_media_match",
      "REVOKE ALL ON FUNCTION internal.inline_scan_recovery_staged_assets_match",
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
      "expected_scan_image_count := inline_image_count",
      "expected_job_image_count := expected_job_image_count + inline_image_count",
      "expected_staged_key_count := audio_key_count + video_key_count",
      "expected_staged_key_count := expected_staged_key_count + image_key_count",
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
      "IF NOT internal.inline_scan_recovery_ledger_matches(",
      "IF NOT internal.inline_scan_recovery_scan_media_match(",
      "IF NOT internal.inline_scan_recovery_staged_assets_match(",
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

  assert(
    !sql.includes("::INTEGER <> CASE"),
    "Compute expected ledger counts before endpoint predicates.",
  );
  assert(
    !sql.includes(
      "<> CASE WHEN uses_inline_images THEN 0 ELSE image_key_count END +",
    ),
    "Compute the expected staged-key count before uniqueness checks.",
  );

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

  const setupEnd = securityFixture.indexOf("SELECT extensions.ok(");
  assert(setupEnd > 0, "Inline recovery fixture setup boundary is missing.");
  const profileSetup = securityFixture.slice(0, setupEnd);
  assertStringIncludes(profileSetup, "'inline_recovery_f101'");
  assertStringIncludes(
    profileSetup,
    "ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email, public_username = EXCLUDED.public_username, public_author_name = EXCLUDED.public_author_name, public_identity_source = EXCLUDED.public_identity_source",
  );
});

Deno.test("scan recovery keeps PostgreSQL routine definitions bounded", async () => {
  const sql = await Deno.readTextFile(migrationUrl);
  const routinePattern =
    /CREATE OR REPLACE FUNCTION\s+([^\s(]+)[\s\S]*?\bAS\s+\$\$([\s\S]*?)\$\$;/gi;
  const routines = [...sql.matchAll(routinePattern)];

  assert(
    routines.length === 4,
    `Expected four decomposed recovery routines, found ${routines.length}.`,
  );
  for (const routine of routines) {
    const name = routine[1];
    const definitionBytes = new TextEncoder().encode(routine[0]).byteLength;
    assert(
      definitionBytes < 16_384,
      `${name} grew to ${definitionBytes} bytes; keep recovery stages decomposed.`,
    );
  }
});

Deno.test("scan recovery routine bodies remain structurally balanced", async () => {
  const sql = await Deno.readTextFile(migrationUrl);
  const routinePattern =
    /CREATE OR REPLACE FUNCTION\s+([^\s(]+)[\s\S]*?\bAS\s+\$\$([\s\S]*?)\$\$;/gi;
  const routines = [...sql.matchAll(routinePattern)];
  assert(routines.length === 4, "Expected all four recovery routine bodies.");

  for (const routine of routines) {
    assertStructurallyBalancedRoutine(routine[1], routine[2]);
  }
});

Deno.test("scan recovery structural validator rejects parser-seam regressions", () => {
  assertStructurallyBalancedRoutine(
    "valid nested fixture",
    `
      BEGIN
          IF TRUE THEN
              value := CASE WHEN TRUE THEN 1 ELSE 0 END;
          ELSIF FALSE THEN
              NULL;
          ELSE
              NULL;
          END IF;
      END;
    `,
  );

  const invalidFixtures = [
    {
      name: "unmatched predicate parenthesis",
      sql: "BEGIN IF (TRUE OR (FALSE) THEN NULL; END IF; END;",
    },
    {
      name: "orphan end if",
      sql: "BEGIN END IF; END;",
    },
    {
      name: "elsif after else",
      sql:
        "BEGIN IF TRUE THEN NULL; ELSE NULL; ELSIF FALSE THEN NULL; END IF; END;",
    },
    {
      name: "repeated case else",
      sql: "BEGIN value := CASE WHEN TRUE THEN 1 ELSE 2 ELSE 3 END; END;",
    },
    {
      name: "unterminated if",
      sql: "BEGIN IF TRUE THEN NULL; END;",
    },
    {
      name: "unterminated literal",
      sql: "BEGIN value := 'missing quote; END;",
    },
  ];

  for (const fixture of invalidFixtures) {
    assertThrows(() =>
      assertStructurallyBalancedRoutine(fixture.name, fixture.sql)
    );
  }
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

Deno.test("video finalization validates canonical media without treating inference frames as images", async () => {
  const [migrationSource, strictFinalizationSource, securityFixtureSource] =
    await Promise.all([
      Deno.readTextFile(videoFinalizationMigrationUrl),
      Deno.readTextFile(strictFinalizationMigrationUrl),
      Deno.readTextFile(securityFixtureUrl),
    ]);
  const sql = normalized(migrationSource);
  const securityFixture = normalized(securityFixtureSource);

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.scan_canonical_media_projection_complete",
      "STABLE SECURITY INVOKER SET search_path = ''",
      "scans.captured_media",
      "JOIN public.scan_ingestion_jobs AS jobs",
      "jobs.media_counts",
      "public.scan_media_reference_path( captured_items.item #> '{image,_0}' )",
      "public.scan_media_reference_path( captured_items.item #> '{video,_0,video}' )",
      "legacy_counts.image_count - (legacy_counts.video_count * 5)",
      "WHERE NOT EXISTS ( SELECT 1 FROM captured_visuals )",
      "assets.user_id = scan_row.user_id",
      "assets.kind = expected_media.kind",
      "assets.status = 'ready'",
      "declared_visual_counts.image_count",
      "declared_visual_counts.video_count",
      "parsed_visual_counts.endpoint = 'identify-multimodal'",
      "parsed_visual_counts.endpoint IN ( 'identify', 'identify-describe', 'audio-spec' )",
      "parsed_visual_counts.image_count - parsed_visual_counts.frame_count",
      "FROM expected_visuals WHERE expected_visuals.kind = 'image'",
      "FROM expected_visuals WHERE expected_visuals.kind = 'video'",
      "REVOKE ALL ON FUNCTION internal.scan_canonical_media_projection_complete",
      "CREATE OR REPLACE FUNCTION internal.scan_media_reference_is_video_inference_frame",
      "jobs.media_counts",
      "jobs.endpoint",
      "-> 'video_inference_frame_count' ) = 'number'",
      "~ '^(0|[1-9]|1[0-6])$'",
      "scan_job.media_counts -> 'image_count' ) = 'number'",
      "parsed_declared_media.endpoint = 'identify-multimodal'",
      "parsed_declared_media.endpoint IN ( 'identify', 'identify-describe', 'audio-spec' )",
      "parsed_declared_media.image_count - parsed_declared_media.frame_count",
      "projection_state.captured_has_video",
      "projection_state.captured_image_count",
      "SELECT image_count FROM declared_media",
      "inference_frames AS",
      "(SELECT frame_count FROM declared_media) = ( SELECT pg_catalog.COUNT(*) FROM inference_frames",
      "inference_frames.url = p_url",
      "legacy_images.sequence > GREATEST",
      "REVOKE ALL ON FUNCTION internal.scan_media_reference_is_video_inference_frame",
      "FROM PUBLIC, anon, authenticated, service_role",
      "PG_GET_FUNCTIONDEF",
      "IF NOT internal.scan_canonical_media_projection_complete(p_scan_id)",
      "Could not locate the exact canonical-media validation block",
      "Could not install the exact canonical-media projection check",
      "Could not locate the exact captured-media validation block",
      "Could not install the exact video-frame manifest exclusion",
      "GRANT EXECUTE ON FUNCTION public.complete_scan_ingestion_finalization",
      "TO service_role",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("CARDINALITY(scans.video_storage_urls) = 0"),
    "Mixed image/video scans must use projection validation, not skip images.",
  );
  assertBefore(
    sql,
    "PERFORM public.refresh_scan_media_assets(p_scan_id)",
    "IF NOT internal.scan_canonical_media_projection_complete(p_scan_id)",
    "Canonical rows must be refreshed before projection validation.",
  );

  for (
    const fragment of [
      "SELECT extensions.plan(30)",
      "'00000000-0000-4000-8000-00000000f114'",
      '"video_inference_frame_count":5',
      "native video counts normalize to the canonical playback projection",
      "compatibility video counts subtract the declared inference-frame subset",
      "public.complete_scan_ingestion_finalization(",
      "SELECT pg_catalog.COUNT(*) = 6",
      "assets.source = 'capture_upload'",
      "frame classification fails closed when the declared set is incomplete",
      "AND NOT EXISTS ( SELECT 1 FROM public.scan_media_assets AS assets",
      "AND assets.kind = 'image' AND assets.status = 'ready'",
    ]
  ) {
    assertStringIncludes(securityFixture, fragment);
  }

  const guardedFragments = [
    ...migrationSource.matchAll(/\$guard\$\n([\s\S]*?)\n\$guard\$/g),
  ].map((match) => match[1]);
  assert(
    guardedFragments.length === 2,
    `Expected two exact finalizer guards, found ${guardedFragments.length}.`,
  );
  for (const guardedFragment of guardedFragments) {
    assert(
      strictFinalizationSource.split(guardedFragment).length - 1 === 1,
      "Each guarded replacement must match the historical finalizer exactly once.",
    );
  }
});
