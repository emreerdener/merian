import { assertEquals, assertFalse, assertStringIncludes } from "@std/assert";
import { speciesDictionaryRefusalAnswer } from "./refusal.ts";

const reasons = [
  "foraging_or_ingestion",
  "medical_or_veterinary",
  "dangerous_handling",
  "legal_or_collection",
  "unknown_reason",
] as const;

Deno.test("dictionary refusals are complete and never imply saved user evidence", () => {
  for (const reason of reasons) {
    const answer = speciesDictionaryRefusalAnswer(reason);
    assertStringIncludes(answer, "I cannot");
    assertStringIncludes(answer, "Species Dictionary page");
    assertFalse(/\b(?:scan|observation|saved|stored)\b/i.test(answer));
  }
});

Deno.test("dictionary refusal categories retain source-specific safety guidance", () => {
  assertStringIncludes(
    speciesDictionaryRefusalAnswer("foraging_or_ingestion"),
    "ingestion-related decision",
  );
  assertStringIncludes(
    speciesDictionaryRefusalAnswer("medical_or_veterinary"),
    "poison control",
  );
  assertStringIncludes(
    speciesDictionaryRefusalAnswer("dangerous_handling"),
    "safe distance",
  );
  assertStringIncludes(
    speciesDictionaryRefusalAnswer("legal_or_collection"),
    "local regulations",
  );
  assertEquals(
    speciesDictionaryRefusalAnswer("unknown_reason"),
    "I cannot help with that request, but I can answer educational questions about traits, habitat, seasonality, taxonomy, or lookalikes from this Species Dictionary page.",
  );
});
