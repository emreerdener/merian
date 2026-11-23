import type { SupabaseClient } from "@supabase/supabase-js";
import { captureObjectBackendDigest } from "../captureObjectRetirement.ts";
import { createServiceRoleClientFromEnvironmentWithOptions } from "../serviceRoleClient.ts";
import {
  cancelInitialStream,
  initialAbortable,
  initialDeadline,
  readInitialStream,
} from "../initialAnalysis/transport.ts";
import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import {
  getHistoryEvidenceConfig,
  PrivateCaptureStageObjectStorage,
} from "./evidenceStorage.ts";
import {
  type InitialEvidenceCapturePlan,
  parseInitialEvidenceCapturePlan,
} from "./initialEvidenceCapturePlan.ts";
import { initialCaptureAudioStageRequest } from "./initialCaptureAudioStaging.ts";
import { initialCaptureStageRequestBody } from "./initialCaptureAudioStageRepository.ts";

type Artifact = InitialEvidenceCapturePlan["uploads"][number];
export interface InitialCaptureClientReceipt {
  readonly request_sha256: string;
  readonly object_id: string;
  readonly artifact: Artifact;
  readonly write_issued: boolean;
  readonly ready: boolean;
}
export interface InitialCaptureClientRepository {
  reserve(
    media: string,
    signal: AbortSignal,
  ): Promise<InitialCaptureClientReceipt>;
  authorize(
    media: string,
    action: "write" | "read" | "verify",
    signal: AbortSignal,
  ): Promise<boolean>;
  complete(
    media: string,
    signal: AbortSignal,
  ): Promise<InitialCaptureClientReceipt>;
}
export interface InitialCaptureClientServices {
  repository: InitialCaptureClientRepository;
  storage: Pick<
    PrivateCaptureStageObjectStorage,
    "writeOnce" | "openBoundStream"
  >;
}

/** Private, service-only adapter bound to a parsed full plan. Its receipt never
 * reaches the client: opaque object IDs and backend selection stay server-side. */
export async function initialCaptureClientRepository(
  plan: InitialEvidenceCapturePlan,
  client: SupabaseClient,
  backend: string,
): Promise<InitialCaptureClientRepository> {
  if (!/^[0-9a-f]{64}$/.test(backend)) return invalidHistory();
  const request = await initialCaptureAudioStageRequest(plan);
  const body = initialCaptureStageRequestBody(request);
  function artifact(media: string) {
    const id = historyUUID(media),
      item = plan.uploads.find((x) => x.media_id === id);
    if (!item) return invalidHistory();
    return item;
  }
  function parse(
    value: unknown,
    expected: Artifact,
  ): InitialCaptureClientReceipt {
    const row = exactObject(value, [
      "request_sha256",
      "object_id",
      "artifact",
      "write_issued",
      "ready",
    ]);
    const objectID = historyUUID(row.object_id);
    const actual = exactObject(row.artifact, Object.keys(expected));
    if (
      row.request_sha256 !== request.request_sha256 ||
      typeof row.write_issued !== "boolean" || typeof row.ready !== "boolean" ||
      (row.ready && !row.write_issued) ||
      Object.entries(expected).some(([key, value]) => actual[key] !== value) ||
      [
        plan.ownerID,
        plan.scanID,
        plan.generation,
        ...plan.uploads.map((x) => x.media_id),
        ...plan.audio.map((x) => x.preparedID),
      ].includes(objectID)
    ) return invalidHistory();
    return Object.freeze({
      request_sha256: request.request_sha256,
      object_id: objectID,
      artifact: expected,
      write_issued: row.write_issued,
      ready: row.ready,
    });
  }
  async function call(action: string, media: string, caller: AbortSignal) {
    caller.throwIfAborted();
    const expected = artifact(media);
    try {
      return await initialDeadline(caller, 5_000, async (signal) => {
        const { data, error } = await initialAbortable(
          signal,
          () =>
            client.rpc("initial_capture_client_stage_action", {
              p_request: body.text,
              p_sha256: body.hash,
              p_backend: backend,
              p_action: action,
              p_media: expected.media_id,
            }).abortSignal(signal),
        );
        signal.throwIfAborted();
        if (error) {
          throw new HistoryError(
            error.message === "analysis_history_operation_conflict"
              ? "analysis_history_operation_conflict"
              : "analysis_history_unavailable",
          );
        }
        if (["write", "read", "verify"].includes(action)) {
          if (typeof data !== "boolean") return invalidHistory();
          return data;
        }
        return parse(data, expected);
      });
    } catch (error) {
      if (
        error instanceof HistoryError &&
        error.code === "analysis_history_operation_conflict"
      ) throw error;
      throw new HistoryError("analysis_history_unavailable");
    }
  }
  async function receipt(
    action: "reserve" | "complete",
    media: string,
    signal: AbortSignal,
  ) {
    const result = await call(action, media, signal);
    if (typeof result === "boolean") return invalidHistory();
    return result;
  }
  return {
    reserve: (media, signal) => receipt("reserve", media, signal),
    complete: (media, signal) => receipt("complete", media, signal),
    async authorize(media, action, signal) {
      const result = await call(action, media, signal);
      if (typeof result !== "boolean") return invalidHistory();
      return result;
    },
  };
}

export async function createInitialCaptureClientServices(
  plan: InitialEvidenceCapturePlan,
  client: SupabaseClient = createServiceRoleClientFromEnvironmentWithOptions({
    requestTimeoutMs: 5_000,
    maximumResponseBytes: 8_192,
  }),
): Promise<InitialCaptureClientServices> {
  const write = getHistoryEvidenceConfig("write"),
    read = getHistoryEvidenceConfig("read");
  const backend = await captureObjectBackendDigest(write);
  if (backend !== await captureObjectBackendDigest(read)) {
    return invalidHistory();
  }
  return {
    repository: await initialCaptureClientRepository(
      plan,
      client,
      backend,
    ),
    storage: new PrivateCaptureStageObjectStorage(() => write, () => read),
  };
}

/** One bounded artifact of a complete frozen plan, before ordinary admission.
 * A consumed/unknown write grant permits only readback recovery, never PUT retry.
 * Upload acknowledgement is not admission, result sealing or native hold release. */
export async function uploadInitialCaptureClientArtifact(
  owner: string,
  candidate: unknown,
  media: string,
  input: Uint8Array,
  createServices: (
    plan: InitialEvidenceCapturePlan,
  ) => Promise<InitialCaptureClientServices>,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const plan = parseInitialEvidenceCapturePlan(owner, candidate),
    mediaID = historyUUID(media);
  const artifact = plan.uploads.find((x) => x.media_id === mediaID);
  if (
    !artifact || !(input instanceof Uint8Array) ||
    input.byteLength !== artifact.byte_count
  ) return invalidHistory();
  const bytes = input.slice();
  if (await evidenceDigest(bytes) !== artifact.sha256) return invalidHistory();
  signal.throwIfAborted();
  const { repository, storage } = await initialAbortable(
    signal,
    () => createServices(plan),
  );
  signal.throwIfAborted();
  const saved = await repository.reserve(mediaID, signal);
  signal.throwIfAborted();
  const object = { object_id: saved.object_id, ...artifact };
  if (
    !saved.write_issued && await repository.authorize(mediaID, "write", signal)
  ) {
    signal.throwIfAborted();
    await initialDeadline(
      signal,
      30_000,
      (current) =>
        initialAbortable(
          current,
          () => storage.writeOnce(object, bytes, current),
        ),
    );
  }
  signal.throwIfAborted();
  if (!await repository.authorize(mediaID, "verify", signal)) {
    throw new HistoryError("analysis_history_unavailable");
  }
  await initialDeadline(signal, 30_000, async (current) => {
    const stream = await initialAbortable(
      current,
      () => storage.openBoundStream(object, current),
      cancelInitialStream,
    );
    const actual = await readInitialStream(
      stream,
      artifact.byte_count,
      current,
    );
    if (
      actual.length !== artifact.byte_count ||
      await evidenceDigest(actual) !== artifact.sha256
    ) throw new HistoryError("analysis_history_evidence_unavailable");
    current.throwIfAborted();
  });
  signal.throwIfAborted();
  const complete = saved.ready
    ? saved
    : await repository.complete(mediaID, signal);
  signal.throwIfAborted();
  if (
    !complete.ready || complete.object_id !== saved.object_id ||
    complete.request_sha256 !== saved.request_sha256
  ) return invalidHistory();
  return Object.freeze({
    schema_version: 1 as const,
    scan_id: plan.scanID,
    generation: plan.generation,
    request_sha256: saved.request_sha256,
    media_id: mediaID,
    ready: true as const,
  });
}
