SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Additive version-1 producer correction only. Never rewrite immutable turns.
CREATE OR REPLACE FUNCTION internal.insight_chat_context_projection(source JSONB)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path = '' AS $$
DECLARE result JSONB; key TEXT; value JSONB; items JSONB;
BEGIN
    IF pg_catalog.jsonb_typeof(source) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
    END IF;
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
    -- Preserve semantic nullness and rank. Invalid evidence cannot become an
    -- apparently empty candidate set through sanitization.
    items:=source->'candidates';
    IF items IS NULL OR items='null'::JSONB THEN
        items:='null'::JSONB;
    ELSE
        IF pg_catalog.jsonb_typeof(items) IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
        END IF;
        IF pg_catalog.jsonb_array_length(items)>6 OR EXISTS (
            SELECT 1 FROM pg_catalog.jsonb_array_elements(items) AS a(item)
            WHERE pg_catalog.jsonb_typeof(item) IS DISTINCT FROM 'object'
        ) THEN
            RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
        END IF;
        SELECT COALESCE(pg_catalog.jsonb_agg(internal.insight_chat_scalars(item,
            ARRAY['taxon_rank','scientific_name','common_name','confidence_score','distinguishing_feature'],500)
            ORDER BY ordinal),'[]'::JSONB)
        INTO items FROM pg_catalog.jsonb_array_elements(items) WITH ORDINALITY AS a(item,ordinal);
    END IF;
    -- Qualification is evaluated on the untouched source, before dropping
    -- unknown metadata. Missing provenance differs from explicit legacy null.
    RETURN result||pg_catalog.jsonb_build_object('candidates',items,
        'metrics_qualified',COALESCE(source?'identification_provenance' AND
            internal.identification_metrics_are_gemini_compatible(
                NULLIF(source->'identification_provenance','null'::JSONB),source->>'inference_tier'),FALSE));
END;
$$;
REVOKE ALL ON FUNCTION internal.insight_chat_context_projection(JSONB) FROM PUBLIC, anon, authenticated, service_role;

RESET lock_timeout;
RESET statement_timeout;
