import { assert, assertEquals } from "@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261011173412_extract_initial_assignment_policy_selectors.sql",
    import.meta.url,
  ),
);

Deno.test("assignment selectors have no funding or execution authority", () => {
  const helpers = migration.split("DO $migration$")[0];
  assertEquals([...helpers.matchAll(/CREATE FUNCTION internal\./g)].length, 2);
  assertEquals([...helpers.matchAll(/SECURITY INVOKER/g)].length, 2);
  assertEquals([...helpers.matchAll(/FOR SHARE;/g)].length, 2);
  assert(
    !/\b(?:INSERT|UPDATE|DELETE|set_config|SECURITY DEFINER)\b/.test(helpers),
  );
  assert(helpers.includes("FROM PUBLIC,anon,authenticated,service_role"));
  assert(!migration.includes("GRANT EXECUTE"));
  assert(!migration.includes("UPDATE internal.initial_analysis_rollout"));
});

Deno.test("assignment extraction is guarded and leaves lifecycle decisions in owners", () => {
  const policy =
    migration.split("old_fragment := $policy$")[1].split("$policy$;")[0];
  const binding =
    migration.split("old_fragment := $binding$")[1].split("$binding$;")[0];
  for (const fragment of [policy, binding]) {
    assert(!/\b(?:INSERT|UPDATE|DELETE|set_config|PERFORM)\b/.test(fragment));
    assert(
      !/reservation_row|is_replay|accepted_protocol|require_.*consent/.test(
        fragment,
      ),
    );
  }
  assertEquals(
    [...migration.matchAll(/\/ pg_catalog.length\(old_fragment\) <> 1/g)]
      .length,
    2,
  );
  assert(migration.includes("initial assignment policy source drift"));
  assert(migration.includes("initial assignment binding source drift"));
});
