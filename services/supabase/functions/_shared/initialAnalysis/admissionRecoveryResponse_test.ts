import { assertEquals, assertRejects } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { validateInitialAdmissionRecoveryResponse } from "./admissionRecoveryResponse.ts";
import schema from "./admission-recovery-response-schema-v2.json" with {
  type: "json",
};
import metadata from "./admission-metadata-schema-v1.json" with {
  type: "json",
};
import vectors from "./fixtures/admission-recovery-response-v2.json" with {
  type: "json",
};

Deno.test("admission recovery: closed schemas retain exact M1 v2 binding", () => {
  assertEquals(schema.admitted.properties.binding, metadata.media_binding);
  assertEquals(schema.transferred.properties.binding, metadata.media_binding);
});
Deno.test("admission recovery: all historical phases and transferred/held decode without current clock", async () => {
  for (const value of vectors.valid) {
    assertEquals(
      await validateInitialAdmissionRecoveryResponse(value),
      initialCanonicalText(value),
    );
  }
});
Deno.test("admission recovery: shared SQL negative vectors reject shape, identity, digest and window faults", async (t) => {
  for (const { name, value } of vectors.invalid) {
    await t.step(name, async () => {
      await assertRejects(
        () => validateInitialAdmissionRecoveryResponse(value),
        Error,
        "initial_analysis_input_invalid",
      );
    });
  }
});
Deno.test("admission recovery: caller mutation during hashing cannot change accepted snapshot", async () => {
  const value = structuredClone(vectors.valid[0]);
  const expected = initialCanonicalText(value);
  const pending = validateInitialAdmissionRecoveryResponse(value);
  value.authority = "dispatch";
  assertEquals(await pending, expected);
  await assertRejects(() => validateInitialAdmissionRecoveryResponse(value));
});
