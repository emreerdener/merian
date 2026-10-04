import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  eraseObservationEvidenceBatch,
  evidenceDigest,
  evidenceObjectKey,
  type EvidenceReceipt,
  type EvidenceRepository,
  parseEvidenceReceipt,
  readObservationEvidence,
  storeObservationEvidence,
} from "./evidence.ts";
import {
  getHistoryEvidenceConfig,
  PrivateHistoryEvidenceStorage,
} from "./evidenceStorage.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const identity = {
  owner_id: id(1),
  observation_id: id(2),
  analysis_id: id(3),
  media_id: id(4),
};
const bytes = new Uint8Array([1, 2, 3]);
async function fixture() {
  const receipt: EvidenceReceipt = {
    ...identity,
    object_id: id(5),
    content_type: "image/jpeg",
    byte_count: 3,
    sha256: await evidenceDigest(bytes),
    expires_at: new Date(Date.now() + 60_000).toISOString(),
    ready_at: null,
  };
  const config = getHistoryEvidenceConfig("write", (key) => ({
    R2_ACCOUNT_ID: "a".repeat(32),
    R2_BUCKET_NAME: "synthetic-public",
    R2_HISTORY_BUCKET_NAME: "synthetic-private",
    R2_HISTORY_WRITE_ACCESS_KEY_ID: "synthetic-key",
    R2_HISTORY_WRITE_SECRET_ACCESS_KEY: "synthetic-secret",
  }[key]));
  let object: { body: Uint8Array; headers: Headers } | undefined;
  const methods: string[] = [];
  const storage = new PrivateHistoryEvidenceStorage(
    () => config,
    () => config,
    async (request) => {
      methods.push(request.method);
      assertEquals(
        new URL(request.url).pathname,
        `/synthetic-private/${evidenceObjectKey(receipt.object_id)}`,
      );
      if (request.method === "HEAD") {
        return new Response(null, {
          status: object ? 200 : 404,
          headers: object?.headers,
        });
      }
      if (request.method === "GET") {
        return new Response(object?.body.slice(), {
          status: object ? 200 : 404,
          headers: object?.headers,
        });
      }
      assertEquals(request.method, "PUT");
      const body = new Uint8Array(await request.arrayBuffer());
      if (
        request.headers.get("if-none-match") === "*" && object
      ) return new Response(null, { status: 412 });
      object = { body, headers: request.headers };
      return new Response(null, { status: 200 });
    },
  );
  let deleted = false;
  let claims = 0;
  const acknowledgments: boolean[] = [];
  const repository: EvidenceRepository = {
    reserve: () => Promise.resolve({ ...receipt }),
    complete: () => {
      if (deleted) throw new Error("deleted");
      return Promise.resolve({
        ...receipt,
        ready_at: new Date().toISOString(),
      });
    },
    readOwned: () => {
      if (deleted) throw new Error("deleted");
      return Promise.resolve({
        ...receipt,
        ready_at: new Date().toISOString(),
      });
    },
    claimErasure: () =>
      Promise.resolve(
        claims++ === 0 ? { object_id: id(5), claim_token: id(6) } : null,
      ),
    finishErasure: (_claim, success) => {
      acknowledgments.push(success);
      return Promise.resolve(true);
    },
  };
  return {
    receipt,
    config,
    storage,
    repository,
    methods,
    acknowledgments,
    object: () => object,
    delete: () => {
      deleted = true;
    },
  };
}
Deno.test("history evidence storage fails closed without a separate private bucket and scoped configuration", () => {
  assertThrows(() => getHistoryEvidenceConfig("read", () => undefined));
  const env: Record<string, string> = {
    R2_ACCOUNT_ID: "a".repeat(32),
    R2_BUCKET_NAME: "same-bucket",
    R2_HISTORY_BUCKET_NAME: "same-bucket",
    R2_HISTORY_READ_ACCESS_KEY_ID: "synthetic-key",
    R2_HISTORY_READ_SECRET_ACCESS_KEY: "synthetic-secret",
  };
  assertThrows(() => getHistoryEvidenceConfig("read", (key) => env[key]));
  env.R2_HISTORY_BUCKET_NAME = "different-bucket";
  assertEquals(
    getHistoryEvidenceConfig("read", (key) => env[key]).bucketName,
    "different-bucket",
  );
  assertThrows(() => getHistoryEvidenceConfig("write", (key) => env[key]));
});
Deno.test("history evidence reserves before writing and fences completion", async () => {
  const f = await fixture();
  const order: string[] = [];
  const result = await storeObservationEvidence(identity, "image/jpeg", bytes, {
    ...f.repository,
    reserve: (input) => {
      order.push("reserve");
      assertEquals(input.sha256, f.receipt.sha256);
      return Promise.resolve(f.receipt);
    },
    complete: async (input) => {
      order.push("complete");
      assertEquals(f.object()?.body, bytes);
      return await f.repository.complete(input, f.receipt.object_id);
    },
  }, {
    ...f.storage,
    writeOnce: async (receipt, body) => {
      order.push("write");
      await f.storage.writeOnce(receipt, body);
    },
    signedRead: () => Promise.resolve("unused"),
    erase: () => Promise.resolve(),
  });
  assertEquals(order, ["reserve", "write", "complete"]);
  assert(result.ready_at);
});
Deno.test("history evidence lost-response retry cannot overwrite a completed object", async () => {
  const f = await fixture();
  await f.storage.writeOnce(f.receipt, bytes);
  await f.storage.writeOnce(f.receipt, bytes);
  assertEquals(f.methods, ["PUT", "HEAD", "PUT", "HEAD"]);
  assertEquals(f.object()?.body, bytes);
  await assertRejects(() =>
    f.storage.writeOnce(f.receipt, new Uint8Array([9]))
  );
  assertEquals(f.methods.length, 4);
});
for (const order of ["upload-first", "erasure-first"]) {
  Deno.test(`history evidence permanent erasure marker prevents resurrection: ${order}`, async () => {
    const f = await fixture();
    if (order === "upload-first") await f.storage.writeOnce(f.receipt, bytes);
    await f.storage.erase(f.receipt.object_id);
    await assertRejects(
      () => f.storage.writeOnce(f.receipt, bytes),
      Error,
      "verification_failed",
    );
    assertEquals(f.object()?.body.byteLength, 0);
    assertEquals(f.object()?.headers.get("x-amz-meta-erased"), "true");
    await f.storage.erase(f.receipt.object_id);
    assertEquals(f.object()?.body.byteLength, 0);
    assert(!f.methods.includes("DELETE"));
  });
}
Deno.test("history evidence deletion after upload rejects completion and owner reads", async () => {
  const f = await fixture();
  const storage = {
    writeOnce: async (receipt: EvidenceReceipt, body: Uint8Array) => {
      await f.storage.writeOnce(receipt, body);
      f.delete();
    },
    signedRead: f.storage.signedRead.bind(f.storage),
    erase: f.storage.erase.bind(f.storage),
  };
  await assertRejects(
    () =>
      storeObservationEvidence(
        identity,
        "image/jpeg",
        bytes,
        f.repository,
        storage,
      ),
    Error,
    "deleted",
  );
  await assertRejects(
    () => readObservationEvidence(identity, f.repository, f.storage),
    Error,
    "deleted",
  );
  assertEquals(await eraseObservationEvidenceBatch(f.repository, f.storage), 1);
  assertEquals(f.object()?.body.byteLength, 0);
});
Deno.test("history evidence read uses owner receipt and bounded no-store GET capability", async () => {
  const f = await fixture();
  const url = new URL(
    await readObservationEvidence(identity, f.repository, f.storage),
  );
  assertEquals(url.hostname, `${"a".repeat(32)}.r2.cloudflarestorage.com`);
  assertEquals(url.searchParams.get("X-Amz-Expires"), "30");
  assertEquals(
    url.searchParams.get("response-cache-control"),
    "private, no-store",
  );
  assert(!url.pathname.includes(identity.owner_id));
  assert(!url.pathname.includes(identity.observation_id));
  await assertRejects(() =>
    readObservationEvidence(identity, {
      ...f.repository,
      readOwned: () => Promise.resolve({ ...f.receipt, owner_id: id(7) }),
    }, f.storage)
  );
  await assertRejects(() =>
    readObservationEvidence(identity, {
      ...f.repository,
      readOwned: () => Promise.resolve(f.receipt),
    }, f.storage)
  );
});
Deno.test("history evidence validates identity, deadline and content before R2 dispatch", async () => {
  const f = await fixture();
  for (
    const path of [
      "../private",
      "https://media.merian.app/synthetic",
      `${id(5)}/extra`,
    ]
  ) assertThrows(() => evidenceObjectKey(path));
  assertThrows(() =>
    parseEvidenceReceipt({ ...f.receipt, byte_count: 0 }, identity)
  );
  assertThrows(() =>
    parseEvidenceReceipt(
      { ...f.receipt, object_id: identity.owner_id },
      identity,
    )
  );
  await assertRejects(() =>
    storeObservationEvidence(
      identity,
      "text/html",
      bytes,
      f.repository,
      f.storage,
    )
  );
  await assertRejects(() =>
    storeObservationEvidence(
      { ...identity, analysis_id: identity.observation_id },
      "image/jpeg",
      bytes,
      f.repository,
      f.storage,
    )
  );
  await assertRejects(() =>
    storeObservationEvidence(identity, "image/jpeg", bytes, {
      ...f.repository,
      reserve: () =>
        Promise.resolve({
          ...f.receipt,
          expires_at: "2000-01-01T00:00:00Z",
        }),
    }, f.storage)
  );
  assertEquals(f.methods, []);
});
Deno.test("history evidence erasure failure and lost claims never acknowledge success", async () => {
  const f = await fixture();
  assertEquals(
    await eraseObservationEvidenceBatch(f.repository, {
      writeOnce: () => Promise.resolve(),
      signedRead: () => Promise.resolve("unused"),
      erase: () => Promise.reject(new Error("synthetic failure")),
    }),
    0,
  );
  assertEquals(f.acknowledgments, [false]);
  const g = await fixture();
  assertEquals(
    await eraseObservationEvidenceBatch({
      ...g.repository,
      finishErasure: () => Promise.resolve(false),
    }, g.storage),
    0,
  );
  assertEquals(g.object()?.body.byteLength, 0);
});
Deno.test("history evidence caller buffer mutation cannot change admitted bytes", async () => {
  const f = await fixture();
  const body = bytes.slice();
  const pending = storeObservationEvidence(
    identity,
    "image/jpeg",
    body,
    f.repository,
    f.storage,
  );
  body.fill(9);
  await pending;
  assertEquals(f.object()?.body, bytes);
});

Deno.test("history evidence erasure refuses successful PUT without verified empty marker", async () => {
  const f = await fixture();
  const storage = new PrivateHistoryEvidenceStorage(
    () => f.config,
    () => f.config,
    () =>
      Promise.resolve(
        new Response(null, { status: 200, headers: { "Content-Length": "3" } }),
      ),
  );
  await assertRejects(
    () => storage.erase(f.receipt.object_id),
    Error,
    "history_evidence_erasure_failed",
  );
});

Deno.test("history provider materialization verifies bytes and denies erased content", async () => {
  const f = await fixture();
  await f.storage.writeOnce(f.receipt, bytes);
  assertEquals(await f.storage.readVerified(f.receipt), bytes);
  await f.storage.erase(f.receipt.object_id);
  await assertRejects(
    () => f.storage.readVerified(f.receipt),
    Error,
    "history_evidence_verification_failed",
  );
});
Deno.test("history provider materialization rejects mismatched digest and oversized streams", async () => {
  const f = await fixture();
  for (const body of [new Uint8Array([8, 8, 8]), new Uint8Array(4)]) {
    const storage = new PrivateHistoryEvidenceStorage(
      () => f.config,
      () => f.config,
      () =>
        Promise.resolve(
          new Response(body, {
            headers: {
              "Content-Type": f.receipt.content_type,
              "Content-Length": String(f.receipt.byte_count),
              "x-amz-meta-sha256": f.receipt.sha256,
            },
          }),
        ),
    );
    await assertRejects(
      () => storage.readVerified(f.receipt),
      Error,
      "history_evidence_verification_failed",
    );
  }
});
