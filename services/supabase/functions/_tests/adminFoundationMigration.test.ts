import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260719161112_add_internal_admin_foundation.sql",
  import.meta.url,
);
const sql = await Deno.readTextFile(migrationUrl);

Deno.test("admin foundation is deny-by-default and app has no table grants", () => {
  assertStringIncludes(
    sql,
    "REVOKE ALL ON SCHEMA internal FROM PUBLIC, anon, authenticated",
  );
  assertStringIncludes(
    sql,
    "REVOKE ALL ON ALL TABLES IN SCHEMA internal FROM PUBLIC, anon, authenticated",
  );
  assertStringIncludes(
    sql,
    "REVOKE ALL ON TABLE public.ai_usage_events FROM PUBLIC, anon, authenticated",
  );
  assertStringIncludes(
    sql,
    "GRANT EXECUTE ON FUNCTION public.admin_get_access_state() TO authenticated",
  );
  assert(!/GRANT\s+(SELECT|INSERT|UPDATE|DELETE).*internal\./i.test(sql));
});

Deno.test("every admin RPC uses a hardened authorization boundary", () => {
  const definitions = [
    ...sql.matchAll(
      /CREATE OR REPLACE FUNCTION public\.(admin_[a-z_]+)\([^]*?\n\$\$;/g,
    ),
  ];
  assert(definitions.length >= 15);
  for (const definition of definitions) {
    const [body, name] = definition;
    assertStringIncludes(body, "SECURITY DEFINER", name);
    assertStringIncludes(body, "SET search_path = ''", name);
    if (name !== "admin_get_access_state" && name !== "admin_begin_session") {
      assertStringIncludes(body, "internal.require_admin(", name);
    }
  }
});

Deno.test("AAL2, Google identity, session expiry, and final-owner protections are explicit", () => {
  for (
    const contract of [
      "caller_aal <> 'aal2'",
      "identity.provider = 'google'",
      "session_row.last_seen_at > NOW() - INTERVAL '30 minutes'",
      "session_row.expires_at > NOW()",
      "The final active owner cannot be disabled or demoted.",
    ]
  ) assertStringIncludes(sql, contract);
});

Deno.test("AI ledger is append-only, priced, anonymized, and idempotently backfilled", () => {
  assertStringIncludes(sql, "AI usage events are append-only.");
  assertStringIncludes(sql, "internal.estimate_ai_cost_microusd");
  assertStringIncludes(
    sql,
    "PERFORM set_config('internal.ai_usage_anonymizing', 'on', TRUE)",
  );
  assertEquals(
    (sql.match(
      /ON CONFLICT \(source_type, source_id, operation\) DO NOTHING/g,
    ) ?? []).length >= 3,
    true,
  );
  assertStringIncludes(
    sql,
    "coverage_scope IN ('complete', 'primary_only', 'partial')",
  );
});

Deno.test("review grouping and reversible moderation contracts are present", () => {
  assertStringIncludes(sql, "UNIQUE (case_type, subject_id)");
  assertStringIncludes(sql, "independent_reporter BOOLEAN");
  assertStringIncludes(sql, "AND independent_reporter");
  assertStringIncludes(
    sql,
    "status = CASE WHEN status IN ('resolved', 'dismissed') THEN 'open'",
  );
  assertStringIncludes(sql, "moderated_at");
  assertStringIncludes(sql, "'explore_projected_post_cards'");
  assertStringIncludes(sql, "'can_view_explore_author_profile'");
  assertStringIncludes(
    sql,
    "CASE WHEN p_hidden THEN 'content_hidden' ELSE 'content_restored' END",
  );
  assertStringIncludes(sql, "review.status IN ('open', 'in_review')");
});

Deno.test("raw lists use capped cursor pagination and immutable internal history", () => {
  assertStringIncludes(
    sql,
    "safe_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100)",
  );
  assertStringIncludes(sql, "p_cursor_updated_at TIMESTAMPTZ DEFAULT NULL");
  assertStringIncludes(sql, "p_cursor_created_at TIMESTAMPTZ DEFAULT NULL");
  assert(!/\bOFFSET\b/i.test(sql));
  assertStringIncludes(sql, "Admin audit records are immutable.");
  assertStringIncludes(sql, "Admin notes are append-only.");
});
