\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN INITIAL STORAGE HELPERS
CREATE FUNCTION pg_temp.initial_owner(owner_id UUID) RETURNS VOID LANGUAGE SQL AS $$
 INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT || '@example.invalid','{}','{}',now(),now());
$$;
CREATE FUNCTION pg_temp.initial_submission(owner_id UUID,scan_id UUID) RETURNS VOID LANGUAGE SQL AS $$
 INSERT INTO internal.initial_analysis_submissions VALUES(scan_id,owner_id,'identify-describe',1,
 '{"synthetic":true}',jsonb_build_array(E'  Synthetic\n\ttext  ','é','é'),'{"synthetic":true}','{"synthetic":true}');
$$;
CREATE FUNCTION pg_temp.initial_result(owner_id UUID,scan_id UUID) RETURNS VOID LANGUAGE SQL AS $$
 INSERT INTO internal.initial_analysis_results VALUES(scan_id,owner_id,scan_id,1,'{"synthetic":true}','{"synthetic":true}');
$$;
CREATE FUNCTION pg_temp.initial_receipt(owner_id UUID,scan_id UUID) RETURNS VOID LANGUAGE SQL AS $$
 INSERT INTO internal.initial_analysis_completions VALUES(scan_id,owner_id,scan_id,1,'{"synthetic":true}');
$$;
CREATE FUNCTION pg_temp.initial_scan(owner_id UUID,scan_id UUID,enrolled BOOLEAN DEFAULT FALSE) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
 VALUES(scan_id::TEXT,owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
 INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture)
 VALUES(scan_id,owner_id,'{}',0.8,FALSE,'flash','private',TRUE);
 IF enrolled THEN
  UPDATE internal.observation_history_rollout SET enrollment_enabled=TRUE;
  INSERT INTO internal.observation_histories(observation_id,initial_selection_permitted) VALUES(scan_id,TRUE);
  UPDATE internal.observation_history_rollout SET enrollment_enabled=FALSE;
 END IF;
END;
$$;
-- END INITIAL STORAGE HELPERS
SELECT extensions.is((SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout),FALSE,'gate ships disabled');
SELECT extensions.ok(relrowsecurity,'private storage RLS') FROM pg_class WHERE oid IN (
 'internal.initial_analysis_rollout'::regclass,'internal.initial_analysis_submissions'::regclass,
 'internal.initial_analysis_results'::regclass,'internal.initial_analysis_completions'::regclass);
SELECT extensions.ok(NOT has_table_privilege(role_name,table_name,privilege),'API table denial '||role_name||' '||table_name||' '||privilege)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 CROSS JOIN unnest(ARRAY['internal.initial_analysis_rollout','internal.initial_analysis_submissions','internal.initial_analysis_results','internal.initial_analysis_completions']) table_name
 CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) privilege;
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'API trigger execution denied')
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 CROSS JOIN unnest(ARRAY['internal.guard_initial_analysis_storage()','internal.erase_initial_analysis_for_scan_fence()',
 'internal.fence_initial_analysis_on_scan_change()','internal.fence_initial_analysis_before_owner_delete()',
 'internal.guard_initial_analysis_scan_erasure_scope()','internal.guard_initial_analysis_tombstone_scope()']) signature;
SELECT extensions.is((SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('admit_initial_analysis','authorize_initial_analysis_dispatch','record_initial_analysis_result','complete_initial_analysis','get_initial_analysis_status','cancel_initial_analysis')),0::BIGINT,'no public lifecycle writer installed');
SELECT pg_temp.initial_owner('00000000-0000-4000-8000-00000000a001');
SELECT pg_temp.initial_owner('00000000-0000-4000-8000-00000000a002');
SELECT extensions.throws_ok($$SELECT pg_temp.initial_submission('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a101')$$,'55000','initial_analysis_unavailable','closed gate denies even schema-owner preparation');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;
SELECT pg_temp.initial_submission('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a101');
SELECT pg_temp.initial_result('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a101');
SELECT pg_temp.initial_receipt('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a101');
SELECT extensions.is((SELECT count(*) FROM public.scans WHERE id='00000000-0000-4000-8000-00000000a101'),0::BIGINT,'evidence can precede scan without inventing a scan');
SELECT extensions.is((SELECT ordered_descriptions FROM internal.initial_analysis_submissions WHERE scan_id='00000000-0000-4000-8000-00000000a101'),jsonb_build_array(E'  Synthetic\n\ttext  ','é','é'),'exact order Unicode and whitespace preserved');
SELECT extensions.throws_ok($$UPDATE internal.initial_analysis_submissions SET route='identify'$$,'22023','initial_analysis_storage_immutable','route cannot change');
SELECT extensions.throws_ok($$UPDATE internal.initial_analysis_results SET result_snapshot='{}'$$,'22023','initial_analysis_storage_immutable','result cannot change');
SELECT extensions.throws_ok($$UPDATE internal.initial_analysis_completions SET receipt_snapshot='{}'$$,'22023','initial_analysis_storage_immutable','receipt cannot change');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_analysis_submissions$$,'22023','initial_analysis_storage_immutable','live evidence cannot disappear without fence');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_analysis_results$$,'22023','initial_analysis_storage_immutable','live result cannot disappear');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_analysis_completions$$,'22023','initial_analysis_storage_immutable','live receipt cannot disappear');
SELECT extensions.throws_ok($$SELECT internal.assert_ghost_profile_merge_reference_preconditions('00000000-0000-4000-8000-00000000a001')$$,'55000','ghost_merge_preserved_reference_present: internal.initial_analysis_submissions.owner_id','merge holds immutable ownership');
SELECT extensions.lives_ok($$SELECT internal.assert_ghost_profile_merge_reference_preconditions('00000000-0000-4000-8000-00000000a002')$$,'unrelated empty-owner merge preflight remains available');
SELECT extensions.throws_ok($$SELECT pg_temp.initial_result('00000000-0000-4000-8000-00000000a002','00000000-0000-4000-8000-00000000a102')$$,'23503',NULL,'missing/foreign input cannot own result');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)
 VALUES('00000000-0000-4000-8000-00000000a101',NULL,now());
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_submissions),0::BIGINT,'pre-row fence erases input and text');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_results),0::BIGINT,'pre-row fence erases result/provenance');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_completions),0::BIGINT,'pre-row fence erases private receipt');
SELECT extensions.throws_ok($$SELECT pg_temp.initial_submission('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a101')$$,'55000','initial_analysis_deleted','late same-owner admission denied');
SELECT extensions.throws_ok($$SELECT pg_temp.initial_submission('00000000-0000-4000-8000-00000000a002','00000000-0000-4000-8000-00000000a101')$$,'55000','initial_analysis_deleted','late different-owner reuse denied');
SELECT pg_temp.initial_submission('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a102');
SELECT pg_temp.initial_result('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a102');
SELECT pg_temp.initial_receipt('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a102');
SELECT pg_temp.initial_scan('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a102');
SELECT extensions.throws_ok($$UPDATE public.scans SET user_id='00000000-0000-4000-8000-00000000a002' WHERE id='00000000-0000-4000-8000-00000000a102'$$,'22023','initial_analysis_owner_immutable','scan cannot transfer private immutable evidence');
UPDATE public.scans SET user_id=NULL,is_tombstoned=TRUE WHERE id='00000000-0000-4000-8000-00000000a102';
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_completions),0::BIGINT,'unenrolled detach erases entire private chain');
SELECT pg_temp.initial_owner('00000000-0000-4000-8000-00000000a003');
SELECT pg_temp.initial_submission('00000000-0000-4000-8000-00000000a003','00000000-0000-4000-8000-00000000a103');
SELECT pg_temp.initial_result('00000000-0000-4000-8000-00000000a003','00000000-0000-4000-8000-00000000a103');
SELECT pg_temp.initial_receipt('00000000-0000-4000-8000-00000000a003','00000000-0000-4000-8000-00000000a103');
SELECT pg_temp.initial_scan('00000000-0000-4000-8000-00000000a003','00000000-0000-4000-8000-00000000a103',TRUE);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SELECT public.apply_user_tombstone('00000000-0000-4000-8000-00000000a003');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_submissions),0::BIGINT,'enrolled detach erases text/input');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_results),0::BIGINT,'enrolled detach erases result');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_completions),0::BIGINT,'enrolled detach erases receipt');
SELECT pg_temp.initial_submission('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a104');
SELECT pg_temp.initial_result('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a104');
SELECT pg_temp.initial_receipt('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a104');
INSERT INTO internal.account_deletion_jobs(user_id) VALUES('00000000-0000-4000-8000-00000000a001');
SELECT extensions.throws_ok($$SELECT pg_temp.initial_submission('00000000-0000-4000-8000-00000000a001','00000000-0000-4000-8000-00000000a105')$$,'55000','initial_analysis_deleted','pending deletion blocks before user row disappears');
DELETE FROM public.users WHERE id='00000000-0000-4000-8000-00000000a001';
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_submissions),0::BIGINT,'account deletion erases pre-row input');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_results),0::BIGINT,'account deletion erases pre-row result');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_completions),0::BIGINT,'account deletion erases pre-row receipt');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id='00000000-0000-4000-8000-00000000a104' AND user_id IS NULL AND completed_at IS NOT NULL),'ownerless completed pre-row fence survives account erasure');
SELECT pg_temp.initial_scan('00000000-0000-4000-8000-00000000a002','00000000-0000-4000-8000-00000000a106');
SELECT extensions.throws_ok($$SELECT pg_temp.initial_submission('00000000-0000-4000-8000-00000000a002','00000000-0000-4000-8000-00000000a106')$$,'22023','initial_analysis_identity_conflict','existing legacy-only scan cannot acquire hidden initial evidence');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT * FROM internal.initial_analysis_submissions$$,'42501',NULL,'actual service read denied');
SELECT extensions.throws_ok($$UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE$$,'42501',NULL,'service cannot enable gate');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
