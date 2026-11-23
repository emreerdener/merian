import { processWavBuffer } from "../audioProcessing.ts";
import { decodeBase64, encodeBase64 } from "../encoding.ts";
import { parseWavHeader } from "../../audio-spec/wav.ts";
import { MEDIA_BUDGETS } from "../mediaBudgets.ts";
import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import {
  initialEvidenceArtifacts,
  initialEvidenceDigest,
  type InitialEvidenceManifest,
  parseInitialEvidenceManifest,
} from "./initialEvidenceManifest.ts";
import { initialRetentionRequest } from "./initialEvidenceRetention.ts";

type Artifact = ReturnType<typeof initialEvidenceArtifacts>[number];
type AudioSlot = Readonly<{
  source: Artifact;
  preparedID: string;
  companion: boolean;
}>;

/** Client-known upload membership plus reserved server-audio identities.
 * No digest of hypothetical DSP output is accepted from the client. This is
 * descriptive input, never a storage, funding, retention or admission proof.
 */
export interface InitialEvidenceCapturePlan {
  readonly ownerID: string;
  readonly scanID: string;
  readonly generation: string;
  readonly uploads: readonly Artifact[];
  readonly audio: readonly AudioSlot[];
}

const plans = new WeakMap<
  InitialEvidenceCapturePlan,
  InitialEvidenceManifest
>();

/** The durable staging owner stores this complete plan, including geometry and
 * reserved DSP identities. It never stores the internal placeholder manifest. */
export function initialCapturePlanValue(plan: InitialEvidenceCapturePlan) {
  const template = plans.get(plan);
  if (!template) return invalidHistory();
  return Object.freeze({
    schema_version: 1 as const,
    scan_id: plan.scanID,
    generation: plan.generation,
    items: Object.freeze(template.items.map((item) => {
      if (item.kind === "audio") {
        return Object.freeze({
          kind: item.kind,
          source: item.source,
          prepared_media_id: item.prepared.media_id,
        });
      }
      if (item.kind === "video") {
        return Object.freeze({
          ...item,
          audio: item.audio === null ? null : Object.freeze({
            source: item.audio.source,
            prepared_media_id: item.audio.prepared.media_id,
          }),
        });
      }
      return item;
    })),
  });
}

export function parseInitialEvidenceCapturePlan(
  authenticatedOwner: string,
  value: unknown,
): InitialEvidenceCapturePlan {
  const ownerID = historyUUID(authenticatedOwner);
  const row = exactObject(value, [
    "schema_version",
    "scan_id",
    "generation",
    "items",
  ]);
  if (
    row.schema_version !== 1 || !Array.isArray(row.items) ||
    row.items.length > 64
  ) return invalidHistory();
  const scanID = historyUUID(row.scan_id),
    generation = historyUUID(row.generation);
  // Reuse the canonical manifest's structure, role, ID and byte-budget checks.
  // The minimum-sized internal audio placeholders are never returned, hashed,
  // uploaded or admitted. Final DSP bytes must pass that same parser again.
  function audio(value: unknown) {
    const audio = exactObject(value, ["source", "prepared_media_id"]);
    return {
      source: audio.source,
      prepared: {
        media_id: historyUUID(audio.prepared_media_id),
        content_type: "audio/wav",
        byte_count: 46,
        sha256: "0".repeat(64),
      },
    };
  }
  const manifest = parseInitialEvidenceManifest(
    {
      schema_version: 9,
      items: row.items.map((value) => {
        if (
          !value || typeof value !== "object" || Array.isArray(value)
        ) return invalidHistory();
        if ("kind" in value && value.kind === "audio") {
          const item = exactObject(value, [
            "kind",
            "source",
            "prepared_media_id",
          ]);
          return {
            kind: "audio",
            ...audio({
              source: item.source,
              prepared_media_id: item.prepared_media_id,
            }),
          };
        }
        if ("kind" in value && value.kind === "video") {
          const item = exactObject(value, [
            "kind",
            "source",
            "playback",
            "frames",
            "audio",
          ]);
          return {
            ...item,
            audio: item.audio === null ? null : audio(item.audio),
          };
        }
        return value;
      }),
    },
    scanID,
    generation,
  );
  const all = initialEvidenceArtifacts(manifest);
  if (
    [scanID, generation, ...all.map((artifact) => artifact.media_id)].includes(
      ownerID,
    )
  ) return invalidHistory();
  const slots: AudioSlot[] = [];
  for (const [index, item] of manifest.items.entries()) {
    const pair = item.kind === "audio"
      ? item
      : item.kind === "video"
      ? item.audio
      : null;
    if (!pair) continue;
    // The ordinary native transport supplies PCM WAV. A historical M4A source
    // remains readable in History but cannot masquerade as this DSP input.
    if (pair.source.content_type !== "audio/wav") return invalidHistory();
    const source = all.find((artifact) =>
      artifact.item_index === index &&
      artifact.media_id === pair.source.media_id
    );
    if (!source) return invalidHistory();
    slots.push(
      Object.freeze({
        source,
        preparedID: pair.prepared.media_id,
        companion: item.kind === "video",
      }),
    );
  }
  const plan = Object.freeze({
    ownerID,
    scanID,
    generation,
    uploads: Object.freeze(
      all.filter((artifact) =>
        artifact.role !== "prepared_audio" &&
        artifact.role !== "prepared_companion_audio"
      ),
    ),
    audio: Object.freeze(slots),
  });
  plans.set(plan, manifest);
  return plan;
}

/** Runs before ingestion admission, against bytes supplied by the authenticated
 * staging collector. All audio source identities are verified before DSP. The
 * result still requires complete image/video source verification and sealed
 * admission; it is not a substitute for either storage owner.
 */
export async function prepareInitialCaptureAudio(
  plan: InitialEvidenceCapturePlan,
  input: readonly Readonly<{ mediaID: string; bytes: Uint8Array }>[],
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const template = plans.get(plan);
  if (
    !template || !Array.isArray(input) || input.length !== plan.audio.length
  ) return invalidHistory();
  // Bound and copy every caller-owned audio buffer before the first suspension.
  const reads = input.map((read, index) => {
    const slot = plan.audio[index];
    if (
      !read || Object.keys(read).length !== 2 ||
      read.mediaID !== slot.source.media_id ||
      !(read.bytes instanceof Uint8Array) ||
      !(read.bytes.buffer instanceof ArrayBuffer) ||
      read.bytes.byteLength !== slot.source.byte_count
    ) return invalidHistory();
    return read.bytes.slice();
  });
  for (const [index, bytes] of reads.entries()) {
    if (await evidenceDigest(bytes) !== plan.audio[index].source.sha256) {
      return invalidHistory();
    }
    signal.throwIfAborted();
  }
  const outputs: InitialPreparedAudioRead[] = [];
  for (const [index, bytes] of reads.entries()) {
    signal.throwIfAborted();
    const slot = plan.audio[index];
    const output = processWavBuffer(bytes.buffer, undefined, {
      preserveSourceWhenTrimmedTooShort: slot.companion,
    }).base64Audio;
    const exact = decodeBase64(output);
    outputs.push({
      artifact: {
        media_id: slot.preparedID,
        content_type: "audio/wav",
        byte_count: exact.byteLength,
        sha256: await evidenceDigest(exact),
      },
      bytes: exact,
    });
  }
  return await recoverInitialCaptureAudio(plan, outputs, signal);
}

export interface InitialPreparedAudioRead {
  readonly artifact: Readonly<{
    media_id: string;
    content_type: string;
    byte_count: number;
    sha256: string;
  }>;
  readonly bytes: Uint8Array;
}

/** Validation only for the server-prepared 16 kHz profile. Never runs DSP. */
export function validateInitialPreparedAudioContainer(bytes: Uint8Array): void {
  if (
    !(bytes.buffer instanceof ArrayBuffer) || bytes.length < 16_044 ||
    bytes.length > MEDIA_BUDGETS.maxAudioRawBytes
  ) return invalidHistory();
  // Own an exact view: a subarray must not validate its unrelated backing bytes.
  const owned = bytes.slice();
  const header = parseWavHeader(owned.buffer);
  if (
    header.audioFormat !== 1 || header.numChannels !== 1 ||
    header.sampleRate !== 16_000 ||
    header.bitsPerSample !== 16 || header.dataOffset !== 44 ||
    header.dataLength !== owned.byteLength - 44 ||
    header.dataLength % 2 !== 0 ||
    new DataView(owned.buffer).getUint32(4, true) !== owned.byteLength - 8
  ) return invalidHistory();
}

/** Reconstructs provider inputs and the final manifest from already-bound
 * server output. No DSP is performed here. The installed staging owner must
 * supply its durable output association; client metadata alone grants nothing.
 * Missing, changed, reordered or malformed output fails without reprocessing.
 */
export async function recoverInitialCaptureAudio(
  plan: InitialEvidenceCapturePlan,
  input: readonly InitialPreparedAudioRead[],
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const template = plans.get(plan);
  if (
    !template || !Array.isArray(input) || input.length !== plan.audio.length
  ) {
    return invalidHistory();
  }
  const reads = input.map((read, index) => {
    const row = exactObject(read, ["artifact", "bytes"]);
    const artifact = exactObject(row.artifact, [
      "media_id",
      "content_type",
      "byte_count",
      "sha256",
    ]);
    if (
      artifact.media_id !== plan.audio[index].preparedID ||
      artifact.content_type !== "audio/wav" ||
      typeof artifact.byte_count !== "number" ||
      !Number.isSafeInteger(artifact.byte_count) ||
      artifact.byte_count < 16_044 ||
      artifact.byte_count > MEDIA_BUDGETS.maxAudioRawBytes ||
      typeof artifact.sha256 !== "string" ||
      !/^[0-9a-f]{64}$/.test(artifact.sha256) ||
      !(row.bytes instanceof Uint8Array) ||
      !(row.bytes.buffer instanceof ArrayBuffer) ||
      row.bytes.byteLength !== artifact.byte_count
    ) return invalidHistory();
    const bytes = row.bytes.slice();
    validateInitialPreparedAudioContainer(bytes);
    return {
      artifact: Object.freeze({
        media_id: plan.audio[index].preparedID,
        content_type: "audio/wav",
        byte_count: artifact.byte_count,
        sha256: artifact.sha256,
      }),
      bytes,
    };
  });
  const processed = new Map<string, string>();
  const prepared = new Map<string, InitialPreparedAudioRead["artifact"]>();
  for (const { artifact, bytes } of reads) {
    if (await evidenceDigest(bytes) !== artifact.sha256) {
      return invalidHistory();
    }
    signal.throwIfAborted();
    prepared.set(artifact.media_id, artifact);
    processed.set(artifact.media_id, encodeBase64(bytes));
  }
  signal.throwIfAborted();
  const manifest = parseInitialEvidenceManifest(
    {
      schema_version: 9,
      items: template.items.map((item) => {
        if (item.kind === "audio") {
          return { ...item, prepared: prepared.get(item.prepared.media_id) };
        }
        if (item.kind === "video" && item.audio) {
          return {
            ...item,
            audio: {
              ...item.audio,
              prepared: prepared.get(item.audio.prepared.media_id),
            },
          };
        }
        return item;
      }),
    },
    plan.scanID,
    plan.generation,
  );
  const request = await initialRetentionRequest({
    schema_version: 1,
    scan_id: plan.scanID,
    generation: plan.generation,
    evidence_manifest: manifest,
    evidence_digest: await initialEvidenceDigest(
      manifest,
      plan.scanID,
      plan.generation,
    ),
  });
  signal.throwIfAborted();
  return Object.freeze({
    request,
    audioBase64s: Object.freeze(
      plan.audio.map((slot) => {
        const value = processed.get(slot.preparedID);
        if (value === undefined) return invalidHistory();
        return value;
      }),
    ),
    readPreparedAudio(mediaID: string): Uint8Array {
      signal.throwIfAborted();
      const value = processed.get(mediaID);
      if (value === undefined) return invalidHistory();
      return decodeBase64(value);
    },
  });
}
