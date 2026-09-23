import { AUDIO_COMPARISON_ARMS, comparisonAudio } from "./comparison/audio.ts";
import {
  AUDIO_COMPARISON_CONFIG_ENV,
  AUDIO_COMPARISON_HEADER,
  audioComparisonScanId,
  resolveAudioComparison,
} from "./comparison/assignment.ts";
import { AUDIO_COMPARISON_PLAN_SHA256 } from "./comparison/plan.ts";
import { IDENTIFICATION_BUNDLE_SHA256 } from "./deploymentIdentity.ts";
import { prepareAudioComparisonPair } from "../../scripts/identification_evaluation/audioComparison.ts";
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
import { decodeBase64, encodeBase64 } from "../_shared/encoding.ts";
import { encodeWav16 } from "../audio-spec/wav.ts";
import { processMultimodalWAV } from "./audio.ts";
import { deriveAIRequestId } from "../_shared/aiQuota.ts";
import { parseIdentifySuccessEnvelope } from "../_shared/identify/contract.ts";
import type { CachedSpeciesRow } from "../_shared/identify/types.ts";

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
const cachedSpecies: CachedSpeciesRow = {
  id: "00000000-0000-4000-8000-000000000501",
  common_names: { en: "Synthetic Cached Name" },
  alternative_common_names: null,
  kingdom: "Animalia",
  phylum: "Arthropoda",
  class: "Insecta",
  order: "Lepidoptera",
  family: "Nymphalidae",
  genus: "Danaus",
  wikipedia_overview: null,
  hazard_type: "none",
  reference_image_url: null,
  wikipedia_url: null,
  iucn_red_list_status: "not_evaluated",
  habitat_description: null,
  gbif_taxon_key: null,
  group_tags: ["insect"],
};

function database(
  options: {
    replay?: boolean;
    comparisonScanId?: string;
    attemptCount?: number;
    flashFallback?: boolean;
    pro?: boolean;
    requestId?: string;
    commitDenied?: boolean;
    consentDenied?: boolean;
    setupFailed?: boolean;
    unknownInsert?: boolean;
    retired?: boolean;
    cachedSpecies?: CachedSpeciesRow;
  } = {},
) {
  const acceptedScanId = options.comparisonScanId ?? scanId;
  const reads: string[] = [];
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
          reads.push("recovery");
          return response({ outcome: "job_not_found" });
        case "ensure_scan_user_profile":
          return response(
            null,
            options.retired ? { message: "scan_user_identity_retired" } : null,
          );
        case "reserve_ai_quota":
          events.push("reserve");
          assertEquals(args.p_user_id, user.id);
          assertEquals(args.p_request_id, options.requestId ?? acceptedScanId);
          assertEquals(args.p_operation, "scan_identification");
          if (options.consentDenied) {
            return response(null, { message: "ai_consent_required" });
          }
          return response({
            reservation_id: "00000000-0000-4000-8000-000000000301",
            request_id: options.requestId ?? acceptedScanId,
            lease_token: "00000000-0000-4000-8000-000000000401",
            lease_expires_at: "2099-01-01T00:00:00Z",
            reservation_state: "reserved",
            is_replay: false,
            attempt_count: options.attemptCount ?? 1,
            model: options.pro ? "gemini-2.5-pro" : "gemini-2.5-flash",
            effective_plan: options.pro ? "pro_paid" : "free",
            effective_tier: options.pro ? "pro" : "free",
            subscription_tier: options.pro ? "pro" : "free",
            trial_active: false,
            entitlement_version: 1,
            policy_version: 1,
            daily_limit: 100,
            daily_remaining: 99,
            original_analysis_id: acceptedScanId,
            complimentary_client_scan_id: null,
            flash_fallback_used: options.flashFallback ?? false,
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
          return response({
            primary: options.cachedSpecies ?? null,
            candidate_common_names: {
              "Danaus gilippus": "Synthetic Candidate",
            },
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
            assertEquals(filters, {
              scan_id: acceptedScanId,
              user_id: user.id,
            });
            return response(
              options.replay || completed
                ? {
                  status: "complete",
                  response_envelope: completed ??
                    {
                      ...envelope,
                      data: { ...envelope.data, scan_id: acceptedScanId },
                    },
                }
                : null,
            );
          }
          if (table === "scans") {
            assertEquals(filters, { id: acceptedScanId, user_id: user.id });
            return response(inserted ? { id: acceptedScanId } : null);
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
  return { client, reads, events, updates, inserted: () => inserted };
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

function audioFixture(sampleRate = 16000, periodScale = 10): string {
  const samples = new Float32Array(sampleRate);
  for (let i = 0; i < samples.length; i++) {
    samples[i] = 0.2 * Math.sin(i / periodScale);
  }
  return encodeBase64(encodeWav16(samples, sampleRate));
}

Deno.test("comparison handler enforces binding, one attempt and fresh durable receipts", async (t) => {
  const names = [
    "AI_QUOTA_IP_HASH_SECRET",
    "POSTHOG_API_KEY",
    AUDIO_COMPARISON_CONFIG_ENV,
    "R2_ACCOUNT_ID",
    "R2_BUCKET_NAME",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
  ];
  const saved = names.map((name) => Deno.env.get(name));
  const originalFetch = globalThis.fetch;
  const log = console.log, error = console.error, warn = console.warn;
  try {
    Deno.env.set(names[0], "synthetic-test-only-hash-secret".repeat(2));
    Deno.env.delete(names[1]);
    Deno.env.delete(names[2]);
    names.slice(3).forEach((name) =>
      Deno.env.set(name, "synthetic-comparison")
    );
    globalThis.fetch = async (input, init) => {
      const req = input instanceof Request ? input : new Request(input, init);
      assertEquals(
        new URL(req.url).origin,
        "https://synthetic-comparison.r2.cloudflarestorage.com",
      );
      assert(["PUT", "DELETE"].includes(req.method));
      await req.arrayBuffer();
      return new Response("", { status: 200 });
    };
    console.log = console.error = console.warn = () => {};
    const source = audioFixture(44100);
    const pair = await prepareAudioComparisonPair(decodeBase64(source));
    const payloadFor = async (slot: number) => ({
      client_scan_id: await audioComparisonScanId(slot),
      observation_contexts: undefined,
      mimeType: "image/webp",
      deviceLocale: "en",
      deviceTimeZone: "UTC",
      currentMonth: 1,
      timeOfDay: "12:00 PM",
      audioBase64s: [source],
      audioMediaItems: [{ kind: "audio", sourceIndex: 0 }],
      ownerMediaTimeline: [{
        kind: "audio",
        sourceIndex: 0,
        audioInputIndex: 0,
      }],
      audio_comparison: { planSha256: AUDIO_COMPARISON_PLAN_SHA256, slot },
    });
    const resolver: typeof resolveAudioComparison = async (input) => {
      const bound = await resolveAudioComparison({
        ...input,
        now: Date.parse("2026-09-23T12:30:00.000Z"),
        configuration: JSON.stringify({
          version: 1,
          ownerId: user.id,
          startsAt: "2026-09-23T12:00:00.000Z",
          expiresAt: "2026-09-23T13:00:00.000Z",
          planSha256: AUDIO_COMPARISON_PLAN_SHA256,
          backendBundleSha256: IDENTIFICATION_BUNDLE_SHA256,
        }),
      });
      if (!bound) return null;
      // Private test composition replaces only frozen media hashes with synthetic
      // audio. Real HTTP callers cannot inject either composition function.
      const arm = pair.arms.find((a) => a.arm === bound.assignment.arm)!;
      return {
        ...bound,
        expiresAt: Date.now() + 60_000,
        assignment: {
          ...bound.assignment,
          sourceWavSha256: pair.sourceWavSha256,
          sourceByteLength: pair.sourceByteLength,
          ...arm,
        },
      };
    };
    const run = (
      db: ReturnType<typeof database>,
      payload: Record<string, unknown>,
      options: {
        resolve?: typeof resolveAudioComparison;
        replay?: number;
        outcome?: AIProviderOutcome | Error;
        inspect?: (input: AIRequest) => void;
      } = {},
    ) =>
      handleIdentifyMultimodalRequest(
        request(payload),
        user,
        db.client,
        0,
        options.replay,
        (input, authority) =>
          createAIExecution(
            {
              provider: "test_only",
              prepare() {
                db.events.push("prepare");
                options.inspect?.(input);
                return () => {
                  db.events.push("invoke");
                  if (options.outcome instanceof Error) {
                    return Promise.reject(options.outcome);
                  }
                  return Promise.resolve(
                    options.outcome ??
                      {
                        ...facts,
                        returnedModel: "gemini-2.5-pro",
                        providerCompletedAt: Date.now(),
                        kind: "draft",
                        draft: {
                          ...draft,
                          audio_subject_type: "no_confident_biological_source",
                        },
                      },
                  );
                };
              },
            },
            input,
            resolveAIClaim(input, authority),
          ),
        options.resolve ?? resolver,
      );

    await t.step(
      "disabled, lost markers and service recovery stop before recovery or quota",
      async () => {
        const payload = await payloadFor(1);
        for (
          const [body, replay] of [
            [payload, undefined],
            [{ ...payload, audio_comparison: undefined }, undefined],
            [{ ...payload, audio_comparison: undefined }, 1],
            [payload, 1],
          ] as const
        ) {
          const db = database();
          const response = await run(db, body, {
            resolve: resolveAudioComparison,
            replay,
          });
          assertEquals(response.status, 409);
          assertEquals(db.reads, []);
          assertEquals(db.events, []);
          assertEquals(response.headers.get(AUDIO_COMPARISON_HEADER), null);
        }
      },
    );
    await t.step(
      "body and exact source mismatches stop before reservation",
      async () => {
        const payload = await payloadFor(1);
        for (
          const body of [{ ...payload, currentMonth: 2 }, {
            ...payload,
            audioBase64s: [audioFixture(44100, 17)],
          }]
        ) {
          const db = database({
            comparisonScanId: payload.client_scan_id,
            pro: true,
          });
          assertEquals((await run(db, body)).status, 409);
          assertEquals(db.events, []);
        }
      },
    );
    for (
      const [name, options] of [
        ["reopened failed/refunded/expired slot", {
          pro: true,
          attemptCount: 2,
        }],
        ["later retry of an excluded slot", { pro: true, attemptCount: 3 }],
        ["Flash entitlement", { pro: false }],
        ["Flash fallback", { pro: false, flashFallback: true }],
      ] as const
    ) {
      await t.step(
        `${name} refunds before ingestion or provider preparation`,
        async () => {
          const payload = await payloadFor(1);
          const db = database({
            comparisonScanId: payload.client_scan_id,
            ...options,
          });
          assertEquals((await run(db, payload)).status, 409);
          assertEquals(db.events, ["reserve", "refunded"]);
        },
      );
    }
    await t.step(
      "request drift after preparation refunds before commitment",
      async () => {
        const payload = await payloadFor(1),
          db = database({
            pro: true,
            comparisonScanId: payload.client_scan_id,
          });
        const response = await run(db, payload, {
          resolve: async (input) => {
            const bound = await resolver(input);
            assert(bound);
            return {
              ...bound,
              assignment: {
                ...bound.assignment,
                providerRequestSha256: "0".repeat(64),
              },
            };
          },
        });
        assertEquals(response.status, 503);
        assertEquals(db.events, [
          "reserve",
          "ledger",
          "prepare",
          "refunded",
          "failed_retryable",
        ]);
        assertEquals(response.headers.get(AUDIO_COMPARISON_HEADER), null);
      },
    );
    for (const slot of [1, 2]) {
      await t.step(
        `slot ${slot} binds actual processed bytes and emits only a fresh durable receipt`,
        async () => {
          const payload = await payloadFor(slot),
            db = database({
              pro: true,
              comparisonScanId: payload.client_scan_id,
            });
          const response = await run(db, payload, {
            inspect: (input) => {
              assert(input.task === "identify");
              const audio = input.evidence.find((part) =>
                part.kind === "audio"
              );
              assert(audio?.kind === "audio");
              assertEquals(
                audio.data,
                encodeBase64(
                  comparisonAudio(
                    decodeBase64(source),
                    AUDIO_COMPARISON_ARMS[slot - 1],
                  ),
                ),
              );
            },
          });
          assertEquals(
            response.status,
            200,
            JSON.stringify(db.events),
          );
          assert(db.events.includes("complete"));
          const receipt = JSON.parse(
            response.headers.get(AUDIO_COMPARISON_HEADER)!,
          );
          assertEquals(receipt.slot, slot);
          assertEquals(receipt.sourceWavSha256, pair.sourceWavSha256);
          assertEquals(
            receipt.processedWavSha256,
            pair.arms[slot - 1].processedWavSha256,
          );
          assertEquals(
            receipt.providerRequestSha256,
            pair.arms[slot - 1].providerRequestSha256,
          );
          assertEquals(
            response.headers.get("X-Merian-Idempotent-Replay"),
            null,
          );
          const replay = await run(db, payload);
          assertEquals(replay.status, 200);
          assertEquals(
            replay.headers.get("X-Merian-Idempotent-Replay"),
            "stored",
          );
          assertEquals(replay.headers.get(AUDIO_COMPARISON_HEADER), null);
          assertEquals(
            db.events.filter((event) => event === "invoke").length,
            1,
          );
        },
      );
    }
    for (const failure of ["setup", "commit", "provider", "persistence"]) {
      await t.step(`${failure} failure has no fresh receipt`, async () => {
        const payload = await payloadFor(1);
        const db = database({
          pro: true,
          comparisonScanId: payload.client_scan_id,
          setupFailed: failure === "setup",
          commitDenied: failure === "commit",
          unknownInsert: failure === "persistence",
        });
        const response = await run(db, payload, {
          outcome: failure === "provider"
            ? new Error("Synthetic uncertain execution")
            : undefined,
        });
        assertEquals(response.status, 503);
        assertEquals(response.headers.get(AUDIO_COMPARISON_HEADER), null);
        assertEquals(response.headers.get("X-Merian-Identification"), null);
        assertEquals(
          db.events.includes("invoke"),
          ["provider", "persistence"].includes(failure),
        );
        assertEquals(db.events.includes("insert"), failure === "persistence");
        assertEquals(db.events.includes("complete"), false);
      });
    }
    await t.step(
      "same audio without marker and reserved ID follows the ordinary route",
      async () => {
        const db = database({ pro: true });
        const payload = {
          ...await payloadFor(1),
          client_scan_id: scanId,
          audio_comparison: undefined,
        };
        const response = await run(db, payload, {
          resolve: resolveAudioComparison,
        });
        assertEquals(
          response.status,
          200,
          JSON.stringify(db.events),
        );
        assertEquals(response.headers.get(AUDIO_COMPARISON_HEADER), null);
        assertEquals(db.events.filter((event) => event === "invoke").length, 1);
      },
    );
  } finally {
    names.forEach((name, i) =>
      saved[i] == null ? Deno.env.delete(name) : Deno.env.set(name, saved[i]!)
    );
    globalThis.fetch = originalFetch;
    console.log = log;
    console.error = error;
    console.warn = warn;
  }
});

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
        assertEquals(result.headers.get("X-Merian-Identification"), null);
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
          const response = await run(db, outcome);
          assertEquals(response.status, 503);
          assertEquals(response.headers.get("X-Merian-Identification"), null);
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
    const audio = audioFixture(44100);
    const secondAudio = audioFixture(44100, 17);
    const expectedAudios = new Map(
      [audio, secondAudio].map((source) => [
        source,
        processMultimodalWAV(
          decodeBase64(source).buffer as ArrayBuffer,
          undefined,
          { present: false, error: null, timeline: null },
        ),
      ]),
    );
    const mediaCases = [
      {
        label: "still",
        imageBase64s: ["AQ=="],
        audioBase64s: [],
        hasVideo: false,
      },
      {
        label: "audio",
        imageBase64s: [],
        audioBase64s: [audio],
        hasVideo: false,
      },
      {
        label: "two distinguishable audio clips",
        imageBase64s: [],
        audioBase64s: [audio, secondAudio],
        hasVideo: false,
      },
      {
        label: "five video snapshots",
        imageBase64s: ["AQ==", "Ag==", "Aw==", "BA==", "BQ=="],
        audioBase64s: [],
        hasVideo: true,
      },
      {
        label: "partial snapshots and companion",
        imageBase64s: ["AQ==", "Ag=="],
        audioBase64s: [audio],
        hasVideo: true,
      },
    ];
    for (const media of mediaCases) {
      await t.step(
        `${media.label} reaches the adapter once with ordered processed evidence`,
        async () => {
          const db = database({ pro: true });
          const isVideo = media.hasVideo;
          const result = await run(
            db,
            { ...facts, kind: "unknown_execution" },
            {
              imageBase64s: media.imageBase64s,
              audioBase64s: media.audioBase64s,
              ...(media.imageBase64s.length === 0
                ? { observation_contexts: [] }
                : {}),
              visualMediaItems: media.imageBase64s.map((_, i) =>
                isVideo
                  ? { kind: "video_frame", clipIndex: 0, frameIndex: i }
                  : { kind: "image", sourceIndex: i }
              ),
              audioMediaItems: media.audioBase64s.map((_, index) =>
                isVideo
                  ? { kind: "video_audio", clipIndex: 0 }
                  : { kind: "audio", sourceIndex: index }
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
              if (media.imageBase64s.length === 0) {
                assert(
                  !input.evidence.some((part) =>
                    part.kind === "text" &&
                    part.source === "observation_context"
                  ),
                );
              }
              assertEquals(images.map((part) => part.data), media.imageBase64s);
              assertEquals(sounds.length, media.audioBase64s.length);
              assertEquals(
                sounds.map((part) => part.data),
                media.audioBase64s.map((source) => expectedAudios.get(source)),
              );
              assertEquals(
                sounds.map((part) => part.inputIndex),
                media.audioBase64s.map((_, index) => index),
              );
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
      "audio expansion budget fails before provider admission with a size error",
      async () => {
        const db = database();
        const oversized = encodeBase64(encodeWav16(new Float32Array(1_000), 1));
        const result = await run(db, new Error("Must not invoke"), {
          imageBase64s: ["AQ=="],
          audioBase64s: [oversized],
        });
        assertEquals(result.status, 413);
        assertEquals((await result.json()).code, "payload_too_large");
        assertEquals(db.events, []);
      },
    );
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
        const diagnostics = JSON.parse(
          result.headers.get("X-Merian-Identification")!,
        );
        assertEquals(diagnostics.requestedModel, "gemini-2.5-flash");
        assertEquals(diagnostics.returnedModel, null);
        assertEquals(diagnostics.usage, {
          promptTokens: 100,
          candidateTokens: 20,
          totalTokens: 127,
          thinkingTokens: 7,
          cachedTokens: 5,
          toolTokens: null,
        });
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
    for (const pro of [false, true]) {
      for (const confidence_score of [0.98, 0.99]) {
        await t.step(
          `normalized ${
            pro ? "Pro" : "Flash"
          } result survives hydration at ${confidence_score}`,
          async () => {
            const db = database({ pro, cachedSpecies });
            const value = {
              ...draft,
              is_biological_subject: true,
              is_live_capture: true,
              scientific_name: "cf. danaus Plexippus L.",
              common_name: "Monarch",
              ai_reasoning: "Synthetic wing pattern.",
              confidence_score,
              candidates: [{
                scientific_name: "cf. Danaus gilippus",
                confidence_score: 0.6,
                distinguishing_feature: "Synthetic alternative pattern.",
              }],
            };
            const result = await run(db, {
              ...facts,
              kind: "draft",
              draft: value,
            });
            assertEquals(result.status, 200);
            const response = parseIdentifySuccessEnvelope(await result.json());
            assertEquals(response.data.scientific_name, "Danaus plexippus");
            assertEquals(response.data.common_name, "Synthetic Cached Name");
            assertEquals(response.data.inference_tier, pro ? "pro" : "flash");
            assertEquals(response.data.life_stage, "unknown");
            assertEquals(response.data.is_invasive, false);
            assertEquals(response.data.invasive_status_region, "Unavailable");
            assertEquals(response.data.taxonomy?.genus, "Danaus");
            assertEquals(
              response.data.candidates,
              confidence_score >= 0.99 ? null : [{
                scientific_name: "Danaus gilippus",
                confidence_score: 0.6,
                distinguishing_feature: "Synthetic alternative pattern.",
                common_name: "Synthetic Candidate",
              }],
            );
            assertEquals(db.inserted()?.ai_confidence_score, confidence_score);
            assertEquals(db.inserted()?.species_id, cachedSpecies.id);
            assertEquals(
              db.events.filter((event) => event === "invoke").length,
              1,
            );
            assert(db.events.indexOf("complete") > db.events.indexOf("insert"));
            assert(
              !db.events.includes("failed") && !db.events.includes("refunded"),
            );
          },
        );
      }
    }
    await t.step(
      "hydrated wire validation still fails before persistence",
      async () => {
        const db = database({
          cachedSpecies: {
            ...cachedSpecies,
            reference_image_url: "",
          },
        });
        const result = await run(db, {
          ...facts,
          kind: "draft",
          draft: {
            ...draft,
            is_biological_subject: true,
            scientific_name: "Danaus plexippus",
            common_name: "Monarch",
            ai_reasoning: "Synthetic wing pattern.",
          },
        });
        assertEquals(result.status, 502);
        assertEquals((await result.json()).code, "identify_response_invalid");
        assertEquals(db.inserted(), null);
        assert(db.events.includes("failed"));
        assert(!db.events.includes("complete"));
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
