-- Canonical admission limits are unchanged. PostgreSQL renders JSONB with
-- separator spaces that do not occur in the exact canonical wire spelling.
SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Accepted canonical trees have at most 4096 value nodes. Each non-root node
-- contributes at most one comma-space and one object colon-space: at most
-- 2 * (4096 - 1) = 8190 extra UTF-8 bytes. Keys/string escaping and integral
-- numeric spelling are identical for the admitted canonical grammar. These are
-- container bounds, not semantic authority: the existing codecs still enforce
-- canonical byte/node/depth, field, media and original identity constraints.
-- Widening the old structural checks preserves every previously stored row;
-- no evidence, canonical bytes, digest, trigger, role or activation is changed.
ALTER TABLE internal.initial_analysis_submissions
    DROP CONSTRAINT initial_analysis_submissions_input_snapshot_check,
    ADD CONSTRAINT initial_analysis_submissions_input_snapshot_check
        CHECK (jsonb_typeof(input_snapshot) = 'object'
            AND octet_length(input_snapshot::TEXT) <= 1056766),
    DROP CONSTRAINT initial_analysis_submissions_ordered_descriptions_check,
    ADD CONSTRAINT initial_analysis_submissions_ordered_descriptions_check
        CHECK (jsonb_typeof(ordered_descriptions) = 'array'
            AND octet_length(ordered_descriptions::TEXT) <= 1056766),
    DROP CONSTRAINT initial_analysis_submissions_configuration_snapshot_check,
    ADD CONSTRAINT initial_analysis_submissions_configuration_snapshot_check
        CHECK (jsonb_typeof(configuration_snapshot) = 'object'
            AND octet_length(configuration_snapshot::TEXT) <= 73753);

-- Input/descriptions: 1048576 + 8190. Configuration: the documented 65536
-- assignment plus its 27-byte canonical wrapper, then 8190. Funding's existing
-- 16384-byte container already exceeds the current 4096 canonical bound plus
-- 8190, and remains unchanged for original legacy recovery. Result/completion
-- containers are separate owners and are not changed by this correction.
RESET statement_timeout;
RESET lock_timeout;
