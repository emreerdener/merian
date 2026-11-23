SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- The V3 normalization operands are constants. Keep the validator and its
-- immutable metrics caller genuinely immutable rather than invoking a generic
-- STABLE polymorphic JSON builder for a constant object.
DO $migration$
DECLARE
    definition TEXT;
    before_fragment TEXT := $before$pg_catalog.jsonb_build_object('version',1,'generation',
              '{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":null}'::JSONB)$before$;
    after_fragment TEXT := $after$'{"version":1,"generation":{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":null}}'::JSONB$after$;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.identification_provenance_is_valid(jsonb)'::regprocedure);
    IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,before_fragment,''))) / pg_catalog.length(before_fragment) <> 1 THEN
        RAISE EXCEPTION 'capture validator volatility source drift';
    END IF;
    EXECUTE pg_catalog.replace(definition,before_fragment,after_fragment);
END;
$migration$;

-- This private contract uses STABLE JSON construction and encoding helpers.
-- Preserve its exact body, typed digest and denial behavior while advertising
-- only the volatility guarantee of its dependencies. No immutable caller,
-- expression index or generated column depends on this helper in this replay.
ALTER FUNCTION internal.initial_evidence_contract(JSONB,TEXT,TEXT) STABLE;

RESET statement_timeout;
RESET lock_timeout;
