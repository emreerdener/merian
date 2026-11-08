import { assertEquals } from "@std/assert";
import vector from "../functions/_shared/initialAnalysis/fixtures/cpm-admitted-proof-v1.json" with {
  type: "json",
};
Deno.test("CPM SQL proof uses the independent frozen manifest and digest vector", async () => {
  const sql = await Deno.readTextFile(
    new URL("../tests/initial_cpm_admitted_proof.sql", import.meta.url),
  );
  const matches = [
    ...sql.matchAll(
      /\$cpm_proof_vector\$([\s\S]*?)\$cpm_proof_vector\$::JSONB/g,
    ),
  ];
  assertEquals(matches.length, 1);
  assertEquals(JSON.parse(matches[0][1]), vector);
});
