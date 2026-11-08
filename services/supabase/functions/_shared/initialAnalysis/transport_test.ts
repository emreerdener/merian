import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import vectors from "./fixtures/admission-v1.json" with { type: "json" };
import catalog from "./configuration-assets-v1.json" with { type: "json" };
import { prepareInitialAdmission } from "./preparation.ts";
import { InitialAnalysisLifecycleRepository } from "./repository.ts";
import {
  createInitialAdmissionTransport,
  INITIAL_ADMISSION_RESPONSE_BYTES,
  INITIAL_ASSET_BYTES,
  type InitialAssetReader,
  initialDeadline,
  readInitialStream,
} from "./transport.ts";

const key = ["sb", "secret", "fixture", "a".repeat(20)].join("_");
const origin = "https://project.supabase.co";
const owner = "00000000-0000-4000-8000-00000000b001";
const scan = "00000000-0000-4000-8000-00000000b002";
const input = vectors.valid[0];
const unknown = {
  outcome: "unknown",
  reason: "write_outcome_unknown",
} as const;
const unavailable = {
  outcome: "held",
  reason: "configuration_unavailable",
} as const;
const signal = () => new AbortController().signal;
const encoder = new TextEncoder();
const root = new URL("../../../../../", import.meta.url);
const assetReader: InitialAssetReader = async (path, revision, caller) => {
  assertEquals(revision, catalog.manifest.repository_revision);
  caller.throwIfAborted();
  return new Blob([await Deno.readFile(new URL(path, root))]).stream();
};
const binding = {
  version: 1 as const,
  owner_id: owner,
  scan_id: scan,
  route: input.input.route,
  submission_digest: input.digest,
  configuration_digest: "a".repeat(64),
  funding_digest: "b".repeat(64),
  descriptions_digest: "c".repeat(64),
  funding_binding_id: "00000000-0000-4000-8000-00000000b003",
  assets_digest: catalog.digest,
};
function repository(
  fetcher: typeof fetch,
  read: InitialAssetReader = assetReader,
) {
  return new InitialAnalysisLifecycleRepository(
    createInitialAdmissionTransport(origin, key, fetcher),
    read,
  );
}
function recover(repo: InitialAnalysisLifecycleRepository, caller = signal()) {
  return repo.recoverAdmission(
    owner,
    scan,
    input.canonical,
    input.digest,
    caller,
  );
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

Deno.test("IC-1 fixed transport rejects untrusted origins and forged adapters", () => {
  for (
    const url of [
      "http://remote.test",
      "https://a.test/path",
      "https://u:p@a.test",
      "https://a.test/?q=x",
      "https://a.test/#x",
    ]
  ) {
    assertThrows(() => createInitialAdmissionTransport(url, key));
  }
  assertThrows(() =>
    new InitialAnalysisLifecycleRepository({
      call: () => Promise.resolve({ data: null, error: null }),
    }, assetReader)
  );
});

Deno.test("IC-1 transport sends one fixed POST with no redirects or auth retry", async () => {
  let calls = 0;
  const repo = repository((url, init) => {
    calls++;
    assertEquals(url, origin + "/rest/v1/rpc/admit_initial_analysis");
    assertEquals(init?.method, "POST");
    assertEquals(init?.redirect, "error");
    assertEquals(init?.credentials, "omit");
    assertEquals(init?.cache, "no-store");
    assert(init?.signal instanceof AbortSignal);
    const headers = new Headers(init?.headers);
    assertEquals(headers.get("apikey"), key);
    assertEquals(headers.get("Authorization"), null);
    const args = JSON.parse(init?.body as string);
    assertEquals(args.p_canonical_input, input.canonical);
    assertEquals(args.p_submission_digest, input.digest);
    assertEquals(args.p_assets_digest, null);
    assertEquals(args.p_ip_hash, null);
    return Promise.resolve(Response.json({ outcome: "replay", binding }));
  }, () => {
    throw new Error("recovery must skip assets");
  });
  assertEquals(await recover(repo), { outcome: "replay", binding });
  assertEquals(calls, 1);
});

Deno.test("IC-1 transient auth redirect malformed and oversized responses never retry", async (t) => {
  const cases = [
    () => Promise.reject(new Error("private transport failure")),
    () => Promise.resolve(new Response("{}", { status: 503 })),
    () => Promise.resolve(new Response("{}", { status: 401 })),
    () => Promise.resolve(new Response("{}", { status: 429 })),
    () =>
      Promise.resolve(
        new Response("{}", {
          status: 307,
          headers: { Location: "https://other.test" },
        }),
      ),
    () => Promise.resolve(new Response("bad json")),
    () => Promise.resolve(new Response(new Uint8Array([255]))),
    () =>
      Promise.resolve(
        Response.json({ outcome: "replay", binding, grant: true }),
      ),
    () =>
      Promise.resolve(
        Response.json({ code: "55000", message: "initial_analysis_deleted" }, {
          status: 502,
        }),
      ),
    ...[200, 500].map((status) => () =>
      Promise.resolve(
        new Response(
          new Blob([new Uint8Array(INITIAL_ADMISSION_RESPONSE_BYTES + 1)])
            .stream(),
          { status },
        ),
      )
    ),
  ];
  for (let index = 0; index < cases.length; index++) {
    await t.step(`case ${index}`, async () => {
      let calls = 0;
      const repo = repository(() => {
        calls++;
        return cases[index]();
      });
      assertEquals(await recover(repo), unknown);
      assertEquals(calls, 1);
    });
  }
});

Deno.test("IC-1 exact SQL denial is preserved without trusting arbitrary database prose", async () => {
  for (
    const [status, code, message, reason] of [
      [400, "22023", "initial_analysis_identity_conflict", "conflict"],
      [404, "P0002", "initial_analysis_owner_unavailable", "owner_unavailable"],
      [500, "55000", "initial_analysis_deleted", "deleted"],
      [500, "55000", "private unrelated prose", null],
    ] as const
  ) {
    const repo = repository(() =>
      Promise.resolve(
        Response.json({ code, message, details: null, hint: null }, { status }),
      )
    );
    assertEquals(
      await recover(repo),
      reason ? { outcome: "held", reason } : unknown,
    );
  }
});

Deno.test("IC-1 pre-aborted calls issue no asset or network I/O", async () => {
  const controller = new AbortController();
  controller.abort();
  let calls = 0;
  const repo = repository(() => {
    calls++;
    throw new Error("network");
  }, () => {
    calls++;
    throw new Error("asset");
  });
  assertEquals(
    await repo.admit(
      owner,
      scan,
      await prepareInitialAdmission(input.input),
      "a".repeat(64),
      controller.signal,
    ),
    unavailable,
  );
  assertEquals(await recover(repo, controller.signal), unknown);
  assertEquals(calls, 0);
});

Deno.test("IC-1 cancelled late asset resolution cannot launch admission and cancels its stream", async () => {
  const caller = new AbortController();
  const entered = deferred<void>();
  const late = deferred<ReadableStream<Uint8Array>>();
  let network = 0, reads = 0, cancelled = false;
  const repo = repository(() => {
    network++;
    throw new Error("network");
  }, (_path, _revision, supplied) => {
    reads++;
    assert(!supplied.aborted);
    entered.resolve();
    return late.promise;
  });
  const pending = repo.admit(
    owner,
    scan,
    await prepareInitialAdmission(input.input),
    "a".repeat(64),
    caller.signal,
  );
  await entered.promise;
  caller.abort();
  assertEquals(await pending, unavailable);
  late.resolve(
    new ReadableStream({
      cancel() {
        cancelled = true;
      },
    }),
  );
  await new Promise((r) => setTimeout(r, 0));
  assertEquals([reads, network, cancelled], [1, 0, true]);
});

Deno.test("IC-1 oversized or stalled asset streams cancel without admission", async () => {
  for (const oversize of [true, false]) {
    const caller = new AbortController();
    const entered = deferred<void>();
    let network = 0, cancelled = false;
    const repo = repository(() => {
      network++;
      throw new Error("network");
    }, () =>
      Promise.resolve(
        new ReadableStream({
          start(controller) {
            if (oversize) {
              controller.enqueue(new Uint8Array(INITIAL_ASSET_BYTES + 1));
            }
            entered.resolve();
          },
          cancel() {
            cancelled = true;
            return new Promise<void>(() => {});
          },
        }),
      ));
    const pending = repo.admit(
      owner,
      scan,
      await prepareInitialAdmission(input.input),
      "a".repeat(64),
      caller.signal,
    );
    await entered.promise;
    if (!oversize) caller.abort();
    assertEquals(await pending, unavailable);
    assertEquals(network, 0);
    assert(cancelled);
  }
});

Deno.test("IC-1 cancellation after final asset prevents write", async () => {
  const caller = new AbortController();
  let network = 0;
  const repo = repository(() => {
    network++;
    throw new Error("network");
  }, async (path, revision, supplied) => {
    const stream = await assetReader(path, revision, supplied);
    if (path === catalog.manifest.files.at(-1)!.path) caller.abort();
    return stream;
  });
  assertEquals(
    await repo.admit(
      owner,
      scan,
      await prepareInitialAdmission(input.input),
      "a".repeat(64),
      caller.signal,
    ),
    unavailable,
  );
  assertEquals(network, 0);
});

Deno.test("IC-1 lost committed admission reply stays unknown and exact recovery skips assets", async () => {
  const caller = new AbortController();
  const issued = deferred<void>();
  const late = deferred<Response>();
  let calls = 0, reads = 0, cancelled = false;
  const requests: Record<string, unknown>[] = [];
  const repo = repository((_url, init) => {
    requests.push(JSON.parse(init!.body as string));
    calls++;
    if (calls === 1) {
      issued.resolve();
      return late.promise;
    }
    return Promise.resolve(Response.json({ outcome: "replay", binding }));
  }, (path, revision, supplied) => {
    reads++;
    return assetReader(path, revision, supplied);
  });
  const pending = repo.admit(
    owner,
    scan,
    await prepareInitialAdmission(input.input),
    "a".repeat(64),
    caller.signal,
  );
  await issued.promise;
  caller.abort();
  assertEquals(await pending, unknown);
  const count = reads;
  late.resolve(
    new Response(
      new ReadableStream({
        cancel() {
          cancelled = true;
        },
      }),
    ),
  );
  await new Promise((r) => setTimeout(r, 0));
  assert(cancelled);
  assertEquals(calls, 1);
  assertEquals(await recover(repo), { outcome: "replay", binding });
  assertEquals(calls, 2);
  assertEquals(reads, count);
  assertEquals(requests[1], {
    ...requests[0],
    p_assets_digest: null,
    p_ip_hash: null,
  });
});

Deno.test("IC-1 stalled RPC response body aborts promptly and releases reader", async () => {
  const caller = new AbortController();
  const entered = deferred<void>();
  let cancelled = false;
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(encoder.encode('{"outcome":'));
    },
    pull() {
      entered.resolve();
    },
    cancel() {
      cancelled = true;
      return new Promise<void>(() => {});
    },
  });
  const repo = repository(() => Promise.resolve(new Response(body)));
  const pending = recover(repo, caller.signal);
  await entered.promise;
  caller.abort();
  assertEquals(await pending, unknown);
  await new Promise((r) => setTimeout(r, 0));
  assert(cancelled);
  assert(!body.locked);
});

Deno.test("IC-1 bounded stream copies chunks and enforces aggregate actual bytes", async () => {
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    start(c) {
      c.enqueue(new Uint8Array(5));
      c.enqueue(new Uint8Array(5));
    },
    cancel() {
      cancelled = true;
    },
  });
  await assertRejects(() => readInitialStream(stream, 9, signal()));
  assert(cancelled);
  assert(!stream.locked);
});

Deno.test("IC-1 real deadline regains control from a noncooperative reader", async () => {
  const began = performance.now();
  await assertRejects(() =>
    initialDeadline(
      signal(),
      15,
      (deadline) => readInitialStream(new ReadableStream(), 8, deadline),
    )
  );
  assert(performance.now() - began < 1_000);
});

Deno.test("IC-1 actual five-second asset budget prevents late network work", async () => {
  let network = 0;
  const repo = repository(() => {
    network++;
    throw new Error("network");
  }, () => new Promise(() => {}));
  const began = performance.now();
  assertEquals(
    await repo.admit(
      owner,
      scan,
      await prepareInitialAdmission(input.input),
      "a".repeat(64),
      signal(),
    ),
    unavailable,
  );
  assert(performance.now() - began >= 4_900);
  assert(performance.now() - began < 8_000);
  assertEquals(network, 0);
});

Deno.test("IC-1 actual twelve-second RPC budget stays unknown without retry", async () => {
  let calls = 0;
  let observed: AbortSignal | undefined;
  const repo = repository((_url, init) => {
    calls++;
    observed = init?.signal ?? undefined;
    return new Promise(() => {});
  });
  const began = performance.now();
  assertEquals(await recover(repo), unknown);
  assert(performance.now() - began >= 11_900);
  assert(performance.now() - began < 15_000);
  assertEquals(calls, 1);
  assert(observed?.aborted);
});

Deno.test("IC-1 immediately ready empty chunks terminate without waiting for timer delivery", async () => {
  let pulls = 0, cancelled = false;
  const body = new ReadableStream<Uint8Array>({
    pull(c) {
      pulls++;
      c.enqueue(new Uint8Array());
    },
    cancel() {
      cancelled = true;
    },
  });
  const repo = repository(() => Promise.resolve(new Response(body)));
  assertEquals(await recover(repo), unknown);
  assert(pulls <= 35);
  assert(cancelled);
  assert(!body.locked);
});

Deno.test("IC-1 excessive tiny positive chunks terminate within work budget", async () => {
  let pulls = 0, cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    pull(c) {
      pulls++;
      c.enqueue(new Uint8Array([32]));
    },
    cancel() {
      cancelled = true;
    },
  });
  await assertRejects(() => readInitialStream(stream, 131_072, signal()));
  assert(pulls <= 4_099);
  assert(cancelled);
  assert(!stream.locked);
});

Deno.test("IC-1 elapsed monotonic deadline prevents dispatch when timer delivery is delayed", async () => {
  let calls = 0;
  const transport = createInitialAdmissionTransport(origin, key, () => {
    calls++;
    return Promise.resolve(Response.json({ outcome: "replay", binding }));
  });
  await assertRejects(() =>
    initialDeadline(signal(), 5, async (outer) => {
      const until = performance.now() + 15;
      while (
        performance.now() < until
      ) { /* Delay timer delivery intentionally. */ }
      return await initialDeadline(outer, 12_000, (inner) =>
        transport.call({
          p_owner: owner,
          p_scan: scan,
          p_canonical_input: input.canonical,
          p_submission_digest: input.digest,
          p_assets_digest: null,
          p_ip_hash: null,
        }, inner));
    })
  );
  assertEquals(calls, 0);
});

Deno.test("IC-1 elapsed deadline discards a late resolver value even before timer delivery", async () => {
  let cancelled = false;
  await assertRejects(() =>
    initialDeadline(signal(), 5, async (deadline) => {
      const until = performance.now() + 15;
      while (performance.now() < until) { /* Block timer callback. */ }
      return await readInitialStream(
        new ReadableStream({
          start(c) {
            c.enqueue(new Uint8Array([1]));
            c.close();
          },
          cancel() {
            cancelled = true;
          },
        }),
        8,
        deadline,
      );
    })
  );
  assert(cancelled);
});

Deno.test("IC-1 completed known binding remains known after later caller cancellation", async () => {
  const caller = new AbortController();
  const result = await recover(
    repository(() =>
      Promise.resolve(Response.json({ outcome: "replay", binding }))
    ),
    caller.signal,
  );
  caller.abort();
  assertEquals(result, { outcome: "replay", binding });
});

Deno.test("IC-1 legacy service credential preserves its existing header policy", async () => {
  const legacy = [
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
    "eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJzZXJ2aWNlX3JvbGUifQ",
    "a".repeat(43),
  ].join(".");
  const repo = new InitialAnalysisLifecycleRepository(
    createInitialAdmissionTransport(origin, legacy, (_url, init) => {
      const headers = new Headers(init?.headers);
      assertEquals(headers.get("apikey"), legacy);
      assertEquals(headers.get("Authorization"), `Bearer ${legacy}`);
      return Promise.resolve(Response.json({ outcome: "replay", binding }));
    }),
    assetReader,
  );
  assertEquals(await recover(repo), { outcome: "replay", binding });
});

Deno.test("IC-1 real RPC response-body deadline cancels a stalled stream", async () => {
  let cancelled = false;
  const body = new ReadableStream<Uint8Array>({
    start(c) {
      c.enqueue(encoder.encode('{"outcome":'));
    },
    cancel() {
      cancelled = true;
    },
  });
  const began = performance.now();
  assertEquals(
    await recover(repository(() => Promise.resolve(new Response(body)))),
    unknown,
  );
  assert(performance.now() - began >= 11_900);
  assert(performance.now() - began < 15_000);
  assert(cancelled);
  assert(!body.locked);
});
