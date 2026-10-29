import { assertEquals, assertRejects } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { initialMediaHash } from "./mediaBinding.ts";
import { initialDeadline } from "./transport.ts";
import {
  type CpmPhotoMarkerDependencies,
  eraseInitialCpmPhotoWrite,
} from "./cpmPhotoMarker.ts";
import {
  type CpmWriteClosureInput,
  type CpmWriteClosureReceipt,
} from "./cpmPhotoWriteClosure.ts";

async function fixture() {
  const id = (n: number) =>
    `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
  const now = Date.now();
  const config = {
    generation: id(4),
    provider: "r2",
    direct_endpoint:
      "https://00000000000000000000000000000000.r2.cloudflarestorage.com",
    private_bucket: "synthetic-private",
    namespace: "initial-preparation/v2",
    credential_profile: "synthetic_only",
    storage_protocol: "conditional_create_permanent_same_key_marker_v1",
  };
  const configuration_digest = await initialMediaHash(new TextEncoder().encode(
    `merian.initial-analysis.media.backend.v1\n${initialCanonicalText(config)}`,
  ));
  const input: CpmWriteClosureInput = {
    binding: {
      attempt_id: id(1),
      scan_id: id(2),
      object_id: id(3),
      assignment_digest: "a".repeat(64),
      backend_generation: id(4),
      backend_configuration_digest: configuration_digest,
      issued_at_ms: now - 1000,
      verification_policy_digest: "b".repeat(64),
    },
    target: { outcome: "retired_marker" },
    backend: { ...config, configuration_digest },
    admission_expires_at_ms: now + 30_000,
    erasure_claim: {
      token: id(5),
      issued_at_ms: now - 100,
      expires_at_ms: now + 59_900,
    },
  };
  const captured = structuredClone(input);
  const markerHeaders = {
    "content-length": "0",
    "content-type": "application/octet-stream",
    "cache-control": "private, no-store",
    "x-amz-meta-merian-state": "erased-v1",
  };
  const calls: string[] = [];
  const controller = new AbortController();
  let saved: CpmWriteClosureReceipt | null = null;
  const deps: CpmPhotoMarkerDependencies = {
    bridge: {
      readReceipt: (attempt, outcome) => {
        calls.push("read");
        assertEquals(attempt, id(1));
        assertEquals(outcome, "retired_marker");
        return Promise.resolve(saved);
      },
      load: () => {
        calls.push("load");
        return Promise.resolve(input);
      },
      requireCurrent: (state) => {
        calls.push("current");
        assertEquals(state, captured);
        for (
          const part of [
            state,
            state.binding,
            state.backend,
            state.target,
            state.erasure_claim,
          ]
        ) {
          assertEquals(Object.isFrozen(part), true);
        }
        return Promise.resolve();
      },
      settle: (receipt, token) => {
        calls.push("settle");
        assertEquals(token, id(5));
        saved = { ...receipt };
        return Promise.resolve(saved);
      },
    },
    signMarker: (profile, request) => {
      calls.push("signMarker");
      assertEquals(profile, "synthetic_only");
      assertEquals(request.method, "PUT");
      return Promise.resolve(request);
    },
    storage: {
      sign: (profile, request) => {
        calls.push("signRead");
        assertEquals(profile, "synthetic_only");
        assertEquals(request.method, "GET");
        return Promise.resolve(request);
      },
      fetch: async (request) => {
        const r = request as Request;
        calls.push(r.method);
        assertEquals(
          r.url,
          `${config.direct_endpoint}/synthetic-private/initial-preparation/v2/${
            id(2)
          }/${id(3)}`,
        );
        assertEquals(r.redirect, "error");
        assertEquals(r.cache, "no-store");
        if (r.method === "PUT") {
          assertEquals(Object.fromEntries(r.headers), markerHeaders);
          assertEquals((await r.arrayBuffer()).byteLength, 0);
          return new Response(null, { status: 200 });
        }
        return new Response(null, { headers: markerHeaders });
      },
    },
  };
  return {
    input,
    captured,
    deps,
    calls,
    controller,
    markerHeaders,
    id,
    save: (receipt: CpmWriteClosureReceipt) => {
      saved = receipt;
    },
    run: () => eraseInitialCpmPhotoWrite(deps, id(1), controller.signal),
  };
}

Deno.test("CPM marker uses one unconditional exact zero-byte PUT then actual observation and settlement", async () => {
  const f = await fixture();
  const result = await f.run();
  assertEquals(result.outcome, "settled");
  assertEquals(
    result.receipt.claim_digest,
    await initialMediaHash(new TextEncoder().encode(
      `merian.initial-analysis.cpm-erasure-claim.v1\n${f.id(5)}`,
    )),
  );
  assertEquals(f.calls, [
    "read",
    "load",
    "current",
    "signMarker",
    "current",
    "PUT",
    "read",
    "current",
    "signRead",
    "current",
    "GET",
    "current",
    "settle",
  ]);
});

Deno.test("CPM marker historical receipt bypasses missing fresh state and all storage", async () => {
  const f = await fixture();
  const receipt: CpmWriteClosureReceipt = {
    attempt_id: f.id(1),
    outcome: "retired_marker",
    policy_digest: "c".repeat(64),
    observed_at: "2026-10-29T10:00:00.123456Z",
    claim_digest: "d".repeat(64),
  };
  f.save(receipt);
  f.deps.bridge.load = () => Promise.reject(new Error("private state erased"));
  assertEquals(await f.run(), { outcome: "replay", receipt });
  assertEquals(f.calls, ["read"]);
});

Deno.test("CPM marker HTTP failure or unknown PUT recovers only through the exact marker read", async (t) => {
  for (const status of [200, 412, 500, "unknown"] as const) {
    await t.step(String(status), async () => {
      const f = await fixture();
      const fetcher = f.deps.storage.fetch;
      f.deps.storage.fetch = (request, init) => {
        if ((request as Request).method !== "PUT") {
          return fetcher(request, init);
        }
        f.calls.push("PUT");
        return status === "unknown"
          ? Promise.reject(new Error("ack lost"))
          : Promise.resolve(new Response(null, { status }));
      };
      assertEquals((await f.run()).outcome, "settled");
      assertEquals(
        f.calls.filter((c) => c === "PUT" || c === "GET" || c === "settle"),
        ["PUT", "GET", "settle"],
      );
    });
  }
});

Deno.test("CPM marker successful PUT without exact zero-byte marker never settles", async (t) => {
  for (const fault of ["missing", "metadata", "bytes", "cache"] as const) {
    await t.step(fault, async () => {
      const f = await fixture();
      const fetcher = f.deps.storage.fetch;
      f.deps.storage.fetch = (request, init) => {
        if ((request as Request).method === "PUT") {
          return fetcher(request, init);
        }
        f.calls.push("GET");
        const h = new Headers(f.markerHeaders);
        if (fault === "metadata") h.set("x-amz-meta-extra", "unexpected");
        if (fault === "cache") h.set("cache-control", "public");
        return Promise.resolve(
          new Response(fault === "bytes" ? new Uint8Array([1]) : null, {
            status: fault === "missing" ? 404 : 200,
            headers: h,
          }),
        );
      };
      await assertRejects(f.run);
      assertEquals(
        f.calls.filter((c) => c === "PUT" || c === "GET" || c === "settle"),
        ["PUT", "GET"],
      );
    });
  }
});

Deno.test("CPM marker refuses signer destination, operation, metadata, condition and body changes before fetch", async (t) => {
  for (
    const change of [
      "key",
      "query",
      "method",
      "copy",
      "condition",
      "metadata",
      "host",
      "body",
      "oversized",
    ] as const
  ) {
    await t.step(change, async () => {
      const f = await fixture();
      f.deps.signMarker = (_profile, request) => {
        const h = new Headers(request.headers);
        if (change === "copy") h.set("x-amz-copy-source", "/another/key");
        if (change === "condition") h.set("If-None-Match", "*");
        if (change === "metadata") h.set("x-amz-meta-other", "unexpected");
        if (change === "host") h.set("host", "different.invalid");
        if (change === "oversized") h.set("authorization", "x".repeat(16_385));
        return Promise.resolve(
          new Request(
            request.url +
              (change === "key"
                ? "/other"
                : change === "query"
                ? "?uploads"
                : ""),
            {
              method: change === "method" ? "DELETE" : "PUT",
              headers: h,
              body: change === "body" ? new Uint8Array([1]) : new Uint8Array(),
            },
          ),
        );
      };
      await assertRejects(f.run);
      assertEquals(f.calls.includes("PUT"), false);
      assertEquals(f.calls.includes("GET"), false);
      assertEquals(f.calls.includes("settle"), false);
    });
  }
});

Deno.test("CPM marker claim replacement before signing, dispatch, GET or settlement cannot settle", async (t) => {
  for (const denial of [1, 2, 3, 4, 5]) {
    await t.step(String(denial), async () => {
      const f = await fixture();
      const check = f.deps.bridge.requireCurrent;
      let n = 0;
      f.deps.bridge.requireCurrent = (input, s) => {
        if (++n === denial) {
          return Promise.reject(new Error("original claim no longer current"));
        }
        return check(input, s);
      };
      await assertRejects(f.run);
      assertEquals(
        f.calls.filter((c) => c === "PUT").length,
        denial >= 3 ? 1 : 0,
      );
      assertEquals(f.calls.includes("GET"), denial === 5);
      assertEquals(f.calls.includes("settle"), false);
    });
  }
});

Deno.test("CPM marker preserves original snapshot and captured signer headers across suspension", async () => {
  const f = await fixture();
  let signed: Request;
  let checks = 0;
  const check = f.deps.bridge.requireCurrent;
  f.deps.signMarker = (_profile, r) => {
    signed = r;
    return Promise.resolve(r);
  };
  f.deps.bridge.requireCurrent = (state, s) => {
    if (++checks === 2) {
      f.input.binding.object_id = f.id(9);
      f.input.erasure_claim!.token = f.id(9);
      f.input.backend.private_bucket = "mutated-bucket";
      signed.headers.set("x-amz-copy-source", "/mutated/key");
    }
    return check(state, s);
  };
  assertEquals((await f.run()).outcome, "settled");
  assertEquals(f.calls.filter((c) => c === "load").length, 1);
});

Deno.test("CPM marker lost settlement acknowledgement reads exact receipt without repeating I/O", async () => {
  const f = await fixture();
  const settle = f.deps.bridge.settle;
  f.deps.bridge.settle = async (receipt, token, s) => {
    await settle(receipt, token, s);
    throw new Error("settlement acknowledgement lost");
  };
  assertEquals((await f.run()).outcome, "replay");
  assertEquals(
    f.calls.filter((c) => c === "PUT" || c === "GET" || c === "settle"),
    ["PUT", "GET", "settle"],
  );
  assertEquals(f.calls.filter((c) => c === "read").length, 3);
});

Deno.test("CPM marker respects short inherited deadline before any signing or storage", async () => {
  const f = await fixture();
  await assertRejects(() =>
    initialDeadline(
      f.controller.signal,
      9900,
      (s) => eraseInitialCpmPhotoWrite(f.deps, f.id(1), s),
    )
  );
  assertEquals(f.calls, ["read", "load"]);
});

Deno.test("CPM marker reserves recovery budget after dispatched PUT timeout and discards late response", async () => {
  const f = await fixture();
  let release!: (response: Response) => void;
  let discarded = false;
  const fetcher = f.deps.storage.fetch;
  f.deps.storage.fetch = (request, init) => {
    if ((request as Request).method !== "PUT") return fetcher(request, init);
    f.calls.push("PUT");
    return new Promise((resolve) => {
      release = resolve;
    });
  };
  const result = await initialDeadline(
    f.controller.signal,
    10_200,
    (s) => eraseInitialCpmPhotoWrite(f.deps, f.id(1), s),
  );
  assertEquals(result.outcome, "settled");
  release(
    new Response(
      new ReadableStream({
        cancel() {
          discarded = true;
        },
      }),
    ),
  );
  await new Promise((resolve) => setTimeout(resolve, 0));
  assertEquals(discarded, true);
  assertEquals(
    f.calls.filter((c) => c === "PUT" || c === "GET" || c === "settle"),
    ["PUT", "GET", "settle"],
  );
});

Deno.test("CPM marker parent cancellation during PUT leaves uncertainty and discards late response", async () => {
  const f = await fixture();
  let release!: (response: Response) => void;
  let discarded = false;
  f.deps.storage.fetch = () => {
    f.calls.push("PUT");
    f.controller.abort();
    return new Promise((resolve) => {
      release = resolve;
    });
  };
  await assertRejects(f.run);
  release(
    new Response(
      new ReadableStream({
        cancel() {
          discarded = true;
        },
      }),
    ),
  );
  await new Promise((resolve) => setTimeout(resolve, 0));
  assertEquals(discarded, true);
  assertEquals(f.calls.includes("GET"), false);
  assertEquals(f.calls.includes("settle"), false);
});

Deno.test("CPM marker cancellation during signing cannot start PUT from a late signature", async () => {
  const f = await fixture();
  let release!: (request: Request) => void;
  let late!: Request;
  let discarded = false;
  f.deps.signMarker = (_profile, request) => {
    late = new Request(request.url, {
      method: "PUT",
      headers: request.headers,
      body: new ReadableStream({
        cancel() {
          discarded = true;
        },
      }),
    });
    f.controller.abort();
    return new Promise((resolve) => {
      release = resolve;
    });
  };
  await assertRejects(f.run);
  release(late);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assertEquals(discarded, true);
  assertEquals(f.calls.includes("PUT"), false);
  assertEquals(f.calls.includes("GET"), false);
});

Deno.test("CPM marker stalled signer body cannot consume recovery budget or start storage", async () => {
  const f = await fixture();
  let discarded = false;
  f.deps.signMarker = (_profile, request) =>
    Promise.resolve(
      new Request(request.url, {
        method: "PUT",
        headers: request.headers,
        body: new ReadableStream({
          cancel() {
            discarded = true;
          },
        }),
      }),
    );
  await assertRejects(() =>
    initialDeadline(
      f.controller.signal,
      10_200,
      (s) => eraseInitialCpmPhotoWrite(f.deps, f.id(1), s),
    )
  );
  assertEquals(discarded, true);
  assertEquals(f.calls.includes("PUT"), false);
  assertEquals(f.calls.includes("GET"), false);
  assertEquals(f.calls.includes("settle"), false);
});

Deno.test("CPM marker refuses malformed historical receipt without falling into fresh work", async () => {
  const f = await fixture();
  f.deps.bridge.readReceipt = () => {
    f.calls.push("read");
    return Promise.resolve({ outcome: "retired_marker" });
  };
  await assertRejects(f.run);
  assertEquals(f.calls, ["read"]);
});

Deno.test("CPM marker rejects live targets and missing or expired original claims before signing", async (t) => {
  for (const invalid of ["live", "missing", "expired"] as const) {
    await t.step(invalid, async () => {
      const f = await fixture();
      if (invalid === "live") {
        f.input.target = {
          outcome: "live_object",
          role: "source",
          byte_count: 4,
          content_type: "image/jpeg",
          sha256: "a".repeat(64),
        };
      }
      if (invalid === "missing") f.input.erasure_claim = null;
      if (invalid === "expired") {
        f.input.erasure_claim = {
          token: f.id(5),
          issued_at_ms: Date.now() - 60_001,
          expires_at_ms: Date.now() - 1,
        };
      }
      await assertRejects(f.run);
      assertEquals(f.calls, ["read", "load"]);
    });
  }
});
