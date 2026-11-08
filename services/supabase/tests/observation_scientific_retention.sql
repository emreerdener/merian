\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SELECT extensions.ok(NOT (SELECT enrollment_enabled FROM internal.observation_history_rollout WHERE singleton),'retention migration does not activate history');
SELECT extensions.ok(NOT has_function_privilege('authenticated','internal.observation_retained_identification(uuid)','EXECUTE')
 AND NOT has_function_privilege('service_role','internal.observation_retained_identification(uuid)','EXECUTE'),'stored science helper is not an API');
SELECT extensions.ok(NOT has_column_privilege('authenticated','public.scans','retained_identification','UPDATE')
 AND NOT has_column_privilege('authenticated','public.scans','retained_identification','INSERT'),'clients cannot forge retained science');
UPDATE internal.observation_history_rollout SET enrollment_enabled=TRUE;
-- BEGIN SCIENTIFIC RETENTION HELPERS
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

CREATE FUNCTION pg_temp.seed_retention(owner_id UUID, observation UUID, rank TEXT DEFAULT 'family', mode TEXT DEFAULT 'ai')
RETURNS UUID LANGUAGE PLPGSQL AS $$
DECLARE child UUID:=gen_random_uuid(); evidence JSONB; authority JSONB; taxon UUID; post UUID; request UUID;
BEGIN
 PERFORM pg_temp.seed_saved_observation(owner_id,observation,TRUE);
 UPDATE public.scans SET ai_reasoning='Synthetic private rationale',human_intervention_notes='Synthetic private note',
 colors=ARRAY['synthetic color'],extracted_visual_traits=ARRAY['synthetic private trait'],
 ecological_interactions=ARRAY['synthetic private text'],depth_scale_text='synthetic depth description',
 individual_count=2,estimated_size_cm=20,sex='female',sex_evidence='Synthetic private explanation',
 user_observation_context='{"description":"synthetic private context"}',llm_usage_metadata='{}'
 WHERE id=observation;
 IF mode='confirmed' THEN
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
  PERFORM public.apply_verified_scan_species_review(owner_id,observation,0,'confirm_name','Retentionfixture accepted',
   '{"scientific_name":"Retentionfixture accepted","gbif_taxon_key":987699783,"rank":"SPECIES","status":"ACCEPTED","kingdom":"Plantae"}');
 ELSIF mode='rejected' THEN
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
  PERFORM public.apply_scan_identification_review(owner_id,observation,0,gen_random_uuid(),'reject',NULL,NULL,0,NULL,NULL);
 ELSIF mode IN ('community','withdrawn') THEN
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
  PERFORM public.apply_scan_identification_review(owner_id,observation,0,gen_random_uuid(),'reject',NULL,NULL,0,NULL,NULL);
  INSERT INTO public.taxon_nodes(path,rank,scientific_name,taxonomy_version_id)
  VALUES(('retention_'||replace(observation::TEXT,'-',''))::public.ltree,'genus','Retentionfixture',public.active_taxonomy_version_id()) RETURNING id INTO taxon;
  INSERT INTO public.explore_posts(user_id,scan_id) VALUES(owner_id,observation) RETURNING id INTO post;
  INSERT INTO public.explore_community_requests(post_id,scan_id,requested_by) VALUES(post,observation,owner_id) RETURNING id INTO request;
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
  UPDATE public.explore_community_requests SET status='resolved',resolved_taxon_node_id=taxon,resolved_at=now() WHERE id=request;
  IF mode='withdrawn' THEN UPDATE public.explore_community_requests SET status='needs_id',resolved_taxon_node_id=NULL,resolved_at=NULL WHERE id=request; END IF;
 END IF;
 INSERT INTO internal.observation_histories(observation_id) VALUES(observation);
 IF mode='none' THEN RETURN NULL; END IF;
 SELECT to_jsonb(s)||jsonb_build_object('ai_confidence_score',0.42,
  'primary_identification',CASE WHEN rank='legacy' THEN NULL ELSE jsonb_build_object('version',1,'resolution',rank,
    'scientific_name',CASE WHEN rank IN ('species','genus','family') THEN 'Newfixture' ELSE NULL END,'common_name',NULL) END,
  'identification_provenance',CASE WHEN rank='legacy' THEN NULL ELSE s.identification_provenance END,
  'is_biological_subject',rank<>'non_biological') INTO evidence FROM public.scans s WHERE id=observation;
 SELECT jsonb_build_object('ai_identification_review',s.ai_identification_review,'confirmed_species_identity',s.confirmed_species_identity,
  'confirmed_species_identity_revision',s.confirmed_species_identity_revision,'confirmed_species_id',s.confirmed_species_id,
  'user_identification_override',s.user_identification_override,'user_confirmed_identification',s.user_confirmed_identification,
  'user_review_state',s.user_review_state) INTO authority FROM public.scans s WHERE id=observation;
 INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,result_snapshot,evidence_manifest,completed_at)
 VALUES(child,observation,1,repeat('a',64),evidence,'{"schema_version":1,"captured_media":[]}',now());
 INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot) VALUES(observation,child,authority);
 UPDATE internal.observation_histories SET selected_analysis_id=child,selection_initialized=TRUE,state_revision=1,
  active_projection=internal.observation_analysis_projection(evidence,authority) WHERE observation_id=observation;
 RETURN child;
END;
$$;
-- END SCIENTIFIC RETENTION HELPERS

CREATE TEMP TABLE cases(n INTEGER,rank TEXT,mode TEXT);
INSERT INTO cases VALUES(1,'species','ai'),(2,'genus','ai'),(3,'family','ai'),(4,'unresolved_biological','ai'),
 (5,'non_biological','ai'),(6,'legacy','ai'),(7,'species','confirmed'),(8,'species','rejected'),
 (9,'species','community'),(10,'species','withdrawn'),(11,'family','none');
SELECT pg_temp.seed_retention(('00000000-0000-4000-8000-'||lpad(n::TEXT,12,'0'))::UUID,
 ('00000000-0000-4000-9000-'||lpad(n::TEXT,12,'0'))::UUID,rank,mode) FROM cases;
CREATE TEMP TABLE original AS SELECT s.id,s.user_id,to_jsonb(s) AS row,
 internal.observation_retained_identification(s.id) AS facts FROM public.scans s JOIN cases c
 ON s.user_id=('00000000-0000-4000-8000-'||lpad(c.n::TEXT,12,'0'))::UUID;

SELECT extensions.ok((SELECT bool_and(internal.retained_identification_is_valid(facts)) FROM original),'all supported active authority/rank cases have valid scalar facts');
SELECT extensions.is((SELECT facts->>'source' FROM original WHERE id='00000000-0000-4000-9000-000000000007'),'verified_selection','confirmation is captured as past scientific interpretation');
SELECT extensions.is((SELECT facts->>'rank' FROM original WHERE id='00000000-0000-4000-9000-000000000008'),'unresolved_biological','rejection never retains primary as current acknowledged identity');
SELECT extensions.is((SELECT facts->>'rank' FROM original WHERE id='00000000-0000-4000-9000-000000000009'),'genus','community broader taxon stays broader');
SELECT extensions.is((SELECT facts->>'rank' FROM original WHERE id='00000000-0000-4000-9000-000000000010'),'unresolved_biological','withdrawal stays unresolved');
SELECT extensions.is((SELECT facts->>'source' FROM original WHERE id='00000000-0000-4000-9000-000000000011'),'none','uninitialized history retains no invented result');

SELECT extensions.ok(NOT internal.retained_identification_is_valid(facts||bad.value),'closed fact schema rejects '||bad.label)
FROM (SELECT facts FROM original WHERE id='00000000-0000-4000-9000-000000000001') f,
 (VALUES ('unknown key','{"private":"no"}'::JSONB),('nested value','{"model":{"private":true}}'),
 ('array','{"provider":[]}'),('bad UUID','{"species_id":"no"}'),('bad confidence','{"ai_confidence_score":1.1}'),
 ('string confidence','{"ai_confidence_score":"0.4"}'),('bad source','{"source":"current"}'),('forged verification','{"verified":true}'),
 ('nonbio mismatch','{"is_biological_subject":false}'),('orphan provenance','{"provenance_version":null}'),
 ('bad names','{"scientific_name":" padded "}'),('oversize',jsonb_build_object('scientific_name',repeat('a',5000)))) bad(label,value);
SELECT extensions.ok(NOT internal.retained_identification_is_valid(facts-'rank'),'missing scalar key rejected') FROM original LIMIT 1;
SELECT extensions.ok(NOT internal.retained_identification_is_valid(facts||'{"source":null}'),'null source rejected') FROM original LIMIT 1;
SELECT extensions.throws_ok($$UPDATE public.scans SET retained_identification=(SELECT facts FROM original LIMIT 1) WHERE id='00000000-0000-4000-9000-000000000001'$$,
 '22023','scientific_retention_immutable','even service-owned live rows cannot acquire fabricated retained state');

-- Changed stored projection aborts the whole transaction without detaching.
UPDATE internal.observation_histories SET active_projection='{}' WHERE observation_id='00000000-0000-4000-9000-000000000001';
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.apply_user_tombstone('00000000-0000-4000-8000-000000000001')$$,
 '55000','scientific_retention_state_invalid','stale projection cannot be materialized');
RESET ROLE;
SELECT extensions.ok(EXISTS(SELECT 1 FROM public.scans WHERE id='00000000-0000-4000-9000-000000000001' AND user_id IS NOT NULL)
 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id='00000000-0000-4000-9000-000000000001'),'failed materialization preserves owner and complete private history');
UPDATE internal.observation_histories h SET active_projection=internal.observation_analysis_projection(r.result_snapshot,a.review_snapshot)
 FROM internal.observation_analysis_results r JOIN internal.observation_analysis_authorities a USING(analysis_id,observation_id)
 WHERE h.observation_id=r.observation_id AND h.selected_analysis_id=r.analysis_id;

-- Future required/generated fields fail atomically until explicitly classified.
ALTER TABLE public.scans ADD COLUMN retention_required TEXT NOT NULL DEFAULT 'synthetic';
SELECT extensions.throws_ok($$SELECT public.apply_user_tombstone('00000000-0000-4000-8000-000000000001')$$,
 '23502',NULL,'unclassified required field cannot survive detachment');
ALTER TABLE public.scans DROP COLUMN retention_required;
ALTER TABLE public.scans ADD COLUMN retention_generated TEXT GENERATED ALWAYS AS (ai_reasoning) STORED;
SELECT extensions.throws_ok($$SELECT public.apply_user_tombstone('00000000-0000-4000-8000-000000000001')$$,
 '55000','scientific_retention_schema_unclassified','unclassified generated field blocks detachment');
ALTER TABLE public.scans DROP COLUMN retention_generated;
SELECT extensions.ok(EXISTS(SELECT 1 FROM public.scans WHERE id='00000000-0000-4000-9000-000000000001' AND user_id IS NOT NULL)
 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id='00000000-0000-4000-9000-000000000001'),'schema classification failures preserve owner and private history');

-- A future nullable field is cleared by default instead of being copied.
ALTER TABLE public.scans ADD COLUMN retention_test_unclassified TEXT;
UPDATE public.scans SET retention_test_unclassified='Synthetic private future field' WHERE id IN (SELECT id FROM original);
-- Existing individual-deletion fence cannot prevent the exact account cleanup.
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id)
 VALUES('00000000-0000-4000-9000-000000000003','00000000-0000-4000-8000-000000000003');
DO $$ DECLARE owner UUID; BEGIN
 FOR owner IN SELECT user_id FROM original LOOP PERFORM public.apply_user_tombstone(owner); END LOOP;
END $$;
SELECT extensions.ok((SELECT bool_and(s.user_id IS NULL AND s.is_tombstoned AND s.retained_identification=o.facts)
 FROM original o JOIN public.scans s USING(id)),'every enrolled observation materializes exactly its acknowledged scalar facts before detachment');
SELECT extensions.ok((SELECT bool_and(s.ai_confidence_score=(o.row->>'ai_confidence_score')::FLOAT
 AND s.primary_identification IS NOT DISTINCT FROM o.row->'primary_identification'
 AND s.identification_provenance IS NOT DISTINCT FROM o.row->'identification_provenance') FROM original o JOIN public.scans s USING(id)),
 'original AI primary/confidence/provenance survive separately from selected result');
SELECT extensions.ok((SELECT bool_and(s.retained_identification->>'ai_confidence_score'='0.42') FROM original o JOIN public.scans s USING(id) WHERE o.facts->>'source'<>'none'),'selected result confidence does not overwrite original score');
SELECT extensions.ok((SELECT bool_and(ai_reasoning IS NULL AND human_intervention_notes IS NULL AND sex_evidence IS NULL
 AND candidates IS NULL AND pet_identification IS NULL AND user_observation_context IS NULL AND captured_media IS NULL
 AND retention_test_unclassified IS NULL AND public_location_label IS NULL AND cardinality(image_storage_urls)=0 AND cardinality(colors)=0
 AND extracted_visual_traits IS NULL AND ecological_interactions IS NULL AND depth_scale_text IS NULL) FROM public.scans s JOIN original USING(id)),
 'private payloads, descriptions, evidence and unclassified future field erased');
SELECT extensions.ok((SELECT bool_and(ai_identification_review IS NULL AND confirmed_species_identity IS NULL AND confirmed_species_id IS NULL
 AND user_identification_override IS NULL AND user_confirmed_identification IS FALSE AND user_review_state='unreviewed'
 AND s.confirmed_species_identity_revision=(o.row->>'confirmed_species_identity_revision')::INTEGER) FROM public.scans s JOIN original o USING(id)),
 'raw review authority cleared while original review revision is retained');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.observation_histories h JOIN original o ON o.id=h.observation_id)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results r JOIN original o ON o.id=r.observation_id),'private child history erased transactionally');
SELECT extensions.ok((SELECT bool_and(s.gps_lat_exact IS NOT DISTINCT FROM (o.row->>'gps_lat_exact')::FLOAT
 AND s.gps_lat_public IS NOT DISTINCT FROM (o.row->>'gps_lat_public')::FLOAT
 AND s.coordinate_uncertainty_in_meters IS NOT DISTINCT FROM (o.row->>'coordinate_uncertainty_in_meters')::INTEGER
 AND s.individual_count=2 AND s.estimated_size_cm=20) FROM public.scans s JOIN original o USING(id)),
 'original coordinates and approved biological measurements unchanged');
SELECT extensions.throws_ok($$UPDATE public.scans SET ai_confidence_score=0.8 WHERE id='00000000-0000-4000-9000-000000000001'$$,
 '22023','scientific_retention_immutable','detached retained facts cannot be rewritten after private history disappears');
SELECT extensions.throws_ok($$UPDATE public.scans SET retained_identification=NULL WHERE id='00000000-0000-4000-9000-000000000001'$$,
 '22023','scientific_retention_immutable','retention marker cannot be cleared to bypass the immutable guard');
SELECT extensions.throws_ok($$UPDATE public.scans SET ai_confidence_score=0.8 WHERE id='00000000-0000-4000-9000-000000000011'$$,
 '22023','scientific_retention_immutable','uninitialized enrolled tombstone is also immutable');
SELECT extensions.lives_ok($$SELECT public.apply_user_tombstone('00000000-0000-4000-8000-000000000001')$$,'account cleanup remains idempotent');
SET LOCAL ROLE anon;
SELECT extensions.is((SELECT count(*)::INT FROM public.scans WHERE id::TEXT LIKE '00000000-0000-4000-9000-%'),0,'anonymous Data API cannot read retained scientific facts');
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.is((SELECT count(*)::INT FROM public.scans WHERE id::TEXT LIKE '00000000-0000-4000-9000-%'),0,'deleted owner cannot read detached facts');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
