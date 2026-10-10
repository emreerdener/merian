\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SELECT extensions.ok(NOT (SELECT chat_context_enabled FROM internal.observation_history_rollout WHERE singleton),'context rollout defaults closed');
SELECT extensions.ok(has_function_privilege('service_role','public.reserve_insight_chat_send_with_context(uuid,uuid,uuid,text,uuid,jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('authenticated','public.reserve_insight_chat_send_with_context(uuid,uuid,uuid,text,uuid,jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('anon','public.reserve_insight_chat_send_with_context(uuid,uuid,uuid,text,uuid,jsonb,integer)','EXECUTE'),'service-only admission');
SELECT extensions.ok(NOT has_table_privilege('service_role','internal.insight_chat_turn_contexts','SELECT,INSERT,UPDATE,DELETE')
 AND NOT has_table_privilege('authenticated','internal.insight_chat_turn_contexts','SELECT,INSERT,UPDATE,DELETE')
 AND NOT has_table_privilege('anon','internal.insight_chat_turn_contexts','SELECT,INSERT,UPDATE,DELETE'),'no direct API table access');
SELECT extensions.is(internal.insight_chat_context_projection('{"candidates":[{"scientific_name":"Example plant","confidence_score":0.8,"media":"excluded"}],"pet_identification":{"species_group":"dog","label":"Mix","label_type":"breed_mix","confidence_score":0.5,"evidence":["Visible coat"],"media":"excluded"}}')#>'{candidates,0}', '{"scientific_name":"Example plant","confidence_score":0.8}'::JSONB,'candidate score uses executable contract key and strips unrelated payload');
SELECT extensions.is(internal.insight_chat_context_projection('{"pet_identification":{"species_group":"dog","label":"Mix","label_type":"breed_mix","confidence_score":0.5,"evidence":["Visible coat"],"media":"excluded"}}')->'pet_identification','{"species_group":"dog","label":"Mix","label_type":"breed_mix","confidence_score":0.5,"evidence":["Visible coat"]}'::JSONB,'pet evidence uses bounded executable contract keys');
SELECT extensions.is((SELECT count(*)::INTEGER FROM pg_constraint WHERE conrelid='internal.insight_chat_turn_contexts'::regclass AND contype='f'),1,'only message FK; ownership follows account merge');

-- BEGIN CHAT CONTEXT HELPERS
CREATE FUNCTION pg_temp.seed_chat_observation(owner_id UUID,observation UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT||'@example.invalid','{}','{}',now(),now()) ON CONFLICT DO NOTHING;
 INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
 VALUES(observation::TEXT,owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
 INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,ai_reasoning,user_observation_context)
 VALUES(observation,owner_id,ARRAY['https://example.invalid/private.jpg'],0.9,TRUE,'flash','private','Original reasoning','{"free_text":"Recorded encounter","media":"do not retain"}');
END;
$$;
CREATE FUNCTION pg_temp.open_chat_fixture() RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 UPDATE internal.observation_history_rollout SET chat_context_enabled=TRUE,reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE;
 UPDATE internal.field_chat_admission_cutover SET seeded_at=now()-interval '2 days',not_before_utc=now()-interval '1 day',beta_early_activation_at=NULL,beta_original_not_before_utc=NULL,
 activated_at=NULL,activated_candidate_sha=NULL,activated_migration_sha256=NULL,
 activated_explore_bundle_sha256=NULL,activated_insight_bundle_sha256=NULL,activated_species_dictionary_bundle_sha256=NULL;
 PERFORM public.activate_field_chat_admission_cutover(repeat('a',40),repeat('b',64),repeat('c',64),repeat('d',64),repeat('e',64));
END;
$$;
-- END CHAT CONTEXT HELPERS
SELECT pg_temp.seed_chat_observation('00000000-0000-4000-8000-00000000cb01',('00000000-0000-4000-8000-00000000cb1'||n)::UUID) FROM generate_series(1,6) n;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SELECT extensions.throws_ok($$SELECT public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb11','Question',gen_random_uuid(),'null',1)$$,'55000','field_chat_context_unavailable','closed gate admits nothing');
SELECT pg_temp.open_chat_fixture();
INSERT INTO public.species_dictionary(id,scientific_name,common_names,wikipedia_overview)
 VALUES('00000000-0000-4000-8000-00000000cb51','Context fixture','{"en":"Original label","private":"Excluded nested field"}','Original overview');
UPDATE public.scans SET species_id='00000000-0000-4000-8000-00000000cb51' WHERE id='00000000-0000-4000-8000-00000000cb11';
CREATE TEMP TABLE saved_chat AS SELECT * FROM public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb11',' Question ','00000000-0000-4000-8000-00000000cb21','null',1);
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.insight_chat_turn_contexts),1,'message and context commit together');
SELECT extensions.is((SELECT context_snapshot->>'source_kind' FROM saved_chat),'legacy_scan_v1','explicit legacy source');
SELECT extensions.is((SELECT context_snapshot#>>'{scan_context,ai_reasoning}' FROM saved_chat),'Original reasoning','allowlisted evidence captured');
SELECT extensions.ok((SELECT NOT (context_snapshot->'scan_context') ?| ARRAY['id','user_id','image_storage_urls','captured_media','gps_lat_exact','field_notes']
 AND context_snapshot#>'{scan_context,user_observation_context}'='{"free_text":"Recorded encounter"}'::JSONB FROM saved_chat),'private fields stripped recursively');
SELECT extensions.ok((SELECT context_snapshot#>>'{scan_context,species_dictionary,scientific_name}'='Context fixture'
 AND context_snapshot#>'{scan_context,species_dictionary,common_names}'='{"en":"Original label"}'::JSONB
 AND context_snapshot#>>'{scan_context,species_dictionary,wikipedia_overview}'='Original overview' FROM saved_chat),'dictionary projection retains bounded reference facts and only English name');
UPDATE public.species_dictionary SET common_names='{"en":"New label"}',wikipedia_overview='New overview' WHERE id='00000000-0000-4000-8000-00000000cb51';
UPDATE public.scans SET ai_reasoning='Changed reasoning',user_observation_context='{"free_text":"Changed"}' WHERE id='00000000-0000-4000-8000-00000000cb11';
UPDATE internal.observation_history_rollout SET chat_context_enabled=FALSE;
SELECT extensions.ok((SELECT r.is_replay AND r.sends_today=1 AND r.context_snapshot=s.context_snapshot
 FROM saved_chat s CROSS JOIN LATERAL public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb11','Question','00000000-0000-4000-8000-00000000cb21','null',1) r),'exact replay retains context through changes and closed gate without another debit');
SELECT extensions.throws_ok($$SELECT public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb11','Different','00000000-0000-4000-8000-00000000cb21','null',1)$$,'23505','field_chat_idempotency_conflict','text cannot rebind');
SELECT extensions.throws_ok($$SELECT public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb11','Question','00000000-0000-4000-8000-00000000cb21','{}',1)$$,'23505','field_chat_idempotency_conflict','ticket cannot rebind');
SELECT extensions.throws_ok($$UPDATE internal.insight_chat_turn_contexts SET context_snapshot='{}'$$,'22023','analysis_history_evidence_immutable','stored context immutable');
UPDATE internal.observation_history_rollout SET chat_context_enabled=TRUE;
SELECT public.reserve_field_chat_send('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'insight','00000000-0000-4000-8000-00000000cb12','Legacy question','00000000-0000-4000-8000-00000000cb22');
SELECT extensions.throws_ok($$SELECT public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb12','Legacy question','00000000-0000-4000-8000-00000000cb22','null',1)$$,'55000','field_chat_context_missing','old admitted message never reconstructs current context');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000cb01"}',TRUE);
SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000cb13',9);
CREATE TEMP TABLE chat_ticket AS SELECT jsonb_build_object('analysis_id',h.selected_analysis_id,'state_revision',h.state_revision,'review_revision',a.review_revision) ticket
 FROM internal.observation_histories h JOIN internal.observation_analysis_authorities a ON a.observation_id=h.observation_id AND a.analysis_id=h.selected_analysis_id
 WHERE h.observation_id='00000000-0000-4000-8000-00000000cb13';
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SELECT extensions.throws_ok($$SELECT public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb13','Question',gen_random_uuid(),'null',1)$$,'40001','field_chat_context_conflict','enrolled send requires displayed ticket');
CREATE TEMP TABLE history_chat AS SELECT * FROM public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb13','History question','00000000-0000-4000-8000-00000000cb23',(SELECT ticket FROM chat_ticket),1);
SELECT extensions.is((SELECT context_snapshot->>'source_kind' FROM history_chat),'analysis_history_v1','selected immutable child captured');
UPDATE public.scans SET ai_reasoning='Mutable parent must not win' WHERE id='00000000-0000-4000-8000-00000000cb13';
UPDATE internal.observation_histories SET state_revision=state_revision+1 WHERE observation_id='00000000-0000-4000-8000-00000000cb13';
SELECT extensions.ok((SELECT r.context_snapshot=s.context_snapshot FROM history_chat s CROSS JOIN LATERAL public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb13','History question','00000000-0000-4000-8000-00000000cb23',(SELECT ticket FROM chat_ticket),1) r),'history replay ignores newer authority revision');
SELECT extensions.throws_ok($$SELECT public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb13','New question',gen_random_uuid(),(SELECT ticket FROM chat_ticket),1)$$,'40001','field_chat_context_conflict','new send never silently rebases');
INSERT INTO internal.observation_histories(observation_id) VALUES('00000000-0000-4000-8000-00000000cb14');
SELECT extensions.throws_ok($$SELECT public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb14','Question',gen_random_uuid(),'null',1)$$,'55000','field_chat_context_unavailable','damaged history never falls back');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.insight_chat_conversations WHERE scan_id='00000000-0000-4000-8000-00000000cb14'),0,'denied admission leaves no empty thread');
SELECT extensions.is((SELECT admitted_count FROM internal.field_chat_daily_admissions WHERE user_id='00000000-0000-4000-8000-00000000cb01' AND admission_day=(now() AT TIME ZONE 'UTC')::DATE),3,'denials do not consume daily cap');
-- A prior unanswered assistant-less user row would correctly block admission;
-- use bounded synthetic assistant prefix to isolate ordering/privacy behavior.
INSERT INTO public.insight_chat_conversations(id,scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000cb35','00000000-0000-4000-8000-00000000cb15','00000000-0000-4000-8000-00000000cb01');
INSERT INTO public.insight_chat_messages(conversation_id,scan_id,user_id,role,message_text,created_at)
 SELECT '00000000-0000-4000-8000-00000000cb35','00000000-0000-4000-8000-00000000cb15','00000000-0000-4000-8000-00000000cb01','assistant',n::TEXT||repeat('x',1000),now()-interval '1 hour'+n*interval '1 second' FROM generate_series(1,14) n;
CREATE TEMP TABLE prefix_chat AS SELECT * FROM public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb15','Prefix question',gen_random_uuid(),'null',1);
SELECT extensions.is((SELECT jsonb_array_length(context_snapshot->'conversation_prefix') FROM prefix_chat),12,'prefix capped at twelve');
SELECT extensions.ok((SELECT context_snapshot#>>'{conversation_prefix,0,text}' LIKE '3x%' AND context_snapshot#>>'{conversation_prefix,11,text}' LIKE '14x%' FROM prefix_chat),'prefix chronological last twelve');
SELECT extensions.ok((SELECT bool_and(length(e->>'text')=900 AND e-ARRAY['role','text']='{}'::JSONB) FROM prefix_chat,jsonb_array_elements(context_snapshot->'conversation_prefix') e),'prefix strips IDs and caps each text');
DELETE FROM public.insight_chat_conversations WHERE id=(SELECT conversation_id FROM saved_chat);
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.insight_chat_turn_contexts WHERE message_id=(SELECT (message->>'id')::UUID FROM saved_chat)),0,'conversation deletion cascades private context');
DELETE FROM public.scans WHERE id='00000000-0000-4000-8000-00000000cb15';
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.insight_chat_turn_contexts WHERE message_id=(SELECT (message->>'id')::UUID FROM prefix_chat)),0,'scan deletion cascades private context');
-- Merge the exact message graph under deferred composite constraints, as the
-- existing merge owner does. Immutable contexts neither block reparenting nor
-- follow the duplicate message which that owner deletes.
SELECT pg_temp.seed_chat_observation('00000000-0000-4000-8000-00000000cb02','00000000-0000-4000-8000-00000000cb18');
SET CONSTRAINTS ALL DEFERRED;
CREATE TEMP TABLE merge_original AS SELECT c.* FROM internal.insight_chat_turn_contexts c JOIN public.insight_chat_messages m ON m.id=c.message_id WHERE m.scan_id='00000000-0000-4000-8000-00000000cb13';
INSERT INTO public.insight_chat_conversations(id,scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000cb38','00000000-0000-4000-8000-00000000cb13','00000000-0000-4000-8000-00000000cb02');
INSERT INTO public.insight_chat_messages(id,conversation_id,scan_id,user_id,role,message_text,client_message_id)
 VALUES('00000000-0000-4000-8000-00000000cb48','00000000-0000-4000-8000-00000000cb38','00000000-0000-4000-8000-00000000cb13','00000000-0000-4000-8000-00000000cb02','user','Duplicate question','00000000-0000-4000-8000-00000000cb28'),
 ('00000000-0000-4000-8000-00000000cb49',(SELECT conversation_id FROM history_chat),'00000000-0000-4000-8000-00000000cb13','00000000-0000-4000-8000-00000000cb01','user','Duplicate question','00000000-0000-4000-8000-00000000cb28');
INSERT INTO internal.insight_chat_turn_contexts SELECT id,1,'null','{}' FROM public.insight_chat_messages WHERE id IN ('00000000-0000-4000-8000-00000000cb48','00000000-0000-4000-8000-00000000cb49');
SELECT internal.merge_ghost_chat_conversations('00000000-0000-4000-8000-00000000cb01','00000000-0000-4000-8000-00000000cb02');
UPDATE public.scans SET user_id='00000000-0000-4000-8000-00000000cb02' WHERE user_id='00000000-0000-4000-8000-00000000cb01';
UPDATE public.insight_chat_conversations SET user_id='00000000-0000-4000-8000-00000000cb02' WHERE user_id='00000000-0000-4000-8000-00000000cb01';
UPDATE public.insight_chat_messages SET user_id='00000000-0000-4000-8000-00000000cb02' WHERE user_id='00000000-0000-4000-8000-00000000cb01';
SET CONSTRAINTS ALL IMMEDIATE;
SELECT extensions.ok((SELECT c.context_snapshot=o.context_snapshot FROM merge_original o JOIN internal.insight_chat_turn_contexts c USING(message_id) JOIN public.insight_chat_messages m ON m.id=c.message_id WHERE m.user_id='00000000-0000-4000-8000-00000000cb02' AND m.conversation_id='00000000-0000-4000-8000-00000000cb38'),'unique message context survives actual conversation merge/reparenting');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.insight_chat_turn_contexts WHERE message_id='00000000-0000-4000-8000-00000000cb48') AND NOT EXISTS(SELECT 1 FROM internal.insight_chat_turn_contexts WHERE message_id='00000000-0000-4000-8000-00000000cb49'),'duplicate source context cascades and target context survives');
SELECT extensions.throws_ok($$SELECT public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb13','History question','00000000-0000-4000-8000-00000000cb23',(SELECT ticket FROM chat_ticket),1)$$,'P0002','field_chat_subject_not_found','old account cannot recover merged context');
SELECT extensions.ok((SELECT r.context_snapshot=s.context_snapshot FROM history_chat s CROSS JOIN LATERAL public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cb02',gen_random_uuid(),'00000000-0000-4000-8000-00000000cb13','History question','00000000-0000-4000-8000-00000000cb23',(SELECT ticket FROM chat_ticket),1) r),'new account recovers exact original context');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok('SELECT * FROM internal.insight_chat_turn_contexts','42501',NULL,'service direct read denied');
SELECT extensions.throws_ok($$INSERT INTO internal.insight_chat_turn_contexts VALUES(gen_random_uuid(),1,'null','{}')$$,'42501',NULL,'service direct insert denied');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok('SELECT * FROM internal.insight_chat_turn_contexts','42501',NULL,'authenticated direct read denied');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT extensions.throws_ok('SELECT * FROM internal.insight_chat_turn_contexts','42501',NULL,'anonymous direct read denied');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
