import { assert, assertStringIncludes } from "@std/assert";

const migration = (name: string) =>
  Deno.readTextFile(new URL(`../../migrations/${name}.sql`, import.meta.url));

Deno.test("history preparation cannot accidentally activate a public writer", async () => {
  const storage = await migration(
    "20261002213257_prepare_observation_analysis_history",
  );
  const selection = await migration(
    "20261002215809_prepare_observation_selection_transactions",
  );
  assertStringIncludes(
    storage,
    "enrollment_enabled BOOLEAN NOT NULL DEFAULT FALSE",
  );
  assertStringIncludes(
    selection,
    "selection_enabled BOOLEAN NOT NULL DEFAULT FALSE",
  );
  assertStringIncludes(storage, "WHERE singleton) IS NOT TRUE");
  assertStringIncludes(selection, "WHERE singleton) IS NOT TRUE");
  assert(!/GRANT\s+EXECUTE/i.test(storage + selection));
  assert(!/CREATE(?: OR REPLACE)? FUNCTION public\./.test(storage + selection));
});

Deno.test("legacy deletion refusal precedes the irreversible generation fence", async () => {
  const route = await Deno.readTextFile(
    new URL("../delete-scan/index.ts", import.meta.url),
  );
  assertStringIncludes(
    route,
    "handleScanDeletion(scanId, user.id, supabaseAdmin)",
  );
  const sql = await migration(
    "20261002215330_protect_enrolled_observation_retention",
  );
  const rejection = sql.indexOf(
    "RETURN 'legacy_observation_delete_requires_upgrade'",
  );
  const fence = sql.indexOf("INSERT INTO internal.scan_deletion_tombstones");
  assert(rejection > 0 && rejection < fence);
  assertStringIncludes(sql, "IF scan_owner IS DISTINCT FROM p_user_id THEN");
  const retention = sql.slice(sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.request_nonbiological_scan_retention_deletions",
  ));
  assertEqualsCount(
    retention,
    "NOT EXISTS (SELECT 1 FROM internal.observation_histories WHERE observation_id = scans.id)",
    2,
  );
  const account = sql.slice(sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.apply_user_tombstone",
  ));
  assert(
    account.indexOf("WHERE users.id = target_user_id FOR UPDATE") <
      account.indexOf("UPDATE public.scans"),
  );
  const completion = sql.slice(
    sql.indexOf("CREATE OR REPLACE FUNCTION public.complete_scan_deletion"),
    sql.indexOf(
      "CREATE OR REPLACE FUNCTION public.request_nonbiological_scan_retention_deletions",
    ),
  );
  const ownerLock = completion.indexOf("WHERE users.id = p_user_id FOR UPDATE");
  assert(
    ownerLock > 0 && ownerLock < completion.indexOf("PG_ADVISORY_XACT_LOCK"),
  );
});

Deno.test("selection persists authority, receipt and reconciliation in one private transaction", async () => {
  const sql = await migration(
    "20261002215809_prepare_observation_selection_transactions",
  );
  assertStringIncludes(sql, "history.state_revision <> expected_revision");
  assertStringIncludes(sql, "authority.review_revision <> expected_review");
  assertStringIncludes(sql, "RETURN saved.receipt");
  assertStringIncludes(sql, "active_projection=projection");
  assertStringIncludes(
    sql,
    "INSERT INTO internal.observation_selection_receipts",
  );
  assertStringIncludes(
    sql,
    "INSERT INTO internal.observation_history_reconciliation",
  );
  // A prepared history transaction must never overwrite immutable original
  // evidence or independently implement complimentary-credit settlement.
  assert(
    !/UPDATE public\.scans|UPDATE internal\.complimentary_scan_usage/.test(sql),
  );
});

function assertEqualsCount(text: string, fragment: string, count: number) {
  assert(text.split(fragment).length - 1 === count);
}

Deno.test("prepared append is private, separately closed and never settles provider or user funding", async () => {
  const sql = await migration(
    "20261003043015_prepare_observation_analysis_append",
  );
  for (
    const fragment of [
      "append_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "REVOKE ALL ON FUNCTION internal.append_observation_analysis(UUID, JSONB)",
      "saved.result_snapshot IS DISTINCT FROM p_request -> 'result_snapshot'",
      "saved.evidence_manifest IS DISTINCT FROM p_request -> 'evidence_manifest'",
      "IF NOT history.selection_initialized THEN",
      "INSERT INTO internal.observation_analysis_authorities",
      "No media variant can pass until protected promotion/read/cleanup exists",
    ]
  ) assertStringIncludes(sql, fragment);
  assert(
    !/GRANT\s+EXECUTE|CREATE(?: OR REPLACE)? FUNCTION public\./i.test(sql),
  );
  assert(
    !/UPDATE (public\.scans|internal\.complimentary_scan_usage|public\.scan_ingestion_jobs)/
      .test(sql),
  );
  assert(
    sql.indexOf("WHERE users.id=p_user_id FOR UPDATE") <
      sql.indexOf("PG_ADVISORY_XACT_LOCK"),
  );
  assert(
    sql.indexOf("internal.scan_deletion_tombstones") <
      sql.indexOf("RETURN internal.observation_analysis_snapshot"),
  );
});

Deno.test("owner history reader is separately held, bounded and cannot enroll or select", async () => {
  const sql = await migration(
    "20261003034325_prepare_owner_analysis_history_reader",
  );
  for (
    const fragment of [
      "reader_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "caller UUID := auth.uid()",
      "scan.user_id = caller AND NOT scan.is_tombstoned",
      "internal.scan_deletion_tombstones",
      "ORDER BY ordinal DESC LIMIT page_limit + 1",
      "pg_catalog.OCTET_LENGTH(snapshot) > 1048576",
      "pg_catalog.OCTET_LENGTH(response::TEXT) > 4194304",
      "p_reader IS DISTINCT FROM 7",
    ]
  ) assertStringIncludes(sql, fragment);
  assert(
    !/UPDATE internal\.observation_histories|INSERT INTO internal\.observation_analysis_results/
      .test(sql),
  );
  assert(!/SET (enrollment_enabled|selection_enabled)/.test(sql));
  assert(
    sql.indexOf("WHERE users.id = caller FOR SHARE") <
      sql.indexOf("PG_ADVISORY_XACT_LOCK"),
  );
  assert(
    sql.indexOf("internal.scan_deletion_tombstones") <
      sql.indexOf("FOR result_row IN"),
  );
});

Deno.test("protected evidence has closed private entrypoints and durable erasure ownership", async () => {
  const sql = await migration(
    "20261003051251_prepare_private_observation_evidence",
  );
  for (
    const fragment of [
      "media_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "media_reader_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "CHECK(object_id NOT IN (owner_id,observation_id,analysis_id,media_id))",
      "CREATE TRIGGER enqueue_observation_evidence_erasure BEFORE DELETE",
      "CREATE TRIGGER fence_observation_evidence AFTER INSERT ON internal.scan_deletion_tombstones",
      "FOR UPDATE SKIP LOCKED LIMIT 1",
      "claim_token=p_claim AND claim_expires_at>clock_timestamp()",
      "FROM PUBLIC, anon, authenticated, service_role",
    ]
  ) assertStringIncludes(sql, fragment);
  assert(
    !/GRANT\s+EXECUTE|CREATE(?: OR REPLACE)? FUNCTION public\./i.test(sql),
  );
  const erasure =
    sql.split("CREATE TABLE internal.observation_evidence_erasure (")[1].split(
      "\n);",
    )[0];
  assert(
    !/REFERENCES|owner_id|observation_id|analysis_id|sha256/.test(erasure),
  );
});

Deno.test("funded child preparation remains private and preserves a permanent deletion namespace", async () => {
  const sql = await migration(
    "20261003054717_prepare_funded_observation_analysis",
  );
  for (
    const fragment of [
      "admission_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "dispatch_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "ALTER TABLE internal.observation_analysis_intents ENABLE ROW LEVEL SECURITY",
      "internal.settle_complimentary_analysis",
      "internal.complete_identification_usage(saved.invocation_id,",
      "analysis_history_admission_required",
      "analysis_history_dispatch_required",
      "analysis_history_completion_required",
      "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)",
      "VALUES(OLD.analysis_id,NULL,now())",
      "CREATE TRIGGER a_guard_history_child_scan_identity BEFORE INSERT ON public.scans",
      "CREATE TRIGGER guard_funded_observation_evidence BEFORE INSERT",
      "IF saved.state='complete' THEN RETURN saved.receipt",
      "saved.input_snapshot<>p_input",
      "history_settlement_source_drift",
    ]
  ) assertStringIncludes(sql, fragment);
  assert(
    !/GRANT\s+EXECUTE|CREATE(?: OR REPLACE)? FUNCTION public\./i.test(sql),
  );
  const complete = sql.slice(
    sql.indexOf("CREATE FUNCTION internal.complete_observation_analysis"),
    sql.indexOf("CREATE FUNCTION internal.fail_observation_analysis"),
  );
  assert(
    complete.indexOf("lock_owned_observation_evidence") <
      complete.indexOf("RETURN saved.receipt"),
  );
  assert(
    complete.indexOf("append_observation_analysis") <
      complete.indexOf("settle_complimentary_analysis"),
  );
  assert(
    complete.indexOf("settle_complimentary_analysis") <
      complete.indexOf("SET state='complete',receipt="),
  );
});

Deno.test("protected photo binding remains private, pinned and incompatible with V1 readers", async () => {
  const sql = await migration(
    "20261003063309_bind_protected_analysis_evidence",
  );
  for (
    const fragment of [
      "protected_analysis_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "internal.admit_protected_observation_analysis",
      "internal.append_protected_observation_analysis",
      "'multimodal_photo_v1'",
      "p_input->'history_protocol' IS DISTINCT FROM '8'",
      "saved.ready_at IS NULL",
      "'analysis_history_evidence_bound'",
      "NEW.state='failed_terminal'",
      "internal.expire_unbound_observation_evidence",
      "'analysis_history_reader_upgrade_required'",
      "CASE WHEN evidence->'schema_version'='2'::JSONB THEN 2 ELSE 1 END",
      "history_media_source_drift",
    ]
  ) assertStringIncludes(sql, fragment);
  assert(!/GRANT\s+EXECUTE/.test(sql));
  assert(!/UPDATE internal\.complimentary_scan_usage/.test(sql));
  assert(!/CREATE(?: OR REPLACE)? FUNCTION public\./.test(sql));
});

Deno.test("protocol 8 owner reader preserves legacy refusal and gates completed-photo service resolution", async () => {
  const sql = await migration("20261003070545_prepare_protocol8_history_reads");
  for (
    const fragment of [
      "p_reader NOT IN (7,8)",
      "IF p_reader=7 AND EXISTS",
      "internal.require_service_role()",
      "reader_enabled AND media_reader_enabled",
      "internal.lock_owned_observation_evidence(p_owner,p_observation)",
      "internal.observation_analysis_results",
      "receipt->'sha256' IS DISTINCT FROM item->'sha256'",
      "TO service_role",
      "history_reader_source_drift",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assert(!/SET (?:reader_enabled|media_reader_enabled)=TRUE/.test(sql));
});

Deno.test("history worker access stays closed and recovery cannot re-admit uncertain executions", async () => {
  const sql = await migration(
    "20261003074429_prepare_observation_analysis_recovery",
  );
  assertStringIncludes(
    sql,
    "orchestration_enabled BOOLEAN NOT NULL DEFAULT FALSE",
  );
  assertStringIncludes(sql, "FROM PUBLIC,anon,authenticated,service_role");
  assertStringIncludes(sql, "internal.require_service_role()");
  assertStringIncludes(sql, "saved.work_expires_at<=clock_timestamp()");
  assertStringIncludes(
    sql,
    "IS DISTINCT FROM saved.provider_outcome#>'{outcome,result}'",
  );
  const recovery =
    sql.split("CREATE FUNCTION public.claim_observation_analysis_recovery")[1]
      .split("CREATE FUNCTION public.advance_owned_observation_analysis")[0];
  assertStringIncludes(
    recovery,
    "state='dispatched' AND provider_outcome IS NOT NULL",
  );
  assert(!recovery.includes("admit_observation_analysis("));
  assert(!recovery.includes("dispatch_observation_analysis("));
  assert(!/SET orchestration_enabled=TRUE/.test(sql));
});

Deno.test("saved enrollment is owner derived, default off, evidence honest and replay never reselects", async () => {
  const sql = await migration(
    "20261003152940_prepare_saved_identification_enrollment",
  );
  for (
    const fragment of [
      "saved_import_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "caller UUID:=auth.uid()",
      "reader_enabled",
      "enrollment_enabled AND saved_import_enabled",
      "request_digest IS NULL AND completed_at IS NULL",
      "ELSE FALSE END) IS TRUE",
      "initial_selection_permitted) VALUES(p_observation,FALSE)",
      "'origin','saved_identification'",
      "'availability','unavailable'",
      "p_reader<9 AND EXISTS",
      "analysis_history_reader_upgrade_required",
      "FROM PUBLIC,anon,authenticated,service_role",
      "TO authenticated",
      "VALUES(OLD.analysis_id,NULL,pg_catalog.now())",
    ]
  ) assertStringIncludes(sql, fragment);
  assert(
    !/UPDATE public.scans|settle_complimentary_analysis|SET saved_import_enabled=TRUE/
      .test(sql),
  );
  const replay = sql.slice(
    sql.indexOf("IF FOUND THEN"),
    sql.indexOf("enrollment_enabled AND"),
  );
  assert(!/UPDATE|INSERT/.test(replay));
  assert(
    sql.indexOf("WHERE users.id=caller FOR UPDATE") <
      sql.indexOf("pg_advisory_xact_lock"),
  );
});

Deno.test("owner state read is separately held and binds preview authority under the observation fence", async () => {
  const sql = await migration(
    "20261003162801_prepare_owner_observation_state_read",
  );
  for (
    const fragment of [
      "state_reader_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "caller UUID := auth.uid()",
      "reader_enabled AND state_reader_enabled",
      "p_reader IS DISTINCT FROM 9",
      "WHERE users.id=caller FOR SHARE",
      "internal.scan_deletion_tombstones",
      "target := COALESCE(target,history.selected_analysis_id)",
      "WHERE observation_id=observation AND analysis_id=target",
      "'review_revision',authority.review_revision",
      "'snapshot',snapshot",
      "FROM PUBLIC, anon, authenticated, service_role",
      "TO authenticated",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assert(
    sql.indexOf("WHERE users.id=caller FOR SHARE") <
      sql.indexOf("PG_ADVISORY_XACT_LOCK"),
  );
  assert(
    !/UPDATE |DELETE FROM|SET state_reader_enabled=TRUE|select_observation_analysis\(/
      .test(sql),
  );
});

Deno.test("owner selection wraps only semantic conflicts, keeps recovery ahead of gates and retains private grants", async () => {
  const sql = await migration(
    "20261003221730_prepare_owned_observation_selection",
  );
  assertStringIncludes(
    sql,
    "selection_api_enabled BOOLEAN NOT NULL DEFAULT FALSE",
  );
  assertStringIncludes(sql, "caller UUID := auth.uid()");
  assertStringIncludes(sql, "p_reader IS DISTINCT FROM 9");
  assertStringIncludes(sql, "pg_catalog.octet_length(p_request::TEXT) > 2048");
  const owner = sql.indexOf("WHERE users.id=caller FOR UPDATE");
  const fence = sql.indexOf("internal.scan_deletion_tombstones");
  const replay = sql.indexOf("RETURN saved.receipt");
  const gate = sql.indexOf("IF (SELECT selection_api_enabled");
  const invoke = sql.indexOf(
    "response := internal.select_observation_analysis",
  );
  assert(
    owner > 0 && owner < fence && fence < replay && replay < gate &&
      gate < invoke,
  );
  assertStringIncludes(
    sql,
    "saved.request_identity IS DISTINCT FROM p_request",
  );
  assertStringIncludes(sql, "EXCEPTION WHEN serialization_failure THEN");
  assertStringIncludes(
    sql,
    "IF SQLERRM IS DISTINCT FROM 'analysis_history_revision_conflict' THEN RAISE; END IF",
  );
  assertStringIncludes(
    sql,
    "INSERT INTO internal.observation_selection_receipts",
  );
  assertStringIncludes(
    sql,
    "GRANT EXECUTE ON FUNCTION public.select_owned_observation_analysis(JSONB,INTEGER) TO authenticated",
  );
  assertStringIncludes(
    sql,
    "'authenticated','public.select_owned_observation_analysis(jsonb,integer)'",
  );
  assert(!/GRANT EXECUTE ON FUNCTION internal\./i.test(sql));
  assert(!/UPDATE internal\.observation_history_rollout/i.test(sql));
});

Deno.test("analysis rejection is owner-bound, revisioned, receipt-fenced and held", async () => {
  const sql = await migration(
    "20261004033948_prepare_analysis_bound_rejection",
  );
  for (
    const fragment of [
      "rejection_api_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "PRIMARY KEY(observation_id,operation_id)",
      "p_reader IS DISTINCT FROM 9",
      "prior_rejection.receipt->>'review_revision'<>expected_review::TEXT",
      "prior_rejection.receipt->>'outcome'<>'applied'",
      "authority.review_revision=expected_review",
      "UPDATE internal.observation_analysis_authorities SET review_revision=expected_review+1",
      "analysis_bound_review_required",
      "LEAST(p_scan_id,p_source_scan_id)",
      "GREATEST(p_scan_id,p_source_scan_id)",
      "observation_id IN (OLD.scan_id,NEW.scan_id)",
      "PERFORM public.require_legacy_scan_review(p_user_id,p_scan_id)",
      "GRANT EXECUTE ON FUNCTION public.review_owned_observation_analysis(JSONB,INTEGER) TO authenticated",
      "GRANT EXECUTE ON FUNCTION public.require_legacy_scan_review(UUID,UUID) TO service_role",
    ]
  ) assertStringIncludes(sql, fragment);
  const owner = sql.indexOf("WHERE users.id=caller FOR UPDATE");
  const fence = sql.indexOf("internal.scan_deletion_tombstones");
  const replay = sql.indexOf("RETURN saved.receipt");
  const gate = sql.indexOf("IF (SELECT rejection_api_enabled");
  assert(owner > 0 && owner < fence && fence < replay && replay < gate);
  assert(
    !/UPDATE public\.scans|UPDATE internal\.observation_history_rollout/i.test(
      sql,
    ),
  );
});

Deno.test("analysis confirmation uses service proof, immutable admission and revisioned completion behind a closed gate", async () => {
  const sql = await migration(
    "20261004043041_prepare_analysis_bound_confirmation",
  );
  for (
    const fragment of [
      "confirmation_api_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "PERFORM internal.require_service_role()",
      "CREATE TABLE internal.observation_confirmation_intents",
      "CREATE INDEX observation_confirmation_intents_analysis_idx",
      "CREATE TRIGGER guard_observation_review_intent BEFORE INSERT",
      "p_verified_name IS DISTINCT FROM intent.scientific_name",
      "history.state_revision=expected_revision AND authority.review_revision=expected_review",
      "UPDATE internal.observation_analysis_authorities SET review_revision=expected_review+1",
      "GRANT EXECUTE ON FUNCTION public.prepare_observation_analysis_confirmation(UUID,JSONB,INTEGER) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.complete_observation_analysis_confirmation(UUID,JSONB,INTEGER,TEXT,JSONB) TO service_role",
      "NOTIFY pgrst, 'reload schema'",
    ]
  ) assertStringIncludes(sql, fragment);
  const owner = sql.indexOf("WHERE users.id=p_user_id FOR UPDATE");
  const fence = sql.indexOf("internal.scan_deletion_tombstones");
  const replay = sql.indexOf("'receipt',saved.receipt");
  const gate = sql.indexOf("IF (SELECT confirmation_api_enabled");
  const verification = sql.indexOf(
    "public.resolve_verified_dictionary_species(p_taxon)",
  );
  assert(
    owner > 0 && owner < fence && fence < replay && replay < gate &&
      gate < verification,
  );
  assert(
    !/GRANT EXECUTE ON FUNCTION internal\.|UPDATE public\.scans|UPDATE internal\.observation_history_rollout/i
      .test(sql),
  );
});

Deno.test("private community authority binds fresh requests and serializes current-source reconciliation without API activation", async () => {
  const sql = await migration(
    "20261004050937_prepare_analysis_community_authority",
  );
  for (
    const fragment of [
      "community_authority_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "CREATE TABLE internal.observation_community_creation_fences",
      "creation_transaction=pg_catalog.pg_current_xact_id()",
      "CREATE TABLE internal.observation_community_bindings",
      "CREATE TABLE internal.observation_community_reconciliation",
      "CREATE INDEX observation_community_bindings_analysis_idx",
      "authority.review_revision<>work.applied_review_revision",
      "SET superseded=TRUE,applied_source_revision=source_revision",
      "WHERE request_id=p_request FOR UPDATE NOWAIT",
      "EXCEPTION WHEN lock_not_available THEN RETURN 'pending'",
      "CREATE TRIGGER zz_delete_observation_community_authority AFTER DELETE",
      "PERFORM internal.reconcile_observation_community_authority(p_owner,p_request)",
    ]
  ) assertStringIncludes(sql, fragment);
  assert(
    !/GRANT EXECUTE|UPDATE internal\.observation_history_rollout/i.test(sql),
  );
  const projector = sql.slice(
    sql.indexOf(
      "CREATE FUNCTION internal.reconcile_observation_community_authority",
    ),
  );
  assert(
    !projector.includes("community_authority_enabled"),
    "Revocation must survive admission hold closure",
  );
  assert(
    !/FROM public\.explore_community_requests[^;]*FOR UPDATE/i.test(projector),
    "Worker must not take request lock after owner/history locks",
  );
  assert(!/UPDATE public\.scans|selected_analysis_id\s*=/i.test(projector));
});

Deno.test("publication snapshots preserve a private writer and immediate public revocation without legacy media fallback", async () => {
  const sql = await migration(
    "20261004054206_prepare_analysis_publication_snapshots",
  );
  for (
    const fragment of [
      "publication_snapshot_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "CREATE TABLE internal.observation_analysis_publications",
      "CREATE TABLE public.explore_analysis_public_projection",
      "FOR UPDATE NOWAIT",
      "work.source_revision=work.applied_source_revision",
      "authority.review_revision=work.applied_review_revision",
      "CREATE TRIGGER invalidate_observation_publication",
      "CREATE TRIGGER reconcile_observation_publication",
      "CREATE TRIGGER guard_observation_publication_media",
      "pg_try_advisory_xact_lock",
      "public.search_species_discovery(uuid,text,text,text,text,jsonb,boolean)",
      "public.get_community_identification_detail(uuid,uuid)",
      "public.get_explore_notifications_with_reactions(uuid,integer,timestamp with time zone,uuid)",
      "FOR UPDATE OF request NOWAIT",
      "FOR UPDATE OF published NOWAIT",
    ]
  ) assertStringIncludes(sql, fragment);
  assert(
    !/GRANT EXECUTE|UPDATE internal\.observation_history_rollout/i.test(sql),
  );
  const publicColumns = sql.slice(
    sql.indexOf("CREATE TABLE public.explore_analysis_public_projection"),
    sql.indexOf("ALTER TABLE public.explore_analysis_public_projection"),
  );
  for (
    const forbidden of [
      "analysis_id",
      "observation_id",
      "owner_id",
      "request_id",
      "review_snapshot",
      "media_manifest",
      "result_snapshot",
    ]
  ) assert(!publicColumns.includes(forbidden));
  assert(
    !/GRANT (?:ALL|INSERT|UPDATE|DELETE).*explore_analysis_public_projection/i
      .test(sql),
  );
});

Deno.test("community admission freezes evidence and replay without exposing an API writer", async () => {
  const sql = await migration(
    "20261004072651_prepare_analysis_community_admission",
  );
  for (
    const fragment of [
      "community_admission_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "CREATE TABLE internal.observation_community_admissions",
      "CREATE TABLE internal.observation_community_admission_fences",
      "f.creation_transaction=pg_catalog.pg_current_xact_id()",
      "CREATE TABLE public.explore_analysis_community_posts",
      "RETURN saved.receipt",
      "PERFORM internal.bind_observation_community_request",
      "guard_observation_community_request_evidence",
      "admitted.post_id IS NULL OR published.post_id IS NOT NULL",
      "published.post_id IS NULL AND admitted.post_id IS NULL THEN",
    ]
  ) assertStringIncludes(sql, fragment);
  const body = sql.slice(
    sql.indexOf("CREATE FUNCTION internal.admit_observation_community_request"),
  );
  assert(
    body.indexOf("internal.scan_deletion_tombstones") <
      body.indexOf("RETURN saved.receipt"),
  );
  assert(
    body.indexOf("RETURN saved.receipt") <
      body.indexOf("IF (SELECT community_admission_enabled"),
  );
  assert(
    !/GRANT EXECUTE|UPDATE internal\.observation_history_rollout/i.test(sql),
  );
  const publicColumns = sql.slice(
    sql.indexOf("CREATE TABLE public.explore_analysis_community_posts"),
    sql.indexOf("ALTER TABLE public.explore_analysis_community_posts"),
  );
  for (
    const field of [
      "analysis_id",
      "owner_id",
      "request_id",
      "intent",
      "receipt",
      "media_manifest",
    ]
  ) assert(!publicColumns.includes(field));
});

Deno.test("publication intent pins private V2 sources before any external or public write", async () => {
  const sql = await migration(
    "20261004075747_prepare_protected_publication_intents",
  );
  for (
    const fragment of [
      "publication_intent_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "CREATE TABLE internal.observation_publication_intents",
      "ON DELETE CASCADE",
      "internal.lock_owned_observation_evidence(p_owner,observation)",
      "public.resolve_owned_observation_photo(p_owner,observation,analysis,(media#>>'{}')::UUID,8)",
      "evidence.evidence_manifest->'schema_version' IS DISTINCT FROM '2'::JSONB",
      "authority.review_revision<>(p_request->>'expected_review_revision')::INTEGER",
      "IF sources IS DISTINCT FROM saved.sources",
    ]
  ) assertStringIncludes(sql, fragment);
  const prepare = sql.slice(
    sql.indexOf(
      "CREATE FUNCTION internal.prepare_observation_publication_intent",
    ),
    sql.indexOf(
      "CREATE FUNCTION internal.revalidate_observation_publication_intent",
    ),
  );
  assert(
    prepare.indexOf("internal.lock_owned_observation_evidence") <
      prepare.indexOf("SELECT * INTO saved"),
  );
  assert(
    !/GRANT EXECUTE|INSERT INTO public\.|UPDATE public\.|UPDATE internal\.observation_history_rollout/i
      .test(sql),
  );
});

Deno.test("private photo moderation keeps attempts source-bound and separate from scan credits", async () => {
  const sql = await migration(
    "20261004083008_prepare_publication_photo_moderation",
  );
  for (
    const fragment of [
      "publication_moderation_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "CREATE TABLE internal.observation_photo_moderations",
      "CREATE TABLE internal.observation_photo_moderation_attempts",
      "UNIQUE NULLS NOT DISTINCT(operation_id,media_id,predecessor_id)",
      "admitted.complimentary_client_scan_id IS NOT NULL",
      "job.quota_request_id,p_ip_hash,NULL,FALSE,3,FALSE",
      "attempt.dispatch_expires_at<=clock_timestamp()",
      "'unknown_execution'",
      "'dispatch_allowed',FALSE",
      "state=p_decision,lease_token=NULL",
    ]
  ) assertStringIncludes(sql, fragment);
  assert(
    !/GRANT EXECUTE|INSERT INTO public\.|UPDATE internal\.observation_history_rollout/i
      .test(sql),
  );
});
