import { assert, assertEquals, assertRejects } from "@std/assert";
import {
  Client,
  PostgresError,
} from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { initialCaptureAudioStageRequest } from "../_shared/analysisHistory/initialCaptureAudioStaging.ts";
import { initialEvidenceDigest } from "../_shared/analysisHistory/initialEvidenceManifest.ts";
import {
  initialRetentionRequest,
  parseInitialRetentionReceipt,
} from "../_shared/analysisHistory/initialEvidenceRetention.ts";
import { parseInitialEvidenceCapturePlan } from "../_shared/analysisHistory/initialEvidenceCapturePlan.ts";
import { buildPrivateCaptureIntent } from "../_shared/analysisHistory/privateCaptureIntent.ts";

const url = Deno.env.get("SUPABASE_DB_TEST_URL");
const provenance = {
  version: 1,
  provider: "gemini",
  binding: "gemini_baseline_v1",
  model: "gemini-2.5-flash",
  variant: "multimodal",
  operation: "scan_identification",
  policy_version: 1,
  prompt: "identify_vision_v1",
  schema: "merian_identify_v1",
  confidence: "unqualified",
  diagnostic_trigger: null,
  prompt_diagnostic_trigger: null,
  safety: null,
  timeout_ms: 90000,
  generation: {
    temperature: 0.1,
    seed: null,
    top_k: null,
    max_output_tokens: 8192,
    thinking_budget: 1024,
  },
};

// Complete synthetic private photo admission through the real SQL owners.
// No object store, HTTP request, or external identification provider is used.
async function seed(
  db: Client,
  owner: string,
  scan: string,
  beforeAdmission?: () => Promise<void>,
) {
  const artifact = (content_type: string) => ({
    media_id: crypto.randomUUID(),
    content_type,
    byte_count: 100,
    sha256: "a".repeat(64),
  });
  const generation = crypto.randomUUID();
  const manifest = {
    schema_version: 9,
    items: [{
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
    }],
  };
  const plan = parseInitialEvidenceCapturePlan(owner, {
    schema_version: 1,
    scan_id: scan,
    generation,
    items: manifest.items,
  });
  const request = await initialCaptureAudioStageRequest(plan);
  const text = JSON.stringify({
    owner_id: owner,
    plan: request.plan,
    recipe: request.recipe,
  });
  const retention = await initialRetentionRequest({
    schema_version: 1,
    scan_id: scan,
    generation,
    evidence_manifest: manifest,
    evidence_digest: await initialEvidenceDigest(manifest, scan, generation),
  });
  const intent = await buildPrivateCaptureIntent({
    plan,
    initialEvidence: retention,
    payload: { user_id: owner },
  });
  await db.queryArray("BEGIN");
  try {
    await db.queryArray(
      "INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1,'authenticated','authenticated','{}','{}',now(),now())",
      [owner],
    );
    const reservation = crypto.randomUUID(), lease = crypto.randomUUID();
    await db.queryArray(
      "INSERT INTO internal.ai_quota_reservations(id,user_id,operation,request_id,lease_token,model,effective_plan,effective_tier,subscription_tier,trial_active,entitlement_version,policy_version,original_analysis_id) VALUES($1,$2,'scan_identification',$3,$4,'gemini-2.5-flash','free','free','free',FALSE,1,1,$5)",
      [reservation, owner, crypto.randomUUID(), lease, scan],
    );
    await db.queryArray(
      "INSERT INTO internal.identification_provider_attempts(reservation_id,attempt_count,operation,effective_plan,model,policy_version,provider,binding,processor_permission,input_profile,minimum_identification_protocol,accepted_identification_protocol) VALUES($1,1,'scan_identification','free','gemini-2.5-flash',1,'gemini','gemini_baseline_v1','google_gemini','multimodal_photo_v1',0,7)",
      [reservation],
    );
    await db.queryArray("COMMIT");
    await beforeAdmission?.();
    await db.queryArray("BEGIN");
    const rollout = (await db.queryObject<{ enabled: boolean }>(
      "SELECT ordinary_initial_evidence_enabled enabled FROM internal.observation_history_rollout WHERE singleton FOR UPDATE",
    )).rows[0].enabled;
    await db.queryArray(
      "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=TRUE",
    );
    const stage = (action: string, media: string) =>
      db.queryArray(
        "SELECT public.initial_capture_client_stage_action($1,$2,$3,$4,$5)",
        [text, request.request_sha256, "b".repeat(64), action, media],
      );
    await stage("reserve", plan.uploads[0].media_id);
    for (const upload of plan.uploads) {
      await stage("write", upload.media_id);
      await stage("complete", upload.media_id);
    }
    await db.queryArray(
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
    await db.queryArray(
      "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=$1",
      [rollout],
    );
    await db.queryArray("COMMIT");
    return { reservation, lease };
  } catch (error) {
    await db.queryArray("ROLLBACK");
    throw error;
  }
}

async function blocked(db: Client, waiter: number, holder: number) {
  for (let n = 0; n < 200; n++) {
    if (
      (await db.queryObject<{ blocked: boolean }>(
        "SELECT $1=ANY(pg_blocking_pids($2)) blocked",
        [holder, waiter],
      )).rows[0].blocked
    ) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("exact transaction blocker was not observed");
}

Deno.test({
  name:
    "private primary dispatch serializes duplicate calls and account/terminal retirement",
  ignore: !url,
  async fn(t) {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    for (const kind of ["duplicate", "account", "terminal"] as const) {
      for (
        const first of kind === "duplicate"
          ? ["dispatch"]
          : ["dispatch", "retirement"]
      ) {
        await t.step(`${kind}:${first}`, async () => {
          const setup = new Client(url),
            writer = new Client(url),
            other = new Client(url);
          const owner = crypto.randomUUID(), scan = crypto.randomUUID();
          await Promise.all([
            setup.connect(),
            writer.connect(),
            other.connect(),
          ]);
          try {
            for (const db of [setup, writer, other]) {
              await db.queryArray(
                "SELECT set_config('request.jwt.claim.role','service_role',false); SET statement_timeout='15s'",
              );
            }
            const { reservation, lease } = await seed(setup, owner, scan);
            const dispatch = (db: Client) =>
              db.queryObject<{ may_dispatch: boolean }>(
                "SELECT * FROM public.commit_identification_invocation($1,$2,$3,1,$4::jsonb)",
                [reservation, owner, lease, JSON.stringify(provenance)],
              );
            const retire = (db: Client) =>
              kind === "account"
                ? db.queryArray(
                  "INSERT INTO internal.account_deletion_jobs(user_id) VALUES($1)",
                  [owner],
                )
                : db.queryArray(
                  "SELECT public.fail_scan_ingestion_terminal($1,$2,'user_deleted',NULL,'user_deleted')",
                  [scan, owner],
                );
            const writerPID = (await writer.queryObject<{ pid: number }>(
              "SELECT pg_backend_pid() pid",
            )).rows[0].pid;
            const otherPID = (await other.queryObject<{ pid: number }>(
              "SELECT pg_backend_pid() pid",
            )).rows[0].pid;
            await writer.queryArray("BEGIN");
            await other.queryArray("BEGIN");
            if (first === "dispatch") {
              const result = await dispatch(writer);
              assertEquals(result.rows[0].may_dispatch, true);
              const waiting =
                (kind === "duplicate" ? dispatch(other) : retire(other)).then(
                  (value) => ({ value }),
                  (error: Error) => ({ error }),
                );
              await blocked(setup, otherPID, writerPID);
              await writer.queryArray("COMMIT");
              const result2 = await waiting;
              if (kind === "duplicate") {
                assert(
                  "error" in result2 &&
                    result2.error.message.includes(
                      "private_capture_dispatch_unavailable",
                    ),
                );
                await other.queryArray("ROLLBACK");
              } else {
                if ("error" in result2) throw result2.error;
                await other.queryArray("COMMIT");
              }
            } else {
              await retire(other);
              const waiting = dispatch(writer).then(
                () => null,
                (error: Error) => error,
              );
              await blocked(setup, writerPID, otherPID);
              await other.queryArray("COMMIT");
              const error = await waiting;
              assert(
                error?.message.includes("private_capture_dispatch_unavailable"),
              );
              await writer.queryArray("ROLLBACK");
            }
            const saved = (await setup.queryObject<
              { state: string; permits: number; invocations: number }
            >(
              "SELECT state,(SELECT count(*)::int FROM internal.private_capture_primary_dispatch WHERE scan_id=$2) permits,(SELECT count(*)::int FROM internal.identification_invocations WHERE scan_id=$2) invocations FROM internal.ai_quota_reservations WHERE id=$1",
              [reservation, scan],
            )).rows[0];
            assertEquals(saved, {
              state: first === "dispatch" ? "committed" : "reserved",
              permits: first === "dispatch" ? 1 : 0,
              invocations: first === "dispatch" ? 1 : 0,
            });
          } finally {
            await writer.queryArray("ROLLBACK");
            await other.queryArray("ROLLBACK");
            await setup.queryArray("DELETE FROM public.users WHERE id=$1;", [
              owner,
            ]);
            await setup.queryArray("DELETE FROM auth.users WHERE id=$1", [
              owner,
            ]);
            await setup.queryArray(
              "DELETE FROM internal.capture_source_admissions WHERE owner_id=$1",
              [owner],
            );
            await setup.queryArray(
              "DELETE FROM internal.capture_source_admission_stops WHERE scan_id=$1",
              [scan],
            );
            await setup.queryArray(
              "DELETE FROM internal.account_deletion_jobs WHERE user_id=$1",
              [owner],
            );
            await Promise.all([setup.end(), writer.end(), other.end()]);
          }
        });
      }
    }
  },
});

Deno.test({
  name:
    "generic quota finalization rejects stale snapshot isolation before private classification",
  ignore: !url,
  async fn() {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    const db = new Client(url);
    await db.connect();
    const owner = crypto.randomUUID(),
      reservation = crypto.randomUUID(),
      lease = crypto.randomUUID();
    try {
      await db.queryArray(
        "SELECT set_config('request.jwt.claim.role','service_role',false)",
      );
      await db.queryArray(
        "INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1,'authenticated','authenticated','{}','{}',now(),now())",
        [owner],
      );
      await db.queryArray(
        "INSERT INTO internal.ai_quota_reservations(id,user_id,operation,request_id,lease_token,model,effective_plan,effective_tier,subscription_tier,trial_active,entitlement_version,policy_version,original_analysis_id) VALUES($1,$2,'scan_identification',$3,$4,'gemini-2.5-flash','free','free','free',FALSE,1,1,$5)",
        [reservation, owner, crypto.randomUUID(), lease, crypto.randomUUID()],
      );
      for (const isolation of ["REPEATABLE READ", "SERIALIZABLE"]) {
        await db.queryArray(`BEGIN ISOLATION LEVEL ${isolation}`);
        await db.queryArray(
          "SELECT count(*) FROM internal.ordinary_initial_evidence",
        );
        await assertRejects(
          () =>
            db.queryArray(
              "SELECT public.finalize_ai_quota_reservation($1,$2,$3,'committed')",
              [reservation, owner, lease],
            ),
          Error,
          "analysis_history_current_snapshot_required",
        );
        await db.queryArray("ROLLBACK");
      }
      assertEquals(
        (await db.queryObject<{ state: string }>(
          "SELECT state FROM internal.ai_quota_reservations WHERE id=$1",
          [reservation],
        )).rows[0].state,
        "reserved",
      );
    } finally {
      await db.queryArray("ROLLBACK");
      await db.queryArray("DELETE FROM public.users WHERE id=$1", [owner]);
      await db.queryArray("DELETE FROM auth.users WHERE id=$1", [owner]);
      await db.end();
    }
  },
});

Deno.test({
  name:
    "private dispatch rejects transactions whose snapshot predates admission",
  ignore: !url,
  async fn(t) {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    for (const isolation of ["REPEATABLE READ", "SERIALIZABLE"]) {
      for (const action of ["quota", "invocation", "dispatch"]) {
        await t.step(`${isolation}:${action}`, async () => {
          const setup = new Client(url), stale = new Client(url);
          const owner = crypto.randomUUID(), scan = crypto.randomUUID();
          await setup.connect();
          await stale.connect();
          try {
            for (const db of [setup, stale]) {
              await db.queryArray(
                "SELECT set_config('request.jwt.claim.role','service_role',false); SET statement_timeout='15s'",
              );
            }
            const { reservation, lease } = await seed(
              setup,
              owner,
              scan,
              async () => {
                await stale.queryArray(`BEGIN ISOLATION LEVEL ${isolation}`);
                assertEquals(
                  (await stale.queryObject<{ count: number }>(
                    "SELECT count(*)::int count FROM internal.ordinary_initial_evidence WHERE scan_id=$1",
                    [scan],
                  )).rows[0].count,
                  0,
                );
              },
            );
            // The other connection committed admission after this snapshot.
            assertEquals(
              (await stale.queryObject<{ count: number }>(
                "SELECT count(*)::int count FROM internal.ordinary_initial_evidence WHERE scan_id=$1",
                [scan],
              )).rows[0].count,
              0,
            );
            const error = await assertRejects(
              async () => {
                if (action === "quota") {
                  await stale.queryArray(
                    "SELECT public.finalize_ai_quota_reservation($1,$2,$3,'committed')",
                    [reservation, owner, lease],
                  );
                } else if (action === "invocation") {
                  await stale.queryArray(
                    "INSERT INTO internal.identification_invocations (reservation_id,attempt_count,lease_sha256,user_id,scan_id,provider,model,binding,input_profile,effective_plan,policy_version,occurred_at,provenance) VALUES($1,1,encode(extensions.digest($2::text,'sha256'),'hex'),$3,$4,'gemini','gemini-2.5-flash','gemini_baseline_v1','multimodal_photo_v1','free',1,clock_timestamp(),$5::jsonb)",
                    [
                      reservation,
                      lease,
                      owner,
                      scan,
                      JSON.stringify(provenance),
                    ],
                  );
                } else {
                  await stale.queryArray(
                    "SELECT * FROM public.commit_identification_invocation($1,$2,$3,1,$4::jsonb)",
                    [reservation, owner, lease, JSON.stringify(provenance)],
                  );
                }
              },
              PostgresError,
              action === "invocation"
                ? "initial_analysis_isolation_unavailable"
                : "analysis_history_current_snapshot_required",
            );
            assertEquals(error.fields.code, "25000");
            await stale.queryArray("ROLLBACK");
            assertEquals(
              (await setup.queryObject<
                { state: string; permits: number; invocations: number }
              >(
                "SELECT state,(SELECT count(*)::int FROM internal.private_capture_primary_dispatch WHERE scan_id=$2) permits,(SELECT count(*)::int FROM internal.identification_invocations WHERE scan_id=$2) invocations FROM internal.ai_quota_reservations WHERE id=$1",
                [reservation, scan],
              )).rows[0],
              { state: "reserved", permits: 0, invocations: 0 },
            );
            // Fresh READ COMMITTED remains functional after the denied attempt.
            assertEquals(
              (await setup.queryObject<{ may_dispatch: boolean }>(
                "SELECT * FROM public.commit_identification_invocation($1,$2,$3,1,$4::jsonb)",
                [reservation, owner, lease, JSON.stringify(provenance)],
              )).rows[0].may_dispatch,
              true,
            );
          } finally {
            await stale.queryArray("ROLLBACK");
            await setup.queryArray("DELETE FROM public.users WHERE id=$1", [
              owner,
            ]);
            await setup.queryArray("DELETE FROM auth.users WHERE id=$1", [
              owner,
            ]);
            await setup.queryArray(
              "DELETE FROM internal.capture_source_admissions WHERE owner_id=$1",
              [owner],
            );
            await setup.queryArray(
              "DELETE FROM internal.capture_source_admission_stops WHERE scan_id=$1",
              [scan],
            );
            await setup.end();
            await stale.end();
          }
        });
      }
    }
  },
});

Deno.test({
  name:
    "unbound refund preserves counters without allowing stale alias dispatch",
  ignore: !url,
  async fn(t) {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    for (const isolation of ["REPEATABLE READ", "SERIALIZABLE"]) {
      await t.step(isolation, async () => {
        const setup = new Client(url), stale = new Client(url);
        const owner = crypto.randomUUID(),
          scan = crypto.randomUUID(),
          alias = crypto.randomUUID();
        let aliasLease = "";
        await setup.connect();
        await stale.connect();
        try {
          for (const db of [setup, stale]) {
            await db.queryArray(
              "SELECT set_config('request.jwt.claim.role','service_role',false); SET statement_timeout='15s'",
            );
          }
          const { reservation, lease } = await seed(
            setup,
            owner,
            scan,
            async () => {
              aliasLease = (await setup.queryObject<{ lease_token: string }>(
                "INSERT INTO internal.ai_quota_reservations SELECT (jsonb_populate_record(NULL::internal.ai_quota_reservations,to_jsonb(q)||jsonb_build_object('id',$1::text,'request_id',$2::text,'original_analysis_id',NULL))).* FROM internal.ai_quota_reservations q WHERE original_analysis_id=$2::uuid RETURNING lease_token",
                [alias, scan],
              )).rows[0].lease_token;
              await setup.queryArray(
                "INSERT INTO internal.ai_quota_counters(scope_type,scope_key,bucket,window_start,window_seconds,request_count) VALUES('user_daily',$1,'capture-refund-proof',date_trunc('day',clock_timestamp()),86400,2)",
                [owner],
              );
              await setup.queryArray(
                "INSERT INTO internal.ai_quota_reservation_counters SELECT $1,scope_type,scope_key,bucket,window_start FROM internal.ai_quota_counters WHERE scope_key=$2 AND bucket='capture-refund-proof'",
                [alias, owner],
              );
              await stale.queryArray(`BEGIN ISOLATION LEVEL ${isolation}`);
              assertEquals(
                (await stale.queryObject<{ n: number }>(
                  "SELECT count(*)::int n FROM internal.ordinary_initial_evidence WHERE scan_id=$1",
                  [scan],
                )).rows[0].n,
                0,
              );
            },
          );
          const refund = (db: Client) =>
            db.queryObject<{ done: boolean }>(
              "SELECT public.finalize_ai_quota_reservation($1,$2,$3,'refunded') done",
              [alias, owner, aliasLease],
            );
          await grantSyntheticCurrentConsent(setup, owner);
          const denyWrapperBinding = async (expectedError: string) => {
            const before = (await setup.queryObject<{ value: unknown }>(
              "SELECT to_jsonb(q) value FROM internal.ai_quota_reservations q WHERE id=$1",
              [alias],
            )).rows[0].value;
            await assertRejects(
              () =>
                setup.queryArray(
                  "SELECT * FROM public.reserve_ai_quota($1,'scan_identification',$2,repeat('c',64),$2,TRUE,3,FALSE)",
                  [owner, scan],
                ),
              PostgresError,
              expectedError,
            );
            assertEquals(
              (await setup.queryObject<{ value: unknown }>(
                "SELECT to_jsonb(q) value FROM internal.ai_quota_reservations q WHERE id=$1",
                [alias],
              )).rows[0].value,
              before,
            );
          };
          assertEquals((await refund(stale)).rows[0].done, true);
          assertEquals((await refund(stale)).rows[0].done, true);
          await stale.queryArray("COMMIT");
          assertEquals(
            (await setup.queryObject<
              {
                state: string;
                refund_count: number;
                counter: number;
                links: number;
              }
            >(
              "SELECT state,refund_count,(SELECT request_count FROM internal.ai_quota_counters WHERE scope_key=$2 AND bucket='capture-refund-proof') counter,(SELECT count(*)::int FROM internal.ai_quota_reservation_counters WHERE reservation_id=$1) links FROM internal.ai_quota_reservations WHERE id=$1",
              [alias, owner],
            )).rows[0],
            { state: "refunded", refund_count: 1, counter: 1, links: 0 },
          );
          for (
            const statement of [
              "UPDATE internal.ai_quota_reservations SET state='reserved' WHERE id=$1",
              "UPDATE internal.ai_quota_reservations SET original_analysis_id=$2 WHERE id=$1",
            ]
          ) {
            await stale.queryArray(`BEGIN ISOLATION LEVEL ${isolation}`);
            const error = await assertRejects(
              () =>
                stale.queryArray(
                  statement,
                  statement.includes("$2") ? [alias, scan] : [alias],
                ),
              PostgresError,
              statement.includes("$2")
                ? "initial_analysis_isolation_unavailable"
                : "analysis_history_current_snapshot_required",
            );
            assertEquals(error.fields.code, "25000");
            await stale.queryArray("ROLLBACK");
          }
          await assertRejects(
            () =>
              setup.queryArray(
                "UPDATE internal.ai_quota_reservations SET original_analysis_id=$2 WHERE id=$1",
                [alias, scan],
              ),
            PostgresError,
            "private_capture_dispatch_immutable",
          );
          await denyWrapperBinding("ai_quota_unavailable");
          await assertRejects(
            () =>
              setup.queryArray(
                "SELECT * FROM public.commit_identification_invocation($1,$2,$3,1,$4::jsonb)",
                [alias, owner, aliasLease, JSON.stringify(provenance)],
              ),
            PostgresError,
          );
          assertEquals(
            (await setup.queryObject<{ n: number }>(
              "SELECT count(*)::int n FROM internal.private_capture_primary_dispatch WHERE scan_id=$1",
              [scan],
            )).rows[0].n,
            0,
          );
          assertEquals(
            (await setup.queryObject<{ may_dispatch: boolean }>(
              "SELECT * FROM public.commit_identification_invocation($1,$2,$3,1,$4::jsonb)",
              [reservation, owner, lease, JSON.stringify(provenance)],
            )).rows[0].may_dispatch,
            true,
          );
          await stale.queryArray(`BEGIN ISOLATION LEVEL ${isolation}`);
          const denied = await assertRejects(
            () =>
              stale.queryArray(
                "UPDATE internal.ai_quota_reservations SET state='failed' WHERE id=$1",
                [reservation],
              ),
            PostgresError,
            "analysis_history_current_snapshot_required",
          );
          assertEquals(denied.fields.code, "25000");
          await stale.queryArray("ROLLBACK");
          // Funding retry remains legal, but cannot mint another scan permit.
          await setup.queryArray(
            "UPDATE internal.ai_quota_reservations SET state='reserved' WHERE id=$1",
            [alias],
          );
          await denyWrapperBinding("private_capture_dispatch_immutable");
          for (
            const mutation of [
              "lease_token=gen_random_uuid()",
              "request_id=gen_random_uuid()",
              "attempt_count=attempt_count+1",
            ]
          ) {
            await stale.queryArray(`BEGIN ISOLATION LEVEL ${isolation}`);
            const error = await assertRejects(() =>
              stale.queryArray(
                `UPDATE internal.ai_quota_reservations SET state='refunded',refund_count=refund_count+1,${mutation} WHERE id=$1`,
                [alias],
              ), PostgresError);
            assertEquals(error.fields.code, "25000");
            await stale.queryArray("ROLLBACK");
          }
          assertEquals(
            (await setup.queryObject<{ refund_count: number; counter: number }>(
              "SELECT refund_count,(SELECT request_count FROM internal.ai_quota_counters WHERE scope_key=$2 AND bucket='capture-refund-proof') counter FROM internal.ai_quota_reservations WHERE id=$1",
              [alias, owner],
            )).rows[0],
            { refund_count: 1, counter: 1 },
          );

          await assertRejects(() =>
            setup.queryArray(
              "SELECT * FROM public.commit_identification_invocation($1,$2,$3,1,$4::jsonb)",
              [alias, owner, aliasLease, JSON.stringify(provenance)],
            ), PostgresError);
          assertEquals(
            (await setup.queryObject<{ n: number }>(
              "SELECT count(*)::int n FROM internal.private_capture_primary_dispatch WHERE scan_id=$1",
              [scan],
            )).rows[0].n,
            1,
          );
        } finally {
          await stale.queryArray("ROLLBACK");
          await setup.queryArray("DELETE FROM public.users WHERE id=$1", [
            owner,
          ]);
          await setup.queryArray("DELETE FROM auth.users WHERE id=$1", [owner]);
          await setup.queryArray(
            "DELETE FROM internal.capture_source_admissions WHERE owner_id=$1",
            [owner],
          );
          await setup.queryArray(
            "DELETE FROM internal.capture_source_admission_stops WHERE scan_id=$1",
            [scan],
          );
          await setup.queryArray(
            "DELETE FROM internal.ai_quota_counters WHERE scope_key=$1 AND bucket='capture-refund-proof'",
            [owner],
          );
          await setup.end();
          await stale.end();
        }
      });
    }
  },
});

Deno.test({
  name:
    "unbound refund row guards serialize with conditional binding and commitment",
  ignore: !url,
  async fn(t) {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    for (const mutation of ["binding", "commitment"]) {
      for (const first of ["refund", "mutation"]) {
        await t.step(`${mutation}:${first}`, async () => {
          const observer = new Client(url),
            refundOwner = new Client(url),
            competing = new Client(url);
          const owner = crypto.randomUUID(),
            reservation = crypto.randomUUID(),
            scan = crypto.randomUUID(),
            lease = crypto.randomUUID();
          await Promise.all([
            observer.connect(),
            refundOwner.connect(),
            competing.connect(),
          ]);
          try {
            for (const db of [observer, refundOwner, competing]) {
              await db.queryArray(
                "SELECT set_config('request.jwt.claim.role','service_role',false); SET statement_timeout='15s'",
              );
            }
            await observer.queryArray(
              "INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1,'authenticated','authenticated','{}','{}',now(),now())",
              [owner],
            );
            await observer.queryArray(
              "INSERT INTO internal.ai_quota_reservations(id,user_id,operation,request_id,lease_token,model,effective_plan,effective_tier,subscription_tier,trial_active,entitlement_version,policy_version) VALUES($1,$2,'scan_identification',$3,$4,'gemini-2.5-flash','free','free','free',FALSE,1,1)",
              [reservation, owner, scan, lease],
            );
            await observer.queryArray(
              "INSERT INTO internal.ai_quota_counters(scope_type,scope_key,bucket,window_start,window_seconds,request_count) VALUES('user_daily',$1,'capture-refund-race',date_trunc('day',clock_timestamp()),86400,2)",
              [owner],
            );
            await observer.queryArray(
              "INSERT INTO internal.ai_quota_reservation_counters SELECT $1,scope_type,scope_key,bucket,window_start FROM internal.ai_quota_counters WHERE scope_key=$2 AND bucket='capture-refund-race'",
              [reservation, owner],
            );
            const refundPID = (await refundOwner.queryObject<{ pid: number }>(
              "SELECT pg_backend_pid() pid",
            )).rows[0].pid;
            const competingPID = (await competing.queryObject<{ pid: number }>(
              "SELECT pg_backend_pid() pid",
            )).rows[0].pid;
            await refundOwner.queryArray(
              "BEGIN ISOLATION LEVEL REPEATABLE READ",
            );
            await refundOwner.queryArray(
              "SELECT state FROM internal.ai_quota_reservations WHERE id=$1",
              [reservation],
            );
            await competing.queryArray("BEGIN");
            const refund = () =>
              refundOwner.queryArray(
                "SELECT public.finalize_ai_quota_reservation($1,$2,$3,'refunded')",
                [reservation, owner, lease],
              );
            // Conditional writes model the competing operation's reserved-state
            // precondition. Both paths still execute all production row guards.
            const mutate = () =>
              competing.queryArray(
                mutation === "binding"
                  ? "UPDATE internal.ai_quota_reservations SET original_analysis_id=$2 WHERE id=$1 AND state='reserved'"
                  : "UPDATE internal.ai_quota_reservations SET state='committed' WHERE id=$1 AND state='reserved'",
                mutation === "binding" ? [reservation, scan] : [reservation],
              );
            if (first === "mutation") {
              await mutate();
              const waiting = refund().then(
                () => null,
                (error: PostgresError) => error,
              );
              await blocked(observer, refundPID, competingPID);
              await competing.queryArray("COMMIT");
              const error = await waiting;
              assertEquals(error?.fields.code, "40001");
              await refundOwner.queryArray("ROLLBACK");
            } else {
              await refund();
              const waiting = mutate();
              await blocked(observer, competingPID, refundPID);
              await refundOwner.queryArray("COMMIT");
              assertEquals((await waiting).rowCount, 0);
              await competing.queryArray("COMMIT");
            }
            const state = (await observer.queryObject<
              {
                state: string;
                refund_count: number;
                bound: boolean;
                counter: number;
                links: number;
              }
            >(
              "SELECT state,refund_count,original_analysis_id IS NOT NULL bound,(SELECT request_count FROM internal.ai_quota_counters WHERE scope_key=$2 AND bucket='capture-refund-race') counter,(SELECT count(*)::int FROM internal.ai_quota_reservation_counters WHERE reservation_id=$1) links FROM internal.ai_quota_reservations WHERE id=$1",
              [reservation, owner],
            )).rows[0];
            assertEquals(
              state,
              first === "refund"
                ? {
                  state: "refunded",
                  refund_count: 1,
                  bound: false,
                  counter: 1,
                  links: 0,
                }
                : {
                  state: mutation === "binding" ? "reserved" : "committed",
                  refund_count: 0,
                  bound: mutation === "binding",
                  counter: 2,
                  links: 1,
                },
            );
            assertEquals(
              (await observer.queryObject<{ n: number }>(
                "SELECT count(*)::int n FROM internal.private_capture_primary_dispatch WHERE scan_id=$1",
                [scan],
              )).rows[0].n,
              0,
            );
          } finally {
            await refundOwner.queryArray("ROLLBACK");
            await competing.queryArray("ROLLBACK");
            await observer.queryArray("DELETE FROM public.users WHERE id=$1", [
              owner,
            ]);
            await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
              owner,
            ]);
            await observer.queryArray(
              "DELETE FROM internal.ai_quota_counters WHERE scope_key=$1 AND bucket='capture-refund-race'",
              [owner],
            );
            await Promise.all([
              observer.end(),
              refundOwner.end(),
              competing.end(),
            ]);
          }
        });
      }
    }
  },
});

async function grantSyntheticCurrentConsent(db: Client, owner: string) {
  await db.queryArray(
    "INSERT INTO public.user_adult_eligibility_receipts(id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build) VALUES(gen_random_uuid(),$1,'2026-08-03',now(),'self_attestation','Synthetic adult receipt','ios','test','ci')",
    [owner],
  );
  await db.queryArray(
    "INSERT INTO public.user_terms_acceptance_receipts(id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build) VALUES(gen_random_uuid(),$1,'2026-08-03',now(),'Synthetic terms receipt','ios','test','ci')",
    [owner],
  );
  await db.queryArray(
    "INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build) VALUES(gen_random_uuid(),$1,'google_gemini','2026-08-04.1','granted',now(),'Synthetic processor disclosure','Synthetic grant','ios','test','ci')",
    [owner],
  );
}

Deno.test({
  name: "actual eight-argument reservation serializes with unbound refund",
  ignore: !url,
  async fn(t) {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    for (const first of ["reservation", "refund"]) {
      await t.step(first, async () => {
        const observer = new Client(url),
          refundOwner = new Client(url),
          contender = new Client(url);
        const owner = crypto.randomUUID(),
          reservation = crypto.randomUUID(),
          request = crypto.randomUUID(),
          scan = crypto.randomUUID(),
          lease = crypto.randomUUID();
        await Promise.all([
          observer.connect(),
          refundOwner.connect(),
          contender.connect(),
        ]);
        try {
          for (const db of [observer, refundOwner, contender]) {
            await db.queryArray(
              "SELECT set_config('request.jwt.claim.role','service_role',false); SET statement_timeout='15s'",
            );
          }
          await observer.queryArray(
            "INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1,'authenticated','authenticated','{}','{}',now(),now())",
            [owner],
          );
          await grantSyntheticCurrentConsent(observer, owner);
          await observer.queryArray(
            "INSERT INTO internal.ai_quota_reservations(id,user_id,operation,request_id,lease_token,lease_expires_at,model,effective_plan,effective_tier,subscription_tier,trial_active,entitlement_version,policy_version) VALUES($1,$2,'scan_identification',$3,$4,now()+interval '10 minutes','gemini-2.5-flash','free','free','free',FALSE,1,1)",
            [reservation, owner, request, lease],
          );
          await observer.queryArray(
            "INSERT INTO internal.ai_quota_counters(scope_type,scope_key,bucket,window_start,window_seconds,request_count) VALUES('user_daily',$1,'capture-wrapper-race',date_trunc('day',clock_timestamp()),86400,2)",
            [owner],
          );
          await observer.queryArray(
            "INSERT INTO internal.ai_quota_reservation_counters SELECT $1,scope_type,scope_key,bucket,window_start FROM internal.ai_quota_counters WHERE scope_key=$2 AND bucket='capture-wrapper-race'",
            [reservation, owner],
          );
          const refundPID = (await refundOwner.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() pid",
          )).rows[0].pid;
          const contenderPID = (await contender.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() pid",
          )).rows[0].pid;
          await refundOwner.queryArray("BEGIN ISOLATION LEVEL REPEATABLE READ");
          await refundOwner.queryArray(
            "SELECT state FROM internal.ai_quota_reservations WHERE id=$1",
            [reservation],
          );
          await contender.queryArray("BEGIN");
          const refund = () =>
            refundOwner.queryObject<{ done: boolean }>(
              "SELECT public.finalize_ai_quota_reservation($1,$2,$3,'refunded') done",
              [reservation, owner, lease],
            );
          const reserve = () =>
            contender.queryObject<
              {
                reservation_id: string;
                lease_token: string;
                attempt_count: number;
                is_replay: boolean;
              }
            >(
              "SELECT reservation_id,lease_token,attempt_count,is_replay FROM public.reserve_ai_quota($1,'scan_identification',$2,repeat('c',64),$3,TRUE,3,FALSE)",
              [owner, request, scan],
            );
          let result;
          if (first === "reservation") {
            result = (await reserve()).rows[0];
            const waiting = refund().then(
              () => null,
              (error: PostgresError) => error,
            );
            await blocked(observer, refundPID, contenderPID);
            await contender.queryArray("COMMIT");
            assertEquals((await waiting)?.fields.code, "40001");
            await refundOwner.queryArray("ROLLBACK");
            assertEquals(result.lease_token, lease);
            assertEquals(result.attempt_count, 1);
            assertEquals(result.is_replay, true);
          } else {
            assertEquals((await refund()).rows[0].done, true);
            const waiting = reserve();
            await blocked(observer, contenderPID, refundPID);
            await refundOwner.queryArray("COMMIT");
            result = (await waiting).rows[0];
            await contender.queryArray("COMMIT");
            assert(result.lease_token !== lease);
            assertEquals(result.attempt_count, 2);
            assertEquals(result.is_replay, false);
          }
          assertEquals(result.reservation_id, reservation);
          const row = (await observer.queryObject<
            {
              state: string;
              original_analysis_id: string;
              request_id: string;
              refund_count: number;
              counter: number;
              old_links: number;
            }
          >(
            "SELECT state,original_analysis_id,request_id,refund_count,(SELECT request_count FROM internal.ai_quota_counters WHERE scope_key=$2 AND bucket='capture-wrapper-race') counter,(SELECT count(*)::int FROM internal.ai_quota_reservation_counters WHERE reservation_id=$1 AND bucket='capture-wrapper-race') old_links FROM internal.ai_quota_reservations WHERE id=$1",
            [reservation, owner],
          )).rows[0];
          assertEquals(row, {
            state: "reserved",
            original_analysis_id: scan,
            request_id: request,
            refund_count: first === "refund" ? 1 : 0,
            counter: first === "refund" ? 1 : 2,
            old_links: first === "refund" ? 0 : 1,
          });
          assertEquals(
            (await observer.queryObject<{ n: number }>(
              "SELECT count(*)::int n FROM internal.private_capture_primary_dispatch WHERE scan_id=$1",
              [scan],
            )).rows[0].n,
            0,
          );
        } finally {
          await refundOwner.queryArray("ROLLBACK");
          await contender.queryArray("ROLLBACK");
          await observer.queryArray("DELETE FROM public.users WHERE id=$1", [
            owner,
          ]);
          await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
            owner,
          ]);
          await observer.queryArray(
            "DELETE FROM internal.ai_quota_counters WHERE scope_key=$1",
            [owner],
          );
          await Promise.all([
            observer.end(),
            refundOwner.end(),
            contender.end(),
          ]);
        }
      });
    }
  },
});
