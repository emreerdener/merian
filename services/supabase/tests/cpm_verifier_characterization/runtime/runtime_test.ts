import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { authAdapter } from "./auth.ts";
import {
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
const OTHER = "00000000-0000-4000-8000-000000000002";
const PUBLIC = "sb_publishable_synthetic_qualification_key_0000";
function environment(clock: ManualClock): Record<string, string> {
  return {
    SUPABASE_URL: PROJECT_URL,
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: PUBLIC }),
    CPM_Q_RUN: "runtime-check",
    CPM_Q_OPERATOR_ID: ID,
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
        "SUPABASE_PUBLISHABLE_KEYS",
        "SUPABASE_ANON_KEY",
      ].includes(name)
    ),
  );
  for (
    const [key, value] of Object.entries({
      SUPABASE_URL: "https://wrong.supabase.co",
      CPM_Q_OPERATOR_ID: "operator",
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
Deno.test("Auth SDK uses only one bounded getUser request, exact subject and abort signal", async () => {
  for (const id of [ID, OTHER]) {
    let calls = 0;
    const abort = new AbortController();
    const authenticate = authAdapter({
      publicKey: PUBLIC,
      operatorID: ID,
      fetchOnce: (request) => {
        calls++;
        assertEquals(request.url, `${PROJECT_URL}/auth/v1/user`);
        assertEquals(request.method, "GET");
        assertEquals(
          request.headers.get("authorization"),
          "Bearer synthetic-jwt",
        );
        assertEquals(request.headers.get("apikey"), PUBLIC);
        assertEquals(request.redirect, "error");
        assertEquals(request.signal.aborted, false);
        return Promise.resolve(
          Response.json({ id, aud: "authenticated", role: "authenticated" }),
        );
      },
    });
    assertEquals(
      await authenticate("synthetic-jwt", abort.signal),
      id === ID ? OPERATOR_ALIAS : null,
    );
    assertEquals(calls, 1);
  }
});
Deno.test("Auth failures never retry or disclose upstream response", async () => {
  for (const status of [401, 403, 429, 500]) {
    let calls = 0;
    const auth = authAdapter({
      publicKey: PUBLIC,
      operatorID: ID,
      fetchOnce: () => {
        calls++;
        return Promise.resolve(
          Response.json({ message: "synthetic denial" }, { status }),
        );
      },
    });
    if (status === 401 || status === 403) {
      assertEquals(await auth("invalid", new AbortController().signal), null);
    } else {await assertRejects(
        () => auth("invalid", new AbortController().signal),
        Error,
        "auth_transport",
      );}
    assertEquals(calls, 1);
  }
  const huge = authAdapter({
    publicKey: PUBLIC,
    operatorID: ID,
    fetchOnce: () => Promise.resolve(new Response(" ".repeat(65_537))),
  });
  await assertRejects(
    () => huge("invalid", new AbortController().signal),
    Error,
    "auth_transport",
  );
});
Deno.test("Auth cancellation propagates during acquisition and stalled response body", async () => {
  for (const bodyPhase of [false, true]) {
    const started = deferred<void>(), abort = new AbortController();
    let seenAbort = false;
    const auth = authAdapter({
      publicKey: PUBLIC,
      operatorID: ID,
      fetchOnce: (request) => {
        started.resolve();
        if (bodyPhase) {
          return Promise.resolve(
            new Response(
              new ReadableStream({
                start(controller) {
                  request.signal.addEventListener("abort", () => {
                    seenAbort = true;
                    controller.error(Error("abort"));
                  }, { once: true });
                },
              }),
            ),
          );
        }
        return new Promise((_resolve, reject) =>
          request.signal.addEventListener("abort", () => {
            seenAbort = true;
            reject(Error("abort"));
          }, { once: true })
        );
      },
    });
    const work = auth("synthetic", abort.signal);
    await started.promise;
    abort.abort();
    await assertRejects(() => work);
    assert(seenAbort);
  }
});
Deno.test("real runtime composition rejects invalid caller before R2 and retains shared reader gate", async () => {
  const clock = new ManualClock(),
    opened = deferred<void>(),
    release = deferred<void>();
  let gets = 0, auths = 0;
  const worker = makeWorker(clock, async (request) => {
    if (request.url === `${PROJECT_URL}/auth/v1/user`) {
      auths++;
      return request.headers.get("authorization") === `Bearer ${DENIED_BEARER}`
        ? Response.json({ message: "synthetic denial" }, { status: 401 })
        : Response.json({ id: ID });
    }
    gets++;
    assert(request.url.includes(`/${BUCKET}/cpm-verifier/runtime-check/`));
    assertEquals(request.method, "GET");
    assertEquals(request.redirect, "error");
    opened.resolve();
    await release.promise;
    return fixtureResponse("a");
  });
  const first = worker.handle(requestFor("runtime-check", 21, CAPABILITY));
  await opened.promise;
  const busy =
    await (await worker.handle(requestFor("runtime-check", 22, CAPABILITY)))
      .json();
  assertEquals(busy.outcome, "busy");
  const denied = await worker.handle(
    requestFor("runtime-check", 26, CAPABILITY, DENIED_BEARER),
  );
  assertEquals(denied.status, 403);
  assertEquals(denied.headers.get("x-merian-handler"), "1");
  assertEquals(gets, 1);
  assertEquals(auths, 3);
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
      (await worker.handle(requestFor("runtime-check", 1, CAPABILITY))).status,
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
    if (req.url === `${PROJECT_URL}/auth/v1/user`) {
      return Promise.resolve(
        req.headers.get("authorization") === `Bearer ${DENIED_BEARER}`
          ? Response.json({ message: "denied" }, { status: 401 })
          : Response.json({ id: ID }),
      );
    }
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
      bearer: "synthetic-operator-bearer",
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
    const worker = makeWorker(clock, (req) =>
      Promise.resolve(
        req.url === `${PROJECT_URL}/auth/v1/user`
          ? req.headers.get("authorization") === `Bearer ${DENIED_BEARER}`
            ? Response.json({ message: "denied" }, { status: 401 })
            : Response.json({ id: ID })
          : fixtureResponse("control"),
      ));
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
        bearer: "synthetic-operator-bearer",
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
    globalThis.fetch = (input) =>
      Promise.resolve(
        new Request(input).url === `${PROJECT_URL}/auth/v1/user`
          ? Response.json({ id: ID })
          : fixtureResponse("control"),
      );
    await import("./entrypoint.ts");
    assertEquals(handlers.length, 1);
    const one =
      await (await handlers[0](requestFor("runtime-check", 1, CAPABILITY)))
        .json();
    const two =
      await (await handlers[0](requestFor("runtime-check", 2, CAPABILITY)))
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

Deno.test("Auth explicitly cancels an abort-ignorant stalled body and awaits cancellation", async () => {
  const started = deferred<void>(),
    closure = deferred<void>(),
    abort = new AbortController();
  let cancelled = false, settled = false;
  const auth = authAdapter({
    publicKey: PUBLIC,
    operatorID: ID,
    fetchOnce: () =>
      Promise.resolve(
        new Response(
          new ReadableStream({
            pull() {
              started.resolve();
            },
            cancel() {
              cancelled = true;
              return closure.promise;
            },
          }),
        ),
      ),
  });
  const work = auth("synthetic", abort.signal).then(() => {
    settled = true;
  }, () => {
    settled = true;
  });
  await started.promise;
  abort.abort();
  for (let i = 0; i < 20; i++) await Promise.resolve();
  assert(cancelled);
  assertEquals(settled, false);
  closure.resolve();
  await work;
  assert(settled);
});
