-- Coding checkpoint: closed storage variants and legacy composite compatibility.
-- No CPM constructor, verification settlement, admission, grant or activation.
-- The existing receipt-proof constraint and transaction witnesses remain intact.
SET statement_timeout = '60s';
SET lock_timeout = '5s';

-- This checks the storage union only. It is NOT verification/admission authority.
-- In particular a self-consistent digest cannot prove inspected media or funding.
CREATE FUNCTION internal.initial_admission_variant_fields_valid(
    p_variant TEXT, p_legacy TEXT[], p_verification TEXT,
    p_verification_digest TEXT, p_retained_roles TEXT,
    p_capacity_predecessor JSONB, p_original_expires_at TIMESTAMPTZ
) RETURNS BOOLEAN LANGUAGE SQL IMMUTABLE SET search_path = '' AS $$
    SELECT COALESCE(
        CASE p_variant
            WHEN 'server_prepared_v3' THEN
                p_legacy IS NOT NULL AND array_ndims(p_legacy)=1
                AND cardinality(p_legacy) BETWEEN 6 AND 7
                AND NOT EXISTS(SELECT 1 FROM unnest(p_legacy) v WHERE v IS NULL)
                AND p_verification IS NULL AND p_verification_digest IS NULL
                AND p_retained_roles IS NULL AND p_capacity_predecessor IS NULL
                AND p_original_expires_at IS NULL
            WHEN 'client_prepared_photo_v1' THEN
                p_legacy IS NOT NULL AND array_ndims(p_legacy)=1
                AND cardinality(p_legacy) BETWEEN 6 AND 7
                AND NOT EXISTS(SELECT 1 FROM unnest(p_legacy) v WHERE v IS NOT NULL)
                AND p_verification IS NOT NULL AND octet_length(p_verification) BETWEEN 1 AND 65536
                AND p_verification_digest IS NOT NULL AND p_verification_digest ~ '^[0-9a-f]{64}$'
                AND p_retained_roles IS NOT NULL AND octet_length(p_retained_roles) BETWEEN 1 AND 65536
                AND p_capacity_predecessor IS NOT NULL
                AND jsonb_typeof(p_capacity_predecessor)='object'
                AND octet_length(p_capacity_predecessor::TEXT)<=16384
                AND p_original_expires_at IS NOT NULL AND isfinite(p_original_expires_at)
            ELSE FALSE
        END, FALSE);
$$;
REVOKE ALL ON FUNCTION internal.initial_admission_variant_fields_valid(TEXT,TEXT[],TEXT,TEXT,TEXT,JSONB,TIMESTAMPTZ)
    FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE internal.initial_preparation_admission_staging
    ADD COLUMN admission_variant TEXT NOT NULL DEFAULT 'server_prepared_v3',
    ADD COLUMN cpm_verification TEXT,
    ADD COLUMN cpm_verification_digest TEXT,
    ADD COLUMN cpm_retained_roles TEXT,
    ADD COLUMN cpm_capacity_predecessor JSONB,
    ADD COLUMN original_admission_expires_at TIMESTAMPTZ,
    ADD CONSTRAINT initial_admission_stage_variant_shape CHECK (
        internal.initial_admission_variant_fields_valid(admission_variant,
            ARRAY[outcome,installation,protocol,destination,phase_window,mapping,media_binding],
            cpm_verification,cpm_verification_digest,cpm_retained_roles,
            cpm_capacity_predecessor,original_admission_expires_at));

ALTER TABLE internal.initial_preparation_admission_receipts
    ADD COLUMN admission_variant TEXT NOT NULL DEFAULT 'server_prepared_v3',
    ADD COLUMN cpm_verification TEXT,
    ADD COLUMN cpm_verification_digest TEXT,
    ADD COLUMN cpm_retained_roles TEXT,
    ADD COLUMN cpm_capacity_predecessor JSONB,
    ADD COLUMN original_admission_expires_at TIMESTAMPTZ,
    ADD CONSTRAINT initial_admission_receipt_variant_shape CHECK (
        internal.initial_admission_variant_fields_valid(admission_variant,
            ARRAY[outcome,installation,protocol,destination,mapping,media_binding],
            cpm_verification,cpm_verification_digest,cpm_retained_roles,
            cpm_capacity_predecessor,original_admission_expires_at));

-- Keep legacy-only NOT NULL constraints in this storage-only increment. A CPM
-- branch remains impossible to persist until its complete consuming writer,
-- proof checks, finite write set, C1 and retained-capacity transitions land.
-- Do not relax them independently or interpret this helper as a verification.

-- jsonb_populate_record(...).* explicitly supplies every composite column;
-- table defaults cannot repair a NULL discriminant in the prospective image.
-- Set it on the original receipt builder without changing canonical proof bytes.
DO $legacy_composite$
DECLARE definition TEXT; anchor TEXT := 'result.accounting:=internal.build_initial_admission_accounting(p_scan);';
BEGIN
    definition:=pg_catalog.pg_get_functiondef('internal.build_initial_admission_receipt(uuid)'::REGPROCEDURE);
    IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,anchor,'')))
        / pg_catalog.length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial admission receipt builder source drift';
    END IF;
    EXECUTE pg_catalog.replace(definition,anchor,
        'result.admission_variant:=''server_prepared_v3'';' || E'\n    ' || anchor);
END;
$legacy_composite$;

RESET lock_timeout;
RESET statement_timeout;
