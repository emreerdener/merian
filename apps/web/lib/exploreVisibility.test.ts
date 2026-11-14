import assert from "node:assert/strict";
import { test } from "node:test";
import { visibilityIds, visibilityResult } from "./exploreVisibility.ts";
import { watchExploreVisibility } from "./watchExploreVisibility.ts";
const id = "00000000-0000-4000-8000-00000000a001";
const other = "00000000-0000-4000-8000-00000000a002";
const tick = () => new Promise<void>((resolve) => setImmediate(resolve));
test("visibility input is bounded, normalized and deduplicated; output cannot introduce IDs", () => {
  assert.deepEqual(visibilityIds([id, id.toUpperCase()]), [id]);
  for (const value of [[], null, ["bad"], Array(129).fill(id), [null]]) {
    assert.equal(visibilityIds(value), null);
  }
  assert.deepEqual(visibilityResult({ visible: [] }, [id]), []);
  assert.throws(() => visibilityResult({ visible: [other] }, [id]));
  assert.throws(() => visibilityResult({}, [id]));
});
test("stream snapshots withdraw and restore cards without a reload", () => {
  let snapshot!: (value: unknown) => void;
  let current: ReadonlySet<string> = new Set();
  const stop = watchExploreVisibility([id], (value) => {
    current = value;
  }, {
    changes: (notify) => {
      snapshot = notify;
      return () => {};
    },
    check: async () => ({ visible: [id] }),
  });
  try {
    assert.equal(current.size, 0);
    snapshot({ visible: [id] });
    assert.equal(current.has(id), true);
    snapshot({ visible: [] });
    assert.equal(current.size, 0);
    snapshot({ visible: [id] });
    assert.equal(current.has(id), true);
    snapshot({ visible: [other] });
    assert.equal(current.size, 0);
  } finally {
    stop();
  }
});
test("stalled stream is closed before polling; queued old snapshots cannot restore withdrawn content", async (t) => {
  t.mock.timers.enable({ apis: ["setInterval", "Date"] });
  let snapshot!: (value: unknown) => void;
  let current: ReadonlySet<string> = new Set();
  let disconnected = false;
  const stop = watchExploreVisibility([id], (value) => {
    current = value;
  }, {
    changes: (notify) => {
      snapshot = notify;
      return () => {
        disconnected = true;
      };
    },
    check: async () => ({ visible: [] }),
  });
  snapshot({ visible: [id] });
  assert.equal(current.size, 1);
  t.mock.timers.tick(6000);
  await tick();
  assert.equal(disconnected, true);
  assert.equal(current.size, 0);
  snapshot({ visible: [id] });
  assert.equal(current.size, 0);
  stop();
});
test("connection failure clears immediately and ignores all old stream events", () => {
  let snapshot!: (value: unknown) => void;
  let failed!: () => void;
  let current: ReadonlySet<string> = new Set();
  const stop = watchExploreVisibility([id], (value) => {
    current = value;
  }, {
    changes: (notify, failure) => {
      snapshot = notify;
      failed = failure;
      return () => {};
    },
    check: () => new Promise(() => {}),
  });
  snapshot({ visible: [id] });
  failed();
  assert.equal(current.size, 0);
  snapshot({ visible: [id] });
  assert.equal(current.size, 0);
  stop();
});
test("missing migration remains closed through polling fallback", async (t) => {
  t.mock.timers.enable({ apis: ["setInterval", "Date"] });
  let current: ReadonlySet<string> = new Set();
  const stop = watchExploreVisibility([id], (value) => {
    current = value;
  }, {
    changes: () => null,
    check: async () => {
      throw new Error("Missing RPC");
    },
  });
  t.mock.timers.tick(2000);
  await tick();
  assert.equal(current.size, 0);
  stop();
});

test("SSE snapshots contain only watched eligibility and stop work on cancellation", async (t) => {
  const { exploreVisibilityStream } = await import(
    "./exploreVisibilityStream.ts"
  );
  t.mock.timers.enable({ apis: ["setTimeout", "Date"] });
  let visible = [id];
  let reads = 0;
  const response = exploreVisibilityStream(
    new Request(`http://localhost/api/explore/changes?ids=${id}`),
    async () => {
      reads++;
      return { visible };
    },
  );
  const reader = response.body!.getReader();
  const first = await reader.read();
  assert.equal(response.headers.get("Cache-Control"), "no-store, no-transform");
  assert.match(new TextDecoder().decode(first.value), /"visible":\[/);
  visible = [];
  t.mock.timers.tick(2000);
  await tick();
  const next = await reader.read();
  assert.match(new TextDecoder().decode(next.value), /"visible":\[\]/);
  await reader.cancel();
  const before = reads;
  t.mock.timers.tick(10000);
  await tick();
  assert.equal(reads, before);
});
test("SSE bounds IDs and concurrent streams, then releases capacity", async () => {
  const { exploreVisibilityStream } = await import(
    "./exploreVisibilityStream.ts"
  );
  const read = async () => ({ visible: [] });
  assert.equal(
    exploreVisibilityStream(
      new Request("http://localhost/api/explore/changes?ids=bad"),
      read,
    ).status,
    400,
  );
  const streams = Array.from(
    { length: 16 },
    () =>
      exploreVisibilityStream(
        new Request(`http://localhost/api/explore/changes?ids=${id}`),
        read,
      ),
  );
  assert.equal(
    exploreVisibilityStream(
      new Request(`http://localhost/api/explore/changes?ids=${id}`),
      read,
    ).status,
    429,
  );
  await Promise.all(streams.map((response) => response.body!.cancel()));
  const again = exploreVisibilityStream(
    new Request(`http://localhost/api/explore/changes?ids=${id}`),
    read,
  );
  assert.equal(again.status, 200);
  await again.body!.cancel();
});

test("reconnect ignores old events and schedules only one replacement stream", async (t) => {
  const { subscribeExploreVisibility } = await import(
    "./subscribeExploreVisibility.ts"
  );
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const callbacks: Array<
    {
      message: (data: string) => void;
      error: () => void;
      reconnect: () => void;
    }
  > = [];
  let closes = 0;
  let failures = 0;
  let snapshots = 0;
  const stop = subscribeExploreVisibility((handlers) => {
    callbacks.push(handlers);
    return () => {
      closes++;
    };
  }, () => {
    snapshots++;
  }, () => {
    failures++;
  });
  callbacks[0].reconnect();
  callbacks[0].error();
  t.mock.timers.tick(100);
  assert.equal(callbacks.length, 2);
  callbacks[0].error();
  callbacks[0].message("{}");
  callbacks[1].message("{}");
  assert.equal(snapshots, 1);
  assert.equal(failures, 0);
  t.mock.timers.tick(5000);
  assert.equal(callbacks.length, 2);
  stop();
  callbacks[1].error();
  t.mock.timers.tick(5000);
  assert.equal(callbacks.length, 2);
  assert.equal(closes, 2);
});
