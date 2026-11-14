import type { GeminiTransportHooks } from "./geminiTransport.ts";
import {
  type GeminiResponseReceipt,
  GeminiResponseRejected,
} from "./geminiEnvelope.ts";

export interface GeminiSmokeClaim {
  state: string;
  owner_token?: string;
  case_digest?: string;
  model?: string;
  receipt?: GeminiResponseReceipt | null;
}
/** The concrete server repository binds release/configuration and deployment
 * identities. This interface has no model, prompt, input or transport overrides. */
export interface GeminiSmokeRepository {
  claim(releaseId: string, caseId: string): Promise<GeminiSmokeClaim>;
  dispatch(releaseId: string, caseId: string, owner: string): Promise<void>;
  receipt(
    releaseId: string,
    caseId: string,
    owner: string,
    receipt: GeminiResponseReceipt,
  ): Promise<void>;
  outcome(
    releaseId: string,
    caseId: string,
    owner: string,
    receipt: GeminiResponseReceipt,
    valid: boolean,
  ): Promise<string>;
  uncertain(releaseId: string, caseId: string, owner: string): Promise<void>;
}
export interface FrozenGeminiSmokeCase {
  readonly id: string;
  readonly digest: string;
  readonly model: string;
  readonly reservationMicrousd: number;
  execute(hooks: GeminiTransportHooks): Promise<void>;
}
/** Claim/dispatch/outcome each persist before proceeding. No automatic reclaim. */
export async function runGeminiReleaseSmoke(
  releaseId: string,
  caseId: string,
  catalog: ReadonlyMap<string, FrozenGeminiSmokeCase>,
  repository: GeminiSmokeRepository,
): Promise<{ state: string; reused: boolean }> {
  const definition = catalog.get(caseId);
  if (!definition) throw new Error("gemini_smoke_case_unknown");
  const claim = await repository.claim(releaseId, caseId);
  if (!claim.owner_token) return { state: claim.state, reused: true };
  if (
    claim.state !== "claimed" || claim.case_digest !== definition.digest ||
    claim.model !== definition.model
  ) {
    throw new Error("gemini_smoke_configuration_mismatch");
  }
  const owner = claim.owner_token;
  let dispatchAttempted = false;
  let receipt: GeminiResponseReceipt | null = null;
  let receiptSaved = false;
  const hooks: GeminiTransportHooks = {
    async beforeTransport() {
      if (dispatchAttempted) throw new Error("gemini_smoke_already_dispatched");
      dispatchAttempted = true;
      await repository.dispatch(releaseId, caseId, owner);
    },
    async recordResponse(value) {
      if (!dispatchAttempted || receipt) {
        throw new Error("gemini_smoke_response_conflict");
      }
      receipt = structuredClone(value);
      await repository.receipt(releaseId, caseId, owner, receipt);
      receiptSaved = true;
    },
  };
  try {
    await definition.execute(hooks);
    if (!receipt || !receiptSaved) {
      throw new Error("gemini_smoke_accounting_missing");
    }
    return {
      state: await repository.outcome(releaseId, caseId, owner, receipt, true),
      reused: false,
    };
  } catch (error) {
    if (error instanceof GeminiResponseRejected && !receipt) {
      receipt = error.receipt;
      try {
        await repository.receipt(releaseId, caseId, owner, receipt);
        receiptSaved = true;
      } catch { /* The dispatch witness retains liability. */ }
    }
    if (receipt && receiptSaved) {
      try {
        return {
          state: await repository.outcome(
            releaseId,
            caseId,
            owner,
            receipt,
            false,
          ),
          reused: false,
        };
      } catch {
        /* A lost outcome acknowledgement never permits another call. */
      }
    }
    if (dispatchAttempted) {
      await repository.uncertain(releaseId, caseId, owner).catch(() => {});
    }
    return {
      state: dispatchAttempted ? "uncertain" : "claimed",
      reused: false,
    };
  }
}
