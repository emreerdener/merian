import { assertEquals, assertRejects } from "@std/assert";
import {
  parseSourceRetirementEnvelope,
  SOURCE_RETIREMENT_HTTP_MAX_BYTES,
} from "./request.ts";
import vectors from "../_shared/analysisHistory/fixtures/source-fingerprint-v1.json" with {
  type: "json",
};
const operation = "00000000-0000-4000-8000-000000000092";
Deno.test("unfunded HTTP envelope freezes candidate and operation before hashing await", async () => {
  const original = {
    schema_version: 1 as const,
    candidate: {
      schema_version: 1 as const,
      input: structuredClone(vectors[0].input),
      fingerprint_version: 1 as const,
      fingerprint: vectors[0].sha256,
    },
    operation_id: operation,
  };
  const expected = structuredClone(original);
  const pending = parseSourceRetirementEnvelope(original);
  original.operation_id = "00000000-0000-4000-8000-000000000093";
  original.candidate.input.request_digest = "b".repeat(64);
  assertEquals(await pending, expected);
  await assertRejects(() =>
    parseSourceRetirementEnvelope({ ...expected, owner_id: operation })
  );
});
Deno.test("unfunded HTTP envelope budget includes exact minimal schema and UUID overhead", () => {
  const wrapper = JSON.stringify({
    schema_version: 1 as const,
    candidate: null,
    operation_id: operation,
  });
  assertEquals(new TextEncoder().encode(wrapper).length - 4, 87);
  assertEquals(SOURCE_RETIREMENT_HTTP_MAX_BYTES, 1_048_576 + 87);
});
