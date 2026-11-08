import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { evidenceErasureRepository } from "./db.ts";
Deno.test("private erasure RPC boundary is fixed, scoped, abortable and strict", async () => {
  const calls: unknown[] = [];
  let value: unknown = 0;
  const client = {
    rpc: (name: string, args: unknown) => ({
      abortSignal: (signal: AbortSignal) => {
        calls.push([name, args, signal.aborted]);
        return Promise.resolve({ data: value, error: null });
      },
    }),
  } as unknown as SupabaseClient;
  const repository = evidenceErasureRepository(client),
    signal = new AbortController().signal;
  assertEquals(await repository.retire(signal), 0);
  value = null;
  assertEquals(await repository.claim(signal), null);
  value = true;
  assertEquals(await repository.finish("object", "token", false, signal), true);
  assertEquals(calls, [["retire_expired_observation_evidence", {}, false], [
    "claim_observation_evidence_erasure",
    {},
    false,
  ], ["finish_observation_evidence_erasure", {
    p_object: "object",
    p_claim: "token",
    p_success: false,
  }, false]]);
  value = "true";
  await assertRejects(() => repository.finish("object", "token", true, signal));
  const aborted = new AbortController();
  aborted.abort();
  const count = calls.length;
  await assertRejects(() => repository.claim(aborted.signal));
  assertEquals(calls.length, count);
});
Deno.test("private erasure database failure has no raw diagnostic or implicit retry", async () => {
  let calls = 0;
  const client = {
    rpc: () => ({
      abortSignal: () => {
        calls++;
        return Promise.resolve({
          data: null,
          error: { message: "private detail" },
        });
      },
    }),
  } as unknown as SupabaseClient;
  const error = await assertRejects(() =>
    evidenceErasureRepository(client).claim(new AbortController().signal)
  );
  assert(error instanceof Error);
  assertEquals(error.message, "private_evidence_erasure_unavailable");
  assertEquals(calls, 1);
});
