-- Enrolled observations alone use the closed scientific allowlist. Legacy
-- retention stays unchanged. No history or publication activation is enabled.
SET lock_timeout = '5s';
SET statement_timeout = '2min';

CREATE FUNCTION internal.retained_identification_is_valid(value JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE PARALLEL SAFE SECURITY INVOKER SET search_path = '' AS $$
DECLARE key TEXT; keys CONSTANT TEXT[] := ARRAY['version','source','rank','scientific_name','common_name','species_id','verified','pending_review','is_biological_subject','ai_confidence_score','inference_tier','provenance_version','provider','binding','model','variant','operation','policy_version','prompt','schema','confidence_policy','safety','timeout_ms'];
BEGIN
    IF value IS NULL THEN RETURN TRUE; END IF;
    IF pg_catalog.jsonb_typeof(value) IS DISTINCT FROM 'object'
       OR pg_catalog.octet_length(value::TEXT)>4096
       OR NOT value ?& keys OR value-keys<>'{}'::JSONB
       OR value->'version' IS DISTINCT FROM '1'::JSONB
       OR value->>'source' NOT IN ('none','legacy','ai_primary','verified_selection')
       OR pg_catalog.jsonb_typeof(value->'source') IS DISTINCT FROM 'string'
       OR pg_catalog.jsonb_typeof(value->'verified') IS DISTINCT FROM 'boolean'
       OR pg_catalog.jsonb_typeof(value->'pending_review') IS DISTINCT FROM 'boolean' THEN RETURN FALSE; END IF;
    IF value->'rank'='null'::JSONB THEN
        IF value->>'source' NOT IN ('none','legacy')
           OR value->'scientific_name'<>'null'::JSONB OR value->'common_name'<>'null'::JSONB THEN RETURN FALSE; END IF;
    ELSIF NOT internal.primary_identification_is_valid(pg_catalog.jsonb_build_object(
        'version',1,'resolution',value->'rank','scientific_name',value->'scientific_name','common_name',value->'common_name')) THEN RETURN FALSE;
    END IF;
    IF value->'species_id'<>'null'::JSONB AND (
        pg_catalog.jsonb_typeof(value->'species_id')<>'string'
        OR value->>'species_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR (value->'rank'<>'null'::JSONB AND value->>'rank'<>'species')) THEN RETURN FALSE; END IF;
    IF value->'is_biological_subject'<>'null'::JSONB
       AND pg_catalog.jsonb_typeof(value->'is_biological_subject')<>'boolean' THEN RETURN FALSE; END IF;
    IF value->'ai_confidence_score'<>'null'::JSONB THEN
        IF pg_catalog.jsonb_typeof(value->'ai_confidence_score')<>'number' THEN RETURN FALSE; END IF;
        IF (value->>'ai_confidence_score')::NUMERIC NOT BETWEEN 0 AND 1 THEN RETURN FALSE; END IF;
    END IF;
    IF value->'inference_tier'<>'null'::JSONB AND (
        pg_catalog.jsonb_typeof(value->'inference_tier')<>'string' OR value->>'inference_tier' NOT IN ('flash','pro')) THEN RETURN FALSE; END IF;
    FOREACH key IN ARRAY ARRAY['provider','binding','model','variant','operation','prompt','schema','confidence_policy','safety'] LOOP
        IF value->key<>'null'::JSONB AND (pg_catalog.jsonb_typeof(value->key)<>'string'
            OR value->>key !~ '^[a-z][a-z0-9_.-]{0,79}$') THEN RETURN FALSE; END IF;
    END LOOP;
    IF value->'provenance_version' NOT IN ('null'::JSONB,'1'::JSONB,'2'::JSONB) THEN RETURN FALSE; END IF;
    FOREACH key IN ARRAY ARRAY['policy_version','timeout_ms'] LOOP
        IF value->key<>'null'::JSONB THEN
            IF pg_catalog.jsonb_typeof(value->key)<>'number' OR value->>key !~ '^[1-9][0-9]{0,8}$' THEN RETURN FALSE; END IF;
            IF key='timeout_ms' AND (value->>key)::BIGINT>999999 THEN RETURN FALSE; END IF;
        END IF;
    END LOOP;
    IF value->'verified'='true'::JSONB AND (
        value->>'source'<>'verified_selection' OR value->>'rank' IS DISTINCT FROM 'species'
        OR value->'species_id'='null'::JSONB OR value->'pending_review'<>'false'::JSONB) THEN RETURN FALSE; END IF;
    IF value->>'source'='verified_selection' AND (
        value->'pending_review'<>'false'::JSONB
        OR (value->>'rank'='species' AND value->'verified'<>'true'::JSONB)) THEN RETURN FALSE; END IF;
    IF value->'is_biological_subject'='false'::JSONB
       AND value->>'rank' IS DISTINCT FROM 'non_biological' THEN RETURN FALSE; END IF;
    IF value->>'rank'='non_biological' AND (
        value->'is_biological_subject' IS DISTINCT FROM 'false'::JSONB
        OR value->'species_id'<>'null'::JSONB OR value->'verified'<>'false'::JSONB) THEN RETURN FALSE; END IF;
    IF value->'provenance_version'='null'::JSONB THEN
        FOREACH key IN ARRAY ARRAY['provider','binding','model','variant','operation','policy_version','prompt','schema','confidence_policy','safety','timeout_ms'] LOOP
            IF value->key<>'null'::JSONB THEN RETURN FALSE; END IF;
        END LOOP;
    END IF;
    -- No selected result is a valid enrolled state; never synthesize a result.
    IF value->>'source'='none' THEN
        IF value->'verified'<>'false'::JSONB OR value->'pending_review'<>'false'::JSONB THEN RETURN FALSE; END IF;
        FOREACH key IN ARRAY keys LOOP
            IF key NOT IN ('version','source','verified','pending_review') AND value->key<>'null'::JSONB THEN RETURN FALSE; END IF;
        END LOOP;
    END IF;
    RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION internal.retained_identification_is_valid(JSONB) FROM PUBLIC,anon,authenticated,service_role;
-- Pure CHECK predicate; it exposes no stored observation or authority.
GRANT EXECUTE ON FUNCTION internal.retained_identification_is_valid(JSONB) TO anon,authenticated,service_role;

ALTER TABLE public.scans ADD COLUMN retained_identification JSONB;
ALTER TABLE public.scans ADD CONSTRAINT scans_retained_identification_check CHECK (
    internal.retained_identification_is_valid(retained_identification)
    AND (retained_identification IS NULL OR (user_id IS NULL AND is_tombstoned))
);
REVOKE INSERT(retained_identification), UPDATE(retained_identification) ON public.scans FROM PUBLIC,anon,authenticated;
COMMENT ON COLUMN public.scans.retained_identification IS
    'Ownerless enrolled-observation scientific facts, materialized before history erasure. Closed flat scalar allowlist; no private result JSON, evidence, review identity or inferred taxonomy version. Historical interpretation never authorizes species credit or publication.';

CREATE FUNCTION internal.observation_retained_identification(observation UUID)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path = '' AS $$
DECLARE history internal.observation_histories; evidence JSONB; authority JSONB;
    projection JSONB; provenance JSONB; facts JSONB;
BEGIN
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=observation;
    IF NOT FOUND THEN RETURN NULL; END IF;
    IF history.selected_analysis_id IS NOT NULL THEN
        SELECT result_snapshot INTO evidence FROM internal.observation_analysis_results
        WHERE observation_id=observation AND analysis_id=history.selected_analysis_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'scientific_retention_state_invalid' USING ERRCODE='55000'; END IF;
        SELECT review_snapshot INTO authority FROM internal.observation_analysis_authorities
        WHERE observation_id=observation AND analysis_id=history.selected_analysis_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'scientific_retention_state_invalid' USING ERRCODE='55000'; END IF;
        projection := internal.observation_analysis_projection(evidence,authority);
        IF projection IS DISTINCT FROM history.active_projection THEN
            RAISE EXCEPTION 'scientific_retention_state_invalid' USING ERRCODE='55000';
        END IF;
        provenance := NULLIF(evidence->'identification_provenance','null'::JSONB);
        IF NOT internal.identification_provenance_is_valid(provenance) THEN
            RAISE EXCEPTION 'scientific_retention_state_invalid' USING ERRCODE='55000';
        END IF;
    ELSIF history.active_projection IS NOT NULL THEN
        RAISE EXCEPTION 'scientific_retention_state_invalid' USING ERRCODE='55000';
    END IF;
    facts := pg_catalog.jsonb_build_object(
        'version',1,'source',COALESCE(projection->>'source','none'),
        'rank',projection->'rank','scientific_name',projection->'scientific_name',
        'common_name',projection->'common_name','species_id',projection->'species_id',
        'verified',COALESCE(projection->'verified','false'::JSONB),
        'pending_review',COALESCE(projection->'pending_review','false'::JSONB),
        'is_biological_subject',evidence->'is_biological_subject',
        'ai_confidence_score',evidence->'ai_confidence_score','inference_tier',evidence->'inference_tier',
        'provenance_version',provenance->'version','provider',provenance->'provider',
        'binding',provenance->'binding','model',provenance->'model','variant',provenance->'variant',
        'operation',provenance->'operation','policy_version',provenance->'policy_version',
        'prompt',provenance->'prompt','schema',provenance->'schema',
        'confidence_policy',provenance->'confidence','safety',provenance->'safety','timeout_ms',provenance->'timeout_ms');
    IF NOT internal.retained_identification_is_valid(facts) THEN
        RAISE EXCEPTION 'scientific_retention_state_invalid' USING ERRCODE='55000';
    END IF;
    RETURN facts;
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_retained_identification(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- A NULL composite plus explicit assignments excludes every unclassified field.
-- Future NOT NULL columns require classification rather than inheriting payloads.
CREATE FUNCTION internal.scientific_detached_observation(original public.scans, facts JSONB)
RETURNS public.scans LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path = '' AS $$
DECLARE retained public.scans;
BEGIN
    retained.id := original.id;
    retained.species_id := original.species_id;
    retained.timestamp := original.timestamp;
    retained.gps_lat_exact := original.gps_lat_exact;
    retained.gps_long_exact := original.gps_long_exact;
    retained.gps_lat_public := original.gps_lat_public;
    retained.gps_long_public := original.gps_long_public;
    retained.geoprivacy := original.geoprivacy;
    retained.coordinate_uncertainty_in_meters := original.coordinate_uncertainty_in_meters;
    retained.gps_elevation := original.gps_elevation;
    retained.weather_condition := original.weather_condition;
    retained.weather_temperature_f := original.weather_temperature_f;
    retained.ai_confidence_score := original.ai_confidence_score;
    retained.ecology_type := original.ecology_type;
    retained.is_invasive := original.is_invasive;
    retained.is_live_capture := original.is_live_capture;
    retained.is_verified := original.is_verified;
    retained.blur_score := original.blur_score;
    retained.current_month := original.current_month;
    retained.time_of_day := original.time_of_day;
    retained.life_stage := original.life_stage;
    retained.reproductive_condition := original.reproductive_condition;
    retained.individual_count := original.individual_count;
    retained.estimated_size_cm := original.estimated_size_cm;
    retained.inference_tier := original.inference_tier;
    retained.image_quality_score := original.image_quality_score;
    retained.is_biological_subject := original.is_biological_subject;
    retained.sex := original.sex;
    retained.sex_confidence := original.sex_confidence;
    retained.zoom_factor := original.zoom_factor;
    retained.invasive_confidence := original.invasive_confidence;
    retained.identification_provenance := original.identification_provenance;
    retained.primary_identification := original.primary_identification;
    retained.confirmed_species_identity_revision := original.confirmed_species_identity_revision;
    retained.user_id := NULL; retained.is_tombstoned := TRUE;
    retained.image_storage_urls := '{}'::TEXT[]; retained.video_storage_urls := '{}'::TEXT[];
    retained.audio_storage_urls := '{}'::TEXT[]; retained.custom_tags := '{}'::TEXT[];
    retained.colors := '{}'::TEXT[]; retained.llm_usage_metadata := '{}'::JSONB;
    retained.is_offline_queued := FALSE; retained.is_flagged := FALSE;
    retained.user_confirmed_identification := FALSE; retained.user_review_state := 'unreviewed';
    retained.retained_identification := facts;
    RETURN retained;
END;
$$;
REVOKE ALL ON FUNCTION internal.scientific_detached_observation(public.scans,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_retained_observation()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
DECLARE facts JSONB; expected public.scans;
BEGIN
    IF TG_OP='INSERT' THEN
        IF NEW.retained_identification IS NOT NULL THEN RAISE EXCEPTION 'scientific_retention_immutable' USING ERRCODE='22023'; END IF;
        RETURN NEW;
    END IF;
    IF OLD.retained_identification IS NOT NULL THEN
        IF pg_catalog.to_jsonb(NEW) IS DISTINCT FROM pg_catalog.to_jsonb(OLD) THEN
            RAISE EXCEPTION 'scientific_retention_immutable' USING ERRCODE='22023';
        END IF;
        RETURN NEW;
    END IF;
    IF OLD.user_id IS NOT NULL AND NEW.user_id IS NULL
       AND EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=OLD.id) THEN
        PERFORM internal.require_service_role();
        -- Direct service writes must not invert the normal user-first order.
        -- The authorized deletion transaction already owns these locks.
        PERFORM id FROM public.users WHERE id=OLD.user_id FOR UPDATE NOWAIT;
        IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||OLD.id::TEXT,0::BIGINT)) THEN
            RAISE EXCEPTION 'scientific_retention_busy' USING ERRCODE='55P03';
        END IF;
        facts := internal.observation_retained_identification(OLD.id);
        expected := internal.scientific_detached_observation(OLD,facts);
        IF pg_catalog.to_jsonb(NEW) IS DISTINCT FROM pg_catalog.to_jsonb(expected) THEN
            RAISE EXCEPTION 'scientific_retention_state_invalid' USING ERRCODE='55000';
        END IF;
    ELSIF NEW.retained_identification IS NOT NULL THEN
        RAISE EXCEPTION 'scientific_retention_immutable' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_retained_observation() FROM PUBLIC,anon,authenticated,service_role;
-- Final BEFORE check observes the normal review/location guard output.
CREATE TRIGGER zz_guard_retained_observation BEFORE INSERT OR UPDATE ON public.scans
FOR EACH ROW EXECUTE FUNCTION internal.guard_retained_observation();

-- Keep the existing full-row deleted-generation guard. Only its exact enrolled
-- detachment branch accepts the explicitly computed allowlisted row.
DO $generation_guard$
DECLARE definition TEXT; marker TEXT := '        IF TG_OP = ''UPDATE'' THEN';
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.reject_deleted_scan_generation_mutation()'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'scientific_retention_generation_source_drift';
    END IF;
    EXECUTE replace(definition,marker,marker||$branch$
            IF OLD.user_id IS NOT NULL AND NEW.user_id IS NULL AND NEW.is_tombstoned
               AND EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=OLD.id)
               AND pg_catalog.to_jsonb(NEW) IS NOT DISTINCT FROM pg_catalog.to_jsonb(
                   internal.scientific_detached_observation(OLD,internal.observation_retained_identification(OLD.id))) THEN
                RETURN NEW;
            END IF;
$branch$);
END;
$generation_guard$;

CREATE OR REPLACE FUNCTION public.apply_user_tombstone(target_user_id UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
DECLARE observation UUID; original public.scans; retained public.scans; facts JSONB; columns TEXT; values_sql TEXT;
BEGIN
    PERFORM internal.require_service_role();
    IF target_user_id IS NULL OR target_user_id='00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'account_deletion_invalid_user' USING ERRCODE='22023';
    END IF;
    PERFORM users.id FROM public.users AS users WHERE users.id=target_user_id FOR UPDATE;
    -- Preserve the publication/consensus lock order and fail without waiting.
    BEGIN
        PERFORM request.id FROM public.explore_community_requests request
        JOIN internal.observation_community_bindings binding ON binding.request_id=request.id
        WHERE binding.owner_id=target_user_id ORDER BY request.id FOR UPDATE OF request NOWAIT;
        PERFORM published.post_id FROM public.explore_analysis_public_projection published
        JOIN public.explore_posts post ON post.id=published.post_id
        WHERE post.user_id=target_user_id ORDER BY published.post_id FOR UPDATE OF published NOWAIT;
    EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END;
    -- Scientific columns are not SET, so coordinate triggers cannot recompute
    -- the preserved location. Existing review guards clear review on detach.
    -- Dynamic column assignment copies only the NULL-initialized allowlist
    -- record, never the original/private JSON. It also clears future nullable
    -- columns by default; a new required field fails until explicitly reviewed.
    SELECT pg_catalog.string_agg(pg_catalog.quote_ident(attname),',' ORDER BY attnum),
           pg_catalog.string_agg('($1).'||pg_catalog.quote_ident(attname),',' ORDER BY attnum)
    INTO columns,values_sql FROM pg_catalog.pg_attribute
    WHERE attrelid='public.scans'::REGCLASS AND attnum>0 AND NOT attisdropped AND attgenerated=''
      AND attname<>ALL(ARRAY['id','species_id','timestamp','gps_lat_exact','gps_long_exact','gps_lat_public','gps_long_public','geoprivacy','coordinate_uncertainty_in_meters','gps_elevation','weather_condition','weather_temperature_f','ai_confidence_score','ecology_type','is_invasive','is_live_capture','is_verified','blur_score','current_month','time_of_day','life_stage','reproductive_condition','individual_count','estimated_size_cm','inference_tier','image_quality_score','is_biological_subject','sex','sex_confidence','zoom_factor','invasive_confidence','identification_provenance','primary_identification','confirmed_species_identity_revision','confirmed_species_id','confirmed_species_identity','ai_identification_review','user_identification_override','user_confirmed_identification','user_review_state']::TEXT[]);
    FOR observation IN SELECT id FROM public.scans WHERE user_id=target_user_id ORDER BY id LOOP
        PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||observation::TEXT,0::BIGINT));
        SELECT * INTO original FROM public.scans WHERE id=observation AND user_id=target_user_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'scientific_retention_state_invalid' USING ERRCODE='55000'; END IF;
        PERFORM observation_id FROM internal.observation_histories WHERE observation_id=observation FOR UPDATE;
        IF FOUND THEN
            IF EXISTS(SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid='public.scans'::REGCLASS
                AND attnum>0 AND NOT attisdropped AND attgenerated<>'') THEN
                RAISE EXCEPTION 'scientific_retention_schema_unclassified' USING ERRCODE='55000';
            END IF;
            PERFORM r.analysis_id FROM internal.observation_analysis_results r
                JOIN internal.observation_histories h ON h.observation_id=r.observation_id AND h.selected_analysis_id=r.analysis_id
                WHERE r.observation_id=observation FOR SHARE OF r;
            PERFORM a.analysis_id FROM internal.observation_analysis_authorities a
                JOIN internal.observation_histories h ON h.observation_id=a.observation_id AND h.selected_analysis_id=a.analysis_id
                WHERE a.observation_id=observation FOR SHARE OF a;
            facts := internal.observation_retained_identification(observation);
            retained := internal.scientific_detached_observation(original,facts);
            EXECUTE 'UPDATE public.scans SET ('||columns||')=(SELECT '||values_sql||') WHERE id=$2'
                USING retained,observation;
        ELSE
            UPDATE public.scans SET user_id=NULL,is_tombstoned=TRUE,
                image_storage_urls='{}',video_storage_urls='{}',audio_storage_urls='{}',captured_media=NULL,
                semantic_location=NULL,public_location_label=NULL,device_locale=NULL,device_time_zone=NULL,
                user_observation_context=NULL,custom_tags='{}',human_intervention_notes=NULL WHERE id=observation;
        END IF;
    END LOOP;
    DELETE FROM public.users WHERE id=target_user_id;
END;
$$;
REVOKE ALL ON FUNCTION public.apply_user_tombstone(UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.apply_user_tombstone(UUID) TO service_role;
COMMENT ON FUNCTION public.apply_user_tombstone(UUID) IS
    'Service-only account detachment. Enrolled observations retain original allowlisted science plus separate acknowledged flat scalar facts before private history cascades. Legacy retention remains unchanged.';
RESET statement_timeout;
RESET lock_timeout;
