import { assertEquals, assertRejects } from "@std/assert";
import { erasePublicationPhoto } from "./handler.ts";
const object = "00000000-0000-4000-8000-000000000001",
  token = "00000000-0000-4000-8000-000000000002";
const claim = () => ({
  object_id: object,
  claim_token: token,
  available_at: "2026-10-01T00:00:00Z",
  claim_expires_at: "2026-10-01T00:02:00Z",
  erased_at: null,
  bound_at: null,
  revoked_at: null,
});
Deno.test("photo erasure processes one durable claim and freezes identity through external I/O", async () => {
  const row = claim();
  const calls: unknown[] = [];
  assertEquals(
    await erasePublicationPhoto({
      claim: (target) => {
        calls.push(target);
        return Promise.resolve(row);
      },
      erase: (id) => {
        calls.push(id);
        row.object_id = token;
        row.claim_token = object;
        return Promise.resolve();
      },
      finish: (id, lease, success) => {
        calls.push([id, lease, success]);
        return Promise.resolve(true);
      },
    }, object),
    { claimed: 1, marked: 1, acknowledged: 1 },
  );
  assertEquals(calls, [object, object, [object, token, true]]);
});
Deno.test("photo erasure does no I/O without a claim and never acknowledges a failed marker as success", async () => {
  let erased = 0;
  const acknowledgements: boolean[] = [];
  const deps = {
    claim: () => Promise.resolve(null),
    erase: () => {
      erased++;
      return Promise.resolve();
    },
    finish: (_id: string, _token: string, success: boolean) => {
      acknowledgements.push(success);
      return Promise.resolve(true);
    },
  };
  assertEquals(await erasePublicationPhoto(deps), {
    claimed: 0,
    marked: 0,
    acknowledged: 0,
  });
  assertEquals(erased, 0);
  assertEquals(
    await erasePublicationPhoto({
      ...deps,
      claim: () => Promise.resolve(claim()),
      erase: () => Promise.reject(new Error("synthetic storage failure")),
    }),
    { claimed: 1, marked: 0, acknowledged: 1 },
  );
  assertEquals(acknowledgements, [false]);
});
Deno.test("photo erasure retains durable recovery after lost acknowledgements without extra storage retries", async () => {
  for (
    const finish of [
      () => Promise.resolve(false),
      () => Promise.reject(new Error("lost response")),
    ]
  ) {
    let writes = 0;
    assertEquals(
      await erasePublicationPhoto({
        claim: () => Promise.resolve(claim()),
        erase: () => {
          writes++;
          return Promise.resolve();
        },
        finish,
      }),
      { claimed: 1, marked: 1, acknowledged: 0 },
    );
    assertEquals(writes, 1);
  }
});
Deno.test("photo erasure rejects malformed, already erased, live bound and misdirected claims before I/O", async () => {
  for (
    const value of [
      {},
      { ...claim(), bound_at: "2026-10-01T00:00:00Z" },
      { ...claim(), erased_at: "2026-10-01T00:00:00Z" },
      { ...claim(), claim_token: null },
      { ...claim(), available_at: "invalid" },
      { ...claim(), object_id: token },
      { ...claim(), extra: true },
    ]
  ) {
    let writes = 0;
    await assertRejects(() =>
      erasePublicationPhoto({
        claim: () => Promise.resolve(value),
        erase: () => {
          writes++;
          return Promise.resolve();
        },
        finish: () => Promise.resolve(true),
      }, object)
    );
    assertEquals(writes, 0);
  }
});
