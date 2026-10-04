import { PublicationPhotoCohortContainerRejection } from "./photoCohortPreflight.ts";
import { publicationAbortable } from "./publicationDeadline.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "./contract.ts";
import type {
  PhotoExecutionDependencies,
  PhotoExecutionScope,
  PhotoModerationState,
  PhotoModerationWork,
} from "./photoExecution.ts";
import type { PublicationPhotoSource } from "./photoClassifier.ts";

export interface PublicationWorkScope {
  owner_id: string;
  observation_id: string;
  operation_id: string;
  work_token: string;
}
export interface RecoveredPhotoWork extends PhotoModerationWork {
  dispatch_expires_at: string | null;
}
export type ActiveRecoveredPhotoWork = RecoveredPhotoWork & {
  state: "reserved" | "dispatched";
  lease_token: string;
};
/** Terminal outcomes are consumed directly; they carry no execution capability. */
export function isActivePhotoWork(
  work: RecoveredPhotoWork,
): work is ActiveRecoveredPhotoWork {
  return (work.state === "reserved" || work.state === "dispatched") &&
    work.lease_token !== null;
}
const states = new Set([
  "reserved",
  "dispatched",
  "approved",
  "rejected",
  "cancelled",
  "unknown_execution",
]);
function receipt(
  value: unknown,
  operation: string,
  source: Readonly<PublicationPhotoSource>,
): RecoveredPhotoWork {
  const r = exactObject(value, [
    "schema_version",
    "attempt_id",
    "operation_id",
    "media_id",
    "state",
    "quota",
    "lease_token",
    "dispatch_expires_at",
    "source",
    "policy_version",
    "provider",
    "model",
    "processor_permission",
  ]);
  const s = exactObject(r.source, [
    "media_id",
    "object_id",
    "content_type",
    "byte_count",
    "sha256",
  ]);
  if (
    r.schema_version !== 1 || r.operation_id !== operation ||
    r.media_id !== source.media_id ||
    !states.has(r.state as string) ||
    r.policy_version !== "photo_publication_v1" ||
    r.provider !== "gemini" || r.model !== "gemini-2.5-flash" ||
    r.processor_permission !== "google_gemini" ||
    Object.keys(s).some((k) =>
      s[k] !== source[k as keyof PublicationPhotoSource]
    )
  ) invalidHistory();
  const active = r.state === "reserved" || r.state === "dispatched";
  if (active) historyUUID(r.lease_token);
  else if (r.lease_token !== null) invalidHistory();
  if (
    r.dispatch_expires_at !== null &&
    (typeof r.dispatch_expires_at !== "string" ||
      r.dispatch_expires_at.length > 40 ||
      !Number.isFinite(Date.parse(r.dispatch_expires_at)))
  ) invalidHistory();
  if (
    (r.state === "dispatched" || r.state === "approved" ||
      r.state === "rejected" || r.state === "unknown_execution") &&
    r.dispatch_expires_at === null
  ) invalidHistory();
  return Object.freeze({
    attempt_id: historyUUID(r.attempt_id),
    operation_id: operation,
    media_id: source.media_id,
    state: r.state as PhotoModerationState,
    lease_token: r.lease_token as string | null,
    dispatch_expires_at: r.dispatch_expires_at as string | null,
    source,
    policy_version: "photo_publication_v1",
    provider: "gemini",
    model: "gemini-2.5-flash",
    processor_permission: "google_gemini",
  });
}
/** Service-private adapter. The future worker must preflight the full cohort
 * before admit; neither this repository nor a work token approves source bytes. */
export function publicationModerationRepository(
  client: SupabaseClient,
  identity: PublicationWorkScope,
  inputs: readonly PublicationPhotoSource[],
  deadlines: {
    signal?: AbortSignal;
    freshSignal?: AbortSignal;
    canDispatch?: () => boolean;
  } = {},
) {
  const scope = Object.freeze({
    p_owner: historyUUID(identity.owner_id),
    p_observation: historyUUID(identity.observation_id),
    p_operation: historyUUID(identity.operation_id),
    p_work: historyUUID(identity.work_token),
  });
  if (inputs.length < 1 || inputs.length > 6) invalidHistory();
  const sources = Object.freeze(inputs.map((input) => {
    const s = { ...input };
    exactObject(s, [
      "media_id",
      "object_id",
      "content_type",
      "byte_count",
      "sha256",
    ]);
    historyUUID(s.media_id);
    historyUUID(s.object_id);
    if (
      s.media_id === s.object_id ||
      !["image/jpeg", "image/png", "image/heic"].includes(s.content_type) ||
      !Number.isSafeInteger(s.byte_count) || s.byte_count < 1 ||
      s.byte_count > 12 * 1024 * 1024 ||
      typeof s.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(s.sha256)
    ) invalidHistory();
    return Object.freeze(s);
  }));
  if (sources.reduce((sum, s) => sum + s.byte_count, 0) > 32 * 1024 * 1024) {
    invalidHistory();
  }
  const byMedia = new Map(sources.map((s) => [historyUUID(s.media_id), s]));
  if (byMedia.size !== sources.length) invalidHistory();
  async function rpc(
    name: string,
    extra: Record<string, unknown> = {},
    fresh = false,
  ): Promise<unknown> {
    try {
      const caller = fresh
        ? deadlines.freshSignal ?? deadlines.signal
        : deadlines.signal;
      const timeout = AbortSignal.timeout(12_000);
      const signal = caller ? AbortSignal.any([caller, timeout]) : timeout;
      const { data, error } = await publicationAbortable(
        signal,
        () => client.rpc(name, { ...scope, ...extra }).abortSignal(signal),
      );
      if (error) throw error;
      return data;
    } catch {
      // No transport retry, database prose, private provider tokens or evidence.
      throw new HistoryError("analysis_history_unavailable");
    }
  }
  const parse = (value: unknown, source: Readonly<PublicationPhotoSource>) => {
    try {
      return receipt(value, scope.p_operation, source);
    } catch {
      throw new HistoryError("analysis_history_unavailable");
    }
  };
  return {
    async read(): Promise<readonly (RecoveredPhotoWork | null)[]> {
      const data = await rpc("read_publication_moderation_work");
      try {
        if (!Array.isArray(data) || data.length !== sources.length) {
          invalidHistory();
        }
        return Object.freeze(data.map((value, i) => {
          const row = exactObject(value, ["media_id", "attempt"]);
          if (row.media_id !== sources[i].media_id) invalidHistory();
          return row.attempt === null
            ? null
            : receipt(row.attempt, scope.p_operation, sources[i]);
        }));
      } catch {
        throw new HistoryError("analysis_history_unavailable");
      }
    },
    async finalize(): Promise<boolean> {
      const data = await rpc("finalize_publication_photo_moderation");
      const row = exactObject(
        data,
        typeof data === "object" && data !== null && "finalized" in data &&
          data.finalized === false
          ? ["finalized"]
          : ["finalized", "status", "reason"],
      );
      if (row.finalized === false) return false;
      if (
        row.finalized !== true ||
        !((row.status === "photos_approved" && row.reason === null) ||
          (row.status === "needs_action" &&
            [
              "photo_rejected",
              "unknown_execution",
              "cancelled",
              "unsupported_source_type",
              "public_container_rejected",
            ].includes(
              row.reason as string,
            )))
      ) invalidHistory();
      return true;
    },
    async rejectContainer(
      rejection: PublicationPhotoCohortContainerRejection,
    ): Promise<boolean> {
      if (!(rejection instanceof PublicationPhotoCohortContainerRejection)) {
        invalidHistory();
      }
      const original = byMedia.get(rejection.attestation.source.media_id);
      if (
        !original ||
        Object.keys(original).some((key) =>
          original[key as keyof PublicationPhotoSource] !==
            rejection.attestation.source[key as keyof PublicationPhotoSource]
        )
      ) invalidHistory();
      const row = exactObject(
        await rpc("finalize_publication_container_rejection", {
          p_attestation: rejection.attestation,
        }),
        ["finalized", "status", "reason"],
      );
      if (
        row.finalized !== true ||
        !((row.status === "needs_action" &&
          row.reason === "public_container_rejected") ||
          (row.status === "admitted" && row.reason === null))
      ) invalidHistory();
      return true;
    },
    async admit(media: string): Promise<RecoveredPhotoWork> {
      const source = byMedia.get(historyUUID(media));
      if (!source) return invalidHistory();
      return parse(
        await rpc(
          "admit_publication_moderation_work",
          { p_media: media },
          true,
        ),
        source,
      );
    },
    execution(work: ActiveRecoveredPhotoWork): PhotoExecutionDependencies {
      if (!isActivePhotoWork(work)) invalidHistory();
      const source = byMedia.get(work.media_id);
      if (
        !source || work.operation_id !== scope.p_operation ||
        Object.keys(source).some((k) =>
          source[k as keyof PublicationPhotoSource] !==
            work.source[k as keyof PublicationPhotoSource]
        )
      ) invalidHistory();
      const attempt = historyUUID(work.attempt_id),
        token = historyUUID(work.lease_token);
      async function advance(
        s: PhotoExecutionScope,
        action: string,
        payload: Record<string, unknown>,
      ) {
        if (
          s.owner_id !== scope.p_owner ||
          s.observation_id !== scope.p_observation ||
          s.attempt_id !== attempt || s.lease_token !== token
        ) invalidHistory();
        return await rpc("advance_publication_moderation_work", {
          p_attempt: attempt,
          p_token: token,
          p_action: action,
          p_payload: payload,
        }, action === "prepare" || action === "dispatch");
      }
      function terminal(value: unknown): PhotoModerationState {
        const r = parse(value, source!);
        if (r.attempt_id !== attempt) {
          throw new HistoryError("analysis_history_unavailable");
        }
        return r.state;
      }
      return {
        saveProof: async (s, proof) => {
          const data = await advance(s, "prepare", { proof });
          if (
            data === null || typeof data !== "object" || Array.isArray(data) ||
            Object.keys(data).length
          ) throw new HistoryError("analysis_history_unavailable");
        },
        dispatch: async (s) => {
          if (deadlines.canDispatch && !deadlines.canDispatch()) {
            throw new HistoryError("analysis_history_unavailable");
          }
          const data = await advance(s, "dispatch", {});
          try {
            const row = exactObject(data, ["dispatch_allowed", "receipt"]);
            const r = receipt(row.receipt, scope.p_operation, source!);
            if (
              typeof row.dispatch_allowed !== "boolean" ||
              r.attempt_id !== attempt ||
              (row.dispatch_allowed &&
                (r.state !== "dispatched" || r.lease_token !== token))
            ) invalidHistory();
            return row.dispatch_allowed;
          } catch {
            throw new HistoryError("analysis_history_unavailable");
          }
        },
        complete: async (s, proof, result) =>
          terminal(await advance(s, "complete", { proof, result })),
        retire: async (s) => terminal(await advance(s, "retire", {})),
      };
    },
  };
}
