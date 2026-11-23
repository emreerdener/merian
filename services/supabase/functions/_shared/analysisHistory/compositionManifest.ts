import { MEDIA_BUDGETS } from "../mediaBudgets.ts";
import {
  type ImageFocusRegion,
  parseImageFocusRegion,
} from "../identify/imageFocus.ts";
import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { EVIDENCE_MAX_BYTES } from "./evidence.ts";
import { parsePreparedVideoProvenance } from "./videoProvenance.ts";

export interface CompositionArtifact {
  readonly media_id: string;
  readonly content_type: string;
  readonly byte_count: number;
  readonly sha256: string;
}
export type CompositionNode =
  | Readonly<{ kind: "description"; text: string }>
  | Readonly<
    {
      kind: "image";
      artifact: CompositionArtifact;
      focus_region?: ImageFocusRegion;
    }
  >
  | Readonly<{ kind: "audio"; artifact: CompositionArtifact }>
  | Readonly<{
    kind: "video";
    provenance: ReturnType<typeof parsePreparedVideoProvenance>;
  }>;

/** One ordered child composition. Metadata alone grants no upload or execution
 * authority. Each video keeps its retained source and exact derivation cohort;
 * companion audio is never reclassified as a standalone toolbar item.
 */
export function parseCompositionManifest(
  value: unknown,
  observationID: string,
  analysisID: string,
  sourceAnalysisID: string,
) {
  const seen = new Set(
    [observationID, analysisID, sourceAnalysisID].map(historyUUID),
  );
  if (seen.size !== 3) return invalidHistory();
  const manifest = exactObject(value, ["schema_version", "items"]);
  if (
    (manifest.schema_version !== 5 && manifest.schema_version !== 6) ||
    !Array.isArray(manifest.items) ||
    manifest.items.length < 1 || manifest.items.length > 64
  ) return invalidHistory();
  let physical = 0, photos = 0, audio = 0, videos = 0, textUnits = 0;
  let imageBytes = 0, totalBytes = 0;
  function retain(item: CompositionArtifact) {
    if (seen.has(item.media_id)) return invalidHistory();
    seen.add(item.media_id);
    totalBytes += item.byte_count;
    if (item.content_type.startsWith("image/")) imageBytes += item.byte_count;
    if (item.content_type === "audio/wav") audio++;
    if (
      totalBytes > EVIDENCE_MAX_BYTES ||
      imageBytes > MEDIA_BUDGETS.maxImageRawBytes ||
      audio > MEDIA_BUDGETS.maxAudioClips
    ) return invalidHistory();
  }
  const items: CompositionNode[] = manifest.items.map((value) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return invalidHistory();
    }
    if ("kind" in value && value.kind === "description") {
      const node = exactObject(value, ["kind", "text"]);
      if (
        typeof node.text !== "string" || !node.text.trim() ||
        node.text.length > 16384 || [...node.text].length > 8192 ||
        (node.text.includes("\0") || /[\uD800-\uDFFF]/u.test(node.text)) ||
        node.text.length > 32000 - textUnits
      ) return invalidHistory();
      textUnits += node.text.length;
      return Object.freeze({ kind: "description" as const, text: node.text });
    }
    physical++;
    if ("kind" in value && value.kind === "video") {
      if (++videos > MEDIA_BUDGETS.maxStagedVideoFiles) return invalidHistory();
      const node = exactObject(value, ["kind", "provenance"]);
      const provenance = parsePreparedVideoProvenance(
        node.provenance,
        observationID,
        analysisID,
      );
      retain(provenance.source);
      provenance.frames.forEach((frame) => retain(frame.artifact));
      if (provenance.audio) retain(provenance.audio.artifact);
      return Object.freeze({ kind: "video" as const, provenance });
    }
    const hasFocus = manifest.schema_version === 6 && "kind" in value &&
      value.kind === "image" && "focus_region" in value;
    const node = exactObject(
      value,
      hasFocus ? ["kind", "artifact", "focus_region"] : ["kind", "artifact"],
    );
    if (node.kind !== "image" && node.kind !== "audio") return invalidHistory();
    const row = exactObject(node.artifact, [
      "media_id",
      "content_type",
      "byte_count",
      "sha256",
    ]);
    const image = node.kind === "image";
    if (
      typeof row.content_type !== "string" ||
      !(image ? ["image/jpeg", "image/png"] : ["audio/wav"])
        .includes(row.content_type) ||
      typeof row.byte_count !== "number" ||
      !Number.isSafeInteger(row.byte_count) ||
      row.byte_count < (image ? 1 : 46) ||
      row.byte_count >
        (image
          ? MEDIA_BUDGETS.maxImageRawBytes
          : MEDIA_BUDGETS.maxAudioRawBytes) ||
      typeof row.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(row.sha256)
    ) return invalidHistory();
    const artifact = Object.freeze({
      media_id: historyUUID(row.media_id),
      content_type: row.content_type,
      byte_count: row.byte_count,
      sha256: row.sha256,
    });
    retain(artifact);
    if (image) photos++;
    if (hasFocus) {
      const focus_region = parseImageFocusRegion(node.focus_region);
      if (!focus_region) return invalidHistory();
      return Object.freeze({ kind: "image" as const, artifact, focus_region });
    }
    return Object.freeze({ kind: node.kind, artifact });
  });
  // Keep the existing photo-history limit. Mixed/recorded compositions use
  // Capture's two physical slots; descriptions never consume those slots.
  if (
    physical < 1 ||
    physical > (physical === photos ? MEDIA_BUDGETS.maxImageCount : 2)
  ) return invalidHistory();
  return Object.freeze({
    schema_version: manifest.schema_version,
    items: Object.freeze(items),
  });
}

export type CompositionManifest = ReturnType<typeof parseCompositionManifest>;
