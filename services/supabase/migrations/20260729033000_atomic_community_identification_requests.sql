-- Create or reopen Ask the Community state without exposing a normal Explore
-- post between independent Data API transactions.
--
-- Audio moderation, media restoration, and taxonomy synchronization remain in
-- Edge code. This short database boundary revalidates the owner scan and then
-- commits the post snapshot and needs-ID request as one transaction.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE OR REPLACE FUNCTION internal.reject_needs_id_explore_republication()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    -- Close the absent-request race in publish_scan_to_explore_atomically:
    -- another transaction can create a needs-ID request after its first
    -- request lookup but while it waits for the owner scan. Recheck at the
    -- actual republish write so a successful share can never remain hidden
    -- behind a concurrently committed community request.
    IF NEW.unshared_at IS NULL
       AND EXISTS (
           SELECT 1
           FROM public.explore_community_requests AS community_request
           WHERE community_request.scan_id = NEW.scan_id
             AND community_request.status = 'needs_id'
             AND community_request.withdrawn_at IS NULL
       ) THEN
        RAISE EXCEPTION
            'Wait for the community to identify this request before sharing it to Explore.'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION internal.reject_needs_id_explore_republication()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_reject_needs_id_explore_republication
    ON public.explore_posts;
CREATE TRIGGER trg_reject_needs_id_explore_republication
BEFORE UPDATE OF shared_at
ON public.explore_posts
FOR EACH ROW
EXECUTE FUNCTION internal.reject_needs_id_explore_republication();

CREATE OR REPLACE FUNCTION public.request_community_identification_atomically(
    p_scan_id UUID,
    p_user_id UUID,
    p_note TEXT,
    p_location_sharing TEXT,
    p_species_common_name TEXT,
    p_media_rows JSONB,
    p_initial_taxon_node_id UUID,
    p_taxonomy_version_id UUID
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_existing_field_notes TEXT;
    v_existing_post_id UUID;
    v_existing_species_common_name TEXT;
    v_hashtags TEXT[] := ARRAY[]::TEXT[];
    v_locked_scan_id UUID;
    v_post_id UUID;
    v_publication JSONB;
    v_request public.explore_community_requests%ROWTYPE;
    v_requested_at TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();
    v_scan_species_id UUID;
BEGIN
    IF p_scan_id IS NULL
       OR p_user_id IS NULL
       OR p_initial_taxon_node_id IS NULL
       OR p_taxonomy_version_id IS NULL THEN
        RAISE EXCEPTION 'Community request identifiers are required'
            USING ERRCODE = '22023';
    END IF;

    IF p_note IS NOT NULL
       AND pg_catalog.CHAR_LENGTH(p_note) > 1000 THEN
        RAISE EXCEPTION 'Community request note is too long'
            USING ERRCODE = '22023';
    END IF;

    -- Consensus processing locks request -> scan. Preserve that order whenever
    -- a request already exists, including legacy rows whose owner needs repair.
    SELECT community_request.*
    INTO v_request
    FROM public.explore_community_requests AS community_request
    WHERE community_request.scan_id = p_scan_id
    ORDER BY community_request.requested_at DESC, community_request.id DESC
    LIMIT 1
    FOR UPDATE OF community_request;

    SELECT
        scan.id,
        COALESCE(scan.confirmed_species_id, scan.species_id)
    INTO v_locked_scan_id, v_scan_species_id
    FROM public.scans AS scan
    WHERE scan.id = p_scan_id
      AND scan.user_id = p_user_id
      AND NOT scan.is_tombstoned
      AND (
          scan.confirmed_species_id IS NOT NULL
          OR scan.species_id IS NOT NULL
      )
      AND (
          COALESCE(
              pg_catalog.CARDINALITY(scan.image_storage_urls),
              0
          )
          + COALESCE(
              pg_catalog.CARDINALITY(scan.video_storage_urls),
              0
          )
          + COALESCE(
              pg_catalog.CARDINALITY(scan.audio_storage_urls),
              0
          )
      ) > 0
    FOR UPDATE OF scan;

    IF v_locked_scan_id IS NULL THEN
        RAISE EXCEPTION 'Owned community-request-eligible scan not found'
            USING ERRCODE = 'P0001';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.taxon_nodes AS taxon_node
        WHERE taxon_node.id = p_initial_taxon_node_id
          AND taxon_node.taxonomy_version_id = p_taxonomy_version_id
          AND taxon_node.species_id = v_scan_species_id
    ) THEN
        RAISE EXCEPTION 'Initial taxon does not match the owner scan'
            USING ERRCODE = '22023';
    END IF;

    IF v_request.id IS NOT NULL
       AND v_request.status <> 'withdrawn' THEN
        SELECT post.id
        INTO v_existing_post_id
        FROM public.explore_posts AS post
        WHERE post.id = v_request.post_id
          AND post.scan_id = p_scan_id
          AND post.user_id = p_user_id
        FOR UPDATE OF post;

        IF v_existing_post_id IS NULL THEN
            RAISE EXCEPTION
                'Community request post ownership does not match the scan'
                USING ERRCODE = 'P0001';
        END IF;

        IF v_request.requested_by IS DISTINCT FROM p_user_id THEN
            UPDATE public.explore_community_requests AS community_request
            SET requested_by = p_user_id,
                updated_at = pg_catalog.CLOCK_TIMESTAMP()
            WHERE community_request.id = v_request.id
            RETURNING community_request.* INTO v_request;
        END IF;

        RETURN pg_catalog.TO_JSONB(v_request);
    END IF;

    SELECT
        post.id,
        post.field_notes,
        post.species_common_name
    INTO
        v_existing_post_id,
        v_existing_field_notes,
        v_existing_species_common_name
    FROM public.explore_posts AS post
    WHERE post.scan_id = p_scan_id
      AND post.user_id = p_user_id
    FOR UPDATE OF post;

    IF v_existing_post_id IS NOT NULL THEN
        SELECT COALESCE(
            pg_catalog.ARRAY_AGG(hashtag.tag ORDER BY hashtag.tag),
            ARRAY[]::TEXT[]
        )
        INTO v_hashtags
        FROM public.explore_post_hashtags AS hashtag
        WHERE hashtag.post_id = v_existing_post_id;
    END IF;

    -- The nested call and the request write share this function's transaction.
    -- If taxonomy/request insertion fails, PostgreSQL rolls the complete post
    -- and media snapshot back rather than exposing a normal Explore post.
    v_publication := public.publish_scan_to_explore_atomically(
        p_scan_id,
        p_user_id,
        COALESCE(
            p_species_common_name,
            v_existing_species_common_name
        ),
        v_existing_field_notes,
        p_location_sharing,
        p_media_rows,
        v_hashtags
    );
    v_post_id := (v_publication ->> 'post_id')::UUID;

    IF v_post_id IS NULL THEN
        RAISE EXCEPTION 'Atomic Explore snapshot returned no post'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_request.id IS NULL THEN
        INSERT INTO public.explore_community_requests (
            post_id,
            scan_id,
            requested_by,
            requested_at,
            status,
            note,
            initial_taxon_node_id,
            taxonomy_version_id,
            current_community_taxon_node_id,
            resolved_taxon_node_id,
            resolved_observation_taxon_node_id,
            consensus_score,
            consensus_identification_count,
            consensus_rank,
            resolved_at,
            withdrawn_at,
            explore_published_at,
            consensus_processing_state,
            last_consensus_job_id,
            updated_at
        )
        VALUES (
            v_post_id,
            p_scan_id,
            p_user_id,
            v_requested_at,
            'needs_id',
            NULLIF(pg_catalog.BTRIM(p_note), ''),
            p_initial_taxon_node_id,
            p_taxonomy_version_id,
            NULL,
            NULL,
            NULL,
            NULL,
            0,
            NULL,
            NULL,
            NULL,
            NULL,
            'idle',
            NULL,
            v_requested_at
        )
        RETURNING * INTO v_request;
    ELSE
        -- A reopened request starts a fresh consensus generation. Preserve old
        -- identification rows as audit history but prevent their active state
        -- or a stale worker lease from resolving the new request.
        UPDATE public.explore_identifications AS identification
        SET withdrawn_at = COALESCE(
                identification.withdrawn_at,
                v_requested_at
            ),
            restored_at = NULL
        WHERE identification.request_id = v_request.id
          AND identification.withdrawn_at IS NULL;

        DELETE FROM public.community_consensus_jobs AS consensus_job
        WHERE consensus_job.request_id = v_request.id;

        UPDATE public.explore_community_requests AS community_request
        SET post_id = v_post_id,
            scan_id = p_scan_id,
            requested_by = p_user_id,
            requested_at = v_requested_at,
            status = 'needs_id',
            note = NULLIF(pg_catalog.BTRIM(p_note), ''),
            initial_taxon_node_id = p_initial_taxon_node_id,
            taxonomy_version_id = p_taxonomy_version_id,
            current_community_taxon_node_id = NULL,
            resolved_taxon_node_id = NULL,
            resolved_observation_taxon_node_id = NULL,
            consensus_score = NULL,
            consensus_identification_count = 0,
            consensus_rank = NULL,
            resolved_at = NULL,
            withdrawn_at = NULL,
            explore_published_at = NULL,
            consensus_processing_state = 'idle',
            last_consensus_job_id = NULL,
            updated_at = v_requested_at
        WHERE community_request.id = v_request.id
        RETURNING community_request.* INTO v_request;
    END IF;

    RETURN pg_catalog.TO_JSONB(v_request);
END;
$function$;

REVOKE ALL ON FUNCTION public.request_community_identification_atomically(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT,
    JSONB,
    UUID,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.request_community_identification_atomically(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT,
    JSONB,
    UUID,
    UUID
) TO service_role;

COMMENT ON FUNCTION public.request_community_identification_atomically(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT,
    JSONB,
    UUID,
    UUID
) IS
    'Service-only owner-checked transaction that creates or reopens one complete needs-ID Explore snapshot and Community request without partial publication.';

RESET statement_timeout;
RESET lock_timeout;

NOTIFY pgrst, 'reload schema';
