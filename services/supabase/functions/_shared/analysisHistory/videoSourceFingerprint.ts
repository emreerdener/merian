import { invalidHistory } from "./contract.ts";
import { parsePreparedVideoAdmission } from "./videoAdmission.ts";

/** Held contract only. SQL/Swift parity is required before any consumer is connected.
 * Distinct domain; never changes v1 photo/audio fingerprints or saved request bytes.
 */
export const VIDEO_SOURCE_FINGERPRINT_VERSION = 1;
const encoder = new TextEncoder();

export function videoSourceCanonicalBytes(
  value: unknown,
): Uint8Array<ArrayBuffer> {
  const input = parsePreparedVideoAdmission(value);
  const manifest = input.evidence_manifest, graph = manifest.provenance;
  const p = graph.parameters;
  const fields: (string | number)[] = [
    "merian.analysis-video-source-binding",
    VIDEO_SOURCE_FINGERPRINT_VERSION,
    input.schema_version,
    input.observation_id,
    input.analysis_id,
    input.source_analysis_id,
    input.request_digest,
    input.entitlement_protocol,
    input.identification_protocol,
    input.history_protocol,
    input.expected_processor_permission,
    graph.audio ? "multimodal_video_audio_v1" : "multimodal_video_frames_v1",
    manifest.schema_version,
    graph.schema_version,
    graph.preprocessing_version,
  ];
  function artifact(item: typeof graph.source) {
    fields.push(item.media_id, item.content_type, item.byte_count, item.sha256);
  }
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
    const a = graph.audio;
    fields.push(
      a.source_media_id,
      a.track,
      a.start_ticks,
      a.end_ticks,
      a.sample_rate,
      a.sample_count,
      a.channels,
      a.bits_per_sample,
      a.encoding,
    );
    artifact(a.artifact);
  }
  fields.push(manifest.descriptions.length, ...manifest.descriptions);
  const framed = fields.map((field) => {
    if (
      typeof field === "number" &&
      (!Number.isSafeInteger(field) || field < 0)
    ) {
      return invalidHistory();
    }
    const text = String(field);
    // Preserve PostgreSQL text parity without replacement or Unicode normalization.
    if (text.includes("\u0000") || /[\uD800-\uDFFF]/u.test(text)) {
      return invalidHistory();
    }
    return `${encoder.encode(text).length}:${text},`;
  });
  const bytes = encoder.encode(framed.join(""));
  if (bytes.length > 262_144) return invalidHistory();
  return bytes;
}

/** Own the validated semantic snapshot before hashing awaits. Not proof of media bytes. */
export async function videoSourceFingerprint(value: unknown): Promise<string> {
  const bytes = videoSourceCanonicalBytes(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}
