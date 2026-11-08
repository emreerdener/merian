import { assert, assertEquals, assertRejects } from "@std/assert";
import { createDriver } from "./driver.ts";
import { type Ack, createHandler } from "./handler.ts";
import { CASES, LIMITS } from "./policy.ts";
import {
  CAPABILITY,
  config,
  deferred,
  fixtureResponse,
  ManualClock,
  MEMORY,
  MemoryJournal,
  until,
} from "./test_support.ts";

Deno.test("fixed 26-case schedule through wrapper/verifier, journal before send, bounded pairs and counters", async () => {
  for (const singleWorker of [false, true]) {
    const clock = new ManualClock(),
      journal = new MemoryJournal(),
      cfg = config(clock);
    const active = new Set<string>();
    let maximum = 0;
    let gets = 0;
    const deps = {
      clock,
      memory: () => MEMORY,
      authenticate: () => Promise.resolve(cfg.operator),
      get: (id: "a" | "b" | "control") => {
        assert(!active.has(id));
        active.add(id);
        gets++;
        const response = fixtureResponse(id);
        const reader = response.body!.getReader();
        return Promise.resolve(
          new Response(
            new ReadableStream<Uint8Array>({
              async pull(controller) {
                const next = await reader.read();
                if (next.done) {
                  reader.releaseLock();
                  active.delete(id);
                  controller.close();
                } else controller.enqueue(next.value);
              },
              async cancel() {
                await reader.cancel();
                reader.releaseLock();
                active.delete(id);
              },
            }, { highWaterMark: 0 }),
            { headers: response.headers },
          ),
        );
      },
    };
    const a = createHandler(cfg, deps),
      b = singleWorker
        ? a
        : createHandler({ ...cfg, worker: "worker-b" }, deps);
    let inFlight = 0;
    const driver = createDriver(cfg.run, CAPABILITY, {
      clock,
      journal,
      send: async (req, signal) => {
        const input = await req.clone().json();
        const last = journal.records.at(-1)!;
        assert(last.attempted.includes(input.case));
        assert(last.obligations.includes(input.case));
        inFlight++;
        maximum = Math.max(maximum, inFlight);
        try {
          return await (input.fixture === "b" ? b : a).handle(
            new Request(req, { signal }),
          );
        } finally {
          inFlight--;
        }
      },
    });
    const result = await driver.run();
    assertEquals(result.phase, "complete");
    assertEquals(result.attempted.length, 26);
    assertEquals(result.obligations, []);
    assertEquals(maximum, 2);
    assertEquals(active.size, 0);
    assertEquals(clock.active, 0);
    assertEquals(result.ordinaryCallsReserved, 178);
    assert(result.transferReserved < LIMITS.transferBytes);
    assertEquals(driver.results().length, 26);
    assertEquals(
      driver.results().find((ack) => ack.case === 26)!.outcome,
      "denied",
    );
    assertEquals(gets, singleWorker ? 23 : 25);
    await driver.reserveCleanup(64);
    assertEquals(driver.snapshot().cleanupCalls, 64);
    await assertRejects(() => driver.reserveCleanup(1));
    await assertRejects(() => driver.run());
    const restarted = createDriver(cfg.run, CAPABILITY, {
      clock,
      journal,
      send: () => {
        throw Error("must not send");
      },
    });
    assertEquals(
      (await restarted.run()).reason,
      "journal_exists_or_unavailable",
    );
    const warm = CASES.filter((c) => c.id >= 3 && c.id <= 11);
    assertEquals(warm.at(-1)!.atMs - warm[0].atMs, LIMITS.cohortSpanMs);
  }
});
Deno.test("bad/missing/truncated acknowledgement stops before next invocation", async () => {
  for (
    const fault of [
      "lost",
      "truncated",
      "mismatch",
      "closure",
      "digest",
      "oversize",
      "memory",
    ]
  ) {
    const clock = new ManualClock(),
      journal = new MemoryJournal(),
      cfg = config(clock);
    let sent = 0;
    const handler = createHandler(cfg, {
      clock,
      memory: () => MEMORY,
      authenticate: () => Promise.resolve(cfg.operator),
      get: (id) => Promise.resolve(fixtureResponse(id)),
    });
    const driver = createDriver(cfg.run, CAPABILITY, {
      clock,
      journal,
      send: async (req) => {
        sent++;
        const response = await handler.handle(req);
        const ack = await response.json() as Ack;
        if (fault === "lost") throw Error("lost acknowledgement");
        if (fault === "truncated") {
          return new Response("{", {
            headers: { "content-type": "application/json" },
          });
        }
        if (fault === "oversize") {
          return new Response(" ".repeat(8193), {
            headers: { "content-type": "application/json" },
          });
        }
        if (fault === "mismatch") ack.case = 2;
        if (fault === "closure") ack.closed = false;
        if (fault === "digest") ack.sha256 = "bad";
        if (fault === "memory") ack.memory.proxy = 96 * 1_048_576;
        return Response.json(ack);
      },
    });
    const result = await driver.run();
    assertEquals(result.phase, "stopped", fault);
    assertEquals(sent, 1, fault);
    assertEquals(result.obligations, [1], fault);
    assertEquals(clock.active, 0, fault);
  }
});
Deno.test("delivery timeout keeps unresolved obligation and owns late body cleanup", async () => {
  const clock = new ManualClock(), journal = new MemoryJournal();
  const late = deferred<Response>();
  let sent = 0;
  let signal!: AbortSignal;
  let cancelled = 0;
  const driver = createDriver("local-check", CAPABILITY, {
    clock,
    journal,
    send: (_req, s) => {
      sent++;
      signal = s;
      return late.promise;
    },
  });
  const running = driver.run();
  await until(() => sent === 1);
  clock.advance(LIMITS.requestMs);
  const state = await running;
  assertEquals(state.phase, "stopped");
  assertEquals(state.obligations, [1]);
  assert(signal.aborted);
  assertEquals(driver.pending().length, 1);
  const pending = driver.pending();
  late.resolve(
    new Response(
      new ReadableStream({
        cancel() {
          cancelled++;
        },
      }),
    ),
  );
  await Promise.all(pending);
  assertEquals(cancelled, 1);
  assertEquals(driver.pending().length, 0);
  assertEquals(driver.results().length, 0);
  assertEquals(sent, 1);
  assertEquals(clock.active, 0);
});
Deno.test("journal failure before send consumes no transport and never retries", async () => {
  const clock = new ManualClock();
  let sent = 0;
  const driver = createDriver("local-check", CAPABILITY, {
    clock,
    journal: {
      begin: () => Promise.resolve(),
      save: () => Promise.reject(Error("disk")),
    },
    send: () => {
      sent++;
      return Promise.resolve(new Response());
    },
  });
  assertEquals((await driver.run()).phase, "stopped");
  assertEquals(sent, 0);
  await assertRejects(() => driver.run());
});

Deno.test("one unresolved pair member stops schedule despite paired busy acknowledgement", async () => {
  const clock = new ManualClock(),
    journal = new MemoryJournal(),
    cfg = config(clock);
  const acquired = deferred<Response>();
  let blocked = false;
  let sent = 0;
  const handler = createHandler(cfg, {
    clock,
    memory: () => MEMORY,
    authenticate: () => Promise.resolve(cfg.operator),
    get: (id) => {
      if (blocked) return acquired.promise;
      return Promise.resolve(fixtureResponse(id));
    },
  });
  const driver = createDriver(cfg.run, CAPABILITY, {
    clock,
    journal,
    send: async (req, signal) => {
      const input = await req.clone().json();
      sent++;
      if (input.case === 21) blocked = true;
      return await handler.handle(new Request(req, { signal }));
    },
  });
  const running = driver.run();
  // Hashing the warm cohorts requires more microtasks than the small helper bound.
  for (
    let i = 0;
    i < 100_000 && !driver.results().some((a) => a.case === 22);
    i++
  ) await Promise.resolve();
  assert(driver.results().some((a) => a.case === 22 && a.outcome === "busy"));
  assert(handler.state().busy);
  clock.advance(LIMITS.requestMs);
  const result = await running;
  assertEquals(result.phase, "stopped");
  assertEquals(result.obligations, [21]);
  assertEquals(sent, 22);
  const pending = driver.pending();
  acquired.resolve(fixtureResponse("a"));
  await Promise.all(pending);
  assertEquals(driver.snapshot().obligations, [21]);
  assertEquals(sent, 22);
  assertEquals(clock.active, 0);
});

Deno.test("invalid response status awaits cancellation and never advances", async () => {
  const clock = new ManualClock(), journal = new MemoryJournal();
  const cancelled = deferred<void>();
  let cancelStarted = false;
  let sends = 0;
  const driver = createDriver("local-check", CAPABILITY, {
    clock,
    journal,
    send: () => {
      sends++;
      return Promise.resolve(
        new Response(
          new ReadableStream({
            cancel() {
              cancelStarted = true;
              return cancelled.promise;
            },
          }),
          { status: 500 },
        ),
      );
    },
  });
  const running = driver.run();
  await until(() => cancelStarted);
  assertEquals(driver.snapshot().obligations, [1]);
  cancelled.resolve();
  assertEquals((await running).phase, "stopped");
  assertEquals(sends, 1);
  assertEquals(clock.active, 0);
});

Deno.test("driver absolute deadline rejects delayed delivery even without timer callback", async () => {
  const clock = new ManualClock(),
    journal = new MemoryJournal(),
    cfg = config(clock);
  let sends = 0;
  const handler = createHandler(cfg, {
    clock,
    memory: () => MEMORY,
    authenticate: () => Promise.resolve(cfg.operator),
    get: (id) => Promise.resolve(fixtureResponse(id)),
  });
  const driver = createDriver(cfg.run, CAPABILITY, {
    clock,
    journal,
    send: async (req) => {
      sends++;
      const response = await handler.handle(req);
      clock.time += LIMITS.requestMs;
      return response;
    },
  });
  assertEquals((await driver.run()).phase, "stopped");
  assertEquals(sends, 1);
  assertEquals(driver.snapshot().obligations, [1]);
  assertEquals(clock.active, 0);
});

Deno.test("cleanup reservations expire after the fixed terminal window", async () => {
  const clock = new ManualClock(), journal = new MemoryJournal();
  const driver = createDriver("local-check", CAPABILITY, {
    clock,
    journal,
    send: () => Promise.reject(Error("synthetic lost delivery")),
  });
  assertEquals((await driver.run()).phase, "stopped");
  clock.advance(LIMITS.cleanupMs - 1);
  await driver.reserveCleanup(1);
  clock.advance(1);
  await assertRejects(() => driver.reserveCleanup(1));
  assertEquals(driver.snapshot().cleanupCalls, 1);
});
