import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { handleIdentifyMultimodalRequest } from "./index.ts";
import type {
  AIAdapter,
  AIProviderOutcome,
  AIRequest,
} from "../_shared/ai/contracts.ts";
import { createAIExecution } from "../_shared/ai/execution.ts";
import { resolveAIClaim } from "../_shared/ai/registry.ts";
import { encodeBase64 } from "../_shared/encoding.ts";
import { encodeWav16 } from "../audio-spec/wav.ts";
import { deriveAIRequestId } from "../_shared/aiQuota.ts";
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
    sharpness: 1,
    framing: 1,
    diagnostic_utility: 1,
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

function database(
  options: {
    replay?: boolean;
    pro?: boolean;
    requestId?: string;
    commitDenied?: boolean;
    consentDenied?: boolean;
    setupFailed?: boolean;
    unknownInsert?: boolean;
    retired?: boolean;
  } = {},
) {
  const events: string[] = [];
  const updates: Record<string, unknown>[] = [];
  let inserted: Record<string, unknown> | null = null;
  let completed: unknown = null;
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
          return response(
            null,
            options.retired ? { message: "scan_user_identity_retired" } : null,
          );
        case "reserve_ai_quota":
          events.push("reserve");
          assertEquals(args.p_user_id, user.id);
          assertEquals(args.p_request_id, options.requestId ?? scanId);
          assertEquals(args.p_operation, "scan_identification");
          if (options.consentDenied) {
            return response(null, { message: "ai_consent_required" });
          }
          return response({
            reservation_id: "00000000-0000-4000-8000-000000000301",
            request_id: options.requestId ?? scanId,
            lease_token: "00000000-0000-4000-8000-000000000401",
            lease_expires_at: "2099-01-01T00:00:00Z",
            reservation_state: "reserved",
            is_replay: false,
            attempt_count: 1,
            model: options.pro ? "gemini-2.5-pro" : "gemini-2.5-flash",
            effective_plan: options.pro ? "pro_paid" : "free",
            effective_tier: options.pro ? "pro" : "free",
            subscription_tier: options.pro ? "pro" : "free",
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
          completed = args.p_response_envelope;
          return response({
            result: "completed",
            response_envelope: args.p_response_envelope,
          });
        case "hydrate_identification_dictionary":
          return response({ primary: null, candidate_common_names: {} });
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
        insert: (_value: Record<string, unknown>) => {
          assertEquals(table, "failed_scan_ingestions");
          action = "insert";
          events.push("dead_letter");
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
              options.replay || completed
                ? {
                  status: "complete",
                  response_envelope: completed ?? envelope,
                }
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

function request(
  overrides: Record<string, unknown> = {},
  signal?: AbortSignal,
) {
  return new Request("https://example.invalid/identify-multimodal", {
    method: "POST",
    signal,
    headers: {
      "Content-Type": "application/json",
      "X-Merian-Entitlement-Protocol": "3",
    },
    body: JSON.stringify({
      user_id: user.id,
      client_scan_id: scanId,
      observation_contexts: [{ freeText: "Synthetic description." }],
      geoprivacy: "private",
      ...overrides,
    }),
  });
}

function audioFixture(): string {
  const samples = new Float32Array(16000);
  for (let i = 0; i < samples.length; i++) samples[i] = 0.2 * Math.sin(i / 10);
  return encodeBase64(encodeWav16(samples, 16000));
}

Deno.test("multimodal handler preserves admission, evidence and recovery through the adapter", async (t) => {
  const savedHash = Deno.env.get("AI_QUOTA_IP_HASH_SECRET");
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
      payload: Record<string, unknown> = {},
      inspect: (input: AIRequest) => void = () => {},
      replayAttempt?: number,
    ) => {
      const adapter: AIAdapter = {
        provider: "test_only",
        prepare(input, snapshot) {
          inspect(input);
          assertEquals(input.variant, "multimodal");
          assertEquals(snapshot.generation.maxOutputTokens, 8192);
          db.events.push("prepare");
          return () => {
            db.events.push("invoke");
            if (outcome instanceof Error) return Promise.reject(outcome);
            return Promise.resolve({
              ...outcome,
              providerCompletedAt: Date.now(),
            });
          };
        },
      };
      return handleIdentifyMultimodalRequest(
        request(payload),
        user,
        db.client,
        0,
        replayAttempt,
        (input, authority) =>
          createAIExecution(adapter, input, resolveAIClaim(input, authority)),
      );
    };
    await t.step(
      "stored completion returns before media resolution and provider preparation",
      async () => {
        const db = database({ replay: true });
        const result = await run(db, new Error("Must not invoke"), {
          r2ObjectKeys: [`staging/${user.id}/synthetic.webp`],
        });
        assertEquals(result.status, 200);
        assertEquals(
          result.headers.get("X-Merian-Idempotent-Replay"),
          "stored",
        );
        assertEquals(await result.json(), envelope);
        assertEquals(db.events, []);
      },
    );
    await t.step("consent denial has no provider preparation", async () => {
      const db = database({ consentDenied: true });
      await assertRejects(
        () => run(db, new Error("Must not invoke")),
        Error,
        "Confirm you are 18",
      );
      assertEquals(db.events, ["reserve"]);
    });
    await t.step(
      "durable setup failure refunds without preparation",
      async () => {
        const db = database({ setupFailed: true });
        assertEquals((await run(db, new Error("Must not invoke"))).status, 503);
        assertEquals(db.events, ["reserve", "ledger", "refunded"]);
      },
    );
    await t.step(
      "binding/configuration failure refunds before commitment",
      async () => {
        const db = database();
        const result = await handleIdentifyMultimodalRequest(
          request(),
          user,
          db.client,
          0,
          undefined,
          (input, authority) => {
            assert(authority.kind === "user_request");
            resolveAIClaim(input, {
              ...authority,
              operation: "scan_audio_identification",
            });
            throw new Error("unreachable");
          },
        );
        assertEquals(result.status, 503);
        assertEquals(db.events, [
          "reserve",
          "ledger",
          "refunded",
          "failed_retryable",
        ]);
      },
    );
    await t.step("failed commitment has no invocation", async () => {
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
        { ...facts, kind: "unknown_execution" as const },
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
        `charged ${
          outcome instanceof Error ? "transport error" : outcome.kind
        } preserves retry ownership`,
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
          assert(typeof db.updates[0].retry_after === "string");
        },
      );
    }
    for (const finishReason of ["SAFETY", "PROHIBITED_CONTENT"]) {
      await t.step(`${finishReason} preserves policy rejection`, async () => {
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
      });
    }
    const audio = audioFixture();
    const mediaCases = [
      { label: "still", imageBase64s: ["AQ=="], audioBase64s: [] },
      { label: "audio", imageBase64s: [], audioBase64s: [audio] },
      {
        label: "five video snapshots",
        imageBase64s: ["AQ==", "Ag==", "Aw==", "BA==", "BQ=="],
        audioBase64s: [],
      },
      {
        label: "partial snapshots and companion",
        imageBase64s: ["AQ==", "Ag=="],
        audioBase64s: [audio],
      },
    ];
    for (const [caseIndex, media] of mediaCases.entries()) {
      await t.step(
        `${media.label} reaches the adapter once with ordered processed evidence`,
        async () => {
          const db = database({ pro: true });
          const isVideo = caseIndex >= 2;
          const result = await run(
            db,
            { ...facts, kind: "unknown_execution" },
            {
              imageBase64s: media.imageBase64s,
              audioBase64s: media.audioBase64s,
              visualMediaItems: media.imageBase64s.map((_, i) =>
                isVideo
                  ? { kind: "video_frame", clipIndex: 0, frameIndex: i }
                  : { kind: "image", sourceIndex: i }
              ),
              audioMediaItems: media.audioBase64s.map(() =>
                isVideo
                  ? { kind: "video_audio", clipIndex: 0 }
                  : { kind: "audio", sourceIndex: 0 }
              ),
              videoR2ObjectKeys: isVideo
                ? [`staging/${user.id}/synthetic.mp4`]
                : [],
              videoFrameCount: isVideo ? 5 : 0,
            },
            (input) => {
              assert(input.variant === "multimodal");
              const images = input.evidence.filter((part) =>
                part.kind === "image"
              );
              const sounds = input.evidence.filter((part) =>
                part.kind === "audio"
              );
              assertEquals(images.map((part) => part.data), media.imageBase64s);
              assertEquals(sounds.length, media.audioBase64s.length);
              assert(
                sounds.every((part) =>
                  part.mimeType === "audio/wav" && part.data.length > 0
                ),
              );
              assertEquals(input.capture.hasVideo, isVideo);
              if (isVideo) {
                assertEquals(
                  input.capture.videoInferenceFrameCount,
                  media.imageBase64s.length,
                );
              }
              if (isVideo && sounds.length) {
                assertEquals(sounds[0].lineage, {
                  kind: "video_audio",
                  sourceIndex: undefined,
                  clipIndex: 0,
                });
              }
              assert(!JSON.stringify(input).includes("staging/"));
            },
          );
          assertEquals(result.status, 503);
          assertEquals(db.events, [
            "reserve",
            "ledger",
            "prepare",
            "committed",
            "invoke",
            "failed",
            "failed_retryable",
          ]);
        },
      );
    }
    await t.step(
      "malformed audio is rejected without losing it from a mixed request",
      async () => {
        const db = database();
        const result = await run(db, new Error("Must not invoke"), {
          imageBase64s: ["AQ=="],
          audioBase64s: ["AQ=="],
        });
        assertEquals(result.status, 400);
        assertEquals((await result.json()).code, "unsupported_audio_codec");
        assertEquals(db.events, []);
      },
    );
    await t.step(
      "service replay still uses owner admission and separately metered request ID",
      async () => {
        const requestId = await deriveAIRequestId(
          scanId,
          "scan-ingestion-replay:2",
        );
        const db = database({ requestId });
        const result = await run(
          db,
          { ...facts, kind: "unknown_execution" },
          {},
          () => {},
          2,
        );
        assertEquals(result.status, 503);
        assertEquals(db.events.filter((event) => event === "invoke").length, 1);
      },
    );
    await t.step(
      "description completion preserves usage and provider timing without image defaults",
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
            modalityBreakdown: { prompt: { text: 100 } },
          },
        });
        assertEquals(result.status, 200);
        const data = (await result.json()).data;
        assertEquals(data.common_name, draft.common_name);
        assertEquals(data.confidence_score, draft.confidence_score);
        // Main text mode retains its existing visual-schema projection, unlike
        // the separate description-compatibility endpoint.
        assertEquals(data.blur_score, 0.9);
        assert(
          result.headers.get("Server-Timing")?.includes("provider;dur=1.0"),
        );
        const row = db.inserted()!;
        assertEquals([
          row.llm_prompt_tokens,
          row.llm_candidate_tokens,
          row.llm_total_tokens,
          row.llm_thinking_tokens,
          row.llm_cached_tokens,
        ], [100, 20, 127, 7, null]);
        assertEquals(row.llm_usage_metadata, { prompt: { text: 100 } });
        assert(db.events.indexOf("complete") > db.events.indexOf("insert"));
        assertEquals(db.events.filter((event) => event === "invoke").length, 1);
      },
    );
    await t.step(
      "unknown persistence retains committed provider quota",
      async () => {
        const db = database({ unknownInsert: true });
        const result = await run(db, { ...facts, kind: "draft", draft });
        assertEquals(result.status, 503);
        assertEquals((await result.json()).code, "scan_persistence_failed");
        assert(
          !db.events.includes("failed") && !db.events.includes("refunded"),
        );
        assert(db.events.includes("failed_retryable"));
      },
    );
    await t.step(
      "foreground cancellation can finalize and replay without another invocation",
      async () => {
        const db = database();
        const controller = new AbortController();
        let entered!: () => void;
        const started = new Promise<void>((resolve) => entered = resolve);
        let release!: (result: AIProviderOutcome) => void;
        const completion = new Promise<AIProviderOutcome>((resolve) =>
          release = resolve
        );
        const adapter: AIAdapter = {
          provider: "test_only",
          prepare() {
            db.events.push("prepare");
            return () => {
              db.events.push("invoke");
              entered();
              return completion;
            };
          },
        };
        const active = handleIdentifyMultimodalRequest(
          request({}, controller.signal),
          user,
          db.client,
          0,
          undefined,
          (input, authority) =>
            createAIExecution(adapter, input, resolveAIClaim(input, authority)),
        );
        await started;
        controller.abort();
        release({
          ...facts,
          providerCompletedAt: Date.now(),
          kind: "draft",
          draft,
        });
        const first = await active;
        assertEquals(first.status, 200);
        const replay = await run(db, new Error("Must not invoke"));
        assertEquals(replay.status, 200);
        assertEquals(
          replay.headers.get("X-Merian-Idempotent-Replay"),
          "stored",
        );
        assertEquals(await replay.json(), await first.json());
        assertEquals(db.events.filter((event) => event === "invoke").length, 1);
      },
    );
    await t.step(
      "identity retired during a committed call cannot save or complete a scan",
      async () => {
        const options = { retired: false };
        const db = database(options);
        const started = Promise.withResolvers<void>();
        const completion = Promise.withResolvers<AIProviderOutcome>();
        const adapter: AIAdapter = {
          provider: "test_only",
          prepare() {
            return () => {
              db.events.push("invoke");
              started.resolve();
              return completion.promise;
            };
          },
        };
        const active = handleIdentifyMultimodalRequest(
          request(),
          user,
          db.client,
          0,
          undefined,
          (input, authority) =>
            createAIExecution(adapter, input, resolveAIClaim(input, authority)),
        );
        await started.promise;
        assert(db.events.includes("committed"));
        options.retired = true;
        completion.resolve({ ...facts, kind: "draft", draft });
        const result = await active;
        assertEquals(result.status, 503);
        assertEquals((await result.json()).code, "scan_persistence_failed");
        assertEquals(db.events.filter((event) => event === "invoke").length, 1);
        assertEquals(db.inserted(), null);
        assert(!db.events.includes("complete"));
        assert(!db.events.includes("refunded"));
        assert(db.events.includes("failed"));
        assert(db.events.includes("failed_retryable"));
        assert(db.events.includes("dead_letter"));
      },
    );
  } finally {
    console.log = log;
    console.error = error;
    console.warn = warn;
    if (savedHash == null) Deno.env.delete("AI_QUOTA_IP_HASH_SECRET");
    else Deno.env.set("AI_QUOTA_IP_HASH_SECRET", savedHash);
    if (savedPosthog == null) Deno.env.delete("POSTHOG_API_KEY");
    else Deno.env.set("POSTHOG_API_KEY", savedPosthog);
  }
});
