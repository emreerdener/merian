SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Preparation only. Import means the surviving saved identification, not a
-- recovered original provider execution. Never fabricate its digest or date.
ALTER TABLE internal.observation_history_rollout
    ADD COLUMN saved_import_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE internal.observation_analysis_results
    ALTER COLUMN request_digest DROP NOT NULL,
    ALTER COLUMN completed_at DROP NOT NULL;
ALTER TABLE internal.observation_analysis_results ADD CONSTRAINT observation_analysis_origin CHECK ((
    CASE WHEN evidence_manifest->'schema_version'='3'::JSONB THEN
        request_digest IS NULL AND completed_at IS NULL AND source_analysis_id IS NULL AND ordinal=1
        AND evidence_manifest ?& ARRAY['schema_version','origin','imported_at_ms','availability']
        AND evidence_manifest-ARRAY['schema_version','origin','imported_at_ms','availability']='{}'::JSONB
        AND evidence_manifest->>'origin'='saved_identification'
        AND evidence_manifest->>'availability'='unavailable'
        AND pg_catalog.jsonb_typeof(evidence_manifest->'imported_at_ms')='number'
        AND (evidence_manifest->>'imported_at_ms') ~ '^[0-9]{1,16}$'
        AND (evidence_manifest->>'imported_at_ms')::NUMERIC BETWEEN 0 AND 8640000000000000
    WHEN evidence_manifest->'schema_version' IN ('1'::JSONB,'2'::JSONB)
        THEN request_digest IS NOT NULL AND completed_at IS NOT NULL
    ELSE FALSE END) IS TRUE
);

CREATE OR REPLACE FUNCTION internal.observation_analysis_snapshot(
    observation UUID, analysis UUID, source_analysis UUID, digest TEXT, ordinal INTEGER,
    completed TIMESTAMPTZ, result JSONB, evidence JSONB
) RETURNS TEXT LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
    SELECT pg_catalog.jsonb_build_object(
        'schema_version',CASE WHEN evidence->'schema_version'='3'::JSONB THEN 3
            WHEN evidence->'schema_version'='2'::JSONB THEN 2 ELSE 1 END,
        'observation_id',observation,'analysis_id',analysis,'ordinal',ordinal,
        'source_analysis_id',source_analysis,'request_digest',digest,
        'completed_at_ms',pg_catalog.floor(EXTRACT(EPOCH FROM completed)*1000),
        'result',result,'evidence_manifest',evidence)::TEXT;
$$;
-- A CHECK yielding NULL would bypass the aggregate size limit for imports.
ALTER TABLE internal.observation_analysis_results DROP CONSTRAINT observation_analysis_readable_snapshot;
ALTER TABLE internal.observation_analysis_results ADD CONSTRAINT observation_analysis_readable_snapshot CHECK (
    (completed_at IS NULL OR (pg_catalog.isfinite(completed_at)
        AND EXTRACT(EPOCH FROM completed_at)*1000 BETWEEN 0 AND 8640000000000000))
    AND pg_catalog.octet_length(internal.observation_analysis_snapshot(
        observation_id,analysis_id,source_analysis_id,request_digest,ordinal,completed_at,result_snapshot,evidence_manifest))<=1048576
);

-- Import only from the locked server row. No client result/review/media input,
-- quota admission, provider execution, species credit or public scan mutation.
CREATE FUNCTION public.enroll_owned_observation_history(p_observation UUID,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE caller UUID:=auth.uid(); scan public.scans; history internal.observation_histories;
    baseline internal.observation_analysis_results; analysis UUID; result JSONB; review JSONB; projection JSONB;
BEGIN
    IF caller IS NULL OR p_observation IS NULL OR p_reader IS DISTINCT FROM 9 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM users.id FROM public.users AS users WHERE users.id=caller FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_observation::TEXT,0::BIGINT));
    SELECT * INTO scan FROM public.scans WHERE id=p_observation AND user_id=caller AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    IF (SELECT reader_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=p_observation FOR UPDATE;
    IF FOUND THEN
        SELECT * INTO baseline FROM internal.observation_analysis_results
            WHERE observation_id=p_observation AND ordinal=1 AND evidence_manifest->'schema_version'='3'::JSONB;
        IF NOT FOUND OR NOT history.selection_initialized THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        -- Recover a lost response without reinstating the original selection.
        RETURN pg_catalog.jsonb_build_object('schema_version',1,'owner_id',caller,
            'observation_id',p_observation,'baseline_analysis_id',baseline.analysis_id);
    END IF;
    IF (SELECT enrollment_enabled AND saved_import_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    result:=pg_catalog.jsonb_build_object('scan_id',scan.id,
        'primary_identification',scan.primary_identification,'identification_provenance',scan.identification_provenance,
        'species_id',scan.species_id,'is_biological_subject',scan.is_biological_subject,
        'candidates',scan.candidates,'pet_identification',scan.pet_identification,
        'ai_confidence_score',scan.ai_confidence_score,'ai_reasoning',scan.ai_reasoning,'inference_tier',scan.inference_tier);
    review:=pg_catalog.jsonb_build_object('ai_identification_review',scan.ai_identification_review,
        'confirmed_species_identity',scan.confirmed_species_identity,'confirmed_species_identity_revision',scan.confirmed_species_identity_revision,
        'confirmed_species_id',scan.confirmed_species_id,'user_identification_override',scan.user_identification_override,
        'user_confirmed_identification',scan.user_confirmed_identification,'user_review_state',scan.user_review_state);
    projection:=internal.observation_analysis_projection(result,review);
    analysis:=pg_catalog.gen_random_uuid();
    -- Reserve the separate child namespace under the same lock as legacy scan
    -- insertion. Imports have no funded intent, so the collision guard below
    -- must cover result IDs as well as provider-intent IDs.
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||analysis::TEXT,0::BIGINT));
    IF analysis IN (caller,p_observation) OR EXISTS(SELECT 1 FROM public.scans WHERE id=analysis)
        OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=analysis::TEXT)
        OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=analysis)
        OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=analysis)
        OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=analysis) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    INSERT INTO internal.observation_histories(observation_id,initial_selection_permitted) VALUES(p_observation,FALSE);
    INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,result_snapshot,evidence_manifest,completed_at)
        VALUES(analysis,p_observation,1,NULL,result,pg_catalog.jsonb_build_object('schema_version',3,
            'origin','saved_identification','imported_at_ms',pg_catalog.floor(EXTRACT(EPOCH FROM pg_catalog.clock_timestamp())*1000),
            'availability','unavailable'),NULL);
    INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_revision,review_snapshot)
        VALUES(p_observation,analysis,0,review);
    UPDATE internal.observation_histories SET selected_analysis_id=analysis,selection_initialized=TRUE,state_revision=1,active_projection=projection
        WHERE observation_id=p_observation;
    RETURN pg_catalog.jsonb_build_object('schema_version',1,'owner_id',caller,
        'observation_id',p_observation,'baseline_analysis_id',analysis);
END;
$$;
REVOKE ALL ON FUNCTION public.enroll_owned_observation_history(UUID,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.enroll_owned_observation_history(UUID,INTEGER) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('authenticated','public.enroll_owned_observation_history(uuid,integer)',
     'Default-off owner enrollment from locked surviving saved identification; never infer original provider evidence.');

-- Existing readers must reject the entire history, not silently page past the
-- imported baseline. V1/V2 bytes and the bounded page envelope are unchanged.
DO $patch$
DECLARE definition TEXT; old TEXT; replacement TEXT;
BEGIN
    definition:=pg_catalog.pg_get_functiondef('public.get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
    old:='p_reader NOT IN (7,8)';
    IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'history_reader_source_drift'; END IF;
    definition:=replace(definition,old,'p_reader NOT IN (7,8,9)');
    old:='IF p_reader=7 AND EXISTS';
    replacement:=$new$IF p_reader<9 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results
        WHERE observation_id=observation AND evidence_manifest->'schema_version'='3'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000';
    END IF;
    IF p_reader=7 AND EXISTS$new$;
    IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'history_reader_source_drift'; END IF;
    definition:=replace(definition,old,replacement);
    old:=$old$(p_reader=8 AND result_row.evidence_manifest -> 'schema_version' = '2'::JSONB
                 AND pg_catalog.JSONB_TYPEOF(result_row.evidence_manifest -> 'items') = 'array'))$old$;
    replacement:=$new$(p_reader>=8 AND result_row.evidence_manifest -> 'schema_version' = '2'::JSONB
                 AND pg_catalog.JSONB_TYPEOF(result_row.evidence_manifest -> 'items') = 'array')
                OR (p_reader=9 AND result_row.evidence_manifest -> 'schema_version' = '3'::JSONB))$new$;
    IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'history_reader_source_drift'; END IF;
    EXECUTE replace(definition,old,replacement);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; old TEXT;
BEGIN
    definition:=pg_catalog.pg_get_functiondef('internal.guard_history_child_scan_identity()'::regprocedure);
    old:='IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=NEW.id) THEN';
    IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'history_identity_source_drift'; END IF;
    EXECUTE replace(definition,old,'IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=NEW.id)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=NEW.id) THEN');
END;
$patch$;

-- Legacy request/settlement paths must recognize imported child identities even
-- though they never have a quota/provider intent of their own.
DO $patch$
DECLARE definition TEXT; old TEXT; signature TEXT; variable TEXT;
BEGIN
    FOREACH signature IN ARRAY ARRAY[
        'public.begin_scan_ingestion(text,uuid,text,jsonb,jsonb,jsonb,text[],text,text,boolean,boolean,jsonb,integer,integer)',
        'public.complete_scan_ingestion_with_entitlement(uuid,uuid,jsonb,jsonb,text[])',
        'public.fail_scan_ingestion_terminal(uuid,uuid,text,text,text)'
    ] LOOP
        variable:=CASE WHEN signature LIKE 'public.begin_scan_ingestion%' THEN 'scan_id_uuid' ELSE 'p_scan_id' END;
        definition:=pg_catalog.pg_get_functiondef(signature::regprocedure);
        old:='IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id='||variable||') THEN';
        IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'history_identity_source_drift'; END IF;
        EXECUTE replace(definition,old,'IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id='||variable||')
            OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id='||variable||') THEN');
    END LOOP;
    definition:=pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::regprocedure);
    old:='    quota_now := pg_catalog.CLOCK_TIMESTAMP();';
    IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'history_identity_source_drift'; END IF;
    EXECUTE replace(definition,old,$new$    IF EXISTS(SELECT 1 FROM internal.observation_analysis_results
        WHERE analysis_id=p_original_analysis_id AND evidence_manifest->'schema_version'='3'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_admission_required' USING ERRCODE='55000';
    END IF;
$new$||old);
END;
$patch$;

-- Imported children have no intent erasure trigger. Preserve their ID fence on
-- every history cascade too, without retaining owner/private snapshot data.
CREATE FUNCTION internal.fence_imported_observation_result()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF OLD.evidence_manifest->'schema_version'='3'::JSONB THEN
        INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)
            VALUES(OLD.analysis_id,NULL,pg_catalog.now()) ON CONFLICT(scan_id) DO NOTHING;
    END IF;
    RETURN OLD;
END;
$$;
REVOKE ALL ON FUNCTION internal.fence_imported_observation_result() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER fence_imported_observation_result BEFORE DELETE ON internal.observation_analysis_results
    FOR EACH ROW EXECUTE FUNCTION internal.fence_imported_observation_result();

COMMENT ON FUNCTION public.enroll_owned_observation_history(UUID,INTEGER) IS
    'Release-held protocol 9 saved baseline import. No auto-selection on replay, no claim of original completion, no media copy or funding. Authority sync and all RFC gates remain prerequisites.';
COMMENT ON FUNCTION public.get_owned_observation_analysis_page(JSONB,INTEGER) IS
    'Default-off owner read: protocol 7 V1, protocol 8 V1/V2, protocol 9 V1/V2/imported V3. Old readers reject whole unsupported histories.';
RESET statement_timeout;
RESET lock_timeout;
