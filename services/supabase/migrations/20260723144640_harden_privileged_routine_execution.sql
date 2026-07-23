-- Privileged routines are deny-by-default.
--
-- PostgreSQL gives PUBLIC EXECUTE on new functions unless the creating role's
-- global default privileges revoke it. Supabase also installs schema-local
-- defaults for its API roles. Revoke both layers before changing or creating
-- any routines in this migration.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

-- API roles must never be able to replace an object resolved by a privileged
-- routine. This is already true on a standard Supabase project; keeping it in
-- the migration makes the invariant explicit and repairable.
REVOKE CREATE ON SCHEMA public FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS internal.privileged_routine_grants (
    role_name TEXT NOT NULL,
    routine_signature TEXT NOT NULL,
    purpose TEXT NOT NULL,
    PRIMARY KEY (role_name, routine_signature),
    CONSTRAINT privileged_routine_grants_role_check
        CHECK (role_name IN ('authenticated', 'service_role')),
    CONSTRAINT privileged_routine_grants_public_signature_check
        CHECK (routine_signature LIKE 'public.%(%'),
    CONSTRAINT privileged_routine_grants_purpose_check
        CHECK (BTRIM(purpose) <> '')
);

COMMENT ON TABLE internal.privileged_routine_grants IS
    'Reviewed allowlist for API-role EXECUTE grants on public SECURITY DEFINER functions. Changes require a migration, catalog tests, and a documented caller boundary.';

REVOKE ALL ON TABLE internal.privileged_routine_grants
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.require_service_role()
RETURNS VOID
LANGUAGE PLPGSQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role'
       AND SESSION_USER NOT IN ('postgres', 'service_role') THEN
        RAISE EXCEPTION 'service_role authorization required'
            USING ERRCODE = '42501';
    END IF;
END;
$$;

COMMENT ON FUNCTION internal.require_service_role() IS
    'Defense-in-depth caller check used by every public SECURITY DEFINER routine exposed to service_role. PostgreSQL-owner sessions remain available for migrations and incident repair.';

REVOKE ALL ON FUNCTION internal.require_service_role()
    FROM PUBLIC, anon, authenticated, service_role;

-- The deletion endpoint authenticates the user before switching to the service
-- client. Keep the database boundary service-only as defense in depth.
CREATE OR REPLACE FUNCTION public.apply_user_tombstone(target_user_id UUID)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF target_user_id IS NULL
       OR target_user_id = '00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'A non-tombstone target user is required.'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.users (
        id,
        current_streak_count,
        total_species_discovered,
        subscription_tier
    )
    VALUES (
        '00000000-0000-0000-0000-000000000000',
        0,
        0,
        'free'
    )
    ON CONFLICT (id) DO NOTHING;

    UPDATE public.scans
    SET user_id = '00000000-0000-0000-0000-000000000000',
        is_tombstoned = TRUE
    WHERE user_id = target_user_id;

    DELETE FROM public.users
    WHERE id = target_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_user_tombstone(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

-- This legacy one-row helper is retained for database-owner compatibility but
-- receives no API-role grant.
CREATE OR REPLACE FUNCTION public.merge_common_name_en(
    p_id UUID,
    p_en_name TEXT
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF p_id IS NULL
       OR NULLIF(pg_catalog.BTRIM(p_en_name), '') IS NULL
       OR pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(p_en_name)) > 120
       OR p_en_name ~ '[[:cntrl:]]' THEN
        RAISE EXCEPTION 'Invalid English common-name update.'
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.species_dictionary AS species
    SET common_names =
        COALESCE(species.common_names, '{}'::JSONB)
        || pg_catalog.JSONB_BUILD_OBJECT(
            'en',
            pg_catalog.BTRIM(p_en_name)
        )
    WHERE species.id = p_id
      AND (
          species.common_names IS NULL
          OR NOT (species.common_names ? 'en')
      );
END;
$$;

REVOKE ALL ON FUNCTION public.merge_common_name_en(UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;

-- Lookalike enrichment is the only runtime caller. Reject oversized,
-- duplicate, malformed, or non-service batches before touching taxonomy data.
CREATE OR REPLACE FUNCTION public.merge_common_name_en_batch(p_updates JSONB)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    update_count INTEGER;
    distinct_id_count INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    IF pg_catalog.JSONB_TYPEOF(p_updates) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'p_updates must be a JSON array.'
            USING ERRCODE = '22023';
    END IF;

    update_count := pg_catalog.JSONB_ARRAY_LENGTH(p_updates);
    IF update_count < 1 OR update_count > 50 THEN
        RAISE EXCEPTION 'p_updates must contain between 1 and 50 entries.'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_updates) AS entry(value)
        WHERE pg_catalog.JSONB_TYPEOF(entry.value) IS DISTINCT FROM 'object'
           OR pg_catalog.JSONB_TYPEOF(entry.value -> 'id')
                IS DISTINCT FROM 'string'
           OR pg_catalog.JSONB_TYPEOF(entry.value -> 'en_name')
                IS DISTINCT FROM 'string'
           OR NOT (
               entry.value ->> 'id'
               ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
           )
           OR NULLIF(
               pg_catalog.BTRIM(entry.value ->> 'en_name'),
               ''
           ) IS NULL
           OR pg_catalog.CHAR_LENGTH(
               pg_catalog.BTRIM(entry.value ->> 'en_name')
           ) > 120
           OR (entry.value ->> 'en_name') ~ '[[:cntrl:]]'
    ) THEN
        RAISE EXCEPTION 'p_updates contains a malformed entry.'
            USING ERRCODE = '22023';
    END IF;

    SELECT pg_catalog.COUNT(DISTINCT entry.value ->> 'id')::INTEGER
    INTO distinct_id_count
    FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_updates) AS entry(value);

    IF distinct_id_count <> update_count THEN
        RAISE EXCEPTION 'p_updates contains duplicate species ids.'
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.species_dictionary AS species
    SET common_names =
        COALESCE(species.common_names, '{}'::JSONB)
        || pg_catalog.JSONB_BUILD_OBJECT('en', updates.en_name)
    FROM (
        SELECT
            (entry.value ->> 'id')::UUID AS id,
            pg_catalog.BTRIM(entry.value ->> 'en_name') AS en_name
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_updates) AS entry(value)
    ) AS updates
    WHERE species.id = updates.id
      AND (
          species.common_names IS NULL
          OR NOT (species.common_names ? 'en')
      );
END;
$$;

REVOKE ALL ON FUNCTION public.merge_common_name_en_batch(JSONB)
    FROM PUBLIC, anon, authenticated, service_role;

-- Qualify the queue columns that conflict with RETURNS TABLE output variables.
-- plpgsql_check catches this existing ambiguity, and the service worker needs
-- the routine to remain executable after the privilege boundary is tightened.
CREATE OR REPLACE FUNCTION public.process_community_consensus_jobs(
    max_jobs INTEGER DEFAULT 25
)
RETURNS TABLE(
    job_id UUID,
    request_id UUID,
    status TEXT,
    error_message TEXT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    job_row public.community_consensus_jobs;
    failure_message TEXT;
BEGIN
    PERFORM internal.require_service_role();

    FOR job_row IN
        SELECT candidate.*
        FROM public.community_consensus_jobs AS candidate
        WHERE candidate.status IN ('pending', 'failed')
          AND candidate.available_at <= pg_catalog.NOW()
          AND candidate.attempt_count < 5
        ORDER BY candidate.available_at ASC, candidate.updated_at ASC
        LIMIT LEAST(
            GREATEST(COALESCE(max_jobs, 25), 1),
            100
        )
        FOR UPDATE OF candidate SKIP LOCKED
    LOOP
        BEGIN
            PERFORM public.process_community_consensus_job(job_row.id);
            RETURN QUERY
            SELECT
                job_row.id,
                job_row.request_id,
                'completed'::TEXT,
                NULL::TEXT;
        EXCEPTION
            WHEN OTHERS THEN
                failure_message := SQLERRM;
                RETURN QUERY
                SELECT
                    job_row.id,
                    job_row.request_id,
                    'failed'::TEXT,
                    failure_message;
        END;
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.process_community_consensus_jobs(INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;

-- A small number of existing definitions use unqualified application enum
-- casts or ltree operators. Qualify those expressions before enforcing an
-- empty search_path on every public definer routine.
DO $migration$
DECLARE
    routine_row RECORD;
    original_definition TEXT;
    qualified_definition TEXT;
BEGIN
    FOR routine_row IN
        SELECT
            function_row.oid,
            function_row.proname
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'public'
          AND function_row.proname IN (
              'apply_explore_community_consensus',
              'apply_field_trip_scan_progress_v2',
              'community_taxon_path',
              'community_materialize_resolved_species',
              'create_community_resolution_notifications',
              'get_field_trip_catalog',
              'get_field_trip_challenge_detail',
              'get_field_trip_challenges_catalog',
              'get_field_trip_community_publications',
              'get_field_trip_template_detail',
              'join_field_trip_challenge',
              'refresh_taxonomy_coverage_targets',
              'refresh_taxonomy_nodes_from_species_dictionary',
              'start_field_trip',
              'submit_explore_community_identification',
              'sync_taxon_nodes_from_species_dictionary',
              'upsert_gbif_community_taxa'
          )
    LOOP
        original_definition :=
            pg_catalog.PG_GET_FUNCTIONDEF(routine_row.oid);
        qualified_definition := pg_catalog.REPLACE(
            original_definition,
            '::subscription_tier_enum',
            '::public.subscription_tier_enum'
        );
        qualified_definition := pg_catalog.REPLACE(
            qualified_definition,
            '::explore_identification_disagreement',
            '::public.explore_identification_disagreement'
        );
        qualified_definition := pg_catalog.REPLACE(
            qualified_definition,
            'node_path LTREE;',
            'node_path public.LTREE;'
        );
        qualified_definition := pg_catalog.REPLACE(
            qualified_definition,
            '::LTREE',
            '::public.LTREE'
        );
        qualified_definition := pg_catalog.REPLACE(
            qualified_definition,
            'exact_genus.path = c.path',
            'exact_genus.path OPERATOR(public.=) c.path'
        );
        qualified_definition := pg_catalog.REPLACE(
            qualified_definition,
            'identified_taxon.path = request_row.resolved_path',
            'identified_taxon.path OPERATOR(public.=) request_row.resolved_path'
        );
        qualified_definition := pg_catalog.REPLACE(
            qualified_definition,
            'path <> node_path',
            'path OPERATOR(public.<>) node_path'
        );
        qualified_definition := pg_catalog.REPLACE(
            qualified_definition,
            'tn.path = node_path',
            'tn.path OPERATOR(public.=) node_path'
        );

        IF routine_row.proname IN (
            'apply_explore_community_consensus',
            'community_materialize_resolved_species',
            'create_community_resolution_notifications',
            'refresh_taxonomy_coverage_targets'
        ) THEN
            qualified_definition := pg_catalog.REPLACE(
                qualified_definition,
                ' @> ',
                ' OPERATOR(public.@>) '
            );
            qualified_definition := pg_catalog.REPLACE(
                qualified_definition,
                ' <@ ',
                ' OPERATOR(public.<@) '
            );
        END IF;

        IF qualified_definition IS DISTINCT FROM original_definition THEN
            EXECUTE qualified_definition;
        END IF;
    END LOOP;
END;
$migration$;

DO $migration$
DECLARE
    routine_row RECORD;
BEGIN
    FOR routine_row IN
        SELECT
            namespace_row.nspname AS schema_name,
            function_row.proname AS routine_name,
            pg_catalog.PG_GET_FUNCTION_IDENTITY_ARGUMENTS(
                function_row.oid
            ) AS identity_arguments
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'public'
          AND function_row.prosecdef
    LOOP
        EXECUTE pg_catalog.FORMAT(
            'ALTER FUNCTION %I.%I(%s) SET search_path TO %L',
            routine_row.schema_name,
            routine_row.routine_name,
            routine_row.identity_arguments,
            ''
        );
    END LOOP;
END;
$migration$;

-- Remove all inherited, historical, and schema-default API grants before
-- applying the reviewed allowlist below.
DO $migration$
DECLARE
    routine_row RECORD;
BEGIN
    FOR routine_row IN
        SELECT
            namespace_row.nspname AS schema_name,
            function_row.proname AS routine_name,
            pg_catalog.PG_GET_FUNCTION_IDENTITY_ARGUMENTS(
                function_row.oid
            ) AS identity_arguments
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'public'
          AND function_row.prosecdef
    LOOP
        EXECUTE pg_catalog.FORMAT(
            'REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC, anon, authenticated, service_role',
            routine_row.schema_name,
            routine_row.routine_name,
            routine_row.identity_arguments
        );
    END LOOP;
END;
$migration$;

DELETE FROM internal.privileged_routine_grants;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    ('authenticated', 'public.admin_ai_usage_summary(integer,text,text,text,text,text,boolean)', 'Admin UI; in-function membership, role, AAL2, and session authorization.'),
    ('authenticated', 'public.admin_begin_session()', 'Admin UI; creates a bounded AAL2 admin session for the current caller.'),
    ('authenticated', 'public.admin_get_access_state()', 'Admin UI; returns access state for the current caller only.'),
    ('authenticated', 'public.admin_get_overview(integer,text,boolean)', 'Admin UI; authorized aggregate overview.'),
    ('authenticated', 'public.admin_get_review_case(uuid)', 'Admin UI; authorized moderation case detail.'),
    ('authenticated', 'public.admin_get_user_detail(uuid)', 'Admin UI; authorized user detail.'),
    ('authenticated', 'public.admin_list_audit(text,timestamp with time zone,bigint,integer)', 'Admin UI; authorized audit pagination.'),
    ('authenticated', 'public.admin_list_feedback(text,text,text,text,timestamp with time zone,uuid,integer)', 'Admin UI; authorized feedback pagination.'),
    ('authenticated', 'public.admin_list_members()', 'Admin UI; owner-authorized membership list.'),
    ('authenticated', 'public.admin_list_review_cases(text,text,text,uuid,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,uuid,integer)', 'Admin UI; authorized review queue.'),
    ('authenticated', 'public.admin_list_sessions()', 'Admin UI; owner-authorized session list.'),
    ('authenticated', 'public.admin_list_users(text,timestamp with time zone,uuid,integer)', 'Admin UI; authorized user search.'),
    ('authenticated', 'public.admin_revoke_session(uuid,text)', 'Admin UI; owner-authorized session revocation.'),
    ('authenticated', 'public.admin_set_content_visibility(uuid,boolean,text)', 'Admin UI; moderator-authorized visibility transition.'),
    ('authenticated', 'public.admin_update_feedback(text,uuid,text,uuid,text[],text)', 'Admin UI; authorized feedback update.'),
    ('authenticated', 'public.admin_update_review_case(uuid,text,text,uuid,boolean,text,text)', 'Admin UI; moderator-authorized review transition.'),
    ('authenticated', 'public.admin_upsert_member(text,text,boolean)', 'Admin UI; owner-authorized membership update.'),
    ('authenticated', 'public.consume_ghost_profile_merge_handoff(uuid,text)', 'Account upgrade; current authenticated target consumes a bound one-time handoff.'),
    ('authenticated', 'public.issue_ghost_profile_merge_handoff(text,text,text)', 'Account upgrade; current authenticated ghost issues a bound one-time handoff.'),

    ('service_role', 'public.active_taxonomy_version_id()', 'Dependency of service-owned taxonomy RPCs and defaults.'),
    ('service_role', 'public.apply_field_trip_scan_progress_atomic(uuid,uuid,uuid,uuid)', 'Field-trip Edge Function atomic progress RPC.'),
    ('service_role', 'public.apply_or_stage_scan_context(uuid,uuid,jsonb)', 'Scan-context Edge Function RPC.'),
    ('service_role', 'public.apply_user_tombstone(uuid)', 'Authenticated safe-delete Edge Function service RPC.'),
    ('service_role', 'public.begin_scan_ingestion(text,uuid,text,jsonb,jsonb,jsonb,text[],text,text,boolean,boolean,jsonb,integer,integer)', 'Identification ingestion Edge Function RPC.'),
    ('service_role', 'public.can_view_field_trip_challenge_entry(uuid,uuid)', 'Field-trip Edge Function visibility RPC and policy helper.'),
    ('service_role', 'public.can_view_field_trip_publication(uuid,uuid)', 'Field-trip Edge Function visibility RPC and policy helper.'),
    ('service_role', 'public.claim_ghost_profile_merge_auth_cleanups(integer)', 'Ghost-merge reconciliation worker lease RPC.'),
    ('service_role', 'public.claim_replayable_scan_ingestion_jobs(integer,integer)', 'Scan-ingestion replay worker lease RPC.'),
    ('service_role', 'public.claim_scan_ingestion_job(text,uuid,text,jsonb,jsonb,uuid[],text,integer)', 'Identification ingestion worker lease RPC.'),
    ('service_role', 'public.claim_species_enrichment_jobs(integer,timestamp with time zone,text)', 'Species enrichment worker lease RPC.'),
    ('service_role', 'public.complete_species_enrichment_job(uuid,boolean,text)', 'Species enrichment worker completion RPC.'),
    ('service_role', 'public.finish_ghost_profile_merge_auth_cleanup(uuid,uuid,boolean,text)', 'Ghost-merge reconciliation worker completion RPC.'),
    ('service_role', 'public.finish_ghost_user_bulk_cleanup(uuid,uuid,boolean,text)', 'Guarded ghost-cleanup operator completion RPC.'),
    ('service_role', 'public.get_field_trip_catalog(uuid,text,integer)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_field_trip_challenge_badges(uuid,uuid,integer)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_field_trip_challenge_detail(uuid,uuid,text,integer)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_field_trip_challenge_entry_comments(uuid,uuid,integer,timestamp with time zone,uuid)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_field_trip_challenge_entry_detail(uuid,uuid)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_field_trip_challenge_hashtags_for_scan(uuid,uuid)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_field_trip_challenge_publications(uuid,uuid,integer,timestamp with time zone,uuid)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_field_trip_challenges_catalog(uuid,text,integer)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_field_trip_comments(uuid,uuid,integer,timestamp with time zone,uuid)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_field_trip_community_publications(uuid,text,uuid,text,text[],text[],integer,integer,timestamp with time zone,uuid)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_field_trip_profile_summaries(uuid,uuid,integer)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_field_trip_publication_detail(uuid,uuid)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_field_trip_scan_contributions(uuid,uuid)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_field_trip_template_detail(uuid,uuid,text)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.get_recent_field_trip_publications(uuid,text,text[],integer,timestamp with time zone,uuid)', 'Field-trip Edge Function read RPC.'),
    ('service_role', 'public.hydrate_identification_dictionary(text,text[])', 'Identification enrichment Edge Function RPC.'),
    ('service_role', 'public.join_field_trip_challenge(uuid,uuid)', 'Field-trip Edge Function mutation RPC.'),
    ('service_role', 'public.list_protected_ghost_profile_merge_sources()', 'Read-only ghost-user audit script RPC.'),
    ('service_role', 'public.merge_common_name_en_batch(jsonb)', 'Bounded lookalike common-name enrichment RPC.'),
    ('service_role', 'public.process_community_consensus_jobs(integer)', 'Community consensus worker RPC.'),
    ('service_role', 'public.publish_field_trip_challenge_entry(uuid,uuid,text,text)', 'Field-trip Edge Function mutation RPC.'),
    ('service_role', 'public.publish_field_trip(uuid,uuid,text,text,text)', 'Field-trip Edge Function mutation RPC.'),
    ('service_role', 'public.publish_resolved_community_request_to_explore(uuid,uuid)', 'Explore sharing Edge Function mutation RPC.'),
    ('service_role', 'public.record_ai_usage_event(text,text,text,text,bigint,bigint,bigint,bigint,bigint,bigint,jsonb,text,uuid,uuid,uuid,uuid,text,uuid,jsonb,timestamp with time zone)', 'Edge Function AI-usage ledger RPC.'),
    ('service_role', 'public.record_ghost_profile_merge_auth_cleanup(uuid,boolean,text)', 'Ghost-merge Edge Function cleanup receipt RPC.'),
    ('service_role', 'public.record_scan_ingestion_intent(text,uuid,text,jsonb,jsonb,jsonb,uuid[],text,text,boolean,boolean,jsonb,integer)', 'Identification ingestion intent RPC.'),
    ('service_role', 'public.refresh_merian_reference_images(integer,integer,boolean,double precision)', 'Reference-image maintenance Edge Function RPC.'),
    ('service_role', 'public.refresh_public_author_identity(uuid)', 'Explore write-path projection maintenance RPC.'),
    ('service_role', 'public.refresh_scan_media_assets(uuid)', 'Scan-media lifecycle Edge Function RPC.'),
    ('service_role', 'public.refresh_taxonomy_coverage_targets()', 'Community-taxonomy maintenance Edge Function RPC.'),
    ('service_role', 'public.refresh_taxonomy_nodes_from_species_dictionary(text,boolean)', 'Service-key taxonomy rebuild Edge Function RPC.'),
    ('service_role', 'public.repair_explore_post_ownership_for_user(uuid)', 'Documented service-role ownership repair RPC.'),
    ('service_role', 'public.replace_species_reference_images(uuid,jsonb)', 'Species-content refresh worker RPC.'),
    ('service_role', 'public.reserve_ghost_user_bulk_cleanup(uuid,integer)', 'Guarded ghost-cleanup operator lease RPC.'),
    ('service_role', 'public.restore_explore_community_identification(uuid,uuid)', 'Community identification Edge Function mutation RPC.'),
    ('service_role', 'public.set_field_trip_pinned_publications(uuid,uuid[])', 'Field-trip Edge Function mutation RPC.'),
    ('service_role', 'public.start_field_trip(uuid,uuid)', 'Field-trip Edge Function mutation RPC.'),
    ('service_role', 'public.submit_explore_community_identification(uuid,uuid,uuid,public.explore_identification_disagreement,text,boolean)', 'Community identification Edge Function mutation RPC.'),
    ('service_role', 'public.sync_taxon_nodes_from_species_dictionary()', 'Community-request taxonomy synchronization RPC.'),
    ('service_role', 'public.upsert_gbif_community_taxa(jsonb,text,integer,boolean)', 'Community-taxonomy import worker RPC.'),
    ('service_role', 'public.user_has_visible_field_trip_profile(uuid,uuid)', 'Dependency of service-owned profile and notification RPCs.'),
    ('service_role', 'public.withdraw_explore_community_identification(uuid,uuid)', 'Community identification Edge Function mutation RPC.');

DO $migration$
DECLARE
    grant_row RECORD;
    routine_oid OID;
    routine_row RECORD;
BEGIN
    FOR grant_row IN
        SELECT
            allowlist.role_name,
            allowlist.routine_signature
        FROM internal.privileged_routine_grants AS allowlist
        ORDER BY allowlist.role_name, allowlist.routine_signature
    LOOP
        routine_oid :=
            pg_catalog.TO_REGPROCEDURE(grant_row.routine_signature);

        IF routine_oid IS NULL THEN
            RAISE EXCEPTION
                'Privileged routine allowlist entry does not resolve: %',
                grant_row.routine_signature;
        END IF;

        SELECT
            namespace_row.nspname AS schema_name,
            function_row.proname AS routine_name,
            pg_catalog.PG_GET_FUNCTION_IDENTITY_ARGUMENTS(
                function_row.oid
            ) AS identity_arguments,
            function_row.prosecdef
        INTO STRICT routine_row
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE function_row.oid = routine_oid;

        IF routine_row.schema_name <> 'public'
           OR NOT routine_row.prosecdef THEN
            RAISE EXCEPTION
                'Allowlisted routine must be a public SECURITY DEFINER function: %',
                grant_row.routine_signature;
        END IF;

        EXECUTE pg_catalog.FORMAT(
            'GRANT EXECUTE ON FUNCTION %I.%I(%s) TO %I',
            routine_row.schema_name,
            routine_row.routine_name,
            routine_row.identity_arguments,
            grant_row.role_name
        );
    END LOOP;
END;
$migration$;

-- SQL-language functions cannot run a procedural caller check. Preserve each
-- reviewed function's signature, attributes, and SQL body while converting it
-- to a PL/pgSQL wrapper with the same return semantics.
DO $migration$
DECLARE
    routine_row RECORD;
    original_definition TEXT;
    definition_marker TEXT := 'AS $function$';
    marker_position INTEGER;
    function_header TEXT;
    original_body TEXT;
    guarded_body TEXT;
    guarded_definition TEXT;
BEGIN
    FOR routine_row IN
        SELECT
            function_row.oid,
            function_row.prosrc,
            function_row.proretset,
            function_row.prorettype
        FROM internal.privileged_routine_grants AS allowlist
        JOIN pg_catalog.pg_proc AS function_row
          ON function_row.oid = pg_catalog.TO_REGPROCEDURE(
              allowlist.routine_signature
          )
        JOIN pg_catalog.pg_language AS language_row
          ON language_row.oid = function_row.prolang
        WHERE allowlist.role_name = 'service_role'
          AND language_row.lanname = 'sql'
        ORDER BY allowlist.routine_signature
    LOOP
        original_definition :=
            pg_catalog.PG_GET_FUNCTIONDEF(routine_row.oid);
        marker_position :=
            pg_catalog.STRPOS(original_definition, definition_marker);

        IF marker_position = 0 THEN
            RAISE EXCEPTION
                'Could not locate SQL body marker for %',
                routine_row.oid::REGPROCEDURE;
        END IF;

        function_header := pg_catalog.SUBSTR(
            original_definition,
            1,
            marker_position - 1
        );
        function_header := pg_catalog.REGEXP_REPLACE(
            function_header,
            'LANGUAGE[[:space:]]+sql',
            'LANGUAGE plpgsql',
            'i'
        );

        IF function_header ~* 'LANGUAGE[[:space:]]+sql' THEN
            RAISE EXCEPTION
                'Could not convert SQL language for %',
                routine_row.oid::REGPROCEDURE;
        END IF;

        original_body := pg_catalog.REGEXP_REPLACE(
            pg_catalog.BTRIM(routine_row.prosrc),
            ';[[:space:]]*$',
            ''
        );

        IF routine_row.proretset THEN
            guarded_body :=
                E'BEGIN\n'
                || E'    PERFORM internal.require_service_role();\n\n'
                || E'    RETURN QUERY\n'
                || original_body
                || E';\nEND;';
        ELSIF routine_row.prorettype = 'pg_catalog.void'::REGTYPE THEN
            guarded_body :=
                E'BEGIN\n'
                || E'    PERFORM internal.require_service_role();\n\n'
                || original_body
                || E';\n    RETURN;\nEND;';
        ELSE
            guarded_body :=
                E'BEGIN\n'
                || E'    PERFORM internal.require_service_role();\n\n'
                || E'    RETURN (\n'
                || original_body
                || E'\n    );\nEND;';
        END IF;

        guarded_definition :=
            function_header
            || definition_marker
            || E'\n'
            || guarded_body
            || E'\n$function$\n';
        BEGIN
            EXECUTE guarded_definition;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE EXCEPTION
                    'Could not wrap service-role SQL function %: %',
                    routine_row.oid::REGPROCEDURE,
                    SQLERRM;
        END;
    END LOOP;
END;
$migration$;

-- Add the same defense-in-depth check to every service-exposed PL/pgSQL
-- routine. This is intentionally catalog-driven so a newly allowlisted
-- service routine cannot omit the in-function caller boundary.
DO $migration$
DECLARE
    routine_row RECORD;
    original_definition TEXT;
    guarded_definition TEXT;
BEGIN
    FOR routine_row IN
        SELECT
            function_row.oid,
            allowlist.routine_signature
        FROM internal.privileged_routine_grants AS allowlist
        JOIN pg_catalog.pg_proc AS function_row
          ON function_row.oid = pg_catalog.TO_REGPROCEDURE(
              allowlist.routine_signature
          )
        JOIN pg_catalog.pg_language AS language_row
          ON language_row.oid = function_row.prolang
        WHERE allowlist.role_name = 'service_role'
          AND language_row.lanname = 'plpgsql'
          AND function_row.prosrc NOT LIKE
              '%internal.require_service_role()%'
        ORDER BY allowlist.routine_signature
    LOOP
        original_definition :=
            pg_catalog.PG_GET_FUNCTIONDEF(routine_row.oid);
        guarded_definition := pg_catalog.REGEXP_REPLACE(
            original_definition,
            E'\n[[:space:]]*BEGIN[[:space:]]*\n',
            E'\nBEGIN\n    PERFORM internal.require_service_role();\n\n',
            'i'
        );

        IF guarded_definition IS NOT DISTINCT FROM original_definition THEN
            RAISE EXCEPTION
                'Could not inject service-role authorization into %',
                routine_row.routine_signature;
        END IF;

        BEGIN
            EXECUTE guarded_definition;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE EXCEPTION
                    'Could not inject service-role authorization into %: %',
                    routine_row.routine_signature,
                    SQLERRM;
        END;
    END LOOP;
END;
$migration$;

-- Fail the migration if the resulting catalog is broader than the allowlist or
-- if any definer routine can resolve attacker-controlled objects.
DO $migration$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'public'
          AND function_row.prosecdef
          AND EXISTS (
              SELECT 1
              FROM pg_catalog.ACLEXPLODE(
                  COALESCE(
                      function_row.proacl,
                      pg_catalog.ACLDEFAULT(
                          'f',
                          function_row.proowner
                      )
                  )
              ) AS acl_row
              WHERE acl_row.grantee = 0
                AND acl_row.privilege_type = 'EXECUTE'
          )
    ) THEN
        RAISE EXCEPTION
            'PUBLIC still has EXECUTE on a public SECURITY DEFINER function.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        CROSS JOIN (
            VALUES ('anon'), ('authenticated'), ('service_role')
        ) AS api_role(role_name)
        WHERE namespace_row.nspname = 'public'
          AND function_row.prosecdef
          AND pg_catalog.HAS_FUNCTION_PRIVILEGE(
              api_role.role_name,
              function_row.oid,
              'EXECUTE'
          )
          AND NOT EXISTS (
              SELECT 1
              FROM internal.privileged_routine_grants AS allowlist
              WHERE allowlist.role_name = api_role.role_name
                AND pg_catalog.TO_REGPROCEDURE(
                    allowlist.routine_signature
                ) = function_row.oid
          )
    ) THEN
        RAISE EXCEPTION
            'An API role has an unexpected SECURITY DEFINER EXECUTE grant.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.privileged_routine_grants AS allowlist
        WHERE NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
            allowlist.role_name,
            pg_catalog.TO_REGPROCEDURE(allowlist.routine_signature),
            'EXECUTE'
        )
    ) THEN
        RAISE EXCEPTION
            'A reviewed SECURITY DEFINER EXECUTE grant is missing.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'public'
          AND function_row.prosecdef
          AND NOT (
              COALESCE(
                  function_row.proconfig,
                  ARRAY[]::TEXT[]
              ) @> ARRAY['search_path=""']::TEXT[]
          )
    ) THEN
        RAISE EXCEPTION
            'A public SECURITY DEFINER function is missing search_path=''''.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.privileged_routine_grants AS allowlist
        JOIN pg_catalog.pg_proc AS function_row
          ON function_row.oid = pg_catalog.TO_REGPROCEDURE(
              allowlist.routine_signature
          )
        WHERE allowlist.role_name = 'authenticated'
          AND function_row.prosrc !~ 'internal[.]require_admin[(]'
          AND function_row.prosrc !~ 'auth[.](uid|jwt)[(]'
    ) THEN
        RAISE EXCEPTION
            'An authenticated definer function lacks caller-bound authorization.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.privileged_routine_grants AS allowlist
        JOIN pg_catalog.pg_proc AS function_row
          ON function_row.oid = pg_catalog.TO_REGPROCEDURE(
              allowlist.routine_signature
          )
        WHERE allowlist.role_name = 'service_role'
          AND function_row.prosrc NOT LIKE
              '%internal.require_service_role()%'
    ) THEN
        RAISE EXCEPTION
            'A service-role definer function lacks in-function authorization.';
    END IF;

    IF EXISTS (
        WITH creator_roles AS (
            SELECT role_row.oid, role_row.rolname
            FROM pg_catalog.pg_roles AS role_row
            WHERE role_row.rolname = 'postgres'
        ),
        candidate_defaults AS (
            SELECT
                creator.rolname AS creator_role,
                'global'::TEXT AS privilege_scope,
                COALESCE(
                    default_acl.defaclacl,
                    pg_catalog.ACLDEFAULT('f', creator.oid)
                ) AS privilege_acl
            FROM creator_roles AS creator
            LEFT JOIN pg_catalog.pg_default_acl AS default_acl
              ON default_acl.defaclrole = creator.oid
             AND default_acl.defaclnamespace = 0
             AND default_acl.defaclobjtype = 'f'

            UNION ALL

            SELECT
                creator.rolname AS creator_role,
                'public'::TEXT AS privilege_scope,
                default_acl.defaclacl AS privilege_acl
            FROM creator_roles AS creator
            JOIN pg_catalog.pg_default_acl AS default_acl
              ON default_acl.defaclrole = creator.oid
             AND default_acl.defaclnamespace = (
                 SELECT namespace_row.oid
                 FROM pg_catalog.pg_namespace AS namespace_row
                 WHERE namespace_row.nspname = 'public'
             )
             AND default_acl.defaclobjtype = 'f'
        )
        SELECT 1
        FROM candidate_defaults AS candidate
        CROSS JOIN LATERAL pg_catalog.ACLEXPLODE(
            candidate.privilege_acl
        ) AS acl_row
        WHERE acl_row.privilege_type = 'EXECUTE'
          AND (
              acl_row.grantee = 0
              OR acl_row.grantee IN (
                  SELECT role_row.oid
                  FROM pg_catalog.pg_roles AS role_row
                  WHERE role_row.rolname IN (
                      'anon',
                      'authenticated',
                      'service_role'
                  )
              )
          )
    ) THEN
        RAISE EXCEPTION
            'A routine creator still has an unsafe default EXECUTE privilege.';
    END IF;

    IF pg_catalog.HAS_SCHEMA_PRIVILEGE('anon', 'public', 'CREATE')
       OR pg_catalog.HAS_SCHEMA_PRIVILEGE(
           'authenticated',
           'public',
           'CREATE'
       )
       OR pg_catalog.HAS_SCHEMA_PRIVILEGE(
           'service_role',
           'public',
           'CREATE'
       ) THEN
        RAISE EXCEPTION
            'An API role can create attacker-controlled objects in public.';
    END IF;
END;
$migration$;
