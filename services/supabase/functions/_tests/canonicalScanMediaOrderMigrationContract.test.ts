import { assertStringIncludes } from "@std/assert";

const migration = new URL(
  "../../migrations/20260815145546_preserve_canonical_scan_media_order.sql",
  import.meta.url,
);
const repairMigration = new URL(
  "../../migrations/20260819194047_repair_canonical_scan_media_order_alignment.sql",
  import.meta.url,
);

function compact(source: string): string {
  return source.replaceAll(/--.*$/gm, "").replaceAll(/\s+/g, " ").trim();
}

Deno.test("canonical scan media order migration preserves the hardened refresh boundary", async () => {
  const sql = compact(await Deno.readTextFile(migration));
  for (
    const fragment of [
      "SET lock_timeout = '5s'",
      "SET statement_timeout = '60s'",
      "CREATE OR REPLACE FUNCTION internal.align_scan_media_asset_order",
      "SECURITY INVOKER SET search_path = ''",
      "media_manifest IS NULL",
      "JSONB_TYPEOF(media_manifest) IS DISTINCT FROM 'array'",
      "JSONB_ARRAY_ELEMENTS(media_manifest) WITH ORDINALITY",
      "public.scan_media_reference_path(raw.media_item #> '{audio,_0}')",
      "ROW_NUMBER() OVER ( PARTITION BY manifest.kind, manifest.url",
      "REVOKE ALL ON FUNCTION internal.align_scan_media_asset_order(UUID) FROM PUBLIC, anon, authenticated, service_role",
      "CREATE OR REPLACE FUNCTION public.refresh_scan_media_assets",
      "SECURITY DEFINER SET search_path = ''",
      "PERFORM internal.require_service_role()",
      "PERFORM internal.align_scan_media_asset_order(target_scan_id)",
      "GRANT EXECUTE ON FUNCTION public.refresh_scan_media_assets(UUID) TO service_role",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("canonical media catalog fixture covers description gaps", async () => {
  const fixture = compact(
    await Deno.readTextFile(
      new URL("../../tests/canonical_scan_media_order.sql", import.meta.url),
    ),
  );
  assertStringIncludes(
    fixture,
    "ARRAY['audio:1', 'image:2', 'video:4']::TEXT[]",
  );
  assertStringIncludes(fixture, "ON CONFLICT (id) DO UPDATE");
  assertStringIncludes(
    fixture,
    "canonical alignment neither drops nor duplicates owner media",
  );
  assertStringIncludes(
    fixture,
    "legacy array refresh bypasses canonical alignment without nulling order",
  );
  assertStringIncludes(
    fixture,
    "ready media realigns when non-ready rows occupy canonical and temporary positions",
  );
  assertStringIncludes(
    fixture,
    "ARRAY['staged:5', 'failed:6']::TEXT[]",
  );
});

Deno.test("canonical media order repair reserves and compacts every generated lifecycle row", async () => {
  const sql = compact(await Deno.readTextFile(repairMigration));
  for (
    const fragment of [
      "SET lock_timeout = '5s'",
      "SET statement_timeout = '60s'",
      "CREATE OR REPLACE FUNCTION internal.align_scan_media_asset_order",
      "SECURITY INVOKER SET search_path = ''",
      "COUNT(*) FILTER ( WHERE asset.status = 'ready' )",
      "manifest_length::BIGINT + pg_catalog.COUNT(*)::BIGINT + 1",
      "PARTITION BY asset.source, asset.role ORDER BY asset.order_index, asset.id ) AS temporary_rank FROM public.scan_media_assets AS asset WHERE asset.scan_id = target_scan_id AND asset.source IN ('scan_refresh', 'backfill')",
      "asset.status <> 'ready'",
      "LEFT JOIN ready_ceiling ON ready_ceiling.source = ranked_non_ready.source AND ready_ceiling.role = ranked_non_ready.role",
      "preserves non-ready lifecycle rows after the ready timeline",
      "REVOKE ALL ON FUNCTION internal.align_scan_media_asset_order(UUID) FROM PUBLIC, anon, authenticated, service_role",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});
