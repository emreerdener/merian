/** Invented contracts only; not approvals or source evidence for a real run. */
import { HOSTED_PROFILES, type HostedSpec, PROVIDERS } from "../hosted.ts";
import { reusableProfile } from "../reusableProfiles.ts";
import { parseEvaluationPricing } from "../runContracts.ts";

export async function hostedSpecFixture(now = Date.now()): Promise<HostedSpec> {
  return {
    version: "hosted_identification_spec_v1",
    experimentId: "synthetic-hosted-test",
    source: {
      commit: "0".repeat(40),
      dirty: false,
      digest: "1".repeat(64),
      sdk: "npm:@google/genai@2.23.0",
    },
    corpusDigest: "2".repeat(64),
    taxonomyDigest: "3".repeat(64),
    orderSeed: 42,
    window: {
      startsAt: new Date(now - 1000).toISOString(),
      expiresAt: new Date(now + 3600000).toISOString(),
    },
    budgetUsd: 40,
    publicRelease: {
      approved: true,
      reviewRef: "synthetic-public-review",
      attribution:
        "Invented test mechanics; no real observations or provider requests.",
    },
    runs: await Promise.all(PROVIDERS.map(async (provider, i) => ({
      provider,
      profileDigest: (await reusableProfile(HOSTED_PROFILES[i])).digest,
      budgetUsd: 20,
      pricing: parseEvaluationPricing({
        version: i ? "evaluation_openai_pricing_v1" : "evaluation_pricing_v1",
        ...(i ? { provider: "openai" } : {}),
        currency: "USD",
        service: "paid_standard_synchronous",
        retrievedAt: new Date(now - 1000).toISOString(),
        sourceUrl: i
          ? "https://developers.openai.com/api/docs/models/gpt-6-sol"
          : "https://ai.google.dev/gemini-api/docs/pricing",
        reviewRef: "synthetic-pricing",
        includesReasoning: true,
        models: (i ? ["gpt-6-sol"] : ["gemini-2.5-flash", "gemini-2.5-pro"])
          .map((model) => ({
            model,
            inputPerMillion: {
              text: 1,
              image: 1,
              cached: 1,
              ...(i ? { cacheWrite: 1 } : { audio: 1 }),
            },
            outputPerMillion: 1,
            maxInputTokens: 1050000,
            maxBillableOutputTokens: 13192,
            limitsEvidenceRef: "synthetic-limits",
          })),
      }),
      review: {
        reviewRef: "synthetic-processor-review",
        reviewedAt: new Date(now - 2000).toISOString(),
        expiresAt: new Date(now + 7200000).toISOString(),
        paidServiceApproved: true,
        inputPermissionApproved: true,
        dedicatedEvaluationProject: false,
        termsRef: "synthetic-terms",
        dataUseRef: "synthetic-data-use",
        regionSubprocessorRef: "synthetic-region",
        retentionAbuseLogRef: "synthetic-retention",
      },
    }))),
  };
}
