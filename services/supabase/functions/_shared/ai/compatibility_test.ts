import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { createIdentifyHandler } from "../../identify/index.ts";
import { createAudioHandler } from "../../audio-spec/index.ts";
import { createDescribeHandler } from "../../identify-describe/index.ts";
import type { AIAdapter, AIProviderOutcome, AIRequest } from "./contracts.ts";
import { createAIExecution } from "./execution.ts";
import { resolveAIClaim } from "./registry.ts";
import { parseIdentifySuccessEnvelope } from "../identify/contract.ts";
import { encodeBase64 } from "../encoding.ts";
import { encodeWav16 } from "../../audio-spec/wav.ts";
import { buildReplayIdentifyPayload } from "../../replay-scan-ingestion/worker.ts";

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
    sharpness: 10,
    framing: 10,
    diagnostic_utility: 10,
    overall_score: 100,
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
    operation: "scan_identification" | "scan_audio_identification";
    replay?: boolean;
    finalizationFailed?: boolean;
    commitDenied?: boolean;
    consentDenied?: boolean;
    setupFailed?: boolean;
    unknownInsert?: boolean;
  },
) {
  const events: string[] = [];
  const updates: Record<string, unknown>[] = [];
  let inserted: Record<string, unknown> | null = null;
  let completed: unknown = null;
  let intent: Record<string, unknown> | null = null;
  let ledger: Record<string, unknown> | null = null;
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
          assertEquals(args.p_operation, options.operation);
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
          intent = args.p_request_payload as Record<string, unknown>;
          ledger = args;
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
          if (options.finalizationFailed) {
            return response(null, {
              message: "Synthetic finalization failure",
            });
          }
          completed = args.p_response_envelope;
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
        insert: () => {
          assertEquals(table, "failed_scan_ingestions");
          action = "insert";
          return query;
        },
        maybeSingle: () => {
          if (table === "users") {
            assertEquals(filters, { id: user.id });
            return response({ default_geoprivacy: "private" });
          }
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
  return {
    client,
    events,
    updates,
    inserted: () => inserted,
    intent: () => intent,
    ledger: () => ledger,
  };
}

const samples = new Float32Array(16000);
for (let i = 0; i < samples.length; i++) samples[i] = 0.2 * Math.sin(i / 10);
const wav = encodeWav16(samples, 16000);
const audioBase64 = encodeBase64(wav);

function request(audio: boolean, staged = false) {
  return new Request(
    `https://example.invalid/${audio ? "audio-spec" : "identify"}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Merian-Entitlement-Protocol": "3",
      },
      body: JSON.stringify({
        user_id: user.id,
        client_scan_id: scanId,
        geoprivacy: "private",
        ...(audio
          ? staged ? { audio_r2_key: `staging/${user.id}/synthetic.wav` } : {
            audio_base64: audioBase64,
            audio_r2_key: `staging/${user.id}/ignored.wav`,
          }
          : staged
          ? { r2ObjectKeys: [`staging/${user.id}/synthetic.webp`] }
          : {
            imageBase64s: ["AQ=="],
            r2ObjectKeys: [],
            description: "Synthetic note.",
          }),
      }),
    },
  );
}

Deno.test("compatibility handlers preserve paid work, media durability and replay", async (t) => {
  const settings: Record<string, string | null> = {
    AI_QUOTA_IP_HASH_SECRET: "synthetic-test-only-hash-secret".repeat(2),
    POSTHOG_API_KEY: null,
    SUPABASE_URL: "https://synthetic.supabase.co",
    SUPABASE_SERVER_API_KEY: ["sb", "secret", "synthetic_test_only_not_real"]
      .join("_"),
    R2_ACCOUNT_ID: "synthetic",
    R2_BUCKET_NAME: "synthetic",
    R2_ACCESS_KEY_ID: "synthetic-test-key",
    R2_SECRET_ACCESS_KEY: "synthetic-test-secret",
  };
  const saved = new Map(
    Object.keys(settings).map((name) => [name, Deno.env.get(name)]),
  );
  const originalFetch = globalThis.fetch;
  const runtime = globalThis as unknown as {
    EdgeRuntime?: { waitUntil(task: Promise<void>): void };
  };
  const originalRuntime = runtime.EdgeRuntime;
  const backgroundTasks: Promise<void>[] = [];
  const telemetry: Record<string, unknown>[] = [];
  const log = console.log, error = console.error, warn = console.warn;
  let mediaEvents: string[] = [];
  let storageFailure = false;
  let unsafe = false;
  try {
    for (const [name, value] of Object.entries(settings)) {
      if (value === null) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
    console.log = console.error = console.warn = () => {};
    runtime.EdgeRuntime = { waitUntil: (task) => backgroundTasks.push(task) };
    globalThis.fetch = async (input, init) => {
      const req = new Request(input, init);
      const url = new URL(req.url);
      if (url.origin === "https://us.i.posthog.com") {
        assertEquals(url.pathname, "/capture/");
        telemetry.push(await req.json());
        return new Response(null, { status: 200 });
      }
      if (
        url.origin === "https://synthetic.supabase.co" &&
        url.pathname === "/rest/v1/user_analytics_consent_events"
      ) {
        return Response.json([{
          event_kind: "granted",
          disclosure_version: "2026-08-04",
        }]);
      }
      if (url.origin === "https://synthetic.supabase.co" && unsafe) {
        assertEquals(url.pathname, "/rest/v1/users");
        if (req.method === "GET") {
          return Promise.resolve(Response.json({ abuse_strikes: 0 }));
        }
        assertEquals(req.method, "PATCH");
        return Promise.resolve(new Response(null, { status: 204 }));
      }
      assertEquals(url.origin, "https://synthetic.r2.cloudflarestorage.com");
      if (req.method === "GET") {
        mediaEvents.push("read");
        return Promise.resolve(
          new Response(
            url.pathname.endsWith(".wav")
              ? new Uint8Array(wav).buffer
              : new Uint8Array([1]).buffer,
          ),
        );
      }
      assert(["PUT", "DELETE"].includes(req.method));
      mediaEvents.push(req.method);
      return Promise.resolve(
        new Response(null, {
          status: storageFailure && req.method === "PUT" ? 403 : 200,
        }),
      );
    };
    for (const audio of [false, true]) {
      const label = audio ? "audio-spec" : "identify";
      const variant = audio ? "audio_compat" : "vision_compat";
      const operation = audio
        ? "scan_audio_identification"
        : "scan_identification";
      const factory = audio ? createAudioHandler : createIdentifyHandler;
      const validDraft = audio
        ? { ...draft, audio_subject_type: "no_confident_biological_source" }
        : draft;
      const newDatabase = (
        options: Omit<Parameters<typeof database>[0], "operation"> = {},
      ) => database({ operation, ...options });
      const run = (
        db: ReturnType<typeof database>,
        outcome: AIProviderOutcome | Error,
        staged = false,
        inspect: (input: AIRequest) => void = () => {},
      ) => {
        const adapter: AIAdapter = {
          provider: "test_only",
          prepare(input, snapshot) {
            assertEquals(input.variant, variant);
            assertEquals(snapshot.operation, operation);
            inspect(input);
            db.events.push("prepare");
            return () => {
              db.events.push("invoke");
              if (outcome instanceof Error) return Promise.reject(outcome);
              return Promise.resolve(outcome);
            };
          },
        };
        return factory((input, authority) =>
          createAIExecution(adapter, input, resolveAIClaim(input, authority))
        )(request(audio, staged), user, db.client);
      };
      const step = (name: string, fn: () => Promise<void>) =>
        t.step(`${label}: ${name}`, async () => {
          mediaEvents = [];
          storageFailure = unsafe = false;
          backgroundTasks.length = telemetry.length = 0;
          try {
            await fn();
          } finally {
            await Promise.all(backgroundTasks);
            Deno.env.delete("POSTHOG_API_KEY");
          }
        });
      await step(
        "stored completion avoids staged-media reads and preparation",
        async () => {
          const db = newDatabase({ replay: true });
          const result = await run(db, new Error("Must not invoke"), true);
          assertEquals(result.status, 200);
          assertEquals(
            result.headers.get("X-Merian-Idempotent-Replay"),
            "stored",
          );
          assertEquals(await result.json(), envelope);
          assertEquals(db.events, []);
          assertEquals(mediaEvents, []);
        },
      );
      await step("consent denial prevents preparation", async () => {
        const db = newDatabase({ consentDenied: true });
        await assertRejects(
          () => run(db, new Error("Must not invoke")),
          Error,
          "Confirm you are 18",
        );
        assertEquals(db.events, ["reserve"]);
        assertEquals(mediaEvents, []);
      });
      await step("setup failure refunds without preparation", async () => {
        const db = newDatabase({ setupFailed: true });
        await assertRejects(
          () => run(db, new Error("Must not invoke")),
          Error,
          "Observation persistence",
        );
        assertEquals(db.events, ["reserve", "ledger", "terminal", "refunded"]);
      });
      await step("binding failure refunds before commitment", async () => {
        const db = newDatabase();
        const result = await factory((input, authority) => {
          assert(authority.kind === "user_request");
          resolveAIClaim(input, {
            ...authority,
            operation: audio
              ? "scan_identification"
              : "scan_audio_identification",
          });
          throw new Error("unreachable");
        })(request(audio), user, db.client);
        assertEquals(result.status, 503);
        assertEquals(db.events, [
          "reserve",
          "ledger",
          "refunded",
          "failed_retryable",
        ]);
      });
      await step("failed commitment has no invocation", async () => {
        const db = newDatabase({ commitDenied: true });
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
          { ...facts, kind: "operational_failure" as const },
          {
            ...facts,
            kind: "invalid_output" as const,
            reason: "json" as const,
          },
          {
            ...facts,
            kind: "invalid_output" as const,
            reason: "finish" as const,
            finishReason: "MAX_TOKENS",
          },
          { ...facts, kind: "draft" as const, draft: { invalid: true } },
        ]
      ) {
        await step(
          `charged ${
            outcome instanceof Error ? "exception" : outcome.kind
          } remains retryable`,
          async () => {
            const db = newDatabase();
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
            assertEquals(mediaEvents, []);
          },
        );
      }
      for (const finishReason of ["SAFETY", "PROHIBITED_CONTENT"]) {
        await step(`${finishReason} keeps terminal response`, async () => {
          const db = newDatabase();
          const result = await run(db, {
            ...facts,
            kind: "refusal",
            finishReason,
          });
          assertEquals(result.status, 400);
          assertEquals((await result.json()).code, "observation_rejected");
          assertEquals(db.events, [
            "reserve",
            "ledger",
            "prepare",
            "committed",
            "invoke",
            "terminal",
          ]);
          assertEquals(mediaEvents, []);
        });
      }
      await step(
        "success promotes media, saves usage and replays without another call",
        async () => {
          Deno.env.set("POSTHOG_API_KEY", "synthetic-test-only");
          const db = newDatabase();
          const result = await run(
            db,
            {
              ...facts,
              providerDurationMs: 1234.5,
              kind: "draft",
              draft: validDraft,
              usage: {
                promptTokens: 100,
                candidateTokens: 20,
                totalTokens: 127,
                thinkingTokens: 7,
                cachedTokens: 5,
                modalityBreakdown: { prompt: { text: 100 } },
              },
            },
            false,
            (input) => {
              assert(
                input.task === "identify" &&
                  input.variant !== "description_compat",
              );
              assertEquals(
                input.evidence.map((item) => item.kind),
                audio ? ["text", "audio"] : ["text", "image", "text"],
              );
              assert(!JSON.stringify(input).includes("staging/"));
            },
          );
          assertEquals(result.status, 200);
          await Promise.all(backgroundTasks);
          assertEquals(telemetry.length, 1);
          assertEquals(
            telemetry[0].event,
            audio ? "AudioScanCompleted" : "ScanCompleted",
          );
          const properties = telemetry[0].properties as Record<string, unknown>;
          assertEquals(properties.ai_provider_duration_ms, 1234.5);
          assertEquals(properties.ai_provider, "gemini");
          assertEquals(
            properties.ai_prompt,
            audio ? "identify_audio_compat_v1" : "identify_vision_v1",
          );
          assertEquals(properties.ai_returned_model, null);
          const data = (await result.clone().json()).data;
          assertEquals(
            data.common_name,
            audio ? "No Wildlife Detected" : draft.common_name,
          );
          assert(!("audio_subject_type" in data));
          assertEquals(
            db.events.filter((event) => event === "invoke").length,
            1,
          );
          assertEquals(mediaEvents, ["PUT"]);
          const row = db.inserted()!;
          assertEquals([
            row.llm_prompt_tokens,
            row.llm_candidate_tokens,
            row.llm_total_tokens,
            row.llm_thinking_tokens,
            row.llm_cached_tokens,
          ], [100, 20, 127, 7, audio ? null : 5]);
          assertEquals(
            (row[
              audio ? "audio_storage_urls" : "image_storage_urls"
            ] as string[]).length,
            1,
          );
          assert(db.events.indexOf("complete") > db.events.indexOf("insert"));
          const intent = db.intent()!;
          assertEquals(intent.endpoint, "identify-multimodal");
          assertEquals(intent.compatibilityEndpoint, label);
          assert(!JSON.stringify(intent).includes(audioBase64));
          assertEquals(db.ledger()!.p_resumable, false);
          assertEquals(db.ledger()!.p_inline_media_redacted, true);
          const replay = await run(db, new Error("Must not invoke"), true);
          assertEquals(replay.status, 200);
          assertEquals(await replay.json(), await result.json());
          assertEquals(mediaEvents, ["PUT"]);
          assertEquals(
            db.events.filter((event) => event === "invoke").length,
            1,
          );
        },
      );
      await step(
        "staged source preserves the resumable main-route handoff",
        async () => {
          const db = newDatabase();
          const result = await run(
            db,
            { ...facts, kind: "unknown_execution" },
            true,
          );
          assertEquals(result.status, 503);
          assertEquals(mediaEvents, ["read"]);
          const intent = db.intent()!;
          assertEquals(intent.endpoint, "identify-multimodal");
          assertEquals(intent.compatibilityEndpoint, label);
          const media = intent.media as Record<string, unknown>;
          assertEquals(media[audio ? "audioR2ObjectKeys" : "r2ObjectKeys"], [
            `staging/${user.id}/synthetic.${audio ? "wav" : "webp"}`,
          ]);
          const ledger = db.ledger()!;
          assertEquals(ledger.p_resumable, true);
          assertEquals(ledger.p_inline_media_redacted, false);
          const replay = buildReplayIdentifyPayload({
            scan_id: scanId,
            user_id: user.id,
            endpoint: "identify-multimodal",
            status: "retrying",
            stage: "server_replay_claimed",
            attempt_count: 2,
            media_counts: ledger.p_media_counts as Record<string, unknown>,
            media_object_keys: ledger.p_media_object_keys as Record<
              string,
              unknown
            >,
            upload_session_ids: [],
            manifest_checksum: "a".repeat(64),
            request_payload: intent,
            payload_checksum: "b".repeat(64),
            replay_attempt_count: 1,
          });
          assertEquals(replay.user_id, user.id);
          assertEquals(replay.client_scan_id, scanId);
          assertEquals(replay[audio ? "audioR2ObjectKeys" : "r2ObjectKeys"], [
            `staging/${user.id}/synthetic.${audio ? "wav" : "webp"}`,
          ]);
          assertEquals(
            replay[audio ? "r2ObjectKeys" : "audioR2ObjectKeys"],
            [],
          );
          assertEquals(replay.videoR2ObjectKeys, []);
          assert(!JSON.stringify(replay).includes(audioBase64));
        },
      );
      await step(
        "unknown persistence retains promoted media and committed quota",
        async () => {
          const db = newDatabase({ unknownInsert: true });
          const result = await run(db, {
            ...facts,
            kind: "draft",
            draft: validDraft,
          });
          assertEquals(result.status, 503);
          assertEquals((await result.json()).code, "scan_persistence_failed");
          assertEquals(mediaEvents, ["PUT"]);
          assert(
            !db.events.includes("failed") && !db.events.includes("refunded"),
          );
          assert(db.events.includes("failed_retryable"));
        },
      );
      await step(
        "post-insert finalization failure preserves compatibility success",
        async () => {
          const db = newDatabase({ finalizationFailed: true });
          const result = await run(db, {
            ...facts,
            kind: "draft",
            draft: validDraft,
          });
          assertEquals(result.status, 200);
          assert(db.inserted());
          assert(db.events.includes("failed_retryable"));
          assert(
            !db.events.includes("failed") && !db.events.includes("refunded"),
          );
          assertEquals(mediaEvents, ["PUT"]);
        },
      );
      await step("failed promotion never reports durable success", async () => {
        const db = newDatabase();
        storageFailure = true;
        const result = await run(db, {
          ...facts,
          kind: "draft",
          draft: validDraft,
        });
        assertEquals(result.status, 503);
        assertEquals(db.inserted(), null);
        assert(db.events.includes("failed"));
        assert(!db.events.includes("complete"));
      });
      if (!audio) {
        await step(
          "mapped safety ratings still block unsafe media before saving",
          async () => {
            unsafe = true;
            const db = newDatabase();
            const result = await run(db, {
              ...facts,
              kind: "draft",
              draft: validDraft,
              safetyRatings: [{ probability: "MEDIUM" }],
            });
            assertEquals(result.status, 400);
            assertEquals((await result.json()).code, "observation_rejected");
            assertEquals(db.inserted(), null);
            assertEquals(mediaEvents, []);
            assert(db.events.includes("terminal"));
          },
        );
      }
    }
    await t.step(
      "description telemetry also uses native invocation duration",
      async () => {
        backgroundTasks.length = telemetry.length = 0;
        Deno.env.set("POSTHOG_API_KEY", "synthetic-test-only");
        const db = database({ operation: "scan_identification" });
        const adapter: AIAdapter = {
          provider: "test_only",
          prepare(input) {
            assertEquals(input.variant, "description_compat");
            return () =>
              Promise.resolve({
                ...facts,
                kind: "draft",
                providerDurationMs: 4321.5,
                draft: {
                  ...draft,
                  image_quality: {
                    sharpness: 0,
                    framing: 0,
                    diagnostic_utility: 0,
                    overall_score: 0,
                  },
                },
              });
          },
        };
        const req = new Request("https://example.invalid/identify-describe", {
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
        const result = await createDescribeHandler((input, authority) =>
          createAIExecution(adapter, input, resolveAIClaim(input, authority))
        )(req, user, db.client);
        assertEquals(result.status, 200);
        await Promise.all(backgroundTasks);
        assertEquals(telemetry.length, 1);
        assertEquals(telemetry[0].event, "ScanCompleted");
        const properties = telemetry[0].properties as Record<string, unknown>;
        assertEquals(properties.ai_provider_duration_ms, 4321.5);
        assertEquals(properties.ai_prompt, "identify_describe_v1");
      },
    );
  } finally {
    await Promise.all(backgroundTasks);
    globalThis.fetch = originalFetch;
    if (originalRuntime === undefined) delete runtime.EdgeRuntime;
    else runtime.EdgeRuntime = originalRuntime;
    console.log = log;
    console.error = error;
    console.warn = warn;
    for (const [name, value] of saved) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
});
