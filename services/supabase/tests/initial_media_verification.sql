\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.admission_owner(owner_id UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT||'@example.invalid','{}','{}',NOW(),NOW());
 INSERT INTO public.user_adult_eligibility_receipts(id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'self_attestation','Synthetic adult attestation','ios','1.0.3','275');
 INSERT INTO public.user_terms_acceptance_receipts(id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'Synthetic terms acceptance','ios','1.0.3','275');
 INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'google_gemini','2026-08-03.1','granted',NOW(),'Synthetic disclosure','Synthetic agreement','ios','1.0.3','275');
END;
$$;
CREATE FUNCTION pg_temp.admission_input() RETURNS JSONB LANGUAGE SQL AS $input$
 SELECT '{"schema_version":1,"route":"identify-describe","ordered_descriptions":["  Synthetic α / é / é\n\ttext  "],"media":[],"owner_timeline":[{"kind":"description","index":0}],"capture":{"has_video":false,"video_clip_count":0,"declared_video_frame_count":0,"video_inference_frame_count":0},"context":{"depth_scale_text":null,"semantic_location":null,"weather_condition":null,"device_locale":null,"device_time_zone":null,"device_region":null,"time_of_day":null,"gps_latitude":null,"gps_longitude":null,"gps_elevation":null,"zoom_factor":null,"estimated_size_cm":null,"weather_temperature_f":null,"current_month":null},"options":{"timestamp":null,"geoprivacy":"private","public_location_label":null,"preferred_goal":null,"observation_context":null},"admission":{"client_protocol":3,"identification_protocol":6,"expected_processor_permission":"google_gemini"},"experiment":null}'::JSONB;
$input$;
CREATE FUNCTION pg_temp.admit_initial(owner_id UUID,scan UUID,value JSONB DEFAULT pg_temp.admission_input()) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.admit_initial_analysis(owner_id,scan,internal.initial_canonical(value),internal.initial_digest('input',internal.initial_canonical(value)),
 (SELECT configuration_assets_digest FROM internal.initial_analysis_rollout WHERE singleton),repeat('a',64));
$$;
CREATE FUNCTION pg_temp.media_input() RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE value JSONB:=pg_temp.admission_input(); items JSONB:='[]'; timeline JSONB:='[{"kind":"description","index":0}]'; i INTEGER; item JSONB;
BEGIN
 FOR i IN 0..7 LOOP
  item:=jsonb_build_object('kind',CASE WHEN i<5 THEN 'image' WHEN i<7 THEN 'audio' ELSE 'video' END,
   'content_type',CASE WHEN i<5 THEN 'image/jpeg' WHEN i<7 THEN 'audio/wav' ELSE 'video/mp4' END,
   'byte_count',CASE WHEN i<5 THEN 1048576 WHEN i<7 THEN 2700000 ELSE 12582912 END,
   'sha256',repeat('a',64),'source_sha256',CASE WHEN i IN (5,6) THEN repeat('b',64) ELSE repeat('a',64) END,
   'input_index',CASE WHEN i<5 THEN i WHEN i<7 THEN i-5 ELSE NULL END,
   'source_index',CASE WHEN i<5 THEN i WHEN i<7 THEN i-5 ELSE NULL END,
   'clip_index',CASE WHEN i=7 THEN 0 ELSE NULL END,'frame_index',NULL,'focus_region',NULL,
   'transform',CASE WHEN i IN (5,6) THEN 'initial_audio_v1' ELSE 'identity_v1' END,
   'transform_parameters',CASE WHEN i IN (5,6) THEN '{"target_sample_rate":16000,"preserve_short_video_context":false}'::JSONB ELSE NULL END);
  item:=item||jsonb_build_object('source_content_type',item->'content_type','source_byte_count',item->'byte_count');
  items:=items||jsonb_build_array(item);
  timeline:=timeline||jsonb_build_array(jsonb_build_object('kind','media','index',i));
 END LOOP;
 RETURN value||jsonb_build_object('route','identify-multimodal','ordered_descriptions','["Synthetic text"]'::JSONB,'media',items,'owner_timeline',timeline,
  'capture','{"has_video":true,"video_clip_count":1,"declared_video_frame_count":0,"video_inference_frame_count":0}'::JSONB);
END;
$$;
CREATE FUNCTION pg_temp.media_digest(p_scan UUID) RETURNS TEXT LANGUAGE SQL AS $$ SELECT submission_digest FROM internal.initial_analysis_admissions WHERE scan_id=p_scan; $$;
CREATE FUNCTION pg_temp.media_allocate(p_owner UUID,p_scan UUID,p_backend UUID DEFAULT '00000000-0000-4000-8000-00000000e000') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.allocate_initial_analysis_media(p_owner,p_scan,pg_temp.media_digest(p_scan),p_backend);
$$;
CREATE TEMP TABLE verification_fixtures(scan UUID PRIMARY KEY,digest TEXT,manifest TEXT,token UUID,binding JSONB);
CREATE FUNCTION pg_temp.verification_setup(p_scan UUID,p_media BOOLEAN DEFAULT TRUE) RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE binding JSONB; claimed JSONB;
BEGIN
 PERFORM pg_temp.admit_initial('00000000-0000-4000-8000-00000000f001',p_scan,CASE WHEN p_media THEN pg_temp.media_input() ELSE pg_temp.admission_input() END);
 binding:=pg_temp.media_allocate('00000000-0000-4000-8000-00000000f001',p_scan,'00000000-0000-4000-8000-00000000f000')->'binding';
 claimed:=public.claim_initial_media_preparation('00000000-0000-4000-8000-00000000f001',p_scan,binding->>'submission_digest',binding->>'manifest_digest');
 INSERT INTO verification_fixtures VALUES(p_scan,binding->>'submission_digest',binding->>'manifest_digest',(claimed#>>'{claim,token}')::UUID,binding);
END;
$$;
CREATE FUNCTION pg_temp.verification_call(p_action TEXT,p_scan UUID,p_token UUID DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT internal.initial_media_verification_action(p_action,'00000000-0000-4000-8000-00000000f001',p_scan,digest,manifest,coalesce(p_token,token)) FROM verification_fixtures WHERE scan=p_scan;
$$;
CREATE FUNCTION pg_temp.expire_preparation(p_scan UUID,p_cohort BOOLEAN DEFAULT FALSE) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 ALTER TABLE internal.initial_analysis_media_preparations DISABLE TRIGGER guard_initial_media_preparation;
 UPDATE internal.initial_analysis_media_preparations SET issued_at=1,expires_at=2 WHERE scan_id=p_scan;
 ALTER TABLE internal.initial_analysis_media_preparations ENABLE TRIGGER guard_initial_media_preparation;
 IF p_cohort THEN
  ALTER TABLE internal.initial_analysis_media_cohorts DISABLE TRIGGER guard_initial_media_cohort;
  UPDATE internal.initial_analysis_media_cohorts SET binding=jsonb_set(binding,'{expires_at}','1') WHERE scan_id=p_scan;
  ALTER TABLE internal.initial_analysis_media_cohorts ENABLE TRIGGER guard_initial_media_cohort;
 END IF;
END;
$$;
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SELECT extensions.ok(NOT initial_analysis_lifecycle_enabled AND media_backend_generation IS NULL,'M2 enables no gate/profile') FROM internal.initial_analysis_rollout;
SELECT extensions.ok(NOT has_table_privilege(r,t,p),'private verification tables deny API access') FROM unnest(ARRAY['anon','authenticated','service_role']) r
 CROSS JOIN unnest(ARRAY['internal.initial_analysis_media_preparations','internal.initial_analysis_media_verifications']) t CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p;
SELECT extensions.ok(NOT has_function_privilege(r,f,'EXECUTE'),'ordinary clients have no verification authority') FROM unnest(ARRAY['anon','authenticated']) r
 CROSS JOIN unnest(ARRAY['public.claim_initial_media_preparation(uuid,uuid,text,text)','public.settle_initial_media_verification(uuid,uuid,text,text,uuid)','public.get_initial_media_verification(uuid,uuid,text,text)','public.get_initial_media_backend(uuid)']) f;
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000f001');
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000f002');
INSERT INTO internal.initial_analysis_media_backends VALUES('00000000-0000-4000-8000-00000000f000','r2','https://00000000000000000000000000000000.r2.cloudflarestorage.com','synthetic-initial-private','initial-analysis/v1','synthetic_profile');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE,media_backend_generation='00000000-0000-4000-8000-00000000f000';
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
SELECT pg_temp.verification_setup('00000000-0000-4000-8000-00000000f101');
SELECT extensions.is(pg_temp.verification_call('claim','00000000-0000-4000-8000-00000000f101'),' {"version":1,"outcome":"held","reason":"busy"}'::JSONB,'lost claim cannot recover a write token');
SELECT extensions.is(pg_temp.verification_call('read','00000000-0000-4000-8000-00000000f101')->>'reason','missing','allocation and claim are not verification');
SELECT extensions.is(public.retire_initial_analysis_media('00000000-0000-4000-8000-00000000f001',scan,digest)->>'reason','in_use','active claim excludes retirement') FROM verification_fixtures;
SELECT extensions.is(pg_temp.verification_call('settle',scan,gen_random_uuid())->>'reason','stale','wrong token cannot verify') FROM verification_fixtures;
SELECT extensions.throws_ok(format('SELECT public.get_initial_media_verification(%L,%L,%L,%L)','00000000-0000-4000-8000-00000000f002',scan,digest,manifest),'P0002','initial_analysis_owner_unavailable','foreign identity precedes private receipt') FROM verification_fixtures;
SELECT extensions.throws_ok(format('SELECT public.get_initial_media_verification(%L,%L,%L,%L)','00000000-0000-4000-8000-00000000f001',scan,digest,repeat('b',64)),'23505','initial_analysis_conflict','manifest conflict') FROM verification_fixtures;
SELECT extensions.throws_ok($$UPDATE internal.initial_analysis_media_preparations SET token=gen_random_uuid()$$,'22023','initial_analysis_storage_immutable','active claim cannot be replaced');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_analysis_media_preparations$$,'22023','initial_analysis_storage_immutable','live claim cannot disappear');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE,media_backend_generation=NULL;
CREATE TEMP TABLE known_verification AS SELECT pg_temp.verification_call('settle',scan) AS value FROM verification_fixtures;
SELECT extensions.is(value->>'outcome','verified','original live claim settles after gate disables') FROM known_verification;
SELECT extensions.is(pg_temp.verification_call('read',scan)->'receipt',(SELECT value->'receipt' FROM known_verification),'exact receipt read') FROM verification_fixtures;
SELECT pg_temp.expire_preparation(scan,TRUE) FROM verification_fixtures;
SELECT extensions.is(pg_temp.verification_call('settle',scan,gen_random_uuid())->'receipt',(SELECT value->'receipt' FROM known_verification),'exact saved receipt ignores expiry and replacement argument') FROM verification_fixtures;
SELECT extensions.is(pg_temp.verification_call('claim',scan)->>'outcome','replay','saved receipt never issues fresh claim') FROM verification_fixtures;
SELECT extensions.is(public.retire_initial_analysis_media('00000000-0000-4000-8000-00000000f001',scan,digest)->>'reason','in_use','verified evidence excludes expiry retirement') FROM verification_fixtures;
SELECT extensions.throws_ok($$UPDATE internal.initial_analysis_media_verifications SET receipt='{}'$$,'22023','initial_analysis_storage_immutable','receipt immutable');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_analysis_media_verifications$$,'22023','initial_analysis_storage_immutable','live receipt cannot disappear');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id IN(SELECT scan FROM verification_fixtures)),'media is not provider result evidence');
SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_verifications WHERE scan_id='00000000-0000-4000-8000-00000000f101'),0::BIGINT,'C1 abandonment erases verification');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_preparations WHERE scan_id='00000000-0000-4000-8000-00000000f101'),0::BIGINT,'C1 abandonment erases claim');
SELECT extensions.ok((SELECT bool_and(retired) FROM internal.initial_analysis_media_registry WHERE scan_id='00000000-0000-4000-8000-00000000f101'),'C1 atomically retires all objects');
SELECT extensions.throws_ok($$SELECT pg_temp.verification_call('read','00000000-0000-4000-8000-00000000f101')$$,'55000','initial_analysis_cancelled','cancel precedes receipt replay');
SELECT extensions.is(public.get_initial_media_backend('00000000-0000-4000-8000-00000000f000')->>'outcome','resolved','cleanup resolves original generation after erasure');
SELECT extensions.is(public.get_initial_media_backend(gen_random_uuid())->>'reason','missing','missing generation has no default fallback');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE,media_backend_generation='00000000-0000-4000-8000-00000000f000';
SELECT pg_temp.verification_setup('00000000-0000-4000-8000-00000000f102',FALSE);
SELECT pg_temp.expire_preparation('00000000-0000-4000-8000-00000000f102');
SELECT extensions.is(pg_temp.verification_call('settle','00000000-0000-4000-8000-00000000f102')->>'reason','stale','expired unchanged token cannot mint receipt');
CREATE TEMP TABLE replacement AS SELECT pg_temp.verification_call('claim','00000000-0000-4000-8000-00000000f102') AS value;
SELECT extensions.is(value->>'outcome','claimed','expired storage ownership can be reacquired for same cohort') FROM replacement;
SELECT extensions.is(pg_temp.verification_call('settle','00000000-0000-4000-8000-00000000f102')->>'reason','stale','old token loses to reclaim');
SELECT extensions.is(pg_temp.verification_call('settle','00000000-0000-4000-8000-00000000f102',(SELECT (value#>>'{claim,token}')::UUID FROM replacement))->>'outcome','verified','explicit empty text cohort settles');
SELECT pg_temp.verification_setup('00000000-0000-4000-8000-00000000f103');
SELECT pg_temp.expire_preparation('00000000-0000-4000-8000-00000000f103',TRUE);
SELECT extensions.is(pg_temp.verification_call('claim','00000000-0000-4000-8000-00000000f103')->>'reason','expired','cohort expiry cannot be renewed');
SELECT extensions.is(public.retire_initial_analysis_media('00000000-0000-4000-8000-00000000f001',scan,digest)->>'outcome','retired','expired unverified cohort retires') FROM verification_fixtures WHERE scan='00000000-0000-4000-8000-00000000f103';
SELECT extensions.is(pg_temp.verification_call('settle','00000000-0000-4000-8000-00000000f103')->>'reason','retired','retirement wins over any token');
SELECT pg_temp.verification_setup('00000000-0000-4000-8000-00000000f104');
CREATE FUNCTION pg_temp.reject_verification() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN RAISE EXCEPTION 'synthetic_receipt_failure' USING ERRCODE='22023'; END; $$;
CREATE TRIGGER zz_reject_verification BEFORE INSERT ON internal.initial_analysis_media_verifications FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_verification();
SELECT extensions.throws_ok($$SELECT pg_temp.verification_call('settle','00000000-0000-4000-8000-00000000f104')$$,'22023','synthetic_receipt_failure','failed receipt transaction is atomic');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_verifications WHERE scan_id='00000000-0000-4000-8000-00000000f104'),0::BIGINT,'no partial verification');
DROP TRIGGER zz_reject_verification ON internal.initial_analysis_media_verifications;
SELECT extensions.is(pg_temp.verification_call('settle','00000000-0000-4000-8000-00000000f104')->>'outcome','verified','original current token may finish after known rollback');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES('00000000-0000-4000-8000-00000000f104',NULL,clock_timestamp());
SELECT extensions.throws_ok($$SELECT pg_temp.verification_call('read','00000000-0000-4000-8000-00000000f104')$$,'55000','initial_analysis_deleted','scan deletion precedes known receipt');
SELECT public.apply_user_tombstone('00000000-0000-4000-8000-00000000f001');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_verifications WHERE scan_id IN(SELECT scan FROM verification_fixtures)),0::BIGINT,'account erases remaining receipt');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_preparations WHERE scan_id IN(SELECT scan FROM verification_fixtures)),0::BIGINT,'account erases remaining claims');
SELECT extensions.ok((SELECT bool_and(retired) FROM internal.initial_analysis_media_registry WHERE scan_id IN(SELECT scan FROM verification_fixtures)),'account preserves retired cleanup identities');
SELECT * FROM extensions.finish();
ROLLBACK;
