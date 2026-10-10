import { assertEquals, assertRejects } from "@std/assert";
import {
  evidenceDigest,
  type EvidenceReceipt,
  parseEvidenceReceipt,
} from "../_shared/analysisHistory/evidence.ts";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";
import {
  type AudioUploadDependencies,
  uploadObservationAudio,
} from "./handler.ts";
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
const metadata = () => ({
  schema_version: 1,
  observation_id: id(2),
  analysis_id: id(3),
  audio: { media_id: id(4), content_type: "audio/wav", byte_count: 46 },
});
function wire(row: unknown = metadata(), audio = wav()) {
  const header = new TextEncoder().encode(JSON.stringify(row));
  const bytes = new Uint8Array(4 + header.length + audio.length);
  new DataView(bytes.buffer).setUint32(0, header.length);
  bytes.set(header, 4);
  bytes.set(audio, 4 + header.length);
  return bytes;
}
function fixture() {
  const calls: string[] = [];
  let saved: EvidenceReceipt | undefined;
  const deps: AudioUploadDependencies = {
    reserve(input) {
      calls.push("reserve");
      saved ??= {
        ...input,
        object_id: id(9),
        expires_at: new Date(Date.now() + 60000).toISOString(),
        ready_at: null,
      };
      return Promise.resolve(saved);
    },
    write(receipt, bytes) {
      calls.push("write");
      assertEquals(bytes, wav());
      assertEquals(receipt.byte_count, 46);
      return Promise.resolve();
    },
    complete(identity, object) {
      calls.push("complete");
      assertEquals(identity.owner_id, id(1));
      assertEquals(object, id(9));
      saved = {
        ...saved!,
        ready_at: saved!.ready_at ?? new Date().toISOString(),
      };
      return Promise.resolve(saved);
    },
  };
  return { deps, calls };
}
const run = (
  body: Uint8Array,
  deps: AudioUploadDependencies,
  signal = new AbortController().signal,
) =>
  uploadObservationAudio(
    new Request("https://example.invalid", { method: "POST" }),
    body,
    id(1),
    deps,
    signal,
  );
Deno.test("audio upload verifies bytes and returns only exact descriptors; ready replay rechecks completion", async () => {
  const f = fixture();
  const response = await run(wire(), f.deps);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    schema_version: 1,
    observation_id: id(2),
    analysis_id: id(3),
    items: [{
      kind: "audio",
      media_id: id(4),
      content_type: "audio/wav",
      byte_count: 46,
      sha256: await evidenceDigest(wav()),
    }],
  });
  assertEquals(response.headers.get("Cache-Control"), "private, no-store");
  const replay = await run(wire(), f.deps);
  assertEquals(replay.status, 200);
  await replay.body?.cancel();
  assertEquals(f.calls, [
    "reserve",
    "write",
    "complete",
    "reserve",
    "complete",
  ]);
});
Deno.test("audio upload rejects malformed metadata and containers before reservation", async () => {
  const row = metadata();
  const corrupt = wav();
  corrupt[4] = 0;
  for (
    const body of [
      wire({ ...row, owner_id: id(1) }),
      wire({ ...row, schema_version: 2 }),
      wire({ ...row, analysis_id: id(2) }),
      wire({ ...row, audio: { ...row.audio, sha256: "a".repeat(64) } }),
      wire({ ...row, audio: { ...row.audio, content_type: "audio/mp4" } }),
      wire({ ...row, audio: { ...row.audio, byte_count: 45 } }),
      wire(row, corrupt),
      wire(row, new Uint8Array(47)),
      new Uint8Array([0, 0, 0, 1, 255, 0]),
    ]
  ) {
    const f = fixture();
    const r = await run(body, f.deps);
    assertEquals(r.status, 400);
    await r.body?.cancel();
    assertEquals(f.calls, []);
  }
});
Deno.test("audio reservation validates full identity, bytes, expiry and closed receipt before storage", async () => {
  for (
    const change of [
      { owner_id: id(7) },
      { object_id: id(2) },
      { content_type: "image/jpeg" },
      { sha256: "b".repeat(64) },
      { byte_count: 48 },
      { expires_at: new Date(0).toISOString() },
      { extra: true },
    ]
  ) {
    const f = fixture(), reserve = f.deps.reserve;
    f.deps.reserve = async (input, signal) => ({
      ...await reserve(input, signal) as EvidenceReceipt,
      ...change,
    });
    const r = await run(wire(), f.deps);
    assertEquals(r.status, 503);
    await r.body?.cancel();
    assertEquals(f.calls, ["reserve"]);
  }
});
Deno.test("audio completion cannot change object expiry or readiness and never retries ambiguous writes", async () => {
  for (
    const change of [{ object_id: id(8) }, {
      expires_at: new Date(0).toISOString(),
    }, { ready_at: null }]
  ) {
    const f = fixture(), complete = f.deps.complete;
    f.deps.complete = async (...args) => ({
      ...await complete(...args) as EvidenceReceipt,
      ...change,
    });
    const r = await run(wire(), f.deps);
    assertEquals(r.status, 503);
    await r.body?.cancel();
    assertEquals(f.calls, ["reserve", "write", "complete"]);
  }
  for (const phase of ["reserve", "write", "complete"] as const) {
    const f = fixture();
    f.deps[phase] = () => {
      f.calls.push(phase);
      throw new Error("unknown");
    };
    const r = await run(wire(), f.deps);
    assertEquals(r.status, 503);
    await r.body?.cancel();
    assertEquals(f.calls.filter((x) => x === phase).length, 1);
  }
});
Deno.test("audio upload owns caller bytes across awaits and abort prevents subsequent work", async () => {
  const f = fixture(), body = wire(), reserve = f.deps.reserve;
  f.deps.reserve = (...args) => {
    body.fill(0);
    return reserve(...args);
  };
  const r = await run(body, f.deps);
  assertEquals(r.status, 200);
  await r.body?.cancel();
  const g = fixture(),
    controller = new AbortController(),
    original = g.deps.reserve;
  g.deps.reserve = async (...args) => {
    const value = await original(...args);
    controller.abort();
    return value;
  };
  const aborted = await run(wire(), g.deps, controller.signal);
  assertEquals(aborted.status, 503);
  await aborted.body?.cancel();
  assertEquals(g.calls, ["reserve"]);
});
Deno.test("audio error mapping retains exact conflict/deletion without leaking private details", async () => {
  for (
    const [code, status] of [["analysis_history_not_found", 404], [
      "analysis_history_operation_conflict",
      409,
    ], ["analysis_history_evidence_unavailable", 503]] as const
  ) {
    const f = fixture();
    f.deps.reserve = () => {
      throw new HistoryError(code);
    };
    const r = await run(wire(), f.deps);
    assertEquals(r.status, status);
    assertEquals((await r.json()).code, code);
  }
});
Deno.test("legacy evidence parser still refuses WAV receipts", async () => {
  const input = {
    owner_id: id(1),
    observation_id: id(2),
    analysis_id: id(3),
    media_id: id(4),
    content_type: "audio/wav",
    byte_count: 46,
    sha256: await evidenceDigest(wav()),
  };
  await assertRejects(() =>
    Promise.resolve().then(() =>
      parseEvidenceReceipt(
        {
          ...input,
          object_id: id(9),
          expires_at: new Date(Date.now() + 60000).toISOString(),
          ready_at: null,
        },
        input,
        input,
      )
    )
  );
});

Deno.test("audio storage aborts before the final bounded completion-attempt window", async () => {
  for (const remaining of [1000, 12040]) {
    const f = fixture(), reserve = f.deps.reserve;
    f.deps.reserve = async (input, signal) => ({
      ...await reserve(input, signal) as EvidenceReceipt,
      expires_at: new Date(Date.now() + remaining).toISOString(),
    });
    let writes = 0;
    f.deps.write = async (_receipt, _bytes, signal) => {
      writes++;
      await new Promise<void>((resolve) => {
        if (signal.aborted) resolve();
        else signal.addEventListener("abort", () => resolve(), { once: true });
      });
      signal.throwIfAborted();
    };
    const response = await run(wire(), f.deps);
    assertEquals(response.status, 503);
    await response.body?.cancel();
    assertEquals(writes, remaining < 12000 ? 0 : 1);
    assertEquals(f.calls, ["reserve"]);
  }
});
