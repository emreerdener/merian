import { isOpenAIProfile } from "../../functions/_shared/ai/openaiRequest.ts";
/** Scripts-only composition. No provider/endpoint override enters production. */
import type { MultimodalAIRequest } from "../../functions/_shared/ai/contracts.ts";
import { createAIExecution } from "../../functions/_shared/ai/execution.ts";
import { createOpenAIEvaluationAdapter } from "../../functions/_shared/ai/openai.ts";
import {
  openAIEvaluationSnapshot,
} from "../../functions/_shared/ai/openaiRequest.ts";
import type { Profile } from "./contracts.ts";
import { fixtureAuthority } from "./profiles.ts";

export async function prepareEvaluationExecution(
  request: MultimodalAIRequest,
  profile: Profile,
  credential: string,
) {
  if (isOpenAIProfile(profile)) {
    return createAIExecution(
      createOpenAIEvaluationAdapter(credential),
      request,
      openAIEvaluationSnapshot(request, profile),
    );
  }
  // Keep SDK initialization out of offline/OpenAI processes and preserve its settings.
  return (await import("../../functions/_shared/ai/production.ts"))
    .prepareAIExecution(request, fixtureAuthority(profile));
}
