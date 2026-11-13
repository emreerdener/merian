import { assertEquals } from "@std/assert";
import { parseInitialCanonicalText } from "../functions/_shared/initialAnalysis/canonical.ts";
import { decodeCpmCompletionAdmission } from "../functions/_shared/initialAnalysis/cpmCompletionAdmission.ts";
import { cpmCompletionAdmissionFixture } from "../functions/_shared/initialAnalysis/fixtures/cpmCompletionAdmission.ts";
import { cpmCompletionAdmissionVectors } from "./initial_cpm_completion_admission_vectors.ts";

Deno.test("original admission byte vectors have explicit accepted and rejected outcomes", async (t) => {
  const fixture = await cpmCompletionAdmissionFixture();
  const vectors = await cpmCompletionAdmissionVectors();
  for (const vector of vectors.documents) {
    await t.step(vector.name, async () => {
      let decoded:
        | Awaited<ReturnType<typeof decodeCpmCompletionAdmission>>
        | undefined;
      try {
        decoded = await decodeCpmCompletionAdmission(
          parseInitialCanonicalText(vector.acknowledgement),
          fixture.binding,
        );
      } catch { /* Negative vectors intentionally fail closed. */ }
      assertEquals(decoded !== undefined, vector.valid);
      if (decoded) {
        assertEquals(decoded.canonical, vector.acknowledgement);
        assertEquals(decoded.admission_canonical, vectors.admission);
      }
    });
  }
});
