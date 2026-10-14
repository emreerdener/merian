import { assert, assertEquals } from "@std/assert";
import { createHandler, requestFor } from "./handler.ts";
import { LIMITS, MiB } from "./policy.ts";
import {
  CAPABILITY,
  config,
  deferred,
  fixtureResponse,
  ManualClock,
  MEMORY,
  until,
} from "./test_support.ts";

Deno.test("representative wrapper rejects unauthorized and invalid inputs without GET", async () => {
  for (
    const mode of [
      "operator",
      "capability",
      "expired",
      "unknown",
      "key",
      "oversize",
      "malformed",
      "method",
      "bearer",
      "extra",
    ]
  ) {
    const clock = new ManualClock();
    let gets = 0;
    const cfg = config(clock);
    if (mode === "expired") cfg.expiresAt = clock.wall();
    const handler = createHandler(cfg, {
      clock,
      memory: () => MEMORY,
      authenticate: () =>
        Promise.resolve(
          mode === "operator" ? "different-operator" : cfg.operator,
        ),
      get: () => {
        gets++;
        return Promise.resolve(fixtureResponse("control"));
      },
    });
    let req = requestFor(
      cfg.run,
      1,
      mode === "capability" ? "wrong" : CAPABILITY,
    );
    if (mode === "method") req = new Request(req.url, { method: "GET" });
    if (mode === "bearer") req.headers.delete("authorization");
    const bodies: Record<string, string> = {
      unknown: '{"run":"local-check","case":27,"fixture":"control"}',
      key: '{"run":"local-check","case":1,"fixture":"../a"}',
      oversize: " ".repeat(4097),
      malformed: "{",
      extra: '{"run":"local-check","case":1,"fixture":"control","extra":1}',
    };
    if (bodies[mode]) {
      req = new Request(req.url, {
        method: "POST",
        headers: req.headers,
        body: bodies[mode],
      });
    }
    const response = await handler.handle(req);
    assert(response.status >= 400, mode);
    await response.body?.cancel();
    assertEquals(gets, 0, mode);
    assertEquals(clock.active, 0, mode);
  }
});
Deno.test("successful handler uses real wrapper, duplicate stops and fixed denial never GETs", async () => {
  const clock = new ManualClock();
  const cfg = config(clock);
  let gets = 0;
  const handler = createHandler(cfg, {
    clock,
    memory: () => MEMORY,
    authenticate: () => Promise.resolve(cfg.operator),
    get: (id) => {
      gets++;
      return Promise.resolve(fixtureResponse(id));
    },
  });
  const first = await handler.handle(requestFor(cfg.run, 1, CAPABILITY));
  assert(first.headers.has("x-request-id"));
  const ack = await first.json();
  assertEquals(ack.outcome, "verified");
  assert(ack.closed && ack.cleanup);
  assertEquals(clock.active, 0);
  const denial = await handler.handle(requestFor(cfg.run, 26, CAPABILITY));
  assertEquals((await denial.json()).outcome, "denied");
  assertEquals(gets, 1);
  const duplicate = await handler.handle(requestFor(cfg.run, 1, CAPABILITY));
  assertEquals(duplicate.status, 409);
  await duplicate.body?.cancel();
  const next = await handler.handle(requestFor(cfg.run, 2, CAPABILITY));
  assertEquals(next.status, 409);
  await next.body?.cancel();
  assertEquals(gets, 1);
  assertEquals(handler.state(), { busy: false, halted: true, seen: 2 });
});
Deno.test("same-worker busy acknowledgement does not release the active reader", async () => {
  const clock = new ManualClock();
  const cfg = config(clock);
  const late = deferred<Response>();
  let gets = 0;
  const handler = createHandler(cfg, {
    clock,
    memory: () => MEMORY,
    authenticate: () => Promise.resolve(cfg.operator),
    get: () => {
      gets++;
      return late.promise;
    },
  });
  const first = handler.handle(requestFor(cfg.run, 21, CAPABILITY));
  await until(() => gets === 1);
  const second = await handler.handle(requestFor(cfg.run, 22, CAPABILITY));
  const ack = await second.json();
  assertEquals(ack.outcome, "busy");
  assertEquals(ack.opened, false);
  assert(handler.state().busy);
  assertEquals(gets, 1);
  late.resolve(fixtureResponse("a"));
  assertEquals((await (await first).json()).outcome, "verified");
  assert(!handler.state().busy);
  assertEquals(clock.active, 0);
});
Deno.test("unknown reader cleanup holds worker and rejects future GET", async () => {
  const clock = new ManualClock();
  const cfg = config(clock);
  let gets = 0;
  const handler = createHandler(cfg, {
    clock,
    memory: () => MEMORY,
    authenticate: () => Promise.resolve(cfg.operator),
    get: () => {
      gets++;
      return Promise.resolve(
        new Response(
          new ReadableStream({
            cancel() {
              throw Error("synthetic cleanup");
            },
          }),
          { status: 500 },
        ),
      );
    },
  });
  const ack = await (await handler.handle(requestFor(cfg.run, 1, CAPABILITY)))
    .json();
  assertEquals(ack.outcome, "stopped");
  assertEquals(ack.closed, false);
  assert(handler.state().busy && handler.state().halted);
  const next = await handler.handle(requestFor(cfg.run, 2, CAPABILITY));
  await next.body?.cancel();
  assertEquals(next.status, 409);
  assertEquals(gets, 1);
  assertEquals(clock.active, 0);
});
Deno.test("expired auth or manifest never starts late GET; sampling ceases at deadline", async () => {
  const clock = new ManualClock();
  const cfg = config(clock);
  const auth = deferred<string>();
  let gets = 0;
  let samples = 0;
  const handler = createHandler(cfg, {
    clock,
    memory: () => {
      samples++;
      return MEMORY;
    },
    authenticate: () => auth.promise,
    get: () => {
      gets++;
      return Promise.resolve(fixtureResponse("control"));
    },
  });
  const request = requestFor(cfg.run, 1, CAPABILITY);
  const pending = handler.handle(request);
  clock.advance(LIMITS.requestMs);
  const count = samples;
  clock.advance(1000);
  assertEquals(samples, count);
  auth.resolve(cfg.operator);
  const response = await pending;
  assertEquals(request.bodyUsed, false);
  assertEquals(samples, count);
  await response.body?.cancel();
  assertEquals(response.status, 409);
  assertEquals(gets, 0);
  assertEquals(clock.active, 0);
});
Deno.test("quiescent growth is ordered per simulated worker and halts on fourth point", async () => {
  const clock = new ManualClock();
  const cfg = config(clock);
  let value = 1 * MiB;
  let gets = 0;
  const deps = {
    clock,
    memory: () => ({ heapUsed: 0, heapTotal: value, external: 0 }),
    authenticate: () => Promise.resolve(cfg.operator),
    get: (id: "a" | "b" | "control") => {
      gets++;
      return Promise.resolve(fixtureResponse(id));
    },
  };
  const a = createHandler(cfg, deps),
    b = createHandler({ ...cfg, worker: "worker-b" }, deps);
  for (const [i, m] of [1, 3, 5, 9].entries()) {
    value = m * MiB;
    const ack = await (await a.handle(requestFor(cfg.run, i + 1, CAPABILITY)))
      .json();
    assertEquals(ack.outcome, i === 3 ? "stopped" : "verified");
  }
  assertEquals(
    (await (await b.handle(requestFor(cfg.run, 1, CAPABILITY))).json()).outcome,
    "verified",
  );
  assertEquals(gets, 5);
  assert(a.state().halted);
  assert(!b.state().halted);
  assertEquals(clock.active, 0);
});

Deno.test("competing duplicate and telemetry stop abort the worker-owned pending reader", async () => {
  for (const trigger of ["duplicate", "telemetry"]) {
    const clock = new ManualClock(),
      cfg = config(clock),
      acquired = deferred<Response>();
    let signal!: AbortSignal;
    let gets = 0;
    let reading = false;
    let memory = MEMORY;
    const handler = createHandler(cfg, {
      clock,
      memory: () => memory,
      authenticate: () => Promise.resolve(cfg.operator),
      get: (_id, s) => {
        gets++;
        signal = s;
        reading = true;
        return acquired.promise;
      },
    });
    const first = handler.handle(requestFor(cfg.run, 21, CAPABILITY));
    await until(() => reading);
    if (trigger === "telemetry") memory = { ...MEMORY, external: 94 * MiB };
    const competing = await handler.handle(
      requestFor(cfg.run, trigger === "duplicate" ? 21 : 22, CAPABILITY),
    );
    await competing.body?.cancel();
    assert(signal.aborted, trigger);
    assert(handler.state().busy, trigger);
    assert(handler.state().halted, trigger);
    const next = await handler.handle(requestFor(cfg.run, 23, CAPABILITY));
    await next.body?.cancel();
    assertEquals(gets, 1);
    memory = MEMORY;
    acquired.resolve(fixtureResponse("a"));
    const ack = await (await first).json();
    assertEquals(ack.outcome, "stopped");
    assert(ack.closed);
    assertEquals(clock.active, 0);
  }
});
Deno.test("absolute deadline rejects success when timer delivery is delayed", async () => {
  for (const phase of ["get", "read", "response"]) {
    const clock = new ManualClock(), cfg = config(clock);
    let reads = 0;
    const handler = createHandler(cfg, {
      clock,
      memory: () => {
        // Response sampling is after entry/auth/manifest, verifier entry/chunk/quiescence.
        reads++;
        if (phase === "response" && reads === 7) clock.time += LIMITS.requestMs;
        return MEMORY;
      },
      authenticate: () => Promise.resolve(cfg.operator),
      get: (id) => {
        if (phase === "get") clock.time += LIMITS.requestMs;
        if (phase !== "read") return Promise.resolve(fixtureResponse(id));
        return Promise.resolve(
          new Response(
            new ReadableStream<Uint8Array>({
              pull(controller) {
                clock.time += LIMITS.requestMs;
                controller.enqueue(new Uint8Array(1));
              },
            }, { highWaterMark: 0 }),
            { headers: { "content-length": "65536" } },
          ),
        );
      },
    });
    const ack = await (await handler.handle(requestFor(cfg.run, 1, CAPABILITY)))
      .json();
    assertEquals(ack.outcome, "stopped", phase);
    assert(handler.state().halted);
    assertEquals(clock.active, 0);
  }
});
