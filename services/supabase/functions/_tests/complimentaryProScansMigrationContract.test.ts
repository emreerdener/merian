import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260802235833_three_complimentary_pro_scans.sql",
  import.meta.url,
);
const ghostMergeMigrationUrl = new URL(
  "../../migrations/20260801210102_make_ghost_merge_schema_aware.sql",
  import.meta.url,
);

function compact(source: string): string {
  return source.replaceAll(/--.*$/gm, "").replaceAll(/\s+/g, " ").trim();
}

function routineSection(sql: string, name: string, nextName: string): string {
  const start = sql.indexOf(`CREATE OR REPLACE FUNCTION public.${name}`);
  const end = sql.indexOf(
    `CREATE OR REPLACE FUNCTION public.${nextName}`,
    start + 1,
  );
  assert(start >= 0, `${name} routine is missing`);
  assert(end > start, `${name} routine boundary is missing`);
  return sql.slice(start, end);
}

Deno.test("complimentary scan migration derives one fixed grant from a private lifetime ledger", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  for (
    const fragment of [
      "CREATE TABLE internal.complimentary_scan_usage",
      "PRIMARY KEY (user_id, client_scan_id)",
      "CHECK (state IN ('held', 'consumed', 'released'))",
      "complimentary_scan_grant INTEGER NOT NULL DEFAULT 3 CHECK (complimentary_scan_grant = 3)",
      "ALTER TABLE internal.complimentary_scan_usage ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.complimentary_scan_usage FROM PUBLIC, anon, authenticated, service_role",
      "COUNT(*) FILTER ( WHERE usage.state = 'consumed' )",
      "COUNT(*) FILTER ( WHERE usage.state = 'held' )",
      "scans_available_to_start := GREATEST( rollout.complimentary_scan_grant - consumed_count - held_count, 0 )",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assert(
    !/complimentary_scan_usage[^;]*(?:balance|remaining)\s+(?:integer|bigint)/i
      .test(
        sql,
      ),
    "The ledger must not maintain a redundant balance counter.",
  );
});

Deno.test("rollout starts legacy and atomically fences functional mode, protocol, and versions", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const cutover = compact(
    await Deno.readTextFile(
      new URL(
        "../../scripts/cutover_complimentary_entitlements.sql",
        import.meta.url,
      ),
    ),
  );
  for (
    const fragment of [
      "VALUES ('current', 'legacy_trial', 3, 0)",
      "entitlement_mode = 'legacy_trial' AND required_client_protocol = 0",
      "entitlement_mode = 'complimentary' AND required_client_protocol = 2",
      "NEW.mode_version := OLD.mode_version + 1",
      "entitlement_version := app_user.entitlement_version + rollout.mode_version",
      "CREATE OR REPLACE FUNCTION public.get_entitlement_rollout_service()",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assertStringIncludes(cutover, "BEGIN");
  assertStringIncludes(
    cutover,
    "SET entitlement_mode = 'complimentary', required_client_protocol = 2",
  );
  assertStringIncludes(cutover, "COMMIT");
});

Deno.test("functional entitlement rewrites preserve volatile snapshot visibility", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const resolver = sql.slice(
    sql.indexOf(
      "CREATE OR REPLACE FUNCTION internal.resolve_effective_entitlement",
    ),
    sql.indexOf(
      "CREATE OR REPLACE FUNCTION internal.user_has_effective_pro",
    ),
  );
  assertStringIncludes(resolver, "LANGUAGE PLPGSQL VOLATILE");
  for (
    const fragment of [
      "volatility_rewritten_count INTEGER := 0",
      "SELECT function_row.oid, function_row.provolatile",
      "IF routine_row.provolatile = 's' THEN",
      "'ALTER FUNCTION %s VOLATILE'",
      "routine_row.oid::pg_catalog.REGPROCEDURE",
      "IF volatility_rewritten_count <> 6 THEN",
      "functional_entitlement_volatility_source_drift",
      "ALTER FUNCTION public.get_recent_field_trip_publications( UUID, TEXT, TEXT[], INTEGER, TIMESTAMPTZ, UUID ) VOLATILE",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("reservation and settlement keep credit linkage separate from provider quota", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.reserve_ai_quota( p_user_id UUID, p_operation TEXT, p_request_id UUID, p_ip_hash TEXT, p_original_analysis_id UUID, p_flash_fallback_eligible BOOLEAN, p_client_protocol INTEGER, p_internal_replay BOOLEAN )",
      "FROM public.users AS users WHERE users.id = p_user_id FOR UPDATE",
      "INSERT INTO internal.complimentary_scan_usage",
      "resolved_flash_fallback := TRUE",
      "RAISE EXCEPTION 'ai_entitlement_required'",
      "FROM public.reserve_ai_quota( p_user_id, p_operation, p_request_id, p_ip_hash ) AS quota",
      "complimentary_client_scan_id = COALESCE",
      "flash_fallback_used = reservations.flash_fallback_used OR resolved_flash_fallback",
      "CREATE OR REPLACE FUNCTION public.fail_scan_ingestion_terminal",
      "'merian.complimentary_terminal_fence'",
      "complimentary_terminal_requires_orchestrator",
      "AND jobs.status NOT IN ('complete', 'failed_terminal')",
      "CREATE OR REPLACE FUNCTION public.complete_scan_ingestion_with_entitlement",
      "settlement_reason = 'paid_before_completion'",
      "settlement_reason = 'durable_result_complete'",
      "'user_id', p_user_id, 'plan_used', plan_used, 'credit_consumed', credit_consumed, 'entitlement_after', pg_catalog.TO_JSONB(entitlement_after)",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const terminalRoutine = sql.slice(
    sql.indexOf(
      "CREATE OR REPLACE FUNCTION public.fail_scan_ingestion_terminal",
    ),
    sql.indexOf(
      "CREATE OR REPLACE FUNCTION public.complete_scan_ingestion_with_entitlement",
    ),
  );
  assert(
    !terminalRoutine.includes("release_ai_quota_reservation_counters"),
    "A complimentary release must not refund provider quota counters.",
  );
});

Deno.test("ledger transitions cannot predate wall-clock hold creation", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  assertEquals(
    (sql.match(/settlement_now := pg_catalog[.]CLOCK_TIMESTAMP[(][)]/g) ?? [])
      .length,
    2,
  );
  for (
    const fragment of [
      "settled_at = settlement_now",
      "updated_at = settlement_now",
      "merge_now := pg_catalog.CLOCK_TIMESTAMP()",
      "settled_at = merge_now",
      "updated_at = merge_now",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assertEquals(sql.includes("settled_at = pg_catalog.NOW()"), false);
});

Deno.test("all complimentary mutations acquire the user lock before quota, job, scan, and ledger locks", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const reservation = routineSection(
    sql,
    "reserve_ai_quota",
    "fail_scan_ingestion_terminal",
  );
  const terminal = routineSection(
    sql,
    "fail_scan_ingestion_terminal",
    "complete_scan_ingestion_with_entitlement",
  );
  const completion = routineSection(
    sql,
    "complete_scan_ingestion_with_entitlement",
    "admin_complimentary_entitlement_summary",
  );

  const assertOrdered = (
    source: string,
    markers: string[],
    label: string,
  ) => {
    let previous = -1;
    for (const marker of markers) {
      const position = source.indexOf(marker);
      assert(position >= 0, `${label} is missing ${marker}`);
      assert(position > previous, `${label} lock order drifted at ${marker}`);
      previous = position;
    }
  };

  assertOrdered(
    reservation,
    [
      "FROM public.users AS users WHERE users.id = p_user_id FOR UPDATE",
      "FROM internal.ai_quota_reservations AS reservations",
      "FROM internal.complimentary_scan_usage AS usage",
      "FROM public.reserve_ai_quota(",
    ],
    "reservation",
  );
  assertOrdered(
    terminal,
    [
      "FROM public.users AS users WHERE users.id = p_user_id FOR UPDATE",
      "UPDATE public.scan_ingestion_jobs AS jobs",
      "UPDATE internal.complimentary_scan_usage AS usage",
    ],
    "terminal settlement",
  );
  assertOrdered(
    completion,
    [
      "FROM public.users AS users WHERE users.id = p_user_id FOR UPDATE",
      "finalization_result := public.complete_scan_ingestion_finalization(",
      "FROM internal.complimentary_scan_usage AS usage",
      "UPDATE public.scan_ingestion_jobs AS jobs",
    ],
    "completion",
  );
});

Deno.test("merge preserves history and caps combined in-flight work to one grant", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.merge_ghost_complimentary_scan_usage",
      "WHEN target_usage.state = 'consumed' OR source_usage.state = 'consumed' THEN 'consumed'",
      "3 - ( SELECT pg_catalog.COUNT(*)::INTEGER FROM internal.complimentary_scan_usage AS consumed_usage",
      "settlement_reason = 'ghost_merge_grant_cap'",
      "PERFORM internal.merge_ghost_complimentary_scan_usage",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("ghost merge preflight recognizes only the reviewed complimentary handler", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const ghostMergeSql = await Deno.readTextFile(ghostMergeMigrationUrl);
  for (
    const fragment of [
      "TO_REGPROCEDURE( 'internal.assert_ghost_profile_merge_reference_policy_coverage()' )",
      "guarded_fragment TEXT := ' ''community_activity_actors'','",
      "' ''complimentary_scan_usage'','",
      "ghost_merge_handler_allowlist_source_drift",
      "ghost_merge_handler_allowlist_rewrite_failed",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const policyRegistration = sql.indexOf(
    "'internal', 'complimentary_scan_usage', 'user_id'",
  );
  const allowlistRewrite = sql.indexOf(
    "ghost_merge_handler_allowlist_source_drift",
  );
  const finalCoverageAssertion = sql.lastIndexOf(
    "SELECT internal.assert_ghost_profile_merge_reference_policy_coverage()",
  );
  assert(
    policyRegistration >= 0 && allowlistRewrite > policyRegistration &&
      finalCoverageAssertion > allowlistRewrite,
    "The reviewed handler must be allowlisted before final catalog enforcement.",
  );
  assert(
    !sql.includes("EXECUTE policy.handler_key"),
    "Handler documentation must never become dynamically executable SQL.",
  );

  const assertionStart = ghostMergeSql.indexOf(
    "CREATE OR REPLACE FUNCTION internal.assert_ghost_profile_merge_reference_policy_coverage()",
  );
  const assertionEnd = ghostMergeSql.indexOf(
    "CREATE OR REPLACE FUNCTION internal.assert_ghost_profile_merge_reference_preconditions(",
    assertionStart,
  );
  assert(assertionStart >= 0 && assertionEnd > assertionStart);
  const assertionSource = ghostMergeSql.slice(assertionStart, assertionEnd);
  const guardedFragment = "              'community_activity_actors',";
  assertEquals(assertionSource.split(guardedFragment).length - 1, 1);
  assertEquals(assertionSource.includes("'complimentary_scan_usage'"), false);
  assertStringIncludes(
    assertionSource.replace(
      guardedFragment,
      `${guardedFragment}\n              'complimentary_scan_usage',`,
    ),
    "              'complimentary_scan_usage',",
  );
});

Deno.test("current admin account views and overview telemetry use effective complimentary entitlement", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const cutover = compact(
    await Deno.readTextFile(
      new URL(
        "../../scripts/cutover_complimentary_entitlements.sql",
        import.meta.url,
      ),
    ),
  );
  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.effective_plan_for_user_or_free",
      "'admin_get_overview', 'admin_list_users', 'admin_get_user_detail'",
      "'''pro_complimentary'', COUNT(*) FILTER",
      "''complimentary_entitlement'', (",
      "''complimentary_usage'', (",
      "CREATE OR REPLACE FUNCTION public.admin_complimentary_entitlement_summary",
      "'stale_holds_15m'",
      "'flash_fallback_reservations'",
      "'available_balance_histogram'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assertStringIncludes(
    cutover,
    "DELETE FROM internal.admin_aggregate_cache WHERE cache_key LIKE 'overview:%'",
  );

  const summary = sql.slice(
    sql.indexOf(
      "CREATE OR REPLACE FUNCTION public.admin_complimentary_entitlement_summary",
    ),
  );
  assertStringIncludes(summary, "entitlement.is_paid");
  assertStringIncludes(
    summary,
    "WHERE per_user.scans_remaining = 0 AND per_user.is_paid",
  );
});

Deno.test("all four public identification routes share protocol, linkage, and fallback fences", async () => {
  const routes = [
    "../identify/index.ts",
    "../identify-describe/index.ts",
    "../identify-multimodal/index.ts",
    "../audio-spec/index.ts",
  ];
  for (const route of routes) {
    const source = await Deno.readTextFile(new URL(route, import.meta.url));
    assertStringIncludes(source, "await entitlementProtocolResponse(");
    assertStringIncludes(source, "originalAnalysisId:");
    assertStringIncludes(source, "flashFallbackEligible:");
    assertStringIncludes(source, "isFlashFallbackEligible(");
  }

  const multimodal = await Deno.readTextFile(
    new URL("../identify-multimodal/index.ts", import.meta.url),
  );
  assertStringIncludes(multimodal, "if (internalReplayAttempt == null)");
  assertStringIncludes(
    multimodal,
    "internalReplay: internalReplayAttempt != null",
  );
  assertStringIncludes(
    multimodal,
    "videoCount: mediaTelemetry.hasVideo ? 1 : 0",
  );
  assertStringIncludes(
    multimodal,
    "descriptionCount: observationEvidenceTexts.length",
  );

  const compatibilityIdentify = await Deno.readTextFile(
    new URL("../identify/index.ts", import.meta.url),
  );
  assertStringIncludes(
    compatibilityIdentify,
    "description.trim().length > 0",
  );
});

Deno.test("enrichment and chat provider calls retain the original analysis linkage", async () => {
  const linkedSources = new Map([
    ["../_shared/groupTagQuota.ts", "originalAnalysisId: parentRequestId"],
    ["../enrich-scan/index.ts", "originalAnalysisId,"],
    ["../insight-chat/index.ts", "originalAnalysisId: scanId"],
    [
      "../explore-post-chat/index.ts",
      "originalAnalysisId: context.post.scan_id",
    ],
  ]);
  for (const [path, marker] of linkedSources) {
    assertStringIncludes(
      await Deno.readTextFile(new URL(path, import.meta.url)),
      marker,
    );
  }
});

Deno.test("recovery workers cannot bypass complimentary settlement", async () => {
  for (
    const path of [
      "../replay-scan-ingestion/db.ts",
      "../reconcile-scan-media-assets/db.ts",
    ]
  ) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assertStringIncludes(source, '"complete_scan_ingestion_with_entitlement"');
    assertStringIncludes(source, '"fail_scan_ingestion_terminal"');
    if (source.includes('"complete_scan_ingestion_finalization"')) {
      throw new Error(`${path} still calls the lower-level finalizer`);
    }
  }
});

Deno.test("catalog fixture exercises the audited credit boundary", async () => {
  const fixture = compact(
    await Deno.readTextFile(
      new URL(
        "../../tests/complimentary_pro_scans_security.sql",
        import.meta.url,
      ),
    ),
  );
  for (
    const marker of [
      "three atomic complimentary holds returned invalid state",
      "fourth compatible scan did not use the separate daily Flash policy",
      "exhausted Pro-only scan unexpectedly fell back",
      "ambiguous/provider failure incorrectly released a hold",
      "terminal release erased provider quota accounting",
      "lower-level terminal settlement unexpectedly bypassed the orchestrator",
      "valid non-biological completion did not consume its hold",
      "purchase-before-settlement did not preserve the credit",
      "paid scan changed complimentary-credit history",
      "merge added grants, lost consumption, or retained excess holds",
    ]
  ) {
    assertStringIncludes(fixture, marker);
  }
  assertEquals(
    (fixture.match(/FROM public.reserve_ai_quota\(/g) ?? []).length >= 5,
    true,
  );
});

Deno.test("replay exhaustion and scan deletion cannot bypass user-first terminal settlement", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const replayStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.claim_replayable_scan_ingestion_jobs",
  );
  const deletionStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.request_scan_deletion",
    replayStart,
  );
  const mergeStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION internal.merge_ghost_complimentary_scan_usage",
    deletionStart,
  );
  assert(
    replayStart >= 0 && deletionStart > replayStart &&
      mergeStart > deletionStart,
  );
  const replay = sql.slice(replayStart, deletionStart);
  const deletion = sql.slice(deletionStart, mergeStart);

  assertStringIncludes(replay, "PERFORM internal.require_service_role()");
  const replayTerminalCall =
    "PERFORM public.fail_scan_ingestion_terminal( over_budget_job.scan_id::UUID, over_budget_job.user_id, 'server_replay_limit_reached', 'Server replay retry limit reached after 10 attempts.', 'replay_exhausted' )";
  assertStringIncludes(replay, replayTerminalCall);
  assert(
    replay.indexOf(replayTerminalCall) <
      replay.indexOf("FOR UPDATE OF jobs SKIP LOCKED"),
    "Replay terminal settlement must happen before any retryable job locks.",
  );

  const userLock = deletion.indexOf(
    "FROM public.users AS users WHERE users.id = p_user_id FOR UPDATE",
  );
  const advisoryLock = deletion.indexOf("PG_ADVISORY_XACT_LOCK");
  const terminalSettlement = deletion.indexOf(
    "PERFORM public.fail_scan_ingestion_terminal(",
  );
  assert(
    userLock >= 0 && advisoryLock > userLock &&
      terminalSettlement > advisoryLock,
    "Scan deletion no longer follows user -> advisory/scan -> terminal settlement order.",
  );
});

Deno.test("disposable database coverage overlaps three complimentary holds behind one user lock", async () => {
  const source = await Deno.readTextFile(
    new URL("./complimentaryScansConcurrencyDb.test.ts", import.meta.url),
  );
  for (
    const marker of [
      "callPromises = callers.map",
      "waitUntilAllCallersBlocked",
      "expected three overlapping lock waiters",
      "three concurrent holds did not leave the expected derived balance",
      "fourth concurrent-test scan did not use Flash fallback",
    ]
  ) {
    assertStringIncludes(source, marker);
  }
});
