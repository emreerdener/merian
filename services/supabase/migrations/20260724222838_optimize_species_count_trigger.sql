-- Replace the per-row, full-history species recount with a statement-level
-- incremental ledger. The scan lock makes the one-time backfill and trigger
-- cutover atomic with respect to scan inserts, updates, deletes, and cascades.
LOCK TABLE public.scans IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE internal.user_species_scan_counts (
    user_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    species_id UUID NOT NULL,
    scan_count BIGINT NOT NULL,
    PRIMARY KEY (user_id, species_id),
    CONSTRAINT user_species_scan_counts_positive_check
        CHECK (scan_count > 0),
    CONSTRAINT user_species_scan_counts_species_id_fkey
        FOREIGN KEY (species_id)
        REFERENCES public.species_dictionary(id)
        ON DELETE NO ACTION
        DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX user_species_scan_counts_species_idx
    ON internal.user_species_scan_counts (species_id, user_id);

ALTER TABLE internal.user_species_scan_counts
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.user_species_scan_counts
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.user_species_scan_counts IS
    'Private incremental ledger of non-null public.scans species assignments. One row represents one distinct species observed by one non-sentinel owner.';
COMMENT ON COLUMN internal.user_species_scan_counts.scan_count IS
    'Number of scans currently assigned to this user/species pair; crossing zero creates or removes one total_species_discovered unit.';
COMMENT ON CONSTRAINT user_species_scan_counts_species_id_fkey
    ON internal.user_species_scan_counts IS
    'Deferred so species deletion can SET NULL on public.scans and let its transition trigger remove ledger state before referential validation.';

INSERT INTO internal.user_species_scan_counts (
    user_id,
    species_id,
    scan_count
)
SELECT
    scans.user_id,
    scans.species_id,
    pg_catalog.COUNT(*)::BIGINT
FROM public.scans AS scans
WHERE scans.species_id IS NOT NULL
  AND scans.user_id
      <> '00000000-0000-0000-0000-000000000000'::UUID
GROUP BY scans.user_id, scans.species_id
ORDER BY scans.user_id, scans.species_id;

-- Repair historical drift once at cutover. Future updates change the public
-- total only when a ledger row crosses the zero boundary.
WITH species_totals AS (
    SELECT
        users.id AS user_id,
        pg_catalog.COUNT(counts.species_id)::INTEGER AS species_count
    FROM public.users AS users
    LEFT JOIN internal.user_species_scan_counts AS counts
        ON counts.user_id = users.id
    WHERE users.id
        <> '00000000-0000-0000-0000-000000000000'::UUID
    GROUP BY users.id
)
UPDATE public.users AS users
SET total_species_discovered = totals.species_count
FROM species_totals AS totals
WHERE users.id = totals.user_id
  AND users.total_species_discovered IS DISTINCT FROM totals.species_count;

CREATE OR REPLACE FUNCTION internal.apply_user_species_scan_count_deltas(
    p_user_ids UUID[],
    p_species_ids UUID[],
    p_scan_deltas BIGINT[]
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF p_user_ids IS NULL
       OR p_species_ids IS NULL
       OR p_scan_deltas IS NULL
       OR pg_catalog.CARDINALITY(p_user_ids)
            <> pg_catalog.CARDINALITY(p_species_ids)
       OR pg_catalog.CARDINALITY(p_user_ids)
            <> pg_catalog.CARDINALITY(p_scan_deltas) THEN
        RAISE EXCEPTION 'invalid_user_species_scan_count_deltas'
            USING ERRCODE = '22023';
    END IF;

    IF pg_catalog.CARDINALITY(p_user_ids) = 0 THEN
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM ROWS FROM (
            pg_catalog.UNNEST(p_user_ids),
            pg_catalog.UNNEST(p_species_ids),
            pg_catalog.UNNEST(p_scan_deltas)
        ) AS deltas(user_id, species_id, scan_delta)
        WHERE deltas.user_id IS NULL
           OR deltas.species_id IS NULL
           OR deltas.scan_delta IS NULL
           OR deltas.scan_delta = 0
           OR deltas.user_id
                = '00000000-0000-0000-0000-000000000000'::UUID
    ) OR EXISTS (
        SELECT 1
        FROM ROWS FROM (
            pg_catalog.UNNEST(p_user_ids),
            pg_catalog.UNNEST(p_species_ids),
            pg_catalog.UNNEST(p_scan_deltas)
        ) AS deltas(user_id, species_id, scan_delta)
        GROUP BY deltas.user_id, deltas.species_id
        HAVING pg_catalog.COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'invalid_user_species_scan_count_deltas'
            USING ERRCODE = '22023';
    END IF;

    -- Serializing all changes for the same user prevents concurrent statements
    -- touching different species from losing a public total increment. UUID
    -- order gives multi-user owner transfers one deterministic lock order.
    PERFORM users.id
    FROM public.users AS users
    JOIN (
        SELECT DISTINCT deltas.user_id
        FROM ROWS FROM (
            pg_catalog.UNNEST(p_user_ids),
            pg_catalog.UNNEST(p_species_ids),
            pg_catalog.UNNEST(p_scan_deltas)
        ) AS deltas(user_id, species_id, scan_delta)
    ) AS affected
      ON affected.user_id = users.id
    ORDER BY users.id
    FOR NO KEY UPDATE OF users;

    -- Missing or insufficient state for a still-live owner is corruption, not
    -- a valid decrement. Abort the scan write instead of hiding drift. A parent
    -- user cascade is the only tolerated missing-owner case.
    IF EXISTS (
        SELECT 1
        FROM ROWS FROM (
            pg_catalog.UNNEST(p_user_ids),
            pg_catalog.UNNEST(p_species_ids),
            pg_catalog.UNNEST(p_scan_deltas)
        ) AS negative(user_id, species_id, scan_delta)
        JOIN public.users AS users
          ON users.id = negative.user_id
        LEFT JOIN internal.user_species_scan_counts AS counts
          ON counts.user_id = negative.user_id
         AND counts.species_id = negative.species_id
        WHERE negative.scan_delta < 0
          AND (
              counts.user_id IS NULL
              OR counts.scan_count < -negative.scan_delta
          )
    ) THEN
        RAISE EXCEPTION 'user_species_scan_count_underflow'
            USING ERRCODE = '23514';
    END IF;

    -- Existing positive pairs only increase their private scan count.
    WITH positive_deltas AS (
        SELECT
            deltas.user_id,
            deltas.species_id,
            deltas.scan_delta
        FROM ROWS FROM (
            pg_catalog.UNNEST(p_user_ids),
            pg_catalog.UNNEST(p_species_ids),
            pg_catalog.UNNEST(p_scan_deltas)
        ) AS deltas(user_id, species_id, scan_delta)
        WHERE deltas.scan_delta > 0
    )
    UPDATE internal.user_species_scan_counts AS counts
    SET scan_count = counts.scan_count + positive.scan_delta
    FROM positive_deltas AS positive
    WHERE counts.user_id = positive.user_id
      AND counts.species_id = positive.species_id;

    -- New positive pairs create one distinct-species unit. ON CONFLICT is a
    -- defensive guard; the ordered user locks serialize normal trigger calls.
    WITH positive_deltas AS (
        SELECT
            deltas.user_id,
            deltas.species_id,
            deltas.scan_delta
        FROM ROWS FROM (
            pg_catalog.UNNEST(p_user_ids),
            pg_catalog.UNNEST(p_species_ids),
            pg_catalog.UNNEST(p_scan_deltas)
        ) AS deltas(user_id, species_id, scan_delta)
        WHERE deltas.scan_delta > 0
    ),
    inserted_species AS (
        INSERT INTO internal.user_species_scan_counts (
            user_id,
            species_id,
            scan_count
        )
        SELECT
            positive.user_id,
            positive.species_id,
            positive.scan_delta
        FROM positive_deltas AS positive
        ORDER BY positive.user_id, positive.species_id
        ON CONFLICT (user_id, species_id) DO NOTHING
        RETURNING user_id
    ),
    increments AS (
        SELECT
            inserted.user_id,
            pg_catalog.COUNT(*)::INTEGER AS species_count
        FROM inserted_species AS inserted
        GROUP BY inserted.user_id
    )
    UPDATE public.users AS users
    SET total_species_discovered =
        users.total_species_discovered + increments.species_count
    FROM increments
    WHERE users.id = increments.user_id;

    -- A zero result removes the distinct-species row and exactly one public
    -- total unit. A missing row is tolerated only when its parent user and the
    -- now-irrelevant public projection are being deleted in this transaction.
    WITH negative_deltas AS (
        SELECT
            deltas.user_id,
            deltas.species_id,
            deltas.scan_delta
        FROM ROWS FROM (
            pg_catalog.UNNEST(p_user_ids),
            pg_catalog.UNNEST(p_species_ids),
            pg_catalog.UNNEST(p_scan_deltas)
        ) AS deltas(user_id, species_id, scan_delta)
        WHERE deltas.scan_delta < 0
    ),
    removed_species AS (
        DELETE FROM internal.user_species_scan_counts AS counts
        USING negative_deltas AS negative
        WHERE counts.user_id = negative.user_id
          AND counts.species_id = negative.species_id
          AND counts.scan_count <= -negative.scan_delta
        RETURNING counts.user_id
    ),
    decrements AS (
        SELECT
            removed.user_id,
            pg_catalog.COUNT(*)::INTEGER AS species_count
        FROM removed_species AS removed
        GROUP BY removed.user_id
    )
    UPDATE public.users AS users
    SET total_species_discovered = GREATEST(
        users.total_species_discovered - decrements.species_count,
        0
    )
    FROM decrements
    WHERE users.id = decrements.user_id;

    -- Remaining negative pairs stay positive and do not change the distinct
    -- total.
    WITH negative_deltas AS (
        SELECT
            deltas.user_id,
            deltas.species_id,
            deltas.scan_delta
        FROM ROWS FROM (
            pg_catalog.UNNEST(p_user_ids),
            pg_catalog.UNNEST(p_species_ids),
            pg_catalog.UNNEST(p_scan_deltas)
        ) AS deltas(user_id, species_id, scan_delta)
        WHERE deltas.scan_delta < 0
    )
    UPDATE internal.user_species_scan_counts AS counts
    SET scan_count = counts.scan_count + negative.scan_delta
    FROM negative_deltas AS negative
    WHERE counts.user_id = negative.user_id
      AND counts.species_id = negative.species_id
      AND counts.scan_count > -negative.scan_delta;
END;
$$;

COMMENT ON FUNCTION internal.apply_user_species_scan_count_deltas(
    UUID[],
    UUID[],
    BIGINT[]
) IS
    'Applies one statement-level set of aggregated scan deltas and updates distinct species totals only when a user/species ledger row crosses zero.';

CREATE OR REPLACE FUNCTION internal.sync_user_species_counts_after_scan_insert()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    changed_user_ids UUID[];
    changed_species_ids UUID[];
    changed_scan_counts BIGINT[];
BEGIN
    SELECT
        pg_catalog.ARRAY_AGG(
            changes.user_id
            ORDER BY changes.user_id, changes.species_id
        ),
        pg_catalog.ARRAY_AGG(
            changes.species_id
            ORDER BY changes.user_id, changes.species_id
        ),
        pg_catalog.ARRAY_AGG(
            changes.scan_delta
            ORDER BY changes.user_id, changes.species_id
        )
    INTO
        changed_user_ids,
        changed_species_ids,
        changed_scan_counts
    FROM (
        SELECT
            inserted.user_id,
            inserted.species_id,
            pg_catalog.COUNT(*)::BIGINT AS scan_delta
        FROM inserted_scans AS inserted
        WHERE inserted.species_id IS NOT NULL
          AND inserted.user_id
              <> '00000000-0000-0000-0000-000000000000'::UUID
        GROUP BY inserted.user_id, inserted.species_id
    ) AS changes;

    IF changed_user_ids IS NOT NULL THEN
        PERFORM internal.apply_user_species_scan_count_deltas(
            changed_user_ids,
            changed_species_ids,
            changed_scan_counts
        );
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION internal.sync_user_species_counts_after_scan_delete()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    changed_user_ids UUID[];
    changed_species_ids UUID[];
    changed_scan_counts BIGINT[];
BEGIN
    SELECT
        pg_catalog.ARRAY_AGG(
            changes.user_id
            ORDER BY changes.user_id, changes.species_id
        ),
        pg_catalog.ARRAY_AGG(
            changes.species_id
            ORDER BY changes.user_id, changes.species_id
        ),
        pg_catalog.ARRAY_AGG(
            changes.scan_delta
            ORDER BY changes.user_id, changes.species_id
        )
    INTO
        changed_user_ids,
        changed_species_ids,
        changed_scan_counts
    FROM (
        SELECT
            deleted.user_id,
            deleted.species_id,
            -pg_catalog.COUNT(*)::BIGINT AS scan_delta
        FROM deleted_scans AS deleted
        WHERE deleted.species_id IS NOT NULL
          AND deleted.user_id
              <> '00000000-0000-0000-0000-000000000000'::UUID
        GROUP BY deleted.user_id, deleted.species_id
    ) AS changes;

    IF changed_user_ids IS NOT NULL THEN
        PERFORM internal.apply_user_species_scan_count_deltas(
            changed_user_ids,
            changed_species_ids,
            changed_scan_counts
        );
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION internal.sync_user_species_counts_after_scan_update()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    changed_user_ids UUID[];
    changed_species_ids UUID[];
    changed_scan_counts BIGINT[];
BEGIN
    SELECT
        pg_catalog.ARRAY_AGG(
            changes.user_id
            ORDER BY changes.user_id, changes.species_id
        ),
        pg_catalog.ARRAY_AGG(
            changes.species_id
            ORDER BY changes.user_id, changes.species_id
        ),
        pg_catalog.ARRAY_AGG(
            changes.scan_delta
            ORDER BY changes.user_id, changes.species_id
        )
    INTO
        changed_user_ids,
        changed_species_ids,
        changed_scan_counts
    FROM (
        SELECT
            raw_changes.user_id,
            raw_changes.species_id,
            pg_catalog.SUM(raw_changes.scan_delta)::BIGINT AS scan_delta
        FROM (
            SELECT
                previous.user_id,
                previous.species_id,
                -1::BIGINT AS scan_delta
            FROM previous_scans AS previous
            WHERE previous.species_id IS NOT NULL
              AND previous.user_id
                  <> '00000000-0000-0000-0000-000000000000'::UUID

            UNION ALL

            SELECT
                current.user_id,
                current.species_id,
                1::BIGINT AS scan_delta
            FROM current_scans AS current
            WHERE current.species_id IS NOT NULL
              AND current.user_id
                  <> '00000000-0000-0000-0000-000000000000'::UUID
        ) AS raw_changes
        GROUP BY raw_changes.user_id, raw_changes.species_id
        HAVING pg_catalog.SUM(raw_changes.scan_delta) <> 0
    ) AS changes;

    -- PostgreSQL does not permit UPDATE OF together with transition tables.
    -- Comparing the complete OLD/NEW statement sets makes unrelated updates a
    -- no-op without falling back to one trigger invocation per row.
    IF changed_user_ids IS NOT NULL THEN
        PERFORM internal.apply_user_species_scan_count_deltas(
            changed_user_ids,
            changed_species_ids,
            changed_scan_counts
        );
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION internal.sync_user_species_counts_after_scan_truncate()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    TRUNCATE TABLE internal.user_species_scan_counts;

    UPDATE public.users AS users
    SET total_species_discovered = 0
    WHERE users.id
        <> '00000000-0000-0000-0000-000000000000'::UUID
      AND users.total_species_discovered <> 0;

    RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION internal.apply_user_species_scan_count_deltas(
    UUID[],
    UUID[],
    BIGINT[]
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.sync_user_species_counts_after_scan_insert()
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.sync_user_species_counts_after_scan_delete()
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.sync_user_species_counts_after_scan_update()
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.sync_user_species_counts_after_scan_truncate()
    FROM PUBLIC, anon, authenticated, service_role;

-- The ghost-profile merge previously suppressed the expensive row trigger and
-- performed one explicit recount. These incremental statement triggers stay
-- enabled during that merge so the ledger cannot diverge; the existing final
-- recount remains a harmless consistency check for the destination profile.
DROP TRIGGER IF EXISTS unified_species_count_sync ON public.scans;
DROP FUNCTION IF EXISTS public.sync_global_species_count();

CREATE TRIGGER sync_user_species_counts_after_insert
AFTER INSERT ON public.scans
REFERENCING NEW TABLE AS inserted_scans
FOR EACH STATEMENT
EXECUTE FUNCTION internal.sync_user_species_counts_after_scan_insert();

CREATE TRIGGER sync_user_species_counts_after_delete
AFTER DELETE ON public.scans
REFERENCING OLD TABLE AS deleted_scans
FOR EACH STATEMENT
EXECUTE FUNCTION internal.sync_user_species_counts_after_scan_delete();

CREATE TRIGGER sync_user_species_counts_after_update
AFTER UPDATE ON public.scans
REFERENCING OLD TABLE AS previous_scans NEW TABLE AS current_scans
FOR EACH STATEMENT
EXECUTE FUNCTION internal.sync_user_species_counts_after_scan_update();

CREATE TRIGGER sync_user_species_counts_after_truncate
AFTER TRUNCATE ON public.scans
FOR EACH STATEMENT
EXECUTE FUNCTION internal.sync_user_species_counts_after_scan_truncate();
