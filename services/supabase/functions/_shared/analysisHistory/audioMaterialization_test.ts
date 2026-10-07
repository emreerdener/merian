import { parseHistoryPage } from "./page.ts";
import { parseHistoryState } from "./state.ts";
import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { materializeAudioAnalysis } from "./audioMaterialization.ts";
import { evidenceDigest } from "./evidence.ts";
import { decodeAnalysisResultSnapshot } from "./result.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
function wav() {
  const bytes = new Uint8Array(46), view = new DataView(bytes.buffer);
  for (
    const [offset, tag] of [[0, "RIFF"], [8, "WAVE"], [12, "fmt "], [
      36,
      "data",
    ]] as const
  ) bytes.set(new TextEncoder().encode(tag), offset);
  for (
    const [offset, value] of [[4, 38], [16, 16], [24, 44100], [28, 88200], [
      40,
      2,
    ]]
  ) view.setUint32(offset, value, true);
  for (const [offset, value] of [[20, 1], [22, 1], [32, 2], [34, 16]]) {
    view.setUint16(offset, value, true);
  }
  return bytes;
}

async function fixture() {
  const bytes = wav();
  const audio = {
    kind: "audio",
    media_id: id(4),
    content_type: "audio/wav",
    byte_count: bytes.length,
    sha256: await evidenceDigest(bytes),
  };
  const input = {
    schema_version: 3,
    observation_id: id(2),
    analysis_id: id(3),
    source_analysis_id: null,
    request_digest: "a".repeat(64),
    evidence_manifest: {
      schema_version: 3,
      items: [{ kind: "description", text: "Before" }, audio, {
        kind: "description",
        text: "After",
      }],
    },
    entitlement_protocol: 3,
    identification_protocol: 6,
    history_protocol: 9,
    expected_processor_permission: "google_gemini",
  };
  const receipt = {
    owner_id: id(1),
    observation_id: id(2),
    analysis_id: id(3),
    media_id: id(4),
    object_id: id(5),
    content_type: "audio/wav",
    byte_count: bytes.length,
    sha256: audio.sha256,
    expires_at: "2026-01-01T00:00:00.000Z",
    ready_at: "2025-12-31T00:00:00.000Z",
  };
  return { input, receipt, bytes };
}
Deno.test("audio materialization preserves exact order and admitted expired receipt without successor", async () => {
  const f = await fixture();
  let reads = 0;
  const evidence = await materializeAudioAnalysis(f.input, id(1), [f.receipt], {
    readVerified(receipt) {
      reads++;
      assertEquals(receipt, f.receipt);
      return Promise.resolve(f.bytes);
    },
  });
  assertEquals(reads, 1);
  assertEquals(evidence.map((e) => e.kind), ["text", "audio", "text"]);
  assertEquals(evidence.map((e) => e.order), [0, 1, 2]);
  assertEquals(
    evidence[1].kind === "audio" && evidence[1].mimeType,
    "audio/wav",
  );
  assertEquals(evidence[1].kind === "audio" && evidence[1].inputIndex, 0);
});
Deno.test("audio materialization rejects receipt scope, readiness and manifest changes before reading", async () => {
  const f = await fixture();
  let reads = 0;
  const storage = {
    readVerified() {
      reads++;
      return Promise.resolve(f.bytes);
    },
  };
  for (
    const change of [
      { owner_id: id(9) },
      { observation_id: id(9) },
      { analysis_id: id(9) },
      { media_id: id(9) },
      { ready_at: null },
      { content_type: "image/jpeg" },
      { byte_count: 48 },
      { sha256: "b".repeat(64) },
      { extra: true },
    ]
  ) {
    await assertRejects(() =>
      materializeAudioAnalysis(
        f.input,
        id(1),
        [{ ...f.receipt, ...change }],
        storage,
      )
    );
  }
  for (const receipts of [[], [f.receipt, f.receipt], null]) {
    await assertRejects(() =>
      materializeAudioAnalysis(f.input, id(1), receipts, storage)
    );
  }
  assertEquals(reads, 0);
});
Deno.test("audio materialization rechecks container length and digest after private read", async () => {
  const f = await fixture();
  const changed = f.bytes.slice();
  changed[44] = 1;
  const malformed = f.bytes.slice();
  malformed[0] = 0;
  for (const bytes of [changed, malformed, f.bytes.slice(0, 44)]) {
    await assertRejects(() =>
      materializeAudioAnalysis(f.input, id(1), [f.receipt], {
        readVerified() {
          return Promise.resolve(bytes);
        },
      })
    );
  }
  await assertRejects(() =>
    materializeAudioAnalysis(f.input, id(1), [f.receipt], {
      readVerified() {
        return Promise.reject(new Error("unavailable"));
      },
    })
  );
});
Deno.test("reader10 distinguishes audio result4 from imported result3 and preserves older snapshots", async () => {
  const f = await fixture();
  const page = JSON.parse(
    await Deno.readTextFile(
      new URL("./fixtures/page-v1.json", import.meta.url),
    ),
  );
  const original = JSON.parse(page.items[0].snapshot);
  const audio = {
    ...original,
    schema_version: 4,
    evidence_manifest: f.input.evidence_manifest,
  };
  // Use the result fixture's immutable observation/analysis; media remains distinct.
  const bytes = JSON.stringify(audio);
  assertEquals(decodeAnalysisResultSnapshot(bytes, 10).schema_version, 4);
  for (const reader of [7, 8, 9] as const) {
    assertThrows(() => decodeAnalysisResultSnapshot(bytes, reader));
  }
  assertThrows(() =>
    decodeAnalysisResultSnapshot(
      JSON.stringify({ ...audio, schema_version: 3 }),
      10,
    )
  );
  assertThrows(() =>
    decodeAnalysisResultSnapshot(
      JSON.stringify({ ...audio, source_analysis_id: id(4) }),
      10,
    )
  );
  assertEquals(
    decodeAnalysisResultSnapshot(page.items[0].snapshot, 10),
    decodeAnalysisResultSnapshot(page.items[0].snapshot, 9),
  );
});

Deno.test("reader10 page and target state keep audio and imported authority separate", async () => {
  const f = await fixture();
  const page = JSON.parse(
    await Deno.readTextFile(
      new URL("./fixtures/page-v1.json", import.meta.url),
    ),
  );
  const state = JSON.parse(
    await Deno.readTextFile(
      new URL("./fixtures/state-v1.json", import.meta.url),
    ),
  );
  const original = JSON.parse(page.items[0].snapshot);
  const audio = {
    ...original,
    schema_version: 4,
    analysis_id: id(70),
    ordinal: 2,
    source_analysis_id: original.analysis_id,
    evidence_manifest: f.input.evidence_manifest,
  };
  page.items.unshift({ ordinal: 2, snapshot: JSON.stringify(audio) });
  const request = {
    schema_version: 1 as const,
    observation_id: page.observation_id,
    before_ordinal: null,
    limit: 10,
  };
  assertEquals(
    parseHistoryPage(page, request, page.owner_id, 10).items.length,
    2,
  );
  assertThrows(() => parseHistoryPage(page, request, page.owner_id, 9));
  // Retain the actual imported V3 sentinel alongside audio, not a relabeled V1.
  page.items[1].snapshot = state.analysis.snapshot;
  assertEquals(
    parseHistoryPage(page, request, page.owner_id, 10).items.length,
    2,
  );
  assertThrows(() => parseHistoryPage(page, request, page.owner_id, 9));
  assertEquals(
    parseHistoryState(
      state,
      {
        schema_version: 1,
        observation_id: page.observation_id,
        analysis_id: original.analysis_id,
      },
      state.owner_id,
      10,
    ).analysis?.snapshot,
    state.analysis.snapshot,
  );
  state.analysis.snapshot = JSON.stringify(audio);
  const target = {
    schema_version: 1 as const,
    observation_id: page.observation_id,
    analysis_id: id(70),
  };
  assertEquals(
    parseHistoryState(state, target, state.owner_id, 10).selected_analysis_id,
    original.analysis_id,
  );
  assertThrows(() => parseHistoryState(state, target, state.owner_id, 9));
});
