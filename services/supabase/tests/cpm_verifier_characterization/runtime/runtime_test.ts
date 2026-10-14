import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { authAdapter } from "./auth.ts";
import {
  AUTH_MODE,
  BUCKET,
  DENIED_BEARER,
  OPERATOR_ALIAS,
  PROJECT_URL,
  readConfig,
  SECRET_NAMES,
} from "./config.ts";
import { createWorker } from "./worker.ts";
import { driverTransport } from "./transport.ts";
import { validateReadiness } from "./run.ts";
import { createDriver } from "../driver.ts";
import { requestFor } from "../handler.ts";
import { FIXTURES, LIMITS } from "../policy.ts";
import {
  CAPABILITY,
  deferred,
  fixtureResponse,
  ManualClock,
  MEMORY,
  MemoryJournal,
} from "../test_support.ts";

const ID = "00000000-0000-4000-8000-000000000001";
const OPERATOR_KEY = "d".repeat(64);
const PUBLIC = "sb_publishable_synthetic_qualification_key_0000";
function environment(clock: ManualClock): Record<string, string> {
  return {
    SUPABASE_URL: PROJECT_URL,
    CPM_Q_RUN: "runtime-check",
    CPM_Q_OPERATOR_KEY: OPERATOR_KEY,
    CPM_Q_CAPABILITY: CAPABILITY,
    CPM_Q_EXPIRES_AT: String(clock.wall() + LIMITS.runMs),
    CPM_Q_R2_ENDPOINT: `https://${"a".repeat(32)}.r2.cloudflarestorage.com`,
    CPM_Q_R2_ACCESS_KEY_ID: "b".repeat(32),
    CPM_Q_R2_SECRET_ACCESS_KEY: "c".repeat(64),
  };
}
function makeWorker(
  clock: ManualClock,
  fetchOnce: (request: Request) => Promise<Response>,
  memoryUsage = () => MEMORY,
) {
  const env = environment(clock);
  return createWorker({
    env: (name) => env[name],
    fetchOnce,
    memoryUsage,
    uuid: () => ID,
    clock,
    versions: { deno: "local-test", v8: "local-test" },
  });
}
Deno.test("runtime config is target-bound, finite, namespaced and fail closed", () => {
  const clock = new ManualClock(),
    env = environment(clock),
    names: string[] = [];
  assertEquals(
    readConfig((name) => {
      names.push(name);
      return env[name];
    }, clock.wall()).run,
    "runtime-check",
  );
  assert(
    names.every((name) =>
      [
        ...SECRET_NAMES,
        "SUPABASE_URL",
      ].includes(name)
    ),
  );
  for (
    const [key, value] of Object.entries({
      SUPABASE_URL: "https://wrong.supabase.co",
      CPM_Q_OPERATOR_KEY: "operator",
      CPM_Q_CAPABILITY: "short",
      CPM_Q_EXPIRES_AT: String(clock.wall() + LIMITS.runMs + 1),
      CPM_Q_R2_ENDPOINT: "https://example.com",
      CPM_Q_R2_ACCESS_KEY_ID: "",
    })
  ) {
    assertThrows(() =>
      readConfig((name) => ({ ...env, [key]: value })[name], clock.wall())
    );
  }
  assertThrows(() =>
    readConfig((name) => env[name], clock.wall() + LIMITS.runMs)
  );
});
Deno.test("test key accepts exact possession only and honors cancellation without network", async () => {
  const authenticate = authAdapter(OPERATOR_KEY);
  assertEquals(
    await authenticate(OPERATOR_KEY, new AbortController().signal),
    OPERATOR_ALIAS,
  );
  for (
    const bad of [
      "",
      "d".repeat(63),
      "d".repeat(65),
      "D".repeat(64),
      "e".repeat(64),
      "synthetic-jwt",
      CAPABILITY,
    ]
  ) {
    assertEquals(await authenticate(bad, new AbortController().signal), null);
  }
  const abort = new AbortController();
  abort.abort();
  assertThrows(() => authenticate(OPERATOR_KEY, abort.signal));
  assertThrows(() => authAdapter(""));
  assertThrows(() => authAdapter(DENIED_BEARER));
});
Deno.test("runtime config rejects reused key and capability or R2 secret", () => {
  const clock = new ManualClock(), env = environment(clock);
  for (const key of ["", "D".repeat(64), DENIED_BEARER, "d".repeat(65)]) {
    assertThrows(() =>
      readConfig(
        (name) => ({ ...env, CPM_Q_OPERATOR_KEY: key })[name],
        clock.wall(),
      )
    );
  }
  for (const key of ["CPM_Q_CAPABILITY", "CPM_Q_R2_SECRET_ACCESS_KEY"]) {
    assertThrows(() =>
      readConfig(
        (name) => ({ ...env, [key]: OPERATOR_KEY })[name],
        clock.wall(),
      )
    );
  }
});
Deno.test("real runtime composition rejects invalid caller before R2 and retains shared reader gate", async () => {
  const clock = new ManualClock(),
    opened = deferred<void>(),
    release = deferred<void>();
  let gets = 0;
  const worker = makeWorker(clock, async (request) => {
    gets++;
    assert(request.url.includes(`/${BUCKET}/cpm-verifier/runtime-check/`));
    assertEquals(request.method, "GET");
    assertEquals(request.redirect, "error");
    opened.resolve();
    await release.promise;
    return fixtureResponse("a");
  });
  const first = worker.handle(
    requestFor("runtime-check", 21, CAPABILITY, OPERATOR_KEY),
  );
  await opened.promise;
  const busy = await (await worker.handle(
    requestFor("runtime-check", 22, CAPABILITY, OPERATOR_KEY),
  ))
    .json();
  assertEquals(busy.outcome, "busy");
  const denied = await worker.handle(
    requestFor("runtime-check", 26, CAPABILITY, DENIED_BEARER),
  );
  assertEquals(denied.status, 403);
  assertEquals(denied.headers.get("x-merian-handler"), "1");
  assertEquals(gets, 1);
  release.resolve();
  const ack = await (await first).json();
  assertEquals(ack.outcome, "verified");
  assertEquals(worker.state().busy, false);
  assertEquals(clock.active, 0);
});
Deno.test("runtime memory omission, zero fields and proxy breach stop before network", async () => {
  for (
    const bad of [{ ...MEMORY, heapTotal: 0 }, { ...MEMORY, heapUsed: 0 }, {
      ...MEMORY,
      external: LIMITS.proxyBytes,
    }]
  ) {
    let calls = 0;
    const clock = new ManualClock();
    const worker = makeWorker(clock, () => {
      calls++;
      throw Error("must not fetch");
    }, () => bad);
    assertEquals(
      (await worker.handle(
        requestFor("runtime-check", 1, CAPABILITY, OPERATOR_KEY),
      )).status,
      409,
    );
    assertEquals(calls, 0);
    assertEquals(clock.active, 0);
  }
});
Deno.test("runtime driver executes genuine invalid-bearer case and pauses before bulk", async () => {
  const clock = new ManualClock(), journal = new MemoryJournal();
  let barrier = false, gets = 0;
  const sent: { id: number; at: number }[] = [];
  const worker = makeWorker(clock, (req) => {
    gets++;
    if (!req.url.endsWith("control.bin")) assert(barrier);
    const id = req.url.endsWith("a.bin")
      ? "a"
      : req.url.endsWith("b.bin")
      ? "b"
      : "control";
    return Promise.resolve(fixtureResponse(id));
  });
  const driver = createDriver("runtime-check", CAPABILITY, {
    clock,
    journal,
    rejectedCaller: true,
    beforeBulk: (controls) => {
      assertEquals(controls.length, 2);
      assertEquals(gets, 2);
      barrier = true;
      clock.advance(300_000);
      return Promise.resolve();
    },
    send: driverTransport({
      operatorKey: OPERATOR_KEY,
      publicKey: PUBLIC,
      fetchOnce: async (req) => {
        const item = await req.clone().json();
        sent.push({ id: item.case, at: clock.now() });
        if (item.case === 26) assertEquals(gets, 0);
        return worker.handle(req);
      },
    }),
  });
  assertEquals((await driver.run()).phase, "complete");
  assertEquals(sent[0].id, 26);
  assertEquals(sent.find((c) => c.id === 3)!.at, 301_000);
  assertEquals(
    sent.find((c) => c.id === 11)!.at - sent.find((c) => c.id === 3)!.at,
    LIMITS.cohortSpanMs,
  );
  assertEquals(driver.results().length, 25);
  assertEquals(driver.denials(), [{ case: 26, status: 403, handler: true }]);
  assertEquals(clock.active, 0);
});
Deno.test("failed or too-late bulk readiness stops before any bulk request", async () => {
  for (const late of [false, true]) {
    const clock = new ManualClock(), journal = new MemoryJournal();
    const sent: number[] = [];
    const worker = makeWorker(
      clock,
      () => Promise.resolve(fixtureResponse("control")),
    );
    const driver = createDriver("runtime-check", CAPABILITY, {
      clock,
      journal,
      rejectedCaller: true,
      expiresAt: clock.wall() + 900_000,
      beforeBulk: () => {
        if (!late) return Promise.reject(Error("not ready"));
        clock.advance(300_000);
        return Promise.resolve();
      },
      send: driverTransport({
        operatorKey: OPERATOR_KEY,
        publicKey: PUBLIC,
        fetchOnce: async (req) => {
          sent.push((await req.clone().json()).case);
          return worker.handle(req);
        },
      }),
    });
    assertEquals((await driver.run()).phase, "stopped");
    assertEquals(sent, [26, 1, 2]);
    await assertRejects(() => driver.run());
  }
});
Deno.test("gateway denial fails before any control or bulk read", async () => {
  const clock = new ManualClock(), journal = new MemoryJournal();
  let sent = 0;
  const driver = createDriver("runtime-check", CAPABILITY, {
    clock,
    journal,
    rejectedCaller: true,
    send: () => {
      sent++;
      return Promise.resolve(new Response(null, { status: 403 }));
    },
  });
  assertEquals((await driver.run()).phase, "stopped");
  assertEquals(sent, 1);
  assertEquals(driver.snapshot().attempted, [26]);
});
Deno.test("readiness requires all exact fixture identities and writer closure", () => {
  const fixture = {
    run: "runtime-check",
    writersClosed: true,
    fixtures: Object.entries(FIXTURES).map(([id, f]) => ({
      id,
      bytes: f.bytes,
      sha256: f.sha256,
    })),
  };
  assert(validateReadiness(fixture, "runtime-check"));
  assert(
    !validateReadiness({ ...fixture, writersClosed: false }, "runtime-check"),
  );
  assert(!validateReadiness(fixture, "different-run"));
  assert(
    !validateReadiness(
      { ...fixture, fixtures: fixture.fixtures.slice(1) },
      "runtime-check",
    ),
  );
});

Deno.test("packaged entrypoint registers once and reuses one module handler without live I/O", async () => {
  const clock = new ManualClock(), env = environment(clock);
  env.CPM_Q_EXPIRES_AT = String(Date.now() + LIMITS.runMs);
  const originalServe = Deno.serve,
    originalGet = Deno.env.get,
    originalFetch = globalThis.fetch,
    originalMemory = Deno.memoryUsage;
  const handlers: ((request: Request) => Promise<Response>)[] = [];
  try {
    Object.defineProperty(Deno.env, "get", {
      configurable: true,
      value: (name: string) => env[name],
    });
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: (handle: (req: Request) => Promise<Response>) => {
        handlers.push(handle);
        return {};
      },
    });
    Object.defineProperty(Deno, "memoryUsage", {
      configurable: true,
      value: () => MEMORY,
    });
    globalThis.fetch = () => Promise.resolve(fixtureResponse("control"));
    await import("./entrypoint.ts");
    assertEquals(handlers.length, 1);
    const one = await (await handlers[0](
      requestFor("runtime-check", 1, CAPABILITY, OPERATOR_KEY),
    ))
      .json();
    const two = await (await handlers[0](
      requestFor("runtime-check", 2, CAPABILITY, OPERATOR_KEY),
    ))
      .json();
    assertEquals(one.outcome, "verified");
    assertEquals(two.outcome, "verified");
    assertEquals(one.worker, two.worker);
  } finally {
    Object.defineProperty(Deno.env, "get", {
      configurable: true,
      value: originalGet,
    });
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: originalServe,
    });
    Object.defineProperty(Deno, "memoryUsage", {
      configurable: true,
      value: originalMemory,
    });
    globalThis.fetch = originalFetch;
  }
});

Deno.test("test-only boundary rejects missing or wrong credentials, wrong run and expired run before R2", async () => {
  for (
    const mode of [
      "missing-key",
      "wrong-key",
      "wrong-capability",
      "missing-capability",
      "wrong-run",
      "expired",
    ]
  ) {
    const clock = new ManualClock();
    let calls = 0;
    const worker = makeWorker(clock, () => {
      calls++;
      throw Error("must not fetch");
    });
    const request = requestFor(
      mode === "wrong-run" ? "other-run" : "runtime-check",
      1,
      CAPABILITY,
      OPERATOR_KEY,
    );
    if (mode === "missing-key") request.headers.delete("authorization");
    if (mode === "wrong-key") {
      request.headers.set("authorization", `Bearer ${"e".repeat(64)}`);
    }
    if (mode === "wrong-capability") {
      request.headers.set("x-qualification-capability", "e".repeat(48));
    }
    if (mode === "missing-capability") {
      request.headers.delete("x-qualification-capability");
    }
    if (mode === "expired") clock.advance(LIMITS.runMs);
    const response = await worker.handle(request);
    assertEquals(
      response.status,
      mode === "wrong-run" ? 400 : mode === "expired" ? 409 : 403,
    );
    assertEquals(response.headers.get("x-cpm-auth-mode"), AUTH_MODE);
    const body = await response.text();
    assert(!body.includes(OPERATOR_KEY));
    assert(!body.includes(CAPABILITY));
    assertEquals(calls, 0);
    assertEquals(clock.active, 0);
  }
});

Deno.test("driver rejects stale auth-mode metadata and closes response without another attempt", async () => {
  for (const mode of [null, "product-jwt-v0"]) {
    let calls = 0, closed = false;
    const send = driverTransport({
      operatorKey: OPERATOR_KEY,
      publicKey: PUBLIC,
      fetchOnce: () => {
        calls++;
        const headers = new Headers({
          "x-cpm-runtime-deno": "test",
          "x-cpm-runtime-v8": "test",
        });
        if (mode) headers.set("x-cpm-auth-mode", mode);
        return Promise.resolve(
          new Response(
            new ReadableStream({
              cancel() {
                closed = true;
              },
            }),
            { headers },
          ),
        );
      },
    });
    await assertRejects(
      () =>
        send(
          requestFor("runtime-check", 26, CAPABILITY),
          new AbortController().signal,
        ),
      Error,
      "runtime_metadata",
    );
    assertEquals(calls, 1);
    assert(closed);
  }
  assertThrows(() =>
    driverTransport({
      operatorKey: "not-a-test-key",
      publicKey: PUBLIC,
      fetchOnce: () => {
        throw Error("never");
      },
    })
  );
});
