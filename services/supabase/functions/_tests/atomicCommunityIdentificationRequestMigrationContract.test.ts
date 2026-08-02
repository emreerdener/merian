import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260729033000_atomic_community_identification_requests.sql",
  import.meta.url,
);
const requestDbUrl = new URL(
  "../request-community-identification/db.ts",
  import.meta.url,
);
const requestIndexUrl = new URL(
  "../request-community-identification/index.ts",
  import.meta.url,
);
const restoredMediaValidationUrl = new URL(
  "../share-scan-to-explore/restoredMediaValidation.ts",
  import.meta.url,
);
const databaseCatalogUrl = new URL(
  "../../tests/atomic_community_identification_request_security.sql",
  import.meta.url,
);

function compact(source: string): string {
  return source.replaceAll(/\s+/g, " ").trim();
}

Deno.test("Community request transaction is invoker-scoped and service-only", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.request_community_identification_atomically",
      "RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = ''",
      "REVOKE ALL ON FUNCTION public.request_community_identification_atomically",
      "FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.request_community_identification_atomically",
      "TO service_role",
      "SET lock_timeout = '10s'",
      "SET statement_timeout = '2min'",
      "RESET statement_timeout",
      "RESET lock_timeout",
      "NOTIFY pgrst, 'reload schema'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Community request transaction locks request then exact owner scan", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const requestLock =
    "FROM public.explore_community_requests AS community_request " +
    "WHERE community_request.scan_id = p_scan_id";
  const scanLock = "FROM public.scans AS scan WHERE scan.id = p_scan_id " +
    "AND scan.user_id = p_user_id";
  const requestLockIndex = sql.indexOf(requestLock);
  const scanLockIndex = sql.indexOf(scanLock);

  assert(requestLockIndex >= 0, "Missing Community request lock.");
  assert(scanLockIndex >= 0, "Missing exact-owner scan lock.");
  assert(
    requestLockIndex < scanLockIndex,
    "Existing Community request must be locked before its scan.",
  );
  for (
    const fragment of [
      "AND NOT scan.is_tombstoned",
      "scan.confirmed_species_id IS NOT NULL OR scan.species_id IS NOT NULL",
      "FOR UPDATE OF scan",
      "Initial taxon does not match the owner scan",
      "taxon_node.species_id = v_scan_species_id",
      "Community request post ownership does not match the scan",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Explore snapshot and needs-ID request commit in one routine transaction", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const catalog = await Deno.readTextFile(databaseCatalogUrl);
  const orderedFragments = [
    "v_publication := public.publish_scan_to_explore_atomically",
    "v_post_id := (v_publication ->> 'post_id')::UUID",
    "INSERT INTO public.explore_community_requests",
  ];
  let previousIndex = -1;

  for (const fragment of orderedFragments) {
    const index = sql.indexOf(fragment);
    assert(index >= 0, `Missing atomic request fragment: ${fragment}`);
    assert(
      index > previousIndex,
      `Atomic request fragment is out of order: ${fragment}`,
    );
    previousIndex = index;
  }
  assert(
    sql.lastIndexOf("RETURN pg_catalog.TO_JSONB(v_request)") > previousIndex,
    "Create/reopen must return only after the request write.",
  );
  for (
    const reset of [
      "explore_published_at = NULL",
      "consensus_processing_state = 'idle'",
      "last_consensus_job_id = NULL",
      "DELETE FROM public.community_consensus_jobs",
      "identification.withdrawn_at IS NULL",
    ]
  ) {
    assertStringIncludes(sql, reset);
  }
  assertStringIncludes(catalog, "SELECT extensions.plan(25)");
  assertStringIncludes(
    catalog,
    "late request failure aborts the complete Community transaction",
  );
  assertStringIncludes(
    catalog,
    "reopen clears stale publication, consensus, and worker state",
  );
  assert(
    catalog.match(/^SELECT extensions\.(?:ok|is|throws_ok)\(/gm)?.length ===
      25,
    "Atomic Community pgTAP plan must match its executable assertions.",
  );
});

Deno.test("concurrent needs-ID creation rejects a late Explore republish", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.reject_needs_id_explore_republication()",
      "SECURITY DEFINER SET search_path = ''",
      "REVOKE ALL ON FUNCTION internal.reject_needs_id_explore_republication()",
      "BEFORE UPDATE OF shared_at ON public.explore_posts",
      "community_request.scan_id = NEW.scan_id",
      "community_request.status = 'needs_id'",
      "Wait for the community to identify this request before sharing it to Explore.",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Community request Edge DB code has one final relational mutation", async () => {
  const source = await Deno.readTextFile(requestDbUrl);

  assertStringIncludes(
    source,
    'supabaseAdmin.rpc(\n    "request_community_identification_atomically"',
  );
  assertStringIncludes(source, "Failed to synchronize taxonomy nodes");
  assertStringIncludes(source, "isCommunityRequestRow(data)");
  assertStringIncludes(source, "isTimestamp(row.requested_at)");
  assertStringIncludes(
    source,
    "communityRequestMatchesIdentity(data, scanId, userId)",
  );
  assertStringIncludes(
    source,
    "row.scan_id.toLowerCase() === scanId.toLowerCase()",
  );
  assertStringIncludes(
    source,
    "row.requested_by.toLowerCase() === userId.toLowerCase()",
  );
  assertStringIncludes(source, 'result.error?.code === "P0001"');
  assertStringIncludes(
    source,
    "result.error.message === COMMUNITY_IDENTIFICATION_PENDING_MESSAGE",
  );
  assert(
    !source.includes("upsertExplorePost") &&
      !source.includes('.from("explore_posts")') &&
      !source.includes('.from("explore_post_media")') &&
      !source.includes('.from("explore_community_requests")'),
    "Separate Community publication mutations returned to Edge code.",
  );
});

Deno.test("Community repair validates and forwards every supported media kind", async () => {
  const [requestIndex, requestDb, restoredMediaValidation] = await Promise.all([
    Deno.readTextFile(requestIndexUrl),
    Deno.readTextFile(requestDbUrl),
    Deno.readTextFile(restoredMediaValidationUrl),
  ]);
  const compactIndex = compact(requestIndex);
  const compactDb = compact(requestDb);
  const compactValidation = compact(restoredMediaValidation);

  assertStringIncludes(
    compactIndex,
    'from "../share-scan-to-explore/restoredMediaValidation.ts"',
  );
  for (
    const fragment of [
      "normalizeRestoredMediaObjectKeys(body, user.id)",
      "restoredVideoObjectKeys, restoredAudioObjectKeys, supabaseAdmin",
    ]
  ) {
    assertStringIncludes(compactIndex, fragment);
  }
  for (
    const fragment of [
      "body.restored_object_keys",
      "body.restored_video_object_keys",
      "MEDIA_BUDGETS.maxStagedVideoFiles",
      "body.restored_audio_object_keys",
      "MEDIA_BUDGETS.maxStagedAudioFiles",
      "combinedKeys.length > MEDIA_BUDGETS.maxStagingFiles",
      "new Set(combinedKeys).size !== combinedKeys.length",
      '.from("scan_media_assets")',
      '.eq("source", "capture_upload")',
      "row.client_scan_id?.toLowerCase() === canonicalScanId",
      "row.kind === expected.kind",
      "row.role === expected.role",
    ]
  ) {
    assertStringIncludes(compactValidation, fragment);
  }
  assertStringIncludes(
    compactDb,
    "restoredObjectKeys, restoredVideoObjectKeys, restoredAudioObjectKeys, supabaseAdmin",
  );
});
