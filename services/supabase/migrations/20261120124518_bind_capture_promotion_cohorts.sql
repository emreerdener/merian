SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- A durable logical request is not the replaceable ingestion job row. Keep the
-- exact cohort after job/intent/source deletion; no cascade or backfill is safe.
CREATE TABLE internal.capture_promotion_cohorts (
    cohort_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    scan_id UUID NOT NULL,
    consumer TEXT NOT NULL CHECK (consumer = 'ordinary_scan_ingestion'),
    ingestion_job_id UUID NOT NULL,
    manifest_checksum TEXT NOT NULL CHECK (manifest_checksum ~ '^[0-9a-f]{64}$'),
    request_checksum TEXT NOT NULL CHECK (request_checksum ~ '^[0-9a-f]{64}$'),
    ingestion_projection JSONB NOT NULL CHECK (pg_catalog.jsonb_typeof(ingestion_projection) = 'object'),
    members JSONB NOT NULL CHECK (pg_catalog.jsonb_typeof(members) = 'array'
        AND pg_catalog.jsonb_array_length(members) BETWEEN 1 AND 8),
    cohort_sha256 TEXT NOT NULL CHECK (cohort_sha256 ~ '^[0-9a-f]{64}$'),
    UNIQUE (owner_id, scan_id, consumer)
);
ALTER TABLE internal.capture_promotion_cohorts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.capture_promotion_cohorts FROM PUBLIC, anon, authenticated, service_role;
ALTER TABLE internal.capture_promotion_operations ADD COLUMN cohort_id UUID
    REFERENCES internal.capture_promotion_cohorts(cohort_id);
CREATE INDEX capture_promotion_cohort_idx ON internal.capture_promotion_operations(cohort_id)
    WHERE cohort_id IS NOT NULL;
COMMENT ON TABLE internal.capture_promotion_cohorts IS
    'Prepared immutable ordered logical ingestion cohort, sealed before member writes. Retains identity after job loss; not verified outcome, finalization, History evidence or publication authority.';

-- Caller already owns account/user/scan locks. Intentionally take no job/intent
-- row lock: begin_scan_ingestion serializes manifest replacement with the same
-- scan advisory; taking a job lock here would invert terminal-owner ordering.
CREATE FUNCTION internal.capture_promotion_ingestion_projection(
    p_owner UUID,p_scan UUID,p_job UUID,p_manifest TEXT,p_request TEXT
) RETURNS JSONB LANGUAGE PLPGSQL SET search_path = '' AS $$
DECLARE j public.scan_ingestion_jobs%ROWTYPE; i public.scan_ingestion_intents%ROWTYPE;
BEGIN
    SELECT * INTO j FROM public.scan_ingestion_jobs WHERE id=p_job;
    IF NOT FOUND OR j.user_id IS DISTINCT FROM p_owner OR j.scan_id IS DISTINCT FROM p_scan::TEXT
        OR j.status NOT IN ('processing','finalizing','retrying','failed_retryable')
        OR j.manifest_checksum IS DISTINCT FROM p_manifest THEN
        RAISE EXCEPTION 'capture_promotion_cohort_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO i FROM public.scan_ingestion_intents WHERE user_id=p_owner AND scan_id=p_scan::TEXT;
    IF NOT FOUND OR i.manifest_checksum IS DISTINCT FROM p_manifest OR i.payload_checksum IS DISTINCT FROM p_request
        OR i.media_object_keys IS DISTINCT FROM j.media_object_keys OR i.media_counts IS DISTINCT FROM j.media_counts
        OR i.upload_session_ids IS DISTINCT FROM j.upload_session_ids OR i.endpoint IS DISTINCT FROM j.endpoint THEN
        RAISE EXCEPTION 'capture_promotion_cohort_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN pg_catalog.jsonb_build_object('consumer','ordinary_scan_ingestion','ownerId',p_owner,'scanId',p_scan,
        'jobId',p_job,'intentId',i.id,'payloadSchemaVersion',i.payload_schema_version,'manifestChecksum',p_manifest,'requestChecksum',p_request,'endpoint',j.endpoint,
        'mediaObjectKeys',j.media_object_keys,'mediaCounts',j.media_counts,'uploadSessionIds',j.upload_session_ids);
END;
$$;

CREATE FUNCTION public.register_capture_promotion_cohort(
    p_cohort UUID,p_job UUID,p_manifest TEXT,p_request TEXT,p_bindings JSONB
) RETURNS TEXT LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
DECLARE b internal.capture_promotion_operations%ROWTYPE; o internal.capture_promotion_operations%ROWTYPE;
    saved internal.capture_promotion_cohorts%ROWTYPE; asset public.scan_media_assets%ROWTYPE;
    owner UUID; scan UUID; projection JSONB; keys JSONB; members JSONB := '[]'; item JSONB; kind TEXT;
    expected_keys JSONB := '[]'; input_keys JSONB := '[]'; ordinal INTEGER; position INTEGER := 0;
    total INTEGER; seal TEXT; existing BOOLEAN; operation_ids UUID[] := '{}';
BEGIN
    PERFORM internal.require_service_role();
    IF p_cohort IS NULL OR p_job IS NULL OR p_manifest IS NULL OR p_manifest !~ '^[0-9a-f]{64}$'
        OR p_request IS NULL OR p_request !~ '^[0-9a-f]{64}$'
        OR p_bindings IS NULL OR pg_catalog.jsonb_typeof(p_bindings) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'capture_promotion_cohort_invalid' USING ERRCODE='22023';
    END IF;
    total := pg_catalog.jsonb_array_length(p_bindings);
    IF total NOT BETWEEN 1 AND 8 OR pg_catalog.octet_length(p_bindings::TEXT)>32768 THEN
        RAISE EXCEPTION 'capture_promotion_cohort_invalid' USING ERRCODE='22023';
    END IF;
    b := internal.parse_capture_promotion_binding(p_bindings->0);
    owner := b.owner_id; scan := b.scan_id;
    PERFORM internal.lock_capture_promotion_source(b);
    projection := internal.capture_promotion_ingestion_projection(owner,scan,p_job,p_manifest,p_request);
    keys := projection->'mediaObjectKeys';
    IF pg_catalog.jsonb_typeof(keys) IS DISTINCT FROM 'object'
        OR (SELECT count(*) FROM pg_catalog.jsonb_object_keys(keys))<>3 OR NOT keys ?& ARRAY['image','audio','video'] THEN
        RAISE EXCEPTION 'capture_promotion_cohort_invalid' USING ERRCODE='22023';
    END IF;
    -- The registration array is canonical image/audio/video grouping, with each
    -- manifest's ordinal preserved. Asset role/order remains separately sealed.
    FOREACH kind IN ARRAY ARRAY['image','audio','video'] LOOP
        IF pg_catalog.jsonb_typeof(keys->kind) IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION 'capture_promotion_cohort_invalid' USING ERRCODE='22023';
        END IF;
        IF pg_catalog.jsonb_array_length(keys->kind) > (CASE kind WHEN 'image' THEN 5 WHEN 'audio' THEN 2 ELSE 1 END) THEN
            RAISE EXCEPTION 'capture_promotion_cohort_invalid' USING ERRCODE='22023';
        END IF;
        expected_keys := expected_keys || (keys->kind);
    END LOOP;
    IF pg_catalog.jsonb_array_length(expected_keys)<>total
        OR EXISTS (SELECT 1 FROM pg_catalog.jsonb_array_elements(expected_keys) v WHERE pg_catalog.jsonb_typeof(v) IS DISTINCT FROM 'string')
        OR (SELECT count(DISTINCT v) FROM pg_catalog.jsonb_array_elements(expected_keys) v)<>total THEN
        RAISE EXCEPTION 'capture_promotion_cohort_invalid' USING ERRCODE='22023';
    END IF;
    SELECT * INTO saved FROM internal.capture_promotion_cohorts WHERE cohort_id=p_cohort;
    existing := FOUND;
    FOREACH kind IN ARRAY ARRAY['image','audio','video'] LOOP
        ordinal := 0;
        FOR item IN SELECT value FROM pg_catalog.jsonb_array_elements(keys->kind) LOOP
            b := internal.parse_capture_promotion_binding(p_bindings->position);
            IF b.owner_id<>owner OR b.scan_id<>scan OR b.source_key IS DISTINCT FROM (item#>>'{}')
                OR b.operation_id=ANY(operation_ids) THEN
                RAISE EXCEPTION 'capture_promotion_cohort_invalid' USING ERRCODE='22023';
            END IF;
            PERFORM public.register_capture_promotion_operation(p_bindings->position);
            SELECT * INTO o FROM internal.capture_promotion_operations WHERE operation_id=b.operation_id FOR UPDATE;
            IF (NOT existing AND o.write_authorized_at IS NOT NULL)
                OR (existing AND o.cohort_id IS DISTINCT FROM p_cohort)
                OR (o.cohort_id IS NOT NULL AND o.cohort_id<>p_cohort) THEN
                RAISE EXCEPTION 'capture_promotion_cohort_conflict' USING ERRCODE='55000';
            END IF;
            SELECT * INTO STRICT asset FROM public.scan_media_assets WHERE id=b.asset_id;
            IF asset.kind IS DISTINCT FROM kind OR asset.role='thumbnail'
                OR NOT (projection->'uploadSessionIds') @> pg_catalog.jsonb_build_array(b.session_id) THEN
                RAISE EXCEPTION 'capture_promotion_cohort_invalid' USING ERRCODE='22023';
            END IF;
            members := members || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
                'binding',p_bindings->position,'kind',kind,'ordinal',ordinal,'role',asset.role,'assetOrder',asset.order_index));
            input_keys := input_keys || pg_catalog.jsonb_build_array(b.source_key);
            operation_ids := pg_catalog.array_append(operation_ids,b.operation_id);
            ordinal := ordinal+1; position := position+1;
        END LOOP;
    END LOOP;
    IF input_keys IS DISTINCT FROM expected_keys THEN
        RAISE EXCEPTION 'capture_promotion_cohort_invalid' USING ERRCODE='22023';
    END IF;
    seal := pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
        pg_catalog.jsonb_build_object('projection',projection,'members',members)::TEXT,'UTF8')),'hex');
    IF existing THEN
        IF saved.ingestion_projection IS DISTINCT FROM projection OR saved.members IS DISTINCT FROM members
            OR saved.cohort_sha256 IS DISTINCT FROM seal THEN
            RAISE EXCEPTION 'capture_promotion_cohort_conflict' USING ERRCODE='55000';
        END IF;
        RETURN saved.cohort_sha256;
    END IF;
    INSERT INTO internal.capture_promotion_cohorts(cohort_id,owner_id,scan_id,consumer,ingestion_job_id,
        manifest_checksum,request_checksum,ingestion_projection,members,cohort_sha256)
    VALUES(p_cohort,owner,scan,'ordinary_scan_ingestion',p_job,p_manifest,p_request,projection,members,seal);
    UPDATE internal.capture_promotion_operations SET cohort_id=p_cohort WHERE operation_id=ANY(operation_ids);
    RETURN seal;
END;
$$;

-- Acquire all source locks before any operation locks. The first source lock
-- acquires the common account/user/scan fences before its asset; all cohort
-- registration and member authorizations share that owner-row serialization.
CREATE FUNCTION internal.lock_capture_promotion_action_sources(b internal.capture_promotion_operations)
RETURNS VOID LANGUAGE PLPGSQL SET search_path = '' AS $$
DECLARE cohort UUID; members JSONB; member JSONB;
BEGIN
    PERFORM internal.lock_capture_promotion_source(b);
    -- Read membership only after the owner lock: enrollment may have committed
    -- while this invocation waited. Never use a pre-lock unbound snapshot.
    SELECT cohort_id INTO cohort FROM internal.capture_promotion_operations WHERE operation_id=b.operation_id;
    IF cohort IS NULL THEN RETURN; END IF;
    SELECT c.members INTO STRICT members FROM internal.capture_promotion_cohorts c WHERE cohort_id=cohort;
    FOR member IN SELECT value FROM pg_catalog.jsonb_array_elements(members) ORDER BY value->'binding'->>'assetId' LOOP
        PERFORM internal.lock_capture_promotion_source(internal.parse_capture_promotion_binding(member->'binding'));
    END LOOP;
END;
$$;

CREATE FUNCTION internal.require_capture_promotion_cohort_current(p_operation UUID)
RETURNS VOID LANGUAGE PLPGSQL SET search_path = '' AS $$
DECLARE o internal.capture_promotion_operations%ROWTYPE; c internal.capture_promotion_cohorts%ROWTYPE;
    peer internal.capture_promotion_operations%ROWTYPE; asset public.scan_media_assets%ROWTYPE;
    member JSONB; projection JSONB; seen BOOLEAN := FALSE;
BEGIN
    SELECT * INTO STRICT o FROM internal.capture_promotion_operations WHERE operation_id=p_operation;
    -- Legacy unbound prepared operations remain content-only. A future finalizer
    -- must require a whole cohort; no implicit backfill or completion authority.
    IF o.cohort_id IS NULL THEN RETURN; END IF;
    SELECT * INTO STRICT c FROM internal.capture_promotion_cohorts WHERE cohort_id=o.cohort_id;
    projection := internal.capture_promotion_ingestion_projection(c.owner_id,c.scan_id,c.ingestion_job_id,c.manifest_checksum,c.request_checksum);
    IF projection IS DISTINCT FROM c.ingestion_projection THEN
        RAISE EXCEPTION 'capture_promotion_cohort_unavailable' USING ERRCODE='55000';
    END IF;
    FOR member IN SELECT value FROM pg_catalog.jsonb_array_elements(c.members) ORDER BY value->'binding'->>'operationId' LOOP
        SELECT * INTO peer FROM internal.capture_promotion_operations WHERE operation_id=(member->'binding'->>'operationId')::UUID FOR UPDATE;
        IF NOT FOUND OR peer.cohort_id IS DISTINCT FROM o.cohort_id OR peer.retired_at IS NOT NULL
            OR member->'binding' IS DISTINCT FROM internal.capture_promotion_binding(peer) THEN
            RAISE EXCEPTION 'capture_promotion_cohort_unavailable' USING ERRCODE='55000';
        END IF;
        SELECT * INTO asset FROM public.scan_media_assets WHERE id=peer.asset_id;
        IF NOT FOUND OR member->>'kind' IS DISTINCT FROM asset.kind OR member->>'role' IS DISTINCT FROM asset.role
            OR (member->>'assetOrder')::INTEGER IS DISTINCT FROM asset.order_index THEN
            RAISE EXCEPTION 'capture_promotion_cohort_unavailable' USING ERRCODE='55000';
        END IF;
        seen := seen OR peer.operation_id=p_operation;
    END LOOP;
    IF NOT seen THEN RAISE EXCEPTION 'capture_promotion_cohort_unavailable' USING ERRCODE='55000'; END IF;
END;
$$;

-- Insert only the new cohort check into the already reviewed fresh-I/O owner.
DO $$
DECLARE source TEXT; before_fragment TEXT := $before$    IF p_action='write_destination' THEN$before$;
    after_fragment TEXT := $after$    PERFORM internal.require_capture_promotion_cohort_current(saved.operation_id);
    IF p_action='write_destination' THEN$after$;
BEGIN
    source := pg_catalog.pg_get_functiondef('public.authorize_capture_promotion_action(jsonb,text)'::regprocedure);
    IF pg_catalog.strpos(source,'PERFORM internal.lock_capture_promotion_source(b);')=0 THEN
        RAISE EXCEPTION 'capture promotion source-lock owner drift';
    END IF;
    source := pg_catalog.replace(source,'PERFORM internal.lock_capture_promotion_source(b);','PERFORM internal.lock_capture_promotion_action_sources(b);');
    IF (pg_catalog.length(source)-pg_catalog.length(pg_catalog.replace(source,before_fragment,'')))/pg_catalog.length(before_fragment)<>1 THEN
        RAISE EXCEPTION 'capture promotion authorization source drift';
    END IF;
    EXECUTE pg_catalog.replace(source,before_fragment,after_fragment);
END;
$$;

REVOKE ALL ON FUNCTION internal.capture_promotion_ingestion_projection(UUID,UUID,UUID,TEXT,TEXT),
    internal.require_capture_promotion_cohort_current(UUID),
    internal.lock_capture_promotion_action_sources(internal.capture_promotion_operations) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.register_capture_promotion_cohort(UUID,UUID,TEXT,TEXT,JSONB) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_capture_promotion_cohort(UUID,UUID,TEXT,TEXT,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.register_capture_promotion_cohort(uuid,uuid,text,text,jsonb)',
     'Prepared immutable full ordinary ingestion cohort and role/order seal before member writes; no finalization or release authority.');
RESET statement_timeout;
RESET lock_timeout;
