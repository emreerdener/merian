import { assertEquals, assertRejects } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { initialMediaHash } from "./mediaBinding.ts";
import { initialDeadline, initialRemainingDeadline } from "./transport.ts";
import {
  closeInitialCpmPhotoWrite,
  type CpmWriteClosureDependencies,
  type CpmWriteClosureInput,
  type CpmWriteClosureReceipt,
} from "./cpmPhotoWriteClosure.ts";

async function fixture(marker = false) {
  const id = (n: number) =>
    `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
  const now = Date.now();
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
  const configuration_digest = await initialMediaHash(
    new TextEncoder().encode(
      `merian.initial-analysis.media.backend.v1\n${
        initialCanonicalText(config)
      }`,
    ),
  );
  const bytes = new Uint8Array([255, 216, 255, 1]);
  const input: CpmWriteClosureInput = {
    binding: {
      attempt_id: id(1),
      scan_id: id(2),
      object_id: id(3),
      assignment_digest: "a".repeat(64),
      backend_generation: id(4),
      backend_configuration_digest: configuration_digest,
      issued_at_ms: now - 1000,
      verification_policy_digest: "b".repeat(64),
    },
    target: marker ? { outcome: "retired_marker" } : {
      outcome: "live_object",
      role: "source",
      byte_count: bytes.length,
      content_type: "image/jpeg",
      sha256: await initialMediaHash(bytes),
    },
    backend: { ...config, configuration_digest },
    admission_expires_at_ms: now + 30_000,
    erasure_claim: marker
      ? { token: id(5), issued_at_ms: now - 100, expires_at_ms: now + 59_900 }
      : null,
  };
  const headers = {
    "content-type": marker ? "application/octet-stream" : "image/jpeg",
    "content-length": marker ? "0" : String(bytes.length),
    "cache-control": "private, no-store",
    ...(marker ? { "x-amz-meta-merian-state": "erased-v1" } : {}),
  };
  const calls: string[] = [];
  const controller = new AbortController();
  let saved: CpmWriteClosureReceipt | null = null;
  let token: string | null = null;
  const deps: CpmWriteClosureDependencies = {
    bridge: {
      readReceipt: (attempt, outcome) => {
        calls.push("read");
        assertEquals(attempt, id(1));
        assertEquals(outcome, marker ? "retired_marker" : "live_object");
        return Promise.resolve(saved);
      },
      load: () => {
        calls.push("load");
        return Promise.resolve(input);
      },
      requireCurrent: (state) => {
        calls.push("current");
        for (
          const part of [state, state.binding, state.target, state.backend]
        ) assertEquals(Object.isFrozen(part), true);
        return Promise.resolve();
      },
      settle: (value, original) => {
        calls.push("settle");
        saved = { ...value };
        token = original;
        return Promise.resolve(saved);
      },
    },
    storage: {
      sign: (_profile, request) => {
        calls.push("sign");
        return Promise.resolve(request);
      },
      fetch: () => {
        calls.push("fetch");
        return Promise.resolve(
          new Response(marker ? new Uint8Array() : bytes.slice(), { headers }),
        );
      },
    },
  };
  return {
    input,
    deps,
    calls,
    controller,
    id,
    saved: () => saved,
    token: () => token,
    save: (value: CpmWriteClosureReceipt) => {
      saved = value;
    },
    run: () =>
      closeInitialCpmPhotoWrite(
        deps,
        id(1),
        marker ? "retired_marker" : "live_object",
        controller.signal,
      ),
  };
}
for (const role of ["source", "ai", "display"] as const) {
  Deno.test(`CPM closure coordinator observes ${role} before one exact settlement`, async () => {
    const f = await fixture();
    if (f.input.target.outcome === "live_object") f.input.target.role = role;
    const result = await f.run();
    assertEquals(result.outcome, "settled");
    assertEquals(f.calls, [
      "read",
      "load",
      "current",
      "sign",
      "current",
      "fetch",
      "current",
      "settle",
    ]);
    assertEquals(result.receipt, f.saved());
    assertEquals(Object.isFrozen(result), true);
    assertEquals(Object.isFrozen(result.receipt), true);
    assertEquals(f.token(), null);
  });
}
Deno.test("CPM marker closure keeps original claim through asynchronous mutation", async () => {
  const f = await fixture(true), original = f.input.erasure_claim!.token;
  const current = f.deps.bridge.requireCurrent;
  f.deps.bridge.requireCurrent = (snapshot, signal) => {
    f.input.erasure_claim!.token = f.id(6);
    f.input.binding.verification_policy_digest = "c".repeat(64);
    assertEquals(snapshot.erasure_claim!.token, original);
    return current(snapshot, signal);
  };
  const result = await f.run();
  assertEquals(f.token(), original);
  assertEquals(result.receipt.policy_digest, "b".repeat(64));
  assertEquals(
    result.receipt.claim_digest,
    await initialMediaHash(
      new TextEncoder().encode(
        `merian.initial-analysis.cpm-erasure-claim.v1\n${original}`,
      ),
    ),
  );
});
Deno.test("CPM saved closure recovers without loading private state or storage IO", async () => {
  const f = await fixture(true);
  const saved = {
    attempt_id: f.id(1),
    outcome: "retired_marker" as const,
    policy_digest: "c".repeat(64),
    observed_at: "1970-01-01T00:00:01.123456Z",
    claim_digest: "d".repeat(64),
  };
  f.save(saved);
  assertEquals(await f.run(), { outcome: "replay", receipt: saved });
  assertEquals(f.calls, ["read"]);
});
Deno.test("CPM unknown settlement reads exact receipt once without re-observation", async () => {
  const f = await fixture();
  const settle = f.deps.bridge.settle;
  f.deps.bridge.settle = async (...args) => {
    await settle(...args);
    throw new Error("synthetic lost acknowledgement");
  };
  assertEquals((await f.run()).outcome, "replay");
  assertEquals(f.calls.filter((x) => x === "read").length, 2);
  assertEquals(f.calls.filter((x) => x === "fetch").length, 1);
  assertEquals(f.calls.filter((x) => x === "settle").length, 1);
});
Deno.test("CPM unknown settlement cannot adopt changed policy time claim or outcome", async () => {
  for (
    const mutation of [
      { attempt_id: "00000000-0000-4000-8000-000000000099" },
      { policy_digest: "e".repeat(64) },
      { observed_at: "1970-01-01T00:00:00.000001Z" },
      { claim_digest: "f".repeat(64) },
      { outcome: "live_object" },
    ]
  ) {
    const f = await fixture(true);
    f.deps.bridge.settle = (value) => {
      f.calls.push("settle");
      f.save({ ...value, ...mutation } as CpmWriteClosureReceipt);
      return Promise.reject(new Error("unknown"));
    };
    await assertRejects(f.run, Error, "initial_media_unavailable");
    assertEquals(f.calls.filter((x) => x === "settle").length, 1);
    assertEquals(f.calls.filter((x) => x === "fetch").length, 1);
  }
});
Deno.test("CPM empty recovery after unknown settlement remains unresolved", async () => {
  const f = await fixture();
  f.deps.bridge.settle = () => {
    f.calls.push("settle");
    return Promise.reject(new Error("unknown"));
  };
  await assertRejects(f.run, Error, "initial_media_unavailable");
  assertEquals(f.calls.filter((x) => x === "read").length, 2);
  assertEquals(f.calls.filter((x) => x === "load").length, 1);
});
Deno.test("CPM mismatched storage never enters settlement or receipt recovery", async () => {
  const f = await fixture();
  f.deps.storage.fetch = () => {
    f.calls.push("fetch");
    return Promise.resolve(new Response(null, { status: 404 }));
  };
  await assertRejects(f.run, Error, "initial_media_unavailable");
  assertEquals(f.calls.includes("settle"), false);
  assertEquals(f.calls.filter((x) => x === "read").length, 1);
});
Deno.test("CPM closure rejects substituted attempt or outcome before signing", async () => {
  for (const kind of ["attempt", "outcome"] as const) {
    const f = await fixture();
    if (kind === "attempt") f.input.binding.attempt_id = f.id(9);
    else f.input.target = { outcome: "retired_marker" };
    await assertRejects(f.run, Error, "initial_media_unavailable");
    assertEquals(f.calls, ["read", "load"]);
  }
});
Deno.test("CPM closure protects settlement reserve and refuses invalid marker claims", async () => {
  for (const kind of ["expired", "budget", "long", "missing"] as const) {
    const f = await fixture(true);
    if (kind === "expired") {
      f.input.erasure_claim!.expires_at_ms = Date.now() - 1;
    }
    if (kind === "budget") {
      f.input.erasure_claim!.expires_at_ms = Date.now() + 4000;
    }
    if (kind === "long") {
      f.input.erasure_claim!.expires_at_ms = Date.now() + 120_000;
    }
    if (kind === "missing") f.input.erasure_claim = null;
    await assertRejects(f.run, Error, "initial_media_unavailable");
    assertEquals(f.calls, ["read", "load"]);
  }
});
Deno.test("CPM late load after abort cannot begin observation", async () => {
  const f = await fixture();
  let resolve!: (value: CpmWriteClosureInput) => void;
  let entered!: () => void;
  const loaded = new Promise<void>((r) => {
    entered = r;
  });
  f.deps.bridge.load = () => {
    f.calls.push("load");
    entered();
    return new Promise((r) => {
      resolve = r;
    });
  };
  const pending = f.run();
  await loaded;
  f.controller.abort();
  await assertRejects(() => pending, Error, "initial_media_unavailable");
  resolve(f.input);
  await Promise.resolve();
  await Promise.resolve();
  assertEquals(f.calls, ["read", "load"]);
});
Deno.test("CPM abort during unknown settlement does not recover or repeat IO", async () => {
  const f = await fixture();
  let resolve!: (value: unknown) => void;
  let entered!: () => void;
  const settling = new Promise<void>((r) => {
    entered = r;
  });
  f.deps.bridge.settle = (value) => {
    f.calls.push("settle");
    f.save({ ...value });
    entered();
    return new Promise((r) => {
      resolve = r;
    });
  };
  const pending = f.run();
  await settling;
  f.controller.abort();
  await assertRejects(() => pending, Error, "initial_media_unavailable");
  resolve(f.saved());
  await Promise.resolve();
  await Promise.resolve();
  assertEquals(f.calls.filter((x) => x === "read").length, 1);
  assertEquals(f.calls.filter((x) => x === "settle").length, 1);
});
Deno.test("CPM lifecycle denial after read suppresses settlement", async () => {
  const f = await fixture();
  let checks = 0;
  f.deps.bridge.requireCurrent = () =>
    ++checks === 3 ? Promise.reject(new Error("retired")) : Promise.resolve();
  await assertRejects(f.run, Error, "initial_media_unavailable");
  assertEquals(f.calls.includes("fetch"), true);
  assertEquals(f.calls.includes("settle"), false);
});

Deno.test("CPM initial receipt latency cannot consume the settlement reserve", async () => {
  const f = await fixture();
  const descriptor = Object.getOwnPropertyDescriptor(performance, "now");
  const now = performance.now.bind(performance);
  let extra = 0;
  Object.defineProperty(performance, "now", {
    configurable: true,
    value: () => now() + extra,
  });
  try {
    f.deps.bridge.readReceipt = () => {
      f.calls.push("read");
      extra = 16_000;
      return Promise.resolve(null);
    };
    await assertRejects(f.run, Error, "initial_media_unavailable");
    assertEquals(f.calls, ["read", "load"]);
  } finally {
    if (descriptor) Object.defineProperty(performance, "now", descriptor);
    else Reflect.deleteProperty(performance, "now");
  }
});
Deno.test("CPM live admission expiry and stray claim block storage", async () => {
  for (const kind of ["expired", "claim"] as const) {
    const f = await fixture();
    if (kind === "expired") f.input.admission_expires_at_ms = Date.now() - 1;
    else {f.input.erasure_claim = {
        token: f.id(5),
        issued_at_ms: Date.now(),
        expires_at_ms: Date.now() + 60_000,
      };}
    await assertRejects(f.run, Error, "initial_media_unavailable");
    assertEquals(f.calls, ["read", "load"]);
  }
});
Deno.test("CPM malformed historical receipt never falls through to fresh IO", async () => {
  const f = await fixture();
  f.deps.bridge.readReceipt = () => {
    f.calls.push("read");
    return Promise.resolve({
      attempt_id: f.id(9),
      outcome: "live_object",
      policy_digest: "b".repeat(64),
      observed_at: "1970-01-01T00:00:01.123456Z",
      claim_digest: null,
    });
  };
  await assertRejects(f.run, Error, "initial_media_unavailable");
  assertEquals(f.calls, ["read"]);
});

Deno.test("CPM inherited deadline below reserve refuses fresh observation", async () => {
  const f = await fixture();
  await assertRejects(
    () =>
      initialDeadline(
        f.controller.signal,
        4000,
        (signal) =>
          closeInitialCpmPhotoWrite(f.deps, f.id(1), "live_object", signal),
      ),
    Error,
    "initial_media_unavailable",
  );
  assertEquals(f.calls, ["read", "load"]);
});

Deno.test("CPM storage budget preserves settlement reserve under tighter parent", async () => {
  const f = await fixture();
  const sign = f.deps.storage.sign;
  let storageBudget = Infinity;
  let settlementBudget = 0;
  f.deps.storage.sign = (profile, request, signal) => {
    storageBudget = initialRemainingDeadline(signal);
    return sign(profile, request, signal);
  };
  const settle = f.deps.bridge.settle;
  f.deps.bridge.settle = (value, claim, signal) => {
    settlementBudget = initialRemainingDeadline(signal);
    return settle(value, claim, signal);
  };
  await initialDeadline(
    f.controller.signal,
    10_000,
    (signal) =>
      closeInitialCpmPhotoWrite(f.deps, f.id(1), "live_object", signal),
  );
  assertEquals(storageBudget > 0 && storageBudget <= 5000, true);
  assertEquals(settlementBudget > 5000 && settlementBudget <= 10_000, true);
  assertEquals(f.calls.filter((x) => x === "settle").length, 1);
});
