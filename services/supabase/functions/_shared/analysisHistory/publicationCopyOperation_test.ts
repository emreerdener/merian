import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  executePublicationCopyOperation,
  type PublicationCopyOperationDependencies,
} from "./publicationCopyOperation.ts";
import { evidenceDigest } from "./evidence.ts";
import {
  joined,
  pngChunk,
  pngParts,
  safePng,
} from "./testing/publicPhotoFixtures.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
async function fixture(count = 2) {
  const bytes = safePng(),
    events: string[] = [],
    targets: (string | null)[] = [];
  let clock = Date.parse("2026-10-04T00:00:00Z"), published = false;
  const scope = {
    owner_id: id(1),
    observation_id: id(2),
    operation_id: id(3),
    work_token: id(4),
  };
  const digest = await evidenceDigest(bytes);
  const members = Array.from(
    { length: count },
    (_, i) => ({
      attempt_id: id(10 + i),
      source: {
        media_id: id(20 + i),
        object_id: id(30 + i),
        content_type: "image/png",
        byte_count: bytes.length,
        sha256: digest,
      },
    }),
  );
  const expires_at = new Date(clock + 600_000).toISOString();
  const copies = members.map((m, i) => ({
    owner_id: scope.owner_id,
    observation_id: scope.observation_id,
    attempt_id: m.attempt_id,
    object_id: id(40 + i),
    lease_token: id(50 + i),
    source: { ...m.source },
    expires_at,
    ready_at: null as string | null,
  }));
  const receipt = {
    schema_version: 1,
    operation_id: scope.operation_id,
    observation_id: scope.observation_id,
    analysis_id: id(60),
    request_id: id(61),
    post_id: id(62),
    status: "admitted",
  };
  const value = () => ({ expires_at, copies: structuredClone(copies) });
  const state = {
    reserved: false,
    lostBind: false,
    badBind: false,
    badRead: false,
    bindDenied: false,
  };
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => ({
      abortSignal: (signal: AbortSignal) => {
        events.push(name);
        signal.throwIfAborted();
        assertEquals(args.p_owner, id(1));
        assertEquals(args.p_operation, id(3));
        if (name === "read_publication_copy_cohort") {
          if (state.badRead) {
            return Promise.reject(new Error("synthetic read loss"));
          }
          return Promise.resolve({
            data: {
              reservation: state.reserved ? value() : null,
              publication: published ? { ...receipt } : null,
            },
            error: null,
          });
        }
        if (name === "reserve_publication_copy_cohort") {
          state.reserved = true;
          return Promise.resolve({ data: value(), error: null });
        }
        if (name === "complete_publication_copy_cohort_photo") {
          const c = copies.find((c) => c.attempt_id === args.p_attempt)!;
          c.ready_at = new Date(clock).toISOString();
          return Promise.resolve({ data: { ...c }, error: null });
        }
        if (name === "bind_publication_copy_cohort") {
          assert(copies.every((c) => c.ready_at !== null));
          if (state.bindDenied) {
            return Promise.reject(new Error("synthetic denial"));
          }
          published = true;
          if (state.lostBind) {
            return Promise.reject(new Error("synthetic lost binding"));
          }
          return Promise.resolve({
            data: state.badBind
              ? { ...receipt, operation_id: id(99) }
              : { ...receipt },
            error: null,
          });
        }
        if (name === "abandon_publication_copy_cohort") {
          return Promise.resolve({
            data: published ? { abandoned: false } : {
              abandoned: true,
              object_ids: copies.map((c) => c.object_id),
            },
            error: null,
          });
        }
        throw new Error("unexpected rpc");
      },
    }),
  } as unknown as SupabaseClient;
  const timers: number[] = [];
  const deps: PublicationCopyOperationDependencies = {
    now: () => clock,
    deadlineSignal: (ms) => {
      timers.push(ms);
      return new AbortController().signal;
    },
    readSource: (source) => {
      events.push(`read:${source.media_id}`);
      return Promise.resolve(bytes);
    },
    storage: {
      writeOnce: (target, input) => {
        assertEquals(input, bytes);
        events.push(`write:${target.object_id}`);
        return Promise.resolve();
      },
    },
    erasure: {
      claim: (target) => {
        targets.push(target);
        return Promise.resolve(null);
      },
      erase: () => {
        throw new Error("unclaimed erase");
      },
      finish: () => {
        throw new Error("unclaimed finish");
      },
    },
  };
  return {
    bytes,
    events,
    scope,
    members,
    copies,
    client,
    state,
    deps,
    timers,
    targets,
    expires: new Date(clock + 120_000).toISOString(),
    advance: (ms: number) => {
      clock += ms;
    },
    publish: () => {
      published = true;
      state.reserved = true;
    },
    run: () =>
      executePublicationCopyOperation(
        client,
        scope,
        members,
        new Date(Date.parse("2026-10-04T00:00:00Z") + 120_000).toISOString(),
        deps,
      ),
  };
}
Deno.test("copy operation preflights all six exact sources before any public write and binds once", async () => {
  const f = await fixture(6);
  assertEquals(await f.run(), "published");
  const read = f.events.filter((e) => e.startsWith("read:"));
  assertEquals(read.length, 6);
  assert(
    f.events.lastIndexOf(read[5]) <
      f.events.findIndex((e) => e.startsWith("write:")),
  );
  assertEquals(f.events.filter((e) => e.startsWith("write:")).length, 6);
  assertEquals(
    f.events.filter((e) => e === "bind_publication_copy_cohort").length,
    1,
  );
  assertEquals(f.targets, []);
  assertEquals(f.timers.slice(0, 3), [110000, 80000, 92000]);
});
Deno.test("copy operation recovers publication without fresh authorization or media I/O even after lease expiry", async () => {
  const f = await fixture();
  f.publish();
  f.advance(130000);
  assertEquals(await f.run(), "published");
  assertEquals(f.events, ["read_publication_copy_cohort"]);
});
Deno.test("copy operation corrupt final source prevents every write and targets entire reserved cohort", async () => {
  const f = await fixture();
  f.deps.readSource = (s) =>
    Promise.resolve(
      s.media_id === id(21) ? new Uint8Array(f.bytes.length) : f.bytes,
    );
  assertEquals(await f.run(), "reconcile");
  assert(!f.events.some((e) => e.startsWith("write:")));
  assertEquals(f.targets, [id(40), id(41)]);
});
Deno.test("copy operation recovers lost or malformed binding reply before cleanup", async () => {
  for (const mode of ["lostBind", "badBind"] as const) {
    const f = await fixture();
    f.state[mode] = true;
    assertEquals(await f.run(), "published");
    assertEquals(f.targets, []);
    assert(
      f.events.lastIndexOf("read_publication_copy_cohort") >
        f.events.indexOf("bind_publication_copy_cohort"),
    );
  }
});
Deno.test("copy operation binding denial cleans all siblings without another write or bind", async () => {
  const f = await fixture();
  f.state.bindDenied = true;
  assertEquals(await f.run(), "reconcile");
  assertEquals(f.targets, [id(40), id(41)]);
  assertEquals(
    f.events.filter((e) => e === "bind_publication_copy_cohort").length,
    1,
  );
});
Deno.test("copy operation expires fresh window across photos instead of resetting per-source budgets", async () => {
  const f = await fixture(6);
  let writes = 0;
  f.deps.storage = {
    writeOnce: () => {
      writes++;
      f.advance(81_000);
      return Promise.resolve();
    },
  };
  assertEquals(await f.run(), "reconcile");
  assertEquals(writes, 1);
  assert(!f.events.includes("bind_publication_copy_cohort"));
  assertEquals(new Set(f.targets), new Set(f.copies.map((c) => c.object_id)));
});
Deno.test("copy operation skips ready writes but freshly verifies every private source", async () => {
  const f = await fixture();
  f.state.reserved = true;
  f.copies[0].ready_at = "2026-10-04T00:00:00Z";
  assertEquals(await f.run(), "published");
  assertEquals(f.events.filter((e) => e.startsWith("read:")).length, 2);
  assertEquals(f.events.filter((e) => e.startsWith("write:")), [
    `write:${id(41)}`,
  ]);
});
Deno.test("copy operation freezes account and source values before asynchronous work", async () => {
  const f = await fixture();
  const running = f.run();
  f.scope.owner_id = id(99);
  f.members[0].source.object_id = id(98);
  assertEquals(await running, "published");
});
Deno.test("copy operation denies expired fresh work without reading or writing media", async () => {
  const f = await fixture();
  f.advance(100_000);
  assertEquals(await f.run(), "reconcile");
  assert(
    !f.events.some((e) => e.startsWith("read:") || e.startsWith("write:")),
  );
});
Deno.test("copy operation regains control from a noncooperative private read", async () => {
  const f = await fixture();
  const fresh = new AbortController();
  f.deps.deadlineSignal = (ms) =>
    ms === 80000 ? fresh.signal : new AbortController().signal;
  f.deps.readSource = () => {
    queueMicrotask(() => fresh.abort());
    return new Promise(() => {});
  };
  assertEquals(await f.run(), "reconcile");
  assertEquals(f.targets, [id(40), id(41)]);
});
Deno.test("copy operation bounds cleanup even if registry transport does not acknowledge abort", async () => {
  const f = await fixture();
  const overall = new AbortController();
  f.deps.deadlineSignal = (ms) =>
    ms === 110000 ? overall.signal : new AbortController().signal;
  f.deps.readSource = () =>
    Promise.reject(new Error("synthetic private failure"));
  f.deps.erasure.claim = () => {
    queueMicrotask(() => overall.abort());
    return new Promise(() => {});
  };
  assertEquals(await f.run(), "reconcile");
});
Deno.test("copy operation rejects malformed lease expiry and oversize cohort before RPC", async () => {
  const f = await fixture();
  await assertRejects(() =>
    executePublicationCopyOperation(
      f.client,
      f.scope,
      f.members,
      "invalid",
      f.deps,
    )
  );
  assertEquals(f.events, []);
  await assertRejects(() =>
    executePublicationCopyOperation(
      f.client,
      f.scope,
      Array(7).fill(f.members[0]),
      f.expires,
      f.deps,
    )
  );
  assertEquals(f.events, []);
});

Deno.test("copy operation aborts stalled public writes and passes overall cancellation to cleanup transports", async () => {
  const f = await fixture();
  const fresh = new AbortController();
  const cleanupSignals: AbortSignal[] = [];
  f.deps.deadlineSignal = (ms) =>
    ms === 80000 ? fresh.signal : new AbortController().signal;
  f.deps.storage = {
    writeOnce: () => {
      queueMicrotask(() => fresh.abort());
      return new Promise(() => {});
    },
  };
  f.deps.erasure.claim = (target, signal) => {
    f.targets.push(target);
    cleanupSignals.push(signal);
    return Promise.resolve(null);
  };
  assertEquals(await f.run(), "reconcile");
  assert(cleanupSignals.length >= 2);
  assert(cleanupSignals.every((s) => !s.aborted));
  assertEquals(new Set(f.targets), new Set([id(40), id(41)]));
  assert(!f.events.includes("bind_publication_copy_cohort"));
});
Deno.test("copy operation failed read cannot invent cleanup object IDs", async () => {
  const f = await fixture();
  f.state.badRead = true;
  assertEquals(await f.run(), "reconcile");
  assertEquals(f.targets, []);
  assert(!f.events.includes("reserve_publication_copy_cohort"));
});

Deno.test("copy operation rejects metadata in the final source before every public write", async () => {
  const f = await fixture();
  const parts = pngParts();
  const metadata = joined(
    parts[0],
    parts[1],
    pngChunk("tEXt", [65, 0, 66]),
    parts[2],
    parts[3],
  );
  const source = {
    ...f.members[1].source,
    byte_count: metadata.length,
    sha256: await evidenceDigest(metadata),
  };
  f.members[1].source = source;
  f.copies[1].source = { ...source };
  f.deps.readSource = (s) =>
    Promise.resolve(s.media_id === source.media_id ? metadata : f.bytes);
  assertEquals(await f.run(), "reconcile");
  assert(!f.events.some((e) => e.startsWith("write:")));
  assertEquals(f.targets, [id(40), id(41)]);
});
