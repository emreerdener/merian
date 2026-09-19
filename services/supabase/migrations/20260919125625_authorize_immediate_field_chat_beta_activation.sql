-- Owner-requested immediate beta activation. Retained first-day usage remains
-- a lower bound: deleted pre-migration sends cannot be reconstructed. Preserve
-- that floor and all future durable accounting; shorten only a pending fence.
-- Deployment must still verify all three live bundles and explicitly activate.
SET lock_timeout = '10s';
SET statement_timeout = '30s';

ALTER TABLE internal.field_chat_admission_cutover
    ADD COLUMN beta_early_activation_at TIMESTAMPTZ,
    ADD COLUMN beta_original_not_before_utc TIMESTAMPTZ,
    ADD CONSTRAINT field_chat_beta_activation_evidence_check CHECK (
        (beta_early_activation_at IS NULL AND beta_original_not_before_utc IS NULL)
        OR (
            beta_early_activation_at IS NOT NULL
            AND beta_original_not_before_utc IS NOT NULL
            AND beta_early_activation_at < beta_original_not_before_utc
            AND beta_original_not_before_utc = pg_catalog.DATE_TRUNC(
                'day', beta_original_not_before_utc, 'UTC'
            )
        )
    );

COMMENT ON COLUMN internal.field_chat_admission_cutover.beta_early_activation_at IS
    'Database timestamp of the one-time owner-requested beta eligibility change; never activation itself. Known daily usage is preserved, deleted legacy usage may be undercounted for this partial UTC day.';
COMMENT ON COLUMN internal.field_chat_admission_cutover.beta_original_not_before_utc IS
    'Original next-UTC-day fence retained as audit evidence when the beta migration advances a pending cutover.';

DO $migration$
DECLARE
    cutover internal.field_chat_admission_cutover%ROWTYPE;
    eligible_at TIMESTAMPTZ;
BEGIN
    SELECT * INTO STRICT cutover
    FROM internal.field_chat_admission_cutover
    WHERE singleton
    FOR UPDATE;

    IF cutover.migration_id <>
        '20260824210544_preserve_field_chat_daily_usage' THEN
        RAISE EXCEPTION 'field_chat_beta_cutover_source_drift';
    END IF;

    eligible_at := GREATEST(
        pg_catalog.CLOCK_TIMESTAMP(), cutover.seeded_at + INTERVAL '1 microsecond'
    );
    -- Active or already-ready environments do not need an exception. Never
    -- rewrite their activation evidence or their existing eligibility time.
    IF cutover.activated_at IS NULL AND eligible_at < cutover.not_before_utc THEN
        IF cutover.not_before_utc <> pg_catalog.DATE_TRUNC(
            'day', cutover.not_before_utc, 'UTC'
        ) THEN
            RAISE EXCEPTION 'field_chat_beta_cutover_boundary_drift';
        END IF;
        UPDATE internal.field_chat_admission_cutover
        SET beta_original_not_before_utc = cutover.not_before_utc,
            beta_early_activation_at = eligible_at,
            not_before_utc = eligible_at
        WHERE singleton AND activated_at IS NULL;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'field_chat_beta_cutover_missing';
        END IF;
    END IF;
END;
$migration$;

RESET statement_timeout;
RESET lock_timeout;
