SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN chat_context_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Ownership follows the existing message graph during account merge. Do not
-- duplicate owner, scan or conversation foreign keys in immutable context.
CREATE TABLE internal.insight_chat_turn_contexts (
    message_id UUID PRIMARY KEY REFERENCES public.insight_chat_messages(id) ON DELETE CASCADE,
    context_version INTEGER NOT NULL CHECK (context_version = 1),
    displayed_ticket JSONB NOT NULL,
    context_snapshot JSONB NOT NULL CHECK (
        pg_catalog.jsonb_typeof(context_snapshot) = 'object'
        AND pg_catalog.octet_length(context_snapshot::TEXT) <= 131072
    )
);
ALTER TABLE internal.insight_chat_turn_contexts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.insight_chat_turn_contexts FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER reject_insight_chat_context_update BEFORE UPDATE
ON internal.insight_chat_turn_contexts FOR EACH ROW
EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

-- Explicit scalar projection: unknown nested objects cannot smuggle media,
-- coordinates or private library payloads through a nominally allowed key.
CREATE FUNCTION internal.insight_chat_scalars(source JSONB, keys TEXT[], max_chars INTEGER DEFAULT 4000)
RETURNS JSONB LANGUAGE SQL STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT COALESCE(pg_catalog.jsonb_object_agg(key,
        CASE WHEN pg_catalog.jsonb_typeof(value)='string'
            THEN pg_catalog.to_jsonb(pg_catalog.left(value #>> '{}',max_chars)) ELSE value END),'{}'::JSONB)
    FROM pg_catalog.jsonb_each(CASE WHEN pg_catalog.jsonb_typeof(source)='object' THEN source ELSE '{}'::JSONB END)
    WHERE key=ANY(keys) AND pg_catalog.jsonb_typeof(value) IN ('null','boolean','number','string');
$$;
REVOKE ALL ON FUNCTION internal.insight_chat_scalars(JSONB,TEXT[],INTEGER) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION internal.insight_chat_context_projection(source JSONB)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path = '' AS $$
DECLARE result JSONB; key TEXT; value JSONB; items JSONB;
BEGIN
    result := internal.insight_chat_scalars(source,ARRAY[
        'timestamp','gps_elevation','weather_condition','weather_temperature_f','semantic_location',
        'current_month','time_of_day','depth_scale_text','ai_confidence_score','inference_tier',
        'ai_reasoning','image_quality_score','blur_score','zoom_factor','ecology_type','life_stage',
        'reproductive_condition','estimated_size_cm','individual_count','sex','sex_confidence','sex_evidence',
        'is_invasive','invasive_status_region','invasive_rationale','invasive_confidence','is_biological_subject',
        'user_identification_override','user_confirmed_identification','user_review_state',
        'confirmed_species_id','confirmed_species_identity_revision','species_id']);
    FOREACH key IN ARRAY ARRAY['extracted_visual_traits','colors','ecological_interactions'] LOOP
        SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.left(item #>> '{}',500) ORDER BY ordinal),'[]'::JSONB)
        INTO items FROM pg_catalog.jsonb_array_elements(CASE WHEN pg_catalog.jsonb_typeof(source->key)='array'
            THEN source->key ELSE '[]'::JSONB END) WITH ORDINALITY AS a(item,ordinal)
        WHERE ordinal<=10 AND pg_catalog.jsonb_typeof(item)='string';
        result:=result||pg_catalog.jsonb_build_object(key,items);
    END LOOP;
    FOREACH key IN ARRAY ARRAY['primary_identification','confirmed_species_identity','identification_provenance',
        'ai_identification_review','user_observation_context','pet_identification'] LOOP
        value:=source->key;
        IF value IS NULL OR value='null'::JSONB THEN
            result:=result||pg_catalog.jsonb_build_object(key,NULL); CONTINUE;
        END IF;
        value:=internal.insight_chat_scalars(value,CASE key
            WHEN 'primary_identification' THEN ARRAY['version','resolution','scientific_name','common_name']
            WHEN 'confirmed_species_identity' THEN ARRAY['version','species_id','scientific_name','common_name','gbif_taxon_key']
            WHEN 'identification_provenance' THEN ARRAY['version','provider','binding','model','variant','operation',
                'policy_version','prompt','schema','confidence','diagnostic_trigger','prompt_diagnostic_trigger','safety','timeout_ms']
            WHEN 'ai_identification_review' THEN ARRAY['version','revision','state','origin_scan_id','operation_id','operation_digest']
            WHEN 'user_observation_context' THEN ARRAY['free_text','freeText']
            ELSE ARRAY['species_group','label','label_type','confidence_score'] END);
        IF key='identification_provenance' THEN
            value:=value||pg_catalog.jsonb_build_object('generation',internal.insight_chat_scalars(source#>'{identification_provenance,generation}',
                ARRAY['temperature','seed','top_k','max_output_tokens','thinking_budget','reasoning_effort','image_detail']));
        ELSIF key='pet_identification' THEN
            SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.left(item#>>'{}',500) ORDER BY ordinal),'[]'::JSONB)
            INTO items FROM pg_catalog.jsonb_array_elements(CASE WHEN pg_catalog.jsonb_typeof(source#>'{pet_identification,evidence}')='array'
                THEN source#>'{pet_identification,evidence}' ELSE '[]'::JSONB END) WITH ORDINALITY AS a(item,ordinal)
                WHERE ordinal<=3 AND pg_catalog.jsonb_typeof(item)='string';
            value:=value||pg_catalog.jsonb_build_object('evidence',items);
        ELSIF key='ai_identification_review' THEN
            value:=value||pg_catalog.jsonb_build_object(
                'origin_identification',CASE WHEN pg_catalog.jsonb_typeof(source#>'{ai_identification_review,origin_identification}')='object'
                    THEN internal.insight_chat_scalars(source#>'{ai_identification_review,origin_identification}',ARRAY['scientific_name','common_name'],160) ELSE NULL END,
                'community',CASE WHEN pg_catalog.jsonb_typeof(source#>'{ai_identification_review,community}')='object'
                    THEN internal.insight_chat_scalars(source#>'{ai_identification_review,community}',ARRAY['request_id','rank','scientific_name','common_name','species_id'],160) ELSE NULL END);
        END IF;
        result:=result||pg_catalog.jsonb_build_object(key,value);
    END LOOP;
    SELECT COALESCE(pg_catalog.jsonb_agg(internal.insight_chat_scalars(item,
        ARRAY['scientific_name','common_name','confidence_score','distinguishing_feature'],500) ORDER BY ordinal),'[]'::JSONB)
    INTO items FROM pg_catalog.jsonb_array_elements(CASE WHEN pg_catalog.jsonb_typeof(source->'candidates')='array'
        THEN source->'candidates' ELSE '[]'::JSONB END) WITH ORDINALITY AS a(item,ordinal)
        WHERE ordinal<=6 AND pg_catalog.jsonb_typeof(item)='object';
    RETURN result||pg_catalog.jsonb_build_object('candidates',items);
END;
$$;
REVOKE ALL ON FUNCTION internal.insight_chat_context_projection(JSONB) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION internal.insight_chat_dictionary_context(species UUID)
RETURNS JSONB LANGUAGE SQL STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT internal.insight_chat_scalars(pg_catalog.to_jsonb(d),ARRAY[
        'id','scientific_name','wikipedia_overview','habitat_description','hazard_type','kingdom','phylum',
        'class','order','family','genus','iucn_red_list_status'])
        || pg_catalog.jsonb_build_object('common_names',internal.insight_chat_scalars(d.common_names,ARRAY['en'],255))
        || COALESCE((SELECT pg_catalog.jsonb_object_agg(key,(SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.left(item#>>'{}',255) ORDER BY ordinal),'[]'::JSONB)
            FROM pg_catalog.jsonb_array_elements(CASE WHEN pg_catalog.jsonb_typeof(value)='array' THEN value ELSE '[]'::JSONB END)
                WITH ORDINALITY AS a(item,ordinal) WHERE ordinal<=10 AND pg_catalog.jsonb_typeof(item)='string'))
            FROM pg_catalog.jsonb_each(pg_catalog.to_jsonb(d)) WHERE key IN ('alternative_common_names','similar_species','group_tags')),'{}'::JSONB)
    FROM public.species_dictionary d WHERE d.id=species;
$$;
REVOKE ALL ON FUNCTION internal.insight_chat_dictionary_context(UUID) FROM PUBLIC, anon, authenticated, service_role;

-- This prepared boundary does not dispatch a provider, settle quota or activate
-- the existing HTTP route. All inserts roll back together on any denial.
CREATE FUNCTION public.reserve_insight_chat_send_with_context(
    p_user_id UUID, p_conversation_id UUID, p_scan_id UUID, p_message_text TEXT,
    p_client_message_id UUID, p_displayed_ticket JSONB, p_context_version INTEGER
)
RETURNS TABLE(conversation_id UUID,message JSONB,is_replay BOOLEAN,sends_today INTEGER,context_snapshot JSONB)
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
DECLARE
    scan public.scans; history internal.observation_histories;
    evidence internal.observation_analysis_results; authority internal.observation_analysis_authorities;
    saved internal.insight_chat_turn_contexts; admitted RECORD;
    existing_id UUID; source JSONB; snapshot JSONB; prefix JSONB; effective JSONB;
    expected_ticket JSONB; selected_species UUID;
BEGIN
    PERFORM internal.require_service_role();
    IF p_user_id IS NULL OR p_scan_id IS NULL OR p_conversation_id IS NULL OR p_client_message_id IS NULL
        OR p_context_version IS DISTINCT FROM 1 OR p_displayed_ticket IS NULL
        OR pg_catalog.octet_length(p_displayed_ticket::TEXT)>1024 THEN
        RAISE EXCEPTION 'field_chat_invalid_request' USING ERRCODE='22023';
    END IF;
    -- Owner first matches history mutation/account deletion and avoids a lock
    -- upgrade after generic admission has obtained a weaker parent key lock.
    PERFORM id FROM public.users WHERE id=p_user_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'field_chat_subject_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian:field-chat:user:'||p_user_id::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian:field-chat:subject:insight:'||p_scan_id::TEXT||':user:'||p_user_id::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_scan_id::TEXT,0::BIGINT));
    SELECT * INTO scan FROM public.scans WHERE id=p_scan_id AND user_id=p_user_id AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan_id) THEN
        RAISE EXCEPTION 'field_chat_subject_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT m.id INTO existing_id FROM public.insight_chat_messages m
        JOIN public.insight_chat_conversations c ON c.id=m.conversation_id AND c.scan_id=m.scan_id AND c.user_id=m.user_id
        WHERE m.scan_id=p_scan_id AND m.user_id=p_user_id AND m.client_message_id=p_client_message_id AND m.role='user';
    IF existing_id IS NOT NULL THEN
        SELECT * INTO saved FROM internal.insight_chat_turn_contexts WHERE message_id=existing_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'field_chat_context_missing' USING ERRCODE='55000'; END IF;
        IF saved.displayed_ticket IS DISTINCT FROM p_displayed_ticket THEN
            RAISE EXCEPTION 'field_chat_idempotency_conflict' USING ERRCODE='23505';
        END IF;
        SELECT * INTO admitted FROM public.reserve_field_chat_send(p_user_id,p_conversation_id,'insight',p_scan_id,p_message_text,p_client_message_id);
        RETURN QUERY SELECT admitted.conversation_id,admitted.message,admitted.is_replay,admitted.sends_today,saved.context_snapshot;
        RETURN;
    END IF;
    IF NOT COALESCE((SELECT chat_context_enabled FROM internal.observation_history_rollout WHERE singleton),FALSE) THEN
        RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=p_scan_id FOR UPDATE;
    IF FOUND THEN
        IF NOT history.selection_initialized OR history.selected_analysis_id IS NULL OR history.state_revision<1 THEN
            RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
        END IF;
        SELECT * INTO evidence FROM internal.observation_analysis_results WHERE observation_id=p_scan_id AND analysis_id=history.selected_analysis_id;
        IF NOT FOUND OR evidence.result_snapshot->>'scan_id' IS DISTINCT FROM p_scan_id::TEXT THEN
            RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
        END IF;
        SELECT * INTO authority FROM internal.observation_analysis_authorities WHERE observation_id=p_scan_id AND analysis_id=history.selected_analysis_id;
        IF NOT FOUND OR NOT authority.review_snapshot ?& ARRAY['ai_identification_review','confirmed_species_identity',
            'confirmed_species_identity_revision','confirmed_species_id','user_identification_override','user_confirmed_identification','user_review_state']
            OR authority.review_snapshot-ARRAY['ai_identification_review','confirmed_species_identity','confirmed_species_identity_revision',
                'confirmed_species_id','user_identification_override','user_confirmed_identification','user_review_state']<>'{}'::JSONB THEN
            RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
        END IF;
        effective:=internal.observation_analysis_projection(evidence.result_snapshot,authority.review_snapshot);
        IF effective IS DISTINCT FROM history.active_projection THEN
            RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
        END IF;
        expected_ticket:=pg_catalog.jsonb_build_object('analysis_id',history.selected_analysis_id,
            'state_revision',history.state_revision,'review_revision',authority.review_revision);
        source:=evidence.result_snapshot||authority.review_snapshot;
    ELSE
        expected_ticket:='null'::JSONB;
        effective:=internal.scan_effective_identification(scan);
        source:=pg_catalog.to_jsonb(scan);
    END IF;
    IF p_displayed_ticket IS DISTINCT FROM expected_ticket THEN
        RAISE EXCEPTION 'field_chat_context_conflict' USING ERRCODE='40001';
    END IF;
    IF effective->>'source'='invalid' THEN RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000'; END IF;
    selected_species:=NULLIF(effective->>'species_id','')::UUID;
    source:=internal.insight_chat_context_projection(source)
        ||pg_catalog.jsonb_build_object('species_dictionary',internal.insight_chat_dictionary_context(selected_species),
            'confirmed_species',internal.insight_chat_dictionary_context(NULLIF(source->>'confirmed_species_id','')::UUID));
    -- Existing admission owns exact text, caps, cutover and conversation UUID.
    SELECT * INTO admitted FROM public.reserve_field_chat_send(p_user_id,p_conversation_id,'insight',p_scan_id,p_message_text,p_client_message_id);
    IF admitted.is_replay THEN RAISE EXCEPTION 'field_chat_context_missing' USING ERRCODE='55000'; END IF;
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('role',m.role,'text',pg_catalog.left(pg_catalog.btrim(m.message_text),900))
        ORDER BY m.created_at,m.id),'[]'::JSONB) INTO prefix
        FROM (SELECT prior.id,prior.role,prior.message_text,prior.created_at FROM public.insight_chat_messages prior
            WHERE prior.conversation_id=admitted.conversation_id AND prior.id<>(admitted.message->>'id')::UUID
            ORDER BY prior.created_at DESC,prior.id DESC LIMIT 12) m;
    snapshot:=pg_catalog.jsonb_build_object('context_version',1,
        'source_kind',CASE WHEN expected_ticket='null'::JSONB THEN 'legacy_scan_v1' ELSE 'analysis_history_v1' END,
        'displayed_ticket',expected_ticket,'scan_context',source,'conversation_prefix',prefix);
    INSERT INTO internal.insight_chat_turn_contexts(message_id,context_version,displayed_ticket,context_snapshot)
        VALUES((admitted.message->>'id')::UUID,1,expected_ticket,snapshot);
    RETURN QUERY SELECT admitted.conversation_id,admitted.message,FALSE,admitted.sends_today,snapshot;
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_insight_chat_send_with_context(UUID,UUID,UUID,TEXT,UUID,JSONB,INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_insight_chat_send_with_context(UUID,UUID,UUID,TEXT,UUID,JSONB,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.reserve_insight_chat_send_with_context(uuid,uuid,uuid,text,uuid,jsonb,integer)',
     'Default-off atomic immutable Insight turn context and idempotent admission; no provider execution.');

RESET statement_timeout;
RESET lock_timeout;
