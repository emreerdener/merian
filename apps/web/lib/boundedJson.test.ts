import assert from "node:assert/strict";
import test from "node:test";
import {
  readBoundedJsonObject,
  readByteStreamWithinLimit,
} from "./boundedJson.ts";

test("bounded JSON reader accepts application/json and +json objects", async () => {
  for (
    const contentType of [
      "application/json; charset=utf-8",
      "application/problem+json",
    ]
  ) {
    const result = await readBoundedJsonObject(
      new Request("https://naturebook.earth/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": contentType },
        body: JSON.stringify({ email: "person@example.com" }),
      }),
      1024,
    );
    assert.deepEqual(result, {
      ok: true,
      value: { email: "person@example.com" },
    });
  }
});

test("bounded JSON reader rejects unsupported types and invalid objects", async () => {
  const unsupported = await readBoundedJsonObject(
    new Request("https://naturebook.earth/api/waitlist", {
      method: "POST",
      body: "{}",
    }),
    1024,
  );
  assert.equal(unsupported.ok, false);
  if (!unsupported.ok) assert.equal(unsupported.code, "unsupported_media_type");

  const array = await readBoundedJsonObject(
    new Request("https://naturebook.earth/api/waitlist", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "[]",
    }),
    1024,
  );
  assert.equal(array.ok, false);
  if (!array.ok) assert.equal(array.code, "invalid_json_object");
});

test("bounded JSON reader enforces declared and streamed byte limits", async () => {
  const declared = await readBoundedJsonObject(
    new Request("https://naturebook.earth/api/waitlist", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": "1025",
      },
      body: "{}",
    }),
    1024,
  );
  assert.equal(declared.ok, false);
  if (!declared.ok) assert.equal(declared.code, "payload_too_large");

  const streamed = await readBoundedJsonObject(
    new Request("https://naturebook.earth/api/waitlist", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ value: "x".repeat(1024) }),
    }),
    1024,
  );
  assert.equal(streamed.ok, false);
  if (!streamed.ok) assert.equal(streamed.code, "payload_too_large");

  const mismatch = await readBoundedJsonObject(
    new Request("https://naturebook.earth/api/waitlist", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": "0",
      },
      body: "{}",
    }),
    1024,
  );
  assert.equal(mismatch.ok, false);
  if (!mismatch.ok) assert.equal(mismatch.code, "invalid_content_length");
});

test("bounded byte stream coalesces tiny chunks without per-chunk retention", async () => {
  const byteCount = 2_049;
  let nextByte = 0;
  const result = await readByteStreamWithinLimit(
    new ReadableStream<Uint8Array>({
      pull(controller) {
        if (nextByte >= byteCount) {
          controller.close();
          return;
        }
        controller.enqueue(Uint8Array.of(nextByte % 251));
        nextByte += 1;
      },
    }),
    byteCount,
  );

  assert.equal(result.ok, true);
  if (result.ok) {
    assert.equal(result.bytes.byteLength, byteCount);
    assert.equal(result.bytes[byteCount - 1], (byteCount - 1) % 251);
  }
});
