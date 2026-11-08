-- Coherent atomic admission candidate. Activation remains disabled.
SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- The durable admitted footprint preserves exact raw bucket bytes. Eligibility
-- must precede preparation allocation and be rechecked before original funding.
-- This is deliberately not a constraint/mutation on historical policy rows.
CREATE FUNCTION internal.assert_initial_admission_policy(p_policy internal.ai_quota_policies)
RETURNS VOID LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path = '' AS $$
BEGIN
    IF p_policy.operation IS DISTINCT FROM 'scan_identification'
        OR p_policy.effective_plan IS NULL
        OR p_policy.effective_plan NOT IN ('free','pro_trial','pro_paid','pro_complimentary')
        OR p_policy.enabled IS DISTINCT FROM TRUE
        OR p_policy.allowed IS DISTINCT FROM TRUE
        OR p_policy.model IS NULL OR pg_catalog.btrim(p_policy.model) = ''
        OR p_policy.policy_version IS NULL
        OR p_policy.policy_version NOT BETWEEN 1 AND 9007199254740991
        OR NOT (
            (p_policy.daily_bucket IS NULL AND p_policy.daily_limit IS NULL)
            OR (p_policy.daily_bucket IS NOT NULL AND p_policy.daily_limit IS NOT NULL
                AND pg_catalog.btrim(p_policy.daily_bucket) <> ''
                AND pg_catalog.octet_length(p_policy.daily_bucket) <= 1024
                AND p_policy.daily_limit > 0)
        )
        OR p_policy.user_rate_bucket IS NULL
        OR pg_catalog.btrim(p_policy.user_rate_bucket) = ''
        OR pg_catalog.octet_length(p_policy.user_rate_bucket) > 1024
        OR p_policy.user_window_seconds IS NULL
        OR p_policy.user_window_seconds NOT BETWEEN 1 AND 3600
        OR p_policy.user_window_limit IS NULL OR p_policy.user_window_limit <= 0
        OR p_policy.ip_rate_bucket IS NULL
        OR pg_catalog.btrim(p_policy.ip_rate_bucket) = ''
        OR pg_catalog.octet_length(p_policy.ip_rate_bucket) > 1024
        OR p_policy.ip_window_seconds IS NULL
        OR p_policy.ip_window_seconds NOT BETWEEN 1 AND 3600
        OR p_policy.ip_window_limit IS NULL OR p_policy.ip_window_limit <= 0
    THEN
        RAISE EXCEPTION 'initial_analysis_assignment_changed' USING ERRCODE = '55000';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_initial_admission_policy(internal.ai_quota_policies)
    FROM PUBLIC, anon, authenticated, service_role;

-- This exact existing resolver runs before the first source fence, intent or
-- registry insert, including raw-intent validation. It does not change policy.
DO $preparation_policy$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    SELECT pg_catalog.pg_get_functiondef(
        'internal.resolve_initial_media_preparation_assignment(uuid,uuid,text,text,boolean,jsonb)'::REGPROCEDURE
    ) INTO STRICT definition;
    anchor := ' SELECT * INTO policy FROM internal.resolve_quota_policy(''scan_identification'',p_plan);';
    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition,anchor,'')))
        / pg_catalog.length(anchor) <> 1 THEN
        RAISE EXCEPTION 'initial atomic preparation policy source drift';
    END IF;
    EXECUTE pg_catalog.replace(definition,anchor,
        anchor || E'\n PERFORM internal.assert_initial_admission_policy(policy);');
END;
$preparation_policy$;

-- The finalizer owns the only stage lifecycle. No stage data is API authority.
CREATE TABLE internal.initial_preparation_admission_staging (
    scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_operation_fences(scan_id),
    owner_id UUID NOT NULL,
    transaction_id XID8 NOT NULL,
    stage_token UUID NOT NULL UNIQUE,
    phase TEXT NOT NULL CHECK (phase IN ('validated','compared','reserved','admitted','allocated','consuming')),
    admission_receipt_id UUID NOT NULL UNIQUE,
    candidate TEXT NOT NULL CHECK (octet_length(candidate) <= 1048576),
    assignment TEXT NOT NULL CHECK (octet_length(assignment) <= 65536),
    outcome TEXT NOT NULL CHECK (octet_length(outcome) <= 131072),
    input TEXT NOT NULL CHECK (octet_length(input) <= 1048576),
    installation TEXT NOT NULL CHECK (octet_length(installation) <= 16384),
    protocol TEXT NOT NULL CHECK (octet_length(protocol) <= 16384),
    destination TEXT NOT NULL CHECK (octet_length(destination) <= 16384),
    phase_window TEXT NOT NULL CHECK (octet_length(phase_window) <= 8192),
    mapping TEXT NOT NULL CHECK (octet_length(mapping) <= 65536),
    media_binding TEXT NOT NULL CHECK (octet_length(media_binding) <= 16384),
    completion_event_seq BIGINT NOT NULL DEFAULT 0 CHECK(completion_event_seq>=0),
    cleanup_cursor BIGINT NOT NULL DEFAULT 0 CHECK(cleanup_cursor>=0),
    prospective_receipt JSONB,
    completion_ledger JSONB CHECK (completion_ledger IS NULL OR octet_length(completion_ledger::TEXT)<=67108864),
    policy internal.ai_quota_policies,
    resolved_link UUID,
    acquire_hold BOOLEAN,
    core8_at TIMESTAMPTZ,
    core4_at TIMESTAMPTZ,
    reservation_id UUID,
    lease_token UUID,
    UNIQUE (scan_id,owner_id),
    CHECK ((phase = 'validated') = (acquire_hold IS NULL)),
    CHECK (phase = 'validated' OR core8_at IS NOT NULL)
);

-- Expected images are bounded by the closed statement set, never caller-selected
-- generic actions. User images contain only ID and entitlement counters.
CREATE TABLE internal.initial_preparation_admission_writes (
    scan_id UUID NOT NULL REFERENCES internal.initial_preparation_admission_staging(scan_id) ON DELETE CASCADE,
    statement_key TEXT NOT NULL,
    relation_name TEXT NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT','UPDATE','UPSERT')),
    old_image JSONB,
    new_image JSONB NOT NULL,
    consumed BOOLEAN NOT NULL DEFAULT FALSE,
    observed_operation TEXT CHECK (observed_operation IN ('INSERT','UPDATE')),
    observed_old_image JSONB,
    observed_new_image JSONB,
    PRIMARY KEY (scan_id,statement_key),
    CHECK (octet_length(new_image::TEXT) <= 4194304),
    CHECK (old_image IS NULL OR octet_length(old_image::TEXT) <= 4194304),
    CHECK (observed_old_image IS NULL OR octet_length(observed_old_image::TEXT) <= 4194304),
    CHECK (observed_new_image IS NULL OR octet_length(observed_new_image::TEXT) <= 4194304),
    CHECK ((NOT consumed AND observed_operation IS NULL AND observed_old_image IS NULL AND observed_new_image IS NULL)
        OR (consumed AND observed_operation IS NOT NULL AND observed_new_image IS NOT NULL
            AND (observed_operation='UPDATE')=(observed_old_image IS NOT NULL)))
);

-- Complete original bytes are co-retained; the receipt has no dependency on the
-- preparation intent and cannot reconstruct missing proof from mutable rows.
CREATE TABLE internal.initial_preparation_admission_receipts (
    scan_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    admission_receipt_id UUID NOT NULL UNIQUE,
    candidate TEXT NOT NULL,
    input TEXT NOT NULL,
    configuration TEXT NOT NULL,
    funding TEXT NOT NULL,
    outcome TEXT NOT NULL,
    installation TEXT NOT NULL,
    protocol TEXT NOT NULL,
    destination TEXT NOT NULL,
    mapping TEXT NOT NULL,
    media_binding TEXT NOT NULL,
    accounting TEXT NOT NULL,
    manifest TEXT NOT NULL,
    receipt_digest TEXT NOT NULL CHECK (receipt_digest ~ '^[0-9a-f]{64}$'),
    UNIQUE (scan_id,owner_id),
    FOREIGN KEY (scan_id,owner_id) REFERENCES internal.initial_analysis_submissions(scan_id,owner_id) ON DELETE CASCADE,
    CHECK (receipt_digest = internal.validate_initial_admitted_proof(
        candidate,input,configuration,funding,outcome,installation,protocol,
        destination,mapping,media_binding,accounting,manifest))
);
CREATE INDEX initial_admission_receipts_owner ON internal.initial_preparation_admission_receipts(owner_id,scan_id);

ALTER TABLE internal.initial_preparation_admission_staging ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_preparation_admission_writes ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_preparation_admission_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_preparation_admission_staging,
    internal.initial_preparation_admission_writes,internal.initial_preparation_admission_receipts
    FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.create_initial_admission_stage(p_owner UUID,p_scan UUID)
RETURNS UUID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    saved internal.initial_analysis_preparation_intents;
    result internal.initial_preparation_outcomes;
    context JSONB; a JSONB; h JSONB; outcome_value JSONB;
    installation_text TEXT; protocol_text TEXT; destination_text TEXT;
    metadata JSONB; scope JSONB; window_value JSONB; mapping_value JSONB; binding_value JSONB;
    media JSONB := '[]'::JSONB; items JSONB := '[]'::JSONB; objects JSONB := '{}'::JSONB;
    source JSONB; source_proof JSONB; prepared JSONB; resolved JSONB; bytes JSONB;
    source_id UUID; prepared_id UUID; receipt_id UUID := pg_catalog.gen_random_uuid();
    token UUID := pg_catalog.gen_random_uuid(); ordinal INTEGER;
    input_text TEXT; outcome_digest TEXT; mapping_text TEXT; binding_text TEXT; window_text TEXT;
    anchor NUMERIC; expiry NUMERIC;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
    SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
    IF saved.owner_id IS DISTINCT FROM p_owner OR saved.canonical_assignment::JSONB->>'version' IS DISTINCT FROM '3' THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
    IF EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_initial_preparation_eligibility(p_scan);
    PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
    IF NOT internal.initial_preparation_execution_coherent(p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    SELECT * INTO STRICT result FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan;
    context := internal.initial_saved_qualified_context(saved.canonical_candidate,saved.canonical_assignment);
    a := context->'assignment'; h := a#>'{handoff,profile}'; outcome_value := result.canonical_outcome::JSONB;
    SELECT canonical_installation INTO STRICT installation_text FROM internal.initial_preparation_handoff_installations
        WHERE digest=a#>>'{handoff,installation_digest}';
    SELECT canonical_artifact INTO STRICT protocol_text FROM internal.initial_preparation_handoff_protocol_artifacts
        WHERE digest=h->>'protocol_artifact_digest';
    SELECT internal.initial_canonical(jsonb_build_object('generation',b.generation,'provider',b.provider,
        'direct_endpoint',b.direct_endpoint,'private_bucket',b.private_bucket,'namespace',b.namespace,
        'credential_profile',b.credential_profile)) INTO STRICT destination_text
        FROM internal.initial_analysis_media_backends b WHERE generation=(h->>'destination_backend_generation')::UUID;
    expiry := floor(extract(epoch FROM saved.expires_at)*1000);
    PERFORM internal.assert_initial_qualified_outcome(p_scan,context,expiry,result.canonical_outcome);
    anchor := floor(extract(epoch FROM clock_timestamp())*1000);
    scope := jsonb_build_object('owner_id',p_owner,'scan_id',p_scan,'admission_receipt_id',receipt_id);
    window_value := scope || jsonb_build_object('version',1,'handoff_profile_digest',a#>'{handoff,profile_digest}',
        'handoff_installation_digest',a#>'{handoff,installation_digest}',
        'protocol_artifact_digest',h->'protocol_artifact_digest','anchor_ms',anchor,
        'original_expires_at_ms',expiry,'cutoffs',internal.initial_handoff_phase_cutoffs(
            internal.initial_canonical(h),protocol_text,anchor,expiry));
    FOR source,ordinal IN SELECT v,(i-1)::INTEGER
        FROM jsonb_array_elements(saved.canonical_candidate::JSONB#>'{source_plan,sources}') WITH ORDINALITY t(v,i)
    LOOP
        source_proof := outcome_value#>ARRAY['source_verification','entries',ordinal::TEXT];
        prepared := outcome_value#>ARRAY['output_manifest','entries',ordinal::TEXT,'prepared'];
        resolved := outcome_value#>ARRAY['resolved_manifest','entries',ordinal::TEXT,'object_id'];
        source_id := pg_catalog.gen_random_uuid();
        prepared_id := CASE WHEN prepared='null'::JSONB THEN NULL
            WHEN source_proof->'bytes'=prepared->'bytes' THEN source_id ELSE pg_catalog.gen_random_uuid() END;
        objects := objects || jsonb_build_object(source_id::TEXT,source_proof->'bytes');
        IF prepared_id IS NOT NULL THEN objects := objects || jsonb_build_object(prepared_id::TEXT,prepared->'bytes'); END IF;
        items := items || jsonb_build_array(jsonb_build_object('index',ordinal,
            'source',jsonb_build_object('original_object_id',source_proof->'object_id','destination_object_id',source_id,'bytes',source_proof->'bytes'),
            'prepared',CASE WHEN prepared_id IS NOT NULL THEN jsonb_build_object('original_object_id',resolved,'destination_object_id',prepared_id,'bytes',prepared->'bytes') END));
        bytes := CASE WHEN prepared='null'::JSONB THEN source_proof->'bytes' ELSE prepared->'bytes' END;
        media := media || jsonb_build_array((source-'prepared_output') || jsonb_build_object(
            'content_type',bytes->'content_type','byte_count',bytes->'byte_count','sha256',bytes->'sha256'));
    END LOOP;
    -- Cross-family uniqueness is explicit; each table's PK alone is insufficient.
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(objects) k
        WHERE EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry r WHERE r.object_id=k::UUID)
           OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry r WHERE r.object_id=k::UUID)) THEN
        RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
    END IF;
    input_text := internal.initial_canonical(((saved.canonical_candidate::JSONB->'source_plan')-'sources') || jsonb_build_object('media',media));
    PERFORM internal.parse_initial_input(input_text);
    outcome_digest := internal.initial_qualified_outcome_digest(result.canonical_outcome);
    mapping_value := scope || jsonb_build_object('version',2,'assignment_digest',saved.assignment_digest,
        'outcome_digest',outcome_digest,'source_backend_generation',h->'source_backend_generation',
        'destination_backend_generation',h->'destination_backend_generation','items',items,
        'objects',(SELECT jsonb_agg(jsonb_build_object('object_id',k,'bytes',v) ORDER BY k COLLATE "C") FROM jsonb_each(objects) t(k,v)));
    window_text := internal.initial_canonical(window_value); mapping_text := internal.initial_canonical(mapping_value);
    binding_value := scope || jsonb_build_object('version',2,'submission_digest',internal.initial_digest('input',input_text),
        'assignment_digest',saved.assignment_digest,'outcome_digest',outcome_digest,
        'mapping_digest',internal.initial_admission_metadata_digest('mapping',mapping_text),
        'destination_backend_generation',h->'destination_backend_generation','phase_window',window_value,
        'phase_window_digest',internal.initial_admission_metadata_digest('phase_window',window_text));
    binding_text := internal.initial_canonical(binding_value);
    metadata := internal.validate_initial_admission_metadata(saved.canonical_candidate,saved.canonical_assignment,
        internal.initial_canonical(context->'profile'),installation_text,
        protocol_text,destination_text,expiry,
        result.canonical_outcome,internal.initial_canonical(scope),window_text,mapping_text,binding_text);
    IF metadata->>'canonical_input' IS DISTINCT FROM input_text THEN
        RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
    END IF;
    INSERT INTO internal.initial_preparation_admission_staging(scan_id,owner_id,transaction_id,stage_token,phase,
        admission_receipt_id,candidate,assignment,outcome,input,installation,protocol,destination,phase_window,mapping,media_binding)
    VALUES(p_scan,p_owner,pg_catalog.pg_current_xact_id(),token,'validated',receipt_id,
        saved.canonical_candidate,saved.canonical_assignment,result.canonical_outcome,input_text,
        installation_text,protocol_text,
        destination_text,window_text,mapping_text,binding_text);
    RETURN token;
END;
$$;
REVOKE ALL ON FUNCTION internal.create_initial_admission_stage(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.freeze_initial_admission_policy(
    p_owner UUID,p_scan UUID,p_plan TEXT,p_fallback BOOLEAN,p_link UUID,p_acquire_hold BOOLEAN,p_core8_at TIMESTAMPTZ
) RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $$
DECLARE
    stage internal.initial_preparation_admission_staging;
    selected_policy internal.ai_quota_policies;
    selected_binding internal.identification_provider_bindings;
    a JSONB; input_value JSONB; client_protocol INTEGER; identification_protocol INTEGER;
BEGIN
    SELECT * INTO stage FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan FOR UPDATE;
    IF NOT FOUND OR stage.owner_id IS DISTINCT FROM p_owner
        OR stage.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
        OR stage.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE)
        OR stage.phase IS DISTINCT FROM 'validated'
        OR p_core8_at IS NULL OR p_acquire_hold IS NULL OR p_fallback IS NULL THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
    a := stage.assignment::JSONB; input_value := stage.input::JSONB;
    IF p_plan IS DISTINCT FROM a->>'effective_plan'
        OR p_fallback IS DISTINCT FROM (a->>'flash_fallback_used')::BOOLEAN
        OR p_link IS DISTINCT FROM (CASE WHEN p_plan='pro_complimentary' THEN p_scan END)
        OR p_acquire_hold IS DISTINCT FROM (p_plan='pro_complimentary') THEN
        RAISE EXCEPTION 'initial_analysis_assignment_changed' USING ERRCODE='55000';
    END IF;
    -- A nonblocking first policy acquisition preserves the retained outer scope.
    SELECT * INTO selected_policy FROM internal.ai_quota_policies
        WHERE operation='scan_identification' AND effective_plan=p_plan FOR SHARE NOWAIT;
    PERFORM internal.assert_initial_admission_policy(selected_policy);
    IF selected_policy.model IS DISTINCT FROM a->>'quota_model'
        OR selected_policy.policy_version IS DISTINCT FROM (a->>'policy_version')::BIGINT THEN
        RAISE EXCEPTION 'initial_analysis_assignment_changed' USING ERRCODE='55000';
    END IF;
    SELECT * INTO selected_binding FROM internal.identification_provider_bindings
        WHERE operation='scan_identification' AND effective_plan=p_plan
            AND model=selected_policy.model AND policy_version=selected_policy.policy_version
            AND input_profile=a->>'input_profile' FOR SHARE NOWAIT;
    IF NOT FOUND OR selected_binding.provider IS DISTINCT FROM a->>'provider'
        OR selected_binding.binding IS DISTINCT FROM a->>'binding'
        OR selected_binding.processor_permission IS DISTINCT FROM a->>'processor_permission'
        OR selected_binding.provider_model IS DISTINCT FROM a->>'provider_model'
        OR selected_binding.minimum_client_protocol IS DISTINCT FROM (a->>'minimum_client_protocol')::INTEGER
        OR selected_binding.minimum_identification_protocol IS DISTINCT FROM (a->>'minimum_identification_protocol')::INTEGER
        OR COALESCE(selected_binding.provider_model,selected_policy.model) IS DISTINCT FROM a->>'effective_model' THEN
        RAISE EXCEPTION 'initial_analysis_assignment_changed' USING ERRCODE='55000';
    END IF;
    client_protocol := internal.require_identification_client_protocol(p_owner,'scan_identification',p_scan,
        a->>'input_profile',(input_value#>>'{admission,client_protocol}')::INTEGER,FALSE,selected_binding.minimum_client_protocol);
    identification_protocol := internal.require_identification_capability(p_owner,'scan_identification',p_scan,
        a->>'input_profile',(input_value#>>'{admission,identification_protocol}')::INTEGER,FALSE,selected_binding.minimum_identification_protocol);
    IF client_protocol IS DISTINCT FROM (a->>'accepted_client_protocol')::INTEGER
        OR identification_protocol IS DISTINCT FROM (a->>'accepted_identification_protocol')::INTEGER THEN
        RAISE EXCEPTION 'initial_analysis_assignment_changed' USING ERRCODE='55000';
    END IF;
    PERFORM config_key FROM internal.ai_consent_rollout_config WHERE config_key='current' FOR SHARE NOWAIT;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
    PERFORM id FROM public.user_adult_eligibility_receipts WHERE user_id=p_owner ORDER BY id FOR SHARE NOWAIT;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
    PERFORM id FROM public.user_terms_acceptance_receipts WHERE user_id=p_owner ORDER BY id FOR SHARE NOWAIT;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
    PERFORM id FROM public.user_ai_consent_events WHERE user_id=p_owner ORDER BY id FOR SHARE NOWAIT;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
    PERFORM internal.require_identification_processor_consent(p_owner,selected_binding.processor_permission);
    IF floor(extract(epoch FROM clock_timestamp())*1000)>=(stage.phase_window::JSONB#>>'{cutoffs,admission}')::NUMERIC THEN
        RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000';
    END IF;
    UPDATE internal.initial_preparation_admission_staging
        SET policy=selected_policy,resolved_link=p_link,acquire_hold=p_acquire_hold,core8_at=p_core8_at,phase='compared'
        WHERE scan_id=p_scan;
END;
$$;
REVOKE ALL ON FUNCTION internal.freeze_initial_admission_policy(UUID,UUID,TEXT,BOOLEAN,UUID,BOOLEAN,TIMESTAMPTZ)
    FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_admission_frozen_policy(p_owner UUID,p_scan UUID,p_plan TEXT)
RETURNS internal.ai_quota_policies LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $$
DECLARE stage internal.initial_preparation_admission_staging;
BEGIN
    SELECT * INTO stage FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan;
    IF NOT FOUND OR stage.owner_id IS DISTINCT FROM p_owner
        OR stage.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
        OR stage.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE)
        OR stage.phase IS DISTINCT FROM 'compared'
        OR (stage.policy).effective_plan IS DISTINCT FROM p_plan
        OR current_setting('merian.quota_v2_fence',TRUE) IS DISTINCT FROM 'on'
        OR current_setting('merian.entitlement_plan_override',TRUE) IS DISTINCT FROM p_plan THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_admission_policy(stage.policy);
    RETURN stage.policy;
END;
$$;
REVOKE ALL ON FUNCTION internal.initial_admission_frozen_policy(UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;

-- Only these existing owners may describe prospective statements. The helper is
-- revoked; neither a caller GUC nor an arbitrary table name opens a write path.
-- One closed statement catalog is shared by live registration and terminal
-- proof validation. Unknown keys cannot select an arbitrary relation.
CREATE FUNCTION internal.initial_admission_statement_contract(p_key TEXT)
RETURNS TABLE(relation_name TEXT,operation TEXT) LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE expected_relation TEXT; expected_operation TEXT;
BEGIN
    expected_relation := CASE p_key
        WHEN 'C8.hold.insert' THEN 'internal.complimentary_scan_usage'
        WHEN 'C8.epoch.update' THEN 'public.users'
        WHEN 'C4.reservation.insert' THEN 'internal.ai_quota_reservations'
        WHEN 'C4.remaining.update' THEN 'internal.ai_quota_reservations'
        WHEN 'C8.attachment.update' THEN 'internal.ai_quota_reservations'
        WHEN 'Counter.daily.upsert' THEN 'internal.ai_quota_counters'
        WHEN 'Counter.user.upsert' THEN 'internal.ai_quota_counters'
        WHEN 'Counter.ip.upsert' THEN 'internal.ai_quota_counters'
        WHEN 'C4.daily.link' THEN 'internal.ai_quota_reservation_counters'
        WHEN 'C4.user.link' THEN 'internal.ai_quota_reservation_counters'
        WHEN 'C4.ip.link' THEN 'internal.ai_quota_reservation_counters'
        WHEN 'Provider.attempt.insert' THEN 'internal.identification_provider_attempts'
        WHEN 'Finalizer.submission.insert' THEN 'internal.initial_analysis_submissions'
        WHEN 'Finalizer.admission.insert' THEN 'internal.initial_analysis_admissions'
        WHEN 'Lifecycle.pending.insert' THEN 'internal.initial_analysis_lifecycle_fences'
        WHEN 'Handoff.receipt.insert' THEN 'internal.initial_preparation_admission_receipts'
        WHEN 'M1.fence.insert' THEN 'internal.initial_analysis_media_allocation_fences'
        WHEN 'M1.cohort.insert' THEN 'internal.initial_analysis_media_cohorts'
        ELSE CASE WHEN p_key ~ '^M1[.]object[.][0-9a-f-]{36}$' THEN 'internal.initial_analysis_media_registry' END END;
    expected_operation := CASE WHEN p_key LIKE 'Counter.%.upsert' THEN 'UPSERT'
        WHEN p_key IN ('C8.epoch.update','C4.remaining.update','C8.attachment.update') THEN 'UPDATE' ELSE 'INSERT' END;
    RETURN QUERY SELECT expected_relation,expected_operation;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_admission_statement_contract(TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.assert_initial_admission_write_registration(
    p_scan UUID,p_key TEXT,p_relation TEXT,p_operation TEXT,p_old JSONB,p_new JSONB
) RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $$
DECLARE stage internal.initial_preparation_admission_staging; expected_relation TEXT; expected_operation TEXT;
BEGIN
    SELECT * INTO stage FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan;
    IF NOT FOUND OR stage.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
        OR stage.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE)
        OR stage.phase NOT IN ('compared','reserved','admitted') OR p_new IS NULL THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    SELECT c.relation_name,c.operation INTO expected_relation,expected_operation
        FROM internal.initial_admission_statement_contract(p_key) c;
    IF expected_relation IS NULL OR p_relation IS DISTINCT FROM expected_relation
        OR p_operation IS DISTINCT FROM expected_operation
        OR (p_operation='UPDATE') IS DISTINCT FROM (p_old IS NOT NULL)
        OR (stage.phase<>'compared' AND p_key ~ '^(C[48][.]|Counter[.]|Provider[.])')
        OR (stage.phase<>'reserved' AND p_key ~ '^(Finalizer[.]|Lifecycle[.]|Handoff[.])')
        OR (stage.phase<>'admitted' AND p_key LIKE 'M1.%') THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    IF p_relation='public.users' AND (p_new-ARRAY['id','complimentary_entitlement_epoch','entitlement_version']<>'{}'::JSONB
        OR p_old-ARRAY['id','complimentary_entitlement_epoch','entitlement_version']<>'{}'::JSONB) THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_initial_admission_write_registration(UUID,TEXT,TEXT,TEXT,JSONB,JSONB)
    FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.register_initial_admission_write(
    p_scan UUID,p_key TEXT,p_relation TEXT,p_operation TEXT,p_old JSONB,p_new JSONB
) RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $$
BEGIN
    -- The table trigger applies the same closed registration contract to every
    -- insertion, including private aliases; registration never bypasses it.
    INSERT INTO internal.initial_preparation_admission_writes(scan_id,statement_key,relation_name,operation,old_image,new_image)
        VALUES(p_scan,p_key,p_relation,p_operation,p_old,p_new);
END; $$;
REVOKE ALL ON FUNCTION internal.register_initial_admission_write(UUID,TEXT,TEXT,TEXT,JSONB,JSONB)
    FROM PUBLIC,anon,authenticated,service_role;

-- Shared pure predicate for both the winning AFTER owner and the immutable
-- transient ledger. UPSERT retains the actual winning event as well as its
-- prewrite specification; mutable counter totals never enter the durable receipt.
CREATE FUNCTION internal.initial_admission_image_matches(
    p_expected internal.initial_preparation_admission_writes,p_operation TEXT,p_old JSONB,p_new JSONB
) RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF p_operation IS NULL OR p_operation NOT IN ('INSERT','UPDATE') OR p_new IS NULL THEN RETURN FALSE; END IF;
    IF p_expected.relation_name='public.users' AND (p_operation<>'UPDATE' OR p_old IS NULL
        OR p_old-ARRAY['id','complimentary_entitlement_epoch','entitlement_version']<>'{}'::JSONB
        OR p_new-ARRAY['id','complimentary_entitlement_epoch','entitlement_version']<>'{}'::JSONB) THEN RETURN FALSE; END IF;
    IF p_expected.operation='UPSERT' THEN
        RETURN COALESCE(
            p_new-ARRAY['request_count','updated_at'] = p_expected.new_image-ARRAY['limit','updated_at']
            AND p_new->'updated_at' = p_expected.new_image->'updated_at'
            AND ((p_operation='INSERT' AND (p_new->>'request_count')::INTEGER=1 AND p_old IS NULL)
                OR (p_operation='UPDATE' AND p_old IS NOT NULL
                    AND p_old-ARRAY['request_count','updated_at'] = p_new-ARRAY['request_count','updated_at']
                    AND (p_new->>'request_count')::INTEGER = (p_old->>'request_count')::INTEGER+1))
            AND (p_new->>'request_count')::INTEGER <= (p_expected.new_image->>'limit')::INTEGER,FALSE);
    END IF;
    RETURN p_expected.operation IS NOT DISTINCT FROM p_operation
        AND p_expected.old_image IS NOT DISTINCT FROM p_old AND p_expected.new_image IS NOT DISTINCT FROM p_new;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_admission_image_matches(internal.initial_preparation_admission_writes,TEXT,JSONB,JSONB)
    FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_admission_expected_write(
    p_scan UUID,p_relation TEXT,p_operation TEXT,p_old JSONB,p_new JSONB,p_consume BOOLEAN
) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $$
DECLARE stage internal.initial_preparation_admission_staging; expected internal.initial_preparation_admission_writes;
    old_value JSONB:=p_old; new_value JSONB:=p_new; matches INTEGER:=0; matched_key TEXT;
BEGIN
    IF p_consume IS NULL OR p_operation IS NULL OR p_new IS NULL
        OR (p_consume AND pg_catalog.pg_trigger_depth()<1) THEN RETURN FALSE; END IF;
    SELECT * INTO stage FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan;
    IF NOT FOUND OR stage.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
        OR stage.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE)
        OR stage.phase NOT IN ('compared','reserved','admitted') THEN RETURN FALSE; END IF;
    IF p_relation='public.users' THEN
        IF p_old-ARRAY['complimentary_entitlement_epoch','entitlement_version'] IS DISTINCT FROM p_new-ARRAY['complimentary_entitlement_epoch','entitlement_version'] THEN RETURN FALSE; END IF;
        SELECT jsonb_object_agg(k,v) INTO old_value FROM jsonb_each(p_old) x(k,v) WHERE k=ANY(ARRAY['id','complimentary_entitlement_epoch','entitlement_version']);
        SELECT jsonb_object_agg(k,v) INTO new_value FROM jsonb_each(p_new) x(k,v) WHERE k=ANY(ARRAY['id','complimentary_entitlement_epoch','entitlement_version']);
    END IF;
    FOR expected IN SELECT * FROM internal.initial_preparation_admission_writes
        WHERE scan_id=p_scan AND relation_name=p_relation AND NOT consumed
    LOOP
        IF (stage.phase<>'compared' AND expected.statement_key ~ '^(C[48][.]|Counter[.]|Provider[.])')
            OR (stage.phase<>'reserved' AND expected.statement_key ~ '^(Finalizer[.]|Lifecycle[.]|Handoff[.])')
            OR (stage.phase<>'admitted' AND expected.statement_key LIKE 'M1.%') THEN CONTINUE; END IF;
        IF NOT internal.initial_admission_image_matches(expected,p_operation,old_value,new_value) THEN CONTINUE; END IF;
        matches:=matches+1; matched_key:=expected.statement_key;
    END LOOP;
    IF matches<>1 THEN RETURN FALSE; END IF;
    IF p_consume THEN
        UPDATE internal.initial_preparation_admission_writes SET consumed=TRUE,observed_operation=p_operation,
            observed_old_image=old_value,observed_new_image=new_value
            WHERE scan_id=p_scan AND statement_key=matched_key AND NOT consumed;
        IF NOT FOUND THEN RETURN FALSE; END IF;
        -- The winning member AFTER event and this scan-bound deferred stage
        -- event are inseparable. Any failure rolls back both expectation and
        -- member. BEFORE INSERT probes in an UPSERT never queue an event.
        UPDATE internal.initial_preparation_admission_staging
            SET completion_event_seq=completion_event_seq+1
            WHERE scan_id=p_scan AND transaction_id=pg_catalog.pg_current_xact_id()
                AND stage_token::TEXT=current_setting('merian.initial_admission_stage',TRUE)
                AND phase=stage.phase AND completion_event_seq<9223372036854775807;
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
    RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION internal.initial_admission_expected_write(UUID,TEXT,TEXT,JSONB,JSONB,BOOLEAN)
    FROM PUBLIC,anon,authenticated,service_role;

-- Instrument existing funding owners without opening their source barrier.
-- The complete finalizer/guard cutover must be reviewed before this is usable.
DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$    quota_now TIMESTAMPTZ;$old$; replacement TEXT := $new$    quota_now TIMESTAMPTZ;
    atomic_initial BOOLEAN := FALSE;
    atomic_old internal.ai_quota_reservations;
    atomic_user JSONB;$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 1';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$            PERFORM internal.assert_initial_preparation_assignment(p_user_id,p_request_id,resolved_plan,resolved_flash_fallback,FALSE);$old$; replacement TEXT := $new$            IF (SELECT canonical_assignment::JSONB->>'version' FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_request_id)='3' THEN
                PERFORM internal.freeze_initial_admission_policy(p_user_id,p_request_id,resolved_plan,
                    resolved_flash_fallback,resolved_link,usage_changed,quota_now);
                atomic_initial := TRUE;
            ELSE
            PERFORM internal.assert_initial_preparation_assignment(p_user_id,p_request_id,resolved_plan,resolved_flash_fallback,FALSE);
            END IF;$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 2';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$                    IF usage_row.user_id IS NULL THEN
                        INSERT INTO internal.complimentary_scan_usage ($old$; replacement TEXT := $new$                    IF atomic_initial AND usage_row.user_id IS NOT NULL THEN
                        RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
                    END IF;
                    IF usage_row.user_id IS NULL THEN
                        IF atomic_initial THEN
                            PERFORM internal.register_initial_admission_write(p_request_id,'C8.hold.insert',
                                'internal.complimentary_scan_usage','INSERT',NULL,to_jsonb(jsonb_populate_record(
                                    NULL::internal.complimentary_scan_usage,jsonb_build_object('user_id',p_user_id,
                                        'client_scan_id',p_original_analysis_id,'state','held','held_at',quota_now,
                                        'created_at',quota_now,'updated_at',quota_now,'reacquisition_count',0))));
                        END IF;
                        INSERT INTO internal.complimentary_scan_usage ($new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 3';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$    IF usage_changed THEN
        UPDATE public.users AS users$old$; replacement TEXT := $new$    IF usage_changed THEN
        IF atomic_initial THEN
            SELECT jsonb_build_object('id',u.id,'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch,
                'entitlement_version',u.entitlement_version) INTO STRICT atomic_user FROM public.users u WHERE u.id=p_user_id;
            PERFORM internal.register_initial_admission_write(p_request_id,'C8.epoch.update','public.users','UPDATE',atomic_user,
                atomic_user || jsonb_build_object('complimentary_entitlement_epoch',(atomic_user->>'complimentary_entitlement_epoch')::BIGINT+1,
                    'entitlement_version',(atomic_user->>'entitlement_version')::BIGINT+1));
        END IF;
        UPDATE public.users AS users$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 4';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$    UPDATE internal.ai_quota_reservations AS reservations
    SET effective_plan = resolved_plan,$old$; replacement TEXT := $new$    IF atomic_initial THEN
        SELECT * INTO STRICT atomic_old FROM internal.ai_quota_reservations WHERE id=quota_result.reservation_id;
        PERFORM internal.register_initial_admission_write(p_request_id,'C8.attachment.update',
            'internal.ai_quota_reservations','UPDATE',to_jsonb(atomic_old),to_jsonb(atomic_old) || jsonb_build_object(
                'effective_plan',resolved_plan,'effective_tier',CASE WHEN resolved_plan IN ('pro_paid','pro_trial','pro_complimentary') THEN 'pro' ELSE 'free' END,
                'subscription_tier',CASE WHEN resolved_plan='pro_paid' THEN 'pro' ELSE 'free' END,'trial_active',resolved_plan='pro_trial',
                'original_analysis_id',COALESCE(atomic_old.original_analysis_id,p_original_analysis_id),
                'complimentary_client_scan_id',COALESCE(atomic_old.complimentary_client_scan_id,resolved_link),
                'client_protocol',COALESCE(atomic_old.client_protocol,p_client_protocol),
                'flash_fallback_used',atomic_old.flash_fallback_used OR resolved_flash_fallback,
                'entitlement_version',entitlement_after.entitlement_version,'updated_at',quota_now));
    END IF;
    UPDATE internal.ai_quota_reservations AS reservations
    SET effective_plan = resolved_plan,$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 5';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$    reservation_found BOOLEAN;$old$; replacement TEXT := $new$    reservation_found BOOLEAN;
    atomic_initial BOOLEAN := FALSE;
    new_reservation_id UUID;
    new_lease_token UUID;$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 6';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$    SELECT selected.* INTO policy_row
    FROM internal.resolve_quota_policy(p_operation,resolved_plan) AS selected;$old$; replacement TEXT := $new$    atomic_initial := EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents
        WHERE scan_id=p_request_id AND canonical_assignment::JSONB->>'version'='3');
    IF atomic_initial THEN
        IF p_operation IS DISTINCT FROM 'scan_identification' THEN
            RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
        END IF;
        policy_row := internal.initial_admission_frozen_policy(p_user_id,p_request_id,resolved_plan);
    ELSE
    SELECT selected.* INTO policy_row
    FROM internal.resolve_quota_policy(p_operation,resolved_plan) AS selected;
    END IF;$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 7';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$        PERFORM internal.assert_initial_preparation_assignment(p_user_id,p_request_id,resolved_plan,
            (SELECT (canonical_assignment::JSONB->>'flash_fallback_used')::BOOLEAN FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_request_id),TRUE);$old$; replacement TEXT := $new$        IF atomic_initial THEN
            IF reservation_found THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
            UPDATE internal.initial_preparation_admission_staging SET core4_at=quota_now WHERE scan_id=p_request_id;
        ELSE
        PERFORM internal.assert_initial_preparation_assignment(p_user_id,p_request_id,resolved_plan,
            (SELECT (canonical_assignment::JSONB->>'flash_fallback_used')::BOOLEAN FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_request_id),TRUE);
        END IF;$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 8';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$    ELSE
        INSERT INTO internal.ai_quota_reservations (
            user_id,$old$; replacement TEXT := $new$    ELSE
        -- Preserve one fresh UUID/default sample, now available before INSERT.
        new_reservation_id := pg_catalog.gen_random_uuid();
        new_lease_token := pg_catalog.gen_random_uuid();
        IF atomic_initial THEN
            UPDATE internal.initial_preparation_admission_staging
                SET reservation_id=new_reservation_id,lease_token=new_lease_token WHERE scan_id=p_request_id;
            PERFORM internal.register_initial_admission_write(p_request_id,'C4.reservation.insert',
                'internal.ai_quota_reservations','INSERT',NULL,to_jsonb(jsonb_populate_record(NULL::internal.ai_quota_reservations,
                    jsonb_build_object('id',new_reservation_id,'user_id',p_user_id,'operation',p_operation,'request_id',p_request_id,
                        'state','reserved','lease_token',new_lease_token,'lease_expires_at',quota_now+INTERVAL '10 minutes',
                        'attempt_count',1,'refund_count',0,'stale_recovery_count',0,'model',policy_row.model,
                        'effective_plan',resolved_plan,'effective_tier',resolved_effective_tier,
                        'subscription_tier',CASE WHEN resolved_plan='pro_paid' THEN 'pro' ELSE 'free' END,
                        'trial_active',resolved_trial_active,'entitlement_version',app_user.entitlement_version,
                        'policy_version',policy_row.policy_version,'daily_limit',policy_row.daily_limit,
                        'reserved_at',quota_now,'created_at',quota_now,'updated_at',quota_now,'flash_fallback_used',FALSE))));
        END IF;
        INSERT INTO internal.ai_quota_reservations (
            id,
            user_id,$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 9';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$        VALUES (
            p_user_id,
            p_operation,
            p_request_id,
            pg_catalog.GEN_RANDOM_UUID(),$old$; replacement TEXT := $new$        VALUES (
            new_reservation_id,
            p_user_id,
            p_operation,
            p_request_id,
            new_lease_token,$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 10';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$        resulting_daily_count := internal.consume_ai_quota_counter(
            'user_daily',$old$; replacement TEXT := $new$        IF atomic_initial THEN
            PERFORM internal.register_initial_admission_write(p_request_id,'Counter.daily.upsert',
                'internal.ai_quota_counters','UPSERT',NULL,jsonb_build_object('scope_type','user_daily','scope_key',p_user_id::TEXT,
                    'bucket',policy_row.daily_bucket,'window_start',daily_window_start,
                    'window_seconds',86400,'limit',policy_row.daily_limit,'updated_at',pg_catalog.now()));
        END IF;
        resulting_daily_count := internal.consume_ai_quota_counter(
            'user_daily',$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 11';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$        INSERT INTO internal.ai_quota_reservation_counters (
            reservation_id,
            scope_type,
            scope_key,
            bucket,
            window_start
        )
        VALUES (
            reservation_row.id,
            'user_daily',$old$; replacement TEXT := $new$        IF atomic_initial THEN
            PERFORM internal.register_initial_admission_write(p_request_id,'C4.daily.link',
                'internal.ai_quota_reservation_counters','INSERT',NULL,jsonb_build_object(
                    'reservation_id',reservation_row.id,'scope_type','user_daily','scope_key',p_user_id::TEXT,
                    'bucket',policy_row.daily_bucket,'window_start',daily_window_start));
        END IF;
        INSERT INTO internal.ai_quota_reservation_counters (
            reservation_id,
            scope_type,
            scope_key,
            bucket,
            window_start
        )
        VALUES (
            reservation_row.id,
            'user_daily',$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 12';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$    PERFORM internal.consume_ai_quota_counter(
        'user_rate',$old$; replacement TEXT := $new$    IF atomic_initial THEN
        PERFORM internal.register_initial_admission_write(p_request_id,'Counter.user.upsert',
            'internal.ai_quota_counters','UPSERT',NULL,jsonb_build_object('scope_type','user_rate','scope_key',p_user_id::TEXT,
                'bucket',policy_row.user_rate_bucket,'window_start',user_window_start,
                'window_seconds',policy_row.user_window_seconds,'limit',policy_row.user_window_limit,'updated_at',pg_catalog.now()));
    END IF;
    PERFORM internal.consume_ai_quota_counter(
        'user_rate',$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 13';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$    INSERT INTO internal.ai_quota_reservation_counters (
        reservation_id,
        scope_type,
        scope_key,
        bucket,
        window_start
    )
    VALUES (
        reservation_row.id,
        'user_rate',$old$; replacement TEXT := $new$    IF atomic_initial THEN
        PERFORM internal.register_initial_admission_write(p_request_id,'C4.user.link',
            'internal.ai_quota_reservation_counters','INSERT',NULL,jsonb_build_object(
                'reservation_id',reservation_row.id,'scope_type','user_rate','scope_key',p_user_id::TEXT,
                'bucket',policy_row.user_rate_bucket,'window_start',user_window_start));
    END IF;
    INSERT INTO internal.ai_quota_reservation_counters (
        reservation_id,
        scope_type,
        scope_key,
        bucket,
        window_start
    )
    VALUES (
        reservation_row.id,
        'user_rate',$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 14';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$    PERFORM internal.consume_ai_quota_counter(
        'ip_rate',$old$; replacement TEXT := $new$    IF atomic_initial THEN
        PERFORM internal.register_initial_admission_write(p_request_id,'Counter.ip.upsert',
            'internal.ai_quota_counters','UPSERT',NULL,jsonb_build_object('scope_type','ip_rate','scope_key',p_ip_hash,
                'bucket',policy_row.ip_rate_bucket,'window_start',ip_window_start,
                'window_seconds',policy_row.ip_window_seconds,'limit',policy_row.ip_window_limit,'updated_at',pg_catalog.now()));
    END IF;
    PERFORM internal.consume_ai_quota_counter(
        'ip_rate',$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 15';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$    INSERT INTO internal.ai_quota_reservation_counters (
        reservation_id,
        scope_type,
        scope_key,
        bucket,
        window_start
    )
    VALUES (
        reservation_row.id,
        'ip_rate',$old$; replacement TEXT := $new$    IF atomic_initial THEN
        PERFORM internal.register_initial_admission_write(p_request_id,'C4.ip.link',
            'internal.ai_quota_reservation_counters','INSERT',NULL,jsonb_build_object(
                'reservation_id',reservation_row.id,'scope_type','ip_rate','scope_key',p_ip_hash,
                'bucket',policy_row.ip_rate_bucket,'window_start',ip_window_start));
    END IF;
    INSERT INTO internal.ai_quota_reservation_counters (
        reservation_id,
        scope_type,
        scope_key,
        bucket,
        window_start
    )
    VALUES (
        reservation_row.id,
        'ip_rate',$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 16';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $owner_patch$
DECLARE definition TEXT; anchor TEXT := $old$    UPDATE internal.ai_quota_reservations AS reservations
    SET
        daily_remaining_after_reservation =$old$; replacement TEXT := $new$    IF atomic_initial THEN
        PERFORM internal.register_initial_admission_write(p_request_id,'C4.remaining.update',
            'internal.ai_quota_reservations','UPDATE',to_jsonb(reservation_row),to_jsonb(reservation_row) || jsonb_build_object(
                'daily_remaining_after_reservation',CASE WHEN policy_row.daily_limit IS NULL THEN NULL
                    ELSE GREATEST(policy_row.daily_limit-resulting_daily_count,0) END,'updated_at',quota_now));
    END IF;
    UPDATE internal.ai_quota_reservations AS reservations
    SET
        daily_remaining_after_reservation =$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic owner source drift 17';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$owner_patch$;

DO $provider_patch$
DECLARE definition TEXT; anchor TEXT := $old$    attempt internal.identification_provider_attempts%ROWTYPE; accepted_capability INTEGER; accepted_protocol INTEGER;$old$; replacement TEXT := $new$    attempt internal.identification_provider_attempts%ROWTYPE; accepted_capability INTEGER; accepted_protocol INTEGER;
    atomic_initial BOOLEAN := FALSE;
    atomic_stage internal.initial_preparation_admission_staging;
    atomic_assignment JSONB;
    attempt_created_at TIMESTAMPTZ;$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic provider source drift 1';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$provider_patch$;

DO $provider_patch$
DECLARE definition TEXT; anchor TEXT := $old$    -- The established user/reservation locks, entitlement, counters and
    -- idempotency remain authoritative.$old$; replacement TEXT := $new$    atomic_initial := EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents
        WHERE scan_id=p_request_id AND canonical_assignment::JSONB->>'version'='3');
    IF atomic_initial THEN
        SELECT * INTO atomic_stage FROM internal.initial_preparation_admission_staging WHERE scan_id=p_request_id;
        IF NOT FOUND OR atomic_stage.owner_id IS DISTINCT FROM p_user_id
            OR atomic_stage.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
            OR atomic_stage.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE)
            OR atomic_stage.phase IS DISTINCT FROM 'validated'
            OR p_original_analysis_id IS DISTINCT FROM p_request_id OR p_internal_replay IS DISTINCT FROM FALSE
            OR p_client_protocol IS DISTINCT FROM (atomic_stage.assignment::JSONB->>'accepted_client_protocol')::INTEGER
            OR p_input_profile IS DISTINCT FROM atomic_stage.assignment::JSONB->>'input_profile'
            OR p_expected_processor_permission IS DISTINCT FROM atomic_stage.assignment::JSONB->>'processor_permission'
            OR p_identification_protocol IS DISTINCT FROM (atomic_stage.assignment::JSONB->>'accepted_identification_protocol')::INTEGER THEN
            RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
        END IF;
        atomic_assignment := atomic_stage.assignment::JSONB;
    END IF;

    -- The established user/reservation locks, entitlement, counters and
    -- idempotency remain authoritative.$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic provider source drift 2';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$provider_patch$;

DO $provider_patch$
DECLARE definition TEXT; anchor TEXT := $old$    IF NOT FOUND AND NOT admitted.is_replay THEN
        SELECT selected.* INTO assignment
        FROM internal.resolve_identification_provider_binding(
            p_operation,admitted.effective_plan,admitted.model,admitted.policy_version,p_input_profile
        ) AS selected;
        accepted_protocol := internal.require_identification_client_protocol(p_user_id, p_operation, p_original_analysis_id, p_input_profile, p_client_protocol, p_internal_replay, assignment.minimum_client_protocol);$old$; replacement TEXT := $new$    IF atomic_initial AND (FOUND OR admitted.is_replay) THEN
        RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
    END IF;
    IF attempt.reservation_id IS NULL AND NOT admitted.is_replay THEN
        IF atomic_initial THEN
            -- Core8 already locked and compared this exact saved binding before
            -- funding; do not invoke a provider selector after the charge.
            assignment := jsonb_populate_record(NULL::internal.identification_provider_bindings,
                jsonb_build_object('operation',p_operation,'effective_plan',atomic_assignment->'effective_plan',
                    'model',atomic_assignment->'quota_model','policy_version',atomic_assignment->'policy_version',
                    'provider',atomic_assignment->'provider','binding',atomic_assignment->'binding',
                    'processor_permission',atomic_assignment->'processor_permission','provider_model',atomic_assignment->'provider_model',
                    'minimum_identification_protocol',atomic_assignment->'minimum_identification_protocol',
                    'minimum_client_protocol',atomic_assignment->'minimum_client_protocol','input_profile',atomic_assignment->'input_profile'));
            accepted_protocol := (atomic_assignment->>'accepted_client_protocol')::INTEGER;
        ELSE
            SELECT selected.* INTO assignment
            FROM internal.resolve_identification_provider_binding(
                p_operation,admitted.effective_plan,admitted.model,admitted.policy_version,p_input_profile
            ) AS selected;
            accepted_protocol := internal.require_identification_client_protocol(p_user_id, p_operation, p_original_analysis_id, p_input_profile, p_client_protocol, p_internal_replay, assignment.minimum_client_protocol);
        END IF;$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic provider source drift 3';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$provider_patch$;

DO $provider_patch$
DECLARE definition TEXT; anchor TEXT := $old$        accepted_capability := internal.require_identification_capability(p_user_id, p_operation, p_original_analysis_id, p_input_profile, p_identification_protocol, p_internal_replay, assignment.minimum_identification_protocol);$old$; replacement TEXT := $new$        IF atomic_initial THEN
            accepted_capability := (atomic_assignment->>'accepted_identification_protocol')::INTEGER;
        ELSE
        accepted_capability := internal.require_identification_capability(p_user_id, p_operation, p_original_analysis_id, p_input_profile, p_identification_protocol, p_internal_replay, assignment.minimum_identification_protocol);
        END IF;$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic provider source drift 4';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$provider_patch$;

DO $provider_patch$
DECLARE definition TEXT; anchor TEXT := $old$        INSERT INTO internal.identification_provider_attempts AS saved ($old$; replacement TEXT := $new$        attempt_created_at := pg_catalog.now();
        IF atomic_initial THEN
            PERFORM internal.register_initial_admission_write(p_request_id,'Provider.attempt.insert',
                'internal.identification_provider_attempts','INSERT',NULL,to_jsonb(jsonb_populate_record(NULL::internal.identification_provider_attempts,
                    jsonb_build_object('reservation_id',admitted.reservation_id,'attempt_count',admitted.attempt_count,
                        'operation',p_operation,'effective_plan',admitted.effective_plan,'model',admitted.model,'policy_version',admitted.policy_version,
                        'provider',assignment.provider,'binding',assignment.binding,'processor_permission',assignment.processor_permission,
                        'provider_model',assignment.provider_model,'minimum_identification_protocol',assignment.minimum_identification_protocol,
                        'accepted_identification_protocol',accepted_capability,'minimum_client_protocol',assignment.minimum_client_protocol,
                        'accepted_client_protocol',accepted_protocol,'input_profile',p_input_profile,'created_at',attempt_created_at))));
        END IF;
        INSERT INTO internal.identification_provider_attempts AS saved ($new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic provider source drift 5';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$provider_patch$;

DO $provider_patch$
DECLARE definition TEXT; anchor TEXT := $old$accepted_client_protocol, input_profile
        ) VALUES ($old$; replacement TEXT := $new$accepted_client_protocol, input_profile, created_at
        ) VALUES ($new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic provider source drift 6';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$provider_patch$;

DO $provider_patch$
DECLARE definition TEXT; anchor TEXT := $old$assignment.minimum_client_protocol, accepted_protocol, p_input_profile
        ) ON CONFLICT$old$; replacement TEXT := $new$assignment.minimum_client_protocol, accepted_protocol, p_input_profile, attempt_created_at
        ) ON CONFLICT$new$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial atomic provider source drift 7';
    END IF;
    EXECUTE replace(definition,anchor,replacement);
END;
$provider_patch$;

-- Encode PostgreSQL's unchanged microsecond timestamp without an epoch or
-- millisecond round trip. This is private historical proof, never a lease grant.
CREATE FUNCTION internal.initial_admission_timestamp(p_value TIMESTAMPTZ)
RETURNS TEXT LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE encoded TEXT;
BEGIN
    IF p_value IS NULL OR NOT pg_catalog.isfinite(p_value) THEN
        RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
    END IF;
    encoded := pg_catalog.to_char(p_value AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
    IF NOT internal.valid_initial_admitted_timestamp(encoded) OR encoded::TIMESTAMPTZ IS DISTINCT FROM p_value THEN
        RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
    END IF;
    RETURN encoded;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_admission_timestamp(TIMESTAMPTZ) FROM PUBLIC,anon,authenticated,service_role;

-- Snapshot only actual original writes after the existing owners finish.
-- The finalizer must still validate/store all twelve components atomically.
CREATE FUNCTION internal.build_initial_admission_accounting(p_scan UUID)
RETURNS TEXT LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_preparation_admission_staging;
    reservation internal.ai_quota_reservations; attempt internal.identification_provider_attempts;
    hold internal.complimentary_scan_usage; expected internal.initial_preparation_admission_writes;
    counter internal.ai_quota_counters; link internal.ai_quota_reservation_counters;
    required_keys TEXT[]:=ARRAY['C4.reservation.insert','C4.remaining.update','C8.attachment.update','Provider.attempt.insert',
        'Counter.user.upsert','C4.user.link','Counter.ip.upsert','C4.ip.link'];
    links JSONB:='[]'::JSONB; complimentary JSONB:='null'::JSONB; encoded TEXT; kind TEXT; link_count INTEGER:=0;
BEGIN
    SELECT * INTO stage FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan;
    IF NOT FOUND OR stage.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
        OR stage.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE)
        OR stage.phase IS DISTINCT FROM 'compared' OR stage.reservation_id IS NULL OR stage.lease_token IS NULL
        OR to_jsonb(stage.policy) IS NULL OR stage.core4_at IS NULL THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_admission_policy(stage.policy);
    IF (stage.policy).daily_limit IS NOT NULL THEN required_keys:=required_keys||ARRAY['Counter.daily.upsert','C4.daily.link']; END IF;
    IF stage.acquire_hold THEN required_keys:=required_keys||ARRAY['C8.hold.insert','C8.epoch.update']; END IF;
    IF (SELECT array_agg(statement_key ORDER BY statement_key COLLATE "C") FROM internal.initial_preparation_admission_writes WHERE scan_id=p_scan)
        IS DISTINCT FROM (SELECT array_agg(k ORDER BY k COLLATE "C") FROM unnest(required_keys) k)
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id=p_scan AND NOT consumed) THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    SELECT * INTO reservation FROM internal.ai_quota_reservations WHERE id=stage.reservation_id FOR UPDATE;
    IF NOT FOUND OR reservation.user_id IS DISTINCT FROM stage.owner_id
        OR reservation.request_id IS DISTINCT FROM p_scan OR reservation.original_analysis_id IS DISTINCT FROM p_scan
        OR reservation.operation IS DISTINCT FROM 'scan_identification' OR reservation.attempt_count IS DISTINCT FROM 1
        OR reservation.state IS DISTINCT FROM 'reserved' OR reservation.lease_token IS DISTINCT FROM stage.lease_token
        OR reservation.operation IS DISTINCT FROM (stage.policy).operation
        OR reservation.effective_plan IS DISTINCT FROM (stage.policy).effective_plan
        OR reservation.model IS DISTINCT FROM (stage.policy).model
        OR reservation.policy_version IS DISTINCT FROM (stage.policy).policy_version
        OR reservation.daily_limit IS DISTINCT FROM (stage.policy).daily_limit
        OR reservation.reserved_at IS DISTINCT FROM stage.core4_at
        OR reservation.lease_expires_at IS DISTINCT FROM stage.core4_at+INTERVAL '10 minutes'
        OR to_jsonb(reservation) IS DISTINCT FROM (SELECT new_image FROM internal.initial_preparation_admission_writes
            WHERE scan_id=p_scan AND statement_key='C8.attachment.update') THEN
        RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
    END IF;
    SELECT * INTO attempt FROM internal.identification_provider_attempts
        WHERE reservation_id=reservation.id AND attempt_count=1 FOR UPDATE;
    IF NOT FOUND OR to_jsonb(attempt) IS DISTINCT FROM (SELECT new_image FROM internal.initial_preparation_admission_writes
        WHERE scan_id=p_scan AND statement_key='Provider.attempt.insert')
        OR (SELECT count(*) FROM internal.identification_provider_attempts WHERE reservation_id=reservation.id)<>1 THEN
        RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
    END IF;
    FOREACH kind IN ARRAY ARRAY['daily','user','ip'] LOOP
        SELECT * INTO expected FROM internal.initial_preparation_admission_writes
            WHERE scan_id=p_scan AND statement_key='C4.'||kind||'.link';
        IF NOT FOUND THEN
            IF kind='daily' AND (stage.policy).daily_limit IS NULL THEN CONTINUE; END IF;
            RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
        END IF;
        SELECT * INTO link FROM internal.ai_quota_reservation_counters l WHERE l.reservation_id=reservation.id
            AND l.scope_type=expected.new_image->>'scope_type'
            AND l.scope_key=expected.new_image->>'scope_key' AND l.bucket=expected.new_image->>'bucket'
            AND l.window_start=(expected.new_image->>'window_start')::TIMESTAMPTZ FOR UPDATE;
        IF NOT FOUND OR to_jsonb(link) IS DISTINCT FROM expected.new_image THEN
            RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
        END IF;
        SELECT * INTO expected FROM internal.initial_preparation_admission_writes
            WHERE scan_id=p_scan AND statement_key='Counter.'||kind||'.upsert';
        SELECT * INTO counter FROM internal.ai_quota_counters c WHERE c.scope_type=link.scope_type
            AND c.scope_key=link.scope_key AND c.bucket=link.bucket AND c.window_start=link.window_start FOR UPDATE;
        IF NOT FOUND OR to_jsonb(counter)-ARRAY['request_count','updated_at'] IS DISTINCT FROM expected.new_image-ARRAY['limit','updated_at'] THEN
            RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
        END IF;
        links:=links||jsonb_build_array(to_jsonb(link)||jsonb_build_object('window_start',internal.initial_admission_timestamp(link.window_start),
            'window_seconds',counter.window_seconds,'delta',1));
        link_count:=link_count+1;
    END LOOP;
    IF (SELECT count(*) FROM internal.ai_quota_reservation_counters WHERE reservation_id=reservation.id)<>link_count THEN
        RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
    END IF;
    SELECT * INTO hold FROM internal.complimentary_scan_usage WHERE user_id=stage.owner_id AND client_scan_id=p_scan FOR UPDATE;
    IF stage.acquire_hold THEN
        IF NOT FOUND OR to_jsonb(hold) IS DISTINCT FROM (SELECT new_image FROM internal.initial_preparation_admission_writes
            WHERE scan_id=p_scan AND statement_key='C8.hold.insert') THEN
            RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
        END IF;
        IF (SELECT jsonb_build_object('id',u.id,'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch,
                'entitlement_version',u.entitlement_version) FROM public.users u WHERE u.id=stage.owner_id)
            IS DISTINCT FROM (SELECT new_image FROM internal.initial_preparation_admission_writes
                WHERE scan_id=p_scan AND statement_key='C8.epoch.update') THEN
            RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
        END IF;
        complimentary:=jsonb_build_object('owner_id',stage.owner_id,'client_scan_id',p_scan,
            'classification','pro_complimentary','state_at_admission','held');
    ELSIF FOUND THEN
        RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
    END IF;
    encoded:=internal.initial_canonical(jsonb_build_object('version',1,
        'reservation',jsonb_build_object('reservation_id',reservation.id,'owner_id',reservation.user_id,'scan_id',p_scan,
            'attempt_count',reservation.attempt_count,'lease_token',reservation.lease_token,
            'lease_expires_at',internal.initial_admission_timestamp(reservation.lease_expires_at)),
        'attempt',to_jsonb(attempt)-'created_at','charges',jsonb_build_object('policy',jsonb_build_object(
            'operation',reservation.operation,'effective_plan',reservation.effective_plan,'policy_version',reservation.policy_version),
            'links',links),'complimentary',complimentary));
    PERFORM internal.parse_initial_admitted_component('accounting',encoded);
    RETURN encoded;
END; $$;
REVOKE ALL ON FUNCTION internal.build_initial_admission_accounting(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Compose all original receipt bytes from the private stage and the existing
-- owners' actual locked rows. This returns a prospective value only: it does
-- not insert a receipt, advance a stage, allocate media or authorize execution.
CREATE FUNCTION internal.build_initial_admission_receipt(p_scan UUID)
RETURNS internal.initial_preparation_admission_receipts
LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_preparation_admission_staging;
    result internal.initial_preparation_admission_receipts;
    reservation internal.ai_quota_reservations;
    a JSONB; metadata JSONB:='{}'::JSONB; proof JSONB:='{}'::JSONB; reference_value JSONB;
    kind TEXT; domain_name TEXT; component TEXT; authorized_at NUMERIC;
BEGIN
    -- This first validates the current xid/token/phase, the frozen policy and
    -- the entire consumed original funding-write set, then locks actual rows.
    result.accounting:=internal.build_initial_admission_accounting(p_scan);
    SELECT * INTO STRICT stage FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan;
    SELECT * INTO STRICT reservation FROM internal.ai_quota_reservations WHERE id=stage.reservation_id;
    a:=stage.assignment::JSONB;
    result.scan_id:=stage.scan_id; result.owner_id:=stage.owner_id;
    result.admission_receipt_id:=stage.admission_receipt_id;
    result.candidate:=stage.candidate; result.input:=stage.input;
    result.outcome:=stage.outcome; result.installation:=stage.installation;
    result.protocol:=stage.protocol; result.destination:=stage.destination;
    result.mapping:=stage.mapping; result.media_binding:=stage.media_binding;
    result.configuration:=internal.initial_canonical(jsonb_build_object('version',2,'assignment',a));
    result.funding:=internal.initial_canonical(jsonb_build_object('version',1,'original',jsonb_build_object(
        'reservation_id',reservation.id,'request_id',reservation.request_id,
        'original_analysis_id',reservation.original_analysis_id,'operation',reservation.operation,
        'attempt_count',reservation.attempt_count,'effective_plan',reservation.effective_plan,
        'effective_tier',reservation.effective_tier,'entitlement_version',reservation.entitlement_version,
        'policy_version',reservation.policy_version,'model',a->'effective_model',
        'complimentary_client_scan_id',reservation.complimentary_client_scan_id,
        'flash_fallback_used',reservation.flash_fallback_used)));
    -- Domains are fixed by component name. A caller supplies neither bytes nor
    -- a selectable hashing/codec scheme; the accepted validator rechecks all.
    FOREACH kind IN ARRAY ARRAY['candidate','input','configuration','funding','outcome',
        'installation','protocol','destination','mapping','media_binding','accounting'] LOOP
        component:=to_jsonb(result)->>kind;
        domain_name:=CASE kind
            WHEN 'candidate' THEN 'preparation-candidate.v2' WHEN 'input' THEN 'input.v1'
            WHEN 'configuration' THEN 'configuration.v1' WHEN 'funding' THEN 'funding.v1'
            WHEN 'outcome' THEN 'preparation-execution.outcome.v2' WHEN 'installation' THEN 'handoff.installation.v1'
            WHEN 'protocol' THEN 'handoff.protocol_artifact.v1' WHEN 'destination' THEN 'handoff.destination_backend.v1'
            WHEN 'mapping' THEN 'handoff.mapping.v2' WHEN 'media_binding' THEN 'handoff.media_binding.v2'
            WHEN 'accounting' THEN 'handoff.accounting.v1' END;
        reference_value:=jsonb_build_object('byte_count',octet_length(component),'digest',
            encode(extensions.digest(convert_to('merian.initial-analysis.'||domain_name||chr(10)||component,'UTF8'),'sha256'),'hex'));
        IF kind IN ('mapping','media_binding') THEN
            metadata:=metadata||jsonb_build_object(kind,reference_value);
        ELSE
            proof:=proof||jsonb_build_object(kind,reference_value);
        END IF;
    END LOOP;
    authorized_at:=floor(extract(epoch FROM clock_timestamp())*1000);
    IF authorized_at<(stage.phase_window::JSONB->>'anchor_ms')::NUMERIC
        OR authorized_at>=(stage.phase_window::JSONB#>>'{cutoffs,admission}')::NUMERIC THEN
        RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000';
    END IF;
    result.manifest:=internal.initial_canonical(jsonb_build_object('version',1,'owner_id',stage.owner_id,
        'scan_id',stage.scan_id,'admission_receipt_id',stage.admission_receipt_id,'route',a->'route',
        'input_schema_version',1,'binding_version',3,'funding_binding_id',reservation.id,
        'authorized_at_ms',authorized_at,'metadata',metadata,'proof',proof,
        'metadata_digest',encode(extensions.digest(convert_to('merian.initial-analysis.handoff.admitted-metadata.v1'||chr(10)||internal.initial_canonical(metadata),'UTF8'),'sha256'),'hex'),
        'proof_digest',encode(extensions.digest(convert_to('merian.initial-analysis.handoff.admitted-proof.v1'||chr(10)||internal.initial_canonical(proof),'UTF8'),'sha256'),'hex'),
        'assignment_digest',internal.initial_preparation_digest('assignment',stage.assignment),
        'phase_window_digest',internal.initial_admission_metadata_digest('phase_window',stage.phase_window),
        'descriptions_digest',internal.initial_digest('descriptions',internal.initial_canonical(stage.input::JSONB->'ordered_descriptions')),
        'assets_digest',a->'asset_manifest_digest'));
    result.receipt_digest:=internal.validate_initial_admitted_proof(result.candidate,result.input,
        result.configuration,result.funding,result.outcome,result.installation,result.protocol,
        result.destination,result.mapping,result.media_binding,result.accounting,result.manifest);
    RETURN result;
END; $$;
REVOKE ALL ON FUNCTION internal.build_initial_admission_receipt(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Reserved two-integer advisory namespace 1229018189 (IADM). Presence is
-- transaction-wide denial only: a forged/session lock may over-deny, never
-- establish provenance. Bigint locks use objsubid=1 and cannot masquerade here.
CREATE FUNCTION internal.initial_admission_sealed()
RETURNS BOOLEAN LANGUAGE SQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
    SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_locks l
        WHERE l.locktype='advisory' AND l.database=(SELECT oid FROM pg_catalog.pg_database WHERE datname=pg_catalog.current_database())
            AND l.pid=pg_catalog.pg_backend_pid() AND l.granted AND l.mode='ExclusiveLock'
            AND l.classid=1229018189::OID AND l.objsubid=2);
$$;
REVOKE ALL ON FUNCTION internal.initial_admission_sealed() FROM PUBLIC,anon,authenticated,service_role;

-- Fixed read-only definer trigger preserves existing direct-table callers:
-- they do not need EXECUTE on the private lock predicate. No table mutation or
-- caller-supplied relation/function resolution occurs under definer privileges.
CREATE FUNCTION internal.guard_initial_admission_seal()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF internal.initial_admission_sealed() THEN
        RAISE EXCEPTION 'initial_analysis_admission_sealed' USING ERRCODE='55000';
    END IF;
    RETURN NULL;
END; $$;
REVOKE ALL ON FUNCTION internal.guard_initial_admission_seal() FROM PUBLIC,anon,authenticated,service_role;

-- Permanent private-row invariants, ordered consumption and full OLD provenance.
CREATE FUNCTION internal.guard_initial_admission_stage()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $$
DECLARE mutable_columns TEXT[]; sealing_entry BOOLEAN:=FALSE;
BEGIN
    IF TG_OP='TRUNCATE' THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    ELSIF TG_OP='DELETE' THEN
        -- Entry into consuming unavoidably acquired the actual xact seal.
        -- Deletion authority instead comes from the original complete OLD proof.
        IF OLD.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
            OR OLD.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE) THEN
            RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
        END IF;
        IF OLD.phase IS DISTINCT FROM 'consuming' OR OLD.completion_ledger IS NULL
            OR OLD.cleanup_cursor IS DISTINCT FROM jsonb_array_length(OLD.completion_ledger)::BIGINT THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_admission_remaining(OLD);
        PERFORM internal.assert_initial_admission_live_snapshot(OLD);
        RETURN OLD;
    END IF;
    -- Seal possession grants nothing. Only the already-proven consuming
    -- cursor branch below can proceed; parent DELETE proves full original OLD.
    IF internal.initial_admission_sealed() AND (TG_OP<>'UPDATE'
        OR OLD.phase IS DISTINCT FROM 'consuming' OR NEW.phase IS DISTINCT FROM 'consuming') THEN
        RAISE EXCEPTION 'initial_analysis_admission_sealed' USING ERRCODE='55000';
    END IF;
    IF NEW.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id() THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    IF TG_OP='INSERT' THEN
        IF NEW.phase IS DISTINCT FROM 'validated' OR to_jsonb(NEW.policy) IS NOT NULL
            OR NEW.resolved_link IS NOT NULL OR NEW.acquire_hold IS NOT NULL
            OR NEW.core8_at IS NOT NULL OR NEW.core4_at IS NOT NULL
            OR NEW.reservation_id IS NOT NULL OR NEW.lease_token IS NOT NULL OR NEW.prospective_receipt IS NOT NULL
            OR NEW.completion_event_seq IS DISTINCT FROM 0 OR NEW.cleanup_cursor IS DISTINCT FROM 0 OR NEW.completion_ledger IS NOT NULL THEN
            RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
        END IF;
        RETURN NEW;
    END IF;
    IF OLD.transaction_id IS DISTINCT FROM NEW.transaction_id
        OR OLD.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE) THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    IF OLD.phase=NEW.phase AND OLD.phase IN ('compared','reserved','admitted')
        AND OLD.completion_event_seq<9223372036854775807
        AND NEW.completion_event_seq=OLD.completion_event_seq+1 THEN
        mutable_columns:=ARRAY['completion_event_seq'];
        IF pg_catalog.pg_trigger_depth()<2 OR NEW.completion_event_seq IS DISTINCT FROM
            (SELECT count(*) FROM internal.initial_preparation_admission_writes WHERE scan_id=OLD.scan_id AND consumed) THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
    ELSIF OLD.phase='allocated' AND NEW.phase='allocated' AND OLD.completion_ledger IS NULL
        AND NEW.completion_ledger IS NOT NULL THEN
        mutable_columns:=ARRAY['completion_ledger'];
        PERFORM internal.assert_initial_admission_ledger(NEW);
        IF NEW.completion_ledger IS DISTINCT FROM internal.initial_admission_ledger_snapshot(OLD.scan_id) THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
    ELSIF OLD.phase='allocated' AND NEW.phase='consuming' AND OLD.cleanup_cursor=0 AND NEW.cleanup_cursor=0 THEN
        mutable_columns:=ARRAY['phase'];
        sealing_entry:=TRUE;
        PERFORM internal.assert_initial_admission_live_snapshot(OLD);
        IF OLD.completion_ledger IS DISTINCT FROM internal.initial_admission_ledger_snapshot(OLD.scan_id) THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
    ELSIF OLD.phase='consuming' AND NEW.phase='consuming' AND OLD.cleanup_cursor<64
        AND NEW.cleanup_cursor=OLD.cleanup_cursor+1 THEN
        mutable_columns:=ARRAY['cleanup_cursor'];
        IF pg_catalog.pg_trigger_depth()<2 THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_admission_remaining(NEW);
    ELSIF OLD.phase='validated' AND NEW.phase='compared' THEN
        mutable_columns:=ARRAY['phase','policy','resolved_link','acquire_hold','core8_at'];
        PERFORM internal.assert_initial_admission_policy(NEW.policy);
        IF NEW.acquire_hold IS NULL OR NEW.core8_at IS NULL OR NOT pg_catalog.isfinite(NEW.core8_at) THEN
            RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
        END IF;
    ELSIF OLD.phase='compared' AND NEW.phase='compared'
        AND OLD.core4_at IS NULL AND NEW.core4_at IS NOT NULL
        AND OLD.reservation_id IS NULL AND OLD.lease_token IS NULL THEN
        mutable_columns:=ARRAY['core4_at'];
        IF NOT pg_catalog.isfinite(NEW.core4_at) THEN
            RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
        END IF;
    ELSIF OLD.phase='compared' AND NEW.phase='compared'
        AND OLD.core4_at IS NOT NULL AND OLD.reservation_id IS NULL AND OLD.lease_token IS NULL
        AND NEW.reservation_id IS NOT NULL AND NEW.lease_token IS NOT NULL THEN
        mutable_columns:=ARRAY['reservation_id','lease_token'];
    ELSIF OLD.phase='compared' AND NEW.phase='reserved' AND OLD.prospective_receipt IS NULL THEN
        mutable_columns:=ARRAY['phase','prospective_receipt'];
        PERFORM internal.assert_initial_admission_prospective(NEW);
    ELSIF OLD.phase='reserved' AND NEW.phase='admitted' THEN
        mutable_columns:=ARRAY['phase'];
        PERFORM internal.assert_initial_admission_materialized(OLD.scan_id,FALSE);
    ELSIF OLD.phase='admitted' AND NEW.phase='allocated' THEN
        mutable_columns:=ARRAY['phase'];
        PERFORM internal.assert_initial_admission_materialized(OLD.scan_id,TRUE);
    ELSE
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    IF to_jsonb(OLD)-mutable_columns IS DISTINCT FROM to_jsonb(NEW)-mutable_columns THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    -- Every reachable consuming parent acquires the actual xact lock before
    -- any child can disappear, including direct/nested private phase updates.
    -- Check immutable columns first; a failed update rolls back this acquisition.
    -- Presence in pg_locks is denial only and is never substituted for this call.
    IF sealing_entry AND NOT pg_catalog.pg_try_advisory_xact_lock(1229018189,pg_catalog.hashtext(OLD.scan_id::TEXT)) THEN
        RAISE EXCEPTION 'initial_analysis_admission_sealed' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION internal.guard_initial_admission_stage() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_initial_admission_stage BEFORE INSERT OR UPDATE OR DELETE
    ON internal.initial_preparation_admission_staging FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_admission_stage();
CREATE TRIGGER guard_initial_admission_stage_truncate BEFORE TRUNCATE
    ON internal.initial_preparation_admission_staging FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_admission_stage();

CREATE FUNCTION internal.guard_initial_admission_expectation()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $$
DECLARE parent internal.initial_preparation_admission_staging;
BEGIN
    IF TG_OP='DELETE' THEN
        SELECT * INTO parent FROM internal.initial_preparation_admission_staging WHERE scan_id=OLD.scan_id;
        IF NOT FOUND OR pg_catalog.pg_trigger_depth()<>1 OR parent.phase IS DISTINCT FROM 'consuming'
            OR parent.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
            OR parent.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE)
            OR parent.completion_ledger IS NULL OR parent.cleanup_cursor>=jsonb_array_length(parent.completion_ledger)
            OR to_jsonb(OLD) IS DISTINCT FROM parent.completion_ledger->parent.cleanup_cursor::INTEGER THEN
            RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_admission_remaining(parent);
        RETURN OLD;
    ELSIF TG_OP='TRUNCATE' THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    IF internal.initial_admission_sealed() THEN
        RAISE EXCEPTION 'initial_analysis_admission_sealed' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_admission_write_registration(NEW.scan_id,NEW.statement_key,
        NEW.relation_name,NEW.operation,NEW.old_image,NEW.new_image);
    IF TG_OP='INSERT' THEN
        IF NEW.consumed IS DISTINCT FROM FALSE OR NEW.observed_operation IS NOT NULL
            OR NEW.observed_old_image IS NOT NULL OR NEW.observed_new_image IS NOT NULL THEN
            RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
        END IF;
    ELSIF pg_catalog.pg_trigger_depth()<2 OR OLD.consumed IS DISTINCT FROM FALSE OR NEW.consumed IS DISTINCT FROM TRUE
        OR to_jsonb(OLD)-ARRAY['consumed','observed_operation','observed_old_image','observed_new_image']
            IS DISTINCT FROM to_jsonb(NEW)-ARRAY['consumed','observed_operation','observed_old_image','observed_new_image']
        OR NOT internal.initial_admission_image_matches(OLD,NEW.observed_operation,NEW.observed_old_image,NEW.observed_new_image) THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION internal.guard_initial_admission_expectation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_initial_admission_expectation BEFORE INSERT OR UPDATE OR DELETE
    ON internal.initial_preparation_admission_writes FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_admission_expectation();
CREATE TRIGGER guard_initial_admission_expectation_truncate BEFORE TRUNCATE
    ON internal.initial_preparation_admission_writes FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_admission_expectation();

-- Every queued stage/member event checks complete live receipt state after
-- consumption, including early INSERT/UPDATE events. No phase is skipped.
-- Terminal DELETE additionally retains and verifies the original full OLD proof.
CREATE FUNCTION internal.require_complete_initial_admission()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $$
DECLARE captured internal.initial_preparation_admission_staging;
BEGIN
    captured:=CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
    IF captured.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=captured.scan_id)
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id=captured.scan_id) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_admission_live_receipt(captured.owner_id,captured.scan_id,captured.admission_receipt_id);
    IF TG_OP='DELETE' THEN
        IF captured.phase IS DISTINCT FROM 'consuming' OR captured.completion_ledger IS NULL
            OR captured.cleanup_cursor IS DISTINCT FROM jsonb_array_length(captured.completion_ledger)::BIGINT THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_admission_live_snapshot(captured);
    END IF;
    RETURN NULL;
END; $$;
REVOKE ALL ON FUNCTION internal.require_complete_initial_admission() FROM PUBLIC,anon,authenticated,service_role;
CREATE CONSTRAINT TRIGGER require_complete_initial_admission
    AFTER INSERT OR UPDATE OR DELETE ON internal.initial_preparation_admission_staging
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.require_complete_initial_admission();

-- Exact prospective images guard the existing owners, independently of the
-- still-closed source/provider barrier. No barrier exception is opened here.
CREATE FUNCTION internal.guard_initial_admission_member()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE active_scan UUID; linked BOOLEAN:=FALSE; old_value JSONB; new_value JSONB;
    relation_name TEXT:=TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME;
BEGIN
    IF TG_OP='TRUNCATE' THEN
        IF EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging) THEN
            RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
        END IF;
        RETURN NULL;
    END IF;
    IF TG_OP<>'INSERT' THEN old_value:=to_jsonb(OLD); END IF;
    IF TG_OP<>'DELETE' THEN new_value:=to_jsonb(NEW); END IF;
    SELECT scan_id INTO active_scan FROM internal.initial_preparation_admission_staging
        WHERE transaction_id=pg_catalog.pg_current_xact_id()
        AND stage_token::TEXT=current_setting('merian.initial_admission_stage',TRUE);
    IF active_scan IS NULL THEN
        -- Clearing a GUC cannot make an operation member become a legacy row.
        -- Check OLD and NEW aliases; the existing outer locks serialize peers.
        IF TG_TABLE_NAME='users' THEN
            SELECT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging
                WHERE owner_id::TEXT IN (old_value->>'id',new_value->>'id')) INTO linked;
        ELSIF TG_TABLE_NAME='ai_quota_reservations' THEN
            SELECT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging
                WHERE scan_id::TEXT IN (old_value->>'request_id',new_value->>'request_id',
                    old_value->>'original_analysis_id',new_value->>'original_analysis_id',
                    old_value->>'complimentary_client_scan_id',new_value->>'complimentary_client_scan_id')
                OR reservation_id::TEXT IN (old_value->>'id',new_value->>'id')) INTO linked;
        ELSIF TG_TABLE_NAME='complimentary_scan_usage' THEN
            SELECT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging
                WHERE scan_id::TEXT IN (old_value->>'client_scan_id',new_value->>'client_scan_id')) INTO linked;
        ELSIF TG_TABLE_NAME IN ('identification_provider_attempts','ai_quota_reservation_counters') THEN
            SELECT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging
                WHERE reservation_id::TEXT IN (old_value->>'reservation_id',new_value->>'reservation_id')) INTO linked;
        ELSIF TG_TABLE_NAME='ai_quota_counters' THEN
            SELECT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes w
                WHERE w.relation_name='internal.ai_quota_counters'
                AND (w.new_image-ARRAY['limit','updated_at'] = old_value-ARRAY['request_count','updated_at']
                    OR w.new_image-ARRAY['limit','updated_at'] = new_value-ARRAY['request_count','updated_at'])) INTO linked;
        ELSE
            SELECT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging
                WHERE scan_id::TEXT IN (old_value->>'scan_id',new_value->>'scan_id')) INTO linked;
        END IF;
        IF linked THEN RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
    ELSIF NOT internal.initial_admission_expected_write(active_scan,relation_name,TG_OP,old_value,new_value,TG_WHEN='AFTER') THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION internal.guard_initial_admission_member() FROM PUBLIC,anon,authenticated,service_role;
DO $member_guards$
DECLARE relation_name TEXT;
BEGIN
    FOREACH relation_name IN ARRAY ARRAY['internal.ai_quota_reservations','internal.complimentary_scan_usage',
        'internal.identification_provider_attempts','internal.ai_quota_counters','internal.ai_quota_reservation_counters',
        'public.users','internal.initial_analysis_submissions','internal.initial_analysis_admissions',
        'internal.initial_analysis_lifecycle_fences','internal.initial_preparation_admission_receipts',
        'internal.initial_analysis_media_allocation_fences','internal.initial_analysis_media_registry',
        'internal.initial_analysis_media_cohorts'] LOOP
        EXECUTE format('CREATE TRIGGER zz_initial_admission_member_before BEFORE INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_admission_member()',relation_name);
        EXECUTE format('CREATE TRIGGER zz_initial_admission_member_after AFTER INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_admission_member()',relation_name);
        EXECUTE format('CREATE TRIGGER zz_initial_admission_member_truncate BEFORE TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_admission_member()',relation_name);
    END LOOP;
END;
$member_guards$;

-- Admission v3 is a closed branch; historical v1/v2 rows retain their shapes.
ALTER TABLE internal.initial_analysis_admissions
    DROP CONSTRAINT initial_analysis_admissions_binding_version_check,
    DROP CONSTRAINT initial_admission_preparation_version,
    ADD COLUMN preparation_outcome_digest TEXT,
    ADD COLUMN preparation_receipt_digest TEXT,
    ADD CONSTRAINT initial_analysis_admissions_binding_version_check CHECK(binding_version IN (1,2,3)),
    ADD CONSTRAINT initial_admission_preparation_version CHECK(
        (binding_version=1 AND preparation_candidate_digest IS NULL AND preparation_assignment_digest IS NULL
            AND preparation_outcome_digest IS NULL AND preparation_receipt_digest IS NULL)
        OR (binding_version=2 AND preparation_candidate_digest IS NOT NULL AND preparation_candidate_digest ~ '^[0-9a-f]{64}$'
            AND preparation_assignment_digest IS NOT NULL AND preparation_assignment_digest ~ '^[0-9a-f]{64}$'
            AND preparation_outcome_digest IS NULL AND preparation_receipt_digest IS NULL)
        OR (binding_version=3 AND preparation_candidate_digest IS NOT NULL AND preparation_candidate_digest ~ '^[0-9a-f]{64}$'
            AND preparation_assignment_digest IS NOT NULL AND preparation_assignment_digest ~ '^[0-9a-f]{64}$'
            AND preparation_outcome_digest IS NOT NULL AND preparation_outcome_digest ~ '^[0-9a-f]{64}$'
            AND preparation_receipt_digest IS NOT NULL AND preparation_receipt_digest ~ '^[0-9a-f]{64}$'));

-- Closed projections shared by registration and final row comparisons. No
-- arbitrary table, caller bytes, new UUID or clock can enter this owner.
CREATE FUNCTION internal.initial_admission_member_images(p_receipt internal.initial_preparation_admission_receipts)
RETURNS TABLE(statement_key TEXT,relation_name TEXT,new_image JSONB)
LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts:=p_receipt; m JSONB:=r.manifest::JSONB; object_value JSONB;
BEGIN
    statement_key:='Finalizer.submission.insert'; relation_name:='internal.initial_analysis_submissions';
    new_image:=jsonb_build_object('scan_id',r.scan_id,'owner_id',r.owner_id,'route',m->'route','input_schema_version',1,
        'input_snapshot',r.input::JSONB,'ordered_descriptions',r.input::JSONB->'ordered_descriptions',
        'configuration_snapshot',r.configuration::JSONB,'funding_snapshot',r.funding::JSONB); RETURN NEXT;
    statement_key:='Finalizer.admission.insert'; relation_name:='internal.initial_analysis_admissions';
    new_image:=jsonb_build_object('scan_id',r.scan_id,'owner_id',r.owner_id,'canonical_input',r.input,
        'submission_digest',m#>'{proof,input,digest}','configuration_digest',m#>'{proof,configuration,digest}',
        'funding_digest',m#>'{proof,funding,digest}','descriptions_digest',m->'descriptions_digest',
        'funding_binding_id',m->'funding_binding_id','assets_digest',m->'assets_digest','binding_version',3,
        'preparation_candidate_digest',m#>'{proof,candidate,digest}','preparation_assignment_digest',m->'assignment_digest',
        'preparation_outcome_digest',m#>'{proof,outcome,digest}','preparation_receipt_digest',r.receipt_digest); RETURN NEXT;
    statement_key:='Lifecycle.pending.insert'; relation_name:='internal.initial_analysis_lifecycle_fences';
    new_image:=jsonb_build_object('scan_id',r.scan_id,'state','pending_pre_dispatch'); RETURN NEXT;
    statement_key:='Handoff.receipt.insert'; relation_name:='internal.initial_preparation_admission_receipts';
    new_image:=to_jsonb(r); RETURN NEXT;
    statement_key:='M1.fence.insert'; relation_name:='internal.initial_analysis_media_allocation_fences';
    new_image:=jsonb_build_object('scan_id',r.scan_id,'state','allocated'); RETURN NEXT;
    statement_key:='M1.cohort.insert'; relation_name:='internal.initial_analysis_media_cohorts';
    new_image:=jsonb_build_object('scan_id',r.scan_id,'owner_id',r.owner_id,'binding',r.media_binding::JSONB); RETURN NEXT;
    FOR object_value IN SELECT value FROM jsonb_array_elements(r.mapping::JSONB->'objects') ORDER BY value->>'object_id' COLLATE "C" LOOP
        statement_key:='M1.object.'||(object_value->>'object_id'); relation_name:='internal.initial_analysis_media_registry';
        new_image:=jsonb_build_object('object_id',object_value->'object_id','scan_id',r.scan_id,
            'backend_generation',r.mapping::JSONB->'destination_backend_generation','retired',FALSE,'marker_confirmed',FALSE,
            'claim_token',NULL,'claim_expires_at',NULL); RETURN NEXT;
    END LOOP;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_admission_member_images(internal.initial_preparation_admission_receipts)
    FROM PUBLIC,anon,authenticated,service_role;

-- Recheck the entire prospective receipt before the first private evidence
-- write. The builder is called once; these checks never resample receipt bytes.
CREATE FUNCTION internal.assert_initial_admission_prospective(p_stage internal.initial_preparation_admission_staging)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE s internal.initial_preparation_admission_staging:=p_stage; r internal.initial_preparation_admission_receipts;
    authorized_at NUMERIC; reservation internal.ai_quota_reservations; expected_funding TEXT;
BEGIN
    IF s.prospective_receipt IS NULL THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    r:=jsonb_populate_record(NULL::internal.initial_preparation_admission_receipts,s.prospective_receipt);
    IF s.prospective_receipt IS NULL OR to_jsonb(r) IS DISTINCT FROM s.prospective_receipt
        OR r.scan_id IS DISTINCT FROM s.scan_id OR r.owner_id IS DISTINCT FROM s.owner_id
        OR r.admission_receipt_id IS DISTINCT FROM s.admission_receipt_id
        OR r.candidate IS DISTINCT FROM s.candidate OR r.input IS DISTINCT FROM s.input OR r.outcome IS DISTINCT FROM s.outcome
        OR r.installation IS DISTINCT FROM s.installation OR r.protocol IS DISTINCT FROM s.protocol
        OR r.destination IS DISTINCT FROM s.destination OR r.mapping IS DISTINCT FROM s.mapping
        OR r.media_binding IS DISTINCT FROM s.media_binding
        OR r.configuration IS DISTINCT FROM internal.initial_canonical(jsonb_build_object('version',2,'assignment',s.assignment::JSONB))
        OR r.accounting IS DISTINCT FROM internal.build_initial_admission_accounting(s.scan_id)
        OR r.receipt_digest IS DISTINCT FROM internal.validate_initial_admitted_proof(r.candidate,r.input,r.configuration,r.funding,
            r.outcome,r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest) THEN
        RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
    END IF;
    -- Canonical proof parity cannot know every live funding field (in
    -- particular entitlement_version). Bind the entire original projection to
    -- the locked owner row, with execution model from the saved assignment.
    SELECT * INTO STRICT reservation FROM internal.ai_quota_reservations WHERE id=s.reservation_id FOR UPDATE;
    expected_funding:=internal.initial_canonical(jsonb_build_object('version',1,'original',jsonb_build_object(
        'reservation_id',reservation.id,'request_id',reservation.request_id,
        'original_analysis_id',reservation.original_analysis_id,'operation',reservation.operation,
        'attempt_count',reservation.attempt_count,'effective_plan',reservation.effective_plan,
        'effective_tier',reservation.effective_tier,'entitlement_version',reservation.entitlement_version,
        'policy_version',reservation.policy_version,'model',s.assignment::JSONB->'effective_model',
        'complimentary_client_scan_id',reservation.complimentary_client_scan_id,
        'flash_fallback_used',reservation.flash_fallback_used)));
    IF r.funding IS DISTINCT FROM expected_funding THEN
        RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
    END IF;
    authorized_at:=(r.manifest::JSONB->>'authorized_at_ms')::NUMERIC;
    IF authorized_at>floor(extract(epoch FROM clock_timestamp())*1000)
        OR floor(extract(epoch FROM clock_timestamp())*1000)>=(s.phase_window::JSONB#>>'{cutoffs,admission}')::NUMERIC THEN
        RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000';
    END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_admission_prospective(internal.initial_preparation_admission_staging)
    FROM PUBLIC,anon,authenticated,service_role;

-- This is phase validation while the stage still exists, not the later
-- complete deferred/terminal verifier. It cannot authorize stage consumption.
CREATE FUNCTION internal.assert_initial_admission_materialized(p_scan UUID,p_media BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE s internal.initial_preparation_admission_staging; r internal.initial_preparation_admission_receipts;
    image RECORD; actual JSONB; amount BIGINT;
BEGIN
    SELECT * INTO s FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan;
    IF NOT FOUND OR s.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
        OR s.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE)
        OR p_media IS NULL OR s.phase NOT IN ('reserved','admitted') THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    r:=jsonb_populate_record(NULL::internal.initial_preparation_admission_receipts,s.prospective_receipt);
    FOR image IN SELECT * FROM internal.initial_admission_member_images(r) LOOP
        IF NOT p_media AND image.statement_key LIKE 'M1.%' THEN CONTINUE; END IF;
        IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes w WHERE w.scan_id=p_scan
            AND w.statement_key=image.statement_key AND w.relation_name=image.relation_name AND w.operation='INSERT'
            AND w.old_image IS NULL AND w.new_image=image.new_image AND w.consumed) THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        IF image.relation_name='internal.initial_analysis_media_registry' THEN
            EXECUTE 'SELECT to_jsonb(t) FROM internal.initial_analysis_media_registry t WHERE object_id=$1'
                INTO actual USING (image.new_image->>'object_id')::UUID;
        ELSE
            EXECUTE format('SELECT to_jsonb(t) FROM %s t WHERE scan_id=$1',image.relation_name) INTO actual USING p_scan;
        END IF;
        IF actual IS DISTINCT FROM image.new_image THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
    IF p_media THEN
        SELECT count(*) INTO amount FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan;
        IF amount<>jsonb_array_length(r.mapping::JSONB->'objects') THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
    END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_admission_materialized(UUID,BOOLEAN) FROM PUBLIC,anon,authenticated,service_role;

-- Keep the original admission AFTER owner for pending lifecycle. Only register
-- its exact original insert before that owner's statement.
DO $pending_owner$
DECLARE definition TEXT; anchor TEXT:=' INSERT INTO internal.initial_analysis_lifecycle_fences(scan_id,state) VALUES(NEW.scan_id,''pending_pre_dispatch'');';
BEGIN
    definition:=pg_catalog.pg_get_functiondef('internal.record_initial_pending_state()'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial pending owner seam changed';
    END IF;
    definition:=replace(definition,anchor,$patch$
 IF EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=NEW.scan_id) THEN
  PERFORM internal.register_initial_admission_write(NEW.scan_id,'Lifecycle.pending.insert','internal.initial_analysis_lifecycle_fences',
   'INSERT',NULL,jsonb_build_object('scan_id',NEW.scan_id,'state','pending_pre_dispatch'));
 END IF;
 INSERT INTO internal.initial_analysis_lifecycle_fences(scan_id,state) VALUES(NEW.scan_id,'pending_pre_dispatch');$patch$);
    EXECUTE definition;
END; $pending_owner$;

-- The a0 source barrier accepts only a currently unconsumed exact owner image.
-- Its ordinary rejection still applies to all other aliases/writers. The paired
-- permanent AFTER guard consumes the image after all original guards succeed.
DO $source_barrier$
DECLARE definition TEXT; anchor TEXT:=' PERFORM internal.reject_initial_preparation_provider_writer(identities);';
BEGIN
    definition:=pg_catalog.pg_get_functiondef('internal.guard_initial_preparation_provider_writer()'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial source barrier seam changed';
    END IF;
    definition:=replace(definition,anchor,$patch$
 IF EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging s
  WHERE s.transaction_id=pg_catalog.pg_current_xact_id()
   AND s.stage_token::TEXT=current_setting('merian.initial_admission_stage',TRUE)
   AND internal.initial_admission_expected_write(s.scan_id,TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,TG_OP,previous_row,current_row,FALSE)) THEN
  RETURN NEW;
 END IF;
 PERFORM internal.reject_initial_preparation_provider_writer(identities);$patch$);
    EXECUTE definition;
END; $source_barrier$;

-- Private nested finalizer work only. Public finalization remains closed and
-- the deferred sentinel forbids committing any stage until terminal verification,
-- recovery, C1 and erasure are integrated into the coherent checkpoint.
CREATE FUNCTION internal.materialize_initial_admission(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts; image RECORD;
BEGIN
    r:=internal.build_initial_admission_receipt(p_scan);
    UPDATE internal.initial_preparation_admission_staging SET phase='reserved',prospective_receipt=to_jsonb(r) WHERE scan_id=p_scan;
    FOR image IN SELECT * FROM internal.initial_admission_member_images(r) LOOP
        IF image.statement_key='Lifecycle.pending.insert' OR image.statement_key LIKE 'M1.%' THEN CONTINUE; END IF;
        PERFORM internal.register_initial_admission_write(p_scan,image.statement_key,image.relation_name,'INSERT',NULL,image.new_image);
        EXECUTE format('INSERT INTO %s SELECT (jsonb_populate_record(NULL::%s,$1)).*',image.relation_name,image.relation_name) USING image.new_image;
    END LOOP;
    UPDATE internal.initial_preparation_admission_staging SET phase='admitted' WHERE scan_id=p_scan;
    -- The complete receipt exists before the first M1 member. Destination IDs
    -- were sampled by stage creation, never by a second media allocation owner.
    FOR image IN SELECT * FROM internal.initial_admission_member_images(r) LOOP
        IF image.statement_key NOT LIKE 'M1.%' THEN CONTINUE; END IF;
        PERFORM internal.register_initial_admission_write(p_scan,image.statement_key,image.relation_name,'INSERT',NULL,image.new_image);
        EXECUTE format('INSERT INTO %s SELECT (jsonb_populate_record(NULL::%s,$1)).*',image.relation_name,image.relation_name) USING image.new_image;
    END LOOP;
    UPDATE internal.initial_preparation_admission_staging SET phase='allocated' WHERE scan_id=p_scan;
END; $$;
REVOKE ALL ON FUNCTION internal.materialize_initial_admission(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- UUID primary keys in separate registries do not serialize cross-family
-- allocation. Every source/output and destination insertion takes the same
-- fail-fast namespace lock before checking the other family. No backend calls
-- or fresh identifiers are introduced. Existing identity immutability remains.
CREATE FUNCTION internal.guard_initial_media_object_namespace()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE conflict_found BOOLEAN;
BEGIN
    IF current_setting('transaction_isolation') IS DISTINCT FROM 'read committed' THEN
        RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000';
    END IF;
    IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-initial-media-object:'||NEW.object_id::TEXT,0::BIGINT)) THEN
        RAISE EXCEPTION 'initial_analysis_scope_busy' USING ERRCODE='55000';
    END IF;
    IF TG_TABLE_NAME='initial_preparation_source_registry' THEN
        SELECT EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE object_id=NEW.object_id) INTO conflict_found;
    ELSIF TG_TABLE_NAME='initial_analysis_media_registry' THEN
        SELECT EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE object_id=NEW.object_id) INTO conflict_found;
    ELSE
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    IF conflict_found THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
    RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION internal.guard_initial_media_object_namespace() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER a00_initial_media_object_namespace BEFORE INSERT OR UPDATE OF object_id
    ON internal.initial_preparation_source_registry FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_object_namespace();
CREATE TRIGGER a00_initial_media_object_namespace BEFORE INSERT OR UPDATE OF object_id
    ON internal.initial_analysis_media_registry FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_object_namespace();

RESET statement_timeout;
RESET lock_timeout;

-- Immutable terminal evidence stays in the transient stage/DELETE event only.
-- This check does not use the current GUC, stage or expectation table, nor a
-- clock. It is necessary but not sufficient for durable admission: the complete
-- live-state verifier and terminal consumption/seal are separate checks.
CREATE FUNCTION internal.assert_initial_admission_ledger(p_stage internal.initial_preparation_admission_staging)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE s internal.initial_preparation_admission_staging:=p_stage; r internal.initial_preparation_admission_receipts;
    w internal.initial_preparation_admission_writes; entry JSONB; image RECORD; contract RECORD;
    required_keys TEXT[]:=ARRAY['C4.reservation.insert','C4.remaining.update','C8.attachment.update','Provider.attempt.insert',
        'Counter.user.upsert','C4.user.link','Counter.ip.upsert','C4.ip.link'];
    actual_keys TEXT[]:=ARRAY[]::TEXT[];
BEGIN
    IF s.phase IS NULL OR s.phase NOT IN ('allocated','consuming') OR s.completion_ledger IS NULL
        OR jsonb_typeof(s.completion_ledger) IS DISTINCT FROM 'array'
        OR s.prospective_receipt IS NULL OR to_jsonb(s.policy) IS NULL OR s.acquire_hold IS NULL
        OR s.core8_at IS NULL OR s.core4_at IS NULL OR s.reservation_id IS NULL OR s.lease_token IS NULL
        OR s.completion_event_seq IS NULL OR s.completion_event_seq<1
        OR s.cleanup_cursor IS NULL OR s.cleanup_cursor<0 OR (s.phase='allocated' AND s.cleanup_cursor<>0) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_admission_policy(s.policy);
    r:=jsonb_populate_record(NULL::internal.initial_preparation_admission_receipts,s.prospective_receipt);
    IF to_jsonb(r) IS DISTINCT FROM s.prospective_receipt OR r.scan_id IS DISTINCT FROM s.scan_id
        OR r.owner_id IS DISTINCT FROM s.owner_id OR r.admission_receipt_id IS DISTINCT FROM s.admission_receipt_id
        OR r.candidate IS DISTINCT FROM s.candidate OR r.input IS DISTINCT FROM s.input OR r.outcome IS DISTINCT FROM s.outcome
        OR r.installation IS DISTINCT FROM s.installation OR r.protocol IS DISTINCT FROM s.protocol
        OR r.destination IS DISTINCT FROM s.destination OR r.mapping IS DISTINCT FROM s.mapping
        OR r.media_binding IS DISTINCT FROM s.media_binding
        OR r.media_binding::JSONB->'phase_window' IS DISTINCT FROM s.phase_window::JSONB
        OR r.configuration IS DISTINCT FROM internal.initial_canonical(jsonb_build_object('version',2,'assignment',s.assignment::JSONB))
        OR r.receipt_digest IS DISTINCT FROM internal.validate_initial_admitted_proof(r.candidate,r.input,r.configuration,r.funding,
            r.outcome,r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    IF (s.policy).daily_limit IS NOT NULL THEN required_keys:=required_keys||ARRAY['Counter.daily.upsert','C4.daily.link']; END IF;
    IF s.acquire_hold THEN required_keys:=required_keys||ARRAY['C8.hold.insert','C8.epoch.update']; END IF;
    FOR image IN SELECT * FROM internal.initial_admission_member_images(r) LOOP
        required_keys:=array_append(required_keys,image.statement_key);
    END LOOP;
    IF jsonb_array_length(s.completion_ledger)<>cardinality(required_keys)
        OR s.completion_event_seq<>cardinality(required_keys) OR s.cleanup_cursor>cardinality(required_keys) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    FOR entry IN SELECT value FROM jsonb_array_elements(s.completion_ledger) LOOP
        IF jsonb_typeof(entry) IS DISTINCT FROM 'object' THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        w:=jsonb_populate_record(NULL::internal.initial_preparation_admission_writes,entry);
        SELECT * INTO contract FROM internal.initial_admission_statement_contract(w.statement_key);
        IF to_jsonb(w) IS DISTINCT FROM entry OR w.scan_id IS DISTINCT FROM s.scan_id
            OR w.statement_key IS NULL OR w.statement_key=ANY(actual_keys) OR w.consumed IS DISTINCT FROM TRUE
            OR contract.relation_name IS NULL OR w.relation_name IS DISTINCT FROM contract.relation_name
            OR w.operation IS DISTINCT FROM contract.operation OR w.new_image IS NULL
            OR (w.operation='UPDATE') IS DISTINCT FROM (w.old_image IS NOT NULL)
            OR NOT internal.initial_admission_image_matches(w,w.observed_operation,w.observed_old_image,w.observed_new_image) THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        actual_keys:=array_append(actual_keys,w.statement_key);
    END LOOP;
    IF actual_keys IS DISTINCT FROM (SELECT array_agg(k ORDER BY k COLLATE "C") FROM unnest(required_keys) k) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    FOR image IN SELECT * FROM internal.initial_admission_member_images(r) LOOP
        SELECT * INTO STRICT w FROM jsonb_populate_recordset(NULL::internal.initial_preparation_admission_writes,s.completion_ledger)
            WHERE statement_key=image.statement_key;
        IF w.new_image IS DISTINCT FROM image.new_image THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_admission_ledger(internal.initial_preparation_admission_staging)
    FROM PUBLIC,anon,authenticated,service_role;

-- Bound the aggregate before building it. Each projected row is already size
-- bounded; this preflight prevents an accidental owner loop from accumulating
-- an unbounded JSON array before the stage column's final size check.
CREATE FUNCTION internal.initial_admission_ledger_snapshot(p_scan UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE row_count BIGINT; byte_count BIGINT; result JSONB;
BEGIN
    SELECT count(*),COALESCE(sum(octet_length(to_jsonb(w)::TEXT)::BIGINT),0)+2*count(*)+2
        INTO row_count,byte_count FROM internal.initial_preparation_admission_writes w WHERE w.scan_id=p_scan;
    -- Current eight-source topology needs at most 34 closed statements. The
    -- defensive ceiling is deliberately distinct from exact-key validation.
    IF row_count<1 OR row_count>64 OR byte_count>67108864 THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT jsonb_agg(to_jsonb(w) ORDER BY w.statement_key COLLATE "C") INTO result
        FROM internal.initial_preparation_admission_writes w WHERE w.scan_id=p_scan;
    RETURN result;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_admission_ledger_snapshot(UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.freeze_initial_admission_ledger(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    UPDATE internal.initial_preparation_admission_staging s
        SET completion_ledger=internal.initial_admission_ledger_snapshot(s.scan_id)
        WHERE s.scan_id=p_scan AND s.transaction_id=pg_catalog.pg_current_xact_id()
            AND s.stage_token::TEXT=current_setting('merian.initial_admission_stage',TRUE)
            AND s.phase='allocated' AND s.completion_ledger IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.freeze_initial_admission_ledger(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Complete live predicate for queued events that retain only the original
-- owner/scan/receipt identity. It requires the existing twelve-component receipt
-- and never reconstructs missing proof from mutable rows, caller GUCs, a stage,
-- or expected-write rows. Full original write provenance remains an additional
-- obligation of the terminal DELETE OLD snapshot, not this receipt-only check.
CREATE FUNCTION internal.assert_initial_admission_live_receipt(p_owner UUID,p_scan UUID,p_receipt UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts; saved internal.initial_analysis_preparation_intents;
    q internal.ai_quota_reservations; attempt internal.identification_provider_attempts;
    link internal.ai_quota_reservation_counters; counter internal.ai_quota_counters; hold internal.complimentary_scan_usage;
    image RECORD; actual JSONB; item JSONB; links JSONB:='[]'::JSONB; complimentary JSONB:='null'::JSONB; expected_funding TEXT;
    expected_accounting TEXT; link_count INTEGER:=0;
BEGIN
    SELECT * INTO r FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
    IF NOT FOUND OR p_owner IS NULL OR p_scan IS NULL OR p_receipt IS NULL
        OR r.owner_id IS DISTINCT FROM p_owner OR r.admission_receipt_id IS DISTINCT FROM p_receipt
        OR r.receipt_digest IS DISTINCT FROM internal.validate_initial_admitted_proof(r.candidate,r.input,r.configuration,r.funding,
            r.outcome,r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_owner)
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan)
        OR NOT internal.initial_media_pending(p_scan)
        OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_owner AND status IN ('pending','storage_pending','auth_pending'))
        OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_verifications WHERE scan_id=p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
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
    END IF;
    FOR image IN SELECT * FROM internal.initial_admission_member_images(r) LOOP
        IF image.relation_name='internal.initial_analysis_media_registry' THEN
            SELECT to_jsonb(t) INTO actual FROM internal.initial_analysis_media_registry t WHERE object_id=(image.new_image->>'object_id')::UUID;
        ELSE
            EXECUTE format('SELECT to_jsonb(t) FROM %s t WHERE scan_id=$1',image.relation_name) INTO actual USING p_scan;
        END IF;
        IF actual IS DISTINCT FROM image.new_image THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
    IF (SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan)<>jsonb_array_length(r.mapping::JSONB->'objects') THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO q FROM internal.ai_quota_reservations WHERE id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID;
    IF NOT FOUND OR q.user_id IS DISTINCT FROM p_owner OR q.request_id IS DISTINCT FROM p_scan
        OR q.original_analysis_id IS DISTINCT FROM p_scan OR q.operation IS DISTINCT FROM 'scan_identification'
        OR q.state IS DISTINCT FROM 'reserved' OR q.attempt_count IS DISTINCT FROM 1 OR q.refund_count<>0 OR q.stale_recovery_count<>0
        OR q.committed_at IS NOT NULL OR q.failed_at IS NOT NULL OR q.refunded_at IS NOT NULL
        OR q.lease_token IS NULL OR q.reserved_at IS NULL OR NOT pg_catalog.isfinite(q.reserved_at)
        OR q.lease_expires_at IS DISTINCT FROM q.reserved_at+INTERVAL '10 minutes'
        OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations other WHERE other.id<>q.id
            AND (other.request_id=p_scan OR other.original_analysis_id=p_scan OR other.complimentary_client_scan_id=p_scan)) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    expected_funding:=internal.initial_canonical(jsonb_build_object('version',1,'original',jsonb_build_object(
        'reservation_id',q.id,'request_id',q.request_id,'original_analysis_id',q.original_analysis_id,'operation',q.operation,
        'attempt_count',q.attempt_count,'effective_plan',q.effective_plan,'effective_tier',q.effective_tier,
        'entitlement_version',q.entitlement_version,'policy_version',q.policy_version,
        'model',r.configuration::JSONB#>'{assignment,effective_model}',
        'complimentary_client_scan_id',q.complimentary_client_scan_id,'flash_fallback_used',q.flash_fallback_used)));
    IF r.funding IS DISTINCT FROM expected_funding THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO attempt FROM internal.identification_provider_attempts WHERE reservation_id=q.id AND attempt_count=1;
    IF NOT FOUND OR attempt.model IS DISTINCT FROM q.model OR attempt.operation IS DISTINCT FROM q.operation
        OR attempt.effective_plan IS DISTINCT FROM q.effective_plan OR attempt.policy_version IS DISTINCT FROM q.policy_version
        OR (SELECT count(*) FROM internal.identification_provider_attempts WHERE reservation_id=q.id)<>1 THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    FOR item IN SELECT value FROM jsonb_array_elements(r.accounting::JSONB#>'{charges,links}') LOOP
        SELECT * INTO link FROM internal.ai_quota_reservation_counters l WHERE l.reservation_id=q.id
            AND l.scope_type=item->>'scope_type' AND l.scope_key=item->>'scope_key' AND l.bucket=item->>'bucket'
            AND l.window_start=(item->>'window_start')::TIMESTAMPTZ;
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
        SELECT * INTO counter FROM internal.ai_quota_counters c WHERE c.scope_type=link.scope_type AND c.scope_key=link.scope_key
            AND c.bucket=link.bucket AND c.window_start=link.window_start;
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
        -- The historical proof stores the original charge, never mutable shared
        -- totals. Permanent guards and mandatory entry sealing protect this tx.
        links:=links||jsonb_build_array(to_jsonb(link)||jsonb_build_object('window_start',internal.initial_admission_timestamp(link.window_start),
            'window_seconds',counter.window_seconds,'delta',1));
        link_count:=link_count+1;
    END LOOP;
    IF (SELECT count(*) FROM internal.ai_quota_reservation_counters WHERE reservation_id=q.id)<>link_count THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    IF q.complimentary_client_scan_id IS NOT NULL THEN
        SELECT * INTO hold FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_scan;
        IF NOT FOUND OR q.complimentary_client_scan_id IS DISTINCT FROM p_scan OR hold.state IS DISTINCT FROM 'held'
            OR hold.settled_at IS NOT NULL OR hold.settlement_reason IS NOT NULL OR hold.reacquisition_count<>0
            OR (SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id=p_scan)<>1 THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        complimentary:=jsonb_build_object('owner_id',p_owner,'client_scan_id',p_scan,'classification','pro_complimentary','state_at_admission','held');
    ELSIF EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    expected_accounting:=internal.initial_canonical(jsonb_build_object('version',1,
        'reservation',jsonb_build_object('reservation_id',q.id,'owner_id',q.user_id,'scan_id',p_scan,
            'attempt_count',q.attempt_count,'lease_token',q.lease_token,'lease_expires_at',internal.initial_admission_timestamp(q.lease_expires_at)),
        'attempt',to_jsonb(attempt)-'created_at','charges',jsonb_build_object('policy',jsonb_build_object(
            'operation',q.operation,'effective_plan',q.effective_plan,'policy_version',q.policy_version),'links',links),'complimentary',complimentary));
    IF r.accounting IS DISTINCT FROM expected_accounting THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_admission_live_receipt(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Deterministic live comparison against the original transient proof. No GUC,
-- mutable stage/expectation lookup, clock sampling, writes or new locks. The
-- caller must retain the original admission lock scope. This helper is not an
-- admission, historical-recovery or stage-deletion authority by itself.
CREATE FUNCTION internal.assert_initial_admission_live_snapshot(p_stage internal.initial_preparation_admission_staging)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE s internal.initial_preparation_admission_staging:=p_stage; r internal.initial_preparation_admission_receipts;
    q internal.ai_quota_reservations;
    attempt internal.identification_provider_attempts; link internal.ai_quota_reservation_counters;
    counter internal.ai_quota_counters; w internal.initial_preparation_admission_writes;
    links JSONB:='[]'::JSONB; complimentary JSONB:='null'::JSONB; expected_accounting TEXT;
    expected_funding TEXT; kind TEXT; link_count INTEGER:=0; first_row JSONB; middle_old JSONB; middle_new JSONB; last_old JSONB;
BEGIN
    PERFORM internal.assert_initial_admission_ledger(s);
    IF s.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
        OR (SELECT to_jsonb(t) FROM internal.initial_preparation_admission_receipts t WHERE scan_id=s.scan_id)
            IS DISTINCT FROM s.prospective_receipt THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_admission_live_receipt(s.owner_id,s.scan_id,s.admission_receipt_id);
    r:=jsonb_populate_record(NULL::internal.initial_preparation_admission_receipts,s.prospective_receipt);
    SELECT * INTO q FROM internal.ai_quota_reservations WHERE id=s.reservation_id;
    SELECT * INTO w FROM jsonb_populate_recordset(NULL::internal.initial_preparation_admission_writes,s.completion_ledger)
        WHERE statement_key='C8.attachment.update';
    IF q.id IS NULL OR to_jsonb(q) IS DISTINCT FROM w.observed_new_image
        OR q.user_id IS DISTINCT FROM s.owner_id OR q.request_id IS DISTINCT FROM s.scan_id
        OR q.original_analysis_id IS DISTINCT FROM s.scan_id OR q.operation IS DISTINCT FROM 'scan_identification'
        OR q.state IS DISTINCT FROM 'reserved' OR q.attempt_count IS DISTINCT FROM 1 OR q.refund_count<>0 OR q.stale_recovery_count<>0
        OR q.committed_at IS NOT NULL OR q.failed_at IS NOT NULL OR q.refunded_at IS NOT NULL
        OR q.lease_token IS DISTINCT FROM s.lease_token OR q.reserved_at IS DISTINCT FROM s.core4_at
        OR q.lease_expires_at IS DISTINCT FROM s.core4_at+INTERVAL '10 minutes'
        OR q.model IS DISTINCT FROM (s.policy).model OR q.effective_plan IS DISTINCT FROM (s.policy).effective_plan
        OR q.policy_version IS DISTINCT FROM (s.policy).policy_version OR q.daily_limit IS DISTINCT FROM (s.policy).daily_limit
        OR q.complimentary_client_scan_id IS DISTINCT FROM s.resolved_link
        OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations other WHERE other.id<>s.reservation_id
            AND (other.request_id=s.scan_id OR other.original_analysis_id=s.scan_id OR other.complimentary_client_scan_id=s.scan_id)) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    last_old:=w.observed_old_image;
    SELECT observed_new_image INTO first_row FROM jsonb_populate_recordset(NULL::internal.initial_preparation_admission_writes,s.completion_ledger)
        WHERE statement_key='C4.reservation.insert';
    SELECT observed_old_image,observed_new_image INTO middle_old,middle_new FROM jsonb_populate_recordset(NULL::internal.initial_preparation_admission_writes,s.completion_ledger)
        WHERE statement_key='C4.remaining.update';
    IF first_row IS DISTINCT FROM middle_old OR middle_new IS DISTINCT FROM last_old THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    expected_funding:=internal.initial_canonical(jsonb_build_object('version',1,'original',jsonb_build_object(
        'reservation_id',q.id,'request_id',q.request_id,'original_analysis_id',q.original_analysis_id,'operation',q.operation,
        'attempt_count',q.attempt_count,'effective_plan',q.effective_plan,'effective_tier',q.effective_tier,
        'entitlement_version',q.entitlement_version,'policy_version',q.policy_version,'model',s.assignment::JSONB->'effective_model',
        'complimentary_client_scan_id',q.complimentary_client_scan_id,'flash_fallback_used',q.flash_fallback_used)));
    IF r.funding IS DISTINCT FROM expected_funding THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO attempt FROM internal.identification_provider_attempts WHERE reservation_id=q.id AND attempt_count=1;
    SELECT * INTO w FROM jsonb_populate_recordset(NULL::internal.initial_preparation_admission_writes,s.completion_ledger)
        WHERE statement_key='Provider.attempt.insert';
    IF to_jsonb(attempt) IS DISTINCT FROM w.observed_new_image
        OR (SELECT count(*) FROM internal.identification_provider_attempts WHERE reservation_id=q.id)<>1 THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    FOREACH kind IN ARRAY ARRAY['daily','user','ip'] LOOP
        SELECT * INTO w FROM jsonb_populate_recordset(NULL::internal.initial_preparation_admission_writes,s.completion_ledger)
            WHERE statement_key='C4.'||kind||'.link';
        IF NOT FOUND THEN CONTINUE; END IF;
        SELECT * INTO link FROM internal.ai_quota_reservation_counters l WHERE l.reservation_id=q.id
            AND l.scope_type=w.new_image->>'scope_type' AND l.scope_key=w.new_image->>'scope_key'
            AND l.bucket=w.new_image->>'bucket' AND l.window_start=(w.new_image->>'window_start')::TIMESTAMPTZ;
        IF to_jsonb(link) IS DISTINCT FROM w.observed_new_image THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        SELECT * INTO w FROM jsonb_populate_recordset(NULL::internal.initial_preparation_admission_writes,s.completion_ledger)
            WHERE statement_key='Counter.'||kind||'.upsert';
        SELECT * INTO counter FROM internal.ai_quota_counters c WHERE c.scope_type=link.scope_type AND c.scope_key=link.scope_key
            AND c.bucket=link.bucket AND c.window_start=link.window_start;
        -- The charge delta is proved by the winning event; only shared counter
        -- identity/window is a persistent association, never its global total.
        IF to_jsonb(counter)-ARRAY['request_count','updated_at'] IS DISTINCT FROM w.observed_new_image-ARRAY['request_count','updated_at'] THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        links:=links||jsonb_build_array(to_jsonb(link)||jsonb_build_object('window_start',internal.initial_admission_timestamp(link.window_start),
            'window_seconds',counter.window_seconds,'delta',1));
        link_count:=link_count+1;
    END LOOP;
    IF (SELECT count(*) FROM internal.ai_quota_reservation_counters WHERE reservation_id=q.id)<>link_count
        OR (SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id=s.scan_id)<>(CASE WHEN s.acquire_hold THEN 1 ELSE 0 END) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    IF s.acquire_hold THEN
        SELECT * INTO w FROM jsonb_populate_recordset(NULL::internal.initial_preparation_admission_writes,s.completion_ledger)
            WHERE statement_key='C8.hold.insert';
        IF (SELECT to_jsonb(t) FROM internal.complimentary_scan_usage t WHERE user_id=s.owner_id AND client_scan_id=s.scan_id) IS DISTINCT FROM w.observed_new_image THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        complimentary:=jsonb_build_object('owner_id',s.owner_id,'client_scan_id',s.scan_id,'classification','pro_complimentary','state_at_admission','held');
    END IF;
    expected_accounting:=internal.initial_canonical(jsonb_build_object('version',1,
        'reservation',jsonb_build_object('reservation_id',q.id,'owner_id',q.user_id,'scan_id',s.scan_id,
            'attempt_count',q.attempt_count,'lease_token',q.lease_token,'lease_expires_at',internal.initial_admission_timestamp(q.lease_expires_at)),
        'attempt',to_jsonb(attempt)-'created_at','charges',jsonb_build_object('policy',jsonb_build_object(
            'operation',q.operation,'effective_plan',q.effective_plan,'policy_version',q.policy_version),'links',links),'complimentary',complimentary));
    IF r.accounting IS DISTINCT FROM expected_accounting THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_admission_live_snapshot(internal.initial_preparation_admission_staging)
    FROM PUBLIC,anon,authenticated,service_role;

-- Explicit parent-present consumption. The original winning-member event count
-- and frozen ledger never change; cleanup has a separate bounded cursor.
CREATE FUNCTION internal.assert_initial_admission_remaining(p_stage internal.initial_preparation_admission_staging)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE s internal.initial_preparation_admission_staging:=p_stage; remaining BIGINT; expected JSONB; actual JSONB;
BEGIN
    -- Entry into consuming already validates the complete immutable proof.
    -- Recheck the exact untouched suffix at every child event, not all twelve
    -- canonical components repeatedly inside the bounded deletion loop.
    IF s.phase IS DISTINCT FROM 'consuming' OR s.completion_ledger IS NULL
        OR jsonb_typeof(s.completion_ledger) IS DISTINCT FROM 'array'
        OR s.cleanup_cursor IS NULL OR s.cleanup_cursor<0
        OR s.cleanup_cursor>jsonb_array_length(s.completion_ledger)
        OR s.completion_event_seq IS DISTINCT FROM jsonb_array_length(s.completion_ledger)::BIGINT THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT count(*) INTO remaining FROM internal.initial_preparation_admission_writes WHERE scan_id=s.scan_id;
    IF remaining<>jsonb_array_length(s.completion_ledger)-s.cleanup_cursor THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT COALESCE(jsonb_agg(e ORDER BY n),'[]'::JSONB) INTO expected
        FROM jsonb_array_elements(s.completion_ledger) WITH ORDINALITY t(e,n) WHERE n>s.cleanup_cursor;
    actual:=CASE WHEN remaining=0 THEN '[]'::JSONB ELSE internal.initial_admission_ledger_snapshot(s.scan_id) END;
    IF actual IS DISTINCT FROM expected THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_admission_remaining(internal.initial_preparation_admission_staging)
    FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.advance_initial_admission_cleanup()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE parent internal.initial_preparation_admission_staging;
BEGIN
    SELECT * INTO parent FROM internal.initial_preparation_admission_staging WHERE scan_id=OLD.scan_id;
    IF NOT FOUND OR TG_OP<>'DELETE' OR TG_WHEN<>'AFTER' OR pg_catalog.pg_trigger_depth()<>1
        OR parent.phase IS DISTINCT FROM 'consuming' OR parent.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
        OR parent.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE)
        OR parent.completion_ledger IS NULL OR parent.cleanup_cursor>=jsonb_array_length(parent.completion_ledger)
        OR to_jsonb(OLD) IS DISTINCT FROM parent.completion_ledger->parent.cleanup_cursor::INTEGER THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    UPDATE internal.initial_preparation_admission_staging SET cleanup_cursor=cleanup_cursor+1
        WHERE scan_id=parent.scan_id AND phase='consuming' AND transaction_id=parent.transaction_id
            AND stage_token=parent.stage_token AND cleanup_cursor=parent.cleanup_cursor;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
    RETURN OLD;
END; $$;
REVOKE ALL ON FUNCTION internal.advance_initial_admission_cleanup() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER advance_initial_admission_cleanup AFTER DELETE ON internal.initial_preparation_admission_writes
    FOR EACH ROW EXECUTE FUNCTION internal.advance_initial_admission_cleanup();

CREATE FUNCTION internal.begin_initial_admission_consumption(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    UPDATE internal.initial_preparation_admission_staging SET phase='consuming'
        WHERE scan_id=p_scan AND transaction_id=pg_catalog.pg_current_xact_id()
            AND stage_token::TEXT=current_setting('merian.initial_admission_stage',TRUE)
            AND phase='allocated' AND cleanup_cursor=0 AND completion_ledger IS NOT NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.begin_initial_admission_consumption(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- The guarded consuming entry has already acquired the actual xact seal.
-- The complete terminal owner subsequently proves/deletes the empty parent.
CREATE FUNCTION internal.consume_initial_admission_writes(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE parent internal.initial_preparation_admission_staging; affected BIGINT;
BEGIN
    LOOP
        SELECT * INTO parent FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan;
        IF NOT FOUND OR parent.phase IS DISTINCT FROM 'consuming'
            OR parent.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
            OR parent.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE) THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_admission_remaining(parent);
        IF parent.cleanup_cursor=jsonb_array_length(parent.completion_ledger) THEN RETURN; END IF;
        DELETE FROM internal.initial_preparation_admission_writes WHERE scan_id=p_scan
            AND statement_key=parent.completion_ledger->parent.cleanup_cursor::INTEGER->>'statement_key';
        GET DIAGNOSTICS affected=ROW_COUNT;
        IF affected<>1 OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging
            WHERE scan_id=p_scan AND cleanup_cursor=parent.cleanup_cursor+1) THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
END; $$;
REVOKE ALL ON FUNCTION internal.consume_initial_admission_writes(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Optional private revalidation always reacquires the transaction lock already
-- taken at consuming entry, even if a matching session lock is now visible. Unlock-all cannot undo
-- it. Fail fast on peer/hash collision; never wait or infer provenance from it.
CREATE FUNCTION internal.seal_initial_admission(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE s internal.initial_preparation_admission_staging;
BEGIN
    SELECT * INTO s FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan;
    IF NOT FOUND OR s.phase IS DISTINCT FROM 'consuming' OR s.cleanup_cursor IS DISTINCT FROM 0
        OR s.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
        OR s.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_admission_live_snapshot(s);
    PERFORM internal.assert_initial_admission_remaining(s);
    IF NOT pg_catalog.pg_try_advisory_xact_lock(1229018189,pg_catalog.hashtext(p_scan::TEXT)) THEN
        RAISE EXCEPTION 'initial_analysis_admission_sealed' USING ERRCODE='55000';
    END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.seal_initial_admission(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- BEFORE STATEMENT runs before row shortcuts, entitlement/retirement triggers,
-- UPSERT probes and zero-row statements. Separate private stage/expectation
-- guards permit only their exact parent-present cleanup, never seal authority.
-- This covers all admission members, preparation proof, competing producers,
-- terminal/erasure aliases and their TRUNCATE/CASCADE paths.
DO $seal_guards$
DECLARE relation_name TEXT;
BEGIN
    FOREACH relation_name IN ARRAY ARRAY[
        'internal.ai_quota_reservations','internal.complimentary_scan_usage',
        'internal.identification_provider_attempts','internal.ai_quota_counters','internal.ai_quota_reservation_counters',
        'public.users','internal.initial_analysis_submissions','internal.initial_analysis_admissions',
        'internal.initial_analysis_lifecycle_fences','internal.initial_preparation_admission_receipts',
        'internal.initial_analysis_media_allocation_fences','internal.initial_analysis_media_registry',
        'internal.initial_analysis_media_cohorts','internal.initial_analysis_operation_fences',
        'internal.initial_analysis_preparation_intents','internal.initial_preparation_source_fences',
        'internal.initial_preparation_source_registry','internal.initial_preparation_source_mapping',
        'internal.initial_preparation_source_verifications','internal.initial_preparation_execution_grants',
        'internal.initial_preparation_output_manifests','internal.initial_preparation_output_mapping',
        'internal.initial_preparation_outcomes','public.scans','public.scan_ingestion_jobs','public.scan_ingestion_intents',
        'internal.observation_histories','internal.observation_analysis_source_bindings',
        'internal.observation_analysis_intents','internal.observation_analysis_results',
        'internal.identification_invocations','internal.initial_analysis_results','internal.initial_analysis_completions',
        'internal.initial_analysis_media_preparations','internal.initial_analysis_media_verifications',
        'internal.initial_analysis_cancellations','internal.scan_deletion_tombstones','internal.account_deletion_jobs'
    ] LOOP
        EXECUTE format('CREATE TRIGGER a00_initial_admission_seal BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_admission_seal()',relation_name);
    END LOOP;
END;
$seal_guards$;

-- Private terminal composition. Public admission remains closed until recovery,
-- settlement/erasure and the complete coherent checkpoint are qualified.
CREATE FUNCTION internal.finish_initial_admission(p_scan UUID)
RETURNS internal.initial_preparation_admission_receipts
LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE s internal.initial_preparation_admission_staging; result internal.initial_preparation_admission_receipts;
    final_checked_at NUMERIC;
BEGIN
    SELECT * INTO s FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan;
    IF NOT FOUND OR s.phase IS DISTINCT FROM 'consuming'
        OR s.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
        OR s.stage_token::TEXT IS DISTINCT FROM current_setting('merian.initial_admission_stage',TRUE) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.consume_initial_admission_writes(p_scan);
    DELETE FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
    SET CONSTRAINTS ALL IMMEDIATE;
    SELECT * INTO result FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
    IF NOT FOUND OR to_jsonb(result) IS DISTINCT FROM s.prospective_receipt THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    -- All consistency checks precede this last nonmutating deadline boundary.
    -- Deferred consistency callbacks themselves never sample a clock or lock.
    final_checked_at:=floor(extract(epoch FROM clock_timestamp())*1000);
    IF final_checked_at<(s.phase_window::JSONB->>'anchor_ms')::NUMERIC
        OR final_checked_at>=(s.phase_window::JSONB#>>'{cutoffs,admission}')::NUMERIC THEN
        RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000';
    END IF;
    RETURN result;
END; $$;
REVOKE ALL ON FUNCTION internal.finish_initial_admission(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Co-retained integrity only, not ownership, current eligibility, unused-funding
-- proof or action authority. Recovery owners must hold the canonical outer scope
-- and apply deletion/cancellation/transfer precedence before using this result.
-- This deliberately has no dependency on preparation intent/source rows, mutable
-- quota state, stage/GUC, current catalogs or elapsed time.
CREATE FUNCTION internal.initial_admission_retained_receipt(p_owner UUID,p_scan UUID,p_receipt UUID)
RETURNS internal.initial_preparation_admission_receipts
LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts; image RECORD; actual JSONB;
BEGIN
    SELECT * INTO r FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
    IF NOT FOUND OR p_owner IS NULL OR p_scan IS NULL OR p_receipt IS NULL
        OR r.owner_id IS DISTINCT FROM p_owner OR r.admission_receipt_id IS DISTINCT FROM p_receipt
        OR r.manifest::JSONB->>'owner_id' IS DISTINCT FROM r.owner_id::TEXT
        OR r.manifest::JSONB->>'scan_id' IS DISTINCT FROM r.scan_id::TEXT
        OR r.manifest::JSONB->>'admission_receipt_id' IS DISTINCT FROM r.admission_receipt_id::TEXT
        OR r.receipt_digest IS DISTINCT FROM internal.validate_initial_admitted_proof(r.candidate,r.input,r.configuration,r.funding,
            r.outcome,r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    FOR image IN SELECT * FROM internal.initial_admission_member_images(r)
        WHERE statement_key IN ('Finalizer.submission.insert','Finalizer.admission.insert') LOOP
        IF image.statement_key='Finalizer.submission.insert' THEN
            SELECT to_jsonb(t) INTO actual FROM internal.initial_analysis_submissions t WHERE scan_id=p_scan;
        ELSE
            SELECT to_jsonb(t) INTO actual FROM internal.initial_analysis_admissions t WHERE scan_id=p_scan;
        END IF;
        IF actual IS DISTINCT FROM image.new_image THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
    RETURN r;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_admission_retained_receipt(UUID,UUID,UUID)
    FROM PUBLIC,anon,authenticated,service_role;

-- Closed recovery metadata only; callers still require original receipt and locked lifecycle proof.
CREATE FUNCTION internal.initial_admission_recovery_response_schema() RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path='' AS $f$ SELECT $json${"admitted":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"authority":{"type":"string","max_bytes":4,"enum":["none"]},"outcome":{"type":"string","max_bytes":8,"enum":["admitted"]},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"admission_receipt_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"binding":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"admission_receipt_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"submission_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"outcome_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"mapping_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"destination_backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"phase_window":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"admission_receipt_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"handoff_profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"handoff_installation_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"protocol_artifact_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"anchor_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"original_expires_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"cutoffs":{"type":"object","properties":{"admission":{"type":"integer","minimum":0,"maximum":9007199254740991},"copy":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification_claim":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification_settlement":{"type":"integer","minimum":0,"maximum":9007199254740991},"transfer":{"type":"integer","minimum":0,"maximum":9007199254740991},"reconciliation":{"type":"integer","minimum":0,"maximum":9007199254740991},"protocol_margin":{"type":"integer","minimum":0,"maximum":9007199254740991}}}}},"phase_window_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"phase":{"type":"string","max_bytes":12,"enum":["copy","verification","transfer","expired"]}}},"transferred":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"authority":{"type":"string","max_bytes":4,"enum":["none"]},"outcome":{"type":"string","max_bytes":11,"enum":["transferred"]},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"admission_receipt_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"binding":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"admission_receipt_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"submission_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"outcome_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"mapping_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"destination_backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"phase_window":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"admission_receipt_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"handoff_profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"handoff_installation_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"protocol_artifact_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"anchor_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"original_expires_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"cutoffs":{"type":"object","properties":{"admission":{"type":"integer","minimum":0,"maximum":9007199254740991},"copy":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification_claim":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification_settlement":{"type":"integer","minimum":0,"maximum":9007199254740991},"transfer":{"type":"integer","minimum":0,"maximum":9007199254740991},"reconciliation":{"type":"integer","minimum":0,"maximum":9007199254740991},"protocol_margin":{"type":"integer","minimum":0,"maximum":9007199254740991}}}}},"phase_window_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"transfer_receipt_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"held":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"authority":{"type":"string","max_bytes":4,"enum":["none"]},"outcome":{"type":"string","max_bytes":4,"enum":["held"]},"reason":{"type":"string","max_bytes":19,"enum":["already_transferred"]},"transfer_receipt_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}}}$json$::JSONB $f$;
CREATE FUNCTION internal.parse_initial_admission_recovery_response(p_text TEXT)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE v JSONB; shape JSONB; binding JSONB; window_value JSONB; phase TEXT; previous NUMERIC; cutoff NUMERIC;
BEGIN
 IF p_text IS NULL OR octet_length(p_text)>32768 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN v:=p_text::JSONB; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 shape:=internal.initial_admission_recovery_response_schema()->(v->>'outcome');
 IF shape IS NULL OR internal.initial_canonical(v) IS DISTINCT FROM p_text OR NOT internal.initial_schema_matches(v,shape) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 IF v->>'outcome'='held' THEN RETURN v; END IF;
 binding:=internal.parse_initial_admission_metadata('media_binding',internal.initial_canonical(v->'binding'));
 window_value:=binding->'phase_window';
 IF v->>'scan_id' IS DISTINCT FROM binding->>'scan_id'
  OR binding->>'owner_id' IS DISTINCT FROM window_value->>'owner_id'
  OR binding->>'scan_id' IS DISTINCT FROM window_value->>'scan_id'
  OR binding->>'admission_receipt_id' IS DISTINCT FROM window_value->>'admission_receipt_id' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 previous:=(window_value->>'anchor_ms')::NUMERIC;
 FOREACH phase IN ARRAY ARRAY['admission','copy','verification_claim','verification','verification_settlement','transfer','reconciliation','protocol_margin'] LOOP
  cutoff:=(window_value#>>ARRAY['cutoffs',phase])::NUMERIC;
  IF cutoff<=previous THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  previous:=cutoff;
 END LOOP;
 IF previous>=(window_value->>'original_expires_at_ms')::NUMERIC
  OR binding->>'phase_window_digest' IS DISTINCT FROM internal.initial_admission_metadata_digest('phase_window',internal.initial_canonical(window_value)) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 RETURN v;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_admission_recovery_response_schema(),internal.parse_initial_admission_recovery_response(TEXT) FROM PUBLIC,anon,authenticated,service_role;

-- Pure response construction only. The observed time is supplied by the locked
-- owner after retained-proof validation, never by a public caller. No phase
-- implies copy/M2 progress or grants action/settlement authority.
CREATE FUNCTION internal.initial_admitted_recovery_response(
 p_receipt internal.initial_preparation_admission_receipts,p_observed_at_ms NUMERIC
) RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE binding JSONB; phase TEXT;
BEGIN
 IF p_observed_at_ms IS NULL OR p_observed_at_ms<0 OR p_observed_at_ms>9007199254740991
  OR p_observed_at_ms<>trunc(p_observed_at_ms) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 binding:=internal.parse_initial_admission_metadata('media_binding',p_receipt.media_binding);
 IF binding->>'owner_id' IS DISTINCT FROM p_receipt.owner_id::TEXT
  OR binding->>'scan_id' IS DISTINCT FROM p_receipt.scan_id::TEXT
  OR binding->>'admission_receipt_id' IS DISTINCT FROM p_receipt.admission_receipt_id::TEXT THEN
  RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
 END IF;
 IF p_observed_at_ms<(binding#>>'{phase_window,anchor_ms}')::NUMERIC THEN
  RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
 END IF;
 phase:=CASE WHEN p_observed_at_ms<(binding#>>'{phase_window,cutoffs,copy}')::NUMERIC THEN 'copy' ELSE 'expired' END;
 RETURN internal.parse_initial_admission_recovery_response(internal.initial_canonical(jsonb_build_object(
  'version',2,'outcome','admitted','authority','none','scan_id',p_receipt.scan_id,
  'admission_receipt_digest',p_receipt.receipt_digest,'binding',binding,'phase',phase)));
END; $$;

-- Private admitted-only recovery. Explicit SQL callers below adopt this branch.
-- No transfer response exists until a qualified durable transfer owner does.
CREATE FUNCTION internal.recover_initial_admitted_media(p_owner UUID,p_scan UUID)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE admitted internal.initial_analysis_admissions; receipt internal.initial_preparation_admission_receipts;
BEGIN
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 -- Preserve the established recovery pair order, then lock the subordinate receipt.
 SELECT * INTO admitted FROM internal.initial_analysis_admissions WHERE scan_id=p_scan AND owner_id=p_owner FOR UPDATE;
 IF NOT FOUND OR admitted.owner_id IS DISTINCT FROM p_owner OR admitted.binding_version<>3 THEN
  RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
 END IF;
 PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=p_scan AND owner_id=p_owner FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
 SELECT * INTO receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan AND owner_id=p_owner FOR UPDATE;
 IF NOT FOUND OR receipt.owner_id IS DISTINCT FROM p_owner
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan)
  OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan
   AND state IN ('pending_pre_dispatch','dispatch_authorized')) THEN
  RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
 END IF;
 receipt:=internal.initial_admission_retained_receipt(p_owner,p_scan,receipt.admission_receipt_id);
 -- Sample only after every blocking lock and the complete retained proof.
 RETURN internal.initial_admitted_recovery_response(receipt,floor(extract(epoch FROM clock_timestamp())*1000));
END; $$;
REVOKE ALL ON FUNCTION internal.initial_admitted_recovery_response(internal.initial_preparation_admission_receipts,NUMERIC),
 internal.recover_initial_admitted_media(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Explicit admitted-v3 recovery branches only. The legacy helper and its
-- no-media intent-erasure caller retain their original response assumptions.
DO $recovery_routing$
DECLARE definition TEXT; anchor TEXT; signature TEXT; branch TEXT;
BEGIN
 branch:=$body$
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=p_scan AND binding_version=3)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan) THEN
  RETURN internal.recover_initial_admitted_media(p_owner,p_scan);
 END IF;
$body$;
 FOREACH signature IN ARRAY ARRAY['public.get_initial_preparation_status(uuid,uuid)','public.finalize_initial_preparation(uuid,uuid,text)'] LOOP
  SELECT pg_get_functiondef(signature::REGPROCEDURE) INTO STRICT definition;
  anchor:=' recovered:=internal.recover_initial_preparation_admission(p_owner,p_scan);';
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
   RAISE EXCEPTION 'initial admitted recovery caller drift: %',signature;
  END IF;
  EXECUTE replace(definition,anchor,branch||anchor);
 END LOOP;
 SELECT pg_get_functiondef('internal.create_initial_media_preparation(uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='assignment TEXT; item JSONB;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial admitted media creator declaration drift'; END IF;
 definition:=replace(definition,anchor,anchor||' recovered JSONB;');
 anchor:=' PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial admitted media creator scope drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=p_scan AND binding_version=3)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan) THEN
  recovered:=internal.recover_initial_admitted_media(p_owner,p_scan);
  IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts r WHERE r.scan_id=p_scan AND r.owner_id=p_owner
   AND r.candidate=p_candidate) THEN
   RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
  END IF;
  RETURN recovered;
 END IF;
$body$);
 -- All old execution actions check intent expiry before their action branch.
 -- Once admitted, they must never route a read/retry into legacy cancellation.
 SELECT pg_get_functiondef('internal.initial_preparation_execution_action(text,uuid,uuid,text,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='reply_version INTEGER; ctx JSONB; handoff JSONB;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial admitted execution declaration drift'; END IF;
 definition:=replace(definition,anchor,anchor||' admitted_recovery JSONB;');
 anchor:=' PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial admitted execution scope drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=p_scan AND binding_version=3)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan) THEN
  admitted_recovery:=internal.recover_initial_admitted_media(p_owner,p_scan);
  IF admitted_recovery#>>'{binding,assignment_digest}' IS DISTINCT FROM p_assignment_digest THEN
   RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
  END IF;
  RETURN internal.initial_preparation_held_reply(2,'incoherent');
 END IF;
$body$);
END; $recovery_routing$;

-- The two permanent namespace fences survive private-proof erasure. Their
-- conjunction conservatively denies settlement after unknown cancellation; it
-- proves neither v3 lineage nor action authority. Erasing private proof cannot
-- reopen generic settlement, including for older media with both fences.
CREATE FUNCTION internal.initial_admitted_settlement_blocked(p_scan UUID)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=p_scan AND binding_version=3)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan)
  OR (EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan)
   AND EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan));
$$;
REVOKE ALL ON FUNCTION internal.initial_admitted_settlement_blocked(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Until the dedicated admitted C1 owner proves complete original unused state,
-- the legacy funding-only predicate must never refund an admitted operation.
-- Either retained half claims this boundary. Damaged proof may still follow the
-- existing unknown/dispatched nonrefundable cancellation and erasure owners.
DO $admitted_cancellation_fence$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_get_functiondef('internal.cancel_initial_analysis(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$  proven:=lifecycle='pending_pre_dispatch' AND admission.owner_id=p_owner AND quota.user_id=p_owner$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'initial admitted cancellation proof drift';
 END IF;
 EXECUTE replace(definition,anchor,$body$  proven:=NOT internal.initial_admitted_settlement_blocked(p_scan)
   AND lifecycle='pending_pre_dispatch' AND admission.owner_id=p_owner AND quota.user_id=p_owner$body$);
 SELECT pg_get_functiondef('internal.guard_initial_lifecycle_fence()'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$ ELSIF TG_OP='UPDATE' THEN$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'initial admitted lifecycle update drift';
 END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
  IF OLD.state='pending_pre_dispatch' AND NEW.state='cancelled_pre_dispatch'
   AND internal.initial_admitted_settlement_blocked(OLD.scan_id) THEN
   RAISE EXCEPTION 'initial_analysis_lifecycle_immutable' USING ERRCODE='22023';
  END IF;
$body$);
 -- Generic service finalization is not admitted C1 or dispatch authority. Lock
 -- and resolve the real reservation before rejecting every settlement state.
 SELECT pg_get_functiondef('internal.finalize_ai_quota_reservation_core(uuid,uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    -- Read the wall clock only after the row-lock wait.';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'initial admitted quota finalizer drift';
 END IF;
 EXECUTE replace(definition,anchor,$body$    IF internal.initial_admitted_settlement_blocked(reservation_row.original_analysis_id)
       OR internal.initial_admitted_settlement_blocked(reservation_row.request_id) THEN
        RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000';
    END IF;

$body$||anchor);
 SELECT pg_get_functiondef('internal.settle_complimentary_analysis(uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$    IF FOUND AND usage_row.state='held' THEN$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'initial admitted complimentary settlement drift';
 END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
        IF internal.initial_admitted_settlement_blocked(p_analysis) THEN
            RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000';
        END IF;
$body$);
END; $admitted_cancellation_fence$;

-- Private transaction-local prestate capture only. No returned value, lock or
-- successful predicate authorizes settlement, lifecycle mutation or erasure.
-- The dedicated C1 transition protocol is intentionally not installed here.
CREATE FUNCTION internal.capture_initial_admitted_cancellation_prestate(p_owner UUID,p_scan UUID)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE admitted internal.initial_analysis_admissions;
    receipt internal.initial_preparation_admission_receipts;
    quota internal.ai_quota_reservations;
    attempt internal.identification_provider_attempts;
    charge internal.ai_quota_reservation_counters;
    counter_row internal.ai_quota_counters;
    usage_row internal.complimentary_scan_usage;
    charges JSONB:='[]'::JSONB; source_rows JSONB; destination_rows JSONB;
    source_fence JSONB; media_fence JSONB; media_cohort JSONB; owner_epoch JSONB;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
    PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
    SELECT * INTO admitted FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
    IF NOT FOUND OR admitted.owner_id IS DISTINCT FROM p_owner OR admitted.binding_version IS DISTINCT FROM 3
        OR internal.initial_admission_sealed()
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan)
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan AND state='pending_pre_dispatch') THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO quota FROM internal.ai_quota_reservations WHERE id=admitted.funding_binding_id FOR UPDATE;
    IF NOT FOUND OR quota.user_id IS DISTINCT FROM p_owner OR quota.request_id IS DISTINCT FROM p_scan
        OR quota.original_analysis_id IS DISTINCT FROM p_scan THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO attempt FROM internal.identification_provider_attempts
        WHERE reservation_id=quota.id AND attempt_count=1 FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
    -- Match release_ai_quota_reservation_counters' daily -> user -> IP order.
    -- The reservation lock precedes link/counter locks and usage follows them.
    FOR charge IN SELECT * FROM internal.ai_quota_reservation_counters l WHERE l.reservation_id=quota.id
        ORDER BY CASE l.scope_type WHEN 'user_daily' THEN 1 WHEN 'user_rate' THEN 2 WHEN 'ip_rate' THEN 3 ELSE 4 END,
            l.scope_key,l.bucket,l.window_start FOR UPDATE LOOP
        SELECT * INTO counter_row FROM internal.ai_quota_counters c
            WHERE c.scope_type=charge.scope_type AND c.scope_key=charge.scope_key
                AND c.bucket=charge.bucket AND c.window_start=charge.window_start FOR UPDATE;
        IF NOT FOUND OR counter_row.request_count<1 THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        charges:=charges||jsonb_build_array(jsonb_build_object('link',to_jsonb(charge),'counter',to_jsonb(counter_row),'release_delta',1));
    END LOOP;
    SELECT * INTO usage_row FROM internal.complimentary_scan_usage
        WHERE user_id=p_owner AND client_scan_id=p_scan FOR UPDATE;
    SELECT jsonb_build_object('id',u.id,'entitlement_version',u.entitlement_version,
        'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch) INTO owner_epoch
        FROM public.users u WHERE u.id=p_owner;
    -- All preparation source and prepared-output objects share this registry.
    PERFORM scan_id FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
    SELECT * INTO receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan FOR UPDATE;
    IF NOT FOUND OR receipt.owner_id IS DISTINCT FROM p_owner THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM scan_id FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_output_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan FOR UPDATE;
    -- No transfer owner/table is installed. Future transfer adds its locked
    -- receipt before M1; absence of progress must never be inferred as transfer.
    PERFORM scan_id FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_verifications WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
    -- Retained integrity and live unused evidence are distinct requirements.
    PERFORM internal.initial_admission_retained_receipt(p_owner,p_scan,receipt.admission_receipt_id);
    PERFORM internal.assert_initial_admission_live_receipt(p_owner,p_scan,receipt.admission_receipt_id);
    IF EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan OR reservation_id=quota.id)
        OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
        OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
        OR EXISTS(SELECT 1 FROM public.scans WHERE id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY object_id),'[]') INTO source_rows
        FROM internal.initial_preparation_source_registry r WHERE scan_id=p_scan;
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY object_id),'[]') INTO destination_rows
        FROM internal.initial_analysis_media_registry r WHERE scan_id=p_scan;
    SELECT to_jsonb(f) INTO source_fence FROM internal.initial_preparation_source_fences f WHERE scan_id=p_scan;
    SELECT to_jsonb(f) INTO media_fence FROM internal.initial_analysis_media_allocation_fences f WHERE scan_id=p_scan;
    SELECT to_jsonb(c) INTO media_cohort FROM internal.initial_analysis_media_cohorts c WHERE scan_id=p_scan;
    RETURN jsonb_build_object('version',1,'authority','none','transaction_id',pg_catalog.pg_current_xact_id()::TEXT,
        'owner_id',p_owner,'scan_id',p_scan,'admission_receipt_id',receipt.admission_receipt_id,
        'admission_receipt_digest',receipt.receipt_digest,'quota',to_jsonb(quota),'attempt',to_jsonb(attempt),
        'charges',charges,'complimentary',CASE WHEN usage_row.client_scan_id IS NULL THEN 'null'::JSONB ELSE to_jsonb(usage_row) END,'owner_epoch',owner_epoch,
        'source_fence',source_fence,'source_registry',source_rows,'media_fence',media_fence,
        'media_cohort',media_cohort,'destination_registry',destination_rows,
        'private_components',jsonb_build_object('admission',to_jsonb(admitted),'receipt',to_jsonb(receipt),
            'intent',(SELECT to_jsonb(t) FROM internal.initial_analysis_preparation_intents t WHERE scan_id=p_scan),
            'submission',(SELECT to_jsonb(t) FROM internal.initial_analysis_submissions t WHERE scan_id=p_scan),
            'source_verification',(SELECT to_jsonb(t) FROM internal.initial_preparation_source_verifications t WHERE scan_id=p_scan),
            'execution_grant',(SELECT to_jsonb(t) FROM internal.initial_preparation_execution_grants t WHERE scan_id=p_scan),
            'output_manifest',(SELECT to_jsonb(t) FROM internal.initial_preparation_output_manifests t WHERE scan_id=p_scan),
            'output_mapping',(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY ordinal),'[]') FROM internal.initial_preparation_output_mapping t WHERE scan_id=p_scan),
            'outcome',(SELECT to_jsonb(t) FROM internal.initial_preparation_outcomes t WHERE scan_id=p_scan)),
        'lifecycle',(SELECT to_jsonb(t) FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=p_scan));
END;
$$;
REVOKE ALL ON FUNCTION internal.capture_initial_admitted_cancellation_prestate(UUID,UUID)
    FROM PUBLIC,anon,authenticated,service_role;

-- Comparison only, never settlement or terminal authority. The future closed C1
-- owner must obtain the prestate itself and bind both timestamps to observed
-- original-owner transitions. Caller-supplied JSON/timestamps or xid equality
-- cannot establish that provenance. This helper grants no guard exception.
CREATE FUNCTION internal.assert_initial_admitted_cancellation_settlement(
    p_before JSONB,p_quota_settled_at TIMESTAMPTZ,p_credit_settled_at TIMESTAMPTZ)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE owner_id UUID; scan UUID; reservation UUID; expected JSONB; actual JSONB;
    charge JSONB; previous_counter internal.ai_quota_counters; original_links JSONB; seen_links JSONB:='[]'::JSONB;
    retained internal.initial_preparation_admission_receipts;
    hold JSONB; epoch BIGINT; entitlement BIGINT;
BEGIN
    IF p_before IS NULL OR jsonb_typeof(p_before) IS DISTINCT FROM 'object'
        OR p_before->>'version' IS DISTINCT FROM '1' OR p_before->>'authority' IS DISTINCT FROM 'none'
        OR p_before->>'transaction_id' IS DISTINCT FROM pg_catalog.pg_current_xact_id()::TEXT
        OR p_quota_settled_at IS NULL OR NOT pg_catalog.isfinite(p_quota_settled_at)
        OR p_quota_settled_at<pg_catalog.transaction_timestamp()
        OR jsonb_typeof(p_before->'quota') IS DISTINCT FROM 'object'
        OR jsonb_typeof(p_before->'attempt') IS DISTINCT FROM 'object'
        OR jsonb_typeof(p_before->'charges') IS DISTINCT FROM 'array'
        OR NOT p_before ? 'complimentary' THEN
        RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
    END IF;
    owner_id:=(p_before->>'owner_id')::UUID;
    scan:=(p_before->>'scan_id')::UUID;
    reservation:=(p_before#>>'{quota,id}')::UUID;
    IF owner_id IS NULL OR scan IS NULL OR reservation IS NULL
        OR p_before#>>'{quota,user_id}' IS DISTINCT FROM owner_id::TEXT
        OR p_before#>>'{quota,request_id}' IS DISTINCT FROM scan::TEXT
        OR p_before#>>'{quota,original_analysis_id}' IS DISTINCT FROM scan::TEXT
        OR p_before#>>'{quota,state}' IS DISTINCT FROM 'reserved'
        OR p_before#>>'{quota,refund_count}' IS DISTINCT FROM '0' THEN
        RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
    END IF;
    expected:=p_before->'quota'||jsonb_build_object('state','refunded','refund_count',1,
        'refunded_at',p_quota_settled_at,'updated_at',p_quota_settled_at);
    SELECT to_jsonb(q) INTO actual FROM internal.ai_quota_reservations q WHERE id=reservation;
    IF actual IS DISTINCT FROM expected
        OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters WHERE reservation_id=reservation)
        OR (SELECT count(*) FROM internal.identification_provider_attempts WHERE reservation_id=reservation)<>1
        OR (SELECT to_jsonb(a) FROM internal.identification_provider_attempts a
            WHERE reservation_id=reservation AND attempt_count=1) IS DISTINCT FROM p_before->'attempt' THEN
        RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
    END IF;
    -- The immutable retained receipt supplies the complete original link set.
    -- This prevents an omitted/duplicated/foreign entry from shrinking the
    -- comparison, but does not attest mutable counter preimages or provenance.
    SELECT * INTO retained FROM internal.initial_preparation_admission_receipts WHERE scan_id=scan;
    IF NOT FOUND OR to_jsonb(retained) IS DISTINCT FROM p_before#>'{private_components,receipt}' THEN
        RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.initial_admission_retained_receipt(owner_id,scan,retained.admission_receipt_id);
    original_links:=retained.accounting::JSONB#>'{charges,links}';
    IF jsonb_array_length(p_before->'charges') IS DISTINCT FROM jsonb_array_length(original_links) THEN
        RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
    END IF;
    FOR charge IN SELECT value FROM jsonb_array_elements(p_before->'charges') LOOP
        IF charge->>'release_delta' IS DISTINCT FROM '1'
            OR charge#>>'{link,reservation_id}' IS DISTINCT FROM reservation::TEXT
            OR jsonb_typeof(charge->'counter') IS DISTINCT FROM 'object' THEN
            RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
        END IF;
        IF seen_links @> jsonb_build_array(charge->'link')
            OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(original_links) l
                WHERE to_jsonb(jsonb_populate_record(NULL::internal.ai_quota_reservation_counters,l-'window_seconds'-'delta'))=charge->'link'
                    AND l->'window_seconds'=charge#>'{counter,window_seconds}' AND l->>'delta'='1')
            OR ((charge->'link')-'reservation_id') IS DISTINCT FROM jsonb_build_object(
                'scope_type',charge#>'{counter,scope_type}','scope_key',charge#>'{counter,scope_key}',
                'bucket',charge#>'{counter,bucket}','window_start',charge#>'{counter,window_start}') THEN
            RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
        END IF;
        seen_links:=seen_links||jsonb_build_array(charge->'link');
        previous_counter:=jsonb_populate_record(NULL::internal.ai_quota_counters,charge->'counter');
        IF previous_counter.request_count IS NULL OR previous_counter.request_count<1 THEN
            RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
        END IF;
        SELECT to_jsonb(c) INTO actual FROM internal.ai_quota_counters c
            WHERE c.scope_type=previous_counter.scope_type AND c.scope_key=previous_counter.scope_key
                AND c.bucket=previous_counter.bucket AND c.window_start=previous_counter.window_start;
        IF previous_counter.request_count=1 THEN
            IF actual IS NOT NULL THEN RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000'; END IF;
        ELSE
            expected:=charge->'counter'||jsonb_build_object('request_count',previous_counter.request_count-1,
                'updated_at',pg_catalog.transaction_timestamp());
            IF actual IS DISTINCT FROM expected THEN
                RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
            END IF;
        END IF;
    END LOOP;
    hold:=p_before->'complimentary';
    epoch:=(p_before#>>'{owner_epoch,complimentary_entitlement_epoch}')::BIGINT;
    entitlement:=(p_before#>>'{owner_epoch,entitlement_version}')::BIGINT;
    IF epoch IS NULL OR entitlement IS NULL THEN RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000'; END IF;
    IF hold='null'::JSONB THEN
        IF p_credit_settled_at IS NOT NULL OR p_before#>'{quota,complimentary_client_scan_id}' IS DISTINCT FROM 'null'::JSONB
            OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=scan) THEN
            RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
        END IF;
    ELSE
        IF jsonb_typeof(hold) IS DISTINCT FROM 'object' OR hold->>'state' IS DISTINCT FROM 'held'
            OR hold->>'user_id' IS DISTINCT FROM owner_id::TEXT OR hold->>'client_scan_id' IS DISTINCT FROM scan::TEXT
            OR p_before#>>'{quota,complimentary_client_scan_id}' IS DISTINCT FROM scan::TEXT
            OR p_credit_settled_at IS NULL OR NOT pg_catalog.isfinite(p_credit_settled_at)
            OR p_credit_settled_at<p_quota_settled_at THEN
            RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
        END IF;
        expected:=hold||jsonb_build_object('state','released','settlement_reason','cancelled_before_dispatch',
            'settled_at',p_credit_settled_at,'updated_at',p_credit_settled_at);
        SELECT to_jsonb(u) INTO actual FROM internal.complimentary_scan_usage u WHERE user_id=owner_id AND client_scan_id=scan;
        IF actual IS DISTINCT FROM expected OR (SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id=scan)<>1 THEN
            RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
        END IF;
        epoch:=epoch+1;
        -- The existing users trigger folds each real epoch transition into the
        -- public monotonic entitlement version; both advance exactly once.
        entitlement:=entitlement+1;
    END IF;
    expected:=p_before->'owner_epoch'||jsonb_build_object('complimentary_entitlement_epoch',epoch,'entitlement_version',entitlement);
    SELECT jsonb_build_object('id',u.id,'entitlement_version',u.entitlement_version,
        'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch) INTO actual FROM public.users u WHERE id=owner_id;
    IF actual IS DISTINCT FROM expected THEN
        RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
    END IF;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR invalid_parameter_value THEN
    RAISE EXCEPTION 'initial_analysis_settlement_incomplete' USING ERRCODE='55000';
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_initial_admitted_cancellation_settlement(JSONB,TIMESTAMPTZ,TIMESTAMPTZ)
    FROM PUBLIC,anon,authenticated,service_role;

-- C1 entry only. This private proof is transaction-local and never authorizes
-- settlement. Until the complete terminal protocol is installed, every entry
-- must roll back: deletion cannot discharge the deferred completion obligation.
CREATE TABLE internal.initial_admitted_cancellation_staging (
    scan_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    transaction_id XID8 NOT NULL UNIQUE,
    phase TEXT NOT NULL DEFAULT 'captured' CHECK (phase IN ('captured','quota')),
    quota_at TIMESTAMPTZ,
    prestate JSONB NOT NULL CHECK (jsonb_typeof(prestate)='object'
        AND octet_length(prestate::TEXT)<=67108864)
);
ALTER TABLE internal.initial_admitted_cancellation_staging ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_admitted_cancellation_staging FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_initial_admitted_cancellation_entry()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF TG_OP='DELETE' THEN
        PERFORM internal.check_initial_cancellation_cleanup_member(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,to_jsonb(OLD),FALSE);
        RETURN OLD;
    END IF;
    PERFORM internal.require_service_role();
    IF TG_OP='UPDATE' THEN
        IF OLD.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
            OR OLD.phase IS DISTINCT FROM 'captured' OR NEW.phase IS DISTINCT FROM 'quota'
            OR OLD.quota_at IS NOT NULL OR NEW.quota_at IS NOT NULL
            OR to_jsonb(OLD)-'phase' IS DISTINCT FROM to_jsonb(NEW)-'phase'
            OR OLD.prestate IS DISTINCT FROM internal.capture_initial_admitted_cancellation_prestate(OLD.owner_id,OLD.scan_id) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        -- The existing finalizer's sampling expression enters this transition.
        -- No caller timestamp is accepted; every derived field remains frozen.
        NEW.quota_at:=pg_catalog.clock_timestamp();
        RETURN NEW;
    ELSIF TG_OP<>'INSERT' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    -- Only owner/scan are inputs. Neither correct-looking JSON nor a current xid
    -- may be supplied. Capture itself obtains/rechecks the complete lock scope.
    IF NEW.scan_id IS NULL OR NEW.owner_id IS NULL OR NEW.transaction_id IS NOT NULL
        OR NEW.prestate IS NOT NULL OR NEW.phase IS DISTINCT FROM 'captured' OR NEW.quota_at IS NOT NULL OR EXISTS(
            SELECT 1 FROM internal.initial_admitted_cancellation_staging
            WHERE transaction_id=pg_catalog.pg_current_xact_id()) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    NEW.prestate:=internal.capture_initial_admitted_cancellation_prestate(NEW.owner_id,NEW.scan_id);
    NEW.transaction_id:=pg_catalog.pg_current_xact_id();
    RETURN NEW;
END;
$$;
CREATE TRIGGER guard_initial_admitted_cancellation_entry BEFORE INSERT OR UPDATE OR DELETE
    ON internal.initial_admitted_cancellation_staging FOR EACH ROW
    EXECUTE FUNCTION internal.guard_initial_admitted_cancellation_entry();
CREATE TRIGGER guard_initial_admitted_cancellation_entry_truncate BEFORE TRUNCATE
    ON internal.initial_admitted_cancellation_staging FOR EACH STATEMENT
    EXECUTE FUNCTION internal.guard_initial_admitted_cancellation_entry();

CREATE FUNCTION internal.require_complete_initial_admitted_cancellation()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    -- Deliberately unconditional while no reviewed terminal owner exists. It
    -- must not infer completion from an absent stage, lifecycle flag or GUC.
    RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
END;
$$;
CREATE CONSTRAINT TRIGGER require_complete_initial_admitted_cancellation
    AFTER INSERT ON internal.initial_admitted_cancellation_staging
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION internal.require_complete_initial_admitted_cancellation();
REVOKE ALL ON FUNCTION internal.guard_initial_admitted_cancellation_entry(),
    internal.require_complete_initial_admitted_cancellation() FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE internal.initial_admitted_cancellation_staging IS
 'Private C1 transaction-only prestate captured by guarded insertion. No settlement authority, no public owner, no successful commit or deletion until the terminal protocol is implemented. Never log, transport or reuse the private snapshot.';

-- Bind the existing original finalizer's post-lock sampling site without
-- changing its defensive admitted-settlement fence. A sampled clock alone is
-- not a transition witness or refund authority; the stage still cannot commit.
CREATE FUNCTION internal.sample_initial_cancellation_quota_clock(
    p_reservation UUID,p_owner UUID,p_lease UUID,p_final_state TEXT)
RETURNS TIMESTAMPTZ LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; sampled TIMESTAMPTZ;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging
        WHERE transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND THEN RETURN pg_catalog.clock_timestamp(); END IF;
    IF stage.phase IS DISTINCT FROM 'captured' OR stage.quota_at IS NOT NULL
        OR stage.owner_id IS DISTINCT FROM p_owner OR p_final_state IS DISTINCT FROM 'refunded'
        OR stage.prestate#>>'{quota,id}' IS DISTINCT FROM p_reservation::TEXT
        OR stage.prestate#>>'{quota,lease_token}' IS DISTINCT FROM p_lease::TEXT
        OR stage.prestate#>>'{quota,state}' IS DISTINCT FROM 'reserved' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    UPDATE internal.initial_admitted_cancellation_staging SET phase='quota'
        WHERE scan_id=stage.scan_id RETURNING quota_at INTO sampled;
    IF NOT FOUND OR sampled IS NULL THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    RETURN sampled;
END;
$$;
REVOKE ALL ON FUNCTION internal.sample_initial_cancellation_quota_clock(UUID,UUID,UUID,TEXT)
    FROM PUBLIC,anon,authenticated,service_role;
DO $c1_quota_clock$
DECLARE definition TEXT; anchor TEXT:='    quota_now := pg_catalog.CLOCK_TIMESTAMP();';
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.finalize_ai_quota_reservation_core(uuid,uuid,uuid,text)'::REGPROCEDURE)
        INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial cancellation quota clock owner drift';
    END IF;
    EXECUTE replace(definition,anchor,
        '    quota_now := internal.sample_initial_cancellation_quota_clock(p_reservation_id,p_user_id,p_lease_token,p_final_state);');
END;
$c1_quota_clock$;

-- Closed quota statement protocol. This is transaction-only evidence, not an
-- action exception or SQL call-stack attestation. A migration administrator can
-- deliberately assemble equivalent registered SQL; API roles cannot register.
CREATE TABLE internal.initial_cancellation_quota_statements (
    scan_id UUID NOT NULL,
    ordinal INTEGER NOT NULL CHECK (ordinal BETWEEN 0 AND 7),
    statement_key TEXT NOT NULL,
    link_identity JSONB,
    expected JSONB NOT NULL,
    observed JSONB NOT NULL DEFAULT '[]',
    closed BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY(scan_id,ordinal),
    CHECK (jsonb_typeof(expected)='array' AND jsonb_array_length(expected)<=3),
    CHECK (jsonb_typeof(observed)='array' AND jsonb_array_length(observed)<=3)
);
ALTER TABLE internal.initial_cancellation_quota_statements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_cancellation_quota_statements FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_cancellation_quota_contract(
    p_stage internal.initial_admitted_cancellation_staging,p_ordinal INTEGER)
RETURNS TABLE(statement_key TEXT,link_identity JSONB,expected JSONB)
LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE charges JSONB:=p_stage.prestate->'charges'; n INTEGER; c JSONB; after_counter JSONB;
BEGIN
    IF p_stage.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
        OR p_stage.phase IS DISTINCT FROM 'quota' OR p_stage.quota_at IS NULL
        OR jsonb_typeof(charges) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    n:=jsonb_array_length(charges);
    IF n>3 OR p_ordinal IS NULL OR p_ordinal<0 OR p_ordinal>2*n+1 THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    expected:='[]'; link_identity:=NULL;
    IF p_ordinal<2*n THEN
        c:=charges->(p_ordinal/2); link_identity:=c->'link';
        after_counter:=(c->'counter')||jsonb_build_object(
            'request_count',(c#>>'{counter,request_count}')::INTEGER-1,'updated_at',transaction_timestamp());
        IF p_ordinal%2=0 THEN
            statement_key:='counter.update';
            expected:=jsonb_build_array(jsonb_build_object('relation','internal.ai_quota_counters',
                'operation','UPDATE','old',c->'counter','new',after_counter));
        ELSE
            statement_key:='counter.delete';
            IF c#>>'{counter,request_count}'='1' THEN
                expected:=jsonb_build_array(jsonb_build_object('relation','internal.ai_quota_counters',
                    'operation','DELETE','old',after_counter,'new',NULL));
            END IF;
        END IF;
    ELSIF p_ordinal=2*n THEN
        statement_key:='links.delete';
        SELECT COALESCE(jsonb_agg(jsonb_build_object('relation','internal.ai_quota_reservation_counters',
            'operation','DELETE','old',value->'link','new',NULL)),'[]') INTO expected
            FROM jsonb_array_elements(charges);
    ELSE
        statement_key:='quota.refund';
        expected:=jsonb_build_array(jsonb_build_object('relation','internal.ai_quota_reservations','operation','UPDATE',
            'old',p_stage.prestate->'quota','new',(p_stage.prestate->'quota')||jsonb_build_object(
                'state','refunded','refund_count',1,'refunded_at',p_stage.quota_at,'updated_at',p_stage.quota_at)));
    END IF;
    RETURN NEXT;
END; $$;

CREATE FUNCTION internal.guard_initial_cancellation_quota_statement()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; contract RECORD; next_ordinal INTEGER; event JSONB;
BEGIN
    IF TG_OP='DELETE' THEN
        PERFORM internal.check_initial_cancellation_cleanup_member(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,to_jsonb(OLD),FALSE);
        RETURN OLD;
    END IF;
    PERFORM internal.require_service_role();
    IF TG_OP NOT IN ('INSERT','UPDATE') THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging
        WHERE scan_id=NEW.scan_id AND transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND OR stage.phase IS DISTINCT FROM 'quota' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_OP='INSERT' THEN
        IF NEW.ordinal IS NOT NULL OR NEW.expected IS NOT NULL OR NEW.observed IS DISTINCT FROM '[]'::JSONB
            OR NEW.closed IS DISTINCT FROM FALSE OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements
                WHERE scan_id=stage.scan_id AND NOT closed) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        SELECT count(*)::INTEGER INTO next_ordinal FROM internal.initial_cancellation_quota_statements WHERE scan_id=stage.scan_id;
        SELECT * INTO STRICT contract FROM internal.initial_cancellation_quota_contract(stage,next_ordinal);
        IF NEW.statement_key IS DISTINCT FROM contract.statement_key OR NEW.link_identity IS DISTINCT FROM contract.link_identity THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        NEW.ordinal:=next_ordinal; NEW.expected:=contract.expected;
    ELSE
        IF OLD.closed OR to_jsonb(OLD)-ARRAY['observed','closed'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['observed','closed'] THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        IF NEW.closed THEN
            IF NEW.observed IS DISTINCT FROM OLD.observed
                OR jsonb_array_length(OLD.observed)<>jsonb_array_length(OLD.expected)
                OR NOT OLD.observed @> OLD.expected OR NOT OLD.expected @> OLD.observed THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
        ELSE
            event:=NEW.observed->(jsonb_array_length(NEW.observed)-1);
            IF pg_catalog.pg_trigger_depth()<2 OR event IS NULL
                OR NEW.observed IS DISTINCT FROM OLD.observed||jsonb_build_array(event)
                OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(OLD.expected) x WHERE x.value=event)
                OR EXISTS(SELECT 1 FROM jsonb_array_elements(OLD.observed) x WHERE x.value=event) THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER guard_initial_cancellation_quota_statement BEFORE INSERT OR UPDATE OR DELETE
    ON internal.initial_cancellation_quota_statements FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_quota_statement();
CREATE TRIGGER guard_initial_cancellation_quota_statement_truncate BEFORE TRUNCATE
    ON internal.initial_cancellation_quota_statements FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_quota_statement();

CREATE FUNCTION internal.begin_initial_cancellation_quota_statement(p_reservation UUID,p_key TEXT,p_link JSONB)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND THEN RETURN; END IF;
    IF stage.prestate#>>'{quota,id}' IS DISTINCT FROM p_reservation::TEXT THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    INSERT INTO internal.initial_cancellation_quota_statements(scan_id,statement_key,link_identity)
        VALUES(stage.scan_id,p_key,p_link);
END; $$;
CREATE FUNCTION internal.end_initial_cancellation_quota_statement(p_reservation UUID,p_key TEXT)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND THEN RETURN; END IF;
    IF stage.prestate#>>'{quota,id}' IS DISTINCT FROM p_reservation::TEXT THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    UPDATE internal.initial_cancellation_quota_statements SET closed=TRUE
        WHERE scan_id=stage.scan_id AND statement_key=p_key AND NOT closed;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
END; $$;

CREATE FUNCTION internal.guard_initial_cancellation_quota_member()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; pending internal.initial_cancellation_quota_statements; event JSONB;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND OR stage.phase<>'quota' THEN
        IF TG_OP='TRUNCATE' THEN RETURN NULL; END IF;
        IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    event:=jsonb_build_object('relation',TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,'operation',TG_OP,
        'old',CASE WHEN TG_OP<>'INSERT' THEN to_jsonb(OLD) END,'new',CASE WHEN TG_OP<>'DELETE' THEN to_jsonb(NEW) END);
    SELECT * INTO pending FROM internal.initial_cancellation_quota_statements WHERE scan_id=stage.scan_id AND NOT closed;
    IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(pending.expected) x WHERE x.value=event)
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(pending.observed) x WHERE x.value=event) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_WHEN='AFTER' THEN
        UPDATE internal.initial_cancellation_quota_statements SET observed=observed||jsonb_build_array(event)
            WHERE scan_id=pending.scan_id AND ordinal=pending.ordinal;
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END; $$;
DO $c1_members$
DECLARE relation_name TEXT;
BEGIN
    FOREACH relation_name IN ARRAY ARRAY['internal.ai_quota_counters','internal.ai_quota_reservation_counters','internal.ai_quota_reservations'] LOOP
        EXECUTE format('CREATE TRIGGER a1_initial_cancellation_quota BEFORE INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_quota_member()',relation_name);
        EXECUTE format('CREATE TRIGGER a1_initial_cancellation_quota_truncate BEFORE TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_quota_member()',relation_name);
        EXECUTE format('CREATE TRIGGER z9_initial_cancellation_quota AFTER INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_quota_member()',relation_name);
    END LOOP;
END; $c1_members$;
REVOKE ALL ON FUNCTION internal.initial_cancellation_quota_contract(internal.initial_admitted_cancellation_staging,INTEGER),
    internal.guard_initial_cancellation_quota_statement(),internal.begin_initial_cancellation_quota_statement(UUID,TEXT,JSONB),
    internal.end_initial_cancellation_quota_statement(UUID,TEXT),internal.guard_initial_cancellation_quota_member()
    FROM PUBLIC,anon,authenticated,service_role;

-- Instrument existing DML verbatim. Anchors fail closed on owner source drift.
-- These owners do not consult FOUND after the instrumented statements.
DO $c1_quota_statements$
DECLARE definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
    SELECT pg_get_functiondef('internal.release_ai_quota_reservation_counters(uuid)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='        UPDATE internal.ai_quota_counters AS counters';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 counter update owner drift'; END IF;
    definition:=replace(definition,anchor,'        PERFORM internal.begin_initial_cancellation_quota_statement(p_reservation_id,''counter.update'',to_jsonb(counter_link));'||E'\n'||anchor);
    anchor:='        DELETE FROM internal.ai_quota_counters AS counters';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 counter delete owner drift'; END IF;
    definition:=replace(definition,anchor,'        PERFORM internal.end_initial_cancellation_quota_statement(p_reservation_id,''counter.update'');'||E'\n'||
        '        PERFORM internal.begin_initial_cancellation_quota_statement(p_reservation_id,''counter.delete'',to_jsonb(counter_link));'||E'\n'||anchor);
    anchor:='    END LOOP;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 counter loop owner drift'; END IF;
    definition:=replace(definition,anchor,'        PERFORM internal.end_initial_cancellation_quota_statement(p_reservation_id,''counter.delete'');'||E'\n'||anchor);
    anchor:='    DELETE FROM internal.ai_quota_reservation_counters AS links';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 links owner drift'; END IF;
    definition:=replace(definition,anchor,'    PERFORM internal.begin_initial_cancellation_quota_statement(p_reservation_id,''links.delete'',NULL);'||E'\n'||anchor);
    anchor:='    WHERE links.reservation_id = p_reservation_id;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 links finish owner drift'; END IF;
    definition:=replace(definition,anchor,anchor||E'\n'||'    PERFORM internal.end_initial_cancellation_quota_statement(p_reservation_id,''links.delete'');');
    EXECUTE definition;
    SELECT pg_get_functiondef('internal.finalize_ai_quota_reservation_core(uuid,uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    anchor:=E'        UPDATE internal.ai_quota_reservations AS reservations\n        SET\n            state = ''refunded'',';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 quota refund owner drift'; END IF;
    definition:=replace(definition,anchor,'        PERFORM internal.begin_initial_cancellation_quota_statement(p_reservation_id,''quota.refund'',NULL);'||E'\n'||anchor);
    anchor:=E'            refunded_at = quota_now,\n            updated_at = quota_now\n        WHERE reservations.id = p_reservation_id;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 quota finish owner drift'; END IF;
    definition:=replace(definition,anchor,anchor||E'\n'||'        PERFORM internal.end_initial_cancellation_quota_statement(p_reservation_id,''quota.refund'');');
    EXECUTE definition;
END; $c1_quota_statements$;

-- Separate credit evidence leaves the C1 stage in quota phase, so completed
-- quota members stay guarded while credit and later terminal work proceeds.
CREATE TABLE internal.initial_cancellation_credit_witness (
    scan_id UUID PRIMARY KEY,
    held BOOLEAN NOT NULL,
    credit_at TIMESTAMPTZ,
    phase TEXT NOT NULL DEFAULT 'sampled' CHECK (phase IN ('sampled','hold_pending','hold_observed','hold_done',
        'owner_pending','owner_observed','owner_done','complete')),
    events JSONB NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(events)='array' AND jsonb_array_length(events)<=2),
    CHECK (held=(credit_at IS NOT NULL))
);
ALTER TABLE internal.initial_cancellation_credit_witness ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_cancellation_credit_witness FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_cancellation_credit_event(
    p_stage internal.initial_admitted_cancellation_staging,p_credit internal.initial_cancellation_credit_witness,p_key TEXT)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE before_image JSONB; after_image JSONB; relation_name TEXT;
BEGIN
    IF NOT p_credit.held OR p_credit.credit_at IS NULL OR p_credit.scan_id IS DISTINCT FROM p_stage.scan_id THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF p_key='hold.release' THEN
        relation_name:='internal.complimentary_scan_usage'; before_image:=p_stage.prestate->'complimentary';
        after_image:=before_image||jsonb_build_object('state','released','settlement_reason','cancelled_before_dispatch',
            'settled_at',p_credit.credit_at,'updated_at',p_credit.credit_at);
    ELSIF p_key='owner.epoch' THEN
        relation_name:='public.users'; before_image:=p_stage.prestate->'owner_epoch';
        after_image:=before_image||jsonb_build_object(
            'complimentary_entitlement_epoch',(before_image->>'complimentary_entitlement_epoch')::BIGINT+1,
            'entitlement_version',(before_image->>'entitlement_version')::BIGINT+1);
    ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    RETURN jsonb_build_object('relation',relation_name,'operation','UPDATE','old',before_image,'new',after_image);
END; $$;

CREATE FUNCTION internal.guard_initial_cancellation_credit_witness()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; actual_hold JSONB; actual_owner JSONB; expected_event JSONB;
BEGIN
    IF TG_OP='DELETE' THEN
        PERFORM internal.check_initial_cancellation_cleanup_member(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,to_jsonb(OLD),FALSE);
        RETURN OLD;
    END IF;
    PERFORM internal.require_service_role();
    IF TG_OP NOT IN ('INSERT','UPDATE') THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging
        WHERE scan_id=NEW.scan_id AND transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND OR stage.phase IS DISTINCT FROM 'quota' OR stage.quota_at IS NULL THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_OP='INSERT' THEN
        IF NEW.held IS NOT NULL OR NEW.credit_at IS NOT NULL OR NEW.phase IS DISTINCT FROM 'sampled'
            OR NEW.events IS DISTINCT FROM '[]'::JSONB
            OR (SELECT count(*) FROM internal.initial_cancellation_quota_statements WHERE scan_id=stage.scan_id AND closed)
                <>2*jsonb_array_length(stage.prestate->'charges')+2
            OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements WHERE scan_id=stage.scan_id AND NOT closed) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        SELECT to_jsonb(u) INTO actual_hold FROM internal.complimentary_scan_usage u WHERE user_id=stage.owner_id AND client_scan_id=stage.scan_id;
        SELECT jsonb_build_object('id',u.id,'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch,
            'entitlement_version',u.entitlement_version) INTO actual_owner FROM public.users u WHERE id=stage.owner_id;
        IF COALESCE(actual_hold,'null'::JSONB) IS DISTINCT FROM stage.prestate->'complimentary'
            OR actual_owner IS DISTINCT FROM stage.prestate->'owner_epoch' THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        NEW.held:=stage.prestate->'complimentary'<>'null'::JSONB;
        IF NEW.held THEN NEW.credit_at:=clock_timestamp(); END IF;
    ELSE
        IF OLD.phase='complete' OR to_jsonb(OLD)-ARRAY['phase','events'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['phase','events'] THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        IF (OLD.phase='hold_pending' AND NEW.phase='hold_observed') OR (OLD.phase='owner_pending' AND NEW.phase='owner_observed') THEN
            expected_event:=internal.initial_cancellation_credit_event(stage,OLD,
                CASE WHEN OLD.phase='hold_pending' THEN 'hold.release' ELSE 'owner.epoch' END);
            IF pg_trigger_depth()<2 OR NEW.events IS DISTINCT FROM OLD.events||jsonb_build_array(expected_event) THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
        ELSE
            IF NEW.events IS DISTINCT FROM OLD.events THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            IF NEW.phase='complete' AND ((NOT OLD.held AND OLD.phase='sampled' AND OLD.events='[]'::JSONB)
                OR (OLD.held AND OLD.phase='owner_done' AND jsonb_array_length(OLD.events)=2)) THEN
                PERFORM internal.assert_initial_admitted_cancellation_settlement(stage.prestate,stage.quota_at,OLD.credit_at);
            ELSIF NOT (OLD.held AND ((OLD.phase='sampled' AND NEW.phase='hold_pending')
                OR (OLD.phase='hold_observed' AND NEW.phase='hold_done')
                OR (OLD.phase='hold_done' AND NEW.phase='owner_pending')
                OR (OLD.phase='owner_observed' AND NEW.phase='owner_done'))) THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER guard_initial_cancellation_credit_witness BEFORE INSERT OR UPDATE OR DELETE
    ON internal.initial_cancellation_credit_witness FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_credit_witness();
CREATE TRIGGER guard_initial_cancellation_credit_witness_truncate BEFORE TRUNCATE
    ON internal.initial_cancellation_credit_witness FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_credit_witness();

CREATE FUNCTION internal.sample_initial_cancellation_credit_clock(p_owner UUID,p_scan UUID,p_failure TEXT)
RETURNS TIMESTAMPTZ LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; sampled TIMESTAMPTZ;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
    IF NOT FOUND THEN RETURN clock_timestamp(); END IF;
    IF stage.owner_id IS DISTINCT FROM p_owner OR stage.scan_id IS DISTINCT FROM p_scan
        OR p_failure IS DISTINCT FROM 'cancelled_before_dispatch'
        OR EXISTS(SELECT 1 FROM internal.initial_cancellation_credit_witness WHERE scan_id=stage.scan_id) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF stage.prestate->'complimentary'<>'null'::JSONB AND internal.initial_admitted_settlement_blocked(p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000';
    END IF;
    INSERT INTO internal.initial_cancellation_credit_witness(scan_id) VALUES(stage.scan_id) RETURNING credit_at INTO sampled;
    -- Absent credit is explicit; never invent a clock or a credit event.
    RETURN sampled;
END; $$;

CREATE FUNCTION internal.advance_initial_cancellation_credit(p_owner UUID,p_scan UUID,p_step TEXT)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; from_phase TEXT; to_phase TEXT;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
    IF NOT FOUND THEN RETURN; END IF;
    IF stage.owner_id IS DISTINCT FROM p_owner OR stage.scan_id IS DISTINCT FROM p_scan THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    from_phase:=CASE p_step WHEN 'hold.begin' THEN 'sampled' WHEN 'hold.end' THEN 'hold_observed'
        WHEN 'owner.begin' THEN 'hold_done' WHEN 'owner.end' THEN 'owner_observed' END;
    to_phase:=CASE p_step WHEN 'hold.begin' THEN 'hold_pending' WHEN 'hold.end' THEN 'hold_done'
        WHEN 'owner.begin' THEN 'owner_pending' WHEN 'owner.end' THEN 'owner_done' END;
    IF from_phase IS NULL THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    UPDATE internal.initial_cancellation_credit_witness SET phase=to_phase WHERE scan_id=stage.scan_id AND phase=from_phase;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
END; $$;
CREATE FUNCTION internal.finish_initial_cancellation_credit(p_owner UUID,p_scan UUID,p_consumed BOOLEAN,p_released BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
    IF NOT FOUND THEN RETURN; END IF;
    IF stage.owner_id IS DISTINCT FROM p_owner OR stage.scan_id IS DISTINCT FROM p_scan OR p_consumed IS DISTINCT FROM FALSE
        OR p_released IS DISTINCT FROM (stage.prestate->'complimentary'<>'null'::JSONB) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    UPDATE internal.initial_cancellation_credit_witness SET phase='complete' WHERE scan_id=stage.scan_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
END; $$;

-- Ordinary users writes run as API roles without private-stage SELECT. This
-- fixed trigger alone uses the trusted owner to inspect the private stage; it
-- has no API EXECUTE grant and exposes no snapshot or arbitrary SQL surface.
CREATE FUNCTION internal.guard_initial_cancellation_credit_member()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; credit internal.initial_cancellation_credit_witness;
    old_value JSONB; new_value JSONB; expected_event JSONB; event JSONB; next_phase TEXT;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
    IF NOT FOUND OR stage.phase<>'quota' THEN
        IF TG_OP='TRUNCATE' THEN RETURN NULL; ELSIF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    IF TG_OP<>'UPDATE' THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    SELECT * INTO credit FROM internal.initial_cancellation_credit_witness WHERE scan_id=stage.scan_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    old_value:=to_jsonb(OLD); new_value:=to_jsonb(NEW);
    IF TG_TABLE_SCHEMA='public' AND TG_TABLE_NAME='users' AND credit.phase='owner_pending' THEN
        -- Never retain unrelated user fields. Their live event must be unchanged.
        IF old_value-ARRAY['complimentary_entitlement_epoch','entitlement_version']
            IS DISTINCT FROM new_value-ARRAY['complimentary_entitlement_epoch','entitlement_version'] THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        SELECT jsonb_object_agg(key,value) INTO old_value FROM jsonb_each(old_value)
            WHERE key=ANY(ARRAY['id','complimentary_entitlement_epoch','entitlement_version']);
        SELECT jsonb_object_agg(key,value) INTO new_value FROM jsonb_each(new_value)
            WHERE key=ANY(ARRAY['id','complimentary_entitlement_epoch','entitlement_version']);
        expected_event:=internal.initial_cancellation_credit_event(stage,credit,'owner.epoch'); next_phase:='owner_observed';
    ELSIF TG_TABLE_SCHEMA='internal' AND TG_TABLE_NAME='complimentary_scan_usage' AND credit.phase='hold_pending' THEN
        expected_event:=internal.initial_cancellation_credit_event(stage,credit,'hold.release'); next_phase:='hold_observed';
    ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    event:=jsonb_build_object('relation',TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,'operation',TG_OP,'old',old_value,'new',new_value);
    IF event IS DISTINCT FROM expected_event THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    IF TG_WHEN='AFTER' THEN
        UPDATE internal.initial_cancellation_credit_witness SET phase=next_phase,events=events||jsonb_build_array(event) WHERE scan_id=stage.scan_id;
    END IF;
    RETURN NEW;
END; $$;
DO $c1_credit_members$
DECLARE relation_name TEXT;
BEGIN
    FOREACH relation_name IN ARRAY ARRAY['internal.complimentary_scan_usage','public.users'] LOOP
        -- Sort after the existing entitlement-version BEFORE trigger. AFTER
        -- independently verifies the actual winning image after all rewrites.
        EXECUTE format('CREATE TRIGGER z9_initial_cancellation_credit BEFORE INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_credit_member()',relation_name);
        EXECUTE format('CREATE TRIGGER z9_initial_cancellation_credit_after AFTER INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_credit_member()',relation_name);
        EXECUTE format('CREATE TRIGGER z9_initial_cancellation_credit_truncate BEFORE TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_credit_member()',relation_name);
    END LOOP;
END; $c1_credit_members$;
REVOKE ALL ON FUNCTION internal.initial_cancellation_credit_event(internal.initial_admitted_cancellation_staging,internal.initial_cancellation_credit_witness,TEXT),
    internal.guard_initial_cancellation_credit_witness(),internal.sample_initial_cancellation_credit_clock(UUID,UUID,TEXT),
    internal.advance_initial_cancellation_credit(UUID,UUID,TEXT),internal.finish_initial_cancellation_credit(UUID,UUID,BOOLEAN,BOOLEAN),
    internal.guard_initial_cancellation_credit_member() FROM PUBLIC,anon,authenticated,service_role;

DO $c1_credit_owner$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    SELECT pg_get_functiondef('internal.settle_complimentary_analysis(uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='    consumed BOOLEAN:=FALSE; released BOOLEAN:=FALSE; changed BOOLEAN:=FALSE; settled TIMESTAMPTZ;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 credit found declaration drift'; END IF;
    definition:=replace(definition,anchor,anchor||' usage_found BOOLEAN;');
    anchor:='    SELECT * INTO usage_row FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_analysis FOR UPDATE;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 credit lookup drift'; END IF;
    definition:=replace(definition,anchor,anchor||E'\n'||'    usage_found:=FOUND;');
    anchor:='    IF FOUND AND usage_row.state=''held'' THEN';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 credit held branch drift'; END IF;
    definition:=replace(definition,anchor,'    IF usage_found AND usage_row.state=''held'' THEN');
    anchor:='    ELSIF FOUND AND usage_row.state=''consumed'' AND p_failure IS NULL THEN consumed:=TRUE;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 credit consumed branch drift'; END IF;
    definition:=replace(definition,anchor,'    ELSIF usage_found AND usage_row.state=''consumed'' AND p_failure IS NULL THEN consumed:=TRUE;');
    anchor:='    settled:=clock_timestamp();';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 credit clock owner drift'; END IF;
    -- Snapshot lookup FOUND explicitly before instrumentation; preserve both legacy branches.
    definition:=replace(definition,anchor,'    settled:=internal.sample_initial_cancellation_credit_clock(p_owner,p_analysis,p_failure);');
    anchor:='            UPDATE internal.complimentary_scan_usage SET state=''released'',settled_at=settled,';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 credit release owner drift'; END IF;
    definition:=replace(definition,anchor,'            PERFORM internal.advance_initial_cancellation_credit(p_owner,p_analysis,''hold.begin'');'||E'\n'||anchor);
    anchor:='            released:=TRUE;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 credit release finish drift'; END IF;
    definition:=replace(definition,anchor,'            PERFORM internal.advance_initial_cancellation_credit(p_owner,p_analysis,''hold.end'');'||E'\n'||anchor);
    anchor:='    IF changed THEN UPDATE public.users SET complimentary_entitlement_epoch=complimentary_entitlement_epoch+1 WHERE id=p_owner; END IF;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 credit epoch owner drift'; END IF;
    definition:=replace(definition,anchor,E'    IF changed THEN\n        PERFORM internal.advance_initial_cancellation_credit(p_owner,p_analysis,''owner.begin'');\n        UPDATE public.users SET complimentary_entitlement_epoch=complimentary_entitlement_epoch+1 WHERE id=p_owner;\n        PERFORM internal.advance_initial_cancellation_credit(p_owner,p_analysis,''owner.end'');\n    END IF;');
    anchor:='    RETURN jsonb_build_object(''credit_consumed'',consumed,''credit_released'',released);';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 credit result owner drift'; END IF;
    definition:=replace(definition,anchor,'    PERFORM internal.finish_initial_cancellation_credit(p_owner,p_analysis,consumed,released);'||E'\n'||anchor);
    EXECUTE definition;
END; $c1_credit_owner$;

-- Lifecycle evidence only: the existing admitted transition fence is unchanged.
-- The stage remains quota so every completed accounting member stays protected.
CREATE TABLE internal.initial_cancellation_lifecycle_witness (
    scan_id UUID PRIMARY KEY,
    phase TEXT NOT NULL DEFAULT 'pending' CHECK (phase IN ('pending','observed','complete')),
    event JSONB
);
ALTER TABLE internal.initial_cancellation_lifecycle_witness ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_cancellation_lifecycle_witness FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_cancellation_lifecycle_event(p_stage internal.initial_admitted_cancellation_staging)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF p_stage.prestate#>>'{lifecycle,state}' IS DISTINCT FROM 'pending_pre_dispatch'
        OR p_stage.prestate#>>'{lifecycle,scan_id}' IS DISTINCT FROM p_stage.scan_id::TEXT THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    RETURN jsonb_build_object('relation','internal.initial_analysis_lifecycle_fences','operation','UPDATE',
        'old',p_stage.prestate->'lifecycle',
        'new',(p_stage.prestate->'lifecycle')||jsonb_build_object('state','cancelled_pre_dispatch'));
END; $$;

CREATE FUNCTION internal.guard_initial_cancellation_lifecycle_witness()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; credit internal.initial_cancellation_credit_witness;
    expected_event JSONB; actual JSONB;
BEGIN
    IF TG_OP='DELETE' THEN
        PERFORM internal.check_initial_cancellation_cleanup_member(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,to_jsonb(OLD),FALSE);
        RETURN OLD;
    END IF;
    PERFORM internal.require_service_role();
    IF TG_OP NOT IN ('INSERT','UPDATE') THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging
        WHERE scan_id=NEW.scan_id AND transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND OR stage.phase IS DISTINCT FROM 'quota' OR stage.quota_at IS NULL THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO credit FROM internal.initial_cancellation_credit_witness WHERE scan_id=stage.scan_id;
    IF NOT FOUND OR credit.phase IS DISTINCT FROM 'complete'
        OR (SELECT count(*) FROM internal.initial_cancellation_quota_statements WHERE scan_id=stage.scan_id AND closed)
            <>2*jsonb_array_length(stage.prestate->'charges')+2
        OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements WHERE scan_id=stage.scan_id AND NOT closed) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    expected_event:=internal.initial_cancellation_lifecycle_event(stage);
    SELECT to_jsonb(f) INTO actual FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=stage.scan_id;
    IF TG_OP='INSERT' THEN
        IF NEW.phase IS DISTINCT FROM 'pending' OR NEW.event IS NOT NULL
            OR actual IS DISTINCT FROM expected_event->'old'
            OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=stage.scan_id) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        -- Receipt-dependent accounting is checked before lifecycle or erasure.
        PERFORM internal.assert_initial_admitted_cancellation_settlement(stage.prestate,stage.quota_at,credit.credit_at);
    ELSE
        IF NEW.scan_id IS DISTINCT FROM OLD.scan_id OR actual IS DISTINCT FROM expected_event->'new' THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        IF OLD.phase='pending' AND NEW.phase='observed' THEN
            IF pg_trigger_depth()<2 OR OLD.event IS NOT NULL OR NEW.event IS DISTINCT FROM expected_event THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
        ELSIF OLD.phase='observed' AND NEW.phase='complete' THEN
            IF OLD.event IS DISTINCT FROM expected_event OR NEW.event IS DISTINCT FROM OLD.event THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
        ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER guard_initial_cancellation_lifecycle_witness BEFORE INSERT OR UPDATE OR DELETE
    ON internal.initial_cancellation_lifecycle_witness FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_lifecycle_witness();
CREATE TRIGGER guard_initial_cancellation_lifecycle_witness_truncate BEFORE TRUNCATE
    ON internal.initial_cancellation_lifecycle_witness FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_lifecycle_witness();

CREATE FUNCTION internal.advance_initial_cancellation_lifecycle(p_owner UUID,p_scan UUID,p_terminal TEXT,p_step TEXT)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND THEN RETURN; END IF;
    IF stage.owner_id IS DISTINCT FROM p_owner OR stage.scan_id IS DISTINCT FROM p_scan
        OR p_terminal IS DISTINCT FROM 'cancelled_pre_dispatch' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF p_step='begin' THEN
        IF EXISTS(SELECT 1 FROM internal.initial_cancellation_lifecycle_witness WHERE scan_id=stage.scan_id) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        INSERT INTO internal.initial_cancellation_lifecycle_witness(scan_id) VALUES(stage.scan_id);
    ELSIF p_step='end' THEN
        UPDATE internal.initial_cancellation_lifecycle_witness SET phase='complete' WHERE scan_id=stage.scan_id AND phase='observed';
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
END; $$;

CREATE FUNCTION internal.guard_initial_cancellation_lifecycle_member()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; witness internal.initial_cancellation_lifecycle_witness; observed_event JSONB;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND THEN
        IF TG_OP='TRUNCATE' THEN RETURN NULL; ELSIF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    IF TG_OP<>'UPDATE' OR stage.phase IS DISTINCT FROM 'quota' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO witness FROM internal.initial_cancellation_lifecycle_witness WHERE scan_id=stage.scan_id;
    IF NOT FOUND OR witness.phase IS DISTINCT FROM 'pending' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    observed_event:=jsonb_build_object('relation',TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,'operation',TG_OP,'old',to_jsonb(OLD),'new',to_jsonb(NEW));
    IF observed_event IS DISTINCT FROM internal.initial_cancellation_lifecycle_event(stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_WHEN='AFTER' THEN
        UPDATE internal.initial_cancellation_lifecycle_witness SET phase='observed',event=observed_event WHERE scan_id=stage.scan_id;
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER z9_initial_cancellation_lifecycle BEFORE INSERT OR UPDATE OR DELETE
    ON internal.initial_analysis_lifecycle_fences FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_lifecycle_member();
CREATE TRIGGER z9_initial_cancellation_lifecycle_after AFTER INSERT OR UPDATE OR DELETE
    ON internal.initial_analysis_lifecycle_fences FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_lifecycle_member();
CREATE TRIGGER z9_initial_cancellation_lifecycle_truncate BEFORE TRUNCATE
    ON internal.initial_analysis_lifecycle_fences FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_lifecycle_member();
REVOKE ALL ON FUNCTION internal.initial_cancellation_lifecycle_event(internal.initial_admitted_cancellation_staging),
    internal.guard_initial_cancellation_lifecycle_witness(),internal.advance_initial_cancellation_lifecycle(UUID,UUID,TEXT,TEXT),
    internal.guard_initial_cancellation_lifecycle_member() FROM PUBLIC,anon,authenticated,service_role;

DO $c1_lifecycle_owner$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    SELECT pg_get_functiondef('internal.cancel_initial_analysis(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='  UPDATE internal.initial_analysis_lifecycle_fences SET state=terminal WHERE scan_id=p_scan;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 lifecycle owner drift'; END IF;
    EXECUTE replace(definition,anchor,
        '  PERFORM internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,terminal,''begin'');'||E'\n'||anchor||E'\n'||
        '  PERFORM internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,terminal,''end'');');
END; $c1_lifecycle_owner$;

-- Retirement evidence is private, rollback-only and ordered source then destination.
-- It never opens the existing lifecycle/action/erasure/deferred boundaries.
CREATE TABLE internal.initial_cancellation_retirement_witness (
    scan_id UUID NOT NULL,
    side TEXT NOT NULL CHECK (side IN ('source','destination')),
    phase TEXT NOT NULL DEFAULT 'pending' CHECK (phase IN ('pending','complete')),
    expected JSONB NOT NULL,
    observed JSONB NOT NULL DEFAULT '[]',
    PRIMARY KEY(scan_id,side),
    CHECK (jsonb_typeof(expected)='array' AND jsonb_array_length(expected) BETWEEN 2 AND 17),
    CHECK (jsonb_typeof(observed)='array' AND jsonb_array_length(observed)<=17)
);
ALTER TABLE internal.initial_cancellation_retirement_witness ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_cancellation_retirement_witness FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_cancellation_retirement_events(p_stage internal.initial_admitted_cancellation_staging,p_side TEXT)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE fence JSONB; rows JSONB; item JSONB; result JSONB; fence_relation TEXT; registry_relation TEXT;
BEGIN
    IF p_side='source' THEN
        fence:=p_stage.prestate->'source_fence'; rows:=p_stage.prestate->'source_registry';
        fence_relation:='internal.initial_preparation_source_fences'; registry_relation:='internal.initial_preparation_source_registry';
    ELSIF p_side='destination' THEN
        fence:=p_stage.prestate->'media_fence'; rows:=p_stage.prestate->'destination_registry';
        fence_relation:='internal.initial_analysis_media_allocation_fences'; registry_relation:='internal.initial_analysis_media_registry';
    ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    IF fence->>'state' IS DISTINCT FROM 'allocated' OR fence->>'scan_id' IS DISTINCT FROM p_stage.scan_id::TEXT
        OR jsonb_typeof(rows) IS DISTINCT FROM 'array' OR jsonb_array_length(rows)<1
        OR jsonb_array_length(rows)>(CASE WHEN p_side='source' THEN 16 ELSE 10 END) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    result:=jsonb_build_array(jsonb_build_object('relation',fence_relation,'operation','UPDATE','old',fence,
        'new',fence||jsonb_build_object('state','retired')));
    FOR item IN SELECT value FROM jsonb_array_elements(rows) ORDER BY (value->>'object_id')::UUID LOOP
        IF item->>'scan_id' IS DISTINCT FROM p_stage.scan_id::TEXT OR item->'retired' IS DISTINCT FROM 'false'::JSONB
            OR item->'marker_confirmed' IS DISTINCT FROM 'false'::JSONB OR item->'claim_token' IS DISTINCT FROM 'null'::JSONB
            OR item->'claim_expires_at' IS DISTINCT FROM 'null'::JSONB THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        result:=result||jsonb_build_array(jsonb_build_object('relation',registry_relation,'operation','UPDATE','old',item,
            'new',item||jsonb_build_object('retired',TRUE)));
    END LOOP;
    RETURN result;
END; $$;

-- Compare the entire current registry set, not only the rows an UPDATE found.
-- This helper is also valid for zero-write retirement reentry after erasure;
-- it reads permanent media metadata, never an erased private receipt.
CREATE FUNCTION internal.assert_initial_cancellation_retirement_images(p_scan UUID,p_side TEXT,p_events JSONB,p_after BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE actual_fence JSONB; actual_rows JSONB; expected_rows JSONB; image_key TEXT;
BEGIN
    IF p_side='source' THEN
        IF (SELECT count(*) FROM (SELECT object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan LIMIT 17) bounded)>16 THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        SELECT to_jsonb(f) INTO actual_fence FROM internal.initial_preparation_source_fences f WHERE scan_id=p_scan;
        SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY object_id),'[]') INTO actual_rows FROM internal.initial_preparation_source_registry r WHERE scan_id=p_scan;
    ELSIF p_side='destination' THEN
        IF (SELECT count(*) FROM (SELECT object_id FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan LIMIT 11) bounded)>10 THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        SELECT to_jsonb(f) INTO actual_fence FROM internal.initial_analysis_media_allocation_fences f WHERE scan_id=p_scan;
        SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY object_id),'[]') INTO actual_rows FROM internal.initial_analysis_media_registry r WHERE scan_id=p_scan;
    ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    IF p_after IS NULL OR jsonb_typeof(p_events) IS DISTINCT FROM 'array' OR jsonb_array_length(p_events)<2 THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    image_key:=CASE WHEN p_after THEN 'new' ELSE 'old' END;
    SELECT jsonb_agg(value->image_key ORDER BY ordinal) INTO expected_rows
        FROM jsonb_array_elements(p_events) WITH ORDINALITY e(value,ordinal) WHERE ordinal>1;
    IF actual_fence IS DISTINCT FROM (p_events->0)->image_key OR actual_rows IS DISTINCT FROM expected_rows THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
END; $$;

CREATE FUNCTION internal.guard_initial_cancellation_retirement_witness()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; credit internal.initial_cancellation_credit_witness;
    lifecycle internal.initial_cancellation_lifecycle_witness; source_witness internal.initial_cancellation_retirement_witness;
BEGIN
    IF TG_OP='DELETE' THEN
        PERFORM internal.check_initial_cancellation_cleanup_member(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,to_jsonb(OLD),FALSE);
        RETURN OLD;
    END IF;
    PERFORM internal.require_service_role();
    IF TG_OP NOT IN ('INSERT','UPDATE') THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE scan_id=NEW.scan_id AND transaction_id=pg_current_xact_id();
    IF NOT FOUND OR stage.phase IS DISTINCT FROM 'quota' OR stage.quota_at IS NULL THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO lifecycle FROM internal.initial_cancellation_lifecycle_witness WHERE scan_id=stage.scan_id;
    IF NOT FOUND OR lifecycle.phase IS DISTINCT FROM 'complete'
        OR lifecycle.event IS DISTINCT FROM internal.initial_cancellation_lifecycle_event(stage)
        OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=stage.scan_id)
            IS DISTINCT FROM lifecycle.event->'new' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_OP='INSERT' THEN
        IF NEW.expected IS NOT NULL OR NEW.observed IS DISTINCT FROM '[]'::JSONB OR NEW.phase IS DISTINCT FROM 'pending'
            OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=stage.scan_id) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        SELECT * INTO credit FROM internal.initial_cancellation_credit_witness WHERE scan_id=stage.scan_id;
        IF NOT FOUND OR credit.phase IS DISTINCT FROM 'complete'
            OR (SELECT count(*) FROM internal.initial_cancellation_quota_statements WHERE scan_id=stage.scan_id AND closed)
                <>2*jsonb_array_length(stage.prestate->'charges')+2
            OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements WHERE scan_id=stage.scan_id AND NOT closed) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        IF NEW.side='source' THEN
            -- Check both original sets before the first permanent retirement.
            PERFORM internal.assert_initial_cancellation_retirement_images(stage.scan_id,'destination',
                internal.initial_cancellation_retirement_events(stage,'destination'),FALSE);
        ELSIF NEW.side='destination' THEN
            SELECT * INTO source_witness FROM internal.initial_cancellation_retirement_witness WHERE scan_id=stage.scan_id AND side='source';
            IF NOT FOUND OR source_witness.phase IS DISTINCT FROM 'complete' OR source_witness.observed IS DISTINCT FROM source_witness.expected THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            PERFORM internal.assert_initial_cancellation_retirement_images(stage.scan_id,'source',source_witness.expected,TRUE);
        END IF;
        PERFORM internal.assert_initial_admitted_cancellation_settlement(stage.prestate,stage.quota_at,credit.credit_at);
        NEW.expected:=internal.initial_cancellation_retirement_events(stage,NEW.side);
        PERFORM internal.assert_initial_cancellation_retirement_images(stage.scan_id,NEW.side,NEW.expected,FALSE);
    ELSE
        IF OLD.phase='complete' OR to_jsonb(OLD)-ARRAY['phase','observed'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['phase','observed'] THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        IF NEW.phase='pending' THEN
            IF pg_trigger_depth()<2 OR jsonb_array_length(OLD.observed)>=jsonb_array_length(OLD.expected)
                OR NEW.observed IS DISTINCT FROM OLD.observed||jsonb_build_array(OLD.expected->jsonb_array_length(OLD.observed)) THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
        ELSIF NEW.phase='complete' THEN
            IF OLD.observed IS DISTINCT FROM OLD.expected OR NEW.observed IS DISTINCT FROM OLD.observed THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            PERFORM internal.assert_initial_cancellation_retirement_images(stage.scan_id,NEW.side,NEW.expected,TRUE);
        ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER guard_initial_cancellation_retirement_witness BEFORE INSERT OR UPDATE OR DELETE
    ON internal.initial_cancellation_retirement_witness FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_retirement_witness();
CREATE TRIGGER guard_initial_cancellation_retirement_witness_truncate BEFORE TRUNCATE
    ON internal.initial_cancellation_retirement_witness FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_retirement_witness();

CREATE FUNCTION internal.advance_initial_cancellation_retirement(p_scan UUID,p_side TEXT,p_step TEXT)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; witness internal.initial_cancellation_retirement_witness;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
    IF NOT FOUND THEN RETURN; END IF;
    IF stage.scan_id IS DISTINCT FROM p_scan OR p_side IS NULL OR p_side NOT IN ('source','destination')
        OR p_step IS NULL OR p_step NOT IN ('begin','end') THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO witness FROM internal.initial_cancellation_retirement_witness WHERE scan_id=p_scan AND side=p_side;
    IF FOUND AND witness.phase='complete' THEN
        -- Original DELETE triggers may call the retirement owner again. Only
        -- exact zero-write reentry is safe; member guards deny any new event.
        PERFORM internal.assert_initial_cancellation_retirement_images(p_scan,p_side,witness.expected,TRUE);
        RETURN;
    END IF;
    IF p_step='begin' THEN
        IF witness.scan_id IS NOT NULL THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        INSERT INTO internal.initial_cancellation_retirement_witness(scan_id,side) VALUES(p_scan,p_side);
    ELSE
        UPDATE internal.initial_cancellation_retirement_witness SET phase='complete' WHERE scan_id=p_scan AND side=p_side AND phase='pending';
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
END; $$;

CREATE FUNCTION internal.guard_initial_cancellation_retirement_member()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; witness internal.initial_cancellation_retirement_witness; side_name TEXT; observed_event JSONB;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
    IF NOT FOUND THEN
        IF TG_OP='TRUNCATE' THEN RETURN NULL; ELSIF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    IF TG_OP<>'UPDATE' OR stage.phase IS DISTINCT FROM 'quota' THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    side_name:=CASE WHEN TG_TABLE_NAME IN ('initial_preparation_source_fences','initial_preparation_source_registry') THEN 'source' ELSE 'destination' END;
    SELECT * INTO witness FROM internal.initial_cancellation_retirement_witness WHERE scan_id=stage.scan_id AND side=side_name;
    IF NOT FOUND OR witness.phase IS DISTINCT FROM 'pending' THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    observed_event:=jsonb_build_object('relation',TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,'operation',TG_OP,'old',to_jsonb(OLD),'new',to_jsonb(NEW));
    IF observed_event IS DISTINCT FROM witness.expected->jsonb_array_length(witness.observed) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_WHEN='AFTER' THEN
        UPDATE internal.initial_cancellation_retirement_witness SET observed=observed||jsonb_build_array(observed_event)
            WHERE scan_id=stage.scan_id AND side=side_name;
    END IF;
    RETURN NEW;
END; $$;
DO $c1_retirement_members$
DECLARE relation_name TEXT;
BEGIN
    FOREACH relation_name IN ARRAY ARRAY['internal.initial_preparation_source_fences','internal.initial_preparation_source_registry',
        'internal.initial_analysis_media_allocation_fences','internal.initial_analysis_media_registry'] LOOP
        EXECUTE format('CREATE TRIGGER z9_initial_cancellation_retirement BEFORE INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_retirement_member()',relation_name);
        EXECUTE format('CREATE TRIGGER z9_initial_cancellation_retirement_after AFTER INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_retirement_member()',relation_name);
        EXECUTE format('CREATE TRIGGER z9_initial_cancellation_retirement_truncate BEFORE TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_retirement_member()',relation_name);
    END LOOP;
END; $c1_retirement_members$;
REVOKE ALL ON FUNCTION internal.initial_cancellation_retirement_events(internal.initial_admitted_cancellation_staging,TEXT),
    internal.assert_initial_cancellation_retirement_images(UUID,TEXT,JSONB,BOOLEAN),internal.guard_initial_cancellation_retirement_witness(),
    internal.advance_initial_cancellation_retirement(UUID,TEXT,TEXT),internal.guard_initial_cancellation_retirement_member()
    FROM PUBLIC,anon,authenticated,service_role;

DO $c1_retirement_owners$
DECLARE definition TEXT; side_name TEXT; signature TEXT; anchor TEXT;
BEGIN
    FOR side_name,signature IN SELECT * FROM (VALUES
        ('source','internal.retire_initial_preparation_source_objects(uuid)'),
        ('destination','internal.retire_initial_media_objects(uuid)')) owners(side_name,signature) LOOP
        SELECT pg_get_functiondef(signature::REGPROCEDURE) INTO STRICT definition;
        anchor:=CASE side_name WHEN 'source' THEN ' UPDATE internal.initial_preparation_source_fences SET state=''retired'''
            ELSE ' UPDATE internal.initial_analysis_media_allocation_fences SET state=''retired''' END;
        IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 retirement begin drift'; END IF;
        definition:=replace(definition,anchor,format(' PERFORM internal.advance_initial_cancellation_retirement(p_scan,%L,''begin'');',side_name)||E'\n'||anchor);
        anchor:=' END LOOP;';
        IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 retirement end drift'; END IF;
        EXECUTE replace(definition,anchor,anchor||E'\n'||format(' PERFORM internal.advance_initial_cancellation_retirement(p_scan,%L,''end'');',side_name));
    END LOOP;
END; $c1_retirement_owners$;

-- Freeze every operation-owned private cascade member before C1 settlement.
-- This inventory does not grant erasure: all private writes remain denied for
-- the entire authentic stage lifetime until a complete terminal owner exists.
CREATE FUNCTION internal.initial_cancellation_private_catalog()
RETURNS TABLE(relation_name TEXT,root_name TEXT,row_limit INTEGER)
LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
 VALUES
 ('internal.initial_analysis_submissions','submission',1),
 ('internal.initial_analysis_admissions','submission',1),
 ('internal.initial_preparation_admission_receipts','submission',1),
 ('internal.initial_analysis_media_cohorts','submission',1),
 ('internal.initial_analysis_media_preparations','submission',1),
 ('internal.initial_analysis_media_verifications','submission',1),
 ('internal.initial_analysis_results','submission',1),
 ('internal.initial_analysis_completions','submission',1),
 ('internal.initial_analysis_preparation_intents','intent',1),
 ('internal.initial_preparation_source_mapping','intent',8),
 ('internal.initial_preparation_source_verifications','intent',1),
 ('internal.initial_preparation_execution_grants','intent',1),
 ('internal.initial_preparation_output_manifests','intent',1),
 ('internal.initial_preparation_output_mapping','intent',8),
 ('internal.initial_preparation_outcomes','intent',1);
$$;

CREATE FUNCTION internal.capture_initial_cancellation_private_images(p_scan UUID)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE member RECORD; row_count BIGINT; member_bytes BIGINT; total_bytes BIGINT:=0;
    images JSONB; result JSONB:='{}'::JSONB;
BEGIN
    IF p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    -- Complete the bounded count/byte preflight BEFORE any JSON aggregation.
    -- The caller already holds the original operation/parent/member lock scope.
    -- Each query scans only indexed scan_id membership and at most limit+1 rows.
    FOR member IN SELECT * FROM internal.initial_cancellation_private_catalog() LOOP
        EXECUTE format('SELECT count(*) FROM (SELECT 1 FROM %s WHERE scan_id=$1 LIMIT %s) bounded',member.relation_name,member.row_limit+1)
            INTO row_count USING p_scan;
        IF row_count>member.row_limit THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        EXECUTE format('SELECT COALESCE(sum(octet_length(to_jsonb(t)::TEXT)),0) FROM %s t WHERE scan_id=$1',member.relation_name)
            INTO member_bytes USING p_scan;
        total_bytes:=total_bytes+member_bytes;
        IF member_bytes>33554432 OR total_bytes>67108864 THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
    FOR member IN SELECT * FROM internal.initial_cancellation_private_catalog() LOOP
        EXECUTE format('SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY (to_jsonb(t)->>''ordinal'')::INTEGER),''[]''::JSONB) FROM %s t WHERE scan_id=$1',member.relation_name)
            INTO images USING p_scan;
        result:=result||jsonb_build_object(member.relation_name,images);
    END LOOP;
    RETURN result;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_cancellation_private_catalog(),internal.capture_initial_cancellation_private_images(UUID)
    FROM PUBLIC,anon,authenticated,service_role;

DO $c1_private_capture$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    SELECT pg_get_functiondef('internal.capture_initial_admitted_cancellation_prestate(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='    PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 source mapping lock drift'; END IF;
    definition:=replace(definition,anchor,anchor||E'\n'||'    PERFORM object_id FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;');
    anchor:='        ''lifecycle'',(SELECT to_jsonb(t) FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=p_scan));';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 private capture drift'; END IF;
    EXECUTE replace(definition,anchor,'        ''erasure_images'',internal.capture_initial_cancellation_private_images(p_scan),'||E'\n'||anchor);
END; $c1_private_capture$;

CREATE FUNCTION internal.guard_initial_cancellation_private_member()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    -- No public erasure branch exists. A caller cannot mutate captured private
    -- evidence or populate an initially empty child while this stage survives.
    IF EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id()) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_OP='TRUNCATE' THEN RETURN NULL; ELSIF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.guard_initial_cancellation_private_member() FROM PUBLIC,anon,authenticated,service_role;
DO $c1_private_guards$
DECLARE member RECORD;
BEGIN
    FOR member IN SELECT * FROM internal.initial_cancellation_private_catalog() LOOP
        EXECUTE format('CREATE TRIGGER a0_initial_cancellation_private BEFORE INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_private_member()',member.relation_name);
        EXECUTE format('CREATE TRIGGER a0_initial_cancellation_private_truncate BEFORE TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_private_member()',member.relation_name);
    END LOOP;
END; $c1_private_guards$;

-- Private, uncommittable erasure protocol. No public cancellation owner calls
-- it yet; the unconditional deferred C1 failure remains in force.
CREATE TABLE internal.initial_cancellation_erasure_witness (
    scan_id UUID NOT NULL,
    root_name TEXT NOT NULL CHECK(root_name IN ('submission','intent')),
    phase TEXT NOT NULL DEFAULT 'pending' CHECK(phase IN ('pending','complete')),
    expected JSONB NOT NULL,
    accounting_images JSONB NOT NULL,
    observed INTEGER[] NOT NULL DEFAULT '{}',
    PRIMARY KEY(scan_id,root_name),
    CHECK(jsonb_typeof(expected)='array' AND jsonb_array_length(expected) BETWEEN 1 AND 21),
    CHECK(cardinality(observed)<=21)
);
ALTER TABLE internal.initial_cancellation_erasure_witness ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_cancellation_erasure_witness FROM PUBLIC,anon,authenticated,service_role;

-- Read only surviving accounting facts. The first witness freezes these only
-- after the original receipt-dependent comparator has passed in full.
CREATE FUNCTION internal.capture_initial_cancellation_accounting_images(p_stage internal.initial_admitted_cancellation_staging)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE reservation UUID:=(p_stage.prestate#>>'{quota,id}')::UUID;
    charge JSONB; counter_image JSONB; counters JSONB:='[]'::JSONB;
BEGIN
    FOR charge IN SELECT value FROM jsonb_array_elements(p_stage.prestate->'charges') LOOP
        SELECT to_jsonb(c) INTO counter_image FROM internal.ai_quota_counters c
            WHERE c.scope_type=charge#>>'{counter,scope_type}' AND c.scope_key=charge#>>'{counter,scope_key}'
                AND c.bucket=charge#>>'{counter,bucket}' AND c.window_start=(charge#>>'{counter,window_start}')::TIMESTAMPTZ;
        counters:=counters||jsonb_build_array(jsonb_build_object('link',charge->'link','counter',counter_image));
    END LOOP;
    RETURN jsonb_build_object(
        'quota',(SELECT to_jsonb(q) FROM internal.ai_quota_reservations q WHERE id=reservation),
        'link_count',(SELECT count(*) FROM internal.ai_quota_reservation_counters WHERE reservation_id=reservation),
        'attempt_count',(SELECT count(*) FROM internal.identification_provider_attempts WHERE reservation_id=reservation),
        'attempt',(SELECT to_jsonb(a) FROM internal.identification_provider_attempts a WHERE reservation_id=reservation AND attempt_count=1),
        'counters',counters,
        'hold_count',(SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id=p_stage.scan_id),
        'hold',(SELECT to_jsonb(h) FROM internal.complimentary_scan_usage h WHERE user_id=p_stage.owner_id AND client_scan_id=p_stage.scan_id),
        'owner_epoch',(SELECT jsonb_build_object('id',u.id,'entitlement_version',u.entitlement_version,
            'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch) FROM public.users u WHERE id=p_stage.owner_id));
END; $$;

CREATE FUNCTION internal.assert_initial_cancellation_erasure_boundary(p_stage internal.initial_admitted_cancellation_staging,p_receipt JSONB)
RETURNS VOID LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE lifecycle internal.initial_cancellation_lifecycle_witness;
    retirement internal.initial_cancellation_retirement_witness; side_name TEXT; accounting JSONB;
BEGIN
    IF (p_receipt IS NOT NULL AND p_receipt IS DISTINCT FROM jsonb_build_object(
            'scan_id',p_stage.scan_id,'owner_id',p_stage.owner_id,'dispatch','dispatch_prevented'))
        OR p_stage.transaction_id IS DISTINCT FROM pg_current_xact_id() OR p_stage.phase IS DISTINCT FROM 'quota'
        OR p_stage.quota_at IS NULL THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO lifecycle FROM internal.initial_cancellation_lifecycle_witness WHERE scan_id=p_stage.scan_id;
    IF NOT FOUND OR lifecycle.phase IS DISTINCT FROM 'complete'
        OR lifecycle.event IS DISTINCT FROM internal.initial_cancellation_lifecycle_event(p_stage)
        OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=p_stage.scan_id)
            IS DISTINCT FROM lifecycle.event->'new'
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_stage.scan_id)
        OR (SELECT to_jsonb(c) FROM internal.initial_analysis_cancellations c WHERE scan_id=p_stage.scan_id)
            IS DISTINCT FROM p_receipt THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    FOREACH side_name IN ARRAY ARRAY['source','destination'] LOOP
        SELECT * INTO retirement FROM internal.initial_cancellation_retirement_witness
            WHERE scan_id=p_stage.scan_id AND side=side_name;
        IF NOT FOUND OR retirement.phase IS DISTINCT FROM 'complete' OR retirement.observed IS DISTINCT FROM retirement.expected
            OR retirement.expected IS DISTINCT FROM internal.initial_cancellation_retirement_events(p_stage,side_name) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_cancellation_retirement_images(p_stage.scan_id,side_name,retirement.expected,TRUE);
    END LOOP;
    SELECT accounting_images INTO accounting FROM internal.initial_cancellation_erasure_witness
        WHERE scan_id=p_stage.scan_id AND root_name='submission';
    IF FOUND AND accounting IS DISTINCT FROM internal.capture_initial_cancellation_accounting_images(p_stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
END; $$;

-- Existing erasure callers still require receipt absence. Only the later
-- receipt comparator supplies its privately derived exact three-field image.
CREATE FUNCTION internal.assert_initial_cancellation_erasure_boundary(p_stage internal.initial_admitted_cancellation_staging)
RETURNS VOID LANGUAGE SQL STABLE SECURITY INVOKER SET search_path='' AS $$
    SELECT internal.assert_initial_cancellation_erasure_boundary(p_stage,NULL::JSONB);
$$;
REVOKE ALL ON FUNCTION internal.assert_initial_cancellation_erasure_boundary(internal.initial_admitted_cancellation_staging,JSONB)
    FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.assert_initial_cancellation_private_progress(p_stage internal.initial_admitted_cancellation_staging,p_erased TEXT[])
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE member RECORD; actual JSONB;
BEGIN
    actual:=internal.capture_initial_cancellation_private_images(p_stage.scan_id);
    FOR member IN SELECT * FROM internal.initial_cancellation_private_catalog() LOOP
        IF actual->member.relation_name IS DISTINCT FROM
            (CASE WHEN member.root_name=ANY(p_erased) THEN '[]'::JSONB ELSE p_stage.prestate->'erasure_images'->member.relation_name END) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
END; $$;

CREATE FUNCTION internal.guard_initial_cancellation_erasure_witness()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; credit internal.initial_cancellation_credit_witness;
    previous internal.initial_cancellation_erasure_witness; member RECORD; item JSONB;
    event_value JSONB; event_count INTEGER; appended INTEGER; complete_indexes INTEGER[];
BEGIN
    IF TG_OP='DELETE' THEN
        PERFORM internal.check_initial_cancellation_cleanup_member(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,to_jsonb(OLD),FALSE);
        RETURN OLD;
    END IF;
    PERFORM internal.require_service_role();
    IF TG_OP NOT IN ('INSERT','UPDATE') THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE scan_id=NEW.scan_id AND transaction_id=pg_current_xact_id();
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    IF TG_OP='INSERT' THEN
        IF NEW.root_name IS NULL OR NEW.root_name NOT IN ('submission','intent') OR NEW.phase IS DISTINCT FROM 'pending'
            OR NEW.expected IS NOT NULL OR NEW.accounting_images IS NOT NULL OR NEW.observed IS DISTINCT FROM '{}'::INTEGER[]
            OR EXISTS(SELECT 1 FROM internal.initial_cancellation_erasure_witness WHERE scan_id=stage.scan_id AND phase='pending') THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_cancellation_erasure_boundary(stage);
        IF NEW.root_name='submission' THEN
            IF EXISTS(SELECT 1 FROM internal.initial_cancellation_erasure_witness WHERE scan_id=stage.scan_id) THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            SELECT * INTO credit FROM internal.initial_cancellation_credit_witness WHERE scan_id=stage.scan_id;
            IF NOT FOUND OR credit.phase IS DISTINCT FROM 'complete'
                OR (SELECT count(*) FROM internal.initial_cancellation_quota_statements WHERE scan_id=stage.scan_id AND closed)
                    <>2*jsonb_array_length(stage.prestate->'charges')+2
                OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements WHERE scan_id=stage.scan_id AND NOT closed) THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            -- Last receipt-dependent comparison. No later phase reads it.
            PERFORM internal.assert_initial_admitted_cancellation_settlement(stage.prestate,stage.quota_at,credit.credit_at);
            NEW.accounting_images:=internal.capture_initial_cancellation_accounting_images(stage);
            PERFORM internal.assert_initial_cancellation_private_progress(stage,'{}');
        ELSE
            SELECT * INTO previous FROM internal.initial_cancellation_erasure_witness WHERE scan_id=stage.scan_id AND root_name='submission';
            IF NOT FOUND OR previous.phase IS DISTINCT FROM 'complete' THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            NEW.accounting_images:=previous.accounting_images;
            PERFORM internal.assert_initial_cancellation_private_progress(stage,ARRAY['submission']);
        END IF;
        NEW.expected:='[]';
        FOR member IN SELECT * FROM internal.initial_cancellation_private_catalog() WHERE root_name=NEW.root_name ORDER BY relation_name LOOP
            FOR item IN SELECT value FROM jsonb_array_elements(stage.prestate->'erasure_images'->member.relation_name) LOOP
                IF item->>'scan_id' IS DISTINCT FROM stage.scan_id::TEXT THEN
                    RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
                END IF;
                event_value:=jsonb_build_object('relation',member.relation_name,'operation','DELETE','old',item);
                IF NEW.expected @> jsonb_build_array(event_value) THEN
                    RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
                END IF;
                NEW.expected:=NEW.expected||jsonb_build_array(event_value);
            END LOOP;
        END LOOP;
    ELSE
        IF OLD.phase IS DISTINCT FROM 'pending' OR to_jsonb(OLD)-ARRAY['phase','observed'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['phase','observed'] THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        event_count:=jsonb_array_length(OLD.expected);
        IF NEW.phase='pending' THEN
            appended:=NEW.observed[cardinality(NEW.observed)];
            IF pg_trigger_depth()<2 OR cardinality(NEW.observed)<>cardinality(OLD.observed)+1
                OR appended IS NULL OR appended<0 OR appended>=event_count OR appended=ANY(OLD.observed)
                OR NEW.observed IS DISTINCT FROM array_append(OLD.observed,appended) THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
        ELSIF NEW.phase='complete' THEN
            SELECT array_agg(i ORDER BY i) INTO complete_indexes FROM generate_series(0,event_count-1) i;
            IF NEW.observed IS DISTINCT FROM OLD.observed
                OR (SELECT array_agg(i ORDER BY i) FROM unnest(OLD.observed) i) IS DISTINCT FROM complete_indexes THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            PERFORM internal.assert_initial_cancellation_erasure_boundary(stage);
            PERFORM internal.assert_initial_cancellation_private_progress(stage,
                CASE WHEN NEW.root_name='submission' THEN ARRAY['submission'] ELSE ARRAY['submission','intent'] END);
        ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER guard_initial_cancellation_erasure_witness BEFORE INSERT OR UPDATE OR DELETE
    ON internal.initial_cancellation_erasure_witness FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_erasure_witness();
CREATE TRIGGER guard_initial_cancellation_erasure_witness_truncate BEFORE TRUNCATE
    ON internal.initial_cancellation_erasure_witness FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_erasure_witness();

CREATE OR REPLACE FUNCTION internal.guard_initial_cancellation_private_member()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; witness internal.initial_cancellation_erasure_witness;
    event_value JSONB; event_index INTEGER; matches INTEGER;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
    IF NOT FOUND THEN
        IF TG_OP='TRUNCATE' THEN RETURN NULL; ELSIF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    IF TG_OP<>'DELETE' OR stage.phase IS DISTINCT FROM 'quota' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO witness FROM internal.initial_cancellation_erasure_witness WHERE scan_id=stage.scan_id AND phase='pending';
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    event_value:=jsonb_build_object('relation',TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,'operation','DELETE','old',to_jsonb(OLD));
    SELECT count(*),min(ordinal-1)::INTEGER INTO matches,event_index
        FROM jsonb_array_elements(witness.expected) WITH ORDINALITY e(value,ordinal) WHERE value=event_value;
    IF matches<>1 OR event_index=ANY(witness.observed) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_WHEN='AFTER' THEN
        UPDATE internal.initial_cancellation_erasure_witness SET observed=array_append(observed,event_index)
            WHERE scan_id=stage.scan_id AND root_name=witness.root_name;
    END IF;
    RETURN OLD;
END; $$;
DO $c1_private_after$
DECLARE member RECORD;
BEGIN
    FOR member IN SELECT * FROM internal.initial_cancellation_private_catalog() LOOP
        EXECUTE format('CREATE TRIGGER z9_initial_cancellation_private_after AFTER DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_private_member()',member.relation_name);
    END LOOP;
END; $c1_private_after$;

CREATE FUNCTION internal.erase_initial_cancellation_private_root(p_scan UUID,p_root TEXT)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF p_scan IS NULL OR p_root IS NULL OR p_root NOT IN ('submission','intent') THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    INSERT INTO internal.initial_cancellation_erasure_witness(scan_id,root_name) VALUES(p_scan,p_root);
    IF p_root='submission' THEN
        DELETE FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
    ELSE
        DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
    END IF;
    UPDATE internal.initial_cancellation_erasure_witness SET phase='complete' WHERE scan_id=p_scan AND root_name=p_root;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_cancellation_erasure_boundary(internal.initial_admitted_cancellation_staging),
    internal.capture_initial_cancellation_accounting_images(internal.initial_admitted_cancellation_staging),
    internal.assert_initial_cancellation_private_progress(internal.initial_admitted_cancellation_staging,TEXT[]),
    internal.guard_initial_cancellation_erasure_witness(),internal.erase_initial_cancellation_private_root(UUID,TEXT)
    FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_initial_cancellation_erased_attempt()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF EXISTS(SELECT 1 FROM internal.initial_cancellation_erasure_witness w
        JOIN internal.initial_admitted_cancellation_staging s USING(scan_id) WHERE s.transaction_id=pg_current_xact_id()) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_OP='TRUNCATE' THEN RETURN NULL; ELSIF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.guard_initial_cancellation_erased_attempt() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER a0_initial_cancellation_erased_attempt BEFORE INSERT OR UPDATE OR DELETE
    ON internal.identification_provider_attempts FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_erased_attempt();
CREATE TRIGGER a0_initial_cancellation_erased_attempt_truncate BEFORE TRUNCATE
    ON internal.identification_provider_attempts FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_erased_attempt();


-- Minimal existing receipt only. No terminal consumption or commit exception.
CREATE TABLE internal.initial_cancellation_receipt_witness (
    scan_id UUID PRIMARY KEY,
    phase TEXT NOT NULL DEFAULT 'pending' CHECK(phase IN ('pending','complete')),
    expected JSONB NOT NULL,
    observed BOOLEAN NOT NULL DEFAULT FALSE
);
ALTER TABLE internal.initial_cancellation_receipt_witness ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_cancellation_receipt_witness FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_cancellation_receipt_image(p_stage internal.initial_admitted_cancellation_staging)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
    SELECT jsonb_build_object('scan_id',p_stage.scan_id,'owner_id',p_stage.owner_id,'dispatch','dispatch_prevented');
$$;

CREATE FUNCTION internal.assert_initial_cancellation_receipt_boundary(p_stage internal.initial_admitted_cancellation_staging,p_present BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE witness internal.initial_cancellation_erasure_witness; indexes INTEGER[];
BEGIN
    IF p_present IS NULL THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    PERFORM internal.assert_initial_cancellation_erasure_boundary(p_stage,
        CASE WHEN p_present THEN internal.initial_cancellation_receipt_image(p_stage) ELSE NULL::JSONB END);
    IF (SELECT count(*) FROM internal.initial_cancellation_erasure_witness WHERE scan_id=p_stage.scan_id)<>2 THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    FOR witness IN SELECT * FROM internal.initial_cancellation_erasure_witness WHERE scan_id=p_stage.scan_id LOOP
        SELECT array_agg(i ORDER BY i) INTO indexes FROM generate_series(0,jsonb_array_length(witness.expected)-1) i;
        IF witness.phase IS DISTINCT FROM 'complete'
            OR (SELECT array_agg(i ORDER BY i) FROM unnest(witness.observed) i) IS DISTINCT FROM indexes
            OR witness.accounting_images IS DISTINCT FROM internal.capture_initial_cancellation_accounting_images(p_stage) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
    PERFORM internal.assert_initial_cancellation_private_progress(p_stage,ARRAY['submission','intent']);
END; $$;

CREATE FUNCTION internal.guard_initial_cancellation_receipt_witness()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging;
BEGIN
    IF TG_OP='DELETE' THEN
        PERFORM internal.check_initial_cancellation_cleanup_member(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,to_jsonb(OLD),FALSE);
        RETURN OLD;
    END IF;
    PERFORM internal.require_service_role();
    IF TG_OP NOT IN ('INSERT','UPDATE') THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE scan_id=NEW.scan_id AND transaction_id=pg_current_xact_id();
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    IF TG_OP='INSERT' THEN
        IF NEW.phase IS DISTINCT FROM 'pending' OR NEW.expected IS NOT NULL OR NEW.observed IS DISTINCT FROM FALSE THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_cancellation_receipt_boundary(stage,FALSE);
        NEW.expected:=internal.initial_cancellation_receipt_image(stage);
    ELSE
        IF OLD.phase IS DISTINCT FROM 'pending' OR NEW.scan_id IS DISTINCT FROM OLD.scan_id
            OR NEW.expected IS DISTINCT FROM OLD.expected THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        IF NEW.phase='pending' AND NOT OLD.observed AND NEW.observed AND pg_trigger_depth()>=2 THEN
            IF (SELECT to_jsonb(c) FROM internal.initial_analysis_cancellations c WHERE scan_id=stage.scan_id) IS DISTINCT FROM OLD.expected THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
        ELSIF NEW.phase='complete' AND OLD.observed AND NEW.observed THEN
            PERFORM internal.assert_initial_cancellation_receipt_boundary(stage,TRUE);
        ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER guard_initial_cancellation_receipt_witness BEFORE INSERT OR UPDATE OR DELETE
    ON internal.initial_cancellation_receipt_witness FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_receipt_witness();
CREATE TRIGGER guard_initial_cancellation_receipt_witness_truncate BEFORE TRUNCATE
    ON internal.initial_cancellation_receipt_witness FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_receipt_witness();

CREATE FUNCTION internal.guard_initial_cancellation_receipt_member()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; witness internal.initial_cancellation_receipt_witness;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
    IF NOT FOUND THEN
        IF TG_OP='DELETE' THEN RETURN OLD; ELSIF TG_OP='TRUNCATE' THEN RETURN NULL; ELSE RETURN NEW; END IF;
    END IF;
    IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    SELECT * INTO witness FROM internal.initial_cancellation_receipt_witness WHERE scan_id=stage.scan_id;
    IF NOT FOUND OR witness.phase IS DISTINCT FROM 'pending' OR witness.observed
        OR to_jsonb(NEW) IS DISTINCT FROM witness.expected
        OR witness.expected IS DISTINCT FROM internal.initial_cancellation_receipt_image(stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_WHEN='BEFORE' THEN
        PERFORM internal.assert_initial_cancellation_receipt_boundary(stage,FALSE);
    ELSE
        UPDATE internal.initial_cancellation_receipt_witness SET observed=TRUE WHERE scan_id=stage.scan_id;
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER a0_initial_cancellation_receipt_member BEFORE INSERT OR UPDATE OR DELETE
    ON internal.initial_analysis_cancellations FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_receipt_member();
CREATE TRIGGER a0_initial_cancellation_receipt_member_truncate BEFORE TRUNCATE
    ON internal.initial_analysis_cancellations FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_receipt_member();
CREATE TRIGGER z9_initial_cancellation_receipt_member AFTER INSERT
    ON internal.initial_analysis_cancellations FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_receipt_member();

CREATE FUNCTION internal.write_initial_cancellation_receipt(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE expected JSONB;
BEGIN
    INSERT INTO internal.initial_cancellation_receipt_witness(scan_id) VALUES(p_scan) RETURNING initial_cancellation_receipt_witness.expected INTO expected;
    INSERT INTO internal.initial_analysis_cancellations SELECT (jsonb_populate_record(NULL::internal.initial_analysis_cancellations,expected)).*;
    UPDATE internal.initial_cancellation_receipt_witness SET phase='complete' WHERE scan_id=p_scan;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_cancellation_receipt_image(internal.initial_admitted_cancellation_staging),
    internal.assert_initial_cancellation_receipt_boundary(internal.initial_admitted_cancellation_staging,BOOLEAN),
    internal.guard_initial_cancellation_receipt_witness(),internal.guard_initial_cancellation_receipt_member(),
    internal.write_initial_cancellation_receipt(UUID) FROM PUBLIC,anon,authenticated,service_role;


-- Transaction-only terminal evidence. Cleanup/deferred acceptance remain closed.
CREATE FUNCTION internal.initial_cancellation_terminal_catalog()
RETURNS TABLE(relation_name TEXT,row_limit INTEGER,order_key TEXT)
LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
    VALUES ('internal.initial_admitted_cancellation_staging',1,'scan_id'),
        ('internal.initial_cancellation_quota_statements',8,'ordinal'),
        ('internal.initial_cancellation_credit_witness',1,'scan_id'),
        ('internal.initial_cancellation_lifecycle_witness',1,'scan_id'),
        ('internal.initial_cancellation_retirement_witness',2,'side'),
        ('internal.initial_cancellation_erasure_witness',2,'root_name'),
        ('internal.initial_cancellation_receipt_witness',1,'scan_id');
$$;

CREATE FUNCTION internal.assert_initial_cancellation_terminal_predecessors(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; quota internal.initial_cancellation_quota_statements;
    credit internal.initial_cancellation_credit_witness; receipt internal.initial_cancellation_receipt_witness;
    erasure internal.initial_cancellation_erasure_witness; contract RECORD; member RECORD;
    n INTEGER; events JSONB; item JSONB;
BEGIN
    PERFORM internal.require_service_role();
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE scan_id=p_scan AND transaction_id=pg_current_xact_id();
    IF NOT FOUND OR stage.prestate->>'scan_id' IS DISTINCT FROM stage.scan_id::TEXT
        OR stage.prestate->>'owner_id' IS DISTINCT FROM stage.owner_id::TEXT
        OR stage.prestate->>'transaction_id' IS DISTINCT FROM stage.transaction_id::TEXT THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_cancellation_receipt_boundary(stage,TRUE);
    n:=2*jsonb_array_length(stage.prestate->'charges')+2;
    IF n<2 OR n>8 OR (SELECT count(*) FROM internal.initial_cancellation_quota_statements WHERE scan_id=p_scan)<>n THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    FOR i IN 0..n-1 LOOP
        SELECT * INTO quota FROM internal.initial_cancellation_quota_statements WHERE scan_id=p_scan AND ordinal=i;
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        SELECT * INTO STRICT contract FROM internal.initial_cancellation_quota_contract(stage,i);
        IF NOT quota.closed OR quota.statement_key IS DISTINCT FROM contract.statement_key
            OR quota.link_identity IS DISTINCT FROM contract.link_identity OR quota.expected IS DISTINCT FROM contract.expected
            OR jsonb_array_length(quota.observed)<>jsonb_array_length(quota.expected)
            OR NOT quota.observed @> quota.expected OR NOT quota.expected @> quota.observed THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
    SELECT * INTO credit FROM internal.initial_cancellation_credit_witness WHERE scan_id=p_scan;
    IF NOT FOUND OR credit.phase IS DISTINCT FROM 'complete'
        OR credit.held IS DISTINCT FROM (stage.prestate->'complimentary'<>'null'::JSONB)
        OR (credit.held AND (credit.credit_at IS NULL OR NOT isfinite(credit.credit_at) OR credit.credit_at<stage.quota_at))
        OR (NOT credit.held AND credit.credit_at IS NOT NULL) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    events:='[]';
    IF credit.held THEN events:=jsonb_build_array(internal.initial_cancellation_credit_event(stage,credit,'hold.release'),
        internal.initial_cancellation_credit_event(stage,credit,'owner.epoch')); END IF;
    IF credit.events IS DISTINCT FROM events THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    -- Reconstruct every OLD deletion event from the frozen original catalog.
    -- Earlier guarded capture supplies provenance; current root absence is
    -- independently checked above without reading erased receipt rows.
    FOR erasure IN SELECT * FROM internal.initial_cancellation_erasure_witness WHERE scan_id=p_scan LOOP
        events:='[]';
        FOR member IN SELECT * FROM internal.initial_cancellation_private_catalog() WHERE root_name=erasure.root_name ORDER BY relation_name LOOP
            FOR item IN SELECT value FROM jsonb_array_elements(stage.prestate->'erasure_images'->member.relation_name) LOOP
                IF item->>'scan_id' IS DISTINCT FROM p_scan::TEXT THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
                events:=events||jsonb_build_array(jsonb_build_object('relation',member.relation_name,'operation','DELETE','old',item));
            END LOOP;
        END LOOP;
        IF erasure.expected IS DISTINCT FROM events THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END LOOP;
    SELECT * INTO receipt FROM internal.initial_cancellation_receipt_witness WHERE scan_id=p_scan;
    IF NOT FOUND OR receipt.phase IS DISTINCT FROM 'complete' OR NOT receipt.observed
        OR receipt.expected IS DISTINCT FROM internal.initial_cancellation_receipt_image(stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
END; $$;

CREATE FUNCTION internal.capture_initial_cancellation_terminal_snapshot(p_scan UUID)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging; member RECORD; count_value INTEGER;
    row_bytes BIGINT; estimated BIGINT; result JSONB; rows_value JSONB; members JSONB:='{}'::JSONB; component_count INTEGER:=0;
BEGIN
    PERFORM internal.require_service_role();
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE scan_id=p_scan AND transaction_id=pg_current_xact_id();
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    result:=jsonb_build_object('version',1,'authority','none','scan_id',p_scan,'owner_id',stage.owner_id,
        'transaction_id',stage.transaction_id::TEXT,'rows','{}'::JSONB);
    estimated:=octet_length(result::TEXT);
    -- Count limit+1, then serialized per-row sums. No row-array aggregation
    -- until every component plus JSON framing fits the combined protocol cap.
    FOR member IN SELECT * FROM internal.initial_cancellation_terminal_catalog() ORDER BY relation_name LOOP
        EXECUTE format('SELECT count(*) FROM (SELECT 1 FROM %s WHERE scan_id=$1 LIMIT %s) bounded',member.relation_name,member.row_limit+1)
            INTO count_value USING p_scan;
        IF count_value>member.row_limit THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        EXECUTE format('SELECT COALESCE(sum(octet_length(to_jsonb(t)::TEXT)),0) FROM %s t WHERE scan_id=$1',member.relation_name)
            INTO row_bytes USING p_scan;
        IF row_bytes>67108864 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        estimated:=estimated+octet_length(to_jsonb(member.relation_name)::TEXT)+4+row_bytes+greatest(count_value-1,0)*2
            +CASE WHEN component_count>0 THEN 2 ELSE 0 END;
        component_count:=component_count+1;
        IF estimated>134217728 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END LOOP;
    PERFORM internal.assert_initial_cancellation_terminal_predecessors(p_scan);
    FOR member IN SELECT * FROM internal.initial_cancellation_terminal_catalog() ORDER BY relation_name LOOP
        EXECUTE format('SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY %I),''[]''::JSONB) FROM %s t WHERE scan_id=$1',member.order_key,member.relation_name)
            INTO rows_value USING p_scan;
        members:=members||jsonb_build_object(member.relation_name,rows_value);
    END LOOP;
    result:=jsonb_set(result,'{rows}',members);
    IF octet_length(result::TEXT) IS DISTINCT FROM estimated OR octet_length(result::TEXT)>134217728 THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    RETURN result;
END; $$;

CREATE TABLE internal.initial_cancellation_terminal_snapshot (
    scan_id UUID PRIMARY KEY,
    transaction_id XID8 NOT NULL UNIQUE,
    proof JSONB NOT NULL CHECK(jsonb_typeof(proof)='object' AND octet_length(proof::TEXT)<=134217728),
    phase TEXT NOT NULL DEFAULT 'frozen' CHECK(phase IN ('frozen','consuming')),
    cleanup_cursor INTEGER NOT NULL DEFAULT 0 CHECK(cleanup_cursor BETWEEN 0 AND 16)
);
ALTER TABLE internal.initial_cancellation_terminal_snapshot ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_cancellation_terminal_snapshot FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION internal.guard_initial_cancellation_terminal_snapshot()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    IF NEW.scan_id IS NULL OR NEW.transaction_id IS NOT NULL OR NEW.proof IS NOT NULL THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    NEW.proof:=internal.capture_initial_cancellation_terminal_snapshot(NEW.scan_id);
    NEW.transaction_id:=pg_current_xact_id();
    RETURN NEW;
END; $$;
CREATE TRIGGER guard_initial_cancellation_terminal_snapshot BEFORE INSERT OR UPDATE OR DELETE
    ON internal.initial_cancellation_terminal_snapshot FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_terminal_snapshot();
CREATE TRIGGER guard_initial_cancellation_terminal_snapshot_truncate BEFORE TRUNCATE
    ON internal.initial_cancellation_terminal_snapshot FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_terminal_snapshot();

CREATE FUNCTION internal.assert_initial_cancellation_terminal_snapshot(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE snapshot internal.initial_cancellation_terminal_snapshot;
BEGIN
    SELECT * INTO snapshot FROM internal.initial_cancellation_terminal_snapshot WHERE scan_id=p_scan;
    IF NOT FOUND OR snapshot.transaction_id IS DISTINCT FROM pg_current_xact_id()
        OR snapshot.phase IS DISTINCT FROM 'frozen' OR snapshot.cleanup_cursor<>0
        OR snapshot.proof IS DISTINCT FROM internal.capture_initial_cancellation_terminal_snapshot(p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_cancellation_terminal_catalog(),internal.assert_initial_cancellation_terminal_predecessors(UUID),
    internal.capture_initial_cancellation_terminal_snapshot(UUID),internal.guard_initial_cancellation_terminal_snapshot(),
    internal.assert_initial_cancellation_terminal_snapshot(UUID) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE internal.initial_cancellation_terminal_snapshot IS
 'Private transaction-only full terminal proof for future exact cleanup; cannot commit, transport or log. No consumption or deferred acceptance authority.';


-- C1 terminal consumption is one private integrated protocol. The public owner
-- remains fenced. The original stage stays in quota; only this snapshot moves.
CREATE FUNCTION internal.initial_cancellation_cleanup_catalog()
RETURNS TABLE(cleanup_order INTEGER,relation_name TEXT,order_key TEXT)
LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
    VALUES (1,'internal.initial_cancellation_quota_statements','ordinal'),
        (2,'internal.initial_cancellation_credit_witness','scan_id'),
        (3,'internal.initial_cancellation_lifecycle_witness','scan_id'),
        (4,'internal.initial_cancellation_retirement_witness','side'),
        (5,'internal.initial_cancellation_erasure_witness','root_name'),
        (6,'internal.initial_cancellation_receipt_witness','scan_id'),
        (7,'internal.initial_admitted_cancellation_staging','scan_id');
$$;

CREATE FUNCTION internal.initial_cancellation_cleanup_count(p_proof JSONB)
RETURNS INTEGER LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
    SELECT sum(jsonb_array_length(p_proof->'rows'->c.relation_name))::INTEGER
        FROM internal.initial_cancellation_cleanup_catalog() c;
$$;

-- Returns one original full OLD; no second aggregate/copy of the whole ledger.
CREATE FUNCTION internal.initial_cancellation_cleanup_entry(p_proof JSONB,p_cursor INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE member RECORD; offset_value INTEGER:=0; n INTEGER;
BEGIN
    IF p_cursor IS NULL OR p_cursor<0 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    FOR member IN SELECT * FROM internal.initial_cancellation_cleanup_catalog() ORDER BY cleanup_order LOOP
        n:=jsonb_array_length(p_proof->'rows'->member.relation_name);
        IF p_cursor<offset_value+n THEN
            RETURN jsonb_build_object('relation',member.relation_name,'key',member.order_key,
                'old',(p_proof->'rows'->member.relation_name)->(p_cursor-offset_value));
        END IF;
        offset_value:=offset_value+n;
    END LOOP;
    RETURN NULL;
END; $$;

-- Compare every expected key and the exact bounded row count, not a repeated
-- aggregate of all surviving full rows. This function grants no delete authority.
CREATE FUNCTION internal.assert_initial_cancellation_cleanup_suffix(p_scan UUID,p_proof JSONB,p_cursor INTEGER)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE member RECORD; item JSONB; actual JSONB; total INTEGER; n INTEGER;
    offset_value INTEGER:=0; remaining INTEGER; actual_count INTEGER;
BEGIN
    total:=internal.initial_cancellation_cleanup_count(p_proof);
    IF total IS NULL OR total<10 OR total>16 OR p_cursor IS NULL OR p_cursor<0 OR p_cursor>total THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    FOR member IN SELECT * FROM internal.initial_cancellation_cleanup_catalog() ORDER BY cleanup_order LOOP
        n:=jsonb_array_length(p_proof->'rows'->member.relation_name);
        remaining:=greatest(0,offset_value+n-greatest(offset_value,p_cursor));
        EXECUTE format('SELECT count(*) FROM (SELECT 1 FROM %s WHERE scan_id=$1 LIMIT 17) bounded',member.relation_name)
            INTO actual_count USING p_scan;
        IF actual_count<>remaining THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        FOR i IN 0..n-1 LOOP
            IF offset_value+i>=p_cursor THEN
                item:=(p_proof->'rows'->member.relation_name)->i;
                EXECUTE format('SELECT to_jsonb(t) FROM %s t WHERE scan_id=$1 AND %I::TEXT=$2',member.relation_name,member.order_key)
                    INTO actual USING p_scan,item->>member.order_key;
                IF actual IS DISTINCT FROM item THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
            END IF;
        END LOOP;
        offset_value:=offset_value+n;
    END LOOP;
END; $$;

-- The proof must come from the guarded immutable snapshot/DELETE OLD chain.
-- No predecessor table or erased receipt is read here. Calling this read-only
-- comparator with arbitrary JSON never authorizes an action or creates proof.
CREATE FUNCTION internal.assert_initial_cancellation_terminal_survivors(p_proof JSONB)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging;
    lifecycle internal.initial_cancellation_lifecycle_witness;
    retirement internal.initial_cancellation_retirement_witness;
    erasure internal.initial_cancellation_erasure_witness;
    receipt internal.initial_cancellation_receipt_witness;
    accounting JSONB; indexes INTEGER[]; side_name TEXT;
BEGIN
    SELECT * INTO stage FROM jsonb_populate_record(NULL::internal.initial_admitted_cancellation_staging,
        p_proof#>'{rows,internal.initial_admitted_cancellation_staging,0}');
    IF p_proof->>'version' IS DISTINCT FROM '1' OR p_proof->>'authority' IS DISTINCT FROM 'none'
        OR p_proof->>'scan_id' IS DISTINCT FROM stage.scan_id::TEXT
        OR p_proof->>'owner_id' IS DISTINCT FROM stage.owner_id::TEXT
        OR p_proof->>'transaction_id' IS DISTINCT FROM pg_current_xact_id()::TEXT
        OR stage.transaction_id IS DISTINCT FROM pg_current_xact_id() OR stage.phase IS DISTINCT FROM 'quota'
        OR stage.quota_at IS NULL OR NOT isfinite(stage.quota_at) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO lifecycle FROM jsonb_populate_record(NULL::internal.initial_cancellation_lifecycle_witness,
        p_proof#>'{rows,internal.initial_cancellation_lifecycle_witness,0}');
    IF lifecycle.phase IS DISTINCT FROM 'complete' OR lifecycle.scan_id IS DISTINCT FROM stage.scan_id
        OR lifecycle.event IS DISTINCT FROM internal.initial_cancellation_lifecycle_event(stage)
        OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=stage.scan_id) IS DISTINCT FROM lifecycle.event->'new'
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=stage.scan_id)
        OR (SELECT to_jsonb(c) FROM internal.initial_analysis_cancellations c WHERE scan_id=stage.scan_id)
            IS DISTINCT FROM internal.initial_cancellation_receipt_image(stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    FOREACH side_name IN ARRAY ARRAY['source','destination'] LOOP
        SELECT * INTO retirement FROM jsonb_populate_record(NULL::internal.initial_cancellation_retirement_witness,
            (SELECT value FROM jsonb_array_elements(p_proof#>'{rows,internal.initial_cancellation_retirement_witness}') WHERE value->>'side'=side_name));
        IF retirement.scan_id IS DISTINCT FROM stage.scan_id OR retirement.phase IS DISTINCT FROM 'complete'
            OR retirement.observed IS DISTINCT FROM retirement.expected
            OR retirement.expected IS DISTINCT FROM internal.initial_cancellation_retirement_events(stage,side_name) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_cancellation_retirement_images(stage.scan_id,side_name,retirement.expected,TRUE);
    END LOOP;
    accounting:=internal.capture_initial_cancellation_accounting_images(stage);
    FOREACH side_name IN ARRAY ARRAY['submission','intent'] LOOP
        SELECT * INTO erasure FROM jsonb_populate_record(NULL::internal.initial_cancellation_erasure_witness,
            (SELECT value FROM jsonb_array_elements(p_proof#>'{rows,internal.initial_cancellation_erasure_witness}') WHERE value->>'root_name'=side_name));
        SELECT array_agg(i ORDER BY i) INTO indexes FROM generate_series(0,jsonb_array_length(erasure.expected)-1) i;
        IF erasure.scan_id IS DISTINCT FROM stage.scan_id OR erasure.phase IS DISTINCT FROM 'complete'
            OR (SELECT array_agg(i ORDER BY i) FROM unnest(erasure.observed) i) IS DISTINCT FROM indexes
            OR erasure.accounting_images IS DISTINCT FROM accounting THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
    SELECT * INTO receipt FROM jsonb_populate_record(NULL::internal.initial_cancellation_receipt_witness,
        p_proof#>'{rows,internal.initial_cancellation_receipt_witness,0}');
    IF receipt.scan_id IS DISTINCT FROM stage.scan_id OR receipt.phase IS DISTINCT FROM 'complete' OR receipt.observed IS DISTINCT FROM TRUE
        OR receipt.expected IS DISTINCT FROM internal.initial_cancellation_receipt_image(stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_cancellation_private_progress(stage,ARRAY['submission','intent']);
END; $$;

-- Reserved distinct two-integer advisory namespace 1128353347 (CANC).
-- Any matching session lock only over-denies; no lock supplies provenance.
CREATE FUNCTION internal.initial_cancellation_sealed()
RETURNS BOOLEAN LANGUAGE SQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
    SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_locks l
        WHERE l.locktype='advisory' AND l.database=(SELECT oid FROM pg_catalog.pg_database WHERE datname=pg_catalog.current_database())
            AND l.pid=pg_catalog.pg_backend_pid() AND l.granted AND l.mode='ExclusiveLock'
            AND l.classid=1128353347::OID AND l.objsubid=2);
$$;

CREATE FUNCTION internal.check_initial_cancellation_cleanup_member(p_relation TEXT,p_old JSONB,p_after BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE snapshot internal.initial_cancellation_terminal_snapshot; entry JSONB;
BEGIN
    PERFORM internal.require_service_role();
    SELECT * INTO snapshot FROM internal.initial_cancellation_terminal_snapshot WHERE scan_id=(p_old->>'scan_id')::UUID;
    IF NOT FOUND OR snapshot.transaction_id IS DISTINCT FROM pg_current_xact_id() OR snapshot.phase IS DISTINCT FROM 'consuming'
        OR p_after IS NULL OR NOT internal.initial_cancellation_sealed() THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    entry:=internal.initial_cancellation_cleanup_entry(snapshot.proof,snapshot.cleanup_cursor);
    IF entry IS NULL OR entry->>'relation' IS DISTINCT FROM p_relation OR entry->'old' IS DISTINCT FROM p_old THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_cancellation_cleanup_suffix(snapshot.scan_id,snapshot.proof,snapshot.cleanup_cursor+CASE WHEN p_after THEN 1 ELSE 0 END);
END; $$;

CREATE FUNCTION internal.advance_initial_cancellation_cleanup()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF TG_OP<>'DELETE' OR TG_WHEN<>'AFTER' OR pg_trigger_depth()<>1 THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.check_initial_cancellation_cleanup_member(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,to_jsonb(OLD),TRUE);
    UPDATE internal.initial_cancellation_terminal_snapshot SET cleanup_cursor=cleanup_cursor+1
        WHERE scan_id=OLD.scan_id AND transaction_id=pg_current_xact_id() AND phase='consuming';
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    RETURN OLD;
END; $$;

CREATE OR REPLACE FUNCTION internal.guard_initial_cancellation_terminal_snapshot()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE total INTEGER;
BEGIN
    PERFORM internal.require_service_role();
    IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    IF TG_OP='INSERT' THEN
        IF internal.initial_cancellation_sealed() OR NEW.scan_id IS NULL OR NEW.transaction_id IS NOT NULL OR NEW.proof IS NOT NULL
            OR NEW.phase IS DISTINCT FROM 'frozen' OR NEW.cleanup_cursor IS DISTINCT FROM 0 THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        NEW.proof:=internal.capture_initial_cancellation_terminal_snapshot(NEW.scan_id);
        NEW.transaction_id:=pg_current_xact_id();
        RETURN NEW;
    END IF;
    IF OLD.transaction_id IS DISTINCT FROM pg_current_xact_id() THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    total:=internal.initial_cancellation_cleanup_count(OLD.proof);
    IF TG_OP='DELETE' THEN
        IF OLD.phase IS DISTINCT FROM 'consuming' OR OLD.cleanup_cursor IS DISTINCT FROM total OR NOT internal.initial_cancellation_sealed() THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_cancellation_cleanup_suffix(OLD.scan_id,OLD.proof,total);
        PERFORM internal.assert_initial_cancellation_terminal_survivors(OLD.proof);
        RETURN OLD;
    END IF;
    IF to_jsonb(OLD)-ARRAY['phase','cleanup_cursor'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['phase','cleanup_cursor'] THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF OLD.phase='frozen' AND NEW.phase='consuming' AND OLD.cleanup_cursor=0 AND NEW.cleanup_cursor=0 THEN
        IF internal.initial_cancellation_sealed() OR internal.initial_admission_sealed() THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        PERFORM internal.assert_initial_cancellation_terminal_snapshot(OLD.scan_id);
        PERFORM internal.assert_initial_cancellation_terminal_survivors(OLD.proof);
        -- Always acquire an actual xact lock, never infer it from pg_locks.
        IF NOT pg_try_advisory_xact_lock(1128353347,hashtext(OLD.scan_id::TEXT)) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
    ELSIF OLD.phase='consuming' AND NEW.phase='consuming' AND OLD.cleanup_cursor<total
        AND NEW.cleanup_cursor=OLD.cleanup_cursor+1 AND pg_trigger_depth()=2 THEN
        -- Depth is context only. The closed AFTER owner matches the exact OLD;
        -- all immutable fields and the complete post-delete suffix also agree.
        PERFORM internal.assert_initial_cancellation_cleanup_suffix(OLD.scan_id,OLD.proof,NEW.cleanup_cursor);
    ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    RETURN NEW;
END; $$;

CREATE FUNCTION internal.assert_initial_cancellation_transients_absent(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE member RECORD; present BOOLEAN;
BEGIN
    FOR member IN SELECT relation_name FROM internal.initial_cancellation_cleanup_catalog()
        UNION ALL SELECT 'internal.initial_cancellation_terminal_snapshot' LOOP
        EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s WHERE scan_id=$1)',member.relation_name) INTO present USING p_scan;
        IF present THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END LOOP;
END; $$;

-- Earlier INSERT and final stage DELETE obligations cannot pass while any
-- snapshot or predecessor remains. Mandatory guarded DELETE supplies provenance;
-- absence, receipt, xid and seal alone are never a standalone permission.
CREATE OR REPLACE FUNCTION internal.require_complete_initial_admitted_cancellation()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE stage internal.initial_admitted_cancellation_staging;
BEGIN
    IF TG_TABLE_SCHEMA<>'internal' OR TG_TABLE_NAME<>'initial_admitted_cancellation_staging'
        OR TG_WHEN<>'AFTER' OR TG_LEVEL<>'ROW' OR TG_OP NOT IN ('INSERT','DELETE') THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    stage:=CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
    IF stage.transaction_id IS DISTINCT FROM pg_current_xact_id() OR NOT internal.initial_cancellation_sealed()
        OR (SELECT to_jsonb(c) FROM internal.initial_analysis_cancellations c WHERE scan_id=stage.scan_id)
            IS DISTINCT FROM internal.initial_cancellation_receipt_image(stage)
        OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=stage.scan_id)
            IS DISTINCT FROM internal.initial_cancellation_lifecycle_event(stage)->'new'
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=stage.scan_id) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_cancellation_transients_absent(stage.scan_id);
    RETURN NULL;
END; $$;
DROP TRIGGER require_complete_initial_admitted_cancellation ON internal.initial_admitted_cancellation_staging;
CREATE CONSTRAINT TRIGGER require_complete_initial_admitted_cancellation AFTER INSERT OR DELETE
    ON internal.initial_admitted_cancellation_staging DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION internal.require_complete_initial_admitted_cancellation();

-- Deferred validation can fire after the private compositor has returned to an
-- API role. Only these read-only, table-bound trigger owners elevate; private
-- helper/table privileges remain revoked. No caller input supplies the proof.
-- Exactly one deferred complete-proof event, from the actual snapshot DELETE.
CREATE FUNCTION internal.require_complete_initial_cancellation_snapshot()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF TG_TABLE_SCHEMA<>'internal' OR TG_TABLE_NAME<>'initial_cancellation_terminal_snapshot'
        OR TG_WHEN<>'AFTER' OR TG_LEVEL<>'ROW' OR TG_OP<>'DELETE' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF OLD.transaction_id IS DISTINCT FROM pg_current_xact_id() OR OLD.phase IS DISTINCT FROM 'consuming'
        OR OLD.cleanup_cursor IS DISTINCT FROM internal.initial_cancellation_cleanup_count(OLD.proof)
        OR NOT internal.initial_cancellation_sealed() THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_cancellation_transients_absent(OLD.scan_id);
    PERFORM internal.assert_initial_cancellation_terminal_survivors(OLD.proof);
    RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER require_complete_initial_cancellation_snapshot AFTER DELETE
    ON internal.initial_cancellation_terminal_snapshot DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION internal.require_complete_initial_cancellation_snapshot();

CREATE FUNCTION internal.guard_initial_cancellation_seal()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE snapshot internal.initial_cancellation_terminal_snapshot; entry JSONB; relation_name TEXT:=TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME;
BEGIN
    IF NOT internal.initial_cancellation_sealed() THEN RETURN NULL; END IF;
    SELECT * INTO snapshot FROM internal.initial_cancellation_terminal_snapshot
        WHERE transaction_id=pg_current_xact_id() AND phase='consuming';
    IF FOUND THEN
        -- Statement permission is only a narrow routing check. Existing exact
        -- row OLD/phase/cursor guards independently authorize every mutation.
        IF relation_name='internal.initial_cancellation_terminal_snapshot' AND TG_OP='UPDATE' THEN RETURN NULL; END IF;
        IF TG_OP='DELETE' THEN
            entry:=internal.initial_cancellation_cleanup_entry(snapshot.proof,snapshot.cleanup_cursor);
            IF entry->>'relation'=relation_name THEN RETURN NULL; END IF;
            IF entry IS NULL AND relation_name='internal.initial_cancellation_terminal_snapshot'
                AND snapshot.cleanup_cursor=internal.initial_cancellation_cleanup_count(snapshot.proof) THEN RETURN NULL; END IF;
        END IF;
    END IF;
    RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
END; $$;

CREATE FUNCTION internal.finish_initial_cancellation_consumption(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE snapshot internal.initial_cancellation_terminal_snapshot; entry JSONB; affected INTEGER;
BEGIN
    PERFORM internal.require_service_role();
    UPDATE internal.initial_cancellation_terminal_snapshot SET phase='consuming' WHERE scan_id=p_scan AND phase='frozen';
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    LOOP
        SELECT * INTO STRICT snapshot FROM internal.initial_cancellation_terminal_snapshot WHERE scan_id=p_scan;
        entry:=internal.initial_cancellation_cleanup_entry(snapshot.proof,snapshot.cleanup_cursor);
        EXIT WHEN entry IS NULL;
        EXECUTE format('DELETE FROM %s WHERE scan_id=$1 AND %I::TEXT=$2',entry->>'relation',entry->>'key')
            USING p_scan,entry->'old'->>(entry->>'key');
        GET DIAGNOSTICS affected=ROW_COUNT;
        IF affected<>1 OR NOT EXISTS(SELECT 1 FROM internal.initial_cancellation_terminal_snapshot
            WHERE scan_id=p_scan AND cleanup_cursor=snapshot.cleanup_cursor+1) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
    DELETE FROM internal.initial_cancellation_terminal_snapshot WHERE scan_id=p_scan;
    GET DIAGNOSTICS affected=ROW_COUNT;
    IF affected<>1 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    PERFORM internal.assert_initial_cancellation_transients_absent(p_scan);
END; $$;

CREATE FUNCTION internal.initial_cancellation_seal_catalog()
RETURNS TABLE(relation_name TEXT) LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
    VALUES ('internal.ai_quota_reservations'),
        ('internal.complimentary_scan_usage'),
        ('internal.identification_provider_attempts'),
        ('internal.ai_quota_counters'),
        ('internal.ai_quota_reservation_counters'),
        ('public.users'),
        ('internal.initial_analysis_submissions'),
        ('internal.initial_analysis_admissions'),
        ('internal.initial_analysis_lifecycle_fences'),
        ('internal.initial_preparation_admission_receipts'),
        ('internal.initial_analysis_media_allocation_fences'),
        ('internal.initial_analysis_media_registry'),
        ('internal.initial_analysis_media_cohorts'),
        ('internal.initial_analysis_operation_fences'),
        ('internal.initial_analysis_preparation_intents'),
        ('internal.initial_preparation_source_fences'),
        ('internal.initial_preparation_source_registry'),
        ('internal.initial_preparation_source_mapping'),
        ('internal.initial_preparation_source_verifications'),
        ('internal.initial_preparation_execution_grants'),
        ('internal.initial_preparation_output_manifests'),
        ('internal.initial_preparation_output_mapping'),
        ('internal.initial_preparation_outcomes'),
        ('public.scans'),
        ('public.scan_ingestion_jobs'),
        ('public.scan_ingestion_intents'),
        ('internal.observation_histories'),
        ('internal.observation_analysis_source_bindings'),
        ('internal.observation_analysis_intents'),
        ('internal.observation_analysis_results'),
        ('internal.identification_invocations'),
        ('internal.initial_analysis_results'),
        ('internal.initial_analysis_completions'),
        ('internal.initial_analysis_media_preparations'),
        ('internal.initial_analysis_media_verifications'),
        ('internal.initial_analysis_cancellations'),
        ('internal.scan_deletion_tombstones'),
        ('internal.account_deletion_jobs'),
        ('internal.initial_preparation_admission_staging'),
        ('internal.initial_preparation_admission_writes'),
        ('internal.initial_admitted_cancellation_staging'),
        ('internal.initial_cancellation_quota_statements'),
        ('internal.initial_cancellation_credit_witness'),
        ('internal.initial_cancellation_lifecycle_witness'),
        ('internal.initial_cancellation_retirement_witness'),
        ('internal.initial_cancellation_erasure_witness'),
        ('internal.initial_cancellation_receipt_witness'),
        ('internal.initial_cancellation_terminal_snapshot');
$$;

DO $c1_consumption_guards$
DECLARE member RECORD;
BEGIN
    FOR member IN SELECT * FROM internal.initial_cancellation_seal_catalog() LOOP
        EXECUTE format('CREATE TRIGGER a00_initial_cancellation_seal BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_seal()',member.relation_name);
    END LOOP;
    FOR member IN SELECT * FROM internal.initial_cancellation_cleanup_catalog() LOOP
        EXECUTE format('CREATE TRIGGER z9_initial_cancellation_cleanup AFTER DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.advance_initial_cancellation_cleanup()',member.relation_name);
    END LOOP;
END; $c1_consumption_guards$;
REVOKE ALL ON FUNCTION internal.initial_cancellation_cleanup_catalog(),internal.initial_cancellation_cleanup_count(JSONB),
    internal.initial_cancellation_cleanup_entry(JSONB,INTEGER),internal.assert_initial_cancellation_cleanup_suffix(UUID,JSONB,INTEGER),
    internal.assert_initial_cancellation_terminal_survivors(JSONB),internal.initial_cancellation_sealed(),
    internal.check_initial_cancellation_cleanup_member(TEXT,JSONB,BOOLEAN),internal.advance_initial_cancellation_cleanup(),
    internal.assert_initial_cancellation_transients_absent(UUID),internal.require_complete_initial_cancellation_snapshot(),
    internal.guard_initial_cancellation_seal(),internal.finish_initial_cancellation_consumption(UUID),
    internal.initial_cancellation_seal_catalog() FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE internal.initial_admitted_cancellation_staging IS
 'Private C1 transaction-only prestate. Stage stays quota through exact snapshot-bound cleanup; no public settlement authority. No private proof may survive terminal commit.';
COMMENT ON TABLE internal.initial_cancellation_terminal_snapshot IS
 'Private immutable full terminal proof with exact winning-AFTER cleanup cursor. Final DELETE OLD carries deferred proof; denial seal survives removal. Never log, transport or persist proof.';

-- Statement routing is not permission to execute a zero-row protocol mutation.
-- Transition relations bind these checks to this actual statement, not a GUC
-- or a caller-supplied count. Every permitted statement has one winning row.
CREATE FUNCTION internal.check_initial_cancellation_cleanup_statement()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE old_image JSONB; new_image JSONB; snapshot internal.initial_cancellation_terminal_snapshot;
    relation_name TEXT:=TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME; entry JSONB;
BEGIN
    IF NOT internal.initial_cancellation_sealed() THEN RETURN NULL; END IF;
    IF TG_OP='UPDATE' THEN
        IF (SELECT count(*) FROM c1_old_rows)<>1 OR (SELECT count(*) FROM c1_new_rows)<>1 THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        SELECT to_jsonb(t) INTO old_image FROM c1_old_rows t;
        SELECT to_jsonb(t) INTO new_image FROM c1_new_rows t;
        SELECT * INTO snapshot FROM internal.initial_cancellation_terminal_snapshot WHERE transaction_id=pg_current_xact_id();
        IF NOT FOUND OR relation_name<>'internal.initial_cancellation_terminal_snapshot'
            OR to_jsonb(snapshot) IS DISTINCT FROM new_image
            OR old_image-ARRAY['phase','cleanup_cursor'] IS DISTINCT FROM new_image-ARRAY['phase','cleanup_cursor']
            OR snapshot.phase IS DISTINCT FROM 'consuming' THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_cancellation_cleanup_suffix(snapshot.scan_id,snapshot.proof,snapshot.cleanup_cursor);
    ELSIF TG_OP='DELETE' THEN
        IF (SELECT count(*) FROM c1_old_rows)<>1 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        SELECT to_jsonb(t) INTO old_image FROM c1_old_rows t;
        IF relation_name='internal.initial_cancellation_terminal_snapshot' THEN
            SELECT * INTO snapshot FROM jsonb_populate_record(NULL::internal.initial_cancellation_terminal_snapshot,old_image);
            IF snapshot.phase IS DISTINCT FROM 'consuming' OR snapshot.transaction_id IS DISTINCT FROM pg_current_xact_id()
                OR snapshot.cleanup_cursor IS DISTINCT FROM internal.initial_cancellation_cleanup_count(snapshot.proof) THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            PERFORM internal.assert_initial_cancellation_transients_absent(snapshot.scan_id);
            PERFORM internal.assert_initial_cancellation_terminal_survivors(snapshot.proof);
        ELSE
            SELECT * INTO snapshot FROM internal.initial_cancellation_terminal_snapshot WHERE transaction_id=pg_current_xact_id();
            IF NOT FOUND OR snapshot.phase IS DISTINCT FROM 'consuming' OR snapshot.cleanup_cursor<1 THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            entry:=internal.initial_cancellation_cleanup_entry(snapshot.proof,snapshot.cleanup_cursor-1);
            IF entry->>'relation' IS DISTINCT FROM relation_name OR entry->'old' IS DISTINCT FROM old_image THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            PERFORM internal.assert_initial_cancellation_cleanup_suffix(snapshot.scan_id,snapshot.proof,snapshot.cleanup_cursor);
        END IF;
    ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    RETURN NULL;
END; $$;
REVOKE ALL ON FUNCTION internal.check_initial_cancellation_cleanup_statement() FROM PUBLIC,anon,authenticated,service_role;
DO $c1_cleanup_statements$
DECLARE member RECORD;
BEGIN
    FOR member IN SELECT relation_name FROM internal.initial_cancellation_cleanup_catalog()
        UNION ALL SELECT 'internal.initial_cancellation_terminal_snapshot' LOOP
        EXECUTE format('CREATE TRIGGER z99_initial_cancellation_cleanup_statement AFTER DELETE ON %s REFERENCING OLD TABLE AS c1_old_rows FOR EACH STATEMENT EXECUTE FUNCTION internal.check_initial_cancellation_cleanup_statement()',member.relation_name);
    END LOOP;
END; $c1_cleanup_statements$;
CREATE TRIGGER z99_initial_cancellation_cleanup_statement_update AFTER UPDATE ON internal.initial_cancellation_terminal_snapshot
    REFERENCING OLD TABLE AS c1_old_rows NEW TABLE AS c1_new_rows
    FOR EACH STATEMENT EXECUTE FUNCTION internal.check_initial_cancellation_cleanup_statement();

-- Preserve denial on the elevated read-only deferred trigger owners.
REVOKE ALL ON FUNCTION internal.require_complete_initial_admitted_cancellation(),
    internal.require_complete_initial_cancellation_snapshot() FROM PUBLIC,anon,authenticated,service_role;

-- The generic admitted-settlement fence remains unconditional. Only these
-- original-owner callsites can cross it inside the authenticated C1 chain.
CREATE FUNCTION internal.initial_cancellation_quota_authorized(p_reservation UUID,p_owner UUID,p_lease UUID,p_final TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE s internal.initial_admitted_cancellation_staging;
BEGIN
 SELECT * INTO s FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR s.phase IS DISTINCT FROM 'captured' OR s.quota_at IS NOT NULL
  OR s.owner_id IS DISTINCT FROM p_owner OR p_final IS DISTINCT FROM 'refunded'
  OR s.prestate#>>'{quota,id}' IS DISTINCT FROM p_reservation::TEXT
  OR s.prestate#>>'{quota,lease_token}' IS DISTINCT FROM p_lease::TEXT THEN RETURN FALSE; END IF;
 RETURN s.prestate IS NOT DISTINCT FROM internal.capture_initial_admitted_cancellation_prestate(s.owner_id,s.scan_id);
END; $$;

CREATE FUNCTION internal.initial_cancellation_credit_authorized(p_owner UUID,p_scan UUID,p_failure TEXT,p_point TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE s internal.initial_admitted_cancellation_staging; w internal.initial_cancellation_credit_witness;
 q JSONB; hold JSONB; owner_epoch JSONB; expected JSONB;
BEGIN
 SELECT * INTO s FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR s.phase IS DISTINCT FROM 'quota' OR s.quota_at IS NULL
  OR s.owner_id IS DISTINCT FROM p_owner OR s.scan_id IS DISTINCT FROM p_scan
  OR p_failure IS DISTINCT FROM 'cancelled_before_dispatch' OR p_point IS NULL OR p_point NOT IN ('sample','settle')
  OR (SELECT count(*) FROM internal.initial_cancellation_quota_statements WHERE scan_id=s.scan_id AND closed)
    <>2*jsonb_array_length(s.prestate->'charges')+2
  OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements WHERE scan_id=s.scan_id AND NOT closed)
 THEN RETURN FALSE; END IF;
 expected:=s.prestate->'quota'||jsonb_build_object('state','refunded','refund_count',1,'refunded_at',s.quota_at,'updated_at',s.quota_at);
 SELECT to_jsonb(t) INTO q FROM internal.ai_quota_reservations t WHERE id=(s.prestate#>>'{quota,id}')::UUID;
 SELECT to_jsonb(t) INTO hold FROM internal.complimentary_scan_usage t WHERE user_id=p_owner AND client_scan_id=p_scan;
 SELECT jsonb_build_object('id',t.id,'complimentary_entitlement_epoch',t.complimentary_entitlement_epoch,
  'entitlement_version',t.entitlement_version) INTO owner_epoch FROM public.users t WHERE id=p_owner;
 IF q IS DISTINCT FROM expected OR COALESCE(hold,'null'::JSONB) IS DISTINCT FROM s.prestate->'complimentary'
  OR owner_epoch IS DISTINCT FROM s.prestate->'owner_epoch'
  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters WHERE reservation_id=(s.prestate#>>'{quota,id}')::UUID)
  OR (SELECT to_jsonb(t) FROM internal.identification_provider_attempts t
    WHERE reservation_id=(s.prestate#>>'{quota,id}')::UUID AND attempt_count=1) IS DISTINCT FROM s.prestate->'attempt'
 THEN RETURN FALSE; END IF;
 SELECT * INTO w FROM internal.initial_cancellation_credit_witness WHERE scan_id=p_scan;
 IF p_point='sample' THEN RETURN NOT FOUND; END IF;
 RETURN COALESCE(FOUND AND w.phase='sampled' AND w.held AND w.credit_at IS NOT NULL AND w.events='[]'::JSONB,FALSE);
END; $$;

CREATE FUNCTION internal.initial_cancellation_lifecycle_authorized(p_old JSONB,p_new JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE s internal.initial_admitted_cancellation_staging; w internal.initial_cancellation_lifecycle_witness;
 credit internal.initial_cancellation_credit_witness; event JSONB;
BEGIN
 SELECT * INTO s FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR s.phase IS DISTINCT FROM 'quota' OR s.quota_at IS NULL THEN RETURN FALSE; END IF;
 SELECT * INTO w FROM internal.initial_cancellation_lifecycle_witness WHERE scan_id=s.scan_id;
 IF NOT FOUND OR w.phase IS DISTINCT FROM 'pending' OR w.event IS NOT NULL THEN RETURN FALSE; END IF;
 SELECT * INTO credit FROM internal.initial_cancellation_credit_witness WHERE scan_id=s.scan_id;
 IF NOT FOUND OR credit.phase IS DISTINCT FROM 'complete' THEN RETURN FALSE; END IF;
 event:=internal.initial_cancellation_lifecycle_event(s);
 IF event->'old' IS DISTINCT FROM p_old OR event->'new' IS DISTINCT FROM p_new THEN RETURN FALSE; END IF;
 PERFORM internal.assert_initial_admitted_cancellation_settlement(s.prestate,s.quota_at,credit.credit_at);
 RETURN TRUE;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_cancellation_quota_authorized(UUID,UUID,UUID,TEXT),
 internal.initial_cancellation_credit_authorized(UUID,UUID,TEXT,TEXT),
 internal.initial_cancellation_lifecycle_authorized(JSONB,JSONB) FROM PUBLIC,anon,authenticated,service_role;

DO $c1_original_owner_authority$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_get_functiondef('internal.finalize_ai_quota_reservation_core(uuid,uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$    IF internal.initial_admitted_settlement_blocked(reservation_row.original_analysis_id)
       OR internal.initial_admitted_settlement_blocked(reservation_row.request_id) THEN$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 quota authority seam drift'; END IF;
 EXECUTE replace(definition,anchor,$body$    IF (internal.initial_admitted_settlement_blocked(reservation_row.original_analysis_id)
       OR internal.initial_admitted_settlement_blocked(reservation_row.request_id))
       AND NOT internal.initial_cancellation_quota_authorized(p_reservation_id,p_user_id,p_lease_token,p_final_state) THEN$body$);
 SELECT pg_get_functiondef('internal.settle_complimentary_analysis(uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='        IF internal.initial_admitted_settlement_blocked(p_analysis) THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 credit authority seam drift'; END IF;
 EXECUTE replace(definition,anchor,$body$        IF internal.initial_admitted_settlement_blocked(p_analysis)
          AND NOT internal.initial_cancellation_credit_authorized(p_owner,p_analysis,p_failure,'settle') THEN$body$);
 SELECT pg_get_functiondef('internal.sample_initial_cancellation_credit_clock(uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$    IF stage.prestate->'complimentary'<>'null'::JSONB AND internal.initial_admitted_settlement_blocked(p_scan) THEN$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 credit sample authority seam drift'; END IF;
 EXECUTE replace(definition,anchor,$body$    IF stage.prestate->'complimentary'<>'null'::JSONB AND internal.initial_admitted_settlement_blocked(p_scan)
       AND NOT internal.initial_cancellation_credit_authorized(p_owner,p_scan,p_failure,'sample') THEN$body$);
 SELECT pg_get_functiondef('internal.guard_initial_lifecycle_fence()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='   AND internal.initial_admitted_settlement_blocked(OLD.scan_id) THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 lifecycle authority seam drift'; END IF;
 EXECUTE replace(definition,anchor,$body$   AND internal.initial_admitted_settlement_blocked(OLD.scan_id)
   AND NOT internal.initial_cancellation_lifecycle_authorized(to_jsonb(OLD),to_jsonb(NEW)) THEN$body$);
END; $c1_original_owner_authority$;

-- Explicit cancellation only. Generic cancellation remains the conservative
-- legacy/account-erasure owner and never inherits positive admitted authority.
CREATE FUNCTION internal.cancel_initial_analysis_explicit(p_owner UUID,p_scan UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE owned_by UUID; scan_exists BOOLEAN; submission internal.initial_analysis_submissions;
 saved internal.initial_analysis_cancellations; lifecycle TEXT;
 q internal.ai_quota_reservations; settlement JSONB;
BEGIN
 PERFORM internal.require_service_role();
 IF p_owner IS NULL OR p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||p_scan::TEXT,0::BIGINT));
 SELECT user_id INTO owned_by FROM public.scans WHERE id=p_scan FOR UPDATE; scan_exists:=FOUND;
 IF scan_exists AND owned_by IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_scan FOR UPDATE;
 SELECT state INTO lifecycle FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan FOR UPDATE;
 SELECT * INTO submission FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND submission.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND saved.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan) THEN RAISE EXCEPTION 'initial_analysis_deleted' USING ERRCODE='55000'; END IF;
 IF scan_exists OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_already_complete' USING ERRCODE='55000'; END IF;
 -- Saved terminal classification precedes any fresh proof inspection; erased
 -- evidence cannot upgrade unknown/dispatched into a prevented/refunded result.
 IF saved.scan_id IS NOT NULL OR lifecycle IS DISTINCT FROM 'pending_pre_dispatch'
  OR NOT internal.initial_admitted_settlement_blocked(p_scan) THEN
  RETURN internal.cancel_initial_analysis(p_owner,p_scan);
 END IF;
 -- Any admitted footprint, including paired permanent fences after damage or
 -- erasure, requires the complete positive proof. Invalid proof fails closed;
 -- no caught preflight/stage error may enter the generic erasure owner.
 INSERT INTO internal.initial_admitted_cancellation_staging(scan_id,owner_id) VALUES(p_scan,p_owner);
 SELECT (jsonb_populate_record(NULL::internal.ai_quota_reservations,prestate->'quota')).* INTO STRICT q
  FROM internal.initial_admitted_cancellation_staging WHERE scan_id=p_scan;
 IF NOT internal.finalize_ai_quota_reservation_core(q.id,p_owner,q.lease_token,'refunded') THEN
  RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000'; END IF;
 settlement:=internal.settle_complimentary_analysis(p_owner,p_scan,'cancelled_before_dispatch');
 IF (settlement->>'credit_released')::BOOLEAN IS DISTINCT FROM (q.complimentary_client_scan_id IS NOT NULL)
  OR (settlement->>'credit_consumed')::BOOLEAN IS DISTINCT FROM FALSE THEN
  RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,'cancelled_pre_dispatch','begin');
 UPDATE internal.initial_analysis_lifecycle_fences SET state='cancelled_pre_dispatch' WHERE scan_id=p_scan;
 PERFORM internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,'cancelled_pre_dispatch','end');
 PERFORM internal.retire_initial_preparation_source_objects(p_scan);
 PERFORM internal.retire_initial_media_objects(p_scan);
 PERFORM internal.erase_initial_cancellation_private_root(p_scan,'submission');
 PERFORM internal.erase_initial_cancellation_private_root(p_scan,'intent');
 PERFORM internal.write_initial_cancellation_receipt(p_scan);
 INSERT INTO internal.initial_cancellation_terminal_snapshot(scan_id) VALUES(p_scan);
 PERFORM internal.finish_initial_cancellation_consumption(p_scan);
 SELECT * INTO STRICT saved FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan AND owner_id=p_owner;
 RETURN jsonb_build_object('version',1,'outcome','cancelled','dispatch',saved.dispatch);
END; $$;
REVOKE ALL ON FUNCTION internal.cancel_initial_analysis_explicit(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
DO $c1_explicit_routing$
DECLARE definition TEXT; anchor TEXT:=' RETURN internal.cancel_initial_analysis(p_owner,p_scan);';
BEGIN
 SELECT pg_get_functiondef('public.cancel_initial_analysis(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'C1 public endpoint drift'; END IF;
 EXECUTE replace(definition,anchor,' RETURN internal.cancel_initial_analysis_explicit(p_owner,p_scan);');
END; $c1_explicit_routing$;
