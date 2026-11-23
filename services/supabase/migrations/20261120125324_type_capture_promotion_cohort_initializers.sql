SET lock_timeout = '5s';
SET statement_timeout = '2min';
-- Forward-only lint repair. The prepared owner is already locally replayed;
-- preserve its behavior and replace only four implicit empty-value casts.
DO $$
DECLARE definition TEXT; old_fragment TEXT; new_fragment TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.register_capture_promotion_cohort(uuid,uuid,text,text,jsonb)'::regprocedure);
    FOR old_fragment,new_fragment IN SELECT * FROM (VALUES
        ($a$members JSONB := '[]'$a$,$b$members JSONB := '[]'::JSONB$b$),
        ($a$expected_keys JSONB := '[]'$a$,$b$expected_keys JSONB := '[]'::JSONB$b$),
        ($a$input_keys JSONB := '[]'$a$,$b$input_keys JSONB := '[]'::JSONB$b$),
        ($a$operation_ids UUID[] := '{}'$a$,$b$operation_ids UUID[] := '{}'::UUID[]$b$)
    ) AS fragments(old_value,new_value) LOOP
        IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,old_fragment,'')))/pg_catalog.length(old_fragment)<>1 THEN
            RAISE EXCEPTION 'capture cohort initializer source drift';
        END IF;
        definition := pg_catalog.replace(definition,old_fragment,new_fragment);
    END LOOP;
    EXECUTE definition;
END;
$$;
RESET statement_timeout;
RESET lock_timeout;
