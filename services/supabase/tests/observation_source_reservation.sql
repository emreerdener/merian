\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
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
BEGIN
 IF input->'schema_version'='2'::JSONB THEN RETURN internal.admit_protected_observation_analysis(owner_id,input,repeat('a',64)); END IF;
 RETURN internal.admit_audio_observation_analysis(owner_id,input,repeat('a',64));
END;
$$;

SELECT extensions.ok(NOT source_reservation_enabled AND NOT source_unfunded_retirement_enabled,'reservation and unfunded retirement default closed') FROM internal.observation_history_rollout;
CREATE FUNCTION pg_temp.candidate(input JSONB) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',1,'input',input,'fingerprint_version',1,'fingerprint',internal.observation_source_fingerprint(input));
$$;
CREATE FUNCTION pg_temp.retirement(child UUID,operation UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT internal.observation_source_identity(b)||jsonb_build_object('operation_id',operation) FROM internal.observation_analysis_source_bindings b WHERE analysis_id=child;
$$;
SELECT set_config('request.jwt.claim.role','service_role',true);
UPDATE internal.observation_history_rollout SET append_enabled=true;
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a002');
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000a001',pg_temp.history_append_request('00000000-0000-4000-8000-00000000a002','00000000-0000-4000-8000-00000000a003'));
CREATE TEMP TABLE candidates(version INTEGER,input JSONB);
INSERT INTO candidates SELECT v,pg_temp.admission_input('00000000-0000-4000-8000-00000000a002','00000000-0000-4000-8000-00000000a003',('00000000-0000-4000-8000-00000000a00'||v+2)::UUID,('00000000-0000-4000-8000-00000000b00'||v)::UUID,v) FROM generate_series(2,3) v;
SELECT extensions.is(public.reserve_owned_observation_analysis_source('00000000-0000-4000-8000-00000000a001',pg_temp.candidate(input),11)->>'state','unavailable','fresh gate closed') FROM candidates WHERE version=2;
UPDATE internal.observation_history_rollout SET source_reservation_enabled=true,source_unfunded_retirement_enabled=true;
SELECT extensions.is(public.reserve_owned_observation_analysis_source('00000000-0000-4000-8000-00000000a001',pg_temp.candidate(input),11)->>'state','reserved','photo reservation') FROM candidates WHERE version=2;
SELECT extensions.is(public.reserve_owned_observation_analysis_source('00000000-0000-4000-8000-00000000a001',pg_temp.candidate(input),11)->>'reason','source_occupied','different child held') FROM candidates WHERE version=3;
UPDATE internal.observation_history_rollout SET source_reservation_enabled=false;
SELECT extensions.is(public.reserve_owned_observation_analysis_source('00000000-0000-4000-8000-00000000a001',pg_temp.candidate(input),11)->>'state','reserved','same candidate replay before gate') FROM candidates WHERE version=2;
SELECT extensions.throws_ok($q$SELECT public.reserve_owned_observation_analysis_source('00000000-0000-4000-8000-00000000a001',pg_temp.candidate(input||jsonb_build_object('request_digest',repeat('c',64))),11) FROM candidates WHERE version=2$q$,'22023','analysis_history_operation_conflict','changed identity conflicts');
CREATE TEMP TABLE proof AS SELECT pg_temp.retirement('00000000-0000-4000-8000-00000000a004','00000000-0000-4000-8000-00000000d001') request;
SELECT extensions.is(public.retire_owned_observation_analysis_source('00000000-0000-4000-8000-00000000a001',request,11)->>'state','retired_unfunded','unfunded retirement') FROM proof;
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy WHERE observation_id='00000000-0000-4000-8000-00000000a002'),0::BIGINT,'occupancy atomically released');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id='00000000-0000-4000-8000-00000000a004'),'binding retained');
UPDATE internal.observation_history_rollout SET source_unfunded_retirement_enabled=false;
SELECT extensions.is(public.retire_owned_observation_analysis_source('00000000-0000-4000-8000-00000000a001',request,11)->>'state','retired_unfunded','exact receipt replay before gate') FROM proof;
SELECT extensions.throws_ok($q$SELECT public.reserve_owned_observation_analysis_source('00000000-0000-4000-8000-00000000a001',pg_temp.candidate(input),11) FROM candidates WHERE version=2$q$,'22023','analysis_history_operation_conflict','old terminal reservation never reopens');
SELECT extensions.throws_ok($q$INSERT INTO internal.observation_analysis_source_occupancy VALUES('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a002','00000000-0000-4000-8000-00000000a003','00000000-0000-4000-8000-00000000a004')$q$,'22023','analysis_history_operation_conflict','direct occupancy resurrection blocked');
SELECT extensions.throws_ok($q$DELETE FROM internal.observation_source_unfunded_retirements$q$,'22023','analysis_history_operation_conflict','live-parent proof deletion blocked');
UPDATE internal.observation_history_rollout SET source_reservation_enabled=true,source_unfunded_retirement_enabled=true;
SELECT extensions.is(public.reserve_owned_observation_analysis_source('00000000-0000-4000-8000-00000000a001',pg_temp.candidate(input),11)->>'state','reserved','new explicit audio candidate after retirement') FROM candidates WHERE version=3;
SELECT extensions.throws_ok($q$SELECT public.reserve_owned_observation_analysis_source('00000000-0000-4000-8000-00000000a001',pg_temp.candidate(input),10) FROM candidates WHERE version=3$q$,'22023','analysis_history_reader_upgrade_required','reader10 unavailable');
SELECT extensions.throws_ok($q$SELECT public.retire_owned_observation_analysis_source('00000000-0000-4000-8000-00000000a001',request||jsonb_build_object('operation_id','00000000-0000-4000-8000-00000000d002'),11) FROM proof$q$,'22023','analysis_history_operation_conflict','different retirement operation conflicts');
SELECT extensions.ok(NOT has_table_privilege('service_role','internal.observation_source_unfunded_retirements','SELECT'),'proof table private');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.reserve_owned_observation_analysis_source(uuid,jsonb,integer)','EXECUTE'),'authenticated cannot reserve');
SELECT extensions.ok(NOT has_function_privilege('anon','public.retire_owned_observation_analysis_source(uuid,jsonb,integer)','EXECUTE'),'anon cannot retire');
SELECT extensions.ok(has_function_privilege('service_role','public.retire_owned_observation_analysis_source(uuid,jsonb,integer)','EXECUTE'),'service retirement callable');

-- Media has already been reserved: absence of funding is insufficient to retire.
UPDATE internal.observation_history_rollout SET media_enabled=true,prepared_audio_evidence_enabled=true;
SELECT public.reserve_owned_observation_audio_evidence_cohort('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a002','00000000-0000-4000-8000-00000000a005','00000000-0000-4000-8000-00000000b003',46,repeat('b',64));
SELECT extensions.throws_ok($q$SELECT public.retire_owned_observation_analysis_source('00000000-0000-4000-8000-00000000a001',pg_temp.retirement('00000000-0000-4000-8000-00000000a005','00000000-0000-4000-8000-00000000d003'),11)$q$,'22023','analysis_history_operation_conflict','pre-admission media holds unfunded retirement');
SELECT extensions.throws_ok($q$SELECT public.reserve_owned_observation_audio_evidence_cohort('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a002','00000000-0000-4000-8000-00000000a004','00000000-0000-4000-8000-00000000b004',46,repeat('b',64))$q$,'22023','analysis_history_operation_conflict','retired child cannot upload');
-- Legacy equivalent UUID text must invalidate never-used evidence.
INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
VALUES('{00000000-0000-4000-8000-00000000BEEF}','00000000-0000-4000-8000-00000000a001','failed_terminal','server_replay_limit_reached','replay_exhausted');
SELECT extensions.ok(NOT internal.observation_source_child_is_unused('00000000-0000-4000-8000-00000000beef'),'legacy braced uppercase identity is occupied');
-- Exact funded retirement is a distinct accepted predecessor class.
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3;
UPDATE internal.observation_history_rollout SET admission_enabled=true,protected_analysis_enabled=true,audio_analysis_enabled=true,source_retirement_enabled=true,execution_retirement_api_enabled=true;
CREATE TEMP TABLE funded AS SELECT pg_temp.seed_bound_admission('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e003','00000000-0000-4000-8000-00000000e004','00000000-0000-4000-8000-00000000e005',2) input;
SELECT pg_temp.admit_bound('00000000-0000-4000-8000-00000000e001',input) FROM funded;
SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000e001',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000e006','observation_id','00000000-0000-4000-8000-00000000e002','analysis_id','00000000-0000-4000-8000-00000000e004','source_analysis_id','00000000-0000-4000-8000-00000000e003','request_digest',repeat('a',64)),9);
SELECT extensions.throws_ok($q$SELECT public.reserve_owned_observation_analysis_source('00000000-0000-4000-8000-00000000e001',pg_temp.candidate(input),11) FROM funded$q$,'22023','analysis_history_operation_conflict','funded retired original conflicts');
SELECT extensions.is(public.reserve_owned_observation_analysis_source('00000000-0000-4000-8000-00000000e001',pg_temp.candidate(input||jsonb_build_object('analysis_id','00000000-0000-4000-8000-00000000e007')),11)->>'state','reserved','new candidate after funded proof') FROM funded;
-- Missing occupancy alone cannot prove retirement.
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c002');
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000c001',pg_temp.history_append_request('00000000-0000-4000-8000-00000000c002','00000000-0000-4000-8000-00000000c003'));
SELECT pg_temp.store_source('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c002','00000000-0000-4000-8000-00000000c003','00000000-0000-4000-8000-00000000c004',false);
SELECT extensions.is(public.reserve_owned_observation_analysis_source('00000000-0000-4000-8000-00000000c001',pg_temp.candidate(pg_temp.source_input('00000000-0000-4000-8000-00000000c002','00000000-0000-4000-8000-00000000c003','00000000-0000-4000-8000-00000000c004')),11)->>'reason','terminal_unproven','missing occupancy without proof holds');
-- Retained retired siblings must participate in the bounded inventory.
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f002');
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000f001',pg_temp.history_append_request('00000000-0000-4000-8000-00000000f002','00000000-0000-4000-8000-00000000f003'));
DO $$ DECLARE child UUID; n INTEGER; BEGIN
 FOR n IN 1..65 LOOP
  child:=('00000000-0000-4000-8000-'||lpad(to_hex(65536+n),12,'0'))::UUID;
  PERFORM public.reserve_owned_observation_analysis_source('00000000-0000-4000-8000-00000000f001',pg_temp.candidate(pg_temp.source_input('00000000-0000-4000-8000-00000000f002','00000000-0000-4000-8000-00000000f003',child)),11);
  PERFORM public.retire_owned_observation_analysis_source('00000000-0000-4000-8000-00000000f001',pg_temp.retirement(child,('00000000-0000-4000-8000-'||lpad(to_hex(131072+n),12,'0'))::UUID),11);
 END LOOP;
END $$;
SELECT extensions.is(public.reserve_owned_observation_analysis_source('00000000-0000-4000-8000-00000000f001',pg_temp.candidate(pg_temp.source_input('00000000-0000-4000-8000-00000000f002','00000000-0000-4000-8000-00000000f003','00000000-0000-4000-8000-00000000f004')),11)->>'reason','coverage_incomplete','65 released siblings hold instead of inferring vacancy');

SELECT * FROM extensions.finish();
ROLLBACK;
