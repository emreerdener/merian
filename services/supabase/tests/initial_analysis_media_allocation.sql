\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN INITIAL MEDIA HELPERS
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
-- END INITIAL MEDIA HELPERS
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SELECT extensions.is((SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout),FALSE,'activation stays false');
SELECT extensions.ok((SELECT media_backend_generation IS NULL FROM internal.initial_analysis_rollout),'no backend selection enabled by migration');
-- Isolate cleanup selection from permanent destinations left by earlier DB tests.
UPDATE internal.initial_analysis_media_registry SET claim_token=gen_random_uuid(),claim_expires_at=clock_timestamp()+interval '1 hour' WHERE retired AND NOT marker_confirmed;
SELECT extensions.ok(NOT has_table_privilege(r,t,p),'private media tables deny API access')
 FROM unnest(ARRAY['anon','authenticated','service_role']) r
 CROSS JOIN unnest(ARRAY['internal.initial_analysis_media_backends','internal.initial_analysis_media_allocation_fences','internal.initial_analysis_media_registry','internal.initial_analysis_media_cohorts']) t
 CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p;
SELECT extensions.ok(NOT has_function_privilege(r,f,'EXECUTE'),'clients cannot call media service functions')
 FROM unnest(ARRAY['anon','authenticated']) r
 CROSS JOIN unnest(ARRAY['public.allocate_initial_analysis_media(uuid,uuid,text,uuid)','public.get_initial_analysis_media(uuid,uuid,text)',
 'public.retire_initial_analysis_media(uuid,uuid,text)','public.claim_initial_analysis_media_erasure()','public.finish_initial_analysis_media_erasure(uuid,uuid,boolean)']) f;
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000e001');
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000e002');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
INSERT INTO internal.initial_analysis_media_backends VALUES('00000000-0000-4000-8000-00000000e000','r2','https://00000000000000000000000000000000.r2.cloudflarestorage.com','synthetic-initial-private','initial-analysis/v1','synthetic_profile');
INSERT INTO internal.initial_analysis_media_backends SELECT '00000000-0000-4000-8000-00000000e009',provider,direct_endpoint,private_bucket,namespace,credential_profile FROM internal.initial_analysis_media_backends WHERE generation='00000000-0000-4000-8000-00000000e000';
SELECT extensions.throws_ok($$UPDATE internal.initial_analysis_media_backends SET private_bucket='changed' WHERE generation='00000000-0000-4000-8000-00000000e000'$$,'22023','initial_analysis_storage_immutable','unused backend config immutable');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_analysis_media_backends$$,'22023','initial_analysis_storage_immutable','generation cannot disappear');
SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101');
SELECT extensions.throws_ok($$SELECT pg_temp.media_allocate('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101')$$,'55000','initial_analysis_unavailable','caller does not select server profile');
UPDATE internal.initial_analysis_rollout SET media_backend_generation='00000000-0000-4000-8000-00000000e000';
CREATE TEMP TABLE empty_allocation AS SELECT pg_temp.media_allocate('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101') AS value;
SELECT extensions.is((SELECT value#>'{binding,items}' FROM empty_allocation),'[]'::JSONB,'explicit empty cohort');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id IN ('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e103')),0::BIGINT,'no text objects');
SELECT extensions.is((SELECT state FROM internal.initial_analysis_media_allocation_fences WHERE scan_id='00000000-0000-4000-8000-00000000e101'),'allocated','empty cohort has permanent fence');
SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e102',pg_temp.media_input());
CREATE TEMP TABLE original_media AS SELECT pg_temp.media_allocate('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e102') AS value;
SELECT extensions.is((SELECT value->>'outcome' FROM original_media),'allocated','maximum cohort accepted');
SELECT extensions.is((SELECT jsonb_array_length(value#>'{binding,items}') FROM original_media),8,'eight ordered inputs');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id IN ('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e103')),10::BIGINT,'ten objects and no cross-item deduplication');
SELECT extensions.is((SELECT value#>'{binding,items,0,source}' FROM original_media),(SELECT value#>'{binding,items,0,prepared}' FROM original_media),'equal tuple shares roles');
SELECT extensions.isnt((SELECT value#>>'{binding,items,5,source,object_id}' FROM original_media),(SELECT value#>>'{binding,items,5,prepared,object_id}' FROM original_media),'different WAV roles separate');
SELECT extensions.is((SELECT value#>'{binding,items,7,prepared}' FROM original_media),'null'::JSONB,'raw clip source only');
SELECT extensions.is((SELECT value#>>'{binding,manifest_digest}' FROM original_media),
 (SELECT encode(extensions.digest(convert_to(E'merian.initial-analysis.media-allocation.v1\n'||internal.initial_canonical((value->'binding')-'manifest_digest'),'UTF8'),'sha256'),'hex') FROM original_media),'canonical manifest digest');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE,media_backend_generation='00000000-0000-4000-8000-00000000e009';
SELECT extensions.is(pg_temp.media_allocate('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e102')->'binding',(SELECT value->'binding' FROM original_media),'replay ignores gate/default');
SELECT extensions.throws_ok($$SELECT pg_temp.media_allocate('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e009')$$,'23505','initial_analysis_conflict','backend conflicts');
SELECT extensions.throws_ok($$SELECT public.get_initial_analysis_media('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e102',repeat('f',64))$$,'23505','initial_analysis_conflict','digest conflicts');
SELECT extensions.throws_ok($$SELECT pg_temp.media_allocate('00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e102')$$,'P0002','initial_analysis_owner_unavailable','foreign replay denied');
SELECT extensions.is(public.retire_initial_analysis_media('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e102',pg_temp.media_digest('00000000-0000-4000-8000-00000000e102'))->>'reason','not_expired','no early retirement');
SELECT extensions.is(public.claim_initial_analysis_media_erasure()->>'outcome','empty','live object no cleanup');
-- Fixture time travel, no production mutation owner.
ALTER TABLE internal.initial_analysis_media_cohorts DISABLE TRIGGER guard_initial_media_cohort;
UPDATE internal.initial_analysis_media_cohorts SET binding=jsonb_set(binding,'{expires_at}','1');
ALTER TABLE internal.initial_analysis_media_cohorts ENABLE TRIGGER guard_initial_media_cohort;
SELECT extensions.is(pg_temp.media_allocate('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e102')->>'reason','expired','expired metadata no renewal');
SELECT extensions.is(pg_temp.media_allocate('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e102')#>>'{binding,expires_at}','1','deadline fixed');
SELECT extensions.is(public.retire_initial_analysis_media('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e102',pg_temp.media_digest('00000000-0000-4000-8000-00000000e102'))->>'outcome','retired','expired unused cohort retires');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_registry WHERE retired AND scan_id IN ('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e103')),10::BIGINT,'whole cohort retirement');
SELECT extensions.is(public.get_initial_analysis_media('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e102',pg_temp.media_digest('00000000-0000-4000-8000-00000000e102'))->>'reason','retired','live retired cohort no binding');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000e102'),'reserved','no funding settlement');
CREATE TEMP TABLE first_claim AS SELECT public.claim_initial_analysis_media_erasure() AS value;
SELECT extensions.is((SELECT value#>>'{object,backend_generation}' FROM first_claim),'00000000-0000-4000-8000-00000000e000','cleanup original backend');
SELECT extensions.is(public.finish_initial_analysis_media_erasure((SELECT (value#>>'{object,object_id}')::UUID FROM first_claim),gen_random_uuid(),TRUE)->>'outcome','stale','wrong token');
UPDATE internal.initial_analysis_media_registry SET claim_expires_at=clock_timestamp()-interval '1 second' WHERE scan_id='00000000-0000-4000-8000-00000000e102' AND claim_token IS NOT NULL;
SELECT extensions.is(public.finish_initial_analysis_media_erasure((SELECT (value#>>'{object,object_id}')::UUID FROM first_claim),(SELECT (value#>>'{object,claim_token}')::UUID FROM first_claim),TRUE)->>'outcome','stale','expired token');
CREATE TEMP TABLE renewed_claim AS SELECT public.claim_initial_analysis_media_erasure() AS value;
SELECT extensions.is((SELECT value#>>'{object,object_id}' FROM renewed_claim),(SELECT value#>>'{object,object_id}' FROM first_claim),'same original object recovery');
SELECT extensions.is(public.finish_initial_analysis_media_erasure((SELECT (value#>>'{object,object_id}')::UUID FROM renewed_claim),(SELECT (value#>>'{object,claim_token}')::UUID FROM renewed_claim),TRUE)->>'outcome','acknowledged','current marker confirmation');
SELECT extensions.is(public.finish_initial_analysis_media_erasure((SELECT (value#>>'{object,object_id}')::UUID FROM renewed_claim),(SELECT (value#>>'{object,claim_token}')::UUID FROM renewed_claim),TRUE)->>'outcome','stale','duplicate acknowledgement stale');
SELECT extensions.throws_ok($$UPDATE internal.initial_analysis_media_registry SET retired=FALSE$$,'22023','initial_analysis_storage_immutable','irreversible retirement');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_analysis_media_registry$$,'22023','initial_analysis_storage_immutable','registry cannot prune');
SELECT extensions.is(public.retire_initial_analysis_media('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',pg_temp.media_digest('00000000-0000-4000-8000-00000000e101'))->>'outcome','retired','empty cohort retires through same state machine');
SELECT extensions.is(public.retire_initial_analysis_media('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',pg_temp.media_digest('00000000-0000-4000-8000-00000000e101'))->>'outcome','retired','live exact retirement idempotent');
CREATE TEMP TABLE saved_digests AS SELECT scan_id,submission_digest FROM internal.initial_analysis_admissions WHERE scan_id IN ('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e103');
SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e102');
SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_cohorts WHERE scan_id IN ('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e103')),0::BIGINT,'cancel erases private roles including empty cohort');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id IN ('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e103')),10::BIGINT,'cleanup discoverability survives');
SELECT extensions.throws_ok(format('SELECT public.%I(%L,%L,%L%s)',fn,'00000000-0000-4000-8000-00000000e001',scan_id,submission_digest,
 CASE WHEN fn='allocate_initial_analysis_media' THEN ',''00000000-0000-4000-8000-00000000e000''' ELSE '' END),
 '55000','initial_analysis_cancelled','cancel precedence') FROM saved_digests CROSS JOIN unnest(ARRAY['allocate_initial_analysis_media','get_initial_analysis_media','retire_initial_analysis_media']) fn;
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) SELECT scan_id,NULL,clock_timestamp() FROM saved_digests;
SELECT extensions.throws_ok(format('SELECT public.%I(%L,%L,%L%s)',fn,'00000000-0000-4000-8000-00000000e001',scan_id,submission_digest,
 CASE WHEN fn='allocate_initial_analysis_media' THEN ',''00000000-0000-4000-8000-00000000e000''' ELSE '' END),
 '55000','initial_analysis_deleted','strong deletion precedence') FROM saved_digests CROSS JOIN unnest(ARRAY['allocate_initial_analysis_media','get_initial_analysis_media','retire_initial_analysis_media']) fn;
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE,media_backend_generation='00000000-0000-4000-8000-00000000e000';
SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e103',pg_temp.media_input());
SELECT extensions.is(public.get_initial_analysis_media('00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e103',pg_temp.media_digest('00000000-0000-4000-8000-00000000e103'))->>'reason','missing','missing read does not allocate');
CREATE FUNCTION pg_temp.reject_cohort() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN RAISE EXCEPTION 'synthetic_cohort_failure' USING ERRCODE='22023'; END; $$;
CREATE TRIGGER zz_reject_cohort BEFORE INSERT ON internal.initial_analysis_media_cohorts FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_cohort();
SELECT extensions.throws_ok($$SELECT pg_temp.media_allocate('00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e103')$$,'22023','synthetic_cohort_failure','all allocations roll back on private cohort failure');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id='00000000-0000-4000-8000-00000000e103'),'rollback permanent fence');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id='00000000-0000-4000-8000-00000000e103'),'rollback orphan destinations');
DROP TRIGGER zz_reject_cohort ON internal.initial_analysis_media_cohorts;
SELECT pg_temp.media_allocate('00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e103');
INSERT INTO saved_digests SELECT scan_id,submission_digest FROM internal.initial_analysis_admissions WHERE scan_id='00000000-0000-4000-8000-00000000e103';
-- Positive later-use evidence excludes expiry retirement.
ALTER TABLE internal.initial_analysis_media_cohorts DISABLE TRIGGER guard_initial_media_cohort;
UPDATE internal.initial_analysis_media_cohorts SET binding=jsonb_set(binding,'{expires_at}','1');
ALTER TABLE internal.initial_analysis_media_cohorts ENABLE TRIGGER guard_initial_media_cohort;
INSERT INTO internal.initial_analysis_results(scan_id,owner_id,result_evidence_id,result_schema_version,result_snapshot,provenance_snapshot)
 VALUES('00000000-0000-4000-8000-00000000e103','00000000-0000-4000-8000-00000000e002',gen_random_uuid(),1,'{}','{}');
SELECT extensions.is(public.retire_initial_analysis_media('00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e103',pg_temp.media_digest('00000000-0000-4000-8000-00000000e103'))->>'reason','in_use','result evidence prevents expiry retirement');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id='00000000-0000-4000-8000-00000000e103' AND retired),0::BIGINT,'later use retains all objects');
SELECT public.apply_user_tombstone('00000000-0000-4000-8000-00000000e002');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_media_cohorts WHERE scan_id IN ('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e103')),'account detachment erases pre-enrollment private cohort');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id='00000000-0000-4000-8000-00000000e103' AND retired),10::BIGINT,'account detachment retires destinations');
SELECT extensions.throws_ok(format('SELECT public.%I(%L,%L,%L%s)',fn,'00000000-0000-4000-8000-00000000e002',scan_id,submission_digest,
 CASE WHEN fn='allocate_initial_analysis_media' THEN ',''00000000-0000-4000-8000-00000000e000''' ELSE '' END),
 'P0002','initial_analysis_owner_unavailable','account erasure never reconstructs private binding') FROM saved_digests CROSS JOIN unnest(ARRAY['allocate_initial_analysis_media','get_initial_analysis_media','retire_initial_analysis_media']) fn WHERE scan_id='00000000-0000-4000-8000-00000000e103';
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT * FROM internal.initial_analysis_media_cohorts$$,'42501',NULL,'actual service role cannot directly read manifest');
SELECT extensions.lives_ok($$SELECT public.claim_initial_analysis_media_erasure()$$,'actual service role may claim closed cleanup envelope');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
