import { initialCompletionResultVectors } from "./initial_completion_result_vectors.ts";
import { assertEquals } from "@std/assert";
import { completionVectors } from "./initial_completion_vectors.ts";
import {
  completionFixturePath,
  completionSwiftPath,
  completionSwiftSchema,
  retainedResultSwiftPath,
  retainedResultSwiftSchema,
} from "./generate_initial_completion_contract.ts";
import { snapshotInitialCompletionDocuments } from "../functions/_shared/initialAnalysis/completionContract.ts";
import { parseInitialCanonicalText } from "../functions/_shared/initialAnalysis/canonical.ts";
import {
  type InitialSchemaRule,
  matchesInitialSchema,
} from "../functions/_shared/initialAnalysis/schema.ts";
import schema from "../functions/_shared/initialAnalysis/completion-schema-v1.json" with {
  type: "json",
};

Deno.test("native completion schema and shared synthetic fixtures match their owners", async () => {
  assertEquals(
    await Deno.readTextFile(completionSwiftPath),
    completionSwiftSchema(),
  );
  assertEquals(
    await Deno.readTextFile(retainedResultSwiftPath),
    retainedResultSwiftSchema(),
  );
  assertEquals(
    await Deno.readTextFile(completionFixturePath),
    JSON.stringify(await completionVectors(), null, 2) + "\n",
  );
});
Deno.test("shared completion documents and byte grammar have explicit accepted/rejected outcomes", async (t) => {
  const fixtures = await completionVectors();
  for (const v of fixtures.documents) {
    await t.step(v.name, async () => {
      const r = parseInitialCanonicalText(v.receipt),
        p = parseInitialCanonicalText(v.projection);
      assertEquals(
        matchesInitialSchema(r, schema.receipt as InitialSchemaRule) &&
          matchesInitialSchema(p, schema.projection as InitialSchemaRule),
        v.structural,
      );
      let accepted = false;
      try {
        await snapshotInitialCompletionDocuments(r, p);
        accepted = true;
      } catch { /* expected invalid vectors */ }
      assertEquals(accepted, v.valid);
    });
  }
  for (const [index, v] of fixtures.canonical.entries()) {
    await t.step(`canonical_${index}`, () => {
      let accepted = false;
      try {
        parseInitialCanonicalText(v.text);
        accepted = true;
      } catch {
        /* expected invalid vectors */
      }
      assertEquals(accepted, v.valid);
    });
  }
});

Deno.test("prospective native result inputs preserve frozen Deno v1 verdicts", async () => {
  const vectors = await initialCompletionResultVectors();
  assertEquals(vectors.filter((v) => v.valid).length, 14);
  assertEquals(vectors.filter((v) => !v.valid).length, 23);
  assertEquals(new Set(vectors.map((v) => v.name)).size, vectors.length);
});
