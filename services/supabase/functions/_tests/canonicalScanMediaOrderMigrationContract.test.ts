import { assertStringIncludes } from "@std/assert";

const migration = new URL(
  "../../migrations/20260815145546_preserve_canonical_scan_media_order.sql",
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
  assertStringIncludes(
    fixture,
    "canonical alignment neither drops nor duplicates owner media",
  );
  assertStringIncludes(
    fixture,
    "legacy array refresh bypasses canonical alignment without nulling order",
  );
});
