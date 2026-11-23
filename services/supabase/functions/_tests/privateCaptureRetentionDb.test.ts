import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { handleIdentifyMultimodalRequest } from "../identify-multimodal/index.ts";
import type { User } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createAIExecution } from "../_shared/ai/execution.ts";
import { resolveAIClaim } from "../_shared/ai/registry.ts";
import { encodeWav16 } from "../audio-spec/wav.ts";
import { evidenceDigest } from "../_shared/analysisHistory/evidence.ts";
import {
  initialCapturePlanValue,
  parseInitialEvidenceCapturePlan,
} from "../_shared/analysisHistory/initialEvidenceCapturePlan.ts";
import {
  initialCaptureClientRepository,
  uploadInitialCaptureClientArtifact,
} from "../_shared/analysisHistory/initialCaptureClientStaging.ts";
import {
  initialCaptureAudioStageRepository,
  initialCaptureAudioStageStorage,
} from "../_shared/analysisHistory/initialCaptureAudioStageRepository.ts";
import { initialCaptureAudioStageRequest } from "../_shared/analysisHistory/initialCaptureAudioStaging.ts";
import { preparePrivateCaptureStage } from "../_shared/analysisHistory/privateCaptureStagePreparation.ts";
import { buildPrivateCaptureIntent } from "../_shared/analysisHistory/privateCaptureIntent.ts";
import {
  preparePrivateCaptureSubmission,
  type PrivateCaptureSubmissionDependencies,
  privateCaptureSubmissionDependencies,
} from "../_shared/analysisHistory/privateCaptureSubmission.ts";
import { initialEvidenceCompletionVerifier } from "../_shared/identify/initialEvidenceEnvelopeV1.ts";
import { finalizeInitialEvidence } from "../_shared/analysisHistory/initialEvidenceFinalization.ts";
import {
  continuePrivateCaptureFinalizations,
  privateFinalizationDependencies,
} from "../replay-scan-ingestion/privateFinalization.ts";
import { recoverAcceptedInitialResult } from "../_shared/analysisHistory/initialEvidenceRecovery.ts";
import page from "../_shared/analysisHistory/fixtures/page-v8.json" with {
  type: "json",
};
import {
  beginScanIngestion,
  completeScanIngestionFinalization,
} from "../_shared/scanIngestionJobs.ts";
import { materializeInitialEvidence } from "../_shared/analysisHistory/initialEvidenceMaterialization.ts";
import { decodeBase64 } from "../_shared/encoding.ts";
import { initialEvidenceRepository } from "../_shared/analysisHistory/initialEvidenceRepository.ts";
import { retainInitialEvidenceFromSource } from "../_shared/analysisHistory/initialEvidenceRetention.ts";
import type { PrivateCaptureStageObjectStorage } from "../_shared/analysisHistory/evidenceStorage.ts";

const url = Deno.env.get("SUPABASE_DB_TEST_URL");

// Exercise the production service adapters against the disposable SQL routines.
// Only HTTP transport is replaced; expected errors roll back their statement.
function sqlClient(db: Client) {
  const calls: string[] = [];
  const failures: string[] = [];
  const provider = {
    enabled: false,
    failNextProfile: false,
    scanID: "",
    requestID: "",
    inputProfile: "",
  };
  const reply = (data: unknown, error: unknown = null) => {
    const value = Promise.resolve({ data, error });
    return Object.assign(value, { abortSignal: () => value });
  };
  const routines: Record<string, readonly string[]> = {
    claim_private_capture_finalizations: ["p_limit"],
    ensure_scan_user_profile: ["p_user_id"],
    recover_owned_initial_completion: ["p_owner", "p_scan"],
    recover_private_capture_completion: ["p_owner", "p_plan"],
    initial_capture_client_stage_action: [
      "p_request",
      "p_sha256",
      "p_backend",
      "p_action",
      "p_media",
    ],
    initial_capture_audio_stage_action: [
      "p_request",
      "p_sha256",
      "p_backend",
      "p_action",
      "p_attempt",
      "p_artifacts",
      "p_object",
    ],
    claim_initial_capture_stage_preparation: [
      "p_request",
      "p_sha256",
      "p_backend",
      "p_attempt",
    ],
    begin_scan_ingestion: [
      "p_scan_id",
      "p_user_id",
      "p_endpoint",
      "p_request_payload",
      "p_media_counts",
      "p_media_object_keys",
      "p_storage_keys",
      "p_manifest_checksum",
      "p_payload_checksum",
      "p_resumable",
      "p_inline_media_redacted",
      "p_redacted_media_counts",
      "p_payload_schema_version",
      "p_lease_seconds",
    ],
    bind_owned_initial_result: [
      "p_owner",
      "p_request",
      "p_result",
      "p_species",
    ],
    recover_owned_initial_result: ["p_owner", "p_request"],
    complete_scan_ingestion_with_entitlement: [
      "p_scan_id",
      "p_user_id",
      "p_response_envelope",
      "p_promoted_urls_by_storage_key",
      "p_deleted_storage_keys",
    ],
    reserve_owned_initial_evidence: ["p_owner", "p_request"],
    complete_owned_initial_evidence: ["p_owner", "p_request", "p_object"],
  };
  const client = {
    from(table: string) {
      calls.push(`table:${table}`);
      assert(
        [
          "scan_ingestion_intents",
          "scan_ingestion_jobs",
          "scans",
          "users",
          "failed_scan_ingestions",
        ]
          .includes(table),
      );
      const filters: [string, unknown][] = [];
      let row: Record<string, unknown> | undefined;
      let update = false;
      let excludedTerminal = false;
      let signal = new AbortController().signal;
      const execute = async () => {
        signal.throwIfAborted();
        await db.queryArray("SAVEPOINT adapter_table");
        try {
          if (row) {
            const keys = Object.keys(row).filter((key) =>
              row![key] !== undefined
            );
            assert(keys.every((key) => /^[a-z_]+$/.test(key)));
            const columns = keys.map((key) => '"' + key + '"').join(",");
            if (update) {
              assertEquals(table, "scan_ingestion_jobs");
              assertEquals(filters.map(([key]) => key), ["scan_id", "user_id"]);
              assert(excludedTerminal);
              await db.queryArray(
                `UPDATE public.scan_ingestion_jobs SET (${columns})=(SELECT ${columns} FROM jsonb_populate_record(NULL::public.scan_ingestion_jobs,$1::jsonb)) WHERE scan_id=$2 AND user_id=$3 AND status NOT IN ('complete','failed_terminal')`,
                [JSON.stringify(row), ...filters.map(([, value]) => value)],
              );
            } else {
              assert(["scans", "failed_scan_ingestions"].includes(table));
              await db.queryArray(
                `INSERT INTO public.${table}(${columns}) SELECT ${columns} FROM jsonb_populate_record(NULL::public.${table},$1::jsonb) ${
                  table === "scans" ? "ON CONFLICT(id) DO NOTHING" : ""
                }`,
                [JSON.stringify(row)],
              );
            }
            await db.queryArray("RELEASE SAVEPOINT adapter_table");
            return { data: null, error: null };
          }
          assert(filters.length > 0);
          const where = filters.map(([key], n) => {
            assert(["id", "scan_id", "user_id"].includes(key));
            return `"${key}"=$${n + 1}`;
          }).join(" AND ");
          const result = await db.queryObject<{ value: unknown }>(
            `SELECT to_jsonb(t) value FROM public.${table} t WHERE ${where}`,
            filters.map(([, value]) => value),
          );
          assert(result.rows.length <= 1);
          await db.queryArray("RELEASE SAVEPOINT adapter_table");
          return { data: result.rows[0]?.value ?? null, error: null };
        } catch (error) {
          failures.push((error as Error).message);
          await db.queryArray(
            "ROLLBACK TO SAVEPOINT adapter_table; RELEASE SAVEPOINT adapter_table",
          );
          return { data: null, error: { message: (error as Error).message } };
        }
      };
      const builder = {
        select: (_columns: string) => builder,
        eq: (key: string, value: unknown) => {
          filters.push([key, value]);
          return builder;
        },
        abortSignal: (current: AbortSignal) => {
          signal = current;
          return builder;
        },
        maybeSingle: execute,
        update: (value: Record<string, unknown>) => {
          row = value;
          update = true;
          return builder;
        },
        not: (key: string, operator: string, value: string) => {
          assertEquals([key, operator, value], [
            "status",
            "in",
            "(complete,failed_terminal)",
          ]);
          excludedTerminal = true;
          return builder;
        },
        insert: (value: Record<string, unknown>) => {
          assertEquals(table, "failed_scan_ingestions");
          row = value;
          return builder;
        },
        upsert: (value: Record<string, unknown>, options: unknown) => {
          assertEquals(options, { onConflict: "id", ignoreDuplicates: true });
          row = value;
          return builder;
        },
        then: (
          resolve: (value: Awaited<ReturnType<typeof execute>>) => unknown,
          reject: (error: unknown) => unknown,
        ) => execute().then(resolve, reject),
      };
      return builder;
    },
    rpc(name: string, args: Record<string, unknown>) {
      if (provider.enabled) {
        if (name === "ensure_scan_user_profile" && provider.failNextProfile) {
          provider.failNextProfile = false;
          return reply(null, {
            message: "Synthetic profile interruption before result binding",
          });
        }
        if (name === "reserve_identification_quota") {
          calls.push("quota:reserve");
          provider.scanID = String(args.p_original_analysis_id);
          provider.requestID = String(args.p_request_id);
          provider.inputProfile = String(args.p_input_profile);
          return reply({
            provider: "gemini",
            binding: "gemini_baseline_v1",
            processor_permission: "google_gemini",
            input_profile: args.p_input_profile,
            reservation_id: "00000000-0000-4000-8000-000000000301",
            request_id: args.p_request_id,
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
            original_analysis_id: args.p_original_analysis_id,
            complimentary_client_scan_id: null,
            flash_fallback_used: false,
            scans_remaining: 0,
            scans_available_to_start: 0,
            in_flight_count: 0,
          });
        }
        if (name === "commit_identification_invocation") {
          calls.push("quota:commit");
          // Seed only the external quota assignment; the actual transactional
          // commit, permanent receipt, funding transition and denial are SQL.
          const execute = async () => {
            await db.queryArray("SAVEPOINT dispatch_commit");
            try {
              await db.queryArray(
                "INSERT INTO internal.ai_quota_reservations(id,user_id,operation,request_id,lease_token,model,effective_plan,effective_tier,subscription_tier,trial_active,entitlement_version,policy_version,original_analysis_id) VALUES($1,$2,'scan_identification',$3,$4,'gemini-2.5-flash','free','free','free',FALSE,1,1,$5) ON CONFLICT(id) DO NOTHING",
                [
                  args.p_reservation_id,
                  args.p_user_id,
                  provider.requestID,
                  args.p_lease_token,
                  provider.scanID,
                ],
              );
              await db.queryArray(
                "INSERT INTO internal.identification_provider_attempts(reservation_id,attempt_count,operation,effective_plan,model,policy_version,provider,binding,processor_permission,input_profile,minimum_identification_protocol,accepted_identification_protocol) VALUES($1,1,'scan_identification','free','gemini-2.5-flash',1,'gemini','gemini_baseline_v1','google_gemini',$2,0,7) ON CONFLICT(reservation_id,attempt_count) DO NOTHING",
                [args.p_reservation_id, provider.inputProfile],
              );
              const data = (await db.queryObject(
                "SELECT * FROM public.commit_identification_invocation($1,$2,$3,$4,$5::jsonb)",
                [
                  args.p_reservation_id,
                  args.p_user_id,
                  args.p_lease_token,
                  args.p_attempt_count,
                  JSON.stringify(args.p_provenance),
                ],
              )).rows;
              await db.queryArray("RELEASE SAVEPOINT dispatch_commit");
              return { data, error: null };
            } catch (error) {
              failures.push((error as Error).message);
              await db.queryArray(
                "ROLLBACK TO SAVEPOINT dispatch_commit; RELEASE SAVEPOINT dispatch_commit",
              );
              return {
                data: null,
                error: { message: (error as Error).message },
              };
            }
          };
          return { abortSignal: execute };
        }
        if (name === "complete_identification_invocation") {
          calls.push("quota:account");
          return reply("00000000-0000-4000-8000-000000000601");
        }
        if (name === "finalize_ai_quota_reservation") {
          calls.push(`quota:${args.p_final_state}`);
          const execute = async () => {
            await db.queryArray("SAVEPOINT quota_settlement");
            try {
              const data = (await db.queryObject<{ value: boolean }>(
                "SELECT public.finalize_ai_quota_reservation($1,$2,$3,$4) value",
                [
                  args.p_reservation_id,
                  args.p_user_id,
                  args.p_lease_token,
                  args.p_final_state,
                ],
              )).rows[0].value;
              await db.queryArray("RELEASE SAVEPOINT quota_settlement");
              return { data, error: null };
            } catch (error) {
              await db.queryArray(
                "ROLLBACK TO SAVEPOINT quota_settlement; RELEASE SAVEPOINT quota_settlement",
              );
              return {
                data: null,
                error: { message: (error as Error).message },
              };
            }
          };
          return { abortSignal: execute };
        }
      }
      assert(Object.hasOwn(routines, name));
      const execute = async (signal: AbortSignal) => {
        signal.throwIfAborted();
        calls.push(`${name}:${args.p_action ?? ""}`);
        await db.queryArray("SAVEPOINT adapter_call");
        try {
          const values = routines[name].map((key) => {
            const value = args[key];
            return !["p_storage_keys", "p_deleted_storage_keys"].includes(
                key,
              ) &&
                value &&
                typeof value === "object"
              ? JSON.stringify(value)
              : value;
          });
          const data = (await db.queryObject<{ value: unknown }>(
            `SELECT public.${name}(${
              values.map((_, n) => `$${n + 1}`).join(",")
            }) value`,
            values,
          )).rows[0].value;
          await db.queryArray("RELEASE SAVEPOINT adapter_call");
          return { data, error: null };
        } catch (error) {
          failures.push((error as Error).message);
          await db.queryArray(
            "ROLLBACK TO SAVEPOINT adapter_call; RELEASE SAVEPOINT adapter_call",
          );
          return { data: null, error: { message: (error as Error).message } };
        }
      };
      return {
        abortSignal: execute,
        then(
          resolve: (value: Awaited<ReturnType<typeof execute>>) => unknown,
          reject: (error: unknown) => unknown,
        ) {
          return execute(new AbortController().signal).then(resolve, reject);
        },
      };
    },
  } as unknown as SupabaseClient;
  return { client, calls, failures, provider };
}

Deno.test({
  name:
    "private whole observation uploads actual bytes, prepares audio once and adopts exact retained evidence",
  ignore: !url,
  async fn(t) {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    for (
      const shape of [
        "two_photos",
        "two_audio",
        "photo_audio",
        "video_audio",
      ] as const
    ) {
      await t.step(shape, async () => {
        const db = new Client(url);
        await db.connect();
        const owner = crypto.randomUUID(),
          scan = crypto.randomUUID(),
          generation = crypto.randomUUID();
        const originals = new Map<string, Uint8Array>();
        async function artifact(
          type: string,
          bytes: Uint8Array = new Uint8Array([1, 2, 3, 4]),
        ) {
          const media_id = crypto.randomUUID();
          originals.set(media_id, bytes.slice());
          return {
            media_id,
            content_type: type,
            byte_count: bytes.length,
            sha256: await evidenceDigest(bytes),
          };
        }
        const samples = Float32Array.from(
          { length: 44_100 },
          (_, n) => .2 * Math.sin(n * .15),
        );
        const wav = encodeWav16(samples, 44_100);
        const selection = {
          x: .1,
          y: .2,
          width: .5,
          height: .6,
          source: "user_selection",
        };
        const photo = async () => ({
          kind: "image",
          source: await artifact("image/heif"),
          prepared: await artifact("image/jpeg"),
          coordinate_basis: "prepared_image_top_left_v1",
          focus_region: selection,
          preparation: {
            schema_version: 1,
            coordinate_basis: "upright_source_top_left_v1",
            format: "nativeSelectedStillImageV2",
            crop_display_size: 390,
            quarter_turns: 0,
            scale: 1,
            offset_x: 0,
            offset_y: 0,
            camera_vertical_center: null,
            source_selection: selection,
          },
        });
        const audio = async () => ({
          kind: "audio",
          source: await artifact("audio/wav", wav),
          prepared_media_id: crypto.randomUUID(),
        });
        const video = async () => ({
          kind: "video",
          source: await artifact("video/mp4"),
          playback: await artifact("video/mp4"),
          frames: [await artifact("image/jpeg"), await artifact("image/jpeg")],
          audio: {
            source: await artifact("audio/wav", wav),
            prepared_media_id: crypto.randomUUID(),
          },
        });
        const items = shape === "two_photos"
          ? [await photo(), await photo()]
          : shape === "two_audio"
          ? [await audio(), await audio()]
          : [
            shape === "photo_audio" ? await photo() : await video(),
            await audio(),
          ];
        const plan = parseInitialEvidenceCapturePlan(owner, {
          schema_version: 1,
          scan_id: scan,
          generation,
          items: [items[0], {
            kind: "description",
            text: "Synthetic note between media",
          }, items[1]],
        });
        const stageBytes = new Map<string, Uint8Array>(),
          retainedBytes = new Map<string, Uint8Array>();
        let writes = 0, reads = 0, lostPut = true;
        const signal = new AbortController().signal;
        const storage = {
          writeOnce(
            object: { object_id: string },
            bytes: Uint8Array,
            current: AbortSignal,
          ) {
            current.throwIfAborted();
            assert(
              !stageBytes.has(object.object_id),
              "stage object must not be overwritten",
            );
            writes++;
            stageBytes.set(object.object_id, bytes.slice());
            if (lostPut) {
              lostPut = false;
              throw new Error("synthetic lost PUT acknowledgement");
            }
            return Promise.resolve();
          },
          openBoundStream(object: { object_id: string }, current: AbortSignal) {
            current.throwIfAborted();
            reads++;
            const bytes = stageBytes.get(object.object_id);
            assert(bytes);
            return Promise.resolve(
              new ReadableStream<Uint8Array>({
                start(controller) {
                  controller.enqueue(bytes.slice());
                  controller.close();
                },
              }),
            );
          },
        };
        try {
          await db.queryArray("BEGIN; SET LOCAL statement_timeout='10s'");
          await db.queryArray(
            "INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1,'authenticated','authenticated','{}','{}',now(),now())",
            [owner],
          );
          const bridge = sqlClient(db);
          const client = {
            repository: await initialCaptureClientRepository(
              plan,
              bridge.client,
              "b".repeat(64),
            ),
            storage,
          };
          const upload = (media: string) =>
            uploadInitialCaptureClientArtifact(
              owner,
              initialCapturePlanValue(plan),
              media,
              originals.get(media)!,
              () => Promise.resolve(client),
              signal,
            );
          // A lost acknowledgement consumes the write, then resumes by readback.
          await assertRejects(
            () => upload(plan.uploads[0].media_id),
            Error,
            "initial_analysis_transport_unavailable",
          );
          for (const file of plan.uploads) {
            assertEquals((await upload(file.media_id)).ready, true);
          }
          assertEquals(writes, plan.uploads.length);
          const repository = initialCaptureAudioStageRepository(
            bridge.client,
            "b".repeat(64),
            "complete_client_stage",
          );
          const services = {
            client,
            audio: {
              repository,
              storage: initialCaptureAudioStageStorage(
                await initialCaptureAudioStageRequest(plan),
                repository,
                storage as unknown as PrivateCaptureStageObjectStorage,
              ),
            },
          };
          const prepared = await preparePrivateCaptureStage(
            plan,
            crypto.randomUUID(),
            services,
            signal,
          );
          assertEquals(writes, plan.uploads.length + plan.audio.length);
          const readsBeforeRecovery = reads;
          const replay = await preparePrivateCaptureStage(
            plan,
            crypto.randomUUID(),
            services,
            signal,
          );
          assertEquals(replay.request, prepared.request);
          assertEquals(writes, plan.uploads.length + plan.audio.length);
          assertEquals(
            reads - readsBeforeRecovery,
            plan.audio.length,
            "prepared recovery reads no original audio",
          );
          const intent = await buildPrivateCaptureIntent({
            plan,
            initialEvidence: prepared.request,
            payload: { user_id: owner, geoprivacy: "open" },
          });
          await db.queryArray(
            "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=TRUE",
          );
          const begin = () =>
            db.queryArray(
              "SELECT public.begin_scan_ingestion($1,$2,'identify-multimodal',$3::jsonb,$4::jsonb,$5::jsonb,$6::text[],NULL,NULL,$7,$8,$9::jsonb,$10,300)",
              [
                scan,
                owner,
                JSON.stringify(intent.payload),
                JSON.stringify(intent.mediaCounts),
                JSON.stringify(intent.mediaObjectKeys),
                intent.storageKeys,
                intent.resumable,
                intent.inlineMediaRedacted,
                JSON.stringify(intent.redactedMediaCounts),
                intent.payloadSchemaVersion,
              ],
            );
          const retainedStorage = {
            writeOnce(object: { object_id: string }, bytes: Uint8Array) {
              assert(!retainedBytes.has(object.object_id));
              retainedBytes.set(object.object_id, bytes.slice());
              return Promise.resolve();
            },
            readVerified(object: { object_id: string }) {
              const bytes = retainedBytes.get(object.object_id);
              assert(bytes);
              return Promise.resolve(bytes.slice());
            },
          };
          let preparationCalls = 0;
          let defaultPrivacy: "open" | "private" = "open";
          let privacyReads = 0;
          const submissionDependencies: PrivateCaptureSubmissionDependencies = {
            resolveGeoprivacy: () => {
              privacyReads++;
              return Promise.resolve(defaultPrivacy);
            },
            async readIntent(who, id, current) {
              current.throwIfAborted();
              const row = (await db.queryObject<
                {
                  payload_schema_version: number;
                  request_payload: Record<string, unknown>;
                }
              >(
                "SELECT payload_schema_version,request_payload FROM public.scan_ingestion_intents WHERE user_id=$1 AND scan_id=$2",
                [who, id],
              )).rows[0];
              return row ?? null;
            },
            async prepare(_plan, current) {
              preparationCalls++;
              return await preparePrivateCaptureStage(
                _plan,
                crypto.randomUUID(),
                services,
                current,
              );
            },
            begin: (value) => beginScanIngestion(value, bridge.client),
            repository: initialEvidenceRepository(bridge.client),
            storage: retainedStorage,
          };
          const submit = () =>
            preparePrivateCaptureSubmission(
              {
                owner,
                plan: initialCapturePlanValue(plan),
                payload: { user_id: owner, client_scan_id: scan },
              },
              submissionDependencies,
              signal,
            );
          // A stale or corrupt byte stream never obtains a ready receipt.
          const firstObject = await client.repository.reserve(
            plan.uploads[0].media_id,
            signal,
          );
          const original = stageBytes.get(firstObject.object_id)!;
          stageBytes.set(
            firstObject.object_id,
            new Uint8Array(original.length),
          );
          await assertRejects(submit);
          assertEquals(retainedBytes.size, 0);
          stageBytes.set(firstObject.object_id, original);
          const submitted = await submit();
          assert(submitted.retained);
          const retained = submitted.retained;
          assert(retained.receipt.items.every((file) => file.ready));
          assertEquals(
            retainedBytes.size,
            plan.uploads.length + plan.audio.length,
          );
          for (const file of retained.receipt.items) {
            assertEquals(
              await evidenceDigest(retainedBytes.get(file.object_id)!),
              file.sha256,
            );
          }
          assertEquals(
            (await db.queryObject<{ adopted: string; cleared: boolean }>(
              "SELECT adopted_evidence_digest adopted,request_body IS NULL cleared FROM internal.initial_capture_audio_stages WHERE scan_id=$1",
              [scan],
            )).rows[0],
            { adopted: prepared.request.evidence_digest, cleared: true },
          );
          assertEquals(
            (await db.queryObject<{ bound: boolean }>(
              "SELECT e.private_capture_request_sha256=s.request_sha256 bound FROM internal.ordinary_initial_evidence e JOIN internal.initial_capture_audio_stages s USING(scan_id) WHERE e.scan_id=$1",
              [scan],
            )).rows[0].bound,
            true,
          );
          await db.queryArray("SAVEPOINT immutable_private_origin");
          await assertRejects(() =>
            db.queryArray(
              "UPDATE internal.ordinary_initial_evidence SET private_capture_request_sha256=NULL WHERE scan_id=$1",
              [scan],
            )
          );
          await db.queryArray(
            "ROLLBACK TO SAVEPOINT immutable_private_origin; RELEASE SAVEPOINT immutable_private_origin",
          );
          // Post-adoption recovery reads retained objects and does not reopen
          // staging or the local originals. Admission is still the same intent.
          const providerReads: string[] = [];
          const providerStorage = {
            readVerified(
              item: Parameters<typeof retainedStorage.readVerified>[0] & {
                role: string;
              },
            ) {
              providerReads.push(item.role);
              assert(
                [
                  "prepared_image",
                  "inference_frame",
                  "prepared_audio",
                  "prepared_companion_audio",
                ].includes(item.role),
              );
              return retainedStorage.readVerified(item);
            },
          };
          const provider = await materializeInitialEvidence(
            owner,
            prepared.request,
            initialEvidenceRepository(bridge.client),
            providerStorage,
            signal,
          );
          assertEquals(
            provider.evidence.map((item) => item.kind),
            shape === "video_audio"
              ? ["image", "image", "audio", "text", "audio"]
              : shape === "two_audio"
              ? ["audio", "text", "audio"]
              : shape === "two_photos"
              ? ["image", "text", "image"]
              : ["image", "text", "audio"],
          );
          assertEquals(
            provider.evidence.map((item) => item.order),
            provider.evidence.map((_, index) => index),
          );
          assertEquals(providerReads.length, shape === "video_audio" ? 4 : 2);
          assertEquals(
            provider.capture.videoClipCount,
            shape === "video_audio" ? 1 : 0,
          );
          const still = provider.evidence.find((item) =>
            item.kind === "image" && item.lineage === null
          );
          if (still?.kind === "image") {
            assertEquals(still.focusRegion, selection);
          }
          for (const input of provider.evidence) {
            if (input.kind === "text") {
              assertEquals(input.text, "Synthetic note between media");
              continue;
            }
            const outputHash = await evidenceDigest(decodeBase64(input.data));
            assert(
              retained.receipt.items.some((file) =>
                providerReads.includes(file.role) && file.sha256 === outputHash
              ),
            );
          }
          const file = retained.receipt.items.find((file) =>
            providerReads.includes(file.role)
          )!;
          const savedProviderBytes = retainedBytes.get(file.object_id)!;
          retainedBytes.set(
            file.object_id,
            new Uint8Array(savedProviderBytes.length),
          );
          await assertRejects(() =>
            materializeInitialEvidence(
              owner,
              prepared.request,
              initialEvidenceRepository(bridge.client),
              providerStorage,
              signal,
            )
          );
          retainedBytes.set(file.object_id, savedProviderBytes);
          await assertRejects(() =>
            materializeInitialEvidence(
              crypto.randomUUID(),
              prepared.request,
              initialEvidenceRepository(bridge.client),
              providerStorage,
              signal,
            )
          );
          const cancelled = AbortSignal.abort();
          const callCount = bridge.calls.length;
          await assertRejects(() =>
            materializeInitialEvidence(
              owner,
              prepared.request,
              initialEvidenceRepository(bridge.client),
              providerStorage,
              cancelled,
            )
          );
          assertEquals(bridge.calls.length, callCount);
          const heldOriginals: [string, Uint8Array][] = [...originals].map((
            [id, bytes],
          ) => [id, bytes.slice()]);
          stageBytes.clear();
          const preparationCountBeforeReplay = preparationCalls;
          const privacyReadsBeforeReplay = privacyReads;
          defaultPrivacy = "private";
          const coldSubmission = await submit();
          assertEquals(coldSubmission.retained?.receipt, retained.receipt);
          assertEquals(preparationCalls, preparationCountBeforeReplay);
          assertEquals(privacyReads, privacyReadsBeforeReplay);
          assertEquals(
            coldSubmission.intent.payload.telemetry.geoprivacy,
            "open",
          );
          await begin();
          const noSource = {
            open() {
              throw new Error("retained recovery must not reopen staging");
            },
          };
          const recovered = await retainInitialEvidenceFromSource(
            owner,
            prepared.request,
            noSource,
            initialEvidenceRepository(bridge.client),
            retainedStorage,
            signal,
          );
          assertEquals(recovered.receipt, retained.receipt);
          assertEquals(
            [...originals],
            heldOriginals,
            "retention never releases native original holds",
          );
          // Real live-handler dispatch/finalization, with only the external
          // provider, quota reservation and usage reporting stubbed. All evidence,
          // quota commitment/settlement, and result SQL
          // remains real; no provider network or paid request is made.
          await db.queryArray("SAVEPOINT first_provider");
          const oldPosthog = Deno.env.get("POSTHOG_API_KEY");
          const oldQuotaSecret = Deno.env.get("AI_QUOTA_IP_HASH_SECRET");
          Deno.env.delete("POSTHOG_API_KEY");
          Deno.env.set(
            "AI_QUOTA_IP_HASH_SECRET",
            "synthetic-test-only-hash-secret".repeat(2),
          );
          bridge.provider.enabled = true;
          try {
            await db.queryArray(
              "INSERT INTO internal.complimentary_scan_usage(user_id,client_scan_id) VALUES($1,$2)",
              [owner, scan],
            );
            let dispatches = 0;
            await db.queryArray("SAVEPOINT interrupted_provider");
            const firstIdentify = (interrupt: boolean) =>
              handleIdentifyMultimodalRequest(
                new Request("https://example.invalid/identify-multimodal", {
                  method: "POST",
                  headers: {
                    "Content-Type": "application/json",
                    "X-Merian-Identification-Protocol": "7",
                    "X-Merian-Identification-Recipient": "google_gemini",
                  },
                  body: JSON.stringify({
                    user_id: owner,
                    client_scan_id: scan,
                    capturePlan: initialCapturePlanValue(plan),
                  }),
                }),
                { id: owner } as User,
                bridge.client,
                0,
                1,
                (input, authority) =>
                  createAIExecution(
                    {
                      provider: "test_only",
                      prepare() {
                        assert(input.variant === "multimodal");
                        assertEquals(
                          input.evidence.filter((item) => item.kind !== "text"),
                          provider.evidence.filter((item) =>
                            item.kind !== "text"
                          ),
                        );
                        return () => {
                          dispatches++;
                          bridge.calls.push("provider:invoke");
                          bridge.provider.failNextProfile = interrupt;
                          return Promise.resolve({
                            kind: "draft" as const,
                            draft: {
                              is_biological_subject: false,
                              is_live_capture: false,
                              common_name: "Synthetic Object",
                              confidence_score: .75,
                              ai_reasoning:
                                "Synthetic fixture identifies a manufactured object.",
                              extracted_visual_traits: [
                                "synthetic smooth surface",
                              ],
                              candidates: [],
                              image_quality: {
                                sharpness: 1,
                                framing: 1,
                                diagnostic_utility: 1,
                                overall_score: 0,
                              },
                              pet_identification: null,
                              ...(shape === "two_audio"
                                ? {
                                  audio_subject_type:
                                    "no_confident_biological_source",
                                }
                                : {}),
                            },
                            providerDurationMs: 1,
                            providerCompletedAt: Date.now(),
                            returnedModel: null,
                            usage: null,
                            finishReason: "STOP",
                            responseCharacters: 0,
                          });
                        };
                      },
                    },
                    input,
                    resolveAIClaim(input, authority),
                  ),
                undefined,
                undefined,
                retainedStorage,
              );
            const interrupted = await firstIdentify(true);
            assertEquals(
              interrupted.status,
              503,
              JSON.stringify(await interrupted.json()),
            );
            assertEquals(dispatches, 1);
            assertEquals(
              bridge.calls.includes("quota:failed"),
              false,
              "post-permit failure retains committed funding",
            );
            assertEquals(
              await recoverAcceptedInitialResult(
                bridge.client,
                owner,
                prepared.request,
                signal,
              ),
              null,
            );
            const held = await firstIdentify(false);
            assertEquals(held.status, 503);
            assertEquals(dispatches, 1, "replayed permit must not dispatch");
            assertEquals(
              bridge.calls.includes("quota:refunded"),
              false,
              "lost or replayed commit acknowledgement cannot refund",
            );
            const deny = async (
              sql: string,
              parameters: unknown[],
              message: string,
            ) => {
              await db.queryArray("SAVEPOINT denied_dispatch");
              try {
                await assertRejects(
                  () => db.queryArray(sql, parameters),
                  Error,
                  message,
                );
              } finally {
                await db.queryArray(
                  "ROLLBACK TO SAVEPOINT denied_dispatch; RELEASE SAVEPOINT denied_dispatch",
                );
              }
            };
            const reservation = "00000000-0000-4000-8000-000000000301";
            const lease = "00000000-0000-4000-8000-000000000401";
            assertEquals(
              (await db.queryObject<{ state: string; permits: number }>(
                "SELECT q.state,(SELECT count(*)::integer FROM internal.private_capture_primary_dispatch WHERE scan_id=$2) permits FROM internal.ai_quota_reservations q WHERE id=$1",
                [reservation, scan],
              )).rows,
              [{ state: "committed", permits: 1 }],
            );
            for (const state of ["failed", "refunded"]) {
              await deny(
                "SELECT public.finalize_ai_quota_reservation($1,$2,$3,$4)",
                [reservation, owner, lease, state],
                state === "failed"
                  ? "private_capture_dispatch_consumed"
                  : "ai_quota_finalization_conflict",
              );
            }
            await deny(
              "UPDATE internal.ai_quota_reservations SET original_analysis_id=NULL WHERE id=$1",
              [reservation],
              "private_capture_dispatch_immutable",
            );
            await deny(
              "UPDATE internal.ai_quota_reservations SET request_id=gen_random_uuid(),state='failed' WHERE id=$1",
              [reservation],
              "private_capture_dispatch_immutable",
            );
            await deny(
              "UPDATE internal.private_capture_primary_dispatch SET attempt_count=attempt_count+1 WHERE scan_id=$1",
              [scan],
              "private_capture_dispatch_immutable",
            );
            const durablePermit = (await db.queryObject<{ value: unknown }>(
              "SELECT to_jsonb(p) value FROM internal.private_capture_primary_dispatch p WHERE scan_id=$1",
              [scan],
            )).rows[0].value;
            const permitIdentity = durablePermit as Record<string, unknown>;
            assertEquals(permitIdentity.owner_id, owner);
            assertEquals(permitIdentity.generation, generation);
            assertEquals(permitIdentity.scan_id, scan);
            assertEquals(permitIdentity.reservation_id, reservation);
            assertEquals(
              (await db.queryObject<{ id: string }>(
                "SELECT id FROM internal.identification_invocations WHERE scan_id=$1",
                [scan],
              )).rows,
              [{ id: permitIdentity.invocation_id }],
            );
            // Accounting retention must never restore a primary permit. This
            // fixture deliberately removes both short-lived accounting owners.
            await db.queryArray(
              "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
              [scan],
            );
            await db.queryArray(
              "DELETE FROM internal.ai_quota_reservations WHERE id=$1",
              [reservation],
            );
            assertEquals(
              (await db.queryObject<{ value: unknown }>(
                "SELECT to_jsonb(p) value FROM internal.private_capture_primary_dispatch p WHERE scan_id=$1",
                [scan],
              )).rows[0].value,
              durablePermit,
            );
            await db.queryArray("SAVEPOINT private_quota_alias");
            await db.queryArray(
              "INSERT INTO internal.ai_quota_reservations(id,user_id,operation,request_id,lease_token,model,effective_plan,effective_tier,subscription_tier,trial_active,entitlement_version,policy_version) VALUES($1,$2,'scan_identification',$3,$4,'gemini-2.5-flash','free','free','free',FALSE,1,1)",
              [reservation, owner, scan, lease],
            );
            await deny(
              "SELECT public.finalize_ai_quota_reservation($1,$2,$3,'committed')",
              [reservation, owner, lease],
              "private_capture_dispatch_required",
            );
            await deny(
              "UPDATE internal.ai_quota_reservations SET request_id=gen_random_uuid(),state='committed' WHERE id=$1",
              [reservation],
              "private_capture_dispatch_immutable",
            );
            await deny(
              "UPDATE internal.ai_quota_reservations SET original_analysis_id=$2 WHERE id=$1",
              [reservation, scan],
              "private_capture_dispatch_immutable",
            );
            await db.queryArray(
              "ROLLBACK TO SAVEPOINT private_quota_alias; RELEASE SAVEPOINT private_quota_alias",
            );
            const afterPruning = await firstIdentify(false);
            assertEquals(afterPruning.status, 503);
            assertEquals(
              dispatches,
              1,
              "accounting pruning cannot grant a new provider call",
            );
            // A separate fixture transaction exercises successful dispatch.
            // Rolling the fixture back is not a production retry/reset path.
            await db.queryArray(
              "ROLLBACK TO SAVEPOINT interrupted_provider; RELEASE SAVEPOINT interrupted_provider",
            );
            const fresh = await firstIdentify(false);
            const freshBody = await fresh.json();
            assertEquals(
              fresh.status,
              200,
              JSON.stringify({
                freshBody,
                failures: bridge.failures,
                calls: bridge.calls.slice(-25),
              }),
            );
            assertEquals(dispatches, 2);
            assertEquals(
              freshBody.initial_evidence.evidence_digest,
              prepared.request.evidence_digest,
            );
            const sealed = await firstIdentify(false);
            assertEquals(sealed.status, 200);
            assertEquals(await sealed.json(), freshBody);
            assertEquals(dispatches, 2, "completed retry never redispatches");
            assertEquals([...originals], heldOriginals);
          } finally {
            bridge.provider.enabled = false;
            bridge.provider.failNextProfile = false;
            if (oldPosthog === undefined) Deno.env.delete("POSTHOG_API_KEY");
            else Deno.env.set("POSTHOG_API_KEY", oldPosthog);
            if (oldQuotaSecret === undefined) {
              Deno.env.delete("AI_QUOTA_IP_HASH_SECRET");
            } else Deno.env.set("AI_QUOTA_IP_HASH_SECRET", oldQuotaSecret);
            await db.queryArray(
              "ROLLBACK TO SAVEPOINT first_provider; RELEASE SAVEPOINT first_provider",
            );
          }
          const result = {
            ...JSON.parse(page.items[0].snapshot).result,
            scan_id: scan,
          };
          const resultRepository = initialEvidenceRepository(bridge.client);
          const acceptedBefore = await recoverAcceptedInitialResult(
            bridge.client,
            owner,
            prepared.request,
            signal,
          );
          assertEquals(acceptedBefore, null);
          let insertCalls = 0, completeCalls = 0;
          const finalizationDependencies = {
            bind: resultRepository.bindResult,
            async insert(
              row: import("../_shared/identify/db.ts").ScanInsertRow,
            ) {
              const accepted = await recoverAcceptedInitialResult(
                bridge.client,
                owner,
                prepared.request,
                signal,
              );
              assertEquals(
                accepted?.result,
                result,
                "binding precedes insertion",
              );
              assertEquals(row.image_storage_urls, []);
              assertEquals(row.audio_storage_urls, []);
              assertEquals(row.video_storage_urls, []);
              assertEquals(row.captured_media, []);
              assertEquals(row.user_observation_context, {
                freeText: "Synthetic note between media",
              });
              await db.queryArray(
                "INSERT INTO public.scans(id,user_id,ai_confidence_score,is_biological_subject,inference_tier,ai_reasoning,candidates,pet_identification,image_storage_urls,video_storage_urls,audio_storage_urls,captured_media) VALUES($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,'{}','{}','{}','[]') ON CONFLICT(id) DO NOTHING",
                [
                  scan,
                  owner,
                  row.ai_confidence_score,
                  row.is_biological_subject,
                  row.inference_tier,
                  row.ai_reasoning,
                  row.candidates === null
                    ? null
                    : JSON.stringify(row.candidates),
                  row.pet_identification === null
                    ? null
                    : JSON.stringify(row.pet_identification),
                ],
              );
              insertCalls++;
            },
            async complete(
              input: Parameters<typeof completeScanIngestionFinalization>[0],
            ) {
              completeCalls++;
              if (completeCalls === 1) {
                throw new Error(
                  "synthetic interruption after persisted insertion",
                );
              }
              return await completeScanIngestionFinalization(
                input,
                bridge.client,
              );
            },
          };
          const finish = () =>
            finalizeInitialEvidence(
              {
                owner,
                request: prepared.request,
                result,
                speciesID: null,
                telemetry: coldSubmission.intent.payload.telemetry,
              },
              finalizationDependencies,
              signal,
            );
          await assertRejects(finish, Error, "synthetic interruption");
          assertEquals(insertCalls, 1);
          assertEquals(
            (await recoverAcceptedInitialResult(
              bridge.client,
              owner,
              prepared.request,
              signal,
            ))?.result,
            result,
          );
          await db.queryArray(
            "INSERT INTO internal.complimentary_scan_usage(user_id,client_scan_id) VALUES($1,$2)",
            [owner, scan],
          );
          // Real scheduler + existing finalization adapters, with no foreground
          // Identify call, provider, quota reservation, or replacement job.
          await db.queryArray("SAVEPOINT private_worker");
          const operational = async () =>
            (await db.queryObject(
              "SELECT to_jsonb(j) job,to_jsonb(i) intent,to_jsonb(f) funding FROM public.scan_ingestion_jobs j JOIN public.scan_ingestion_intents i USING(scan_id,user_id) JOIN internal.complimentary_scan_usage f ON f.user_id=j.user_id AND f.client_scan_id=j.scan_id::uuid WHERE j.scan_id=$1",
              [scan],
            )).rows;
          const beforeClaim = await operational();
          const worker = privateFinalizationDependencies(bridge.client);
          await db.queryArray("SAVEPOINT missing_worker_artifact");
          await db.queryArray(
            "DELETE FROM internal.ordinary_initial_evidence_objects WHERE object_id=(SELECT object_id FROM internal.ordinary_initial_evidence_objects WHERE scan_id=$1 LIMIT 1)",
            [scan],
          );
          assertEquals(
            await worker.claim(signal),
            [],
            "incomplete retention cannot reach finalization",
          );
          assertEquals(
            await operational(),
            beforeClaim,
            "missing evidence must not terminalize or settle funding",
          );
          assertEquals(
            (await db.queryObject<{ held: boolean }>(
              "SELECT retry_at>clock_timestamp() held FROM internal.private_capture_finalization_leases WHERE scan_id=$1",
              [scan],
            )).rows[0].held,
            true,
            "malformed work is delayed instead of starving other candidates",
          );
          await db.queryArray(
            "ROLLBACK TO SAVEPOINT missing_worker_artifact; RELEASE SAVEPOINT missing_worker_artifact",
          );
          const claimed = await worker.claim(signal);
          assertEquals(
            await operational(),
            beforeClaim,
            "scheduling preserves original operational and funding state",
          );
          assertEquals(Array.isArray(claimed) ? claimed.length : -1, 1);
          assertEquals(
            await worker.claim(signal),
            [],
            "an active scheduling lease prevents duplicate claims",
          );
          await db.queryArray(
            "UPDATE internal.private_capture_finalization_leases SET retry_at=clock_timestamp()-interval '1 second' WHERE scan_id=$1",
            [scan],
          );
          assertEquals(
            await worker.claim(signal),
            claimed,
            "expired claim returns the same immutable work",
          );
          assertEquals(
            await operational(),
            beforeClaim,
            "claim expiry does not change provider attempts or funding",
          );
          await db.queryArray("SAVEPOINT worker_account_retirement");
          const retired = await continuePrivateCaptureFinalizations({
            ...worker,
            claim: () => Promise.resolve(claimed),
            async finalize(current, accepted, currentSignal) {
              // Retirement lands after accepted-result recovery and immediately
              // before the real bind/upsert/completion adapters.
              await db.queryArray(
                "INSERT INTO internal.account_deletion_jobs(user_id) VALUES($1)",
                [owner],
              );
              return await worker.finalize(current, accepted, currentSignal);
            },
          }, signal);
          assertEquals(retired, {
            claimed: 1,
            completed: 0,
            alreadyComplete: 0,
            held: 1,
          });
          assertEquals(
            (await db.queryObject<{ state: string }>(
              "SELECT state FROM internal.complimentary_scan_usage WHERE user_id=$1 AND client_scan_id=$2",
              [owner, scan],
            )).rows[0].state,
            "held",
          );
          await db.queryArray(
            "ROLLBACK TO SAVEPOINT worker_account_retirement; RELEASE SAVEPOINT worker_account_retirement",
          );
          const callStart = bridge.calls.length;
          const continued = await continuePrivateCaptureFinalizations({
            ...worker,
            claim: () => Promise.resolve(claimed),
          }, signal);
          assertEquals(continued, {
            claimed: 1,
            completed: 1,
            alreadyComplete: 0,
            held: 0,
          }, JSON.stringify(bridge.failures));
          assertEquals(
            bridge.calls.slice(callStart).some((call) =>
              call.startsWith("quota:")
            ),
            false,
          );
          assertEquals(
            (await db.queryObject<{ state: string }>(
              "SELECT state FROM internal.complimentary_scan_usage WHERE user_id=$1 AND client_scan_id=$2",
              [owner, scan],
            )).rows[0].state,
            "consumed",
          );
          assertEquals(
            await worker.claim(signal),
            [],
            "sealed work is never claimed again",
          );
          assertEquals(
            await continuePrivateCaptureFinalizations({
              ...worker,
              claim: () => Promise.resolve(claimed),
            }, signal),
            { claimed: 1, completed: 0, alreadyComplete: 1, held: 0 },
            "a delayed claimant reads the existing exact seal",
          );
          await db.queryArray(
            "ROLLBACK TO SAVEPOINT private_worker; RELEASE SAVEPOINT private_worker",
          );
          const finalInput = {
            scanId: scan,
            userId: owner,
            promotedUrlsByStorageKey: new Map<string, string>(),
            deletedStorageKeys: [],
            responseEnvelope: { success: true, data: result },
            initialEvidence: {
              generation,
              evidence_digest: prepared.request.evidence_digest,
              verifyResponse: initialEvidenceCompletionVerifier({
                ownerID: owner,
                scanID: scan,
                generation,
                evidenceDigest: prepared.request.evidence_digest,
              }),
            },
          };
          // The low-level finalizer is not an entitlement-completion capability.
          await db.queryArray("SAVEPOINT missing_fence");
          await assertRejects(() =>
            db.queryArray(
              "SELECT public.complete_scan_ingestion_finalization($1,$2,$3::jsonb,$4::text[])",
              [scan, owner, "{}", []],
            )
          );
          await db.queryArray(
            "ROLLBACK TO SAVEPOINT missing_fence; RELEASE SAVEPOINT missing_fence",
          );
          // Even a ready retained graph cannot legitimize public-media drift.
          await db.queryArray("SAVEPOINT public_drift");
          await db.queryArray(
            "UPDATE public.scans SET image_storage_urls=ARRAY['https://media.merian.app/synthetic-test-only.webp'] WHERE id=$1",
            [scan],
          );
          await assertRejects(() =>
            completeScanIngestionFinalization(finalInput, bridge.client)
          );
          await db.queryArray(
            "ROLLBACK TO SAVEPOINT public_drift; RELEASE SAVEPOINT public_drift",
          );
          await db.queryArray("SAVEPOINT before_completion");
          await db.queryArray(
            "UPDATE public.scans SET geoprivacy='obscured' WHERE id=$1 AND user_id=$2",
            [scan, owner],
          );
          const completed = await finish();
          assertEquals(
            (await db.queryObject<{ privacy: string }>(
              "SELECT geoprivacy::text privacy FROM public.scans WHERE id=$1",
              [scan],
            )).rows[0].privacy,
            "obscured",
            "completion preserves a privacy edit made after insertion",
          );
          assertEquals(
            insertCalls,
            2,
            "accepted-result retry reuses the immutable binding",
          );
          assertEquals(completed.responseEnvelope?.initial_evidence, {
            schema_version: 1,
            owner_id: owner,
            scan_id: scan,
            generation,
            evidence_digest: prepared.request.evidence_digest,
          });
          assertEquals(
            (await completeScanIngestionFinalization(finalInput, bridge.client))
              .responseEnvelope,
            completed.responseEnvelope,
          );
          assertEquals(
            (await db.queryObject<{ value: unknown }>(
              "SELECT public.recover_owned_initial_completion($1,$2) value",
              [owner, scan],
            )).rows[0].value,
            completed.responseEnvelope,
          );
          // Rewind only the completion, then exercise the live HTTP handler's
          // accepted-result recovery using production adapters and real SQL.
          await db.queryArray(
            "ROLLBACK TO SAVEPOINT before_completion; RELEASE SAVEPOINT before_completion",
          );
          await db.queryArray(
            "UPDATE public.users SET default_geoprivacy='private' WHERE id=$1",
            [owner],
          );
          let providerCalls = 0;
          const identify = (
            capturePlan: unknown = initialCapturePlanValue(plan),
          ) =>
            handleIdentifyMultimodalRequest(
              new Request("https://example.invalid/identify-multimodal", {
                method: "POST",
                headers: {
                  "Content-Type": "application/json",
                  "X-Merian-Identification-Protocol": "7",
                },
                body: JSON.stringify({
                  user_id: owner,
                  client_scan_id: scan,
                  capturePlan,
                }),
              }),
              { id: owner } as User,
              bridge.client,
              0,
              1,
              () => {
                providerCalls++;
                throw new Error("Recovery must not dispatch a provider");
              },
              undefined,
              undefined,
              retainedStorage,
            );
          await preparePrivateCaptureSubmission(
            {
              owner,
              plan: initialCapturePlanValue(plan),
              payload: { user_id: owner, client_scan_id: scan },
              normalizedTelemetry: {
                gpsLatitude: null,
                gpsLongitude: null,
                currentMonth: null,
              },
            },
            privateCaptureSubmissionDependencies(
              bridge.client,
              retainedStorage,
            ),
            signal,
          );
          const acceptedRecovery = await identify();
          const acceptedEnvelope = await acceptedRecovery.json();
          assertEquals(
            acceptedRecovery.status,
            200,
            JSON.stringify({
              acceptedEnvelope,
              failures: bridge.failures,
              calls: bridge.calls.slice(-12),
            }),
          );
          assertEquals(acceptedEnvelope, completed.responseEnvelope);
          const completedRecovery = await identify();
          const completedBody = await completedRecovery.json();
          assertEquals(
            completedRecovery.status,
            200,
            JSON.stringify({
              completedBody,
              failures: bridge.failures,
              calls: bridge.calls.slice(-8),
            }),
          );
          assertEquals(
            completedBody,
            completed.responseEnvelope,
          );
          assertEquals(providerCalls, 0);
          const changedPlan = {
            ...initialCapturePlanValue(plan),
            generation: crypto.randomUUID(),
          };
          assertEquals((await identify(changedPlan)).status, 409);
          const changedNotes = {
            ...initialCapturePlanValue(plan),
            items: initialCapturePlanValue(plan).items.map((item) =>
              item.kind === "description"
                ? { ...item, text: "Different synthetic note" }
                : item
            ),
          };
          assertEquals((await identify(changedNotes)).status, 409);
          await db.queryArray("SAVEPOINT completed_job_cleanup");
          await db.queryArray(
            "DELETE FROM public.scan_ingestion_intents WHERE scan_id=$1 AND user_id=$2",
            [scan, owner],
          );
          await db.queryArray(
            "DELETE FROM public.scan_ingestion_jobs WHERE scan_id=$1 AND user_id=$2",
            [scan, owner],
          );
          const afterCleanup = await identify();
          assertEquals(afterCleanup.status, 200);
          assertEquals(await afterCleanup.json(), completed.responseEnvelope);
          assertEquals(providerCalls, 0);
          await db.queryArray(
            "UPDATE public.scans SET is_tombstoned=TRUE WHERE id=$1",
            [scan],
          );
          assert(
            (await identify()).status !== 200,
            "tombstone blocks even a sealed exact-plan retry",
          );
          await db.queryArray(
            "ROLLBACK TO SAVEPOINT completed_job_cleanup; RELEASE SAVEPOINT completed_job_cleanup",
          );
          assertEquals(
            (await db.queryObject<{ privacy: string }>(
              "SELECT geoprivacy::text privacy FROM public.scans WHERE id=$1",
              [scan],
            )).rows[0].privacy,
            "private",
          );
          await db.queryArray(
            "UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,state_reader_enabled=TRUE,media_reader_enabled=TRUE,enrollment_enabled=TRUE",
          );
          await db.queryArray(
            "SELECT set_config('request.jwt.claim.sub',$1,true)",
            [owner],
          );
          const enrolled = (await db.queryObject<{ value: unknown }>(
            "SELECT public.enroll_owned_observation_history($1,$2) value",
            [scan, 18],
          )).rows[0].value;
          assert(enrolled);
        } finally {
          await db.queryArray("ROLLBACK");
          await db.end();
        }
      });
    }
  },
});
