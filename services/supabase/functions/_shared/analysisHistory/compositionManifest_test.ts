import { assertEquals, assertNotEquals, assertThrows } from "@std/assert";
import { parseExecutableAnalysisInput } from "./analysisInput.ts";
import { parseCompositionAdmission } from "./compositionAdmission.ts";
import { compositionFingerprint } from "./compositionFingerprint.ts";
import { parseCompositionManifest } from "./compositionManifest.ts";
import { parsePreparedVideoManifest } from "./videoManifest.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const observation = id(1), child = id(2), source = id(3);
const vectors: {
  manifest: unknown;
  observation_id: string;
  analysis_id: string;
}[] = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/video-manifest-v4.json", import.meta.url),
  ),
);
const graph = parsePreparedVideoManifest(
  vectors[0].manifest,
  vectors[0].observation_id,
  vectors[0].analysis_id,
).provenance;
function artifact(n: number, audio = false) {
  return {
    media_id: id(n),
    content_type: audio ? "audio/wav" : "image/jpeg",
    byte_count: 100,
    sha256: "a".repeat(64),
  };
}
function photo(n = 10) {
  return { kind: "image", artifact: artifact(n) };
}
function audio(n = 20) {
  return { kind: "audio", artifact: artifact(n, true) };
}
function video(n = 100, withAudio = true) {
  return {
    kind: "video",
    provenance: {
      ...graph,
      source: { ...graph.source, media_id: id(n) },
      frames: graph.frames.map((frame, index) => ({
        ...frame,
        source_media_id: id(n),
        artifact: { ...frame.artifact, media_id: id(n + index + 1) },
      })),
      audio: withAudio && graph.audio
        ? {
          ...graph.audio,
          source_media_id: id(n),
          artifact: { ...graph.audio.artifact, media_id: id(n + 6) },
        }
        : null,
    },
  };
}
const note = (text = "submitted notes") => ({ kind: "description", text });
function manifest(items: unknown[]) {
  return { schema_version: 5, items };
}
function request(items: unknown[]) {
  return {
    schema_version: 5,
    observation_id: observation,
    analysis_id: child,
    source_analysis_id: source,
    request_digest: "b".repeat(64),
    evidence_manifest: manifest(items),
    entitlement_protocol: 3,
    identification_protocol: 7,
    history_protocol: 10,
    expected_processor_permission: "google_gemini",
  };
}
const parse = (items: unknown[]) =>
  parseCompositionManifest(manifest(items), observation, child, source);

Deno.test("V6 photo focus survives parsing but cannot enter V5 admission", async () => {
  const rows: { name: string; focus_region: unknown; valid: boolean }[] = JSON
    .parse(
      await Deno.readTextFile(
        new URL("./fixtures/composition-focus-v6.json", import.meta.url),
      ),
    );
  for (const row of rows) {
    const items = [{ ...photo(), focus_region: row.focus_region }, audio()];
    const value = { schema_version: 6, items };
    const decode = () =>
      parseCompositionManifest(value, observation, child, source);
    if (row.valid) {
      assertEquals<unknown>(decode(), value, row.name);
    } else assertThrows(decode, Error, undefined, row.name);
    assertThrows(() => parse(items));
    assertThrows(() =>
      parseCompositionAdmission({ ...request(items), evidence_manifest: value })
    );
    assertThrows(() =>
      parseCompositionManifest(
        {
          schema_version: 6,
          items: [{ ...audio(), focus_region: row.focus_region }],
        },
        observation,
        child,
        source,
      )
    );
  }
});

Deno.test("composition raw Unicode vectors agree across native and Edge JSON decoders", async () => {
  const rows: { valid: boolean; manifest_utf8: string }[] = JSON.parse(
    await Deno.readTextFile(
      new URL("./fixtures/composition-text-v5.json", import.meta.url),
    ),
  );
  for (const row of rows) {
    const decode = () =>
      parseCompositionManifest(
        JSON.parse(row.manifest_utf8),
        observation,
        child,
        source,
      );
    if (row.valid) {
      assertEquals(decode().items.at(-1), { kind: "description", text: "🦋" });
    } else assertThrows(decode);
  }
});

Deno.test("composition native/backend golden requests and fingerprints", async () => {
  const values: {
    valid: boolean;
    name: string;
    input: unknown;
    fingerprint?: string;
  }[] = JSON.parse(
    await Deno.readTextFile(
      new URL("./fixtures/composition-request-v5.json", import.meta.url),
    ),
  );
  assertEquals(values.length, 18);
  for (const value of values) {
    if (value.valid) {
      assertEquals(
        await compositionFingerprint(value.input),
        value.fingerprint,
        value.name,
      );
    } else {
      assertThrows(
        () => parseCompositionAdmission(value.input),
        Error,
        undefined,
        value.name,
      );
    }
  }
});

Deno.test("composition retains each supported physical shape and interleaved notes", () => {
  for (
    const nodes of [
      [photo()],
      [audio()],
      [video()],
      [photo(), photo(11)],
      [photo(), audio()],
      [photo(), video()],
      [audio(), video()],
      [audio(), audio(21)],
    ]
  ) {
    const items = [
      note("before"),
      nodes[0],
      note("between"),
      ...nodes.slice(1),
      note("after"),
    ];
    assertEquals<unknown>(parse(items).items, items);
    assertEquals<unknown>(
      parseCompositionAdmission(request(items)),
      request(items),
    );
  }
  assertEquals(parse([10, 11, 12, 13, 14].map(photo)).items.length, 5);
});

Deno.test("composition rejects empty/text-only, excess physical nodes and unknown fields", () => {
  for (
    const items of [
      [],
      [note()],
      [photo(), audio(), photo(11)],
      [10, 11, 12, 13, 14, 15].map(photo),
      [{ ...photo(), extra: true }],
      [{
        ...audio(),
        artifact: { ...artifact(20, true), url: "https://example.invalid" },
      }],
      [{
        kind: "audio",
        artifact: { ...artifact(20, true), content_type: "audio/mp4" },
      }],
      [photo(), note("\u0000")],
      [photo(), note("\uD800")],
      [
        photo(),
        note("a".repeat(8192)),
        note("a".repeat(8192)),
        note("a".repeat(8192)),
        note("a".repeat(8192)),
      ],
    ]
  ) assertThrows(() => parse(items));
});

Deno.test("composition rejects parent/source/child aliases and cross-node video artifact reuse", () => {
  for (const n of [1, 2, 3]) assertThrows(() => parse([photo(n)]));
  assertThrows(() => parse([photo(), photo()]));
  assertThrows(() => parse([audio(), audio()]));
  assertThrows(() => parse([video(), video()]));
  assertThrows(() => parse([video(), video(200)]));
  assertThrows(() => parse([photo(101), video()]));
  const clip = video();
  clip.provenance.frames[0].artifact.media_id = source;
  assertThrows(() => parse([clip]));
});

Deno.test("composition enforces shared byte budgets across different nodes", () => {
  const first = photo(), second = photo(11);
  first.artifact.byte_count = 5 * 1024 * 1024;
  assertThrows(() => parse([first, second]));
  assertThrows(() =>
    parse([{
      ...audio(),
      artifact: { ...artifact(20, true), byte_count: 2_700_001 },
    }])
  );
  const clip = video();
  clip.provenance.frames.forEach((frame) =>
    frame.artifact.byte_count = 1_048_576
  );
  assertThrows(() => parse([clip, photo()]));
});

Deno.test("composition owns immutable metadata and grants no legacy execution authority", () => {
  const clip = video(), image = photo();
  const result = parse([image, clip]);
  const before = structuredClone(result);
  image.artifact.sha256 = "c".repeat(64);
  clip.provenance.frames[0].actual_time_ticks++;
  assertEquals(result, before);
  const frozen = (value: unknown): void => {
    if (value && typeof value === "object") {
      assertEquals(Object.isFrozen(value), true);
      Object.values(value).forEach(frozen);
    }
  };
  frozen(result);
  assertThrows(() => parseExecutableAnalysisInput(request([photo(), audio()])));
  for (
    const change of [{ history_protocol: 9 }, { identification_protocol: 6 }, {
      source_analysis_id: null,
    }, { expected_processor_permission: "openai" }]
  ) {
    assertThrows(() =>
      parseCompositionAdmission({ ...request([photo(), audio()]), ...change })
    );
  }
});

Deno.test("composition fingerprint binds timeline, exact Unicode, video linkage and immutable input", async () => {
  const original = request([photo(), note("é"), audio()]);
  const hash = await compositionFingerprint(original);
  assertEquals(
    await compositionFingerprint(JSON.parse(JSON.stringify(original))),
    hash,
  );
  assertNotEquals(
    await compositionFingerprint(request([audio(), note("é"), photo()])),
    hash,
  );
  assertNotEquals(
    await compositionFingerprint(request([photo(), note("e\u0301"), audio()])),
    hash,
  );
  const clip = video();
  const before = await compositionFingerprint(request([clip]));
  clip.provenance.frames[0].actual_time_ticks++;
  assertNotEquals(await compositionFingerprint(request([clip])), before);
  const mutable = request([photo(), audio()]);
  const expected = await compositionFingerprint(mutable);
  const pending = compositionFingerprint(mutable);
  mutable.evidence_manifest.items.reverse();
  assertEquals(await pending, expected);
});
