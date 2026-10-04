SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN rejection_api_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE internal.observation_review_receipts (
    observation_id UUID NOT NULL,
    analysis_id UUID NOT NULL,
    operation_id UUID NOT NULL,
    request_identity JSONB NOT NULL CHECK (pg_catalog.octet_length(request_identity::TEXT)<=2048),
    receipt JSONB NOT NULL CHECK (pg_catalog.octet_length(receipt::TEXT)<=4096),
    PRIMARY KEY(observation_id,operation_id),
    FOREIGN KEY(observation_id,analysis_id)
        REFERENCES internal.observation_analysis_results(observation_id,analysis_id) ON DELETE CASCADE
);
ALTER TABLE internal.observation_review_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_review_receipts FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_review_generation BEFORE INSERT OR UPDATE ON internal.observation_review_receipts
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_observation_review_receipt_update BEFORE UPDATE ON internal.observation_review_receipts
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

-- Reject/Undo only. Confirmation needs a separately admitted, analysis-bound
-- verified taxon; legacy scan confirmation must never authorize this child.
CREATE FUNCTION public.review_owned_observation_analysis(p_request JSONB,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE
    caller UUID := auth.uid(); observation UUID; target UUID; operation UUID;
    expected_revision INTEGER; expected_review INTEGER;
    history internal.observation_histories; evidence internal.observation_analysis_results;
    authority internal.observation_analysis_authorities; saved internal.observation_review_receipts;
    prior_rejection internal.observation_review_receipts;
    response JSONB; review JSONB; next_authority JSONB; origin JSONB; ai_revision INTEGER; species_revision INTEGER;
BEGIN
    IF caller IS NULL OR p_reader IS DISTINCT FROM 9 OR pg_catalog.octet_length(p_request::TEXT) > 2048 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF pg_catalog.JSONB_TYPEOF(p_request) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    IF (SELECT pg_catalog.COUNT(*) FROM pg_catalog.JSONB_OBJECT_KEYS(p_request)) <> 8
        OR NOT p_request ?& ARRAY['schema_version','observation_id','analysis_id','operation_id','expected_observation_revision','expected_review_revision','action','undo_operation_id']
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
    IF p_request->>'action' NOT IN ('reject','undo') OR p_request->>'action' IS NULL
        OR (p_request->>'action'='reject' AND p_request->'undo_operation_id' IS DISTINCT FROM 'null'::JSONB)
        OR (p_request->>'action'='undo' AND COALESCE(p_request->>'undo_operation_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    observation := (p_request ->> 'observation_id')::UUID;
    target := (p_request ->> 'analysis_id')::UUID;
    operation := (p_request ->> 'operation_id')::UUID;
    expected_revision := (p_request ->> 'expected_observation_revision')::INTEGER;
    expected_review := (p_request ->> 'expected_review_revision')::INTEGER;


    PERFORM users.id FROM public.users AS users WHERE users.id=caller FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||observation::TEXT,0::BIGINT));
    PERFORM scans.id FROM public.scans AS scans WHERE scans.id=observation AND scans.user_id=caller AND NOT scans.is_tombstoned FOR UPDATE;
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
        RETURN saved.receipt;
    END IF;
    IF (SELECT rejection_api_enabled AND reader_enabled AND state_reader_enabled
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
        -- Validate the exact stored authority before deriving any transition.
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
            OR authority.review_snapshot->>'user_review_state'='user_overridden'
            OR NULLIF(review->'community','null'::JSONB) IS NOT NULL THEN
            RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
        END IF;
        IF p_request->>'action'='reject' THEN
            IF COALESCE(review->>'state','clear')<>'clear' THEN
                RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
            END IF;
            origin := pg_catalog.jsonb_build_object('scientific_name',evidence.result_snapshot#>>'{primary_identification,scientific_name}',
                'common_name',evidence.result_snapshot#>>'{primary_identification,common_name}');
            IF NULLIF(evidence.result_snapshot->'primary_identification','null'::JSONB) IS NULL THEN
                SELECT pg_catalog.jsonb_build_object('scientific_name',scientific_name,'common_name',common_names->>'en') INTO origin
                FROM public.species_dictionary WHERE id=(evidence.result_snapshot->>'species_id')::UUID;
            END IF;
        ELSE
            -- Undo names an acknowledged rejection, and both CAS revisions must
            -- still match. It clears rejection; it never recreates confirmation.
            SELECT * INTO prior_rejection FROM internal.observation_review_receipts
            WHERE observation_id=observation AND analysis_id=target AND operation_id=(p_request->>'undo_operation_id')::UUID;
            IF NOT FOUND OR prior_rejection.request_identity->>'action'<>'reject'
                OR prior_rejection.receipt->>'outcome'<>'applied'
                OR prior_rejection.receipt->>'review_revision'<>expected_review::TEXT
                OR review->>'state' IS DISTINCT FROM 'ai_rejected'
                OR review->>'operation_id' IS DISTINCT FROM p_request->>'undo_operation_id' THEN
                RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
            END IF;
            origin := review->'origin_identification';
        END IF;
        review := pg_catalog.jsonb_build_object('version',1,'revision',ai_revision+1,
            'state',CASE WHEN p_request->>'action'='reject' THEN 'ai_rejected' ELSE 'clear' END,
            'origin_scan_id',observation,'origin_identification',origin,'operation_id',operation,
            'operation_digest',pg_catalog.md5(p_request::TEXT),'community',NULL);
        next_authority := pg_catalog.jsonb_build_object('ai_identification_review',review,
            'confirmed_species_identity',NULL,'confirmed_species_identity_revision',species_revision+1,
            'confirmed_species_id',NULL,'user_identification_override',NULL,
            'user_confirmed_identification',FALSE,'user_review_state','unreviewed');
        UPDATE internal.observation_analysis_authorities SET review_revision=expected_review+1,review_snapshot=next_authority
            WHERE observation_id=observation AND analysis_id=target;
        -- The existing authority trigger atomically advances the parent, updates
        -- its projection only for the selected child, and enqueues reconciliation.
        response := p_request || pg_catalog.jsonb_build_object('outcome','applied',
            'observation_revision',history.state_revision+1,'review_revision',expected_review+1);
    END IF;
    INSERT INTO internal.observation_review_receipts(observation_id,analysis_id,operation_id,request_identity,receipt)
        VALUES(observation,target,operation,p_request,response);
    RETURN response;
END;
$$;
REVOKE ALL ON FUNCTION public.review_owned_observation_analysis(JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.review_owned_observation_analysis(JSONB,INTEGER) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('authenticated','public.review_owned_observation_analysis(jsonb,integer)',
     'Default-off protocol 9 owner Reject/Undo bound to a child analysis and both revisions, with immutable operation outcomes.');

-- Legacy Edge preflight and authoritative commit share this owner/generation
-- fence. A preflight alone cannot protect against enrollment during verification.
CREATE FUNCTION internal.require_unenrolled_review_target(p_user_id UUID,p_scan_id UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM users.id FROM public.users AS users WHERE users.id=p_user_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'identification_review_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_scan_id::TEXT,0::BIGINT));
    -- Owner and generation locks serialize enrollment/deletion. Commit routines
    -- acquire their established scan/request row locks afterwards; taking the
    -- scan here would invert community's request-before-scan order.
    PERFORM scans.id FROM public.scans AS scans WHERE scans.id=p_scan_id AND scans.user_id=p_user_id AND NOT scans.is_tombstoned;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan_id) THEN
        RAISE EXCEPTION 'identification_review_not_found' USING ERRCODE='P0002';
    END IF;
    IF EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=p_scan_id) THEN
        RAISE EXCEPTION 'analysis_bound_review_required' USING ERRCODE='55000';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.require_unenrolled_review_target(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.require_legacy_scan_review(p_user_id UUID,p_scan_id UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.require_unenrolled_review_target(p_user_id,p_scan_id);
END;
$$;
REVOKE ALL ON FUNCTION public.require_legacy_scan_review(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.require_legacy_scan_review(UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.require_legacy_scan_review(uuid,uuid)','Owner-bound legacy review preflight before quota or taxonomy verification; commit repeats the guard.');

-- Keep the established state machines byte-for-byte except for the entry guard.
DO $patch$
DECLARE definition TEXT; old TEXT; signature TEXT;
BEGIN
    FOREACH signature IN ARRAY ARRAY[
        'public.apply_scan_identification_review(uuid,uuid,integer,uuid,text,text,jsonb,integer,uuid,integer)',
        'public.apply_verified_scan_species_review(uuid,uuid,integer,text,text,jsonb)'] LOOP
        definition := pg_catalog.pg_get_functiondef(signature::REGPROCEDURE);
        old := CASE WHEN signature LIKE 'public.apply_scan_identification_review(%'
            THEN E'    IF p_action = ''carry'' THEN\n        PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK('
            ELSE '    -- Same generation fence as finalization, recovery and deletion; no network' END;
        IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN
            RAISE EXCEPTION 'legacy_review_source_drift';
        END IF;
        IF signature LIKE 'public.apply_scan_identification_review(%' THEN
            EXECUTE replace(definition,old,$guard$
    IF p_action='carry' AND p_source_scan_id IS NOT NULL THEN
        PERFORM internal.require_unenrolled_review_target(p_user_id,LEAST(p_scan_id,p_source_scan_id));
        PERFORM internal.require_unenrolled_review_target(p_user_id,GREATEST(p_scan_id,p_source_scan_id));
    ELSE
        PERFORM internal.require_unenrolled_review_target(p_user_id,p_scan_id);
    END IF;
$guard$||old);
        ELSE
            EXECUTE replace(definition,old,E'    PERFORM internal.require_unenrolled_review_target(p_user_id,p_scan_id);\n'||old);
        END IF;
    END LOOP;
END;
$patch$;

-- Acquire owner/generation locks before any Community request/scan lock or
-- publication. A late insert trigger cannot establish this order: requested_by
-- FK validation itself can wait on the owner's row lock.
DO $community$
DECLARE definition TEXT; old TEXT := '    -- Consensus processing locks request -> scan.';
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.request_community_identification_atomically(uuid,uuid,text,text,text,jsonb,uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN
        RAISE EXCEPTION 'community_review_source_drift';
    END IF;
    EXECUTE replace(definition,old,E'    PERFORM public.require_legacy_scan_review(p_user_id,p_scan_id);\n'||old);
END;
$community$;

-- Also fence direct/legacy community authority projection. Never copy mutable
-- public.scans review into whichever private child happens to be selected.
CREATE FUNCTION internal.guard_enrolled_scan_review()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    -- Account detachment/explicit deletion must retain their existing cleanup path.
    IF NEW.user_id IS NULL OR NEW.is_tombstoned OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=NEW.id) THEN RETURN NEW; END IF;
    IF ROW(NEW.ai_identification_review,NEW.confirmed_species_identity,NEW.confirmed_species_identity_revision,
        NEW.confirmed_species_id,NEW.user_identification_override,NEW.user_confirmed_identification,NEW.user_review_state)
        IS DISTINCT FROM ROW(OLD.ai_identification_review,OLD.confirmed_species_identity,OLD.confirmed_species_identity_revision,
        OLD.confirmed_species_id,OLD.user_identification_override,OLD.user_confirmed_identification,OLD.user_review_state)
        AND EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=NEW.id) THEN
        RAISE EXCEPTION 'analysis_bound_review_required' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_enrolled_scan_review() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER z_guard_enrolled_scan_review BEFORE UPDATE ON public.scans
FOR EACH ROW EXECUTE FUNCTION internal.guard_enrolled_scan_review();

CREATE FUNCTION internal.guard_enrolled_community_request()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF TG_OP='UPDATE' AND OLD.scan_id IS DISTINCT FROM NEW.scan_id THEN
        -- Reparenting must not move a request out of protected history either.
        -- Lock both observations in UUID order for direct reparent writers.
        PERFORM scans.id FROM public.scans AS scans WHERE scans.id IN (OLD.scan_id,NEW.scan_id) ORDER BY scans.id FOR UPDATE;
        IF EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id IN (OLD.scan_id,NEW.scan_id)) THEN
            RAISE EXCEPTION 'analysis_bound_review_required' USING ERRCODE='55000';
        END IF;
        IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.scan_id)
            OR EXISTS(SELECT 1 FROM public.scans WHERE id=OLD.scan_id AND is_tombstoned) THEN
            RAISE EXCEPTION 'identification_review_not_found' USING ERRCODE='P0002';
        END IF;
    END IF;
    -- Existing community writers already hold scan/request row locks. Do not
    -- acquire owner/advisory locks here: that would invert the global order.
    -- Enrollment needs this same scan row before creating history, so this row
    -- lock alone serializes the membership check without a higher-order lock.
    PERFORM scans.id FROM public.scans AS scans WHERE scans.id=NEW.scan_id AND NOT scans.is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=NEW.scan_id) THEN
        RAISE EXCEPTION 'identification_review_not_found' USING ERRCODE='P0002';
    END IF;
    IF EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=NEW.scan_id) THEN
        RAISE EXCEPTION 'analysis_bound_review_required' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_enrolled_community_request() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_enrolled_community_request BEFORE INSERT OR UPDATE OF scan_id,status,resolved_taxon_node_id,withdrawn_at ON public.explore_community_requests
FOR EACH ROW EXECUTE FUNCTION internal.guard_enrolled_community_request();

COMMENT ON FUNCTION public.review_owned_observation_analysis(JSONB,INTEGER) IS
    'Prepared Reject/Undo only. Exact replay is historical proof, never current state; read protocol 9 state after every outcome. Confirmation, community authority and native admission remain held.';
RESET statement_timeout;
RESET lock_timeout;
