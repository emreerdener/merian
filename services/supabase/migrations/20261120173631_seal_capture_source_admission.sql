SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Staging and the collector already accept M4A audio. Preserve that parity in
-- the prepared promotion owner; MP4 audio uses the audio, not video, ceiling.
DO $audio$
DECLARE constraint_name TEXT; definition TEXT; signature TEXT;
BEGIN
    SELECT conname INTO STRICT constraint_name FROM pg_constraint
        WHERE conrelid='internal.capture_promotion_operations'::regclass AND contype='c'
            AND pg_get_constraintdef(oid) LIKE '%content_type%';
    EXECUTE format('ALTER TABLE internal.capture_promotion_operations DROP CONSTRAINT %I',constraint_name);
    ALTER TABLE internal.capture_promotion_operations ADD CONSTRAINT capture_promotion_content_budget CHECK (byte_count>0 AND CASE
        WHEN content_type IN ('image/jpeg','image/png','image/webp','image/heic','image/heif') THEN byte_count<=5242880
        WHEN content_type IN ('audio/wav','audio/mp4') THEN byte_count<=2700000
        WHEN content_type='video/mp4' THEN byte_count<=12582912 ELSE FALSE END);
    FOREACH signature IN ARRAY ARRAY['internal.parse_capture_promotion_binding(jsonb)',
        'internal.lock_capture_promotion_source(internal.capture_promotion_operations)'] LOOP
        definition := pg_get_functiondef(signature::regprocedure);
        IF (length(definition)-length(replace(definition,$a$b.content_type = 'audio/wav'$a$,'')))/length($a$b.content_type = 'audio/wav'$a$)<>1 THEN
            RAISE EXCEPTION 'capture_source_audio_parity_drift';
        END IF;
        EXECUTE replace(definition,$a$b.content_type = 'audio/wav'$a$,$a$b.content_type IN ('audio/wav','audio/mp4')$a$);
    END LOOP;
END;
$audio$;

-- Independent of mutable jobs, intents, assets and profile cascades. Retirement
-- erases the recovery document, retaining only a no-reuse identity marker.
CREATE TABLE internal.capture_source_admissions (
    scan_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    recovery JSONB,
    admitted_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    retired_at TIMESTAMPTZ,
    CHECK ((recovery IS NULL) = (retired_at IS NOT NULL))
);
CREATE INDEX capture_source_admissions_owner_idx ON internal.capture_source_admissions(owner_id);
ALTER TABLE internal.capture_source_admissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.capture_source_admissions FROM PUBLIC, anon, authenticated, service_role;

-- Terminal/bookkeeping writers hold job or intent locks. Their one-way stop
-- marker is separate from the recovery document: they must never wait on a
-- seal row held by account/scan retirement before that retirement locks a job.
CREATE TABLE internal.capture_source_admission_stops (
    scan_id UUID PRIMARY KEY,
    stopped_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE internal.capture_source_admission_stops ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.capture_source_admission_stops FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION internal.capture_source_intent_projection(row_value JSONB)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path = '' AS $$
    SELECT jsonb_build_object('endpoint',row_value->'endpoint',
        'payload_schema_version',row_value->'payload_schema_version',
        'request_payload',row_value->'request_payload','media_counts',row_value->'media_counts',
        'media_object_keys',row_value->'media_object_keys','upload_session_ids',row_value->'upload_session_ids',
        'manifest_checksum',row_value->'manifest_checksum','payload_checksum',row_value->'payload_checksum',
        'inline_media_redacted',row_value->'inline_media_redacted','redacted_media_counts',row_value->'redacted_media_counts');
$$;
CREATE FUNCTION internal.capture_source_job_projection(row_value JSONB)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path = '' AS $$
    SELECT jsonb_build_object('endpoint',row_value->'endpoint','media_counts',row_value->'media_counts',
        'media_object_keys',row_value->'media_object_keys','upload_session_ids',row_value->'upload_session_ids',
        'manifest_checksum',row_value->'manifest_checksum');
$$;

CREATE FUNCTION internal.prepare_capture_source_admission(
    p_owner UUID,p_scan UUID,p_endpoint TEXT,p_payload JSONB,p_counts JSONB,p_keys JSONB,
    p_storage TEXT[],p_resumable BOOLEAN,p_inline BOOLEAN,p_redacted JSONB,p_schema INTEGER
) RETURNS JSONB LANGUAGE PLPGSQL SET search_path = '' AS $$
DECLARE saved internal.capture_source_admissions; identity JSONB; observations JSONB; proofs JSONB := '[]';
    item JSONB; kind TEXT; key TEXT; mime TEXT; bytes BIGINT; total INTEGER; position INTEGER := 0;
    image_bytes BIGINT := 0; expected JSONB := '[]'; sessions UUID[] := '{}'; asset public.scan_media_assets;
    authority internal.capture_object_authorities; manifest TEXT; checksum TEXT; payload JSONB; projection JSONB;
BEGIN
    -- Caller holds account intake -> owner -> scan fences. Do not lock an
    -- existing seal here: all-writer triggers recheck it after job/intent waits.
    SELECT * INTO saved FROM internal.capture_source_admissions WHERE scan_id=p_scan;
    IF NOT FOUND AND NOT COALESCE(p_payload ?| ARRAY['captureSourceObservations','captureSourceProofs'],FALSE) THEN RETURN NULL; END IF;
    IF EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_owner)
        OR (saved.scan_id IS NOT NULL AND (saved.owner_id<>p_owner OR saved.retired_at IS NOT NULL))
        OR EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id=p_scan) THEN
        RAISE EXCEPTION 'capture_source_admission_unavailable' USING ERRCODE='55000';
    END IF;
    identity := jsonb_build_object('endpoint',p_endpoint,'payload',p_payload-ARRAY[
        'captureSourceObservations','captureSourceProofs','uploadSessionIds','manifestChecksum'],
        'mediaCounts',p_counts,'mediaObjectKeys',p_keys,'storageKeys',to_jsonb(p_storage),
        'resumable',p_resumable,'inlineMediaRedacted',p_inline,'redactedMediaCounts',p_redacted,'schema',p_schema);
    IF saved.scan_id IS NOT NULL THEN
        IF identity IS DISTINCT FROM saved.recovery->'identity'
            OR NOT ((p_payload ? 'captureSourceObservations' AND NOT p_payload ? 'captureSourceProofs'
                AND p_payload->'captureSourceObservations'=saved.recovery->'observations')
              OR (p_payload ? 'captureSourceProofs' AND NOT p_payload ? 'captureSourceObservations'
                AND p_payload->'captureSourceProofs'=saved.recovery#>'{intent,request_payload,captureSourceProofs}')) THEN
            RAISE EXCEPTION 'capture_source_admission_conflict' USING ERRCODE='55000';
        END IF;
        RETURN saved.recovery->'intent';
    END IF;
    -- No retroactive upgrade of a legacy generation, even if its other mutable
    -- row was lost. Only the atomic begin owner may create a new witness.
    IF EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=p_scan::TEXT)
        OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE scan_id=p_scan::TEXT)
        OR p_payload ? 'captureSourceProofs' THEN
        RAISE EXCEPTION 'capture_source_admission_conflict' USING ERRCODE='55000';
    END IF;
    observations := p_payload->'captureSourceObservations';
    IF p_schema IS DISTINCT FROM 3 OR p_endpoint IS DISTINCT FROM 'identify-multimodal'
        OR p_resumable IS DISTINCT FROM TRUE OR p_inline IS DISTINCT FROM FALSE
        OR p_payload->'schemaVersion' IS DISTINCT FROM '3'::JSONB
        OR p_payload->>'clientScanId' IS DISTINCT FROM p_scan::TEXT
        OR p_payload->'endpoint' IS DISTINCT FROM '"identify-multimodal"'::JSONB
        OR p_payload->'mediaCounts' IS DISTINCT FROM p_counts
        OR jsonb_typeof(observations) IS DISTINCT FROM 'object'
        OR observations-ARRAY['version','items']<>'{}' OR observations->'version' IS DISTINCT FROM '1'::JSONB
        OR jsonb_typeof(observations->'items') IS DISTINCT FROM 'array'
        OR jsonb_typeof(p_keys) IS DISTINCT FROM 'object'
        OR NOT p_keys ?& ARRAY['image','audio','video'] OR p_keys-ARRAY['image','audio','video']<>'{}' THEN
        RAISE EXCEPTION 'capture_source_admission_invalid' USING ERRCODE='22023';
    END IF;
    FOREACH kind IN ARRAY ARRAY['image','audio','video'] LOOP
        IF jsonb_typeof(p_keys->kind) IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION 'capture_source_admission_invalid' USING ERRCODE='22023';
        END IF;
        IF jsonb_array_length(p_keys->kind)>(CASE kind WHEN 'image' THEN 5 WHEN 'audio' THEN 2 ELSE 1 END)
            OR p_payload#>ARRAY['media',CASE kind WHEN 'image' THEN 'r2ObjectKeys' WHEN 'audio' THEN 'audioR2ObjectKeys' ELSE 'videoR2ObjectKeys' END] IS DISTINCT FROM p_keys->kind
            OR p_counts->(kind||'_count') IS DISTINCT FROM to_jsonb(jsonb_array_length(p_keys->kind)) THEN
            RAISE EXCEPTION 'capture_source_admission_invalid' USING ERRCODE='22023';
        END IF;
        expected := expected || (p_keys->kind);
    END LOOP;
    total := jsonb_array_length(expected);
    IF total NOT BETWEEN 1 AND 8 OR jsonb_array_length(observations->'items')<>total
        OR octet_length(observations::TEXT)>32768 OR to_jsonb(p_storage) IS DISTINCT FROM expected
        OR (SELECT count(DISTINCT value->>'backendSHA256') FROM jsonb_array_elements(observations->'items'))<>1
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(expected) v WHERE jsonb_typeof(v) IS DISTINCT FROM 'string')
        OR (SELECT count(DISTINCT v) FROM jsonb_array_elements(expected) v)<>total
        OR EXISTS(SELECT 1 FROM jsonb_each(p_redacted) e WHERE e.value IS DISTINCT FROM '0'::JSONB) THEN
        RAISE EXCEPTION 'capture_source_admission_invalid' USING ERRCODE='22023';
    END IF;
    -- Stable asset lock order, independent of user-visible item order.
    PERFORM id FROM public.scan_media_assets WHERE user_id=p_owner AND client_scan_id=p_scan
        AND source='capture_upload' AND storage_key=ANY(p_storage) ORDER BY storage_key,id FOR UPDATE;
    FOREACH kind IN ARRAY ARRAY['image','audio','video'] LOOP
        FOR key IN SELECT value FROM jsonb_array_elements_text(p_keys->kind) LOOP
            item := observations->'items'->position;
            IF jsonb_typeof(item) IS DISTINCT FROM 'object' OR NOT item ?& ARRAY['sourceKey','backendSHA256','contentType','byteCount','sha256']
                OR item-ARRAY['sourceKey','backendSHA256','contentType','byteCount','sha256']<>'{}'
                OR item->'sourceKey' IS DISTINCT FROM to_jsonb(key)
                OR key !~ ('^staging/'||p_owner::TEXT||'/[A-Za-z0-9_.-]{1,255}$')
                OR strpos(key,'..')>0
                OR jsonb_typeof(item->'backendSHA256') IS DISTINCT FROM 'string' OR item->>'backendSHA256' !~ '^[0-9a-f]{64}$'
                OR jsonb_typeof(item->'sha256') IS DISTINCT FROM 'string' OR item->>'sha256' !~ '^[0-9a-f]{64}$'
                OR jsonb_typeof(item->'contentType') IS DISTINCT FROM 'string'
                OR jsonb_typeof(item->'byteCount') IS DISTINCT FROM 'number' OR item->>'byteCount' !~ '^[1-9][0-9]{0,7}$' THEN
                RAISE EXCEPTION 'capture_source_admission_invalid' USING ERRCODE='22023';
            END IF;
            mime := item->>'contentType'; bytes := (item->>'byteCount')::BIGINT;
            IF (kind='image' AND (mime NOT IN ('image/jpeg','image/png','image/webp','image/heic','image/heif') OR bytes>5242880))
                OR (kind='audio' AND (mime NOT IN ('audio/wav','audio/mp4') OR bytes>2700000))
                OR (kind='video' AND (mime<>'video/mp4' OR bytes>12582912)) THEN
                RAISE EXCEPTION 'capture_source_admission_invalid' USING ERRCODE='22023';
            END IF;
            IF kind='image' THEN image_bytes := image_bytes+bytes; END IF;
            IF image_bytes>5242880 THEN RAISE EXCEPTION 'capture_source_admission_invalid' USING ERRCODE='22023'; END IF;
            SELECT * INTO asset FROM public.scan_media_assets WHERE user_id=p_owner AND client_scan_id=p_scan
                AND source='capture_upload' AND storage_key=key AND status='staged';
            IF NOT FOUND OR asset.kind IS DISTINCT FROM kind OR asset.role='thumbnail' OR asset.upload_session_id IS NULL
                OR asset.content_type IS DISTINCT FROM mime OR asset.byte_size IS DISTINCT FROM bytes
                OR (SELECT count(*) FROM public.scan_media_assets WHERE user_id=p_owner AND client_scan_id=p_scan
                    AND source='capture_upload' AND storage_key=key AND status='staged')<>1
                OR (asset.checksum_sha256 IS NOT NULL AND asset.checksum_sha256 IS DISTINCT FROM item->>'sha256') THEN
                RAISE EXCEPTION 'capture_source_admission_unavailable' USING ERRCODE='55000';
            END IF;
            SELECT * INTO authority FROM internal.capture_object_authorities
                WHERE backend_sha256=item->>'backendSHA256' AND object_key=key FOR UPDATE;
            IF NOT FOUND OR authority.retired_at IS NOT NULL OR authority.owner_id IS DISTINCT FROM p_owner
                OR authority.scan_id IS DISTINCT FROM p_scan OR authority.asset_id IS DISTINCT FROM asset.id
                OR authority.session_id IS DISTINCT FROM asset.upload_session_id THEN
                RAISE EXCEPTION 'capture_source_admission_unavailable' USING ERRCODE='55000';
            END IF;
            UPDATE public.scan_media_assets SET checksum_sha256=item->>'sha256' WHERE id=asset.id AND checksum_sha256 IS NULL;
            proofs := proofs || jsonb_build_array(item || jsonb_build_object('assetId',asset.id,'sessionId',asset.upload_session_id,
                'kind',asset.kind,'role',asset.role,'assetOrder',asset.order_index,'ordinal',position));
            sessions := array_append(sessions,asset.upload_session_id); position := position+1;
        END LOOP;
    END LOOP;
    SELECT array_agg(DISTINCT value ORDER BY value) INTO sessions FROM unnest(sessions) value;
    manifest := encode(sha256(convert_to(jsonb_build_object('mediaCounts',p_counts,'mediaObjectKeys',p_keys,
        'uploadSessionIds',to_jsonb(sessions))::TEXT,'UTF8')),'hex');
    payload := (p_payload-'captureSourceObservations') || jsonb_build_object('captureSourceProofs',jsonb_build_object('version',1,'items',proofs),
        'uploadSessionIds',to_jsonb(sessions),'manifestChecksum',manifest);
    checksum := encode(sha256(convert_to(payload::TEXT,'UTF8')),'hex');
    projection := jsonb_build_object('endpoint',p_endpoint,'payload_schema_version',p_schema,'request_payload',payload,
        'media_counts',p_counts,'media_object_keys',p_keys,'upload_session_ids',to_jsonb(sessions),'manifest_checksum',manifest,
        'payload_checksum',checksum,'inline_media_redacted',p_inline,'redacted_media_counts',p_redacted);
    INSERT INTO internal.capture_source_admissions(scan_id,owner_id,recovery)
        VALUES(p_scan,p_owner,jsonb_build_object('identity',identity,'observations',observations,'intent',projection));
    RETURN projection;
END;
$$;

CREATE FUNCTION internal.guard_capture_source_admission() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
DECLARE saved internal.capture_source_admissions; scan UUID; expected JSONB; actual JSONB;
BEGIN
    actual := to_jsonb(NEW);
    IF NEW.scan_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
        IF actual->'request_payload' ?| ARRAY['captureSourceObservations','captureSourceProofs']
            OR (TG_OP='UPDATE' AND EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id::TEXT=OLD.scan_id)) THEN
            RAISE EXCEPTION 'capture_source_admission_conflict' USING ERRCODE='55000';
        END IF;
        RETURN NEW;
    END IF;
    scan := NEW.scan_id::UUID;
    -- INSERT has no existing child-row lock. Serialize direct service inserts
    -- before reading the seal; UPDATE must not take owner after a child lock.
    IF TG_OP='INSERT' THEN
        PERFORM id FROM public.users WHERE id=NEW.user_id FOR UPDATE;
        PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||scan::TEXT,0));
    ELSIF OLD.user_id IS DISTINCT FROM NEW.user_id OR OLD.scan_id IS DISTINCT FROM NEW.scan_id THEN
        IF EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id::TEXT=OLD.scan_id OR scan_id=scan) THEN
            -- Existing private merge authority permits only metadata reparenting
            -- after the original admission was permanently retired and erased.
            IF NEW.scan_id=OLD.scan_id AND (to_jsonb(NEW)-ARRAY['user_id','updated_at'])=(to_jsonb(OLD)-ARRAY['user_id','updated_at'])
                AND EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id=scan AND owner_id=OLD.user_id AND retired_at IS NOT NULL)
                AND EXISTS(SELECT 1 FROM internal.capture_reparent_transactions WHERE transaction_id=pg_current_xact_id()
                    AND source_owner=OLD.user_id AND target_owner=NEW.user_id) THEN RETURN NEW; END IF;
            RAISE EXCEPTION 'capture_source_admission_conflict' USING ERRCODE='55000';
        END IF;
    END IF;
    IF TG_OP='INSERT' THEN
        -- Account intake does not acquire the owner row. Hold a shared seal lock
        -- until the inserted child commits so erasure cannot pass this insert.
        -- Updates never acquire this lock (retirement can hold seal -> job).
        SELECT * INTO saved FROM internal.capture_source_admissions WHERE scan_id=scan FOR SHARE;
    ELSE
        SELECT * INTO saved FROM internal.capture_source_admissions WHERE scan_id=scan;
    END IF;
    IF TG_TABLE_NAME='scan_ingestion_intents' AND actual->'request_payload' ? 'captureSourceObservations' THEN
        RAISE EXCEPTION 'capture_source_admission_conflict' USING ERRCODE='55000';
    END IF;
    IF saved.scan_id IS NULL THEN
        IF TG_TABLE_NAME='scan_ingestion_intents' AND actual->'request_payload' ? 'captureSourceProofs' THEN
            RAISE EXCEPTION 'capture_source_admission_conflict' USING ERRCODE='55000';
        END IF;
        RETURN NEW;
    END IF;
    IF saved.retired_at IS NOT NULL THEN
        -- Retirement may still terminalize/bookkeep existing rows. Freeze their
        -- projection locally after erasure; no new rows or identity activation.
        IF TG_OP='INSERT' THEN RAISE EXCEPTION 'capture_source_admission_unavailable' USING ERRCODE='55000'; END IF;
        expected := to_jsonb(OLD);
    ELSE
        IF saved.owner_id IS DISTINCT FROM NEW.user_id THEN RAISE EXCEPTION 'capture_source_admission_conflict' USING ERRCODE='55000'; END IF;
        expected := saved.recovery->'intent';
    END IF;
    actual := to_jsonb(NEW);
    IF (TG_TABLE_NAME='scan_ingestion_intents' AND internal.capture_source_intent_projection(actual) IS DISTINCT FROM internal.capture_source_intent_projection(expected))
        OR (TG_TABLE_NAME='scan_ingestion_jobs' AND internal.capture_source_job_projection(actual) IS DISTINCT FROM internal.capture_source_job_projection(expected)) THEN
        RAISE EXCEPTION 'capture_source_admission_conflict' USING ERRCODE='55000';
    END IF;
    IF TG_OP='INSERT' AND EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id=scan) THEN
        RAISE EXCEPTION 'capture_source_admission_unavailable' USING ERRCODE='55000';
    END IF;
    IF TG_TABLE_NAME='scan_ingestion_intents' THEN
        IF saved.retired_at IS NOT NULL AND NEW.resumable THEN NEW.resumable := FALSE; END IF;
        IF TG_OP='UPDATE' AND NOT OLD.resumable AND NEW.resumable THEN
            RAISE EXCEPTION 'capture_source_admission_unavailable' USING ERRCODE='55000';
        END IF;
        IF NOT NEW.resumable THEN INSERT INTO internal.capture_source_admission_stops(scan_id) VALUES(scan) ON CONFLICT DO NOTHING; END IF;
    ELSIF TG_OP='UPDATE' AND OLD.status IN ('failed_terminal','complete') AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'capture_source_admission_unavailable' USING ERRCODE='55000';
    ELSIF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM OLD.status AND NEW.status NOT IN ('failed_terminal','failed_retryable')
        AND (saved.retired_at IS NOT NULL OR EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id=scan)) THEN
        RAISE EXCEPTION 'capture_source_admission_unavailable' USING ERRCODE='55000';
    ELSIF NEW.status IN ('failed_terminal','complete') THEN
        INSERT INTO internal.capture_source_admission_stops(scan_id) VALUES(scan) ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER c_guard_capture_source_admission BEFORE INSERT OR UPDATE ON public.scan_ingestion_intents
    FOR EACH ROW EXECUTE FUNCTION internal.guard_capture_source_admission();
CREATE TRIGGER c_guard_capture_source_admission BEFORE INSERT OR UPDATE ON public.scan_ingestion_jobs
    FOR EACH ROW EXECUTE FUNCTION internal.guard_capture_source_admission();

CREATE FUNCTION internal.retire_capture_source_admissions() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF TG_TABLE_NAME='scan_deletion_tombstones' THEN
        UPDATE internal.capture_source_admissions SET recovery=NULL,retired_at=COALESCE(retired_at,clock_timestamp()) WHERE scan_id=NEW.scan_id;
        RETURN NEW;
    ELSIF TG_TABLE_NAME='users' THEN
        UPDATE internal.capture_source_admissions SET recovery=NULL,retired_at=COALESCE(retired_at,clock_timestamp()) WHERE owner_id=OLD.id;
        RETURN OLD;
    ELSE
        UPDATE internal.capture_source_admissions SET recovery=NULL,retired_at=COALESCE(retired_at,clock_timestamp()) WHERE owner_id=NEW.user_id;
        RETURN NEW;
    END IF;
END;
$$;
CREATE TRIGGER retire_capture_source_admissions AFTER INSERT ON internal.scan_deletion_tombstones
    FOR EACH ROW EXECUTE FUNCTION internal.retire_capture_source_admissions();
CREATE TRIGGER retire_capture_source_admissions AFTER INSERT ON internal.account_deletion_jobs
    FOR EACH ROW EXECUTE FUNCTION internal.retire_capture_source_admissions();
CREATE TRIGGER retire_capture_source_admissions BEFORE DELETE ON public.users
    FOR EACH ROW EXECUTE FUNCTION internal.retire_capture_source_admissions();

DO $patch$
DECLARE definition TEXT; anchor TEXT; finish TEXT; first_offset INTEGER; last_offset INTEGER;
BEGIN
    definition := pg_get_functiondef('public.begin_scan_ingestion(text,uuid,text,jsonb,jsonb,jsonb,text[],text,text,boolean,boolean,jsonb,integer,integer)'::regprocedure);
    anchor := '    ledger_stage TEXT;';
    IF strpos(definition,anchor)=0 THEN RAISE EXCEPTION 'capture_source_begin_declaration_drift'; END IF;
    definition := replace(definition,anchor,anchor||E'\n    capture_admission JSONB;');
    anchor := '    IF p_user_id IS NOT NULL THEN';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'capture_source_begin_owner_drift'; END IF;
    definition := replace(definition,anchor,anchor||E'\n        PERFORM pg_advisory_xact_lock(hashtextextended(''merian-capture-account-retirement:''||p_user_id::TEXT,0));');
    anchor := E'    SELECT COALESCE(\n        pg_catalog.ARRAY_AGG(';
    finish := '    INSERT INTO public.scan_ingestion_jobs AS existing_job (';
    first_offset := strpos(definition,anchor); last_offset := strpos(definition,finish);
    IF first_offset=0 OR last_offset<=first_offset THEN RAISE EXCEPTION 'capture_source_begin_normalization_drift'; END IF;
    definition := substr(definition,1,first_offset-1)||$body$
    capture_admission := internal.prepare_capture_source_admission(p_user_id,scan_id_uuid,p_endpoint,p_request_payload,
        p_media_counts,p_media_object_keys,p_storage_keys,p_resumable,p_inline_media_redacted,p_redacted_media_counts,p_payload_schema_version);
    IF capture_admission IS NOT NULL THEN
        SELECT COALESCE(array_agg(value::UUID),'{}'::UUID[]) INTO resolved_upload_session_ids
            FROM jsonb_array_elements_text(capture_admission->'upload_session_ids');
        stored_payload := capture_admission->'request_payload';
        resolved_manifest_checksum := capture_admission->>'manifest_checksum';
        resolved_payload_checksum := capture_admission->>'payload_checksum';
    ELSE
$body$||substr(definition,first_offset,last_offset-first_offset)||E'    END IF;\n\n'||substr(definition,last_offset);
    EXECUTE definition;

    definition := pg_get_functiondef('public.recover_inline_scan_ingestion_completion(uuid,uuid)'::regprocedure);
    anchor := '    IF p_user_id IS NOT NULL THEN';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'capture_source_inline_owner_drift'; END IF;
    definition := replace(definition,anchor,anchor||E'\n        PERFORM pg_advisory_xact_lock(hashtextextended(''merian-capture-account-retirement:''||p_user_id::TEXT,0));');
    anchor := '    SELECT jobs.*';
    IF strpos(definition,anchor)=0 THEN RAISE EXCEPTION 'capture_source_inline_recovery_drift'; END IF;
    EXECUTE replace(definition,anchor,$body$
    IF EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id=p_scan_id) THEN RETURN 'not_applicable'; END IF;
$body$||anchor);

    definition := pg_get_functiondef('internal.prepare_scan_ingestions_for_identity_merge(uuid,uuid)'::regprocedure);
    anchor := '    -- The caller already holds both profile rows';
    IF strpos(definition,anchor)=0 THEN RAISE EXCEPTION 'capture_source_merge_drift'; END IF;
    -- No late account-intake lock: the merge already holds both owner rows.
    EXECUTE replace(definition,anchor,$body$
    UPDATE internal.capture_source_admissions SET recovery=NULL,retired_at=COALESCE(retired_at,clock_timestamp()) WHERE owner_id=p_source_user_id;
    -- Immutable evidence intents cannot be reparented. The completed scan and
    -- existing History result remain the result owners; no source replay survives.
    DELETE FROM public.scan_ingestion_intents WHERE user_id=p_source_user_id
        AND scan_id IN (SELECT scan_id::TEXT FROM internal.capture_source_admissions WHERE owner_id=p_source_user_id);
$body$||anchor);
END;
$patch$;

REVOKE ALL ON FUNCTION internal.capture_source_intent_projection(JSONB),internal.capture_source_job_projection(JSONB),
    internal.prepare_capture_source_admission(UUID,UUID,TEXT,JSONB,JSONB,JSONB,TEXT[],BOOLEAN,BOOLEAN,JSONB,INTEGER),
    internal.guard_capture_source_admission(),internal.retire_capture_source_admissions() FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE internal.capture_source_admissions IS
    'Private immutable ordinary capture admission and retry witness; independent of mutable ledgers. Recovery payload is erased on retirement; owner/scan marker cannot be rebound.';
RESET statement_timeout;
RESET lock_timeout;
