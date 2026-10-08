import { parseExecutableAnalysisInput } from "./analysisInput.ts";
import { exactObject, historyUUID, invalidHistory } from "./contract.ts";

/** Prepared fingerprint only: no reservation, authentication or dispatch authority.
 * SQL and Swift parity are required before any producer or consumer is connected.
 * The existing request_digest and saved request bytes are never rewritten.
 * That digest is a replay identifier, not server-verified proof of JSON byte hashing.
 */
export const SOURCE_FINGERPRINT_VERSION = 1;
const encoder = new TextEncoder();

/** UTF-8 netstrings in a fixed semantic order, independent of JSON serialization.
 * Owner is an authorization/storage scope, excluded to preserve account-merge identity.
 */
export function sourceReservationCanonicalBytes(
  value: unknown,
): Uint8Array<ArrayBuffer> {
  const supplied = exactObject(value, [
    "schema_version",
    "observation_id",
    "analysis_id",
    "source_analysis_id",
    "request_digest",
    "evidence_manifest",
    "entitlement_protocol",
    "identification_protocol",
    "history_protocol",
    "expected_processor_permission",
  ]);
  if (supplied.schema_version !== 2 && supplied.schema_version !== 3) {
    return invalidHistory();
  }
  const input = parseExecutableAnalysisInput(supplied);
  const source = historyUUID(input.source_analysis_id);
  const manifest = exactObject(input.evidence_manifest, [
    "schema_version",
    "items",
  ]);
  if (!Array.isArray(manifest.items)) return invalidHistory();
  const fields: (string | number)[] = [
    "merian.analysis-source-reservation",
    SOURCE_FINGERPRINT_VERSION,
    scalar(input.schema_version),
    scalar(input.observation_id),
    scalar(input.analysis_id),
    source,
    scalar(input.request_digest),
    scalar(input.entitlement_protocol),
    scalar(input.identification_protocol),
    scalar(input.history_protocol),
    scalar(input.expected_processor_permission),
    input.schema_version === 2 ? "multimodal_photo_v1" : "multimodal_audio_v1",
    scalar(manifest.schema_version),
    manifest.items.length,
  ];
  for (const raw of manifest.items) {
    if (raw.kind === "description") {
      const item = exactObject(raw, ["kind", "text"]);
      fields.push("description", scalar(item.text));
    } else {
      const item = exactObject(raw, [
        "kind",
        "media_id",
        "content_type",
        "byte_count",
        "sha256",
      ]);
      // This stricter future reservation binding never aliases any source identity.
      if (item.media_id === source) return invalidHistory();
      fields.push(
        scalar(item.kind),
        scalar(item.media_id),
        scalar(item.content_type),
        scalar(item.byte_count),
        scalar(item.sha256),
      );
    }
  }
  const frames = fields.map((field) => {
    const text = String(field);
    // PostgreSQL text cannot preserve NUL or lone UTF-16 surrogates. Never replace them.
    if (
      text.includes("\u0000") || [...text].some((c) => {
        const point = c.codePointAt(0) ?? 0;
        return point >= 0xd800 && point <= 0xdfff;
      })
    ) return invalidHistory();
    return `${encoder.encode(text).length}:${text},`;
  });
  const bytes = encoder.encode(frames.join(""));
  if (bytes.length > 262_144) return invalidHistory();
  return bytes;
}

/** Snapshot the validated bytes before the asynchronous hash boundary. */
export async function sourceReservationFingerprint(
  value: unknown,
): Promise<string> {
  const bytes = sourceReservationCanonicalBytes(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

function scalar(value: unknown): string | number {
  if (typeof value === "string") return value;
  if (
    typeof value === "number" && Number.isSafeInteger(value) && value >= 0 &&
    !Object.is(value, -0)
  ) return value;
  return invalidHistory();
}
