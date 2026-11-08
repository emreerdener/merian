import { assertEquals } from "@std/assert";
import vector from "../functions/_shared/initialAnalysis/fixtures/cpm-admission-submission-v1.json" with {
  type: "json",
};
Deno.test("CPM submission SQL and consuming coordinator share the independent frozen projection", async () => {
  const source = await Deno.readTextFile(
    new URL("../tests/initial_cpm_submission_projection.sql", import.meta.url),
  );
  const matches = [
    ...source.matchAll(
      /\$projection_vector\$([\s\S]*?)\$projection_vector\$::JSONB/g,
    ),
  ];
  assertEquals(matches.length, 1);
  assertEquals(JSON.parse(matches[0][1]), vector);
});
