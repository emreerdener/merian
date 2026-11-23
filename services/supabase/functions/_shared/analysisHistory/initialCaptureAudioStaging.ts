import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { initialEvidenceArtifacts } from "./initialEvidenceManifest.ts";
import { MEDIA_BUDGETS } from "../mediaBudgets.ts";
import { evidenceDigest } from "./evidence.ts";
import {
  cancelInitialStream,
  initialAbortable,
  initialDeadline,
  readInitialStream,
} from "../initialAnalysis/transport.ts";
import {
  initialCapturePlanValue,
  type InitialEvidenceCapturePlan,
  type InitialPreparedAudioRead,
  prepareInitialCaptureAudio,
  recoverInitialCaptureAudio,
} from "./initialEvidenceCapturePlan.ts";

// Increment when the actual processing recipe changes. An existing bound
// output is recovered under its saved recipe, never implicitly migrated.
export const INITIAL_CAPTURE_AUDIO_RECIPE =
  "mono-pcm16-16000-trim-bandlimited-v1";

type Artifact = InitialPreparedAudioRead["artifact"];
export interface InitialCaptureAudioStageRequest {
  readonly owner_id: string;
  readonly plan: ReturnType<typeof initialCapturePlanValue>;
  readonly recipe: typeof INITIAL_CAPTURE_AUDIO_RECIPE;
  readonly request_sha256: string;
}
export interface InitialCaptureAudioStageObject {
  readonly object_id: string;
  readonly media_id: string;
  readonly artifact: Artifact | null;
  readonly ready: boolean;
}
export interface InitialCaptureAudioStageReceipt {
  readonly request_sha256: string;
  readonly attempt_id: string;
  readonly items: readonly InitialCaptureAudioStageObject[];
}

/** Server-installed staging authority. reserve durably records the complete
 * plan, source associations, recipe, destination obligations and an exclusive
 * preparation attempt BEFORE DSP. It returns the saved attempt on replay.
 * bind atomically fixes all output metadata; the binding cannot be replaced.
 * Objects are private, excluded from client PUT signing and generic TTL cleanup.
 * Retirement and adoption must serialize with these operations, account/scan
 * deletion and late writes. No ingestion job or funding is created here.
 */
export interface InitialCaptureAudioStageRepository {
  reserve(
    request: InitialCaptureAudioStageRequest,
    attempt: string,
    signal: AbortSignal,
  ): Promise<unknown>;
  bind(
    request: InitialCaptureAudioStageRequest,
    attempt: string,
    artifacts: readonly Artifact[],
    signal: AbortSignal,
  ): Promise<unknown>;
  complete(
    request: InitialCaptureAudioStageRequest,
    object: InitialCaptureAudioStageObject,
    signal: AbortSignal,
  ): Promise<unknown>;
}
export interface InitialCaptureAudioStageStorage {
  /** Conditional create only; implementation joins termination or preserves a
   * durable late-write obligation. A timeout is never permission to overwrite. */
  writeOnce(
    object: InitialCaptureAudioStageObject,
    bytes: Uint8Array,
    signal: AbortSignal,
  ): Promise<void>;
  read(
    object: InitialCaptureAudioStageObject,
    signal: AbortSignal,
  ): Promise<ReadableStream<Uint8Array>>;
}

function receipt(
  value: unknown,
  plan: InitialEvidenceCapturePlan,
  requestSHA256: string,
  previous?: InitialCaptureAudioStageReceipt,
): InitialCaptureAudioStageReceipt {
  const row = exactObject(value, ["request_sha256", "attempt_id", "items"]);
  if (row.request_sha256 !== requestSHA256) return invalidHistory();
  const attempt = historyUUID(row.attempt_id);
  const seen = new Set([
    plan.ownerID,
    plan.scanID,
    plan.generation,
    ...plan.uploads.map((file) => file.media_id),
    ...plan.audio.map((slot) => slot.preparedID),
  ]);
  if (
    seen.has(attempt) || !Array.isArray(row.items) ||
    row.items.length !== plan.audio.length ||
    (previous && previous.attempt_id !== attempt)
  ) return invalidHistory();
  seen.add(attempt);
  const items = row.items.map((value, index) => {
    const item = exactObject(value, [
      "object_id",
      "media_id",
      "artifact",
      "ready",
    ]);
    const object = historyUUID(item.object_id),
      media = historyUUID(item.media_id);
    if (
      seen.has(object) || media !== plan.audio[index].preparedID ||
      typeof item.ready !== "boolean"
    ) return invalidHistory();
    seen.add(object);
    let artifact: Artifact | null = null;
    if (item.artifact !== null) {
      const parsed = exactObject(item.artifact, [
        "media_id",
        "content_type",
        "byte_count",
        "sha256",
      ]);
      if (
        parsed.media_id !== media || parsed.content_type !== "audio/wav" ||
        typeof parsed.byte_count !== "number" ||
        !Number.isSafeInteger(parsed.byte_count) ||
        parsed.byte_count < 16_044 ||
        parsed.byte_count > MEDIA_BUDGETS.maxAudioRawBytes ||
        typeof parsed.sha256 !== "string" ||
        !/^[0-9a-f]{64}$/.test(parsed.sha256)
      ) return invalidHistory();
      artifact = Object.freeze({
        media_id: media,
        content_type: "audio/wav",
        byte_count: parsed.byte_count,
        sha256: parsed.sha256,
      });
    }
    if (item.ready && artifact === null) return invalidHistory();
    const prior = previous?.items[index];
    if (
      prior && (prior.object_id !== object || (prior.ready && !item.ready) ||
        (prior.artifact !== null &&
          JSON.stringify(prior.artifact) !== JSON.stringify(artifact)))
    ) return invalidHistory();
    return Object.freeze({
      object_id: object,
      media_id: media,
      artifact,
      ready: item.ready,
    });
  });
  // Metadata binding is an atomic whole-output set, never partial DSP progress.
  if (
    items.some((item) => item.artifact === null) &&
    items.some((item) => item.artifact !== null)
  ) return invalidHistory();
  return Object.freeze({
    request_sha256: requestSHA256,
    attempt_id: attempt,
    items: Object.freeze(items),
  });
}

async function readBytes(
  open: (signal: AbortSignal) => Promise<ReadableStream<Uint8Array>>,
  length: number,
  caller: AbortSignal,
) {
  return await initialDeadline(caller, 10_000, async (signal) => {
    const stream = await initialAbortable(
      signal,
      () => open(signal),
      cancelInitialStream,
    );
    const bytes = await readInitialStream(stream, length, signal);
    if (bytes.byteLength !== length) return invalidHistory();
    return bytes;
  });
}

/** Canonical complete-plan binding shared by orchestration and its durable adapter. */
export async function initialCaptureAudioStageRequest(
  plan: InitialEvidenceCapturePlan,
): Promise<InitialCaptureAudioStageRequest> {
  const body = Object.freeze({
    owner_id: plan.ownerID,
    plan: initialCapturePlanValue(plan),
    recipe: INITIAL_CAPTURE_AUDIO_RECIPE,
  });
  return Object.freeze({
    ...body,
    request_sha256: await evidenceDigest(
      new TextEncoder().encode(JSON.stringify(body)),
    ),
  });
}

/** Prepared composition for the existing staging owner, not an HTTP entry
 * point. A recovered binding reads exact stored outputs without reading raw
 * audio or running DSP. A lost bind acknowledgement must be retried through
 * reserve; this invocation must not guess that it owns a write.
 */
export async function stageInitialCaptureAudio(
  plan: InitialEvidenceCapturePlan,
  attempt: string,
  source: {
    read(
      artifact: InitialEvidenceCapturePlan["audio"][number]["source"],
      signal: AbortSignal,
    ): Promise<ReadableStream<Uint8Array>>;
  },
  repository: InitialCaptureAudioStageRepository,
  storage: InitialCaptureAudioStageStorage,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  historyUUID(attempt);
  if (
    [
      plan.ownerID,
      plan.scanID,
      plan.generation,
      ...plan.uploads.map((file) => file.media_id),
      ...plan.audio.map((slot) => slot.preparedID),
    ].includes(attempt)
  ) return invalidHistory();
  if (!plan.audio.length) {
    return Object.freeze({
      result: await recoverInitialCaptureAudio(plan, [], signal),
      stage: null,
    });
  }
  const request = await initialCaptureAudioStageRequest(plan);
  signal.throwIfAborted();
  let saved = receipt(
    await repository.reserve(request, attempt, signal),
    plan,
    request.request_sha256,
  );
  signal.throwIfAborted();
  let fresh: Awaited<ReturnType<typeof prepareInitialCaptureAudio>> | null =
    null;
  if (saved.items.every((item) => item.artifact === null)) {
    if (saved.attempt_id !== attempt) return invalidHistory();
    const inputs: { mediaID: string; bytes: Uint8Array }[] = [];
    for (const slot of plan.audio) {
      inputs.push({
        mediaID: slot.source.media_id,
        bytes: await readBytes(
          (current) => source.read(slot.source, current),
          slot.source.byte_count,
          signal,
        ),
      });
    }
    signal.throwIfAborted();
    fresh = await prepareInitialCaptureAudio(plan, inputs, signal);
    const outputs = initialEvidenceArtifacts(fresh.request.evidence_manifest)
      .filter((file) =>
        file.role === "prepared_audio" ||
        file.role === "prepared_companion_audio"
      )
      .map((file) =>
        Object.freeze({
          media_id: file.media_id,
          content_type: file.content_type,
          byte_count: file.byte_count,
          sha256: file.sha256,
        })
      );
    signal.throwIfAborted();
    saved = receipt(
      await repository.bind(request, attempt, outputs, signal),
      plan,
      request.request_sha256,
      saved,
    );
    signal.throwIfAborted();
    if (
      saved.items.some((item, index) =>
        item.ready ||
        JSON.stringify(item.artifact) !== JSON.stringify(outputs[index])
      )
    ) return invalidHistory();
  }
  const reads: InitialPreparedAudioRead[] = [];
  for (const item of saved.items) {
    signal.throwIfAborted();
    if (!item.artifact) return invalidHistory();
    if (fresh) {
      await storage.writeOnce(
        item,
        fresh.readPreparedAudio(item.media_id),
        signal,
      );
      signal.throwIfAborted();
    }
    const bytes = await readBytes(
      (current) => storage.read(item, current),
      item.artifact.byte_count,
      signal,
    );
    signal.throwIfAborted();
    reads.push({ artifact: item.artifact, bytes });
  }
  const result = await recoverInitialCaptureAudio(plan, reads, signal);
  // No ready marker is persisted until every returned byte has been verified.
  for (let index = 0; index < saved.items.length; index++) {
    signal.throwIfAborted();
    const item = saved.items[index];
    if (item.ready) continue;
    saved = receipt(
      await repository.complete(request, item, signal),
      plan,
      request.request_sha256,
      saved,
    );
    signal.throwIfAborted();
    if (!saved.items[index].ready) return invalidHistory();
  }
  return Object.freeze({ result, stage: saved });
}
