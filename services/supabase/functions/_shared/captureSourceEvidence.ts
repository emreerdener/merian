/** Prepared server-only byte snapshots. This is not database admission, a client
 * claim, immutable storage, or permission to release originals. The collector
 * must supply bytes from its bounded authenticated read, before provider work. */
import { captureObjectBackendDigest } from "./captureObjectRetirement.ts";
import { encodeBase64 } from "./encoding.ts";
import {
  MEDIA_BUDGETS,
  STAGING_ALLOWED_CONTENT_TYPES,
  type StagingMediaKind,
} from "./mediaBudgets.ts";

export interface CaptureSourceRead {
  readonly sourceKey: string;
  readonly kind: StagingMediaKind;
  readonly contentType: string;
  readonly bytes: Uint8Array<ArrayBuffer>;
}
export interface CaptureSourceObservation {
  readonly sourceKey: string;
  readonly backendSHA256: string;
  readonly contentType: string;
  readonly byteCount: number;
  readonly sha256: string;
}
export interface CaptureSourceObservations {
  readonly version: 1;
  readonly items: readonly CaptureSourceObservation[];
}
export interface CaptureSourceSnapshots {
  readonly ownerId: string;
  readonly observations: CaptureSourceObservations;
  /** Provider preparation consumes these exact snapshots, never another GET. */
  imageBase64s(): string[];
  audioBuffers(): ArrayBuffer[];
  /** Isolated original bytes for retention, including raw video; no second GET. */
  sourceBytes(sourceKey: string): Uint8Array<ArrayBuffer>;
}

const snapshots = new WeakMap<
  CaptureSourceSnapshots,
  readonly StagingMediaKind[]
>();
const invalid = () => new Error("invalid_capture_source_evidence");
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

/** All caller-owned bytes and identity are copied before the first await. The
 * process-local handle prevents a deserialized HTTP object from masquerading as
 * collector evidence. It does not replace the later SQL ownership/seal checks. */
export async function captureSourceSnapshots(
  ownerId: string,
  inputBackend: { readonly endpoint: string; readonly bucketName: string },
  inputReads: readonly CaptureSourceRead[],
): Promise<CaptureSourceSnapshots> {
  if (typeof ownerId !== "string" || !uuid.test(ownerId)) throw invalid();
  const backend = Object.freeze({ ...inputBackend });
  if (
    typeof backend.endpoint !== "string" ||
    typeof backend.bucketName !== "string"
  ) throw invalid();
  const endpoint = new URL(backend.endpoint);
  if (
    endpoint.protocol !== "https:" || endpoint.username || endpoint.password ||
    backend.endpoint !== endpoint.origin ||
    !/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/.test(backend.bucketName) ||
    !Array.isArray(inputReads) || inputReads.length < 1 ||
    inputReads.length > MEDIA_BUDGETS.maxStagingFiles
  ) throw invalid();
  const counts = { image: 0, audio: 0, video: 0 };
  const keys = new Set<string>();
  let imageBytes = 0;
  let totalBytes = 0;
  const maximumBytes = MEDIA_BUDGETS.maxImageRawBytes +
    MEDIA_BUDGETS.maxAudioRawBytes * MEDIA_BUDGETS.maxAudioClips +
    MEDIA_BUDGETS.maxVideoRawBytes;
  // Validate complete membership and all sizes before allocating private copies.
  const reads = inputReads.map((read: CaptureSourceRead) => {
    if (!read || Object.keys(read).length !== 4) throw invalid();
    const { sourceKey, kind, contentType, bytes } = read;
    if (
      (kind !== "image" && kind !== "audio" && kind !== "video") ||
      typeof sourceKey !== "string" ||
      !new RegExp(`^staging/${ownerId}/[A-Za-z0-9_.-]{1,255}$`).test(
        sourceKey,
      ) ||
      sourceKey.includes("..") || keys.has(sourceKey) ||
      !STAGING_ALLOWED_CONTENT_TYPES[kind].includes(contentType) ||
      !(bytes instanceof Uint8Array) || !(bytes.buffer instanceof ArrayBuffer)
    ) throw invalid();
    keys.add(sourceKey);
    counts[kind]++;
    const limit = kind === "image"
      ? MEDIA_BUDGETS.maxImageRawBytes
      : kind === "audio"
      ? MEDIA_BUDGETS.maxAudioRawBytes
      : MEDIA_BUDGETS.maxVideoRawBytes;
    if (bytes.byteLength < 1 || bytes.byteLength > limit) throw invalid();
    if (kind === "image") imageBytes += bytes.byteLength;
    totalBytes += bytes.byteLength;
    return { sourceKey, kind, contentType, bytes };
  });
  if (
    counts.image > MEDIA_BUDGETS.maxImageCount ||
    counts.audio > MEDIA_BUDGETS.maxAudioClips ||
    counts.video > MEDIA_BUDGETS.maxStagedVideoFiles ||
    imageBytes > MEDIA_BUDGETS.maxImageRawBytes || totalBytes > maximumBytes
  ) throw invalid();
  const retained = reads.map((read) => ({
    ...read,
    bytes: read.bytes.slice(),
  }));
  const backendSHA256 = await captureObjectBackendDigest(backend);
  const items: CaptureSourceObservation[] = [];
  for (const read of retained) {
    const digest = new Uint8Array(
      await crypto.subtle.digest("SHA-256", read.bytes),
    );
    items.push(Object.freeze({
      sourceKey: read.sourceKey,
      backendSHA256,
      contentType: read.contentType,
      byteCount: read.bytes.byteLength,
      sha256: [...digest].map((v) => v.toString(16).padStart(2, "0")).join(""),
    }));
  }
  const result: CaptureSourceSnapshots = Object.freeze({
    ownerId,
    observations: Object.freeze({
      version: 1 as const,
      items: Object.freeze(items),
    }),
    imageBase64s: () =>
      retained.filter((r) => r.kind === "image").map((r) =>
        encodeBase64(r.bytes)
      ),
    audioBuffers: () =>
      retained.filter((r) => r.kind === "audio").map((r) =>
        r.bytes.slice().buffer
      ),
    sourceBytes: (sourceKey: string) => {
      const source = retained.find((r) => r.sourceKey === sourceKey);
      if (!source) throw invalid();
      return source.bytes.slice();
    },
  });
  snapshots.set(result, Object.freeze(retained.map((r) => r.kind)));
  return result;
}

/** Require exact complete ordered transport membership. Do not deduplicate,
 * trim, sort, infer or silently omit a missing source when constructing intent. */
export function captureSourceObservationsForIntent(
  snapshot: CaptureSourceSnapshots,
  mediaKeys: {
    readonly image: readonly string[];
    readonly audio: readonly string[];
    readonly video: readonly string[];
  },
): CaptureSourceObservations {
  const kinds = snapshots.get(snapshot);
  if (!kinds) throw invalid();
  const expected = (["image", "audio", "video"] as const).flatMap((kind) =>
    mediaKeys[kind].map((sourceKey) => ({ kind, sourceKey }))
  );
  if (
    expected.length !== kinds.length ||
    expected.some((item, i) =>
      item.kind !== kinds[i] ||
      item.sourceKey !== snapshot.observations.items[i].sourceKey
    )
  ) throw invalid();
  return snapshot.observations;
}
