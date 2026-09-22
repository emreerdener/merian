import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { createDescribeHandler } from "./index.ts";
import type { AIAdapter, AIProviderOutcome } from "../_shared/ai/contracts.ts";
import { createAIExecution } from "../_shared/ai/execution.ts";
import { resolveAIClaim } from "../_shared/ai/registry.ts";
import { parseIdentifySuccessEnvelope } from "../_shared/identify/contract.ts";

const scanId = "00000000-0000-4000-8000-000000000101";
const user: User = {
  id: "00000000-0000-4000-8000-000000000201",
  app_metadata: {},
  user_metadata: {},
  aud: "authenticated",
  created_at: "2026-09-21T00:00:00Z",
};
const draft = {
  is_biological_subject: false,
  is_live_capture: false,
  common_name: "Synthetic Object",
  confidence_score: 0.75,
  ai_reasoning: "Synthetic description identifies a manufactured object.",
  extracted_visual_traits: ["synthetic smooth surface"],
  candidates: [],
  image_quality: {
    sharpness: 0,
    framing: 0,
    diagnostic_utility: 0,
    overall_score: 0,
  },
  pet_identification: null,
};
const envelope = parseIdentifySuccessEnvelope({
  success: true,
  data: {
    ...draft,
    scan_id: scanId,
    inference_tier: "flash",
    blur_score: 0,
    colors: [],
    estimated_size_cm: null,
  },
});
const facts = {
  providerDurationMs: 1,
  providerCompletedAt: Date.now(),
  returnedModel: null,
  usage: null,
  finishReason: "STOP",
  responseCharacters: 0,
};

// The deterministic provider exists only in this test module. Production
// prepareAIExecution has no provider argument, lookup name, or environment hook.
function testAdapter(
  events: string[],
  outcome: AIProviderOutcome | Error,
): AIAdapter {
  return {
    provider: "test_only",
    prepare(request, snapshot) {
      assert(request.variant === "description_compat");
      assertEquals(request.evidence, [{
        kind: "text",
        source: "description",
        order: 0,
        text: "Observation Description:\nSynthetic description.",
      }]);
      assertEquals(snapshot.model, "gemini-2.5-flash");
      events.push("prepare");
      return () => {
        events.push("invoke");
        if (outcome instanceof Error) return Promise.reject(outcome);
        return Promise.resolve(outcome);
      };
    },
  };
}

function database(
  options: {
    replay?: boolean;
    commitDenied?: boolean;
    consentDenied?: boolean;
    setupFailed?: boolean;
    unknownInsert?: boolean;
  } = {},
) {
  const events: string[] = [];
  const updates: Record<string, unknown>[] = [];
  let inserted: Record<string, unknown> | null = null;
  const response = (
    data: unknown,
    error: { message: string } | null = null,
  ) => {
    const promise = Promise.resolve({ data, error });
    return Object.assign(promise, { abortSignal: () => promise });
  };
  const client = {
    rpc(name: string, args: Record<string, unknown> = {}) {
      switch (name) {
        case "get_entitlement_rollout_service":
          return response({
            entitlement_mode: "complimentary",
            required_client_protocol: 3,
            mode_version: 1,
          });
        case "recover_stranded_scan_ingestion_attempt":
          return response({ outcome: "job_not_found" });
        case "ensure_scan_user_profile":
          return response(null);
        case "reserve_ai_quota":
          events.push("reserve");
          assertEquals(args.p_user_id, user.id);
          assertEquals(args.p_request_id, scanId);
          assertEquals(args.p_operation, "scan_identification");
          if (options.consentDenied) {
            return response(null, { message: "ai_consent_required" });
          }
          return response({
            reservation_id: "00000000-0000-4000-8000-000000000301",
            request_id: scanId,
            lease_token: "00000000-0000-4000-8000-000000000401",
            lease_expires_at: "2099-01-01T00:00:00Z",
            reservation_state: "reserved",
            is_replay: false,
            attempt_count: 1,
            model: "gemini-2.5-flash",
            effective_plan: "free",
            effective_tier: "free",
            subscription_tier: "free",
            trial_active: false,
            entitlement_version: 1,
            policy_version: 1,
            daily_limit: 100,
            daily_remaining: 99,
            original_analysis_id: scanId,
            complimentary_client_scan_id: null,
            flash_fallback_used: false,
            scans_remaining: 0,
            scans_available_to_start: 0,
            in_flight_count: 0,
          });
        case "begin_scan_ingestion":
          events.push("ledger");
          if (options.setupFailed) {
            return response(null, { message: "Synthetic setup failure" });
          }
          return response({
            upload_session_ids: [],
            manifest_checksum: "a".repeat(64),
            payload_checksum: "b".repeat(64),
            stage: "claimed",
            already_complete: false,
          });
        case "finalize_ai_quota_reservation":
          events.push(String(args.p_final_state));
          return response(
            !(options.commitDenied && args.p_final_state === "committed"),
          );
        case "fail_scan_ingestion_terminal":
          events.push("terminal");
          return response(null);
        case "complete_scan_ingestion_with_entitlement":
          events.push("complete");
          return response({
            result: "completed",
            response_envelope: args.p_response_envelope,
          });
        default:
          throw new Error(`Unexpected RPC: ${name}`);
      }
    },
    from(table: string) {
      const filters: Record<string, unknown> = {};
      let action = "read";
      const query = {
        select: () => query,
        eq: (key: string, value: unknown) => {
          filters[key] = value;
          return query;
        },
        abortSignal: () => query,
        not: () => query,
        update: (value: Record<string, unknown>) => {
          assertEquals(table, "scan_ingestion_jobs");
          action = "update";
          updates.push(value);
          events.push(String(value.status));
          return query;
        },
        upsert: (value: Record<string, unknown>) => {
          assertEquals(table, "scans");
          events.push("insert");
          action = "insert";
          if (options.unknownInsert) {
            throw new Error("Synthetic lost write response");
          }
          inserted = value;
          return query;
        },
        maybeSingle: () => {
          if (table === "scan_ingestion_jobs") {
            assertEquals(filters, { scan_id: scanId, user_id: user.id });
            return response(
              options.replay
                ? { status: "complete", response_envelope: envelope }
                : null,
            );
          }
          if (table === "scans") {
            assertEquals(filters, { id: scanId, user_id: user.id });
            return response(inserted ? { id: scanId } : null);
          }
          throw new Error(`Unexpected read: ${table}`);
        },
        then: (resolve: (value: { data: null; error: null }) => unknown) => {
          assert(action !== "read");
          return Promise.resolve({ data: null, error: null }).then(resolve);
        },
      };
      return query;
    },
  } as unknown as SupabaseClient;
  return { client, events, updates, inserted: () => inserted };
}

function request() {
  return new Request("https://example.invalid/identify-describe", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Merian-Entitlement-Protocol": "3",
    },
    body: JSON.stringify({
      user_id: user.id,
      client_scan_id: scanId,
      description: "Synthetic description.",
      geoprivacy: "private",
    }),
  });
}

Deno.test("describe handler executes the shared boundary and preserves recovery", async (t) => {
  const saved = Deno.env.get("AI_QUOTA_IP_HASH_SECRET");
  const savedPosthog = Deno.env.get("POSTHOG_API_KEY");
  const log = console.log, error = console.error, warn = console.warn;
  try {
    Deno.env.set(
      "AI_QUOTA_IP_HASH_SECRET",
      "synthetic-test-only-hash-secret".repeat(2),
    );
    Deno.env.delete("POSTHOG_API_KEY");
    console.log = console.error = console.warn = () => {};
    const run = (
      db: ReturnType<typeof database>,
      outcome: AIProviderOutcome | Error,
    ) => {
      const adapter = testAdapter(db.events, outcome);
      return createDescribeHandler((input, authority) =>
        createAIExecution(adapter, input, resolveAIClaim(input, authority))
      )(request(), user, db.client);
    };
    await t.step(
      "stored completion returns without reservation or adapter preparation",
      async () => {
        const db = database({ replay: true });
        const result = await run(db, new Error("Must not invoke"));
        assertEquals(result.status, 200);
        assertEquals(
          result.headers.get("X-Merian-Idempotent-Replay"),
          "stored",
        );
        assertEquals(await result.json(), envelope);
        assertEquals(db.events, []);
      },
    );
    await t.step(
      "current consent denial stops before provider preparation",
      async () => {
        const db = database({ consentDenied: true });
        await assertRejects(
          () => run(db, new Error("Must not invoke")),
          Error,
          "Confirm you are 18",
        );
        assertEquals(db.events, ["reserve"]);
      },
    );
    await t.step("setup failure refunds before preparation", async () => {
      const db = database({ setupFailed: true });
      await assertRejects(
        () => run(db, new Error("Must not invoke")),
        Error,
        "Observation persistence",
      );
      assertEquals(db.events, ["reserve", "ledger", "terminal", "refunded"]);
    });
    await t.step(
      "binding mismatch refunds without commitment or dispatch",
      async () => {
        const db = database();
        const result = await createDescribeHandler((input, authority) => {
          assert(authority.kind === "user_request");
          resolveAIClaim(input, {
            ...authority,
            operation: "scan_audio_identification",
          });
          throw new Error("unreachable");
        })(request(), user, db.client);
        assertEquals(result.status, 503);
        assertEquals(db.events, [
          "reserve",
          "ledger",
          "refunded",
          "failed_retryable",
        ]);
      },
    );
    await t.step("failed quota commitment never invokes", async () => {
      const db = database({ commitDenied: true });
      assertEquals((await run(db, new Error("Must not invoke"))).status, 503);
      assertEquals(db.events, [
        "reserve",
        "ledger",
        "prepare",
        "committed",
        "refunded",
        "failed_retryable",
      ]);
    });
    for (
      const outcome of [
        new Error("Synthetic lost response"),
        new DOMException("Synthetic cancellation", "AbortError"),
        { ...facts, kind: "unknown_execution" as const },
        { ...facts, kind: "operational_failure" as const },
        { ...facts, kind: "invalid_output" as const, reason: "json" as const },
        {
          ...facts,
          kind: "invalid_output" as const,
          reason: "finish" as const,
          finishReason: "MAX_TOKENS",
        },
        { ...facts, kind: "draft" as const, draft: { invalid: true } },
      ]
    ) {
      await t.step(
        `charged failure ${
          outcome instanceof Error ? outcome.name : outcome.kind
        } invokes once`,
        async () => {
          const db = database();
          assertEquals((await run(db, outcome)).status, 503);
          assertEquals(db.events, [
            "reserve",
            "ledger",
            "prepare",
            "committed",
            "invoke",
            "failed",
            "failed_retryable",
          ]);
          assertEquals(db.updates[0].status, "failed_retryable");
          assert(typeof db.updates[0].retry_after === "string");
        },
      );
    }
    for (const finishReason of ["SAFETY", "PROHIBITED_CONTENT"]) {
      await t.step(
        `${finishReason} keeps the existing terminal policy response`,
        async () => {
          const db = database();
          const response = await run(db, {
            ...facts,
            kind: "refusal",
            finishReason,
          });
          assertEquals(response.status, 400);
          assertEquals((await response.json()).code, "observation_rejected");
          assertEquals(db.events, [
            "reserve",
            "ledger",
            "prepare",
            "committed",
            "invoke",
            "terminal",
          ]);
        },
      );
    }
    await t.step(
      "successful draft reaches durable owner persistence with usage intact",
      async () => {
        const db = database();
        const result = await run(db, {
          ...facts,
          kind: "draft",
          draft,
          usage: {
            promptTokens: 100,
            candidateTokens: 20,
            totalTokens: 127,
            thinkingTokens: 7,
            cachedTokens: 5,
            modalityBreakdown: {
              prompt: { text: 100 },
              cached: {},
              candidates: {},
              tool: {},
            },
          },
        });
        assertEquals(result.status, 200);
        assertEquals(await result.json(), envelope);
        assertEquals(db.events, [
          "reserve",
          "ledger",
          "prepare",
          "committed",
          "invoke",
          "finalizing",
          "insert",
          "complete",
        ]);
        const row = db.inserted()!;
        assertEquals([
          row.llm_prompt_tokens,
          row.llm_candidate_tokens,
          row.llm_total_tokens,
          row.llm_thinking_tokens,
          row.llm_cached_tokens,
        ], [100, 20, 127, 7, 5]);
        assertEquals(row.llm_usage_metadata, {
          prompt: { text: 100 },
          cached: {},
          candidates: {},
          tool: {},
        });
        assertEquals(row.image_storage_urls, []);
        assertEquals(row.is_live_capture, false);
      },
    );
    await t.step(
      "unknown database write preserves charged recovery ownership",
      async () => {
        const db = database({ unknownInsert: true });
        const result = await run(db, { ...facts, kind: "draft", draft });
        assertEquals(result.status, 503);
        assertEquals((await result.json()).code, "scan_persistence_failed");
        assertEquals(db.events, [
          "reserve",
          "ledger",
          "prepare",
          "committed",
          "invoke",
          "finalizing",
          "insert",
          "failed_retryable",
        ]);
      },
    );
  } finally {
    console.log = log;
    console.error = error;
    console.warn = warn;
    if (saved == null) Deno.env.delete("AI_QUOTA_IP_HASH_SECRET");
    else Deno.env.set("AI_QUOTA_IP_HASH_SECRET", saved);
    if (savedPosthog == null) Deno.env.delete("POSTHOG_API_KEY");
    else Deno.env.set("POSTHOG_API_KEY", savedPosthog);
  }
});
