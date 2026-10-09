import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HistoryError } from "./contract.ts";
import { sourceReservationRepository } from "./sourceReservationRepository.ts";
import { sourceReservationIdentity } from "./sourceReservation.ts";
import vectors from "./fixtures/source-fingerprint-v1.json" with {
  type: "json",
};
const owner = "00000000-0000-4000-8000-000000000090";
const operation = "00000000-0000-4000-8000-000000000092";
const candidate = () => ({
  schema_version: 1,
  input: structuredClone(vectors[0].input),
  fingerprint_version: 1,
  fingerprint: vectors[0].sha256,
});
const identity = await sourceReservationIdentity(candidate());
const scope = {
  schema_version: 1,
  owner_id: owner,
  observation_id: identity.observation_id,
  source_analysis_id: identity.source_analysis_id,
};
const reserved = { ...identity, owner_id: owner, state: "reserved" as const };
const retired = {
  ...identity,
  operation_id: operation,
  owner_id: owner,
  state: "retired_unfunded" as const,
};
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
  return { repository: sourceReservationRepository(client), calls };
}
const signal = () => new AbortController().signal;
for (
  const response of [reserved, {
    ...scope,
    state: "held",
    reason: "source_occupied",
  }, { ...scope, state: "unavailable" }]
) {
  Deno.test(`source RPC reserve decodes ${response.state} without execution authority`, async () => {
    const f = fixture(() => Promise.resolve({ data: response, error: null }));
    const original = candidate();
    assertEquals(
      await f.repository.reserve(owner, original, signal()),
      response,
    );
    assertEquals(f.calls.length, 1);
    assertEquals(
      f.calls[0].routine,
      "reserve_owned_observation_analysis_source",
    );
    assertEquals(f.calls[0].args, {
      p_owner: owner,
      p_request: original,
      p_reader: 11,
    });
    assert(!("may_dispatch" in response));
  });
}
Deno.test("source RPC retirement retains caller operation and full original candidate", async () => {
  const f = fixture(() => Promise.resolve({ data: retired, error: null }));
  assertEquals(
    await f.repository.retireUnfunded(owner, candidate(), operation, signal()),
    retired,
  );
  assertEquals(f.calls.length, 1);
  assertEquals(f.calls[0].routine, "retire_owned_observation_analysis_source");
  assertEquals(f.calls[0].args, {
    p_owner: owner,
    p_request: { ...identity, operation_id: operation },
    p_reader: 11,
  });
});
for (const method of ["reserve", "retire"] as const) {
  const invoke = (f: ReturnType<typeof fixture>, caller = signal()) =>
    method === "reserve"
      ? f.repository.reserve(owner, candidate(), caller)
      : f.repository.retireUnfunded(owner, candidate(), operation, caller);
  Deno.test(`source RPC ${method} snapshots before hashing and RPC awaits`, async () => {
    const f = fixture(() =>
      Promise.resolve({
        data: method === "reserve" ? reserved : retired,
        error: null,
      })
    );
    const original = candidate();
    const pending = method === "reserve"
      ? f.repository.reserve(owner, original, signal())
      : f.repository.retireUnfunded(owner, original, operation, signal());
    original.input.request_digest = "c".repeat(64);
    original.fingerprint = "d".repeat(64);
    assertEquals(await pending, method === "reserve" ? reserved : retired);
    assertEquals(f.calls.length, 1);
  });
  Deno.test(`source RPC ${method} errors and malformed replies stay uncertain without retry`, async () => {
    for (
      const reply of [
        () => Promise.reject(new Error("synthetic lost response")),
        () =>
          Promise.resolve({
            data: null,
            error: { message: "analysis_history_operation_conflict" },
          }),
        () =>
          Promise.resolve({
            data: { ...reserved, owner_id: operation },
            error: null,
          }),
        () =>
          Promise.resolve({
            data: { ...retired, operation_id: owner },
            error: null,
          }),
        () =>
          Promise.resolve({
            data: { ...reserved, extra: "x".repeat(2049) },
            error: null,
          }),
        () => Promise.resolve({ data: null, error: null }),
      ]
    ) {
      const f = fixture(reply);
      await assertRejects(
        () => invoke(f),
        HistoryError,
        "analysis_history_unavailable",
      );
      assertEquals(f.calls.length, 1);
    }
  });
  Deno.test(`source RPC ${method} cancellation before dispatch makes no call`, async () => {
    const f = fixture(() => Promise.resolve({ data: retired, error: null }));
    const c = new AbortController();
    c.abort();
    await assertRejects(
      () => invoke(f, c.signal),
      HistoryError,
      "analysis_history_unavailable",
    );
    assertEquals(f.calls.length, 0);
  });
  Deno.test(`source RPC ${method} regains control from uncooperative transport`, async () => {
    let began!: () => void;
    const started = new Promise<void>((r) => began = r);
    let finish!: (value: { data: unknown; error: unknown }) => void;
    const f = fixture(() => {
      began();
      return new Promise((r) => finish = r);
    });
    const c = new AbortController();
    const pending = invoke(f, c.signal);
    await started;
    c.abort();
    await assertRejects(
      () => pending,
      HistoryError,
      "analysis_history_unavailable",
    );
    assert(f.calls[0].signal.aborted);
    finish({ data: method === "reserve" ? reserved : retired, error: null });
    await Promise.resolve();
    assertEquals(f.calls.length, 1);
  });
}
Deno.test("source RPC uses an actual five-second deadline for stalled requests", async () => {
  const f = fixture(() => new Promise(() => {}));
  const start = performance.now();
  await assertRejects(
    () => f.repository.reserve(owner, candidate(), signal()),
    HistoryError,
    "analysis_history_unavailable",
  );
  assert(f.calls[0].signal.aborted);
  assert(performance.now() - start >= 4900);
  assertEquals(f.calls.length, 1);
});
