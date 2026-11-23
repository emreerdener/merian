import { assertEquals } from "@std/assert";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";
import {
  INITIAL_UPLOAD_METADATA_MAX_BYTES,
  uploadInitialEvidence,
} from "./handler.ts";
import { fixture, frame, id } from "./testFixtures.ts";
const req = () => new Request("https://example.invalid", { method: "POST" });

Deno.test("ordinary binary upload verifies one artifact before readiness and exact ready replay", async () => {
  for (const version of [7, 8]) {
    const f = await fixture(3, version), signal = new AbortController().signal;
    const response = await uploadInitialEvidence(
      req(),
      frame(f.metadata, f.source),
      f.owner,
      f.dependencies,
      signal,
    );
    assertEquals(response.status, 200);
    assertEquals(await response.json(), f.receipt);
    assertEquals(response.headers.get("cache-control"), "private, no-store");
    assertEquals(f.events, ["reserve", "write", "read", "complete"]);
    assertEquals(f.receipt.items.map((x) => x.ready), [true, false]);
    f.events.length = 0;
    const replay = await uploadInitialEvidence(
      req(),
      frame(f.metadata, f.source),
      f.owner,
      f.dependencies,
      signal,
    );
    assertEquals(replay.status, 200);
    await replay.body?.cancel();
    assertEquals(f.events, ["reserve", "read"]);
  }
});

Deno.test("ordinary binary upload rejects framing identity hash and open metadata before allocation", async () => {
  const f = await fixture();
  const badLength = frame(f.metadata, f.source);
  new DataView(badLength.buffer).setUint32(
    0,
    INITIAL_UPLOAD_METADATA_MAX_BYTES + 1,
  );
  for (
    const bytes of [
      new Uint8Array(),
      badLength,
      new Uint8Array([0, 0, 0, 1, 255, 1]),
      frame({ ...f.metadata, owner_id: f.owner }, f.source),
      frame({ ...f.metadata, object_id: id(100) }, f.source),
      frame({ ...f.metadata, schema_version: 2 }, f.source),
      frame({ ...f.metadata, media_id: id(99) }, f.source),
      frame(f.metadata, f.source.slice(1)),
      frame(f.metadata, new Uint8Array([9, 9, 9])),
      frame({
        ...f.metadata,
        request: { ...f.request, evidence_digest: "0".repeat(64) },
      }, f.source),
    ]
  ) {
    const response = await uploadInitialEvidence(
      req(),
      bytes,
      f.owner,
      f.dependencies,
      new AbortController().signal,
    );
    assertEquals(response.status, 400);
    await response.body?.cancel();
  }
  assertEquals(f.events, []);
});

Deno.test("ordinary binary upload accepts V8 source over provider bound without enlarging prepared role", async () => {
  const f = await fixture(5_242_881);
  const response = await uploadInitialEvidence(
    req(),
    frame(f.metadata, f.source),
    f.owner,
    f.dependencies,
    new AbortController().signal,
  );
  assertEquals(response.status, 200);
  await response.body?.cancel();
  f.events.length = 0;
  const denied = await uploadInitialEvidence(
    req(),
    frame({ ...f.metadata, media_id: id(4) }, f.source),
    f.owner,
    f.dependencies,
    new AbortController().signal,
  );
  assertEquals(denied.status, 400);
  await denied.body?.cancel();
  assertEquals(f.events, []);
});

Deno.test("ordinary upload keeps failure and cancellation held and never acknowledges changed readback", async () => {
  for (
    const stage of [
      "reserve",
      "write",
      "read",
      "complete",
      "cancelWrite",
      "changedRead",
      "crossedReceipt",
      "regressedPeer",
    ]
  ) {
    const f = await fixture(), controller = new AbortController();
    const unavailable = () => Promise.reject(new Error("private diagnostic"));
    if (stage === "reserve") {
      f.dependencies.repository.reserve = () =>
        Promise.reject(new HistoryError("analysis_history_operation_conflict"));
    }
    if (stage === "write") f.dependencies.storage.writeOnce = unavailable;
    if (stage === "read") f.dependencies.storage.verifyStored = unavailable;
    if (stage === "complete") f.dependencies.repository.complete = unavailable;
    if (stage === "cancelWrite") {
      f.dependencies.storage.writeOnce = () => {
        controller.abort();
        return Promise.resolve();
      };
    }
    if (stage === "changedRead") {
      f.buffers.set(id(3), new Uint8Array([9, 9, 9]));
    }
    if (stage === "crossedReceipt") f.receipt.items[0].media_id = id(77);
    if (stage === "regressedPeer") {
      f.receipt.items[1].ready = true;
      f.dependencies.repository.complete = () => {
        f.receipt.items[0].ready = true;
        f.receipt.items[1].ready = false;
        return Promise.resolve(f.receipt);
      };
    }
    const response = await uploadInitialEvidence(
      req(),
      frame(f.metadata, f.source),
      f.owner,
      f.dependencies,
      controller.signal,
    );
    assertEquals(response.status >= 400, true);
    assertEquals((await response.text()).includes("private diagnostic"), false);
    if (
      ["write", "read", "cancelWrite", "changedRead", "crossedReceipt"]
        .includes(stage)
    ) assertEquals(f.events.includes("complete"), false);
  }
});
