\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $test$
DECLARE
    first_user_id UUID := '00000000-0000-4000-8000-00000000d101';
    second_user_id UUID := '00000000-0000-4000-8000-00000000d102';
    first_species_id UUID := '00000000-0000-4000-8000-00000000d111';
    second_species_id UUID := '00000000-0000-4000-8000-00000000d112';
    third_species_id UUID := '00000000-0000-4000-8000-00000000d113';
    first_scan_id UUID := '00000000-0000-4000-8000-00000000d121';
    second_scan_id UUID := '00000000-0000-4000-8000-00000000d122';
    third_scan_id UUID := '00000000-0000-4000-8000-00000000d123';
    null_species_scan_id UUID := '00000000-0000-4000-8000-00000000d124';
    dictionary_scan_id UUID := '00000000-0000-4000-8000-00000000d125';
    target_signature TEXT;
BEGIN
    IF (
        SELECT pg_catalog.COUNT(*)
        FROM pg_catalog.pg_trigger AS trigger_row
        JOIN pg_catalog.pg_class AS relation_row
          ON relation_row.oid = trigger_row.tgrelid
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = relation_row.relnamespace
        WHERE namespace_row.nspname = 'public'
          AND relation_row.relname = 'scans'
          AND NOT trigger_row.tgisinternal
          AND trigger_row.tgname IN (
              'sync_user_species_counts_after_insert',
              'sync_user_species_counts_after_delete',
              'sync_user_species_counts_after_update',
              'sync_user_species_counts_after_truncate'
          )
          AND (trigger_row.tgtype::INTEGER & 1) = 0
    ) <> 4 THEN
        RAISE EXCEPTION
            'species-count maintenance is not exactly four statement triggers';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger AS trigger_row
        JOIN pg_catalog.pg_class AS relation_row
          ON relation_row.oid = trigger_row.tgrelid
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = relation_row.relnamespace
        WHERE namespace_row.nspname = 'public'
          AND relation_row.relname = 'scans'
          AND trigger_row.tgname = 'unified_species_count_sync'
    ) OR pg_catalog.TO_REGPROCEDURE(
        'public.sync_global_species_count()'
    ) IS NOT NULL THEN
        RAISE EXCEPTION 'legacy full-history species recount is still installed';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger AS trigger_row
        WHERE trigger_row.tgname = 'sync_user_species_counts_after_insert'
          AND trigger_row.tgrelid = 'public.scans'::REGCLASS
          AND trigger_row.tgnewtable = 'inserted_scans'
          AND trigger_row.tgoldtable IS NULL
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger AS trigger_row
        WHERE trigger_row.tgname = 'sync_user_species_counts_after_delete'
          AND trigger_row.tgrelid = 'public.scans'::REGCLASS
          AND trigger_row.tgoldtable = 'deleted_scans'
          AND trigger_row.tgnewtable IS NULL
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger AS trigger_row
        WHERE trigger_row.tgname = 'sync_user_species_counts_after_update'
          AND trigger_row.tgrelid = 'public.scans'::REGCLASS
          AND trigger_row.tgoldtable = 'previous_scans'
          AND trigger_row.tgnewtable = 'current_scans'
          AND trigger_row.tgattr::TEXT = ''
    ) THEN
        RAISE EXCEPTION
            'species-count triggers do not expose the expected transition tables';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'internal'
          AND (
              function_row.proname = 'apply_user_species_scan_count_deltas'
              OR function_row.proname LIKE
                  'sync_user_species_counts_after_scan_%'
          )
          AND (
              NOT function_row.prosecdef
              OR NOT (
                  COALESCE(
                      function_row.proconfig,
                      ARRAY[]::TEXT[]
                  ) @> ARRAY['search_path=""']::TEXT[]
              )
          )
    ) THEN
        RAISE EXCEPTION
            'a species-count definer routine lacks an empty search_path';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.user_species_scan_counts',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.user_species_scan_counts',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.user_species_scan_counts',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'an API role can read the species-count ledger';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint AS constraint_row
        JOIN pg_catalog.pg_class AS relation_row
          ON relation_row.oid = constraint_row.conrelid
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = relation_row.relnamespace
        WHERE namespace_row.nspname = 'internal'
          AND relation_row.relname = 'user_species_scan_counts'
          AND constraint_row.contype = 'f'
          AND constraint_row.confrelid =
              'public.species_dictionary'::REGCLASS
          AND constraint_row.confdeltype = 'a'
          AND constraint_row.condeferrable
          AND constraint_row.condeferred
    ) THEN
        RAISE EXCEPTION
            'species-count dictionary FK is not deferred NO ACTION';
    END IF;

    FOREACH target_signature IN ARRAY ARRAY[
        'internal.apply_user_species_scan_count_deltas(uuid[],uuid[],bigint[])',
        'internal.sync_user_species_counts_after_scan_insert()',
        'internal.sync_user_species_counts_after_scan_delete()',
        'internal.sync_user_species_counts_after_scan_update()',
        'internal.sync_user_species_counts_after_scan_truncate()'
    ]
    LOOP
        IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
            'anon',
            target_signature,
            'EXECUTE'
        ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
            'authenticated',
            target_signature,
            'EXECUTE'
        ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
            'service_role',
            target_signature,
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'an API role can execute private species-count routine %',
                target_signature;
        END IF;
    END LOOP;

    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        email_confirmed_at,
        last_sign_in_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at,
        is_anonymous
    )
    SELECT
        '00000000-0000-0000-0000-000000000000'::UUID,
        seed.user_id,
        'authenticated',
        'authenticated',
        seed.email,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}'::JSONB,
        '{}'::JSONB,
        pg_catalog.NOW() - INTERVAL '30 days',
        pg_catalog.NOW(),
        FALSE
    FROM (
        VALUES
            (
                first_user_id,
                'species-count-first@example.invalid'
            ),
            (
                second_user_id,
                'species-count-second@example.invalid'
            )
    ) AS seed(user_id, email);

    INSERT INTO public.users (
        id,
        email,
        public_username,
        public_author_name,
        public_identity_source,
        created_at,
        subscription_tier
    )
    VALUES
        (
            first_user_id,
            'species-count-first@example.invalid',
            'species_count_d101',
            'Species Count First',
            'alias',
            pg_catalog.NOW() - INTERVAL '30 days',
            'free'
        ),
        (
            second_user_id,
            'species-count-second@example.invalid',
            'species_count_d102',
            'Species Count Second',
            'alias',
            pg_catalog.NOW() - INTERVAL '30 days',
            'free'
        )
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        public_username = EXCLUDED.public_username,
        public_author_name = EXCLUDED.public_author_name,
        public_identity_source = EXCLUDED.public_identity_source,
        created_at = EXCLUDED.created_at,
        subscription_tier = EXCLUDED.subscription_tier;

    INSERT INTO public.species_dictionary (
        id,
        scientific_name,
        common_names,
        kingdom,
        phylum,
        class,
        "order",
        family,
        genus,
        native_region
    )
    VALUES
        (
            first_species_id,
            'Incrementa prima',
            '{"en":"Incremental first"}'::JSONB,
            'Animalia',
            'Chordata',
            'Aves',
            'Passeriformes',
            'Incrementidae',
            'Incrementa',
            'Test region'
        ),
        (
            second_species_id,
            'Incrementa secunda',
            '{"en":"Incremental second"}'::JSONB,
            'Animalia',
            'Chordata',
            'Aves',
            'Passeriformes',
            'Incrementidae',
            'Incrementa',
            'Test region'
        ),
        (
            third_species_id,
            'Incrementa tertia',
            '{"en":"Incremental third"}'::JSONB,
            'Animalia',
            'Chordata',
            'Aves',
            'Passeriformes',
            'Incrementidae',
            'Incrementa',
            'Test region'
        );

    INSERT INTO public.scans (
        id,
        user_id,
        species_id,
        ai_confidence_score
    )
    VALUES
        (first_scan_id, first_user_id, first_species_id, 0.95),
        (second_scan_id, first_user_id, first_species_id, 0.94),
        (third_scan_id, first_user_id, second_species_id, 0.93),
        (null_species_scan_id, first_user_id, NULL, 0.10);

    IF (
        SELECT users.total_species_discovered
        FROM public.users AS users
        WHERE users.id = first_user_id
    ) <> 2 OR NOT EXISTS (
        SELECT 1
        FROM internal.user_species_scan_counts AS counts
        WHERE counts.user_id = first_user_id
          AND counts.species_id = first_species_id
          AND counts.scan_count = 2
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.user_species_scan_counts AS counts
        WHERE counts.user_id = first_user_id
          AND counts.species_id = second_species_id
          AND counts.scan_count = 1
    ) THEN
        RAISE EXCEPTION
            'bulk insert did not create exact distinct-species ledger state';
    END IF;

    -- A deliberately corrupted public projection proves that an unrelated
    -- scan update no longer invokes a hidden full-history recount.
    UPDATE public.users AS users
    SET total_species_discovered = 777
    WHERE users.id = first_user_id;

    UPDATE public.scans AS scans
    SET weather_condition = 'contract-unrelated-update'
    WHERE scans.user_id = first_user_id;

    IF (
        SELECT users.total_species_discovered
        FROM public.users AS users
        WHERE users.id = first_user_id
    ) <> 777 OR (
        SELECT pg_catalog.SUM(counts.scan_count)
        FROM internal.user_species_scan_counts AS counts
        WHERE counts.user_id = first_user_id
    ) <> 3 THEN
        RAISE EXCEPTION
            'an unrelated scan update changed species-count state';
    END IF;

    UPDATE public.users AS users
    SET total_species_discovered = 2
    WHERE users.id = first_user_id;

    -- One bulk statement exercises both owner and species transitions.
    UPDATE public.scans AS scans
    SET
        user_id = CASE
            WHEN scans.id = first_scan_id THEN second_user_id
            ELSE scans.user_id
        END,
        species_id = CASE
            WHEN scans.id = third_scan_id THEN third_species_id
            ELSE scans.species_id
        END
    WHERE scans.id IN (first_scan_id, third_scan_id);

    IF (
        SELECT users.total_species_discovered
        FROM public.users AS users
        WHERE users.id = first_user_id
    ) <> 2 OR (
        SELECT users.total_species_discovered
        FROM public.users AS users
        WHERE users.id = second_user_id
    ) <> 1 THEN
        RAISE EXCEPTION
            'bulk OLD/NEW transitions produced incorrect user totals';
    END IF;

    -- Moving the final first-species scan away from the old owner must
    -- decrement OLD.user_id while preserving the new owner's duplicate count.
    UPDATE public.scans AS scans
    SET user_id = second_user_id
    WHERE scans.id = second_scan_id;

    IF (
        SELECT users.total_species_discovered
        FROM public.users AS users
        WHERE users.id = first_user_id
    ) <> 1 OR (
        SELECT users.total_species_discovered
        FROM public.users AS users
        WHERE users.id = second_user_id
    ) <> 1 OR NOT EXISTS (
        SELECT 1
        FROM internal.user_species_scan_counts AS counts
        WHERE counts.user_id = second_user_id
          AND counts.species_id = first_species_id
          AND counts.scan_count = 2
    ) THEN
        RAISE EXCEPTION
            'owner transfer did not clear OLD and increment NEW atomically';
    END IF;

    UPDATE public.scans AS scans
    SET species_id = second_species_id
    WHERE scans.id = first_scan_id;

    IF (
        SELECT users.total_species_discovered
        FROM public.users AS users
        WHERE users.id = second_user_id
    ) <> 2 THEN
        RAISE EXCEPTION
            'species replacement did not maintain both ledger boundaries';
    END IF;

    DELETE FROM public.scans AS scans
    WHERE scans.id = second_scan_id;

    IF (
        SELECT users.total_species_discovered
        FROM public.users AS users
        WHERE users.id = second_user_id
    ) <> 1 OR EXISTS (
        SELECT 1
        FROM internal.user_species_scan_counts AS counts
        WHERE counts.user_id = second_user_id
          AND counts.species_id = first_species_id
    ) THEN
        RAISE EXCEPTION
            'last-scan deletion did not remove one distinct-species unit';
    END IF;

    -- Account erasure retains the biological row as an ownerless tombstone.
    -- Its OLD owner must lose the final species unit while the NULL NEW owner
    -- is excluded from the private ledger.
    UPDATE public.scans AS scans
    SET user_id = NULL,
        is_tombstoned = TRUE
    WHERE scans.id = third_scan_id;

    IF (
        SELECT users.total_species_discovered
        FROM public.users AS users
        WHERE users.id = first_user_id
    ) <> 0 OR EXISTS (
        SELECT 1
        FROM internal.user_species_scan_counts AS counts
        WHERE counts.user_id = first_user_id
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.scans AS scans
        WHERE scans.id = third_scan_id
          AND scans.user_id IS NULL
          AND scans.is_tombstoned
    ) THEN
        RAISE EXCEPTION
            'ownerless tombstone did not clear OLD owner species state';
    END IF;

    DELETE FROM public.scans AS scans
    WHERE scans.id IN (
        first_scan_id,
        third_scan_id,
        null_species_scan_id
    );

    IF EXISTS (
        SELECT 1
        FROM public.users AS users
        WHERE users.id IN (first_user_id, second_user_id)
          AND users.total_species_discovered <> 0
    ) OR EXISTS (
        SELECT 1
        FROM internal.user_species_scan_counts AS counts
        WHERE counts.user_id IN (first_user_id, second_user_id)
    ) THEN
        RAISE EXCEPTION
            'bulk deletion did not clear incremental species-count state';
    END IF;

    BEGIN
        PERFORM internal.apply_user_species_scan_count_deltas(
            ARRAY[first_user_id],
            ARRAY[first_species_id],
            ARRAY[-1::BIGINT]
        );
        RAISE EXCEPTION 'expected missing-ledger decrement rejection';
    EXCEPTION
        WHEN CHECK_VIOLATION THEN
            IF SQLERRM <> 'user_species_scan_count_underflow' THEN
                RAISE;
            END IF;
    END;

    -- Dictionary deletion sets matching scan species to null. The deferred
    -- ledger FK lets that scan transition remove the ledger row and projection
    -- before checking referential integrity at transaction end.
    INSERT INTO public.scans (
        id,
        user_id,
        species_id,
        ai_confidence_score
    )
    VALUES (
        dictionary_scan_id,
        first_user_id,
        third_species_id,
        0.92
    );

    DELETE FROM public.species_dictionary AS species
    WHERE species.id = third_species_id;

    SET CONSTRAINTS internal.user_species_scan_counts_species_id_fkey IMMEDIATE;

    IF (
        SELECT scans.species_id
        FROM public.scans AS scans
        WHERE scans.id = dictionary_scan_id
    ) IS NOT NULL OR (
        SELECT users.total_species_discovered
        FROM public.users AS users
        WHERE users.id = first_user_id
    ) <> 0 OR EXISTS (
        SELECT 1
        FROM internal.user_species_scan_counts AS counts
        WHERE counts.user_id = first_user_id
          AND counts.species_id = third_species_id
    ) THEN
        RAISE EXCEPTION
            'dictionary deletion did not flow through scan transition state';
    END IF;
END;
$test$;

SELECT extensions.pass(
    'species-count ledger, statement triggers, OLD/NEW handling, and private ACLs hold'
);
SELECT * FROM extensions.finish();
ROLLBACK;
