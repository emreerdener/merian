import { assert, assertEquals } from "@std/assert";
import {
  createOpenAIConfidenceEvaluationAdapter,
  createOpenAIPhotoAdapter,
} from "../../../functions/_shared/ai/openai.ts";
import { createAIExecution } from "../../../functions/_shared/ai/execution.ts";
import { openAIConfidenceSnapshot } from "../../../functions/_shared/ai/openaiPhotoConfidence.ts";
import { openAIPhotoSnapshot } from "../../../functions/_shared/ai/openaiPhoto.ts";
import {
  openAIPhotoModerationFixture,
  openAIPhotoRequestFixture,
  openAIResponseFixture,
} from "../../../functions/_shared/ai/testing/openaiFixtures.ts";
import { projectConfidenceOutcome } from "../confidenceProjection.ts";
import { confidenceFixture, confidenceOutcome } from "./confidenceFixtures.ts";

export function registerConfidenceAccountingTests() {
  Deno.test("confidence accounting accepts optional and positive cache writes through the real adapter without inventing counts", async () => {
    const fixture = confidenceFixture();
    fixture.pricing.models[0].inputPerMillion.cacheWrite = 5;
    const request = openAIPhotoRequestFixture();
    for (
      const writes of [undefined, null, 0, 1, 80, -1, 81, 0.5, "0", 100000001]
    ) {
      const raw = openAIResponseFixture();
      const details: Record<string, unknown> = {
        ...raw.usage.input_tokens_details,
      };
      if (writes !== undefined) details.cache_write_tokens = writes;
      let calls = 0;
      const fetcher: typeof fetch = () => {
        calls++;
        return Promise.resolve(
          Response.json({
            ...raw,
            service_tier: "default",
            moderation: openAIPhotoModerationFixture(),
            usage: { ...raw.usage, input_tokens_details: details },
          }),
        );
      };
      const outcome = await createAIExecution(
        createOpenAIConfidenceEvaluationAdapter(
          "synthetic-confidence",
          fetcher,
        ),
        request,
        openAIConfidenceSnapshot(request),
      ).invoke();
      assertEquals(calls, 1);
      assertEquals(outcome.kind, "draft");
      const valid = writes == null ||
        (typeof writes === "number" && Number.isSafeInteger(writes) &&
          writes >= 0 && writes <= 80);
      const projected = projectConfidenceOutcome(
        "c001",
        outcome,
        fixture.taxonomy,
        fixture.pricing,
      );
      assertEquals(projected.settledNanoUsd, valid ? 700_000 : null);
      if (valid) {
        assertEquals(
          projected.accounting.usage?.cacheWriteTokens,
          writes ?? null,
        );
      } else assertEquals(projected.accounting.usage, null);
      // Existing production decoding remains exactly as before this assessment repair.
      const historical = await createAIExecution(
        createOpenAIPhotoAdapter("synthetic-confidence", fetcher),
        request,
        openAIPhotoSnapshot(request, 1),
      ).invoke();
      assert(historical.usage !== null);
      assertEquals(
        historical.usage.cacheWriteTokens,
        valid ? writes ?? null : null,
      );
    }
  });
  Deno.test("confidence projection rejects contradictory injected cache usage and preserves bounded billing evidence", () => {
    const fixture = confidenceFixture();
    const good = confidenceOutcome(fixture.corpus.cases[0]);
    assert(good.usage);
    for (const writes of [-1, 81, .5, "0"]) {
      const result = projectConfidenceOutcome(
        "c001",
        {
          ...good,
          usage: { ...good.usage, cacheWriteTokens: writes as number },
        },
        fixture.taxonomy,
        fixture.pricing,
      );
      assertEquals(result.settledNanoUsd, null);
      assert(!JSON.stringify(result.accounting).includes("Synthetic"));
    }
  });
}
