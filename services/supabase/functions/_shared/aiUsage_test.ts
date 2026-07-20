import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { geminiUsageModalityBreakdown } from "./aiUsage.ts";

Deno.test("Gemini modality token details are normalized without prompt content", () => {
  assertEquals(
    geminiUsageModalityBreakdown({
      promptTokensDetails: [
        { modality: "TEXT", tokenCount: 12 },
        { modality: "IMAGE", tokenCount: 100 },
        { modality: "TEXT", tokenCount: 3 },
      ],
      cacheTokensDetails: [{ modality: "TEXT", tokenCount: 4 }],
      candidatesTokensDetails: [{ modality: "TEXT", tokenCount: 20 }],
    }),
    {
      prompt: { text: 15, image: 100 },
      cached: { text: 4 },
      candidates: { text: 20 },
      tool: {},
    },
  );
});
