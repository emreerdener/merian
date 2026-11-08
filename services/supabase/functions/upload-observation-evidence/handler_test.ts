import { assertEquals } from "@std/assert";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";
import { type EvidenceReceipt } from "../_shared/analysisHistory/evidence.ts";
import {
  type UploadDependencies,
  uploadObservationEvidence,
} from "./handler.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const photos = [
  { media_id: id(4), content_type: "image/jpeg", byte_count: 3 },
  { media_id: id(5), content_type: "image/png", byte_count: 4 },
];
export function wire(
  metadata: unknown = {
    schema_version: 1,
    observation_id: id(2),
    analysis_id: id(3),
    photos,
  },
  payload = new Uint8Array([1, 2, 3, 4, 5, 6, 7]),
) {
  const header = new TextEncoder().encode(JSON.stringify(metadata));
  const bytes = new Uint8Array(4 + header.length + payload.length);
  new DataView(bytes.buffer).setUint32(0, header.length);
  bytes.set(header, 4);
  bytes.set(payload, 4 + header.length);
  return bytes;
}
function fixture() {
  const calls: string[] = [];
  let receipts: EvidenceReceipt[] = [];
  const deps: UploadDependencies = {
    reserve(input, signal) {
      signal.throwIfAborted();
      assertEquals(input.owner_id, id(1));
      calls.push("reserve");
      const deadline = new Date(Date.now() + 60_000).toISOString();
      receipts = input.items.map((item, i) => ({
        ...item,
        owner_id: input.owner_id,
        observation_id: input.observation_id,
        analysis_id: input.analysis_id,
        object_id: id(20 + i),
        expires_at: deadline,
        ready_at: null,
      }));
      return Promise.resolve(receipts);
    },
    write(receipt, bytes, signal) {
      signal.throwIfAborted();
      calls.push(`write:${receipt.media_id}`);
      assertEquals(
        bytes,
        receipt.media_id === id(4)
          ? new Uint8Array([1, 2, 3])
          : new Uint8Array([4, 5, 6, 7]),
      );
      return Promise.resolve();
    },
    complete(identity, object, signal) {
      signal.throwIfAborted();
      calls.push(`complete:${identity.media_id}`);
      return Promise.resolve({
        ...receipts.find((r) => r.object_id === object),
        ready_at: new Date().toISOString(),
      });
    },
  };
  return { deps, calls };
}
const req = () => new Request("https://example.invalid", { method: "POST" });
const run = (
  body: Uint8Array,
  deps: UploadDependencies,
  signal = new AbortController().signal,
) => uploadObservationEvidence(req(), body, id(1), deps, signal);
Deno.test("private upload reserves full actual-byte cohort before writes and exposes only V2 references", async () => {
  const { deps, calls } = fixture();
  const response = await run(wire(), deps);
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Cache-Control"), "private, no-store");
  const result = await response.json();
  assertEquals(Object.keys(result).sort(), [
    "analysis_id",
    "items",
    "observation_id",
    "schema_version",
  ]);
  assertEquals(
    result.items.map((item: Record<string, unknown>) =>
      Object.keys(item).sort()
    ),
    photos.map(
      () => ["byte_count", "content_type", "kind", "media_id", "sha256"],
    ),
  );
  assertEquals(
    result.items[0].sha256,
    "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
  );
  assertEquals(calls, [
    "reserve",
    `write:${id(4)}`,
    `complete:${id(4)}`,
    `write:${id(5)}`,
    `complete:${id(5)}`,
  ]);
});
Deno.test("private upload rejects malformed, duplicate, unsupported and mismatched complete bodies before reservation", async () => {
  for (
    const body of [
      new Uint8Array(),
      wire({}, new Uint8Array([1])),
      wire({
        schema_version: 1,
        observation_id: id(2),
        analysis_id: id(3),
        photos: [photos[0], photos[0]],
      }),
      wire({
        schema_version: 1,
        observation_id: id(2),
        analysis_id: id(3),
        photos: [{ ...photos[0], content_type: "image/heic" }, photos[1]],
      }),
      wire(undefined, new Uint8Array([1, 2])),
      wire(undefined, new Uint8Array(8)),
      wire({
        schema_version: 1,
        observation_id: id(2),
        analysis_id: id(3),
        photos,
        owner_id: id(9),
      }),
    ]
  ) {
    const { deps, calls } = fixture();
    const response = await run(body, deps);
    assertEquals(response.status, 400);
    await response.body?.cancel();
    assertEquals(calls, []);
  }
});
Deno.test("private upload validates every reservation before any object write", async () => {
  const { deps, calls } = fixture();
  const reserve = deps.reserve;
  deps.reserve = async (...args) => {
    const result = await reserve(...args) as EvidenceReceipt[];
    result[1].sha256 = "f".repeat(64);
    return result;
  };
  const response = await run(wire(), deps);
  assertEquals(response.status, 503);
  await response.body?.cancel();
  assertEquals(calls, ["reserve"]);
});
Deno.test("private upload lost-response ready replay rechecks deletion without replacing bytes", async () => {
  const { deps, calls } = fixture();
  const reserve = deps.reserve;
  deps.reserve = async (...args) =>
    (await reserve(...args) as EvidenceReceipt[]).map((r) => ({
      ...r,
      ready_at: new Date().toISOString(),
    }));
  const response = await run(wire(), deps);
  assertEquals(response.status, 200);
  await response.body?.cancel();
  assertEquals(calls, ["reserve", `complete:${id(4)}`, `complete:${id(5)}`]);
});
Deno.test("private upload deletion during storage prevents completion and further writes", async () => {
  const { deps, calls } = fixture();
  deps.complete = () => {
    throw new HistoryError("analysis_history_not_found");
  };
  const response = await run(wire(), deps);
  assertEquals(response.status, 404);
  await response.body?.cancel();
  assertEquals(calls, ["reserve", `write:${id(4)}`]);
});
Deno.test("private upload shared deadline regains control from stalled write without completing", async () => {
  const { deps, calls } = fixture();
  const controller = new AbortController();
  deps.write = () => {
    controller.abort();
    return new Promise(() => {});
  };
  const response = await run(wire(), deps, controller.signal);
  assertEquals(response.status, 503);
  await response.body?.cancel();
  assertEquals(calls, ["reserve"]);
});
