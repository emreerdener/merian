import { assert, assertEquals } from "@std/assert";
import profile from "../_shared/initialAnalysis/media-preparation-profile-schema-v1.json" with {
  type: "json",
};
import assignment from "../_shared/initialAnalysis/media-assignment-schema-v2.json" with {
  type: "json",
};
import response from "../_shared/initialAnalysis/media-preparation-response-schema-v2.json" with {
  type: "json",
};
import vectors from "../_shared/initialAnalysis/fixtures/media-lifecycle-v2.json" with {
  type: "json",
};
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261011194522_prepare_initial_media_source_lifecycle.sql",
    import.meta.url,
  ),
);
const tests = await Deno.readTextFile(
  new URL("../../tests/initial_media_source_lifecycle.sql", import.meta.url),
);
Deno.test("media lifecycle closed schemas and canonical fixtures are identical in SQL and TypeScript", () => {
  const embedded = [...sql.matchAll(/SELECT \$json\$(.*?)\$json\$::JSONB;/gs)]
    .map((m) => JSON.parse(m[1]));
  embedded.push(
    JSON.parse(sql.match(/SELECT '(.*?)'::JSONB;/s)![1].replaceAll("''", "'")),
  );
  assertEquals(embedded, [profile, assignment, response]);
  assertEquals(JSON.parse(tests.split("$vectors$")[1]), vectors.valid);
});
Deno.test("inactive source catalogs are never seeded or exposed to API roles", () => {
  for (
    const table of [
      "initial_preparation_profiles",
      "initial_preparation_installations",
      "initial_preparation_source_backends",
      "initial_preparation_selections",
      "initial_preparation_current_selection",
    ]
  ) {
    assert(!sql.includes(`INSERT INTO internal.${table}`));
  }
  assert(!sql.includes("SET initial_analysis_lifecycle_enabled=TRUE"));
  assert(!sql.includes("CREATE FUNCTION public.dispatch"));
  assert(sql.includes("ENABLE ROW LEVEL SECURITY"));
  assert(sql.includes("FROM PUBLIC,anon,authenticated,service_role"));
});
Deno.test("existing preparation owners are patched only through exact checked anchors", () => {
  const patches =
    sql.split("DO $integration$")[1].split("END; $integration$;")[0];
  for (
    const chunk of patches.split(
      /(?:definition:=|EXECUTE )replace\(definition,anchor/,
    ).slice(0, -1)
  ) {
    assert(chunk.includes("/length(anchor)<>1"));
  }
  for (
    const owner of [
      "cancel_initial_analysis",
      "erase_initial_analysis_for_scan_fence",
      "fence_initial_analysis_on_scan_change",
      "fence_initial_analysis_before_owner_delete",
      "get_initial_preparation_status",
      "finalize_initial_preparation",
    ]
  ) assert(patches.includes(owner));
});
