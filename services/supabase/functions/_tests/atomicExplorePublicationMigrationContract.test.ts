import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260729024157_atomic_explore_scan_publication.sql",
  import.meta.url,
);
const dbSourceUrl = new URL(
  "../share-scan-to-explore/db.ts",
  import.meta.url,
);
const routeSourceUrl = new URL(
  "../share-scan-to-explore/index.ts",
  import.meta.url,
);

function compact(source: string): string {
  return source.replaceAll(/\s+/g, " ").trim();
}

Deno.test("atomic Explore publication is invoker-scoped and service-only", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.publish_scan_to_explore_atomically",
      "RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = ''",
      "REVOKE ALL ON FUNCTION public.publish_scan_to_explore_atomically",
      "FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.publish_scan_to_explore_atomically",
      "TO service_role",
      "SET lock_timeout = '10s'",
      "SET statement_timeout = '2min'",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("SECURITY DEFINER"),
    "The final publication RPC must retain service-role invoker privileges.",
  );
});

Deno.test("atomic Explore publication revalidates and locks the exact owner scan", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "FROM public.scans AS scan WHERE scan.id = p_scan_id AND scan.user_id = p_user_id",
      "AND NOT scan.is_tombstoned",
      "scan.confirmed_species_id IS NOT NULL OR scan.species_id IS NOT NULL",
      "FOR UPDATE",
      "scan.geoprivacy::TEXT",
      "v_location_sharing := COALESCE(p_location_sharing, v_scan_geoprivacy)",
      "RAISE EXCEPTION 'Owned share-eligible scan not found'",
      "WHERE existing.user_id = EXCLUDED.user_id",
      "RAISE EXCEPTION 'Explore post ownership does not match the scan'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("atomic Explore publication preserves community-request lock order", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const requestLock =
    "FROM public.explore_community_requests AS community_request " +
    "WHERE community_request.scan_id = p_scan_id " +
    "AND community_request.requested_by = p_user_id " +
    "FOR UPDATE OF community_request";
  const scanLock = "FROM public.scans AS scan WHERE scan.id = p_scan_id " +
    "AND scan.user_id = p_user_id";
  const requestLockIndex = sql.indexOf(requestLock);
  const scanLockIndex = sql.indexOf(scanLock);

  assert(requestLockIndex >= 0, "Missing owner community-request lock.");
  assert(scanLockIndex >= 0, "Missing exact owner scan lock.");
  assert(
    requestLockIndex < scanLockIndex,
    "Community request must be locked before its scan to prevent deadlocks.",
  );
  assertStringIncludes(
    sql,
    "IF v_community_request_status = 'needs_id' THEN RAISE EXCEPTION " +
      "'Wait for the community to identify this request before sharing it to Explore.'",
  );
});

Deno.test("atomic Explore publication validates exact bounded media and hashtags", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "IF v_media_count < 1 OR v_media_count > 6",
      "IF pg_catalog.CARDINALITY(v_hashtags) > 5",
      "Duplicate Explore hashtags are not permitted",
      "v_media_item ?& ARRAY[",
      "Explore media order must be unique and contiguous",
      "FROM pg_catalog.UNNEST(v_image_urls) AS source_image(url)",
      "FROM pg_catalog.UNNEST(v_video_urls) AS source_video(url)",
      "FROM pg_catalog.UNNEST(v_audio_urls) AS source_audio(url)",
      "FROM pg_catalog.UNNEST(v_image_urls) AS source_thumbnail(url)",
      "pg_catalog.BTRIM(media.url)",
      "pg_catalog.BTRIM(media.thumbnail_url)",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("post, media, hashtags, and community state share one routine body", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const orderedFragments = [
    "INSERT INTO public.explore_posts AS existing",
    "DELETE FROM public.explore_post_media AS media",
    "INSERT INTO public.explore_post_media",
    "DELETE FROM public.explore_post_hashtags AS hashtag",
    "INSERT INTO public.explore_post_hashtags",
    "PERFORM public.publish_resolved_community_request_to_explore",
    "RETURN pg_catalog.JSONB_BUILD_OBJECT",
  ];
  let previousIndex = -1;

  for (const fragment of orderedFragments) {
    const index = sql.indexOf(fragment);
    assert(index >= 0, `Missing publication fragment: ${fragment}`);
    assert(
      index > previousIndex,
      `Publication fragment is out of order: ${fragment}`,
    );
    previousIndex = index;
  }
});

Deno.test("Explore Edge code uses only the atomic final publication mutation", async () => {
  const [dbSource, routeSource] = await Promise.all([
    Deno.readTextFile(dbSourceUrl),
    Deno.readTextFile(routeSourceUrl),
  ]);

  assertStringIncludes(
    dbSource,
    'supabaseAdmin.rpc(\n    "publish_scan_to_explore_atomically"',
  );
  assertStringIncludes(routeSource, "publishExplorePostAtomically(");
  for (
    const obsoleteMutation of [
      '.from("explore_posts")',
      '.from("explore_post_media")',
      '.from("explore_post_hashtags")',
      "replaceExplorePostMediaRows",
      "replaceExplorePostHashtags",
      "markResolvedCommunityRequestPublishedToExplore",
    ]
  ) {
    assert(
      !dbSource.includes(obsoleteMutation) &&
        !routeSource.includes(obsoleteMutation),
      `Separate Explore mutation path remains: ${obsoleteMutation}`,
    );
  }
});

Deno.test("atomic publication result is confirmed before HTTP success", async () => {
  const [dbSource, routeSource] = await Promise.all([
    Deno.readTextFile(dbSourceUrl).then(compact),
    Deno.readTextFile(routeSourceUrl).then(compact),
  ]);

  for (
    const fragment of [
      'row.publication_status === "published"',
      'row.location_sharing === "private"',
      "!isAtomicExplorePublicationResult(data)",
      "location_sharing: post.location_sharing",
      "publication_status: post.publication_status",
    ]
  ) {
    assert(
      dbSource.includes(fragment) || routeSource.includes(fragment),
      `Missing publication confirmation: ${fragment}`,
    );
  }

  assertEquals(
    (routeSource.match(/publication_status: post\.publication_status/g) ?? [])
      .length,
    1,
  );
});
