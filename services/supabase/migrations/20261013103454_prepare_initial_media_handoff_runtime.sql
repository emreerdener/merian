-- Private, inactive admitted-media handoff v2. The original twelve-component
-- admitted receipt is the only context; no API role receives mutation authority.
SET lock_timeout='5s';
SET statement_timeout='120s';

CREATE FUNCTION internal.initial_media_copy_progress_shape(
    p_objects TEXT,p_started BIGINT,p_last BIGINT,p_completed BIGINT
) RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE objects JSONB; item JSONB; previous UUID; object_key UUID; shape JSONB;
BEGIN
    IF p_objects IS NULL OR pg_catalog.octet_length(p_objects)>8192
        OR p_started IS NULL OR p_started<0 OR p_started>9007199254740991 THEN RETURN FALSE; END IF;
    BEGIN objects:=p_objects::JSONB;
    EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE; END;
    IF pg_catalog.jsonb_typeof(objects) IS DISTINCT FROM 'array'
        OR internal.initial_canonical(objects) IS DISTINCT FROM p_objects THEN RETURN FALSE; END IF;
    IF pg_catalog.jsonb_array_length(objects)>10 THEN RETURN FALSE; END IF;
    shape:=internal.initial_media_handoff_proof_schema()#>'{verification_receipt,properties,objects,items}';
    FOR item IN SELECT value FROM pg_catalog.jsonb_array_elements(objects) LOOP
        IF NOT internal.initial_schema_matches(item,shape) THEN RETURN FALSE; END IF;
        object_key:=(item->>'object_id')::UUID;
        IF previous IS NOT NULL AND object_key<=previous THEN RETURN FALSE; END IF;
        previous:=object_key;
    END LOOP;
    IF previous IS NULL THEN RETURN p_last IS NULL AND p_completed IS NULL; END IF;
    RETURN p_last IS NOT NULL AND p_last>=p_started AND p_last<=9007199254740991
        AND (p_completed IS NULL OR (p_completed>=p_last AND p_completed<=9007199254740991));
END; $$;

CREATE FUNCTION internal.initial_media_handoff_document_shape(
    p_kind TEXT,p_owner UUID,p_scan UUID,p_document TEXT,p_digest TEXT
) RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE document JSONB; binding JSONB;
BEGIN
    IF p_owner IS NULL OR p_scan IS NULL OR p_document IS NULL OR p_digest IS NULL THEN RETURN FALSE; END IF;
    document:=internal.parse_initial_media_handoff_proof(p_kind,p_document);
    binding:=CASE p_kind WHEN 'claim' THEN document->'binding'
        WHEN 'verification_receipt' THEN document#>'{claim,binding}'
        WHEN 'transfer_receipt' THEN document#>'{verification_receipt,claim,binding}' END;
    RETURN binding->>'owner_id'=p_owner::TEXT AND binding->>'scan_id'=p_scan::TEXT
        AND p_digest=internal.initial_media_handoff_proof_digest(p_kind,p_document);
END; $$;

CREATE TABLE internal.initial_media_copy_progress (
    scan_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    admission_receipt_digest TEXT NOT NULL CHECK(admission_receipt_digest ~ '^[0-9a-f]{64}$'),
    copy_adapter_digest TEXT NOT NULL CHECK(copy_adapter_digest ~ '^[0-9a-f]{64}$'),
    started_at_ms BIGINT NOT NULL,
    completed_objects TEXT NOT NULL,
    last_object_at_ms BIGINT,
    completed_at_ms BIGINT,
    UNIQUE(scan_id,owner_id),
    FOREIGN KEY(scan_id,owner_id) REFERENCES internal.initial_preparation_admission_receipts(scan_id,owner_id) ON DELETE CASCADE,
    CHECK(internal.initial_media_copy_progress_shape(completed_objects,started_at_ms,last_object_at_ms,completed_at_ms))
);
CREATE TABLE internal.initial_media_verification_claims_v2 (
    scan_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    claim TEXT NOT NULL,
    claim_digest TEXT NOT NULL,
    UNIQUE(scan_id,owner_id),
    FOREIGN KEY(scan_id,owner_id) REFERENCES internal.initial_preparation_admission_receipts(scan_id,owner_id) ON DELETE CASCADE,
    CHECK(internal.initial_media_handoff_document_shape('claim',owner_id,scan_id,claim,claim_digest))
);
CREATE TABLE internal.initial_media_verification_receipts_v2 (
    scan_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    receipt TEXT NOT NULL,
    receipt_digest TEXT NOT NULL,
    UNIQUE(scan_id,owner_id),
    FOREIGN KEY(scan_id,owner_id) REFERENCES internal.initial_preparation_admission_receipts(scan_id,owner_id) ON DELETE CASCADE,
    CHECK(internal.initial_media_handoff_document_shape('verification_receipt',owner_id,scan_id,receipt,receipt_digest))
);
CREATE TABLE internal.initial_preparation_transfer_receipts (
    scan_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    receipt TEXT NOT NULL,
    receipt_digest TEXT NOT NULL,
    UNIQUE(scan_id,owner_id),
    FOREIGN KEY(scan_id,owner_id) REFERENCES internal.initial_preparation_admission_receipts(scan_id,owner_id) ON DELETE CASCADE,
    CHECK(internal.initial_media_handoff_document_shape('transfer_receipt',owner_id,scan_id,receipt,receipt_digest))
);

ALTER TABLE internal.initial_media_copy_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_media_verification_claims_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_media_verification_receipts_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_preparation_transfer_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.initial_media_copy_progress,
    internal.initial_media_verification_claims_v2,internal.initial_media_verification_receipts_v2,
    internal.initial_preparation_transfer_receipts FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION internal.initial_media_copy_progress_shape(TEXT,BIGINT,BIGINT,BIGINT),
    internal.initial_media_handoff_document_shape(TEXT,UUID,UUID,TEXT,TEXT) FROM PUBLIC,anon,authenticated,service_role;

-- Relational locks only. Callers acquire owner, ingestion advisory, scan/history
-- and lifecycle/intent/submission/cancellation/admission first. Raw erasure uses
-- the same actual registry union without requiring valid JSON or funding.
CREATE FUNCTION internal.lock_initial_media_handoff_members(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    PERFORM scan_id FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_output_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_verifications WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_media_copy_progress WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_media_verification_claims_v2 WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
END; $$;

CREATE FUNCTION internal.lock_initial_media_handoff_scope(p_owner UUID,p_scan UUID,p_fresh BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE admitted internal.initial_analysis_admissions; charge internal.ai_quota_reservation_counters;
BEGIN
    IF p_owner IS NULL OR p_scan IS NULL OR p_fresh IS NULL THEN
        RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
    END IF;
    IF current_setting('transaction_isolation') IS DISTINCT FROM 'read committed' THEN
        RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000';
    END IF;
    -- This is exclusively the live path. Terminal and raw privacy owners retain
    -- their dedicated already-held/fail-fast outer lock discipline.
    PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
    PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
    SELECT * INTO admitted FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
    IF NOT FOUND OR admitted.owner_id IS DISTINCT FROM p_owner OR admitted.binding_version IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    IF p_fresh THEN PERFORM internal.lock_initial_preparation_eligibility(p_scan); END IF;
    PERFORM id FROM internal.ai_quota_reservations WHERE id=admitted.funding_binding_id FOR UPDATE;
    PERFORM reservation_id FROM internal.identification_provider_attempts
        WHERE reservation_id=admitted.funding_binding_id AND attempt_count=1 FOR UPDATE;
    FOR charge IN SELECT * FROM internal.ai_quota_reservation_counters l WHERE l.reservation_id=admitted.funding_binding_id
        ORDER BY CASE l.scope_type WHEN 'user_daily' THEN 1 WHEN 'user_rate' THEN 2 WHEN 'ip_rate' THEN 3 ELSE 4 END,
            l.scope_key,l.bucket,l.window_start FOR UPDATE LOOP
        PERFORM scope_type FROM internal.ai_quota_counters c WHERE c.scope_type=charge.scope_type
            AND c.scope_key=charge.scope_key AND c.bucket=charge.bucket AND c.window_start=charge.window_start FOR UPDATE;
    END LOOP;
    PERFORM client_scan_id FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_scan FOR UPDATE;
    PERFORM internal.lock_initial_media_handoff_members(p_scan);
END; $$;
REVOKE ALL ON FUNCTION internal.lock_initial_media_handoff_members(UUID),
    internal.lock_initial_media_handoff_scope(UUID,UUID,BOOLEAN) FROM PUBLIC,anon,authenticated,service_role;

-- Validate stored progress and its exact chain. This is consistency only: no
-- physical I/O attestation, current eligibility, time extension or execution.
CREATE FUNCTION internal.assert_initial_media_handoff_chain(p_owner UUID,p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts; progress internal.initial_media_copy_progress;
    claim internal.initial_media_verification_claims_v2; verified internal.initial_media_verification_receipts_v2;
    transferred internal.initial_preparation_transfer_receipts; objects JSONB; item JSONB; proof JSONB;
BEGIN
    SELECT * INTO r FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
    IF NOT FOUND OR r.owner_id IS DISTINCT FROM p_owner THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    r:=internal.initial_admission_retained_receipt(p_owner,p_scan,r.admission_receipt_id);
    SELECT * INTO progress FROM internal.initial_media_copy_progress WHERE scan_id=p_scan;
    SELECT * INTO claim FROM internal.initial_media_verification_claims_v2 WHERE scan_id=p_scan;
    SELECT * INTO verified FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=p_scan;
    SELECT * INTO transferred FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan;
    IF progress.scan_id IS NULL THEN
        IF claim.scan_id IS NOT NULL OR verified.scan_id IS NOT NULL OR transferred.scan_id IS NOT NULL THEN
            RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
        END IF;
        RETURN;
    END IF;
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('object_id',o->'object_id',
        'backend_generation',r.mapping::JSONB->'destination_backend_generation')||(o->'bytes') ORDER BY ordinal)
        INTO objects FROM pg_catalog.jsonb_array_elements(r.mapping::JSONB->'objects') WITH ORDINALITY AS x(o,ordinal);
    IF progress.owner_id IS DISTINCT FROM p_owner OR progress.admission_receipt_digest IS DISTINCT FROM r.receipt_digest
        OR progress.copy_adapter_digest IS DISTINCT FROM r.configuration::JSONB#>>'{assignment,handoff,profile,copy_adapter_digest}'
        OR NOT internal.initial_media_copy_progress_shape(progress.completed_objects,progress.started_at_ms,
            progress.last_object_at_ms,progress.completed_at_ms)
        OR progress.started_at_ms<(r.manifest::JSONB->>'authorized_at_ms')::BIGINT
        OR progress.started_at_ms>=(r.media_binding::JSONB#>>'{phase_window,cutoffs,copy}')::BIGINT
        OR progress.last_object_at_ms>=(r.media_binding::JSONB#>>'{phase_window,cutoffs,copy}')::BIGINT
        OR progress.completed_at_ms>=(r.media_binding::JSONB#>>'{phase_window,cutoffs,copy}')::BIGINT
        OR (progress.completed_at_ms IS NOT NULL AND progress.completed_objects::JSONB IS DISTINCT FROM objects) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
    END IF;
    FOR item IN SELECT value FROM pg_catalog.jsonb_array_elements(progress.completed_objects::JSONB) LOOP
        IF NOT EXISTS(SELECT 1 FROM pg_catalog.jsonb_array_elements(objects) AS x(value) WHERE value=item) THEN
            RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
    IF claim.scan_id IS NULL THEN
        IF verified.scan_id IS NOT NULL OR transferred.scan_id IS NOT NULL THEN
            RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
        END IF;
        RETURN;
    END IF;
    IF claim.owner_id IS DISTINCT FROM p_owner OR progress.completed_at_ms IS NULL
        OR (claim.claim::JSONB->>'issued_at_ms')::BIGINT<progress.completed_at_ms THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
    END IF;
    proof:=internal.validate_initial_media_handoff_proof('claim',r.candidate,r.input,r.configuration,r.funding,r.outcome,
        r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest,claim.claim,NULL,NULL);
    IF claim.claim_digest IS DISTINCT FROM proof->>'digest' THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
    END IF;
    IF verified.scan_id IS NULL THEN
        IF transferred.scan_id IS NOT NULL THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
        RETURN;
    END IF;
    proof:=internal.validate_initial_media_handoff_proof('verification_receipt',r.candidate,r.input,r.configuration,r.funding,r.outcome,
        r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest,claim.claim,verified.receipt,NULL);
    IF verified.owner_id IS DISTINCT FROM p_owner OR verified.receipt_digest IS DISTINCT FROM proof->>'digest' THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
    END IF;
    IF transferred.scan_id IS NOT NULL THEN
        proof:=internal.validate_initial_media_handoff_proof('transfer_receipt',r.candidate,r.input,r.configuration,r.funding,r.outcome,
            r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest,claim.claim,verified.receipt,transferred.receipt);
        IF transferred.owner_id IS DISTINCT FROM p_owner OR transferred.receipt_digest IS DISTINCT FROM proof->>'digest' THEN
            RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
        END IF;
    END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_media_handoff_chain(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Expand exact C1 images and both existing denial seals. The four durable
-- children belong to submission erasure, never to transient cleanup. Migration
-- patches assert a single known source anchor and do not expose runtime SQL.
DO $handoff_private_catalogs$
DECLARE definition TEXT; anchor TEXT; relation_name TEXT;
BEGIN
    SELECT pg_get_functiondef('internal.initial_cancellation_private_catalog()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=' (''internal.initial_preparation_admission_receipts'',''submission'',1),';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff C1 private catalog drift'; END IF;
    EXECUTE replace(definition,anchor,anchor||E'\n'||
        ' (''internal.initial_media_copy_progress'',''submission'',1),'||E'\n'||
        ' (''internal.initial_media_verification_claims_v2'',''submission'',1),'||E'\n'||
        ' (''internal.initial_media_verification_receipts_v2'',''submission'',1),'||E'\n'||
        ' (''internal.initial_preparation_transfer_receipts'',''submission'',1),');
    SELECT pg_get_functiondef('internal.initial_cancellation_seal_catalog()'::REGPROCEDURE) INTO STRICT definition;
    anchor:='        (''internal.initial_preparation_admission_receipts''),';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff C1 seal catalog drift'; END IF;
    EXECUTE replace(definition,anchor,anchor||E'\n'||
        '        (''internal.initial_media_copy_progress''),'||E'\n'||
        '        (''internal.initial_media_verification_claims_v2''),'||E'\n'||
        '        (''internal.initial_media_verification_receipts_v2''),'||E'\n'||
        '        (''internal.initial_preparation_transfer_receipts''),');
    FOREACH relation_name IN ARRAY ARRAY['internal.initial_media_copy_progress',
        'internal.initial_media_verification_claims_v2','internal.initial_media_verification_receipts_v2',
        'internal.initial_preparation_transfer_receipts'] LOOP
        EXECUTE format('CREATE TRIGGER a0_initial_cancellation_private BEFORE INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_private_member()',relation_name);
        EXECUTE format('CREATE TRIGGER a0_initial_cancellation_private_truncate BEFORE TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_private_member()',relation_name);
        EXECUTE format('CREATE TRIGGER z9_initial_cancellation_private_after AFTER DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_private_member()',relation_name);
        EXECUTE format('CREATE TRIGGER a00_initial_cancellation_seal BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_seal()',relation_name);
        EXECUTE format('CREATE TRIGGER a00_initial_admission_seal BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_admission_seal()',relation_name);
    END LOOP;
END; $handoff_private_catalogs$;

DO $handoff_c1_and_merge_locks$
DECLARE definition TEXT; anchor TEXT; signature TEXT;
BEGIN
    -- C1's existing capture owns its funding order and captures exact new rows
    -- through the extended fixed private catalog. Merge terminal protection
    -- observes the same transfer/progress slots and requires all to be absent.
    FOREACH signature IN ARRAY ARRAY['internal.capture_initial_admitted_cancellation_prestate(uuid,uuid)',
        'internal.lock_initial_merge_target_terminal(uuid,uuid)'] LOOP
        SELECT pg_get_functiondef(signature::REGPROCEDURE) INTO STRICT definition;
        anchor:='    PERFORM scan_id FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan FOR UPDATE;';
        IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff transfer lock source drift'; END IF;
        definition:=replace(definition,anchor,anchor||E'\n'||'    PERFORM scan_id FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan FOR UPDATE;');
        anchor:='    PERFORM scan_id FROM internal.initial_analysis_media_verifications WHERE scan_id=p_scan FOR UPDATE;';
        IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff progress lock source drift'; END IF;
        definition:=replace(definition,anchor,anchor||E'\n'||
            '    PERFORM scan_id FROM internal.initial_media_copy_progress WHERE scan_id=p_scan FOR UPDATE;'||E'\n'||
            '    PERFORM scan_id FROM internal.initial_media_verification_claims_v2 WHERE scan_id=p_scan FOR UPDATE;'||E'\n'||
            '    PERFORM scan_id FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=p_scan FOR UPDATE;');
        IF signature='internal.capture_initial_admitted_cancellation_prestate(uuid,uuid)' THEN
            anchor:='    -- No transfer owner/table is installed. Future transfer adds its locked'||E'\n'||
                '    -- receipt before M1; absence of progress must never be inferred as transfer.';
            IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff C1 transfer comment drift'; END IF;
            definition:=replace(definition,anchor,'    -- Transfer is locked before M1; new private rows join exact C1 images.');
            anchor:='    PERFORM internal.assert_initial_admission_live_receipt(p_owner,p_scan,receipt.admission_receipt_id);';
            IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff C1 chain source drift'; END IF;
            definition:=replace(definition,anchor,anchor||E'\n'||'    PERFORM internal.assert_initial_media_handoff_chain(p_owner,p_scan);');
        END IF;
        EXECUTE definition;
    END LOOP;
    SELECT pg_get_functiondef('internal.cancel_initial_analysis_explicit(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
    anchor:=' SELECT * INTO submission FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff C1 outer lock source drift'; END IF;
    EXECUTE replace(definition,anchor,
        ' IF internal.initial_admitted_settlement_blocked(p_scan) THEN'||E'\n'||
        '  PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;'||E'\n'||
        ' END IF;'||E'\n'||anchor);
END; $handoff_c1_and_merge_locks$;

-- A transferred operation has deliberately erased intent-root proof. Its
-- admitted receipt remains self-contained, and its actual source registry must
-- be the exact retired original union. Cleanup lease/marker progress is allowed;
-- it never changes those identities or reopens data writes. Original funding,
-- lifecycle and still-live M1 predicates remain in the caller below.
CREATE FUNCTION internal.assert_initial_transferred_preparation(p_owner UUID,p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts; expected UUID[]; actual UUID[]; member RECORD; present BOOLEAN;
BEGIN
    SELECT * INTO r FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
    IF NOT FOUND OR p_owner IS NULL OR p_scan IS NULL OR r.owner_id IS DISTINCT FROM p_owner THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_media_handoff_chain(p_owner,p_scan);
    IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan AND owner_id=p_owner)
        OR (SELECT to_jsonb(t) FROM internal.initial_preparation_source_fences t WHERE scan_id=p_scan)
            IS DISTINCT FROM jsonb_build_object('scan_id',p_scan,'state','retired','execution_state','issued','provider_barrier','blocked_pre_admission') THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
    END IF;
    FOR member IN SELECT relation_name FROM internal.initial_cancellation_private_catalog() WHERE root_name='intent' LOOP
        EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s WHERE scan_id=$1)',member.relation_name) INTO present USING p_scan;
        IF present THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    END LOOP;
    SELECT array_agg(object_id ORDER BY object_id) INTO expected FROM (
        SELECT (value->>'object_id')::UUID AS object_id
            FROM jsonb_array_elements(r.outcome::JSONB#>'{source_verification,entries}')
        UNION
        SELECT (value->>'object_id')::UUID AS object_id
            FROM jsonb_array_elements(r.outcome::JSONB#>'{resolved_manifest,entries}') WHERE value->>'object_id' IS NOT NULL
    ) original;
    SELECT array_agg(object_id ORDER BY object_id) INTO actual FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan;
    IF expected IS NULL OR actual IS DISTINCT FROM expected
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan
            AND (NOT retired OR backend_generation IS DISTINCT FROM (r.configuration::JSONB#>>'{assignment,preparation,backend_generation}')::UUID))
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry src
            JOIN internal.initial_analysis_media_registry dst USING(object_id) WHERE src.scan_id=p_scan OR dst.scan_id=p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
    END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_transferred_preparation(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

DO $handoff_transferred_live_proof$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    SELECT pg_get_functiondef('internal.assert_initial_admission_live_receipt(uuid,uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$anchor$    SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
    IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner OR saved.canonical_candidate IS DISTINCT FROM r.candidate
        OR saved.canonical_assignment IS DISTINCT FROM internal.initial_canonical(r.configuration::JSONB->'assignment')
        OR floor(extract(epoch FROM saved.expires_at)*1000) IS DISTINCT FROM ((r.media_binding::JSONB->'phase_window')->>'original_expires_at_ms')::NUMERIC
        OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan
            AND state='allocated' AND provider_barrier='blocked_pre_admission' AND execution_state='issued')
        OR (SELECT canonical_outcome FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan) IS DISTINCT FROM r.outcome
        OR NOT internal.initial_preparation_execution_coherent(p_scan)
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan AND claim_expires_at IS NOT NULL)
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry src
            JOIN internal.initial_analysis_media_registry dst USING(object_id) WHERE src.scan_id=p_scan OR dst.scan_id=p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;$anchor$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff live preparation proof source drift'; END IF;
    EXECUTE replace(definition,anchor,
        '    IF EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan) THEN'||E'\n'||
        '        PERFORM internal.assert_initial_transferred_preparation(p_owner,p_scan);'||E'\n'||
        '    ELSE'||E'\n'||anchor||E'\n'||'    END IF;');
END; $handoff_transferred_live_proof$;

-- Zero source-retirement events are legitimate only for the exact transferred
-- preimage captured by C1. Keep that whole image available through terminal
-- cleanup; an empty event list alone must never prove successful retirement.
CREATE FUNCTION internal.assert_initial_cancellation_retirement_images(
    p_scan UUID,p_side TEXT,p_events JSONB,p_after BOOLEAN,p_prestate JSONB
) RETURNS VOID LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE actual_fence JSONB; actual_rows JSONB;
BEGIN
    IF p_events IS DISTINCT FROM '[]'::JSONB THEN
        PERFORM internal.assert_initial_cancellation_retirement_images(p_scan,p_side,p_events,p_after);
        RETURN;
    END IF;
    IF p_scan IS NULL OR p_side IS DISTINCT FROM 'source' OR p_after IS NULL OR p_prestate IS NULL
        OR p_prestate->>'scan_id' IS DISTINCT FROM p_scan::TEXT
        OR p_prestate#>>'{source_fence,state}' IS DISTINCT FROM 'retired'
        OR jsonb_array_length(p_prestate#>'{erasure_images,internal.initial_preparation_transfer_receipts}') IS DISTINCT FROM 1
        OR jsonb_typeof(p_prestate->'source_registry') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF jsonb_array_length(p_prestate->'source_registry') NOT BETWEEN 1 AND 16
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_prestate->'source_registry') e WHERE e->'retired' IS DISTINCT FROM 'true'::JSONB)
        OR (SELECT count(*) FROM (SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan LIMIT 17) bounded)>16 THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT to_jsonb(f) INTO actual_fence FROM internal.initial_preparation_source_fences f WHERE scan_id=p_scan;
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY object_id),'[]') INTO actual_rows FROM internal.initial_preparation_source_registry r WHERE scan_id=p_scan;
    IF actual_fence IS DISTINCT FROM p_prestate->'source_fence' OR actual_rows IS DISTINCT FROM p_prestate->'source_registry' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_cancellation_retirement_images(UUID,TEXT,JSONB,BOOLEAN,JSONB)
    FROM PUBLIC,anon,authenticated,service_role;

DO $handoff_c1_retired_source$
DECLARE definition TEXT; anchor TEXT; patch RECORD;
BEGIN
    SELECT pg_get_functiondef('internal.initial_cancellation_retirement_events(internal.initial_admitted_cancellation_staging,text)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='    IF fence->>''state'' IS DISTINCT FROM ''allocated'' OR fence->>''scan_id'' IS DISTINCT FROM p_stage.scan_id::TEXT';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff C1 source event drift'; END IF;
    EXECUTE replace(definition,anchor,$addition$    IF p_side='source' AND fence->>'state'='retired' THEN
        IF fence->>'scan_id' IS DISTINCT FROM p_stage.scan_id::TEXT
            OR jsonb_typeof(rows) IS DISTINCT FROM 'array'
            OR jsonb_array_length(rows) NOT BETWEEN 1 AND 16
            OR jsonb_array_length(p_stage.prestate#>'{erasure_images,internal.initial_preparation_transfer_receipts}') IS DISTINCT FROM 1
            OR p_stage.prestate#>>'{erasure_images,internal.initial_preparation_transfer_receipts,0,scan_id}' IS DISTINCT FROM p_stage.scan_id::TEXT
            OR p_stage.prestate#>>'{erasure_images,internal.initial_preparation_transfer_receipts,0,owner_id}' IS DISTINCT FROM p_stage.owner_id::TEXT
            OR EXISTS(SELECT 1 FROM jsonb_array_elements(rows) e WHERE e->>'scan_id' IS DISTINCT FROM p_stage.scan_id::TEXT OR e->'retired' IS DISTINCT FROM 'true'::JSONB)
            OR EXISTS(SELECT 1 FROM internal.initial_cancellation_private_catalog() c WHERE c.root_name='intent'
                AND p_stage.prestate->'erasure_images'->c.relation_name IS DISTINCT FROM '[]'::JSONB) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        RETURN '[]'::JSONB;
    END IF;
$addition$||anchor);
    -- Every caller has the protected captured stage, including the terminal
    -- survivor comparator reconstructed from its immutable terminal snapshot.
    FOR patch IN SELECT * FROM (VALUES
        ('internal.advance_initial_cancellation_retirement(uuid,text,text)',
         'internal.assert_initial_cancellation_retirement_images(p_scan,p_side,witness.expected,TRUE);',
         'internal.assert_initial_cancellation_retirement_images(p_scan,p_side,witness.expected,TRUE,stage.prestate);'),
        ('internal.assert_initial_cancellation_erasure_boundary(internal.initial_admitted_cancellation_staging,jsonb)',
         'internal.assert_initial_cancellation_retirement_images(p_stage.scan_id,side_name,retirement.expected,TRUE);',
         'internal.assert_initial_cancellation_retirement_images(p_stage.scan_id,side_name,retirement.expected,TRUE,p_stage.prestate);'),
        ('internal.assert_initial_cancellation_terminal_survivors(jsonb)',
         'internal.assert_initial_cancellation_retirement_images(stage.scan_id,side_name,retirement.expected,TRUE);',
         'internal.assert_initial_cancellation_retirement_images(stage.scan_id,side_name,retirement.expected,TRUE,stage.prestate);'),
        ('internal.guard_initial_cancellation_retirement_witness()',
         'internal.initial_cancellation_retirement_events(stage,''destination''),FALSE);',
         'internal.initial_cancellation_retirement_events(stage,''destination''),FALSE,stage.prestate);'),
        ('internal.guard_initial_cancellation_retirement_witness()',
         'internal.assert_initial_cancellation_retirement_images(stage.scan_id,''source'',source_witness.expected,TRUE);',
         'internal.assert_initial_cancellation_retirement_images(stage.scan_id,''source'',source_witness.expected,TRUE,stage.prestate);'),
        ('internal.guard_initial_cancellation_retirement_witness()',
         'internal.assert_initial_cancellation_retirement_images(stage.scan_id,NEW.side,NEW.expected,FALSE);',
         'internal.assert_initial_cancellation_retirement_images(stage.scan_id,NEW.side,NEW.expected,FALSE,stage.prestate);'),
        ('internal.guard_initial_cancellation_retirement_witness()',
         'internal.assert_initial_cancellation_retirement_images(stage.scan_id,NEW.side,NEW.expected,TRUE);',
         'internal.assert_initial_cancellation_retirement_images(stage.scan_id,NEW.side,NEW.expected,TRUE,stage.prestate);')
    ) changes(signature,old_call,new_call) LOOP
        SELECT pg_get_functiondef(patch.signature::REGPROCEDURE) INTO STRICT definition;
        IF (length(definition)-length(replace(definition,patch.old_call,'')))/length(patch.old_call)<>1 THEN
            RAISE EXCEPTION 'handoff C1 captured retirement image call drift';
        END IF;
        EXECUTE replace(definition,patch.old_call,patch.new_call);
    END LOOP;
END; $handoff_c1_retired_source$;

ALTER TABLE internal.initial_cancellation_retirement_witness DROP CONSTRAINT initial_cancellation_retirement_witness_expected_check;
ALTER TABLE internal.initial_cancellation_retirement_witness ADD CONSTRAINT initial_cancellation_retirement_witness_expected_check
    CHECK(jsonb_typeof(expected)='array' AND (jsonb_array_length(expected) BETWEEN 2 AND 17 OR (side='source' AND expected='[]'::JSONB)));

ALTER TABLE internal.initial_cancellation_erasure_witness DROP CONSTRAINT initial_cancellation_erasure_witness_expected_check;
ALTER TABLE internal.initial_cancellation_erasure_witness ADD CONSTRAINT initial_cancellation_erasure_witness_expected_check
    CHECK(jsonb_typeof(expected)='array' AND (jsonb_array_length(expected) BETWEEN 1 AND 21 OR (root_name='intent' AND expected='[]'::JSONB)));

CREATE FUNCTION internal.initial_media_handoff_recovery_response(
    p_receipt internal.initial_preparation_admission_receipts,p_observed_at_ms NUMERIC
) RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE binding JSONB; phase TEXT; cutoff_name TEXT; transfer_digest TEXT;
    image RECORD; actual JSONB;
BEGIN
    -- Reuse the accepted pure envelope validation, including clock bounds. Its
    -- legacy copy-only classification is replaced below by actual durable facts.
    PERFORM internal.initial_admitted_recovery_response(p_receipt,p_observed_at_ms);
    IF (SELECT to_jsonb(r) FROM internal.initial_preparation_admission_receipts r WHERE scan_id=p_receipt.scan_id)
        IS DISTINCT FROM to_jsonb(p_receipt) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_media_handoff_chain(p_receipt.owner_id,p_receipt.scan_id);
    -- Recovery never settles original funding, but cannot return a usable-looking
    -- original binding for a different or retired M1 cohort.
    FOR image IN SELECT * FROM internal.initial_admission_member_images(p_receipt) WHERE statement_key LIKE 'M1.%' LOOP
        IF image.relation_name='internal.initial_analysis_media_registry' THEN
            SELECT to_jsonb(t) INTO actual FROM internal.initial_analysis_media_registry t WHERE object_id=(image.new_image->>'object_id')::UUID;
        ELSE
            EXECUTE format('SELECT to_jsonb(t) FROM %s t WHERE scan_id=$1',image.relation_name) INTO actual USING p_receipt.scan_id;
        END IF;
        IF actual IS DISTINCT FROM image.new_image THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    END LOOP;
    IF (SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id=p_receipt.scan_id)
        <>jsonb_array_length(p_receipt.mapping::JSONB->'objects') THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
    END IF;
    binding:=p_receipt.media_binding::JSONB;
    SELECT receipt_digest INTO transfer_digest FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_receipt.scan_id;
    IF FOUND THEN
        PERFORM internal.assert_initial_transferred_preparation(p_receipt.owner_id,p_receipt.scan_id);
        RETURN internal.parse_initial_admission_recovery_response(internal.initial_canonical(jsonb_build_object(
            'version',2,'outcome','transferred','authority','none','scan_id',p_receipt.scan_id,
            'admission_receipt_digest',p_receipt.receipt_digest,'binding',binding,'transfer_receipt_digest',transfer_digest)));
    END IF;
    IF EXISTS(SELECT 1 FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=p_receipt.scan_id) THEN
        phase:='transfer'; cutoff_name:='transfer';
    ELSIF EXISTS(SELECT 1 FROM internal.initial_media_verification_claims_v2 WHERE scan_id=p_receipt.scan_id) THEN
        phase:='verification'; cutoff_name:='verification_settlement';
    ELSIF EXISTS(SELECT 1 FROM internal.initial_media_copy_progress WHERE scan_id=p_receipt.scan_id AND completed_at_ms IS NOT NULL) THEN
        phase:='verification'; cutoff_name:='verification_claim';
    ELSE phase:='copy'; cutoff_name:='copy'; END IF;
    IF p_observed_at_ms>=(binding#>>ARRAY['phase_window','cutoffs',cutoff_name])::NUMERIC THEN phase:='expired'; END IF;
    RETURN internal.parse_initial_admission_recovery_response(internal.initial_canonical(jsonb_build_object(
        'version',2,'outcome','admitted','authority','none','scan_id',p_receipt.scan_id,
        'admission_receipt_digest',p_receipt.receipt_digest,'binding',binding,'phase',phase)));
END; $$;
REVOKE ALL ON FUNCTION internal.initial_media_handoff_recovery_response(internal.initial_preparation_admission_receipts,NUMERIC)
    FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.recover_initial_admitted_media(p_owner UUID,p_scan UUID)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE receipt internal.initial_preparation_admission_receipts;
BEGIN
    -- Classification precedence does not change acquisition order: original
    -- intent/submission/cancellation/admission and funding precede transfer/M1.
    PERFORM internal.lock_initial_media_handoff_scope(p_owner,p_scan,FALSE);
    SELECT * INTO receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
    IF NOT FOUND OR receipt.owner_id IS DISTINCT FROM p_owner
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan)
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan
            AND state IN ('pending_pre_dispatch','dispatch_authorized')) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    receipt:=internal.initial_admission_retained_receipt(p_owner,p_scan,receipt.admission_receipt_id);
    RETURN internal.initial_media_handoff_recovery_response(receipt,floor(extract(epoch FROM clock_timestamp())*1000));
END; $$;

-- Raw privacy roots already own (or fail-fast acquire) owner and ingestion
-- advisory scope. They do not invoke the live preparation scope, inspect JSON,
-- require current eligibility, or settle funding. Lock surviving relational
-- members before lifecycle fencing and either private root's DELETE triggers.
CREATE FUNCTION internal.lock_initial_media_handoff_erasure_rows(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    PERFORM id FROM public.scans WHERE id=p_scan FOR UPDATE;
    PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
    PERFORM internal.lock_initial_media_handoff_members(p_scan);
END; $$;
REVOKE ALL ON FUNCTION internal.lock_initial_media_handoff_erasure_rows(UUID) FROM PUBLIC,anon,authenticated,service_role;


-- Owner deletion must also discover surviving admitted identities whose two
-- private roots have disappeared. These are relational ownership routes only;
-- neither a receipt document nor a funding/refund proof is required. A fence
-- alone has no owner and is never arbitrarily attributed to the deleting user.
CREATE FUNCTION internal.initial_media_handoff_erasure_identities(p_owner UUID)
RETURNS TABLE(scan_id UUID) LANGUAGE SQL STABLE SECURITY INVOKER SET search_path='' AS $$
    SELECT scan_id FROM internal.initial_analysis_submissions WHERE owner_id=p_owner
    UNION SELECT scan_id FROM internal.initial_analysis_preparation_intents WHERE owner_id=p_owner
    UNION SELECT candidates.scan_id FROM (
        SELECT id AS scan_id FROM public.scans WHERE user_id=p_owner
        UNION SELECT scan_id FROM internal.initial_analysis_cancellations WHERE owner_id=p_owner
        UNION SELECT scan_id FROM internal.initial_analysis_admissions WHERE owner_id=p_owner
        UNION SELECT scan_id FROM internal.initial_preparation_admission_receipts WHERE owner_id=p_owner
        UNION SELECT scan_id FROM internal.initial_media_copy_progress WHERE owner_id=p_owner
        UNION SELECT scan_id FROM internal.initial_media_verification_claims_v2 WHERE owner_id=p_owner
        UNION SELECT scan_id FROM internal.initial_media_verification_receipts_v2 WHERE owner_id=p_owner
        UNION SELECT scan_id FROM internal.initial_preparation_transfer_receipts WHERE owner_id=p_owner
        UNION SELECT original_analysis_id FROM internal.ai_quota_reservations WHERE user_id=p_owner
        UNION SELECT request_id FROM internal.ai_quota_reservations WHERE user_id=p_owner
        UNION SELECT client_scan_id FROM internal.complimentary_scan_usage WHERE user_id=p_owner
    ) AS candidates WHERE candidates.scan_id IS NOT NULL
        AND internal.initial_admitted_settlement_blocked(candidates.scan_id);
$$;
REVOKE ALL ON FUNCTION internal.initial_media_handoff_erasure_identities(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Closed migration-time source patches preserve all legacy branches and raw
-- owner/advisory guards. No runtime SQL executor or new root is exposed.
DO $handoff_raw_erasure$
DECLARE definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
    SELECT pg_get_functiondef('internal.erase_initial_analysis_for_scan_fence()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$ PERFORM internal.fence_initial_analysis_erasure(NEW.scan_id);$before$;
    replacement:=$after$ IF internal.initial_admitted_settlement_blocked(NEW.scan_id) THEN
  PERFORM internal.lock_initial_media_handoff_erasure_rows(NEW.scan_id);
 END IF;
 PERFORM internal.fence_initial_analysis_erasure(NEW.scan_id);$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff raw erasure source drift: erase_initial_analysis_for_scan_fence'; END IF;
    EXECUTE replace(definition,anchor,replacement);
    SELECT pg_get_functiondef('internal.cancel_initial_analysis(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$ classification:=internal.initial_cancellation_dispatch(terminal);$before$;
    replacement:=$after$ classification:=internal.initial_cancellation_dispatch(terminal);
 IF internal.initial_admitted_settlement_blocked(p_scan) THEN
  PERFORM internal.lock_initial_media_handoff_members(p_scan);
 END IF;$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff raw erasure source drift: cancel_initial_analysis'; END IF;
    EXECUTE replace(definition,anchor,replacement);
    SELECT pg_get_functiondef('internal.fence_initial_analysis_on_scan_change()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$    INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)$before$;
    replacement:=$after$    IF internal.initial_admitted_settlement_blocked(identity) THEN
        PERFORM internal.lock_initial_media_handoff_erasure_rows(identity);
    END IF;
    INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff raw erasure source drift: fence_initial_analysis_on_scan_change'; END IF;
    EXECUTE replace(definition,anchor,replacement);
    SELECT pg_get_functiondef('internal.fence_initial_analysis_before_owner_delete()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$        INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)$before$;
    replacement:=$after$        IF internal.initial_admitted_settlement_blocked(identity) THEN
            PERFORM internal.lock_initial_media_handoff_erasure_rows(identity);
        END IF;
        INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff raw erasure source drift: fence_initial_analysis_before_owner_delete'; END IF;
    EXECUTE replace(definition,anchor,replacement);
    SELECT pg_get_functiondef('internal.erase_initial_analysis_for_scan_fence()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$ DELETE FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id;
 PERFORM internal.retire_initial_preparation_source_objects(NEW.scan_id);
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id;$before$;
    replacement:=$after$ IF internal.initial_admitted_settlement_blocked(NEW.scan_id) THEN
     PERFORM internal.retire_initial_preparation_source_objects(NEW.scan_id);
     IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id) THEN
         PERFORM internal.retire_initial_media_objects(NEW.scan_id);
     END IF;
     DELETE FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id;
     DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id;
 ELSE
 DELETE FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id;
 PERFORM internal.retire_initial_preparation_source_objects(NEW.scan_id);
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id;
 END IF;$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff raw erasure source drift: erase_initial_analysis_for_scan_fence'; END IF;
    EXECUTE replace(definition,anchor,replacement);
    SELECT pg_get_functiondef('internal.cancel_initial_analysis(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$ DELETE FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
 PERFORM internal.retire_initial_preparation_source_objects(p_scan);
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;$before$;
    replacement:=$after$ IF internal.initial_admitted_settlement_blocked(p_scan) THEN
     PERFORM internal.retire_initial_preparation_source_objects(p_scan);
     IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=p_scan) THEN
         PERFORM internal.retire_initial_media_objects(p_scan);
     END IF;
     DELETE FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
     DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 ELSE
 DELETE FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
 PERFORM internal.retire_initial_preparation_source_objects(p_scan);
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 END IF;$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff raw erasure source drift: cancel_initial_analysis'; END IF;
    EXECUTE replace(definition,anchor,replacement);
    SELECT pg_get_functiondef('internal.fence_initial_analysis_on_scan_change()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$    DELETE FROM internal.initial_analysis_submissions WHERE scan_id=identity;
    PERFORM internal.retire_initial_preparation_source_objects(identity);
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;$before$;
    replacement:=$after$    IF internal.initial_admitted_settlement_blocked(identity) THEN
        -- A new tombstone already ran the callback; no second erasure
        -- is needed. Existing tombstones still require the locked fallback.
        IF EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=identity)
          OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity)
          OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=identity AND state<>'retired')
          OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=identity AND NOT retired)
          OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=identity AND state<>'retired')
          OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=identity AND NOT retired) THEN
        PERFORM internal.retire_initial_preparation_source_objects(identity);
        IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=identity) THEN
            PERFORM internal.retire_initial_media_objects(identity);
        END IF;
        DELETE FROM internal.initial_analysis_submissions WHERE scan_id=identity;
        DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;
        END IF;
    ELSE
    DELETE FROM internal.initial_analysis_submissions WHERE scan_id=identity;
    PERFORM internal.retire_initial_preparation_source_objects(identity);
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;
    END IF;$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff raw erasure source drift: fence_initial_analysis_on_scan_change'; END IF;
    EXECUTE replace(definition,anchor,replacement);
    SELECT pg_get_functiondef('internal.fence_initial_analysis_before_owner_delete()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$        DELETE FROM internal.initial_analysis_submissions WHERE scan_id=identity;
        PERFORM internal.retire_initial_preparation_source_objects(identity);
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;$before$;
    replacement:=$after$        IF internal.initial_admitted_settlement_blocked(identity) THEN
            -- A new tombstone already ran the callback; no second erasure
            -- is needed. Existing tombstones still require the locked fallback.
            IF EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=identity)
              OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity)
          OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=identity AND state<>'retired')
          OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=identity AND NOT retired)
          OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=identity AND state<>'retired')
          OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=identity AND NOT retired) THEN
            PERFORM internal.retire_initial_preparation_source_objects(identity);
            IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=identity) THEN
                PERFORM internal.retire_initial_media_objects(identity);
            END IF;
            DELETE FROM internal.initial_analysis_submissions WHERE scan_id=identity;
            DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;
            END IF;
        ELSE
        DELETE FROM internal.initial_analysis_submissions WHERE scan_id=identity;
        PERFORM internal.retire_initial_preparation_source_objects(identity);
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;
        END IF;$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff raw erasure source drift: fence_initial_analysis_before_owner_delete'; END IF;
    EXECUTE replace(definition,anchor,replacement);
END; $handoff_raw_erasure$;


DO $handoff_raw_missing_roots$
DECLARE definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
    SELECT pg_get_functiondef('internal.fence_initial_analysis_on_scan_change()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity) THEN$before$;
    replacement:=$after$AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity)
      AND NOT internal.initial_admitted_settlement_blocked(identity) THEN$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff raw identity source drift: fence_initial_analysis_on_scan_change'; END IF;
    EXECUTE replace(definition,anchor,replacement);
    SELECT pg_get_functiondef('internal.guard_initial_analysis_scan_erasure_scope()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=OLD.id) THEN$before$;
    replacement:=$after$OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=OLD.id)
      OR internal.initial_admitted_settlement_blocked(OLD.id) THEN$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff raw identity source drift: guard_initial_analysis_scan_erasure_scope'; END IF;
    EXECUTE replace(definition,anchor,replacement);
    SELECT pg_get_functiondef('internal.guard_initial_analysis_tombstone_scope()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id) THEN$before$;
    replacement:=$after$AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id)
       AND NOT internal.initial_admitted_settlement_blocked(NEW.scan_id) THEN$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff raw identity source drift: guard_initial_analysis_tombstone_scope'; END IF;
    EXECUTE replace(definition,anchor,replacement);
    SELECT pg_get_functiondef('internal.fence_initial_analysis_before_owner_delete()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$IF EXISTS(SELECT 1 FROM (SELECT scan_id,owner_id FROM internal.initial_analysis_submissions UNION SELECT scan_id,owner_id FROM internal.initial_analysis_preparation_intents) AS submission
        JOIN public.scans AS scan ON scan.id=submission.scan_id
        WHERE submission.owner_id=OLD.id AND scan.user_id IS NOT NULL) THEN$before$;
    replacement:=$after$IF EXISTS(SELECT 1 FROM internal.initial_media_handoff_erasure_identities(OLD.id) AS candidate
        JOIN public.scans AS scan ON scan.id=candidate.scan_id
        WHERE scan.user_id IS NOT NULL) THEN$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff raw identity source drift: fence_initial_analysis_before_owner_delete'; END IF;
    EXECUTE replace(definition,anchor,replacement);
    SELECT pg_get_functiondef('internal.fence_initial_analysis_before_owner_delete()'::REGPROCEDURE) INTO STRICT definition;
    anchor:=$before$FOR identity IN SELECT scan_id FROM internal.initial_analysis_submissions WHERE owner_id=OLD.id UNION SELECT scan_id FROM internal.initial_analysis_preparation_intents WHERE owner_id=OLD.id ORDER BY scan_id LOOP$before$;
    replacement:=$after$FOR identity IN SELECT scan_id FROM internal.initial_media_handoff_erasure_identities(OLD.id) ORDER BY scan_id LOOP$after$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'handoff raw identity source drift: fence_initial_analysis_before_owner_delete'; END IF;
    EXECUTE replace(definition,anchor,replacement);
END; $handoff_raw_missing_roots$;

-- Private plan construction is deliberately not a mutation owner. The future
-- stage INSERT guard must derive and retain this result itself; a returned JSON
-- value, receipt, or caller-supplied plan never grants DML authority.
CREATE FUNCTION internal.initial_media_handoff_snapshot_catalog()
RETURNS TABLE(relation_name TEXT,projection TEXT,predicate TEXT,ordering TEXT,row_limit INTEGER)
LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
    SELECT 'internal.'||name,'to_jsonb(t)','t.scan_id=$1',
        CASE WHEN name IN ('initial_preparation_source_mapping','initial_preparation_output_mapping') THEN 't.ordinal'
            WHEN name IN ('initial_preparation_source_registry','initial_analysis_media_registry') THEN 't.object_id'
            ELSE 't.scan_id' END,maximum
    FROM (VALUES
        ('initial_analysis_submissions',1),('initial_analysis_admissions',1),
        ('initial_preparation_admission_receipts',1),('initial_analysis_media_cohorts',1),
        ('initial_analysis_media_preparations',1),('initial_analysis_media_verifications',1),
        ('initial_analysis_results',1),('initial_analysis_completions',1),
        ('initial_analysis_preparation_intents',1),('initial_preparation_source_mapping',8),
        ('initial_preparation_source_verifications',1),('initial_preparation_execution_grants',1),
        ('initial_preparation_output_manifests',1),('initial_preparation_output_mapping',8),
        ('initial_preparation_outcomes',1),('initial_media_copy_progress',1),
        ('initial_media_verification_claims_v2',1),('initial_media_verification_receipts_v2',1),
        ('initial_preparation_transfer_receipts',1),('initial_preparation_source_fences',1),
        ('initial_preparation_source_registry',16),('initial_analysis_media_allocation_fences',1),
        ('initial_analysis_media_registry',10),('initial_analysis_lifecycle_fences',1),
        ('initial_analysis_operation_fences',1)
    ) AS members(name,maximum)
    UNION ALL VALUES
        ('public.users','jsonb_build_object(''id'',t.id,''entitlement_version'',t.entitlement_version,''complimentary_entitlement_epoch'',t.complimentary_entitlement_epoch)',
            't.id=$2','t.id',1),
        ('internal.ai_quota_reservations','to_jsonb(t)','t.id=$3','t.id',1),
        ('internal.identification_provider_attempts','to_jsonb(t)','t.reservation_id=$3','t.attempt_count',1),
        ('internal.ai_quota_reservation_counters','to_jsonb(t)','t.reservation_id=$3',
            't.scope_type COLLATE "C",t.scope_key COLLATE "C",t.bucket COLLATE "C",t.window_start',3),
        ('internal.ai_quota_counters','to_jsonb(t)',
            'EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters l WHERE l.reservation_id=$3 AND l.scope_type=t.scope_type AND l.scope_key=t.scope_key AND l.bucket=t.bucket AND l.window_start=t.window_start)',
            't.scope_type COLLATE "C",t.scope_key COLLATE "C",t.bucket COLLATE "C",t.window_start',3),
        ('internal.complimentary_scan_usage','to_jsonb(t)','t.user_id=$2 AND t.client_scan_id=$1','t.client_scan_id',1);
$$;

CREATE FUNCTION internal.capture_initial_media_handoff_snapshot(p_owner UUID,p_scan UUID)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE member RECORD; reservation UUID; rows BIGINT; bytes BIGINT; largest BIGINT;
    total BIGINT:=2; images JSONB; result JSONB:='{}'::JSONB;
BEGIN
    IF p_owner IS NULL OR p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    SELECT funding_binding_id INTO reservation FROM internal.initial_analysis_admissions
        WHERE scan_id=p_scan AND owner_id=p_owner AND binding_version=3;
    IF reservation IS NULL THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    -- Caller holds the complete ordered scope. Preflight ALL relation counts,
    -- row bytes and JSON envelope bytes before the first array aggregation.
    FOR member IN SELECT * FROM internal.initial_media_handoff_snapshot_catalog() LOOP
        EXECUTE format('SELECT count(*) FROM (SELECT 1 FROM %s t WHERE %s LIMIT %s) b',
            member.relation_name,member.predicate,member.row_limit+1) INTO rows USING p_scan,p_owner,reservation;
        IF rows>member.row_limit THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
        EXECUTE format('SELECT COALESCE(sum(octet_length((%s)::TEXT)),0),COALESCE(max(octet_length((%s)::TEXT)),0) FROM %s t WHERE %s',
            member.projection,member.projection,member.relation_name,member.predicate)
            INTO bytes,largest USING p_scan,p_owner,reservation;
        total:=total+bytes+2*rows+octet_length(to_jsonb(member.relation_name)::TEXT)+6;
        IF largest>33554432 OR total>67108864 THEN
            RAISE EXCEPTION 'initial_analysis_handoff_bounds' USING ERRCODE='54000';
        END IF;
    END LOOP;
    FOR member IN SELECT * FROM internal.initial_media_handoff_snapshot_catalog() LOOP
        EXECUTE format('SELECT COALESCE(jsonb_agg(%s ORDER BY %s),''[]''::JSONB) FROM %s t WHERE %s',
            member.projection,member.ordering,member.relation_name,member.predicate)
            INTO images USING p_scan,p_owner,reservation;
        result:=result||jsonb_build_object(member.relation_name,images);
    END LOOP;
    IF octet_length(result::TEXT)>67108864 THEN RAISE EXCEPTION 'initial_analysis_handoff_bounds' USING ERRCODE='54000'; END IF;
    RETURN result;
END; $$;

CREATE FUNCTION internal.assert_initial_media_handoff_cascade_catalog()
RETURNS VOID LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE parent TEXT; child TEXT; expected INTEGER;
BEGIN
    -- Reject drift in both the set and column-level shape of the effective FKs.
    -- Other registry FKs are irrelevant: neither registry is deleted here.
    FOREACH parent IN ARRAY ARRAY['internal.initial_analysis_preparation_intents','internal.initial_preparation_output_manifests'] LOOP
        expected:=CASE WHEN parent='internal.initial_analysis_preparation_intents' THEN 5 ELSE 1 END;
        IF (SELECT count(*) FROM pg_catalog.pg_constraint WHERE contype='f' AND confrelid=parent::REGCLASS)<>expected THEN
            RAISE EXCEPTION 'initial_analysis_handoff_cascade_drift' USING ERRCODE='55000';
        END IF;
        FOR child IN SELECT unnest(CASE WHEN expected=5 THEN ARRAY[
            'internal.initial_preparation_source_mapping','internal.initial_preparation_source_verifications',
            'internal.initial_preparation_execution_grants','internal.initial_preparation_output_manifests',
            'internal.initial_preparation_outcomes'] ELSE ARRAY['internal.initial_preparation_output_mapping'] END) LOOP
            IF (SELECT count(*) FROM pg_catalog.pg_constraint c WHERE c.contype='f'
                AND c.confrelid=parent::REGCLASS AND c.conrelid=child::REGCLASS
                AND c.confdeltype='c' AND NOT c.condeferrable AND c.convalidated
                AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=child::REGCLASS AND attname='scan_id')]::SMALLINT[]
                AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid=parent::REGCLASS AND attname='scan_id')]::SMALLINT[])<>1 THEN
                RAISE EXCEPTION 'initial_analysis_handoff_cascade_drift' USING ERRCODE='55000';
            END IF;
        END LOOP;
    END LOOP;
END; $$;

CREATE FUNCTION internal.plan_initial_media_handoff_mutation(
    p_owner UUID,p_scan UUID,p_action TEXT,p_admission_digest TEXT,
    p_object UUID DEFAULT NULL,p_claim UUID DEFAULT NULL,p_verification_digest TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts; snapshot JSONB; progress JSONB; claim JSONB; verified JSONB;
    objects JSONB; object_value JSONB; old_image JSONB; new_image JSONB; document TEXT; kind TEXT;
    relation TEXT; operation TEXT; member TEXT; cutoff BIGINT; now_ms BIGINT; prior_ms BIGINT;
    events JSONB:='[]'::JSONB; frames JSONB:='[]'::JSONB; indices JSONB; frame_id INTEGER;
    intent_frame INTEGER; manifest_frame INTEGER; parent_frame INTEGER; event_index INTEGER; final_plan JSONB;
    original_sources UUID[]; actual_sources UUID[]; ledger_bytes BIGINT; row_image JSONB;
BEGIN
    IF p_owner IS NULL OR p_scan IS NULL OR p_action IS NULL OR p_action NOT IN
        ('start_copy','record_object','complete_copy','claim','verify','transfer')
        OR p_admission_digest IS NULL OR p_admission_digest !~ '^[0-9a-f]{64}$'
        OR (p_object IS NOT NULL) IS DISTINCT FROM (p_action='record_object')
        OR (p_claim IS NOT NULL) IS DISTINCT FROM (p_action='verify')
        OR (p_verification_digest IS NOT NULL) IS DISTINCT FROM (p_action='transfer')
        OR (p_verification_digest IS NOT NULL AND p_verification_digest !~ '^[0-9a-f]{64}$') THEN
        RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
    END IF;
    -- Fresh mutations only. Exact replays belong before this planner and must
    -- never resample authority, acquire fresh eligibility late, or issue a token.
    PERFORM internal.lock_initial_media_handoff_scope(p_owner,p_scan,TRUE);
    SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
    IF r.receipt_digest IS DISTINCT FROM p_admission_digest THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_admission_live_receipt(p_owner,p_scan,r.admission_receipt_id);
    PERFORM internal.assert_initial_media_handoff_chain(p_owner,p_scan);
    IF EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan
            OR reservation_id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID)
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
    END IF;
    snapshot:=internal.capture_initial_media_handoff_snapshot(p_owner,p_scan);
    SELECT array_agg(object_id ORDER BY object_id) INTO original_sources FROM (
        SELECT (value->>'object_id')::UUID AS object_id FROM jsonb_array_elements(r.outcome::JSONB#>'{source_verification,entries}')
        UNION SELECT (value->>'object_id')::UUID FROM jsonb_array_elements(r.outcome::JSONB#>'{resolved_manifest,entries}')
            WHERE value->>'object_id' IS NOT NULL
    ) original;
    SELECT array_agg((value->>'object_id')::UUID ORDER BY (value->>'object_id')::UUID) INTO actual_sources
        FROM jsonb_array_elements(snapshot->'internal.initial_preparation_source_registry');
    IF original_sources IS NULL OR actual_sources IS DISTINCT FROM original_sources
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(snapshot->'internal.initial_preparation_source_registry') x(value)
            WHERE value->>'retired' IS DISTINCT FROM 'false' OR value->>'marker_confirmed' IS DISTINCT FROM 'false'
                OR value->>'claim_token' IS NOT NULL OR value->>'claim_expires_at' IS NOT NULL
                OR value->>'backend_generation' IS DISTINCT FROM r.configuration::JSONB#>>'{assignment,preparation,backend_generation}') THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
    END IF;
    progress:=snapshot->'internal.initial_media_copy_progress'->0;
    claim:=snapshot->'internal.initial_media_verification_claims_v2'->0;
    verified:=snapshot->'internal.initial_media_verification_receipts_v2'->0;
    SELECT jsonb_agg(jsonb_build_object('object_id',o->'object_id',
        'backend_generation',r.mapping::JSONB->'destination_backend_generation')||(o->'bytes') ORDER BY (o->>'object_id')::UUID)
        INTO objects FROM jsonb_array_elements(r.mapping::JSONB->'objects') x(o);
    kind:=CASE p_action WHEN 'claim' THEN 'verification_claim' WHEN 'verify' THEN 'verification_settlement'
        WHEN 'transfer' THEN 'transfer' ELSE 'copy' END;
    cutoff:=(r.media_binding::JSONB#>>ARRAY['phase_window','cutoffs',kind])::BIGINT;
    now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
    prior_ms:=greatest((r.manifest::JSONB->>'authorized_at_ms')::BIGINT,
        (progress->>'started_at_ms')::BIGINT,(progress->>'last_object_at_ms')::BIGINT,
        (progress->>'completed_at_ms')::BIGINT,((claim->>'claim')::JSONB->>'issued_at_ms')::BIGINT);
    IF now_ms<prior_ms OR now_ms>=cutoff THEN
        RAISE EXCEPTION 'initial_analysis_handoff_expired' USING ERRCODE='55000';
    END IF;
    IF p_action IN ('start_copy','record_object','complete_copy') THEN
        relation:='internal.initial_media_copy_progress'; old_image:=progress;
        IF p_action='start_copy' THEN
            IF progress IS NOT NULL THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
            operation:='INSERT';
            new_image:=jsonb_build_object('scan_id',p_scan,'owner_id',p_owner,'admission_receipt_digest',r.receipt_digest,
                'copy_adapter_digest',r.configuration::JSONB#>'{assignment,handoff,profile,copy_adapter_digest}',
                'started_at_ms',now_ms,'completed_objects','[]','last_object_at_ms',NULL,'completed_at_ms',NULL);
        ELSE
            IF progress IS NULL OR progress->>'completed_at_ms' IS NOT NULL OR claim IS NOT NULL THEN
                RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
            operation:='UPDATE';
            IF p_action='record_object' THEN
                SELECT value INTO object_value FROM jsonb_array_elements(objects) WHERE (value->>'object_id')::UUID=p_object;
                IF object_value IS NULL OR EXISTS(SELECT 1 FROM jsonb_array_elements((progress->>'completed_objects')::JSONB)
                    WHERE (value->>'object_id')::UUID=p_object) THEN
                    RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
                SELECT jsonb_agg(value ORDER BY (value->>'object_id')::UUID) INTO objects
                    FROM jsonb_array_elements((progress->>'completed_objects')::JSONB||jsonb_build_array(object_value));
                new_image:=progress||jsonb_build_object('completed_objects',internal.initial_canonical(objects),'last_object_at_ms',now_ms);
            ELSE
                IF (progress->>'completed_objects')::JSONB IS DISTINCT FROM objects THEN
                    RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
                new_image:=progress||jsonb_build_object('completed_at_ms',now_ms);
            END IF;
        END IF;
    ELSE
        operation:='INSERT';
        IF progress->>'completed_at_ms' IS NULL THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
        IF p_action='claim' THEN
            IF claim IS NOT NULL THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
            relation:='internal.initial_media_verification_claims_v2'; kind:='claim';
            document:=internal.initial_canonical(jsonb_build_object('version',2,'binding',r.media_binding::JSONB,
                'admission_receipt_digest',r.receipt_digest,'verification_adapter_digest',
                r.configuration::JSONB#>'{assignment,handoff,profile,verification_adapter_digest}',
                'claim_token',extensions.gen_random_uuid(),'issued_at_ms',now_ms));
        ELSIF p_action='verify' THEN
            IF claim IS NULL OR verified IS NOT NULL OR ((claim->>'claim')::JSONB->>'claim_token')::UUID IS DISTINCT FROM p_claim THEN
                RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
            relation:='internal.initial_media_verification_receipts_v2'; kind:='verification_receipt';
            document:=internal.initial_canonical(jsonb_build_object('version',2,'claim',(claim->>'claim')::JSONB,
                'claim_digest',claim->'claim_digest','objects',objects,'authorized_at_ms',now_ms));
        ELSE
            IF verified IS NULL OR verified->>'receipt_digest' IS DISTINCT FROM p_verification_digest
                OR now_ms<((verified->>'receipt')::JSONB->>'authorized_at_ms')::BIGINT THEN
                RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
            relation:='internal.initial_preparation_transfer_receipts'; kind:='transfer_receipt';
            document:=internal.initial_canonical(jsonb_build_object('version',1,'admission_receipt_digest',r.receipt_digest,
                'protocol_artifact_digest',r.media_binding::JSONB#>'{phase_window,protocol_artifact_digest}',
                'verification_receipt',(verified->>'receipt')::JSONB,'verification_receipt_digest',verified->'receipt_digest',
                'authorized_at_ms',now_ms));
        END IF;
        PERFORM internal.validate_initial_media_handoff_proof(kind,r.candidate,r.input,r.configuration,r.funding,r.outcome,
            r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest,
            CASE WHEN p_action='claim' THEN document ELSE claim->>'claim' END,
            CASE WHEN p_action='verify' THEN document ELSE verified->>'receipt' END,
            CASE WHEN p_action='transfer' THEN document ELSE NULL END);
        new_image:=jsonb_build_object('scan_id',p_scan,'owner_id',p_owner)||CASE WHEN p_action='claim'
            THEN jsonb_build_object('claim',document,'claim_digest',internal.initial_media_handoff_proof_digest(kind,document))
            ELSE jsonb_build_object('receipt',document,'receipt_digest',internal.initial_media_handoff_proof_digest(kind,document)) END;
    END IF;
    -- Bound duplicated OLD/NEW bytes before constructing the event array. The
    -- fixed 512-byte per-event envelope allowance exceeds every closed key and
    -- relation name plus JSON punctuation; the final exact size is checked too.
    ledger_bytes:=2+COALESCE(octet_length(old_image::TEXT),4)+octet_length(new_image::TEXT)+512;
    IF p_action='transfer' THEN
        ledger_bytes:=ledger_bytes+2*octet_length((snapshot->'internal.initial_preparation_source_fences'->0)::TEXT)+512;
        FOR row_image IN SELECT value FROM jsonb_array_elements(snapshot->'internal.initial_preparation_source_registry') LOOP
            ledger_bytes:=ledger_bytes+2*octet_length(row_image::TEXT)+512;
        END LOOP;
        FOREACH member IN ARRAY ARRAY['initial_analysis_preparation_intents','initial_preparation_source_mapping',
            'initial_preparation_source_verifications','initial_preparation_execution_grants',
            'initial_preparation_output_manifests','initial_preparation_output_mapping','initial_preparation_outcomes'] LOOP
            FOR row_image IN SELECT value FROM jsonb_array_elements(snapshot->('internal.'||member)) LOOP
                ledger_bytes:=ledger_bytes+octet_length(row_image::TEXT)+512;
            END LOOP;
        END LOOP;
    END IF;
    IF ledger_bytes>67108864 THEN RAISE EXCEPTION 'initial_analysis_handoff_bounds' USING ERRCODE='54000'; END IF;
    events:=jsonb_build_array(jsonb_build_object('ordinal',0,'frame',0,'relation',relation,'operation',operation,'old',old_image,'new',new_image));
    frames:=jsonb_build_array(jsonb_build_object('id',0,'parent',NULL,'relation',relation,'operation',operation,'events',jsonb_build_array(0)));
    IF p_action='transfer' THEN
        PERFORM internal.assert_initial_media_handoff_cascade_catalog();
        old_image:=snapshot->'internal.initial_preparation_source_fences'->0;
        IF old_image->>'state' IS DISTINCT FROM 'allocated' OR old_image->>'execution_state' IS DISTINCT FROM 'issued'
            OR old_image->>'provider_barrier' IS DISTINCT FROM 'blocked_pre_admission' THEN
            RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
        relation:='internal.initial_preparation_source_fences';
        events:=events||jsonb_build_array(jsonb_build_object('ordinal',1,'frame',1,'relation',relation,'operation','UPDATE',
            'old',old_image,'new',old_image||'{"state":"retired"}'::JSONB));
        frames:=frames||jsonb_build_array(jsonb_build_object('id',1,'parent',NULL,'relation',relation,'operation','UPDATE','events',jsonb_build_array(1)));
        relation:='internal.initial_preparation_source_registry';
        IF jsonb_array_length(snapshot->relation)=0 THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
        FOR old_image IN SELECT value FROM jsonb_array_elements(snapshot->relation) ORDER BY (value->>'object_id')::UUID LOOP
            IF old_image->>'retired' IS DISTINCT FROM 'false' OR old_image->>'marker_confirmed' IS DISTINCT FROM 'false'
                OR old_image->>'claim_token' IS NOT NULL OR old_image->>'claim_expires_at' IS NOT NULL THEN
                RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
            frame_id:=jsonb_array_length(frames); event_index:=jsonb_array_length(events);
            events:=events||jsonb_build_array(jsonb_build_object('ordinal',event_index,'frame',frame_id,'relation',relation,'operation','UPDATE',
                'old',old_image,'new',old_image||'{"retired":true}'::JSONB));
            frames:=frames||jsonb_build_array(jsonb_build_object('id',frame_id,'parent',NULL,'relation',relation,'operation','UPDATE','events',jsonb_build_array(event_index)));
        END LOOP;
        intent_frame:=jsonb_array_length(frames);
        FOREACH member IN ARRAY ARRAY['initial_analysis_preparation_intents','initial_preparation_source_mapping',
            'initial_preparation_source_verifications','initial_preparation_execution_grants',
            'initial_preparation_output_manifests','initial_preparation_output_mapping','initial_preparation_outcomes'] LOOP
            relation:='internal.'||member; frame_id:=jsonb_array_length(frames); indices:='[]'::JSONB;
            IF member='initial_analysis_preparation_intents' THEN
                parent_frame:=NULL;
                IF jsonb_array_length(snapshot->relation)<>1 THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
            ELSIF member='initial_preparation_output_mapping' THEN
                -- No manifest row means no FK grandchild statement at all.
                IF jsonb_array_length(snapshot->'internal.initial_preparation_output_manifests')=0 THEN CONTINUE; END IF;
                parent_frame:=manifest_frame;
            ELSE parent_frame:=intent_frame;
            END IF;
            IF member='initial_preparation_output_manifests' THEN manifest_frame:=frame_id; END IF;
            FOR old_image IN SELECT value FROM jsonb_array_elements(snapshot->relation) LOOP
                event_index:=jsonb_array_length(events); indices:=indices||jsonb_build_array(event_index);
                events:=events||jsonb_build_array(jsonb_build_object('ordinal',event_index,'frame',frame_id,'relation',relation,
                    'operation','DELETE','old',old_image,'new',NULL));
            END LOOP;
            frames:=frames||jsonb_build_array(jsonb_build_object('id',frame_id,'parent',parent_frame,
                'relation',relation,'operation','DELETE','events',indices));
        END LOOP;
    END IF;
    -- Every old/new image is already bounded by the snapshot or a stricter
    -- canonical document schema. Include envelope/duplication before persistence.
    IF jsonb_array_length(events)>(CASE WHEN p_action='transfer' THEN 39 ELSE 1 END)
        OR jsonb_array_length(frames)>32 OR octet_length(events::TEXT)>67108864
        OR octet_length(internal.initial_canonical(frames))>32768 THEN
        RAISE EXCEPTION 'initial_analysis_handoff_bounds' USING ERRCODE='54000'; END IF;
    final_plan:=jsonb_build_object('version',1,'authority','none','owner_id',p_owner,'scan_id',p_scan,
        'action',p_action,'admission_receipt_digest',p_admission_digest,'object_id',p_object,'claim_token',p_claim,
        'verification_receipt_digest',p_verification_digest,'authorized_at_ms',now_ms,'cutoff_ms',cutoff,
        'snapshot',snapshot,'events',events,'frames',frames);
    RETURN final_plan;
END; $$;

REVOKE ALL ON FUNCTION internal.initial_media_handoff_snapshot_catalog(),
    internal.capture_initial_media_handoff_snapshot(UUID,UUID),
    internal.assert_initial_media_handoff_cascade_catalog(),
    internal.plan_initial_media_handoff_mutation(UUID,UUID,TEXT,TEXT,UUID,UUID,TEXT)
    FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;
