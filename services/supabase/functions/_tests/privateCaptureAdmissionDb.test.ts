import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { initialCaptureAudioStageRequest } from "../_shared/analysisHistory/initialCaptureAudioStaging.ts";
import { initialEvidenceDigest } from "../_shared/analysisHistory/initialEvidenceManifest.ts";
import {
  initialRetentionRequest,
  parseInitialRetentionReceipt,
} from "../_shared/analysisHistory/initialEvidenceRetention.ts";
import { parseInitialEvidenceCapturePlan } from "../_shared/analysisHistory/initialEvidenceCapturePlan.ts";
import { buildPrivateCaptureIntent } from "../_shared/analysisHistory/privateCaptureIntent.ts";

const url = Deno.env.get("SUPABASE_DB_TEST_URL");
const artifact = (content_type: string, byte_count = 100) => ({
  media_id: crypto.randomUUID(),
  content_type,
  byte_count,
  sha256: "a".repeat(64),
});
Deno.test({
  name:
    "private schema4 admission seals complete ready graph atomically and cold replay preserves retained adoption",
  ignore: !url,
  async fn(t) {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    for (const kind of ["photo", "photo_audio", "video_audio"] as const) {
      await t.step(kind, async () => {
        const db = new Client(url);
        await db.connect();
        const owner = crypto.randomUUID(),
          scan = crypto.randomUUID(),
          generation = crypto.randomUUID(),
          attempt = crypto.randomUUID();
        const photo = {
          kind: "image",
          source: artifact("image/heif"),
          prepared: artifact("image/jpeg"),
          coordinate_basis: "prepared_image_top_left_v1",
          focus_region: null,
          preparation: {
            schema_version: 1,
            coordinate_basis: "upright_source_top_left_v1",
            format: "nativeStillImageV1",
            crop_display_size: null,
            quarter_turns: 0,
            scale: 1,
            offset_x: 0,
            offset_y: 0,
            camera_vertical_center: null,
            source_selection: null,
          },
        };
        const audio = {
          kind: "audio",
          source: artifact("audio/wav"),
          prepared: artifact("audio/wav", 16044),
        };
        const video = {
          kind: "video",
          source: artifact("video/mp4"),
          playback: artifact("video/mp4"),
          frames: [artifact("image/jpeg"), artifact("image/jpeg")],
          audio: {
            source: artifact("audio/wav"),
            prepared: artifact("audio/wav", 16044),
          },
        };
        const manifest = {
          schema_version: 9,
          items: kind === "photo"
            ? [photo]
            : [kind === "photo_audio" ? photo : video, {
              kind: "description",
              text: "Synthetic field note",
            }, audio],
        };
        const plan = parseInitialEvidenceCapturePlan(owner, {
          schema_version: 1,
          scan_id: scan,
          generation,
          items: manifest.items.map((item) =>
            item.kind === "audio"
              ? {
                kind: "audio",
                source: audio.source,
                prepared_media_id: audio.prepared.media_id,
              }
              : item.kind === "video"
              ? {
                ...video,
                audio: {
                  source: video.audio.source,
                  prepared_media_id: video.audio.prepared.media_id,
                },
              }
              : item
          ),
        });
        const request = await initialCaptureAudioStageRequest(plan),
          text = JSON.stringify({
            owner_id: owner,
            plan: request.plan,
            recipe: request.recipe,
          });
        const retention = await initialRetentionRequest({
          schema_version: 1,
          scan_id: scan,
          generation,
          evidence_manifest: manifest,
          evidence_digest: await initialEvidenceDigest(
            manifest,
            scan,
            generation,
          ),
        });
        const intent = await buildPrivateCaptureIntent({
          plan,
          initialEvidence: retention,
          payload: { user_id: owner },
        });
        assertEquals(
          intent.mediaCounts.image_count,
          kind === "video_audio" ? 0 : 1,
        );
        assertEquals(
          intent.mediaCounts.video_frame_count,
          kind === "video_audio" ? 2 : 0,
        );
        const begin = async (value = intent) =>
          (await db.queryObject<{ value: unknown }>(
            "SELECT public.begin_scan_ingestion($1,$2,'identify-multimodal',$3::jsonb,$4::jsonb,$5::jsonb,$6::text[],NULL,NULL,$7,$8,$9::jsonb,$10,300) value",
            [
              scan,
              owner,
              JSON.stringify(value.payload),
              JSON.stringify(value.mediaCounts),
              JSON.stringify(value.mediaObjectKeys),
              value.storageKeys,
              value.resumable,
              value.inlineMediaRedacted,
              JSON.stringify(value.redactedMediaCounts),
              value.payloadSchemaVersion,
            ],
          )).rows[0].value;
        const client = (
          action: string,
          media = plan.uploads[0].media_id,
        ) =>
          db.queryArray(
            "SELECT public.initial_capture_client_stage_action($1,$2,$3,$4,$5)",
            [text, request.request_sha256, "b".repeat(64), action, media],
          );
        const reject = async (work: () => Promise<unknown>, code: string) => {
          await db.queryArray("SAVEPOINT rejected");
          await assertRejects(work, Error, code);
          await db.queryArray("ROLLBACK TO SAVEPOINT rejected");
        };
        try {
          await db.queryArray("BEGIN; SET LOCAL statement_timeout='10s'");
          await db.queryArray(
            "INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1,'authenticated','authenticated','{}','{}',now(),now())",
            [owner],
          );
          await reject(() => begin(), "capture_source_admission_unavailable");
          await reject(
            () =>
              db.queryArray(
                "INSERT INTO public.scan_ingestion_intents(scan_id,user_id,request_payload,payload_schema_version) VALUES($1,$2,$3::jsonb,4)",
                [
                  scan,
                  owner,
                  JSON.stringify({
                    ...intent.payload,
                    initialEvidence: undefined,
                  }),
                ],
              ),
            "capture_source_admission_conflict",
          );
          await client("reserve");
          await reject(() => begin(), "analysis_history_evidence_unavailable");
          await reject(
            () =>
              db.queryArray(
                "INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage) VALUES($1,$2,'processing','ai_inference_started')",
                [scan, owner],
              ),
            "capture_source_admission_conflict",
          );
          for (const upload of plan.uploads) {
            await client("write", upload.media_id);
            await client("complete", upload.media_id);
          }
          if (plan.audio.length) {
            await reject(
              () => begin(),
              "analysis_history_evidence_unavailable",
            );
            const saved = (await db.queryObject<
              { value: { items: { object_id: string }[] } }
            >(
              "SELECT public.claim_initial_capture_stage_preparation($1,$2,$3,$4) value",
              [text, request.request_sha256, "b".repeat(64), attempt],
            )).rows[0].value;
            const outputs = kind === "photo_audio"
              ? [audio.prepared]
              : [video.audio.prepared, audio.prepared];
            await db.queryArray(
              "SELECT public.initial_capture_audio_stage_action($1,$2,$3,'bind',$4,$5::jsonb,NULL)",
              [
                text,
                request.request_sha256,
                "b".repeat(64),
                attempt,
                JSON.stringify(outputs),
              ],
            );
            for (const [index, object] of saved.items.entries()) {
              await db.queryArray(
                "SELECT public.initial_capture_audio_stage_action($1,$2,$3,'write',NULL,$4::jsonb,$5)",
                [
                  text,
                  request.request_sha256,
                  "b".repeat(64),
                  JSON.stringify(outputs[index]),
                  object.object_id,
                ],
              );
              await reject(
                () => begin(),
                "analysis_history_evidence_unavailable",
              );
              await db.queryArray(
                "SELECT public.initial_capture_audio_stage_action($1,$2,$3,'complete',NULL,$4::jsonb,$5)",
                [
                  text,
                  request.request_sha256,
                  "b".repeat(64),
                  JSON.stringify(outputs[index]),
                  object.object_id,
                ],
              );
            }
          }
          const badCounts = structuredClone(intent);
          badCounts.mediaCounts.image_count++;
          await reject(
            () => begin(badCounts),
            "capture_source_admission_invalid",
          );
          const publicKeys = structuredClone(intent);
          publicKeys.storageKeys = ["staging/synthetic/forbidden"];
          await reject(
            () => begin(publicKeys),
            "capture_source_admission_invalid",
          );
          const badProof = structuredClone(intent);
          badProof.payload.privateCaptureStage.requestSHA256 = "c".repeat(64);
          await reject(
            () => begin(badProof),
            "capture_source_admission_unavailable",
          );
          await db.queryArray(
            "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=TRUE",
          );
          const first = await begin();
          const saved = (await db.queryObject<
            {
              payload: Record<string, unknown>;
              schema: number;
              kind: string;
              jobs: number;
            }
          >(
            "SELECT i.request_payload payload,i.payload_schema_version schema,s.recovery->>'kind' kind,(SELECT count(*)::int FROM public.scan_ingestion_jobs WHERE scan_id=$1) jobs FROM public.scan_ingestion_intents i JOIN internal.capture_source_admissions s ON s.scan_id::text=i.scan_id WHERE i.scan_id=$1",
            [scan],
          )).rows[0];
          assertEquals(saved.schema, 4);
          assertEquals(saved.kind, "private_capture_stage_v1");
          assertEquals(saved.jobs, 1);
          assertEquals(saved.payload.initialEvidence, retention);
          assertEquals(await begin(), first);
          await reject(
            () => begin(badProof),
            "capture_source_admission_conflict",
          );
          await reject(
            () =>
              db.queryArray(
                "UPDATE public.scan_ingestion_intents SET request_payload=request_payload-'privateCaptureStage' WHERE scan_id=$1",
                [scan],
              ),
            "analysis_history_operation_conflict",
          );
          await reject(
            () =>
              db.queryArray(
                "UPDATE public.scan_ingestion_jobs SET media_counts='{}' WHERE scan_id=$1",
                [scan],
              ),
            "capture_source_admission_conflict",
          );
          await db.queryArray(
            "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=TRUE",
          );
          const retained = parseInitialRetentionReceipt(
            (await db.queryObject<{ value: unknown }>(
              "SELECT public.reserve_owned_initial_evidence($1,$2::jsonb) value",
              [owner, JSON.stringify(retention)],
            )).rows[0].value,
            owner,
            retention,
          );
          for (const object of retained.items) {
            await db.queryArray(
              "SELECT public.complete_owned_initial_evidence($1,$2::jsonb,$3)",
              [owner, JSON.stringify(retention), object.object_id],
            );
          }
          assertEquals(
            (await db.queryObject<{ adopted: string; cleared: boolean }>(
              "SELECT adopted_evidence_digest adopted,request_body IS NULL cleared FROM internal.initial_capture_audio_stages WHERE scan_id=$1",
              [scan],
            )).rows[0],
            { adopted: retention.evidence_digest, cleared: true },
          );
          assertEquals(await begin(), first);
          await db.queryArray(
            "DELETE FROM public.scan_ingestion_intents WHERE scan_id=$1",
            [scan],
          );
          await db.queryArray(
            "DELETE FROM public.scan_ingestion_jobs WHERE scan_id=$1",
            [scan],
          );
          assertEquals(await begin(), first);
          assertEquals(
            (await db.queryObject<{ payload: unknown }>(
              "SELECT request_payload payload FROM public.scan_ingestion_intents WHERE scan_id=$1",
              [scan],
            )).rows[0].payload,
            saved.payload,
          );
          await db.queryArray(
            "UPDATE public.scan_ingestion_intents SET resumable=FALSE WHERE scan_id=$1",
            [scan],
          );
          await reject(() => begin(), "capture_source_admission_unavailable");
        } finally {
          await db.queryArray("ROLLBACK");
          await db.end();
        }
      });
    }
  },
});
