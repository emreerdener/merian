import { exactObject, invalidHistory } from "./contract.ts";
import { parsePreparedVideoAdmission } from "./videoAdmission.ts";
import { videoSourceCanonicalBytes } from "./videoSourceFingerprint.ts";

/** Metadata projection only. Neither a receipt nor upload/retirement authority. */
export function preparedVideoCohortItems(input: unknown) {
  // Apply the full cross-runtime binding contract, including text constraints.
  videoSourceCanonicalBytes(input);
  const graph = parsePreparedVideoAdmission(input).evidence_manifest.provenance;
  const item = (
    role: "source" | "frame" | "audio",
    index: number | null,
    artifact: typeof graph.source,
  ) => Object.freeze({ role, index, ...artifact });
  return Object.freeze([
    item("source", null, graph.source),
    ...graph.frames.map((frame) => item("frame", frame.index, frame.artifact)),
    ...(graph.audio ? [item("audio", null, graph.audio.artifact)] : []),
  ]);
}

/** Match a complete ordered inventory, never independent item acknowledgements.
 * No ownership, readiness, source-to-output byte proof or dispatch is implied.
 */
export function matchPreparedVideoCohortItems(value: unknown, input: unknown) {
  const expected = preparedVideoCohortItems(input);
  if (!Array.isArray(value) || value.length !== expected.length) {
    return invalidHistory();
  }
  const keys = [
    "role",
    "index",
    "media_id",
    "content_type",
    "byte_count",
    "sha256",
  ] as const;
  for (const [index, item] of expected.entries()) {
    const actual = exactObject(value[index], keys);
    if (keys.some((key) => actual[key] !== item[key])) return invalidHistory();
  }
  return expected;
}
