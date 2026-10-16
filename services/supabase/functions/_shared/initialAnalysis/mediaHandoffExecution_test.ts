import { assert, assertEquals } from "@std/assert";
import {
  executeOriginalMediaHandoff,
  type HandoffExecutionDependencies,
  readOriginalHandoffStatus,
} from "./mediaHandoffExecution.ts";
import { handoffExecutionFixture } from "./mediaHandoffTestFixtures.ts";
import { type HandoffIdentity } from "./mediaHandoffRows.ts";

async function fixture(index = 0, stage = 0) {
  const f = await handoffExecutionFixture(index, stage);
  const controller = new AbortController();
  const calls: string[] = [];
  const storageCalls: string[] = [];
  const objects = new Map<string, Uint8Array<ArrayBuffer>>();
  const types = new Map<string, string>();
  const url = (namespace: string, id: string) =>
    `https://00000000000000000000000000000000.r2.cloudflarestorage.com/synthetic-only/${namespace}/${f.identity.scan_id}/${id}`;
  for (const item of f.mapping.items) {
    for (
      const role of [item.source, ...(item.prepared ? [item.prepared] : [])]
    ) {
      const key = url("initial-preparation/v2", role.original_object_id);
      objects.set(key, new Uint8Array(role.bytes.byte_count));
      types.set(key, role.bytes.content_type);
    }
  }
  for (const o of f.mapping.objects) {
    const key = url("initial-analysis/v1", o.object_id);
    types.set(key, o.bytes.content_type);
    if (stage >= 2) objects.set(key, new Uint8Array(o.bytes.byte_count));
  }
  function checked(id: HandoffIdentity, name: string) {
    assertEquals(id, f.identity);
    calls.push(name);
  }
  const deps: HandoffExecutionDependencies = {
    bridge: {
      readState: (id) => {
        checked(id, "state");
        return Promise.resolve(f.state());
      },
      loadCopy: (id) => {
        checked(id, "load-copy");
        return Promise.resolve(f.io());
      },
      loadVerification: (id, token) => {
        checked(id, "load-verification");
        assertEquals(token, f.proof.claim.claim_token);
        return Promise.resolve(f.io());
      },
      beginCopy: (id) => {
        checked(id, "begin");
        return Promise.resolve(f.advance(1, "progress"));
      },
      recordObject: (id, object) => {
        checked(id, "object " + object);
        return Promise.resolve(f.advance(2, "progress", object));
      },
      completeCopy: (id) => {
        checked(id, "complete");
        return Promise.resolve(f.advance(3, "progress"));
      },
      claimVerification: (id) => {
        checked(id, "claim");
        return Promise.resolve(f.advance(4, "claim"));
      },
      settleVerification: (id, token) => {
        checked(id, "settle");
        assertEquals(token, f.proof.claim.claim_token);
        return Promise.resolve(f.advance(5, "verification"));
      },
      transfer: (id, digest) => {
        checked(id, "transfer");
        assertEquals(digest, f.proof.verification_receipt_digest);
        return Promise.resolve(f.advance(6, "transfer"));
      },
    },
    attest: (rows) => {
      calls.push("attest");
      assertEquals(rows.identity, f.identity);
      return Promise.resolve({
        copy_adapter_digest: f.handoff.copy_adapter_digest,
        verification_adapter_digest: f.handoff.verification_adapter_digest,
        protocol_artifact_digest: f.handoff.protocol_artifact_digest,
      });
    },
    storage: {
      sign: (_profile, request) => Promise.resolve(request),
      fetch: async (input) => {
        const r = input as Request;
        storageCalls.push(r.method + " " + r.url);
        if (r.method === "PUT") {
          assertEquals(r.headers.get("if-none-match"), "*");
          if (objects.has(r.url)) return new Response(null, { status: 412 });
          objects.set(r.url, new Uint8Array(await r.arrayBuffer()));
          return new Response(null, { status: 200 });
        }
        const bytes = objects.get(r.url);
        return bytes
          ? new Response(bytes.slice(), {
            headers: {
              "Content-Type": types.get(r.url)!,
              "Content-Length": String(bytes.length),
              "Cache-Control": "private, no-store",
            },
          })
          : new Response(null, { status: 404 });
      },
    },
  };
  return {
    ...f,
    controller,
    calls,
    storageCalls,
    objects,
    url,
    deps,
    run: () => executeOriginalMediaHandoff(deps, f.identity, controller.signal),
  };
}
for (const index of [0, 2, 3, 6]) {
  Deno.test(
    "handoff coordinator copies and verifies synthetic cohort " + index,
    async () => {
      const f = await fixture(index);
      const result = await f.run();
      assertEquals(result, {
        outcome: "transferred",
        transferDigest: f.proof.transfer_receipt_digest,
      });
      const put = f.storageCalls.filter((c) => c.startsWith("PUT "));
      assertEquals(
        put,
        f.mapping.objects.map((o: { object_id: string }) =>
          "PUT " + f.url("initial-analysis/v1", o.object_id)
        ).sort(),
      );
      const expectedSources: string[] = [];
      for (const item of f.mapping.items) {
        expectedSources.push(
          "GET " +
            f.url("initial-preparation/v2", item.source.original_object_id),
        );
        if (item.prepared) {
          expectedSources.push(
            "GET " +
              f.url("initial-preparation/v2", item.prepared.original_object_id),
          );
        }
      }
      assertEquals(
        f.storageCalls.filter((c) => c.includes("initial-preparation")).sort(),
        expectedSources.sort(),
      );
      assertEquals(
        f.storageCalls.filter((c) =>
          c.startsWith("GET ") && c.includes("initial-analysis")
        ).length,
        f.mapping.objects.length * 2,
      );
      assertEquals(f.calls.filter((c) => c === "transfer").length, 1);
    },
  );
}
for (const stage of [2, 3, 4, 5, 6]) {
  Deno.test(
    "handoff coordinator resumes only absent stage " + stage,
    async () => {
      const f = await fixture(0, stage);
      assertEquals((await f.run()).outcome, "transferred");
      assertEquals(f.storageCalls.filter((c) => c.startsWith("PUT")).length, 0);
      assertEquals(f.calls.includes("begin"), false);
      assertEquals(f.calls.includes("claim"), stage < 4);
      assertEquals(f.calls.includes("settle"), stage < 5);
      assertEquals(f.calls.includes("transfer"), stage < 6);
    },
  );
}
for (
  const method of [
    "beginCopy",
    "recordObject",
    "completeCopy",
    "claimVerification",
    "settleVerification",
    "transfer",
  ] as const
) {
  Deno.test(
    "handoff unknown committed " + method + " recovers once and stops",
    async () => {
      const f = await fixture();
      const old = f.deps.bridge[method];
      // The fixture acknowledges no outcome, even though its synthetic write ran.
      Object.assign(f.deps.bridge, {
        [method]: async (...args: Parameters<typeof old>) => {
          await Reflect.apply(old, f.deps.bridge, args);
          throw new Error("lost acknowledgement");
        },
      });
      const result = await f.run();
      assertEquals(result.outcome, "unresolved");
      assert(result.outcome === "unresolved" && result.recovered !== null);
      assertEquals(f.calls.at(-1), "state");
      const writers = f.calls.filter((c) =>
        ["begin", "complete", "claim", "settle", "transfer"].includes(c) ||
        c.startsWith("object ")
      );
      const expected = [
        "beginCopy",
        "recordObject",
        "completeCopy",
        "claimVerification",
        "settleVerification",
        "transfer",
      ].indexOf(method) + 1;
      assertEquals(writers.length, expected);
    },
  );
}
Deno.test("handoff malformed writer acknowledgement recovers without resend", async () => {
  const f = await fixture();
  f.deps.bridge.beginCopy = () => Promise.resolve({ progress: null });
  const result = await f.run();
  assertEquals(result.outcome, "unresolved");
  assertEquals(f.calls.filter((c) => c === "state").length, 3);
  assertEquals(f.storageCalls, []);
});
Deno.test("handoff cancellation during unknown SQL never starts recovery", async () => {
  const f = await fixture();
  f.deps.bridge.beginCopy = () => {
    f.controller.abort();
    return new Promise(() => {});
  };
  assertEquals((await f.run()).outcome, "unresolved");
  assertEquals(f.calls.filter((c) => c === "state").length, 2);
  assertEquals(f.storageCalls, []);
});
Deno.test("handoff saved artifact mismatch blocks copy", async () => {
  const f = await fixture();
  const old = f.deps.attest;
  f.deps.attest = async (...args) => ({
    ...await old(...args),
    copy_adapter_digest: "f".repeat(64),
  });
  assertEquals((await f.run()).outcome, "unresolved");
  assertEquals(f.storageCalls, []);
  assert(!f.calls.includes("begin"));
});
Deno.test("handoff fresh backend change blocks next I/O", async () => {
  const f = await fixture();
  let count = 0;
  f.deps.bridge.loadCopy = () => {
    const io = f.io();
    if (++count === 2) io.source_backend.private_bucket = "changed";
    return Promise.resolve(io);
  };
  assertEquals((await f.run()).outcome, "unresolved");
  assertEquals(f.storageCalls, []);
});
Deno.test("handoff unknown PUT does one exact readback and never retries", async () => {
  const f = await fixture();
  const old = f.deps.storage.fetch;
  f.deps.storage.fetch = async (...args) => {
    const r = await old(...args);
    if ((args[0] as Request).method === "PUT") throw new Error("lost put");
    return r;
  };
  assertEquals((await f.run()).outcome, "transferred");
  assertEquals(f.storageCalls.filter((c) => c.startsWith("PUT")).length, 1);
});
Deno.test("handoff marker is not overwritten or settled", async () => {
  const f = await fixture();
  f.objects.set(
    f.url("initial-analysis/v1", f.mapping.objects[0].object_id),
    new Uint8Array([9]),
  );
  assertEquals((await f.run()).outcome, "unresolved");
  assertEquals(f.calls.some((c) => c.startsWith("object ")), false);
});
Deno.test("handoff insufficient original copy reserve prevents first writer", async () => {
  const f = await fixture();
  f.setObserved(f.binding.phase_window.cutoffs.copy - 4999);
  assertEquals((await f.run()).outcome, "unresolved");
  assert(!f.calls.includes("begin"));
});
Deno.test("handoff bootstrap elapsed time is subtracted and loaders cannot extend it", async () => {
  const f = await fixture();
  f.setObserved(f.binding.phase_window.cutoffs.copy - 8000);
  let now = 0;
  using _clock = fakeClock(() => now);
  const old = f.deps.bridge.readState;
  f.deps.bridge.readState = async (...args) => {
    const value = await old(...args);
    now = 4000;
    return value;
  };
  assertEquals((await f.run()).outcome, "unresolved");
  assert(!f.calls.includes("begin"));
});
Deno.test("handoff explicit expired status remains read only", async () => {
  const f = await fixture(0, 4);
  f.setObserved(f.binding.phase_window.original_expires_at_ms + 1000);
  assert(
    await readOriginalHandoffStatus(
      f.deps.bridge,
      f.identity,
      f.controller.signal,
    ),
  );
  assertEquals(f.calls, ["state"]);
  assertEquals(f.storageCalls, []);
});

function fakeClock(now: () => number) {
  const original = Object.getOwnPropertyDescriptor(performance, "now");
  Object.defineProperty(performance, "now", { configurable: true, value: now });
  return {
    [Symbol.dispose]() {
      if (original) Object.defineProperty(performance, "now", original);
      else Reflect.deleteProperty(performance, "now");
    },
  };
}
for (const late of [false, true]) {
  Deno.test(
    "handoff independent verification finishes " +
      (late ? "after" : "just before") + " original cutoff",
    async () => {
      const f = await fixture(0, 4);
      const remaining = f.binding.phase_window.cutoffs.verification -
        f.getObserved();
      let now = 0;
      using _clock = fakeClock(() => now);
      const old = f.deps.storage.fetch;
      f.deps.storage.fetch = async (...args) => {
        const response = await old(...args);
        now = remaining + (late ? 1 : -1);
        return response;
      };
      assertEquals(
        (await f.run()).outcome,
        late ? "unresolved" : "transferred",
      );
      assertEquals(f.calls.includes("settle"), !late);
    },
  );
}
for (
  const [stage, cutoff, forbidden] of [[3, "verification_claim", "claim"], [
    5,
    "transfer",
    "transfer",
  ]] as const
) {
  Deno.test(
    "handoff " + cutoff + " reserve is checked before writer",
    async () => {
      const f = await fixture(0, stage);
      f.setObserved(f.binding.phase_window.cutoffs[cutoff] - 4999);
      assertEquals((await f.run()).outcome, "unresolved");
      assert(!f.calls.includes(forbidden));
    },
  );
}
Deno.test("handoff late bootstrap success ignoring timer cannot advance", async () => {
  const f = await fixture();
  let now = 0;
  using _clock = fakeClock(() => now);
  f.deps.bridge.readState = () => {
    now = 5001;
    return Promise.resolve(f.state());
  };
  assertEquals((await f.run()).outcome, "unresolved");
  assertEquals(f.storageCalls, []);
  assert(!f.calls.includes("begin"));
});
Deno.test("handoff late writer success ignores acknowledgement and stops after recovery", async () => {
  const f = await fixture();
  let now = 0;
  using _clock = fakeClock(() => now);
  const old = f.deps.bridge.beginCopy;
  f.deps.bridge.beginCopy = async (...args) => {
    const result = await old(...args);
    now = 5001;
    return result;
  };
  const result = await f.run();
  assert(result.outcome === "unresolved" && result.recovered !== null);
  assertEquals(f.calls.filter((c) => c === "state").length, 3);
  assertEquals(f.storageCalls, []);
});
Deno.test("handoff exhausted reconciliation never launches unknown-write recovery", async () => {
  const f = await fixture();
  const end = f.binding.phase_window.cutoffs.reconciliation - f.getObserved();
  let now = 0;
  using _clock = fakeClock(() => now);
  f.deps.bridge.beginCopy = () => {
    now = end;
    throw new Error("unknown");
  };
  assertEquals((await f.run()).outcome, "unresolved");
  assertEquals(f.calls.filter((c) => c === "state").length, 2);
});
Deno.test("handoff late recovery success is discarded", async () => {
  const f = await fixture();
  let now = 0;
  using _clock = fakeClock(() => now);
  const old = f.deps.bridge.readState;
  let reads = 0;
  f.deps.bridge.readState = async (...args) => {
    const result = await old(...args);
    if (++reads > 2) now = 5001;
    return result;
  };
  f.deps.bridge.beginCopy = () => {
    throw new Error("unknown");
  };
  assertEquals(await f.run(), { outcome: "unresolved", recovered: null });
  assertEquals(f.storageCalls, []);
});
for (const dependency of ["artifact", "loader", "signer", "fetch"] as const) {
  Deno.test(
    "handoff cancellation defeats " + dependency + " ignoring abort",
    async () => {
      const f = await fixture();
      const stall = () => {
        f.controller.abort();
        return new Promise<never>(() => {});
      };
      if (dependency === "artifact") f.deps.attest = stall;
      if (dependency === "loader") f.deps.bridge.loadCopy = stall;
      if (dependency === "signer") f.deps.storage.sign = stall;
      if (dependency === "fetch") f.deps.storage.fetch = stall;
      assertEquals(await f.run(), { outcome: "unresolved", recovered: null });
      assert(!f.calls.some((c) => c.startsWith("object ")));
      assert(!f.calls.includes("claim"));
    },
  );
}
Deno.test("handoff source mutation after verified GET cannot substitute the transmitted bytes", async () => {
  const f = await fixture();
  const old = f.deps.storage.sign;
  f.deps.storage.sign = async (...args) => {
    const request = await old(...args);
    if (request.method === "PUT") {
      for (const key of f.objects.keys()) {
        if (key.includes("initial-preparation")) {
          f.objects.set(key, new Uint8Array([9]));
        }
      }
    }
    return request;
  };
  assertEquals((await f.run()).outcome, "transferred");
});
Deno.test("handoff changed stage while resolving artifact stops before begin", async () => {
  const f = await fixture();
  const old = f.deps.attest;
  f.deps.attest = async (...args) => {
    const a = await old(...args);
    f.advance(1, "progress");
    return a;
  };
  assertEquals((await f.run()).outcome, "unresolved");
  assert(!f.calls.includes("begin"));
  assertEquals(f.storageCalls, []);
});
for (const method of ["GET", "PUT"]) {
  Deno.test(
    "handoff fresh context changed during " + method +
      " signing prevents fetch",
    async () => {
      const f = await fixture();
      const old = f.deps.storage.sign;
      let changed = false;
      f.deps.storage.sign = async (...args) => {
        const r = await old(...args);
        if (r.method === method) changed = true;
        return r;
      };
      f.deps.bridge.loadCopy = () => {
        const io = f.io();
        if (changed) io.source_backend.private_bucket = "changed";
        return Promise.resolve(io);
      };
      assertEquals((await f.run()).outcome, "unresolved");
      assertEquals(
        f.storageCalls.some((c) => c.startsWith(method + " ")),
        false,
      );
      assert(!f.calls.some((c) => c.startsWith("object ")));
    },
  );
}
