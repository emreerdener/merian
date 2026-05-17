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
    city TEXT;
    admin_area TEXT;
    city_is_private BOOLEAN;
    admin_is_private BOOLEAN;
    admin_is_known_state BOOLEAN;
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

    IF part_count >= 2 AND LOWER(parts[part_count]) = ANY(country_names) THEN
        parts := TRIM_ARRAY(parts, 1);
        part_count := part_count - 1;
    END IF;

    admin_area := parts[part_count];
    admin_is_private := (
        admin_area ~* '[-+]?[0-9]{1,3}\.[0-9]{3,}[^0-9+-]+[-+]?[0-9]{1,3}\.[0-9]{3,}'
        OR LOWER(admin_area) = ANY(country_names)
        OR admin_area ~* '(^|[^[:alpha:]])(gps|latitude|longitude|coordinate)s?([^[:alpha:]]|$)'
    );

    IF admin_is_private THEN
        RETURN NULL;
    END IF;

    IF part_count >= 2 THEN
        city := parts[part_count - 1];
        city_is_private := (
            city ~* '^[0-9]+'
            OR city ~* '(^|[^[:alpha:]])(street|avenue|road|boulevard|drive|lane|court|terrace|highway|route|suite|unit|apartment)([^[:alpha:]]|$)'
            OR city ~* '(^|[^[:alpha:]])(st|ave|rd|blvd|dr|ln|ct|pl)\.?$'
            OR city ~* '(^|[^[:alpha:]])(gps|latitude|longitude|coordinate)s?([^[:alpha:]]|$)'
            OR city ~* '(^|[^[:alpha:]])(park|trail|preserve|garden|campus|building|museum|hotel|restaurant|cafe|creek|beach|woods|forest|campground)\.?$'
            OR city ~* '[-+]?[0-9]{1,3}\.[0-9]{3,}[^0-9+-]+[-+]?[0-9]{1,3}\.[0-9]{3,}'
        );

        IF city_is_private THEN
            admin_is_known_state := UPPER(admin_area) = ANY(state_codes)
                OR LOWER(admin_area) = ANY(state_names);
            RETURN CASE WHEN admin_is_known_state THEN admin_area ELSE NULL END;
        END IF;

        RETURN CONCAT_WS(', ', NULLIF(city, ''), NULLIF(admin_area, ''));
    END IF;

    admin_is_known_state := UPPER(admin_area) = ANY(state_codes)
        OR LOWER(admin_area) = ANY(state_names);

    RETURN CASE WHEN admin_is_known_state THEN admin_area ELSE NULL END;
END;
$$;
