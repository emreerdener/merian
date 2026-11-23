import { assertEquals, assertThrows } from "@std/assert";
import { captureObjectBackendDigest } from "./captureObjectRetirement.ts";
import {
  type CapturePromotionBinding,
  type CapturePromotionStorageDependencies,
  snapshotCapturePromotionBinding,
  transferVerifiedCapturePromotion,
  verifyCapturePromotionDestination,
} from "./capturePromotionStorage.ts";

const backend = {
  endpoint: "https://storage.invalid",
  bucketName: "synthetic",
};
const original = new Uint8Array([1, 2, 3, 4]);
const changed = new Uint8Array([9, 8, 7, 6]);

Deno.test("capture promotion preserves audio MP4 parity and its audio byte ceiling", async () => {
  const f = await fixture("audio/mp4");
  assertEquals(
    await transferVerifiedCapturePromotion(
      f.binding,
      f.deps,
      new AbortController().signal,
    ),
    { outcome: "verified", write: "acknowledged" },
  );
  assertThrows(() =>
    snapshotCapturePromotionBinding({ ...f.binding, byteCount: 2700001 })
  );
  assertEquals(
    snapshotCapturePromotionBinding({ ...f.binding, byteCount: 2700000 })
      .byteCount,
    2700000,
  );
});

Deno.test("capture transfer freezes authorization, signer and fetch dependencies across awaits", async () => {
  const f = await fixture();
  const originalAuthorize = f.deps.authorize;
  const deps = {
    ...f.deps,
    authorize: (
      b: Readonly<CapturePromotionBinding>,
      action: "read_source" | "write_destination" | "read_destination",
      signal: AbortSignal,
    ) => {
      deps.authorize = () => {
        throw new Error("replacement authority used");
      };
      deps.sign = () => {
        throw new Error("replacement signer used");
      };
      deps.fetch = () => {
        throw new Error("replacement fetch used");
      };
      return originalAuthorize(b, action, signal);
    },
  };
  assertEquals(
    await transferVerifiedCapturePromotion(
      f.binding,
      deps,
      new AbortController().signal,
    ),
    { outcome: "verified", write: "acknowledged" },
  );
});
async function fixture(contentType = "image/webp") {
  const sha256 = [
    ...new Uint8Array(await crypto.subtle.digest("SHA-256", original)),
  ]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
  const ownerId = "00000000-0000-4000-8000-000000000001";
  const binding: CapturePromotionBinding = {
    operationId: "00000000-0000-4000-8000-000000000002",
    ownerId,
    scanId: "00000000-0000-4000-8000-000000000003",
    assetId: "00000000-0000-4000-8000-000000000004",
    sessionId: "00000000-0000-4000-8000-000000000005",
    backendSHA256: await captureObjectBackendDigest(backend),
    sourceKey: `staging/${ownerId}/synthetic.webp`,
    destinationKey: `public_uploads/free/${ownerId}/synthetic.webp`,
    byteCount: original.length,
    contentType,
    sha256,
  };
  const events: string[] = [];
  let source = original.slice();
  let target: Uint8Array | null = null;
  let putStatus = 200;
  let unknownPut = false;
  let denied = "";
  let sourceResponse: (() => Response) | null = null;
  let replaceSignerBody = false;
  let alterSignedHeader = false;
  const response = (bytes: Uint8Array) =>
    new Response(bytes.slice(), {
      headers: {
        "Content-Type": binding.contentType,
        "Content-Length": String(binding.byteCount),
      },
    });
  const deps: CapturePromotionStorageDependencies = {
    backend,
    authorize: (saved, action) => {
      events.push(`authorize:${action}`);
      assertEquals(Object.isFrozen(saved), true);
      if (action === denied) throw new Error("synthetic denial");
      // A later staging overwrite cannot change the source snapshot being sent.
      if (action === "write_destination") source = changed.slice();
      return Promise.resolve();
    },
    sign: (request) => {
      events.push(`sign:${request.method}`);
      const headers = new Headers(request.headers);
      if (alterSignedHeader) headers.set("If-None-Match", "incorrect");
      if (request.method === "PUT" && replaceSignerBody) {
        return Promise.resolve(
          new Request(request.url, {
            method: "PUT",
            headers,
            body: changed.slice(),
          }),
        );
      }
      if (request.method === "PUT" && alterSignedHeader) {
        return Promise.resolve(new Request(request, { headers }));
      }
      return Promise.resolve(request);
    },
    fetch: async (input, init) => {
      const request = new Request(input, init);
      events.push(request.method);
      if (request.method === "PUT") {
        assertEquals(request.headers.get("If-None-Match"), "*");
        assertEquals(request.headers.get("x-amz-copy-source"), null);
        assertEquals(request.redirect, "error");
        const bytes = new Uint8Array(await request.arrayBuffer());
        assertEquals(bytes, original);
        if (putStatus === 200) target = bytes;
        if (unknownPut) throw new Error("synthetic unknown write");
        return new Response(null, { status: putStatus });
      }
      if (request.url.endsWith(binding.sourceKey)) {
        return sourceResponse?.() ?? response(source);
      }
      return target ? response(target) : new Response(null, { status: 404 });
    },
  };
  return {
    binding,
    deps,
    events,
    run: (signal = new AbortController().signal) =>
      transferVerifiedCapturePromotion(binding, deps, signal),
    verify: (signal = new AbortController().signal) =>
      verifyCapturePromotionDestination(binding, deps, signal),
    source: (bytes: Uint8Array) => source = new Uint8Array(bytes),
    target: (bytes: Uint8Array) => target = bytes,
    status: (status: number) => putStatus = status,
    unknown: () => unknownPut = true,
    deny: (action: string) => denied = action,
    sourceResponse: (make: () => Response) => sourceResponse = make,
    replaceSignerBody: () => replaceSignerBody = true,
    alterSignedHeader: () => alterSignedHeader = true,
  };
}

Deno.test("capture promotion sends the verified snapshot despite later staging overwrite", async () => {
  const f = await fixture();
  assertEquals(await f.run(), { outcome: "verified", write: "acknowledged" });
  assertEquals(f.events, [
    "authorize:read_source",
    "sign:GET",
    "GET",
    "authorize:write_destination",
    "sign:PUT",
    "PUT",
    "authorize:read_destination",
    "sign:GET",
    "GET",
  ]);
});
Deno.test("capture promotion signer cannot substitute bytes or conditional headers", async () => {
  const f = await fixture();
  f.replaceSignerBody();
  assertEquals(await f.run(), { outcome: "verified", write: "acknowledged" });
  const g = await fixture();
  g.alterSignedHeader();
  assertEquals(await g.run(), { outcome: "held", write: "not_started" });
  assertEquals(g.events.includes("PUT"), false);
});
Deno.test("capture promotion requires actual source digest before any destination write", async () => {
  const f = await fixture();
  f.source(changed);
  assertEquals(await f.run(), { outcome: "held", write: "not_started" });
  assertEquals(f.events, ["authorize:read_source", "sign:GET", "GET"]);
});
Deno.test("capture promotion verifies an existing conditional-write target by bytes", async () => {
  for (const bytes of [original, changed]) {
    const f = await fixture();
    f.status(412);
    f.target(bytes);
    assertEquals(
      await f.run(),
      bytes === original
        ? { outcome: "verified", write: "precondition_failed" }
        : { outcome: "held", write: "acknowledged" },
    );
    assertEquals(f.events.filter((e) => e === "PUT").length, 1);
  }
});
Deno.test("capture promotion holds unknown writes without retry, readback or deletion", async () => {
  for (const status of [200, 500, 403]) {
    const f = await fixture();
    f.status(status);
    if (status === 200) f.unknown();
    assertEquals(await f.run(), { outcome: "held", write: "unknown" });
    assertEquals(f.events.filter((e) => e === "PUT").length, 1);
    assertEquals(f.events.at(-1), "PUT");
  }
});
Deno.test("capture promotion reauthorizes every I/O and holds after merge or retirement denial", async () => {
  for (
    const action of ["read_source", "write_destination", "read_destination"]
  ) {
    const f = await fixture();
    f.deny(action);
    assertEquals(await f.run(), {
      outcome: "held",
      write: action === "read_destination" ? "acknowledged" : "not_started",
    });
    assertEquals(f.events.at(-1), `authorize:${action}`);
  }
});
Deno.test("capture promotion rejects malformed bindings and backend drift before authorization", async () => {
  const variants = [
    { backendSHA256: "0".repeat(64) },
    { byteCount: 0 },
    { byteCount: 12 * 1024 * 1024 },
    { contentType: "text/plain" },
    { sha256: "not a digest" },
    { operationId: "bad" },
    { sourceKey: "staging/foreign/file" },
    { destinationKey: "public_uploads/free/foreign/file" },
  ];
  for (const variant of variants) {
    const f = await fixture();
    assertEquals(
      await transferVerifiedCapturePromotion(
        { ...f.binding, ...variant },
        f.deps,
        new AbortController().signal,
      ),
      { outcome: "held", write: "not_started" },
    );
    assertEquals(f.events, []);
  }
});
Deno.test("capture promotion rejects actual stream overflow, short content and encoded bodies", async () => {
  for (const variant of ["overflow", "short", "encoding", "type", "length"]) {
    const f = await fixture();
    f.sourceResponse(() =>
      new Response(
        variant === "overflow"
          ? new Uint8Array(5)
          : original.slice(variant === "short" ? 1 : 0),
        {
          headers: {
            "Content-Length": variant === "length" ? "5" : "4",
            "Content-Type": variant === "type" ? "image/jpeg" : "image/webp",
            ...(variant === "encoding" ? { "Content-Encoding": "gzip" } : {}),
          },
        },
      )
    );
    assertEquals(await f.run(), { outcome: "held", write: "not_started" });
    assertEquals(f.events.includes("PUT"), false);
  }
});
Deno.test("capture promotion aborts a stalled authorization without advancing on its late reply", async () => {
  const f = await fixture(), controller = new AbortController();
  let release!: () => void;
  let entered!: () => void;
  const arrival = new Promise<void>((resolve) => entered = resolve);
  f.deps.authorize = () =>
    new Promise<void>((resolve) => {
      release = resolve;
      entered();
    });
  const running = f.run(controller.signal);
  await arrival;
  controller.abort();
  assertEquals(await running, { outcome: "held", write: "not_started" });
  release();
  await Promise.resolve();
  assertEquals(f.events, []);
});
Deno.test("capture promotion freezes the complete binding before an awaited callback", async () => {
  const f = await fixture();
  const originalAuthorize = f.deps.authorize;
  f.deps.authorize = (binding, action, signal) => {
    assertEquals(binding.destinationKey.endsWith("synthetic.webp"), true);
    Object.assign(f.binding, {
      destinationKey: `public_uploads/free/${f.binding.ownerId}/changed.webp`,
    });
    return originalAuthorize(binding, action, signal);
  };
  assertEquals(await f.run(), { outcome: "verified", write: "acknowledged" });
});

Deno.test("capture promotion rejects signer-added storage semantics before PUT", async () => {
  for (
    const header of [
      "x-amz-acl",
      "x-amz-tagging",
      "x-amz-object-lock-mode",
      "x-amz-website-redirect-location",
      "x-amz-server-side-encryption",
      "x-amz-meta-owner",
      "x-amz-copy-source",
      "content-encoding",
    ]
  ) {
    const f = await fixture();
    f.deps.sign = (request) => {
      if (request.method !== "PUT") return Promise.resolve(request);
      const headers = new Headers(request.headers);
      headers.set(header, "synthetic");
      return Promise.resolve(new Request(request, { headers }));
    };
    assertEquals(await f.run(), { outcome: "held", write: "not_started" });
    assertEquals(f.events.includes("PUT"), false);
  }
});
Deno.test("capture promotion 200 does not claim the destination was newly created", async () => {
  const f = await fixture();
  f.target(changed);
  // This hostile transport overwrites regardless of If-None-Match. The result
  // reports only acknowledgement and exact readback, never create authority.
  assertEquals(await f.run(), { outcome: "verified", write: "acknowledged" });
});
Deno.test("capture promotion cancels late signed bodies after caller abort", async () => {
  const f = await fixture(), controller = new AbortController();
  let release!: (request: Request) => void;
  let entered!: () => void, cancelled!: () => void;
  let requestUrl = "";
  const arrival = new Promise<void>((resolve) => entered = resolve);
  const cancellation = new Promise<void>((resolve) => cancelled = resolve);
  f.deps.sign = (request) => {
    requestUrl = request.url;
    return new Promise<Request>((resolve) => {
      release = resolve;
      entered();
    });
  };
  const run = f.run(controller.signal);
  await arrival;
  controller.abort();
  assertEquals(await run, { outcome: "held", write: "not_started" });
  release(
    new Request(requestUrl, {
      method: "POST",
      body: new ReadableStream({ cancel: () => cancelled() }),
    }),
  );
  await cancellation;
  assertEquals(f.events, ["authorize:read_source"]);
});
Deno.test("capture promotion holds aborted PUT and cancels its late response without retry", async () => {
  const f = await fixture(), controller = new AbortController();
  const originalFetch = f.deps.fetch;
  let release!: (response: Response) => void;
  let entered!: () => void, cancelled!: () => void;
  const arrival = new Promise<void>((resolve) => entered = resolve);
  const cancellation = new Promise<void>((resolve) => cancelled = resolve);
  f.deps.fetch = (input, init) => {
    const request = new Request(input, init);
    if (request.method !== "PUT") return originalFetch(request);
    f.events.push("PUT");
    void request.body?.cancel();
    return new Promise<Response>((resolve) => {
      release = resolve;
      entered();
    });
  };
  const run = f.run(controller.signal);
  await arrival;
  controller.abort();
  assertEquals(await run, { outcome: "held", write: "unknown" });
  release(new Response(new ReadableStream({ cancel: () => cancelled() })));
  await cancellation;
  assertEquals(f.events.at(-1), "PUT");
});

Deno.test("capture recovery verifies an unknown write without reading overwritten staging or issuing another PUT", async () => {
  const f = await fixture();
  f.unknown();
  assertEquals(await f.run(), { outcome: "held", write: "unknown" });
  f.events.length = 0;
  f.source(changed);
  assertEquals(await f.verify(), { outcome: "verified" });
  assertEquals(f.events, ["authorize:read_destination", "sign:GET", "GET"]);
});

Deno.test("capture recovery holds absent and mismatched destinations without writing or erasing", async () => {
  for (const target of [null, changed]) {
    const f = await fixture();
    if (target) f.target(target);
    assertEquals(await f.verify(), { outcome: "held" });
    assertEquals(f.events, ["authorize:read_destination", "sign:GET", "GET"]);
  }
});

Deno.test("capture recovery requires fresh authority and exact backend before signing", async () => {
  const f = await fixture();
  f.target(original);
  f.deny("read_destination");
  assertEquals(await f.verify(), { outcome: "held" });
  assertEquals(f.events, ["authorize:read_destination"]);
  const g = await fixture();
  Object.assign(g.binding, { backendSHA256: "b".repeat(64) });
  assertEquals(await g.verify(), { outcome: "held" });
  assertEquals(g.events, []);
});

Deno.test("capture recovery validates actual destination stream and transport semantics", async () => {
  for (const variant of ["oversize", "short", "encoded", "mime", "status"]) {
    const f = await fixture();
    f.deps.fetch = () =>
      Promise.resolve(
        new Response(
          variant === "oversize"
            ? new Uint8Array(5)
            : variant === "short"
            ? new Uint8Array(3)
            : original.slice(),
          {
            status: variant === "status" ? 206 : 200,
            headers: {
              "content-type": variant === "mime"
                ? "image/png"
                : f.binding.contentType,
              "content-length": String(f.binding.byteCount),
              ...(variant === "encoded" ? { "content-encoding": "gzip" } : {}),
            },
          },
        ),
      );
    assertEquals(await f.verify(), { outcome: "held" });
    assertEquals(f.events, ["authorize:read_destination", "sign:GET"]);
  }
});

Deno.test("capture recovery preabort does no I/O and late fetch responses are cancelled", async () => {
  const first = await fixture();
  const aborted = new AbortController();
  aborted.abort();
  assertEquals(await first.verify(aborted.signal), { outcome: "held" });
  assertEquals(first.events, []);
  const f = await fixture();
  const controller = new AbortController();
  let finish: (value: Response) => void = () => {};
  let cancelled = false;
  f.deps.fetch = () => {
    const pending = new Promise<Response>((resolve) => finish = resolve);
    queueMicrotask(() => controller.abort());
    return pending;
  };
  assertEquals(await f.verify(controller.signal), { outcome: "held" });
  finish(
    new Response(
      new ReadableStream({
        cancel: () => {
          cancelled = true;
        },
      }),
    ),
  );
  await new Promise((resolve) => setTimeout(resolve, 0));
  assertEquals(cancelled, true);
  assertEquals(f.events, ["authorize:read_destination", "sign:GET"]);
});
