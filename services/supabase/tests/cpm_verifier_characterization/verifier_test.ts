import { assert, assertEquals } from "@std/assert";
import { verify } from "./verifier.ts";
import { FIXTURES, LIMITS, MiB } from "./policy.ts";
import { Growth, Samples } from "./telemetry.ts";
import {
  deferred,
  fixtureResponse,
  ManualClock,
  MEMORY,
  until,
} from "./test_support.ts";

Deno.test("exact incremental fixture identities and timer cleanup", async () => {
  for (const id of ["a", "b", "control"] as const) {
    const clock = new ManualClock();
    const result = await verify(id, new AbortController().signal, {
      clock,
      memory: () => MEMORY,
      get: () => Promise.resolve(fixtureResponse(id)),
    });
    assert(result.ok);
    assert(result.closed);
    assertEquals(result.bytes, FIXTURES[id].bytes);
    assertEquals(result.sha256, FIXTURES[id].sha256);
    assertEquals(result.memory.rss, "unavailable");
    assertEquals(clock.active, 0);
  }
});
Deno.test("corruption truncation overrun and response rejection close owned body", async () => {
  for (const fault of ["corrupt", "truncated", "overrun"] as const) {
    const clock = new ManualClock();
    const response = fixtureResponse("control", fault);
    const result = await verify("control", new AbortController().signal, {
      clock,
      memory: () => MEMORY,
      get: () => Promise.resolve(response),
    });
    assert(!result.ok);
    assert(result.closed);
    assert(!response.body!.locked);
    assertEquals(clock.active, 0);
  }
  for (const kind of ["status", "redirect", "length", "encoding"] as const) {
    const clock = new ManualClock();
    let cancelled = 0;
    const response = new Response(
      new ReadableStream({
        cancel() {
          cancelled++;
        },
      }),
      {
        status: kind === "status" ? 500 : 200,
        headers: {
          "content-length": kind === "length" ? "1" : "65536",
          ...(kind === "encoding" ? { "content-encoding": "gzip" } : {}),
        },
      },
    );
    if (kind === "redirect") {
      Object.defineProperty(response, "redirected", { value: true });
    }
    const result = await verify("control", new AbortController().signal, {
      clock,
      memory: () => MEMORY,
      get: () => Promise.resolve(response),
    });
    assert(!result.ok);
    assert(result.closed);
    assertEquals(cancelled, 1);
    assertEquals(clock.active, 0);
  }
});
Deno.test("abort before GET opens nothing; late acquisition stays owned until cancellation", async () => {
  const clock = new ManualClock();
  const caller = new AbortController();
  caller.abort();
  let gets = 0;
  const deps = {
    clock,
    memory: () => MEMORY,
    get: () => {
      gets++;
      return Promise.resolve(fixtureResponse("control"));
    },
  };
  const before = await verify("control", caller.signal, deps);
  assert(!before.ok);
  assertEquals(gets, 0);
  assertEquals(clock.active, 0);
  const acquired = deferred<Response>();
  let cancelled = 0;
  let finished = false;
  let signal: AbortSignal | undefined;
  const pending = verify("control", new AbortController().signal, {
    ...deps,
    get: (_id, s) => {
      signal = s;
      return acquired.promise;
    },
  }).then((r) => {
    finished = true;
    return r;
  });
  clock.advance(LIMITS.requestMs);
  assert(signal?.aborted);
  assert(!finished);
  assertEquals(clock.active, 0);
  acquired.resolve(
    new Response(
      new ReadableStream({
        cancel() {
          cancelled++;
        },
      }),
      { headers: { "content-length": "65536" } },
    ),
  );
  const after = await pending;
  assert(!after.ok);
  assert(after.closed);
  assertEquals(cancelled, 1);
});
Deno.test("stalled read abort awaits read settlement then cancellation", async () => {
  const clock = new ManualClock();
  const pull = deferred<void>();
  let started = false;
  let settled = false;
  let controller!: ReadableStreamDefaultController<Uint8Array>;
  const response = new Response(
    new ReadableStream<Uint8Array>({
      start(c) {
        controller = c;
      },
      pull() {
        started = true;
        return pull.promise;
      },
    }, { highWaterMark: 0 }),
    { headers: { "content-length": "65536" } },
  );
  const pending = verify("control", new AbortController().signal, {
    clock,
    memory: () => MEMORY,
    get: () => Promise.resolve(response),
  }).then((r) => {
    settled = true;
    return r;
  });
  await until(() => started);
  clock.advance(LIMITS.requestMs);
  assert(!settled);
  controller.enqueue(new Uint8Array(1));
  pull.resolve();
  const result = await pending;
  assert(!result.ok);
  assert(result.closed);
  assert(!response.body!.locked);
  assertEquals(clock.active, 0);
});
Deno.test("cancellation failure is never positive cleanup", async () => {
  const clock = new ManualClock();
  const response = new Response(
    new ReadableStream({
      cancel() {
        throw Error("synthetic cleanup failure");
      },
    }),
    { status: 500 },
  );
  const result = await verify("control", new AbortController().signal, {
    clock,
    memory: () => MEMORY,
    get: () => Promise.resolve(response),
  });
  assert(!result.ok);
  assert(!result.closed);
  assertEquals(result.reason, "cleanup_unknown");
  assertEquals(clock.active, 0);
});
Deno.test("telemetry invalid fields and proxy threshold stop before GET", async () => {
  for (
    const sample of [
      undefined,
      {},
      { ...MEMORY, external: NaN },
      { ...MEMORY, heapUsed: -1 },
      { ...MEMORY, heapTotal: 0 },
      { ...MEMORY, external: 94 * MiB },
    ]
  ) {
    const clock = new ManualClock();
    let gets = 0;
    const result = await verify("control", new AbortController().signal, {
      clock,
      memory: () => sample,
      get: () => {
        gets++;
        return Promise.resolve(fixtureResponse("control"));
      },
    });
    assert(!result.ok);
    assertEquals(gets, 0);
    assertEquals(clock.active, 0);
  }
  const samples = new Samples();
  assertEquals(
    samples.take({ heapUsed: 0, heapTotal: 95 * MiB, external: MiB - 1 }),
    96 * MiB - 1,
  );
  assertEquals(samples.summary.rss, "unavailable");
  const growth = new Growth();
  assertEquals([1, 3, 5, 9].map((m) => growth.add(m * MiB)), [
    false,
    false,
    false,
    true,
  ]);
  assertEquals(new Growth().add(99 * MiB), false);
  const reset = new Growth();
  assertEquals([1, 3, 3, 20].map((m) => reset.add(m * MiB)), [
    false,
    false,
    false,
    false,
  ]);
});

Deno.test("active sampling stops on proxy breach while acquisition is pending", async () => {
  const clock = new ManualClock();
  const late = deferred<Response>();
  let value = MEMORY;
  let signal!: AbortSignal;
  const result = verify("control", new AbortController().signal, {
    clock,
    memory: () => value,
    get: (_id, s) => {
      signal = s;
      return late.promise;
    },
  });
  value = { ...MEMORY, external: 94 * MiB };
  clock.advance(100);
  assert(signal.aborted);
  late.resolve(fixtureResponse("control"));
  const final = await result;
  assert(!final.ok);
  assert(final.closed);
  assertEquals(clock.active, 0);
});
Deno.test("per-chunk and chunk-count limits reject synthetic streams without aggregate allocation", async () => {
  for (const oversize of [true, false]) {
    const clock = new ManualClock();
    let chunks = 0;
    let cancelled = 0;
    const response = new Response(
      new ReadableStream<Uint8Array>({
        pull(controller) {
          chunks++;
          controller.enqueue(
            new Uint8Array(oversize ? LIMITS.maxChunkBytes + 1 : 0),
          );
        },
        cancel() {
          cancelled++;
        },
      }, { highWaterMark: 0 }),
      { headers: { "content-length": String(FIXTURES.a.bytes) } },
    );
    const result = await verify("a", new AbortController().signal, {
      clock,
      memory: () => MEMORY,
      get: () => Promise.resolve(response),
    });
    assert(!result.ok);
    assert(result.closed);
    assertEquals(cancelled, 1);
    assertEquals(chunks, oversize ? 1 : LIMITS.maxChunks + 1);
    assertEquals(clock.active, 0);
  }
});
