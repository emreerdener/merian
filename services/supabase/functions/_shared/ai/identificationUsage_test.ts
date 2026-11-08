import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { AIQuotaReservation } from "../aiQuota.ts";
import type { AIExecutionOutcome, PreparedAIExecution } from "./contracts.ts";
import { openAIPhotoSnapshot } from "./openaiPhoto.ts";
import {
  type IdentificationAccountingPort,
  prepareAccountedIdentification,
} from "./identificationUsage.ts";

const id = "00000000-0000-4000-8000-000000000101";
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
const reservation = {
  id,
  leaseToken: id,
  requestId: id,
  attemptCount: 1,
} as AIQuotaReservation;
function outcome(kind: AIExecutionOutcome["kind"]): AIExecutionOutcome {
  return {
    kind,
    ...(kind === "draft"
      ? { draft: { secret: "generated content must never persist" } }
      : {}),
    ...(kind === "invalid_output" ? { reason: "json" as const } : {}),
    execution: { ...snapshot, durationMs: 10 },
    returnedModel: "gpt-6-sol",
    serviceTier: "default",
    finishReason: "completed",
    providerDurationMs: 10,
    providerCompletedAt: 1000,
    responseCharacters: 20,
    usage: {
      promptTokens: 100,
      cachedTokens: 20,
      cacheWriteTokens: 5,
      outputTokens: 40,
      candidateTokens: 30,
      thinkingTokens: 10,
      toolTokens: 0,
      totalTokens: 140,
      modalityBreakdown: {},
    },
  } as AIExecutionOutcome;
}
function setup(
  options: {
    duplicate?: boolean;
    commitThrows?: boolean;
    reportFails?: boolean;
    providerThrows?: boolean;
    kind?: AIExecutionOutcome["kind"];
    missing?: boolean;
    accounting?: IdentificationAccountingPort;
  } = {},
) {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const events: string[] = [];
  const client = {
    rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      events.push(name);
      return {
        abortSignal: () => {
          if (name === "commit_identification_invocation") {
            if (options.commitThrows) {
              return Promise.reject(new Error("transport"));
            }
            return Promise.resolve({
              data: [{ invocation_id: id, may_dispatch: !options.duplicate }],
              error: null,
            });
          }
          if (options.reportFails) {
            return Promise.reject(new Error("synthetic private diagnostic"));
          }
          return Promise.resolve({ data: id, error: null });
        },
      };
    },
  } as unknown as SupabaseClient;
  const result = outcome(options.kind ?? "draft");
  const execution: PreparedAIExecution = {
    snapshot,
    invoke: () => {
      events.push("provider");
      if (options.providerThrows) return Promise.reject(new Error("provider"));
      return Promise.resolve(
        options.missing ? { ...result, usage: null } : result,
      );
    },
  };
  return {
    calls,
    events,
    accounted: prepareAccountedIdentification(
      client,
      id,
      reservation,
      execution,
      options.accounting,
    ),
  };
}
Deno.test("accounting durably commits before exactly one invocation and reports only native facts", async () => {
  const { calls, events, accounted } = setup();
  await assertRejects(() => accounted.invoke());
  await accounted.lease.commit();
  await accounted.lease.commit();
  await accounted.invoke();
  await assertRejects(() => accounted.invoke());
  assertEquals(events, [
    "commit_identification_invocation",
    "provider",
    "complete_identification_invocation",
  ]);
  assertEquals(calls[1].args.p_outcome, "draft");
  assertEquals(calls[1].args.p_usage, {
    input_tokens: 100,
    cached_tokens: 20,
    cache_write_tokens: 5,
    output_tokens: 40,
    candidate_tokens: 30,
    thinking_tokens: 10,
    total_tokens: 140,
    tool_tokens: 0,
    service_tier: "default",
    modality_breakdown: {},
  });
  assertEquals(JSON.stringify(calls).includes("generated content"), false);
});
for (const options of [{ duplicate: true }, { commitThrows: true }]) {
  Deno.test(`unowned or ambiguous accounting commit forbids dispatch ${JSON.stringify(options)}`, async () => {
    const { events, accounted } = setup(options);
    await assertRejects(() => accounted.lease.commit());
    await assertRejects(() => accounted.invoke());
    assertEquals(events, ["commit_identification_invocation"]);
  });
}
for (
  const kind of [
    "refusal",
    "invalid_output",
    "operational_failure",
    "unknown_execution",
  ] as const
) {
  Deno.test(`accounting retains provider usage on ${kind}`, async () => {
    const { calls, accounted } = setup({ kind });
    await accounted.lease.commit();
    assertEquals((await accounted.invoke()).kind, kind);
    assertEquals(calls[1].args.p_outcome, kind);
  });
}
Deno.test("missing usage remains null and report failure never retries provider", async () => {
  const { calls, events, accounted } = setup({
    reportFails: true,
    missing: true,
  });
  await accounted.lease.commit();
  assertEquals((await accounted.invoke()).kind, "draft");
  assertEquals(
    (calls[1].args.p_usage as Record<string, unknown>).input_tokens,
    null,
  );
  assertEquals(events.filter((e) => e === "provider").length, 1);
});
Deno.test("unexpected adapter throw records uncertainty without exception content", async () => {
  const { calls, accounted } = setup({ providerThrows: true });
  await accounted.lease.commit();
  await assertRejects(() => accounted.invoke());
  assertEquals(calls[1].args.p_outcome, "unknown_execution");
  assertEquals(calls[1].args.p_usage, {});
});

Deno.test("trusted accounting port commits before one provider call without ordinary RPCs", async () => {
  const portEvents: string[] = [];
  const reports: { invocationId: string; result: AIExecutionOutcome | null }[] =
    [];
  const { calls, events, accounted } = setup({
    accounting: {
      commit: () => {
        portEvents.push("committed");
        return Promise.resolve({ kind: "fresh", invocationId: id });
      },
      report: (invocationId, result) => {
        portEvents.push("reported");
        reports.push({ invocationId, result });
        return Promise.resolve();
      },
    },
  });
  await assertRejects(() => accounted.invoke());
  await accounted.lease.commit();
  await accounted.lease.commit();
  assertEquals(events, []);
  assertEquals(portEvents, ["committed"]);
  const first = accounted.invoke();
  await assertRejects(() => accounted.invoke());
  const result = await first;
  assertEquals(events, ["provider"]);
  assertEquals(portEvents, ["committed", "reported"]);
  assertEquals(reports, [{ invocationId: id, result }]);
  assertEquals(calls, []);
});

for (const decision of ["held", "ambiguous", "invalid_identity"] as const) {
  Deno.test(`trusted accounting ${decision} never grants provider execution`, async () => {
    let reports = 0;
    const { calls, events, accounted } = setup({
      accounting: {
        commit: () => {
          if (decision === "ambiguous") {
            return Promise.reject(new Error("synthetic transport uncertainty"));
          }
          return Promise.resolve(
            decision === "held"
              ? { kind: "held" }
              : { kind: "fresh", invocationId: "invalid" },
          );
        },
        report: () => {
          reports += 1;
          return Promise.resolve();
        },
      },
    });
    await assertRejects(() => accounted.lease.commit());
    await assertRejects(() => accounted.invoke());
    assertEquals(events, []);
    assertEquals(calls, []);
    assertEquals(reports, 0);
  });
}

Deno.test("trusted report failure preserves valid original result and does not retry provider", async () => {
  let reports = 0;
  const { calls, events, accounted } = setup({
    accounting: {
      commit: () => Promise.resolve({ kind: "fresh", invocationId: id }),
      report: () => {
        reports += 1;
        return Promise.reject(new Error("synthetic reporting failure"));
      },
    },
  });
  await accounted.lease.commit();
  assertEquals(await accounted.invoke(), outcome("draft"));
  await assertRejects(() => accounted.invoke());
  assertEquals(reports, 1);
  assertEquals(events, ["provider"]);
  assertEquals(calls, []);
});

Deno.test("trusted reporting is awaited and provider throw reports original uncertainty once", async () => {
  const reported = Promise.withResolvers<void>();
  const release = Promise.withResolvers<void>();
  const reports: { invocationId: string; result: AIExecutionOutcome | null }[] =
    [];
  const { calls, events, accounted } = setup({
    providerThrows: true,
    accounting: {
      commit: () => Promise.resolve({ kind: "fresh", invocationId: id }),
      report: (invocationId, result) => {
        reports.push({ invocationId, result });
        reported.resolve();
        return release.promise;
      },
    },
  });
  await accounted.lease.commit();
  let returned = false;
  const invocation = assertRejects(() => accounted.invoke(), Error, "provider")
    .then(() => {
      returned = true;
    });
  await reported.promise;
  assertEquals(returned, false);
  assertEquals(reports, [{ invocationId: id, result: null }]);
  release.resolve();
  await invocation;
  await assertRejects(() => accounted.invoke());
  assertEquals(events, ["provider"]);
  assertEquals(calls, []);
});
