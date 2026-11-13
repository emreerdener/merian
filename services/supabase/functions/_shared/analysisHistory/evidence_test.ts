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

import { getPublicationPhotoConfig } from "./publicPhotoStorage.ts";

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
    R2_SCANS_PRIVATE_BUCKET_NAME: "synthetic-private",
    R2_SCANS_PRIVATE_WRITE_ACCESS_KEY_ID: "synthetic-key",
    R2_SCANS_PRIVATE_WRITE_SECRET_ACCESS_KEY: "synthetic-secret",
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
    R2_SCANS_PRIVATE_BUCKET_NAME: "same-bucket",
    R2_SCANS_PRIVATE_READ_ACCESS_KEY_ID: "synthetic-key",
    R2_SCANS_PRIVATE_READ_SECRET_ACCESS_KEY: "synthetic-secret",
  };
  assertThrows(() => getHistoryEvidenceConfig("read", (key) => env[key]));
  env.R2_SCANS_PRIVATE_BUCKET_NAME = "different-bucket";
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

Deno.test("private erasure propagates cancellation before PUT, before HEAD and after HEAD", async () => {
  const f = await fixture();
  for (const phase of ["before", "PUT", "HEAD"]) {
    const controller = new AbortController(), calls: string[] = [];
    if (phase === "before") controller.abort();
    const storage = new PrivateHistoryEvidenceStorage(
      () => f.config,
      () => f.config,
      (req) => {
        calls.push(req.method);
        assert(!req.signal.aborted);
        if (req.method === phase) controller.abort();
        return Promise.resolve(
          new Response(null, {
            headers: { "Content-Length": "0", "x-amz-meta-erased": "true" },
          }),
        );
      },
    );
    await assertRejects(() =>
      storage.erase(f.receipt.object_id, controller.signal)
    );
    assertEquals(
      calls,
      phase === "before" ? [] : phase === "PUT" ? ["PUT"] : ["PUT", "HEAD"],
    );
  }
});

Deno.test("private scans configuration rejects legacy-only and mixed settings for both storage owners", () => {
  const base: Record<string, string> = {
    R2_ACCOUNT_ID: "a".repeat(32),
    R2_BUCKET_NAME: "synthetic-public",
    R2_SCANS_PRIVATE_BUCKET_NAME: "synthetic-private",
    R2_SCANS_PRIVATE_READ_ACCESS_KEY_ID: "private-read-key",
    R2_SCANS_PRIVATE_READ_SECRET_ACCESS_KEY: "private-read-secret",
    R2_SCANS_PRIVATE_WRITE_ACCESS_KEY_ID: "private-write-key",
    R2_SCANS_PRIVATE_WRITE_SECRET_ACCESS_KEY: "private-write-secret",
    R2_PUBLICATION_READ_ACCESS_KEY_ID: "public-read-key",
    R2_PUBLICATION_READ_SECRET_ACCESS_KEY: "public-read-secret",
    R2_PUBLICATION_WRITE_ACCESS_KEY_ID: "public-write-key",
    R2_PUBLICATION_WRITE_SECRET_ACCESS_KEY: "public-write-secret",
  };
  const legacy = [
    "R2_HISTORY_BUCKET_NAME",
    "R2_HISTORY_READ_ACCESS_KEY_ID",
    "R2_HISTORY_READ_SECRET_ACCESS_KEY",
    "R2_HISTORY_WRITE_ACCESS_KEY_ID",
    "R2_HISTORY_WRITE_SECRET_ACCESS_KEY",
  ];
  for (const access of ["read", "write"] as const) {
    assertEquals(
      getHistoryEvidenceConfig(access, (key) => base[key]).bucketName,
      "synthetic-private",
    );
    assertEquals(
      getPublicationPhotoConfig(access, (key) => base[key]).bucketName,
      "synthetic-public",
    );
    for (const legacyName of legacy) {
      const newName = legacyName.replace("R2_HISTORY_", "R2_SCANS_PRIVATE_");
      for (const value of ["", base[newName]]) {
        for (const mixed of [false, true]) {
          const env = { ...base, [legacyName]: value };
          if (!mixed) {
            for (const name of Object.keys(env)) {
              if (name.startsWith("R2_SCANS_PRIVATE_")) delete env[name];
            }
          }
          for (
            const [readConfig, message] of [
              [
                getHistoryEvidenceConfig,
                "history_evidence_storage_unavailable",
              ],
              [
                getPublicationPhotoConfig,
                "publication_photo_storage_unavailable",
              ],
            ] as const
          ) {
            const error = assertThrows(
              () => readConfig(access, (key) => env[key]),
              Error,
            );
            assertEquals(error.message, message);
            assertEquals(error.cause, undefined);
          }
        }
      }
    }
    for (const suffix of ["ACCESS_KEY_ID", "SECRET_ACCESS_KEY"]) {
      const env = { ...base };
      delete env[`R2_SCANS_PRIVATE_${access.toUpperCase()}_${suffix}`];
      assertThrows(
        () => getHistoryEvidenceConfig(access, (key) => env[key]),
        Error,
        "history_evidence_storage_unavailable",
      );
    }
  }
});

// Exercise the default AwsClient path; injected Transport fixtures bypass signing.
for (const cancellation of ["caller", "deadline"] as const) {
  Deno.test(`private storage signed requests retain ${cancellation} cancellation`, async (t) => {
    for (
      const phase of [
        "upload PUT",
        "upload HEAD",
        "read GET",
        "erase PUT",
        "erase HEAD",
      ]
    ) {
      await t.step(phase, async () => {
        const f = await fixture();
        const controller = new AbortController();
        const originalFetch = globalThis.fetch;
        const originalTimeout = AbortSignal.timeout;
        const calls: string[] = [];
        let observed: AbortSignal | undefined;
        const method = phase.split(" ")[1];
        try {
          if (cancellation === "deadline") {
            AbortSignal.timeout = () => controller.signal;
          }
          globalThis.fetch = (input, init) => {
            const request = new Request(input, init);
            calls.push(request.method);
            if (request.method === method) {
              observed = request.signal;
              controller.abort(
                new DOMException("synthetic cancellation", "AbortError"),
              );
              return Promise.reject(controller.signal.reason);
            }
            return Promise.resolve(new Response(null, { status: 200 }));
          };
          const storage = new PrivateHistoryEvidenceStorage(
            () => f.config,
            () => f.config,
          );
          const caller = cancellation === "caller"
            ? controller.signal
            : undefined;
          await assertRejects(
            () =>
              phase.startsWith("upload")
                ? storage.writeOnce(f.receipt, bytes, caller)
                : phase.startsWith("read")
                ? storage.readVerified(f.receipt, caller)
                : storage.erase(f.receipt.object_id, caller),
            DOMException,
            "synthetic cancellation",
          );
          assert(
            observed,
            "the real signing path must reach the synthetic fetch",
          );
          assert(
            observed.aborted,
            "signing must preserve cancellation on the outgoing request",
          );
          assertEquals(calls, method === "HEAD" ? ["PUT", "HEAD"] : [method]);
        } finally {
          globalThis.fetch = originalFetch;
          AbortSignal.timeout = originalTimeout;
        }
      });
    }
  });
}

Deno.test("private storage leaves retryable HTTP failures to the durable owner", async (t) => {
  for (const status of [429, 503]) {
    await t.step(String(status), async () => {
      const f = await fixture();
      const originalFetch = globalThis.fetch;
      const originalRandom = Math.random;
      const calls: string[] = [];
      try {
        // A regression must fail promptly, without the SDK's exponential wait.
        Math.random = () => 0;
        globalThis.fetch = (input, init) => {
          calls.push(new Request(input, init).method);
          if (calls.length > 1) {
            return Promise.reject(new Error("unexpected SDK retry"));
          }
          return Promise.resolve(new Response(null, { status }));
        };
        const storage = new PrivateHistoryEvidenceStorage(
          () => f.config,
          () => f.config,
        );
        await assertRejects(
          () => storage.writeOnce(f.receipt, bytes),
          Error,
          "history_evidence_storage_unavailable",
        );
        assertEquals(calls, ["PUT"]);
      } finally {
        globalThis.fetch = originalFetch;
        Math.random = originalRandom;
      }
    });
  }
});
