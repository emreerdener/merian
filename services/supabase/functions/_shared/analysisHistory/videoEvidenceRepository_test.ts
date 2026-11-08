import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import inputs from "./fixtures/video-source-fingerprint-v1.json" with {
  type: "json",
};
import vectors from "./fixtures/video-evidence-v2.json" with { type: "json" };
import { videoEvidenceRepository } from "./videoEvidenceRepository.ts";
import { HistoryError } from "./contract.ts";
const bytes = (v: unknown) => new TextEncoder().encode(JSON.stringify(v));
const candidate = (i = 0) => ({
  schema_version: 2,
  input: structuredClone(inputs[i].input),
  fingerprint_version: 1,
  fingerprint: inputs[i].sha256,
});
const owner = vectors[0].allocated.owner_id;
type Call = {
  routine: string;
  args: Record<string, unknown>;
  signal: AbortSignal;
};
function fixture(
  reply: (call: Call) => Promise<{ data: unknown; error: unknown }>,
) {
  const calls: Call[] = [];
  const client = {
    rpc(routine: string, args: Record<string, unknown>) {
      return {
        abortSignal(signal: AbortSignal) {
          const call = { routine, args, signal };
          calls.push(call);
          return reply(call);
        },
      };
    },
  } as unknown as SupabaseClient;
  return { repository: videoEvidenceRepository(client), calls };
}
const signal = () => new AbortController().signal;
Deno.test("video allocation RPC preserves exact six/seven inventory and ready replay", async () => {
  for (const [i, v] of vectors.entries()) {
    const partial = {
      ...v.allocated,
      items: v.allocated.items.map((item, index) =>
        index === 0 ? v.ready.items[0] : item
      ),
    };
    for (const response of [v.allocated, partial, v.ready]) {
      const f = fixture(() => Promise.resolve({ data: response, error: null }));
      assertEquals<unknown>(
        await f.repository.reserve(owner, candidate(i), signal()),
        response,
      );
      assertEquals(f.calls.length, 1);
      assertEquals(
        f.calls[0].routine,
        "reserve_owned_observation_video_evidence",
      );
      assertEquals(f.calls[0].args, {
        p_owner: owner,
        p_request: v.request,
        p_reader: 12,
      });
    }
  }
});
Deno.test("video completion binds exact prior object and monotonic whole receipt", async () => {
  const v = vectors[0];
  for (const prior of [v.allocated, v.ready]) {
    const f = fixture(() => Promise.resolve({ data: v.ready, error: null }));
    assertEquals<unknown>(
      await f.repository.complete(
        owner,
        candidate(),
        bytes(prior),
        prior.items[2].media_id,
        signal(),
      ),
      v.ready,
    );
    assertEquals(f.calls[0].args, {
      p_owner: owner,
      p_request: v.request,
      p_media: prior.items[2].media_id,
      p_object: prior.items[2].object_id,
      p_reader: 12,
    });
    assertEquals(
      f.calls[0].routine,
      "complete_owned_observation_video_evidence",
    );
    assertEquals(f.calls.length, 1);
  }
});
Deno.test("video completion snapshots original candidate and receipt before awaits", async () => {
  const v = vectors[0], original = candidate(), prior = bytes(v.allocated);
  const f = fixture(() => Promise.resolve({ data: v.ready, error: null }));
  const result = f.repository.complete(
    owner,
    original,
    prior,
    v.allocated.items[0].media_id,
    signal(),
  );
  original.input.request_digest = "0".repeat(64);
  prior.fill(0);
  assertEquals<unknown>(await result, v.ready);
  assertEquals(f.calls[0].args.p_request, v.request);
});
Deno.test("video completion denies forged target and malformed prior without RPC", async () => {
  const v = vectors[0],
    f = fixture(() => Promise.resolve({ data: v.ready, error: null }));
  for (
    const [prior, media] of [[bytes(v.allocated), owner], [
      new Uint8Array(8193),
      v.allocated.items[0].media_id,
    ], [
      bytes({ ...v.allocated, owner_id: v.allocated.analysis_id }),
      v.allocated.items[0].media_id,
    ]] as const
  ) {
    await assertRejects(() =>
      f.repository.complete(owner, candidate(), prior, media, signal())
    );
  }
  assertEquals(f.calls.length, 0);
});
Deno.test("video RPC uncertain malformed lost or oversized replies never retry", async () => {
  for (const method of ["reserve", "complete"] as const) {
    for (
      const response of [
        null,
        { ...vectors[0].ready, extra: "x".repeat(8192) },
        { ...vectors[0].ready, owner_id: vectors[0].ready.analysis_id },
      ]
    ) {
      const f = fixture(() => Promise.resolve({ data: response, error: null }));
      await assertRejects(
        () =>
          method === "reserve"
            ? f.repository.reserve(owner, candidate(), signal())
            : f.repository.complete(
              owner,
              candidate(),
              bytes(vectors[0].allocated),
              vectors[0].allocated.items[0].media_id,
              signal(),
            ),
        HistoryError,
        "analysis_history_unavailable",
      );
      assertEquals(f.calls.length, 1);
    }
  }
  for (
    const error of [new Error("lost reply"), {
      message: "private upstream detail",
    }, { message: "analysis_history_operation_conflict" }]
  ) {
    const f = fixture(() =>
      error instanceof Error
        ? Promise.reject(error)
        : Promise.resolve({ data: null, error })
    );
    await assertRejects(
      () => f.repository.reserve(owner, candidate(), signal()),
      HistoryError,
      error.message === "analysis_history_operation_conflict"
        ? error.message
        : "analysis_history_unavailable",
    );
    assertEquals(f.calls.length, 1);
  }
});
Deno.test("video completion rejects changed allocation expiry timestamps and unacknowledged target", async () => {
  const v = vectors[0];
  for (
    const response of [v.allocated, {
      ...v.ready,
      expires_at: "2099-01-01T00:00:00.000Z",
    }, {
      ...v.ready,
      items: v.ready.items.map((item, i) =>
        i ? item : { ...item, object_id: owner }
      ),
    }, {
      ...v.ready,
      items: v.ready.items.map((item, i) =>
        i ? item : { ...item, ready_at: "2025-01-01T00:00:00.000Z" }
      ),
    }]
  ) {
    const f = fixture(() => Promise.resolve({ data: response, error: null }));
    await assertRejects(
      () =>
        f.repository.complete(
          owner,
          candidate(),
          bytes(v.ready),
          v.ready.items[0].media_id,
          signal(),
        ),
      HistoryError,
      "analysis_history_unavailable",
    );
    assertEquals(f.calls.length, 1);
  }
});
Deno.test("video RPC cancellation prevents dispatch and releases stalled waits without successor", async () => {
  const controller = new AbortController();
  controller.abort();
  const before = fixture(() => new Promise(() => {}));
  await assertRejects(() =>
    before.repository.reserve(owner, candidate(), controller.signal)
  );
  assertEquals(before.calls.length, 0);
  let started!: () => void;
  const entered = new Promise<void>((resolve) => started = resolve);
  const active = new AbortController();
  const f = fixture(() => {
    started();
    return new Promise(() => {});
  });
  const pending = f.repository.reserve(owner, candidate(), active.signal);
  await entered;
  active.abort();
  await assertRejects(
    () => pending,
    HistoryError,
    "analysis_history_unavailable",
  );
  assertEquals(f.calls.length, 1);
  assert(f.calls[0].signal.aborted);
});
Deno.test("video RPC imposes five second deadline on uncooperative transport", async () => {
  const f = fixture(() => new Promise(() => {}));
  const start = performance.now();
  await assertRejects(
    () => f.repository.reserve(owner, candidate(), signal()),
    HistoryError,
    "analysis_history_unavailable",
  );
  assert(performance.now() - start >= 4500);
  assertEquals(f.calls.length, 1);
  assert(f.calls[0].signal.aborted);
});

Deno.test("video completion accepts concurrent progress beyond the saved readiness lower bound", async () => {
  const v = vectors[0], target = v.allocated.items[0].media_id;
  const prior = structuredClone(v.allocated);
  const partial = {
    ...v.allocated,
    items: v.allocated.items.map((item, index) =>
      index < 2 ? v.ready.items[index] : item
    ),
  };
  const f = fixture(() => Promise.resolve({ data: partial, error: null }));
  assertEquals<unknown>(
    await f.repository.complete(
      owner,
      candidate(),
      bytes(prior),
      target,
      signal(),
    ),
    partial,
  );
  assertEquals(f.calls.length, 1);
  // A different item's acknowledgement alone cannot acknowledge our target.
  const missing = {
    ...partial,
    items: partial.items.map((item, index) =>
      index === 0 ? prior.items[0] : item
    ),
  };
  const denied = fixture(() => Promise.resolve({ data: missing, error: null }));
  await assertRejects(
    () =>
      denied.repository.complete(
        owner,
        candidate(),
        bytes(prior),
        target,
        signal(),
      ),
    HistoryError,
    "analysis_history_unavailable",
  );
  assertEquals(denied.calls.length, 1);
});
