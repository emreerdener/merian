import { assert, assertEquals, assertRejects } from "@std/assert";
import {
  eraseObservationEvidence,
  type EvidenceErasureDependencies,
} from "./handler.ts";
const object = "00000000-0000-4000-8000-000000000001";
const token = "00000000-0000-4000-8000-000000000002";
function fixture() {
  let time = 0;
  const wall = Date.parse("2026-10-01T00:00:00Z");
  const row = {
    object_id: object,
    claim_token: token,
    claim_expires_at: new Date(wall + 60_000).toISOString(),
  };
  const calls: unknown[] = [];
  const limits: number[] = [];
  const deps: EvidenceErasureDependencies = {
    now: () => time,
    wallNow: () => wall + time,
    timeout: (ms) => {
      limits.push(ms);
      return new AbortController().signal;
    },
    retire: (signal) => {
      assert(!signal.aborted);
      calls.push("retire");
      return Promise.resolve(5);
    },
    retireVideo: (signal) => {
      assert(!signal.aborted);
      calls.push("retireVideo");
      return Promise.resolve(7);
    },
    claim: () => {
      calls.push("claim");
      return Promise.resolve(row);
    },
    erase: (id, signal) => {
      assert(!signal.aborted);
      calls.push(["erase", id]);
      return Promise.resolve();
    },
    finish: (id, lease, success, signal) => {
      assert(!signal.aborted);
      calls.push(["finish", id, lease, success]);
      return Promise.resolve(true);
    },
  };
  return { deps, calls, limits, row, advance: (ms: number) => time += ms };
}
Deno.test("private erasure retires one cohort, marks one frozen object and settles its original token", async () => {
  const f = fixture();
  f.deps.erase = (id) => {
    f.calls.push(["erase", id]);
    f.row.object_id = token;
    f.row.claim_token = object;
    return Promise.resolve();
  };
  assertEquals(await eraseObservationEvidence(f.deps), {
    retired: 5,
    video_retired: 7,
    retirement_failures: 0,
    claimed: 1,
    marked: 1,
    acknowledged: 1,
  });
  assertEquals(f.calls, ["retire", "retireVideo", "claim", ["erase", object], [
    "finish",
    object,
    token,
    true,
  ]]);
  assertEquals(f.limits, [90_000, 12_000, 12_000, 12_000, 25_000, 12_000]);
});
Deno.test("private erasure does no storage work when disabled or empty", async () => {
  const f = fixture();
  f.deps.claim = () => Promise.resolve(null);
  assertEquals(await eraseObservationEvidence(f.deps), {
    retired: 5,
    video_retired: 7,
    retirement_failures: 0,
    claimed: 0,
    marked: 0,
    acknowledged: 0,
  });
  assertEquals(f.calls, ["retire", "retireVideo"]);
});
Deno.test("private erasure rejects malformed bounded receipts before storage", async () => {
  for (
    const value of [{}, [], false, { ...fixture().row, extra: 1 }, {
      ...fixture().row,
      object_id: "bad",
    }, { ...fixture().row, claim_expires_at: "2026-10-01" }]
  ) {
    const f = fixture();
    f.deps.claim = () => Promise.resolve(value);
    await assertRejects(() => eraseObservationEvidence(f.deps));
    assertEquals(f.calls, ["retire", "retireVideo"]);
  }
});
Deno.test("late claim reply preserves completion reserve and never extends original lease", async () => {
  const f = fixture();
  f.deps.claim = () => {
    f.advance(23_000);
    return Promise.resolve(f.row);
  };
  assertEquals(await eraseObservationEvidence(f.deps), {
    retired: 5,
    video_retired: 7,
    retirement_failures: 0,
    claimed: 1,
    marked: 0,
    acknowledged: 1,
  });
  assertEquals(f.calls, ["retire", "retireVideo", [
    "finish",
    object,
    token,
    false,
  ]]);
});
Deno.test("expired claim cannot write or settle and future clock skew cannot extend sixty seconds", async () => {
  const f = fixture();
  f.deps.claim = () => {
    f.advance(61_000);
    return Promise.resolve(f.row);
  };
  assertEquals(await eraseObservationEvidence(f.deps), {
    retired: 5,
    video_retired: 7,
    retirement_failures: 0,
    claimed: 1,
    marked: 0,
    acknowledged: 0,
  });
  assertEquals(f.calls, ["retire", "retireVideo"]);
  const g = fixture();
  g.row.claim_expires_at = "2027-01-01T00:00:00Z";
  g.deps.claim = () => {
    g.advance(23_000);
    return Promise.resolve(g.row);
  };
  await eraseObservationEvidence(g.deps);
  assertEquals(g.calls, ["retire", "retireVideo", [
    "finish",
    object,
    token,
    false,
  ]]);
});
Deno.test("storage failure or lost acknowledgement never retries external I/O", async () => {
  const f = fixture();
  f.deps.erase = () => Promise.reject(new Error("private storage detail"));
  assertEquals(await eraseObservationEvidence(f.deps), {
    retired: 5,
    video_retired: 7,
    retirement_failures: 0,
    claimed: 1,
    marked: 0,
    acknowledged: 1,
  });
  assertEquals(f.calls.at(-1), ["finish", object, token, false]);
  const g = fixture();
  g.deps.finish = () => Promise.reject(new Error("unknown commit"));
  assertEquals(await eraseObservationEvidence(g.deps), {
    retired: 5,
    video_retired: 7,
    retirement_failures: 0,
    claimed: 1,
    marked: 1,
    acknowledged: 0,
  });
  assertEquals(g.calls, ["retire", "retireVideo", "claim", ["erase", object]]);
});
Deno.test("private erasure respects parent cancellation before I/O and between marker and settlement", async () => {
  const f = fixture(), controller = new AbortController();
  controller.abort();
  await assertRejects(() =>
    eraseObservationEvidence(f.deps, controller.signal)
  );
  assertEquals(f.calls, []);
  const g = fixture(), active = new AbortController();
  g.deps.erase = () => {
    active.abort();
    return Promise.resolve();
  };
  assertEquals(await eraseObservationEvidence(g.deps, active.signal), {
    retired: 5,
    video_retired: 7,
    retirement_failures: 0,
    claimed: 1,
    marked: 0,
    acknowledged: 0,
  });
  assertEquals(g.calls, ["retire", "retireVideo", "claim"]);
});
Deno.test("private erasure aborts stalled storage but leaves time to report failure", async () => {
  const f = fixture(), storage = new AbortController();
  f.deps.timeout = (ms) =>
    ms === 25_000 ? storage.signal : new AbortController().signal;
  f.deps.erase = () => {
    storage.abort();
    return new Promise(() => {});
  };
  assertEquals(await eraseObservationEvidence(f.deps), {
    retired: 5,
    video_retired: 7,
    retirement_failures: 0,
    claimed: 1,
    marked: 0,
    acknowledged: 1,
  });
  assertEquals(f.calls.at(-1), ["finish", object, token, false]);
});
Deno.test("unknown claim reply does not probe, retry or reach storage", async () => {
  const f = fixture();
  f.deps.claim = () => Promise.reject(new Error("unknown"));
  await assertRejects(() => eraseObservationEvidence(f.deps));
  assertEquals(f.calls, ["retire", "retireVideo"]);
});

Deno.test("each retirement lane progresses independently after the other's lost acknowledgement", async () => {
  for (const phase of ["retire", "retireVideo"] as const) {
    const f = fixture();
    let attempts = 0;
    f.deps[phase] = () => {
      attempts++;
      return Promise.reject(new Error("private SQL detail"));
    };
    const result = await eraseObservationEvidence(f.deps);
    assertEquals(attempts, 1);
    assertEquals(result.retirement_failures, 1);
    assertEquals(result.retired, phase === "retire" ? 0 : 5);
    assertEquals(result.video_retired, phase === "retireVideo" ? 0 : 7);
    assertEquals([result.claimed, result.marked, result.acknowledged], [
      1,
      1,
      1,
    ]);
  }
});

Deno.test("invalid retirement counts never inflate receipts or block an independently claimed obligation", async () => {
  for (const [phase, maximum] of [["retire", 5], ["retireVideo", 7]] as const) {
    for (const value of [-1, maximum + 1, 1.5, "1", null, Number.NaN]) {
      const f = fixture();
      f.deps[phase] = () => Promise.resolve(value);
      const result = await eraseObservationEvidence(f.deps);
      assertEquals(result.retirement_failures, 1);
      assertEquals(result.marked, 1);
      assertEquals(result[phase === "retire" ? "retired" : "video_retired"], 0);
    }
  }
});

Deno.test("two failed retirement stages retain enough original request budget for one marker and settlement", async () => {
  const f = fixture();
  const fail = () => {
    f.advance(12_000);
    return Promise.reject(new Error("stage unavailable"));
  };
  f.deps.retire = fail;
  f.deps.retireVideo = fail;
  f.deps.claim = () => {
    f.row.claim_expires_at = "2026-10-01T00:01:24Z";
    return Promise.resolve(f.row);
  };
  const result = await eraseObservationEvidence(f.deps);
  assertEquals(result.retirement_failures, 2);
  assertEquals([result.claimed, result.marked, result.acknowledged], [1, 1, 1]);
  assertEquals(f.limits, [90_000, 12_000, 12_000, 12_000, 25_000, 12_000]);
});

Deno.test("zero retirement does not suppress an independently granted cleanup claim", async () => {
  const f = fixture();
  f.deps.retire = f.deps.retireVideo = () => Promise.resolve(0);
  const result = await eraseObservationEvidence(f.deps);
  assertEquals(result, {
    retired: 0,
    video_retired: 0,
    retirement_failures: 0,
    claimed: 1,
    marked: 1,
    acknowledged: 1,
  });
});

Deno.test("parent cancellation between retirement lanes prevents video retirement and claim", async () => {
  const f = fixture(), parent = new AbortController();
  f.deps.retire = () => {
    parent.abort();
    return Promise.resolve(0);
  };
  await assertRejects(() => eraseObservationEvidence(f.deps, parent.signal));
  assertEquals(f.calls, []);
});

Deno.test("slow scheduling cannot acquire a claim without the unchanged marker reserve", async () => {
  const f = fixture();
  f.deps.retire = () => {
    f.advance(21_000);
    return Promise.resolve(0);
  };
  f.deps.retireVideo = () => {
    f.advance(21_000);
    return Promise.resolve(6);
  };
  assertEquals(await eraseObservationEvidence(f.deps), {
    retired: 0,
    video_retired: 6,
    retirement_failures: 0,
    claimed: 0,
    marked: 0,
    acknowledged: 0,
  });
  assertEquals(f.calls, []);
});

Deno.test("complete six and seven-object video retirement receipts preserve one marker capacity", async () => {
  for (const count of [6, 7]) {
    const f = fixture();
    f.deps.retireVideo = () => Promise.resolve(count);
    const result = await eraseObservationEvidence(f.deps);
    assertEquals(result.video_retired, count);
    assertEquals(result.retirement_failures, 0);
    assertEquals(result.marked, 1);
  }
});
