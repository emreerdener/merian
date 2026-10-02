/** Private evaluator wiring, with the existing accounted/moderated transport. */
import { createAIExecution } from "../../functions/_shared/ai/execution.ts";
import {
  createOpenAIPhotoEvaluationTransport,
  createOpenAIPhotoPrimaryEvaluationAdapter,
} from "../../functions/_shared/ai/openai.ts";
import { openAIPhotoPrimarySnapshot } from "../../functions/_shared/ai/openaiPhotoPrimary.ts";
import { liveCredential } from "./admission.ts";
import { assertPrivateReviewReady } from "./explanationView.ts";
import {
  buildPhotoFeatureRequest,
  decodePhotoFeatureDraft,
  photoFeatureSnapshot,
} from "./photoFeatureCandidate.ts";
import type { FeatureProvider } from "./photoFeatureRun.ts";
export function photoFeatureAdapter(
  credential: string,
  fetcher: typeof fetch = fetch,
) {
  return createOpenAIPhotoEvaluationTransport(
    credential,
    buildPhotoFeatureRequest,
    (value) => {
      const decoded = decodePhotoFeatureDraft(value);
      return {
        ...decoded.identification,
        diagnostic_features: decoded.features,
      };
    },
    fetcher,
  );
}
export function liveFeatureProvider(): FeatureProvider {
  let credential = "";
  return {
    mode: "live",
    preflight: async () => {
      await assertPrivateReviewReady();
      credential = await liveCredential("openai");
    },
    invoke: (arm, request) =>
      arm === "features"
        ? createAIExecution(
          photoFeatureAdapter(credential),
          request,
          photoFeatureSnapshot(request),
        ).invoke()
        : createAIExecution(
          createOpenAIPhotoPrimaryEvaluationAdapter(credential),
          request,
          openAIPhotoPrimarySnapshot(request),
        ).invoke(),
  };
}
