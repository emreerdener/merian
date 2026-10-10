import { assert, assertEquals, assertRejects } from "@std/assert";
import inputs from "./fixtures/video-source-fingerprint-v1.json" with {
  type: "json",
};
import vectors from "./fixtures/video-evidence-v2.json" with { type: "json" };
import {
  buildVideoEvidenceUploadRequest,
  decodeVideoEvidenceAllocation,
  decodeVideoEvidenceReceipt,
  decodeVideoEvidenceUploadRequest,
  VIDEO_EVIDENCE_READER,
  VIDEO_EVIDENCE_RECEIPT_MAX_BYTES,
  VIDEO_EVIDENCE_REQUEST_MAX_BYTES,
} from "./videoEvidence.ts";
const bytes = (v: unknown) => new TextEncoder().encode(JSON.stringify(v));
const owner = vectors[0].allocated.owner_id;
const candidate = (i = 0) => ({
  schema_version: 2,
  input: structuredClone(inputs[i].input),
  fingerprint_version: 1,
  fingerprint: inputs[i].sha256,
});
Deno.test("video upload whole-inventory fixed audio silent Unicode request and receipt vectors", async () => {
  assertEquals(VIDEO_EVIDENCE_READER, 12);
  for (const [i, v] of vectors.entries()) {
    const request = await buildVideoEvidenceUploadRequest(candidate(i));
    assertEquals<unknown>(request, v.request);
    assertEquals<unknown>(
      await decodeVideoEvidenceUploadRequest(bytes(v.request), candidate(i)),
      v.request,
    );
    for (const value of [v.allocated, v.ready]) {
      const result = await decodeVideoEvidenceReceipt(
        bytes(value),
        candidate(i),
        owner,
      );
      assertEquals<unknown>(result, value);
      assert(
        Object.isFrozen(result) && Object.isFrozen(result.items) &&
          result.items.every(Object.isFrozen),
      );
    }
    assertEquals<unknown>(
      await decodeVideoEvidenceReceipt(
        bytes(v.ready),
        candidate(i),
        owner,
        bytes(v.allocated),
      ),
      v.ready,
    );
    assertEquals<unknown>(
      await decodeVideoEvidenceReceipt(
        bytes(v.ready),
        candidate(i),
        owner,
        bytes(v.ready),
      ),
      v.ready,
    );
  }
});
Deno.test("video upload rejects every mismatched scope field and incomplete or reordered inventory", async () => {
  const v = vectors[0];
  for (const key of Object.keys(v.request)) {
    for (const target of [v.request, v.allocated]) {
      const changed: Record<string, unknown> = structuredClone(target);
      delete changed[key];
      if (target === v.request) {
        await assertRejects(() =>
          decodeVideoEvidenceUploadRequest(bytes(changed), candidate())
        );
      } else {await assertRejects(() =>
          decodeVideoEvidenceReceipt(bytes(changed), candidate(), owner)
        );}
      changed[key] = "wrong";
      if (target === v.request) {
        await assertRejects(() =>
          decodeVideoEvidenceUploadRequest(bytes(changed), candidate())
        );
      } else {await assertRejects(() =>
          decodeVideoEvidenceReceipt(bytes(changed), candidate(), owner)
        );}
    }
  }
  for (
    const items of [[], v.request.items.slice(1), [
      ...v.request.items,
      v.request.items[0],
    ], [...v.request.items].reverse()]
  ) {
    await assertRejects(() =>
      decodeVideoEvidenceUploadRequest(
        bytes({ ...v.request, items }),
        candidate(),
      )
    );
  }
  for (
    const items of [[], v.allocated.items.slice(1), [
      ...v.allocated.items,
      v.allocated.items[0],
    ], [...v.allocated.items].reverse()]
  ) {
    await assertRejects(() =>
      decodeVideoEvidenceReceipt(
        bytes({ ...v.allocated, items }),
        candidate(),
        owner,
      )
    );
  }
  await assertRejects(() =>
    decodeVideoEvidenceReceipt(bytes(v.allocated), candidate(1), owner)
  );
  await assertRejects(() =>
    decodeVideoEvidenceReceipt(
      bytes(v.allocated),
      candidate(),
      "00000000-0000-4000-8000-000000000091",
    )
  );
});
Deno.test("video upload binds every artifact field and rejects unknown keys", async () => {
  const v = vectors[0];
  for (let i = 0; i < v.request.items.length; i++) {
    for (const key of Object.keys(v.request.items[i])) {
      const request = structuredClone(v.request),
        receipt = structuredClone(v.allocated);
      const a = request.items[i] as Record<string, unknown>,
        b = receipt.items[i] as Record<string, unknown>;
      a[key] = b[key] = "wrong";
      await assertRejects(() =>
        decodeVideoEvidenceUploadRequest(bytes(request), candidate())
      );
      await assertRejects(() =>
        decodeVideoEvidenceReceipt(bytes(receipt), candidate(), owner)
      );
    }
  }
  await assertRejects(() =>
    decodeVideoEvidenceUploadRequest(
      bytes({ ...v.request, extra: true }),
      candidate(),
    )
  );
  await assertRejects(() =>
    decodeVideoEvidenceReceipt(
      bytes({ ...v.allocated, extra: true }),
      candidate(),
      owner,
    )
  );
  const changed = structuredClone(v.allocated);
  Object.assign(changed.items[0], { url: "https://example.invalid" });
  await assertRejects(() =>
    decodeVideoEvidenceReceipt(bytes(changed), candidate(), owner)
  );
});
Deno.test("video upload object IDs cannot alias any scope artifact or each other", async () => {
  const v = vectors[0];
  for (
    const id of [
      owner,
      v.request.observation_id,
      v.request.source_analysis_id,
      v.request.analysis_id,
      ...v.request.items.map((x) => x.media_id),
      v.allocated.items[1].object_id,
      "bad",
    ]
  ) {
    const changed = structuredClone(v.allocated);
    changed.items[0].object_id = id;
    await assertRejects(() =>
      decodeVideoEvidenceReceipt(bytes(changed), candidate(), owner)
    );
  }
});
Deno.test("video upload expiry and readiness are strict and completion cannot replace allocation", async () => {
  const v = vectors[0];
  for (
    const expires_at of [
      null,
      true,
      "2026-02-30T00:00:00.000Z",
      "0000-10-10T00:05:00.000Z",
      "2026-10-10",
      "2026-10-10T00:05:00+00:00",
    ]
  ) {
    await assertRejects(() =>
      decodeVideoEvidenceReceipt(
        bytes({ ...v.allocated, expires_at }),
        candidate(),
        owner,
      )
    );
  }
  for (
    const state of [
      "reserved",
      "complete",
      "retired_pre_execution",
      "ready",
      true,
    ]
  ) {
    await assertRejects(() =>
      decodeVideoEvidenceReceipt(
        bytes({ ...v.allocated, state }),
        candidate(),
        owner,
      )
    );
  }
  await assertRejects(() =>
    decodeVideoEvidenceReceipt(
      bytes({ ...v.ready, state: "allocated" }),
      candidate(),
      owner,
    )
  );
  for (
    const ready_at of [
      v.ready.expires_at,
      "2026-10-10T00:06:00.000Z",
      "0000-10-10T00:00:00.000Z",
      "bad",
      true,
    ]
  ) {
    const changed = structuredClone(v.ready);
    Object.assign(changed.items[0], { ready_at });
    await assertRejects(() =>
      decodeVideoEvidenceReceipt(bytes(changed), candidate(), owner)
    );
  }
  const partial = structuredClone(v.allocated);
  Object.assign(partial.items[0], { ready_at: v.ready.items[0].ready_at });
  await decodeVideoEvidenceReceipt(
    bytes(partial),
    candidate(),
    owner,
    bytes(v.allocated),
  );
  await decodeVideoEvidenceReceipt(
    bytes(v.ready),
    candidate(),
    owner,
    bytes(partial),
  );
  await assertRejects(() =>
    decodeVideoEvidenceReceipt(
      bytes(v.allocated),
      candidate(),
      owner,
      bytes(partial),
    )
  );
  const replaced = structuredClone(v.ready);
  replaced.items[0].object_id = "00000000-0000-4000-8000-000000000999";
  await assertRejects(() =>
    decodeVideoEvidenceReceipt(
      bytes(replaced),
      candidate(),
      owner,
      bytes(v.allocated),
    )
  );
  await assertRejects(() =>
    decodeVideoEvidenceReceipt(
      bytes({ ...v.ready, expires_at: "2026-10-10T00:06:00.000Z" }),
      candidate(),
      owner,
      bytes(v.allocated),
    )
  );
  const retimed = structuredClone(v.ready);
  retimed.items[0].ready_at = "2026-10-10T00:01:00.000Z";
  await assertRejects(() =>
    decodeVideoEvidenceReceipt(
      bytes(retimed),
      candidate(),
      owner,
      bytes(v.ready),
    )
  );
});
Deno.test("video upload bounds strict UTF8 and unsupported candidate versions fail closed", async () => {
  for (
    const bad of [
      new Uint8Array(),
      bytes([]),
      bytes(null),
      new Uint8Array([0xc3, 0x28]),
      new Uint8Array([0x7b, 0, 0x7d, 0]),
    ]
  ) {
    await assertRejects(() =>
      decodeVideoEvidenceUploadRequest(bad, candidate())
    );
    await assertRejects(() =>
      decodeVideoEvidenceReceipt(bad, candidate(), owner)
    );
  }
  await assertRejects(() =>
    decodeVideoEvidenceUploadRequest(
      new Uint8Array(VIDEO_EVIDENCE_REQUEST_MAX_BYTES + 1).fill(32),
      candidate(),
    )
  );
  await assertRejects(() =>
    decodeVideoEvidenceReceipt(
      new Uint8Array(VIDEO_EVIDENCE_RECEIPT_MAX_BYTES + 1).fill(32),
      candidate(),
      owner,
    )
  );
  for (const schema_version of [1, 3, true]) {
    await assertRejects(() =>
      buildVideoEvidenceUploadRequest({ ...candidate(), schema_version })
    );
  }
});
Deno.test("video upload snapshots all bytes and original candidate before asynchronous hashing", async () => {
  const c = candidate(),
    data = bytes(vectors[0].ready),
    prior = bytes(vectors[0].allocated);
  const promise = decodeVideoEvidenceReceipt(data, c, owner, prior);
  data.fill(0);
  prior.fill(0);
  c.input.evidence_manifest.provenance.frames.reverse();
  assertEquals<unknown>(await promise, vectors[0].ready);
});

Deno.test("video fresh allocation never accepts partially or completely ready snapshots", async () => {
  for (const [i, v] of vectors.entries()) {
    assertEquals<unknown>(
      await decodeVideoEvidenceAllocation(
        bytes(v.allocated),
        candidate(i),
        owner,
      ),
      v.allocated,
    );
    await assertRejects(() =>
      decodeVideoEvidenceAllocation(bytes(v.ready), candidate(i), owner)
    );
    const partial = structuredClone(v.allocated);
    Object.assign(partial.items[0], { ready_at: v.ready.items[0].ready_at });
    await assertRejects(() =>
      decodeVideoEvidenceAllocation(bytes(partial), candidate(i), owner)
    );
  }
});
