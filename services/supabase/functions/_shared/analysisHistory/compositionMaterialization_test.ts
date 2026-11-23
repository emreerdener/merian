import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  compositionCohortItems,
  matchCompositionCohortItems,
} from "./compositionCohort.ts";
import { decodeCompositionEvidenceReceipt } from "./compositionEvidence.ts";
import { materializeCompositionAnalysis } from "./compositionMaterialization.ts";
import { compositionByteFixture as fixture } from "./compositionByteTestFixtures.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const json = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value));

Deno.test("composition cohort retains timeline position and video artifact roles", async () => {
  const f = await fixture();
  const items = compositionCohortItems(f.input);
  assertEquals(
    items.map((item) => [item.node_index, item.role, item.frame_index]),
    [
      [1, "audio", null],
      [3, "video_source", null],
      ...[0, 1, 2, 3, 4].map((index) => [3, "video_frame", index]),
      [3, "video_audio", null],
    ],
  );
  assertEquals(matchCompositionCohortItems(items, f.input), items);
  assertThrows(() =>
    matchCompositionCohortItems([...items].reverse(), f.input)
  );
  assertThrows(() => matchCompositionCohortItems(items.slice(1), f.input));
});

Deno.test("composition receipts reject cross-owner, reordered, partial and mutated allocations", async () => {
  const f = await fixture();
  const decode = (
    value: unknown,
    owner = f.receipt.owner_id,
    prior?: Uint8Array,
  ) => decodeCompositionEvidenceReceipt(json(value), f.input, owner, prior);
  assertEquals((await decode(f.receipt)).items.length, 8);
  await assertRejects(() => decode(f.receipt, id(9999)));
  for (
    const mutate of [
      (r: typeof f.receipt) => {
        r.fingerprint = "b".repeat(64);
      },
      (r: typeof f.receipt) => {
        r.items.reverse();
      },
      (r: typeof f.receipt) => {
        r.items.pop();
      },
      (r: typeof f.receipt) => {
        r.items[0].object_id = r.items[1].object_id;
      },
      (r: typeof f.receipt) => {
        r.items[0].object_id = r.source_analysis_id;
      },
      (r: typeof f.receipt) => {
        r.items[0].ready_at = null;
      },
      (r: typeof f.receipt) => {
        r.items[0].ready_at = r.expires_at;
      },
    ]
  ) {
    const changed = structuredClone(f.receipt);
    mutate(changed);
    await assertRejects(() => decode(changed));
  }
  const allocated = structuredClone(f.receipt);
  allocated.state = "allocated";
  allocated.items.forEach((item) => {
    item.ready_at = null;
  });
  await decode(f.receipt, f.receipt.owner_id, json(allocated));
  await assertRejects(() =>
    decode(allocated, f.receipt.owner_id, json(f.receipt))
  );
  const replaced = structuredClone(f.receipt);
  replaced.items[0].object_id = id(8888);
  await assertRejects(() =>
    decode(replaced, f.receipt.owner_id, json(allocated))
  );
});

Deno.test("composition materialization preserves audio/video/notes order and keeps source private", async () => {
  const f = await fixture();
  const reads: string[] = [];
  const request = await materializeCompositionAnalysis(
    f.input,
    f.receipt.owner_id,
    json(f.receipt),
    {
      read: (item, options) => {
        assertEquals(options.maximumBytes, item.byte_count);
        reads.push(item.media_id);
        return Promise.resolve(f.bytes.get(item.media_id)!);
      },
    },
    new AbortController().signal,
  );
  assertEquals(reads, f.receipt.items.map((item) => item.media_id));
  assertEquals(request.evidence.map((e) => e.kind), [
    "text",
    "audio",
    "text",
    "image",
    "image",
    "image",
    "image",
    "image",
    "audio",
    "text",
  ]);
  assertEquals(
    request.evidence.map((e) => e.order),
    request.evidence.map((_, i) => i),
  );
  assertEquals(
    request.evidence.filter((e) => e.kind === "audio").map((
      e,
    ) => [e.inputIndex, e.lineage]),
    [[0, null], [1, { kind: "video_audio", clipIndex: 0 }]],
  );
  assertEquals(request.capture, {
    hasVideo: true,
    videoClipCount: 1,
    declaredVideoFrameCount: 5,
    videoInferenceFrameCount: 5,
  });
  assertEquals(request.evidence[0], {
    kind: "text",
    source: "observation_context",
    order: 0,
    text: "  before 🦋  ",
  });
});

Deno.test("composition photo/audio and cancellation never return partial evidence", async () => {
  const f = await fixture(false);
  const read = (item: { media_id: string }) =>
    Promise.resolve(f.bytes.get(item.media_id)!);
  const result = await materializeCompositionAnalysis(
    f.input,
    f.receipt.owner_id,
    json(f.receipt),
    { read },
    new AbortController().signal,
  );
  assertEquals(result.evidence.map((e) => e.kind), [
    "text",
    "audio",
    "text",
    "image",
    "text",
  ]);
  assertEquals(result.capture.hasVideo, false);
  for (const fault of ["size", "hash", "abort", "read"] as const) {
    const controller = new AbortController();
    let count = 0;
    await assertRejects(() =>
      materializeCompositionAnalysis(
        f.input,
        f.receipt.owner_id,
        json(f.receipt),
        {
          read: async (item) => {
            count++;
            if (count === 1) return read(item);
            if (fault === "read") throw new Error("synthetic_read_failure");
            if (fault === "abort") controller.abort();
            const bytes = (await read(item)).slice();
            if (fault === "size") return bytes.subarray(1);
            if (fault === "hash") bytes[0] ^= 1;
            return bytes;
          },
        },
        controller.signal,
      )
    );
    assertEquals(count, 2);
  }
  const allocated = structuredClone(f.receipt);
  allocated.state = "allocated";
  allocated.items[0].ready_at = null;
  let reads = 0;
  await assertRejects(() =>
    materializeCompositionAnalysis(
      f.input,
      f.receipt.owner_id,
      json(allocated),
      {
        read: () => {
          reads++;
          return Promise.resolve(new Uint8Array());
        },
      },
      new AbortController().signal,
    )
  );
  assertEquals(reads, 0);
});
