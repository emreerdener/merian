import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260803180211_harden_collection_ownership_and_memberships.sql",
  import.meta.url,
);

function compact(source: string): string {
  return source.replaceAll(/--.*$/gm, "").replaceAll(/\s+/g, " ").trim();
}

Deno.test("collection ownership upsert is atomic, owner-guarded, and service-only", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.upsert_owned_collections( p_user_id UUID, p_collections JSONB )",
      "SECURITY INVOKER SET search_path = ''",
      "INSERT INTO public.collections AS existing",
      "ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, created_at = EXCLUDED.created_at WHERE existing.user_id = EXCLUDED.user_id",
      "written.id IS NOT NULL",
      "REVOKE ALL ON FUNCTION public.upsert_owned_collections(UUID, JSONB) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.upsert_owned_collections(UUID, JSONB) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("SET user_id = EXCLUDED.user_id"),
    "A UUID collision must never reparent an existing collection.",
  );
});

Deno.test("collection memberships require two owner-matched parents at every write boundary", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "DELETE FROM public.collection_scans AS membership USING public.collections AS collection, public.scans AS scan",
      "collection.user_id IS DISTINCT FROM scan.user_id",
      "CREATE OR REPLACE FUNCTION public.insert_owned_collection_scans( p_user_id UUID, p_rows JSONB )",
      "collection.user_id = p_user_id JOIN public.scans AS scan",
      "scan.user_id = p_user_id",
      "CREATE TRIGGER enforce_collection_scan_owner_match BEFORE INSERT OR UPDATE OF collection_id, scan_id ON public.collection_scans",
      'CREATE POLICY "Users can read their own collection scans"',
      'CREATE POLICY "Users can delete their own collection scans"',
      'CREATE POLICY "Users can add scans to their own collections"',
      "scan.user_id = (SELECT auth.uid())",
      "GRANT EXECUTE ON FUNCTION public.insert_owned_collection_scans(UUID, JSONB) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("service collection writes cannot update ownership directly", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "REVOKE UPDATE ON TABLE public.collections FROM service_role",
      "REVOKE UPDATE (id, user_id, name, created_at) ON TABLE public.collections FROM service_role",
      "GRANT UPDATE (name, created_at) ON TABLE public.collections TO service_role",
      "SET lock_timeout = '5s'",
      "SET statement_timeout = '30s'",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});
