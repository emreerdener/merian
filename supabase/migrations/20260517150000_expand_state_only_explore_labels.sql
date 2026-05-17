CREATE OR REPLACE FUNCTION public.sanitize_explore_location(raw_location TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    cleaned TEXT := BTRIM(REGEXP_REPLACE(COALESCE(raw_location, ''), '\s+', ' ', 'g'));
    raw_parts TEXT[];
    parts TEXT[] := ARRAY[]::TEXT[];
    part TEXT;
    part_count INTEGER;
    admin_area TEXT;
    city_is_private BOOLEAN;
    admin_is_private BOOLEAN;
    state_index INTEGER;
    city_index INTEGER;
    candidate_city TEXT;
    candidate_state_code TEXT;
    candidate_state_name TEXT;
    candidate_admin_area TEXT;
    state_without_zip TEXT;
    state_position INTEGER;
    private_part_pattern TEXT := '(^[0-9]+)|(^|[^[:alpha:]])(street|avenue|road|boulevard|drive|lane|court|terrace|highway|route|suite|unit|apartment)([^[:alpha:]]|$)|(^|[^[:alpha:]])(st|ave|rd|blvd|dr|ln|ct|pl)\.?$|(^|[^[:alpha:]])(gps|latitude|longitude|coordinate)s?([^[:alpha:]]|$)|(^|[^[:alpha:]])(park|trail|preserve|garden|campus|building|museum|hotel|restaurant|cafe|creek|beach|woods|forest|campground|bay|harbor|harbour|marina|island|lake|pond|river|canal|inlet|lagoon|wetland|swamp|sound|cove|estuary)\.?$|[-+]?[0-9]{1,3}\.[0-9]{3,}[^0-9+-]+[-+]?[0-9]{1,3}\.[0-9]{3,}';
    admin_part_pattern TEXT := '(^|[^[:alpha:]])(county|parish|borough|district|municipality|prefecture)([^[:alpha:]]|$)|(^|[^[:alpha:]])(province|region)\.?$';
    state_codes TEXT[] := ARRAY[
        'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'DC', 'FL',
        'GA', 'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME',
        'MD', 'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH',
        'NJ', 'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI',
        'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI',
        'WY'
    ];
    state_names TEXT[] := ARRAY[
        'alabama', 'alaska', 'arizona', 'arkansas', 'california', 'colorado',
        'connecticut', 'delaware', 'district of columbia', 'florida', 'georgia',
        'hawaii', 'idaho', 'illinois', 'indiana', 'iowa', 'kansas', 'kentucky',
        'louisiana', 'maine', 'maryland', 'massachusetts', 'michigan',
        'minnesota', 'mississippi', 'missouri', 'montana', 'nebraska', 'nevada',
        'new hampshire', 'new jersey', 'new mexico', 'new york',
        'north carolina', 'north dakota', 'ohio', 'oklahoma', 'oregon',
        'pennsylvania', 'rhode island', 'south carolina', 'south dakota',
        'tennessee', 'texas', 'utah', 'vermont', 'virginia', 'washington',
        'west virginia', 'wisconsin', 'wyoming'
    ];
    state_display_names TEXT[] := ARRAY[
        'Alabama', 'Alaska', 'Arizona', 'Arkansas', 'California', 'Colorado',
        'Connecticut', 'Delaware', 'District of Columbia', 'Florida', 'Georgia',
        'Hawaii', 'Idaho', 'Illinois', 'Indiana', 'Iowa', 'Kansas', 'Kentucky',
        'Louisiana', 'Maine', 'Maryland', 'Massachusetts', 'Michigan',
        'Minnesota', 'Mississippi', 'Missouri', 'Montana', 'Nebraska', 'Nevada',
        'New Hampshire', 'New Jersey', 'New Mexico', 'New York',
        'North Carolina', 'North Dakota', 'Ohio', 'Oklahoma', 'Oregon',
        'Pennsylvania', 'Rhode Island', 'South Carolina', 'South Dakota',
        'Tennessee', 'Texas', 'Utah', 'Vermont', 'Virginia', 'Washington',
        'West Virginia', 'Wisconsin', 'Wyoming'
    ];
    country_names TEXT[] := ARRAY[
        'united states', 'united states of america', 'usa', 'us', 'canada'
    ];
BEGIN
    IF cleaned = '' THEN
        RETURN NULL;
    END IF;

    IF cleaned ~* '[-+]?[0-9]{1,3}\.[0-9]{3,}[^0-9+-]+[-+]?[0-9]{1,3}\.[0-9]{3,}' THEN
        RETURN NULL;
    END IF;

    raw_parts := REGEXP_SPLIT_TO_ARRAY(cleaned, '\s*,\s*');

    FOREACH part IN ARRAY raw_parts LOOP
        part := BTRIM(part);
        IF part <> '' THEN
            parts := ARRAY_APPEND(parts, part);
        END IF;
    END LOOP;

    part_count := COALESCE(ARRAY_LENGTH(parts, 1), 0);

    IF part_count = 0 THEN
        RETURN NULL;
    END IF;

    IF part_count = 2
       AND parts[1] ~ '^\s*[-+]?[0-9]+(\.[0-9]+)?\s*$'
       AND parts[2] ~ '^\s*[-+]?[0-9]+(\.[0-9]+)?\s*$' THEN
        RETURN NULL;
    END IF;

    parts := ARRAY(
        SELECT retained_part
        FROM UNNEST(parts) AS retained_parts(retained_part)
        WHERE LOWER(retained_part) <> ALL(country_names)
    );
    part_count := COALESCE(ARRAY_LENGTH(parts, 1), 0);

    IF part_count = 0 THEN
        RETURN NULL;
    END IF;

    state_index := part_count;
    WHILE state_index >= 1 LOOP
        admin_area := parts[state_index];
        candidate_admin_area := BTRIM(REGEXP_REPLACE(admin_area, '\s+(united states of america|united states|usa|us|canada)$', '', 'i'));
        state_without_zip := BTRIM(REGEXP_REPLACE(candidate_admin_area, '\s+[0-9]{5}(-[0-9]{4})?$', ''));
        candidate_state_code := NULL;
        candidate_state_name := NULL;

        state_position := ARRAY_POSITION(state_codes, UPPER(state_without_zip));
        IF state_position IS NOT NULL THEN
            candidate_state_code := state_codes[state_position];
            candidate_state_name := state_display_names[state_position];
        ELSE
            state_position := ARRAY_POSITION(state_names, LOWER(state_without_zip));
            IF state_position IS NOT NULL THEN
                candidate_state_code := state_codes[state_position];
                candidate_state_name := state_display_names[state_position];
            END IF;
        END IF;

        IF candidate_state_code IS NOT NULL THEN
            city_index := state_index - 1;
            WHILE city_index >= 1 LOOP
                candidate_city := parts[city_index];
                city_is_private := (
                    candidate_city ~* private_part_pattern
                    OR candidate_city ~* admin_part_pattern
                );

                IF city_is_private = FALSE THEN
                    RETURN CONCAT_WS(', ', NULLIF(candidate_city, ''), NULLIF(candidate_state_code, ''));
                END IF;

                city_index := city_index - 1;
            END LOOP;

            RETURN candidate_state_name;
        END IF;

        state_index := state_index - 1;
    END LOOP;

    admin_area := parts[part_count];
    admin_is_private := (
        LOWER(admin_area) = ANY(country_names)
        OR admin_area ~* private_part_pattern
    );

    IF admin_is_private THEN
        RETURN NULL;
    END IF;

    IF part_count >= 2 THEN
        city_index := part_count - 1;
        WHILE city_index >= 1 LOOP
            candidate_city := parts[city_index];
            city_is_private := (
                candidate_city ~* private_part_pattern
                OR candidate_city ~* admin_part_pattern
            );

            IF city_is_private = FALSE THEN
                RETURN CONCAT_WS(', ', NULLIF(candidate_city, ''), NULLIF(admin_area, ''));
            END IF;

            city_index := city_index - 1;
        END LOOP;

        RETURN NULL;
    END IF;

    RETURN admin_area;
END;
$$;

UPDATE public.scans
SET public_location_label = public.resolve_explore_location_label(
    public_location_label,
    semantic_location
)
WHERE public_location_label IS DISTINCT FROM public.resolve_explore_location_label(
    public_location_label,
    semantic_location
);
