import { assertEquals } from "@std/assert";
import { evidenceDigest } from "./evidence.ts";
import {
  executePublicationPhotoCopy,
  type PhotoCopyDependencies,
} from "./photoCopyExecution.ts";
import { safePng } from "./testing/publicPhotoFixtures.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
async function fixture() {
  const events: string[] = [], bytes = safePng();
  const scope = { owner_id: id(1), observation_id: id(2), attempt_id: id(3) };
  const source = {
    media_id: id(4),
    object_id: id(5),
    content_type: "image/png",
    byte_count: bytes.length,
    sha256: await evidenceDigest(bytes),
  };
  const receipt = {
    ...scope,
    object_id: id(6),
    source: { ...source },
    lease_token: id(7),
    expires_at: "2099-01-01T00:10:00Z",
    ready_at: null as string | null,
  };
  const lease = { ...scope, object_id: id(6), lease_token: id(7) };
  const deps: PhotoCopyDependencies = {
    reserve: (received) => {
      events.push("reserve");
      assertEquals(received, scope);
      return Promise.resolve(structuredClone(receipt));
    },
    readSource: (received) => {
      events.push("read");
      assertEquals(received, source);
      return Promise.resolve(bytes);
    },
    storage: {
      writeOnce: (target, input) => {
        events.push("write");
        assertEquals(target, { object_id: id(6), source });
        assertEquals(input, bytes);
        return Promise.resolve();
      },
    },
    complete: (received) => {
      events.push("complete");
      assertEquals(received, lease);
      return Promise.resolve({ ...receipt, ready_at: "2099-01-01T00:00:01Z" });
    },
    abandon: (received) => {
      events.push("abandon");
      assertEquals(received, lease);
      return Promise.resolve();
    },
    erasure: {
      claim: (object) => {
        events.push("claim");
        assertEquals(object, id(6));
        return Promise.resolve({
          object_id: id(6),
          available_at: "2000-01-01T00:00:00Z",
          claim_token: id(8),
          claim_expires_at: "2099-01-01T00:00:00Z",
          erased_at: null,
          bound_at: null,
          revoked_at: null,
        });
      },
      erase: (object) => {
        events.push("erase");
        assertEquals(object, id(6));
        return Promise.resolve();
      },
      finish: (object, token, success) => {
        events.push("finish");
        assertEquals([object, token, success], [id(6), id(8), true]);
        return Promise.resolve(true);
      },
    },
  };
  return { events, bytes, scope, source, receipt, deps };
}
const fail = () => Promise.reject(new Error("synthetic failure"));

Deno.test("photo copy stops before I/O when its fixed reservation is already expired", async () => {
  const f = await fixture();
  f.deps.now = () => Date.parse(f.receipt.expires_at);
  assertEquals(
    await executePublicationPhotoCopy(f.scope, f.source, f.deps),
    "reconcile",
  );
  assertEquals(f.events, ["reserve", "abandon", "claim", "erase", "finish"]);
});
Deno.test("photo copy carries one deadline through I/O and cleans uncertain expiry without completing", async (t) => {
  for (const stage of ["read", "write", "complete"] as const) {
    await t.step(stage, async () => {
      const f = await fixture(), controller = new AbortController();
      const expiry = Date.parse(f.receipt.expires_at);
      let now = expiry - 25;
      f.deps.now = () => now;
      f.deps.deadlineSignal = (duration) => {
        assertEquals(duration, 25);
        return controller.signal;
      };
      const expire = () => {
        now = expiry;
        controller.abort();
      };
      f.deps.readSource = (_source, signal) => {
        assertEquals(signal, controller.signal);
        f.events.push("read");
        if (stage === "read") expire();
        return Promise.resolve(f.bytes);
      };
      f.deps.storage = {
        writeOnce: (_target, _bytes, signal) => {
          assertEquals(signal, controller.signal);
          f.events.push("write");
          if (stage === "write") expire();
          return Promise.resolve();
        },
      };
      f.deps.complete = (_lease, signal) => {
        assertEquals(signal, controller.signal);
        f.events.push("complete");
        expire();
        return Promise.resolve({
          ...f.receipt,
          ready_at: "2099-01-01T00:00:01Z",
        });
      };
      assertEquals(
        await executePublicationPhotoCopy(f.scope, f.source, f.deps),
        "reconcile",
      );
      const expected = ["reserve", "read"];
      if (stage !== "read") expected.push("write");
      if (stage === "complete") expected.push("complete");
      assertEquals(f.events, [
        ...expected,
        "abandon",
        "claim",
        "erase",
        "finish",
      ]);
    });
  }
});

Deno.test("photo copy reserves before I/O and marks staging ready only after verified write", async () => {
  const f = await fixture();
  assertEquals(
    await executePublicationPhotoCopy(f.scope, f.source, f.deps),
    "ready",
  );
  assertEquals(f.events, ["reserve", "read", "write", "complete"]);
});
Deno.test("photo copy replays ready staging without another write", async () => {
  const f = await fixture();
  f.receipt.ready_at = "2099-01-01T00:00:01Z";
  assertEquals(
    await executePublicationPhotoCopy(f.scope, f.source, f.deps),
    "ready",
  );
  assertEquals(f.events, ["reserve"]);
});
Deno.test("photo copy lost reservation response performs no source or destination I/O", async () => {
  const f = await fixture();
  f.deps.reserve = fail;
  assertEquals(
    await executePublicationPhotoCopy(f.scope, f.source, f.deps),
    "reconcile",
  );
  assertEquals(f.events, []);
});
Deno.test("photo copy rejects wrong scope, source, opaque key and malformed reservation without cleanup", async (t) => {
  const mutations: ((r: Record<string, unknown>) => void)[] = [
    (r) => r.owner_id = id(99),
    (r) => r.observation_id = id(99),
    (r) => r.attempt_id = id(99),
    (r) => r.source = {},
    (r) => (r.source as Record<string, unknown>).sha256 = "0".repeat(64),
    (r) => r.object_id = id(5),
    (r) => r.object_id = id(1),
    (r) => r.lease_token = 5,
    (r) => r.expires_at = "invalid",
    (r) => r.ready_at = true,
    (r) => r.extra = true,
  ];
  for (const [index, mutate] of mutations.entries()) {
    await t.step(String(index), async () => {
      const f = await fixture();
      mutate(f.receipt);
      assertEquals(
        await executePublicationPhotoCopy(f.scope, f.source, f.deps),
        "reconcile",
      );
      assertEquals(f.events, ["reserve"]);
    });
  }
});
Deno.test("photo copy verifies private digest and container before calling public writer", async (t) => {
  for (const malformedContainer of [false, true]) {
    await t.step(String(malformedContainer), async () => {
      const f = await fixture();
      f.bytes[0] = 0;
      if (malformedContainer) {
        f.source.sha256 = await evidenceDigest(f.bytes);
        f.receipt.source = { ...f.source };
      }
      assertEquals(
        await executePublicationPhotoCopy(f.scope, f.source, f.deps),
        "reconcile",
      );
      assertEquals(f.events, [
        "reserve",
        "read",
        "abandon",
        "claim",
        "erase",
        "finish",
      ]);
    });
  }
});
Deno.test("photo copy freezes caller account, source and receipt before asynchronous work", async () => {
  const f = await fixture(), original = structuredClone(f.receipt);
  f.deps.reserve = (scope) => {
    assertEquals(scope.owner_id, id(1));
    f.scope.owner_id = id(99);
    f.source.object_id = id(99);
    return Promise.resolve(f.receipt);
  };
  f.deps.readSource = (source) => {
    assertEquals(source, original.source);
    f.receipt.object_id = id(99);
    f.receipt.lease_token = id(99);
    return Promise.resolve(f.bytes);
  };
  f.deps.storage = {
    writeOnce: (target) => {
      assertEquals(target, { object_id: id(6), source: original.source });
      return Promise.resolve();
    },
  };
  f.deps.complete = (scope) => {
    assertEquals(scope, {
      owner_id: id(1),
      observation_id: id(2),
      attempt_id: id(3),
      object_id: id(6),
      lease_token: id(7),
    });
    return Promise.resolve({ ...original, ready_at: "2099-01-01T00:00:01Z" });
  };
  assertEquals(
    await executePublicationPhotoCopy(f.scope, f.source, f.deps),
    "ready",
  );
});
Deno.test("photo copy retries only exact completion after lost acknowledgement", async () => {
  const f = await fixture(), complete = f.deps.complete;
  let calls = 0;
  f.deps.complete = async (scope, signal) => {
    const result = await complete(scope, signal);
    if (++calls === 1) throw new Error("lost ack");
    return result;
  };
  assertEquals(
    await executePublicationPhotoCopy(f.scope, f.source, f.deps),
    "ready",
  );
  assertEquals(f.events, ["reserve", "read", "write", "complete", "complete"]);
});
Deno.test("photo copy cleans an uncertain write even if deletion removed private receipt", async () => {
  const f = await fixture();
  f.deps.storage = {
    writeOnce: () => {
      f.events.push("write");
      return fail();
    },
  };
  f.deps.abandon = () => {
    f.events.push("abandon");
    return fail();
  };
  assertEquals(
    await executePublicationPhotoCopy(f.scope, f.source, f.deps),
    "reconcile",
  );
  assertEquals(f.events, [
    "reserve",
    "read",
    "write",
    "abandon",
    "claim",
    "erase",
    "finish",
  ]);
});
Deno.test("photo copy completion failure cannot erase a concurrent valid bound publication", async () => {
  const f = await fixture();
  f.deps.complete = () => {
    f.events.push("complete");
    return fail();
  };
  f.deps.abandon = () => {
    f.events.push("abandon");
    return fail();
  };
  f.deps.erasure.claim = (target) => {
    assertEquals(target, id(6));
    f.events.push("claim");
    return Promise.resolve(null);
  };
  assertEquals(
    await executePublicationPhotoCopy(f.scope, f.source, f.deps),
    "reconcile",
  );
  assertEquals(f.events, [
    "reserve",
    "read",
    "write",
    "complete",
    "complete",
    "abandon",
    "claim",
  ]);
});
Deno.test("photo copy mismatched completion cannot authorize readiness or redirect cleanup", async (t) => {
  for (const key of ["object_id", "lease_token", "expires_at", "ready_at"]) {
    await t.step(key, async () => {
      const f = await fixture();
      f.deps.complete = () => {
        f.events.push("complete");
        return Promise.resolve({
          ...f.receipt,
          ready_at: "2099-01-01T00:00:01Z",
          [key]: key === "ready_at"
            ? null
            : key === "expires_at"
            ? "2099-01-01T00:20:00Z"
            : id(99),
        });
      };
      assertEquals(
        await executePublicationPhotoCopy(f.scope, f.source, f.deps),
        "reconcile",
      );
      assertEquals(f.events.slice(-4), ["abandon", "claim", "erase", "finish"]);
    });
  }
});
Deno.test("photo copy leaves durable cleanup recovery when target claim or marker fails", async (t) => {
  for (const failure of ["claim", "erase", "finish"] as const) {
    await t.step(failure, async () => {
      const f = await fixture();
      f.deps.storage = { writeOnce: fail };
      f.deps.erasure[failure] = fail;
      if (failure === "erase") {
        f.deps.erasure.finish = (_object, _token, success) => {
          assertEquals(success, false);
          return Promise.resolve(true);
        };
      }
      assertEquals(
        await executePublicationPhotoCopy(f.scope, f.source, f.deps),
        "reconcile",
      );
    });
  }
});

Deno.test("generic single photo cleanup ignores foreign IDs returned by an invalid adapter", async () => {
  const f = await fixture();
  const targets: (string | null)[] = [];
  f.deps.readSource = () => Promise.reject(new Error("synthetic failure"));
  f.deps.abandon = (() =>
    Promise.resolve([
      f.receipt.object_id,
      id(99),
    ])) as unknown as PhotoCopyDependencies["abandon"];
  f.deps.erasure.claim = (target) => {
    targets.push(target);
    return Promise.resolve(null);
  };
  assertEquals(
    await executePublicationPhotoCopy(f.scope, f.source, f.deps),
    "reconcile",
  );
  assertEquals(targets, [f.receipt.object_id]);
});
