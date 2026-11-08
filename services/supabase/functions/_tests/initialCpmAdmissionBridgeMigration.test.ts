import { assert, assertEquals } from "@std/assert";
import schema from "../_shared/initialAnalysis/cpm-admission-bridge-response-schema-v1.json" with {
  type: "json",
};

const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261102213355_prepare_initial_cpm_admission_bridge.sql",
    import.meta.url,
  ),
);

Deno.test("CPM bridge database and transport share the same closed observation schema", () => {
  const matches = [...sql.matchAll(/\$json\$(.*?)\$json\$/gs)];
  assertEquals(matches.length, 1);
  assertEquals(JSON.parse(matches[0][1]), schema);
  assertEquals(schema.properties.authority.enum, ["none"]);
  assertEquals(schema.properties.outcome.enum, ["unadmitted", "admitted"]);
});

Deno.test("CPM bridge exposes only the three service operations and preserves legacy functions", () => {
  assert(!/CREATE OR REPLACE FUNCTION/i.test(sql));
  const definitions = [
    ...sql.matchAll(
      /CREATE FUNCTION public\.([a-z_]+)\([\s\S]*?AS \$\$([\s\S]*?)\$\$;/g,
    ),
  ];
  assertEquals(definitions.map((x) => x[1]), [
    "read_initial_cpm_photo_admission",
    "begin_initial_cpm_photo_admission",
    "admit_initial_cpm_photo",
  ]);
  for (const definition of definitions) {
    assert(definition[0].includes("SECURITY DEFINER SET search_path=''"));
    assert(definition[2].includes("PERFORM internal.require_service_role();"));
  }
  assert(!/TO (?:PUBLIC|anon|authenticated)\s*;/i.test(sql));
  assert(
    !/CREATE TABLE|ALTER TABLE|UPDATE internal\.initial_analysis_rollout/i.test(
      sql,
    ),
  );
});
