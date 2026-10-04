import { historyUUID, invalidHistory } from "./contract.ts";
import {
  type PhotoClassifierProof,
  type PhotoClassifierResult,
  preparePublicationPhotoClassifier,
  type PublicationPhotoSource,
} from "./photoClassifier.ts";

export type PhotoModerationState =
  | "reserved"
  | "dispatched"
  | "approved"
  | "rejected"
  | "cancelled"
  | "unknown_execution";
export interface PhotoModerationWork {
  attempt_id: string;
  operation_id: string;
  media_id: string;
  state: PhotoModerationState;
  lease_token: string | null;
  source: PublicationPhotoSource;
  policy_version: string;
  provider: string;
  model: string;
  processor_permission: string;
}
export interface PhotoExecutionScope {
  readonly owner_id: string;
  readonly observation_id: string;
  readonly attempt_id: string;
  readonly lease_token: string;
}
export interface PhotoExecutionDependencies {
  // All repository operations must be scoped to the verified owner, observation,
  // this attempt and its original lease. No method may admit a successor.
  saveProof(
    scope: PhotoExecutionScope,
    proof: PhotoClassifierProof,
  ): Promise<void>;
  dispatch(scope: PhotoExecutionScope): Promise<boolean>;
  complete(
    scope: PhotoExecutionScope,
    proof: PhotoClassifierProof,
    result: PhotoClassifierResult,
  ): Promise<PhotoModerationState>;
  retire(scope: PhotoExecutionScope): Promise<PhotoModerationState>;
  prepare?: typeof preparePublicationPhotoClassifier;
}
const terminal = new Set([
  "approved",
  "rejected",
  "cancelled",
  "unknown_execution",
]);
/** Prepared owner, without an endpoint or scheduler. SQL remains authoritative. */
export async function executePublicationPhotoModeration(
  identity: { owner_id: string; observation_id: string },
  work: PhotoModerationWork,
  deps: PhotoExecutionDependencies,
): Promise<PhotoModerationState | "pending"> {
  const owner = historyUUID(identity.owner_id);
  const observation = historyUUID(identity.observation_id);
  historyUUID(work.attempt_id);
  historyUUID(work.operation_id);
  historyUUID(work.media_id);
  if (
    work.source.media_id !== work.media_id ||
    work.policy_version !== "photo_publication_v1" ||
    work.provider !== "gemini" || work.model !== "gemini-2.5-flash" ||
    work.processor_permission !== "google_gemini"
  ) return invalidHistory();
  if (terminal.has(work.state)) return work.state;
  if (work.state !== "reserved" && work.state !== "dispatched") {
    return invalidHistory();
  }
  const scope: PhotoExecutionScope = Object.freeze({
    owner_id: owner,
    observation_id: observation,
    attempt_id: work.attempt_id,
    lease_token: historyUUID(work.lease_token),
  });
  const retire = async (): Promise<PhotoModerationState | "pending"> => {
    try {
      const state = await deps.retire(scope);
      return terminal.has(state) ? state : "pending";
    } catch {
      return "pending";
    }
  };
  // Recovery can only retire an expired dispatch (or observe another worker's
  // committed terminal result). It never reconstructs an invocation permit.
  if (work.state === "dispatched") return await retire();
  let prepared: Awaited<ReturnType<typeof preparePublicationPhotoClassifier>>;
  try {
    prepared = await (deps.prepare ?? preparePublicationPhotoClassifier)(
      work.source,
    );
    await deps.saveProof(scope, prepared.proof);
  } catch {
    // This owner has not requested dispatch. SQL refuses cancellation if a
    // concurrent owner already dispatched, so this cannot refund its execution.
    return await retire();
  }
  try {
    if (await deps.dispatch(scope) !== true) return "pending";
  } catch {
    // A lost dispatch acknowledgement may have committed quota. Never invoke
    // or attempt an immediate refund when the single permit is uncertain.
    return "pending";
  }
  let result: PhotoClassifierResult;
  try {
    result = await prepared.invoke();
  } catch {
    return "pending";
  }
  // Repeat only the identical atomic write after a lost response. No provider
  // retry and no automatic successor, even if both completion replies are lost.
  for (let n = 0; n < 2; n++) {
    try {
      const state = await deps.complete(scope, prepared.proof, result);
      return state === result.decision ? state : "pending";
    } catch { /* Exact completion may already have committed. */ }
  }
  return "pending";
}
