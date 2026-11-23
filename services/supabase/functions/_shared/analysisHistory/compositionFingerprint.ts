import { imageFocusFingerprintFields } from "../identify/imageFocus.ts";
import {
  parseCompositionAdmission,
  parseCompositionRequestStructure,
  parseFocusedCompositionRequestStructure,
} from "./compositionAdmission.ts";
import type { CompositionArtifact } from "./compositionManifest.ts";
import { invalidHistory } from "./contract.ts";

/** Separate domain; never recanonicalize a stored photo/audio/video request.
 * All text is byte-exact UTF-8. Metadata fingerprinting proves no media bytes.
 */
export function compositionCanonicalBytes(
  value: unknown,
): Uint8Array<ArrayBuffer> {
  return canonicalBytes(parseCompositionAdmission(value), false);
}

/** V6 has a distinct typed unsigned digest. It never hashes JSON float text. */
export async function focusedCompositionRequestDigest(
  value: unknown,
): Promise<string> {
  return await digest(
    canonicalBytes(parseFocusedCompositionRequestStructure(value), true),
  );
}

export async function focusedCompositionFingerprint(
  value: unknown,
): Promise<string> {
  const input = await validateFocusedCompositionAdmission(value);
  return digest(canonicalBytes(input, false));
}

/** Identity validation only; byte verification and ownership are separate gates. */
export async function validateFocusedCompositionAdmission(value: unknown) {
  const input = parseFocusedCompositionRequestStructure(value);
  if (input.request_digest !== await digest(canonicalBytes(input, true))) {
    return invalidHistory();
  }
  return input;
}

function canonicalBytes(
  input:
    | ReturnType<typeof parseCompositionAdmission>
    | ReturnType<typeof parseFocusedCompositionRequestStructure>,
  unsigned: boolean,
): Uint8Array<ArrayBuffer> {
  const fields: (string | number)[] = [
    unsigned
      ? "merian.analysis-composition-request"
      : "merian.analysis-composition-source-binding",
    input.schema_version === 6 ? 2 : 1,
    input.schema_version,
    input.observation_id,
    input.analysis_id,
    input.source_analysis_id,
    ...(unsigned ? [] : [input.request_digest]),
    input.entitlement_protocol,
    input.identification_protocol,
    input.history_protocol,
    input.expected_processor_permission,
    input.evidence_manifest.schema_version,
    input.evidence_manifest.items.length,
  ];
  function artifact(item: CompositionArtifact) {
    fields.push(item.media_id, item.content_type, item.byte_count, item.sha256);
  }
  for (const item of input.evidence_manifest.items) {
    fields.push(item.kind);
    if (item.kind === "description") {
      fields.push(item.text);
    } else if (item.kind === "video") {
      const graph = item.provenance, p = graph.parameters;
      fields.push(graph.schema_version, graph.preprocessing_version);
      artifact(graph.source);
      fields.push(
        p.timescale,
        p.frame_pipeline,
        p.decode_long_edge,
        p.duration_ticks,
        p.sampling,
        p.preferred_track_transform ? 1 : 0,
        p.crop,
        p.crop_center_basis_points,
        p.inference_long_edge,
        p.encoding_quality_percent,
        graph.frames.length,
      );
      for (const frame of graph.frames) {
        fields.push(
          frame.index,
          frame.source_media_id,
          frame.requested_time_ticks,
          frame.actual_time_ticks,
        );
        artifact(frame.artifact);
      }
      fields.push(graph.audio ? 1 : 0);
      if (graph.audio) {
        const audio = graph.audio;
        fields.push(
          audio.source_media_id,
          audio.track,
          audio.start_ticks,
          audio.end_ticks,
          audio.sample_rate,
          audio.sample_count,
          audio.channels,
          audio.bits_per_sample,
          audio.encoding,
        );
        artifact(audio.artifact);
      }
    } else {
      artifact(item.artifact);
      if (input.schema_version === 6 && item.kind === "image") {
        fields.push(item.focus_region ? 1 : 0);
        if (item.focus_region) {
          fields.push(...imageFocusFingerprintFields(item.focus_region));
        }
      }
    }
  }
  const encoder = new TextEncoder();
  const bytes = encoder.encode(
    fields.map((field) => {
      const text = String(field);
      if ((text.includes("\0") || /[\uD800-\uDFFF]/u.test(text))) {
        return invalidHistory();
      }
      return `${encoder.encode(text).length}:${text},`;
    }).join(""),
  );
  if (bytes.length > 262_144) return invalidHistory();
  return bytes;
}

export async function compositionFingerprint(value: unknown): Promise<string> {
  return await digest(compositionCanonicalBytes(value));
}

async function digest(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(
    new Uint8Array(hash),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

/** V5 preserves its original digest semantics. V6 verifies the typed unsigned
 * request digest before producing an identity used for ownership. */
export async function compositionRequestFingerprint(
  value: unknown,
): Promise<string> {
  const input = parseCompositionRequestStructure(value);
  return input.schema_version === 6
    ? await focusedCompositionFingerprint(input)
    : await compositionFingerprint(input);
}
export async function validateCompositionRequest(value: unknown) {
  const input = parseCompositionRequestStructure(value);
  if (input.schema_version === 6) {
    return await validateFocusedCompositionAdmission(input);
  }
  return input;
}
