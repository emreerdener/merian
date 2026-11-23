import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { initialCaptureAudioStageRequest } from "../_shared/analysisHistory/initialCaptureAudioStaging.ts";
import { parseInitialEvidenceCapturePlan } from "../_shared/analysisHistory/initialEvidenceCapturePlan.ts";

const url = Deno.env.get("SUPABASE_DB_TEST_URL");
const artifact = (content_type: string, byte_count = 100) => ({
  media_id: crypto.randomUUID(),
  content_type,
  byte_count,
  sha256: "a".repeat(64),
});
Deno.test({
  name:
    "private client inventory binds exact full graph, separates DSP authority and retires both namespaces of stage artifacts",
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
          generation = crypto.randomUUID();
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
          prepared_media_id: crypto.randomUUID(),
        };
        const video = {
          kind: "video",
          source: artifact("video/mp4"),
          playback: artifact("video/mp4"),
          frames: [artifact("image/jpeg"), artifact("image/jpeg")],
          audio: {
            source: artifact("audio/wav"),
            prepared_media_id: crypto.randomUUID(),
          },
        };
        const plan = parseInitialEvidenceCapturePlan(owner, {
          schema_version: 1,
          scan_id: scan,
          generation,
          items: kind === "photo"
            ? [photo]
            : [kind === "photo_audio" ? photo : video, {
              kind: "description",
              text: "Synthetic field notes",
            }, audio],
        });
        const request = await initialCaptureAudioStageRequest(plan);
        const text = JSON.stringify({
          owner_id: owner,
          plan: request.plan,
          recipe: request.recipe,
        });
        type Receipt = {
          object_id: string;
          artifact: unknown;
          write_issued: boolean;
          ready: boolean;
          request_sha256: string;
        };
        const call = async (
          action: string,
          media = plan.uploads[0].media_id,
          requestText = text,
          sha = request.request_sha256,
          backend = "b".repeat(64),
        ) =>
          (await db.queryObject<{ value: Receipt | boolean }>(
            "SELECT public.initial_capture_client_stage_action($1,$2,$3,$4,$5) value",
            [requestText, sha, backend, action, media],
          )).rows[0].value;
        const claim = async (attempt = crypto.randomUUID()) =>
          (await db.queryObject<
            { value: { items: { object_id: string }[]; attempt_id: string } }
          >(
            "SELECT public.claim_initial_capture_stage_preparation($1,$2,$3,$4) value",
            [text, request.request_sha256, "b".repeat(64), attempt],
          )).rows[0].value;
        const reject = async (run: () => Promise<unknown>, code: string) => {
          await db.queryArray("SAVEPOINT rejected");
          await assertRejects(run, Error, code);
          await db.queryArray("ROLLBACK TO SAVEPOINT rejected");
        };
        try {
          await db.queryArray("BEGIN; SET LOCAL statement_timeout='10s'");
          await db.queryArray(
            "INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1,'authenticated','authenticated','{}','{}',now(),now())",
            [owner],
          );
          for (const role of ["anon", "authenticated"]) {
            await db.queryArray(`SET LOCAL ROLE ${role}`);
            await reject(() => call("reserve"), "permission denied");
            await db.queryArray("RESET ROLE");
          }
          await reject(() => call("read"), "analysis_history_unavailable");
          await reject(
            () => call("reserve", crypto.randomUUID()),
            "invalid_analysis_history",
          );
          const first = await call("reserve") as Receipt;
          assertEquals(first.artifact, plan.uploads[0]);
          assertEquals(first.ready, false);
          assertEquals(first.write_issued, false);
          assertEquals(await call("reserve"), first);
          await reject(
            () =>
              call("reserve", plan.uploads[0].media_id, text, "c".repeat(64)),
            "invalid_analysis_history",
          );
          await reject(
            () =>
              call(
                "reserve",
                plan.uploads[0].media_id,
                text,
                request.request_sha256,
                "c".repeat(64),
              ),
            "analysis_history_operation_conflict",
          );
          await reject(() => claim(), "analysis_history_evidence_unavailable");
          for (const slot of plan.audio) {
            await reject(
              () => call("reserve", slot.preparedID),
              "invalid_analysis_history",
            );
          }
          const ids: string[] = [];
          for (const upload of plan.uploads) {
            const saved = await call("reserve", upload.media_id) as Receipt;
            ids.push(saved.object_id);
            assertEquals(saved.artifact, upload);
            await reject(
              () => call("verify", upload.media_id),
              "analysis_history_unavailable",
            );
            await reject(
              () => call("complete", upload.media_id),
              "analysis_history_unavailable",
            );
            assertEquals(await call("write", upload.media_id), true);
            assertEquals(await call("write", upload.media_id), false);
            assertEquals(await call("verify", upload.media_id), true);
            await reject(
              () => call("read", upload.media_id),
              "analysis_history_unavailable",
            );
            const ready = await call("complete", upload.media_id) as Receipt;
            assert(ready.ready && ready.write_issued);
            assertEquals(await call("read", upload.media_id), true);
            assertEquals(await call("complete", upload.media_id), ready);
          }
          const attempt = crypto.randomUUID();
          const prepared = await claim(attempt);
          assertEquals(prepared.attempt_id, attempt);
          assertEquals((await claim(attempt)).attempt_id, attempt);
          if (plan.audio.length) {
            await reject(() => claim(), "analysis_history_unavailable");
            const outputs = plan.audio.map((slot) => ({
              ...artifact("audio/wav", 16044),
              media_id: slot.preparedID,
            }));
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
            assertEquals((await claim()).attempt_id, attempt);
          }
          // Inventory metadata drift is denied even when all ready markers exist.
          await db.queryArray("SAVEPOINT damaged");
          await db.queryArray(
            "UPDATE internal.initial_capture_client_stage_objects SET artifact=jsonb_set(artifact,'{sha256}',to_jsonb(repeat('d',64))) WHERE object_id=$1",
            [ids[0]],
          );
          await reject(() => claim(), "analysis_history_evidence_unavailable");
          await db.queryArray("ROLLBACK TO SAVEPOINT damaged");
          const before = (await db.queryObject<{ count: number }>(
            "SELECT count(*)::int count FROM public.scan_ingestion_jobs WHERE scan_id=$1",
            [scan],
          )).rows[0];
          assertEquals(before.count, 0);
          // Account deletion intake is the existing fenced retirement trigger.
          await db.queryArray("DELETE FROM public.users WHERE id=$1", [owner]);
          const state = (await db.queryObject<
            {
              clients: number;
              audio: number;
              erased: number;
              cleared: boolean;
            }
          >(
            "SELECT (SELECT count(*)::int FROM internal.initial_capture_client_stage_objects WHERE scan_id=$1) clients,(SELECT count(*)::int FROM internal.initial_capture_audio_stage_objects WHERE scan_id=$1) audio,(SELECT count(*)::int FROM internal.initial_capture_audio_stage_erasure WHERE object_id=ANY($2::uuid[])) erased,(SELECT request_body IS NULL FROM internal.initial_capture_audio_stages WHERE scan_id=$1) cleared",
            [scan, [...ids, ...prepared.items.map((x) => x.object_id)]],
          )).rows[0];
          assertEquals(state, {
            clients: 0,
            audio: 0,
            erased: ids.length + prepared.items.length,
            cleared: true,
          });
          await reject(() => call("complete"), "analysis_history_unavailable");
        } finally {
          await db.queryArray("ROLLBACK");
          await db.end();
        }
      });
    }
  },
});
