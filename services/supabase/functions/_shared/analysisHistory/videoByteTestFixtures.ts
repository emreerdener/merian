import { videoSourceFingerprint } from "./videoSourceFingerprint.ts";
import { evidenceDigest } from "./evidence.ts";
import { buildVideoEvidenceUploadRequest } from "./videoEvidence.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const load = async (name: string) =>
  JSON.parse(
    await Deno.readTextFile(
      new URL(`./fixtures/${name}.json`, import.meta.url),
    ),
  );
const corpus = await load("retained-video-variants");
const frames = await load("video-frame-containers");
const vectors = await load("video-request-v4");
const decode = (base64: string) =>
  Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));

export async function videoByteFixture(audio: boolean) {
  const source = corpus.find((row: { hasAudio: boolean }) =>
    row.hasAudio === audio
  );
  const input = structuredClone(vectors[0].input);
  const graph = input.evidence_manifest.provenance;
  const sourceBytes = decode(source.base64), frame = decode(frames[0].base64);
  graph.source.byte_count = sourceBytes.length;
  graph.source.sha256 = await evidenceDigest(sourceBytes);
  graph.parameters.duration_ticks = source.durationTicks;
  graph.parameters.inference_long_edge = frames[0].edge;
  const bytes = [sourceBytes];
  for (const [index, row] of graph.frames.entries()) {
    row.requested_time_ticks = Math.min(
      Math.max(Math.round(source.durationTicks * (1 + 2 * index) / 10), 30),
      source.durationTicks - 30,
    );
    row.actual_time_ticks = row.requested_time_ticks;
    row.artifact.content_type = frames[0].content_type;
    row.artifact.byte_count = frame.length;
    row.artifact.sha256 = await evidenceDigest(frame);
    bytes.push(frame.slice());
  }
  if (audio) {
    const samples = source.durationTicks * 44100 / 600;
    const wav = new Uint8Array(44 + samples * 2),
      view = new DataView(wav.buffer);
    for (
      const [at, text] of [[0, "RIFF"], [8, "WAVE"], [12, "fmt "], [
        36,
        "data",
      ]] as const
    ) wav.set(new TextEncoder().encode(text), at);
    for (
      const [at, n] of [
        [4, wav.length - 8],
        [16, 16],
        [24, 44100],
        [28, 88200],
        [40, samples * 2],
      ]
    ) view.setUint32(at, n, true);
    for (const [at, n] of [[20, 1], [22, 1], [32, 2], [34, 16]]) {
      view.setUint16(at, n, true);
    }
    Object.assign(graph.audio, {
      start_ticks: 0,
      end_ticks: source.durationTicks,
      sample_count: samples,
    });
    Object.assign(graph.audio.artifact, {
      byte_count: wav.length,
      sha256: await evidenceDigest(wav),
    });
    bytes.push(wav);
  } else graph.audio = null;
  const candidate = {
    schema_version: 2,
    input,
    fingerprint_version: 1,
    fingerprint: await videoSourceFingerprint(input),
  };
  const request = await buildVideoEvidenceUploadRequest(candidate);
  const receipt = {
    ...request,
    owner_id: id(900),
    state: "ready",
    expires_at: "2026-01-01T00:00:00.000Z",
    items: request.items.map((item, i) => ({
      ...item,
      object_id: id(800 + i),
      ready_at: "2025-12-31T23:59:00.000Z",
    })),
  };
  return { input: candidate, receipt, bytes };
}
