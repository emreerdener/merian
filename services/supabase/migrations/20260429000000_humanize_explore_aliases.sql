CREATE OR REPLACE FUNCTION public.build_default_public_alias(target_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    alias_hash BYTEA := DECODE(MD5(target_user_id::TEXT), 'hex');
    first_words TEXT[] := ARRAY[
        'Amber', 'Aster', 'Briar', 'Cedar',
        'Clover', 'Ember', 'Fern', 'Juniper',
        'Maple', 'Meadow', 'Moss', 'Oak',
        'River', 'Sage', 'Stone', 'Willow'
    ];
    second_words TEXT[] := ARRAY[
        'Brook', 'Dawn', 'Dune', 'Field',
        'Glen', 'Grove', 'Harbor', 'Hollow',
        'Path', 'Ridge', 'Sky', 'Sprout',
        'Trail', 'Vale', 'Vista', 'Wren'
    ];
    first_index INTEGER;
    second_index INTEGER;
    suffix_number INTEGER;
BEGIN
    first_index := (GET_BYTE(alias_hash, 0) % ARRAY_LENGTH(first_words, 1)) + 1;
    second_index := (GET_BYTE(alias_hash, 1) % ARRAY_LENGTH(second_words, 1)) + 1;
    suffix_number := (((GET_BYTE(alias_hash, 2) * 256) + GET_BYTE(alias_hash, 3)) % 90) + 10;

    RETURN first_words[first_index] || ' ' || second_words[second_index] || ' ' || suffix_number::TEXT;
END;
$$;

UPDATE public.users
SET public_author_name = public.build_default_public_alias(id)
WHERE public_identity_source = 'alias';
