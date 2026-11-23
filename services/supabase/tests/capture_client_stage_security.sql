\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SELECT extensions.ok((SELECT relrowsecurity FROM pg_class WHERE oid='internal.initial_capture_client_stage_objects'::regclass),'private client inventory is RLS protected');
SELECT extensions.ok(NOT has_table_privilege(role_name,'internal.initial_capture_client_stage_objects',privilege),'client inventory denies '||role_name||' '||privilege)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE']) privilege;
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'private helper denies '||role_name||signature)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY[
 'internal.assert_initial_capture_client_stage(uuid,boolean)',
 'internal.private_capture_media_counts(jsonb)',
 'internal.private_capture_finalization_ready(uuid,uuid)',
 'internal.prepare_private_capture_stage_admission(uuid,uuid,text,jsonb,jsonb,jsonb,text[],boolean,boolean,jsonb,integer)',
 'internal.initial_capture_client_stage_receipt(uuid,uuid)',
 'internal.assert_initial_capture_audio_retention(uuid,jsonb)',
 'internal.adopt_initial_capture_audio_retention(internal.ordinary_initial_evidence)']) signature;
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'client RPC denial '||role_name||signature)
 FROM unnest(ARRAY['anon','authenticated']) role_name CROSS JOIN unnest(ARRAY[
 'public.initial_capture_client_stage_action(text,text,text,text,uuid)',
 'public.recover_private_capture_completion(uuid,jsonb)',
 'public.claim_initial_capture_stage_preparation(text,text,text,uuid)']) signature;
SELECT extensions.ok(has_function_privilege('service_role',signature,'EXECUTE'),'service grant '||signature)
 FROM unnest(ARRAY['public.initial_capture_client_stage_action(text,text,text,text,uuid)','public.claim_initial_capture_stage_preparation(text,text,text,uuid)','public.recover_private_capture_completion(uuid,jsonb)']) signature;
SET LOCAL ROLE anon;
SELECT extensions.throws_ok($$SELECT public.initial_capture_client_stage_action(NULL,NULL,NULL,NULL,NULL)$$,'42501','permission denied for function initial_capture_client_stage_action','anonymous cannot enter private upload capability');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.claim_initial_capture_stage_preparation(NULL,NULL,NULL,NULL)$$,'42501','permission denied for function claim_initial_capture_stage_preparation','client cannot claim DSP');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.initial_capture_client_stage_action(NULL,NULL,NULL,'write',gen_random_uuid())$$,'22023','invalid_analysis_history','service still needs complete canonical identity');
SELECT extensions.throws_ok($$SELECT public.claim_initial_capture_stage_preparation(NULL,NULL,NULL,NULL)$$,'22023','invalid_analysis_history','service cannot claim absent graph');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
