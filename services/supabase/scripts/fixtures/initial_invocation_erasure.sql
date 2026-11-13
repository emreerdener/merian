CREATE FUNCTION pg_temp.invocation_provenance() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT '{"version":1,"provider":"gemini","binding":"gemini_baseline_v1","model":"gemini-2.5-flash","variant":"multimodal","operation":"scan_identification","policy_version":1,"prompt":"identify_vision_v1","schema":"merian_identify_v1","confidence":"unqualified","diagnostic_trigger":null,"prompt_diagnostic_trigger":null,"safety":null,"timeout_ms":90000,"generation":{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":1024}}'::JSONB
$$;
-- The runner reuses the guarded admission fixture. Synthetic profiles and
-- admission commit only inside its verified disposable local database.
SELECT set_config('merian.test_funding_tripwire','off',TRUE);
CREATE FUNCTION pg_temp.admit_erasure_scan(scan UUID, vector_index INTEGER DEFAULT 2) RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE owner_id CONSTANT UUID:='00000000-0000-4000-8000-00000000f001'; stage internal.initial_preparation_admission_staging;
 receipt internal.initial_preparation_admission_receipts; reservation internal.ai_quota_reservations; invocation UUID:=gen_random_uuid(); profile_name TEXT;
BEGIN
 SELECT v#>>'{profile,spec,input_profile}' INTO STRICT profile_name FROM media_vectors WHERE i=vector_index;
 PERFORM pg_temp.media_create(scan,vector_index);
 PERFORM pg_temp.execution_advance(scan,4);
 PERFORM internal.create_initial_admission_stage(owner_id,scan);
 SELECT * INTO STRICT stage FROM internal.initial_preparation_admission_staging WHERE scan_id=scan;
 PERFORM set_config('merian.initial_admission_stage',stage.stage_token::TEXT,TRUE);
 PERFORM set_config('merian.initial_preparation_funding',owner_id::TEXT||':'||scan::TEXT,TRUE);
 PERFORM set_config('merian.initial_analysis_admission',owner_id::TEXT||':'||scan::TEXT,TRUE);
 PERFORM * FROM public.reserve_identification_quota(owner_id,'scan_identification',scan,repeat('a',64),scan,FALSE,3,FALSE,profile_name,'google_gemini',6);
 PERFORM internal.materialize_initial_admission(scan);
 PERFORM internal.freeze_initial_admission_ledger(scan);
 PERFORM internal.begin_initial_admission_consumption(scan);
 receipt:=internal.finish_initial_admission(scan);
 SET CONSTRAINTS ALL IMMEDIATE;
 SET CONSTRAINTS ALL DEFERRED;
END; $$;
CREATE FUNCTION pg_temp.seed_admitted_invocation(scan UUID) RETURNS UUID LANGUAGE PLPGSQL AS $$
DECLARE owner_id CONSTANT UUID:='00000000-0000-4000-8000-00000000f001'; receipt internal.initial_preparation_admission_receipts; reservation internal.ai_quota_reservations; invocation UUID:=gen_random_uuid();
BEGIN
 SELECT * INTO STRICT receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=scan;
 SELECT * INTO STRICT reservation FROM internal.ai_quota_reservations WHERE user_id=owner_id AND request_id=scan;
 -- Only the future dispatch INSERT is injected. Real receipt, funding and
 -- erasure guards remain enabled; this is not positive dispatch qualification.
 ALTER TABLE internal.identification_invocations DISABLE TRIGGER a00_initial_invocation_authority;
 ALTER TABLE internal.identification_invocations DISABLE TRIGGER a0_initial_preparation_provider_barrier;
 INSERT INTO internal.identification_invocations(id,user_id,scan_id,reservation_id,attempt_count,lease_sha256,provider,model,binding,input_profile,effective_plan,policy_version,provenance,occurred_at,is_initial_analysis,initial_admission_receipt_id)
 VALUES(invocation,owner_id,scan,reservation.id,reservation.attempt_count,encode(extensions.digest(convert_to(reservation.lease_token::TEXT,'UTF8'),'sha256'),'hex'),receipt.accounting::JSONB#>>'{attempt,provider}',
 COALESCE(receipt.accounting::JSONB#>>'{attempt,provider_model}',receipt.accounting::JSONB#>>'{attempt,model}'),
 receipt.accounting::JSONB#>>'{attempt,binding}',receipt.accounting::JSONB#>>'{attempt,input_profile}',
 receipt.accounting::JSONB#>>'{attempt,effective_plan}',(receipt.accounting::JSONB#>>'{attempt,policy_version}')::INTEGER,
 pg_temp.invocation_provenance()||jsonb_build_object('provider',receipt.accounting::JSONB#>>'{attempt,provider}',
  'model',COALESCE(receipt.accounting::JSONB#>>'{attempt,provider_model}',receipt.accounting::JSONB#>>'{attempt,model}'),
  'binding',receipt.accounting::JSONB#>>'{attempt,binding}',
  'policy_version',(receipt.accounting::JSONB#>>'{attempt,policy_version}')::INTEGER),
 '2000-01-01T00:00:00Z',TRUE,receipt.admission_receipt_id);
 ALTER TABLE internal.identification_invocations ENABLE TRIGGER a00_initial_invocation_authority;
 ALTER TABLE internal.identification_invocations ENABLE TRIGGER a0_initial_preparation_provider_barrier;
 RETURN invocation;
END; $$;
-- Admission seals intentionally outlive its composer within a transaction.
-- The guarded runner commits this synthetic fixture only in its fresh local
-- disposable, so erasure uses a new transaction with every seal still enabled.
SELECT pg_temp.admit_erasure_scan('00000000-0000-4000-8000-000000000401');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;
COMMIT;
BEGIN;
CREATE TEMP TABLE fixture AS SELECT '00000000-0000-4000-8000-000000000401'::UUID scan,pg_temp.seed_admitted_invocation('00000000-0000-4000-8000-000000000401') invocation;
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_admission_receipts r JOIN fixture f ON r.scan_id=f.scan),1::BIGINT,'fixture owns a real guarded admission receipt');
CREATE FUNCTION pg_temp.cancellation_snapshot() RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE relation TEXT; rows JSONB; images JSONB:='{}';
BEGIN
 FOR relation IN SELECT relation_name FROM internal.initial_cancellation_private_catalog()
  UNION SELECT unnest(ARRAY['public.users','public.ai_usage_events',
   'internal.account_deletion_jobs','internal.initial_analysis_lifecycle_fences',
   'internal.initial_analysis_operation_fences','internal.initial_analysis_cancellations',
   'internal.scan_deletion_tombstones','internal.identification_invocations',
   'internal.ai_quota_reservations','internal.ai_quota_reservation_counters',
   'internal.ai_quota_counters','internal.identification_provider_attempts',
   'internal.complimentary_scan_usage','internal.initial_admitted_cancellation_staging',
   'internal.initial_cpm_photo_capacity_reservations','internal.initial_cpm_photo_write_attempts','internal.initial_cpm_photo_write_closures',
   'internal.initial_cancellation_quota_statements','internal.initial_cancellation_credit_witness',
   'internal.initial_cancellation_invocation_witness','internal.initial_cancellation_lifecycle_witness',
   'internal.initial_cancellation_retirement_witness','internal.initial_cancellation_erasure_witness',
   'internal.initial_cancellation_receipt_witness']) LOOP
  EXECUTE format('SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::TEXT),''[]''::JSONB) FROM %s r',relation) INTO rows;
  images:=images||jsonb_build_object(relation,rows);
 END LOOP;
 RETURN images;
END; $$;
CREATE TEMP TABLE cancellation_before AS SELECT pg_temp.cancellation_snapshot() image;
CREATE FUNCTION pg_temp.cpm_retained_image(scan UUID, retire BOOLEAN DEFAULT FALSE) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object(
  'capacity',(SELECT jsonb_agg(to_jsonb(c) ORDER BY c.scan_id) FROM internal.initial_cpm_photo_capacity_reservations c WHERE c.scan_id=scan),
  'attempts',(SELECT jsonb_agg(CASE WHEN retire THEN to_jsonb(a)||'{"retired":true}'::JSONB ELSE to_jsonb(a) END ORDER BY a.object_id) FROM internal.initial_cpm_photo_write_attempts a WHERE a.scan_id=scan),
  'closures',(SELECT jsonb_agg(to_jsonb(c) ORDER BY c.attempt_id) FROM internal.initial_cpm_photo_write_closures c JOIN internal.initial_cpm_photo_write_attempts a USING(attempt_id) WHERE a.scan_id=scan))
$$;
CREATE TEMP SEQUENCE prior_retirement_seen;
CREATE FUNCTION pg_temp.observe_prior_retirement() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF NEW.id=(SELECT invocation FROM fixture) AND internal.initial_invocation_retired(NEW) THEN
  PERFORM nextval('pg_temp.prior_retirement_seen');
 END IF;
 RETURN NEW;
END; $$;
CREATE FUNCTION pg_temp.account_funding_unchanged() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM cancellation_before b,
   jsonb_array_elements(b.image->'internal.ai_quota_reservations') q
   WHERE q->>'id'=OLD.id::TEXT AND q-'user_id'=to_jsonb(OLD)-'user_id')
  OR (TG_OP='UPDATE' AND (to_jsonb(NEW)-'user_id' IS DISTINCT FROM to_jsonb(OLD)-'user_id'
    OR (NEW.user_id IS NOT NULL AND NEW.user_id IS DISTINCT FROM OLD.user_id))) THEN
  RAISE EXCEPTION 'classified account erasure changed funding';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END; $$;
CREATE FUNCTION pg_temp.erasure_probe(mode TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE scan UUID; invocation UUID; before_image JSONB; code TEXT; detail TEXT; science_facts JSONB;
BEGIN
 SELECT f.scan,f.invocation INTO STRICT scan,invocation FROM fixture f;
 BEGIN
  IF mode IN ('invocation_only','account_later_failure') THEN
   -- Corrupt leftover has no private root or receipt. Discover it through the
   -- classified invocation, then require atomic denial rather than erasing its
   -- original correlation through ordinary owner anonymization.
   INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)
    VALUES('00000000-0000-4000-8000-000000000499','00000000-0000-4000-8000-00000000f001',clock_timestamp());
   INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES('00000000-0000-4000-8000-000000000499');
   ALTER TABLE internal.identification_invocations DISABLE TRIGGER a00_initial_invocation_authority;
   ALTER TABLE internal.identification_invocations DISABLE TRIGGER a0_initial_preparation_provider_barrier;
   INSERT INTO internal.identification_invocations SELECT (jsonb_populate_record(NULL::internal.identification_invocations,
    to_jsonb(i)||jsonb_build_object('id',gen_random_uuid(),'scan_id','00000000-0000-4000-8000-000000000499',
     'reservation_id',gen_random_uuid(),'initial_admission_receipt_id',gen_random_uuid()))).* FROM internal.identification_invocations i WHERE id=invocation;
   ALTER TABLE internal.identification_invocations ENABLE TRIGGER a00_initial_invocation_authority;
   ALTER TABLE internal.identification_invocations ENABLE TRIGGER a0_initial_preparation_provider_barrier;
   IF NOT EXISTS(SELECT 1 FROM internal.initial_media_handoff_erasure_identities('00000000-0000-4000-8000-00000000f001') e
      WHERE e.scan_id='00000000-0000-4000-8000-000000000499')
     OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id='00000000-0000-4000-8000-000000000499')
     OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id='00000000-0000-4000-8000-000000000499') THEN
    RAISE EXCEPTION 'invocation-only fixture/discovery failed'; END IF;
  END IF;
  IF mode IN ('existing_tombstone','account_existing_tombstone') THEN
   ALTER TABLE internal.scan_deletion_tombstones DISABLE TRIGGER erase_initial_analysis_for_scan_fence;
   INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES(scan,'00000000-0000-4000-8000-00000000f001',clock_timestamp());
   ALTER TABLE internal.scan_deletion_tombstones ENABLE TRIGGER erase_initial_analysis_for_scan_fence;
  END IF;
  IF mode IN ('wrong_receipt','missing_receipt') THEN
   ALTER TABLE internal.identification_invocations DISABLE TRIGGER require_initial_invocation_erasure;
   ALTER TABLE internal.identification_invocations DISABLE TRIGGER a00_initial_invocation_authority;
   UPDATE internal.identification_invocations SET initial_admission_receipt_id=CASE WHEN mode='wrong_receipt' THEN gen_random_uuid() ELSE NULL END WHERE id=invocation;
   ALTER TABLE internal.identification_invocations ENABLE TRIGGER a00_initial_invocation_authority;
   ALTER TABLE internal.identification_invocations ENABLE TRIGGER require_initial_invocation_erasure;
  END IF;
  IF mode IN ('reservation_alias','account_alias') THEN
   -- Corrupt scan correlation while retaining the exact original reservation.
   ALTER TABLE internal.identification_invocations DISABLE TRIGGER a00_initial_invocation_authority;
   ALTER TABLE internal.identification_invocations DISABLE TRIGGER a0_initial_preparation_provider_barrier;
   UPDATE internal.identification_invocations SET scan_id='00000000-0000-4000-8000-000000000498' WHERE id=invocation;
   ALTER TABLE internal.identification_invocations ENABLE TRIGGER a00_initial_invocation_authority;
   ALTER TABLE internal.identification_invocations ENABLE TRIGGER a0_initial_preparation_provider_barrier;
  ELSIF mode='saved_cancellation' THEN
   -- Seed a consistent saved terminal receipt to exercise the replay branch.
   ALTER TABLE internal.initial_analysis_lifecycle_fences DISABLE TRIGGER USER;
   UPDATE internal.initial_analysis_lifecycle_fences SET state='cancelled_unknown' WHERE scan_id=scan;
   ALTER TABLE internal.initial_analysis_lifecycle_fences ENABLE TRIGGER USER;
   INSERT INTO internal.initial_analysis_cancellations(scan_id,owner_id,dispatch)
    VALUES(scan,'00000000-0000-4000-8000-00000000f001','dispatch_outcome_unknown');
  END IF;
  IF mode='account_later_failure' THEN
   PERFORM setval('pg_temp.prior_retirement_seen',1,FALSE);
   CREATE TRIGGER test_observe_prior_retirement AFTER UPDATE ON internal.identification_invocations
    FOR EACH ROW EXECUTE FUNCTION pg_temp.observe_prior_retirement();
  END IF;
  IF mode='account_science' THEN
   UPDATE internal.observation_history_rollout SET enrollment_enabled=TRUE;
   PERFORM pg_temp.seed_retention('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-000000000497','family','ai');
   science_facts:=internal.observation_retained_identification('00000000-0000-4000-8000-000000000497');
  END IF;
  IF mode IN ('generic_cancellation','public_account','positive_unused','reservation_alias','saved_cancellation','account_existing_tombstone','account_alias','account_later_failure','account_science') THEN
   PERFORM set_config('request.jwt.claim.role','service_role',TRUE);
   IF mode IN ('generic_cancellation','reservation_alias','saved_cancellation') THEN
    PERFORM internal.cancel_initial_analysis('00000000-0000-4000-8000-00000000f001',scan);
    IF EXISTS(SELECT 1 FROM internal.identification_invocations i WHERE i.id=invocation AND i.initial_admission_receipt_id IS NOT NULL)
      AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts r WHERE r.scan_id=scan) THEN
     RAISE EXCEPTION 'original receipt erased before invocation retirement' USING ERRCODE='Z0002'; END IF;
   ELSIF mode IN ('public_account','account_existing_tombstone','account_alias','account_later_failure','account_science') THEN
    before_image:=pg_temp.cancellation_snapshot();
    CREATE TRIGGER test_account_funding_unchanged BEFORE UPDATE OR DELETE ON internal.ai_quota_reservations
     FOR EACH ROW EXECUTE FUNCTION pg_temp.account_funding_unchanged();
    SET LOCAL ROLE service_role;
    PERFORM public.apply_user_tombstone('00000000-0000-4000-8000-00000000f001');
    RESET ROLE;
    SET CONSTRAINTS ALL IMMEDIATE;
    IF EXISTS(SELECT 1 FROM public.users WHERE id='00000000-0000-4000-8000-00000000f001')
      OR NOT EXISTS(SELECT 1 FROM internal.identification_invocations i WHERE i.id=invocation AND internal.initial_invocation_retired(i))
      OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts r WHERE r.scan_id=scan)
      OR (SELECT count(*) FROM public.ai_usage_events e JOIN internal.identification_invocations i ON i.event_id=e.id
          WHERE i.id=invocation AND e.outcome='unknown' AND e.user_id IS NULL AND e.scan_id IS NULL
           AND e.source_id IS NULL AND e.conversation_id IS NULL AND e.message_id IS NULL)<>1
      OR (SELECT count(*) FROM public.ai_usage_events)<>1+jsonb_array_length(before_image->'public.ai_usage_events')
      OR (pg_temp.cancellation_snapshot()->'internal.ai_quota_counters') IS DISTINCT FROM
         (SELECT image->'internal.ai_quota_counters' FROM cancellation_before) THEN
     RAISE EXCEPTION 'public account erasure invariant failed'; END IF;
    IF mode='account_science' AND NOT EXISTS(SELECT 1 FROM public.scans
      WHERE id='00000000-0000-4000-8000-000000000497' AND user_id IS NULL AND is_tombstoned
       AND retained_identification=science_facts AND ai_confidence_score=0.9
       AND user_observation_context IS NULL AND ai_reasoning IS NULL AND cardinality(image_storage_urls)=0) THEN
     RAISE EXCEPTION 'public account lost retained science'; END IF;

   ELSE
    -- Remove only the injected future invocation to recover the actual unused
    -- guarded admission. The existing refundable C1 proof must stay unchanged.
    ALTER TABLE internal.identification_invocations DISABLE TRIGGER a00_initial_invocation_authority;
    DELETE FROM internal.identification_invocations WHERE id=invocation;
    ALTER TABLE internal.identification_invocations ENABLE TRIGGER a00_initial_invocation_authority;
    SET LOCAL ROLE service_role;
    IF public.cancel_initial_analysis('00000000-0000-4000-8000-00000000f001',scan)->>'dispatch' IS DISTINCT FROM 'dispatch_prevented' THEN
     RAISE EXCEPTION 'unused cancellation classification changed'; END IF;
    RESET ROLE;
    IF EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging WHERE scan_id=scan)
     OR EXISTS(SELECT 1 FROM internal.initial_cancellation_lifecycle_witness WHERE scan_id=scan) THEN
     RAISE EXCEPTION 'unused cancellation left live proof rows'; END IF;
    -- Exercise captured INSERT and DELETE evidence after real witness cleanup.
    SET CONSTRAINTS ALL IMMEDIATE;
   END IF;
   RAISE EXCEPTION 'pass' USING ERRCODE='Z0001';
  END IF;
  IF mode='partial_clear' THEN
   UPDATE internal.identification_invocations SET scan_id=NULL WHERE id=invocation;
  ELSIF mode IN ('no_tombstone','root_left','immediate','event_changed') THEN
   PERFORM internal.complete_identification_usage(invocation,'unknown_execution','{}');
   IF mode<>'no_tombstone' THEN
    -- Fault injection leaves the real private root in place. The invocation
    -- transition and all of its validation triggers remain enabled.
    ALTER TABLE internal.scan_deletion_tombstones DISABLE TRIGGER erase_initial_analysis_for_scan_fence;
    INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES(scan,'00000000-0000-4000-8000-00000000f001',clock_timestamp());
    ALTER TABLE internal.scan_deletion_tombstones ENABLE TRIGGER erase_initial_analysis_for_scan_fence;
   END IF;
   IF mode='immediate' THEN SET CONSTRAINTS ALL IMMEDIATE; END IF;
   UPDATE internal.identification_invocations SET user_id=NULL,scan_id=NULL,reservation_id=NULL,lease_sha256=NULL,initial_admission_receipt_id=NULL,
    event_id=CASE WHEN mode='event_changed' THEN gen_random_uuid() ELSE event_id END WHERE id=invocation;
   SET CONSTRAINTS ALL IMMEDIATE;
  ELSIF mode IN ('raw_owner_delete','existing_tombstone','invocation_only') THEN
   DELETE FROM public.users WHERE id='00000000-0000-4000-8000-00000000f001';
   SET CONSTRAINTS ALL IMMEDIATE;
   IF NOT EXISTS(SELECT 1 FROM internal.identification_invocations i WHERE i.id=invocation AND internal.initial_invocation_retired(i))
     OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts r WHERE r.scan_id=scan) THEN
    RAISE EXCEPTION 'owner erasure assertion failed'; END IF;
  ELSE
   INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES(scan,'00000000-0000-4000-8000-00000000f001',clock_timestamp());
   SET CONSTRAINTS ALL IMMEDIATE;
  END IF;
  RAISE EXCEPTION 'pass' USING ERRCODE='Z0001';
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,detail=MESSAGE_TEXT;
 END;
 IF mode='account_later_failure' AND NOT (SELECT is_called FROM pg_temp.prior_retirement_seen) THEN
  RETURN 'Z0003:earlier retirement was not observed'; END IF;
 RETURN code||':'||detail;
END; $$;
-- Private accounted capture is not a cancellation composer. These rollback
-- probes qualify original association, existing-event preservation and atomic
-- accounting failure only; no invocation retirement or stage is authorized.
CREATE FUNCTION pg_temp.capture_probe(mode TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE scan UUID; inv_id UUID; captured JSONB; before_image JSONB; after_image JSONB;
 original_event JSONB; code TEXT; detail TEXT; result_image JSONB; receipt internal.initial_preparation_admission_receipts;
BEGIN
 SELECT f.scan,f.invocation INTO STRICT scan,inv_id FROM fixture f;
 BEGIN
  PERFORM set_config('request.jwt.claim.role','service_role',TRUE);
  IF mode IN ('completed','bad_event','bad_metadata') THEN
   PERFORM internal.complete_identification_usage(inv_id,'draft','{"input_tokens":21,"candidate_tokens":8,"total_tokens":29}'::JSONB);
   IF mode IN ('bad_event','bad_metadata') THEN
    ALTER TABLE public.ai_usage_events DISABLE TRIGGER USER;
    UPDATE public.ai_usage_events SET
     source_id=CASE WHEN mode='bad_event' THEN gen_random_uuid() ELSE source_id END,
     metadata=CASE WHEN mode='bad_metadata' THEN metadata||'{"ai_binding":"wrong"}'::JSONB ELSE metadata END
     WHERE id=(SELECT event_id FROM internal.identification_invocations WHERE id=inv_id);
    ALTER TABLE public.ai_usage_events ENABLE TRIGGER USER;
   END IF;
   SELECT to_jsonb(e) INTO original_event FROM public.ai_usage_events e
    WHERE id=(SELECT event_id FROM internal.identification_invocations WHERE id=inv_id);
  END IF;
  IF mode IN ('wrong_receipt','wrong_lease','alias','ordinary') THEN
   ALTER TABLE internal.identification_invocations DISABLE TRIGGER USER;
   UPDATE internal.identification_invocations SET
    initial_admission_receipt_id=CASE WHEN mode='wrong_receipt' THEN gen_random_uuid() WHEN mode='ordinary' THEN NULL ELSE initial_admission_receipt_id END,
    lease_sha256=CASE WHEN mode='wrong_lease' THEN repeat('0',64) ELSE lease_sha256 END,
    scan_id=CASE WHEN mode='alias' THEN '00000000-0000-4000-8000-000000000498'::UUID ELSE scan_id END,
    is_initial_analysis=CASE WHEN mode='ordinary' THEN FALSE ELSE is_initial_analysis END WHERE id=inv_id;
   ALTER TABLE internal.identification_invocations ENABLE TRIGGER USER;
  END IF;
  IF mode='renewed_lease' THEN
   -- Later current lease is deliberately different; retained receipt identity
   -- must still select the original invocation, without renewing execution.
   ALTER TABLE internal.ai_quota_reservations DISABLE TRIGGER USER;
   UPDATE internal.ai_quota_reservations SET lease_token=gen_random_uuid(),lease_expires_at='2000-01-01T00:00:00Z'
    WHERE id=(SELECT reservation_id FROM internal.identification_invocations WHERE id=inv_id);
   ALTER TABLE internal.ai_quota_reservations ENABLE TRIGGER USER;
  END IF;
  IF mode='consumed_s0' THEN
   -- Exercise the real mechanical stage lifecycle, not a manually acquired
   -- advisory lock. Legacy result barriers are isolated only in this rollback
   -- probe, just as initial_consuming_stage.sql does; this grants no dispatch.
   ALTER TABLE internal.initial_analysis_results DISABLE TRIGGER USER;
   CREATE TRIGGER test_s0_before_stmt BEFORE INSERT ON internal.initial_analysis_results
    FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member();
   CREATE TRIGGER test_s0_after_stmt AFTER INSERT ON internal.initial_analysis_results
    FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member();
   CREATE TRIGGER test_s0_before_row BEFORE INSERT ON internal.initial_analysis_results
    FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member();
   CREATE TRIGGER test_s0_after_row AFTER INSERT ON internal.initial_analysis_results
    FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member();
   SELECT * INTO STRICT receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=scan;
   result_image:=jsonb_build_object('scan_id',scan,'owner_id',receipt.owner_id,'result_evidence_id',gen_random_uuid(),
    'result_schema_version',1,'result_snapshot','{}'::JSONB,'provenance_snapshot','{}'::JSONB);
   INSERT INTO internal.initial_consuming_staging(transaction_id,scan_id,owner_id,operation,
    admission_receipt_id,admission_receipt_digest,reservation_id,invocation_id,result_evidence_id,expected_writes)
   VALUES(pg_current_xact_id(),scan,receipt.owner_id,'result',receipt.admission_receipt_id,receipt.receipt_digest,
    (receipt.accounting::JSONB#>>'{reservation,reservation_id}')::UUID,inv_id,(result_image->>'result_evidence_id')::UUID,
    jsonb_build_array(jsonb_build_array(jsonb_build_object('old',NULL,'new',result_image))));
   INSERT INTO internal.initial_analysis_results SELECT * FROM jsonb_populate_record(NULL::internal.initial_analysis_results,result_image);
   DELETE FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
   SET CONSTRAINTS ALL IMMEDIATE;
   SET CONSTRAINTS ALL DEFERRED;
   IF EXISTS(SELECT 1 FROM internal.initial_consuming_staging) OR NOT EXISTS(
    SELECT 1 FROM pg_catalog.pg_locks l WHERE l.locktype='advisory' AND l.pid=pg_backend_pid()
     AND l.classid=1396920143::OID AND l.objid::BIGINT=(hashtext(pg_current_xact_id()::TEXT)::BIGINT & 4294967295)
     AND l.objsubid=2 AND l.granted) THEN RAISE EXCEPTION 'consumed S0 latch fixture incomplete'; END IF;
  END IF;
  before_image:=pg_temp.cancellation_snapshot();
  captured:=internal.capture_initial_accounted_cancellation_prestate('00000000-0000-4000-8000-00000000f001',scan);
  after_image:=pg_temp.cancellation_snapshot();
  IF captured->>'variant' IS DISTINCT FROM 'accounted_invocation'
   OR captured#>>'{invocation,id}' IS DISTINCT FROM inv_id::TEXT
   OR captured#>>'{invocation,event_id}' IS DISTINCT FROM captured#>>'{event,id}'
   OR captured#>>'{event,source_id}' IS DISTINCT FROM inv_id::TEXT
   OR captured#>>'{event,outcome}' IS DISTINCT FROM (CASE WHEN mode='completed' THEN 'success' ELSE 'unknown' END)
   OR (mode='completed' AND captured->'event' IS DISTINCT FROM original_event)
   OR captured->'invocation' IS DISTINCT FROM (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=inv_id)
   OR before_image-ARRAY['internal.identification_invocations','public.ai_usage_events'] IS DISTINCT FROM
      after_image-ARRAY['internal.identification_invocations','public.ai_usage_events']
   OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging)
   OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=scan) THEN
   RAISE EXCEPTION 'accounted capture invariant failed'; END IF;
  -- Repeated capture preserves the same event and funding; it is not an
  -- invocation statement witness and does not grant a cancellation transition.
  IF captured IS DISTINCT FROM internal.capture_initial_accounted_cancellation_prestate('00000000-0000-4000-8000-00000000f001',scan) THEN
   RAISE EXCEPTION 'accounted capture replay changed evidence'; END IF;
  RAISE EXCEPTION 'pass' USING ERRCODE='Z0001';
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,detail=MESSAGE_TEXT;
 END;
 RETURN code||':'||detail;
END; $$;
SELECT extensions.is(pg_temp.capture_probe('unknown'),'Z0001:pass','accounted capture reconciles once without changing funding or private roots');
SELECT extensions.is(pg_temp.capture_probe('completed'),'Z0001:pass','accounted capture preserves the existing completed report and prices');
SELECT extensions.is(pg_temp.capture_probe('renewed_lease'),'Z0001:pass','accounted capture uses the retained original lease rather than an expired renewed lease');
SELECT extensions.is(pg_temp.capture_probe('wrong_receipt'),'55000:initial_analysis_cancellation_incomplete','accounted capture rejects another original receipt');
SELECT extensions.is(pg_temp.capture_probe('wrong_lease'),'55000:initial_analysis_cancellation_incomplete','accounted capture rejects a different original lease digest');
SELECT extensions.is(pg_temp.capture_probe('alias'),'55000:initial_analysis_cancellation_incomplete','accounted capture detects reservation aliases before accounting');
SELECT extensions.is(pg_temp.capture_probe('ordinary'),'55000:initial_analysis_cancellation_incomplete','accounted capture cannot adopt an ordinary invocation');
SELECT extensions.is(pg_temp.capture_probe('bad_event'),'55000:initial_analysis_cancellation_incomplete','accounted capture validates source correlation after producer early return');
SELECT extensions.is(pg_temp.capture_probe('bad_metadata'),'55000:initial_analysis_cancellation_incomplete','accounted capture rejects conflicting event attribution');
SELECT extensions.is(pg_temp.capture_probe('consumed_s0'),'55000:initial_analysis_cancellation_incomplete','accounted capture rejects the retained latch after real S0 stage consumption');
SELECT extensions.ok(pg_temp.cancellation_snapshot()=(SELECT image FROM cancellation_before),'accounted capture probes roll back all accounting and fault injection');
-- Stage entry is atomic, but accounted completion is deliberately held until
-- its exact retirement and terminal proofs are implemented. Sequence observation
-- survives subtransaction rollback and proves reconciliation actually preceded
-- a suppressed row or later failure. No synthetic row image leaves the database.
CREATE TEMP SEQUENCE c1_accounting_seen;
CREATE FUNCTION pg_temp.observe_c1_accounting() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF NEW.source_id=(SELECT invocation FROM fixture) THEN PERFORM nextval('pg_temp.c1_accounting_seen'); END IF;
 RETURN NEW;
END; $$;
CREATE FUNCTION pg_temp.suppress_c1_stage() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN RETURN NULL; END; $$;
CREATE FUNCTION pg_temp.fail_c1_stage() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN RAISE EXCEPTION 'late_stage_failure' USING ERRCODE='55000'; END; $$;
CREATE FUNCTION pg_temp.stage_entry_probe(mode TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE scan UUID; inv_id UUID; stage internal.initial_admitted_cancellation_staging;
 before_image JSONB; prior_event JSONB; code TEXT; detail TEXT;
BEGIN
 SELECT f.scan,f.invocation INTO STRICT scan,inv_id FROM fixture f;
 PERFORM setval('pg_temp.c1_accounting_seen',1,FALSE);
 BEGIN
  PERFORM set_config('request.jwt.claim.role','service_role',TRUE);
  IF mode='existing' THEN
   PERFORM internal.complete_identification_usage(inv_id,'draft','{"input_tokens":21,"candidate_tokens":8,"total_tokens":29}'::JSONB);
   SELECT to_jsonb(e) INTO prior_event FROM public.ai_usage_events e
    WHERE id=(SELECT event_id FROM internal.identification_invocations WHERE id=inv_id);
  END IF;
  CREATE TRIGGER test_c1_accounting_seen AFTER INSERT ON public.ai_usage_events
   FOR EACH ROW EXECUTE FUNCTION pg_temp.observe_c1_accounting();
  IF mode='suppressed' THEN
   CREATE TRIGGER zzzz_suppress_c1_stage BEFORE INSERT ON internal.initial_admitted_cancellation_staging
    FOR EACH ROW EXECUTE FUNCTION pg_temp.suppress_c1_stage();
  ELSIF mode='late_failure' THEN
   CREATE TRIGGER zzzz_fail_c1_stage AFTER INSERT ON internal.initial_admitted_cancellation_staging
    FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_c1_stage();
  ELSIF mode='immediate' THEN SET CONSTRAINTS ALL IMMEDIATE;
  ELSIF mode='caller_variant' THEN
   INSERT INTO internal.initial_admitted_cancellation_staging(owner_id,scan_id,variant)
    VALUES('00000000-0000-4000-8000-00000000f001',scan,'unused');
  ELSIF mode='caller_prestate' THEN
   INSERT INTO internal.initial_admitted_cancellation_staging(owner_id,scan_id,prestate)
    VALUES('00000000-0000-4000-8000-00000000f001',scan,'{}');
  ELSIF mode='caller_xid' THEN
   INSERT INTO internal.initial_admitted_cancellation_staging(owner_id,scan_id,transaction_id)
    VALUES('00000000-0000-4000-8000-00000000f001',scan,pg_current_xact_id());
  ELSIF mode='caller_clock' THEN
   INSERT INTO internal.initial_admitted_cancellation_staging(owner_id,scan_id,quota_at)
    VALUES('00000000-0000-4000-8000-00000000f001',scan,clock_timestamp());
  ELSIF mode='caller_phase' THEN
   INSERT INTO internal.initial_admitted_cancellation_staging(owner_id,scan_id,phase)
    VALUES('00000000-0000-4000-8000-00000000f001',scan,'accounted');
  ELSIF mode='public_hold' THEN
   SET LOCAL ROLE service_role;
   PERFORM public.cancel_initial_analysis('00000000-0000-4000-8000-00000000f001',scan);
   RESET ROLE;
   SET CONSTRAINTS ALL IMMEDIATE;
   RAISE EXCEPTION 'pass' USING ERRCODE='Z0001';
  ELSIF mode='unused_seal' THEN
   ALTER TABLE internal.identification_invocations DISABLE TRIGGER a00_initial_invocation_authority;
   DELETE FROM internal.identification_invocations WHERE id=inv_id;
   ALTER TABLE internal.identification_invocations ENABLE TRIGGER a00_initial_invocation_authority;
   SET LOCAL ROLE service_role;
   PERFORM public.cancel_initial_analysis('00000000-0000-4000-8000-00000000f001',scan);
   RESET ROLE;
   IF NOT internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging) THEN
    RAISE EXCEPTION 'unused seal fixture incomplete'; END IF;
   UPDATE public.ai_usage_events SET outcome=outcome WHERE FALSE;
   RAISE EXCEPTION 'sealed ledger mutation unexpectedly opened';
  END IF;
  before_image:=pg_temp.cancellation_snapshot();
  stage:=internal.begin_initial_cancellation_stage('00000000-0000-4000-8000-00000000f001',scan);
  IF stage.variant IS DISTINCT FROM 'accounted_invocation' OR stage.phase IS DISTINCT FROM 'accounted'
   OR stage.quota_at IS NOT NULL OR stage.prestate->>'variant' IS DISTINCT FROM stage.variant
   OR stage.prestate#>>'{invocation,id}' IS DISTINCT FROM inv_id::TEXT
   OR (mode='existing' AND stage.prestate->'event' IS DISTINCT FROM prior_event)
   OR before_image-ARRAY['internal.identification_invocations','public.ai_usage_events','internal.initial_admitted_cancellation_staging']
      IS DISTINCT FROM pg_temp.cancellation_snapshot()-ARRAY['internal.identification_invocations','public.ai_usage_events','internal.initial_admitted_cancellation_staging']
   OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements)
   OR EXISTS(SELECT 1 FROM internal.initial_cancellation_credit_witness) THEN
   RAISE EXCEPTION 'accounted stage invariant failed'; END IF;
  CASE mode
   WHEN 'duplicate' THEN PERFORM internal.begin_initial_cancellation_stage('00000000-0000-4000-8000-00000000f001',scan);
   WHEN 'update' THEN UPDATE internal.initial_admitted_cancellation_staging SET phase='quota' WHERE scan_id=scan;
   WHEN 'delete' THEN DELETE FROM internal.initial_admitted_cancellation_staging WHERE scan_id=scan;
   WHEN 'ledger_insert' THEN INSERT INTO public.ai_usage_events(id) SELECT gen_random_uuid() WHERE FALSE;
   WHEN 'ledger_update' THEN UPDATE public.ai_usage_events SET outcome=outcome WHERE FALSE;
   WHEN 'ledger_delete' THEN DELETE FROM public.ai_usage_events WHERE FALSE;
   WHEN 'ledger_service' THEN SET LOCAL ROLE service_role; UPDATE public.ai_usage_events SET outcome=outcome WHERE FALSE; RESET ROLE;
   WHEN 'unfinished' THEN SET CONSTRAINTS ALL IMMEDIATE;
   ELSE NULL;
  END CASE;
  RAISE EXCEPTION 'pass' USING ERRCODE='Z0001';
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,detail=MESSAGE_TEXT;
 END;
 IF mode IN ('valid','suppressed','late_failure','immediate','public_hold','unfinished')
  AND NOT (SELECT is_called FROM pg_temp.c1_accounting_seen) THEN
  RETURN 'Z0003:reconciliation was not observed'; END IF;
 IF (mode='existing' OR mode LIKE 'caller_%') AND (SELECT is_called FROM pg_temp.c1_accounting_seen) THEN
  RETURN 'Z0003:unexpected accounting production'; END IF;
 RETURN code||':'||detail;
END; $$;
SELECT extensions.is(pg_temp.stage_entry_probe(mode),expected,label) FROM (VALUES
 ('valid','Z0001:pass','entry derives accounted stage without refund witnesses'),
 ('existing','Z0001:pass','entry preserves completed accounting without producing another event'),
 ('suppressed','55000:initial_analysis_cancellation_incomplete','missing returned stage rolls back observed reconciliation'),
 ('late_failure','55000:late_stage_failure','late stage failure rolls back observed reconciliation'),
 ('immediate','55000:initial_analysis_cancellation_incomplete','immediate constraint failure rolls back observed reconciliation'),
 ('caller_variant','55000:initial_analysis_cancellation_incomplete','caller cannot select stage variant'),
 ('caller_prestate','55000:initial_analysis_cancellation_incomplete','caller cannot supply stage proof'),
 ('caller_xid','55000:initial_analysis_cancellation_incomplete','caller cannot supply current transaction identity'),
 ('caller_clock','55000:initial_analysis_cancellation_incomplete','caller cannot supply quota clock'),
 ('caller_phase','55000:initial_analysis_cancellation_incomplete','caller cannot select accounted phase'),
 ('duplicate','55000:initial_analysis_cancellation_incomplete','duplicate stage fails atomically'),
 ('update','55000:initial_analysis_cancellation_incomplete','accounted stage cannot enter refund phase'),
 ('delete','55000:initial_analysis_cancellation_incomplete','accounted stage cannot bypass terminal cleanup'),
 ('ledger_insert','55000:initial_analysis_cancellation_incomplete','visible stage blocks zero-row usage insertion'),
 ('ledger_update','55000:initial_analysis_cancellation_incomplete','visible stage blocks no-op usage update'),
 ('ledger_delete','55000:initial_analysis_cancellation_incomplete','visible stage blocks zero-row usage deletion'),
 ('ledger_service','55000:initial_analysis_cancellation_incomplete','actual service-role ledger statement reaches stage freeze without private-table privilege leakage'),
 ('unfinished','55000:initial_analysis_cancellation_incomplete','unfinished accounted stage cannot satisfy deferred completion'),
 ('public_hold','Z0001:pass','public accounted composer completes original proof chain without refund'),
 ('unused_seal','55000:initial_analysis_cancellation_incomplete','actual completed unused C1 seals usage statements after stage cleanup')
) cases(mode,expected,label);
CREATE FUNCTION pg_temp.service_usage_probe() RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE code TEXT; detail TEXT;
BEGIN
 BEGIN
  PERFORM set_config('request.jwt.claim.role','service_role',TRUE);
  SET LOCAL ROLE service_role;
  INSERT INTO public.ai_usage_events(operation,model) VALUES('scan_identification','gemini-2.5-flash');
  INSERT INTO public.ai_usage_events(id) SELECT gen_random_uuid() WHERE FALSE;
  UPDATE public.ai_usage_events SET outcome=outcome WHERE FALSE;
  DELETE FROM public.ai_usage_events WHERE FALSE;
  RESET ROLE;
  RAISE EXCEPTION 'pass' USING ERRCODE='Z0001';
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,detail=MESSAGE_TEXT;
 END;
 RETURN code||':'||detail;
END; $$;
SELECT extensions.is(pg_temp.service_usage_probe(),'Z0001:pass','actual service-role ledger insert and empty statements remain usable outside C1');
SELECT extensions.ok(pg_temp.cancellation_snapshot()=(SELECT image FROM cancellation_before),'all entry failures restore exact accounting funding stage and private images');
SELECT extensions.ok(NOT has_function_privilege(role_name,'internal.begin_initial_cancellation_stage(uuid,uuid)','EXECUTE'),role_name||' cannot invoke private stage entry')
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.initial_cancellation_seal_catalog() WHERE relation_name='public.ai_usage_events')
 AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ai_usage_events'::REGCLASS AND tgname='a00_initial_cancellation_seal'
  AND tgenabled='O' AND tgfoid='internal.guard_initial_cancellation_seal()'::REGPROCEDURE),
 'usage ledger is in both the terminal seal catalog and actual enabled trigger installation');
-- Witness mechanics only: the original retirement/provider row barriers may
-- be isolated below inside rollback. Mandatory new statement/row/witness guards
-- stay enabled, and the real authority-closed case keeps every barrier enabled.
-- Deferred stage completion and original invocation erasure are never waived:
-- successful mechanics deliberately roll back before transaction completion.
CREATE TEMP TABLE unrelated_witness_attack(phase TEXT);
CREATE TEMP SEQUENCE witness_preadvance_seen;
CREATE FUNCTION pg_temp.unrelated_witness_advance() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 UPDATE internal.initial_cancellation_invocation_witness SET phase=NEW.phase WHERE scan_id=(SELECT scan FROM fixture);
 RETURN NEW;
END; $$;
CREATE TRIGGER unrelated_witness_advance AFTER INSERT ON unrelated_witness_attack
 FOR EACH ROW EXECUTE FUNCTION pg_temp.unrelated_witness_advance();
CREATE FUNCTION pg_temp.suppress_invocation_row() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN RETURN NULL; END; $$;
CREATE FUNCTION pg_temp.extra_invocation_statement() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN UPDATE internal.identification_invocations SET event_id=event_id WHERE FALSE; RETURN NEW; END; $$;
CREATE FUNCTION pg_temp.invocation_witness_probe(mode TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE scan UUID; inv_id UUID; other_id UUID:=gen_random_uuid(); stage internal.initial_admitted_cancellation_staging;
 witness internal.initial_cancellation_invocation_witness; code TEXT; detail TEXT;
BEGIN
 SELECT f.scan,f.invocation INTO STRICT scan,inv_id FROM fixture f;
 PERFORM setval('pg_temp.witness_preadvance_seen',1,FALSE);
 BEGIN
  PERFORM set_config('request.jwt.claim.role','service_role',TRUE);
  IF mode='completed' THEN PERFORM internal.complete_identification_usage(inv_id,'draft','{"input_tokens":21,"candidate_tokens":8,"total_tokens":29}'::JSONB); END IF;
  IF mode<>'authority_closed' THEN
   ALTER TABLE internal.identification_invocations DISABLE TRIGGER a00_initial_invocation_authority;
   ALTER TABLE internal.identification_invocations DISABLE TRIGGER a0_initial_preparation_provider_barrier;
  END IF;
  IF mode='multirow' THEN
   INSERT INTO internal.identification_invocations SELECT (jsonb_populate_record(NULL::internal.identification_invocations,
    to_jsonb(i)||jsonb_build_object('id',other_id,'is_initial_analysis',FALSE,'initial_admission_receipt_id',NULL,
     'scan_id',NULL,'reservation_id',NULL,'user_id',NULL,'event_id',NULL,'lease_sha256',NULL))).*
    FROM internal.identification_invocations i WHERE i.id=inv_id;
  END IF;
  IF mode='no_stage' THEN
   INSERT INTO internal.initial_cancellation_invocation_witness(scan_id) VALUES(scan);
   RAISE EXCEPTION 'witness without stage unexpectedly opened';
  END IF;
  stage:=internal.begin_initial_cancellation_stage('00000000-0000-4000-8000-00000000f001',scan);
  IF mode='foreign_scan' THEN
   INSERT INTO internal.initial_cancellation_invocation_witness(scan_id) VALUES(other_id);
  ELSIF mode='supplied_expected' THEN
   INSERT INTO internal.initial_cancellation_invocation_witness(scan_id,expected) VALUES(scan,'{}');
  ELSIF mode='supplied_event' THEN
   INSERT INTO internal.initial_cancellation_invocation_witness(scan_id,event_image) VALUES(scan,'{}');
  ELSIF mode='supplied_phase' THEN
   INSERT INTO internal.initial_cancellation_invocation_witness(scan_id,phase) VALUES(scan,'writing');
  END IF;
  IF mode<>'missing_witness' THEN
   INSERT INTO internal.initial_cancellation_invocation_witness(scan_id) VALUES(scan) RETURNING * INTO witness;
   IF witness.phase IS DISTINCT FROM 'pending' OR witness.expected IS DISTINCT FROM internal.initial_cancellation_invocation_event(stage)
    OR witness.event_image IS DISTINCT FROM stage.prestate->'event' THEN RAISE EXCEPTION 'witness derivation failed'; END IF;
  END IF;
  CASE mode
   WHEN 'duplicate' THEN INSERT INTO internal.initial_cancellation_invocation_witness(scan_id) VALUES(scan);
   WHEN 'direct_writing' THEN UPDATE internal.initial_cancellation_invocation_witness SET phase='writing' WHERE scan_id=scan;
   WHEN 'direct_complete' THEN UPDATE internal.initial_cancellation_invocation_witness SET phase='complete' WHERE scan_id=scan;
   WHEN 'delete_witness' THEN DELETE FROM internal.initial_cancellation_invocation_witness WHERE scan_id=scan;
   WHEN 'truncate_witness' THEN TRUNCATE internal.initial_cancellation_invocation_witness;
   WHEN 'foreign_writing' THEN
    INSERT INTO unrelated_witness_attack VALUES('writing');
    IF (SELECT phase FROM internal.initial_cancellation_invocation_witness WHERE scan_id=scan) IS DISTINCT FROM 'writing' THEN
     RAISE EXCEPTION 'unrelated preadvance fixture incomplete'; END IF;
    PERFORM nextval('pg_temp.witness_preadvance_seen');
   WHEN 'foreign_observed' THEN INSERT INTO unrelated_witness_attack VALUES('writing'); INSERT INTO unrelated_witness_attack VALUES('observed');
   WHEN 'foreign_complete' THEN INSERT INTO unrelated_witness_attack VALUES('complete');
   WHEN 'zero_rows' THEN UPDATE internal.identification_invocations SET user_id=NULL,scan_id=NULL,reservation_id=NULL,lease_sha256=NULL,initial_admission_receipt_id=NULL WHERE FALSE;
   WHEN 'noop' THEN UPDATE internal.identification_invocations SET event_id=event_id WHERE id=inv_id;
   WHEN 'insert_statement' THEN INSERT INTO internal.identification_invocations(id) SELECT gen_random_uuid() WHERE FALSE;
   WHEN 'delete_statement' THEN DELETE FROM internal.identification_invocations WHERE FALSE;
   WHEN 'suppressed' THEN CREATE TRIGGER zzzz_suppress_invocation BEFORE UPDATE ON internal.identification_invocations
    FOR EACH ROW EXECUTE FUNCTION pg_temp.suppress_invocation_row();
   WHEN 'nested_extra' THEN CREATE TRIGGER zzzz_extra_invocation AFTER UPDATE ON internal.identification_invocations
    FOR EACH ROW EXECUTE FUNCTION pg_temp.extra_invocation_statement();
   WHEN 'quota_noop' THEN UPDATE internal.ai_quota_reservations SET state=state WHERE FALSE;
   WHEN 'counter_noop' THEN UPDATE internal.ai_quota_counters SET request_count=request_count WHERE FALSE;
   WHEN 'credit_noop' THEN DELETE FROM internal.complimentary_scan_usage WHERE FALSE;
   WHEN 'owner_noop' THEN UPDATE public.users SET entitlement_version=entitlement_version WHERE FALSE;
   WHEN 'attempt_noop' THEN DELETE FROM internal.identification_provider_attempts WHERE FALSE;
   WHEN 'link_noop' THEN DELETE FROM internal.ai_quota_reservation_counters WHERE FALSE;
   ELSE NULL;
  END CASE;
  UPDATE internal.identification_invocations SET user_id=NULL,scan_id=NULL,reservation_id=NULL,lease_sha256=NULL,initial_admission_receipt_id=NULL,
   model=CASE WHEN mode='wrong_new' THEN 'wrong-model' ELSE model END WHERE id=inv_id OR (mode='multirow' AND id=other_id);
  IF mode='extra_statement' THEN UPDATE internal.identification_invocations SET event_id=event_id WHERE FALSE; END IF;
  SELECT * INTO STRICT witness FROM internal.initial_cancellation_invocation_witness WHERE scan_id=scan;
  IF witness.phase IS DISTINCT FROM 'complete' OR witness.expected IS DISTINCT FROM internal.initial_cancellation_invocation_event(stage)
   OR witness.event_image IS DISTINCT FROM stage.prestate->'event'
   OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=scan)
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=scan) THEN
   RAISE EXCEPTION 'statement-observed witness completion failed'; END IF;
  PERFORM internal.assert_initial_cancellation_accounted_images(stage,TRUE);
  IF mode='unfinished' THEN SET CONSTRAINTS ALL IMMEDIATE; END IF;
  RAISE EXCEPTION 'pass' USING ERRCODE='Z0001';
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,detail=MESSAGE_TEXT;
 END;
 IF mode='foreign_writing' AND NOT (SELECT is_called FROM pg_temp.witness_preadvance_seen) THEN
  RETURN 'Z0003:unrelated preadvance was not observed'; END IF;
 RETURN code||':'||detail;
END; $$;
SELECT extensions.is(pg_temp.invocation_witness_probe(mode),expected,label) FROM (VALUES
 ('valid','Z0001:pass','exact invocation update completes only the mechanical witness'),
 ('completed','Z0001:pass','witness preserves previously completed event and funding'),
 ('authority_closed','Z0001:pass','real retirement authority accepts only the exact current writing witness'),
 ('no_stage','55000:initial_analysis_cancellation_incomplete','witness requires original current stage'),
 ('foreign_scan','55000:initial_analysis_cancellation_incomplete','witness rejects another scan'),
 ('supplied_expected','55000:initial_analysis_cancellation_incomplete','caller cannot supply invocation expectation'),
 ('supplied_event','55000:initial_analysis_cancellation_incomplete','caller cannot supply event image'),
 ('supplied_phase','55000:initial_analysis_cancellation_incomplete','caller cannot preselect progress'),
 ('duplicate','55000:initial_analysis_cancellation_incomplete','duplicate witness is rejected'),
 ('direct_writing','55000:initial_analysis_cancellation_incomplete','direct writing progress is rejected'),
 ('direct_complete','55000:initial_analysis_cancellation_incomplete','direct completion is rejected'),
 ('delete_witness','55000:initial_analysis_cancellation_incomplete','witness cannot bypass terminal cleanup'),
 ('truncate_witness','55000:initial_analysis_cancellation_incomplete','empty or pending witness cannot be truncated'),
 ('foreign_writing','55000:initial_analysis_cancellation_incomplete','unrelated nested preadvance grants no usable invocation authority'),
 ('foreign_observed','55000:initial_analysis_cancellation_incomplete','unrelated nested observation requires actual retired invocation'),
 ('foreign_complete','55000:initial_analysis_cancellation_incomplete','unrelated nested completion without invocation change fails'),
 ('missing_witness','55000:initial_analysis_cancellation_incomplete','invocation update requires the exact witness'),
 ('zero_rows','55000:initial_analysis_cancellation_incomplete','zero-row invocation statement cannot complete witness'),
 ('noop','55000:initial_analysis_cancellation_incomplete','no-op invocation update fails exact image proof'),
 ('wrong_new','55000:initial_analysis_cancellation_incomplete','extra invocation field change fails exact image proof'),
 ('multirow','55000:initial_analysis_cancellation_incomplete','extra invocation row fails one-row statement proof'),
 ('insert_statement','55000:initial_analysis_cancellation_incomplete','visible stage denies even empty invocation INSERT'),
 ('delete_statement','55000:initial_analysis_cancellation_incomplete','visible stage denies even empty invocation DELETE'),
 ('suppressed','55000:initial_analysis_cancellation_incomplete','suppressed invocation row cannot complete witness'),
 ('nested_extra','55000:initial_analysis_cancellation_incomplete','nested extra invocation statement cannot use observed progress'),
 ('extra_statement','55000:initial_analysis_cancellation_incomplete','completed witness cannot authorize another empty statement'),
 ('quota_noop','55000:initial_analysis_cancellation_incomplete','accounted stage denies zero-row quota mutation'),
 ('counter_noop','55000:initial_analysis_cancellation_incomplete','accounted stage denies zero-row counter mutation'),
 ('credit_noop','55000:initial_analysis_cancellation_incomplete','accounted stage denies zero-row credit mutation'),
 ('owner_noop','55000:initial_analysis_cancellation_incomplete','accounted stage denies zero-row owner mutation'),
 ('attempt_noop','55000:initial_analysis_cancellation_incomplete','accounted stage denies zero-row provider-attempt mutation'),
 ('link_noop','55000:initial_analysis_cancellation_incomplete','accounted stage denies zero-row quota-link mutation'),
 ('unfinished','55000:initial_analysis_cancellation_incomplete','mechanical witness does not satisfy held transaction completion')
) cases(mode,expected,label);
SELECT extensions.ok(pg_temp.cancellation_snapshot()=(SELECT image FROM cancellation_before),'all witness attacks and mechanical success roll back exact stage funding ledger invocation and private images');
SELECT extensions.ok(relrowsecurity,'invocation witness RLS enabled') FROM pg_class
 WHERE oid='internal.initial_cancellation_invocation_witness'::REGCLASS;
SELECT extensions.ok(NOT has_table_privilege(role_name,'internal.initial_cancellation_invocation_witness','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),
 role_name||' cannot access invocation witness') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;

-- Lifecycle mechanics use the same rollback-only isolation as invocation
-- mechanics. A dispatch-authorized prestate is injected before capture with
-- only the unavailable dispatch transition guard briefly disabled; all guards
-- are restored before the lifecycle witness begins.
CREATE FUNCTION pg_temp.lifecycle_witness_probe(mode TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE scan UUID; inv_id UUID; stage internal.initial_admitted_cancellation_staging;
 witness internal.initial_cancellation_lifecycle_witness; expected_event JSONB; terminal_state TEXT; code TEXT; detail TEXT;
BEGIN
 SELECT f.scan,f.invocation INTO STRICT scan,inv_id FROM fixture f;
 BEGIN
  PERFORM set_config('request.jwt.claim.role','service_role',TRUE);
  ALTER TABLE internal.identification_invocations DISABLE TRIGGER a00_initial_invocation_authority;
  ALTER TABLE internal.identification_invocations DISABLE TRIGGER a0_initial_preparation_provider_barrier;
  IF mode IN ('dispatched','dispatched_completed') THEN
   ALTER TABLE internal.initial_analysis_lifecycle_fences DISABLE TRIGGER guard_initial_lifecycle_fence;
   UPDATE internal.initial_analysis_lifecycle_fences SET state='dispatch_authorized' WHERE scan_id=scan;
   ALTER TABLE internal.initial_analysis_lifecycle_fences ENABLE TRIGGER guard_initial_lifecycle_fence;
  END IF;
  IF mode IN ('completed','dispatched_completed') THEN
   PERFORM internal.complete_identification_usage(inv_id,'draft','{"input_tokens":21,"candidate_tokens":8,"total_tokens":29}'::JSONB);
  END IF;
  stage:=internal.begin_initial_cancellation_stage('00000000-0000-4000-8000-00000000f001',scan);
  expected_event:=internal.initial_cancellation_lifecycle_event(stage);
  terminal_state:=CASE WHEN mode IN ('dispatched','dispatched_completed') THEN 'cancelled_dispatched' ELSE 'cancelled_unknown' END;
  IF expected_event#>>'{new,state}' IS DISTINCT FROM terminal_state THEN RAISE EXCEPTION 'wrong derived lifecycle'; END IF;
  IF mode='missing_invocation' THEN
   PERFORM internal.advance_initial_cancellation_lifecycle(stage.owner_id,scan,terminal_state,'begin');
   RAISE EXCEPTION 'missing invocation prerequisite accepted';
  END IF;
  INSERT INTO internal.initial_cancellation_invocation_witness(scan_id) VALUES(scan);
  IF mode='pending_invocation' THEN
   PERFORM internal.advance_initial_cancellation_lifecycle(stage.owner_id,scan,terminal_state,'begin');
   RAISE EXCEPTION 'pending invocation prerequisite accepted';
  END IF;
  UPDATE internal.identification_invocations SET user_id=NULL,scan_id=NULL,reservation_id=NULL,lease_sha256=NULL,initial_admission_receipt_id=NULL WHERE id=inv_id;
  IF mode='mixed_credit' THEN INSERT INTO internal.initial_cancellation_credit_witness(scan_id) VALUES(scan); END IF;
  IF mode='no_lifecycle_witness' THEN
   UPDATE internal.initial_analysis_lifecycle_fences SET state=terminal_state WHERE scan_id=scan;
   RAISE EXCEPTION 'missing lifecycle witness accepted';
  END IF;
  IF mode='supplied_event' THEN
   INSERT INTO internal.initial_cancellation_lifecycle_witness(scan_id,event) VALUES(scan,expected_event);
  END IF;
  PERFORM internal.advance_initial_cancellation_lifecycle(stage.owner_id,scan,
   CASE WHEN mode='refund_terminal' THEN 'cancelled_pre_dispatch' WHEN mode='wrong_terminal' THEN 'cancelled_dispatched' ELSE terminal_state END,'begin');
  IF mode='duplicate_begin' THEN PERFORM internal.advance_initial_cancellation_lifecycle(stage.owner_id,scan,terminal_state,'begin'); END IF;
  IF mode='direct_observed' THEN UPDATE internal.initial_cancellation_lifecycle_witness SET phase='observed',event=expected_event WHERE scan_id=scan; END IF;
  IF mode='early_end' THEN PERFORM internal.advance_initial_cancellation_lifecycle(stage.owner_id,scan,terminal_state,'end'); END IF;
  IF mode='suppressed' THEN CREATE TRIGGER zzzz_suppress_lifecycle BEFORE UPDATE ON internal.initial_analysis_lifecycle_fences
   FOR EACH ROW EXECUTE FUNCTION pg_temp.suppress_invocation_row(); END IF;
  UPDATE internal.initial_analysis_lifecycle_fences SET state=terminal_state WHERE scan_id=scan AND mode<>'zero_rows';
  IF mode='extra_update' THEN UPDATE internal.initial_analysis_lifecycle_fences SET state=state WHERE scan_id=scan; END IF;
  PERFORM internal.advance_initial_cancellation_lifecycle(stage.owner_id,scan,terminal_state,'end');
  SELECT * INTO STRICT witness FROM internal.initial_cancellation_lifecycle_witness WHERE scan_id=scan;
  IF witness.phase IS DISTINCT FROM 'complete' OR witness.event IS DISTINCT FROM expected_event
   OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=scan) IS DISTINCT FROM expected_event->'new'
   OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements WHERE scan_id=scan)
   OR EXISTS(SELECT 1 FROM internal.initial_cancellation_credit_witness WHERE scan_id=scan)
   OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=scan)
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=scan) THEN
   RAISE EXCEPTION 'lifecycle completion images incorrect'; END IF;
  PERFORM internal.assert_initial_cancellation_accounted_images(stage,TRUE);
  IF mode='unfinished' THEN SET CONSTRAINTS ALL IMMEDIATE; END IF;
  IF mode='media_still_held' THEN
   INSERT INTO internal.initial_cancellation_terminal_snapshot(scan_id) VALUES(scan);
   RAISE EXCEPTION 'incomplete terminal proof unexpectedly accepted';
  END IF;
  RAISE EXCEPTION 'pass' USING ERRCODE='Z0001';
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,detail=MESSAGE_TEXT;
 END;
 RETURN code||':'||detail;
END; $$;
SELECT extensions.is(pg_temp.lifecycle_witness_probe(mode),expected,label) FROM (VALUES
 ('valid','Z0001:pass','known pending lifecycle derives unknown cancellation without refund'),
 ('dispatched','Z0001:pass','known dispatched lifecycle derives dispatched cancellation without refund'),
 ('completed','Z0001:pass','pending lifecycle preserves completed usage and funding'),
 ('dispatched_completed','Z0001:pass','dispatched lifecycle preserves completed usage and funding'),
 ('missing_invocation','55000:initial_analysis_cancellation_incomplete','lifecycle requires invocation witness'),
 ('pending_invocation','55000:initial_analysis_cancellation_incomplete','lifecycle requires completed invocation retirement'),
 ('mixed_credit','55000:initial_analysis_cancellation_incomplete','accounted lifecycle cannot enter refund witness family'),
 ('no_lifecycle_witness','55000:initial_analysis_cancellation_incomplete','lifecycle row requires exact pending lifecycle witness'),
 ('supplied_event','55000:initial_analysis_cancellation_incomplete','caller cannot supply observed lifecycle event'),
 ('refund_terminal','55000:initial_analysis_cancellation_incomplete','known invocation cannot select refundable cancellation'),
 ('wrong_terminal','55000:initial_analysis_cancellation_incomplete','pending invocation cannot select dispatched cancellation'),
 ('duplicate_begin','55000:initial_analysis_cancellation_incomplete','duplicate lifecycle begin fails closed'),
 ('direct_observed','55000:initial_analysis_cancellation_incomplete','unobserved lifecycle progress fails closed'),
 ('early_end','55000:initial_analysis_cancellation_incomplete','lifecycle end requires an actual row update'),
 ('suppressed','55000:initial_analysis_cancellation_incomplete','suppressed lifecycle update cannot complete witness'),
 ('zero_rows','55000:initial_analysis_cancellation_incomplete','zero-row lifecycle update cannot complete witness'),
 ('extra_update','22023:initial_analysis_lifecycle_immutable','observed lifecycle witness denies extra row mutation'),
 ('unfinished','55000:initial_analysis_cancellation_incomplete','completed lifecycle witness cannot bypass deferred transaction hold'),
 ('media_still_held','55000:initial_analysis_cancellation_incomplete','terminal proof still rejects incomplete lifecycle-only transaction')
) cases(mode,expected,label);
SELECT extensions.ok(pg_temp.cancellation_snapshot()=(SELECT image FROM cancellation_before),'all lifecycle mechanics roll back exact funding usage invocation lifecycle witnesses and private roots');


CREATE FUNCTION pg_temp.shared_erasure_probe(mode TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE scan UUID; inv_id UUID; stage internal.initial_admitted_cancellation_staging;
 terminal_state TEXT; expected_receipt JSONB; images JSONB; code TEXT; detail TEXT;
BEGIN
 SELECT f.scan,f.invocation INTO STRICT scan,inv_id FROM fixture f;
 BEGIN
  PERFORM set_config('request.jwt.claim.role','service_role',TRUE);
  -- Mechanical integration only: preserve the real retirement-authority hold.
  ALTER TABLE internal.identification_invocations DISABLE TRIGGER a00_initial_invocation_authority;
  ALTER TABLE internal.identification_invocations DISABLE TRIGGER a0_initial_preparation_provider_barrier;
  IF mode IN ('dispatched','dispatched_completed') THEN
   ALTER TABLE internal.initial_analysis_lifecycle_fences DISABLE TRIGGER guard_initial_lifecycle_fence;
   UPDATE internal.initial_analysis_lifecycle_fences SET state='dispatch_authorized' WHERE scan_id=scan;
   ALTER TABLE internal.initial_analysis_lifecycle_fences ENABLE TRIGGER guard_initial_lifecycle_fence;
  END IF;
  IF mode IN ('completed','dispatched_completed') THEN
   PERFORM internal.complete_identification_usage(inv_id,'draft','{"input_tokens":21,"candidate_tokens":8,"total_tokens":29}'::JSONB);
  END IF;
  stage:=internal.begin_initial_cancellation_stage('00000000-0000-4000-8000-00000000f001',scan);
  INSERT INTO internal.initial_cancellation_invocation_witness(scan_id) VALUES(scan);
  UPDATE internal.identification_invocations SET user_id=NULL,scan_id=NULL,reservation_id=NULL,lease_sha256=NULL,initial_admission_receipt_id=NULL WHERE id=inv_id;
  IF mode='before_lifecycle' THEN PERFORM internal.retire_initial_preparation_source_objects(scan); END IF;
  terminal_state:=internal.initial_cancellation_lifecycle_event(stage)#>>'{new,state}';
  expected_receipt:=internal.initial_cancellation_receipt_image(stage);
  IF expected_receipt->>'dispatch' IS DISTINCT FROM (CASE WHEN mode IN ('dispatched','dispatched_completed')
   THEN 'dispatch_already_authorized' ELSE 'dispatch_outcome_unknown' END) THEN
   RAISE EXCEPTION 'incorrect receipt derivation'; END IF;
  PERFORM internal.advance_initial_cancellation_lifecycle(stage.owner_id,scan,terminal_state,'begin');
  UPDATE internal.initial_analysis_lifecycle_fences SET state=terminal_state WHERE scan_id=scan;
  PERFORM internal.advance_initial_cancellation_lifecycle(stage.owner_id,scan,terminal_state,'end');
  IF mode='destination_first' THEN PERFORM internal.retire_initial_media_objects(scan); END IF;
  IF mode='root_before_media' THEN PERFORM internal.erase_initial_cancellation_private_root(scan,'submission'); END IF;
  IF mode='supplied_media' THEN INSERT INTO internal.initial_cancellation_retirement_witness(scan_id,side,expected) VALUES(scan,'source','[]'); END IF;
  IF mode='unobserved_media' THEN
   INSERT INTO internal.initial_cancellation_retirement_witness(scan_id,side) VALUES(scan,'source');
   IF (SELECT jsonb_array_length(expected) FROM internal.initial_cancellation_retirement_witness WHERE scan_id=scan AND side='source')=0 THEN
    RAISE EXCEPTION 'unobserved media fixture requires real row events'; END IF;
   UPDATE internal.initial_cancellation_retirement_witness SET phase='complete' WHERE scan_id=scan AND side='source';
  END IF;
  PERFORM internal.retire_initial_preparation_source_objects(scan);
  PERFORM internal.retire_initial_media_objects(scan);
  IF mode='media_reentry' THEN
   PERFORM internal.retire_initial_preparation_source_objects(scan); PERFORM internal.retire_initial_media_objects(scan);
  END IF;
  IF mode='intent_first' THEN PERFORM internal.erase_initial_cancellation_private_root(scan,'intent'); END IF;
  IF mode='early_receipt' THEN PERFORM internal.write_initial_cancellation_receipt(scan); END IF;
  IF mode='direct_root' THEN DELETE FROM internal.initial_analysis_submissions WHERE scan_id=scan; END IF;
  IF mode='supplied_erasure' THEN
   INSERT INTO internal.initial_cancellation_erasure_witness(scan_id,root_name,accounting_images) VALUES(scan,'submission','{}');
  END IF;
  IF mode='unobserved_erasure' THEN
   INSERT INTO internal.initial_cancellation_erasure_witness(scan_id,root_name) VALUES(scan,'submission');
   UPDATE internal.initial_cancellation_erasure_witness SET phase='complete' WHERE scan_id=scan AND root_name='submission';
  END IF;
  PERFORM internal.erase_initial_cancellation_private_root(scan,'submission');
  IF EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=scan) THEN
   RAISE EXCEPTION 'submission cascade left receipt'; END IF;
  -- These post-erasure checks must use frozen surviving identities only.
  images:=internal.capture_initial_cancellation_accounting_images(stage);
  IF images->'invocation' IS DISTINCT FROM internal.initial_cancellation_invocation_event(stage)->'new'
   OR images->'event' IS DISTINCT FROM stage.prestate->'event'
   OR (SELECT accounting_images FROM internal.initial_cancellation_erasure_witness WHERE scan_id=scan AND root_name='submission')
      IS DISTINCT FROM images THEN RAISE EXCEPTION 'frozen accounting lost after receipt deletion'; END IF;
  IF mode='after_submission_funding' THEN UPDATE internal.ai_quota_counters SET request_count=request_count WHERE FALSE; END IF;
  IF mode='after_submission_usage' THEN DELETE FROM public.ai_usage_events WHERE FALSE; END IF;
  PERFORM internal.erase_initial_cancellation_private_root(scan,'intent');
  IF mode='wrong_receipt_boundary' THEN
   PERFORM internal.assert_initial_cancellation_erasure_boundary(stage,expected_receipt||'{"dispatch":"dispatch_prevented"}'::JSONB);
  END IF;
  IF mode='supplied_receipt' THEN INSERT INTO internal.initial_cancellation_receipt_witness(scan_id,expected) VALUES(scan,expected_receipt); END IF;
  IF mode='unobserved_receipt' THEN
   INSERT INTO internal.initial_cancellation_receipt_witness(scan_id) VALUES(scan);
   UPDATE internal.initial_cancellation_receipt_witness SET phase='complete' WHERE scan_id=scan;
  END IF;
  PERFORM internal.write_initial_cancellation_receipt(scan);
  IF mode='duplicate_receipt' THEN PERFORM internal.write_initial_cancellation_receipt(scan); END IF;
  PERFORM internal.assert_initial_cancellation_receipt_boundary(stage,TRUE);
  IF (SELECT to_jsonb(c) FROM internal.initial_analysis_cancellations c WHERE scan_id=scan) IS DISTINCT FROM expected_receipt
   OR (SELECT count(*) FROM internal.initial_cancellation_retirement_witness WHERE scan_id=scan AND phase='complete')<>2
   OR (SELECT count(*) FROM internal.initial_cancellation_erasure_witness WHERE scan_id=scan AND phase='complete')<>2
   OR (SELECT count(*) FROM internal.initial_cancellation_receipt_witness WHERE scan_id=scan AND phase='complete' AND observed)<>1
   OR internal.capture_initial_cancellation_accounting_images(stage) IS DISTINCT FROM images THEN
   RAISE EXCEPTION 'shared erasure final images incorrect'; END IF;
  IF mode='terminal_still_held' THEN
   INSERT INTO internal.initial_cancellation_terminal_snapshot(scan_id) VALUES(scan); SET CONSTRAINTS ALL IMMEDIATE; END IF;
  IF mode='unfinished' THEN SET CONSTRAINTS ALL IMMEDIATE; END IF;
  RAISE EXCEPTION 'pass' USING ERRCODE='Z0001';
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,detail=MESSAGE_TEXT;
 END;
 RETURN code||':'||detail;
END; $$;
SELECT extensions.is(pg_temp.shared_erasure_probe(mode),expected,label) FROM (VALUES
 ('valid','Z0001:pass','pending unknown accounting survives guarded media and private erasure through receipt'),
 ('dispatched','Z0001:pass','authorized dispatch produces already-authorized receipt after exact erasure'),
 ('completed','Z0001:pass','completed usage survives pending cancellation through private receipt erasure'),
 ('dispatched_completed','Z0001:pass','completed dispatched usage survives exact root cascade and matching receipt'),
 ('media_reentry','Z0001:pass','completed media retirement permits exact zero-write reentry'),
 ('before_lifecycle','55000:initial_analysis_cancellation_incomplete','media retirement requires completed lifecycle witness'),
 ('destination_first','55000:initial_analysis_cancellation_incomplete','destination retirement requires completed source retirement'),
 ('root_before_media','55000:initial_analysis_cancellation_incomplete','private erasure requires both media retirements'),
 ('supplied_media','55000:initial_analysis_cancellation_incomplete','caller cannot supply media retirement images'),
 ('unobserved_media','55000:initial_analysis_cancellation_incomplete','media retirement completion requires observed exact rows'),
 ('intent_first','55000:initial_analysis_cancellation_incomplete','intent erasure cannot precede submission erasure'),
 ('early_receipt','55000:initial_analysis_cancellation_incomplete','receipt requires both complete root erasures'),
 ('direct_root','55000:initial_analysis_cancellation_incomplete','direct root delete cannot bypass erasure witness'),
 ('supplied_erasure','55000:initial_analysis_cancellation_incomplete','caller cannot supply erasure accounting images'),
 ('unobserved_erasure','55000:initial_analysis_cancellation_incomplete','private erasure cannot complete without observed cascade'),
 ('after_submission_funding','55000:initial_analysis_cancellation_incomplete','funding remains frozen after original receipt deletion'),
 ('after_submission_usage','55000:initial_analysis_cancellation_incomplete','usage remains frozen after original receipt deletion'),
 ('wrong_receipt_boundary','55000:initial_analysis_cancellation_incomplete','known execution cannot substitute prevented receipt'),
 ('supplied_receipt','55000:initial_analysis_cancellation_incomplete','caller cannot supply terminal receipt witness image'),
 ('unobserved_receipt','55000:initial_analysis_cancellation_incomplete','receipt completion requires actual observed insert'),
 ('duplicate_receipt','55000:initial_analysis_cancellation_incomplete','matching saved receipt cannot authorize another witness'),
 ('terminal_still_held','55000:initial_analysis_cancellation_incomplete','unconsumed terminal snapshot cannot satisfy deferred completion'),
 ('unfinished','55000:initial_analysis_cancellation_incomplete','complete shared erasure cannot bypass deferred accounted hold')
) cases(mode,expected,label);
SELECT extensions.ok(pg_temp.cancellation_snapshot()=(SELECT image FROM cancellation_before),'all media private and receipt mechanical cases roll back exact surviving and erased images');


-- Real accounted public cancellation: only the original future dispatch seed
-- above is injected. No invocation retirement/provider/cancellation guard is
-- disabled in these transactions. Captured synthetic images stay inside SQL.
CREATE TEMP TABLE terminal_evidence(kind TEXT PRIMARY KEY,image JSONB);
CREATE FUNCTION pg_temp.observe_terminal_evidence() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO terminal_evidence(kind,image) VALUES(TG_OP,CASE WHEN TG_OP='INSERT' THEN to_jsonb(NEW) ELSE to_jsonb(OLD) END);
 RETURN NULL;
END; $$;
CREATE FUNCTION pg_temp.fail_terminal_cleanup() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN RAISE EXCEPTION 'terminal_cleanup_failure' USING ERRCODE='55000'; END; $$;
CREATE FUNCTION pg_temp.accounted_cancellation_probe(mode TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE scan UUID; inv_id UUID; response JSONB; before_funding JSONB; prior_event JSONB;
 stage internal.initial_admitted_cancellation_staging; proof JSONB; bad JSONB; code TEXT; detail TEXT;
 expected_dispatch TEXT; result_event JSONB; retained_result JSONB; before_call JSONB; retained_cpm JSONB;
BEGIN
 SELECT f.scan,f.invocation INTO STRICT scan,inv_id FROM fixture f;
 BEGIN
  PERFORM set_config('request.jwt.claim.role','service_role',TRUE);
  IF mode IN ('dispatched','dispatched_completed','frozen_dispatched') THEN
   -- Only unavailable initial dispatch state is injected; restore before C1.
   ALTER TABLE internal.initial_analysis_lifecycle_fences DISABLE TRIGGER guard_initial_lifecycle_fence;
   UPDATE internal.initial_analysis_lifecycle_fences SET state='dispatch_authorized' WHERE scan_id=scan;
   ALTER TABLE internal.initial_analysis_lifecycle_fences ENABLE TRIGGER guard_initial_lifecycle_fence;
  END IF;
  IF mode IN ('completed','dispatched_completed','frozen_completed') THEN
   PERFORM internal.complete_identification_usage(inv_id,'draft','{"input_tokens":21,"candidate_tokens":8,"total_tokens":29}'::JSONB);
   SELECT to_jsonb(e) INTO prior_event FROM public.ai_usage_events e WHERE id=(SELECT event_id FROM internal.identification_invocations WHERE id=inv_id);
  END IF;
  IF mode LIKE 'frozen_%' OR mode='completion_first' THEN
   -- Inject only future producer prestate; neither result production nor its
   -- semantic codec is qualified here. Restore both barriers before public C1.
   ALTER TABLE internal.initial_analysis_results DISABLE TRIGGER guard_initial_analysis_result;
   ALTER TABLE internal.initial_analysis_results DISABLE TRIGGER a0_initial_preparation_provider_barrier;
   INSERT INTO internal.initial_analysis_results(scan_id,owner_id,result_evidence_id,result_schema_version,result_snapshot,provenance_snapshot)
    VALUES(scan,'00000000-0000-4000-8000-00000000f001',gen_random_uuid(),1,
     '{"synthetic_cancellation_fixture":"immutable result","nested":{"values":[1,"original",null]}}','{"synthetic_cancellation_fixture":"original provenance"}');
   ALTER TABLE internal.initial_analysis_results ENABLE TRIGGER guard_initial_analysis_result;
   ALTER TABLE internal.initial_analysis_results ENABLE TRIGGER a0_initial_preparation_provider_barrier;
   SELECT to_jsonb(r) INTO STRICT retained_result FROM internal.initial_analysis_results r WHERE r.scan_id=scan;
   IF mode='completion_first' THEN
    ALTER TABLE internal.initial_analysis_completions DISABLE TRIGGER guard_initial_analysis_completion;
    ALTER TABLE internal.initial_analysis_completions DISABLE TRIGGER a0_initial_preparation_provider_barrier;
    INSERT INTO internal.initial_analysis_completions(scan_id,owner_id,result_evidence_id,receipt_version,receipt_snapshot)
     VALUES(scan,'00000000-0000-4000-8000-00000000f001',(retained_result->>'result_evidence_id')::UUID,1,'{}');
    ALTER TABLE internal.initial_analysis_completions ENABLE TRIGGER guard_initial_analysis_completion;
    ALTER TABLE internal.initial_analysis_completions ENABLE TRIGGER a0_initial_preparation_provider_barrier;
   END IF;
  END IF;
  before_funding:=pg_temp.cancellation_snapshot()-ARRAY['internal.identification_invocations','public.ai_usage_events'];
  CREATE TRIGGER zzzz_observe_terminal_stage AFTER INSERT ON internal.initial_admitted_cancellation_staging
   FOR EACH ROW EXECUTE FUNCTION pg_temp.observe_terminal_evidence();
  CREATE TRIGGER zzzz_observe_terminal_delete AFTER DELETE ON internal.initial_cancellation_terminal_snapshot
   FOR EACH ROW EXECUTE FUNCTION pg_temp.observe_terminal_evidence();
  IF mode='suppress_invocation_cleanup' THEN
   CREATE TRIGGER zzzz_suppress_invocation_cleanup BEFORE DELETE ON internal.initial_cancellation_invocation_witness
    FOR EACH ROW EXECUTE FUNCTION pg_temp.suppress_invocation_row();
  ELSIF mode='suppress_terminal_delete' THEN
   CREATE TRIGGER zzzz_suppress_terminal_delete BEFORE DELETE ON internal.initial_cancellation_terminal_snapshot
    FOR EACH ROW EXECUTE FUNCTION pg_temp.suppress_invocation_row();
  ELSIF mode IN ('late_cleanup_failure','frozen_late_failure') THEN
   CREATE TRIGGER zzzzz_fail_terminal AFTER DELETE ON internal.initial_cancellation_terminal_snapshot
    FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_terminal_cleanup();
  ELSIF mode='frozen_suppress' THEN
   CREATE TRIGGER zzzz_suppress_result_delete BEFORE DELETE ON internal.initial_analysis_results
    FOR EACH ROW EXECUTE FUNCTION pg_temp.suppress_invocation_row();
  ELSIF mode='immediate' THEN SET CONSTRAINTS ALL IMMEDIATE;
  END IF;
  retained_cpm:=pg_temp.cpm_retained_image(scan,TRUE);
  before_call:=pg_temp.cancellation_snapshot();
  BEGIN
   SET LOCAL ROLE service_role;
   response:=public.cancel_initial_analysis('00000000-0000-4000-8000-00000000f001',scan);
   RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
   IF pg_temp.cancellation_snapshot() IS DISTINCT FROM before_call THEN
    RAISE EXCEPTION 'failed cancellation changed original private result or funding'; END IF;
   RAISE;
  END;
  IF pg_temp.cpm_retained_image(scan) IS DISTINCT FROM retained_cpm
   OR EXISTS(SELECT 1 FROM internal.initial_cpm_photo_role_mapping m WHERE m.scan_id=scan) THEN
   RAISE EXCEPTION 'CPM cancellation changed original liability or left private roles'; END IF;
  expected_dispatch:=CASE WHEN mode IN ('dispatched','dispatched_completed','frozen_dispatched') THEN 'dispatch_already_authorized' ELSE 'dispatch_outcome_unknown' END;
  IF response IS DISTINCT FROM jsonb_build_object('version',1,'outcome','cancelled','dispatch',expected_dispatch) THEN
   RAISE EXCEPTION 'incorrect public cancellation reply'; END IF;
  SELECT (jsonb_populate_record(NULL::internal.initial_admitted_cancellation_staging,image)).* INTO STRICT stage FROM terminal_evidence WHERE kind='INSERT';
  SELECT image->'proof' INTO STRICT proof FROM terminal_evidence WHERE kind='DELETE';
  IF internal.initial_cancellation_cleanup_count(proof)<>8 OR stage.variant IS DISTINCT FROM 'accounted_invocation'
   OR stage.phase IS DISTINCT FROM 'accounted' OR stage.quota_at IS NOT NULL
   OR (SELECT (image->>'cleanup_cursor')::INTEGER FROM terminal_evidence WHERE kind='DELETE')<>8
   OR NOT internal.initial_cancellation_sealed() THEN RAISE EXCEPTION 'terminal proof did not consume exact eight rows'; END IF;
  IF retained_result IS NOT NULL AND
   (stage.prestate#>'{erasure_images,internal.initial_analysis_results}' IS DISTINCT FROM jsonb_build_array(retained_result)
    OR EXISTS(SELECT 1 FROM internal.initial_analysis_results r WHERE r.scan_id=scan)) THEN
   RAISE EXCEPTION 'retained result was not captured and erased exactly'; END IF;
  PERFORM internal.assert_initial_cancellation_transients_absent(scan);
  PERFORM internal.assert_initial_cancellation_accounted_final(stage);
  PERFORM internal.assert_initial_cancellation_terminal_survivors(proof);
  SELECT to_jsonb(e) INTO STRICT result_event FROM public.ai_usage_events e WHERE id=(stage.prestate#>>'{event,id}')::UUID;
  IF result_event IS DISTINCT FROM stage.prestate->'event'
   OR (prior_event IS NOT NULL AND result_event IS DISTINCT FROM prior_event)
   OR result_event->>'source_id' IS DISTINCT FROM inv_id::TEXT
   OR result_event->>'scan_id' IS DISTINCT FROM scan::TEXT THEN
   RAISE EXCEPTION 'cancellation altered original accounting'; END IF;
  -- Independently exercise both deferred proof orders after every live witness
  -- has disappeared; neither checker can depend on another checker firing.
  IF mode='stage_first' THEN
   SET CONSTRAINTS internal.require_complete_initial_admitted_cancellation IMMEDIATE;
   SET CONSTRAINTS internal.require_complete_initial_cancellation_snapshot IMMEDIATE;
  ELSIF mode='terminal_first' THEN
   SET CONSTRAINTS internal.require_complete_initial_cancellation_snapshot IMMEDIATE;
   SET CONSTRAINTS internal.require_complete_initial_admitted_cancellation IMMEDIATE;
  END IF;
  IF mode='mixed_proof' THEN
   bad:=jsonb_set(proof,'{rows,internal.initial_cancellation_credit_witness}',jsonb_build_array(jsonb_build_object('scan_id',scan)));
   PERFORM internal.assert_initial_cancellation_terminal_shape(bad);
   RAISE EXCEPTION 'mixed proof accepted';
  ELSIF mode='union17' THEN
   bad:=jsonb_set(proof,'{rows,internal.initial_cancellation_quota_statements}',(SELECT jsonb_agg(jsonb_build_object('scan_id',scan)) FROM generate_series(1,8)));
   bad:=jsonb_set(bad,'{rows,internal.initial_cancellation_credit_witness}',jsonb_build_array(jsonb_build_object('scan_id',scan)));
   PERFORM internal.assert_initial_cancellation_terminal_shape(bad);
   RAISE EXCEPTION 'seventeen-row union accepted';
  ELSIF mode='missing_invocation_proof' THEN
   PERFORM internal.assert_initial_cancellation_terminal_survivors(jsonb_set(proof,'{rows,internal.initial_cancellation_invocation_witness}','[]'));
  ELSIF mode='wrong_invocation_proof' THEN
   PERFORM internal.assert_initial_cancellation_terminal_survivors(jsonb_set(proof,'{rows,internal.initial_cancellation_invocation_witness,0,expected,old,id}',to_jsonb(gen_random_uuid())));
  ELSIF mode='wrong_event_proof' THEN
   PERFORM internal.assert_initial_cancellation_terminal_survivors(jsonb_set(proof,'{rows,internal.initial_cancellation_invocation_witness,0,event_image}','{}'));
  ELSIF mode='wrong_captured_stage' THEN
   stage.prestate:=jsonb_set(stage.prestate,'{invocation,id}',to_jsonb(gen_random_uuid()));
   PERFORM internal.assert_initial_cancellation_accounted_final(stage);
  ELSIF mode='sealed_usage' THEN UPDATE public.ai_usage_events SET outcome=outcome WHERE FALSE;
  ELSIF mode='sealed_funding' THEN UPDATE internal.ai_quota_counters SET request_count=request_count WHERE FALSE;
  ELSIF mode='sealed_invocation' THEN DELETE FROM internal.identification_invocations WHERE FALSE;
  ELSIF mode='sealed_witness' THEN DELETE FROM internal.initial_cancellation_invocation_witness WHERE FALSE;
  ELSIF mode='replay' THEN
   SET LOCAL ROLE service_role;
   IF public.cancel_initial_analysis(stage.owner_id,scan) IS DISTINCT FROM response THEN RAISE EXCEPTION 'saved receipt replay changed'; END IF;
   RESET ROLE;
   IF internal.complete_identification_usage(inv_id,'unknown_execution','{}') IS DISTINCT FROM (stage.prestate#>>'{event,id}')::UUID THEN
    RAISE EXCEPTION 'accounting replay did not reuse original event'; END IF;
  END IF;
  SET LOCAL ROLE service_role;
  SET CONSTRAINTS ALL IMMEDIATE;
  RESET ROLE;
  RAISE EXCEPTION 'pass' USING ERRCODE='Z0001';
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,detail=MESSAGE_TEXT;
 END;
 RETURN code||':'||detail;
END; $$;
SELECT extensions.is(pg_temp.accounted_cancellation_probe(mode),expected,label) FROM (VALUES
 ('frozen_pending','Z0001:pass','public cancellation captures and erases exact private result with every C1 guard enabled'),
 ('frozen_completed','Z0001:pass','private result cancellation preserves completed usage'),
 ('frozen_dispatched','Z0001:pass','dispatched cancellation erases exact private result without refund'),
 ('frozen_suppress','55000:initial_analysis_cancellation_incomplete','suppressed private result deletion restores exact result funding and accounting'),
 ('frozen_late_failure','55000:terminal_cleanup_failure','late terminal failure restores original private result and funding'),
 ('completion_first','55000:initial_analysis_already_complete','existing completion denies cancellation and preserves private result'),
 ('valid','Z0001:pass','real public pending cancellation consumes exact terminal proof without refund'),
 ('dispatched','Z0001:pass','real public dispatched cancellation preserves original funded accounting'),
 ('completed','Z0001:pass','real public cancellation preserves completed usage payload'),
 ('dispatched_completed','Z0001:pass','real dispatched completed cancellation preserves exact usage payload'),
 ('stage_first','Z0001:pass','captured stage proof completes before independent terminal proof'),
 ('terminal_first','Z0001:pass','captured terminal proof completes before independent stage proof'),
 ('replay','Z0001:pass','saved cancellation and accounting replay reuse immutable outcomes'),
 ('suppress_invocation_cleanup','55000:initial_analysis_cancellation_incomplete','suppressed invocation witness cleanup rolls back full cancellation'),
 ('suppress_terminal_delete','55000:initial_analysis_cancellation_incomplete','suppressed terminal deletion cannot escape complete cursor proof'),
 ('late_cleanup_failure','55000:terminal_cleanup_failure','failure after terminal cleanup rolls back accounting and private erasure'),
 ('immediate','55000:initial_analysis_cancellation_incomplete','immediate constraints reject premature stage before cancellation progresses'),
 ('mixed_proof','55000:initial_analysis_cancellation_incomplete','mixed witness families fail even below the sixteen-row limit'),
 ('union17','55000:initial_analysis_cancellation_incomplete','impossible seventeen-row witness union is rejected'),
 ('missing_invocation_proof','55000:initial_analysis_cancellation_incomplete','terminal survivor proof requires original invocation witness'),
 ('wrong_invocation_proof','55000:initial_analysis_cancellation_incomplete','terminal proof rejects another original invocation identity'),
 ('wrong_event_proof','55000:initial_analysis_cancellation_incomplete','terminal proof rejects changed original event'),
 ('wrong_captured_stage','55000:initial_analysis_cancellation_incomplete','captured stage independently rejects changed invocation identity'),
 ('sealed_usage','55000:initial_analysis_cancellation_incomplete','terminal seal denies zero-row usage mutation after cleanup'),
 ('sealed_funding','55000:initial_analysis_cancellation_incomplete','terminal seal denies zero-row funding mutation after cleanup'),
 ('sealed_invocation','55000:initial_analysis_cancellation_incomplete','terminal seal denies zero-row invocation deletion after cleanup'),
 ('sealed_witness','55000:initial_analysis_cancellation_incomplete','terminal seal denies zero-row cleaned witness deletion')
) cases(mode,expected,label);
SELECT extensions.ok(pg_temp.cancellation_snapshot()=(SELECT image FROM cancellation_before),'all real accounted cancellation probes preserve exact pre-call state after rollback');

SELECT extensions.is(pg_temp.erasure_probe('partial_clear'),'55000:initial_analysis_invocation_immutable','partial clear is denied');
SELECT extensions.is(pg_temp.erasure_probe('no_tombstone'),'55000:initial_analysis_invocation_erasure_unavailable','full clear without irreversible tombstone denied');
SELECT extensions.is(pg_temp.erasure_probe('wrong_receipt'),'55000:initial_analysis_invocation_erasure_unavailable','wrong original receipt rejects erasure');
SELECT extensions.is(pg_temp.erasure_probe('missing_receipt'),'55000:initial_analysis_invocation_erasure_unavailable','missing original receipt rejects erasure');
SELECT extensions.is(pg_temp.erasure_probe('root_left'),'55000:initial_analysis_invocation_erasure_incomplete','deferred captured-OLD proof rejects surviving private root');
SELECT extensions.is(pg_temp.erasure_probe('immediate'),'55000:initial_analysis_invocation_erasure_incomplete','immediate constraints reject early retirement atomically');
SELECT extensions.is(pg_temp.erasure_probe('event_changed'),'55000:initial_analysis_invocation_immutable','retirement cannot replace the accounting event');
SELECT extensions.is(pg_temp.erasure_probe('raw_owner_delete'),'Z0001:pass','raw owner erasure retires invocation before deleting owner');
SELECT extensions.is(pg_temp.erasure_probe('existing_tombstone'),'Z0001:pass','owner deletion handles an already-existing tombstone');
SELECT extensions.is(pg_temp.erasure_probe('invocation_only'),'55000:initial_analysis_invocation_erasure_unavailable','invocation-only existing-tombstone leftover is discovered and missing proof fails closed');
SELECT extensions.is(pg_temp.erasure_probe('generic_cancellation'),'55000:initial_analysis_cancellation_incomplete','known invocation generic cancellation holds before losing original receipt');
SELECT extensions.is(pg_temp.erasure_probe('reservation_alias'),'55000:initial_analysis_cancellation_incomplete','original reservation match holds even when invocation scan correlation differs');
SELECT extensions.is(pg_temp.erasure_probe('saved_cancellation'),'55000:initial_analysis_cancellation_incomplete','saved cancellation cannot replay past unresolved classified invocation');
SELECT extensions.is(pg_temp.erasure_probe('public_account'),'Z0001:pass','public account retires invocation before receipt erasure with retained accounting and unchanged funding');
SELECT extensions.is(pg_temp.erasure_probe('account_existing_tombstone'),'Z0001:pass','public account explicitly retires work behind an existing tombstone');
SELECT extensions.is(pg_temp.erasure_probe('account_alias'),'55000:initial_analysis_invocation_erasure_unavailable','public account rejects reservation alias before erasure');
SELECT extensions.is(pg_temp.erasure_probe('account_later_failure'),'55000:initial_analysis_invocation_erasure_unavailable','later corrupt identity rolls back an observed earlier retirement');
SELECT extensions.is(pg_temp.erasure_probe('account_science'),'Z0001:pass','public account composes classified retirement with retained scientific detachment');
SELECT extensions.is(pg_temp.erasure_probe('positive_unused'),'Z0001:pass','actual refundable C1 remains available for the unchanged positive-unused proof');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones t JOIN fixture f ON t.scan_id=f.scan)
 AND EXISTS(SELECT 1 FROM internal.identification_invocations i JOIN fixture f ON i.id=f.invocation WHERE i.event_id IS NULL AND i.initial_admission_receipt_id IS NOT NULL)
 AND EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts r JOIN fixture f ON r.scan_id=f.scan),'all probe changes roll back including unknown accounting and private erasure');
SELECT extensions.ok(pg_temp.cancellation_snapshot()=(SELECT image FROM cancellation_before),'all boundary probes preserve exact owner lifecycle funding accounting and private images after rollback');
SELECT extensions.lives_ok($$INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) SELECT scan,'00000000-0000-4000-8000-00000000f001',clock_timestamp() FROM fixture$$,'scan tombstone retires original invocation and private root');
SELECT extensions.lives_ok('SET CONSTRAINTS ALL IMMEDIATE','captured original identity proves complete erasure');
SELECT extensions.ok(internal.initial_invocation_retired(i),'all original correlation cleared while classification and event retained') FROM internal.identification_invocations i JOIN fixture f ON i.id=f.invocation;
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_submissions s JOIN fixture f ON s.scan_id=f.scan),0::BIGINT,'private submission erased');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_admission_receipts r JOIN fixture f ON r.scan_id=f.scan),0::BIGINT,'original receipt erased');
SELECT extensions.is((SELECT count(*) FROM public.ai_usage_events e JOIN fixture f ON e.source_id=f.invocation AND e.outcome='unknown'),1::BIGINT,'unknown usage reconciled exactly once');
SELECT extensions.is(internal.reconcile_identification_usage(1000),0,'retired accounting replay creates no event');
SELECT extensions.is((SELECT count(*) FROM internal.identification_invocations i JOIN fixture f ON i.id=f.invocation),0::BIGINT,'thirty-day pruning accepts complete retired state');
SELECT * FROM extensions.finish();
ROLLBACK;
