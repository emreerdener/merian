import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { initialMediaHash, type InitialMediaRole } from "./mediaBinding.ts";
import {
  decodeHandoffDestinationBackend,
  decodeHandoffSourceBackend,
  discardHandoffSource,
  type HandoffSourceBackend,
  type HandoffStorageDependencies,
  type HandoffVerifiedObject,
  readHandoffSource,
  retainHandoffDestination,
  verifyHandoffDestination,
} from "./mediaHandoffStorage.ts";
import { initialDeadline } from "./transport.ts";

async function fixture() {
  const scan = "00000000-0000-4000-8000-000000000001";
  const object = "00000000-0000-4000-8000-000000000002";
  const destination = "00000000-0000-4000-8000-000000000003";
  const sourceConfig = {
    generation: "00000000-0000-4000-8000-000000000004",
    provider: "r2",
    direct_endpoint:
      "https://00000000000000000000000000000000.r2.cloudflarestorage.com",
    private_bucket: "synthetic-private",
    namespace: "initial-preparation/v2",
    credential_profile: "synthetic_profile",
    storage_protocol: "conditional_create_permanent_same_key_marker_v1",
  };
  const configuration_digest = await initialMediaHash(
    new TextEncoder().encode(
      `merian.initial-analysis.media.backend.v1\n${
        initialCanonicalText(sourceConfig)
      }`,
    ),
  );
  const rawSource = { ...sourceConfig, configuration_digest };
  const source = await decodeHandoffSourceBackend(
    rawSource,
    sourceConfig.generation,
    configuration_digest,
  );
  const rawDestination = {
    generation: "00000000-0000-4000-8000-000000000005",
    provider: "r2",
    direct_endpoint: sourceConfig.direct_endpoint,
    private_bucket: sourceConfig.private_bucket,
    namespace: "initial-analysis/v1",
    credential_profile: sourceConfig.credential_profile,
  };
  const backend = decodeHandoffDestinationBackend(
    rawDestination,
    rawDestination.generation,
  );
  const bytes = new Uint8Array([255, 216, 255, 1]);
  const role: InitialMediaRole = {
    object_id: object,
    content_type: "image/jpeg",
    byte_count: bytes.length,
    sha256: await initialMediaHash(bytes),
  };
  const target = { ...role, object_id: destination };
  const url = (namespace: string, id: string) =>
    `${sourceConfig.direct_endpoint}/${sourceConfig.private_bucket}/${namespace}/${scan}/${id}`;
  const sourceURL = url(source.namespace, object),
    destinationURL = url(backend.namespace, destination);
  const objects = new Map<string, Uint8Array<ArrayBuffer>>([[
    sourceURL,
    bytes.slice(),
  ]]);
  const calls: string[] = [];
  let fresh = 0;
  const signal = new AbortController().signal;
  const deps: HandoffStorageDependencies = {
    beforeIO: () => {
      fresh++;
      return Promise.resolve();
    },
    sign: (_profile, request) => Promise.resolve(request),
    fetch: async (input) => {
      const r = input as Request;
      calls.push(r.method + " " + r.url);
      if (r.method === "PUT") {
        assertEquals(r.headers.get("if-none-match"), "*");
        if (objects.has(r.url)) return new Response(null, { status: 412 });
        objects.set(r.url, new Uint8Array(await r.arrayBuffer()));
        return new Response(null, { status: 200 });
      }
      const saved = objects.get(r.url);
      if (!saved) return new Response(null, { status: 404 });
      return new Response(saved.slice(), {
        headers: {
          "Content-Type": role.content_type,
          "Content-Length": String(saved.length),
          "Cache-Control": "private, no-store",
        },
      });
    },
  };
  return {
    scan,
    source,
    backend,
    rawSource,
    rawDestination,
    sourceURL,
    destinationURL,
    role,
    target,
    bytes,
    signal,
    objects,
    calls,
    deps,
    fresh: () => fresh,
  };
}

Deno.test("handoff copy retains the verified private snapshot after source overwrite and signer body substitution", async () => {
  const f = await fixture();
  const token = await readHandoffSource(
    f.deps,
    f.source,
    f.scan,
    f.role,
    f.signal,
  );
  f.objects.set(f.sourceURL, new Uint8Array([9, 9, 9, 9]));
  f.deps.sign = (_profile, r) =>
    Promise.resolve(
      r.method === "PUT"
        ? new Request(r.url, {
          method: "PUT",
          headers: r.headers,
          body: new Uint8Array([8, 8, 8, 8]),
        })
        : r,
    );
  await retainHandoffDestination(
    f.deps,
    f.backend,
    f.scan,
    f.target,
    token,
    f.signal,
  );
  assertEquals(f.objects.get(f.destinationURL), f.bytes);
  assertEquals(f.calls, [
    "GET " + f.sourceURL,
    "PUT " + f.destinationURL,
    "GET " + f.destinationURL,
  ]);
  assertEquals(f.fresh(), 6);
  await assertRejects(() =>
    retainHandoffDestination(
      f.deps,
      f.backend,
      f.scan,
      f.target,
      token,
      f.signal,
    )
  );
  assertEquals(f.calls.length, 3);
});
Deno.test("handoff unknown PUT only reads original destination once", async () => {
  const f = await fixture(), original = f.deps.fetch;
  f.deps.fetch = async (input, init) => {
    const response = await original(input, init);
    if ((input as Request).method === "PUT") {
      throw new Error("synthetic lost acknowledgement");
    }
    return response;
  };
  const token = await readHandoffSource(
    f.deps,
    f.source,
    f.scan,
    f.role,
    f.signal,
  );
  await retainHandoffDestination(
    f.deps,
    f.backend,
    f.scan,
    f.target,
    token,
    f.signal,
  );
  assertEquals(f.calls.map((c) => c.split(" ")[0]), ["GET", "PUT", "GET"]);
});
Deno.test("handoff unknown PUT without a matching stored object cannot succeed or repeat", async () => {
  const f = await fixture(), original = f.deps.fetch;
  f.deps.fetch = (input, init) => {
    if ((input as Request).method === "PUT") {
      f.calls.push("PUT " + (input as Request).url);
      throw new Error("synthetic transport");
    }
    return original(input, init);
  };
  const token = await readHandoffSource(
    f.deps,
    f.source,
    f.scan,
    f.role,
    f.signal,
  );
  await assertRejects(() =>
    retainHandoffDestination(
      f.deps,
      f.backend,
      f.scan,
      f.target,
      token,
      f.signal,
    )
  );
  assertEquals(f.calls.map((c) => c.split(" ")[0]), ["GET", "PUT", "GET"]);
});
for (const kind of ["mismatch", "marker"]) {
  Deno.test("handoff never overwrites destination " + kind, async () => {
    const f = await fixture();
    f.objects.set(
      f.destinationURL,
      kind === "marker" ? new Uint8Array() : new Uint8Array([1, 2, 3, 4]),
    );
    const token = await readHandoffSource(
      f.deps,
      f.source,
      f.scan,
      f.role,
      f.signal,
    );
    await assertRejects(() =>
      retainHandoffDestination(
        f.deps,
        f.backend,
        f.scan,
        f.target,
        token,
        f.signal,
      )
    );
    assertEquals(
      f.objects.get(f.destinationURL),
      kind === "marker" ? new Uint8Array() : new Uint8Array([1, 2, 3, 4]),
    );
  });
}
for (const kind of ["fresh", "signer"]) {
  Deno.test(
    "handoff pre-PUT " + kind + " failure starts no readback",
    async () => {
      const f = await fixture(),
        token = await readHandoffSource(
          f.deps,
          f.source,
          f.scan,
          f.role,
          f.signal,
        );
      if (kind === "fresh") {
        f.deps.beforeIO = () => Promise.reject(new Error("synthetic denied"));
      } else f.deps.sign = () => Promise.reject(new Error("synthetic denied"));
      await assertRejects(() =>
        retainHandoffDestination(
          f.deps,
          f.backend,
          f.scan,
          f.target,
          token,
          f.signal,
        )
      );
      assertEquals(f.calls, ["GET " + f.sourceURL]);
    },
  );
}
for (
  const kind of [
    "url",
    "method",
    "conditional",
    "length",
    "metadata",
    "encoding",
  ]
) {
  Deno.test("handoff rejects signer alteration: " + kind, async () => {
    const f = await fixture(),
      token = await readHandoffSource(
        f.deps,
        f.source,
        f.scan,
        f.role,
        f.signal,
      );
    f.deps.sign = (_p, r) => {
      const headers = new Headers(r.headers);
      if (kind === "conditional") headers.delete("if-none-match");
      if (kind === "length") headers.set("content-length", "5");
      if (kind === "metadata") headers.set("x-amz-meta-other", "unexpected");
      if (kind === "encoding") headers.set("content-encoding", "gzip");
      return Promise.resolve(
        new Request(kind === "url" ? r.url + "-changed" : r.url, {
          method: kind === "method" ? "POST" : r.method,
          headers,
        }),
      );
    };
    await assertRejects(() =>
      retainHandoffDestination(
        f.deps,
        f.backend,
        f.scan,
        f.target,
        token,
        f.signal,
      )
    );
    assertEquals(f.calls, ["GET " + f.sourceURL]);
  });
}
for (
  const kind of [
    "type",
    "length",
    "encoding",
    "cache",
    "metadata",
    "truncated",
    "extra",
    "digest",
  ]
) {
  Deno.test(
    "handoff source rejects byte/response mismatch: " + kind,
    async () => {
      const f = await fixture();
      f.deps.fetch = () => {
        const headers = new Headers({
          "Content-Type": "image/jpeg",
          "Content-Length": "4",
          "Cache-Control": "private, no-store",
        });
        if (kind === "type") headers.set("Content-Type", "video/mp4");
        if (kind === "length") headers.set("Content-Length", "5");
        if (kind === "encoding") headers.set("Content-Encoding", "gzip");
        if (kind === "cache") headers.set("Cache-Control", "public");
        if (kind === "metadata") {
          headers.set("x-amz-meta-merian-state", "erased-v1");
        }
        return Promise.resolve(
          new Response(
            kind === "truncated"
              ? f.bytes.slice(0, 3)
              : kind === "extra"
              ? new Uint8Array(5)
              : kind === "digest"
              ? new Uint8Array(4)
              : f.bytes.slice(),
            { headers },
          ),
        );
      };
      await assertRejects(() =>
        readHandoffSource(f.deps, f.source, f.scan, f.role, f.signal)
      );
    },
  );
}
Deno.test("handoff source backend is pinned and privately branded", async () => {
  const f = await fixture();
  await assertRejects(() =>
    decodeHandoffSourceBackend(
      { ...f.rawSource, private_bucket: "changed-bucket" },
      f.source.generation,
      f.source.configuration_digest,
    )
  );
  await assertRejects(() =>
    decodeHandoffSourceBackend(
      { ...f.rawSource, namespace: "initial-analysis/v1" },
      f.source.generation,
      f.source.configuration_digest,
    )
  );
  await assertRejects(() =>
    readHandoffSource(
      f.deps,
      { ...f.source } as HandoffSourceBackend,
      f.scan,
      f.role,
      f.signal,
    )
  );
  assertThrows(() =>
    decodeHandoffDestinationBackend(f.rawSource, f.source.generation)
  );
  assertEquals(f.calls, []);
});
Deno.test("handoff tokens cannot be forged, reused after discard, or cross scan/tuple", async () => {
  const f = await fixture();
  await assertRejects(() =>
    retainHandoffDestination(
      f.deps,
      f.backend,
      f.scan,
      f.target,
      {} as HandoffVerifiedObject,
      f.signal,
    )
  );
  const token = await readHandoffSource(
    f.deps,
    f.source,
    f.scan,
    f.role,
    f.signal,
  );
  await assertRejects(() =>
    retainHandoffDestination(
      f.deps,
      f.backend,
      "00000000-0000-4000-8000-000000000099",
      f.target,
      token,
      f.signal,
    )
  );
  await assertRejects(() =>
    retainHandoffDestination(
      f.deps,
      f.backend,
      f.scan,
      { ...f.target, sha256: "f".repeat(64) },
      token,
      f.signal,
    )
  );
  discardHandoffSource(token);
  await assertRejects(() =>
    retainHandoffDestination(
      f.deps,
      f.backend,
      f.scan,
      f.target,
      token,
      f.signal,
    )
  );
  assertEquals(f.calls, ["GET " + f.sourceURL]);
});
Deno.test("handoff M2 independently GETs and hashes the destination without PUT", async () => {
  const f = await fixture();
  f.objects.set(f.destinationURL, f.bytes.slice());
  await verifyHandoffDestination(f.deps, f.backend, f.scan, f.target, f.signal);
  assertEquals(f.calls, ["GET " + f.destinationURL]);
});
Deno.test("handoff cancellation after unknown PUT cannot start readback", async () => {
  const f = await fixture(),
    controller = new AbortController(),
    original = f.deps.fetch;
  const token = await readHandoffSource(
    f.deps,
    f.source,
    f.scan,
    f.role,
    controller.signal,
  );
  f.deps.fetch = async (input, init) => {
    const response = await original(input, init);
    controller.abort();
    return response;
  };
  await assertRejects(() =>
    retainHandoffDestination(
      f.deps,
      f.backend,
      f.scan,
      f.target,
      token,
      controller.signal,
    )
  );
  assertEquals(f.calls.map((c) => c.split(" ")[0]), ["GET", "PUT"]);
});
Deno.test("handoff late signer ignoring abort cannot initiate fetch", async () => {
  const f = await fixture();
  let release!: (r: Request) => void;
  let request!: Request;
  f.deps.sign = (_p, r) => {
    request = r;
    return new Promise((resolve) => {
      release = resolve;
    });
  };
  await assertRejects(() =>
    initialDeadline(
      f.signal,
      20,
      (signal) => readHandoffSource(f.deps, f.source, f.scan, f.role, signal),
    )
  );
  release(request);
  await new Promise((r) => setTimeout(r, 0));
  assertEquals(f.calls, []);
});

for (const contentType of ["audio/wav", "video/mp4"]) {
  Deno.test(
    "handoff retains exact " + contentType +
      " identity without structural claims",
    async () => {
      const f = await fixture();
      f.role.content_type = contentType;
      f.target.content_type = contentType;
      const token = await readHandoffSource(
        f.deps,
        f.source,
        f.scan,
        f.role,
        f.signal,
      );
      await retainHandoffDestination(
        f.deps,
        f.backend,
        f.scan,
        f.target,
        token,
        f.signal,
      );
      await verifyHandoffDestination(
        f.deps,
        f.backend,
        f.scan,
        f.target,
        f.signal,
      );
      assertEquals(f.objects.get(f.destinationURL), f.bytes);
    },
  );
}
Deno.test("handoff role bounds reject before source I/O", async () => {
  const f = await fixture();
  for (const byte_count of [0, -1, 12_582_913, 1.5, Infinity]) {
    await assertRejects(() =>
      readHandoffSource(
        f.deps,
        f.source,
        f.scan,
        { ...f.role, byte_count },
        f.signal,
      )
    );
  }
  assertEquals(f.calls, []);
});
Deno.test("handoff late fresh fact callback cannot start signing", async () => {
  const f = await fixture();
  let release!: () => void;
  let signed = false;
  f.deps.beforeIO = () =>
    new Promise((resolve) => {
      release = resolve;
    });
  f.deps.sign = (_p, r) => {
    signed = true;
    return Promise.resolve(r);
  };
  await assertRejects(() =>
    initialDeadline(
      f.signal,
      20,
      (signal) => readHandoffSource(f.deps, f.source, f.scan, f.role, signal),
    )
  );
  release();
  await new Promise((r) => setTimeout(r, 0));
  assertEquals(signed, false);
  assertEquals(f.calls, []);
});
Deno.test("handoff late fetch body is discarded after deadline", async () => {
  const f = await fixture();
  let release!: (response: Response) => void;
  let cancelled = false;
  f.deps.fetch = () =>
    new Promise((resolve) => {
      release = resolve;
    });
  await assertRejects(() =>
    initialDeadline(
      f.signal,
      20,
      (signal) => readHandoffSource(f.deps, f.source, f.scan, f.role, signal),
    )
  );
  release(
    new Response(
      new ReadableStream({
        cancel() {
          cancelled = true;
        },
      }),
    ),
  );
  await new Promise((r) => setTimeout(r, 0));
  assertEquals(cancelled, true);
});
