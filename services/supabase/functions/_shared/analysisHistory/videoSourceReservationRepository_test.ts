import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HistoryError } from "./contract.ts";
import { videoSourceReservationRepository } from "./videoSourceReservationRepository.ts";
import vectors from "./fixtures/video-source-fingerprint-v1.json" with {
  type: "json",
};
import receipts from "./fixtures/video-source-reservation-v2.json" with {
  type: "json",
};
const owner = "00000000-0000-4000-8000-000000000090";
const candidate = () => ({
  schema_version: 2,
  input: structuredClone(vectors[0].input),
  fingerprint_version: 1,
  fingerprint: vectors[0].sha256,
});
const signal = () => new AbortController().signal;
function fixture(
  reply: (
    routine: string,
    args: Record<string, unknown>,
    signal: AbortSignal,
  ) => Promise<{ data: unknown; error: unknown }>,
) {
  let count = 0;
  const client = {
    rpc(routine: string, args: Record<string, unknown>) {
      return {
        abortSignal(signal: AbortSignal) {
          count++;
          return reply(routine, args, signal);
        },
      };
    },
  } as unknown as SupabaseClient;
  return {
    repository: videoSourceReservationRepository(client),
    count: () => count,
  };
}
Deno.test("video source reserve and exact read-only recovery use separate reader12 RPCs and full identity", async () => {
  for (const method of ["reserve", "recover"] as const) {
    for (const data of receipts[0].replies) {
      const f = fixture((routine, args) => {
        assertEquals(
          routine,
          method === "reserve"
            ? "reserve_owned_observation_video_source"
            : "get_owned_observation_video_source",
        );
        assertEquals(args, {
          p_owner: owner,
          p_request: method === "reserve" ? candidate() : receipts[0].identity,
          p_reader: 12,
        });
        return Promise.resolve({ data, error: null });
      });
      assertEquals<unknown>(
        await f.repository[method](owner, candidate(), signal()),
        data,
      );
      assertEquals(f.count(), 1);
    }
  }
});
Deno.test("video source adapter freezes candidate before awaits for reserve and recovery", async () => {
  for (const method of ["reserve", "recover"] as const) {
    const request = candidate(), original = structuredClone(request);
    const f = fixture((_routine, args) => {
      assertEquals(
        args.p_request,
        method === "reserve" ? original : receipts[0].identity,
      );
      return Promise.resolve({ data: receipts[0].replies[0], error: null });
    });
    const pending = f.repository[method](owner, request, signal());
    request.input.request_digest = "f".repeat(64);
    request.input.evidence_manifest.provenance.frames.reverse();
    await pending;
  }
});
Deno.test("video source invalid input prevents RPC and wrong receipts never become authority", async () => {
  const f = fixture(() =>
    Promise.resolve({ data: receipts[0].replies[0], error: null })
  );
  for (const method of ["reserve", "recover"] as const) {
    await assertRejects(() =>
      f.repository[method](
        owner,
        { ...candidate(), schema_version: 1 },
        signal(),
      )
    );
  }
  assertEquals(f.count(), 0);
  for (
    const data of [
      { ...receipts[0].replies[0], owner_id: receipts[0].identity.analysis_id },
      { ...receipts[0].replies[0], fingerprint: "0".repeat(64) },
      { ...receipts[0].replies[0], extra: true },
      "x".repeat(2049),
    ]
  ) {
    const bad = fixture(() => Promise.resolve({ data, error: null }));
    await assertRejects(
      () => bad.repository.reserve(owner, candidate(), signal()),
      HistoryError,
      "analysis_history_unavailable",
    );
    assertEquals(bad.count(), 1);
  }
});
Deno.test("video source adapter preserves conflict but never retries lost or failed replies", async () => {
  for (const method of ["reserve", "recover"] as const) {
    for (const conflict of [true, false]) {
      const f = fixture(() =>
        Promise.resolve({
          data: null,
          error: {
            message: conflict
              ? "analysis_history_operation_conflict"
              : "private diagnostic",
          },
        })
      );
      await assertRejects(
        () => f.repository[method](owner, candidate(), signal()),
        HistoryError,
        conflict
          ? "analysis_history_operation_conflict"
          : "analysis_history_unavailable",
      );
      assertEquals(f.count(), 1);
    }
    const f = fixture(() => Promise.reject(new Error("lost")));
    await assertRejects(() =>
      f.repository[method](owner, candidate(), signal())
    );
    assertEquals(f.count(), 1);
  }
});
Deno.test("video source adapter cancellation releases stalled calls and rejects late replies", async () => {
  for (const method of ["reserve", "recover"] as const) {
    const controller = new AbortController();
    let start!: () => void,
      finish!: (v: { data: unknown; error: null }) => void;
    const entered = new Promise<void>((r) => start = r);
    const f = fixture(() => {
      start();
      return new Promise((r) => finish = r);
    });
    const pending = f.repository[method](owner, candidate(), controller.signal);
    await entered;
    controller.abort();
    await assertRejects(() => pending);
    finish({ data: receipts[0].replies[0], error: null });
    await Promise.resolve();
    assertEquals(f.count(), 1);
    await assertRejects(() =>
      f.repository[method](owner, candidate(), controller.signal)
    );
    assertEquals(f.count(), 1);
  }
});
Deno.test("video source adapter uses actual five second timeout", async () => {
  const f = fixture(() => new Promise(() => {}));
  const start = Date.now();
  await assertRejects(
    () => f.repository.reserve(owner, candidate(), signal()),
    HistoryError,
    "analysis_history_unavailable",
  );
  assertEquals(Date.now() - start >= 4900, true);
  assertEquals(f.count(), 1);
});
