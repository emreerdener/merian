import { assertEquals, assertRejects } from "@std/assert";
import {
  type CaptureSourceCollectorDependencies,
  type CaptureSourceKeys,
  collectCaptureSourceSnapshots,
} from "./captureSourceCollector.ts";
import { captureSourceObservationsForIntent } from "./captureSourceEvidence.ts";
import { MEDIA_BUDGETS } from "./mediaBudgets.ts";
import { initialDeadline } from "./initialAnalysis/transport.ts";

const owner = "00000000-0000-4000-8000-000000000001";
const key = (name: string) => `staging/${owner}/${name}`;
const backend = {
  endpoint: "https://synthetic.r2.cloudflarestorage.com",
  bucketName: "synthetic-capture",
};
const one = (): CaptureSourceKeys => ({
  image: [key("photo")],
  audio: [],
  video: [],
});
const fresh = () => new AbortController().signal;
const failure = "capture_source_collection_unavailable";
function dependencies(
  fetcher: typeof fetch,
): CaptureSourceCollectorDependencies {
  return {
    backend: { ...backend },
    sign: (request) => {
      const headers = new Headers(request.headers);
      headers.set("Authorization", "synthetic-test-signature");
      return Promise.resolve(new Request(request, { headers }));
    },
    fetch: fetcher,
  };
}
function body(mime = "image/jpeg", bytes = new Uint8Array([1, 2, 3])) {
  return new Response(bytes, {
    headers: {
      "Content-Type": mime,
      "Content-Length": String(bytes.byteLength),
    },
  });
}

Deno.test("collector retains complete mixed-media bytes with signed GETs and immutable membership", async () => {
  const keys = {
    image: [key("photo")],
    audio: [key("audio")],
    video: [key("video")],
  };
  const requested: string[] = [];
  const deps = dependencies((input) => {
    const request = input as Request;
    requested.push(request.url);
    assertEquals(request.method, "GET");
    assertEquals(request.redirect, "error");
    assertEquals(request.cache, "no-store");
    assertEquals(request.credentials, "omit");
    assertEquals(request.body, null);
    assertEquals(
      request.headers.get("authorization"),
      "synthetic-test-signature",
    );
    const mime = requested.length === 1
      ? "image/jpeg"
      : requested.length === 2
      ? "audio/mp4"
      : "video/mp4";
    return Promise.resolve(body(mime));
  });
  const pending = collectCaptureSourceSnapshots(owner, keys, deps, fresh());
  keys.image[0] = key("replacement");
  deps.fetch = () => {
    throw new Error("replacement must not run");
  };
  deps.sign = () => {
    throw new Error("replacement must not run");
  };
  const snapshot = await pending;
  assertEquals(
    requested,
    ["photo", "audio", "video"].map((name) =>
      `${backend.endpoint}/${backend.bucketName}/${key(name)}`
    ),
  );
  assertEquals(snapshot.imageBase64s(), ["AQID"]);
  assertEquals(
    new Uint8Array(snapshot.audioBuffers()[0]),
    new Uint8Array([1, 2, 3]),
  );
  assertEquals(
    snapshot.observations.items.map((item) => item.sha256),
    Array(3).fill(
      "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
    ),
  );
  assertEquals(
    captureSourceObservationsForIntent(snapshot, {
      image: [key("photo")],
      audio: [key("audio")],
      video: [key("video")],
    }),
    snapshot.observations,
  );
});

Deno.test("collector rejects complete malformed inventories before signing or storage I/O", async () => {
  let calls = 0;
  const deps = dependencies(() => {
    calls++;
    throw new Error("unexpected fetch");
  });
  deps.sign = () => {
    calls++;
    throw new Error("unexpected sign");
  };
  const cases: unknown[] = [
    null,
    {},
    { image: [], audio: [], video: [] },
    { ...one(), claimedHash: "untrusted" },
    { ...one(), audio: null },
    { ...one(), audio: [key("photo")] },
    { ...one(), video: ["staging/foreign/video"] },
    { ...one(), video: [key("../video")] },
    { ...one(), video: [key("%2Fvideo")] },
    { ...one(), image: [key("photo"), 7] },
    { ...one(), image: Array.from({ length: 6 }, (_, i) => key(String(i))) },
    { ...one(), audio: [key("a"), key("b"), key("c")] },
    { ...one(), video: [key("v1"), key("v2")] },
  ];
  for (const value of cases) {
    await assertRejects(
      () =>
        collectCaptureSourceSnapshots(
          owner,
          value as CaptureSourceKeys,
          deps,
          fresh(),
        ),
      Error,
      failure,
    );
  }
  await assertRejects(
    () => collectCaptureSourceSnapshots("foreign", one(), deps, fresh()),
    Error,
    failure,
  );
  assertEquals(calls, 0);
});

Deno.test("collector rejects invalid backend and altered signed request before fetch", async () => {
  let calls = 0;
  for (
    const value of [
      { ...backend, endpoint: "http://synthetic.invalid" },
      { ...backend, endpoint: `${backend.endpoint}/path` },
      { ...backend, bucketName: "../bucket" },
    ]
  ) {
    const deps = dependencies(() => {
      calls++;
      return Promise.resolve(body());
    });
    await assertRejects(
      () =>
        collectCaptureSourceSnapshots(owner, one(), {
          ...deps,
          backend: value,
        }, fresh()),
      Error,
      failure,
    );
  }
  for (
    const variant of [
      "url",
      "method",
      "header",
      "range",
      "host",
      "authorization",
    ]
  ) {
    const deps = dependencies(() => {
      calls++;
      return Promise.resolve(body());
    });
    const sign = deps.sign;
    deps.sign = async (request, signal) => {
      const signed = await sign(request, signal);
      if (variant === "url") {
        return new Request("https://foreign.invalid/", signed);
      }
      if (variant === "method") {
        return new Request(signed, { method: "DELETE" });
      }
      if (variant === "header") signed.headers.set("Cache-Control", "public");
      if (variant === "range") signed.headers.set("Range", "bytes=0-2");
      if (variant === "host") signed.headers.set("Host", "foreign.invalid");
      if (variant === "authorization") signed.headers.delete("authorization");
      return signed;
    };
    await assertRejects(
      () => collectCaptureSourceSnapshots(owner, one(), deps, fresh()),
      Error,
      failure,
    );
  }
  assertEquals(calls, 0);
});

Deno.test("collector cancels rejected headers without waiting for cancellation acknowledgement", async () => {
  for (
    const [status, headers] of [
      [403, {}],
      [206, {}],
      [200, { "Content-Type": "audio/wav" }],
      [200, { "Content-Encoding": "gzip" }],
      [200, { "Content-Range": "bytes 0-2/3" }],
      ...[
        "0",
        "-1",
        "03",
        "NaN",
        "3.5",
        "9999999999999999999999",
        String(MEDIA_BUDGETS.maxImageRawBytes + 1),
      ].map((length) => [200, { "Content-Length": length }] as const),
    ] as readonly (readonly [number, Record<string, string>])[]
  ) {
    let cancelled = false;
    let calls = 0;
    const response = new Response(
      new ReadableStream({
        cancel() {
          cancelled = true;
          return new Promise<void>(() => {});
        },
      }),
      { status, headers: { "Content-Type": "image/jpeg", ...headers } },
    );
    const deps = dependencies(() => {
      calls++;
      return Promise.resolve(response);
    });
    await assertRejects(
      () =>
        collectCaptureSourceSnapshots(
          owner,
          {
            ...one(),
            audio: [key("later")],
          },
          deps,
          fresh(),
        ),
      Error,
      failure,
    );
    assertEquals(cancelled, true);
    assertEquals(response.body?.locked, false);
    assertEquals(calls, 1);
  }
});

Deno.test("collector bounds actual streams, aggregate images, and exact declared lengths", async () => {
  for (const length of ["2", "4"]) {
    await assertRejects(
      () =>
        collectCaptureSourceSnapshots(
          owner,
          one(),
          dependencies(() =>
            Promise.resolve(
              new Response(new Uint8Array([1, 2, 3]), {
                headers: {
                  "Content-Type": "image/jpeg",
                  "Content-Length": length,
                },
              }),
            )
          ),
          fresh(),
        ),
      Error,
      failure,
    );
  }
  let calls = 0;
  let cancelled = false;
  const deps = dependencies(() => {
    calls++;
    if (calls === 1) {
      return Promise.resolve(
        body("image/jpeg", new Uint8Array(MEDIA_BUDGETS.maxImageRawBytes - 1)),
      );
    }
    return Promise.resolve(
      new Response(
        new ReadableStream({
          start(controller) {
            controller.enqueue(new Uint8Array([1, 2]));
          },
          cancel() {
            cancelled = true;
          },
        }),
        { headers: { "Content-Type": "image/jpeg" } },
      ),
    );
  });
  await assertRejects(
    () =>
      collectCaptureSourceSnapshots(
        owner,
        {
          image: [key("first"), key("second")],
          audio: [],
          video: [],
        },
        deps,
        fresh(),
      ),
    Error,
    failure,
  );
  assertEquals(cancelled, true);
  assertEquals(calls, 2);
  const unknownLength = await collectCaptureSourceSnapshots(
    owner,
    one(),
    dependencies(() =>
      Promise.resolve(
        new Response(new Uint8Array([4]), {
          headers: { "Content-Type": "image/png" },
        }),
      )
    ),
    fresh(),
  );
  assertEquals(unknownLength.observations.items[0].byteCount, 1);
  await assertRejects(
    () =>
      collectCaptureSourceSnapshots(
        owner,
        one(),
        dependencies(() =>
          Promise.resolve(
            new Response(new Uint8Array(), {
              headers: { "Content-Type": "image/jpeg" },
            }),
          )
        ),
        fresh(),
      ),
    Error,
    failure,
  );
});

Deno.test("collector aborts stalled sign/read/fetch and cancels late responses", async () => {
  for (const stage of ["sign", "fetch", "read"]) {
    const controller = new AbortController();
    let cancelled = false;
    let finishFetch: (response: Response) => void = () => {};
    const response = new Response(
      new ReadableStream({
        pull() {
          if (stage === "read") controller.abort();
        },
        cancel() {
          cancelled = true;
        },
      }, { highWaterMark: 0 }),
      { headers: { "Content-Type": "image/jpeg" } },
    );
    const deps = dependencies(() => {
      if (stage === "fetch") {
        controller.abort();
        return new Promise<Response>((resolve) => {
          finishFetch = resolve;
        });
      }
      return Promise.resolve(response);
    });
    if (stage === "sign") {
      deps.sign = () => {
        controller.abort();
        return new Promise<Request>(() => {});
      };
    }
    await assertRejects(
      () =>
        collectCaptureSourceSnapshots(owner, one(), deps, controller.signal),
      Error,
      failure,
    );
    if (stage === "fetch") {
      finishFetch(response);
      await new Promise((resolve) => setTimeout(resolve, 0));
    }
    if (stage !== "sign") assertEquals(cancelled, true);
    else await response.body?.cancel();
    assertEquals(response.body?.locked, false);
  }
  await assertRejects(
    () =>
      initialDeadline(fresh(), 5, (signal) =>
        collectCaptureSourceSnapshots(
          owner,
          one(),
          dependencies(() => new Promise<Response>(() => {})),
          signal,
        )),
    Error,
    failure,
  );
});

Deno.test("collector cancels late signing bodies and hides dependency diagnostics", async () => {
  const controller = new AbortController();
  let finish: (request: Request) => void = () => {};
  let called = false;
  let cancelled = false;
  const deps = dependencies(() => {
    called = true;
    return Promise.resolve(body());
  });
  deps.sign = () => {
    controller.abort();
    return new Promise<Request>((resolve) => {
      finish = resolve;
    });
  };
  await assertRejects(
    () => collectCaptureSourceSnapshots(owner, one(), deps, controller.signal),
    Error,
    failure,
  );
  finish(
    new Request("https://synthetic.invalid/", {
      method: "POST",
      body: new ReadableStream({
        cancel() {
          cancelled = true;
        },
      }),
    }),
  );
  await new Promise((resolve) => setTimeout(resolve, 0));
  assertEquals(cancelled, true);
  assertEquals(called, false);
  const error = await assertRejects(() =>
    collectCaptureSourceSnapshots(
      owner,
      one(),
      dependencies(() => {
        throw new Error("synthetic-private-diagnostic");
      }),
      fresh(),
    ), Error);
  assertEquals(error.message, failure);
});

Deno.test("collector enforces audio/video and pathological stream caps before creating evidence", async () => {
  for (
    const [kind, mime, cap] of [
      ["audio", "audio/mp4", MEDIA_BUDGETS.maxAudioRawBytes],
      ["video", "video/mp4", MEDIA_BUDGETS.maxVideoRawBytes],
    ] as const
  ) {
    let cancelled = false;
    const response = new Response(
      new ReadableStream({
        start(controller) {
          controller.enqueue(new Uint8Array(cap + 1));
        },
        cancel() {
          cancelled = true;
        },
      }),
      { headers: { "Content-Type": mime } },
    );
    await assertRejects(
      () =>
        collectCaptureSourceSnapshots(
          owner,
          {
            image: [],
            audio: [],
            video: [],
            [kind]: [key(kind)],
          },
          dependencies(() => Promise.resolve(response)),
          fresh(),
        ),
      Error,
      failure,
    );
    assertEquals(cancelled, true);
  }
  for (const size of [0, 1]) {
    let cancelled = false;
    const response = new Response(
      new ReadableStream({
        pull(controller) {
          controller.enqueue(new Uint8Array(size));
        },
        cancel() {
          cancelled = true;
        },
      }),
      { headers: { "Content-Type": "image/jpeg" } },
    );
    await assertRejects(
      () =>
        collectCaptureSourceSnapshots(
          owner,
          one(),
          dependencies(() => Promise.resolve(response)),
          fresh(),
        ),
      Error,
      failure,
    );
    assertEquals(cancelled, true);
    assertEquals(response.body?.locked, false);
  }
  let fetches = 0;
  await assertRejects(
    () =>
      collectCaptureSourceSnapshots(
        owner,
        {
          image: [key("full"), key("excess")],
          audio: [],
          video: [],
        },
        dependencies(() => {
          fetches++;
          return Promise.resolve(
            body("image/jpeg", new Uint8Array(MEDIA_BUDGETS.maxImageRawBytes)),
          );
        }),
        fresh(),
      ),
    Error,
    failure,
  );
  assertEquals(fetches, 1);
});
