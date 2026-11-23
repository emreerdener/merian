import { assert, assertEquals } from "@std/assert";

Deno.test("accepted initial pruning preserves original rows without introducing recovery authority", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261121002834_preserve_accepted_initial_finalization_inputs.sql",
      import.meta.url,
    ),
  );
  assertEquals(
    (sql.match(/CREATE TRIGGER a_preserve_accepted_initial_finalization/g) ??
      []).length,
    2,
  );
  for (
    const guard of [
      "accepted_result IS NOT NULL AND sealed_at IS NULL AND retired_at IS NULL",
      "internal.account_deletion_jobs",
      "internal.scan_deletion_tombstones",
      "EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id)",
      "RETURN NULL;",
      "FROM PUBLIC,anon,authenticated,service_role",
      "SET search_path=''",
    ]
  ) assert(sql.includes(guard), guard);
  const body = sql.split("AS $$")[1].split("$$;")[0];
  assert(
    !/\b(?:INSERT|UPDATE|DELETE\s+FROM|FOR\s+UPDATE)\b/.test(
      body.replace(/--[^\n]*/g, ""),
    ),
  );
  assert(!sql.includes("GRANT EXECUTE"));
});
