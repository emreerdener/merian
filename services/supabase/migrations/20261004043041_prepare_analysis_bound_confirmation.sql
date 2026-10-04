SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN confirmation_api_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- An interrupted lookup must resume the same intent and verification name.
CREATE TABLE internal.observation_confirmation_intents (
    observation_id UUID NOT NULL,
    analysis_id UUID NOT NULL,
    operation_id UUID NOT NULL,
    request_identity JSONB NOT NULL CHECK (pg_catalog.octet_length(request_identity::TEXT)<=2048),
    scientific_name TEXT NOT NULL CHECK (length(scientific_name) BETWEEN 1 AND 160),
    PRIMARY KEY(observation_id,operation_id),
    FOREIGN KEY(observation_id,analysis_id)
        REFERENCES internal.observation_analysis_results(observation_id,analysis_id) ON DELETE CASCADE
);
ALTER TABLE internal.observation_confirmation_intents ENABLE ROW LEVEL SECURITY;
CREATE INDEX observation_confirmation_intents_analysis_idx ON internal.observation_confirmation_intents(observation_id,analysis_id);
REVOKE ALL ON internal.observation_confirmation_intents FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_confirmation_generation BEFORE INSERT OR UPDATE ON internal.observation_confirmation_intents
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_observation_confirmation_intent_update BEFORE UPDATE ON internal.observation_confirmation_intents
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

-- Reject/Undo and confirmation share operation UUIDs, including unfinished intents.
-- Supported writers already hold the observation's owner/generation/history locks.
CREATE FUNCTION internal.guard_observation_review_intent()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF EXISTS(SELECT 1 FROM internal.observation_confirmation_intents
        WHERE observation_id=NEW.observation_id AND operation_id=NEW.operation_id
        AND request_identity IS DISTINCT FROM NEW.request_identity) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_observation_review_intent() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_review_intent BEFORE INSERT ON internal.observation_review_receipts
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_review_intent();

-- Both phases use one lock/authorization/identity implementation. Network lookup
-- happens between transactions. Completion always rechecks current authority.
CREATE FUNCTION internal.confirm_observation_analysis(
    p_user_id UUID,p_request JSONB,p_reader INTEGER,p_complete BOOLEAN,
    p_verified_name TEXT,p_taxon JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE
    observation UUID; target UUID; operation UUID;
    expected_revision INTEGER; expected_review INTEGER;
    history internal.observation_histories; evidence internal.observation_analysis_results;
    authority internal.observation_analysis_authorities; saved internal.observation_review_receipts;
    intent internal.observation_confirmation_intents;
    response JSONB; review JSONB; next_authority JSONB; origin JSONB;
    ai_revision INTEGER; species_revision INTEGER; name TEXT;
    species UUID; saved_name TEXT; identity JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF p_user_id IS NULL OR p_reader IS DISTINCT FROM 9 OR pg_catalog.octet_length(p_request::TEXT) > 2048 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF pg_catalog.JSONB_TYPEOF(p_request) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    IF (SELECT pg_catalog.COUNT(*) FROM pg_catalog.JSONB_OBJECT_KEYS(p_request)) <> 8
        OR NOT p_request ?& ARRAY['schema_version','observation_id','analysis_id','operation_id','expected_observation_revision','expected_review_revision','action','scientific_name']
        OR p_request -> 'schema_version' IS DISTINCT FROM '1'::JSONB
        OR COALESCE(p_request ->> 'observation_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR COALESCE(p_request ->> 'analysis_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR COALESCE(p_request ->> 'operation_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'expected_observation_revision') IS DISTINCT FROM 'number'
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'expected_review_revision') IS DISTINCT FROM 'number'
        OR COALESCE(p_request ->> 'expected_observation_revision','') !~ '^[0-9]{1,10}$'
        OR COALESCE(p_request ->> 'expected_review_revision','') !~ '^[0-9]{1,10}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    IF (p_request ->> 'expected_observation_revision')::BIGINT > 2147483646
        OR (p_request ->> 'expected_review_revision')::BIGINT > 2147483646 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    IF p_request->>'action' NOT IN ('confirm_primary','confirm_name') OR p_request->>'action' IS NULL
        OR (p_request->>'action'='confirm_primary' AND p_request->'scientific_name' IS DISTINCT FROM 'null'::JSONB)
        OR (p_request->>'action'='confirm_name' AND (
            pg_catalog.jsonb_typeof(p_request->'scientific_name') IS DISTINCT FROM 'string'
            OR length(p_request->>'scientific_name') NOT BETWEEN 1 AND 160
            OR btrim(p_request->>'scientific_name') IS DISTINCT FROM p_request->>'scientific_name'
            OR p_request->>'scientific_name' ~ '[[:cntrl:]]')) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    observation := (p_request ->> 'observation_id')::UUID;
    target := (p_request ->> 'analysis_id')::UUID;
    operation := (p_request ->> 'operation_id')::UUID;
    expected_revision := (p_request ->> 'expected_observation_revision')::INTEGER;
    expected_review := (p_request ->> 'expected_review_revision')::INTEGER;


    PERFORM users.id FROM public.users AS users WHERE users.id=p_user_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||observation::TEXT,0::BIGINT));
    PERFORM scans.id FROM public.scans AS scans WHERE scans.id=observation AND scans.user_id=p_user_id AND NOT scans.is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO saved FROM internal.observation_review_receipts WHERE observation_id=observation AND operation_id=operation;
    IF FOUND THEN
        IF saved.request_identity IS DISTINCT FROM p_request THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN pg_catalog.jsonb_build_object('schema_version',1,'status','complete','receipt',saved.receipt);
    END IF;
    SELECT * INTO intent FROM internal.observation_confirmation_intents WHERE observation_id=observation AND operation_id=operation;
    IF FOUND AND intent.request_identity IS DISTINCT FROM p_request THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF p_complete AND intent.operation_id IS NULL THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    IF (SELECT confirmation_api_enabled AND reader_enabled AND state_reader_enabled
        FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO evidence FROM internal.observation_analysis_results WHERE observation_id=observation AND analysis_id=target;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO authority FROM internal.observation_analysis_authorities WHERE observation_id=observation AND analysis_id=target FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
    response := p_request || pg_catalog.jsonb_build_object('outcome','revision_conflict');
    IF history.selection_initialized AND history.state_revision=expected_revision AND authority.review_revision=expected_review THEN
        IF history.state_revision>=2147483646 OR authority.review_revision>=2147483646 THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
        END IF;
        IF NOT authority.review_snapshot ?& ARRAY['ai_identification_review','confirmed_species_identity',
            'confirmed_species_identity_revision','confirmed_species_id','user_identification_override','user_confirmed_identification','user_review_state']
            OR authority.review_snapshot-ARRAY['ai_identification_review','confirmed_species_identity',
            'confirmed_species_identity_revision','confirmed_species_id','user_identification_override','user_confirmed_identification','user_review_state']<>'{}'::JSONB THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
        END IF;
        PERFORM internal.observation_analysis_projection(evidence.result_snapshot,authority.review_snapshot);
        review := NULLIF(authority.review_snapshot->'ai_identification_review','null'::JSONB);
        ai_revision := COALESCE((review->>'revision')::INTEGER,0);
        species_revision := (authority.review_snapshot->>'confirmed_species_identity_revision')::INTEGER;
        IF ai_revision>=999999999 OR species_revision IS NULL OR species_revision>=2147483646 THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
        END IF;
        IF evidence.result_snapshot->'is_biological_subject' IS DISTINCT FROM 'true'::JSONB
            OR NULLIF(review->'community','null'::JSONB) IS NOT NULL THEN
            RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
        END IF;
        IF NULLIF(evidence.result_snapshot->'primary_identification','null'::JSONB) IS NULL THEN
            RAISE EXCEPTION 'species_review_requires_primary' USING ERRCODE='22023';
        END IF;
        IF p_request->>'action'='confirm_primary' THEN
            IF evidence.result_snapshot#>>'{primary_identification,resolution}' IS DISTINCT FROM 'species' THEN
                RAISE EXCEPTION 'species_review_primary_not_species' USING ERRCODE='22023';
            END IF;
            name := evidence.result_snapshot#>>'{primary_identification,scientific_name}';
        ELSE
            name := p_request->>'scientific_name';
        END IF;
        IF name IS NULL OR length(name) NOT BETWEEN 1 AND 160 OR btrim(name)<>name OR name ~ '[[:cntrl:]]' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        IF intent.operation_id IS NOT NULL AND intent.scientific_name IS DISTINCT FROM name THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        IF NOT p_complete THEN
            INSERT INTO internal.observation_confirmation_intents(observation_id,analysis_id,operation_id,request_identity,scientific_name)
                VALUES(observation,target,operation,p_request,name) ON CONFLICT(observation_id,operation_id) DO NOTHING;
            RETURN pg_catalog.jsonb_build_object('schema_version',1,'status','verify','request',p_request,'scientific_name',name);
        END IF;
        IF p_verified_name IS DISTINCT FROM intent.scientific_name THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        IF p_taxon IS NULL THEN
            response := p_request || pg_catalog.jsonb_build_object('outcome','not_verified');
        ELSE
            -- Only the service endpoint supplies freshly verified proof. A synonym's
            -- accepted canonical name may legitimately differ from the frozen query.
            species := public.resolve_verified_dictionary_species(p_taxon);
            SELECT scientific_name INTO STRICT saved_name FROM public.species_dictionary
                WHERE id=species AND is_public_biological AND gbif_taxon_key=(p_taxon->>'gbif_taxon_key')::INTEGER FOR SHARE;
            identity := pg_catalog.jsonb_build_object('version',1,'species_id',species,
                'scientific_name',saved_name,'common_name',NULL,'gbif_taxon_key',p_taxon->'gbif_taxon_key');
            IF NOT internal.confirmed_species_identity_is_valid(identity) THEN
                RAISE EXCEPTION 'invalid_verified_species' USING ERRCODE='22023';
            END IF;
            origin := COALESCE(review->'origin_identification',pg_catalog.jsonb_build_object(
                'scientific_name',evidence.result_snapshot#>>'{primary_identification,scientific_name}',
                'common_name',evidence.result_snapshot#>>'{primary_identification,common_name}'));
            -- Explicit acceptance clears rejection of this child only. Selection
            -- never invokes this transition or transfers another child's review.
            review := pg_catalog.jsonb_build_object('version',1,'revision',ai_revision+1,'state','clear',
                'origin_scan_id',COALESCE(review->>'origin_scan_id',observation::TEXT),
                'origin_identification',origin,'operation_id',operation,
                'operation_digest',pg_catalog.md5(p_request::TEXT),'community',NULL);
            next_authority := pg_catalog.jsonb_build_object('ai_identification_review',review,
                'confirmed_species_identity',identity,'confirmed_species_identity_revision',species_revision+1,
                'confirmed_species_id',species,
                'user_identification_override',CASE WHEN p_request->>'action'='confirm_name' THEN name ELSE NULL END,
                'user_confirmed_identification',p_request->>'action'='confirm_primary',
                'user_review_state',CASE WHEN p_request->>'action'='confirm_primary' THEN 'ai_confirmed' ELSE 'user_overridden' END);
            PERFORM internal.observation_analysis_projection(evidence.result_snapshot,next_authority);
            UPDATE internal.observation_analysis_authorities SET review_revision=expected_review+1,review_snapshot=next_authority
                WHERE observation_id=observation AND analysis_id=target;
            response := p_request || pg_catalog.jsonb_build_object('outcome','applied',
                'observation_revision',history.state_revision+1,'review_revision',expected_review+1);
        END IF;
    END IF;
    INSERT INTO internal.observation_review_receipts(observation_id,analysis_id,operation_id,request_identity,receipt)
        VALUES(observation,target,operation,p_request,response);
    RETURN pg_catalog.jsonb_build_object('schema_version',1,'status','complete','receipt',response);
END;
$$;
REVOKE ALL ON FUNCTION internal.confirm_observation_analysis(UUID,JSONB,INTEGER,BOOLEAN,TEXT,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.prepare_observation_analysis_confirmation(p_user_id UUID,p_request JSONB,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    RETURN internal.confirm_observation_analysis(p_user_id,p_request,p_reader,FALSE,NULL,NULL);
END;
$$;
CREATE FUNCTION public.complete_observation_analysis_confirmation(p_user_id UUID,p_request JSONB,p_reader INTEGER,p_verified_name TEXT,p_taxon JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    RETURN internal.confirm_observation_analysis(p_user_id,p_request,p_reader,TRUE,p_verified_name,p_taxon);
END;
$$;
REVOKE ALL ON FUNCTION public.prepare_observation_analysis_confirmation(UUID,JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.complete_observation_analysis_confirmation(UUID,JSONB,INTEGER,TEXT,JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_observation_analysis_confirmation(UUID,JSONB,INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_observation_analysis_confirmation(UUID,JSONB,INTEGER,TEXT,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.prepare_observation_analysis_confirmation(uuid,jsonb,integer)','Closed-gate owner-bound immutable confirmation admission or completed replay before taxonomy lookup.'),
    ('service_role','public.complete_observation_analysis_confirmation(uuid,jsonb,integer,text,jsonb)','Complete admitted analysis confirmation with verified species proof and both current revisions.');

RESET statement_timeout;
RESET lock_timeout;
NOTIFY pgrst, 'reload schema';
