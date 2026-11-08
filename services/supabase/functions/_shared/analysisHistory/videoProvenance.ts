import { MEDIA_BUDGETS } from "../mediaBudgets.ts";
import { exactObject, historyUUID, invalidHistory } from "./contract.ts";

function integer(value: unknown, min: number, max: number): number {
  if (
    typeof value !== "number" || !Number.isSafeInteger(value) || value < min ||
    value > max
  ) return invalidHistory();
  return value;
}

/** Private metadata groundwork only: no admission, byte verification or provider authority.
 * The retained clip MUST be the actual derivation source. Existing parallel legacy
 * preprocessing cannot be relabelled as this generation. Retry uses saved outputs.
 */
export function parsePreparedVideoProvenance(
  value: unknown,
  observationID: string,
  analysisID: string,
) {
  const seen = new Set([historyUUID(observationID), historyUUID(analysisID)]);
  if (seen.size !== 2) return invalidHistory();
  const row = exactObject(value, [
    "schema_version",
    "preprocessing_version",
    "source",
    "parameters",
    "frames",
    "audio",
  ]);
  if (
    row.schema_version !== 1 || row.preprocessing_version !== "retained_clip_v1"
  ) return invalidHistory();
  function artifact(
    value: unknown,
    types: readonly string[],
    min: number,
    max: number,
  ) {
    const item = exactObject(value, [
      "media_id",
      "content_type",
      "byte_count",
      "sha256",
    ]);
    const id = historyUUID(item.media_id);
    if (
      seen.has(id) || typeof item.content_type !== "string" ||
      !types.includes(item.content_type) ||
      typeof item.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(item.sha256)
    ) return invalidHistory();
    seen.add(id);
    return Object.freeze({
      media_id: id,
      content_type: item.content_type,
      byte_count: integer(item.byte_count, min, max),
      sha256: item.sha256,
    });
  }
  const source = artifact(
    row.source,
    ["video/mp4"],
    1,
    MEDIA_BUDGETS.maxVideoRawBytes,
  );
  const p = exactObject(row.parameters, [
    "timescale",
    "frame_pipeline",
    "decode_long_edge",
    "duration_ticks",
    "sampling",
    "preferred_track_transform",
    "crop",
    "crop_center_basis_points",
    "inference_long_edge",
    "encoding_quality_percent",
  ]);
  // Five requested samples at 10/30/50/70/90 percent, bounded away from either end.
  // A new producer must record actual decoder times, not substitute requested times.
  if (
    p.timescale !== 600 || p.frame_pipeline !== "direct_inference_v1" ||
    p.decode_long_edge !== 2048 || p.sampling !== "five_interior_v1" ||
    p.preferred_track_transform !== true ||
    p.crop !== "square_v1" || p.encoding_quality_percent !== 85 ||
    (p.inference_long_edge !== 768 && p.inference_long_edge !== 1024)
  ) return invalidHistory();
  const duration = integer(p.duration_ticks, 60, 3000);
  const parameters = Object.freeze({
    timescale: 600 as const,
    frame_pipeline: "direct_inference_v1" as const,
    decode_long_edge: 2048 as const,
    duration_ticks: duration,
    sampling: "five_interior_v1" as const,
    preferred_track_transform: true as const,
    crop: "square_v1" as const,
    crop_center_basis_points: integer(p.crop_center_basis_points, 0, 10000),
    inference_long_edge: p.inference_long_edge,
    encoding_quality_percent: 85 as const,
  });
  if (!Array.isArray(row.frames) || row.frames.length !== 5) {
    return invalidHistory();
  }
  let frameBytes = 0;
  let previousTime = -1;
  const frames = Object.freeze(row.frames.map((value, index) => {
    const frame = exactObject(value, [
      "index",
      "source_media_id",
      "requested_time_ticks",
      "actual_time_ticks",
      "artifact",
    ]);
    const expected = Math.min(
      Math.max(Math.floor(duration * (1 + 2 * index) / 10 + 0.5), 30),
      duration - 30,
    );
    if (
      frame.index !== index || frame.source_media_id !== source.media_id ||
      frame.requested_time_ticks !== expected
    ) return invalidHistory();
    const output = artifact(
      frame.artifact,
      ["image/webp", "image/jpeg"],
      1,
      MEDIA_BUDGETS.maxImageRawBytes,
    );
    frameBytes += output.byte_count;
    if (frameBytes > MEDIA_BUDGETS.maxImageRawBytes) return invalidHistory();
    const actualTime = integer(frame.actual_time_ticks, 0, duration - 1);
    if (actualTime < previousTime) return invalidHistory();
    previousTime = actualTime;
    return Object.freeze({
      index,
      source_media_id: source.media_id,
      requested_time_ticks: expected,
      actual_time_ticks: actualTime,
      artifact: output,
    });
  }));
  function audio(value: unknown) {
    if (value === null) return null;
    const item = exactObject(value, [
      "source_media_id",
      "track",
      "start_ticks",
      "end_ticks",
      "sample_rate",
      "sample_count",
      "channels",
      "bits_per_sample",
      "encoding",
      "artifact",
    ]);
    if (
      item.source_media_id !== source.media_id ||
      item.track !== "first_audio_track" || item.sample_rate !== 44100 ||
      item.channels !== 1 ||
      item.bits_per_sample !== 16 || item.encoding !== "pcm_s16le"
    ) return invalidHistory();
    const start = integer(item.start_ticks, 0, duration - 1);
    const end = integer(item.end_ticks, start + 1, duration);
    const samples = integer(item.sample_count, 1, 220500);
    // At most one tick of duration rounding; output sample count stays exact.
    if (Math.abs(samples * 600 - (end - start) * 44100) > 44100) {
      return invalidHistory();
    }
    const output = artifact(
      item.artifact,
      ["audio/wav"],
      44 + samples * 2,
      MEDIA_BUDGETS.maxAudioRawBytes,
    );
    return Object.freeze({
      source_media_id: source.media_id,
      track: "first_audio_track" as const,
      start_ticks: start,
      end_ticks: end,
      sample_count: samples,
      sample_rate: 44100 as const,
      channels: 1 as const,
      bits_per_sample: 16 as const,
      encoding: "pcm_s16le" as const,
      artifact: output,
    });
  }
  return Object.freeze({
    schema_version: 1 as const,
    preprocessing_version: "retained_clip_v1" as const,
    source,
    parameters,
    frames,
    audio: audio(row.audio),
  });
}
