import { MEDIA_BUDGETS } from "../mediaBudgets.ts";
import { exactObject, historyUUID, invalidHistory } from "./contract.ts";

export type PreparedAudioEvidence =
  | Readonly<{
    kind: "audio";
    media_id: string;
    content_type: "audio/wav";
    byte_count: number;
    sha256: string;
  }>
  | Readonly<{ kind: "description"; text: string }>;

/** Metadata contract only. It proves neither WAV contents nor upload readiness.
 * No current admission, reader or provider route accepts this generation.
 */
export function parsePreparedAudioManifest(
  value: unknown,
  observationID: string,
  analysisID: string,
): Readonly<{ schema_version: 3; items: readonly PreparedAudioEvidence[] }> {
  const observation = historyUUID(observationID);
  const analysis = historyUUID(analysisID);
  if (observation === analysis) return invalidHistory();
  const manifest = exactObject(value, ["schema_version", "items"]);
  if (
    manifest.schema_version !== 3 || !Array.isArray(manifest.items) ||
    manifest.items.length < 1 || manifest.items.length > 64
  ) return invalidHistory();
  let audioCount = 0;
  let textUnits = 0;
  const items: PreparedAudioEvidence[] = manifest.items.map((value) => {
    if (
      value !== null && typeof value === "object" &&
      "kind" in value && value.kind === "description"
    ) {
      const item = exactObject(value, ["kind", "text"]);
      if (
        typeof item.text !== "string" || !item.text.trim() ||
        item.text.length > 16384 || [...item.text].length > 8192 ||
        item.text.length > 32000 - textUnits
      ) return invalidHistory();
      textUnits += item.text.length;
      return Object.freeze({ kind: "description" as const, text: item.text });
    }
    const item = exactObject(value, [
      "kind",
      "media_id",
      "content_type",
      "byte_count",
      "sha256",
    ]);
    const media = historyUUID(item.media_id);
    if (
      item.kind !== "audio" || item.content_type !== "audio/wav" ||
      ++audioCount !== 1 || media === observation || media === analysis ||
      typeof item.byte_count !== "number" ||
      !Number.isSafeInteger(item.byte_count) || item.byte_count < 46 ||
      item.byte_count > MEDIA_BUDGETS.maxAudioRawBytes ||
      typeof item.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(item.sha256)
    ) return invalidHistory();
    return Object.freeze({
      kind: "audio" as const,
      media_id: media,
      content_type: "audio/wav" as const,
      byte_count: item.byte_count,
      sha256: item.sha256,
    });
  });
  if (audioCount !== 1) return invalidHistory();
  return Object.freeze({ schema_version: 3, items: Object.freeze(items) });
}
