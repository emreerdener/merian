import { parseCompositionRequestStructure } from "./compositionAdmission.ts";
import type { CompositionArtifact } from "./compositionManifest.ts";
import { exactObject, invalidHistory } from "./contract.ts";

export const COMPOSITION_ITEM_KEYS = [
  "node_index",
  "role",
  "frame_index",
  "media_id",
  "content_type",
  "byte_count",
  "sha256",
] as const;
export type CompositionCohortItem =
  & CompositionArtifact
  & Readonly<{
    node_index: number;
    role: "image" | "audio" | "video_source" | "video_frame" | "video_audio";
    frame_index: number | null;
  }>;

/** Stable inventory for one child, including retained video sources. Node indexes
 * refer to the exact submitted timeline (notes included), not filtered positions.
 * This projection is neither an allocation receipt nor dispatch authority.
 */
export function compositionCohortItems(
  value: unknown,
): readonly CompositionCohortItem[] {
  const input = parseCompositionRequestStructure(value);
  const items: CompositionCohortItem[] = [];
  for (const [node_index, node] of input.evidence_manifest.items.entries()) {
    const append = (
      role: CompositionCohortItem["role"],
      artifact: CompositionArtifact,
      frame_index: number | null = null,
    ) => {
      items.push(Object.freeze({ node_index, role, frame_index, ...artifact }));
    };
    if (node.kind === "description") continue;
    if (node.kind !== "video") {
      append(node.kind, node.artifact);
      continue;
    }
    append("video_source", node.provenance.source);
    for (const frame of node.provenance.frames) {
      append("video_frame", frame.artifact, frame.index);
    }
    if (node.provenance.audio) {
      append("video_audio", node.provenance.audio.artifact);
    }
  }
  return Object.freeze(items);
}

export function matchCompositionCohortItems(value: unknown, input: unknown) {
  const expected = compositionCohortItems(input);
  if (!Array.isArray(value) || value.length !== expected.length) {
    return invalidHistory();
  }
  for (const [index, item] of expected.entries()) {
    const actual = exactObject(value[index], COMPOSITION_ITEM_KEYS);
    if (COMPOSITION_ITEM_KEYS.some((key) => actual[key] !== item[key])) {
      return invalidHistory();
    }
  }
  return expected;
}
