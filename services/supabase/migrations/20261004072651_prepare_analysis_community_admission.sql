SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Private atomic preparation. No API grant, moderation bypass, or rollout.
ALTER TABLE internal.observation_history_rollout
    ADD COLUMN community_admission_enabled BOOLEAN NOT NULL DEFAULT FALSE;
CREATE TABLE internal.observation_community_admissions (
    operation_id UUID PRIMARY KEY,
    observation_id UUID NOT NULL,
    analysis_id UUID NOT NULL,
    owner_id UUID NOT NULL,
    request_id UUID NOT NULL UNIQUE,
    post_id UUID NOT NULL UNIQUE,
    intent JSONB NOT NULL CHECK(pg_catalog.octet_length(intent::TEXT)<=70000),
    receipt JSONB NOT NULL CHECK(pg_catalog.octet_length(receipt::TEXT)<=4096),
    FOREIGN KEY(observation_id,analysis_id) REFERENCES internal.observation_analysis_results(observation_id,analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_community_admissions_analysis_idx ON internal.observation_community_admissions(observation_id,analysis_id);
ALTER TABLE internal.observation_community_admissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_community_admissions FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_community_admission BEFORE INSERT OR UPDATE ON internal.observation_community_admissions
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_observation_community_admission_update BEFORE UPDATE ON internal.observation_community_admissions
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

-- Transient proof created only by the private admission owner, before the
-- request INSERT. The existing AFTER INSERT creation fence remains required.
CREATE TABLE internal.observation_community_admission_fences (
    request_id UUID PRIMARY KEY,
    post_id UUID NOT NULL,
    observation_id UUID NOT NULL,
    owner_id UUID NOT NULL,
    creation_transaction XID8 NOT NULL
);
ALTER TABLE internal.observation_community_admission_fences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_community_admission_fences FROM PUBLIC,anon,authenticated,service_role;

-- A sanitized public marker keeps readers from falling back to mutable private
-- scan fields, even if the private history is later erased. Media remains in
-- the existing, now frozen, post cohort; no private identities are exposed here.
CREATE TABLE public.explore_analysis_community_posts (
    post_id UUID PRIMARY KEY REFERENCES public.explore_posts(id) ON DELETE CASCADE
);
ALTER TABLE public.explore_analysis_community_posts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.explore_analysis_community_posts FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.explore_analysis_community_posts TO anon,authenticated,service_role;

DO $insert_guard$
DECLARE definition TEXT; marker TEXT:=E'BEGIN\n    IF TG_OP=';
BEGIN
    definition:=pg_catalog.pg_get_functiondef('internal.guard_enrolled_community_request()'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'community_admission_guard_source_drift'; END IF;
    EXECUTE replace(definition,marker,$new$BEGIN
    IF TG_OP='INSERT' AND EXISTS(SELECT 1 FROM internal.observation_community_admission_fences f
        WHERE f.request_id=NEW.id AND f.post_id=NEW.post_id AND f.observation_id=NEW.scan_id
        AND f.owner_id=NEW.requested_by AND f.creation_transaction=pg_catalog.pg_current_xact_id()) THEN
        RETURN NEW;
    END IF;
    IF TG_OP=$new$);
END;
$insert_guard$;

CREATE FUNCTION internal.admit_observation_community_request(p_owner UUID,p_operation UUID,p_observation UUID,p_analysis UUID,
    p_observation_revision INTEGER,p_review_revision INTEGER,p_taxonomy UUID,p_initial_taxon UUID,p_note TEXT,p_approved_media JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE history internal.observation_histories; authority internal.observation_analysis_authorities;
    saved internal.observation_community_admissions; evidence internal.observation_analysis_results;
    intent JSONB; receipt JSONB; identity JSONB; item JSONB; ordinal BIGINT;
    request UUID:=pg_catalog.gen_random_uuid(); post UUID:=pg_catalog.gen_random_uuid();
BEGIN
    PERFORM internal.require_service_role();
    IF p_owner IS NULL OR p_operation IS NULL OR p_observation IS NULL OR p_analysis IS NULL OR p_taxonomy IS NULL
        OR p_observation_revision IS NULL OR p_observation_revision NOT BETWEEN 0 AND 2147483646
        OR p_review_revision IS NULL OR p_review_revision NOT BETWEEN 0 AND 2147483646
        OR pg_catalog.char_length(p_note)>1000 OR pg_catalog.jsonb_typeof(p_approved_media) IS DISTINCT FROM 'array'
        OR pg_catalog.octet_length(p_approved_media::TEXT)>65536 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF pg_catalog.jsonb_array_length(p_approved_media) NOT BETWEEN 1 AND 6 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    -- These are server-approved PUBLIC copies. The eventual moderated publisher
    -- must prove analysis evidence ownership before calling; no private ticket,
    -- arbitrary client URL or raw private history payload is an admissible input.
    FOR item,ordinal IN SELECT value,ordinality FROM pg_catalog.jsonb_array_elements(p_approved_media) WITH ORDINALITY LOOP
        IF pg_catalog.jsonb_typeof(item) IS DISTINCT FROM 'object'
            OR NOT item ?& ARRAY['kind','url','thumbnail_url','order_index','duration_seconds','has_audio']
            OR item-ARRAY['kind','url','thumbnail_url','order_index','duration_seconds','has_audio']<>'{}'::JSONB
            OR item->>'kind' NOT IN ('image','video','audio')
            OR pg_catalog.jsonb_typeof(item->'kind') IS DISTINCT FROM 'string'
            OR pg_catalog.jsonb_typeof(item->'url') IS DISTINCT FROM 'string'
            OR pg_catalog.jsonb_typeof(item->'thumbnail_url') IS DISTINCT FROM 'string'
            OR item->'order_index' IS DISTINCT FROM pg_catalog.to_jsonb(ordinal-1)
            OR pg_catalog.jsonb_typeof(item->'has_audio') IS DISTINCT FROM 'boolean'
            OR item->>'url' !~ '^https://[^/?#@[:space:]]+/[^?#[:space:]]+$'
            OR item->>'thumbnail_url' !~ '^https://[^/?#@[:space:]]+/[^?#[:space:]]+$'
            OR item->>'url' ~ '/object/(sign|authenticated)/'
            OR item->>'thumbnail_url' ~ '/object/(sign|authenticated)/'
            OR pg_catalog.char_length(item->>'url')>2048 OR pg_catalog.char_length(item->>'thumbnail_url')>2048
            OR (item->'duration_seconds'<>'null'::JSONB AND pg_catalog.jsonb_typeof(item->'duration_seconds')<>'number') THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        IF item->'duration_seconds'<>'null'::JSONB AND (item->>'duration_seconds')::NUMERIC NOT BETWEEN 0 AND 3600 THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
    intent:=pg_catalog.jsonb_build_object('observation_revision',p_observation_revision,'review_revision',p_review_revision,
        'taxonomy_version_id',p_taxonomy,'initial_taxon_id',p_initial_taxon,'note',p_note,'media',p_approved_media);
    PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_observation::TEXT,0::BIGINT));
    PERFORM id FROM public.scans WHERE id=p_observation AND user_id=p_owner AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=p_observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO saved FROM internal.observation_community_admissions WHERE operation_id=p_operation;
    IF FOUND THEN
        IF ROW(saved.owner_id,saved.observation_id,saved.analysis_id,saved.intent) IS DISTINCT FROM ROW(p_owner,p_observation,p_analysis,intent) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN saved.receipt;
    END IF;
    IF (SELECT community_admission_enabled AND community_authority_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO authority FROM internal.observation_analysis_authorities WHERE observation_id=p_observation AND analysis_id=p_analysis FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF NOT history.selection_initialized OR history.state_revision<>p_observation_revision OR authority.review_revision<>p_review_revision THEN
        RAISE EXCEPTION 'analysis_history_revision_conflict' USING ERRCODE='40001';
    END IF;
    SELECT * INTO STRICT evidence FROM internal.observation_analysis_results WHERE observation_id=p_observation AND analysis_id=p_analysis;
    identity:=internal.observation_analysis_projection(evidence.result_snapshot,authority.review_snapshot);
    IF evidence.result_snapshot->'is_biological_subject' IS DISTINCT FROM 'true'::JSONB
        OR authority.review_snapshot->>'user_review_state' IS DISTINCT FROM 'unreviewed'
        OR NULLIF(authority.review_snapshot#>'{ai_identification_review,community}','null'::JSONB) IS NOT NULL
        OR EXISTS(SELECT 1 FROM pg_catalog.unnest(ARRAY[identity->>'scientific_name',identity->>'common_name']) name
            WHERE pg_catalog.lower(pg_catalog.btrim(COALESCE(name,''))) IN ('human','humans','human being','person','homo sapiens','homo sapien')) THEN
        RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
    END IF;
    IF p_taxonomy IS DISTINCT FROM public.active_taxonomy_version_id() OR (p_initial_taxon IS NOT NULL AND NOT EXISTS(
        SELECT 1 FROM public.taxon_nodes t WHERE t.id=p_initial_taxon AND t.taxonomy_version_id=p_taxonomy
        AND pg_catalog.lower(t.scientific_name) NOT IN ('homo sapiens','homo sapien','human')
        AND pg_catalog.lower(COALESCE(t.common_name,'')) NOT IN ('human','humans','human being','person'))) THEN
        RAISE EXCEPTION 'invalid_identification_review' USING ERRCODE='22023';
    END IF;
    -- Existing discussions are not silently rebound or replaced. A separate
    -- explicit shared-update contract must handle those observations.
    IF EXISTS(SELECT 1 FROM public.explore_posts WHERE scan_id=p_observation)
        OR EXISTS(SELECT 1 FROM public.explore_community_requests WHERE scan_id=p_observation) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    INSERT INTO public.explore_posts(id,user_id,scan_id,location_sharing,public_latitude,public_longitude,public_location_label)
    VALUES(post,p_owner,p_observation,'private',NULL,NULL,NULL);
    -- The ordinary post-insert trigger may have seeded legacy scan media. It is
    -- replaced before the immutable marker and before the transaction is visible.
    DELETE FROM public.explore_post_media WHERE post_id=post;
    INSERT INTO public.explore_post_media(post_id,kind,url,thumbnail_url,order_index,duration_seconds,has_audio)
    SELECT post,m.kind,m.url,m.thumbnail_url,m.order_index,m.duration_seconds,m.has_audio
    FROM pg_catalog.jsonb_to_recordset(p_approved_media) AS m(kind TEXT,url TEXT,thumbnail_url TEXT,order_index INTEGER,duration_seconds DOUBLE PRECISION,has_audio BOOLEAN);
    INSERT INTO public.explore_analysis_community_posts VALUES(post);
    INSERT INTO internal.observation_community_admission_fences VALUES(request,post,p_observation,p_owner,pg_catalog.pg_current_xact_id());
    INSERT INTO public.explore_community_requests(id,post_id,scan_id,requested_by,note,initial_taxon_node_id,taxonomy_version_id)
    VALUES(request,post,p_observation,p_owner,p_note,p_initial_taxon,p_taxonomy);
    PERFORM internal.bind_observation_community_request(p_owner,p_observation,p_analysis,request,p_observation_revision,p_review_revision);
    DELETE FROM internal.observation_community_admission_fences WHERE request_id=request;
    receipt:=pg_catalog.jsonb_build_object('schema_version',1,'operation_id',p_operation,'observation_id',p_observation,
        'analysis_id',p_analysis,'request_id',request,'post_id',post,'status','admitted');
    INSERT INTO internal.observation_community_admissions VALUES(p_operation,p_observation,p_analysis,p_owner,request,post,intent,receipt);
    RETURN receipt;
END;
$$;
REVOKE ALL ON FUNCTION internal.admit_observation_community_request(UUID,UUID,UUID,UUID,INTEGER,INTEGER,UUID,UUID,TEXT,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_observation_community_request_evidence()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF ROW(NEW.note,NEW.initial_taxon_node_id) IS DISTINCT FROM ROW(OLD.note,OLD.initial_taxon_node_id)
        AND EXISTS(SELECT 1 FROM public.explore_analysis_community_posts WHERE post_id=OLD.post_id) THEN
        RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_observation_community_request_evidence() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_community_request_evidence BEFORE UPDATE OF note,initial_taxon_node_id ON public.explore_community_requests
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_community_request_evidence();

-- Freeze public media from initial needs_id admission, not just after resolution.
DO $media_guard$
DECLARE definition TEXT; marker TEXT;
BEGIN
    definition:=pg_catalog.pg_get_functiondef('internal.guard_observation_publication_media()'::REGPROCEDURE);
    FOREACH marker IN ARRAY ARRAY['OLD.post_id','NEW.post_id'] LOOP
        IF strpos(definition,'EXISTS(SELECT 1 FROM public.explore_analysis_public_projection WHERE post_id='||marker||')')=0 THEN
            RAISE EXCEPTION 'community_admission_media_source_drift';
        END IF;
        definition:=replace(definition,'EXISTS(SELECT 1 FROM public.explore_analysis_public_projection WHERE post_id='||marker||')',
            '(EXISTS(SELECT 1 FROM public.explore_analysis_public_projection WHERE post_id='||marker||') OR EXISTS(SELECT 1 FROM public.explore_analysis_community_posts WHERE post_id='||marker||'))');
    END LOOP;
    EXECUTE definition;
    definition:=pg_catalog.pg_get_functiondef('public.refresh_explore_post_media(uuid)'::REGPROCEDURE);
    marker:='EXISTS(SELECT 1 FROM public.explore_analysis_public_projection WHERE post_id=target_post_id)';
    IF strpos(definition,marker)=0 THEN RAISE EXCEPTION 'community_admission_refresh_source_drift'; END IF;
    EXECUTE replace(definition,marker,'('||marker||' OR EXISTS(SELECT 1 FROM public.explore_analysis_community_posts WHERE post_id=target_post_id))');
END;
$media_guard$;

-- Preserve the existing service-mediated reader authorization and privacy
-- predicates. Pending requests use frozen public media and never private AI
-- suggestions/provenance. The feed already uses the same guarded post cohort.
DO $detail$
DECLARE definition TEXT; marker TEXT;
BEGIN
    definition:=pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    marker:='LEFT JOIN public.explore_analysis_public_projection published ON published.post_id=ep.id';
    IF strpos(definition,marker)=0 THEN RAISE EXCEPTION 'community_admission_detail_source_drift'; END IF;
    definition:=replace(definition,marker,marker||E'\n    LEFT JOIN public.explore_analysis_community_posts admitted ON admitted.post_id=ep.id');
    FOREACH marker IN ARRAY ARRAY['s.image_storage_urls[1]','COALESCE(suggestions.suggested_taxa, ''[]''::JSONB)','s.inference_tier','metrics.compatible'] LOOP
        IF strpos(definition,'published.post_id IS NULL THEN '||marker)=0 THEN RAISE EXCEPTION 'community_admission_private_detail_source_drift'; END IF;
        definition:=replace(definition,'published.post_id IS NULL THEN '||marker,'published.post_id IS NULL AND admitted.post_id IS NULL THEN '||marker);
    END LOOP;
    marker:='AND ((published.post_id IS NULL AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0)>0) OR (published.post_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.explore_projected_post_cards(self_id) card WHERE card.post_id=ep.id)))';
    IF strpos(definition,marker)=0 THEN RAISE EXCEPTION 'community_admission_visibility_source_drift'; END IF;
    definition:=replace(definition,marker,'AND ((admitted.post_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.explore_post_media m WHERE m.post_id=ep.id AND m.health_status<>''missing'')) OR (admitted.post_id IS NULL AND '||substr(marker,4)||'))');
    EXECUTE definition;
    -- After request removal, the old scan projection must not publish this
    -- cohort as an ordinary legacy Explore post. Resolution requires registration.
    definition:=pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    marker:='LEFT JOIN public.explore_analysis_public_projection AS published ON published.post_id=ep.id';
    IF strpos(definition,marker)=0 THEN RAISE EXCEPTION 'community_admission_explore_source_drift'; END IF;
    definition:=replace(definition,marker,marker||E'\n    LEFT JOIN public.explore_analysis_community_posts AS admitted ON admitted.post_id=ep.id');
    -- Patch a unique existing predicate rather than the first subquery WHERE.
    marker:='ep.unshared_at IS NULL';
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'community_admission_explore_visibility_source_drift'; END IF;
    EXECUTE replace(definition,marker,marker||' AND (admitted.post_id IS NULL OR published.post_id IS NOT NULL)');
END;
$detail$;

RESET statement_timeout;
RESET lock_timeout;
