import { assert, assertEquals } from "@std/assert";

Deno.test("prepared audio stages retain private ownership and deletion obligations without activating submission", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261120195723_prepare_initial_capture_audio_stages.sql",
      import.meta.url,
    ),
  );
  for (
    const table of [
      "initial_capture_audio_stages",
      "initial_capture_audio_stage_objects",
      "initial_capture_audio_stage_erasure",
    ]
  ) {
    assert(
      sql.includes(`ALTER TABLE internal.${table} ENABLE ROW LEVEL SECURITY`),
    );
  }
  assert(sql.includes("PERFORM internal.require_service_role()"));
  assert(
    sql.includes(
      "SECURITY DEFINER SET search_path='' SET statement_timeout='10s'",
    ),
  );
  assert(
    sql.includes(
      "encode(extensions.digest(convert_to(p_request,'UTF8'),'sha256'),'hex') IS DISTINCT FROM p_sha256",
    ),
  );
  assert(sql.includes("saved.request_body IS DISTINCT FROM body"));
  assert(sql.includes("saved.backend_sha256<>p_backend"));
  assert(
    sql.indexOf("merian-capture-account-retirement:") <
      sql.indexOf("PERFORM id FROM public.users"),
  );
  assert(
    sql.indexOf("PERFORM id FROM public.users") <
      sql.indexOf("merian-scan-ingestion:"),
  );
  assert(
    sql.includes(
      "IF obj.write_issued_at IS NOT NULL THEN RETURN 'false'::JSONB",
    ),
  );
  assert(
    sql.includes("INSERT INTO internal.initial_capture_audio_stage_erasure"),
  );
  assertEquals(
    (sql.match(/CREATE TRIGGER retire_initial_capture_audio_stage/g) ?? [])
      .length,
    3,
  );
  assert(
    sql.includes(
      "internal.prepare_scan_ingestions_for_identity_merge(uuid,uuid)",
    ),
  );
  assert(
    !/INSERT INTO public.scan_media_assets|INSERT INTO public.scan_ingestion|cron\.schedule|UPDATE internal.observation_history_rollout/
      .test(sql),
  );
  const repair = await Deno.readTextFile(
    new URL(
      "../../migrations/20261120200525_repair_capture_stage_deletion_trigger.sql",
      import.meta.url,
    ),
  );
  assert(repair.includes("IF TG_TABLE_NAME='users' THEN target:=OLD.id;"));
  assert(repair.includes("ELSE target:=NEW.user_id; END IF;"));
});
Deno.test("typed stage cleanup extends the existing dispatcher without activation or legacy namespace leakage", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261120200815_integrate_capture_stage_private_erasure.sql",
      import.meta.url,
    ),
  );
  assert(
    sql.includes(
      "PERFORM internal.require_observation_evidence_dispatch(p_dispatch_id)",
    ),
  );
  assert(sql.includes("ORDER BY available_at,kind,object_id LIMIT 1"));
  assert(sql.includes("FOR UPDATE SKIP LOCKED"));
  assert(
    sql.includes("claim_expires_at=clock_timestamp()+interval '60 seconds'"),
  );
  assert(sql.includes("backend_sha256=p_backend AND claim_token=p_claim"));
  assert(
    sql.includes("claim_expires_at>clock_timestamp() AND erased_at IS NULL"),
  );
  const finish = sql.slice(
    sql.indexOf("CREATE FUNCTION public.finish_private_evidence_erasure_v4"),
    sql.indexOf("REVOKE ALL ON FUNCTION public.claim_private"),
  );
  assert(finish.includes("PERFORM internal.require_service_role()"));
  assert(!finish.includes("require_observation_evidence_dispatch"));
  assert(sql.includes("last_receipt_schema_version IN(2,3,4)"));
  assert(sql.includes("'capture_stage',stage_queue"));
  assert(
    !/CREATE OR REPLACE FUNCTION public.claim_observation_evidence_erasure|cron\.schedule|SET enabled|UPDATE internal.observation_history_rollout/
      .test(sql),
  );
});

Deno.test("private capture successors keep grants closed and reuse admission and retirement owners", async () => {
  const client = await Deno.readTextFile(
    new URL(
      "../../migrations/20261120203942_extend_private_capture_stage_client_inventory.sql",
      import.meta.url,
    ),
  );
  const admission = await Deno.readTextFile(
    new URL(
      "../../migrations/20261120205233_seal_private_capture_stage_admission.sql",
      import.meta.url,
    ),
  );
  const adoption = await Deno.readTextFile(
    new URL(
      "../../migrations/20261120202921_adopt_capture_audio_stage_after_retention.sql",
      import.meta.url,
    ),
  );
  assert(
    client.includes(
      "ALTER TABLE internal.initial_capture_client_stage_objects ENABLE ROW LEVEL SECURITY",
    ),
  );
  assert(!client.includes("GRANT ALL"));
  assert(client.includes("FROM PUBLIC,anon,authenticated,service_role"));
  assert(
    admission.includes(
      "PERFORM internal.assert_initial_capture_client_stage(p_scan,true)",
    ),
  );
  assert(
    admission.includes(
      "PERFORM internal.assert_initial_capture_audio_retention(p_owner,request)",
    ),
  );
  assert(admission.includes("INSERT INTO internal.capture_source_admissions"));
  assert(!/CREATE TABLE|GRANT EXECUTE/.test(admission));
  assert(
    adoption.indexOf(
      "PERFORM internal.assert_initial_capture_audio_retention(p_saved.owner_id",
    ) <
      adoption.indexOf(
        "IF stage.scan_id IS NULL OR stage.adopted_evidence_digest",
      ),
  );
  for (const sql of [client, admission, adoption]) {
    assert(
      !/cron\.schedule|UPDATE internal.observation_history_rollout|INSERT INTO public.scan_media_assets/
        .test(sql),
    );
  }
});
