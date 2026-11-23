SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Pre-admission preparation only. No funding, ingestion job or provider claim.
-- The fixed private capture-stage/v1 namespace is disjoint from History objects.
CREATE TABLE internal.initial_capture_audio_stages (
    scan_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    generation UUID NOT NULL UNIQUE,
    attempt_id UUID NOT NULL UNIQUE,
    backend_sha256 TEXT NOT NULL CHECK (backend_sha256 ~ '^[0-9a-f]{64}$'),
    request_sha256 TEXT NOT NULL CHECK (request_sha256 ~ '^[0-9a-f]{64}$'),
    request_body JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    bound_at TIMESTAMPTZ,
    retired_at TIMESTAMPTZ,
    CHECK ((request_body IS NULL) = (retired_at IS NOT NULL))
);
CREATE INDEX initial_capture_audio_stages_owner ON internal.initial_capture_audio_stages(owner_id);
CREATE TABLE internal.initial_capture_audio_stage_objects (
    object_id UUID PRIMARY KEY,
    scan_id UUID NOT NULL REFERENCES internal.initial_capture_audio_stages(scan_id),
    media_id UUID NOT NULL UNIQUE,
    position INTEGER NOT NULL CHECK(position BETWEEN 0 AND 1),
    artifact JSONB,
    write_issued_at TIMESTAMPTZ,
    ready_at TIMESTAMPTZ,
    UNIQUE(scan_id,position),
    CHECK(write_issued_at IS NULL OR artifact IS NOT NULL),
    CHECK(ready_at IS NULL OR write_issued_at IS NOT NULL)
);
-- Permanent opaque no-reuse and marker obligation; no owner/scan FK cascade.
CREATE TABLE internal.initial_capture_audio_stage_erasure (
    object_id UUID PRIMARY KEY,
    backend_sha256 TEXT NOT NULL CHECK (backend_sha256 ~ '^[0-9a-f]{64}$'),
    available_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    claim_token UUID,
    claim_expires_at TIMESTAMPTZ,
    erased_at TIMESTAMPTZ,
    CHECK((claim_token IS NULL) = (claim_expires_at IS NULL))
);
CREATE INDEX initial_capture_audio_stage_erasure_due ON internal.initial_capture_audio_stage_erasure(available_at,object_id) WHERE erased_at IS NULL;
ALTER TABLE internal.initial_capture_audio_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_capture_audio_stage_objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_capture_audio_stage_erasure ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_capture_audio_stages,internal.initial_capture_audio_stage_objects,internal.initial_capture_audio_stage_erasure FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_capture_audio_stage_receipt(p_scan UUID)
RETURNS JSONB LANGUAGE SQL STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT jsonb_build_object('request_sha256',s.request_sha256,'attempt_id',s.attempt_id,
    'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('object_id',o.object_id,'media_id',o.media_id,
        'artifact',o.artifact,'ready',o.ready_at IS NOT NULL) ORDER BY o.position)
        FROM internal.initial_capture_audio_stage_objects o WHERE o.scan_id=s.scan_id),'[]'::JSONB))
 FROM internal.initial_capture_audio_stages s WHERE s.scan_id=p_scan AND s.retired_at IS NULL;
$$;

-- The canonical text is hashed as UTF8, not jsonb::text (whose spacing/key order
-- differs from the Edge canonical serializer). Both hash AND parsed full body
-- must match on replay. No client body can mint this service-only authority.
CREATE FUNCTION public.initial_capture_audio_stage_action(
    p_request TEXT,p_sha256 TEXT,p_backend TEXT,p_action TEXT,p_attempt UUID,p_artifacts JSONB,p_object UUID
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE body JSONB; contract JSONB; owner UUID; scan UUID; generation UUID;
    saved internal.initial_capture_audio_stages; candidate UUID; item JSONB; n INTEGER; obj internal.initial_capture_audio_stage_objects;
BEGIN
    PERFORM internal.require_service_role();
    IF p_request IS NULL OR octet_length(p_request)>1044480 OR p_sha256 IS NULL
        OR p_sha256 !~ '^[0-9a-f]{64}$' OR p_backend IS NULL OR p_backend !~ '^[0-9a-f]{64}$'
        OR encode(extensions.digest(convert_to(p_request,'UTF8'),'sha256'),'hex') IS DISTINCT FROM p_sha256
        OR p_action IS NULL OR p_action NOT IN ('reserve','bind','read','write','complete') THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    body:=p_request::JSONB;
    IF jsonb_typeof(body) IS DISTINCT FROM 'object' OR NOT(body ?& ARRAY['owner_id','plan','recipe'])
        OR body-ARRAY['owner_id','plan','recipe']<>'{}'
        OR jsonb_typeof(body->'owner_id') IS DISTINCT FROM 'string'
        OR body->>'owner_id' !~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
        OR body->>'recipe' IS DISTINCT FROM 'mono-pcm16-16000-trim-bandlimited-v1' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    owner:=(body->>'owner_id')::UUID;
    contract:=internal.initial_capture_plan_contract(owner,body->'plan');
    scan:=(contract->>'scan_id')::UUID; generation:=(contract->>'generation')::UUID;
    IF jsonb_array_length(contract->'audio') NOT BETWEEN 1 AND 2
        OR (p_action IN ('reserve','bind') AND (p_attempt IS NULL OR p_attempt IN(owner,scan,generation)
          OR EXISTS(SELECT 1 FROM jsonb_array_elements(contract->'uploads') x WHERE x->>'media_id'=p_attempt::TEXT)
          OR EXISTS(SELECT 1 FROM jsonb_array_elements(contract->'audio') x WHERE x->>'prepared_media_id'=p_attempt::TEXT)))
        OR (p_action='reserve' AND (p_artifacts IS NOT NULL OR p_object IS NOT NULL))
        OR (p_action='bind' AND p_object IS NOT NULL)
        OR (p_action IN ('read','write','complete') AND (p_attempt IS NOT NULL OR p_object IS NULL)) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-capture-account-retirement:'||owner::TEXT,0));
    PERFORM id FROM public.users WHERE id=owner FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=owner) THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||scan::TEXT,0));
    IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=scan)
        OR EXISTS(SELECT 1 FROM public.scans WHERE id=scan AND (user_id<>owner OR is_tombstoned))
        OR EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id=scan) THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO saved FROM internal.initial_capture_audio_stages WHERE scan_id=scan FOR UPDATE;
    IF FOUND THEN
        IF saved.owner_id<>owner OR saved.generation<>generation OR saved.backend_sha256<>p_backend
            OR saved.request_sha256<>p_sha256 OR saved.request_body IS DISTINCT FROM body OR saved.retired_at IS NOT NULL THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='55000';
        END IF;
    ELSE
        IF p_action<>'reserve' OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=scan::TEXT)
            OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE scan_id=scan::TEXT)
            OR EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id=scan)
            OR EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id=scan) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='55000';
        END IF;
        INSERT INTO internal.initial_capture_audio_stages(scan_id,owner_id,generation,attempt_id,backend_sha256,request_sha256,request_body)
            VALUES(scan,owner,generation,p_attempt,p_backend,p_sha256,body) RETURNING * INTO saved;
        n:=0;
        FOR item IN SELECT value FROM jsonb_array_elements(contract->'audio') LOOP
            FOR attempt IN 1..4 LOOP
                candidate:=gen_random_uuid();
                PERFORM pg_advisory_xact_lock(hashtextextended('merian-capture-stage-object:'||candidate::TEXT,0));
                EXIT WHEN candidate NOT IN(owner,scan,generation,p_attempt)
                    AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(contract->'uploads') x WHERE x->>'media_id'=candidate::TEXT)
                    AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(contract->'audio') x WHERE x->>'prepared_media_id'=candidate::TEXT)
                    AND NOT EXISTS(SELECT 1 FROM internal.initial_capture_audio_stage_objects WHERE object_id=candidate)
                    AND NOT EXISTS(SELECT 1 FROM internal.initial_capture_audio_stage_erasure WHERE object_id=candidate);
                IF attempt=4 THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
            END LOOP;
            INSERT INTO internal.initial_capture_audio_stage_objects(object_id,scan_id,media_id,position)
                VALUES(candidate,scan,(item->>'prepared_media_id')::UUID,n);
            n:=n+1;
        END LOOP;
    END IF;
    IF (SELECT count(*) FROM internal.initial_capture_audio_stage_objects WHERE scan_id=scan)<>jsonb_array_length(contract->'audio') THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    IF p_action='reserve' THEN RETURN internal.initial_capture_audio_stage_receipt(scan); END IF;
    IF p_action='bind' THEN
        IF saved.attempt_id<>p_attempt OR saved.bound_at IS NOT NULL OR jsonb_typeof(p_artifacts) IS DISTINCT FROM 'array'
            OR jsonb_array_length(p_artifacts)<>jsonb_array_length(contract->'audio') THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='55000';
        END IF;
        n:=0;
        FOR item IN SELECT value FROM jsonb_array_elements(p_artifacts) LOOP
            IF jsonb_typeof(item) IS DISTINCT FROM 'object' OR NOT(item ?& ARRAY['media_id','content_type','byte_count','sha256'])
                OR item-ARRAY['media_id','content_type','byte_count','sha256']<>'{}'
                OR item->'media_id' IS DISTINCT FROM contract#>ARRAY['audio',n::TEXT,'prepared_media_id']
                OR item->'content_type' IS DISTINCT FROM '"audio/wav"'::JSONB
                OR jsonb_typeof(item->'byte_count') IS DISTINCT FROM 'number' OR item->>'byte_count' !~ '^[1-9][0-9]{0,6}$'
                OR (item->>'byte_count')::INTEGER NOT BETWEEN 16044 AND 2700000
                OR jsonb_typeof(item->'sha256') IS DISTINCT FROM 'string' OR item->>'sha256' !~ '^[0-9a-f]{64}$' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            UPDATE internal.initial_capture_audio_stage_objects SET artifact=item WHERE scan_id=scan AND position=n;
            n:=n+1;
        END LOOP;
        UPDATE internal.initial_capture_audio_stages SET bound_at=clock_timestamp() WHERE scan_id=scan;
        RETURN internal.initial_capture_audio_stage_receipt(scan);
    END IF;
    SELECT * INTO obj FROM internal.initial_capture_audio_stage_objects WHERE object_id=p_object AND scan_id=scan FOR UPDATE;
    IF NOT FOUND OR saved.bound_at IS NULL OR obj.artifact IS NULL OR obj.artifact IS DISTINCT FROM p_artifacts THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='55000';
    END IF;
    IF p_action='write' THEN
        IF obj.write_issued_at IS NOT NULL THEN RETURN 'false'::JSONB; END IF;
        UPDATE internal.initial_capture_audio_stage_objects SET write_issued_at=clock_timestamp() WHERE object_id=p_object;
        RETURN 'true'::JSONB;
    END IF;
    IF obj.write_issued_at IS NULL THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
    IF p_action='read' THEN RETURN 'true'::JSONB; END IF;
    -- Trusted byte-verifying server attestation, never independent storage proof.
    UPDATE internal.initial_capture_audio_stage_objects SET ready_at=COALESCE(ready_at,clock_timestamp()) WHERE object_id=p_object;
    RETURN internal.initial_capture_audio_stage_receipt(scan);
END;
$$;

-- Metadata retirement records exact opaque marker obligations before erasing the
-- complete source plan. No expiry/absence is used to infer safe abandonment.
CREATE FUNCTION internal.retire_initial_capture_audio_stage(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    INSERT INTO internal.initial_capture_audio_stage_erasure(object_id,backend_sha256)
        SELECT o.object_id,s.backend_sha256 FROM internal.initial_capture_audio_stage_objects o
        JOIN internal.initial_capture_audio_stages s USING(scan_id) WHERE s.scan_id=p_scan
        ON CONFLICT(object_id) DO NOTHING;
    DELETE FROM internal.initial_capture_audio_stage_objects WHERE scan_id=p_scan;
    UPDATE internal.initial_capture_audio_stages SET request_body=NULL,retired_at=COALESCE(retired_at,clock_timestamp()) WHERE scan_id=p_scan;
END;
$$;
CREATE FUNCTION internal.retire_initial_capture_audio_stages_for_deletion()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE target UUID; scan UUID;
BEGIN
    IF TG_TABLE_NAME='scan_deletion_tombstones' THEN
        PERFORM internal.retire_initial_capture_audio_stage(NEW.scan_id); RETURN NEW;
    END IF;
    target:=CASE WHEN TG_TABLE_NAME='users' THEN OLD.id ELSE NEW.user_id END;
    -- Deletion intake already owns the account fence/owner; do not acquire it
    -- after child-row locks. Reserve/bind cannot cross the existing owner fence.
    FOR scan IN SELECT scan_id FROM internal.initial_capture_audio_stages WHERE owner_id=target ORDER BY scan_id LOOP
        PERFORM internal.retire_initial_capture_audio_stage(scan);
    END LOOP;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END;
$$;
CREATE TRIGGER retire_initial_capture_audio_stage AFTER INSERT ON internal.scan_deletion_tombstones
    FOR EACH ROW EXECUTE FUNCTION internal.retire_initial_capture_audio_stages_for_deletion();
CREATE TRIGGER retire_initial_capture_audio_stage AFTER INSERT ON internal.account_deletion_jobs
    FOR EACH ROW EXECUTE FUNCTION internal.retire_initial_capture_audio_stages_for_deletion();
CREATE TRIGGER retire_initial_capture_audio_stage BEFORE DELETE ON public.users
    FOR EACH ROW EXECUTE FUNCTION internal.retire_initial_capture_audio_stages_for_deletion();

-- Identity merge has both owner rows already. Retire prospective pre-admission
-- stages too: they need not have a public scan or ingestion job yet.
DO $merge$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    definition:=pg_get_functiondef('internal.prepare_scan_ingestions_for_identity_merge(uuid,uuid)'::regprocedure);
    anchor:='    -- The caller already holds both profile rows';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'capture_stage_merge_drift'; END IF;
    EXECUTE replace(definition,anchor,$body$
    PERFORM internal.retire_initial_capture_audio_stage(s.scan_id)
        FROM internal.initial_capture_audio_stages s WHERE s.owner_id=p_source_user_id ORDER BY s.scan_id;
$body$||anchor);
END;
$merge$;

REVOKE ALL ON FUNCTION internal.initial_capture_audio_stage_receipt(UUID),
    internal.retire_initial_capture_audio_stage(UUID),internal.retire_initial_capture_audio_stages_for_deletion()
    FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.initial_capture_audio_stage_action(TEXT,TEXT,TEXT,TEXT,UUID,JSONB,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.initial_capture_audio_stage_action(TEXT,TEXT,TEXT,TEXT,UUID,JSONB,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.initial_capture_audio_stage_action(text,text,text,text,uuid,jsonb,uuid)',
    'Private pre-admission audio stage reservation, immutable output binding, one-shot write and verified readback attestation; no funding or ingestion authority.');

RESET statement_timeout;
RESET lock_timeout;
