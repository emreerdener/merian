import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { initialCaptureAudioStageRequest } from "../_shared/analysisHistory/initialCaptureAudioStaging.ts";
import { parseInitialEvidenceCapturePlan } from "../_shared/analysisHistory/initialEvidenceCapturePlan.ts";
import { initialEvidenceDigest } from "../_shared/analysisHistory/initialEvidenceManifest.ts";
import {
  initialRetentionRequest,
  parseInitialRetentionReceipt,
} from "../_shared/analysisHistory/initialEvidenceRetention.ts";

const url = Deno.env.get("SUPABASE_DB_TEST_URL");
const artifact = (content_type: string, byte_count = 100) => ({
  media_id: crypto.randomUUID(),
  content_type,
  byte_count,
  sha256: "a".repeat(64),
});
Deno.test({
  name:
    "audio stage adoption follows complete exact ordinary retention and cold replay never recreates stage bytes",
  ignore: !url,
  async fn(t) {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    for (const kind of ["photo_audio", "video_audio"] as const) {
      await t.step(kind, async () => {
        const db = new Client(url);
        await db.connect();
        const owner = crypto.randomUUID(),
          scan = crypto.randomUUID(),
          generation = crypto.randomUUID(),
          attempt = crypto.randomUUID();
        const source = artifact("audio/wav"),
          prepared = artifact("audio/wav", 16044);
        const companionSource = artifact("audio/wav"),
          companionPrepared = artifact("audio/wav", 16044);
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
        const video = {
          kind: "video",
          source: artifact("video/mp4"),
          playback: artifact("video/mp4"),
          frames: [artifact("image/jpeg")],
          audio: {
            source: companionSource,
            prepared_media_id: companionPrepared.media_id,
          },
        };
        const plan = parseInitialEvidenceCapturePlan(owner, {
          schema_version: 1,
          scan_id: scan,
          generation,
          items: [
            { kind: "audio", source, prepared_media_id: prepared.media_id },
            { kind: "description", text: "Synthetic field note" },
            kind === "photo_audio" ? photo : video,
          ],
        });
        const request = await initialCaptureAudioStageRequest(plan);
        const requestText = JSON.stringify({
          owner_id: owner,
          plan: request.plan,
          recipe: request.recipe,
        });
        const outputs = kind === "photo_audio"
          ? [prepared]
          : [prepared, companionPrepared];
        const manifest = {
          schema_version: 9,
          items: [
            { kind: "audio", source, prepared },
            { kind: "description", text: "Synthetic field note" },
            kind === "photo_audio" ? photo : {
              ...video,
              audio: { source: companionSource, prepared: companionPrepared },
            },
          ],
        };
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
        const stage = async (
          action: string,
          object: string | null = null,
          output: unknown = null,
        ) =>
          (await db.queryObject<{ value: { items: { object_id: string }[] } }>(
            "SELECT public.initial_capture_audio_stage_action($1,$2,$3,$4,$5::uuid,$6::jsonb,$7::uuid) value",
            [
              requestText,
              request.request_sha256,
              "b".repeat(64),
              action,
              ["reserve", "bind"].includes(action) ? attempt : null,
              output === null ? null : JSON.stringify(output),
              object,
            ],
          )).rows[0].value;
        const reserve = async (value: unknown = retention) =>
          (await db.queryObject<{ value: unknown }>(
            "SELECT public.reserve_owned_initial_evidence($1,$2::jsonb) value",
            [owner, JSON.stringify(value)],
          )).rows[0].value;
        const rejects = async (body: () => Promise<unknown>, code: string) => {
          await db.queryArray("SAVEPOINT rejected");
          await assertRejects(body, Error, code);
          await db.queryArray("ROLLBACK TO SAVEPOINT rejected");
        };
        try {
          await db.queryArray("BEGIN; SET LOCAL statement_timeout='10s'");
          await db.queryArray(
            "INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1,'authenticated','authenticated','{}','{}',now(),now())",
            [owner],
          );
          await rejects(() =>
            db.queryArray(
              "SELECT internal.assert_initial_capture_audio_retention($1,$2::jsonb)",
              [owner, JSON.stringify(retention)],
            ), "analysis_history_evidence_unavailable");
          const reservedStage = await stage("reserve");
          await db.queryArray(
            "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=TRUE",
          );
          await db.queryArray(
            "INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,media_counts) VALUES($1,$2,'finalizing','provider_accepted','{}')",
            [scan, owner],
          );
          await db.queryArray(
            "INSERT INTO public.scan_ingestion_intents(scan_id,user_id,request_payload,payload_checksum) VALUES($1,$2,$3::jsonb,repeat('a',64))",
            [scan, owner, JSON.stringify({ initialEvidence: retention })],
          );
          await rejects(
            () => reserve(),
            "analysis_history_evidence_unavailable",
          );
          await stage("bind", null, outputs);
          for (const [index, item] of reservedStage.items.entries()) {
            await stage("write", item.object_id, outputs[index]);
            // Trusted byte-readback attestation is simulated only in this DB test.
            await stage("complete", item.object_id, outputs[index]);
          }
          const changed = structuredClone(manifest);
          changed.items[1] = {
            kind: "description",
            text: "Changed observation",
          };
          await rejects(() =>
            reserve({
              ...retention,
              evidence_manifest: changed,
              evidence_digest: "c".repeat(64),
            }), "invalid_analysis_history");
          const changedRequest = {
            ...retention,
            evidence_manifest: changed,
            evidence_digest: await initialEvidenceDigest(
              changed,
              scan,
              generation,
            ),
          };
          await rejects(
            () => reserve(changedRequest),
            "analysis_history_operation_conflict",
          );
          const receipt = parseInitialRetentionReceipt(
            await reserve(),
            owner,
            retention,
          );
          assert(receipt.items.every((item) => !item.ready));
          await db.queryArray("SAVEPOINT deleted_stage");
          await db.queryArray(
            "SELECT internal.retire_initial_capture_audio_stage($1)",
            [scan],
          );
          await rejects(
            () => reserve(),
            "analysis_history_evidence_unavailable",
          );
          await db.queryArray("ROLLBACK TO SAVEPOINT deleted_stage");
          for (const [index, item] of receipt.items.entries()) {
            await db.queryArray(
              "SELECT public.complete_owned_initial_evidence($1,$2::jsonb,$3)",
              [owner, JSON.stringify(retention), item.object_id],
            );
            const saved = (await db.queryObject<
              {
                adopted: string | null;
                objects: number;
                erased: number;
                cleared: boolean;
              }
            >(
              "SELECT s.adopted_evidence_digest adopted,s.request_body IS NULL cleared,(SELECT count(*)::int FROM internal.initial_capture_audio_stage_objects WHERE scan_id=s.scan_id) objects,(SELECT count(*)::int FROM internal.initial_capture_audio_stage_erasure WHERE object_id=ANY($2::uuid[])) erased FROM internal.initial_capture_audio_stages s WHERE scan_id=$1",
              [
                scan,
                reservedStage.items.map((x) => x.object_id),
              ],
            )).rows[0];
            const last = index === receipt.items.length - 1;
            assertEquals(saved, {
              adopted: last ? retention.evidence_digest : null,
              cleared: last,
              objects: last ? 0 : outputs.length,
              erased: last ? outputs.length : 0,
            });
          }
          const replay = parseInitialRetentionReceipt(
            await reserve(),
            owner,
            retention,
            receipt,
          );
          assert(replay.items.every((item) => item.ready));
          await db.queryArray(
            "SELECT public.complete_owned_initial_evidence($1,$2::jsonb,$3)",
            [owner, JSON.stringify(retention), receipt.items.at(-1)!.object_id],
          );
          await rejects(
            () => stage("reserve"),
            "analysis_history_operation_conflict",
          );
          await rejects(
            () => reserve(changedRequest),
            "analysis_history_operation_conflict",
          );
          await db.queryArray("SAVEPOINT damaged_adoption");
          await db.queryArray(
            "UPDATE internal.initial_capture_audio_stages SET adopted_evidence_digest=repeat('d',64) WHERE scan_id=$1",
            [scan],
          );
          await rejects(() => reserve(), "analysis_history_operation_conflict");
          await rejects(
            () =>
              db.queryArray(
                "SELECT internal.adopt_initial_capture_audio_retention(e) FROM internal.ordinary_initial_evidence e WHERE scan_id=$1",
                [scan],
              ),
            "analysis_history_operation_conflict",
          );
          await db.queryArray("ROLLBACK TO SAVEPOINT damaged_adoption");
        } finally {
          await db.queryArray("ROLLBACK");
          await db.end();
        }
      });
    }
  },
});
