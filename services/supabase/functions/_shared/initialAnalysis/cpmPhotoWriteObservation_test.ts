import { assertEquals, assertRejects } from "@std/assert";
import { createHash } from "node:crypto";
import { initialCanonicalText } from "./canonical.ts";
import { initialMediaHash } from "./mediaBinding.ts";
import {
  CPM_PHOTO_CONTENT_TYPES,
  type CpmWriteObservationBinding,
  type CpmWriteObservationDependencies,
  type CpmWriteObservationTarget,
  observeInitialCpmPhotoWrite,
} from "./cpmPhotoWriteObservation.ts";

async function fixture(marker = false) {
  const id = (n: number) =>
    `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
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
  const backend = { ...config, configuration_digest };
  const binding: CpmWriteObservationBinding = {
    attempt_id: id(1),
    scan_id: id(2),
    object_id: id(3),
    assignment_digest: "a".repeat(64),
    backend_generation: id(4),
    backend_configuration_digest: configuration_digest,
    issued_at_ms: 1000,
    verification_policy_digest: "b".repeat(64),
  };
  const bytes = new Uint8Array([255, 216, 255, 1]);
  const target: CpmWriteObservationTarget = marker
    ? { outcome: "retired_marker" }
    : {
      outcome: "live_object",
      role: "source",
      byte_count: bytes.length,
      content_type: "image/jpeg",
      sha256: await initialMediaHash(bytes),
    };
  const headers = new Headers({
    "content-type": marker ? "application/octet-stream" : "image/jpeg",
    "content-length": marker ? "0" : String(bytes.length),
    "cache-control": "private, no-store",
  });
  if (marker) headers.set("x-amz-meta-merian-state", "erased-v1");
  const controller = new AbortController();
  const requests: Request[] = [];
  let checks = 0;
  const deps: CpmWriteObservationDependencies = {
    requireCurrent: (b, t) => {
      assertEquals(Object.isFrozen(b), true);
      assertEquals(Object.isFrozen(t), true);
      checks++;
      return Promise.resolve();
    },
    sign: (profile, r) => {
      assertEquals(profile, "synthetic_only");
      return Promise.resolve(r);
    },
    fetch: (r) => {
      requests.push(r as Request);
      return Promise.resolve(
        new Response(marker ? new Uint8Array() : bytes.slice(), { headers }),
      );
    },
  };
  return {
    backend,
    binding,
    target,
    bytes,
    headers,
    controller,
    requests,
    deps,
    checks: () => checks,
    run: () =>
      observeInitialCpmPhotoWrite(
        deps,
        binding,
        target,
        backend,
        controller.signal,
      ),
  };
}

for (
  const [role, size] of [
    ["source", 33_554_432],
    ["ai", 5_242_880],
    ["display", 4_194_304],
  ] as const
) {
  Deno.test(`CPM incremental observation covers every byte at the ${role} limit`, async () => {
    const f = await fixture();
    if (f.target.outcome !== "live_object") throw new Error("fixture");
    const chunk = new Uint8Array(65_536);
    const expected = createHash("sha256");
    for (let i = 0; i < size / chunk.length; i++) {
      chunk.fill(i % 251);
      expected.update(chunk);
    }
    f.target.role = role;
    f.target.byte_count = size;
    f.target.sha256 = expected.digest("hex");
    expected.destroy();
    f.headers.set("content-length", String(size));
    let reads = 0;
    const body = new ReadableStream<Uint8Array>({
      pull(c) {
        if (reads === size / chunk.length) return c.close();
        // The next pull mutates the same view: no deferred digest may retain it.
        chunk.fill(reads++ % 251);
        c.enqueue(chunk);
      },
    }, { highWaterMark: 0 });
    f.deps.fetch = () =>
      Promise.resolve(new Response(body, { headers: f.headers }));
    assertEquals((await f.run()).target, f.target);
    assertEquals(reads * chunk.length, size);
    assertEquals(body.locked, false);
    assertEquals(f.checks(), 3);
  });
}

Deno.test("CPM incremental hashing rejects a changed final byte and truncation", async () => {
  for (const variant of ["tail", "short", "extra"] as const) {
    const f = await fixture();
    if (f.target.outcome !== "live_object") throw new Error("fixture");
    const original = new Uint8Array(8192).fill(37);
    f.target.byte_count = original.length;
    f.target.sha256 = await initialMediaHash(original);
    f.headers.set("content-length", String(original.length));
    const first = original.slice(0, 4096);
    const last = variant === "short"
      ? original.slice(4096, -1)
      : original.slice(4096);
    if (variant === "tail") last[last.length - 1] ^= 1;
    const body = new ReadableStream<Uint8Array>({
      start(c) {
        c.enqueue(first);
        c.enqueue(last);
        if (variant === "extra") c.enqueue(new Uint8Array([37]));
        c.close();
      },
    });
    f.deps.fetch = () =>
      Promise.resolve(new Response(body, { headers: f.headers }));
    await assertRejects(f.run);
    assertEquals(f.checks(), 2);
    assertEquals(body.locked, false);
  }
});

Deno.test("CPM incremental reader preserves chunk and consecutive-empty limits", async () => {
  for (const empty of [false, true]) {
    const f = await fixture();
    if (f.target.outcome !== "live_object") throw new Error("fixture");
    const count = empty ? 33 : 4097;
    f.target.byte_count = empty ? 1 : count;
    f.headers.set("content-length", String(f.target.byte_count));
    let reads = 0, cancelled = 0;
    const body = new ReadableStream<Uint8Array>({
      pull(c) {
        reads++;
        c.enqueue(new Uint8Array(empty ? 0 : 1));
      },
      cancel() {
        cancelled++;
      },
    }, { highWaterMark: 0 });
    f.deps.fetch = () =>
      Promise.resolve(new Response(body, { headers: f.headers }));
    await assertRejects(f.run);
    assertEquals(reads, count);
    assertEquals(cancelled, 1);
    assertEquals(f.checks(), 2);
    assertEquals(body.locked, false);
  }
});

Deno.test("CPM abort during a stalled body never reaches the final lifecycle check", async () => {
  const f = await fixture();
  let entered!: () => void;
  const reading = new Promise<void>((r) => entered = r);
  let cancelled = 0;
  const body = new ReadableStream<Uint8Array>({
    pull() {
      entered();
    },
    cancel() {
      cancelled++;
    },
  }, { highWaterMark: 0 });
  f.deps.fetch = () =>
    Promise.resolve(new Response(body, { headers: f.headers }));
  const rejected = assertRejects(f.run);
  await reading;
  f.controller.abort();
  await rejected;
  assertEquals(cancelled, 1);
  assertEquals(body.locked, false);
  assertEquals(f.checks(), 2);
});

for (const role of ["source", "ai", "display"] as const) {
  Deno.test(`CPM ${role} observation reads exact bytes once without write authority`, async () => {
    const f = await fixture();
    if (f.target.outcome === "live_object") f.target.role = role;
    const result = await f.run();
    assertEquals(result, { binding: f.binding, target: f.target });
    assertEquals(Object.isFrozen(result), true);
    assertEquals(f.checks(), 3);
    assertEquals(f.requests.length, 1);
    const r = f.requests[0];
    assertEquals(r.method, "GET");
    assertEquals(r.redirect, "error");
    assertEquals(r.cache, "no-store");
    assertEquals(
      r.url,
      `${f.backend.direct_endpoint}/synthetic-private/initial-preparation/v2/${f.binding.scan_id}/${f.binding.object_id}`,
    );
    assertEquals(r.headers.get("cache-control"), "no-cache, no-store");
  });
}

Deno.test("CPM retired marker requires the exact empty marker, never HEAD/PUT or an absent object", async () => {
  const f = await fixture(true);
  assertEquals((await f.run()).target.outcome, "retired_marker");
  for (
    const variant of [
      "absent",
      "wrong-marker",
      "private-metadata",
      "nonempty",
      "encoded",
    ]
  ) {
    const g = await fixture(true);
    if (variant === "wrong-marker") {
      g.headers.set("x-amz-meta-merian-state", "other");
    }
    if (variant === "private-metadata") {
      g.headers.set("x-amz-meta-sha256", "a".repeat(64));
    }
    if (variant === "encoded") g.headers.set("content-encoding", "identity");
    g.deps.fetch = () =>
      Promise.resolve(
        new Response(variant === "nonempty" ? new Uint8Array([1]) : null, {
          status: variant === "absent" ? 404 : 200,
          headers: g.headers,
        }),
      );
    await assertRejects(g.run);
  }
});

Deno.test("CPM observation rejects wrong bytes, metadata, length and uncertain HTTP without retry", async () => {
  for (
    const variant of [
      "hash",
      "short",
      "long",
      "type",
      "cache",
      "metadata",
      "range",
      "412",
      "404",
      "503",
      "network",
    ]
  ) {
    const f = await fixture();
    let calls = 0;
    if (variant === "type") f.headers.set("content-type", "image/png");
    if (variant === "cache") f.headers.set("cache-control", "public");
    if (variant === "metadata") {
      f.headers.set("x-amz-meta-merian-state", "erased-v1");
    }
    if (variant === "range") f.headers.set("content-range", "bytes 0-3/4");
    f.deps.fetch = () => {
      calls++;
      if (variant === "network") {
        return Promise.reject(new Error("synthetic lost read"));
      }
      return Promise.resolve(
        new Response(
          variant === "hash"
            ? new Uint8Array(4)
            : variant === "short"
            ? new Uint8Array(3)
            : variant === "long"
            ? new Uint8Array(5)
            : f.bytes,
          {
            status: /^\d+$/.test(variant) ? Number(variant) : 200,
            headers: f.headers,
          },
        ),
      );
    };
    await assertRejects(f.run);
    assertEquals(calls, 1);
  }
});

Deno.test("CPM signer cannot change object, method, cache or add conditional/range reads", async () => {
  for (
    const variant of [
      "object",
      "method",
      "cache",
      "if-match",
      "range",
      "x-amz-meta-any",
    ]
  ) {
    const f = await fixture();
    f.deps.sign = (_p, r) => {
      const h = new Headers(r.headers);
      if (variant === "cache") h.set("cache-control", "public");
      if (["if-match", "range", "x-amz-meta-any"].includes(variant)) {
        h.set(variant, "changed");
      }
      return Promise.resolve(
        new Request(variant === "object" ? r.url + "other" : r.url, {
          method: variant === "method" ? "HEAD" : "GET",
          headers: h,
        }),
      );
    };
    await assertRejects(f.run);
    assertEquals(f.requests.length, 0);
  }
});

Deno.test("CPM lifecycle retirement or stale marker claim wins before/after signing and after byte read", async () => {
  for (const marker of [false, true]) {
    for (const failAt of [1, 2, 3]) {
      const f = await fixture(marker);
      let checks = 0;
      f.deps.requireCurrent = () =>
        ++checks === failAt
          ? Promise.reject(new Error("synthetic stale lifecycle"))
          : Promise.resolve();
      await assertRejects(f.run);
      assertEquals(f.requests.length, failAt === 3 ? 1 : 0);
    }
  }
});

Deno.test("CPM observation snapshots caller identities and rejects backend substitution", async () => {
  const f = await fixture();
  const expected = structuredClone({ binding: f.binding, target: f.target });
  const running = f.run();
  f.binding.object_id = "changed";
  f.backend.private_bucket = "changed";
  if (f.target.outcome === "live_object") f.target.sha256 = "0".repeat(64);
  assertEquals(await running, expected);
  const g = await fixture();
  g.backend.private_bucket = "changed";
  await assertRejects(g.run);
  assertEquals(g.checks(), 0);
});

Deno.test("CPM role bounds and closed fields reject before signing", async () => {
  for (
    const [role, limit] of [["source", 33554432], ["ai", 5242880], [
      "display",
      4194304,
    ]] as const
  ) {
    const f = await fixture();
    if (f.target.outcome === "live_object") {
      f.target.role = role;
      f.target.byte_count = limit + 1;
    }
    await assertRejects(f.run);
    assertEquals(f.checks(), 0);
  }
  const f = await fixture();
  Object.assign(f.binding, { extra: true });
  await assertRejects(f.run);
  assertEquals(f.checks(), 0);
});

Deno.test("CPM cancellation rejects a late successful read and cancels its stream", async () => {
  const f = await fixture();
  let enter!: () => void, finish!: (r: Response) => void;
  const entered = new Promise<void>((r) => enter = r);
  let cancelled = false;
  f.deps.fetch = () => {
    enter();
    return new Promise<Response>((r) => finish = r);
  };
  const rejected = assertRejects(f.run);
  await entered;
  f.controller.abort();
  await rejected;
  finish(
    new Response(
      new ReadableStream({
        cancel() {
          cancelled = true;
        },
      }),
      { headers: f.headers },
    ),
  );
  await new Promise((r) => setTimeout(r, 0));
  assertEquals(cancelled, true);
  assertEquals(f.checks(), 2);
});

Deno.test("CPM pre-aborted read never invokes backend signing or storage", async () => {
  const f = await fixture();
  f.controller.abort();
  await assertRejects(f.run);
  assertEquals(f.checks(), 0);
  assertEquals(f.requests.length, 0);
});

Deno.test("CPM signed headers are privately captured before the next lifecycle await", async () => {
  const f = await fixture();
  let signed: Request | undefined;
  f.deps.sign = (_p, r) => {
    signed = r;
    return Promise.resolve(r);
  };
  f.deps.requireCurrent = () => {
    signed?.headers.set("range", "bytes=0-1");
    return Promise.resolve();
  };
  await f.run();
  assertEquals(f.requests[0].headers.has("range"), false);
});

Deno.test("CPM observation preserves source MIME and rejects non-JPEG derivatives before IO", async (t) => {
  for (const role of ["source", "ai", "display"] as const) {
    for (const type of CPM_PHOTO_CONTENT_TYPES) {
      await t.step(`${role} ${type}`, async () => {
        const f = await fixture();
        if (f.target.outcome !== "live_object") throw new Error("fixture");
        f.target.role = role;
        f.target.content_type = type;
        f.headers.set("content-type", type);
        if (role !== "source" && type !== "image/jpeg") {
          await assertRejects(f.run);
          assertEquals(f.requests.length, 0);
          assertEquals(f.checks(), 0);
        } else {
          const result = await f.run();
          assertEquals(result.target, f.target);
          assertEquals(f.requests.length, 1);
          // Metadata vocabulary never permits a mismatched storage response.
          f.headers.set("content-type", "image/gif");
          await assertRejects(f.run);
        }
      });
    }
  }
});

Deno.test("CPM inspection finishes only exact bytes and releases on every reader outcome", async (t) => {
  for (const mode of ["success", "hash", "push", "finish", "shared"] as const) {
    await t.step(mode, async () => {
      const f = await fixture();
      let finished = 0, released = 0, pushed = 0;
      const bytes = mode === "shared"
        ? new Uint8Array(new SharedArrayBuffer(f.bytes.length))
        : f.bytes.slice();
      bytes.set(f.bytes);
      if (mode === "hash") bytes[0] ^= 1;
      const body = new ReadableStream<Uint8Array>({
        start(c) {
          c.enqueue(bytes);
          c.close();
        },
      });
      f.deps.fetch = () =>
        Promise.resolve(new Response(body, { headers: f.headers }));
      const run = () =>
        observeInitialCpmPhotoWrite(
          f.deps,
          f.binding,
          f.target,
          f.backend,
          f.controller.signal,
          () => ({
            push(chunk) {
              pushed += chunk.length;
              if (mode === "push") throw new Error("inspection_failed");
            },
            finish() {
              finished++;
              if (mode === "finish") throw new Error("structure_rejected");
            },
            release() {
              released++;
            },
          }),
        );
      if (mode === "success") await run();
      else await assertRejects(run);
      assertEquals(released, 1);
      assertEquals(finished, ["success", "finish"].includes(mode) ? 1 : 0);
      assertEquals(pushed, mode === "shared" ? 0 : f.bytes.length);
      assertEquals(body.locked, false);
    });
  }
});
