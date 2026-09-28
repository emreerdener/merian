import type {
  AIExecutionAuthority,
  AIRequest,
  PreparedAIExecution,
} from "./contracts.ts";
import { createAIExecution } from "./execution.ts";
import { geminiAdapter } from "./gemini.ts";
import { resolveAIClaim } from "./registry.ts";
import { createOpenAIPhotoAdapter } from "./openai.ts";

// Reviewed source gate, independent of credentials and database assignments.
// Remove only with compatible history readers, qualified evidence and an
// explicitly authorized activation. This is never a client/environment switch.
const OPENAI_PHOTO_DISPATCH_ENABLED: boolean = false;

/** The sole production composition. No adapter argument or runtime override. */
export function prepareAIExecution(
  request: AIRequest,
  authority: AIExecutionAuthority,
): PreparedAIExecution {
  const snapshot = resolveAIClaim(request, authority);
  if (snapshot.provider === "openai") {
    if (!OPENAI_PHOTO_DISPATCH_ENABLED) {
      throw new Error("ai_provider_not_enabled");
    }
    return createAIExecution(
      createOpenAIPhotoAdapter(Deno.env.get("NATUREBOOK_OPENAI_API_KEY") ?? ""),
      request,
      snapshot,
    );
  }
  return createAIExecution(geminiAdapter, request, snapshot);
}
