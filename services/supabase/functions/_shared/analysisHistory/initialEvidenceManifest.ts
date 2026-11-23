import { MEDIA_BUDGETS } from "../mediaBudgets.ts";
import {
  imageFocusFingerprintFields,
  type ImageFocusRegion,
  parseImageFocusRegion,
} from "../identify/imageFocus.ts";
import type { CompositionArtifact } from "./compositionManifest.ts";
import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { EVIDENCE_MAX_BYTES, evidenceDigest } from "./evidence.ts";
import {
  type InitialPhotoPreparation,
  initialPhotoPreparationFields,
  parseInitialPhotoPreparation,
} from "./initialPhotoPreparation.ts";

// Ordinary retained-original storage bounds. These never enlarge provider or
// historical V7 admission. Display derivatives remain local and are not roles
// in this manifest. The maximum graph is 64 MiB originals + 5 MiB AI images.
export const INITIAL_ORIGINAL_MAX_BYTES = 32 * 1024 * 1024;
export const INITIAL_ORIGINAL_COHORT_MAX_BYTES = 64 * 1024 * 1024;
export const INITIAL_V8_MAX_BYTES = INITIAL_ORIGINAL_COHORT_MAX_BYTES +
  MEDIA_BUDGETS.maxImageRawBytes;

export type InitialEvidenceNode =
  | Readonly<{ kind: "description"; text: string }>
  | Readonly<{
    kind: "image";
    source: CompositionArtifact;
    prepared: CompositionArtifact;
    coordinate_basis: "prepared_image_top_left_v1";
    focus_region: ImageFocusRegion | null;
    preparation?: InitialPhotoPreparation;
  }>
  | Readonly<{
    kind: "audio";
    source: CompositionArtifact;
    prepared: CompositionArtifact;
  }>
  | Readonly<{
    kind: "video";
    source: CompositionArtifact;
    playback: CompositionArtifact;
    frames: readonly CompositionArtifact[];
    audio:
      | Readonly<{
        source: CompositionArtifact;
        prepared: CompositionArtifact;
      }>
      | null;
  }>;

/** Truthful ordinary-capture evidence, distinct from a retained_clip_v1
 * reanalysis recipe. Frame order is known; capture timing, sampling and crop
 * derivation are deliberately not asserted. A later request may prepare the
 * retained clip anew without rewriting this original evidence.
 */
export function parseInitialEvidenceManifest(
  value: unknown,
  scanID: string,
  generation: string,
) {
  const seen = new Set([historyUUID(scanID), historyUUID(generation)]);
  if (seen.size !== 2) return invalidHistory();
  const manifest = exactObject(value, ["schema_version", "items"]);
  if (
    (manifest.schema_version !== 7 && manifest.schema_version !== 8 &&
      manifest.schema_version !== 9) ||
    !Array.isArray(manifest.items) ||
    manifest.items.length < 1 || manifest.items.length > 64
  ) return invalidHistory();
  const version = manifest.schema_version;
  let totalBytes = 0, imageBytes = 0, originalBytes = 0, textUnits = 0;
  let physical = 0, photos = 0, videos = 0, audioCount = 0;
  function artifact(
    value: unknown,
    type: "image" | "audio" | "video",
    source = false,
  ) {
    const row = exactObject(value, [
      "media_id",
      "content_type",
      "byte_count",
      "sha256",
    ]);
    const id = historyUUID(row.media_id);
    const types = type === "image"
      ? (source
        ? ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"]
        : ["image/jpeg", "image/png"])
      : type === "audio"
      ? (source ? ["audio/wav", "audio/mp4"] : ["audio/wav"])
      : ["video/mp4"];
    const limit = type === "image"
      ? (source && version >= 8
        ? INITIAL_ORIGINAL_MAX_BYTES
        : MEDIA_BUDGETS.maxImageRawBytes)
      : type === "audio"
      ? MEDIA_BUDGETS.maxAudioRawBytes
      : MEDIA_BUDGETS.maxVideoRawBytes;
    if (
      seen.has(id) || typeof row.content_type !== "string" ||
      !types.includes(row.content_type) ||
      typeof row.byte_count !== "number" ||
      !Number.isSafeInteger(row.byte_count) ||
      row.byte_count < (row.content_type === "audio/wav" ? 46 : 1) ||
      row.byte_count > limit || typeof row.sha256 !== "string" ||
      !/^[0-9a-f]{64}$/.test(row.sha256)
    ) return invalidHistory();
    seen.add(id);
    totalBytes += row.byte_count;
    if (type === "image" && !source) imageBytes += row.byte_count;
    if (type === "image" && source) originalBytes += row.byte_count;
    if (
      totalBytes >
        (version >= 8 ? INITIAL_V8_MAX_BYTES : EVIDENCE_MAX_BYTES) ||
      (version >= 8 && originalBytes > INITIAL_ORIGINAL_COHORT_MAX_BYTES) ||
      imageBytes > MEDIA_BUDGETS.maxImageRawBytes
    ) return invalidHistory();
    return Object.freeze({
      media_id: id,
      content_type: row.content_type,
      byte_count: row.byte_count,
      sha256: row.sha256,
    });
  }
  function audio(value: unknown) {
    if (++audioCount > MEDIA_BUDGETS.maxAudioClips) return invalidHistory();
    const row = exactObject(value, ["source", "prepared"]);
    // Distinct role identities even when normalization preserved the bytes.
    return Object.freeze({
      source: artifact(row.source, "audio", true),
      prepared: artifact(row.prepared, "audio"),
    });
  }
  const items: InitialEvidenceNode[] = manifest.items.map((value) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return invalidHistory();
    }
    if ("kind" in value && value.kind === "description") {
      const row = exactObject(value, ["kind", "text"]);
      if (
        typeof row.text !== "string" || !row.text.trim() ||
        row.text.length > 16384 || [...row.text].length > 8192 ||
        row.text.includes("\0") || /[\uD800-\uDFFF]/u.test(row.text) ||
        (textUnits += row.text.length) > 32000
      ) return invalidHistory();
      return Object.freeze({ kind: "description" as const, text: row.text });
    }
    physical++;
    if ("kind" in value && value.kind === "image") {
      const row = exactObject(value, [
        "kind",
        "source",
        "prepared",
        "coordinate_basis",
        "focus_region",
        ...(version === 9 ? ["preparation"] : []),
      ]);
      if (row.coordinate_basis !== "prepared_image_top_left_v1") {
        return invalidHistory();
      }
      const focus = row.focus_region === null
        ? null
        : parseImageFocusRegion(row.focus_region);
      if (row.focus_region !== null && !focus) return invalidHistory();
      photos++;
      return Object.freeze({
        kind: "image" as const,
        source: artifact(row.source, "image", true),
        prepared: artifact(row.prepared, "image"),
        coordinate_basis: "prepared_image_top_left_v1" as const,
        focus_region: focus,
        ...(version === 9
          ? { preparation: parseInitialPhotoPreparation(row.preparation) }
          : {}),
      });
    }
    if ("kind" in value && value.kind === "audio") {
      const row = exactObject(value, ["kind", "source", "prepared"]);
      return Object.freeze({
        kind: "audio" as const,
        ...audio({ source: row.source, prepared: row.prepared }),
      });
    }
    const row = exactObject(value, [
      "kind",
      "source",
      "playback",
      "frames",
      "audio",
    ]);
    if (
      row.kind !== "video" || ++videos > MEDIA_BUDGETS.maxStagedVideoFiles ||
      !Array.isArray(row.frames) || row.frames.length < 1 ||
      row.frames.length > MEDIA_BUDGETS.maxImageCount
    ) return invalidHistory();
    return Object.freeze({
      kind: "video" as const,
      source: artifact(row.source, "video", true),
      playback: artifact(row.playback, "video"),
      frames: Object.freeze(
        row.frames.map((frame) => artifact(frame, "image")),
      ),
      audio: row.audio === null ? null : audio(row.audio),
    });
  });
  if (
    physical < 1 ||
    physical > (physical === photos ? MEDIA_BUDGETS.maxImageCount : 2)
  ) return invalidHistory();
  return Object.freeze({
    schema_version: version,
    items: Object.freeze(items),
  });
}

export type InitialEvidenceManifest = ReturnType<
  typeof parseInitialEvidenceManifest
>;

/** A role is scoped to its owner-facing item; frames and companion audio never
 * become independent toolbar items. Every artifact occurs once in this table.
 */
export function initialEvidenceArtifacts(manifest: InitialEvidenceManifest) {
  return manifest.items.flatMap((item, itemIndex) => {
    const role = (artifact: CompositionArtifact, role: string, index = 0) =>
      Object.freeze({
        ...artifact,
        item_index: itemIndex,
        role,
        role_index: index,
      });
    switch (item.kind) {
      case "description":
        return [];
      case "image":
        return [
          role(item.source, "source_image"),
          role(item.prepared, "prepared_image"),
        ];
      case "audio":
        return [
          role(item.source, "source_audio"),
          role(item.prepared, "prepared_audio"),
        ];
      case "video":
        return [
          role(item.source, "source_video"),
          role(item.playback, "playback_video"),
          ...item.frames.map((frame, i) => role(frame, "inference_frame", i)),
          ...(item.audio
            ? [
              role(item.audio.source, "source_companion_audio"),
              role(item.audio.prepared, "prepared_companion_audio"),
            ]
            : []),
        ];
    }
  });
}

/** Typed UTF-8 digest, not JSON number spelling. This proves metadata identity;
 * the storage owner separately verifies every actual prepared/source buffer.
 */
export async function initialEvidenceDigest(
  value: unknown,
  scanID: string,
  generation: string,
) {
  return await evidenceDigest(
    initialEvidenceCanonicalBytes(value, scanID, generation),
  );
}

export function initialEvidenceCanonicalBytes(
  value: unknown,
  scanID: string,
  generation: string,
) {
  const manifest = parseInitialEvidenceManifest(value, scanID, generation);
  const fields: (string | number)[] = [
    "merian.initial-evidence",
    1,
    scanID,
    generation,
    manifest.schema_version,
    manifest.items.length,
  ];
  const artifact = (a: CompositionArtifact) => {
    fields.push(a.media_id, a.content_type, a.byte_count, a.sha256);
  };
  for (const item of manifest.items) {
    fields.push(item.kind);
    if (item.kind === "description") fields.push(item.text);
    else if (item.kind === "image") {
      artifact(item.source);
      artifact(item.prepared);
      fields.push(item.coordinate_basis, item.focus_region ? 1 : 0);
      if (item.focus_region) {
        fields.push(...imageFocusFingerprintFields(item.focus_region));
      }
      if (manifest.schema_version === 9) {
        fields.push(...initialPhotoPreparationFields(item.preparation));
      }
    } else if (item.kind === "audio") {
      artifact(item.source);
      artifact(item.prepared);
    } else {
      artifact(item.source);
      artifact(item.playback);
      fields.push(item.frames.length);
      item.frames.forEach(artifact);
      fields.push(item.audio ? 1 : 0);
      if (item.audio) {
        artifact(item.audio.source);
        artifact(item.audio.prepared);
      }
    }
  }
  const utf8 = new TextEncoder();
  return utf8.encode(
    fields.map((value) => {
      const text = String(value);
      return `${utf8.encode(text).length}:${text},`;
    }).join(""),
  );
}
