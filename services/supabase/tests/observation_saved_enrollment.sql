\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(21);
SELECT extensions.ok(NOT (SELECT saved_import_enabled OR enrollment_enabled FROM internal.observation_history_rollout WHERE singleton),'import defaults closed');
SELECT extensions.ok(has_function_privilege('authenticated','public.enroll_owned_observation_history(uuid,integer)','EXECUTE')
 AND NOT has_function_privilege('anon','public.enroll_owned_observation_history(uuid,integer)','EXECUTE')
 AND NOT has_function_privilege('service_role','public.enroll_owned_observation_history(uuid,integer)','EXECUTE'),'only authenticated owner can request enrollment');

-- BEGIN SAVED ENROLLMENT HELPERS
CREATE FUNCTION pg_temp.seed_saved_observation(owner_id UUID,observation UUID,has_primary BOOLEAN DEFAULT FALSE) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT||'@example.invalid','{}','{}',now(),now()) ON CONFLICT DO NOTHING;
 INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
 VALUES(observation::TEXT,owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
 INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,identification_provenance,primary_identification)
 VALUES(observation,owner_id,ARRAY['https://example.invalid/legacy-public.jpg'],0.9,TRUE,'flash','private',CASE WHEN has_primary THEN '{"version":2,"provider":"openai","binding":"openai_photo_v1","model":"gpt-6-sol","variant":"multimodal","operation":"scan_identification","policy_version":2,"prompt":"synthetic_primary_fixture_v1","schema":"merian_identify_primary_v1","confidence":"openai_unqualified_v1","diagnostic_trigger":null,"prompt_diagnostic_trigger":null,"safety":"openai_photo_moderation_v1","timeout_ms":90000,"generation":{"max_output_tokens":8192,"reasoning_effort":"low","image_detail":"high"}}'::JSONB END,CASE WHEN has_primary THEN '{"version":1,"resolution":"genus","scientific_name":"Savedfixture","common_name":null}'::JSONB END);
END;
$$;
-- END SAVED ENROLLMENT HELPERS
SELECT pg_temp.seed_saved_observation('00000000-0000-4000-8000-00000000d801',('00000000-0000-4000-8000-00000000d81'||n)::UUID,n=2) FROM generate_series(1,6) n;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000d801","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000d811',9)$$,'55000','analysis_history_unavailable','closed import refuses owner');
SELECT extensions.throws_ok($$SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000d811',8)$$,'22023','invalid_analysis_history','old importer refused');
RESET ROLE;
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE;
-- Legacy candidates are preserved as opaque saved JSON, not current provider DTOs.
UPDATE public.scans SET candidates='{}' WHERE id='00000000-0000-4000-8000-00000000d811';
-- Corrected, rejected, resolved, withdrawn and non-biological saved states.
SET LOCAL ROLE service_role;
SELECT public.apply_verified_scan_species_review('00000000-0000-4000-8000-00000000d801','00000000-0000-4000-8000-00000000d812',0,'confirm_name','Savedfixture accepted',
 '{"scientific_name":"Savedfixture accepted","gbif_taxon_key":987699781,"rank":"SPECIES","status":"ACCEPTED","kingdom":"Plantae"}');
SELECT public.apply_scan_identification_review('00000000-0000-4000-8000-00000000d801','00000000-0000-4000-8000-00000000d813',0,gen_random_uuid(),'reject',NULL,NULL,NULL,NULL,NULL);
RESET ROLE;
DO $$ DECLARE node UUID; post UUID; request UUID; observation UUID; n INTEGER; BEGIN
 INSERT INTO public.taxon_nodes(path,rank,scientific_name,taxonomy_version_id)
 VALUES('savedfixture','genus','Savedfixture',public.active_taxonomy_version_id()) RETURNING id INTO node;
 FOR n IN 4..5 LOOP
  observation:=('00000000-0000-4000-8000-00000000d81'||n)::UUID;
  INSERT INTO public.explore_posts(user_id,scan_id) VALUES('00000000-0000-4000-8000-00000000d801',observation) RETURNING id INTO post;
  INSERT INTO public.explore_community_requests(post_id,scan_id,requested_by) VALUES(post,observation,'00000000-0000-4000-8000-00000000d801') RETURNING id INTO request;
  SET LOCAL ROLE service_role;
  UPDATE public.explore_community_requests SET status='resolved',resolved_taxon_node_id=node,resolved_at=now() WHERE id=request;
  IF n=5 THEN UPDATE public.explore_community_requests SET status='needs_id',resolved_taxon_node_id=NULL,resolved_at=NULL WHERE id=request; END IF;
  RESET ROLE;
 END LOOP;
END $$;
UPDATE public.scans SET is_biological_subject=FALSE WHERE id='00000000-0000-4000-8000-00000000d816';
CREATE TEMP TABLE before_enrollment AS SELECT id,to_jsonb(s) AS entire_scan,
 internal.scan_effective_identification(s) || CASE WHEN NOT is_biological_subject THEN '{"rank":"non_biological","species_id":null,"verified":false}'::JSONB ELSE '{}'::JSONB END AS projection,
 public.field_trip_scan_evidence_is_eligible(s) AS eligible FROM public.scans s WHERE user_id='00000000-0000-4000-8000-00000000d801';
CREATE TEMP TABLE import_receipts(observation UUID PRIMARY KEY,receipt JSONB);
GRANT ALL ON import_receipts TO authenticated;
SET LOCAL ROLE authenticated;
INSERT INTO import_receipts SELECT ('00000000-0000-4000-8000-00000000d81'||n)::UUID,
 public.enroll_owned_observation_history(('00000000-0000-4000-8000-00000000d81'||n)::UUID,9) FROM generate_series(1,6) n;
RESET ROLE;
SELECT extensions.ok((SELECT bool_and(to_jsonb(s)=b.entire_scan AND public.field_trip_scan_evidence_is_eligible(s)=b.eligible)
 FROM before_enrollment b JOIN public.scans s ON s.id=b.id),'all saved scan fields and existing eligibility unchanged');
SELECT extensions.ok((SELECT bool_and(h.active_projection=b.projection AND h.state_revision=1 AND h.selection_initialized AND NOT h.initial_selection_permitted)
 FROM before_enrollment b JOIN internal.observation_histories h ON h.observation_id=b.id),'initial selected projection preserves correction/rejection/community/withdrawal/nonbio');
SELECT extensions.ok((SELECT bool_and(a.review_revision=0 AND a.review_snapshot=(SELECT jsonb_object_agg(key,value) FROM jsonb_each(b.entire_scan)
 WHERE key=ANY(ARRAY['ai_identification_review','confirmed_species_identity','confirmed_species_identity_revision','confirmed_species_id','user_identification_override','user_confirmed_identification','user_review_state'])))
 FROM before_enrollment b JOIN internal.observation_analysis_authorities a ON a.observation_id=b.id),'seven review fields copied exactly; history revision is independently zero');
SELECT extensions.ok((SELECT bool_and(r.request_digest IS NULL AND r.completed_at IS NULL AND r.source_analysis_id IS NULL
 AND r.analysis_id<>r.observation_id AND r.evidence_manifest->>'availability'='unavailable'
 AND NOT r.result_snapshot ?| ARRAY['image_storage_urls','captured_media','user_observation_context','user_id','gps_lat_exact'])
 FROM internal.observation_analysis_results r JOIN before_enrollment b ON b.id=r.observation_id),'no fabricated execution, private receipt, location or owner payload');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.observation_history_reconciliation),0,'baseline grants no new credit/reconciliation');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_page('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000d811","before_ordinal":1,"limit":20}',8)$$,
 '55000','analysis_history_reader_upgrade_required','protocol8 refuses whole import even beyond page cursor');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_page('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000d811","before_ordinal":null,"limit":20}',7)$$,
 '55000','analysis_history_reader_upgrade_required','protocol7 refuses imported history');
SELECT extensions.is((public.get_owned_observation_analysis_page('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000d811","before_ordinal":null,"limit":20}',9)#>>'{items,0,snapshot}')::JSONB->>'schema_version','3','protocol9 returns explicit saved origin');
RESET ROLE;
SELECT extensions.throws_ok($$INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,result_snapshot,evidence_manifest)
 VALUES(gen_random_uuid(),'00000000-0000-4000-8000-00000000d811',9,'{}','{"schema_version":1,"captured_media":[]}')$$,'23514',NULL,'nullable import columns never weaken V1 execution metadata');
SELECT extensions.throws_ok($$INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,result_snapshot,evidence_manifest)
 VALUES(gen_random_uuid(),'00000000-0000-4000-8000-00000000d811',9,'{}','{"schema_version":3,"origin":null,"availability":null,"imported_at_ms":null}')$$,'23514',NULL,'null import manifest cannot evade CHECK');
DO $$ DECLARE base internal.observation_analysis_results; next_id UUID:=gen_random_uuid(); old_receipt JSONB; repeated JSONB; BEGIN
 SELECT * INTO base FROM internal.observation_analysis_results WHERE observation_id='00000000-0000-4000-8000-00000000d811';
 INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,completed_at,result_snapshot,evidence_manifest)
 VALUES(next_id,base.observation_id,2,repeat('a',64),now(),base.result_snapshot,'{"schema_version":1,"captured_media":[{"description":{"_0":{"freeText":"Synthetic later result"}}}]}');
 INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
 SELECT base.observation_id,next_id,review_snapshot FROM internal.observation_analysis_authorities WHERE analysis_id=base.analysis_id;
 UPDATE internal.observation_histories SET selected_analysis_id=next_id,state_revision=4 WHERE observation_id=base.observation_id;
 UPDATE internal.observation_history_rollout SET enrollment_enabled=FALSE,saved_import_enabled=FALSE;
 SELECT receipt INTO old_receipt FROM import_receipts WHERE observation=base.observation_id;
 SET LOCAL ROLE authenticated;
 repeated:=public.enroll_owned_observation_history(base.observation_id,9);
 RESET ROLE;
 IF repeated<>old_receipt OR NOT EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=base.observation_id AND selected_analysis_id=next_id AND state_revision=4) THEN RAISE EXCEPTION 'replay changed selection'; END IF;
END $$;
SELECT extensions.pass('lost response replay returns original baseline without overwriting later selection even after admission closes');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000d802","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000d811',9)$$,'P0002','analysis_history_not_found','foreign owner cannot replay import');
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000d801","role":"authenticated"}',TRUE);
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000d811','00000000-0000-4000-8000-00000000d801');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000d811',9)$$,'P0002','analysis_history_not_found','deletion beats baseline replay');
RESET ROLE;
DELETE FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000d812';
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones t JOIN import_receipts r ON t.scan_id=(r.receipt->>'baseline_analysis_id')::UUID WHERE r.observation='00000000-0000-4000-8000-00000000d812' AND t.user_id IS NULL),'import cascade preserves only ownerless child fence');
SELECT extensions.throws_ok($$INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy)
 SELECT (receipt->>'baseline_analysis_id')::UUID,'00000000-0000-4000-8000-00000000d801','{}',0.9,TRUE,'flash','private' FROM import_receipts WHERE observation='00000000-0000-4000-8000-00000000d813'$$,'22023','analysis_history_operation_conflict','imported child cannot become legacy scan');
SELECT extensions.ok(NOT (SELECT selection_enabled OR admission_enabled OR dispatch_enabled OR orchestration_enabled FROM internal.observation_history_rollout WHERE singleton),'import does not activate execution or selection');
SELECT extensions.ok((SELECT bool_and(internal.observation_analysis_snapshot(
 '00000000-0000-4000-8000-00000000d811','00000000-0000-4000-8000-00000000d899',NULL,repeat('a',64),2,'2026-01-01T00:00:00Z','{}',jsonb_build_object('schema_version',v))
 =jsonb_build_object('schema_version',v,'observation_id','00000000-0000-4000-8000-00000000d811','analysis_id','00000000-0000-4000-8000-00000000d899',
 'ordinal',2,'source_analysis_id',NULL,'request_digest',repeat('a',64),'completed_at_ms',1767225600000,'result','{}'::JSONB,'evidence_manifest',jsonb_build_object('schema_version',v))::TEXT)
 FROM generate_series(1,2) v),'V1/V2 serializer bytes unchanged by import branch');
SELECT * FROM extensions.finish();
ROLLBACK;
