import type { SupabaseClient } from "@supabase/supabase-js";
import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import {
  initialCapturePlanValue,
  type InitialEvidenceCapturePlan,
  parseInitialEvidenceCapturePlan,
} from "./initialEvidenceCapturePlan.ts";
import {
  INITIAL_CAPTURE_AUDIO_RECIPE,
  type InitialCaptureAudioStageObject,
  type InitialCaptureAudioStageRepository,
  type InitialCaptureAudioStageRequest,
  initialCaptureAudioStageRequest,
  type InitialCaptureAudioStageStorage,
} from "./initialCaptureAudioStaging.ts";
import {
  getHistoryEvidenceConfig,
  PrivateCaptureStageObjectStorage,
} from "./evidenceStorage.ts";
import { captureObjectBackendDigest } from "../captureObjectRetirement.ts";
import {
  initialAbortable,
  initialDeadline,
} from "../initialAnalysis/transport.ts";

/** Own all request data synchronously, before hashing or transport suspension. */
export function initialCaptureStageRequestBody(
  value: InitialCaptureAudioStageRequest,
) {
  const row = exactObject(value, [
    "owner_id",
    "plan",
    "recipe",
    "request_sha256",
  ]);
  const plan = parseInitialEvidenceCapturePlan(
    historyUUID(row.owner_id),
    row.plan,
  );
  if (
    row.recipe !== INITIAL_CAPTURE_AUDIO_RECIPE ||
    typeof row.request_sha256 !== "string" ||
    !/^[0-9a-f]{64}$/.test(row.request_sha256)
  ) return invalidHistory();
  return {
    text: JSON.stringify({
      owner_id: plan.ownerID,
      plan: initialCapturePlanValue(plan),
      recipe: INITIAL_CAPTURE_AUDIO_RECIPE,
    }),
    hash: row.request_sha256,
  };
}

/** Service-only adapter. Canonical request text avoids SQL/JS JSON serialization
 * differences. SQL repeats full identity, owner, deletion and phase checks.
 * A timed-out write authorization is consumed/unknown, never retried here. */
export function initialCaptureAudioStageRepository(
  client: SupabaseClient,
  backendSHA256: string,
  reservation: "audio_stage" | "complete_client_stage" = "audio_stage",
): InitialCaptureAudioStageRepository & {
  authorize(
    request: InitialCaptureAudioStageRequest,
    object: InitialCaptureAudioStageObject,
    action: "read" | "write",
    signal: AbortSignal,
  ): Promise<void>;
} {
  if (!/^[0-9a-f]{64}$/.test(backendSHA256)) return invalidHistory();
  async function call(
    request: InitialCaptureAudioStageRequest,
    action: "reserve" | "bind" | "read" | "write" | "complete",
    attempt: string | null,
    artifacts: unknown,
    object: string | null,
    caller: AbortSignal,
  ) {
    caller.throwIfAborted();
    const body = initialCaptureStageRequestBody(request);
    const args = {
      p_request: body.text,
      p_sha256: body.hash,
      p_backend: backendSHA256,
      p_action: action,
      p_attempt: attempt === null ? null : historyUUID(attempt),
      p_artifacts: structuredClone(artifacts),
      p_object: object === null ? null : historyUUID(object),
    };
    if (
      await evidenceDigest(new TextEncoder().encode(body.text)) !== body.hash
    ) return invalidHistory();
    caller.throwIfAborted();
    try {
      return await initialDeadline(caller, 5_000, async (signal) => {
        const { data, error } = await initialAbortable(
          signal,
          () =>
            client.rpc(
              action === "reserve" && reservation === "complete_client_stage"
                ? "claim_initial_capture_stage_preparation"
                : "initial_capture_audio_stage_action",
              action === "reserve" && reservation === "complete_client_stage"
                ? {
                  p_request: args.p_request,
                  p_sha256: args.p_sha256,
                  p_backend: args.p_backend,
                  p_attempt: args.p_attempt,
                }
                : args,
            ).abortSignal(signal),
        );
        signal.throwIfAborted();
        if (error) {
          throw new HistoryError(
            error.message === "analysis_history_operation_conflict"
              ? "analysis_history_operation_conflict"
              : "analysis_history_unavailable",
          );
        }
        return data;
      });
    } catch (error) {
      if (
        error instanceof HistoryError &&
        error.code === "analysis_history_operation_conflict"
      ) throw error;
      throw new HistoryError("analysis_history_unavailable");
    }
  }
  return {
    reserve: (request, attempt, signal) =>
      call(request, "reserve", attempt, null, null, signal),
    bind: (request, attempt, artifacts, signal) =>
      call(request, "bind", attempt, artifacts, null, signal),
    complete: (request, object, signal) =>
      call(
        request,
        "complete",
        null,
        object.artifact,
        object.object_id,
        signal,
      ),
    async authorize(request, object, action, signal) {
      if (
        await call(
          request,
          action,
          null,
          object.artifact,
          object.object_id,
          signal,
        ) !== true
      ) {
        throw new HistoryError("analysis_history_unavailable");
      }
    },
  };
}

/** Each object I/O requires a fresh durable stage check. Reads return a bounded
 * metadata-checked stream; stageInitialCaptureAudio verifies its complete bytes.
 * Retirement uses a separate opaque marker claim, never this upload authority. */
export function initialCaptureAudioStageStorage(
  request: InitialCaptureAudioStageRequest,
  repository: ReturnType<typeof initialCaptureAudioStageRepository>,
  objects: PrivateCaptureStageObjectStorage,
): InitialCaptureAudioStageStorage {
  // Synchronous snapshot: caller mutation cannot retarget an in-flight object.
  const owned = structuredClone(request);
  initialCaptureStageRequestBody(owned);
  function snapshot(value: InitialCaptureAudioStageObject) {
    const row = exactObject(value, [
      "object_id",
      "media_id",
      "artifact",
      "ready",
    ]);
    const object = historyUUID(row.object_id),
      media = historyUUID(row.media_id);
    const artifact = exactObject(row.artifact, [
      "media_id",
      "content_type",
      "byte_count",
      "sha256",
    ]);
    if (
      artifact.media_id !== media || artifact.content_type !== "audio/wav" ||
      typeof artifact.byte_count !== "number" ||
      !Number.isSafeInteger(artifact.byte_count) ||
      artifact.byte_count < 16_044 || artifact.byte_count > 2_700_000 ||
      typeof artifact.sha256 !== "string" ||
      !/^[0-9a-f]{64}$/.test(artifact.sha256) ||
      typeof row.ready !== "boolean"
    ) return invalidHistory();
    return {
      object_id: object,
      media_id: media,
      ready: row.ready,
      artifact: {
        media_id: media,
        content_type: "audio/wav",
        byte_count: artifact.byte_count,
        sha256: artifact.sha256,
      },
    };
  }
  return {
    async writeOnce(value, input, signal) {
      signal.throwIfAborted();
      const object = snapshot(value), bytes = input.slice();
      if (
        bytes.length !== object.artifact.byte_count ||
        await evidenceDigest(bytes) !== object.artifact.sha256
      ) return invalidHistory();
      signal.throwIfAborted();
      await repository.authorize(owned, object, "write", signal);
      signal.throwIfAborted();
      // A stalled/lost transport acknowledgement remains a durable issued-write
      // obligation. Deadline recovery never retries PUT or releases the object.
      await initialDeadline(
        signal,
        30_000,
        (current) =>
          initialAbortable(current, () =>
            objects.writeOnce(
              { object_id: object.object_id, ...object.artifact },
              bytes,
              current,
            )),
      );
    },
    async read(value, signal) {
      signal.throwIfAborted();
      const object = snapshot(value);
      await repository.authorize(owned, object, "read", signal);
      signal.throwIfAborted();
      return await objects.openBoundStream({
        object_id: object.object_id,
        ...object.artifact,
      }, signal);
    },
  };
}

/** Production construction resolves the audited private bucket once and binds
 * both read/write credentials to that exact backend before any stage action. */
export async function createInitialCaptureAudioStageServices(
  plan: InitialEvidenceCapturePlan,
  client: SupabaseClient,
  reservation: "audio_stage" | "complete_client_stage" = "audio_stage",
) {
  const write = getHistoryEvidenceConfig("write"),
    read = getHistoryEvidenceConfig("read");
  const backend = await captureObjectBackendDigest(write);
  if (backend !== await captureObjectBackendDigest(read)) {
    return invalidHistory();
  }
  const request = await initialCaptureAudioStageRequest(plan);
  const repository = initialCaptureAudioStageRepository(
    client,
    backend,
    reservation,
  );
  const objects = new PrivateCaptureStageObjectStorage(() => write, () => read);
  return {
    repository,
    storage: initialCaptureAudioStageStorage(request, repository, objects),
  };
}
