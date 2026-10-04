SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Registration remains private. The moderated atomic publisher is a separate
-- activation requirement; this migration introduces no API writer or scheduler.
ALTER TABLE internal.observation_history_rollout
    ADD COLUMN publication_snapshot_enabled BOOLEAN NOT NULL DEFAULT FALSE;
CREATE TABLE internal.observation_analysis_publications (
    publication_id UUID PRIMARY KEY,
    post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    observation_id UUID NOT NULL,
    analysis_id UUID NOT NULL,
    owner_id UUID NOT NULL,
    request_id UUID NOT NULL REFERENCES internal.observation_community_bindings(request_id) ON DELETE CASCADE,
    publication_version INTEGER NOT NULL CHECK(publication_version BETWEEN 1 AND 2147483646),
    observation_revision INTEGER NOT NULL,
    review_revision INTEGER NOT NULL,
    original_identity JSONB NOT NULL CHECK(pg_catalog.octet_length(original_identity::TEXT)<=4096),
    media_manifest JSONB NOT NULL CHECK(pg_catalog.jsonb_typeof(media_manifest)='array'
        AND pg_catalog.jsonb_array_length(media_manifest) BETWEEN 1 AND 6
        AND pg_catalog.octet_length(media_manifest::TEXT)<=65536),
    UNIQUE(post_id,publication_version),
    FOREIGN KEY(observation_id,analysis_id) REFERENCES internal.observation_analysis_results(observation_id,analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_analysis_publications_analysis_idx ON internal.observation_analysis_publications(observation_id,analysis_id);
CREATE INDEX observation_analysis_publications_request_idx ON internal.observation_analysis_publications(request_id);
ALTER TABLE internal.observation_analysis_publications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_analysis_publications FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_publication_generation BEFORE INSERT OR UPDATE ON internal.observation_analysis_publications
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_observation_publication_update BEFORE UPDATE ON internal.observation_analysis_publications
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

-- This is an allowlisted public projection, never a history/authority mirror.
-- Keep a row even after authority/history removal so readers never fall back to
-- the legacy scan's identity. Privacy still comes from the existing post guards.
CREATE TABLE public.explore_analysis_public_projection (
    post_id UUID PRIMARY KEY REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    publication_version INTEGER NOT NULL CHECK(publication_version BETWEEN 1 AND 2147483646),
    species_id UUID,
    scientific_name TEXT,
    common_name TEXT,
    identification JSONB,
    CHECK(scientific_name IS NULL OR pg_catalog.char_length(scientific_name)<=500),
    CHECK(common_name IS NULL OR pg_catalog.char_length(common_name)<=500),
    CHECK(identification IS NULL OR (
        pg_catalog.jsonb_typeof(identification)='object'
        AND identification ?& ARRAY['version','rank','label_source','original_rank','original_scientific_name','original_common_name']
        AND identification-ARRAY['version','rank','label_source','original_rank','original_scientific_name','original_common_name']='{}'::JSONB
        AND identification->'version'='1'::JSONB
        AND identification->>'rank' IN ('species','genus')
        AND identification->>'label_source'='community'
        AND pg_catalog.octet_length(identification::TEXT)<=4096)),
    CHECK(identification IS NOT NULL OR (species_id IS NULL AND scientific_name IS NULL AND common_name IS NULL))
);
ALTER TABLE public.explore_analysis_public_projection ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.explore_analysis_public_projection FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.explore_analysis_public_projection TO anon,authenticated,service_role;
CREATE POLICY "Visible owner publication labels" ON public.explore_analysis_public_projection FOR SELECT TO authenticated
USING (EXISTS(SELECT 1 FROM public.explore_posts p JOIN public.scans s ON s.id=p.scan_id
    WHERE p.id=post_id AND p.user_id=(SELECT auth.uid()) AND p.unshared_at IS NULL
    AND p.moderated_at IS NULL AND p.media_health_status<>'quarantined' AND NOT s.is_tombstoned));

-- Every owner/history writer uses NOWAIT here: request-first consensus can hold
-- this row before its notification FK waits on the owner. Roll back and retry
-- the whole operation rather than adding an owner -> public-row wait cycle.
CREATE FUNCTION internal.refresh_observation_publication(p_post UUID,p_invalidate BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE publication internal.observation_analysis_publications; authority internal.observation_analysis_authorities;
    work internal.observation_community_reconciliation; request public.explore_community_requests;
    identity JSONB; labels JSONB; visible_species UUID; scientific TEXT; common TEXT;
BEGIN
    BEGIN
        PERFORM post_id FROM public.explore_analysis_public_projection WHERE post_id=p_post FOR UPDATE NOWAIT;
    EXCEPTION WHEN lock_not_available THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END;
    IF NOT FOUND THEN RETURN; END IF;
    IF NOT p_invalidate THEN
        SELECT p.* INTO publication FROM internal.observation_analysis_publications p
        JOIN public.explore_analysis_public_projection v ON v.post_id=p.post_id AND v.publication_version=p.publication_version
        WHERE p.post_id=p_post;
        IF FOUND THEN
            SELECT * INTO authority FROM internal.observation_analysis_authorities WHERE analysis_id=publication.analysis_id;
            SELECT * INTO work FROM internal.observation_community_reconciliation WHERE request_id=publication.request_id;
            SELECT * INTO request FROM public.explore_community_requests WHERE id=publication.request_id;
            IF NOT work.superseded AND work.source_revision=work.applied_source_revision
                AND authority.review_revision=work.applied_review_revision
                AND request.status='resolved' AND request.withdrawn_at IS NULL
                AND authority.review_snapshot#>>'{ai_identification_review,community,request_id}'=publication.request_id::TEXT THEN
                identity := internal.observation_analysis_projection(
                    (SELECT result_snapshot FROM internal.observation_analysis_results WHERE analysis_id=publication.analysis_id),authority.review_snapshot);
                IF identity->>'rank' IN ('species','genus') AND identity->>'source'='verified_selection'
                    AND COALESCE((identity->>'pending_review')::BOOLEAN,FALSE)=FALSE
                    AND NOT EXISTS(SELECT 1 FROM pg_catalog.unnest(ARRAY[identity->>'scientific_name',identity->>'common_name']) name
                        WHERE pg_catalog.lower(pg_catalog.btrim(COALESCE(name,''))) IN ('human','humans','human being','person','homo sapiens','homo sapien')) THEN
                    scientific := identity->>'scientific_name'; common := identity->>'common_name';
                    visible_species := CASE WHEN identity->>'rank'='species' AND identity->>'verified'='true' THEN (identity->>'species_id')::UUID END;
                    labels := publication.original_identity || pg_catalog.jsonb_build_object('version',1,'rank',identity->>'rank','label_source','community');
                END IF;
            END IF;
        END IF;
    END IF;
    UPDATE public.explore_analysis_public_projection SET species_id=visible_species,scientific_name=scientific,common_name=common,identification=labels
    WHERE post_id=p_post;
END;
$$;
REVOKE ALL ON FUNCTION internal.refresh_observation_publication(UUID,BOOLEAN) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.sync_observation_publication()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE target UUID; invalidate BOOLEAN;
BEGIN
    IF TG_TABLE_NAME='observation_analysis_publications' THEN
        PERFORM internal.refresh_observation_publication(OLD.post_id,TRUE);
    ELSIF TG_TABLE_NAME='observation_analysis_authorities' THEN
        FOR target IN SELECT post_id FROM internal.observation_analysis_publications WHERE analysis_id=NEW.analysis_id ORDER BY post_id LOOP
            PERFORM internal.refresh_observation_publication(target,TRUE);
        END LOOP;
    ELSE
        invalidate := NEW.source_revision<>NEW.applied_source_revision OR NEW.superseded;
        FOR target IN SELECT post_id FROM internal.observation_analysis_publications WHERE request_id=NEW.request_id ORDER BY post_id LOOP
            PERFORM internal.refresh_observation_publication(target,invalidate);
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.sync_observation_publication() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER invalidate_observation_publication AFTER UPDATE ON internal.observation_analysis_authorities
FOR EACH ROW EXECUTE FUNCTION internal.sync_observation_publication();
CREATE TRIGGER reconcile_observation_publication AFTER UPDATE ON internal.observation_community_reconciliation
FOR EACH ROW EXECUTE FUNCTION internal.sync_observation_publication();
CREATE TRIGGER erase_observation_publication_authority AFTER DELETE ON internal.observation_analysis_publications
FOR EACH ROW EXECUTE FUNCTION internal.sync_observation_publication();

CREATE FUNCTION internal.register_observation_publication(p_owner UUID,p_request UUID,p_publication UUID,
    p_observation_revision INTEGER,p_review_revision INTEGER,p_approved_media JSONB)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE binding internal.observation_community_bindings; history internal.observation_histories;
    authority internal.observation_analysis_authorities; saved internal.observation_analysis_publications;
    request public.explore_community_requests; manifest JSONB; original JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF p_publication IS NULL OR p_observation_revision IS NULL OR p_review_revision IS NULL
        OR p_observation_revision NOT BETWEEN 0 AND 2147483646 OR p_review_revision NOT BETWEEN 0 AND 2147483646
        OR pg_catalog.jsonb_typeof(p_approved_media) IS DISTINCT FROM 'array'
        OR pg_catalog.octet_length(p_approved_media::TEXT)>65536 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO binding FROM internal.observation_community_bindings WHERE request_id=p_request AND owner_id=p_owner;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||binding.observation_id::TEXT,0::BIGINT));
    PERFORM id FROM public.scans WHERE id=binding.observation_id AND user_id=p_owner AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=binding.observation_id) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=binding.observation_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO saved FROM internal.observation_analysis_publications WHERE publication_id=p_publication;
    IF FOUND THEN
        IF ROW(saved.owner_id,saved.request_id,saved.observation_revision,saved.review_revision,saved.media_manifest)
            IS DISTINCT FROM ROW(p_owner,p_request,p_observation_revision,p_review_revision,p_approved_media) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN;
    END IF;
    IF (SELECT publication_snapshot_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO authority FROM internal.observation_analysis_authorities WHERE analysis_id=binding.analysis_id FOR UPDATE;
    IF NOT history.selection_initialized OR history.state_revision<>p_observation_revision OR authority.review_revision<>p_review_revision THEN
        RAISE EXCEPTION 'analysis_history_revision_conflict' USING ERRCODE='40001';
    END IF;
    BEGIN
        PERFORM request_id FROM internal.observation_community_reconciliation WHERE request_id=p_request FOR UPDATE NOWAIT;
        SELECT * INTO request FROM public.explore_community_requests WHERE id=p_request FOR UPDATE NOWAIT;
        PERFORM id FROM public.explore_posts WHERE id=binding.post_id AND scan_id=binding.observation_id AND user_id=p_owner
            AND unshared_at IS NULL AND moderated_at IS NULL AND media_health_status<>'quarantined' FOR UPDATE NOWAIT;
        IF NOT FOUND OR request.status IS DISTINCT FROM 'resolved' OR request.withdrawn_at IS NOT NULL OR request.explore_published_at IS NULL THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
        END IF;
        PERFORM id FROM public.explore_post_media WHERE post_id=binding.post_id ORDER BY id FOR UPDATE NOWAIT;
    EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END;
    IF EXISTS(SELECT 1 FROM public.explore_analysis_public_projection WHERE post_id=binding.post_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('kind',kind,'url',url,'thumbnail_url',thumbnail_url,
        'order_index',order_index,'duration_seconds',duration_seconds,'has_audio',has_audio) ORDER BY order_index) INTO manifest
    FROM public.explore_post_media WHERE post_id=binding.post_id;
    IF manifest IS DISTINCT FROM p_approved_media OR pg_catalog.jsonb_array_length(manifest) NOT BETWEEN 1 AND 6
        OR EXISTS(SELECT 1 FROM public.explore_post_media WHERE post_id=binding.post_id
            AND (url !~ '^https://[^?#]+$' OR thumbnail_url IS NULL OR thumbnail_url !~ '^https://[^?#]+$'
                OR url LIKE '%/object/sign/%' OR url LIKE '%/object/authenticated/%'
                OR thumbnail_url LIKE '%/object/sign/%' OR thumbnail_url LIKE '%/object/authenticated/%')) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    SELECT pg_catalog.jsonb_build_object('original_rank',result_snapshot#>'{primary_identification,resolution}',
        'original_scientific_name',result_snapshot#>'{primary_identification,scientific_name}',
        'original_common_name',result_snapshot#>'{primary_identification,common_name}') INTO original
    FROM internal.observation_analysis_results WHERE analysis_id=binding.analysis_id;
    IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('merian-analysis-publication-references',0::BIGINT)) THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    -- The dictionary compatibility cache can outlive a normalized reference row.
    -- Remove only URLs attributed to this post; preserve all other fallback URLs.
    UPDATE public.species_dictionary species SET reference_image_url=(
        SELECT pg_catalog.string_agg(pg_catalog.btrim(item.url),',' ORDER BY item.ordinality)
        FROM pg_catalog.unnest(pg_catalog.string_to_array(species.reference_image_url,',')) WITH ORDINALITY item(url,ordinality)
        WHERE NOT EXISTS(SELECT 1 FROM public.species_reference_image_merian_sources source
            WHERE source.explore_post_id=binding.post_id AND source.species_id=species.id AND source.image_url=pg_catalog.btrim(item.url)))
    WHERE species.reference_image_url IS NOT NULL AND EXISTS(SELECT 1 FROM public.species_reference_image_merian_sources source
        WHERE source.explore_post_id=binding.post_id AND source.species_id=species.id
            AND EXISTS(SELECT 1 FROM pg_catalog.unnest(pg_catalog.string_to_array(species.reference_image_url,',')) item(url) WHERE pg_catalog.btrim(item.url)=source.image_url));
    DELETE FROM public.species_reference_images ref USING public.species_reference_image_merian_sources source
    WHERE source.explore_post_id=binding.post_id AND ref.source='merian'
        AND (source.reference_image_id=ref.id OR (source.reference_image_id IS NULL AND source.species_id=ref.species_id AND source.image_url=ref.url));
    UPDATE public.species_reference_image_merian_sources SET reference_image_id=NULL,is_promoted=FALSE,disqualified_at=pg_catalog.now(),updated_at=pg_catalog.now()
    WHERE explore_post_id=binding.post_id;
    INSERT INTO internal.observation_analysis_publications VALUES(p_publication,binding.post_id,binding.observation_id,binding.analysis_id,
        p_owner,p_request,1,p_observation_revision,p_review_revision,original,manifest);
    INSERT INTO public.explore_analysis_public_projection(post_id,publication_version) VALUES(binding.post_id,1);
    PERFORM internal.refresh_observation_publication(binding.post_id,FALSE);
    IF NOT EXISTS(SELECT 1 FROM public.explore_analysis_public_projection WHERE post_id=binding.post_id AND identification IS NOT NULL) THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.register_observation_publication(UUID,UUID,UUID,INTEGER,INTEGER,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_observation_publication_media()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF TG_OP='UPDATE' AND ROW(NEW.id,NEW.post_id,NEW.kind,NEW.url,NEW.thumbnail_url,NEW.order_index,NEW.duration_seconds,NEW.has_audio)
        IS NOT DISTINCT FROM ROW(OLD.id,OLD.post_id,OLD.kind,OLD.url,OLD.thumbnail_url,OLD.order_index,OLD.duration_seconds,OLD.has_audio) THEN RETURN NEW; END IF;
    IF TG_OP='DELETE' AND NOT EXISTS(SELECT 1 FROM public.explore_posts WHERE id=OLD.post_id AND unshared_at IS NULL) THEN RETURN OLD; END IF;
    IF (TG_OP<>'INSERT' AND EXISTS(SELECT 1 FROM public.explore_analysis_public_projection WHERE post_id=OLD.post_id))
        OR (TG_OP<>'DELETE' AND EXISTS(SELECT 1 FROM public.explore_analysis_public_projection WHERE post_id=NEW.post_id)) THEN
        RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE='22023';
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_observation_publication_media() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_publication_media BEFORE INSERT OR UPDATE OR DELETE ON public.explore_post_media
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_publication_media();


-- Replace exact reviewed fragments and abort on source drift; preserve each
-- function signature, invoker/definer boundary, grant and unrelated predicate.
DO $patch0$
DECLARE definition TEXT; marker TEXT := $old$BEGIN
$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.explore_effective_species_id(public.scans,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: internal.explore_effective_species_id(public.scans,uuid) fragment 0';
    END IF;
    EXECUTE replace(definition,marker,$new$BEGIN
    IF EXISTS(SELECT 1 FROM public.explore_analysis_public_projection WHERE post_id=target_post_id) THEN
        RETURN (SELECT species_id FROM public.explore_analysis_public_projection WHERE post_id=target_post_id);
    END IF;
$new$);
END;
$patch0$;
DO $patch1$
DECLARE definition TEXT; marker TEXT := $old$BEGIN
$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.explore_identification_labels(public.scans,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: internal.explore_identification_labels(public.scans,uuid) fragment 1';
    END IF;
    EXECUTE replace(definition,marker,$new$BEGIN
    IF EXISTS(SELECT 1 FROM public.explore_analysis_public_projection WHERE post_id=target_post_id) THEN
        RETURN (SELECT identification FROM public.explore_analysis_public_projection WHERE post_id=target_post_id);
    END IF;
$new$);
END;
$patch1$;
DO $patch2$
DECLARE definition TEXT; marker TEXT := $old$    -- This invoker reads persisted rows$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 2';
    END IF;
    EXECUTE replace(definition,marker,$new$    LEFT JOIN public.explore_analysis_public_projection AS published ON published.post_id=ep.id
    -- This invoker reads persisted rows$new$);
END;
$patch2$;
DO $patch3$
DECLARE definition TEXT; marker TEXT := $old$CASE WHEN identity.value ->> 'source' = 'legacy' OR projection.projection_state = 'community_resolved' THEN public.explore_post_community_common_name($old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 3';
    END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NOT NULL THEN COALESCE(published.common_name,published.scientific_name,'Identification unresolved') WHEN identity.value ->> 'source' = 'legacy' OR projection.projection_state = 'community_resolved' THEN public.explore_post_community_common_name($new$);
END;
$patch3$;
DO $patch4$
DECLARE definition TEXT; marker TEXT := $old$CASE WHEN identity.value ->> 'source' = 'legacy' OR projection.projection_state = 'community_resolved' THEN public.explore_post_community_scientific_name($old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 4';
    END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NOT NULL THEN COALESCE(published.scientific_name,'') WHEN identity.value ->> 'source' = 'legacy' OR projection.projection_state = 'community_resolved' THEN public.explore_post_community_scientific_name($new$);
END;
$patch4$;
DO $patch5$
DECLARE definition TEXT; marker TEXT := $old$CASE WHEN identity.value ->> 'source' = 'verified_selection' THEN NULL ELSE scans.pet_identification END$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 5';
    END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NOT NULL OR identity.value ->> 'source' = 'verified_selection' THEN NULL ELSE scans.pet_identification END$new$);
END;
$patch5$;
DO $patch6$
DECLARE definition TEXT; marker TEXT := $old$        scans.time_of_day,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 6';
    END IF;
    EXECUTE replace(definition,marker,$new$        CASE WHEN published.post_id IS NULL THEN scans.time_of_day END AS time_of_day,$new$);
END;
$patch6$;
DO $patch7$
DECLARE definition TEXT; marker TEXT := $old$        scans.current_month,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 7';
    END IF;
    EXECUTE replace(definition,marker,$new$        CASE WHEN published.post_id IS NULL THEN scans.current_month END AS current_month,$new$);
END;
$patch7$;
DO $patch8$
DECLARE definition TEXT; marker TEXT := $old$        scans.weather_condition,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 8';
    END IF;
    EXECUTE replace(definition,marker,$new$        CASE WHEN published.post_id IS NULL THEN scans.weather_condition END AS weather_condition,$new$);
END;
$patch8$;
DO $patch9$
DECLARE definition TEXT; marker TEXT := $old$        scans.weather_temperature_f,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 9';
    END IF;
    EXECUTE replace(definition,marker,$new$        CASE WHEN published.post_id IS NULL THEN scans.weather_temperature_f END AS weather_temperature_f,$new$);
END;
$patch9$;
DO $patch10$
DECLARE definition TEXT; marker TEXT := $old$CASE WHEN identity.value ->> 'source' = 'invalid' THEN NULL$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 10';
    END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NOT NULL THEN published.identification WHEN identity.value ->> 'source' = 'invalid' THEN NULL$new$);
END;
$patch10$;
DO $patch11$
DECLARE definition TEXT; marker TEXT := $old$        SELECT CASE
            WHEN scans.primary_identification IS NULL$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 11';
    END IF;
    EXECUTE replace(definition,marker,$new$        SELECT CASE
            WHEN published.post_id IS NOT NULL THEN 'analysis_publication'
            WHEN scans.primary_identification IS NULL$new$);
END;
$patch11$;
DO $patch12$
DECLARE definition TEXT; marker TEXT := $old$        SELECT CASE identity_source.source
$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 12';
    END IF;
    EXECUTE replace(definition,marker,$new$        SELECT CASE identity_source.source
            WHEN 'analysis_publication' THEN pg_catalog.jsonb_build_object('source','analysis_publication',
                'rank',COALESCE(published.identification->>'rank','unresolved_biological'),
                'scientific_name',published.scientific_name,'common_name',published.common_name,'species_id',published.species_id)
$new$);
END;
$patch12$;
DO $patch13$
DECLARE definition TEXT; marker TEXT := $old$ON species.id = CASE WHEN projection.projection_state = 'community_resolved' THEN$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 13';
    END IF;
    EXECUTE replace(definition,marker,$new$ON species.id = CASE WHEN published.post_id IS NOT NULL THEN published.species_id WHEN projection.projection_state = 'community_resolved' THEN$new$);
END;
$patch13$;
DO $patch14$
DECLARE definition TEXT; marker TEXT := $old$      AND (
          COALESCE(
              projection.projection_state::TEXT,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 14';
    END IF;
    EXECUTE replace(definition,marker,$new$      AND (published.post_id IS NOT NULL OR
          COALESCE(
              projection.projection_state::TEXT,$new$);
END;
$patch14$;
DO $patch15$
DECLARE definition TEXT; marker TEXT := $old$AND scans.is_biological_subject IS DISTINCT FROM FALSE$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 15';
    END IF;
    EXECUTE replace(definition,marker,$new$AND (published.post_id IS NOT NULL OR scans.is_biological_subject IS DISTINCT FROM FALSE)$new$);
END;
$patch15$;
DO $patch16$
DECLARE definition TEXT; marker TEXT := $old$identity.value ->> 'common_name',scans.user_identification_override$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.explore_projected_post_cards(uuid) fragment 16';
    END IF;
    EXECUTE replace(definition,marker,$new$identity.value ->> 'common_name',CASE WHEN published.post_id IS NULL THEN scans.user_identification_override END$new$);
END;
$patch16$;
DO $patch17$
DECLARE definition TEXT; marker TEXT := $old$    INNER JOIN public.users AS author$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_post_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.get_explore_post_detail(uuid,uuid) fragment 17';
    END IF;
    EXECUTE replace(definition,marker,$new$    LEFT JOIN public.explore_analysis_public_projection AS published ON published.post_id=post.id
    INNER JOIN public.users AS author$new$);
END;
$patch17$;
DO $patch18$
DECLARE definition TEXT; marker TEXT := $old$CASE WHEN internal.scan_effective_identification(scan) ->> 'source' = 'verified_selection'$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_post_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.get_explore_post_detail(uuid,uuid) fragment 18';
    END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NOT NULL OR internal.scan_effective_identification(scan) ->> 'source' = 'verified_selection'$new$);
END;
$patch18$;
DO $patch19$
DECLARE definition TEXT; marker TEXT := $old$        CASE
            WHEN COALESCE(
                scan.user_review_state,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_post_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.get_explore_post_detail(uuid,uuid) fragment 19';
    END IF;
    EXECUTE replace(definition,marker,$new$        CASE
            WHEN published.post_id IS NULL AND COALESCE(
                scan.user_review_state,$new$);
END;
$patch19$;
DO $patch20$
DECLARE definition TEXT; marker TEXT := $old$            scan.image_storage_urls
$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_post_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.get_explore_post_detail(uuid,uuid) fragment 20';
    END IF;
    EXECUTE replace(definition,marker,$new$            CASE WHEN published.post_id IS NULL THEN scan.image_storage_urls ELSE ARRAY(SELECT m.url FROM public.explore_post_media m WHERE m.post_id=post.id) END
$new$);
END;
$patch20$;
DO $patch21$
DECLARE definition TEXT; marker TEXT := $old$AND internal.scan_identification_is_shareable(scan)$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_post_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.get_explore_post_detail(uuid,uuid) fragment 21';
    END IF;
    EXECUTE replace(definition,marker,$new$AND (published.post_id IS NOT NULL OR internal.scan_identification_is_shareable(scan))$new$);
END;
$patch21$;
DO $patch22$
DECLARE definition TEXT; marker TEXT := $old$WHERE ep.unshared_at IS NULL$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.refresh_merian_reference_images(integer,integer,boolean,double precision)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>2 THEN
        RAISE EXCEPTION 'publication_source_drift: public.refresh_merian_reference_images(integer,integer,boolean,double precision) fragment 22';
    END IF;
    EXECUTE replace(definition,marker,$new$WHERE ep.unshared_at IS NULL
              AND NOT EXISTS(SELECT 1 FROM public.explore_analysis_public_projection ap WHERE ap.post_id=ep.id)$new$);
END;
$patch22$;
DO $patch23$
DECLARE definition TEXT; marker TEXT := $old$BEGIN
$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.refresh_explore_post_media(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN
        RAISE EXCEPTION 'publication_source_drift: public.refresh_explore_post_media(uuid) fragment 23';
    END IF;
    EXECUTE replace(definition,marker,$new$BEGIN
    IF EXISTS(SELECT 1 FROM public.explore_analysis_public_projection WHERE post_id=target_post_id) THEN RETURN; END IF;
$new$);
END;
$patch23$;
DO $search$
DECLARE definition TEXT; marker TEXT := $old$CASE WHEN projection.projection_state::TEXT = 'community_resolved'
                   THEN community_taxon.species_id ELSE COALESCE(scan.confirmed_species_id,scan.species_id) END$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.search_species_discovery(uuid,text,text,text,text,jsonb,boolean)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_discovery_source_drift'; END IF;
    definition := replace(definition,marker,'internal.explore_effective_species_id(scan,cards.post_id)');
    definition := replace(definition,E'            LEFT JOIN public.explore_observation_projection projection ON projection.post_id = cards.post_id\n','');
    definition := replace(definition,E'            LEFT JOIN public.taxon_nodes community_taxon ON community_taxon.id = projection.public_taxon_node_id\n','');
    EXECUTE definition;
END;
$search$;

DO $detail0$
DECLARE definition TEXT; marker TEXT := $old$    JOIN public.scans s
$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_detail_source_drift_0'; END IF;
    EXECUTE replace(definition,marker,$new$    LEFT JOIN public.explore_analysis_public_projection published ON published.post_id=ep.id
    JOIN public.scans s
$new$);
END;
$detail0$;
DO $detail1$
DECLARE definition TEXT; marker TEXT := $old$        s.image_storage_urls[1] AS hero_image_url,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_detail_source_drift_1'; END IF;
    EXECUTE replace(definition,marker,$new$        CASE WHEN published.post_id IS NULL THEN s.image_storage_urls[1] ELSE public.explore_post_hero_image_url(ep.id) END AS hero_image_url,$new$);
END;
$detail1$;
DO $detail2$
DECLARE definition TEXT; marker TEXT := $old$        COALESCE(suggestions.suggested_taxa, '[]'::JSONB) AS suggested_taxa,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_detail_source_drift_2'; END IF;
    EXECUTE replace(definition,marker,$new$        CASE WHEN published.post_id IS NULL THEN COALESCE(suggestions.suggested_taxa, '[]'::JSONB) ELSE '[]'::JSONB END AS suggested_taxa,$new$);
END;
$detail2$;
DO $detail3$
DECLARE definition TEXT; marker TEXT := $old$        s.inference_tier,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_detail_source_drift_3'; END IF;
    EXECUTE replace(definition,marker,$new$        CASE WHEN published.post_id IS NULL THEN s.inference_tier END AS inference_tier,$new$);
END;
$detail3$;
DO $detail4$
DECLARE definition TEXT; marker TEXT := $old$        metrics.compatible AS ai_confidence_qualified,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_detail_source_drift_4'; END IF;
    EXECUTE replace(definition,marker,$new$        CASE WHEN published.post_id IS NULL THEN metrics.compatible ELSE FALSE END AS ai_confidence_qualified,$new$);
END;
$detail4$;
DO $detail5$
DECLARE definition TEXT; marker TEXT := $old$AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_detail_source_drift_5'; END IF;
    EXECUTE replace(definition,marker,$new$AND ((published.post_id IS NULL AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0)>0) OR (published.post_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.explore_projected_post_cards(self_id) card WHERE card.post_id=ep.id)))$new$);
END;
$detail5$;

DO $communitylabel0$
DECLARE definition TEXT; marker TEXT := $old$ecr.status::TEXT,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_label_source_drift_0'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NOT NULL AND published.identification IS NULL THEN 'needs_id' ELSE ecr.status::TEXT END,$new$);
END;
$communitylabel0$;
DO $communitylabel1$
DECLARE definition TEXT; marker TEXT := $old$eop.projection_state::TEXT AS projection_state,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_label_source_drift_1'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NOT NULL AND published.identification IS NULL THEN 'community_needs_id' ELSE eop.projection_state::TEXT END AS projection_state,$new$);
END;
$communitylabel1$;
DO $communitylabel2$
DECLARE definition TEXT; marker TEXT := $old$COALESCE(ecr.current_community_taxon_node_id, ecr.initial_taxon_node_id) AS current_taxon_id,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_label_source_drift_2'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NULL OR published.identification IS NOT NULL THEN COALESCE(ecr.current_community_taxon_node_id, ecr.initial_taxon_node_id) END AS current_taxon_id,$new$);
END;
$communitylabel2$;
DO $communitylabel3$
DECLARE definition TEXT; marker TEXT := $old$current_taxon.common_name AS current_common_name,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_label_source_drift_3'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NULL OR published.identification IS NOT NULL THEN current_taxon.common_name END AS current_common_name,$new$);
END;
$communitylabel3$;
DO $communitylabel4$
DECLARE definition TEXT; marker TEXT := $old$current_taxon.scientific_name AS current_scientific_name,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_label_source_drift_4'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NULL OR published.identification IS NOT NULL THEN current_taxon.scientific_name END AS current_scientific_name,$new$);
END;
$communitylabel4$;
DO $communitylabel5$
DECLARE definition TEXT; marker TEXT := $old$current_taxon.rank AS current_rank,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_label_source_drift_5'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NULL OR published.identification IS NOT NULL THEN current_taxon.rank END AS current_rank,$new$);
END;
$communitylabel5$;
DO $communitylabel6$
DECLARE definition TEXT; marker TEXT := $old$current_taxon.path::TEXT AS current_path,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_label_source_drift_6'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NULL OR published.identification IS NOT NULL THEN current_taxon.path::TEXT END AS current_path,$new$);
END;
$communitylabel6$;
DO $communitylabel7$
DECLARE definition TEXT; marker TEXT := $old$ecr.resolved_taxon_node_id AS resolved_taxon_id,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_community_label_source_drift_7'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NULL OR published.identification IS NOT NULL THEN ecr.resolved_taxon_node_id END AS resolved_taxon_id,$new$);
END;
$communitylabel7$;

DO $reference_lock$
DECLARE definition TEXT; marker TEXT := $old$    PERFORM internal.require_service_role();$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.refresh_merian_reference_images(integer,integer,boolean,double precision)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_reference_lock'; END IF;
    EXECUTE replace(definition,marker,$new$    PERFORM internal.require_service_role();
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-analysis-publication-references',0::BIGINT));$new$);
END;
$reference_lock$;

DO $initial0$
DECLARE definition TEXT; marker TEXT := $old$ecr.initial_taxon_node_id AS initial_taxon_id,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_initial0'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NULL OR published.identification IS NOT NULL THEN ecr.initial_taxon_node_id END AS initial_taxon_id,$new$);
END;
$initial0$;

DO $initial1$
DECLARE definition TEXT; marker TEXT := $old$initial_taxon.common_name AS initial_common_name,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_initial1'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NULL OR published.identification IS NOT NULL THEN initial_taxon.common_name END AS initial_common_name,$new$);
END;
$initial1$;

DO $initial2$
DECLARE definition TEXT; marker TEXT := $old$initial_taxon.scientific_name AS initial_scientific_name,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_initial2'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NULL OR published.identification IS NOT NULL THEN initial_taxon.scientific_name END AS initial_scientific_name,$new$);
END;
$initial2$;

DO $initial3$
DECLARE definition TEXT; marker TEXT := $old$initial_taxon.rank AS initial_rank,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_initial3'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NULL OR published.identification IS NOT NULL THEN initial_taxon.rank END AS initial_rank,$new$);
END;
$initial3$;

DO $initial4$
DECLARE definition TEXT; marker TEXT := $old$initial_taxon.path::TEXT AS initial_path,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_initial4'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NULL OR published.identification IS NOT NULL THEN initial_taxon.path::TEXT END AS initial_path,$new$);
END;
$initial4$;

DO $notification_join0$
DECLARE definition TEXT; marker TEXT := $old$        FROM visible_explore_notifications n$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_notifications(uuid,integer,timestamp with time zone,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_notification_join0'; END IF;
    EXECUTE replace(definition,marker,$new$        FROM visible_explore_notifications n
        LEFT JOIN public.explore_analysis_public_projection published ON published.post_id=n.post_id$new$);
END;
$notification_join0$;

DO $notification_label0_0$
DECLARE definition TEXT; marker TEXT := $old$display_taxon.common_name AS community_taxon_common_name,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_notifications(uuid,integer,timestamp with time zone,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_notification_label0_0'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NOT NULL THEN published.common_name ELSE display_taxon.common_name END AS community_taxon_common_name,$new$);
END;
$notification_label0_0$;

DO $notification_label0_1$
DECLARE definition TEXT; marker TEXT := $old$display_taxon.scientific_name AS community_taxon_scientific_name,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_notifications(uuid,integer,timestamp with time zone,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_notification_label0_1'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NOT NULL THEN published.scientific_name ELSE display_taxon.scientific_name END AS community_taxon_scientific_name,$new$);
END;
$notification_label0_1$;

DO $notification_display0$
DECLARE definition TEXT; marker TEXT := $old$            COALESCE(
                NULLIF(BTRIM(display_taxon.common_name), ''),
                NULLIF(BTRIM(display_taxon.scientific_name), ''),
                NULLIF(BTRIM(initial_taxon.common_name), ''),
                NULLIF(BTRIM(initial_taxon.scientific_name), ''),
                'Community request'
            ) AS community_request_display_name,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_notifications(uuid,integer,timestamp with time zone,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_notification_display0'; END IF;
    EXECUTE replace(definition,marker,$new$            CASE WHEN published.post_id IS NOT NULL THEN COALESCE(published.common_name,published.scientific_name,'Community request') ELSE COALESCE(
                NULLIF(BTRIM(display_taxon.common_name), ''),
                NULLIF(BTRIM(display_taxon.scientific_name), ''),
                NULLIF(BTRIM(initial_taxon.common_name), ''),
                NULLIF(BTRIM(initial_taxon.scientific_name), ''),
                'Community request'
            ) END AS community_request_display_name,$new$);
END;
$notification_display0$;

DO $notification_join1$
DECLARE definition TEXT; marker TEXT := $old$        FROM visible_explore_notifications n$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_notifications_with_reactions(uuid,integer,timestamp with time zone,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_notification_join1'; END IF;
    EXECUTE replace(definition,marker,$new$        FROM visible_explore_notifications n
        LEFT JOIN public.explore_analysis_public_projection published ON published.post_id=n.post_id$new$);
END;
$notification_join1$;

DO $notification_label1_0$
DECLARE definition TEXT; marker TEXT := $old$display_taxon.common_name AS community_taxon_common_name,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_notifications_with_reactions(uuid,integer,timestamp with time zone,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_notification_label1_0'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NOT NULL THEN published.common_name ELSE display_taxon.common_name END AS community_taxon_common_name,$new$);
END;
$notification_label1_0$;

DO $notification_label1_1$
DECLARE definition TEXT; marker TEXT := $old$display_taxon.scientific_name AS community_taxon_scientific_name,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_notifications_with_reactions(uuid,integer,timestamp with time zone,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_notification_label1_1'; END IF;
    EXECUTE replace(definition,marker,$new$CASE WHEN published.post_id IS NOT NULL THEN published.scientific_name ELSE display_taxon.scientific_name END AS community_taxon_scientific_name,$new$);
END;
$notification_label1_1$;

DO $notification_display1$
DECLARE definition TEXT; marker TEXT := $old$            COALESCE(
                NULLIF(BTRIM(display_taxon.common_name), ''),
                NULLIF(BTRIM(display_taxon.scientific_name), ''),
                NULLIF(BTRIM(initial_taxon.common_name), ''),
                NULLIF(BTRIM(initial_taxon.scientific_name), ''),
                'Community request'
            ) AS community_request_display_name,$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_notifications_with_reactions(uuid,integer,timestamp with time zone,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_notification_display1'; END IF;
    EXECUTE replace(definition,marker,$new$            CASE WHEN published.post_id IS NOT NULL THEN COALESCE(published.common_name,published.scientific_name,'Community request') ELSE COALESCE(
                NULLIF(BTRIM(display_taxon.common_name), ''),
                NULLIF(BTRIM(display_taxon.scientific_name), ''),
                NULLIF(BTRIM(initial_taxon.common_name), ''),
                NULLIF(BTRIM(initial_taxon.scientific_name), ''),
                'Community request'
            ) END AS community_request_display_name,$new$);
END;
$notification_display1$;

DO $account_fence$
DECLARE definition TEXT; marker TEXT := $old$    UPDATE public.scans AS scans$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.apply_user_tombstone(uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_source_drift_account_fence'; END IF;
    EXECUTE replace(definition,marker,$new$    -- Bound consensus can hold request/public rows before notification FKs
    -- reach the owner. Acquire them without waiting before any detach/cascade.
    BEGIN
        PERFORM request.id FROM public.explore_community_requests request
        JOIN internal.observation_community_bindings binding ON binding.request_id=request.id
        WHERE binding.owner_id=target_user_id ORDER BY request.id FOR UPDATE OF request NOWAIT;
        PERFORM published.post_id FROM public.explore_analysis_public_projection published
        JOIN public.explore_posts post ON post.id=published.post_id
        WHERE post.user_id=target_user_id ORDER BY published.post_id FOR UPDATE OF published NOWAIT;
    EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END;

    UPDATE public.scans AS scans$new$);
END;
$account_fence$;

DO $notification_visibility0$
DECLARE definition TEXT; marker TEXT := $old$                          COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
                          AND s.geoprivacy <> 'private'
                          AND owner.is_shadowbanned = FALSE$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_notifications(uuid,integer,timestamp with time zone,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_notification_visibility_source_drift_0'; END IF;
    EXECUTE replace(definition,marker,$new$                          ((EXISTS(SELECT 1 FROM public.explore_analysis_public_projection ap WHERE ap.post_id=ep.id)
                            AND EXISTS(SELECT 1 FROM public.explore_projected_post_cards(self_id) card WHERE card.post_id=ep.id))
                          OR (NOT EXISTS(SELECT 1 FROM public.explore_analysis_public_projection ap WHERE ap.post_id=ep.id)
                            AND COALESCE(ARRAY_LENGTH(s.image_storage_urls,1),0)>0 AND s.geoprivacy<>'private' AND owner.is_shadowbanned=FALSE))$new$);
END;
$notification_visibility0$;
DO $notification_visibility1$
DECLARE definition TEXT; marker TEXT := $old$                          COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
                          AND s.geoprivacy <> 'private'
                          AND owner.is_shadowbanned = FALSE$old$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_explore_notifications_with_reactions(uuid,integer,timestamp with time zone,uuid)'::REGPROCEDURE);
    IF (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'publication_notification_visibility_source_drift_1'; END IF;
    EXECUTE replace(definition,marker,$new$                          ((EXISTS(SELECT 1 FROM public.explore_analysis_public_projection ap WHERE ap.post_id=ep.id)
                            AND EXISTS(SELECT 1 FROM public.explore_projected_post_cards(self_id) card WHERE card.post_id=ep.id))
                          OR (NOT EXISTS(SELECT 1 FROM public.explore_analysis_public_projection ap WHERE ap.post_id=ep.id)
                            AND COALESCE(ARRAY_LENGTH(s.image_storage_urls,1),0)>0 AND s.geoprivacy<>'private' AND owner.is_shadowbanned=FALSE))$new$);
END;
$notification_visibility1$;

RESET statement_timeout;
RESET lock_timeout;
