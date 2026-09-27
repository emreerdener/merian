import { assertEquals } from "@std/assert";
import { geminiMetricProvenance } from "../../_tests/identificationMetricsTestFixtures.ts";
import { identificationMetricsAreGeminiCompatible as compatible } from "./metricCompatibility.ts";

Deno.test("metric compatibility distinguishes legacy absence from missing or future metadata", () => {
  const original = geminiMetricProvenance();
  assertEquals(compatible(null, undefined), true);
  assertEquals(compatible(original, "flash"), true);
  assertEquals(compatible(original, "pro"), false);
  for (
    const value of [
      undefined,
      {},
      [],
      true,
      "invalid",
      { ...original, policy_version: 2 },
      { ...original, provider: "openai" },
      { ...original, extra: 1 },
      { ...original, generation: { ...original.generation, extra: 1 } },
      { ...original, prompt: ["identify_vision_v1"] },
    ]
  ) {
    assertEquals(compatible(value, "flash"), false);
  }
  for (const key of Object.keys(original)) {
    const missing: Record<string, unknown> = { ...original };
    delete missing[key];
    assertEquals(compatible(missing, "flash"), false);
  }
});
