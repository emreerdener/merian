import { assert, assertEquals } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261009000303_prepare_source_reservation_and_unfunded_retirement.sql",
    import.meta.url,
  ),
);
Deno.test("source reservation and unfunded retirement stay service-only with closed independent gates", () => {
  for (
    const gate of [
      "source_reservation_enabled",
      "source_unfunded_retirement_enabled",
    ]
  ) assert(sql.includes(`${gate} BOOLEAN NOT NULL DEFAULT FALSE`));
  assertEquals(
    (sql.match(/PERFORM internal.require_service_role\(\)/g) ?? []).length,
    2,
  );
  assertEquals((sql.match(/GRANT EXECUTE/g) ?? []).length, 2);
  assert(!/TO authenticated|TO anon|cron\.(?:schedule|unschedule)/.test(sql));
  assert(sql.includes("analysis_id UUID NOT NULL UNIQUE"));
  assert(
    sql.includes(
      "REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE",
    ),
  );
});
Deno.test("source absence and replay retain canonical identity and bounded inventory", () => {
  assert(sql.includes("internal.source_child_uuid(scan_id)=p_analysis"));
  assertEquals((sql.match(/LIMIT 65/g) ?? []).length, 7);
  assert(sql.includes("internal.observation_source_release_proven(binding)"));
  const retire = sql.slice(
    sql.indexOf(
      "CREATE FUNCTION public.retire_owned_observation_analysis_source",
    ),
  );
  assert(
    retire.indexOf("RETURN prior.receipt") <
      retire.indexOf("SELECT source_unfunded_retirement_enabled"),
  );
  assert(
    retire.indexOf(
      "INSERT INTO internal.observation_source_unfunded_retirements",
    ) <
      retire.indexOf(
        "DELETE FROM internal.observation_analysis_source_occupancy",
      ),
  );
  assert(!retire.includes("finalize_ai_quota"));
});
