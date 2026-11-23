import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { initialEvidenceDigest } from "../_shared/analysisHistory/initialEvidenceManifest.ts";
import {
  initialRetentionRequest,
  parseInitialRetentionReceipt,
} from "../_shared/analysisHistory/initialEvidenceRetention.ts";

async function raceRequest(scan: string, generation: string) {
  const artifact = () => ({
    media_id: crypto.randomUUID(),
    content_type: "image/jpeg",
    byte_count: 100,
    sha256: "a".repeat(64),
  });
  const manifest = {
    schema_version: 7,
    items: [{
      kind: "image",
      source: artifact(),
      prepared: artifact(),
      coordinate_basis: "prepared_image_top_left_v1",
      focus_region: null,
    }],
  };
  return await initialRetentionRequest({
    schema_version: 1,
    scan_id: scan,
    generation,
    evidence_manifest: manifest,
    evidence_digest: await initialEvidenceDigest(manifest, scan, generation),
  });
}

Deno.test({
  name:
    "pruning waits for accepted binding and preserves the original job and intent",
  ignore: !Deno.env.get("SUPABASE_DB_TEST_URL"),
  async fn() {
    const url = Deno.env.get("SUPABASE_DB_TEST_URL");
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    const setup = new Client(url),
      binding = new Client(url),
      pruning = new Client(url);
    await Promise.all([setup.connect(), binding.connect(), pruning.connect()]);
    const owner = crypto.randomUUID(),
      scan = crypto.randomUUID(),
      generation = crypto.randomUUID();
    try {
      await setup.queryArray(
        "INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1::uuid,'authenticated','authenticated',$1::uuid::text||'@example.invalid','{}','{}',now(),now())",
        [owner],
      );
      await setup.queryArray(
        "INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,media_counts) VALUES($1,$2,'finalizing','provider_accepted','{}')",
        [scan, owner],
      );
      await binding.queryArray(
        "BEGIN; SET LOCAL statement_timeout='5s'; SELECT set_config('request.jwt.claim.role','service_role',true)",
      );
      const gate = (await binding.queryObject<{ enabled: boolean }>(
        "SELECT ordinary_initial_evidence_enabled enabled FROM internal.observation_history_rollout FOR UPDATE",
      )).rows[0].enabled;
      await binding.queryArray(
        "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=true",
      );
      const request = await raceRequest(scan, generation),
        wire = JSON.stringify(request);
      await binding.queryArray(
        "INSERT INTO public.scan_ingestion_intents(scan_id,user_id,request_payload,payload_checksum) VALUES($1,$2,$3::jsonb,repeat('a',64))",
        [scan, owner, JSON.stringify({ initialEvidence: request })],
      );
      const receipt = (await binding.queryObject<
        { value: { items: { object_id: string }[] } }
      >(
        "SELECT public.reserve_owned_initial_evidence($1,$2::jsonb) value",
        [owner, wire],
      )).rows[0].value;
      for (const item of receipt.items) {
        await binding.queryArray(
          "SELECT public.complete_owned_initial_evidence($1,$2::jsonb,$3)",
          [owner, wire, item.object_id],
        );
      }
      const result = {
        scan_id: scan,
        is_biological_subject: false,
        confidence_score: 0.2,
        inference_tier: "flash",
        ai_reasoning: null,
      };
      await binding.queryArray(
        "SELECT public.bind_owned_initial_result($1,$2::jsonb,$3::jsonb,NULL)",
        [owner, wire, JSON.stringify(result)],
      );
      await binding.queryArray(
        "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=$1",
        [gate],
      );
      await pruning.queryArray("BEGIN; SET LOCAL statement_timeout='5s'");
      const pid = (await pruning.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() pid",
      )).rows[0].pid;
      let finished = false;
      const deletion = pruning.queryObject(
        "DELETE FROM public.scan_ingestion_jobs WHERE scan_id=$1 AND user_id=$2 RETURNING id",
        [scan, owner],
      )
        .finally(() => {
          finished = true;
        });
      let blocked = false;
      for (let attempt = 0; attempt < 100 && !finished; attempt++) {
        blocked = (await setup.queryObject<{ blocked: boolean }>(
          "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
          [pid],
        )).rows[0].blocked;
        if (blocked) break;
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
      assert(blocked, "pruning must wait for the original job's binding lock");
      await binding.queryArray("COMMIT");
      assertEquals((await deletion).rows, []);
      assertEquals(
        (await pruning.queryObject(
          "DELETE FROM public.scan_ingestion_intents WHERE scan_id=$1 AND user_id=$2 RETURNING id",
          [scan, owner],
        )).rows,
        [],
      );
      await pruning.queryArray("COMMIT");
      assertEquals(
        (await setup.queryObject(
          "SELECT accepted_result result,retired_at,sealed_at FROM internal.ordinary_initial_evidence WHERE scan_id=$1",
          [scan],
        )).rows,
        [{ result, retired_at: null, sealed_at: null }],
      );
    } finally {
      await binding.queryArray("ROLLBACK").catch(() => {});
      await pruning.queryArray("ROLLBACK").catch(() => {});
      await setup.queryArray("DELETE FROM public.users WHERE id=$1", [owner]);
      await setup.queryArray("DELETE FROM auth.users WHERE id=$1", [owner]);
      await Promise.all([setup.end(), binding.end(), pruning.end()]);
    }
  },
});

Deno.test({
  name:
    "stale legacy terminal decision rechecks evidence after waiting for the job lock",
  ignore: !Deno.env.get("SUPABASE_DB_TEST_URL"),
  async fn() {
    const url = Deno.env.get("SUPABASE_DB_TEST_URL");
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    const setup = new Client(url),
      binding = new Client(url),
      terminal = new Client(url);
    await Promise.all([setup.connect(), binding.connect(), terminal.connect()]);
    const owner = crypto.randomUUID(),
      scan = crypto.randomUUID(),
      generation = crypto.randomUUID();
    try {
      await setup.queryArray("BEGIN");
      await setup.queryArray(
        "INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1::uuid,'authenticated','authenticated',$1::uuid::text||'@example.invalid','{}','{}',now(),now())",
        [owner],
      );
      await setup.queryArray(
        "INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,media_counts) VALUES($1,$2,'finalizing','provider_accepted','{}')",
        [scan, owner],
      );
      await setup.queryArray(
        "INSERT INTO internal.complimentary_scan_usage(user_id,client_scan_id) VALUES($1,$2)",
        [owner, scan],
      );
      await setup.queryArray("COMMIT");
      await binding.queryArray("BEGIN; SET LOCAL statement_timeout='5s'");
      // The real intent trigger owns the job lock while a stale terminal
      // decision starts in another connection. Restore the gate before commit;
      // no activation change escapes this synthetic transaction.
      const oldGate = (await binding.queryObject<{ enabled: boolean }>(
        "SELECT ordinary_initial_evidence_enabled enabled FROM internal.observation_history_rollout FOR UPDATE",
      )).rows[0].enabled;
      await binding.queryArray(
        "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=true",
      );
      await binding.queryArray(
        "INSERT INTO public.scan_ingestion_intents(scan_id,user_id,request_payload,payload_checksum) VALUES($1,$2,$3::jsonb,repeat('a',64))",
        [
          scan,
          owner,
          JSON.stringify({
            initialEvidence: await raceRequest(scan, generation),
          }),
        ],
      );
      await binding.queryArray(
        "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=$1",
        [oldGate],
      );
      await terminal.queryArray(
        "BEGIN; SET LOCAL statement_timeout='5s'; SELECT set_config('request.jwt.claim.role','service_role',true)",
      );
      const pid = (await terminal.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() pid",
      )).rows[0].pid;
      let finished = false;
      const outcome = terminal.queryArray(
        "SELECT public.fail_scan_ingestion_terminal($1,$2,'server_replay_limit_reached','Synthetic stale decision','replay_exhausted')",
        [scan, owner],
      ).then(() => "unexpected_success", (error) => String(error)).then(
        (result) => {
          finished = true;
          return result;
        },
      );
      let blocked = false;
      for (let attempt = 0; attempt < 100 && !finished; attempt++) {
        blocked = (await setup.queryObject<{ blocked: boolean }>(
          "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
          [pid],
        )).rows[0].blocked;
        if (blocked) break;
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
      assert(blocked, "terminal settlement must wait for the binding job lock");
      await binding.queryArray("COMMIT");
      assert((await outcome).includes("initial_evidence_recovery_required"));
      await terminal.queryArray("ROLLBACK");
      assertEquals(
        (await setup.queryObject(
          "SELECT j.status,j.stage,j.initial_evidence_generation::text generation,f.state FROM public.scan_ingestion_jobs j JOIN internal.complimentary_scan_usage f ON f.client_scan_id=j.scan_id::uuid AND f.user_id=j.user_id WHERE j.scan_id=$1",
          [scan],
        )).rows,
        [{
          status: "finalizing",
          stage: "provider_accepted",
          generation,
          state: "held",
        }],
      );
    } finally {
      await Promise.allSettled([
        setup.queryArray("ROLLBACK"),
        binding.queryArray("ROLLBACK"),
        terminal.queryArray("ROLLBACK"),
      ]);
      await setup.queryArray("DELETE FROM public.users WHERE id=$1", [owner]);
      await setup.queryArray("DELETE FROM auth.users WHERE id=$1", [owner]);
      await Promise.all([setup.end(), binding.end(), terminal.end()]);
    }
  },
});

const url = Deno.env.get("SUPABASE_DB_TEST_URL");
Deno.test({
  name:
    "initial evidence admission cannot resurrect a legacy job after terminalization wins",
  ignore: !url,
  async fn() {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    const setup = new Client(url),
      binding = new Client(url),
      terminal = new Client(url);
    await Promise.all([setup.connect(), binding.connect(), terminal.connect()]);
    const owner = crypto.randomUUID(),
      scan = crypto.randomUUID(),
      generation = crypto.randomUUID();
    const artifact = () => ({
      media_id: crypto.randomUUID(),
      content_type: "image/jpeg",
      byte_count: 100,
      sha256: "a".repeat(64),
    });
    const manifest = {
      schema_version: 7,
      items: [{
        kind: "image",
        source: artifact(),
        prepared: artifact(),
        coordinate_basis: "prepared_image_top_left_v1",
        focus_region: null,
      }],
    };
    const request = await initialRetentionRequest({
      schema_version: 1,
      scan_id: scan,
      generation,
      evidence_manifest: manifest,
      evidence_digest: await initialEvidenceDigest(manifest, scan, generation),
    });
    try {
      await setup.queryArray("BEGIN");
      await setup.queryArray(
        "INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1::uuid,'authenticated','authenticated',$1::uuid::text||'@example.invalid','{}','{}',now(),now())",
        [owner],
      );
      await setup.queryArray(
        "INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,media_counts) VALUES($1,$2,'finalizing','provider_accepted','{}')",
        [scan, owner],
      );
      await setup.queryArray(
        "INSERT INTO internal.complimentary_scan_usage(user_id,client_scan_id) VALUES($1,$2)",
        [owner, scan],
      );
      await setup.queryArray("COMMIT");
      await terminal.queryArray(
        "BEGIN; SET LOCAL statement_timeout='5s'; SELECT set_config('request.jwt.claim.role','service_role',true)",
      );
      await terminal.queryArray(
        "SELECT public.fail_scan_ingestion_terminal($1,$2,'server_replay_limit_reached','Synthetic stale decision','replay_exhausted')",
        [scan, owner],
      );
      await binding.queryArray("BEGIN; SET LOCAL statement_timeout='5s'");
      // The gate change is never committed; this enables only the synthetic
      // binding attempt and rolls back along with its rejected intent.
      await binding.queryArray(
        "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=true",
      );
      const pid = (await binding.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() pid",
      )).rows[0].pid;
      let finished = false;
      const outcome = binding.queryArray(
        "INSERT INTO public.scan_ingestion_intents(scan_id,user_id,request_payload,payload_checksum) VALUES($1,$2,$3::jsonb,repeat('a',64))",
        [scan, owner, JSON.stringify({ initialEvidence: request })],
      )
        .then(() => "unexpected_success", (error) => String(error)).then(
          (result) => {
            finished = true;
            return result;
          },
        );
      let blocked = false;
      for (let attempt = 0; attempt < 100 && !finished; attempt++) {
        blocked = (await setup.queryObject<{ blocked: boolean }>(
          "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
          [pid],
        )).rows[0].blocked;
        if (blocked) break;
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
      assert(
        blocked,
        "binding must wait for terminalization's ownership locks",
      );
      await terminal.queryArray("COMMIT");
      assert((await outcome).includes("analysis_history_operation_conflict"));
      await binding.queryArray("ROLLBACK");
      assertEquals(
        (await setup.queryObject(
          "SELECT j.status,j.initial_evidence_generation::text generation,f.state FROM public.scan_ingestion_jobs j JOIN internal.complimentary_scan_usage f ON f.client_scan_id=j.scan_id::uuid AND f.user_id=j.user_id WHERE j.scan_id=$1",
          [scan],
        )).rows,
        [{ status: "failed_terminal", generation: null, state: "released" }],
      );
      assertEquals(
        (await setup.queryObject<{ n: number }>(
          "SELECT count(*)::int n FROM public.scan_ingestion_intents WHERE scan_id=$1",
          [scan],
        )).rows[0].n,
        0,
      );
    } finally {
      await Promise.allSettled([
        setup.queryArray("ROLLBACK"),
        binding.queryArray("ROLLBACK"),
        terminal.queryArray("ROLLBACK"),
      ]);
      await setup.queryArray("DELETE FROM public.users WHERE id=$1", [owner]);
      await setup.queryArray("DELETE FROM auth.users WHERE id=$1", [owner]);
      await Promise.all([setup.end(), binding.end(), terminal.end()]);
    }
  },
});
for (const manifestVersion of [7, 8, 9] as const) {
  Deno.test({
    name:
      `ordinary initial V${manifestVersion} retention binds job, readers, recovery and erasure`,
    ignore: !url,
    async fn() {
      assert(
        url &&
          ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
      );
      const db = new Client(url);
      await db.connect();
      const owner = crypto.randomUUID(),
        scan = crypto.randomUUID(),
        generation = crypto.randomUUID();
      const artifact = () => ({
        media_id: crypto.randomUUID(),
        content_type: "image/jpeg",
        byte_count: 100,
        sha256: "a".repeat(64),
      });
      const manifest = {
        schema_version: manifestVersion,
        items: [{
          kind: "image",
          source: {
            ...artifact(),
            byte_count: manifestVersion >= 8 ? 33_554_432 : 100,
          },
          prepared: artifact(),
          coordinate_basis: "prepared_image_top_left_v1",
          ...(manifestVersion === 9
            ? {
              preparation: {
                schema_version: 1,
                coordinate_basis: "upright_source_top_left_v1",
                format: "nativeSelectedStillImageV2",
                crop_display_size: 390,
                quarter_turns: 1,
                scale: 1.5,
                offset_x: -30,
                offset_y: 25,
                camera_vertical_center: null,
                source_selection: {
                  x: 0.2,
                  y: 0.3,
                  width: 0.1,
                  height: 0.2,
                  source: "user_selection",
                },
              },
            }
            : {}),
          focus_region: {
            x: 0.1,
            y: 0.2,
            width: 0.3,
            height: 0.4,
            source: "user_selection",
          },
        }],
      };
      const request = await initialRetentionRequest({
        schema_version: 1,
        scan_id: scan,
        generation,
        evidence_digest: await initialEvidenceDigest(
          manifest,
          scan,
          generation,
        ),
        evidence_manifest: manifest,
      });
      const denied = async (
        action: () => Promise<unknown>,
        message?: string,
      ) => {
        await db.queryArray("SAVEPOINT deny");
        await assertRejects(action, Error, message);
        await db.queryArray(
          "ROLLBACK TO SAVEPOINT deny; RELEASE SAVEPOINT deny",
        );
      };
      const reserve = async (who = owner, value: unknown = request) =>
        (await db.queryObject<{ value: unknown }>(
          "SELECT internal.reserve_ordinary_initial_evidence($1,$2::jsonb) value",
          [who, JSON.stringify(value)],
        )).rows[0].value;
      const complete = async (object: string) =>
        (await db.queryObject<{ value: unknown }>(
          "SELECT internal.complete_ordinary_initial_evidence($1,$2::jsonb,$3) value",
          [owner, JSON.stringify(request), object],
        )).rows[0].value;
      const recoverAccepted = async (
        who = owner,
        candidate: unknown = request,
      ) =>
        (await db.queryObject<{ value: unknown }>(
          "SELECT public.recover_owned_initial_result($1,$2::jsonb) value",
          [who, JSON.stringify(candidate)],
        )).rows[0].value;
      await db.queryArray("BEGIN");
      try {
        await db.queryArray(
          "INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1::uuid,'authenticated','authenticated',$1::uuid::text||'@example.invalid','{}','{}',now(),now())",
          [owner],
        );
        await denied(() => reserve());
        await db.queryArray(
          'INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,media_counts) VALUES($1,$2,\'processing\',\'request_received\',\'{"image_count":1,"audio_count":0,"video_count":0,"required_video_count":0,"video_frame_count":0,"video_inference_frame_count":0}\')',
          [scan, owner],
        );
        const saveIntent = () =>
          db.queryArray(
            "INSERT INTO public.scan_ingestion_intents(scan_id,user_id,request_payload,payload_checksum) VALUES($1,$2,$3::jsonb,repeat('a',64))",
            [scan, owner, JSON.stringify({ initialEvidence: request })],
          );
        await denied(saveIntent);
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=true",
        );
        await db.queryArray("SAVEPOINT legacy_upgrade");
        await db.queryArray(
          "INSERT INTO public.scan_ingestion_intents(scan_id,user_id,request_payload,payload_checksum) VALUES($1,$2,'{}',repeat('a',64))",
          [scan, owner],
        );
        await denied(() =>
          db.queryArray(
            "UPDATE public.scan_ingestion_intents SET request_payload=$2::jsonb WHERE scan_id=$1",
            [scan, JSON.stringify({ initialEvidence: request })],
          ), "analysis_history_operation_conflict");
        await db.queryArray(
          "ROLLBACK TO SAVEPOINT legacy_upgrade; RELEASE SAVEPOINT legacy_upgrade",
        );
        await saveIntent();
        await denied(() =>
          db.queryArray(
            "UPDATE public.scan_ingestion_intents SET request_payload='{}' WHERE user_id=$1",
            [owner],
          )
        );
        await denied(() =>
          db.queryArray(
            "UPDATE public.scan_ingestion_jobs SET initial_evidence_generation=NULL WHERE user_id=$1",
            [owner],
          )
        );
        await db.queryArray(
          "SELECT set_config('request.jwt.claim.role','service_role',true)",
        );
        const assertLegacyReplayExcluded = async () => {
          await db.queryArray("SAVEPOINT replay_exclusion");
          await db.queryArray(
            "INSERT INTO internal.complimentary_scan_usage(user_id,client_scan_id) VALUES($1,$2)",
            [owner, scan],
          );
          for (const attempts of [0, 9, 10]) {
            await db.queryArray(
              "UPDATE public.scan_ingestion_jobs SET status='finalizing',lock_expires_at=now()-interval '1 minute' WHERE scan_id=$1",
              [scan],
            );
            await db.queryArray(
              "UPDATE public.scan_ingestion_intents SET resumable=true,inline_media_redacted=false,replay_attempt_count=$2 WHERE scan_id=$1",
              [scan, attempts],
            );
            const snapshot = async () =>
              (await db.queryObject<{ value: unknown }>(
                "SELECT jsonb_build_object('job',to_jsonb(j),'intent',to_jsonb(i),'funding',to_jsonb(f)) value FROM public.scan_ingestion_jobs j JOIN public.scan_ingestion_intents i USING(scan_id,user_id) JOIN internal.complimentary_scan_usage f ON f.user_id=j.user_id AND f.client_scan_id=j.scan_id::uuid WHERE j.scan_id=$1",
                [scan],
              )).rows[0].value;
            const before = await snapshot();
            const claimed = await db.queryObject<{ scan_id: string }>(
              "SELECT * FROM public.claim_replayable_scan_ingestion_jobs(50,300)",
            );
            assertEquals(
              claimed.rows.some((row) => row.scan_id === scan),
              false,
            );
            assertEquals(await snapshot(), before);
            // A stale worker that already decided to give up must recheck under
            // settlement locks, not bypass the batch exclusion by calling the RPC.
            for (
              const reason of [
                "replay_exhausted",
                "media_reconciliation_abandoned",
              ]
            ) {
              await denied(() =>
                db.queryArray(
                  "SELECT public.fail_scan_ingestion_terminal($1,$2,'server_replay_limit_reached','Synthetic retry exhaustion',$3)",
                  [scan, owner, reason],
                ), "initial_evidence_recovery_required");
              assertEquals(await snapshot(), before);
            }
          }
          await db.queryArray(
            "ROLLBACK TO SAVEPOINT replay_exclusion; RELEASE SAVEPOINT replay_exclusion",
          );
        };
        // Fence the request even before retention creates its durable identity.
        await assertLegacyReplayExcluded();
        const result = {
          scan_id: scan,
          is_biological_subject: false,
          confidence_score: 0.2,
          inference_tier: "flash",
          ai_reasoning: null,
        };
        const insertResult = async () => {
          await db.queryArray(
            "INSERT INTO public.scans(id,user_id,ai_confidence_score,is_biological_subject,inference_tier,image_storage_urls) VALUES($1,$2,0.2,false,'flash',ARRAY['https://media.merian.app/synthetic-test.jpg'])",
            [scan, owner],
          );
          await db.queryArray(
            "INSERT INTO internal.complimentary_scan_usage(user_id,client_scan_id) VALUES($1,$2)",
            [owner, scan],
          );
        };
        await db.queryArray("SAVEPOINT missing_evidence");
        await insertResult();
        const finalize = async () =>
          (await db.queryObject<
            { value: { response_envelope: { initial_evidence: unknown } } }
          >(
            "SELECT public.complete_scan_ingestion_with_entitlement($1,$2,$3::jsonb,'{}','{}') value",
            [
              scan,
              owner,
              JSON.stringify({ success: true, data: result }),
            ],
          )).rows[0].value;
        await denied(finalize);
        assertEquals(
          (await db.queryObject<{ state: string }>(
            "SELECT state FROM internal.complimentary_scan_usage WHERE user_id=$1",
            [owner],
          )).rows[0].state,
          "held",
        );
        assertEquals(
          (await db.queryObject<{ status: string }>(
            "SELECT status FROM public.scan_ingestion_jobs WHERE user_id=$1",
            [owner],
          )).rows[0].status,
          "processing",
        );
        await db.queryArray(
          "ROLLBACK TO SAVEPOINT missing_evidence; RELEASE SAVEPOINT missing_evidence",
        );
        let receipt = parseInitialRetentionReceipt(
          await reserve(),
          owner,
          request,
        );
        // The new table must not disable all merges, but its immutable owner
        // cannot be rewritten by a merge that actually contains these records.
        await db.queryArray(
          "SELECT internal.assert_ghost_profile_merge_reference_policy_coverage()",
        );
        await db.queryArray(
          "SELECT internal.assert_ghost_profile_merge_reference_preconditions($1)",
          [crypto.randomUUID()],
        );
        await db.queryArray("SAVEPOINT merge_owner");
        await assertRejects(
          () =>
            db.queryArray(
              "SELECT internal.assert_ghost_profile_merge_reference_preconditions($1)",
              [owner],
            ),
          Error,
          "ghost_merge_preserved_reference_present: internal.ordinary_initial_evidence.owner_id",
        );
        await db.queryArray(
          "ROLLBACK TO SAVEPOINT merge_owner; RELEASE SAVEPOINT merge_owner",
        );
        assertEquals(receipt.items.length, 2);
        assertEquals(receipt.items.map((x) => x.ready), [false, false]);
        await denied(() => recoverAccepted());
        assertEquals(
          parseInitialRetentionReceipt(await reserve(), owner, request),
          receipt,
        );
        await denied(() => reserve(crypto.randomUUID()));
        await denied(() =>
          reserve(owner, { ...request, evidence_digest: "b".repeat(64) })
        );
        await denied(() => complete(crypto.randomUUID()));
        await denied(() =>
          db.queryArray(
            "UPDATE internal.ordinary_initial_evidence SET evidence_digest=repeat('b',64) WHERE scan_id=$1",
            [scan],
          )
        );
        await denied(() =>
          db.queryArray(
            "UPDATE internal.ordinary_initial_evidence_objects SET object_id=gen_random_uuid() WHERE scan_id=$1",
            [scan],
          )
        );
        // Acceptance survives rollout closure. It does not allocate new identities.
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=false",
        );
        for (const item of receipt.items) {
          receipt = parseInitialRetentionReceipt(
            await complete(item.object_id),
            owner,
            request,
            receipt,
          );
        }
        assertEquals(receipt.items.map((x) => x.ready), [true, true]);
        await denied(() =>
          db.queryArray(
            "UPDATE internal.ordinary_initial_evidence_objects SET ready_at=NULL WHERE scan_id=$1",
            [scan],
          )
        );
        for (const role of ["anon", "authenticated", "service_role"]) {
          await db.queryArray(`SET LOCAL ROLE ${role}`);
          await denied(() => reserve());
          await denied(() =>
            db.queryArray("SELECT * FROM internal.ordinary_initial_evidence")
          );
          await db.queryArray("RESET ROLE");
        }
        // Lost rows cannot authorize replacement storage for the same allocation.
        await db.queryArray("SAVEPOINT lost_object");
        await db.queryArray(
          "DELETE FROM internal.ordinary_initial_evidence_objects WHERE object_id=$1",
          [receipt.items[0].object_id],
        );
        await denied(() => reserve());
        assertEquals(
          (await db.queryObject<{ n: number }>(
            "SELECT count(*)::int n FROM internal.observation_evidence_erasure WHERE object_id=$1",
            [receipt.items[0].object_id],
          )).rows[0].n,
          1,
        );
        await db.queryArray(
          "ROLLBACK TO SAVEPOINT lost_object; RELEASE SAVEPOINT lost_object",
        );
        const bindResult = async (value: unknown = result) =>
          (await db.queryObject<{ value: string }>(
            "SELECT public.bind_owned_initial_result($1,$2::jsonb,$3::jsonb,NULL) value",
            [owner, JSON.stringify(request), JSON.stringify(value)],
          )).rows[0].value;
        for (const tier of [null, undefined, 1, true, {}, [], "unknown"]) {
          await denied(() => bindResult({ ...result, inference_tier: tier }));
        }
        assertEquals(await recoverAccepted(), null);
        const boundDigest = await bindResult();
        const accepted = {
          schema_version: 1,
          owner_id: owner,
          scan_id: scan,
          generation,
          evidence_digest: request.evidence_digest,
          result,
          species_id: null,
          result_digest: boundDigest,
        };
        assertEquals(await recoverAccepted(), accepted);
        // Real pruning triggers must retain the exact original operational
        // inputs until accepted-result finalization or explicit retirement.
        // No disabled-trigger fault fixture can prove this boundary.
        await db.queryArray("SAVEPOINT accepted_pruning");
        await db.queryArray(
          "INSERT INTO internal.complimentary_scan_usage(user_id,client_scan_id) VALUES($1,$2)",
          [owner, scan],
        );
        const beforePrune = (await db.queryObject(
          "SELECT to_jsonb(j) job,to_jsonb(i) intent,to_jsonb(f) funding FROM public.scan_ingestion_jobs j JOIN public.scan_ingestion_intents i ON i.scan_id=j.scan_id AND i.user_id=j.user_id JOIN internal.complimentary_scan_usage f ON f.client_scan_id=j.scan_id::uuid AND f.user_id=j.user_id WHERE j.scan_id=$1",
          [scan],
        )).rows;
        assertEquals(beforePrune.length, 1);
        for (const table of ["scan_ingestion_intents", "scan_ingestion_jobs"]) {
          const deleted = await db.queryObject(
            `DELETE FROM public.${table} WHERE scan_id=$1 AND user_id=$2 RETURNING id`,
            [scan, owner],
          );
          assertEquals(deleted.rows.length, 0);
        }
        assertEquals(
          (await db.queryObject(
            "SELECT to_jsonb(j) job,to_jsonb(i) intent,to_jsonb(f) funding FROM public.scan_ingestion_jobs j JOIN public.scan_ingestion_intents i ON i.scan_id=j.scan_id AND i.user_id=j.user_id JOIN internal.complimentary_scan_usage f ON f.client_scan_id=j.scan_id::uuid AND f.user_id=j.user_id WHERE j.scan_id=$1",
            [scan],
          )).rows,
          beforePrune,
        );
        assertEquals(await recoverAccepted(), accepted);
        assertEquals(
          (await db.queryObject<{ n: number }>(
            "SELECT count(*)::int n FROM internal.observation_evidence_erasure WHERE object_id=ANY($1::uuid[])",
            [receipt.items.map((item) => item.object_id)],
          )).rows[0].n,
          0,
        );
        await db.queryArray(
          "ROLLBACK TO SAVEPOINT accepted_pruning; RELEASE SAVEPOINT accepted_pruning",
        );
        // Public profile cleanup precedes Auth deletion (users_id_fkey is
        // restrictive). The later Auth FK cascade must clear operational rows
        // even without the higher-level account-deletion job fixture.
        await db.queryArray("SAVEPOINT accepted_account_delete");
        await db.queryArray("DELETE FROM public.users WHERE id=$1", [owner]);
        await db.queryArray("DELETE FROM auth.users WHERE id=$1", [owner]);
        assertEquals(
          (await db.queryObject<{ remaining: number }>(
            "SELECT ((SELECT count(*) FROM public.scan_ingestion_jobs WHERE user_id=$1)+(SELECT count(*) FROM public.scan_ingestion_intents WHERE user_id=$1)+(SELECT count(*) FROM internal.ordinary_initial_evidence WHERE owner_id=$1))::int remaining",
            [owner],
          )).rows[0].remaining,
          0,
        );
        assertEquals(
          (await db.queryObject<{ n: number }>(
            "SELECT count(*)::int n FROM internal.observation_evidence_erasure WHERE object_id=ANY($1::uuid[])",
            [receipt.items.map((item) => item.object_id)],
          )).rows[0].n,
          receipt.items.length,
        );
        await db.queryArray(
          "ROLLBACK TO SAVEPOINT accepted_account_delete; RELEASE SAVEPOINT accepted_account_delete",
        );
        // A bound result and held funding survive both ordinary claim and retry
        // exhaustion, even when the finalization lease has expired.
        await assertLegacyReplayExcluded();
        await denied(() => recoverAccepted(crypto.randomUUID()));
        await denied(() =>
          recoverAccepted(owner, {
            ...request,
            generation: crypto.randomUUID(),
          })
        );
        await denied(() =>
          recoverAccepted(owner, {
            ...request,
            evidence_digest: "b".repeat(64),
          })
        );
        await db.queryArray("SAVEPOINT lost_recovery_artifact");
        await db.queryArray(
          "DELETE FROM internal.ordinary_initial_evidence_objects WHERE object_id=$1",
          [receipt.items[0].object_id],
        );
        await denied(() => recoverAccepted());
        await db.queryArray(
          "ROLLBACK TO SAVEPOINT lost_recovery_artifact; RELEASE SAVEPOINT lost_recovery_artifact",
        );
        assertEquals(await bindResult(), boundDigest);
        await denied(() => bindResult({ ...result, confidence_score: 0.8 }));
        // Provider acceptance alone is not a completed scan. A terminal job
        // retires even an accepted-but-unsealed result and owns byte erasure.
        await db.queryArray("SAVEPOINT accepted_terminal");
        await db.queryArray(
          "UPDATE public.scan_ingestion_jobs SET status='failed_terminal' WHERE scan_id=$1 AND user_id=$2",
          [scan, owner],
        );
        assertEquals(
          (await db.queryObject<
            { retired: boolean; sealed: boolean; accepted: boolean }
          >(
            "SELECT retired_at IS NOT NULL retired, sealed_at IS NOT NULL sealed, accepted_result IS NOT NULL accepted FROM internal.ordinary_initial_evidence WHERE scan_id=$1",
            [scan],
          )).rows[0],
          { retired: true, sealed: false, accepted: true },
        );
        assertEquals(
          (await db.queryObject<{ n: number }>(
            "SELECT count(*)::int n FROM internal.observation_evidence_erasure WHERE object_id=ANY($1::uuid[])",
            [receipt.items.map((item) => item.object_id)],
          )).rows[0].n,
          receipt.items.length,
        );
        await denied(() => reserve());
        await denied(() => bindResult());
        await denied(() => recoverAccepted());
        await db.queryArray(
          "ROLLBACK TO SAVEPOINT accepted_terminal; RELEASE SAVEPOINT accepted_terminal",
        );
        await insertResult();
        // A delayed finalizer must neither adopt a mutated scan projection nor
        // consume funding when it cannot prove the original result.
        await db.queryArray("SAVEPOINT changed_projection");
        await db.queryArray(
          "UPDATE public.scans SET ai_confidence_score=0.9 WHERE id=$1",
          [scan],
        );
        await denied(finalize);
        assertEquals(
          (await db.queryObject<{ state: string }>(
            "SELECT state FROM internal.complimentary_scan_usage WHERE user_id=$1",
            [owner],
          )).rows[0].state,
          "held",
        );
        await db.queryArray(
          "ROLLBACK TO SAVEPOINT changed_projection; RELEASE SAVEPOINT changed_projection",
        );
        // Geometry V9 alone must not reclassify direct photo evidence as a private-stage upload.
        assertEquals(
          (await db.queryObject<{ origin: string | null }>(
            "SELECT private_capture_request_sha256 origin FROM internal.ordinary_initial_evidence WHERE scan_id=$1",
            [scan],
          )).rows[0].origin,
          null,
        );
        // A completed server proof, not a receipt, is the durable enrollment input.
        const final = await finalize();
        const recover = async (who = owner) =>
          (await db.queryObject<{ value: unknown }>(
            "SELECT public.recover_owned_initial_completion($1,$2) value",
            [who, scan],
          )).rows[0].value;
        assertEquals(final.response_envelope.initial_evidence, {
          schema_version: 1,
          owner_id: owner,
          scan_id: scan,
          generation,
          evidence_digest: request.evidence_digest,
        });
        assertEquals(
          (await finalize()).response_envelope,
          final.response_envelope,
        );
        assertEquals(await recover(), final.response_envelope);
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET reader_enabled=true,state_reader_enabled=true,media_reader_enabled=true,enrollment_enabled=true,ordinary_initial_evidence_enabled=true",
        );
        await db.queryArray(
          "SELECT set_config('request.jwt.claim.sub',$1,true)",
          [owner],
        );
        const currentReader = manifestVersion === 9
          ? 18
          : manifestVersion === 8
          ? 17
          : 16;
        const currentProtocol = manifestVersion >= 8 ? 4 : 3;
        const enroll = async (reader = currentReader) =>
          (await db.queryObject<{ value: { baseline_analysis_id: string } }>(
            "SELECT public.enroll_owned_observation_history($1,$2) value",
            [scan, reader],
          )).rows[0].value;
        await denied(() => enroll(9));
        if (manifestVersion >= 8) await denied(() => enroll(16));
        if (manifestVersion === 9) await denied(() => enroll(17));
        const association = await enroll();
        assert(
          ![owner, scan, generation].some((id) =>
            id === association.baseline_analysis_id
          ),
        );
        assertEquals(await enroll(), association);
        const baseline = (await db.queryObject<{ value: string }>(
          "SELECT internal.observation_result_snapshot(r) value FROM internal.observation_analysis_results r WHERE analysis_id=$1",
          [association.baseline_analysis_id],
        )).rows[0].value;
        const decodedBaseline = JSON.parse(baseline);
        assertEquals(decodedBaseline.schema_version, 8);
        assertEquals(decodedBaseline.source_analysis_id, null);
        assertEquals(decodedBaseline.ordinal, 1);
        assertEquals(
          decodedBaseline.initial_evidence,
          final.response_envelope.initial_evidence,
        );
        assertEquals(decodedBaseline.evidence_manifest, manifest);
        assertEquals(decodedBaseline.result, { ...result, species_id: null });
        const page = async (reader: number) =>
          (await db.queryObject<{ value: { items: { snapshot: string }[] } }>(
            "SELECT public.get_owned_observation_analysis_page($1::jsonb,$2) value",
            [
              JSON.stringify({
                schema_version: 1,
                observation_id: scan,
                before_ordinal: null,
                limit: 20,
              }),
              reader,
            ],
          )).rows[0].value;
        assertEquals((await page(currentReader)).items.map((x) => x.snapshot), [
          baseline,
        ]);
        for (
          const reader of [
            7,
            8,
            9,
            10,
            11,
            13,
            14,
            15,
            ...(manifestVersion >= 8 ? [16] : []),
            ...(manifestVersion === 9 ? [17] : []),
          ]
        ) {
          await denied(() => page(reader));
        }
        const selection = (await db.queryObject<
          {
            value: {
              baseline_state: { analysis: { snapshot: string } };
              selected_state: { analysis: { snapshot: string } };
            };
          }
        >(
          "SELECT public.get_owned_observation_enrollment_selection($1::jsonb,$2) value",
          [
            JSON.stringify({ schema_version: 1, observation_id: scan }),
            currentReader,
          ],
        )).rows[0].value;
        assertEquals(selection.baseline_state.analysis.snapshot, baseline);
        assertEquals(selection.selected_state.analysis.snapshot, baseline);
        const resolve = async (
          media: string,
          protocol = currentProtocol,
          who = owner,
        ) =>
          (await db.queryObject<
            {
              value: {
                schema_version: number;
                expires_at: null;
                media_id: string;
                object_id: string;
              };
            }
          >(
            "SELECT public.resolve_owned_observation_media($1,$2,$3,$4,$5) value",
            [who, scan, association.baseline_analysis_id, media, protocol],
          )).rows[0].value;
        for (
          const item of [manifest.items[0].source, manifest.items[0].prepared]
        ) {
          const receipt = await resolve(item.media_id);
          assertEquals(receipt.schema_version, manifestVersion >= 8 ? 3 : 2);
          assertEquals(receipt.expires_at, null);
          assertEquals(receipt.media_id, item.media_id);
          for (
            const protocol of [1, 2, ...(manifestVersion >= 8 ? [3] : [])]
          ) {
            await denied(() => resolve(item.media_id, protocol));
          }
          await denied(() =>
            resolve(item.media_id, currentProtocol, crypto.randomUUID())
          );
        }
        await denied(() => resolve(crypto.randomUUID()));
        await db.queryArray("SAVEPOINT missing_retained_source");
        await db.queryArray(
          "DELETE FROM internal.ordinary_initial_evidence_objects WHERE scan_id=$1 AND role='source_image'",
          [scan],
        );
        await denied(() => resolve(manifest.items[0].prepared.media_id));
        await db.queryArray(
          "ROLLBACK TO SAVEPOINT missing_retained_source; RELEASE SAVEPOINT missing_retained_source",
        );
        // Replaying enrollment after projection edits preserves the original result.
        await db.queryArray(
          "UPDATE public.scans SET ai_confidence_score=0.7 WHERE id=$1",
          [scan],
        );
        assertEquals(await enroll(), association);
        assertEquals(
          (await db.queryObject<{ value: string }>(
            "SELECT internal.observation_result_snapshot(r) value FROM internal.observation_analysis_results r WHERE analysis_id=$1",
            [association.baseline_analysis_id],
          )).rows[0].value,
          baseline,
        );
        for (const role of ["anon", "authenticated"]) {
          await db.queryArray(`SET LOCAL ROLE ${role}`);
          await denied(() => recover());
          await denied(() => recoverAccepted());
          await denied(() =>
            db.queryArray(
              "SELECT public.reserve_owned_initial_evidence($1,$2::jsonb)",
              [owner, JSON.stringify(request)],
            )
          );
          await denied(() =>
            db.queryArray(
              "SELECT public.complete_owned_initial_evidence($1,$2::jsonb,$3)",
              [owner, JSON.stringify(request), receipt.items[0].object_id],
            )
          );
          await db.queryArray("RESET ROLE");
        }
        assertEquals(
          (await db.queryObject<{ state: string }>(
            "SELECT state FROM internal.complimentary_scan_usage WHERE user_id=$1",
            [owner],
          )).rows[0].state,
          "consumed",
        );
        await db.queryArray(
          "DELETE FROM public.scan_ingestion_intents WHERE user_id=$1",
          [owner],
        );
        await db.queryArray(
          "DELETE FROM public.scan_ingestion_jobs WHERE user_id=$1",
          [owner],
        );
        assertEquals(
          parseInitialRetentionReceipt(await reserve(), owner, request),
          receipt,
        );
        await db.queryArray("SET LOCAL ROLE service_role");
        assertEquals(await recover(), final.response_envelope);
        assertEquals(await recoverAccepted(), accepted);
        await db.queryArray("RESET ROLE");
        await denied(() =>
          db.queryArray(
            "UPDATE internal.ordinary_initial_evidence SET completion_response='{\"changed\":true}' WHERE scan_id=$1",
            [scan],
          )
        );
        await db.queryArray(
          "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
          [scan, owner],
        );
        await denied(() => reserve());
        await denied(() => recover());
        await denied(() => recoverAccepted());
        await denied(() => resolve(manifest.items[0].prepared.media_id));
        assertEquals(
          (await db.queryObject<{ n: number }>(
            "SELECT count(*)::int n FROM internal.observation_evidence_erasure WHERE object_id=ANY($1::uuid[])",
            [receipt.items.map((x) => x.object_id)],
          )).rows[0].n,
          2,
        );
      } finally {
        await db.queryArray("ROLLBACK");
        await db.end();
      }
    },
  });
}

Deno.test({
  name:
    "ordinary initial scheduler updates do not invert retention job and intent locks",
  ignore: !url,
  async fn() {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    const setup = new Client(url),
      retention = new Client(url),
      scheduler = new Client(url);
    await Promise.all([
      setup.connect(),
      retention.connect(),
      scheduler.connect(),
    ]);
    const owner = crypto.randomUUID(),
      scan = crypto.randomUUID(),
      generation = crypto.randomUUID();
    const artifact = () => ({
      media_id: crypto.randomUUID(),
      content_type: "image/jpeg",
      byte_count: 100,
      sha256: "b".repeat(64),
    });
    const manifest = {
      schema_version: 7,
      items: [{
        kind: "image",
        source: artifact(),
        prepared: artifact(),
        coordinate_basis: "prepared_image_top_left_v1",
        focus_region: null,
      }],
    };
    const request = await initialRetentionRequest({
      schema_version: 1,
      scan_id: scan,
      generation,
      evidence_digest: await initialEvidenceDigest(manifest, scan, generation),
      evidence_manifest: manifest,
    });
    try {
      await setup.queryArray("BEGIN");
      await setup.queryArray(
        "INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1::uuid,'authenticated','authenticated',$1::uuid::text||'@example.invalid','{}','{}',now(),now())",
        [owner],
      );
      await setup.queryArray(
        'INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,media_counts) VALUES($1,$2,\'processing\',\'request_received\',\'{"image_count":1,"audio_count":0,"video_count":0,"required_video_count":0,"video_frame_count":0,"video_inference_frame_count":0}\')',
        [scan, owner],
      );
      const old = (await setup.queryObject<{ enabled: boolean }>(
        "SELECT ordinary_initial_evidence_enabled enabled FROM internal.observation_history_rollout FOR UPDATE",
      )).rows[0].enabled;
      await setup.queryArray(
        "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=true",
      );
      await setup.queryArray(
        "INSERT INTO public.scan_ingestion_intents(scan_id,user_id,request_payload,payload_checksum) VALUES($1,$2,$3::jsonb,repeat('b',64))",
        [scan, owner, JSON.stringify({ initialEvidence: request })],
      );
      await setup.queryArray(
        "UPDATE internal.observation_history_rollout SET ordinary_initial_evidence_enabled=$1",
        [old],
      );
      await setup.queryArray("COMMIT");
      await retention.queryArray(
        "BEGIN; SET LOCAL lock_timeout='2s'; SET LOCAL statement_timeout='3s'",
      );
      await scheduler.queryArray(
        "BEGIN; SET LOCAL lock_timeout='2s'; SET LOCAL statement_timeout='3s'",
      );
      await scheduler.queryArray(
        "SELECT id FROM public.scan_ingestion_intents WHERE scan_id=$1 FOR UPDATE",
        [scan],
      );
      await retention.queryArray(
        "SELECT id FROM public.scan_ingestion_jobs WHERE scan_id=$1 FOR UPDATE",
        [scan],
      );
      // Retention holds the job while the scheduler already owns the intent.
      // The old trigger blocks here until lock_timeout; the corrected trigger
      // updates only the counter, allowing retention to acquire the intent next.
      await scheduler.queryArray(
        "UPDATE public.scan_ingestion_intents SET replay_attempt_count=replay_attempt_count+1 WHERE scan_id=$1",
        [scan],
      );
      await scheduler.queryArray("COMMIT");
      const count = (await retention.queryObject<{ count: number }>(
        "SELECT replay_attempt_count count FROM public.scan_ingestion_intents WHERE scan_id=$1 FOR UPDATE",
        [scan],
      )).rows[0].count;
      assertEquals(count, 1);
      await retention.queryArray("COMMIT");
    } finally {
      await Promise.allSettled([
        retention.queryArray("ROLLBACK"),
        scheduler.queryArray("ROLLBACK"),
        setup.queryArray("ROLLBACK"),
      ]);
      await setup.queryArray("DELETE FROM public.users WHERE id=$1", [owner]);
      await setup.queryArray("DELETE FROM auth.users WHERE id=$1", [owner]);
      await Promise.all([setup.end(), retention.end(), scheduler.end()]);
    }
  },
});
