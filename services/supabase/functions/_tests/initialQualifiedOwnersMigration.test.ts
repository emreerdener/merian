import { assert, assertEquals } from "@std/assert";

const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261012000419_qualify_initial_preparation_owners.sql",
    import.meta.url,
  ),
);
Deno.test("qualified owner cutover preserves the funding and activation boundary", () => {
  assert(
    !/GRANT EXECUTE|SET initial_analysis_lifecycle_enabled=TRUE/.test(sql),
  );
  assert(
    !/CREATE OR REPLACE FUNCTION (?:internal|public)\.(?:finalize_initial_preparation|admit_initial_analysis|authorize_initial_analysis_dispatch|lock_initial_media_scope|guard_initial_lifecycle_fence)/
      .test(sql),
  );
  assert(!/INSERT INTO internal\.initial_preparation_handoff_/.test(sql));
  assert(sql.includes("'blocked_pre_admission'"));
  assert(sql.includes("FROM PUBLIC,anon,authenticated,service_role"));
});
Deno.test("qualified runtime fixtures share the same synthetic installation helper", async () => {
  const texts = await Promise.all(
    ["initial_media_source_lifecycle.sql", "initial_preparation_execution.sql"]
      .map((name) =>
        Deno.readTextFile(new URL(`../../tests/${name}`, import.meta.url))
      ),
  );
  const helper = (text: string) =>
    text.split("-- BEGIN QUALIFIED HANDOFF FIXTURE")[1]?.split(
      "-- END QUALIFIED HANDOFF FIXTURE",
    )[0];
  assert(helper(texts[0]));
  assertEquals(helper(texts[0]), helper(texts[1]));
});
