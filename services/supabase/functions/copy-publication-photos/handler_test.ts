import { assert, assertEquals } from "@std/assert";
import {
  type CopyClaim,
  type CopyFinalization,
  copyPublicationPhotos,
  type CopyWorkerDependencies,
} from "./handler.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
function fixture(result: CopyFinalization = { status: "pending" }) {
  const calls: string[] = [];
  let elapsed = 0;
  const claim: CopyClaim = {
    scope: {
      owner_id: id(1),
      observation_id: id(2),
      operation_id: id(3),
      work_token: id(4),
    },
    cohort: [{
      attempt_id: id(5),
      source: {
        media_id: id(6),
        object_id: id(7),
        content_type: "image/jpeg",
        byte_count: 4,
        sha256: "a".repeat(64),
      },
    }],
    work_expires_at: new Date(Date.now() + 120_000).toISOString(),
  };
  const deps: CopyWorkerDependencies = {
    now: () => elapsed,
    list: () => {
      calls.push("list");
      return Promise.resolve([{
        owner_id: id(1),
        observation_id: id(2),
        operation_id: id(3),
      }]);
    },
    claim: () => {
      calls.push("claim");
      return Promise.resolve(claim);
    },
    finalize: () => {
      calls.push("finalize");
      return Promise.resolve(result);
    },
    execute: (work, signal) => {
      assertEquals(work, claim);
      assert(!signal.aborted);
      calls.push("execute");
      return Promise.resolve("published");
    },
    cleanup: (targets) => {
      assertEquals(targets, [id(8)]);
      calls.push("cleanup");
      return Promise.resolve();
    },
    release: () => {
      calls.push("release");
      return Promise.resolve();
    },
  };
  return { deps, calls, clock: (n: number) => elapsed = n };
}
Deno.test("copy worker finalizes before controller and releases the original claim", async () => {
  const f = fixture();
  assertEquals(await copyPublicationPhotos(f.deps), {
    claimed: 1,
    published: 1,
    needs_action: 0,
  });
  assertEquals(f.calls, ["list", "claim", "finalize", "execute", "release"]);
});
Deno.test("copy worker separates historical publication note remediation and expired cohort cleanup", async () => {
  for (
    const result of [{ status: "admitted" }, {
      status: "needs_action",
      targets: [],
    }, { status: "needs_action", targets: [id(8)] }] as CopyFinalization[]
  ) {
    const f = fixture(result);
    const counts = await copyPublicationPhotos(f.deps);
    assertEquals(counts, {
      claimed: 1,
      published: result.status === "admitted" ? 1 : 0,
      needs_action: result.status === "needs_action" ? 1 : 0,
    });
    assert(!f.calls.includes("execute"));
    assertEquals(
      f.calls.includes("cleanup"),
      result.status === "needs_action" && result.targets.length > 0,
    );
    assertEquals(f.calls.at(-1), "release");
  }
});
Deno.test("copy worker refuses to truncate controller cleanup reserve after slow setup", async () => {
  for (const elapsed of [13_000, 13_001]) {
    const f = fixture();
    const finalize = f.deps.finalize;
    f.deps.finalize = (...args) => {
      f.clock(elapsed);
      return finalize(...args);
    };
    await copyPublicationPhotos(f.deps);
    assertEquals(f.calls.includes("execute"), elapsed === 13_000);
    assertEquals(f.calls.at(-1), "release");
  }
});
Deno.test("copy worker does not infer terminality from finalizer or controller uncertainty", async () => {
  for (const stage of ["finalize", "execute"] as const) {
    const f = fixture();
    f.deps[stage] = (): Promise<never> =>
      Promise.reject(new Error("private transport detail"));
    f.deps.release = () => {
      f.calls.push("release");
      throw new Error("retired");
    };
    assertEquals(await copyPublicationPhotos(f.deps), {
      claimed: 1,
      published: 0,
      needs_action: 0,
    });
    assertEquals(f.calls.at(-1), "release");
    assert(!f.calls.includes("cleanup"));
  }
});
Deno.test("copy worker interrupts uncooperative execution but preserves release window", async () => {
  const f = fixture(),
    action = new AbortController(),
    overall = new AbortController();
  f.deps.deadlineSignal = (ms) =>
    ms === 123_000 ? action.signal : overall.signal;
  f.deps.execute = () => {
    action.abort();
    return new Promise(() => {});
  };
  f.deps.release = (_w, signal) => {
    assert(!signal.aborted);
    f.calls.push("release");
    return Promise.resolve();
  };
  assertEquals(await copyPublicationPhotos(f.deps), {
    claimed: 1,
    published: 0,
    needs_action: 0,
  });
  assertEquals(f.calls.at(-1), "release");
});
Deno.test("copy worker preserves needs-action after cleanup failure and never copies notes", async () => {
  const f = fixture({ status: "needs_action", targets: [id(8)] });
  f.deps.cleanup = () => Promise.reject(new Error("marker transport"));
  assertEquals(await copyPublicationPhotos(f.deps), {
    claimed: 1,
    published: 0,
    needs_action: 1,
  });
  assert(!f.calls.includes("execute"));
  assertEquals(f.calls.at(-1), "release");
});
Deno.test("copy worker empty or competed claims never execute or release foreign work", async () => {
  const f = fixture();
  f.deps.claim = () => Promise.resolve(null);
  assertEquals(await copyPublicationPhotos(f.deps), {
    claimed: 0,
    published: 0,
    needs_action: 0,
  });
  assert(!f.calls.includes("release"));
  f.deps.list = () => Promise.resolve([]);
  await copyPublicationPhotos(f.deps);
});
