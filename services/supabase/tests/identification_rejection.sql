\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(10);
CREATE TEMP TABLE rejection_fixture AS SELECT
 '00000000-0000-4000-8000-00000000cf01'::UUID owner_id,
 '00000000-0000-4000-8000-00000000cf02'::UUID other_id,
 '00000000-0000-4000-8000-00000000cf11'::UUID scan_id,
 '00000000-0000-4000-8000-00000000cf12'::UUID replacement_id,
 '00000000-0000-4000-8000-00000000cf21'::UUID operation_id;
GRANT SELECT ON rejection_fixture TO anon,authenticated,service_role;
DO $$ DECLARE f rejection_fixture%ROWTYPE; BEGIN
 SELECT * INTO f FROM rejection_fixture;
 INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(f.owner_id,'authenticated','authenticated','rejection-owner@example.invalid','{}','{}',NOW(),NOW()),
 (f.other_id,'authenticated','authenticated','rejection-other@example.invalid','{}','{}',NOW(),NOW());
 INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
 VALUES(f.scan_id::TEXT,f.owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted'),
 (f.replacement_id::TEXT,f.owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
 INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture)
 VALUES(f.scan_id,f.owner_id,'{}',0.9,TRUE,'flash','open',TRUE),
 (f.replacement_id,f.owner_id,'{}',0.9,TRUE,'flash','private',TRUE);
END $$;
SELECT extensions.ok(NOT has_column_privilege('anon','public.scans','ai_identification_review','SELECT')
 AND NOT has_column_privilege('authenticated','public.scans','ai_identification_review','SELECT'), 'raw review history is never exposed through public scan grants');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.apply_scan_identification_review(uuid,uuid,integer,uuid,text,text,jsonb,integer,uuid,integer)','EXECUTE'), 'clients cannot assert trusted ownership or taxonomy');
DO $$ DECLARE f rejection_fixture%ROWTYPE; receipt JSONB; repeated JSONB; denied BOOLEAN; BEGIN
 SELECT * INTO f FROM rejection_fixture;
 SET LOCAL ROLE service_role;
 receipt := public.apply_scan_identification_review(f.owner_id,f.scan_id,0,f.operation_id,'reject',NULL,NULL,NULL,NULL,NULL);
 repeated := public.apply_scan_identification_review(f.owner_id,f.scan_id,0,f.operation_id,'reject',NULL,NULL,NULL,NULL,NULL);
 IF receipt IS DISTINCT FROM repeated OR receipt #>> '{review,state}' <> 'ai_rejected' THEN RAISE EXCEPTION 'retry changed decision'; END IF;
 RESET ROLE;
 IF (SELECT ai_identification_review FROM public.scans WHERE id=f.scan_id) IS DISTINCT FROM
    (SELECT ai_identification_review FROM public.scan_ingestion_jobs WHERE scan_id=f.scan_id::TEXT) THEN RAISE EXCEPTION 'backup drift'; END IF;
 SET LOCAL ROLE service_role;
 denied := FALSE;
 BEGIN PERFORM public.apply_scan_identification_review(f.owner_id,f.scan_id,0,f.operation_id,'undo',NULL,NULL,NULL,NULL,NULL);
 EXCEPTION WHEN serialization_failure THEN denied := TRUE; END;
 IF NOT denied THEN RAISE EXCEPTION 'operation collision accepted'; END IF;
 RESET ROLE;
END $$;
SELECT extensions.pass('rejection and owner backup commit atomically; retry is idempotent and semantic collision conflicts');
SELECT extensions.ok((SELECT internal.scan_effective_identification(s) -> 'species_id' = 'null'::JSONB
 AND NOT public.field_trip_scan_evidence_is_eligible(s) FROM public.scans s WHERE id=(SELECT scan_id FROM rejection_fixture)), 'rejected identity supplies no species or Field Trip credit');
DO $$ DECLARE f rejection_fixture%ROWTYPE; count_rows INTEGER; BEGIN
 SELECT * INTO f FROM rejection_fixture;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.other_id,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 SELECT COUNT(*) INTO count_rows FROM public.get_owned_scan_ai_reviews(ARRAY[f.scan_id]);
 IF count_rows <> 0 THEN RAISE EXCEPTION 'another owner read history'; END IF;
 RESET ROLE;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.owner_id,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 SELECT COUNT(*) INTO count_rows FROM public.get_owned_scan_ai_reviews(ARRAY[f.scan_id]);
 IF count_rows <> 1 THEN RAISE EXCEPTION 'owner cannot read history'; END IF;
 RESET ROLE;
END $$;
SELECT extensions.pass('owner history RPC binds auth identity even for public scans');
DO $$ DECLARE f rejection_fixture%ROWTYPE; receipt JSONB; denied BOOLEAN; BEGIN
 SELECT * INTO f FROM rejection_fixture;
 SET LOCAL ROLE service_role;
 receipt := public.apply_scan_identification_review(f.owner_id,f.replacement_id,0,f.operation_id,'carry',NULL,NULL,NULL,f.scan_id,1);
 IF receipt #>> '{review,state}' <> 'awaiting_acceptance' OR receipt #>> '{review,origin_scan_id}' <> f.scan_id::TEXT THEN RAISE EXCEPTION 'replacement lost rejection'; END IF;
 denied := FALSE;
 BEGIN PERFORM public.apply_scan_identification_review(f.owner_id,f.replacement_id,1,gen_random_uuid(),'undo',NULL,NULL,NULL,NULL,NULL);
 EXCEPTION WHEN invalid_parameter_value THEN denied := TRUE; END;
 IF NOT denied THEN RAISE EXCEPTION 'proposal accepted by undo'; END IF;
 RESET ROLE;
END $$;
SELECT extensions.pass('reanalysis carries the original rejection and requires explicit acceptance');
DO $$ DECLARE f rejection_fixture%ROWTYPE; denied BOOLEAN; BEGIN
 SELECT * INTO f FROM rejection_fixture;
 PERFORM set_config('request.headers','{"x-merian-identification-protocol":"5"}',TRUE);
 SET LOCAL ROLE authenticated;
 denied := FALSE;
 BEGIN PERFORM id FROM public.scans WHERE id=f.scan_id; EXCEPTION WHEN SQLSTATE 'PT426' THEN denied:=TRUE; END;
 IF NOT denied THEN RAISE EXCEPTION 'old reader misread rejection'; END IF;
 PERFORM set_config('request.headers','{"x-merian-identification-protocol":"6"}',TRUE);
 PERFORM id FROM public.scans WHERE id=f.scan_id;
 RESET ROLE;
END $$;
SELECT extensions.pass('old readers fail explicitly; protocol 6 reads affected owner records');
DO $$ DECLARE f rejection_fixture%ROWTYPE; node_id UUID; post_id UUID; request_id UUID; identity JSONB; saved JSONB; denied BOOLEAN; BEGIN
 SELECT * INTO f FROM rejection_fixture;
 INSERT INTO public.taxon_nodes(path,rank,scientific_name,taxonomy_version_id,gbif_taxon_key)
 VALUES('rejectionfixture','species','Rejectionfixture accepted',public.active_taxonomy_version_id(),987699991) RETURNING id INTO node_id;
 INSERT INTO public.explore_posts(user_id,scan_id) VALUES(f.owner_id,f.replacement_id) RETURNING id INTO post_id;
 INSERT INTO public.explore_community_requests(post_id,scan_id,requested_by) VALUES(post_id,f.replacement_id,f.owner_id) RETURNING id INTO request_id;
 SET LOCAL ROLE service_role;
 UPDATE public.explore_community_requests SET status='resolved',resolved_taxon_node_id=node_id,resolved_at=NOW() WHERE id=request_id;
 RESET ROLE;
 SELECT internal.scan_effective_identification(s) INTO identity FROM public.scans s WHERE id=f.replacement_id;
 IF identity ->> 'scientific_name' <> 'Rejectionfixture accepted' OR identity ->> 'rank' <> 'species' OR identity -> 'species_id' = 'null'::JSONB THEN RAISE EXCEPTION 'community identity reverted to AI'; END IF;
 IF NOT (SELECT public.field_trip_scan_evidence_is_eligible(s) FROM public.scans s WHERE id=f.replacement_id) THEN RAISE EXCEPTION 'community species not eligible'; END IF;
 SELECT ai_identification_review INTO saved FROM public.scans WHERE id=f.replacement_id;
 SET LOCAL ROLE service_role;
 denied := FALSE;
 BEGIN PERFORM public.apply_scan_identification_review(f.owner_id,f.replacement_id,(saved ->> 'revision')::INTEGER,gen_random_uuid(),'undo',NULL,NULL,NULL,NULL,NULL);
 EXCEPTION WHEN invalid_parameter_value THEN denied := TRUE; END;
 IF NOT denied THEN RAISE EXCEPTION 'undo erased community authority'; END IF;
 RESET ROLE;
 IF (SELECT ai_identification_review FROM public.scans WHERE id=f.replacement_id) IS DISTINCT FROM saved THEN RAISE EXCEPTION 'denied undo changed authority'; END IF;
 SET LOCAL ROLE service_role;
 UPDATE public.explore_community_requests SET status='needs_id',resolved_taxon_node_id=NULL,resolved_at=NULL WHERE id=request_id;
 RESET ROLE;
 IF NOT (SELECT internal.scan_has_unresolved_review(s) FROM public.scans s WHERE id=f.replacement_id) THEN RAISE EXCEPTION 'community reversal retained authority'; END IF;
 INSERT INTO public.taxon_nodes(path,rank,scientific_name,taxonomy_version_id)
 VALUES('rejectiongenusfixture','genus','Rejectionfixture',public.active_taxonomy_version_id()) RETURNING id INTO node_id;
 SET LOCAL ROLE service_role;
 UPDATE public.explore_community_requests SET status='resolved',resolved_taxon_node_id=node_id,resolved_at=NOW() WHERE id=request_id;
 RESET ROLE;
 SELECT internal.scan_effective_identification(s) INTO identity FROM public.scans s WHERE id=f.replacement_id;
 IF identity ->> 'rank' <> 'genus' OR identity -> 'species_id' <> 'null'::JSONB OR (identity ->> 'pending_review')::BOOLEAN THEN RAISE EXCEPTION 'genus resolution invented species or remained pending'; END IF;
 IF (SELECT public.field_trip_scan_evidence_is_eligible(s) FROM public.scans s WHERE id=f.replacement_id) THEN RAISE EXCEPTION 'genus earned species credit'; END IF;
 SET LOCAL ROLE service_role;
 UPDATE public.explore_community_requests SET status='needs_id',resolved_taxon_node_id=NULL,resolved_at=NULL WHERE id=request_id;
 RESET ROLE;
END $$;
SELECT extensions.pass('community consensus resolves separately from AI and reversal revokes that authority');
DO $$ DECLARE f rejection_fixture%ROWTYPE; legacy_id UUID := '00000000-0000-4000-8000-00000000cf99'; BEGIN
 SELECT * INTO f FROM rejection_fixture;
 INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy)
 VALUES(legacy_id,f.owner_id,'{}',0.8,TRUE,'flash','private');
 SET LOCAL ROLE service_role;
 PERFORM public.apply_scan_identification_review(f.owner_id,legacy_id,0,f.operation_id,'reject',NULL,NULL,NULL,NULL,NULL);
 RESET ROLE;
 IF NOT EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=legacy_id::TEXT AND ai_identification_review ->> 'state'='ai_rejected') THEN RAISE EXCEPTION 'older scan has no review backup'; END IF;
END $$;
SELECT extensions.pass('older saved observations get a trusted owner-job backup without client recovery data');
DO $$ DECLARE f rejection_fixture%ROWTYPE; BEGIN
 SELECT * INTO f FROM rejection_fixture;
 SET LOCAL ROLE service_role;
 PERFORM public.apply_scan_identification_review(f.owner_id,f.scan_id,1,gen_random_uuid(),'undo',NULL,NULL,NULL,NULL,NULL);
 IF (SELECT ai_identification_review ->> 'state' FROM public.scans WHERE id=f.scan_id) <> 'clear' THEN RAISE EXCEPTION 'undo failed'; END IF;
 UPDATE public.scans SET is_tombstoned=TRUE WHERE id=f.replacement_id;
 RESET ROLE;
 IF EXISTS (SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=f.replacement_id::TEXT AND ai_identification_review IS NOT NULL) THEN RAISE EXCEPTION 'tombstone retained owner history'; END IF;
 RESET ROLE;
END $$;
SELECT extensions.pass('undo restores unreviewed state and tombstone clears owner backup');
SELECT * FROM extensions.finish();
ROLLBACK;
