import { createServiceRoleClientFromEnvironment } from "../serviceRoleClient.ts";
import {
  geminiReservationTransport,
  type GeminiTransportHooks,
} from "./geminiTransport.ts";
import type {
  AIExecutionAuthority,
  AIRequest,
  PreparedAIExecution,
} from "./contracts.ts";
import { createAIExecution } from "./execution.ts";
import { geminiAdapter } from "./gemini.ts";
import { resolveAIClaim } from "./registry.ts";
import { createOpenAIPhotoAdapter } from "./openai.ts";

// Deploy the enabled adapter before assigning photos in the database.
// Admission still owns the exact input, recipient permission and client minimum;
// credentials and client input never choose or override the provider.
const OPENAI_PHOTO_DISPATCH_ENABLED: boolean = true;

/** The sole production composition. No adapter argument or runtime override. */
export function prepareAIExecution(
  request: AIRequest,
  authority: AIExecutionAuthority,
  transport?: GeminiTransportHooks,
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
  const execution = createAIExecution(geminiAdapter, request, snapshot);
  return Object.freeze({
    snapshot: execution.snapshot,
    invoke: async () => {
      let hooks = transport;
      if (
        !hooks && authority.kind === "user_request" &&
        authority.reservation.leaseToken
      ) {
        hooks = geminiReservationTransport(
          createServiceRoleClientFromEnvironment(),
          authority.userId,
          {
            id: authority.reservation.id,
            leaseToken: authority.reservation.leaseToken,
            attemptCount: authority.reservation.attemptCount,
          },
        );
      }
      if (!hooks) throw new Error("gemini_transport_authority_required");
      return await execution.invoke(hooks);
    },
  });
}
