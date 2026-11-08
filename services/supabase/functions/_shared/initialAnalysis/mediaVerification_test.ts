import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import vectors from "./fixtures/admission-v1.json" with { type: "json" };
import { initialCanonicalText, initialDigest } from "./canonical.ts";
import { type InitialInput } from "./semantics.ts";
import {
  type InitialMediaBinding,
  type InitialMediaBuffers,
  initialMediaHash,
  snapshotInitialMedia,
} from "./mediaBinding.ts";
import {
  eraseOneInitialMediaObject,
  type InitialMediaDependencies,
  type InitialMediaOperation,
  verifyAndRetainInitialMedia,
} from "./mediaVerification.ts";

async function fixture(count = 1) {
  const input = structuredClone(
    vectors.valid[0].input,
  ) as unknown as InitialInput;
  if (count) {
    input.route = "identify-multimodal";
    input.ordered_descriptions = ["Synthetic media"];
  }
  const buffers: InitialMediaBuffers[] = [];
  for (let i = 0; i < count; i++) {
    const bytes = new Uint8Array([255, 216, 255, i]);
    const hash = await initialMediaHash(bytes);
    input.media.push({
      kind: "image",
      content_type: "image/jpeg",
      source_content_type: "image/jpeg",
      byte_count: 4,
      source_byte_count: 4,
      sha256: hash,
      source_sha256: hash,
      input_index: i,
      source_index: i,
      clip_index: null,
      frame_index: null,
      focus_region: null,
      transform: "identity_v1",
      transform_parameters: null,
    });
    input.owner_timeline.push({ kind: "media", index: i });
    buffers.push({ source: bytes, prepared: bytes.slice() });
  }
  const scope = {
    owner_id: crypto.randomUUID(),
    scan_id: crypto.randomUUID(),
    submission_digest: await initialDigest(
      "input",
      initialCanonicalText(input),
    ),
  };
  const manifest = {
    version: 1 as const,
    ...scope,
    backend_generation: crypto.randomUUID(),
    expires_at: Date.now() + 300_000,
    items: input.media.map((item, index) => {
      const role = {
        object_id: crypto.randomUUID(),
        content_type: item.content_type,
        byte_count: item.byte_count,
        sha256: item.sha256,
      };
      return { index, input: item, source: role, prepared: role };
    }),
  };
  const binding: InitialMediaBinding = {
    ...manifest,
    manifest_digest: await initialMediaHash(
      new TextEncoder().encode(
        `merian.initial-analysis.media-allocation.v1\n${
          initialCanonicalText(manifest)
        }`,
      ),
    ),
  };
  const backend = {
    generation: binding.backend_generation,
    provider: "r2",
    direct_endpoint:
      "https://00000000000000000000000000000000.r2.cloudflarestorage.com",
    private_bucket: "synthetic-private",
    namespace: "initial-analysis/v1",
    credential_profile: "synthetic_profile",
  };
  const calls: InitialMediaOperation[] = [];
  const requests: { url: string; method: string; headers: Headers }[] = [];
  const objects = new Map<
    string,
    { bytes: Uint8Array<ArrayBuffer>; headers: Headers }
  >();
  const receipt = {
    version: 1,
    ...scope,
    manifest_digest: binding.manifest_digest,
    backend_generation: binding.backend_generation,
    verified_at: Date.now(),
  };
  let verified = false;
  const deps: InitialMediaDependencies = {
    sign: (_profile, _purpose, request) => Promise.resolve(request),
    call: (op) => {
      calls.push(op);
      if (op === "get_initial_media_backend") {
        return Promise.resolve({ version: 1, outcome: "resolved", backend });
      }
      if (op === "claim_initial_media_preparation") {
        return Promise.resolve({
          version: 1,
          outcome: "claimed",
          binding,
          claim: {
            token: crypto.randomUUID(),
            issued_at: Date.now(),
            expires_at: Date.now() + 59_000,
          },
        });
      }
      if (op === "settle_initial_media_verification") {
        verified = true;
        return Promise.resolve({ version: 1, outcome: "verified", receipt });
      }
      if (op === "get_initial_media_verification") {
        return Promise.resolve(
          verified
            ? { version: 1, outcome: "replay", receipt }
            : { version: 1, outcome: "held", reason: "missing" },
        );
      }
      if (op === "claim_initial_analysis_media_erasure") {
        return Promise.resolve({
          version: 1,
          outcome: "claimed",
          object: {
            scan_id: scope.scan_id,
            object_id: binding.items[0].source.object_id,
            backend_generation: binding.backend_generation,
            claim_token: crypto.randomUUID(),
            claim_expires_at: Date.now() + 59_000,
          },
        });
      }
      return Promise.resolve({ version: 1, outcome: "acknowledged" });
    },
    fetch: async (request, options) => {
      assert(request instanceof Request);
      assertEquals(options?.redirect, "error");
      assertEquals(options?.cache, "no-store");
      requests.push({
        url: request.url,
        method: request.method,
        headers: request.headers,
      });
      if (request.method === "PUT") {
        if (
          request.headers.get("if-none-match") === "*" &&
          objects.has(request.url)
        ) return new Response(null, { status: 412 });
        const bytes = new Uint8Array(await request.arrayBuffer());
        const headers = new Headers({
          "content-type": request.headers.get("content-type")!,
          "cache-control": request.headers.get("cache-control")!,
          "content-length": String(bytes.length),
        });
        if (request.headers.has("x-amz-meta-merian-state")) {
          headers.set(
            "x-amz-meta-merian-state",
            request.headers.get("x-amz-meta-merian-state")!,
          );
        }
        objects.set(request.url, { bytes, headers });
        return new Response(null, { status: 200 });
      }
      const saved = objects.get(request.url);
      return saved
        ? new Response(saved.bytes.slice(), { headers: saved.headers })
        : new Response(null, { status: 404 });
    },
  };
  const controller = new AbortController();
  const run = () =>
    verifyAndRetainInitialMedia(
      deps,
      binding,
      input,
      scope,
      buffers,
      controller.signal,
    );
  return {
    input,
    binding,
    scope,
    buffers,
    backend,
    calls,
    requests,
    objects,
    receipt,
    deps,
    controller,
    run,
  };
}
Deno.test("M2 entire cohort uses original conditional destinations and exact GET", async () => {
  const f = await fixture(2);
  assertEquals((await f.run()).outcome, "verified");
  assertEquals(f.requests.map((r) => r.method), ["PUT", "GET", "PUT", "GET"]);
  assert(
    f.requests.filter((r) => r.method === "PUT").every((r) =>
      r.headers.get("if-none-match") === "*"
    ),
  );
  assertEquals(f.calls, [
    "claim_initial_media_preparation",
    "get_initial_media_backend",
    "settle_initial_media_verification",
  ]);
});
Deno.test("M2 empty text cohort has no physical storage request", async () => {
  const f = await fixture(0);
  assertEquals((await f.run()).outcome, "verified");
  assertEquals(f.requests, []);
});
Deno.test("M2 copies both original roles and binding before caller mutation", async () => {
  const f = await fixture();
  const original = structuredClone(f.binding);
  const call = f.deps.call;
  f.deps.call = (op, args, signal) =>
    op === "claim_initial_media_preparation"
      ? Promise.resolve({
        version: 1,
        outcome: "claimed",
        binding: original,
        claim: {
          token: crypto.randomUUID(),
          issued_at: Date.now(),
          expires_at: Date.now() + 59_000,
        },
      })
      : call(op, args, signal);
  const pending = f.run();
  f.buffers[0].source.fill(0);
  f.buffers[0].prepared!.fill(1);
  f.input.ordered_descriptions[0] = "changed";
  f.binding.items[0].source.sha256 = "b".repeat(64);
  assertEquals((await pending).outcome, "verified");
  assertEquals(
    [...f.objects.values()][0].bytes,
    new Uint8Array([255, 216, 255, 0]),
  );
});
for (
  const change of [
    "extra",
    "owner",
    "index",
    "tuple",
    "object",
    "oversize",
    "alias",
    "container",
  ]
) {
  Deno.test(`M2 pre-copy rejects ${change}`, async () => {
    const f = await fixture(2);
    const b = f.binding as unknown as Record<string, unknown>;
    if (change === "extra") b.extra = true;
    if (change === "owner") b.owner_id = crypto.randomUUID();
    if (change === "index") f.binding.items[0].index = 1;
    if (change === "tuple") f.binding.items[0].source.byte_count = 3;
    if (change === "object") {
      f.binding.items[1].source.object_id = f.binding.items[0].source.object_id;
    }
    if (change === "oversize") f.buffers[0].source = new Uint8Array(1024);
    if (change === "alias") f.buffers[0].prepared![3] = 99;
    if (change === "container") {
      f.buffers[0].source.fill(0);
      f.buffers[0].prepared!.fill(0);
    }
    assertThrows(() =>
      snapshotInitialMedia(f.binding, f.input, f.scope, f.buffers)
    );
    assertEquals(f.calls, []);
  });
}
Deno.test("M2 invalid digest cannot claim or retain", async () => {
  const f = await fixture();
  f.binding.manifest_digest = "a".repeat(64);
  await assertRejects(f.run);
  assertEquals(f.calls, []);
});
for (
  const reason of [
    "busy",
    "retired",
    "expired",
    "disabled",
    "in_use",
    "missing",
  ]
) {
  Deno.test(`M2 held ${reason} supplies no storage authority`, async () => {
    const f = await fixture();
    f.deps.call = () =>
      Promise.resolve({ version: 1, outcome: "held", reason });
    assertEquals((await f.run()).outcome, "held");
    assertEquals(f.requests, []);
  });
}
Deno.test("M2 replay supplies known receipt but no storage authority", async () => {
  const f = await fixture();
  f.deps.call = () =>
    Promise.resolve({ version: 1, outcome: "replay", receipt: f.receipt });
  assertEquals((await f.run()).outcome, "replay");
  assertEquals(f.requests, []);
});
Deno.test("M2 insufficient remaining claim preserves settlement reserve", async () => {
  const f = await fixture();
  f.deps.call = () =>
    Promise.resolve({
      version: 1,
      outcome: "claimed",
      binding: f.binding,
      claim: {
        token: crypto.randomUUID(),
        issued_at: Date.now(),
        expires_at: Date.now() + 4999,
      },
    });
  assertEquals(await f.run(), {
    version: 1,
    outcome: "held",
    reason: "budget",
  });
  assertEquals(f.requests, []);
});
for (
  const field of [
    "generation",
    "direct_endpoint",
    "private_bucket",
    "namespace",
    "credential_profile",
    "extra",
  ]
) {
  Deno.test(`M2 rejects malformed backend ${field}`, async () => {
    const f = await fixture();
    (f.backend as unknown as Record<string, unknown>)[field] = "invalid/value";
    await assertRejects(f.run);
    assertEquals(f.requests, []);
  });
}
Deno.test("M2 unknown PUT recovers exactly once from the same object", async () => {
  const f = await fixture();
  const fetch = f.deps.fetch;
  f.deps.fetch = async (request, init) => {
    const r = await fetch(request, init);
    if ((request as Request).method === "PUT") {
      throw Error("synthetic lost reply");
    }
    return r;
  };
  assertEquals((await f.run()).outcome, "verified");
  assertEquals(f.requests.map((r) => r.method), ["PUT", "GET"]);
});
Deno.test("M2 lost settlement reads receipt without repeating storage or claim", async () => {
  const f = await fixture();
  const call = f.deps.call;
  f.deps.call = async (op, args, signal) => {
    const r = await call(op, args, signal);
    if (op === "settle_initial_media_verification") {
      throw Error("synthetic lost reply");
    }
    return r;
  };
  assertEquals((await f.run()).outcome, "replay");
  assertEquals(f.calls, [
    "claim_initial_media_preparation",
    "get_initial_media_backend",
    "settle_initial_media_verification",
    "get_initial_media_verification",
  ]);
  assertEquals(f.requests.length, 2);
});
for (
  const fault of ["bytes", "extra-byte", "encoding", "metadata", "partial"]
) {
  Deno.test(`M2 no receipt for actual retained ${fault} mismatch`, async () => {
    const f = await fixture(2);
    const fetch = f.deps.fetch;
    let reads = 0;
    f.deps.fetch = async (req, init) => {
      const response = await fetch(req, init);
      if ((req as Request).method !== "GET") return response;
      reads++;
      if (fault === "partial" && reads === 1) return response;
      const headers = new Headers(response.headers);
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (fault === "encoding") headers.set("content-encoding", "gzip");
      else if (fault === "metadata") {
        headers.set(
          "x-amz-meta-old-private-digest",
          "synthetic",
        );
      } else bytes[3] = 99;
      return new Response(
        fault === "extra-byte" ? new Uint8Array([...bytes, 0]) : bytes,
        { headers },
      );
    };
    await assertRejects(f.run);
    assert(!f.calls.includes("settle_initial_media_verification"));
  });
}
Deno.test("M2 marker before late create prevents resurrection", async () => {
  const f = await fixture();
  await eraseOneInitialMediaObject(f.deps, f.controller.signal);
  await assertRejects(f.run);
  assertEquals([...f.objects.values()][0].bytes.length, 0);
  assert(!f.calls.includes("settle_initial_media_verification"));
});
Deno.test("M2 marker after write removes bytes and metadata before acknowledgement", async () => {
  const f = await fixture();
  await f.run();
  assertEquals(
    await eraseOneInitialMediaObject(f.deps, f.controller.signal),
    "acknowledged",
  );
  const saved = [...f.objects.values()][0];
  assertEquals(saved.bytes.length, 0);
  assertEquals(saved.headers.get("x-amz-meta-merian-state"), "erased-v1");
  assertEquals(f.calls.at(-1), "finish_initial_analysis_media_erasure");
});
for (
  const fault of ["marker", "length", "type", "cache", "encoding", "extra"]
) {
  Deno.test(`M2 cleanup rejects wrong marker ${fault} without acknowledgement`, async () => {
    const f = await fixture();
    const fetch = f.deps.fetch;
    f.deps.fetch = async (req, init) => {
      const r = await fetch(req, init);
      if ((req as Request).method !== "GET") return r;
      const headers = new Headers(r.headers);
      await r.arrayBuffer();
      const key = {
        marker: "x-amz-meta-merian-state",
        length: "content-length",
        type: "content-type",
        cache: "cache-control",
        encoding: "content-encoding",
        extra: "x-amz-meta-old-private-digest",
      }[fault]!;
      headers.set(key, "wrong");
      return new Response(new Uint8Array(), { headers });
    };
    await assertRejects(() =>
      eraseOneInitialMediaObject(f.deps, f.controller.signal)
    );
    assert(!f.calls.includes("finish_initial_analysis_media_erasure"));
  });
}
Deno.test("M2 abort discards late fetch and never settles", async () => {
  const f = await fixture();
  let release!: (r: Response) => void;
  let started!: () => void;
  const began = new Promise<void>((resolve) => started = resolve);
  const fetch = f.deps.fetch;
  f.deps.fetch = (req, init) =>
    (req as Request).method === "GET"
      ? (started(), new Promise((resolve) => release = resolve))
      : fetch(req, init);
  const pending = f.run();
  await began;
  f.controller.abort();
  await assertRejects(() => pending);
  release(new Response(new Uint8Array([255, 216, 255, 0])));
  await Promise.resolve();
  assert(!f.calls.includes("settle_initial_media_verification"));
});
Deno.test("M2 signer cannot redirect private bytes", async () => {
  const f = await fixture();
  f.deps.sign = () =>
    Promise.resolve(new Request("https://example.invalid/wrong"));
  await assertRejects(f.run);
  assertEquals(f.requests, []);
});
Deno.test("M2 empty and stale cleanup are not affirmative marker confirmation", async () => {
  const f = await fixture();
  const call = f.deps.call;
  f.deps.call = (op, args, signal) =>
    op === "finish_initial_analysis_media_erasure"
      ? Promise.resolve({ version: 1, outcome: "stale" })
      : call(op, args, signal);
  assertEquals(
    await eraseOneInitialMediaObject(f.deps, f.controller.signal),
    "stale",
  );
  f.deps.call = () => Promise.resolve({ version: 1, outcome: "empty" });
  assertEquals(
    await eraseOneInitialMediaObject(f.deps, f.controller.signal),
    "empty",
  );
});
Deno.test("M2 bounds actual empty-chunk stream work without receipt", async () => {
  const f = await fixture();
  const fetch = f.deps.fetch;
  f.deps.fetch = async (req, init) => {
    const r = await fetch(req, init);
    if ((req as Request).method !== "GET") return r;
    await r.arrayBuffer();
    return new Response(
      new ReadableStream({
        pull(c) {
          c.enqueue(new Uint8Array());
        },
      }),
      { headers: r.headers },
    );
  };
  await assertRejects(f.run);
  assert(!f.calls.includes("settle_initial_media_verification"));
});
Deno.test("M2 unknown cleanup acknowledgement is not repeated or inferred", async () => {
  const f = await fixture();
  const call = f.deps.call;
  f.deps.call = (op, args, signal) => {
    if (op === "finish_initial_analysis_media_erasure") {
      f.calls.push(op);
      throw Error("synthetic lost ack");
    }
    return call(op, args, signal);
  };
  await assertRejects(() =>
    eraseOneInitialMediaObject(f.deps, f.controller.signal)
  );
  assertEquals(
    f.calls.filter((x) => x === "finish_initial_analysis_media_erasure").length,
    1,
  );
});
Deno.test("M2 preserves distinct WAV source/prepared objects and source-only MP4", async () => {
  const f = await fixture(0);
  f.input.route = "identify-multimodal";
  f.input.ordered_descriptions = ["Synthetic clips"];
  const wav = new Uint8Array(48), view = new DataView(wav.buffer);
  wav.set(new TextEncoder().encode("RIFF"));
  view.setUint32(4, 40, true);
  wav.set(new TextEncoder().encode("WAVEfmt "), 8);
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, 16000, true);
  view.setUint32(28, 32000, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  wav.set(new TextEncoder().encode("data"), 36);
  view.setUint32(40, 4, true);
  const prepared = wav.slice();
  prepared[44] = 1;
  const video = new Uint8Array(16);
  new DataView(video.buffer).setUint32(0, 16);
  video.set(new TextEncoder().encode("ftypisom"), 4);
  for (const [index, bytes] of [wav, video].entries()) {
    const kind = index === 0 ? "audio" : "video",
      type = index === 0 ? "audio/wav" : "video/mp4";
    const consumed = index === 0 ? prepared : bytes;
    const item = {
      kind,
      content_type: type,
      source_content_type: type,
      byte_count: consumed.length,
      source_byte_count: bytes.length,
      sha256: await initialMediaHash(consumed),
      source_sha256: await initialMediaHash(bytes),
      input_index: index === 0 ? 0 : null,
      source_index: index === 0 ? 0 : null,
      clip_index: index === 0 ? null : 0,
      frame_index: null,
      focus_region: null,
      transform: index === 0 ? "initial_audio_v1" : "identity_v1",
      transform_parameters: index === 0
        ? { target_sample_rate: 16000, preserve_short_video_context: false }
        : null,
    } as InitialInput["media"][number];
    f.input.media.push(item);
    f.input.owner_timeline.push({ kind: "media", index });
    f.buffers.push({ source: bytes, prepared: index === 0 ? prepared : null });
    f.binding.items.push({
      index,
      input: item,
      source: {
        object_id: crypto.randomUUID(),
        content_type: type,
        byte_count: bytes.length,
        sha256: item.source_sha256,
      },
      prepared: index === 0
        ? {
          object_id: crypto.randomUUID(),
          content_type: type,
          byte_count: consumed.length,
          sha256: item.sha256,
        }
        : null,
    });
  }
  f.input.capture = {
    has_video: true,
    video_clip_count: 1,
    declared_video_frame_count: 0,
    video_inference_frame_count: 0,
  };
  f.scope.submission_digest = await initialDigest(
    "input",
    initialCanonicalText(f.input),
  );
  f.binding.submission_digest = f.scope.submission_digest;
  const { manifest_digest: _, ...manifest } = f.binding;
  void _;
  f.binding.manifest_digest = await initialMediaHash(
    new TextEncoder().encode(
      `merian.initial-analysis.media-allocation.v1\n${
        initialCanonicalText(manifest)
      }`,
    ),
  );
  f.receipt.submission_digest = f.scope.submission_digest;
  f.receipt.manifest_digest = f.binding.manifest_digest;
  assertEquals((await f.run()).outcome, "verified");
  assertEquals(f.objects.size, 3);
  assertEquals(f.requests.map((r) => r.method), [
    "PUT",
    "GET",
    "PUT",
    "GET",
    "PUT",
    "GET",
  ]);
});
Deno.test("M2 checks signature on retained copy after source changes in copy window", async () => {
  const f = await fixture(2);
  const invalid = new Uint8Array(4), hash = await initialMediaHash(invalid);
  f.input.media[0].sha256 = hash;
  f.input.media[0].source_sha256 = hash;
  f.binding.items[0].source.sha256 = hash;
  f.binding.items[0].prepared!.sha256 = hash;
  f.scope.submission_digest = await initialDigest(
    "input",
    initialCanonicalText(f.input),
  );
  f.binding.submission_digest = f.scope.submission_digest;
  const { manifest_digest: _, ...manifest } = f.binding;
  void _;
  f.binding.manifest_digest = await initialMediaHash(
    new TextEncoder().encode(
      `merian.initial-analysis.media-allocation.v1\n${
        initialCanonicalText(manifest)
      }`,
    ),
  );
  f.receipt.submission_digest = f.scope.submission_digest;
  f.receipt.manifest_digest = f.binding.manifest_digest;
  // Deterministically simulate a concurrent shared-buffer mutation after the
  // first role's signature/alias checks, before the cohort's private copies.
  const secondSource = f.buffers[1].source;
  Object.defineProperty(f.buffers[1], "source", {
    get() {
      f.buffers[0].source.fill(0);
      f.buffers[0].prepared!.fill(0);
      return secondSource;
    },
  });
  await assertRejects(f.run);
  assertEquals(f.calls, []);
  assertEquals(f.requests, []);
});
Deno.test("M2 fixes copy and alias work lengths before a caller buffer grows", async () => {
  const f = await fixture(2);
  const backing = new ArrayBuffer(4, { maxByteLength: 1024 });
  const tracking = new Uint8Array(backing);
  tracking.set(f.buffers[0].source);
  f.buffers[0] = { source: tracking, prepared: tracking };
  const secondSource = f.buffers[1].source;
  Object.defineProperty(f.buffers[1], "source", {
    get() {
      backing.resize(1024);
      return secondSource;
    },
  });
  assertEquals((await f.run()).outcome, "verified");
  assertEquals([...f.objects.values()].map((x) => x.bytes.length), [4, 4]);
});
