import { assertEquals, assertRejects } from "@std/assert";
import { videoSourceFingerprint } from "./videoSourceFingerprint.ts";
import { evidenceDigest } from "./evidence.ts";
import { buildVideoEvidenceUploadRequest } from "./videoEvidence.ts";
import { materializeVideoCohort } from "./videoMaterialization.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const json = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value));
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

async function fixture(audio: boolean) {
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

Deno.test("video materialization preserves complete audio/silent saved cohort and independent bytes", async () => {
  for (const audio of [true, false]) {
    const f = await fixture(audio), signal = new AbortController().signal;
    let reads = 0;
    const result = await materializeVideoCohort(
      f.input,
      id(900),
      json(f.receipt),
      {
        read(item, options) {
          assertEquals(item, f.receipt.items[reads]);
          assertEquals(options, {
            maximumBytes: f.bytes[reads].length,
            signal,
          });
          return Promise.resolve(f.bytes[reads++]);
        },
      },
      signal,
    );
    assertEquals(reads, audio ? 7 : 6);
    assertEquals(result.items.map((row) => row.bytes), f.bytes);
    result.items[0].bytes.fill(0);
    assertEquals(f.bytes[0][0], 0); // MP4 starts with a big-endian box size.
    assertEquals(await evidenceDigest(f.bytes[0]), f.receipt.items[0].sha256);
  }
});

Deno.test("video materialization denies mismatched or partial receipts before storage", async () => {
  const f = await fixture(true);
  let reads = 0;
  for (
    const change of [{ owner_id: id(901) }, { state: "allocated" }, {
      items: f.receipt.items.slice(1),
    }, { analysis_id: id(902) }]
  ) {
    await assertRejects(() =>
      materializeVideoCohort(
        f.input,
        id(900),
        json({ ...f.receipt, ...change }),
        {
          read() {
            reads++;
            return Promise.resolve(f.bytes[0]);
          },
        },
        new AbortController().signal,
      )
    );
  }
  assertEquals(reads, 0);
});

Deno.test("video materialization stops at every corrupt or missing item without repair", async () => {
  const f = await fixture(true);
  for (let failure = 0; failure < 7; failure++) {
    for (const mode of ["digest", "length", "missing"]) {
      let reads = 0;
      await assertRejects(() =>
        materializeVideoCohort(f.input, id(900), json(f.receipt), {
          read() {
            const index = reads++, bytes = f.bytes[index].slice();
            if (index === failure) {
              if (mode === "missing") {
                return Promise.reject(new Error("unavailable"));
              }
              if (mode === "length") return Promise.resolve(bytes.subarray(1));
              bytes[bytes.length - 1] ^= 1;
            }
            return Promise.resolve(bytes);
          },
        }, new AbortController().signal)
      );
      assertEquals(reads, failure + 1);
    }
  }
});

Deno.test("video materialization snapshots caller metadata and stops after aborted reads", async () => {
  const f = await fixture(false),
    original = structuredClone(f.input),
    receipt = json(f.receipt);
  let reads = 0;
  const pending = materializeVideoCohort(f.input, id(900), receipt, {
    read() {
      return Promise.resolve(f.bytes[reads++]);
    },
  }, new AbortController().signal);
  f.input.input.evidence_manifest.provenance.source.sha256 = "0".repeat(64);
  receipt.fill(0);
  assertEquals(
    (await pending).receipt.items[0].sha256,
    original.input.evidence_manifest.provenance.source.sha256,
  );
  for (const during of [false, true]) {
    const controller = new AbortController();
    reads = 0;
    if (!during) controller.abort();
    await assertRejects(() =>
      materializeVideoCohort(original, id(900), json(f.receipt), {
        read() {
          reads++;
          controller.abort();
          return Promise.resolve(f.bytes[0]);
        },
      }, controller.signal)
    );
    assertEquals(reads, during ? 1 : 0);
  }
});
