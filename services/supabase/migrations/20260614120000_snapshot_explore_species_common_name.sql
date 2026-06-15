ALTER TABLE public.explore_posts
    ADD COLUMN IF NOT EXISTS species_common_name TEXT;

COMMENT ON COLUMN public.explore_posts.species_common_name IS
    'Common-name snapshot shown on Explore, captured from the insight sheet at share time.';

CREATE OR REPLACE FUNCTION public.explore_post_species_common_name(
    snapshot_common_name TEXT,
    common_names JSONB,
    scientific_name TEXT
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        NULLIF(BTRIM(snapshot_common_name), ''),
        public.public_species_common_name(common_names),
        NULLIF(BTRIM(scientific_name), ''),
        'Unknown Subject'
    );
$$;

DO $$
DECLARE
    function_signature TEXT;
    target_function REGPROCEDURE;
    function_definition TEXT;
    patched_definition TEXT;
    previous_expression CONSTANT TEXT :=
        'COALESCE(NULLIF(sd.common_names->>''en'', ''''), sd.scientific_name, ''Unknown Subject'')';
    next_expression CONSTANT TEXT :=
        'public.explore_post_species_common_name(ep.species_common_name, sd.common_names, sd.scientific_name)';
BEGIN
    FOREACH function_signature IN ARRAY ARRAY[
        'public.get_explore_post(uuid, uuid)',
        'public.get_explore_feed(uuid, integer, timestamp with time zone, uuid)',
        'public.get_explore_feed_trending(uuid, integer, integer, timestamp with time zone, uuid)',
        'public.get_explore_feed_nearby(uuid, double precision, double precision, integer, timestamp with time zone, uuid)',
        'public.get_explore_feed_following(uuid, integer, timestamp with time zone, uuid)',
        'public.get_explore_author_posts(uuid, uuid, integer, timestamp with time zone, uuid)',
        'public.get_explore_map_posts(uuid, double precision, double precision, double precision, double precision, integer)',
        'public.get_explore_hashtag_posts(uuid, text, integer, timestamp with time zone, uuid)'
    ] LOOP
        target_function := TO_REGPROCEDURE(function_signature);
        IF target_function IS NULL THEN
            RAISE EXCEPTION 'Could not find Explore RPC % to patch species common-name projection', function_signature;
        END IF;

        function_definition := PG_GET_FUNCTIONDEF(target_function);
        patched_definition := REPLACE(function_definition, previous_expression, next_expression);

        IF patched_definition = function_definition THEN
            RAISE EXCEPTION 'Explore RPC % did not contain expected species common-name projection', function_signature;
        END IF;

        EXECUTE patched_definition;
    END LOOP;
END $$;
