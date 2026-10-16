import { assert, assertStringIncludes } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261006101459_preserve_chat_context_semantics.sql",
    import.meta.url,
  ),
);
Deno.test("chat semantic projection preserves nullness and qualifies untouched metadata without rewriting history", () => {
  for (
    const marker of [
      "CREATE OR REPLACE FUNCTION internal.insight_chat_context_projection",
      "SECURITY INVOKER SET search_path = ''",
      "items:='null'::JSONB",
      "ARRAY['taxon_rank','scientific_name'",
      "source?'identification_provenance'",
      "NULLIF(source->'identification_provenance','null'::JSONB)",
      "FROM PUBLIC, anon, authenticated, service_role",
      "RESET lock_timeout",
      "RESET statement_timeout",
    ]
  ) assertStringIncludes(sql, marker);
  for (
    const forbidden of [
      "UPDATE internal.",
      "INSERT INTO",
      "chat_context_enabled=TRUE",
      "GRANT EXECUTE",
    ]
  ) {
    assert(!sql.includes(forbidden), forbidden);
  }
});
