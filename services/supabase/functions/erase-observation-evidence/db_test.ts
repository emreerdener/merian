import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { evidenceErasureRepository } from "./db.ts";

Deno.test("private erasure diagnostics expose only fixed stages and categories", async () => {
  const secret = "private-owner-dispatch-object-token-response";
  const logs: unknown[] = [];
  let code = "57014";
  const client = {
    rpc: () => ({
      abortSignal: () =>
        Promise.resolve({
          data: secret,
          error: { code, message: secret, details: secret, hint: secret },
        }),
    }),
  } as unknown as SupabaseClient;
  const repo = evidenceErasureRepository(
    client,
    secret,
    (event, details) => logs.push({ event, ...details }),
  );
  const signal = new AbortController().signal;
  const calls = [
    () => repo.retire(signal),
    () => repo.retireVideo(signal),
    () => repo.retireComposition(signal),
    () => repo.claim(signal),
    () =>
      repo.finish(secret, secret, false, signal, {
        namespace: "history",
        backend_sha256: null,
      }),
  ];
  for (const call of calls) {
    await assertRejects(call, Error, "private_evidence_erasure_unavailable");
  }
  assertEquals(
    logs,
    ["retire_history", "retire_video", "retire_composition", "claim", "finish"]
      .map((stage) => ({
        event: "private_evidence_rpc_failed",
        stage,
        code: "database_query_cancelled",
      })),
  );
  for (
    const [input, expected] of [
      ["55P03", "database_lock_unavailable"],
      ["42501", "database_permission_denied"],
      ["42883", "database_routine_missing"],
      ["P0001", "database_error"],
      [secret, "database_error"],
    ]
  ) {
    code = input;
    await assertRejects(() => repo.claim(signal));
    assertEquals(logs.at(-1), {
      event: "private_evidence_rpc_failed",
      stage: "claim",
      code: expected,
    });
  }
  assert(!JSON.stringify(logs).includes(secret));
});

Deno.test("private erasure diagnostic failure preserves original transport rejection and makes no retry", async () => {
  let calls = 0;
  const original = new Error("private transport response");
  const client = {
    rpc: () => ({
      abortSignal: () => {
        calls++;
        return Promise.reject(original);
      },
    }),
  } as unknown as SupabaseClient;
  const repo = evidenceErasureRepository(client, "private dispatch", () => {
    throw new Error("logger failed");
  });
  const error = await assertRejects(() =>
    repo.claim(new AbortController().signal)
  );
  assertEquals(error, original);
  assertEquals(calls, 1);
});

Deno.test("private erasure parent cancellation logs no reason payload and issues no RPC", async () => {
  const controller = new AbortController();
  controller.abort(new Error("private cancellation payload"));
  const logs: unknown[] = [];
  const client = {
    rpc: () => {
      throw new Error("must not dispatch");
    },
  } as unknown as SupabaseClient;
  const repo = evidenceErasureRepository(
    client,
    "private dispatch",
    (event, details) => logs.push({ event, ...details }),
  );
  await assertRejects(() => repo.claim(controller.signal));
  assertEquals(logs, [{
    event: "private_evidence_rpc_failed",
    stage: "claim",
    code: "parent_cancelled",
  }]);
});

Deno.test("private erasure successful RPCs emit no failure diagnostics", async () => {
  const logs: unknown[] = [];
  const client = {
    rpc: () => ({
      abortSignal: () => Promise.resolve({ data: null, error: null }),
    }),
  } as unknown as SupabaseClient;
  assertEquals(
    await evidenceErasureRepository(
      client,
      "private dispatch",
      (...args) => logs.push(args),
    ).claim(new AbortController().signal),
    null,
  );
  assertEquals(logs, []);
});

Deno.test("private erasure unchanged twelve-second RPC deadline emits fixed diagnosis", async () => {
  const logs: unknown[] = [];
  let calls = 0;
  const client = {
    rpc: () => ({
      abortSignal: () => {
        calls++;
        return new Promise(() => {});
      },
    }),
  } as unknown as SupabaseClient;
  await assertRejects(() =>
    evidenceErasureRepository(
      client,
      "private dispatch",
      (event, details) => logs.push({ event, ...details }),
    ).claim(new AbortController().signal)
  );
  assertEquals(calls, 1);
  assertEquals(logs, [{
    event: "private_evidence_rpc_failed",
    stage: "claim",
    code: "rpc_deadline",
  }]);
});

Deno.test("private erasure production logger never receives database detail or identities", async () => {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.join(" "));
  };
  try {
    const client = {
      rpc: () => ({
        abortSignal: () =>
          Promise.resolve({
            data: "sensitive data",
            error: {
              code: "unknown-sensitive-code",
              message: "sensitive message",
            },
          }),
      }),
    } as unknown as SupabaseClient;
    await assertRejects(() =>
      evidenceErasureRepository(client, "sensitive dispatch").claim(
        new AbortController().signal,
      )
    );
    assertEquals(logs.length, 1);
    const row = JSON.parse(logs[0]);
    assertEquals(Object.keys(row).sort(), ["code", "event", "stage", "ts"]);
    assertEquals(row.code, "database_error");
    assertEquals(row.stage, "claim");
    assertEquals(row.event, "private_evidence_rpc_failed");
    assert(!logs[0].includes("sensitive"));
  } finally {
    console.error = original;
  }
});
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
  const repository = evidenceErasureRepository(
      client,
      "00000000-0000-4000-8000-00000000ee01",
    ),
    signal = new AbortController().signal;
  assertEquals(await repository.retire(signal), 0);
  assertEquals(await repository.retireVideo(signal), 0);
  assertEquals(await repository.retireComposition(signal), 0);
  value = null;
  assertEquals(await repository.claim(signal), null);
  value = true;
  assertEquals(
    await repository.finish("object", "token", false, signal, {
      namespace: "history",
      backend_sha256: null,
    }),
    true,
  );
  assertEquals(calls, [["retire_expired_observation_evidence_for_dispatch", {
    p_dispatch_id: "00000000-0000-4000-8000-00000000ee01",
  }, false], [
    "retire_expired_observation_video_evidence_for_dispatch",
    { p_dispatch_id: "00000000-0000-4000-8000-00000000ee01" },
    false,
  ], [
    "retire_expired_observation_composition_evidence_for_dispatch",
    { p_dispatch_id: "00000000-0000-4000-8000-00000000ee01" },
    false,
  ], [
    "claim_private_evidence_erasure_v4_for_dispatch",
    { p_dispatch_id: "00000000-0000-4000-8000-00000000ee01" },
    false,
  ], ["finish_private_evidence_erasure_v4", {
    p_namespace: "history",
    p_backend: null,
    p_object: "object",
    p_claim: "token",
    p_success: false,
  }, false]]);
  value = "true";
  await assertRejects(() =>
    repository.finish("object", "token", true, signal, {
      namespace: "history",
      backend_sha256: null,
    })
  );
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
    evidenceErasureRepository(client, "00000000-0000-4000-8000-00000000ee01")
      .claim(new AbortController().signal)
  );
  assert(error instanceof Error);
  assertEquals(error.message, "private_evidence_erasure_unavailable");
  assertEquals(calls, 1);
});

Deno.test("private erasure malformed finish logs only fixed tokens and still rejects", async () => {
  for (
    const value of [null, "private response", { object: "private identity" }]
  ) {
    for (const loggerThrows of [false, true]) {
      const logs: unknown[] = [];
      let calls = 0;
      const client = {
        rpc: () => ({
          abortSignal: () => {
            calls++;
            return Promise.resolve({ data: value, error: null });
          },
        }),
      } as unknown as SupabaseClient;
      const repo = evidenceErasureRepository(
        client,
        "private dispatch",
        (event, details) => {
          logs.push({ event, ...details });
          if (loggerThrows) throw new Error("private logger failure");
        },
      );
      await assertRejects(
        () =>
          repo.finish(
            "private object",
            "private token",
            true,
            new AbortController().signal,
            { namespace: "history", backend_sha256: null },
          ),
        Error,
        "private_evidence_erasure_unavailable",
      );
      assertEquals(calls, 1);
      assertEquals(logs, [{
        event: "private_evidence_rpc_failed",
        stage: "finish",
        code: "rpc_invalid_response",
      }]);
    }
  }
});
