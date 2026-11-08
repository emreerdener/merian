-- Inactive private transaction protocol. API roles cannot construct a stage,
-- mutate its ledger or invoke these helpers. No physical I/O is installed.
SET lock_timeout='5s';
SET statement_timeout='120s';

CREATE TABLE internal.initial_media_handoff_staging (
    scan_id UUID PRIMARY KEY, owner_id UUID NOT NULL,
    action TEXT NOT NULL CHECK(action IN ('start_copy','record_object','complete_copy','claim','verify','transfer')),
    admission_digest TEXT NOT NULL, object_id UUID, claim_token UUID, verification_digest TEXT,
    transaction_id XID8 NOT NULL UNIQUE,
    authorized_at_ms BIGINT NOT NULL, cutoff_ms BIGINT NOT NULL,
    snapshot JSONB NOT NULL CHECK(octet_length(snapshot::TEXT)<=67108864),
    events JSONB NOT NULL CHECK(jsonb_typeof(events)='array' AND jsonb_array_length(events) BETWEEN 1 AND 64 AND octet_length(events::TEXT)<=67108864),
    frames JSONB NOT NULL CHECK(jsonb_typeof(frames)='array' AND jsonb_array_length(frames) BETWEEN 1 AND 32 AND octet_length(internal.initial_canonical(frames))<=32768),
    phase TEXT NOT NULL CHECK(phase IN ('applying','complete','consuming')),
    next_root INTEGER NOT NULL CHECK(next_root BETWEEN 0 AND 32),
    registered INTEGER CHECK(registered BETWEEN 0 AND 31),
    active INTEGER[] NOT NULL CHECK(cardinality(active)<=32),
    after_seen INTEGER[] NOT NULL CHECK(cardinality(after_seen)<=32),
    closed INTEGER[] NOT NULL CHECK(cardinality(closed)<=32),
    frozen JSONB CHECK(jsonb_typeof(frozen)='array' AND jsonb_array_length(frozen)<=64 AND octet_length(frozen::TEXT)<=67108864),
    cleanup_cursor INTEGER NOT NULL CHECK(cleanup_cursor BETWEEN 0 AND 64)
);
CREATE TABLE internal.initial_media_handoff_writes (
    scan_id UUID NOT NULL REFERENCES internal.initial_media_handoff_staging(scan_id) ON DELETE CASCADE,
    ordinal INTEGER NOT NULL CHECK(ordinal BETWEEN 0 AND 63),
    frame_id INTEGER NOT NULL CHECK(frame_id BETWEEN 0 AND 31),
    relation_name TEXT NOT NULL, operation TEXT NOT NULL CHECK(operation IN ('INSERT','UPDATE','DELETE')),
    old_image JSONB CHECK(octet_length(old_image::TEXT)<=33554432),
    new_image JSONB CHECK(octet_length(new_image::TEXT)<=33554432),
    before_seen BOOLEAN NOT NULL DEFAULT FALSE,
    consumed BOOLEAN NOT NULL DEFAULT FALSE,
    observed_old JSONB CHECK(octet_length(observed_old::TEXT)<=33554432),
    observed_new JSONB CHECK(octet_length(observed_new::TEXT)<=33554432),
    PRIMARY KEY(scan_id,ordinal)
);
ALTER TABLE internal.initial_media_handoff_staging ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_media_handoff_writes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_media_handoff_staging,internal.initial_media_handoff_writes FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_media_handoff_sealed()
RETURNS BOOLEAN LANGUAGE SQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
    SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_locks l WHERE l.locktype='advisory'
        AND l.database=(SELECT oid FROM pg_catalog.pg_database WHERE datname=pg_catalog.current_database())
        AND l.pid=pg_catalog.pg_backend_pid() AND l.granted AND l.mode='ExclusiveLock'
        AND l.classid=1229801542::OID AND l.objsubid=2);
$$;

CREATE FUNCTION internal.initial_media_handoff_row_image(p_relation TEXT,p_image JSONB)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE actual JSONB; predicate TEXT;
BEGIN
    IF p_image IS NULL OR jsonb_typeof(p_image)<>'object' OR p_relation IS NULL THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    IF p_relation IN ('internal.initial_media_copy_progress','internal.initial_media_verification_claims_v2',
        'internal.initial_media_verification_receipts_v2','internal.initial_preparation_transfer_receipts',
        'internal.initial_preparation_source_fences','internal.initial_analysis_preparation_intents',
        'internal.initial_preparation_source_verifications','internal.initial_preparation_execution_grants',
        'internal.initial_preparation_output_manifests','internal.initial_preparation_outcomes') THEN
        predicate:='t.scan_id=($1->>''scan_id'')::UUID';
    ELSIF p_relation='internal.initial_preparation_source_registry' THEN
        predicate:='t.object_id=($1->>''object_id'')::UUID';
    ELSIF p_relation IN ('internal.initial_preparation_source_mapping','internal.initial_preparation_output_mapping') THEN
        predicate:='t.scan_id=($1->>''scan_id'')::UUID AND t.ordinal=($1->>''ordinal'')::INTEGER';
    ELSE RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    EXECUTE format('SELECT to_jsonb(t) FROM %s t WHERE %s',p_relation,predicate) INTO actual USING p_image;
    RETURN actual;
END; $$;

CREATE FUNCTION internal.assert_initial_media_handoff_poststate(p internal.initial_media_handoff_staging)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE actual JSONB; expected JSONB:=p.snapshot; event JSONB; images JSONB; relation TEXT; old_image JSONB; new_image JSONB;
    now_ms BIGINT; receipt_id UUID;
BEGIN
    IF p.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id() OR p.owner_id IS NULL OR p.scan_id IS NULL THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    FOR event IN SELECT value FROM jsonb_array_elements(p.events) LOOP
        relation:=event->>'relation'; old_image:=NULLIF(event->'old','null'::JSONB); new_image:=NULLIF(event->'new','null'::JSONB);
        images:=expected->relation;
        IF images IS NULL OR (old_image IS NOT NULL AND (SELECT count(*) FROM jsonb_array_elements(images) x WHERE x.value=old_image)<>1) THEN
            RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        IF old_image IS NOT NULL THEN SELECT COALESCE(jsonb_agg(value),'[]') INTO images FROM jsonb_array_elements(images) WHERE value<>old_image; END IF;
        IF new_image IS NOT NULL THEN images:=images||jsonb_build_array(new_image); END IF;
        expected:=jsonb_set(expected,ARRAY[relation],images,FALSE);
    END LOOP;
    actual:=internal.capture_initial_media_handoff_snapshot(p.owner_id,p.scan_id);
    IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(expected) x(key))
        IS DISTINCT FROM (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(actual) x(key)) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    FOR relation IN SELECT jsonb_object_keys(expected) LOOP
        IF (SELECT COALESCE(jsonb_agg(value ORDER BY value),'[]') FROM jsonb_array_elements(expected->relation))
            IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(value ORDER BY value),'[]') FROM jsonb_array_elements(actual->relation)) THEN
            RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    END LOOP;
    receipt_id:=(p.snapshot#>>'{internal.initial_preparation_admission_receipts,0,admission_receipt_id}')::UUID;
    PERFORM internal.assert_initial_admission_live_receipt(p.owner_id,p.scan_id,receipt_id);
    -- The transferred live-receipt branch already proves the complete handoff
    -- chain through assert_initial_transferred_preparation. Scope locks keep
    -- that receipt stable; retain the explicit chain proof before transfer.
    IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p.scan_id) THEN
        PERFORM internal.assert_initial_media_handoff_chain(p.owner_id,p.scan_id);
    END IF;
    now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
    IF now_ms<p.authorized_at_ms OR now_ms>=p.cutoff_ms THEN
        RAISE EXCEPTION 'initial_analysis_handoff_expired' USING ERRCODE='55000'; END IF;
END; $$;

CREATE FUNCTION internal.assert_initial_media_handoff_ledger(p internal.initial_media_handoff_staging,p_consuming BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry internal.initial_media_handoff_writes; expected JSONB; frozen_entry JSONB;
BEGIN
    IF p_consuming IS NULL OR p.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id() THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    IF (SELECT count(*) FROM internal.initial_media_handoff_writes WHERE scan_id=p.scan_id)
        <>jsonb_array_length(p.events)-(CASE WHEN p_consuming THEN p.cleanup_cursor ELSE 0 END) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    IF p_consuming AND (p.frozen IS NULL OR jsonb_array_length(p.frozen)<>jsonb_array_length(p.events)) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    FOR expected_ordinal IN 0..jsonb_array_length(p.events)-1 LOOP
        expected:=p.events->expected_ordinal;
        IF (expected->>'ordinal')::INTEGER<>expected_ordinal THEN RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        IF p_consuming THEN
            frozen_entry:=p.frozen->expected_ordinal;
            IF frozen_entry IS DISTINCT FROM jsonb_build_object('scan_id',p.scan_id,'ordinal',expected_ordinal,
                'frame_id',expected->'frame','relation_name',expected->'relation','operation',expected->'operation',
                'old_image',expected->'old','new_image',expected->'new','before_seen',TRUE,'consumed',TRUE,
                'observed_old',expected->'old','observed_new',expected->'new') THEN
                RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
            IF expected_ordinal<p.cleanup_cursor THEN
                IF EXISTS(SELECT 1 FROM internal.initial_media_handoff_writes w WHERE w.scan_id=p.scan_id AND w.ordinal=expected_ordinal) THEN
                    RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
                CONTINUE;
            END IF;
        END IF;
        SELECT * INTO entry FROM internal.initial_media_handoff_writes w WHERE w.scan_id=p.scan_id AND w.ordinal=expected_ordinal;
        IF NOT FOUND OR to_jsonb(entry) IS DISTINCT FROM jsonb_build_object('scan_id',p.scan_id,'ordinal',expected_ordinal,
            'frame_id',expected->'frame','relation_name',expected->'relation','operation',expected->'operation',
            'old_image',expected->'old','new_image',expected->'new','before_seen',TRUE,'consumed',TRUE,
            'observed_old',expected->'old','observed_new',expected->'new') THEN
            RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    END LOOP;
END; $$;

CREATE FUNCTION internal.guard_initial_media_handoff_stage()
RETURNS TRIGGER LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE plan JSONB; frame JSONB; parent_event JSONB; root INTEGER; top INTEGER; event JSONB; now_ms BIGINT;
    controls TEXT[]:=ARRAY['phase','next_root','registered','active','after_seen','closed','frozen','cleanup_cursor'];
    before_control JSONB; after_control JSONB; completed internal.initial_media_handoff_staging;
    matches INTEGER; candidate INTEGER; changed BOOLEAN; parent_id INTEGER;
BEGIN
    IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    IF TG_OP='INSERT' THEN
        IF internal.initial_media_handoff_sealed() OR internal.initial_admission_sealed() OR internal.initial_cancellation_sealed()
            OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_staging WHERE transaction_id=pg_catalog.pg_current_xact_id())
            OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE transaction_id=pg_catalog.pg_current_xact_id())
            OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_catalog.pg_current_xact_id())
            OR (to_jsonb(NEW)-ARRAY['scan_id','owner_id','action','admission_digest','object_id','claim_token','verification_digest'])
                <>jsonb_build_object('transaction_id',NULL,'authorized_at_ms',NULL,'cutoff_ms',NULL,'snapshot',NULL,'events',NULL,'frames',NULL,
                    'phase',NULL,'next_root',NULL,'registered',NULL,'active',NULL,'after_seen',NULL,'closed',NULL,'frozen',NULL,'cleanup_cursor',NULL) THEN
            RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        plan:=internal.plan_initial_media_handoff_mutation(NEW.owner_id,NEW.scan_id,NEW.action,NEW.admission_digest,
            NEW.object_id,NEW.claim_token,NEW.verification_digest);
        NEW.transaction_id:=pg_catalog.pg_current_xact_id(); NEW.authorized_at_ms:=(plan->>'authorized_at_ms')::BIGINT;
        NEW.cutoff_ms:=(plan->>'cutoff_ms')::BIGINT; NEW.snapshot:=plan->'snapshot'; NEW.events:=plan->'events'; NEW.frames:=plan->'frames';
        NEW.phase:='applying'; NEW.next_root:=0; NEW.active:=ARRAY[]::INTEGER[]; NEW.after_seen:=ARRAY[]::INTEGER[]; NEW.closed:=ARRAY[]::INTEGER[]; NEW.cleanup_cursor:=0;
        RETURN NEW;
    END IF;
    IF OLD.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id() THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    IF TG_OP='DELETE' THEN
        IF OLD.phase<>'consuming' OR NOT internal.initial_media_handoff_sealed()
            OR OLD.cleanup_cursor<>jsonb_array_length(OLD.events) THEN
            RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        PERFORM internal.assert_initial_media_handoff_ledger(OLD,TRUE);
        PERFORM internal.assert_initial_media_handoff_poststate(OLD);
        RETURN OLD;
    END IF;
    IF (to_jsonb(NEW)-controls) IS DISTINCT FROM (to_jsonb(OLD)-controls) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    before_control:=to_jsonb(OLD); after_control:=to_jsonb(NEW);
    now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
    IF now_ms<OLD.authorized_at_ms OR now_ms>=OLD.cutoff_ms THEN
        RAISE EXCEPTION 'initial_analysis_handoff_expired' USING ERRCODE='55000'; END IF;
    IF OLD.phase='complete' AND NEW.phase='consuming' AND internal.initial_media_handoff_sealed()
        AND (before_control-'phase')=(after_control-'phase') THEN
        PERFORM internal.assert_initial_media_handoff_ledger(OLD,FALSE);
        PERFORM internal.assert_initial_media_handoff_poststate(OLD); RETURN NEW;
    END IF;
    IF OLD.phase='consuming' AND internal.initial_media_handoff_sealed()
        AND NEW.cleanup_cursor=OLD.cleanup_cursor+1 AND (before_control-'cleanup_cursor')=(after_control-'cleanup_cursor') THEN
        PERFORM internal.assert_initial_media_handoff_ledger(NEW,TRUE); RETURN NEW;
    END IF;
    IF OLD.phase<>'applying' OR internal.initial_media_handoff_sealed() THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    IF NEW.phase='complete' AND (before_control-'phase')=(after_control-'phase') THEN
        IF OLD.registered IS NOT NULL OR cardinality(OLD.active)<>0
            OR cardinality(OLD.closed)<>jsonb_array_length(OLD.frames) OR cardinality(OLD.after_seen)<>jsonb_array_length(OLD.frames)
            OR OLD.next_root<>(SELECT count(*) FROM jsonb_array_elements(OLD.frames) x WHERE x.value->>'parent' IS NULL) THEN
            RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        PERFORM internal.assert_initial_media_handoff_ledger(OLD,FALSE);
        PERFORM internal.assert_initial_media_handoff_poststate(OLD);
        -- Freeze exact consumed proof before any deletion. Its size includes
        -- expected and observed images, so preflight the doubled row storage.
        IF (SELECT COALESCE(sum(octet_length(to_jsonb(w)::TEXT)+2),0)+2 FROM internal.initial_media_handoff_writes w WHERE scan_id=OLD.scan_id)>67108864 THEN
            RAISE EXCEPTION 'initial_analysis_handoff_bounds' USING ERRCODE='54000'; END IF;
        SELECT jsonb_agg(to_jsonb(w) ORDER BY ordinal) INTO NEW.frozen FROM internal.initial_media_handoff_writes w WHERE scan_id=OLD.scan_id;
        RETURN NEW;
    END IF;
    IF NEW.phase<>'applying' THEN RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    SELECT (value->>'id')::INTEGER INTO root FROM jsonb_array_elements(OLD.frames)
        WHERE value->>'parent' IS NULL ORDER BY (value->>'id')::INTEGER OFFSET OLD.next_root LIMIT 1;
    IF OLD.registered IS NULL AND cardinality(OLD.active)=0 AND NEW.registered=root
        AND (before_control-'registered')=(after_control-'registered') THEN
        IF (SELECT count(*) FROM internal.initial_media_handoff_writes WHERE scan_id=OLD.scan_id)<>jsonb_array_length(OLD.events) THEN
            RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        RETURN NEW;
    END IF;
    -- BEFORE callbacks may overlap across siblings. The immutable DAG, not
    -- callback nesting, determines parentage. Append one uniquely eligible frame.
    IF cardinality(NEW.active)=cardinality(OLD.active)+1 AND NEW.active[1:cardinality(OLD.active)]=OLD.active
        AND (before_control-ARRAY['active','registered'])=(after_control-ARRAY['active','registered']) THEN
        top:=NEW.active[cardinality(NEW.active)]; frame:=OLD.frames->top;
        IF frame IS NULL OR top=ANY(OLD.closed) OR top=ANY(OLD.active) OR top=ANY(OLD.after_seen) OR NEW.registered IS NOT NULL
            OR (frame->>'id')::INTEGER IS DISTINCT FROM top THEN RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        parent_id:=(frame->>'parent')::INTEGER;
        IF parent_id IS NULL THEN
            IF cardinality(OLD.active)<>0 OR top IS DISTINCT FROM OLD.registered OR top IS DISTINCT FROM root THEN
                RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        ELSE
            IF OLD.registered IS NOT NULL OR NOT parent_id=ANY(OLD.active) OR parent_id=ANY(OLD.closed) THEN
                RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
            SELECT count(*) INTO matches FROM jsonb_array_elements(OLD.events) x
                WHERE (value->>'frame')::INTEGER=parent_id;
            IF matches<>1 THEN RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
            SELECT value INTO parent_event FROM jsonb_array_elements(OLD.events) WHERE (value->>'frame')::INTEGER=parent_id;
            IF parent_event->>'operation'<>'DELETE'
                OR NOT EXISTS(SELECT 1 FROM internal.initial_media_handoff_writes w WHERE w.scan_id=OLD.scan_id
                    AND w.ordinal=(parent_event->>'ordinal')::INTEGER AND w.frame_id=parent_id AND w.before_seen
                    AND w.operation='DELETE' AND w.relation_name=parent_event->>'relation'
                    AND w.old_image=parent_event->'old' AND w.new_image IS NULL)
                OR internal.initial_media_handoff_row_image(parent_event->>'relation',parent_event->'old') IS NOT NULL THEN
                RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        END IF;
        RETURN NEW;
    END IF;
    -- Observe AFTER once, then derive logical closure bottom-up. A parent AFTER
    -- callback may precede descendant callbacks; it cannot close their subtree.
    IF cardinality(NEW.after_seen)=cardinality(OLD.after_seen)+1
        AND NEW.after_seen[1:cardinality(OLD.after_seen)]=OLD.after_seen
        AND (before_control-'after_seen')=(after_control-'after_seen') THEN
        top:=NEW.after_seen[cardinality(NEW.after_seen)];
        IF top IS NULL OR NOT top=ANY(OLD.active) OR top=ANY(OLD.after_seen) OR top=ANY(OLD.closed) THEN
            RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        FOR event IN SELECT value FROM jsonb_array_elements(OLD.events) WHERE (value->>'frame')::INTEGER=top LOOP
            IF NOT EXISTS(SELECT 1 FROM internal.initial_media_handoff_writes w WHERE w.scan_id=OLD.scan_id
                AND w.ordinal=(event->>'ordinal')::INTEGER AND w.before_seen AND w.consumed
                AND w.observed_old IS NOT DISTINCT FROM w.old_image AND w.observed_new IS NOT DISTINCT FROM w.new_image) THEN
                RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        END LOOP;
        LOOP
            changed:=FALSE;
            FOREACH candidate IN ARRAY NEW.active LOOP
                IF candidate=ANY(NEW.after_seen) AND NOT EXISTS(
                    SELECT 1 FROM jsonb_array_elements(OLD.frames) x WHERE (value->>'parent')::INTEGER=candidate
                        AND NOT (value->>'id')::INTEGER=ANY(NEW.closed)) THEN
                    NEW.active:=array_remove(NEW.active,candidate); NEW.closed:=NEW.closed||candidate; changed:=TRUE;
                    IF OLD.frames->candidate->>'parent' IS NULL THEN
                        IF candidate IS DISTINCT FROM root THEN RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
                        NEW.next_root:=NEW.next_root+1;
                    END IF;
                END IF;
            END LOOP;
            EXIT WHEN NOT changed;
        END LOOP;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000';
END; $$;

CREATE FUNCTION internal.require_initial_media_handoff_completion()
RETURNS TRIGGER LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_media_handoff_staging;
BEGIN
    stage:=CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
    IF EXISTS(SELECT 1 FROM internal.initial_media_handoff_staging WHERE scan_id=stage.scan_id)
        OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_writes WHERE scan_id=stage.scan_id) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_unfinished' USING ERRCODE='55000'; END IF;
    IF TG_OP='DELETE' THEN
        -- Snapshot, events, identity and timing are immutable across stage
        -- updates. The terminal DELETE carries that same witness plus the
        -- consumed frozen ledger. Earlier callbacks still reject unfinished
        -- work; do not repeat full proof validation for every control update.
        PERFORM internal.assert_initial_media_handoff_poststate(stage);
        IF stage.phase<>'consuming' OR stage.cleanup_cursor<>jsonb_array_length(stage.events) THEN
            RAISE EXCEPTION 'initial_analysis_handoff_unfinished' USING ERRCODE='55000'; END IF;
        PERFORM internal.assert_initial_media_handoff_ledger(stage,TRUE);
    END IF;
    RETURN NULL;
END; $$;

CREATE TRIGGER a0_initial_media_handoff_stage BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_media_handoff_staging
    FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_handoff_stage();
CREATE TRIGGER a0_initial_media_handoff_stage_truncate BEFORE TRUNCATE ON internal.initial_media_handoff_staging
    FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_media_handoff_stage();
CREATE CONSTRAINT TRIGGER initial_media_handoff_completion AFTER INSERT OR UPDATE OR DELETE ON internal.initial_media_handoff_staging
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.require_initial_media_handoff_completion();

CREATE FUNCTION internal.guard_initial_media_handoff_write()
RETURNS TRIGGER LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_media_handoff_staging; expected JSONB; entry_scan UUID; image JSONB;
BEGIN
    IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    entry_scan:=CASE WHEN TG_OP='DELETE' THEN OLD.scan_id ELSE NEW.scan_id END;
    SELECT * INTO stage FROM internal.initial_media_handoff_staging WHERE scan_id=entry_scan;
    IF NOT FOUND OR stage.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id() THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    IF TG_OP='DELETE' THEN
        IF stage.phase<>'consuming' OR NOT internal.initial_media_handoff_sealed() OR OLD.ordinal<>stage.cleanup_cursor THEN
            RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        IF TG_WHEN='BEFORE' THEN
            PERFORM internal.assert_initial_media_handoff_ledger(stage,TRUE);
            IF to_jsonb(OLD) IS DISTINCT FROM stage.frozen->stage.cleanup_cursor THEN
                RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        ELSE
            UPDATE internal.initial_media_handoff_staging SET cleanup_cursor=cleanup_cursor+1 WHERE scan_id=entry_scan;
        END IF;
        RETURN OLD;
    END IF;
    IF stage.phase<>'applying' OR internal.initial_media_handoff_sealed() THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    expected:=stage.events->NEW.ordinal;
    IF expected IS NULL OR (expected->>'ordinal')::INTEGER IS DISTINCT FROM NEW.ordinal THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    IF TG_OP='INSERT' THEN
        IF cardinality(stage.active)<>0 OR cardinality(stage.closed)<>0 OR stage.registered IS NOT NULL OR stage.next_root<>0
            OR NEW.ordinal<>(SELECT count(*) FROM internal.initial_media_handoff_writes WHERE scan_id=entry_scan)
            OR (to_jsonb(NEW)-ARRAY['scan_id','ordinal']) IS DISTINCT FROM
                jsonb_build_object('frame_id',NULL,'relation_name',NULL,'operation',NULL,'old_image',NULL,'new_image',NULL,
                    'before_seen',FALSE,'consumed',FALSE,'observed_old',NULL,'observed_new',NULL) THEN
            RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        NEW.frame_id:=(expected->>'frame')::INTEGER; NEW.relation_name:=expected->>'relation'; NEW.operation:=expected->>'operation';
        NEW.old_image:=NULLIF(expected->'old','null'::JSONB); NEW.new_image:=NULLIF(expected->'new','null'::JSONB);
        image:=internal.initial_media_handoff_row_image(NEW.relation_name,COALESCE(NEW.old_image,NEW.new_image));
        IF image IS DISTINCT FROM NEW.old_image THEN RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        RETURN NEW;
    END IF;
    IF OLD.consumed OR NOT NEW.frame_id=ANY(stage.active) OR NEW.frame_id=ANY(stage.after_seen)
        OR (to_jsonb(OLD)-ARRAY['before_seen','consumed','observed_old','observed_new'])
            IS DISTINCT FROM (to_jsonb(NEW)-ARRAY['before_seen','consumed','observed_old','observed_new'])
        OR (to_jsonb(OLD)-ARRAY['before_seen','consumed','observed_old','observed_new'])
            IS DISTINCT FROM jsonb_build_object('scan_id',entry_scan,'ordinal',NEW.ordinal,
                'frame_id',expected->'frame','relation_name',expected->'relation','operation',expected->'operation',
                'old_image',expected->'old','new_image',expected->'new') THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    IF NOT OLD.before_seen AND NEW.before_seen AND NOT NEW.consumed
        AND OLD.observed_old IS NULL AND OLD.observed_new IS NULL AND NEW.observed_old IS NULL AND NEW.observed_new IS NULL
        AND internal.initial_media_handoff_row_image(NEW.relation_name,COALESCE(NEW.old_image,NEW.new_image)) IS NOT DISTINCT FROM NEW.old_image THEN
        RETURN NEW;
    END IF;
    IF NOT OLD.before_seen OR NOT NEW.before_seen OR NOT NEW.consumed
        OR OLD.observed_old IS NOT NULL OR OLD.observed_new IS NOT NULL
        OR NEW.observed_old IS DISTINCT FROM OLD.old_image OR NEW.observed_new IS DISTINCT FROM OLD.new_image
        OR internal.initial_media_handoff_row_image(NEW.relation_name,COALESCE(NEW.new_image,NEW.old_image)) IS DISTINCT FROM NEW.new_image THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER a0_initial_media_handoff_write BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_media_handoff_writes
    FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_handoff_write();
CREATE TRIGGER z9_initial_media_handoff_write AFTER DELETE ON internal.initial_media_handoff_writes
    FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_handoff_write();
CREATE TRIGGER a0_initial_media_handoff_write_truncate BEFORE TRUNCATE ON internal.initial_media_handoff_writes
    FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_media_handoff_write();

-- Ordinary public-table callers must not need access to the private stage.
-- This trigger-only owner reads the current transaction's stage and changes
-- only its proven frame ledger; parent-table RLS and grants remain unchanged.
-- Direct EXECUTE stays revoked from every API role below.
CREATE FUNCTION internal.guard_initial_media_handoff_statement()
RETURNS TRIGGER LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE stage internal.initial_media_handoff_staging; frame JSONB; chosen INTEGER; matches INTEGER;
    relation TEXT:=TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME;
BEGIN
    IF internal.initial_media_handoff_sealed() THEN RAISE EXCEPTION 'initial_analysis_handoff_sealed' USING ERRCODE='55000'; END IF;
    SELECT * INTO stage FROM internal.initial_media_handoff_staging WHERE transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND THEN RETURN NULL; END IF;
    IF stage.phase<>'applying' OR TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    IF TG_WHEN='BEFORE' THEN
        IF cardinality(stage.active)=0 THEN
            chosen:=stage.registered;
        ELSE
            SELECT count(*),min((value->>'id')::INTEGER) INTO matches,chosen FROM jsonb_array_elements(stage.frames)
                WHERE (value->>'parent')::INTEGER=ANY(stage.active)
                    AND value->>'relation'=relation AND value->>'operation'=TG_OP
                    AND NOT (value->>'id')::INTEGER=ANY(stage.closed) AND NOT (value->>'id')::INTEGER=ANY(stage.active)
                    AND NOT (value->>'id')::INTEGER=ANY(stage.after_seen);
            IF matches<>1 THEN RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        END IF;
        frame:=stage.frames->chosen;
        IF frame IS NULL OR frame->>'relation' IS DISTINCT FROM relation OR frame->>'operation' IS DISTINCT FROM TG_OP THEN
            RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        UPDATE internal.initial_media_handoff_staging SET active=active||chosen,registered=NULL WHERE scan_id=stage.scan_id;
    ELSE
        SELECT count(*),min((value->>'id')::INTEGER) INTO matches,chosen FROM jsonb_array_elements(stage.frames)
            WHERE (value->>'id')::INTEGER=ANY(stage.active) AND NOT (value->>'id')::INTEGER=ANY(stage.after_seen)
                AND value->>'relation'=relation AND value->>'operation'=TG_OP;
        IF matches<>1 THEN RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        UPDATE internal.initial_media_handoff_staging SET after_seen=after_seen||chosen WHERE scan_id=stage.scan_id;
    END IF;
    RETURN NULL;
END; $$;

CREATE FUNCTION internal.guard_initial_media_handoff_domain_row()
RETURNS TRIGGER LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_media_handoff_staging; entry internal.initial_media_handoff_writes;
    prior_image JSONB; next_image JSONB; matches INTEGER; relation TEXT:=TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME; scan UUID;
BEGIN
    prior_image:=CASE WHEN TG_OP='INSERT' THEN NULL ELSE to_jsonb(OLD) END;
    next_image:=CASE WHEN TG_OP='DELETE' THEN NULL ELSE to_jsonb(NEW) END;
    scan:=(COALESCE(prior_image,next_image)->>'scan_id')::UUID;
    SELECT * INTO stage FROM internal.initial_media_handoff_staging WHERE transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND THEN
        IF relation IN ('internal.initial_media_copy_progress','internal.initial_media_verification_claims_v2',
            'internal.initial_media_verification_receipts_v2','internal.initial_preparation_transfer_receipts') THEN
            IF TG_OP<>'DELETE' OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=scan AND state='retired')
                OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=scan AND state='retired')
                OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=scan AND NOT retired)
                OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=scan AND NOT retired)
                OR NOT (EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=scan)
                    OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=(prior_image->>'owner_id')::UUID)
                    OR EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=scan AND internal.initial_cancellation_dispatch(state) IS NOT NULL)) THEN
                RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        END IF;
        IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    SELECT count(*) INTO matches FROM internal.initial_media_handoff_writes w WHERE w.scan_id=stage.scan_id
        AND w.frame_id=ANY(stage.active) AND NOT w.frame_id=ANY(stage.after_seen) AND NOT w.consumed
        AND w.before_seen=(TG_WHEN='AFTER') AND w.relation_name=relation AND w.operation=TG_OP
        AND w.old_image IS NOT DISTINCT FROM prior_image AND w.new_image IS NOT DISTINCT FROM next_image;
    IF matches<>1 OR stage.phase<>'applying' OR scan IS DISTINCT FROM stage.scan_id THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    SELECT * INTO STRICT entry FROM internal.initial_media_handoff_writes w WHERE w.scan_id=stage.scan_id
        AND w.frame_id=ANY(stage.active) AND NOT w.frame_id=ANY(stage.after_seen) AND NOT w.consumed
        AND w.before_seen=(TG_WHEN='AFTER') AND w.relation_name=relation AND w.operation=TG_OP
        AND w.old_image IS NOT DISTINCT FROM prior_image AND w.new_image IS NOT DISTINCT FROM next_image;
    IF TG_WHEN='BEFORE' THEN
        UPDATE internal.initial_media_handoff_writes SET before_seen=TRUE WHERE scan_id=stage.scan_id AND ordinal=entry.ordinal;
    ELSE
        UPDATE internal.initial_media_handoff_writes SET consumed=TRUE,observed_old=prior_image,observed_new=next_image
            WHERE scan_id=stage.scan_id AND ordinal=entry.ordinal;
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END; $$;

-- Fixed domain statement guards cover both expected mutations and every
-- accounting/provider/erasure competitor. Empty extra statements are denied.
DO $handoff_statement_guards$
DECLARE relation TEXT;
BEGIN
    FOR relation IN SELECT relation_name FROM internal.initial_cancellation_seal_catalog()
        UNION SELECT unnest(ARRAY['internal.initial_analysis_rollout','internal.initial_preparation_profile_eligibility',
            'internal.initial_preparation_backend_eligibility','internal.initial_preparation_handoff_eligibility']) LOOP
        EXECUTE format('CREATE TRIGGER a000_initial_media_handoff_statement BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_media_handoff_statement()',relation);
        EXECUTE format('CREATE TRIGGER z999_initial_media_handoff_statement AFTER INSERT OR UPDATE OR DELETE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_media_handoff_statement()',relation);
    END LOOP;
    FOREACH relation IN ARRAY ARRAY['internal.initial_media_copy_progress','internal.initial_media_verification_claims_v2',
        'internal.initial_media_verification_receipts_v2','internal.initial_preparation_transfer_receipts',
        'internal.initial_preparation_source_fences','internal.initial_preparation_source_registry',
        'internal.initial_analysis_preparation_intents','internal.initial_preparation_source_mapping',
        'internal.initial_preparation_source_verifications','internal.initial_preparation_execution_grants',
        'internal.initial_preparation_output_manifests','internal.initial_preparation_output_mapping','internal.initial_preparation_outcomes'] LOOP
        EXECUTE format('CREATE TRIGGER a000_initial_media_handoff_row BEFORE INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_handoff_domain_row()',relation);
        EXECUTE format('CREATE TRIGGER z999_initial_media_handoff_row AFTER INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_handoff_domain_row()',relation);
    END LOOP;
END; $handoff_statement_guards$;

CREATE FUNCTION internal.initial_media_handoff_transfer_event(p_relation TEXT,p_old JSONB,p_new JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_media_handoff_staging; receipt internal.initial_media_handoff_writes;
    source_event internal.initial_media_handoff_writes;
BEGIN
    SELECT * INTO stage FROM internal.initial_media_handoff_staging WHERE transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND OR stage.action<>'transfer' OR stage.phase<>'applying' OR internal.initial_media_handoff_sealed()
        OR p_relation NOT IN ('internal.initial_preparation_source_fences','internal.initial_analysis_preparation_intents')
        OR (SELECT count(*) FROM internal.initial_media_handoff_writes WHERE scan_id=stage.scan_id
            AND frame_id=ANY(stage.active) AND NOT frame_id=ANY(stage.after_seen) AND before_seen AND NOT consumed AND relation_name=p_relation
            AND operation=CASE WHEN p_new IS NULL THEN 'DELETE' ELSE 'UPDATE' END
            AND old_image IS NOT DISTINCT FROM p_old AND new_image IS NOT DISTINCT FROM p_new)<>1 THEN RETURN FALSE; END IF;
    SELECT * INTO receipt FROM internal.initial_media_handoff_writes WHERE scan_id=stage.scan_id AND ordinal=0;
    IF NOT FOUND OR NOT receipt.consumed OR receipt.relation_name<>'internal.initial_preparation_transfer_receipts'
        OR receipt.operation<>'INSERT' OR receipt.observed_new IS DISTINCT FROM receipt.new_image
        OR internal.initial_media_handoff_row_image(receipt.relation_name,receipt.new_image) IS DISTINCT FROM receipt.new_image THEN RETURN FALSE; END IF;
    IF p_relation='internal.initial_analysis_preparation_intents' THEN
        FOR source_event IN SELECT * FROM internal.initial_media_handoff_writes WHERE scan_id=stage.scan_id
            AND relation_name IN ('internal.initial_preparation_source_fences','internal.initial_preparation_source_registry') LOOP
            IF NOT source_event.consumed OR source_event.observed_old IS DISTINCT FROM source_event.old_image
                OR source_event.observed_new IS DISTINCT FROM source_event.new_image
                OR internal.initial_media_handoff_row_image(source_event.relation_name,source_event.new_image) IS DISTINCT FROM source_event.new_image THEN RETURN FALSE; END IF;
        END LOOP;
    END IF;
    RETURN TRUE;
END; $$;

DO $handoff_exact_transfer_exceptions$
DECLARE definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
    SELECT pg_get_functiondef('internal.guard_initial_source_storage()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$  IF TG_TABLE_NAME='initial_preparation_source_fences' THEN$before$;
    replacement:=anchor||E'\n'||$after$   IF internal.initial_media_handoff_transfer_event('internal.initial_preparation_source_fences',to_jsonb(OLD),to_jsonb(NEW)) THEN RETURN NEW; END IF;$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff exact source guard drift'; END IF;
    EXECUTE replace(definition,anchor,replacement);
    SELECT pg_get_functiondef('internal.guard_initial_preparation_storage()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$ ELSIF TG_OP='DELETE' THEN$before$;
    replacement:=anchor||E'\n'||$after$  IF internal.initial_media_handoff_transfer_event('internal.initial_analysis_preparation_intents',to_jsonb(OLD),NULL) THEN RETURN OLD; END IF;$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff exact intent guard drift'; END IF;
    EXECUTE replace(definition,anchor,replacement);
    SELECT pg_get_functiondef('internal.retire_initial_sources_before_erasure()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$ IF OLD.canonical_candidate::JSONB->>'variant'='media_sources' THEN$before$;
    replacement:=$after$ -- Transfer has already retired the exact captured union. Calling the
 -- generic helper here would emit unregistered duplicate UPDATE statements.
 IF internal.initial_media_handoff_transfer_event('internal.initial_analysis_preparation_intents',to_jsonb(OLD),NULL) THEN RETURN OLD; END IF;
$after$||anchor;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff exact erasure guard drift'; END IF;
    EXECUTE replace(definition,anchor,replacement);
END; $handoff_exact_transfer_exceptions$;

DO $handoff_transient_reciprocal_seals$
DECLARE definition TEXT; anchor TEXT; relation TEXT;
BEGIN
    SELECT pg_get_functiondef('internal.initial_cancellation_seal_catalog()'::REGPROCEDURE) INTO STRICT definition;
    anchor:='        (''internal.initial_preparation_admission_staging''),';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff transient seal catalog drift'; END IF;
    EXECUTE replace(definition,anchor,anchor||E'\n'||
        '        (''internal.initial_media_handoff_staging''),'||E'\n'||'        (''internal.initial_media_handoff_writes''),');
    FOREACH relation IN ARRAY ARRAY['internal.initial_media_handoff_staging','internal.initial_media_handoff_writes'] LOOP
        EXECUTE format('CREATE TRIGGER a00_initial_cancellation_seal BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_seal()',relation);
        EXECUTE format('CREATE TRIGGER a00_initial_admission_seal BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_admission_seal()',relation);
    END LOOP;
END; $handoff_transient_reciprocal_seals$;

-- Execute only the already captured transaction-local graph. Fixed operation
-- owners will create the stage after their distinct replay/argument checks;
-- this helper accepts neither an action nor caller-provided images.
CREATE FUNCTION internal.execute_initial_media_handoff_stage(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_media_handoff_staging; frame JSONB; event JSONB; image JSONB;
BEGIN
    SELECT * INTO stage FROM internal.initial_media_handoff_staging WHERE scan_id=p_scan;
    IF NOT FOUND OR stage.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id() OR stage.phase<>'applying'
        OR stage.next_root<>0 OR stage.registered IS NOT NULL OR cardinality(stage.active)<>0 OR cardinality(stage.closed)<>0 OR cardinality(stage.after_seen)<>0
        OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_writes WHERE scan_id=p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    FOR entry_ordinal IN 0..jsonb_array_length(stage.events)-1 LOOP
        INSERT INTO internal.initial_media_handoff_writes(scan_id,ordinal) VALUES(p_scan,entry_ordinal);
    END LOOP;
    FOR frame IN SELECT value FROM jsonb_array_elements(stage.frames) WHERE value->>'parent' IS NULL ORDER BY (value->>'id')::INTEGER LOOP
        IF jsonb_array_length(frame->'events')<>1 THEN RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
        event:=stage.events->((frame#>>'{events,0}')::INTEGER); image:=NULLIF(event->'new','null'::JSONB);
        UPDATE internal.initial_media_handoff_staging SET registered=(frame->>'id')::INTEGER WHERE scan_id=p_scan;
        CASE frame->>'relation'
        WHEN 'internal.initial_media_copy_progress' THEN
            IF frame->>'operation'='INSERT' THEN
                INSERT INTO internal.initial_media_copy_progress SELECT * FROM jsonb_populate_record(NULL::internal.initial_media_copy_progress,image);
            ELSE
                UPDATE internal.initial_media_copy_progress SET completed_objects=image->>'completed_objects',
                    last_object_at_ms=(image->>'last_object_at_ms')::BIGINT,completed_at_ms=(image->>'completed_at_ms')::BIGINT WHERE scan_id=p_scan;
            END IF;
        WHEN 'internal.initial_media_verification_claims_v2' THEN
            INSERT INTO internal.initial_media_verification_claims_v2 SELECT * FROM jsonb_populate_record(NULL::internal.initial_media_verification_claims_v2,image);
        WHEN 'internal.initial_media_verification_receipts_v2' THEN
            INSERT INTO internal.initial_media_verification_receipts_v2 SELECT * FROM jsonb_populate_record(NULL::internal.initial_media_verification_receipts_v2,image);
        WHEN 'internal.initial_preparation_transfer_receipts' THEN
            INSERT INTO internal.initial_preparation_transfer_receipts SELECT * FROM jsonb_populate_record(NULL::internal.initial_preparation_transfer_receipts,image);
        WHEN 'internal.initial_preparation_source_fences' THEN
            UPDATE internal.initial_preparation_source_fences SET state='retired' WHERE scan_id=p_scan;
        WHEN 'internal.initial_preparation_source_registry' THEN
            UPDATE internal.initial_preparation_source_registry SET retired=TRUE WHERE object_id=(image->>'object_id')::UUID;
        WHEN 'internal.initial_analysis_preparation_intents' THEN
            DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
        ELSE RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000';
        END CASE;
    END LOOP;
    -- Transfer-state constraints see the still-present stage/provisional receipt.
    SET CONSTRAINTS internal.initial_source_intent_cohort,internal.initial_source_fence_cohort,
        internal.initial_source_mapping_cohort,internal.initial_source_registry_cohort,internal.initial_execution_cohort IMMEDIATE;
    UPDATE internal.initial_media_handoff_staging SET phase='complete' WHERE scan_id=p_scan;
    IF NOT pg_catalog.pg_try_advisory_xact_lock(1229801542,pg_catalog.hashtext(p_scan::TEXT)) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_seal_busy' USING ERRCODE='55P03'; END IF;
    UPDATE internal.initial_media_handoff_staging SET phase='consuming' WHERE scan_id=p_scan;
    FOR entry_ordinal IN 0..jsonb_array_length(stage.events)-1 LOOP
        DELETE FROM internal.initial_media_handoff_writes WHERE scan_id=p_scan AND ordinal=entry_ordinal;
    END LOOP;
    SELECT * INTO STRICT stage FROM internal.initial_media_handoff_staging WHERE scan_id=p_scan;
    DELETE FROM internal.initial_media_handoff_staging WHERE scan_id=p_scan;
    SET CONSTRAINTS ALL IMMEDIATE;
    PERFORM internal.assert_initial_media_handoff_poststate(stage);
END; $$;

REVOKE ALL ON FUNCTION internal.guard_initial_media_handoff_write(),internal.guard_initial_media_handoff_statement(),
    internal.guard_initial_media_handoff_domain_row(),internal.initial_media_handoff_transfer_event(TEXT,JSONB,JSONB),
    internal.execute_initial_media_handoff_stage(UUID)
    FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION internal.initial_media_handoff_sealed(),internal.initial_media_handoff_row_image(TEXT,JSONB),
    internal.assert_initial_media_handoff_poststate(internal.initial_media_handoff_staging),
    internal.assert_initial_media_handoff_ledger(internal.initial_media_handoff_staging,BOOLEAN),
    internal.guard_initial_media_handoff_stage(),internal.require_initial_media_handoff_completion()
    FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;
