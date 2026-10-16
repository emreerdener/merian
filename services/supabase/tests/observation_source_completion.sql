\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN SOURCE COMPLETION HELPERS

CREATE FUNCTION pg_temp.history_append_request(observation UUID, analysis UUID, source UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE SQL AS $$
    SELECT JSONB_BUILD_OBJECT('schema_version',1,'observation_id',observation,'analysis_id',analysis,
        'source_analysis_id',source,'request_digest',REPEAT('a',64),
        'result_snapshot',JSONB_BUILD_OBJECT('scan_id',observation,'species_id',NULL,
            'scientific_name',NULL,'common_name','Synthetic object','is_biological_subject',FALSE,
            'is_live_capture',TRUE,'confidence_score',0.8,'blur_score',0.2,'colors','[]'::JSONB,
            'estimated_size_cm',NULL,'inference_tier','flash','pet_identification',NULL,'candidates',NULL,
            'image_quality',NULL,'ai_reasoning','Synthetic fixture.','extracted_visual_traits','[]'::JSONB),
        'evidence_manifest','{"schema_version":1,"captured_media":[{"description":{"_0":{"freeText":"Synthetic observation."}}}]}'::JSONB);
$$;
CREATE FUNCTION pg_temp.seed_history_append(owner_id UUID, observation UUID, permit_initial BOOLEAN DEFAULT TRUE)
RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
    INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT || '@example.invalid','{}','{}',NOW(),NOW());
    INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
    VALUES(observation::TEXT,owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
    INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture)
    VALUES(observation,owner_id,'{}',0.8,FALSE,'flash','private',TRUE);
    UPDATE internal.observation_history_rollout SET enrollment_enabled=TRUE;
    INSERT INTO internal.observation_histories(observation_id,initial_selection_permitted) VALUES(observation,permit_initial);
    UPDATE internal.observation_history_rollout SET enrollment_enabled=FALSE;
END;
$$;

CREATE FUNCTION pg_temp.source_input(observation UUID,source UUID,child UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',3,'observation_id',observation,'analysis_id',child,'source_analysis_id',source,
 'request_digest',repeat('a',64),'entitlement_protocol',3,'identification_protocol',6,'history_protocol',9,'expected_processor_permission','google_gemini',
 'evidence_manifest',jsonb_build_object('schema_version',3,'items',jsonb_build_array(jsonb_build_object('kind','audio',
 'media_id','00000000-0000-4000-8000-00000000f999','content_type','audio/wav','byte_count',46,'sha256',repeat('b',64)))));
$$;
CREATE FUNCTION pg_temp.store_source(owner_id UUID,observation UUID,source UUID,child UUID,occupy BOOLEAN DEFAULT TRUE) RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE input JSONB:=pg_temp.source_input(observation,source,child);
BEGIN
 INSERT INTO internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id,input_snapshot,fingerprint_version,fingerprint)
 VALUES(child,owner_id,observation,source,input,1,internal.observation_source_fingerprint(input));
 IF occupy THEN
 INSERT INTO internal.observation_analysis_source_occupancy(owner_id,observation_id,source_analysis_id,analysis_id) VALUES(owner_id,observation,source,child);
 END IF;
END;
$$;
CREATE FUNCTION pg_temp.seed_funded_history(owner_id UUID,observation UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
    PERFORM pg_temp.seed_history_append(owner_id,observation);
    INSERT INTO public.user_adult_eligibility_receipts(id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'self_attestation','Synthetic adult attestation','ios','1.0.3','275');
    INSERT INTO public.user_terms_acceptance_receipts(id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'Synthetic terms acceptance','ios','1.0.3','275');
    INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'google_gemini','2026-08-03.1','granted',NOW(),'Synthetic disclosure','Synthetic agreement','ios','1.0.3','275');
END;
$$;

CREATE FUNCTION pg_temp.admission_input(parent UUID,source UUID,child UUID,media UUID,version INTEGER) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT pg_temp.source_input(parent,source,child) || jsonb_build_object('schema_version',version,'history_protocol',CASE version WHEN 2 THEN 8 ELSE 9 END,
 'evidence_manifest',jsonb_build_object('schema_version',version,'items',jsonb_build_array(jsonb_build_object('kind',CASE version WHEN 2 THEN 'image' ELSE 'audio' END,'media_id',media,'content_type',CASE version WHEN 2 THEN 'image/jpeg' ELSE 'audio/wav' END,'byte_count',46,'sha256',repeat('b',64)))));
$$;
CREATE FUNCTION pg_temp.seed_bound_admission(owner_id UUID,parent UUID,source UUID,child UUID,media UUID,version INTEGER) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE input JSONB:=pg_temp.admission_input(parent,source,child,media,version); receipt JSONB;
BEGIN
 PERFORM pg_temp.seed_funded_history(owner_id,parent);
 PERFORM internal.append_observation_analysis(owner_id,pg_temp.history_append_request(parent,source));
 INSERT INTO internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id,input_snapshot,fingerprint_version,fingerprint)
 VALUES(child,owner_id,parent,source,input,1,internal.observation_source_fingerprint(input));
 INSERT INTO internal.observation_analysis_source_occupancy VALUES(owner_id,parent,source,child);
 IF version=2 THEN
  receipt:=(public.reserve_owned_observation_evidence_cohort(owner_id,parent,child,internal.observation_source_cohort_items(input,2)))->0;
 ELSE receipt:=public.reserve_owned_observation_audio_evidence_cohort(owner_id,parent,child,media,46,repeat('b',64)); END IF;
 PERFORM internal.complete_observation_evidence(owner_id,parent,child,media,(receipt->>'object_id')::UUID);
 RETURN input;
END;
$$;
CREATE FUNCTION pg_temp.admit_bound(owner_id UUID,input JSONB) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE fixture_ip TEXT := encode(extensions.digest('source-admission-fixture:' || owner_id::TEXT,'sha256'),'hex');
BEGIN
 -- Concurrency suites reuse this helper with independent synthetic owners.
 -- Keep one stable IP per owner/replay without sharing a suite-wide rate bucket.
 IF input->'schema_version'='2'::JSONB THEN RETURN internal.admit_protected_observation_analysis(owner_id,input,fixture_ip); END IF;
 RETURN internal.admit_audio_observation_analysis(owner_id,input,fixture_ip);
END;
$$;
CREATE FUNCTION pg_temp.funded_provenance(analysis UUID) RETURNS JSONB LANGUAGE SQL AS $$
    SELECT jsonb_build_object('version',1,'provider',q->>'provider','binding',q->>'binding','model',q->>'model','variant','multimodal','operation','scan_identification','policy_version',(q->>'policy_version')::BIGINT,
        'prompt','identify_vision_v1','schema','merian_identify_v1','confidence','unqualified','diagnostic_trigger',NULL,'prompt_diagnostic_trigger',NULL,'safety',NULL,'timeout_ms',90000,
        'generation','{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":1024}'::JSONB)
    FROM (SELECT quota AS q FROM internal.observation_analysis_intents WHERE analysis_id=analysis) s;
$$;

CREATE FUNCTION pg_temp.prepare_source_draft(owner_id UUID,parent UUID,source UUID,child UUID,version INTEGER,unknown_first BOOLEAN DEFAULT FALSE,mismatch_first BOOLEAN DEFAULT FALSE,paid_first BOOLEAN DEFAULT FALSE)
RETURNS UUID LANGUAGE PLPGSQL AS $$
DECLARE input JSONB; claim JSONB; work UUID; q JSONB; result JSONB; draft JSONB; usage JSONB:='{}';
BEGIN
 input:=pg_temp.seed_bound_admission(owner_id,parent,source,child,gen_random_uuid(),version);
 IF paid_first THEN UPDATE public.users SET subscription_tier='pro',subscription_expires_at=NOW()+INTERVAL '1 day' WHERE id=owner_id; END IF;
 PERFORM pg_temp.admit_bound(owner_id,input);
 claim:=public.claim_observation_analysis_recovery(owner_id,parent,child);
 work:=(claim->>'work_token')::UUID;
 -- Admission recovery may not claim admitted work; begin owns its initial claim.
 IF work IS NULL THEN
  claim:=public.begin_owned_observation_analysis(owner_id,input,encode(extensions.digest(owner_id::TEXT,'sha256'),'hex'));
  work:=(claim->>'work_token')::UUID;
 END IF;
 PERFORM public.advance_owned_observation_analysis(owner_id,parent,child,work,'dispatch',jsonb_build_object('provenance',pg_temp.funded_provenance(child)));
 SELECT quota INTO q FROM internal.observation_analysis_intents WHERE analysis_id=child;
 IF unknown_first THEN
  PERFORM internal.complete_identification_usage(invocation_id,'unknown_execution','{}') FROM internal.observation_analysis_intents WHERE analysis_id=child;
 END IF;
 IF mismatch_first THEN
  PERFORM internal.complete_identification_usage(invocation_id,'draft','{"total_tokens":42}') FROM internal.observation_analysis_intents WHERE analysis_id=child;
 END IF;
 result:=(pg_temp.history_append_request(parent,child,source)->'result_snapshot')||jsonb_build_object('is_biological_subject',TRUE,'scientific_name','Syntheticus fixture','identification_provenance',pg_temp.funded_provenance(child));
 PERFORM public.advance_owned_observation_analysis(owner_id,parent,child,work,'outcome',jsonb_build_object('quota_token',q->'lease_token','value',
 jsonb_build_object('schema_version',1,'provenance',pg_temp.funded_provenance(child),'outcome',jsonb_build_object('kind','draft','result',result-'species_id'),'usage',usage)));
 result:=result||jsonb_build_object('species_id',public.advance_owned_observation_analysis(owner_id,parent,child,work,'resolve_species','{}')->'id');
 draft:=jsonb_build_object('schema_version',version,'observation_id',parent,'analysis_id',child,'source_analysis_id',source,
 'request_digest',input->'request_digest','result_snapshot',result,'evidence_manifest',input->'evidence_manifest');
 PERFORM public.advance_owned_observation_analysis(owner_id,parent,child,work,'draft',jsonb_build_object('draft',draft));
 RETURN work;
END;
$$;
CREATE FUNCTION pg_temp.reserve_next(owner_id UUID,parent UUID,source UUID,child UUID,version INTEGER) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.reserve_owned_observation_analysis_source(owner_id,jsonb_build_object('schema_version',1,'input',input,'fingerprint_version',1,'fingerprint',internal.observation_source_fingerprint(input)),11)
 FROM (SELECT pg_temp.admission_input(parent,source,child,gen_random_uuid(),version) input) s;
$$;
-- END SOURCE COMPLETION HELPERS
SELECT extensions.ok(NOT source_completion_release_enabled,'completion release defaults closed') FROM internal.observation_history_rollout;
SELECT extensions.ok(NOT has_table_privilege(role_name,'internal.observation_source_completion_receipts',privilege),'private proof '||role_name||'/'||privilege)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE']) privilege;
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3;
UPDATE internal.observation_history_rollout SET append_enabled=TRUE,media_enabled=TRUE,prepared_audio_evidence_enabled=TRUE,
 admission_enabled=TRUE,protected_analysis_enabled=TRUE,audio_analysis_enabled=TRUE,dispatch_enabled=TRUE,
 source_dispatch_enabled=TRUE,orchestration_enabled=TRUE,source_reservation_enabled=TRUE,source_completion_release_enabled=TRUE;
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
CREATE TEMP TABLE completion_cases(owner_id UUID,parent UUID,source UUID,child UUID,work UUID,version INTEGER);
INSERT INTO completion_cases SELECT gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),NULL,v FROM generate_series(2,3) v;
UPDATE completion_cases SET work=pg_temp.prepare_source_draft(owner_id,parent,source,child,version);
SELECT extensions.is(public.advance_owned_observation_analysis(owner_id,parent,child,work,'complete','{}')->>'state','complete','version '||version||' completes') FROM completion_cases;
SELECT extensions.ok(internal.observation_source_completion_proven(b),'durable proof validates version '||c.version)
 FROM completion_cases c JOIN internal.observation_analysis_source_bindings b ON b.analysis_id=c.child;
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy o WHERE o.analysis_id=c.child),0::BIGINT,'completion atomically releases occupancy '||version) FROM completion_cases c;
SELECT extensions.is((SELECT selected_analysis_id FROM internal.observation_histories WHERE observation_id=parent),source,'completion preserves selected source '||version) FROM completion_cases;
SELECT extensions.is((SELECT proof#>>'{settlement,state}' FROM internal.observation_source_completion_receipts WHERE analysis_id=child),'consumed','original complimentary allocation consumed '||version) FROM completion_cases;
SELECT extensions.ok((SELECT proof#>'{accounting,estimated_cost_microusd}'='null'::JSONB FROM internal.observation_source_completion_receipts WHERE analysis_id=child),'null price still permits known success '||version) FROM completion_cases;
SELECT extensions.throws_ok(format('UPDATE internal.observation_source_completion_receipts SET proof=proof WHERE analysis_id=%L',child),'22023','analysis_history_operation_conflict','proof immutable') FROM completion_cases;
SELECT extensions.throws_ok(format('DELETE FROM internal.observation_source_completion_receipts WHERE analysis_id=%L',child),'22023','analysis_history_operation_conflict','proof retained before parent deletion') FROM completion_cases;
SET LOCAL TIME ZONE 'Asia/Kolkata';
SELECT extensions.ok(internal.observation_source_completion_proven(b),'permanent product proof ignores session time zone '||c.version)
 FROM completion_cases c JOIN internal.observation_analysis_source_bindings b ON b.analysis_id=c.child;
SET LOCAL TIME ZONE 'UTC';
UPDATE internal.observation_history_rollout SET selection_enabled=TRUE;
SELECT internal.select_observation_analysis(owner_id,jsonb_build_object('schema_version',1,'observation_id',parent,'analysis_id',child,
 'operation_id',gen_random_uuid(),'expected_observation_revision',h.state_revision,'expected_review_revision',a.review_revision))
 FROM completion_cases c JOIN internal.observation_histories h ON h.observation_id=c.parent JOIN internal.observation_analysis_authorities a ON a.analysis_id=c.child;
SELECT extensions.ok(internal.observation_source_completion_proven(b),'explicit selection cannot invalidate permanent proof '||c.version)
 FROM completion_cases c JOIN internal.observation_analysis_source_bindings b ON b.analysis_id=c.child;
CREATE FUNCTION pg_temp.review_completed(owner_id UUID,parent UUID,child UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE request JSONB;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::TEXT,TRUE);
 SELECT jsonb_build_object('schema_version',1,'observation_id',parent,'analysis_id',child,'operation_id',gen_random_uuid(),
 'expected_observation_revision',h.state_revision,'expected_review_revision',a.review_revision,'action','reject','undo_operation_id',NULL)
 INTO request FROM internal.observation_histories h JOIN internal.observation_analysis_authorities a USING(observation_id)
 WHERE h.observation_id=parent AND a.analysis_id=child;
 PERFORM public.review_owned_observation_analysis(request,10);
END;
$$;
UPDATE internal.observation_history_rollout SET rejection_api_enabled=TRUE,reader_enabled=TRUE,state_reader_enabled=TRUE;
SELECT pg_temp.review_completed(owner_id,parent,child) FROM completion_cases;
SELECT extensions.ok(internal.observation_source_completion_proven(b),'review cannot invalidate permanent proof '||c.version)
 FROM completion_cases c JOIN internal.observation_analysis_source_bindings b ON b.analysis_id=c.child;
SELECT set_config('request.jwt.claims','{}',TRUE);
SELECT extensions.throws_ok(format('SELECT internal.perform_ghost_profile_merge(%L,%L)',a.owner_id,b.owner_id),'55000','ghost_merge_source_history_requires_attention','merge cannot reparent completed source proof') FROM completion_cases a CROSS JOIN completion_cases b WHERE a.version=2 AND b.version=3;
SELECT extensions.throws_ok(format('INSERT INTO internal.observation_source_completion_receipts SELECT analysis_id,owner_id,observation_id,source_analysis_id,proof||''{"schema_version":2}''::jsonb FROM internal.observation_source_completion_receipts WHERE analysis_id=%L',child),'22023','analysis_history_operation_conflict','malformed direct proof insert lacks completion owner') FROM completion_cases;
-- Accounting retention does not erase permanent execution proof.
DELETE FROM internal.identification_invocations WHERE scan_id IN (SELECT child FROM completion_cases);
SELECT extensions.ok(internal.observation_source_completion_proven(b),'proof survives invocation removal '||c.version)
 FROM completion_cases c JOIN internal.observation_analysis_source_bindings b ON b.analysis_id=c.child;
SELECT extensions.is(pg_temp.reserve_next(owner_id,parent,source,gen_random_uuid(),version)->>'state','reserved','new explicit child follows completed predecessor '||version) FROM completion_cases;
CREATE TEMP TABLE held_cases(owner_id UUID,parent UUID,source UUID,child UUID,work UUID,scenario TEXT);
INSERT INTO held_cases SELECT gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),NULL,s FROM unnest(ARRAY['unknown','closed','mismatch','missing','missing_event']) s;
UPDATE held_cases SET work=pg_temp.prepare_source_draft(owner_id,parent,source,child,3,scenario='unknown',scenario='mismatch');
DELETE FROM internal.identification_invocations WHERE scan_id IN (SELECT child FROM held_cases WHERE scenario='missing');
UPDATE internal.identification_invocations SET event_id=NULL WHERE scan_id IN (SELECT child FROM held_cases WHERE scenario='missing_event');
SELECT extensions.is(public.advance_owned_observation_analysis(owner_id,parent,child,work,'complete','{}')->>'state','complete','late or mismatched accounting preserves result: '||scenario) FROM held_cases WHERE scenario<>'closed';
UPDATE internal.observation_history_rollout SET source_completion_release_enabled=FALSE;
SELECT extensions.is(public.advance_owned_observation_analysis(owner_id,parent,child,work,'complete','{}')->>'state','complete','closed release gate preserves completion') FROM held_cases WHERE scenario='closed';
UPDATE internal.observation_history_rollout SET source_completion_release_enabled=TRUE;
SELECT extensions.is((SELECT count(*) FROM internal.observation_source_completion_receipts r WHERE r.analysis_id=child),0::BIGINT,'no proof for '||scenario) FROM held_cases;
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy o WHERE o.analysis_id=child),1::BIGINT,'occupancy held for '||scenario) FROM held_cases;
SELECT extensions.is(public.begin_owned_observation_analysis(owner_id,(SELECT input_snapshot FROM internal.observation_analysis_intents WHERE analysis_id=child),encode(extensions.digest(owner_id::TEXT,'sha256'),'hex'))->>'state','complete','lost reply returns terminal completion '||scenario) FROM held_cases;
SELECT extensions.is((SELECT count(*) FROM internal.observation_source_completion_receipts r WHERE r.analysis_id=child),0::BIGINT,'replay never backfills '||scenario) FROM held_cases;
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) SELECT parent,owner_id FROM completion_cases;
SELECT extensions.is((SELECT count(*) FROM internal.observation_source_completion_receipts),0::BIGINT,'parent erasure cascades immutable completion proofs');
CREATE TEMP TABLE paid_case AS SELECT gen_random_uuid() owner_id,gen_random_uuid() parent,gen_random_uuid() source,gen_random_uuid() child,NULL::UUID work;
UPDATE paid_case SET work=pg_temp.prepare_source_draft(owner_id,parent,source,child,3);
UPDATE public.users SET subscription_tier='pro',subscription_expires_at=NOW()+INTERVAL '1 day' WHERE id IN (SELECT owner_id FROM paid_case);
SELECT extensions.is(public.advance_owned_observation_analysis(owner_id,parent,child,work,'complete','{}')->>'state','complete','paid upgrade completes same result') FROM paid_case;
SELECT extensions.is((SELECT proof#>>'{settlement,reason}' FROM internal.observation_source_completion_receipts WHERE analysis_id=child),'paid_before_completion','paid upgrade release proof retains original disposition') FROM paid_case;
CREATE TEMP TABLE no_allocation_case AS SELECT gen_random_uuid() owner_id,gen_random_uuid() parent,gen_random_uuid() source,gen_random_uuid() child,NULL::UUID work;
UPDATE no_allocation_case SET work=pg_temp.prepare_source_draft(owner_id,parent,source,child,3,FALSE,FALSE,TRUE);
SELECT extensions.is(public.advance_owned_observation_analysis(owner_id,parent,child,work,'complete','{}')->>'state','complete','paid original funding completes without allocation') FROM no_allocation_case;
SELECT extensions.is((SELECT proof#>>'{settlement,state}' FROM internal.observation_source_completion_receipts WHERE analysis_id=child),'not_allocated','no-allocation proof uses original funding identity') FROM no_allocation_case;
CREATE TEMP TABLE failure_case AS SELECT gen_random_uuid() owner_id,gen_random_uuid() parent,gen_random_uuid() source,gen_random_uuid() child,NULL::UUID work;
UPDATE failure_case SET work=pg_temp.prepare_source_draft(owner_id,parent,source,child,2);
CREATE FUNCTION pg_temp.fail_completion_proof() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN RAISE EXCEPTION 'synthetic proof storage failure' USING ERRCODE='P0001'; END; $$;
CREATE TRIGGER test_fail_proof BEFORE INSERT ON internal.observation_source_completion_receipts FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_completion_proof();
SELECT extensions.throws_ok(format('SELECT public.advance_owned_observation_analysis(%L,%L,%L,%L,''complete'',''{}'')',owner_id,parent,child,work),'P0001','synthetic proof storage failure','storage failure rolls back entire completion') FROM failure_case;
SELECT extensions.is((SELECT state FROM internal.observation_analysis_intents WHERE analysis_id=child),'draft','failed proof leaves original draft') FROM failure_case;
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_results WHERE analysis_id=child),0::BIGINT,'failed proof leaves no result append') FROM failure_case;
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id=child),'held','failed proof leaves credit held') FROM failure_case;
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy WHERE analysis_id=child),1::BIGINT,'failed proof cannot release source') FROM failure_case;
DROP TRIGGER test_fail_proof ON internal.observation_source_completion_receipts;
SELECT extensions.is(public.advance_owned_observation_analysis(owner_id,parent,child,work,'complete','{}')->>'state','complete','same operation completes after storage recovery') FROM failure_case;
SELECT * FROM extensions.finish();
ROLLBACK;
