import { assertEquals, assertNotEquals, assertThrows } from "@std/assert";
import {
  initialEvidenceArtifacts,
  initialEvidenceDigest,
  parseInitialEvidenceManifest,
} from "./initialEvidenceManifest.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const scan = id(1), generation = id(2);
function artifact(n: number, type = "image/jpeg") {
  return {
    media_id: id(n),
    content_type: type,
    byte_count: 100,
    sha256: "a".repeat(64),
  };
}
const photo = () => ({
  kind: "image",
  source: artifact(10),
  prepared: artifact(3),
  coordinate_basis: "prepared_image_top_left_v1",
  focus_region: {
    x: 0.1,
    y: 0.2,
    width: 0.3,
    height: 0.4,
    source: "user_selection",
  },
});

Deno.test("V8 retains full originals while V7 and provider bounds remain unchanged", async () => {
  const mib = 1024 * 1024;
  const a = photo(), b = photo();
  a.source.byte_count = 32 * mib;
  a.prepared.byte_count = 2.5 * mib;
  b.source = { ...artifact(11), byte_count: 32 * mib };
  b.prepared = { ...artifact(12), byte_count: 2.5 * mib };
  const value = { schema_version: 8, items: [a, b] };
  assertEquals(
    parseInitialEvidenceManifest(value, scan, generation).schema_version,
    8,
  );
  assertThrows(() =>
    parseInitialEvidenceManifest(
      { ...value, schema_version: 7 },
      scan,
      generation,
    )
  );
  for (
    const alter of [
      (v: typeof value) => {
        v.items[0].source.byte_count++;
      },
      (v: typeof value) => {
        v.items[0].prepared.byte_count++;
      },
      (v: typeof value) => {
        v.items.push({
          ...photo(),
          source: artifact(13),
          prepared: artifact(14),
        });
      },
    ]
  ) {
    const copy = structuredClone(value);
    alter(copy);
    assertThrows(() => parseInitialEvidenceManifest(copy, scan, generation));
  }
  const old = manifest();
  assertNotEquals(
    await initialEvidenceDigest(old, scan, generation),
    await initialEvidenceDigest(
      { ...old, schema_version: 8 },
      scan,
      generation,
    ),
  );
});

Deno.test("V8 independently bounds original cohort and mixed provider frames", () => {
  const mib = 1024 * 1024;
  const images = [1, 2, 3].map((n) => ({
    ...photo(),
    source: { ...artifact(30 + n), byte_count: 22 * mib },
    prepared: artifact(40 + n),
  }));
  assertThrows(() =>
    parseInitialEvidenceManifest(
      { schema_version: 8, items: images },
      scan,
      generation,
    )
  );
  const p = photo(), v = video();
  p.source.byte_count = 32 * mib;
  p.prepared.byte_count = 4 * mib;
  v.frames = [{ ...artifact(5), byte_count: mib }];
  v.source.byte_count = 12 * mib;
  v.playback.byte_count = 12 * mib;
  v.audio.source.byte_count = v.audio.prepared.byte_count = 2_700_000;
  const mixed = { schema_version: 8, items: [p, v] };
  assertEquals(
    parseInitialEvidenceManifest(mixed, scan, generation).items.length,
    2,
  );
  v.frames[0].byte_count++;
  assertThrows(() => parseInitialEvidenceManifest(mixed, scan, generation));
});
const video = () => ({
  kind: "video",
  source: artifact(20, "video/mp4"),
  playback: artifact(4, "video/mp4"),
  frames: [artifact(5), artifact(6)],
  audio: {
    source: artifact(7, "audio/wav"),
    prepared: artifact(8, "audio/wav"),
  },
});
const manifest = () => ({
  schema_version: 7,
  items: [
    photo(),
    { kind: "description", text: "  Synthetic 🦋 context.  " },
    video(),
  ],
});

Deno.test("initial evidence keeps owner nodes separate from exact provider/source roles", () => {
  const parsed = parseInitialEvidenceManifest(manifest(), scan, generation);
  assertEquals(parsed.items.map((x) => x.kind), [
    "image",
    "description",
    "video",
  ]);
  assertEquals(
    initialEvidenceArtifacts(parsed).map((
      { item_index, role, role_index },
    ) => [item_index, role, role_index]),
    [
      [0, "source_image", 0],
      [0, "prepared_image", 0],
      [2, "source_video", 0],
      [2, "playback_video", 0],
      [2, "inference_frame", 0],
      [2, "inference_frame", 1],
      [2, "source_companion_audio", 0],
      [2, "prepared_companion_audio", 0],
    ],
  );
  assertEquals(parsed.items[1], {
    kind: "description",
    text: "  Synthetic 🦋 context.  ",
  });
  assertEquals(Object.isFrozen(parsed.items), true);
});

Deno.test("initial evidence rejects invented recipes, crossed roles, duplicate IDs and invalid focus", () => {
  for (
    const alter of [
      (m: ReturnType<typeof manifest>) =>
        Object.assign(m.items[2], {
          preprocessing_version: "retained_clip_v1",
        }),
      (m: ReturnType<typeof manifest>) =>
        Object.assign(m.items[0], { coordinate_basis: "original_image" }),
      (m: ReturnType<typeof manifest>) =>
        Object.assign(m.items[0], {
          focus_region: {
            x: 0.9,
            y: 0,
            width: 0.2,
            height: 1,
            source: "user_selection",
          },
        }),
      (m: ReturnType<typeof manifest>) =>
        Object.assign(m.items[0], {
          focus_region: {
            x: NaN,
            y: 0,
            width: 1,
            height: 1,
            source: "user_selection",
          },
        }),
      (m: ReturnType<typeof manifest>) =>
        Object.assign(m.items[2], { playback: artifact(3, "video/mp4") }),
      (m: ReturnType<typeof manifest>) =>
        Object.assign(m.items[2], { frames: [artifact(5, "video/mp4")] }),
      (m: ReturnType<typeof manifest>) =>
        Object.assign(m.items[2], {
          audio: {
            source: artifact(7, "audio/wav"),
            prepared: artifact(7, "audio/wav"),
          },
        }),
      (m: ReturnType<typeof manifest>) =>
        Object.assign(m, { schema_version: 6 }),
    ]
  ) {
    const m = manifest();
    alter(m);
    assertThrows(() => parseInitialEvidenceManifest(m, scan, generation));
  }
  assertThrows(() =>
    parseInitialEvidenceManifest(
      { schema_version: 7, items: [{ kind: "description", text: "No media" }] },
      scan,
      generation,
    )
  );
  assertThrows(() => parseInitialEvidenceManifest(manifest(), scan, scan));
});

Deno.test("initial evidence digest binds bytes, order, generation, exact context and selection", async () => {
  const base = manifest(),
    expected = await initialEvidenceDigest(base, scan, generation);
  assertEquals(
    await initialEvidenceDigest(
      JSON.parse(JSON.stringify(base)),
      scan,
      generation,
    ),
    expected,
  );
  for (
    const alter of [
      (m: ReturnType<typeof manifest>) => m.items.reverse(),
      (m: ReturnType<typeof manifest>) =>
        Object.assign(m.items[1], { text: "Synthetic 🦋 context." }),
      (m: ReturnType<typeof manifest>) =>
        Object.assign(m.items[0], {
          prepared: { ...artifact(3), sha256: "b".repeat(64) },
        }),
      (m: ReturnType<typeof manifest>) =>
        Object.assign(m.items[0], {
          focus_region: { ...photo().focus_region, x: 0.11 },
        }),
      (m: ReturnType<typeof manifest>) =>
        Object.assign(m.items[0], {
          focus_region: {
            ...photo().focus_region,
            source: "vision_objectness",
          },
        }),
      (m: ReturnType<typeof manifest>) =>
        Object.assign(m.items[2], { frames: [artifact(6), artifact(5)] }),
    ]
  ) {
    const m = manifest();
    alter(m);
    assertNotEquals(await initialEvidenceDigest(m, scan, generation), expected);
  }
  assertNotEquals(await initialEvidenceDigest(base, scan, id(9)), expected);
  const zero = { ...photo(), focus_region: { ...photo().focus_region, x: 0 } };
  const negativeZero = {
    ...zero,
    focus_region: { ...zero.focus_region, x: -0 },
  };
  assertEquals(
    await initialEvidenceDigest(
      { schema_version: 7, items: [zero] },
      scan,
      generation,
    ),
    await initialEvidenceDigest(
      { schema_version: 7, items: [negativeZero] },
      scan,
      generation,
    ),
  );
});
