import { assertEquals, assertThrows } from "@std/assert";
import { parsePreparedVideoProvenance } from "./videoProvenance.ts";
import { parsePreparedAudioManifest } from "./audioManifest.ts";
import { parseProtectedEvidenceManifest } from "./protectedManifest.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const artifact = (n: number, content_type: string) => ({
  media_id: id(n),
  content_type,
  byte_count: 100,
  sha256: "a".repeat(64),
});
function fixture() {
  return {
    schema_version: 1,
    preprocessing_version: "retained_clip_v1",
    source: artifact(3, "video/mp4"),
    parameters: {
      timescale: 600,
      frame_pipeline: "direct_inference_v1",
      decode_long_edge: 2048,
      duration_ticks: 3000,
      sampling: "five_interior_v1",
      preferred_track_transform: true,
      crop: "square_v1",
      crop_center_basis_points: 5000,
      inference_long_edge: 1024,
      encoding_quality_percent: 85,
    },
    frames: Array.from(
      { length: 5 },
      (_, index) => ({
        index,
        source_media_id: id(3),
        requested_time_ticks: 300 + index * 600,
        actual_time_ticks: 300 + index * 600,
        artifact: artifact(index + 4, "image/jpeg"),
      }),
    ),
    audio: {
      source_media_id: id(3),
      track: "first_audio_track",
      start_ticks: 0,
      end_ticks: 3000,
      sample_rate: 44100,
      sample_count: 220500,
      channels: 1,
      bits_per_sample: 16,
      encoding: "pcm_s16le",
      artifact: { ...artifact(9, "audio/wav"), byte_count: 441044 },
    },
  };
}
const parse = (value: unknown) =>
  parsePreparedVideoProvenance(value, id(1), id(2));
Deno.test("video provenance preserves ordered immutable outputs and exact JSON round trip", () => {
  const input = fixture(),
    expected = structuredClone(input),
    output = parse(input);
  input.frames.reverse();
  input.source.sha256 = "b".repeat(64);
  input.parameters.crop_center_basis_points = 0;
  assertEquals<unknown>(output, expected);
  assertEquals(parse(JSON.parse(JSON.stringify(output))), output);
  const frozen = (value: unknown): void => {
    if (value !== null && typeof value === "object") {
      assertEquals(Object.isFrozen(value), true);
      for (const child of Object.values(value)) frozen(child);
    }
  };
  frozen(output);
  assertEquals(parse({ ...fixture(), audio: null }).audio, null);
  for (const inference_long_edge of [768, 1024]) {
    const value = fixture();
    value.parameters.inference_long_edge = inference_long_edge;
    assertEquals(
      parse(value).parameters.inference_long_edge,
      inference_long_edge,
    );
  }
});
Deno.test("video provenance rejects forged links, duplicate identities and reordered samples", () => {
  const mutations: ((v: ReturnType<typeof fixture>) => void)[] = [
    (v) => {
      v.frames.reverse();
    },
    (v) => {
      v.frames.pop();
    },
    (v) => {
      v.frames.push(v.frames[0]);
    },
    (v) => {
      v.frames[1].artifact.media_id = v.frames[0].artifact.media_id;
    },
    (v) => {
      v.frames[1].artifact.media_id = v.source.media_id;
    },
    (v) => {
      v.audio.artifact.media_id = v.frames[0].artifact.media_id;
    },
    (v) => {
      v.source.media_id = id(1);
    },
    (v) => {
      v.frames[0].artifact.media_id = id(2);
    },
    (v) => {
      v.frames[0].source_media_id = id(99);
    },
    (v) => {
      v.audio.source_media_id = id(99);
    },
    (v) => {
      v.frames[0].index = 2;
    },
    (v) => {
      v.frames[0].requested_time_ticks++;
    },
    (v) => {
      v.frames[0].actual_time_ticks = 3000;
    },
    (v) => {
      v.frames[0].actual_time_ticks = -1;
    },
    (v) => {
      v.audio.end_ticks = 0;
    },
    (v) => {
      v.audio.start_ticks = 3000;
    },
  ];
  for (const mutate of mutations) {
    const v = fixture();
    mutate(v);
    assertThrows(() => parse(v));
  }
  assertThrows(() => parsePreparedVideoProvenance(fixture(), id(1), id(1)));
});
Deno.test("video provenance bounds every artifact and combined frame bytes", () => {
  for (const number of [0, -1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER]) {
    const v = fixture();
    v.source.byte_count = number;
    assertThrows(() => parse(v));
  }
  for (const path of ["source", "frame", "audio"]) {
    for (const sha256 of ["", "A".repeat(64), "a".repeat(63), "g".repeat(64)]) {
      const v = fixture(),
        item = path === "source"
          ? v.source
          : path === "frame"
          ? v.frames[0].artifact
          : v.audio.artifact;
      item.sha256 = sha256;
      assertThrows(() => parse(v));
    }
  }
  const v = fixture();
  v.source.byte_count = 12 * 1024 * 1024;
  v.audio.artifact.byte_count = 2700000;
  v.frames.forEach((f) => {
    f.artifact.byte_count = 1024 * 1024;
  });
  parse(v);
  v.frames[0].artifact.byte_count++;
  assertThrows(() => parse(v));
  for (const duration_ticks of [0, 59, 3001, 600.5]) {
    const v = fixture();
    v.parameters.duration_ticks = duration_ticks;
    assertThrows(() => parse(v));
  }
  const short = fixture();
  short.parameters.duration_ticks = 60;
  short.audio.end_ticks = 60;
  short.audio.sample_count = 4410;
  short.frames.forEach((f) => {
    f.requested_time_ticks = 30;
    f.actual_time_ticks = 30;
  });
  parse(short);
});
Deno.test("video provenance has closed version, parameter and authority boundaries", () => {
  for (
    const field of [
      "provider",
      "input_profile",
      "model",
      "url",
      "object_key",
      "path",
    ]
  ) {
    const v = fixture();
    assertThrows(() => parse({ ...v, [field]: "forbidden" }));
    assertThrows(() =>
      parse({ ...v, source: { ...v.source, [field]: "forbidden" } })
    );
    assertThrows(() =>
      parse({ ...v, parameters: { ...v.parameters, [field]: "forbidden" } })
    );
    assertThrows(() =>
      parse({
        ...v,
        frames: [
          { ...v.frames[0], [field]: "forbidden" },
          ...v.frames.slice(1),
        ],
      })
    );
    assertThrows(() =>
      parse({ ...v, audio: { ...v.audio, [field]: "forbidden" } })
    );
  }
  const v = fixture();
  for (
    const [key, value] of Object.entries({
      timescale: 1000,
      frame_pipeline: "legacy",
      decode_long_edge: 4096,
      sampling: "legacy",
      preferred_track_transform: false,
      crop: "none",
      crop_center_basis_points: 10001,
      inference_long_edge: 2048,
      encoding_quality_percent: 86,
    })
  ) {
    assertThrows(() =>
      parse({ ...v, parameters: { ...v.parameters, [key]: value } })
    );
  }
  for (
    const [key, value] of Object.entries({
      track: "second",
      sample_rate: 48000,
      channels: 2,
      bits_per_sample: 32,
      encoding: "float",
    })
  ) {
    assertThrows(() => parse({ ...v, audio: { ...v.audio, [key]: value } }));
  }
  assertThrows(() => parse({ ...v, schema_version: 2 }));
  assertThrows(() => parse({ ...v, preprocessing_version: "legacy" }));
  assertThrows(() =>
    parse({ ...v, source: { ...v.source, content_type: "video/quicktime" } })
  );
  assertThrows(() => parsePreparedAudioManifest(v, id(1), id(2)));
  assertThrows(() => parseProtectedEvidenceManifest(v));
});

Deno.test("video provenance records offset audio and nondecreasing actual frame times", () => {
  const v = fixture();
  v.audio.start_ticks = 600;
  v.audio.end_ticks = 1800;
  v.audio.sample_count = 88200;
  assertEquals(parse(v).audio?.sample_count, 88200);
  v.audio.sample_count = 220500;
  assertThrows(() => parse(v));
  const frames = fixture();
  frames.frames[4].actual_time_ticks = 0;
  assertThrows(() => parse(frames));
  frames.frames.forEach((f) => {
    f.actual_time_ticks = 1500;
  });
  parse(frames);
  const invalid = fixture();
  invalid.audio.artifact.byte_count = 46;
  assertThrows(() => parse(invalid));
});
