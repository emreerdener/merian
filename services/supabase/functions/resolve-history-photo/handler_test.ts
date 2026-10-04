import { assert, assertEquals } from "@std/assert";
import { resolveHistoryPhoto } from "./handler.ts";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";

const req = new Request("https://example.invalid/resolve-history-photo", {
  method: "POST",
});
const identity = {
  owner_id: "00000000-0000-4000-8000-000000000001",
  observation_id: "00000000-0000-4000-8000-000000000002",
  analysis_id: "00000000-0000-4000-8000-000000000003",
  media_id: "00000000-0000-4000-8000-000000000004",
};
const receipt = {
  ...identity,
  object_id: "00000000-0000-4000-8000-000000000005",
  content_type: "image/jpeg",
  byte_count: 3,
  sha256: "a".repeat(64),
  expires_at: "2026-01-01T00:00:00Z",
  ready_at: "2026-01-01T00:00:00Z",
};
const { owner_id, ...ids } = identity;
const body = { ...ids, reader_protocol: 8 };
Deno.test("photo resolver delivers only temporary content ticket after two owner checks", async () => {
  let reads = 0;
  const response = await resolveHistoryPhoto(req, body, owner_id, {
    receipt: (input) => {
      assertEquals(input, identity);
      reads++;
      return Promise.resolve(receipt);
    },
    sign: () =>
      Promise.resolve("https://example.invalid/synthetic-signed-photo"),
  });
  assertEquals(response.status, 200);
  assertEquals(reads, 2);
  assertEquals(response.headers.get("Cache-Control"), "private, no-store");
  const ticket = await response.json();
  assert(!("object_id" in ticket));
  assert(!("ready_at" in ticket));
  assertEquals(ticket.media_id, identity.media_id);
  assert(ticket.expires_at_ms <= Date.now() + 30_000);
});
Deno.test("photo resolver denies owner injection and unsupported readers before access", async () => {
  for (
    const invalid of [{ ...body, owner_id }, { ...body, reader_protocol: 7 }, {
      ...body,
      media_id: "bad",
    }]
  ) {
    const response = await resolveHistoryPhoto(req, invalid, owner_id, {
      receipt: () => {
        throw new Error("must not access");
      },
      sign: () => {
        throw new Error("must not sign");
      },
    });
    assertEquals(response.status, 400);
  }
});
Deno.test("photo resolver deletion during signing wins and storage errors stay private", async () => {
  let reads = 0;
  const response = await resolveHistoryPhoto(req, body, owner_id, {
    receipt: () => {
      if (++reads === 2) throw new HistoryError("analysis_history_not_found");
      return Promise.resolve(receipt);
    },
    sign: () =>
      Promise.resolve("https://example.invalid/synthetic-signed-photo"),
  });
  assertEquals(response.status, 404);
  const failure = await resolveHistoryPhoto(req, body, owner_id, {
    receipt: () => Promise.resolve(receipt),
    sign: () => {
      throw new Error("private-object-diagnostic");
    },
  });
  assertEquals(failure.status, 503);
  assert(!(await failure.text()).includes("private-object-diagnostic"));
});
