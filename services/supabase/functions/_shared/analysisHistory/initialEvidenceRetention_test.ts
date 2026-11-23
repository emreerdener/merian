import { assertEquals, assertRejects } from "@std/assert";
import { evidenceDigest } from "./evidence.ts";
import {
  initialEvidenceArtifacts,
  initialEvidenceDigest,
} from "./initialEvidenceManifest.ts";
import {
  type InitialRetentionRepository,
  initialRetentionRequest,
  type InitialRetentionStorage,
  retainInitialEvidence,
  retainInitialEvidenceFromSource,
} from "./initialEvidenceRetention.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
async function fixture() {
  const bytes = new Uint8Array([1, 2, 3]), hash = await evidenceDigest(bytes);
  const artifact = (n: number) => ({
    media_id: id(n),
    content_type: "image/jpeg",
    byte_count: bytes.length,
    sha256: hash,
  });
  const manifest = {
    schema_version: 7,
    items: [{
      kind: "image",
      source: artifact(3),
      prepared: artifact(4),
      coordinate_basis: "prepared_image_top_left_v1",
      focus_region: {
        x: 0.1,
        y: 0.2,
        width: 0.3,
        height: 0.4,
        source: "user_selection",
      },
    }],
  };
  const value = {
    schema_version: 1,
    scan_id: id(1),
    generation: id(2),
    evidence_digest: await initialEvidenceDigest(manifest, id(1), id(2)),
    evidence_manifest: manifest,
  };
  const request = await initialRetentionRequest(value), owner = id(9);
  const receipt = {
    schema_version: 1,
    owner_id: owner,
    scan_id: id(1),
    generation: id(2),
    evidence_digest: value.evidence_digest,
    items: initialEvidenceArtifacts(request.evidence_manifest).map((x, n) => ({
      ...x,
      object_id: id(100 + n),
      ready: false,
    })),
  };
  const events: string[] = [];
  const repository: InitialRetentionRepository = {
    reserve() {
      events.push("reserve");
      return Promise.resolve(structuredClone(receipt));
    },
    complete(_owner, _request, object) {
      events.push(`complete:${object}`);
      receipt.items.find((x) => x.object_id === object)!.ready = true;
      return Promise.resolve(structuredClone(receipt));
    },
  };
  const storage: InitialRetentionStorage = {
    writeOnce(item, input) {
      assertEquals(input, bytes);
      events.push(`write:${item.object_id}`);
      return Promise.resolve();
    },
    readVerified(item) {
      events.push(`read:${item.object_id}`);
      return Promise.resolve(bytes.slice());
    },
  };
  return {
    bytes,
    value,
    receipt,
    owner,
    events,
    repository,
    storage,
    buffers: new Map([[id(3), bytes.slice()], [id(4), bytes.slice()]]),
    signal: new AbortController(),
  };
}

Deno.test("initial retention allocates before writes and proves each readback before readiness", async () => {
  const f = await fixture();
  const retained = await retainInitialEvidence(
    f.owner,
    f.value,
    f.buffers,
    f.repository,
    f.storage,
    f.signal.signal,
  );
  assertEquals(retained.receipt.items.every((x) => x.ready), true);
  assertEquals(f.events, [
    "reserve",
    `write:${id(100)}`,
    `read:${id(100)}`,
    `complete:${id(100)}`,
    `write:${id(101)}`,
    `read:${id(101)}`,
    `complete:${id(101)}`,
  ]);
  f.events.length = 0;
  await retainInitialEvidence(
    f.owner,
    f.value,
    f.buffers,
    f.repository,
    f.storage,
    f.signal.signal,
  );
  assertEquals(f.events, ["reserve", `read:${id(100)}`, `read:${id(101)}`]);
});

Deno.test("source retention opens one qualified lease at a time and closes before readback", async () => {
  const f = await fixture();
  let live = 0;
  const source = {
    open(item: { media_id: string }) {
      assertEquals(live, 0);
      live++;
      f.events.push(`open:${item.media_id}`);
      return Promise.resolve({
        bytes: f.bytes.slice(),
        close() {
          live--;
          f.events.push(`close:${item.media_id}`);
          return Promise.resolve();
        },
      });
    },
  };
  const read = f.storage.readVerified;
  f.storage.readVerified = (item, signal) => {
    assertEquals(live, 0);
    return read(item, signal);
  };
  await retainInitialEvidenceFromSource(
    f.owner,
    f.value,
    source,
    f.repository,
    f.storage,
    f.signal.signal,
  );
  assertEquals(live, 0);
  assertEquals(f.events, [
    "reserve",
    `open:${id(3)}`,
    `write:${id(100)}`,
    `close:${id(3)}`,
    `read:${id(100)}`,
    `complete:${id(100)}`,
    `open:${id(4)}`,
    `write:${id(101)}`,
    `close:${id(4)}`,
    `read:${id(101)}`,
    `complete:${id(101)}`,
  ]);
  f.events.length = 0;
  source.open = () => {
    throw new Error("ready recovery must not open source");
  };
  await retainInitialEvidenceFromSource(
    f.owner,
    f.value,
    source,
    f.repository,
    f.storage,
    f.signal.signal,
  );
  assertEquals(f.events, ["reserve", `read:${id(100)}`, `read:${id(101)}`]);
});

Deno.test("source retention closes corrupt, oversized, failed and cancelled leases without completing", async (t) => {
  for (
    const failure of [
      "size",
      "hash",
      "write",
      "cancel-open",
      "cancel-write",
      "close",
    ] as const
  ) {
    await t.step(failure, async () => {
      const f = await fixture();
      let closed = 0, opened = 0;
      const source = {
        open() {
          opened++;
          if (failure === "cancel-open") f.signal.abort();
          return Promise.resolve({
            bytes: failure === "size"
              ? new Uint8Array(4)
              : failure === "hash"
              ? new Uint8Array([9, 2, 3])
              : f.bytes.slice(),
            close() {
              closed++;
              if (failure === "close") {
                throw new Error("lease release unavailable");
              }
              return Promise.resolve();
            },
          });
        },
      };
      f.storage.writeOnce = () => {
        if (failure === "write") throw new Error("write unavailable");
        if (failure === "cancel-write") f.signal.abort();
        return Promise.resolve();
      };
      await assertRejects(() =>
        retainInitialEvidenceFromSource(
          f.owner,
          f.value,
          source,
          f.repository,
          f.storage,
          f.signal.signal,
        )
      );
      assertEquals(opened, 1);
      assertEquals(closed, 1);
      assertEquals(f.events, ["reserve"]);
      assertEquals(f.receipt.items.every((x) => !x.ready), true);
    });
  }
});

Deno.test("source retention validates receipt before opening and resumes only unfinished artifacts", async () => {
  const f = await fixture();
  let opened = 0;
  const source = {
    open() {
      opened++;
      return Promise.resolve({
        bytes: f.bytes.slice(),
        close: () => Promise.resolve(),
      });
    },
  };
  f.receipt.items.reverse();
  await assertRejects(() =>
    retainInitialEvidenceFromSource(
      f.owner,
      f.value,
      source,
      f.repository,
      f.storage,
      f.signal.signal,
    )
  );
  assertEquals(opened, 0);
  f.receipt.items.reverse();
  f.receipt.items[0].ready = true;
  f.events.length = 0;
  await retainInitialEvidenceFromSource(
    f.owner,
    f.value,
    source,
    f.repository,
    f.storage,
    f.signal.signal,
  );
  assertEquals(opened, 1);
  assertEquals(f.events, [
    "reserve",
    `read:${id(100)}`,
    `write:${id(101)}`,
    `read:${id(101)}`,
    `complete:${id(101)}`,
  ]);
});

Deno.test("initial retention rejects changed input bytes before allocation and corrupt readback before completion", async () => {
  const f = await fixture();
  f.buffers.get(id(4))![0] = 9;
  await assertRejects(() =>
    retainInitialEvidence(
      f.owner,
      f.value,
      f.buffers,
      f.repository,
      f.storage,
      f.signal.signal,
    )
  );
  assertEquals(f.events, []);
  f.buffers.set(id(4), f.bytes.slice());
  f.storage.readVerified = () => Promise.resolve(new Uint8Array([9, 2, 3]));
  await assertRejects(() =>
    retainInitialEvidence(
      f.owner,
      f.value,
      f.buffers,
      f.repository,
      f.storage,
      f.signal.signal,
    )
  );
  assertEquals(f.events, ["reserve", `write:${id(100)}`]);
  assertEquals(f.receipt.items.every((x) => !x.ready), true);
});

Deno.test("initial retention rejects crossed receipts and never marks a cancelled write ready", async () => {
  const f = await fixture();
  f.receipt.items.reverse();
  await assertRejects(() =>
    retainInitialEvidence(
      f.owner,
      f.value,
      f.buffers,
      f.repository,
      f.storage,
      f.signal.signal,
    )
  );
  assertEquals(f.events, ["reserve"]);
  f.receipt.items.reverse();
  f.events.length = 0;
  f.storage.writeOnce = () => {
    f.signal.abort();
    return Promise.resolve();
  };
  await assertRejects(() =>
    retainInitialEvidence(
      f.owner,
      f.value,
      f.buffers,
      f.repository,
      f.storage,
      f.signal.signal,
    )
  );
  assertEquals(f.events, ["reserve"]);
  assertEquals(f.receipt.items.every((x) => !x.ready), true);
});

Deno.test("initial retention owns mutable inputs before awaiting and rejects object replacement", async () => {
  const f = await fixture();
  const pending = retainInitialEvidence(
    f.owner,
    f.value,
    f.buffers,
    f.repository,
    f.storage,
    f.signal.signal,
  );
  f.buffers.get(id(4))![0] = 99;
  f.value.evidence_manifest.items[0].focus_region.x = 0.5;
  await pending;
  const g = await fixture();
  g.repository.complete = (_owner, _request, object) => {
    const item = g.receipt.items.find((x) => x.object_id === object)!;
    item.ready = true;
    item.object_id = id(200);
    return Promise.resolve(g.receipt);
  };
  await assertRejects(() =>
    retainInitialEvidence(
      g.owner,
      g.value,
      g.buffers,
      g.repository,
      g.storage,
      g.signal.signal,
    )
  );
  assertEquals(g.events, ["reserve", `write:${id(100)}`, `read:${id(100)}`]);
});
