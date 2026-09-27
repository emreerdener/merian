import { assert, assertEquals } from "@std/assert";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { createAudioHandler } from "../../audio-spec/index.ts";
import { encodeWav16 } from "../../audio-spec/wav.ts";
import { createDescribeHandler } from "../../identify-describe/index.ts";
import { handleIdentifyMultimodalRequest } from "../../identify-multimodal/index.ts";
import { createIdentifyHandler } from "../../identify/index.ts";
import { openAIPhotoSnapshot } from "../ai/openaiPhoto.ts";
import { identificationProvenance } from "../ai/provenance.ts";
import { openAITextFixture } from "../ai/testing/openaiFixtures.ts";
import { encodeBase64 } from "../encoding.ts";
import {
  buildCompletedIdentifyEnvelope,
  type CompletedScanResponseRow,
} from "./completedResponse.ts";
import {
  completedIdentifyResponse,
  identifyResultResponse,
} from "./resultResponse.ts";

const scanId = "00000000-0000-4000-8000-000000000101";
const user: User = {
  id: "00000000-0000-4000-8000-000000000201",
  app_metadata: {},
  user_metadata: {},
  aud: "authenticated",
  created_at: "2026-09-21T00:00:00Z",
};
const provenance = identificationProvenance(openAIPhotoSnapshot({
  ...openAITextFixture(),
  evidence: [{
    kind: "image",
    order: 0,
    inputIndex: 0,
    lineage: { kind: "image", sourceIndex: 0 },
    mimeType: "image/png",
    data: "AQID",
  }],
}, 2));
const scan: CompletedScanResponseRow = {
  id: scanId,
  user_id: user.id,
  species_id: null,
  device_locale: null,
  ai_confidence_score: 0.94,
  is_biological_subject: false,
  is_live_capture: false,
  blur_score: 0,
  ecology_type: null,
  is_invasive: null,
  invasive_status_region: null,
  invasive_rationale: null,
  invasive_confidence: null,
  colors: [],
  estimated_size_cm: null,
  life_stage: null,
  reproductive_condition: null,
  sex: null,
  sex_confidence: null,
  sex_evidence: null,
  individual_count: null,
  ecological_interactions: null,
  ai_reasoning: "Synthetic smooth manufactured object.",
  extracted_visual_traits: ["synthetic smooth surface"],
  inference_tier: "flash",
  identification_provenance: provenance,
  candidates: [],
  image_quality_score: 100,
  pet_identification: null,
};
const envelope = buildCompletedIdentifyEnvelope(scan, null);
const prepare = () => {
  throw new Error("Replay must not prepare a provider call");
};
const samples = Float32Array.from(
  { length: 16000 },
  (_, i) => 0.2 * Math.sin(i / 10),
);
const audioBase64 = encodeBase64(encodeWav16(samples, 16000));
const handlers = {
  "identify": createIdentifyHandler(prepare),
  "identify-describe": createDescribeHandler(prepare),
  "audio-spec": createAudioHandler(prepare),
  "identify-multimodal": (req: Request, owner: User, db: SupabaseClient) =>
    handleIdentifyMultimodalRequest(req, owner, db, 0, undefined, prepare),
};

function request(endpoint: string, protocol: string | null): Request {
  const headers = new Headers({
    "Content-Type": "application/json",
    "X-Merian-Entitlement-Protocol": "3",
    // Spoofed worker headers must never grant a decoder exemption.
    "X-Merian-Internal-Replay": "true",
    "X-Merian-Replay-User-Id": user.id,
    "X-Merian-Replay-Attempt": "1",
  });
  if (protocol !== null) {
    headers.set("X-Merian-Identification-Protocol", protocol);
    headers.set("X-Merian-Identification-Recipient", "google_gemini");
  }
  return new Request(`https://example.invalid/${endpoint}`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      user_id: user.id,
      client_scan_id: scanId,
      geoprivacy: "private",
      description: "Synthetic manufactured object with a smooth surface.",
      imageBase64s: ["AQID"],
      r2ObjectKeys: [],
      audio_base64: audioBase64,
    }),
  });
}

type Stage = "initial" | "quota" | "ingestion";
type Source = "stored" | "reconstructed";
function database(stage: Stage, source: Source) {
  const events: string[] = [];
  let complete = stage === "initial";
  const response = (data: unknown) => {
    const promise = Promise.resolve({ data, error: null });
    return Object.assign(promise, { abortSignal: () => promise });
  };
  const client = {
    rpc(name: string, args: Record<string, unknown> = {}) {
      events.push(name);
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
        case "reserve_identification_quota":
          assert(stage !== "initial");
          complete = stage === "quota";
          return response({
            provider: "gemini",
            binding: "gemini_baseline_v1",
            processor_permission: "google_gemini",
            input_profile: args.p_input_profile,
            reservation_id: "00000000-0000-4000-8000-000000000301",
            request_id: scanId,
            lease_token: "00000000-0000-4000-8000-000000000401",
            lease_expires_at: "2099-01-01T00:00:00Z",
            reservation_state: complete ? "committed" : "reserved",
            is_replay: complete,
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
          assertEquals(stage, "ingestion");
          complete = true;
          return response({
            upload_session_ids: [],
            manifest_checksum: "a".repeat(64),
            payload_checksum: "b".repeat(64),
            stage: "complete",
            already_complete: true,
          });
        case "finalize_ai_quota_reservation":
          assertEquals(args.p_final_state, "refunded");
          return response(true);
        default:
          throw new Error(`Unexpected RPC: ${name}`);
      }
    },
    from(table: string) {
      const filters: Record<string, unknown> = {};
      const query = {
        select: () => query,
        abortSignal: () => query,
        eq: (key: string, value: unknown) => {
          filters[key] = value;
          return query;
        },
        maybeSingle: () => {
          if (table === "users") {
            return response({ default_geoprivacy: "private" });
          }
          assertEquals(
            filters,
            table === "scans"
              ? { id: scanId, user_id: user.id }
              : { scan_id: scanId, user_id: user.id },
          );
          if (table === "scan_ingestion_jobs") {
            return response(
              complete
                ? {
                  status: "complete",
                  response_envelope: source === "stored" ? envelope : null,
                }
                : null,
            );
          }
          if (table === "scans") {
            assert(complete);
            return response(scan);
          }
          throw new Error(`Unexpected table: ${table}`);
        },
      };
      return query;
    },
  } as unknown as SupabaseClient;
  return { client, events };
}

Deno.test("all identification handlers gate current readers at every completed replay branch", async (t) => {
  const original = Deno.env.get("AI_QUOTA_IP_HASH_SECRET");
  const log = console.log, error = console.error;
  try {
    Deno.env.set(
      "AI_QUOTA_IP_HASH_SECRET",
      "synthetic-reader-test-only".repeat(2),
    );
    console.log = console.error = () => {};
    for (const [endpoint, handler] of Object.entries(handlers)) {
      for (const stage of ["initial", "quota", "ingestion"] as const) {
        for (const source of ["stored", "reconstructed"] as const) {
          for (
            const protocol of stage === "initial"
              ? [null, "3", "4"]
              : [null, "4"]
          ) {
            await t.step(
              `${endpoint}/${stage}/${source}/${protocol ?? "missing"}`,
              async () => {
                const db = database(stage, source);
                const result = await handler(
                  request(endpoint, protocol),
                  user,
                  db.client,
                );
                if (protocol === "4") {
                  assertEquals(result.status, 200);
                  assertEquals(
                    result.headers.get("X-Merian-Idempotent-Replay"),
                    source,
                  );
                  assertEquals(await result.json(), envelope);
                } else {
                  assertEquals(result.status, 426);
                  const body = await result.json();
                  assertEquals(body.code, "client_update_required");
                  assert(!("data" in body));
                  assertEquals(
                    result.headers.get("X-Merian-Idempotent-Replay"),
                    null,
                  );
                }
                if (stage === "initial") {
                  assert(!db.events.includes("reserve_identification_quota"));
                } else {
                  assert(db.events.includes("reserve_identification_quota"));
                  assertEquals(
                    db.events.includes("begin_scan_ingestion"),
                    stage === "ingestion",
                  );
                }
              },
            );
          }
        }
      }
    }
  } finally {
    if (original === undefined) Deno.env.delete("AI_QUOTA_IP_HASH_SECRET");
    else Deno.env.set("AI_QUOTA_IP_HASH_SECRET", original);
    console.log = log;
    console.error = error;
  }
});

Deno.test("result emission preserves legacy reads and requires exact V2 reader support", async () => {
  const legacy = buildCompletedIdentifyEnvelope({
    ...scan,
    identification_provenance: null,
  }, null);
  const req = request("identify-multimodal", null);
  assertEquals(await identifyResultResponse(req, legacy).json(), legacy);
  const v1 = buildCompletedIdentifyEnvelope({
    ...scan,
    identification_provenance: {
      ...provenance,
      version: 1,
      provider: "gemini",
      generation: {
        temperature: 0.1,
        seed: null,
        top_k: null,
        max_output_tokens: 8192,
        thinking_budget: null,
      },
    },
  }, null);
  assertEquals(await identifyResultResponse(req, v1).json(), v1);
  for (const source of ["stored", "reconstructed"] as const) {
    for (const protocol of [null, "3", "04", "4.0", "5", "4, 4"]) {
      assertEquals(
        completedIdentifyResponse(request("identify", protocol), {
          envelope,
          source,
        }).status,
        426,
      );
    }
    // This argument is supplied only after internal service authentication; headers alone fail above.
    assertEquals(
      await completedIdentifyResponse(req, { envelope, source }, true).json(),
      envelope,
    );
  }
  assertEquals(identifyResultResponse(req, envelope).status, 426);
  assertEquals(
    await identifyResultResponse(req, envelope, {}, true).json(),
    envelope,
  );
  assertEquals(
    await identifyResultResponse(request("identify", "4"), envelope).json(),
    envelope,
  );
});
