import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { AIQuotaReservation } from "../aiQuota.ts";
import type { AIExecutionOutcome } from "../ai/contracts.ts";
import { openAIPhotoSnapshot } from "../ai/openaiPhoto.ts";
import { initialCanonicalText } from "./canonical.ts";
import { prepareInitialAccountedIdentification } from "./dispatchAccounting.ts";
import { initialDeadline } from "./transport.ts";

const id = "00000000-0000-4000-8000-000000000101";
const other = "00000000-0000-4000-8000-000000000102";
const binding = {
  owner_id: id,
  scan_id: id,
  submission_digest: "a".repeat(64),
  config_digest: "b".repeat(64),
  funding_binding_id: id,
  funding_binding_digest: "c".repeat(64),
  admission_receipt_id: id,
  admission_receipt_digest: "d".repeat(64),
};
const fresh = {
  version: 1,
  owner_id: id,
  scan_id: id,
  submission_digest: binding.submission_digest,
  admission_receipt_id: id,
  admission_receipt_digest: binding.admission_receipt_digest,
  outcome: "fresh",
  invocation_id: id,
};
const usageReply = {
  version: 1,
  owner_id: id,
  scan_id: id,
  submission_digest: binding.submission_digest,
  invocation_id: id,
  event_id: other,
};
const snapshot = openAIPhotoSnapshot({
  task: "identify",
  variant: "multimodal",
  evidence: [{
    kind: "image",
    order: 0,
    inputIndex: 0,
    lineage: null,
    data: "AA==",
    mimeType: "image/jpeg",
  }],
  capture: {
    hasVideo: false,
    videoClipCount: 0,
    declaredVideoFrameCount: 0,
    videoInferenceFrameCount: 0,
  },
}, 1);
const result: AIExecutionOutcome = {
  kind: "draft",
  draft: { synthetic: "private output" },
  execution: { ...snapshot, durationMs: 1 },
  providerDurationMs: 1,
  providerCompletedAt: 1000,
  returnedModel: "gpt-6-sol",
  usage: null,
  finishReason: "completed",
  responseCharacters: 20,
};
function setup(options: {
  dispatch?: () => Promise<Response>;
  report?: () => Promise<Response>;
  provider?: () => Promise<AIExecutionOutcome>;
  caller?: AbortSignal;
  evidence?: string;
  origin?: string;
} = {}) {
  const calls: { path: string; args: Record<string, unknown> }[] = [];
  const events: string[] = [];
  const caller = options.caller ?? new AbortController().signal;
  const client = {
    rpc() {
      throw new Error("ordinary RPC must not be called");
    },
  } as unknown as SupabaseClient;
  const prepared = prepareInitialAccountedIdentification({
    client,
    reservation: {
      id,
      leaseToken: id,
      requestId: id,
      attemptCount: 1,
    } as AIQuotaReservation,
    execution: {
      snapshot,
      invoke: () => {
        events.push("provider");
        return options.provider ? options.provider() : Promise.resolve(result);
      },
    },
    binding: { ...binding },
    executionEvidence: options.evidence ??
      initialCanonicalText({ version: 1, synthetic_verifier_proof: true }),
    origin: options.origin ?? "https://project.supabase.co",
    serverApiKey: ["sb", "secret", "fixture", "a".repeat(20)].join("_"),
    caller,
    fetcher: async (url, init) => {
      const path = new URL(String(url)).pathname.split("/").at(-1)!;
      const args = JSON.parse(String(init?.body));
      calls.push({ path, args });
      events.push(path);
      assertEquals(init?.redirect, "error");
      assertEquals(init?.cache, "no-store");
      assertEquals(init?.credentials, "omit");
      assertEquals(init?.method, "POST");
      if (path === "authorize_initial_analysis_dispatch") {
        return options.dispatch
          ? await options.dispatch()
          : Response.json(fresh);
      }
      assertEquals(path, "report_initial_analysis_usage");
      assert(!init?.signal?.aborted);
      return options.report
        ? await options.report()
        : Response.json(usageReply);
    },
  });
  return { prepared, calls, events };
}
Deno.test("initial composition exposes one invocation only, fixed original RPCs, no generic lease", async () => {
  const { prepared, calls, events } = setup();
  assertEquals(Object.keys(prepared), ["invoke"]);
  const run = prepared.invoke();
  await assertRejects(() => prepared.invoke());
  assertEquals(await run, { invocationId: id, outcome: result });
  await assertRejects(() => prepared.invoke());
  assertEquals(events, [
    "authorize_initial_analysis_dispatch",
    "provider",
    "report_initial_analysis_usage",
  ]);
  assertEquals(Object.keys(calls[0].args).sort(), [
    "p_execution_evidence",
    "p_expected",
    "p_lease_token",
    "p_owner",
    "p_scan",
  ]);
  const expected = JSON.parse(String(calls[0].args.p_expected));
  assertEquals(expected.config_digest, binding.config_digest);
  assertEquals(expected.funding_binding_digest, binding.funding_binding_digest);
  assertEquals(expected.admission_receipt_id, binding.admission_receipt_id);
  assertEquals(calls[1].args.p_invocation, id);
  assertEquals(calls[1].args.p_outcome, "draft");
  assertEquals(JSON.stringify(calls).includes("private output"), false);
});
for (
  const [name, reply] of Object.entries({
    held: { ...fresh, outcome: "held", invocation_id: null },
    replay: { ...fresh, outcome: "replay" },
    wrong_owner: { ...fresh, owner_id: other },
    wrong_scan: { ...fresh, scan_id: other },
    wrong_submission: { ...fresh, submission_digest: "f".repeat(64) },
    wrong_receipt: { ...fresh, admission_receipt_id: other },
    wrong_receipt_digest: {
      ...fresh,
      admission_receipt_digest: "f".repeat(64),
    },
    invalid_invocation: { ...fresh, invocation_id: "bad" },
    extra_key: { ...fresh, may_dispatch: true },
    missing_key: { ...fresh, invocation_id: undefined },
  })
) {
  Deno.test(`initial dispatch ${name} never invokes, refunds or retries`, async () => {
    const { prepared, calls, events } = setup({
      dispatch: () => Promise.resolve(Response.json(reply)),
    });
    await assertRejects(() => prepared.invoke());
    await assertRejects(() => prepared.invoke());
    assertEquals(calls.length, 1);
    assertEquals(events, ["authorize_initial_analysis_dispatch"]);
  });
}
for (
  const mode of ["lost_ack", "gateway", "oversized", "invalid_utf8"] as const
) {
  Deno.test(`initial ${mode} dispatch outcome is held without retry`, async () => {
    const { prepared, calls, events } = setup({
      dispatch: () => {
        if (mode === "lost_ack") {
          return Promise.reject(new Error("synthetic lost reply"));
        }
        return Promise.resolve(
          mode === "gateway"
            ? Response.json(fresh, { status: 503 })
            : mode === "oversized"
            ? new Response(" ".repeat(8193))
            : new Response(new Uint8Array([255])),
        );
      },
    });
    await assertRejects(() => prepared.invoke());
    await assertRejects(() => prepared.invoke());
    assertEquals(calls.length, 1);
    assertEquals(events, ["authorize_initial_analysis_dispatch"]);
  });
}
Deno.test("initial cancellation before dispatch performs no I/O", async () => {
  const caller = new AbortController();
  caller.abort();
  const { prepared, calls } = setup({ caller: caller.signal });
  await assertRejects(() => prepared.invoke());
  assertEquals(calls, []);
});
Deno.test("late fresh acknowledgement after bounded cancellation cannot dispatch", async () => {
  const pending = Promise.withResolvers<Response>();
  let cancelCount = 0;
  await initialDeadline(new AbortController().signal, 10, async (caller) => {
    const { prepared, calls, events } = setup({
      caller,
      dispatch: () => pending.promise,
    });
    await assertRejects(() => prepared.invoke());
    pending.resolve(
      new Response(
        new ReadableStream({
          cancel() {
            cancelCount += 1;
          },
        }),
      ),
    );
    // Flush late fulfillment/disposal without sleeping past another deadline.
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
    await assertRejects(() => prepared.invoke());
    assertEquals(calls.length, 1);
    assertEquals(events, ["authorize_initial_analysis_dispatch"]);
  });
  assertEquals(cancelCount, 1);
});
Deno.test("foreground cancellation during provider execution still reports and preserves original result", async () => {
  const caller = new AbortController();
  const { prepared, calls } = setup({
    caller: caller.signal,
    provider: () => {
      caller.abort();
      return Promise.resolve(result);
    },
  });
  assertEquals(await prepared.invoke(), { invocationId: id, outcome: result });
  assertEquals(calls.length, 2);
});
Deno.test("failed initial usage report preserves result and never invokes again", async () => {
  const { prepared, calls, events } = setup({
    report: () => Promise.reject(new Error("synthetic report loss")),
  });
  assertEquals(await prepared.invoke(), { invocationId: id, outcome: result });
  await assertRejects(() => prepared.invoke());
  assertEquals(calls.length, 2);
  assertEquals(events.filter((e) => e === "provider").length, 1);
});
Deno.test("initial provider exception reports unknown once before rethrowing", async () => {
  const { prepared, calls } = setup({
    provider: () => Promise.reject(new Error("synthetic provider error")),
  });
  await assertRejects(
    () => prepared.invoke(),
    Error,
    "synthetic provider error",
  );
  assertEquals(calls[1].args.p_outcome, "unknown_execution");
  assertEquals(calls[1].args.p_usage, "{}");
  await assertRejects(() => prepared.invoke());
  assertEquals(calls.length, 2);
});
Deno.test("initial evidence and endpoint bounds reject before networking", () => {
  for (const evidence of ["{} ", "null", "[]", " ".repeat(65537)]) {
    assertThrows(() => setup({ evidence }));
  }
  for (
    const origin of [
      "https://project.supabase.co/path",
      "https://project.supabase.co?other=1",
      "http://remote.invalid",
    ]
  ) assertThrows(() => setup({ origin }));
});

Deno.test("initial reporting deadline bounds an abort-ignoring dependency without losing the result", async () => {
  const { prepared, calls, events } = setup({
    report: () => new Promise<Response>(() => {}),
  });
  const start = performance.now();
  assertEquals(await prepared.invoke(), { invocationId: id, outcome: result });
  const elapsed = performance.now() - start;
  assert(elapsed >= 4900 && elapsed < 7000);
  await assertRejects(() => prepared.invoke());
  assertEquals(calls.length, 2);
  assertEquals(events.filter((event) => event === "provider").length, 1);
});
