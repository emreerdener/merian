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

-- This whole fixture is synthetic and rolled back. It installs no runtime,
-- performs no object/provider IO and grants no qualification outside this test.
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_profiles),0::BIGINT,'CPM profiles unseeded');
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_current_selection),0::BIGINT,'CPM selection unseeded');
SELECT extensions.is((SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout),FALSE,'ordinary activation held');
SELECT extensions.ok(NOT EXISTS(
 SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) r
 CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p
 CROSS JOIN unnest(ARRAY['initial_cpm_photo_profiles','initial_cpm_photo_profile_eligibility','initial_cpm_photo_selections',
  'initial_cpm_photo_current_selection','initial_cpm_photo_role_mapping','initial_cpm_photo_capacity_reservations']) t
 WHERE has_table_privilege(r,'internal.'||t,p)),'private CPM tables inaccessible to application roles');
SELECT extensions.lives_ok($$SELECT internal.assert_ghost_profile_merge_reference_policy_coverage()$$,'new owner reference classified by existing merge owner');
SELECT extensions.is((SELECT strategy FROM internal.ghost_profile_merge_reference_policies
 WHERE source_schema='internal' AND source_table='initial_cpm_photo_capacity_reservations' AND source_column='owner_id'),
 'preserve','capacity ownership cannot transfer during identity merge');
SELECT extensions.is((SELECT root_name||':'||row_limit FROM internal.initial_cancellation_private_catalog()
 WHERE relation_name='internal.initial_cpm_photo_role_mapping'),'intent:6','CPM private cascade has bounded existing C1 ownership');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_cancellation_private_catalog()
 WHERE relation_name='internal.initial_cpm_photo_capacity_reservations'),'surviving capacity is not a private erasure child');
SELECT extensions.is((SELECT count(*) FROM pg_trigger WHERE tgrelid='internal.initial_cpm_photo_role_mapping'::REGCLASS
 AND NOT tgisinternal AND tgenabled='O' AND tgname IN ('a0_initial_cancellation_private','a0_initial_cancellation_private_truncate',
 'z9_initial_cancellation_private_after','a00_initial_cancellation_seal','a00_initial_admission_seal',
 'a000_initial_media_handoff_statement','z999_initial_media_handoff_statement','a000_initial_media_handoff_row','z999_initial_media_handoff_row')),
 9::BIGINT,'new private child installs all existing mutation boundaries');
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000f001');
CREATE TEMP TABLE cpm_fixture AS SELECT $fixture${"version":1,"variant":"client_prepared_photo","content_canonical":"{\"contexts\":[{\"text_utf8_base64\":\"IO+7v2EAZcyB8J+mrQo=\"}],\"contract\":\"client_prepared_media_v1\",\"kind\":\"initial_photo\",\"package_id\":\"00000000-0000-4000-8000-000000000002\",\"photos\":[{\"ai\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000004\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"display\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000005\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"ordinal\":0,\"recipe\":{\"camera_vertical_center_bits\":null,\"crop_display_size_bits\":null,\"format\":\"nativeStillImageV1\",\"is_pro\":false,\"offset_x_bits\":\"8000000000000000\",\"offset_y_bits\":\"0000000000000000\",\"quarter_turns\":0,\"scale_bits\":\"3ff0000000000000\"},\"source\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000003\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}}],\"resource_profile\":\"P1-L1\",\"scan_id\":\"00000000-0000-4000-8000-000000000001\",\"version\":1}","admission":{"client_protocol":3,"identification_protocol":6,"expected_processor_permission":"google_gemini"}}$fixture$::JSONB value;

CREATE FUNCTION pg_temp.cpm_candidate(scan UUID) RETURNS TEXT LANGUAGE SQL AS $$
 SELECT internal.initial_canonical(jsonb_set(value,'{content_canonical}',to_jsonb(
  internal.initial_canonical(jsonb_set((value->>'content_canonical')::JSONB,'{scan_id}',to_jsonb(scan::TEXT)))))) FROM cpm_fixture;
$$;
CREATE FUNCTION pg_temp.cpm_create(scan UUID, owner_id UUID DEFAULT '00000000-0000-4000-8000-00000000f001') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.create_initial_preparation_intent(owner_id,scan,pg_temp.cpm_candidate(scan));
$$;
SELECT extensions.throws_ok($$SELECT pg_temp.cpm_create('00000000-0000-4000-8000-00000000f101')$$,'55000','initial_analysis_unavailable','held activation refuses allocation');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;
SELECT extensions.throws_ok($$SELECT pg_temp.cpm_create('00000000-0000-4000-8000-00000000f101')$$,'55000','initial_analysis_preparation_unavailable','missing CPM selector refuses allocation');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_operation_fences),0::BIGINT,'failed selection leaves no claim');
CREATE TEMP TABLE cpm_profile AS SELECT jsonb_build_object('version',1,'resource_profile','P1-L1','input_profile','vision_compat_v1',
 'route','identify','output_language','en','composition_policy','cpm_photo_contexts_v1','verifier_protocol','cpm_photo_full_bytes_v1',
 'verifier_build_digest',repeat('a',64),'original_content_types',jsonb_build_array('image/jpeg','image/png'),
 'asset_manifest_digest',configuration_assets_digest,'evidence_digest',repeat('c',64),'reviewed_revision',repeat('d',40)) value
 FROM internal.initial_analysis_rollout;
INSERT INTO internal.initial_cpm_photo_profiles
 SELECT encode(extensions.digest(convert_to('merian.initial-analysis.cpm-photo-profile.v1'||E'\n'||internal.initial_canonical(value),'UTF8'),'sha256'),'hex'),
 value->>'resource_profile',value->>'input_profile',value->>'route',value->>'output_language',value->>'composition_policy',value->>'verifier_protocol',
 value->>'verifier_build_digest',ARRAY(SELECT jsonb_array_elements_text(value->'original_content_types')),
 value->>'asset_manifest_digest',value->>'evidence_digest',value->>'reviewed_revision' FROM cpm_profile;
INSERT INTO internal.initial_preparation_installations(digest,target_kind,target_digest,evidence_digest,reviewed_revision,installer_protocol)
 SELECT internal.initial_media_contract_digest('installation',internal.initial_canonical(v)),v->>'target_kind',v->>'target_digest',v->>'evidence_digest',v->>'reviewed_revision',v->>'installer_protocol'
 FROM (SELECT jsonb_build_object('target_kind','profile','target_digest',digest,'evidence_digest',evidence_digest,'reviewed_revision',reviewed_revision,
 'installer_protocol','reviewed_database_owner_install_v1') v FROM internal.initial_cpm_photo_profiles) x;
INSERT INTO internal.initial_cpm_photo_profile_eligibility(profile_digest,installation_digest,state)
 SELECT target_digest,digest,'eligible' FROM internal.initial_preparation_installations WHERE target_kind='profile';
CREATE TEMP TABLE backend_fixture AS SELECT jsonb_build_object('generation','00000000-0000-4000-8000-00000000fb01','provider','r2','direct_endpoint','https://'||repeat('0',32)||'.r2.cloudflarestorage.com','private_bucket','synthetic-only','namespace','initial-preparation/v2','credential_profile','synthetic_only','storage_protocol','conditional_create_permanent_same_key_marker_v1') value;
INSERT INTO internal.initial_preparation_source_backends(generation,configuration_digest,provider,direct_endpoint,private_bucket,namespace,credential_profile,storage_protocol)
SELECT (value->>'generation')::UUID,internal.initial_media_contract_digest('backend',internal.initial_canonical(value)),value->>'provider',value->>'direct_endpoint',value->>'private_bucket',value->>'namespace',value->>'credential_profile',value->>'storage_protocol' FROM backend_fixture;
INSERT INTO internal.initial_preparation_installations(digest,target_kind,target_digest,evidence_digest,reviewed_revision,installer_protocol)
SELECT internal.initial_media_contract_digest('installation',internal.initial_canonical(value)),value->>'target_kind',value->>'target_digest',value->>'evidence_digest',value->>'reviewed_revision',value->>'installer_protocol' FROM (
 SELECT jsonb_build_object('target_kind','backend','target_digest',configuration_digest,'evidence_digest',repeat('a',64),'reviewed_revision',repeat('b',40),'installer_protocol','reviewed_database_owner_install_v1') value FROM internal.initial_preparation_source_backends) x;
INSERT INTO internal.initial_preparation_backend_eligibility(generation,configuration_digest,installation_digest,state) SELECT b.generation,b.configuration_digest,i.digest,'eligible' FROM internal.initial_preparation_source_backends b JOIN internal.initial_preparation_installations i ON i.target_kind='backend' AND i.target_digest=b.configuration_digest;

INSERT INTO internal.initial_cpm_photo_selections(generation,profile_digest,backend_generation)
 SELECT '00000000-0000-4000-8000-00000000fc01',digest,'00000000-0000-4000-8000-00000000fb01' FROM internal.initial_cpm_photo_profiles;
INSERT INTO internal.initial_cpm_photo_current_selection VALUES('P1-L1','00000000-0000-4000-8000-00000000fc01');
CREATE TEMP TABLE cpm_saved AS SELECT pg_temp.cpm_create('00000000-0000-4000-8000-00000000f101') response;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
-- Negotiated backend projection: preserve old replies and all original liabilities.
SAVEPOINT backend_projection;
CREATE TEMP TABLE cpm_bound_saved AS SELECT public.create_initial_cpm_photo_v3_allocation(
 '00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101',
 pg_temp.cpm_candidate('00000000-0000-4000-8000-00000000f101')) response;
SELECT extensions.is(response->>'version','3','negotiated private v3 allocation') FROM cpm_bound_saved;
SELECT extensions.is(response-'backend_generation'-'backend_configuration_digest'-'version',
 (SELECT response-'version' FROM cpm_saved),'v3 retains exact original assignment') FROM cpm_bound_saved;
SELECT extensions.is(response->>'backend_configuration_digest',
 (SELECT configuration_digest FROM internal.initial_preparation_source_backends WHERE generation='00000000-0000-4000-8000-00000000fb01'),
 'v3 digest comes from immutable saved backend') FROM cpm_bound_saved;
SELECT extensions.is(public.get_initial_cpm_photo_v3_status('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101'),response,
 'v3 status exactly recovers original tuple') FROM cpm_bound_saved;
SELECT extensions.throws_ok($$SELECT public.get_initial_cpm_photo_v3_status('00000000-0000-4000-8000-00000000f002','00000000-0000-4000-8000-00000000f101')$$,
 'P0002','initial_analysis_owner_unavailable','v3 foreign owner remains opaque');
SELECT extensions.throws_ok($$SELECT internal.initial_cpm_photo_bound_response('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101',
 (SELECT response||jsonb_build_object('assignment_digest',repeat('0',64)) FROM cpm_saved))$$,
 '22023','initial_analysis_input_invalid','v3 cannot bind altered assignment digest');
SELECT extensions.ok(NOT has_function_privilege(r,signature,'EXECUTE'),'v3 denies '||r||' on '||signature)
 FROM unnest(ARRAY['anon','authenticated']) r CROSS JOIN unnest(ARRAY[
 'public.create_initial_cpm_photo_v3_allocation(uuid,uuid,text)','public.get_initial_cpm_photo_v3_status(uuid,uuid)']) signature;
SELECT extensions.ok(has_function_privilege('service_role',signature,'EXECUTE'),'v3 service role allowed on '||signature)
 FROM unnest(ARRAY['public.create_initial_cpm_photo_v3_allocation(uuid,uuid,text)','public.get_initial_cpm_photo_v3_status(uuid,uuid)']) signature;
SELECT extensions.ok(NOT has_function_privilege(r,'internal.initial_cpm_photo_bound_response(uuid,uuid,jsonb)','EXECUTE'),'binding helper denies '||r)
 FROM unnest(ARRAY['anon','authenticated','service_role']) r;
SAVEPOINT fresh_backend_projection;
CREATE TEMP TABLE cpm_bound_fresh AS SELECT public.create_initial_cpm_photo_v3_allocation(
 '00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f102',
 pg_temp.cpm_candidate('00000000-0000-4000-8000-00000000f102')) response;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.is(response->>'version','3','fresh v3 create projects its just-persisted assignment in the same transaction') FROM cpm_bound_fresh;
SELECT extensions.is(public.get_initial_cpm_photo_v3_status('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f102'),response,
 'fresh v3 create and recovered status are identical') FROM cpm_bound_fresh;
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_capacity_reservations),2::BIGINT,'fresh v3 adds one liability');
SELECT extensions.ok(internal.initial_cpm_photo_cohort_complete('00000000-0000-4000-8000-00000000f102'),'fresh v3 cohort complete');
ROLLBACK TO fresh_backend_projection;
RELEASE fresh_backend_projection;
-- Rotation installs a different immutable generation. It must not rebase the old cohort.
INSERT INTO internal.initial_preparation_source_backends(generation,configuration_digest,provider,direct_endpoint,private_bucket,namespace,credential_profile,storage_protocol)
 SELECT (v->>'generation')::UUID,internal.initial_media_contract_digest('backend',internal.initial_canonical(v)),v->>'provider',v->>'direct_endpoint',v->>'private_bucket',v->>'namespace',v->>'credential_profile',v->>'storage_protocol'
 FROM (SELECT value||jsonb_build_object('generation','00000000-0000-4000-8000-00000000fb02','private_bucket','synthetic-rotated') v FROM backend_fixture) fixture;
INSERT INTO internal.initial_cpm_photo_selections(generation,profile_digest,backend_generation)
 SELECT '00000000-0000-4000-8000-00000000fc02',digest,'00000000-0000-4000-8000-00000000fb02' FROM internal.initial_cpm_photo_profiles;
UPDATE internal.initial_cpm_photo_current_selection SET generation='00000000-0000-4000-8000-00000000fc02';
UPDATE internal.initial_preparation_backend_eligibility SET state='revoked' WHERE generation='00000000-0000-4000-8000-00000000fb01';
SELECT extensions.is(public.get_initial_cpm_photo_v3_status('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101'),response,
 'rotation and revocation do not rewrite historical tuple') FROM cpm_bound_saved;
SELECT extensions.is(public.create_initial_cpm_photo_v3_allocation('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101',
 pg_temp.cpm_candidate('00000000-0000-4000-8000-00000000f101')),response,'create replay preserves old tuple after rotation') FROM cpm_bound_saved;
SELECT extensions.is(public.get_initial_preparation_status('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101'),response,
 'legacy status unchanged after v3 recovery') FROM cpm_saved;
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_capacity_reservations),1::BIGINT,'v3 replay retains single liability');
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_write_attempts),0::BIGINT,'v3 metadata never issues a write');
ROLLBACK TO backend_projection;
RELEASE backend_projection;
SELECT extensions.is(response->>'outcome','allocated','closed allocation reply') FROM cpm_saved;
SELECT extensions.is(response->>'authority','none','allocation grants no authority') FROM cpm_saved;
SELECT extensions.ok(internal.initial_cpm_photo_cohort_complete('00000000-0000-4000-8000-00000000f101'),'complete bound cohort');
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_role_mapping),3::BIGINT,'three distinct roles even with equal hashes');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_source_mapping),0::BIGINT,'no fabricated legacy source mappings');
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_capacity_reservations WHERE state='pending'),1::BIGINT,'one pending capacity reservation');
SELECT extensions.is((SELECT declared_retained_bytes FROM internal.initial_cpm_photo_capacity_reservations),3::BIGINT,'all role occurrences counted');
SELECT extensions.is((SELECT expires_at-created_at FROM internal.initial_analysis_preparation_intents),INTERVAL '30 minutes','fixed CPM deadline');
SELECT extensions.is(pg_temp.cpm_create('00000000-0000-4000-8000-00000000f101'),response,'lost acknowledgement recovers exact original') FROM cpm_saved;
SELECT extensions.is(public.get_initial_preparation_status('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101'),response,'status recovers exact original') FROM cpm_saved;
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_capacity_reservations),1::BIGINT,'replay does not reserve again');
SELECT extensions.throws_ok($$SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101',
 internal.initial_canonical(jsonb_set(pg_temp.cpm_candidate('00000000-0000-4000-8000-00000000f101')::JSONB,'{admission,expected_processor_permission}','"openai"')))$$,
 '22023','initial_analysis_identity_conflict','changed candidate never rebases original');
SELECT extensions.throws_ok($$UPDATE internal.initial_cpm_photo_capacity_reservations SET state='released'$$,'22023','initial_analysis_storage_immutable','live intent cannot release capacity');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_cpm_photo_role_mapping$$,'22023','initial_analysis_storage_immutable','cannot drop a live role');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_analysis_preparation_intents$$,'22023','initial_analysis_storage_immutable','cannot drop live intent');
SELECT extensions.throws_ok($$SELECT internal.initial_preparation_execution_action('status','00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101',(SELECT response->>'assignment_digest' FROM cpm_saved))$$,
 '55000','initial_analysis_cpm_io_unavailable','legacy execution refuses CPM');
SELECT extensions.throws_ok($$INSERT INTO internal.initial_preparation_source_verifications(scan_id,canonical_receipt,digest) VALUES('00000000-0000-4000-8000-00000000f101','{}',repeat('a',64))$$,
 '55000','initial_analysis_cpm_io_unavailable','raw legacy source proof refuses CPM');
SELECT extensions.throws_ok($$SELECT * FROM public.reserve_identification_quota('00000000-0000-4000-8000-00000000f001','scan_identification','00000000-0000-4000-8000-00000000f101',repeat('a',64),'00000000-0000-4000-8000-00000000f101',FALSE,3,FALSE,'vision_compat_v1','google_gemini',6)$$,'55000',NULL,'direct legacy quota path cannot fund CPM');
SELECT extensions.throws_ok($$SELECT public.finalize_initial_preparation('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101',NULL)$$,'55000','initial_analysis_cpm_io_unavailable','legacy finalize cannot fund CPM');
CREATE FUNCTION pg_temp.incomplete_capacity() RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO internal.initial_analysis_operation_fences VALUES('00000000-0000-4000-8000-00000000f199');
 INSERT INTO internal.initial_cpm_photo_capacity_reservations(scan_id,owner_id,declared_retained_bytes)
 VALUES('00000000-0000-4000-8000-00000000f199','00000000-0000-4000-8000-00000000f001',3);
 SET CONSTRAINTS ALL IMMEDIATE;
END; $$;
SELECT extensions.throws_ok($$SELECT pg_temp.incomplete_capacity()$$,'23514','initial_analysis_source_cohort_invalid','partial raw reservation cannot commit');
CREATE TEMP TABLE cpm_service_request AS SELECT pg_temp.cpm_candidate('00000000-0000-4000-8000-00000000f102') candidate;
GRANT SELECT ON cpm_service_request TO service_role;
SET LOCAL ROLE service_role;
SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f102',(SELECT candidate FROM cpm_service_request))->>'outcome';
SET CONSTRAINTS ALL IMMEDIATE;
RESET ROLE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.ok(internal.initial_cpm_photo_cohort_complete('00000000-0000-4000-8000-00000000f102'),'service-role second slot and deferred validation');
SELECT extensions.throws_ok($$SELECT pg_temp.cpm_create('00000000-0000-4000-8000-00000000f103')$$,'55000','initial_analysis_capacity_unavailable','third owner slot denied');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id='00000000-0000-4000-8000-00000000f103'),'capacity rejection rolls back identity claim');
-- Outstanding-write bookkeeping is database-owner-only and grants no IO.
SAVEPOINT closure_cases;
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_write_policies),0::BIGINT,'closure policy is never installed by migration');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) r
 CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) privilege
 CROSS JOIN unnest(ARRAY['initial_cpm_photo_write_policies','initial_cpm_photo_write_closures']) t
 WHERE has_table_privilege(r,'internal.'||t,privilege)),'closure tables deny API roles');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) r
 CROSS JOIN unnest(ARRAY['internal.bind_initial_cpm_photo_write_policy(uuid,uuid,text)','internal.settle_initial_cpm_photo_write_closure(uuid,text,text,timestamptz,uuid)']) f
 WHERE has_function_privilege(r,f,'EXECUTE')),'closure routines deny API roles');
CREATE TEMP TABLE closure_policy AS SELECT jsonb_build_object('version',1,'backend_generation',generation,
 'backend_configuration_digest',configuration_digest,'observation_build_digest',repeat('1',64),
 'enforcement_evidence_digest',repeat('2',64),'reviewed_revision',repeat('3',40),
 'protocol','conditional_create_permanent_same_key_marker_v1') v FROM internal.initial_preparation_source_backends;
INSERT INTO internal.initial_cpm_photo_write_policies
 SELECT encode(extensions.digest(convert_to('merian.initial-analysis.cpm-write-policy.v1'||E'\n'||internal.initial_canonical(v),'UTF8'),'sha256'),'hex'),
 (v->>'backend_generation')::UUID,v->>'backend_configuration_digest',v->>'observation_build_digest',v->>'enforcement_evidence_digest',v->>'reviewed_revision',v->>'protocol','eligible'
 FROM closure_policy;
-- END CPM CLOSURE POLICY FIXTURE
-- A verification start is durable and cannot become fresh again after a lost
-- response. This remains a private start boundary, not verifier/admission proof.
SAVEPOINT verification_start;
CREATE FUNCTION pg_temp.start_verification() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT internal.begin_initial_cpm_photo_verification(owner_id,scan_id,assignment_digest)
 FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000f101';
$$;
SELECT extensions.ok(NOT has_function_privilege(r,
 'internal.begin_initial_cpm_photo_verification(uuid,uuid,text)','EXECUTE'),'verification start denies '||r)
 FROM unnest(ARRAY['anon','authenticated','service_role']) r;
SELECT extensions.ok(NOT has_table_privilege(r,'internal.initial_cpm_verification_start_context',privilege),
 'private start context denies '||r||' '||privilege)
 FROM unnest(ARRAY['anon','authenticated','service_role']) r
 CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) privilege;
SELECT extensions.throws_ok($$SELECT pg_temp.start_verification()$$,'55000','initial_analysis_verification_required',
 'verification cannot start from an allocated but unwritten cohort');
DO $$ DECLARE s internal.initial_analysis_preparation_intents; m RECORD;
 w internal.initial_cpm_photo_write_attempts; policy TEXT;
BEGIN
 SELECT * INTO STRICT s FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000f101';
 SELECT digest INTO STRICT policy FROM internal.initial_cpm_photo_write_policies;
 FOR m IN SELECT object_id FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=s.scan_id ORDER BY object_id LOOP
  w:=internal.initial_cpm_photo_write_action('bind',s.owner_id,s.scan_id,s.assignment_digest,m.object_id);
  PERFORM internal.bind_initial_cpm_photo_write_policy(s.owner_id,w.attempt_id,policy);
  w:=internal.initial_cpm_photo_write_action('may_have_issued',s.owner_id,s.scan_id,s.assignment_digest,m.object_id);
  PERFORM internal.settle_initial_cpm_photo_write_closure(w.attempt_id,policy,'live_object',w.issued_at,NULL);
 END LOOP;
END; $$;
SAVEPOINT verification_revoked;
UPDATE internal.initial_cpm_photo_write_policies SET state='revoked';
SELECT extensions.throws_ok($$SELECT pg_temp.start_verification()$$,'55000','initial_analysis_preparation_unavailable',
 'revoked closure policy cannot authorize a fresh verification start');
ROLLBACK TO verification_revoked;
SELECT extensions.throws_ok($$UPDATE internal.initial_analysis_preparation_intents
 SET cpm_verification_attempt_id=gen_random_uuid(),cpm_verification_started_at=clock_timestamp(),
 cpm_verification_snapshot_digest=repeat('a',64) WHERE scan_id='00000000-0000-4000-8000-00000000f101'$$,
 '22023','initial_analysis_storage_immutable','raw verification start cannot fabricate a snapshot');
SELECT extensions.throws_ok($forged$DO $$ DECLARE s internal.initial_analysis_preparation_intents;
 attempt UUID:=gen_random_uuid(); snapshot TEXT;
BEGIN
 SELECT * INTO STRICT s FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000f101';
 snapshot:=internal.initial_cpm_verification_start_snapshot(s.owner_id,s.scan_id);
 PERFORM set_config('merian.initial_cpm_verification_start',s.scan_id::TEXT||':'||attempt::TEXT,TRUE);
 UPDATE internal.initial_analysis_preparation_intents SET cpm_verification_attempt_id=attempt,
  cpm_verification_started_at=clock_timestamp(),cpm_verification_snapshot_digest=encode(extensions.digest(convert_to(
   'merian.initial-analysis.cpm-verification-start.v1'||E'\n'||snapshot,'UTF8'),'sha256'),'hex') WHERE scan_id=s.scan_id;
END; $$;$forged$,'22023','initial_analysis_storage_immutable','forged routing marker with a correct snapshot is not a writer context');
CREATE TEMP TABLE verification_nested_denials(denied BOOLEAN);
CREATE FUNCTION pg_temp.nested_verification_start() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 BEGIN
  UPDATE internal.initial_analysis_preparation_intents SET cpm_verification_attempt_id=NEW.cpm_verification_attempt_id,
   cpm_verification_started_at=NEW.cpm_verification_started_at,cpm_verification_snapshot_digest=NEW.cpm_verification_snapshot_digest
   WHERE scan_id=NEW.scan_id;
 EXCEPTION WHEN SQLSTATE '22023' THEN
  IF SQLERRM<>'initial_analysis_storage_immutable' THEN RAISE; END IF;
  INSERT INTO verification_nested_denials VALUES(TRUE); RETURN NEW;
 END;
 RAISE EXCEPTION 'nested verification start consumed the same context twice' USING ERRCODE='ZX701';
END; $$;
CREATE TRIGGER zzzz_nested_verification_start BEFORE UPDATE ON internal.initial_analysis_preparation_intents
 FOR EACH ROW EXECUTE FUNCTION pg_temp.nested_verification_start();
CREATE TEMP TABLE verification_started AS SELECT pg_temp.start_verification() value;
DROP TRIGGER zzzz_nested_verification_start ON internal.initial_analysis_preparation_intents;
SELECT extensions.is((SELECT count(*) FROM verification_nested_denials WHERE denied),1::BIGINT,
 'exact nested UPDATE cannot reuse the original consumed context');
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_verification_start_context),0::BIGINT,
 'successful start leaves no reusable transaction context');
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.throws_ok($unconsumed$DO $$ BEGIN
 INSERT INTO internal.initial_cpm_verification_start_context
 VALUES(pg_catalog.pg_current_xact_id(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),repeat('a',64),repeat('b',64));
 SET CONSTRAINTS ALL IMMEDIATE;
END; $$;$unconsumed$,'55000','initial_analysis_verification_start_incomplete',
 'unconsumed private context cannot survive deferred validation');
CREATE TEMP TABLE verification_intent_digest AS
 SELECT internal.initial_cpm_verification_intent_digest(s) digest
 FROM internal.initial_analysis_preparation_intents s WHERE scan_id='00000000-0000-4000-8000-00000000f101';
SELECT extensions.is(value->>'outcome','started','complete closed cohort starts verification once') FROM verification_started;
SELECT extensions.is(jsonb_array_length((value->>'snapshot_canonical')::JSONB->'members'),3,
 'start snapshot covers original, AI and display roles') FROM verification_started;
SET LOCAL TIME ZONE 'Pacific/Auckland';
SELECT extensions.is(internal.initial_cpm_verification_intent_digest(s),d.digest,
 'intent image digest survives a positive session offset')
 FROM internal.initial_analysis_preparation_intents s CROSS JOIN verification_intent_digest d
 WHERE s.scan_id='00000000-0000-4000-8000-00000000f101';
SELECT extensions.is(internal.initial_cpm_verification_start_snapshot(
 '00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101'),
 value->>'snapshot_canonical','exact snapshot timestamps are independent of a positive session offset') FROM verification_started;
SET LOCAL TIME ZONE 'America/Chicago';
SELECT extensions.is(internal.initial_cpm_verification_intent_digest(s),d.digest,
 'intent image digest survives a negative session offset')
 FROM internal.initial_analysis_preparation_intents s CROSS JOIN verification_intent_digest d
 WHERE s.scan_id='00000000-0000-4000-8000-00000000f101';
SELECT extensions.is(internal.initial_cpm_verification_start_snapshot(
 '00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101'),
 value->>'snapshot_canonical','exact snapshot timestamps are independent of a negative session offset') FROM verification_started;
SELECT extensions.is(pg_temp.start_verification(),'{"version":1,"outcome":"held","authority":"none"}'::JSONB,
 'lost fresh acknowledgement cannot be replayed into another media read');
SELECT extensions.is((SELECT cpm_verification_attempt_id::TEXT FROM internal.initial_analysis_preparation_intents
 WHERE scan_id='00000000-0000-4000-8000-00000000f101'),value->>'attempt_id','attempt identity remains fixed') FROM verification_started;
SELECT extensions.throws_ok($$UPDATE internal.initial_analysis_preparation_intents SET cpm_verification_attempt_id=NULL,
 cpm_verification_started_at=NULL,cpm_verification_snapshot_digest=NULL
 WHERE scan_id='00000000-0000-4000-8000-00000000f101'$$,'22023','initial_analysis_storage_immutable','started verifier cannot reset');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;
SELECT extensions.is(pg_temp.start_verification()->>'outcome','held','disabled fresh admission does not renew a started verifier');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations)
 AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_admissions),'verification start does not fund or admit');
ROLLBACK TO verification_start;

-- Fresh issuance is an invocation result, never inferred from a stored state.
SAVEPOINT fresh_issuance;
CREATE TEMP TABLE issuance_args AS SELECT s.owner_id,s.scan_id,s.assignment_digest,m.object_id,m.role,p.digest policy
 FROM internal.initial_analysis_preparation_intents s JOIN internal.initial_cpm_photo_role_mapping m USING(scan_id)
 CROSS JOIN internal.initial_cpm_photo_write_policies p WHERE s.scan_id='00000000-0000-4000-8000-00000000f101';
GRANT SELECT ON issuance_args TO service_role;
-- Status is a closed observation, including when no attempt exists.
CREATE FUNCTION pg_temp.write_status(role_name TEXT DEFAULT 'source') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.read_initial_cpm_photo_write_status(owner_id,scan_id,assignment_digest,object_id)
 FROM issuance_args WHERE role=role_name;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.write_status(TEXT) TO service_role;
SELECT extensions.ok(has_function_privilege('service_role','public.read_initial_cpm_photo_write_status(uuid,uuid,text,uuid)','EXECUTE'),'status service allowlisted');
SET LOCAL ROLE anon;
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_write_status(NULL,NULL,NULL,NULL)$$,'42501',NULL,'anon cannot read status');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_write_status(NULL,NULL,NULL,NULL)$$,'42501',NULL,'authenticated cannot read status directly');
RESET ROLE;
SAVEPOINT status_guard;
SELECT set_config('request.jwt.claim.role','',TRUE);
-- Test the internal guard independently of the production ACL. This temporary
-- grant exists only inside the rollback-local fixture savepoint.
GRANT EXECUTE ON FUNCTION public.read_initial_cpm_photo_write_status(UUID,UUID,TEXT,UUID) TO authenticated;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_write_status(NULL,NULL,NULL,NULL)$$,'42501','service_role authorization required','definer requires service caller internally');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_temp.write_status(),jsonb_build_object('version',1,'authority','none','scan_id',scan_id,
 'assignment_digest',assignment_digest,'object_id',object_id,'attempt',NULL),'actual opaque service recovers closed absent status') FROM issuance_args WHERE role='source';
RESET ROLE;
ROLLBACK TO status_guard;
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_write_attempts),0::BIGINT,'absent status never binds attempt');
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_write_status(gen_random_uuid(),scan_id,assignment_digest,object_id) FROM issuance_args WHERE role='source'$$,'P0002','initial_analysis_owner_unavailable','foreign owner denied status');
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_write_status(owner_id,scan_id,repeat('0',64),object_id) FROM issuance_args WHERE role='source'$$,'22023','initial_analysis_identity_conflict','changed digest denied status');
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_write_status(owner_id,scan_id,assignment_digest,gen_random_uuid()) FROM issuance_args WHERE role='source'$$,'22023','initial_analysis_identity_conflict','foreign object denied status');
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_write_status(owner_id,scan_id,'invalid',object_id) FROM issuance_args WHERE role='source'$$,'22023','initial_analysis_input_invalid','malformed digest denied status');
SAVEPOINT status_bound;
SELECT internal.initial_cpm_photo_write_action('bind',owner_id,scan_id,assignment_digest,object_id) IS NOT NULL FROM issuance_args WHERE role='source';
CREATE TEMP TABLE bound_status AS SELECT pg_temp.write_status() value;
SELECT extensions.is(value#>>'{attempt,state}','bound','bound status cannot advance possible issuance') FROM bound_status;
SELECT extensions.is(pg_temp.write_status(),value,'bound status preserves original clock') FROM bound_status;
SELECT extensions.is((SELECT state FROM internal.initial_cpm_photo_write_attempts),'bound','status leaves bound state');
ROLLBACK TO status_bound;

CREATE FUNCTION pg_temp.begin_write(role_name TEXT DEFAULT 'source') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.begin_initial_cpm_photo_write(owner_id,scan_id,assignment_digest,object_id,policy)
 FROM issuance_args WHERE role=role_name;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.begin_write(TEXT) TO service_role;
SELECT extensions.ok(has_function_privilege('service_role','public.begin_initial_cpm_photo_write(uuid,uuid,text,uuid,text)','EXECUTE'),'issuance service allowlisted');
SELECT extensions.ok(NOT has_function_privilege('anon','public.begin_initial_cpm_photo_write(uuid,uuid,text,uuid,text)','EXECUTE')
 AND NOT has_function_privilege('authenticated','public.begin_initial_cpm_photo_write(uuid,uuid,text,uuid,text)','EXECUTE'),'issuance denies client roles');
SELECT extensions.throws_ok($$SELECT public.begin_initial_cpm_photo_write(owner_id,scan_id,assignment_digest,object_id,NULL) FROM issuance_args WHERE role='source'$$,'22023','initial_analysis_input_invalid','policy required before bind');
SELECT extensions.throws_ok($$SELECT public.begin_initial_cpm_photo_write(owner_id,scan_id,assignment_digest,object_id,repeat('0',64)) FROM issuance_args WHERE role='source'$$,'55000','initial_analysis_preparation_unavailable','unknown policy rolls back binding');
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_write_attempts),0::BIGINT,'failed policy leaves no attempt');
SELECT extensions.throws_ok($$SELECT public.begin_initial_cpm_photo_write(gen_random_uuid(),scan_id,assignment_digest,object_id,policy) FROM issuance_args WHERE role='source'$$,'P0002','initial_analysis_owner_unavailable','foreign owner cannot advance');
SELECT extensions.throws_ok($$SELECT public.begin_initial_cpm_photo_write(owner_id,scan_id,repeat('0',64),object_id,policy) FROM issuance_args WHERE role='source'$$,'22023','initial_analysis_identity_conflict','changed assignment cannot advance');
SAVEPOINT issuance_revoked;
UPDATE internal.initial_cpm_photo_write_policies SET state='revoked';
SELECT extensions.throws_ok($$SELECT pg_temp.begin_write()$$,'55000','initial_analysis_preparation_unavailable','revoked policy cannot begin');
ROLLBACK TO issuance_revoked;
SAVEPOINT issuance_each_role;
SET LOCAL ROLE service_role;
CREATE TEMP TABLE issuance_fresh AS SELECT pg_temp.begin_write() value;
SELECT extensions.is((SELECT value->>'outcome' FROM issuance_fresh),'fresh','actual service caller receives fresh once');
SELECT extensions.is((SELECT value#>>'{observation,target,role}' FROM issuance_fresh),'source','fresh snapshot binds exact original role');
SELECT extensions.is((SELECT count(*)::INTEGER FROM issuance_fresh, jsonb_object_keys(value)),5,'fresh response is closed');
RESET ROLE;
CREATE TEMP TABLE issuance_row AS SELECT * FROM internal.initial_cpm_photo_write_attempts;
CREATE TEMP TABLE issued_status AS SELECT pg_temp.write_status() value;
CREATE TEMP TABLE status_capacity AS SELECT jsonb_agg(to_jsonb(c) ORDER BY c.scan_id) value FROM internal.initial_cpm_photo_capacity_reservations c;
SELECT extensions.is((SELECT value FROM issued_status),jsonb_build_object('version',1,'authority','none','scan_id',a.scan_id,
 'assignment_digest',a.assignment_digest,'object_id',a.object_id,'attempt',jsonb_build_object('attempt_id',a.attempt_id,'state',a.state,
 'created_at_ms',floor(extract(epoch FROM a.created_at)*1000)::BIGINT,
 'capability_expires_at_ms',floor(extract(epoch FROM a.capability_expires_at)*1000)::BIGINT,'write_closed',FALSE)),
 'issued status has exact closed public-safe fields, no private configuration') FROM issuance_row a;
SELECT extensions.ok(octet_length(value::TEXT)<=2048,'status projection fits two KiB') FROM issued_status;
SELECT extensions.is(pg_temp.write_status(),value,'lost response recovers exact attempt without issuance') FROM issued_status;
SELECT extensions.is((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.scan_id) FROM internal.initial_cpm_photo_capacity_reservations c),(SELECT value FROM status_capacity),'status never changes capacity');
SAVEPOINT status_revocation;
UPDATE internal.initial_cpm_photo_profile_eligibility SET state='revoked';
UPDATE internal.initial_preparation_backend_eligibility SET state='revoked';
UPDATE internal.initial_cpm_photo_write_policies SET state='revoked';
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;
SELECT extensions.is(pg_temp.write_status(),value,'revocation and rollout drift preserve exact status') FROM issued_status;
ROLLBACK TO status_revocation;
SAVEPOINT status_cancel;
SELECT public.cancel_initial_analysis(owner_id,scan_id)->>'dispatch' FROM issuance_args WHERE role='source';
SELECT extensions.throws_ok($$SELECT pg_temp.write_status()$$,'55000','initial_analysis_cancelled','cancelled scope cannot recover private status');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE retired AND state='may_have_issued'),'cancelled status denial retains liability');
ROLLBACK TO status_cancel;
SAVEPOINT status_account_delete;
DELETE FROM public.users WHERE id='00000000-0000-4000-8000-00000000f001';
SELECT extensions.throws_ok($$SELECT pg_temp.write_status()$$,'P0002','initial_analysis_owner_unavailable','deleted owner cannot recover private status');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations WHERE owner_id IS NULL AND state='pending'),'deleted status denial retains global liability');
ROLLBACK TO status_account_delete;

SELECT extensions.is((SELECT write_capability_state FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='00000000-0000-4000-8000-00000000f101'),'may_have_issued','fresh response retains outstanding liability');
SELECT extensions.is(pg_temp.begin_write(),jsonb_build_object('outcome','held','attempt_id',(SELECT attempt_id FROM issuance_row)),'lost fresh response recovers only held');
SELECT extensions.is(pg_temp.begin_write(),pg_temp.begin_write(),'repeated recovery never becomes fresh');
SELECT extensions.is((SELECT to_jsonb(a) FROM internal.initial_cpm_photo_write_attempts a),(SELECT to_jsonb(a) FROM issuance_row a),'replay does not renew clocks or alter attempt');
SELECT extensions.throws_ok($$SELECT pg_temp.begin_write('ai')$$,'55000','initial_analysis_cpm_write_outstanding','another role cannot overlap outstanding write');
SELECT extensions.throws_ok($$SELECT public.begin_initial_cpm_photo_write(owner_id,scan_id,assignment_digest,object_id,repeat('0',64)) FROM issuance_args WHERE role='source'$$,'22023','initial_analysis_identity_conflict','replay cannot substitute policy');
UPDATE internal.initial_cpm_photo_write_policies SET state='revoked';
SELECT extensions.is(pg_temp.begin_write()->>'outcome','held','historical held does not require fresh eligibility');
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK TO issuance_each_role;
SELECT extensions.is(pg_temp.begin_write('ai')#>>'{observation,target,role}','ai','AI fresh snapshot binds exact role');
ROLLBACK TO issuance_each_role;
SELECT extensions.is(pg_temp.begin_write('display')#>>'{observation,target,role}','display','display fresh snapshot binds exact role');
ROLLBACK TO fresh_issuance;

CREATE FUNCTION pg_temp.closure_write(action TEXT,role_name TEXT DEFAULT 'source') RETURNS internal.initial_cpm_photo_write_attempts LANGUAGE SQL AS $$
 SELECT internal.initial_cpm_photo_write_action(action,'00000000-0000-4000-8000-00000000f001',
 '00000000-0000-4000-8000-00000000f101',s.assignment_digest,m.object_id)
 FROM internal.initial_analysis_preparation_intents s JOIN internal.initial_cpm_photo_role_mapping m USING(scan_id)
 WHERE s.scan_id='00000000-0000-4000-8000-00000000f101' AND m.role=role_name;
$$;
CREATE TEMP TABLE closure_attempt AS SELECT (pg_temp.closure_write('bind')).*;
CREATE FUNCTION pg_temp.close_source(outcome TEXT DEFAULT 'live_object',at_time TIMESTAMPTZ DEFAULT NULL,claim UUID DEFAULT NULL)
 RETURNS internal.initial_cpm_photo_write_closures LANGUAGE SQL AS $$
 SELECT internal.settle_initial_cpm_photo_write_closure(a.attempt_id,p.digest,outcome,COALESCE(at_time,a.issued_at),claim)
 FROM internal.initial_cpm_photo_write_attempts a CROSS JOIN internal.initial_cpm_photo_write_policies p
 WHERE a.attempt_id=(SELECT attempt_id FROM closure_attempt);
$$;
SELECT extensions.throws_ok($$SELECT pg_temp.close_source()$$,'22023','initial_analysis_input_invalid','bound attempt has no issuance observation');
SAVEPOINT legacy_unbound;
SELECT (pg_temp.closure_write('may_have_issued')).state;
SELECT extensions.throws_ok($$SELECT pg_temp.close_source()$$,'55000','initial_analysis_preparation_required','legacy issued attempt cannot acquire closure policy afterwards');
SELECT extensions.throws_ok($$SELECT internal.bind_initial_cpm_photo_write_policy('00000000-0000-4000-8000-00000000f001',(SELECT attempt_id FROM closure_attempt),(SELECT digest FROM internal.initial_cpm_photo_write_policies))$$,'22023','initial_analysis_storage_immutable','policy cannot attach after issuance');
ROLLBACK TO legacy_unbound;
SELECT extensions.lives_ok($$SELECT internal.bind_initial_cpm_photo_write_policy('00000000-0000-4000-8000-00000000f001',(SELECT attempt_id FROM closure_attempt),(SELECT digest FROM internal.initial_cpm_photo_write_policies))$$,'bind policy before issuance');
SAVEPOINT revoked_backend_raw;
UPDATE internal.initial_preparation_backend_eligibility SET state='revoked';
SELECT extensions.throws_ok($raw$DO $$ BEGIN
 UPDATE internal.initial_cpm_photo_write_attempts SET state='may_have_issued',issued_at=clock_timestamp() WHERE attempt_id=(SELECT attempt_id FROM closure_attempt);
 UPDATE internal.initial_cpm_photo_capacity_reservations SET write_capability_state='may_have_issued' WHERE scan_id='00000000-0000-4000-8000-00000000f101';
 SET CONSTRAINTS ALL IMMEDIATE;
END $$;$raw$,'55000','initial_analysis_preparation_unavailable','raw policy-bound issuance honors backend revocation');
SELECT extensions.is((SELECT state FROM internal.initial_cpm_photo_write_attempts WHERE attempt_id=(SELECT attempt_id FROM closure_attempt)),'bound','raw revocation refusal preserves original state');
ROLLBACK TO revoked_backend_raw;
SAVEPOINT revoked_policy;
UPDATE internal.initial_cpm_photo_write_policies SET state='revoked';
SELECT extensions.throws_ok($$SELECT pg_temp.closure_write('may_have_issued')$$,'55000','initial_analysis_preparation_unavailable','revoked policy prevents issuance transition');
SELECT extensions.throws_ok($$UPDATE internal.initial_cpm_photo_write_policies SET state='eligible'$$,'22023','initial_analysis_storage_immutable','policy revocation irreversible');
ROLLBACK TO revoked_policy;
SELECT (pg_temp.closure_write('may_have_issued')).state;
CREATE FUNCTION pg_temp.observation_snapshot(outcome TEXT DEFAULT 'live_object',claim UUID DEFAULT NULL,expected JSONB DEFAULT NULL)
 RETURNS JSONB LANGUAGE SQL AS $$
 SELECT internal.read_initial_cpm_photo_observation((SELECT attempt_id FROM closure_attempt),outcome,claim,expected);
$$;
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 WHERE has_function_privilege(role_name,'internal.read_initial_cpm_photo_observation(uuid,text,uuid,jsonb)','EXECUTE')),'observation snapshot denies every API role');
CREATE TEMP TABLE observation_saved AS SELECT pg_temp.observation_snapshot() value;
SELECT extensions.is(value#>>'{target,role}','source','snapshot reads original mapped source role') FROM observation_saved;
SELECT extensions.is(value#>>'{target,sha256}',(SELECT canonical_assignment::JSONB#>>'{preparation,role_mapping,0,declaration,sha256}' FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000f101'),'snapshot hash comes from saved declaration') FROM observation_saved;
SELECT extensions.is(pg_temp.observation_snapshot('live_object',NULL,value),value,'unchanged current snapshot matches original') FROM observation_saved;
SELECT extensions.throws_ok($$SELECT pg_temp.observation_snapshot('live_object',NULL,(SELECT value||'{"extra":true}'::JSONB FROM observation_saved))$$,'22023','initial_analysis_identity_conflict','current check rejects changed original facts');
SELECT extensions.throws_ok($$SELECT pg_temp.observation_snapshot('live_object',gen_random_uuid())$$,'22023','initial_analysis_input_invalid','live observation refuses cleanup token');
SELECT extensions.throws_ok($$SELECT pg_temp.observation_snapshot('retired_marker',gen_random_uuid())$$,'55000','initial_analysis_preparation_required','marker observation refuses live registry');
SELECT extensions.throws_ok($$SELECT pg_temp.close_source('live_object','2000-01-01')$$,'55000','initial_analysis_preparation_required','observation cannot precede issuance');
SELECT extensions.throws_ok($$SELECT pg_temp.close_source('live_object',clock_timestamp()+INTERVAL '1 hour')$$,'55000','initial_analysis_preparation_required','future observation denied');
SELECT extensions.throws_ok($$SELECT pg_temp.close_source('retired_marker',NULL,gen_random_uuid())$$,'55000','initial_analysis_preparation_required','live registry denies marker closure');
SELECT extensions.throws_ok($$UPDATE internal.initial_cpm_photo_write_attempts SET write_closed=TRUE$$,'22023',NULL,'raw closure without receipt denied');
SAVEPOINT revoke_after_issue;
UPDATE internal.initial_cpm_photo_write_policies SET state='revoked';
SELECT extensions.throws_ok($$SELECT pg_temp.close_source()$$,'55000','initial_analysis_preparation_unavailable','revocation before settlement keeps hold');
SELECT extensions.throws_ok($$SELECT pg_temp.observation_snapshot()$$,'55000','initial_analysis_preparation_unavailable','revocation prevents fresh observation');
ROLLBACK TO revoke_after_issue;
-- Actual role boundary and exact microsecond transport; synthetic and rolled back.
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated']) r
 CROSS JOIN unnest(ARRAY['public.read_initial_cpm_photo_write_closure(uuid,text)',
 'public.read_initial_cpm_photo_observation(uuid,text,uuid,jsonb)',
 'public.settle_initial_cpm_photo_write_closure(uuid,text,text,text,uuid)']) f
 WHERE has_function_privilege(r,f,'EXECUTE')),'closure service facades deny user API roles');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM unnest(ARRAY[
 'public.read_initial_cpm_photo_write_closure(uuid,text)',
 'public.read_initial_cpm_photo_observation(uuid,text,uuid,jsonb)',
 'public.settle_initial_cpm_photo_write_closure(uuid,text,text,text,uuid)']) f
 WHERE NOT has_function_privilege('service_role',f,'EXECUTE')),'closure service facades grant only reviewed service access');
SET LOCAL ROLE anon;
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_write_closure(gen_random_uuid(),'live_object')$$,'42501',NULL,'anon cannot read closure');
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_observation(gen_random_uuid(),'live_object',NULL,NULL)$$,'42501',NULL,'anon cannot read snapshot');
SELECT extensions.throws_ok($$SELECT public.settle_initial_cpm_photo_write_closure(gen_random_uuid(),repeat('a',64),'live_object','2026-01-01T00:00:00.000000Z',NULL)$$,'42501',NULL,'anon cannot settle');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_write_closure(gen_random_uuid(),'live_object')$$,'42501',NULL,'authenticated cannot read closure');
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_observation(gen_random_uuid(),'live_object',NULL,NULL)$$,'42501',NULL,'authenticated cannot read snapshot');
SELECT extensions.throws_ok($$SELECT public.settle_initial_cpm_photo_write_closure(gen_random_uuid(),repeat('a',64),'live_object','2026-01-01T00:00:00.000000Z',NULL)$$,'42501',NULL,'authenticated cannot settle');
RESET ROLE;
SAVEPOINT closure_service_projection;
CREATE TEMP TABLE closure_service_args AS SELECT attempt_id,write_policy_digest policy,
 to_char((issued_at+INTERVAL '123 microseconds') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') observed
 FROM internal.initial_cpm_photo_write_attempts WHERE attempt_id=(SELECT attempt_id FROM closure_attempt);
GRANT SELECT ON closure_service_args,observation_saved TO service_role;
SELECT set_config('request.jwt.claim.role','',TRUE);
SET LOCAL ROLE service_role;
SELECT extensions.is(public.read_initial_cpm_photo_write_closure(attempt_id,'live_object'),NULL::JSONB,'service reads missing receipt as null') FROM closure_service_args;
SELECT extensions.is(public.read_initial_cpm_photo_observation(attempt_id,'live_object',NULL,NULL),(SELECT value FROM observation_saved),'opaque service role reads authoritative snapshot') FROM closure_service_args;
SELECT extensions.is(public.read_initial_cpm_photo_observation(attempt_id,'live_object',NULL,(SELECT value FROM observation_saved)),(SELECT value FROM observation_saved),'service exact current recheck') FROM closure_service_args;
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_observation(attempt_id,'live_object',NULL,(SELECT value||'{"extra":true}'::JSONB FROM observation_saved)) FROM closure_service_args$$,'22023','initial_analysis_identity_conflict','service recheck rejects changed snapshot');
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_observation(attempt_id,'live_object',NULL,'[]'::JSONB) FROM closure_service_args$$,'22023','initial_analysis_input_invalid','service expected snapshot must be object');
SELECT extensions.throws_ok($$SELECT public.settle_initial_cpm_photo_write_closure(attempt_id,policy,'live_object','2026-01-01T00:00:00.000Z',NULL) FROM closure_service_args$$,'22023','initial_analysis_input_invalid','settlement refuses ambiguous timestamp precision');
SELECT extensions.is(public.settle_initial_cpm_photo_write_closure(attempt_id,policy,'live_object',observed,NULL)->>'observed_at',observed,'service preserves six-digit microsecond settlement') FROM closure_service_args;
SELECT extensions.is(public.read_initial_cpm_photo_write_closure(attempt_id,'live_object')->>'observed_at',observed,'receipt read preserves original microseconds') FROM closure_service_args;
SELECT extensions.is(public.settle_initial_cpm_photo_write_closure(attempt_id,policy,'live_object',observed,NULL),public.read_initial_cpm_photo_write_closure(attempt_id,'live_object'),'service exact settlement replay') FROM closure_service_args;
SELECT extensions.throws_ok($$SELECT public.settle_initial_cpm_photo_write_closure(attempt_id,policy,'live_object',left(observed,23)||'000Z',NULL) FROM closure_service_args$$,'22023','initial_analysis_identity_conflict','flooring historical microseconds cannot replace receipt');
RESET ROLE;
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
UPDATE internal.initial_cpm_photo_write_policies SET state='revoked';
SELECT extensions.is(public.read_initial_cpm_photo_write_closure(attempt_id,'live_object')->>'observed_at',observed,'historical service read survives revocation') FROM closure_service_args;
ROLLBACK TO closure_service_projection;
CREATE TEMP TABLE closure_saved AS SELECT (pg_temp.close_source()).*;
SELECT extensions.is(public.read_initial_cpm_photo_write_status('00000000-0000-4000-8000-00000000f001',a.scan_id,a.assignment_digest,a.object_id)#>>'{attempt,write_closed}','true','status reports saved closure without verification or release') FROM closure_attempt a;
SELECT extensions.is((SELECT state FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='00000000-0000-4000-8000-00000000f101'),'pending','closed status retains capacity');

SELECT extensions.ok((SELECT write_closed FROM internal.initial_cpm_photo_write_attempts WHERE attempt_id=(SELECT attempt_id FROM closure_attempt)),'live closure closes exact role');
SELECT extensions.is(to_jsonb(pg_temp.close_source()),to_jsonb(s),'closure replay exact') FROM closure_saved s;
SELECT extensions.throws_ok($$SELECT pg_temp.close_source('live_object',clock_timestamp())$$,'22023','initial_analysis_identity_conflict','replay cannot replace observation time');
SELECT extensions.is((SELECT capability_expires_at FROM internal.initial_cpm_photo_write_attempts WHERE attempt_id=(SELECT attempt_id FROM closure_attempt)),(SELECT capability_expires_at FROM closure_attempt),'closure does not renew ticket');
SELECT extensions.is((SELECT state FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='00000000-0000-4000-8000-00000000f101'),'pending','live closure does not release capacity');
SELECT extensions.throws_ok($$UPDATE internal.initial_cpm_photo_write_closures SET observed_at=clock_timestamp()$$,'22023',NULL,'closure immutable');
SELECT extensions.throws_ok($$TRUNCATE internal.initial_cpm_photo_write_closures$$,'22023',NULL,'closure truncate denied');
SELECT extensions.lives_ok($$SELECT pg_temp.closure_write('bind','ai')$$,'closed role permits next binding');
SELECT extensions.lives_ok($$SELECT pg_temp.closure_write('may_have_issued','ai')$$,'next role may be outstanding only after closure');
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_write_attempts WHERE state='may_have_issued' AND NOT write_closed),1::BIGINT,'one outstanding role preserved');
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
CREATE TEMP TABLE closure_display AS SELECT m.object_id,s.assignment_digest FROM internal.initial_cpm_photo_role_mapping m JOIN internal.initial_analysis_preparation_intents s USING(scan_id) WHERE m.scan_id='00000000-0000-4000-8000-00000000f101' AND m.role='display';
SELECT public.cancel_initial_analysis('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101')->>'dispatch';
SELECT extensions.is(to_jsonb(pg_temp.close_source()),to_jsonb(s),'historical live receipt replays after erasure without reviving it') FROM closure_saved s;
SELECT extensions.ok(internal.initial_cpm_photo_retired_write_hold('00000000-0000-4000-8000-00000000f101'),'retirement keeps exact issued graph');
SELECT extensions.is(public.read_initial_cpm_photo_write_closure(attempt_id,'live_object')->>'observed_at',to_char(observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'service historical read survives private erasure') FROM closure_saved;

DO $$ BEGIN
 PERFORM public.claim_initial_preparation_source_erasure(); PERFORM public.claim_initial_preparation_source_erasure(); PERFORM public.claim_initial_preparation_source_erasure();
END; $$;
CREATE TEMP TABLE closure_claim AS SELECT clock_timestamp() observed_at,r.claim_token FROM internal.initial_preparation_source_registry r JOIN closure_attempt a USING(object_id);
SELECT extensions.throws_ok($$SELECT pg_temp.observation_snapshot()$$,'55000','initial_analysis_preparation_required','erased private state denies fresh live observation');
SELECT extensions.throws_ok($$SELECT pg_temp.observation_snapshot('retired_marker',gen_random_uuid())$$,'55000','initial_analysis_preparation_required','snapshot cannot adopt another cleanup claim');
CREATE TEMP TABLE marker_snapshot AS SELECT pg_temp.observation_snapshot('retired_marker',claim_token) value FROM closure_claim;
SELECT extensions.is(value->'target','{"outcome":"retired_marker"}'::JSONB,'marker needs no erased private declaration') FROM marker_snapshot;
SELECT extensions.is(value#>>'{erasure_claim,token}',(SELECT claim_token::TEXT FROM closure_claim),'original token retained') FROM marker_snapshot;
SELECT extensions.ok((value#>>'{erasure_claim,issued_at_ms}')::NUMERIC>=extract(epoch FROM r.claim_expires_at-INTERVAL '1 minute')*1000
 AND (value#>>'{erasure_claim,issued_at_ms}')::NUMERIC<extract(epoch FROM r.claim_expires_at-INTERVAL '1 minute')*1000+1
 AND (value#>>'{erasure_claim,expires_at_ms}')::NUMERIC<=extract(epoch FROM r.claim_expires_at)*1000
 AND (value#>>'{erasure_claim,expires_at_ms}')::NUMERIC>extract(epoch FROM r.claim_expires_at)*1000-1,
 'microsecond projection only shortens original claim interval') FROM marker_snapshot CROSS JOIN internal.initial_preparation_source_registry r JOIN closure_attempt a USING(object_id);
SELECT extensions.is(pg_temp.observation_snapshot('retired_marker',(SELECT claim_token FROM closure_claim),value),value,'marker current check preserves exact captured snapshot') FROM marker_snapshot;

SAVEPOINT marker_service_projection;
GRANT SELECT ON closure_attempt,closure_claim,marker_snapshot TO service_role;
SELECT set_config('request.jwt.claim.role','',TRUE);
SET LOCAL ROLE service_role;
SELECT extensions.is(public.read_initial_cpm_photo_observation(a.attempt_id,'retired_marker',c.claim_token,NULL),m.value,'opaque service reads original marker snapshot') FROM closure_attempt a CROSS JOIN closure_claim c CROSS JOIN marker_snapshot m;
SELECT extensions.is(public.read_initial_cpm_photo_observation(a.attempt_id,'retired_marker',c.claim_token,m.value),m.value,'service marker recheck preserves captured token and snapshot') FROM closure_attempt a CROSS JOIN closure_claim c CROSS JOIN marker_snapshot m;
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_photo_observation(attempt_id,'retired_marker',gen_random_uuid(),NULL) FROM closure_attempt$$,'55000','initial_analysis_preparation_required','service cannot substitute original marker claim');
SELECT extensions.is(public.settle_initial_cpm_photo_write_closure(a.attempt_id,(SELECT value#>>'{binding,verification_policy_digest}' FROM marker_snapshot),'retired_marker',to_char(c.observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),c.claim_token)->>'outcome','retired_marker','opaque service settles marker through existing owner') FROM closure_attempt a CROSS JOIN closure_claim c;
SELECT extensions.is(public.read_initial_cpm_photo_write_closure(a.attempt_id,'retired_marker')->>'observed_at',to_char(c.observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'service recovers exact marker receipt') FROM closure_attempt a CROSS JOIN closure_claim c;
RESET ROLE;
ROLLBACK TO marker_service_projection;

SELECT extensions.throws_ok($$SELECT pg_temp.close_source('retired_marker',NULL,gen_random_uuid())$$,'55000','initial_analysis_preparation_required','replacement token cannot settle original observation');
SELECT extensions.lives_ok($$SELECT pg_temp.close_source('retired_marker',(SELECT observed_at FROM closure_claim),(SELECT claim_token FROM closure_claim))$$,'original live erasure claim permits marker closure');
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_write_closures),2::BIGINT,'live and terminal observations remain distinct');
SELECT extensions.ok(NOT (SELECT marker_confirmed FROM internal.initial_preparation_source_registry r JOIN closure_attempt a USING(object_id)),'write closure never acknowledges cleanup itself');
SELECT public.finish_initial_preparation_source_erasure(a.object_id,c.claim_token,TRUE)->>'outcome' FROM closure_attempt a CROSS JOIN closure_claim c;
SELECT extensions.lives_ok($$SELECT pg_temp.close_source('retired_marker',(SELECT observed_at FROM closure_claim),(SELECT claim_token FROM closure_claim))$$,'exact marker replay survives cleanup acknowledgement');
SELECT extensions.is((SELECT state FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='00000000-0000-4000-8000-00000000f101'),'pending','marker closure never releases capacity');
SELECT extensions.throws_ok($$SELECT internal.initial_cpm_photo_write_action('bind','00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101',(SELECT assignment_digest FROM closure_display),(SELECT object_id FROM closure_display))$$,'55000',NULL,'retired scan cannot bind another role');
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations),0::BIGINT,'closure never funds analysis');
ROLLBACK TO closure_cases;

SAVEPOINT write_hold_cases;
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) privilege
 WHERE has_table_privilege(role_name,'internal.initial_cpm_photo_write_attempts',privilege)),
 'write attempts deny every API role');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 WHERE has_function_privilege(role_name,'internal.initial_cpm_photo_write_action(text,uuid,uuid,text,uuid)','EXECUTE')),
 'write action has no API grant');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT internal.initial_cpm_photo_write_action('bind',NULL,NULL,NULL,NULL)$$,
 '42501',NULL,'real service role cannot enter bookkeeping');
RESET ROLE;
CREATE FUNCTION pg_temp.cpm_write(action TEXT,role_name TEXT DEFAULT 'source')
 RETURNS internal.initial_cpm_photo_write_attempts LANGUAGE SQL AS $$
 SELECT internal.initial_cpm_photo_write_action(action,'00000000-0000-4000-8000-00000000f001',
 '00000000-0000-4000-8000-00000000f101',s.assignment_digest,m.object_id)
 FROM internal.initial_analysis_preparation_intents s JOIN internal.initial_cpm_photo_role_mapping m USING(scan_id)
 WHERE s.scan_id='00000000-0000-4000-8000-00000000f101' AND m.role=role_name;
$$;
SELECT extensions.ok((pg_temp.cpm_write('status')).attempt_id IS NULL,'status never creates attempt');
CREATE TEMP TABLE write_before AS SELECT (pg_temp.cpm_write('bind')).*;
SELECT extensions.is(to_jsonb(pg_temp.cpm_write('bind')),to_jsonb(w),'binding replay is exact without renewed clocks') FROM write_before w;
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_write_attempts),1::BIGINT,'replay keeps one attempt');
SELECT extensions.is((SELECT capability_expires_at-created_at FROM write_before),INTERVAL '10 minutes','attempt clock is bounded');
SELECT extensions.is((SELECT admission_expires_at FROM write_before),(SELECT expires_at FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000f101'),'original admission deadline retained');
SELECT extensions.throws_ok($$UPDATE internal.initial_cpm_photo_write_attempts SET capability_expires_at=capability_expires_at+INTERVAL '1 minute'$$,'22023',NULL,'attempt expiry cannot renew');
SELECT extensions.throws_ok($$UPDATE internal.initial_cpm_photo_write_attempts SET object_id=gen_random_uuid()$$,'55000',NULL,'attempt cannot move destination');
SELECT extensions.throws_ok($$SELECT internal.initial_cpm_photo_write_action('bind','00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101',repeat('0',64),(SELECT object_id FROM write_before))$$,'22023','initial_analysis_identity_conflict','changed assignment rejected');
SELECT extensions.lives_ok($$SELECT pg_temp.cpm_write('bind','ai')$$,'second role can be bound before issuance');
SELECT extensions.throws_ok($$SELECT pg_temp.cpm_write('close')$$,'22023','initial_analysis_input_invalid','no fabricated closure action');
SELECT extensions.throws_ok($$SELECT pg_temp.cpm_write('refresh')$$,'22023','initial_analysis_input_invalid','no refresh action');
SAVEPOINT write_revoked;
UPDATE internal.initial_preparation_backend_eligibility SET state='revoked';
SELECT extensions.is(to_jsonb(pg_temp.cpm_write('status')),to_jsonb(w),'revoked backend preserves exact status') FROM write_before w;
SELECT extensions.throws_ok($$SELECT pg_temp.cpm_write('may_have_issued')$$,'55000','initial_analysis_preparation_unavailable','revocation prevents new issuance bookkeeping');
ROLLBACK TO write_revoked;
CREATE TEMP TABLE write_issued AS SELECT (pg_temp.cpm_write('may_have_issued')).*;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.is((SELECT state FROM write_issued),'may_have_issued','uncertain signer outcome recorded before IO');
SELECT extensions.ok(internal.initial_cpm_photo_cohort_complete('00000000-0000-4000-8000-00000000f101'),'outstanding write keeps structurally complete cohort');
SELECT extensions.is((SELECT write_capability_state FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='00000000-0000-4000-8000-00000000f101'),'may_have_issued','capacity records conservative liability');
SELECT extensions.is(to_jsonb(pg_temp.cpm_write('may_have_issued')),to_jsonb(w),'lost signer acknowledgement returns exact original state') FROM write_issued w;
SELECT extensions.throws_ok($$SELECT pg_temp.cpm_write('may_have_issued','ai')$$,'55000','initial_analysis_cpm_write_outstanding','a second outstanding role is forbidden');
SELECT extensions.throws_ok($$SELECT pg_temp.cpm_write('bind','display')$$,'55000','initial_analysis_cpm_write_outstanding','cannot bind a new role while write is outstanding');
SELECT extensions.throws_ok($$UPDATE internal.initial_cpm_photo_write_attempts SET state='bound',issued_at=NULL WHERE state='may_have_issued'$$,'22023','initial_analysis_storage_immutable','unknown issuance cannot reset');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_cpm_photo_write_attempts$$,'22023','initial_analysis_storage_immutable','attempt identity survives deletion');
SELECT extensions.throws_ok($$TRUNCATE internal.initial_cpm_photo_write_attempts CASCADE$$,'22023','initial_analysis_storage_immutable','attempt identity survives truncate');
SELECT extensions.is(public.get_initial_preparation_status('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101'),response,'preparation recovery remains exact while outstanding') FROM cpm_saved;
SELECT extensions.is(public.cancel_initial_analysis('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101')->>'dispatch','dispatch_prevented','provider dispatch prevention does not claim storage closure');
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.ok(internal.initial_cpm_photo_retired_write_hold('00000000-0000-4000-8000-00000000f101'),'private erasure leaves exact retired outstanding graph');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE NOT retired),'retirement reaches bound and issued attempts');
SELECT extensions.throws_ok($$UPDATE internal.initial_cpm_photo_capacity_reservations SET state='released' WHERE scan_id='00000000-0000-4000-8000-00000000f101'$$,'22023','initial_analysis_storage_immutable','retirement cannot release outstanding capacity');
SELECT extensions.throws_ok($$UPDATE internal.initial_cpm_photo_write_attempts SET retired=FALSE$$,'55000',NULL,'retired attempt cannot resurrect');
CREATE TEMP TABLE write_marker AS SELECT public.claim_initial_preparation_source_erasure() value;
SELECT extensions.is(public.finish_initial_preparation_source_erasure((value#>>'{object,object_id}')::UUID,(value#>>'{object,claim_token}')::UUID,TRUE)->>'outcome','acknowledged','existing marker acknowledgement remains independent') FROM write_marker;
SELECT extensions.is((SELECT state FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='00000000-0000-4000-8000-00000000f101'),'pending','marker acknowledgement does not close uncertain writes');
SELECT extensions.throws_ok($$SELECT pg_temp.cpm_create('00000000-0000-4000-8000-00000000f103')$$,'55000','initial_analysis_capacity_unavailable','outstanding cancellation does not free the owner slot');
DELETE FROM public.users WHERE id='00000000-0000-4000-8000-00000000f001';
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.ok(internal.initial_cpm_photo_retired_write_hold('00000000-0000-4000-8000-00000000f101'),'account deletion preserves outstanding global liability');
SELECT extensions.ok((SELECT owner_id IS NULL AND state='pending' FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='00000000-0000-4000-8000-00000000f101'),'account deletion detaches owner without releasing capacity');
SELECT extensions.lives_ok($$SELECT internal.assert_ghost_profile_merge_reference_policy_coverage()$$,'permanent attempt adds no unclassified account reference');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents) AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_role_mapping),'account erasure removes private declarations');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations),0::BIGINT,'write bookkeeping never funds');
ROLLBACK TO write_hold_cases;
-- Original never-issued cancellation and account-erasure cases continue below.

SAVEPOINT eligibility_change;
UPDATE internal.initial_cpm_photo_profile_eligibility SET state='revoked';
DELETE FROM internal.initial_cpm_photo_current_selection;
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;
SELECT extensions.is(pg_temp.cpm_create('00000000-0000-4000-8000-00000000f101'),response,'saved recovery ignores current revocation/selector/gate drift') FROM cpm_saved;
ROLLBACK TO eligibility_change;
SELECT extensions.is(public.cancel_initial_analysis('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-00000000f101')->>'dispatch','dispatch_prevented','never-issued CPM cancellation is proved');
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.is((SELECT state FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='00000000-0000-4000-8000-00000000f101'),'released','proved closure releases reservation');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id='00000000-0000-4000-8000-00000000f101' AND retired),3::BIGINT,'all roles permanently retired');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000f101'),'private intent removed');
SELECT extensions.lives_ok($$SELECT pg_temp.cpm_create('00000000-0000-4000-8000-00000000f103')$$,'released slot reusable for different operation');
SELECT extensions.throws_ok($$SELECT pg_temp.cpm_create('00000000-0000-4000-8000-00000000f101')$$,'55000',NULL,'cancelled identity never creates fresh allocation');
DELETE FROM public.users WHERE id='00000000-0000-4000-8000-00000000f001';
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations WHERE state<>'released' OR owner_id IS NOT NULL),'account erasure detaches owner after never-issued release');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_source_registry WHERE retired),9::BIGINT,'account erasure retires every role');
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_role_mapping),0::BIGINT,'private role mapping erased');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations),0::BIGINT,'allocation/cancellation never funds');
SELECT extensions.is((SELECT count(*) FROM internal.identification_invocations),0::BIGINT,'allocation never executes');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_execution_grants),0::BIGINT,'no legacy execution grants');

SAVEPOINT two_photo_fixture;
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000f002');
UPDATE cpm_fixture SET value=jsonb_set(value,'{content_canonical}',to_jsonb(internal.initial_canonical(
 jsonb_set((value->>'content_canonical')::JSONB,'{photos}',
  ((value->>'content_canonical')::JSONB->'photos')||jsonb_build_array(
   jsonb_set(jsonb_set(jsonb_set(jsonb_set((value->>'content_canonical')::JSONB#>'{photos,0}',
    '{ordinal}','1'),'{source,reference_id}','"00000000-0000-4000-8000-000000000013"'),
    '{ai,reference_id}','"00000000-0000-4000-8000-000000000014"'),
    '{display,reference_id}','"00000000-0000-4000-8000-000000000015"'))))));
SELECT extensions.lives_ok($$SELECT pg_temp.cpm_create('00000000-0000-4000-8000-00000000f201','00000000-0000-4000-8000-00000000f002')$$,'two-photo allocation');
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_role_mapping WHERE scan_id='00000000-0000-4000-8000-00000000f201'),6::BIGINT,'both photos register all three roles');
SELECT extensions.is(internal.capture_initial_cancellation_private_images('00000000-0000-4000-8000-00000000f201')->'internal.initial_cpm_photo_role_mapping',
 (SELECT jsonb_agg(to_jsonb(m) ORDER BY photo_ordinal,role COLLATE "C") FROM internal.initial_cpm_photo_role_mapping m
 WHERE scan_id='00000000-0000-4000-8000-00000000f201'),'C1 captures all six roles in deterministic photo/role order');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES('00000000-0000-4000-8000-00000000f201',NULL,clock_timestamp());
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id='00000000-0000-4000-8000-00000000f201' AND retired),6::BIGINT,'pre-row tombstone retires both photos');
SELECT extensions.is((SELECT state FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='00000000-0000-4000-8000-00000000f201'),'released','tombstone releases never-issued capacity');
ROLLBACK TO two_photo_fixture;

SAVEPOINT expiry_fixture;
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000f002');
SELECT pg_temp.cpm_create('00000000-0000-4000-8000-00000000f202','00000000-0000-4000-8000-00000000f002')->>'outcome';
SET CONSTRAINTS ALL IMMEDIATE;
-- Trusted local clock fixture, never an allowed production mutation: move the
-- full immutable assignment clock and matching row/digest together.
ALTER TABLE internal.initial_analysis_preparation_intents DISABLE TRIGGER guard_initial_preparation_storage;
UPDATE internal.initial_analysis_preparation_intents
 SET created_at='2000-01-01T00:00:00Z',expires_at='2000-01-01T00:30:00Z',
 canonical_assignment=internal.initial_canonical(canonical_assignment::JSONB||jsonb_build_object('created_at_ms',946684800000::BIGINT,'expires_at_ms',946686600000::BIGINT)),
 assignment_digest=internal.initial_cpm_photo_digest('assignment',internal.initial_canonical(canonical_assignment::JSONB||jsonb_build_object('created_at_ms',946684800000::BIGINT,'expires_at_ms',946686600000::BIGINT)))
 WHERE scan_id='00000000-0000-4000-8000-00000000f202';
ALTER TABLE internal.initial_analysis_preparation_intents ENABLE TRIGGER guard_initial_preparation_storage;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.is(public.get_initial_preparation_status('00000000-0000-4000-8000-00000000f002','00000000-0000-4000-8000-00000000f202'),
 '{"version":1,"variant":"client_prepared_photo","outcome":"terminal_held","authority":"none","scan_id":"00000000-0000-4000-8000-00000000f202","reason":"expired"}'::JSONB,'expiry holds identity and retires allocation');
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.is((SELECT state FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='00000000-0000-4000-8000-00000000f202'),'released','expired never-issued allocation releases capacity');
SELECT extensions.throws_ok($$SELECT pg_temp.cpm_create('00000000-0000-4000-8000-00000000f202','00000000-0000-4000-8000-00000000f002')$$,'55000','initial_analysis_cancelled','expiry cannot renew the old operation');
ROLLBACK TO expiry_fixture;
SAVEPOINT account_tombstone_fixture;
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000f002');
SELECT pg_temp.cpm_create('00000000-0000-4000-8000-00000000f203','00000000-0000-4000-8000-00000000f002')->>'outcome';
SELECT public.apply_user_tombstone('00000000-0000-4000-8000-00000000f002');
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id='00000000-0000-4000-8000-00000000f203' AND retired),3::BIGINT,'supported account tombstone retires all roles');
SELECT extensions.is((SELECT state FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='00000000-0000-4000-8000-00000000f203'),'released','supported account tombstone releases never-issued reservation');
ROLLBACK TO account_tombstone_fixture;

-- Sequential global limit/rollback proof. Concurrent last-slot contention is a
-- separate multi-session qualification; this test does not claim it.
CREATE TEMP TABLE cpm_global AS SELECT n,
 ('00000000-0000-4000-8000-'||lpad((90000+n)::TEXT,12,'0'))::UUID owner_id,
 ('00000000-0000-4000-8000-'||lpad((91000+n)::TEXT,12,'0'))::UUID scan
 FROM generate_series(1,17) n;
SELECT pg_temp.admission_owner(owner_id) FROM cpm_global ORDER BY n;
SELECT pg_temp.cpm_create(scan,owner_id)->>'outcome' FROM cpm_global WHERE n<=16 ORDER BY n;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_capacity_reservations WHERE state='pending'),16::BIGINT,'global pool admits sixteen');
SELECT extensions.throws_ok(format('SELECT pg_temp.cpm_create(%L,%L)',scan,owner_id),'55000','initial_analysis_capacity_unavailable','seventeenth global allocation denied') FROM cpm_global WHERE n=17;
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences f JOIN cpm_global g ON g.scan=f.scan_id WHERE g.n=17),'global capacity rejection rolls back all claims');
SELECT * FROM extensions.finish();
ROLLBACK;
