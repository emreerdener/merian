SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Account deletion removes the person and all account-owned content, but a
-- submitted scan is also a scientific observation. Exact coordinates,
-- elevation, time, taxonomy, identification, quality, environmental, and
-- provenance facts remain on the ownerless tombstone. Public scan policies
-- continue to exclude every tombstoned row.
CREATE OR REPLACE FUNCTION public.apply_user_tombstone(target_user_id UUID)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF target_user_id IS NULL
       OR target_user_id =
            '00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'account_deletion_invalid_user'
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.scans AS scans
    SET user_id = NULL,
        is_tombstoned = TRUE,
        image_storage_urls = ARRAY[]::TEXT[],
        video_storage_urls = ARRAY[]::TEXT[],
        audio_storage_urls = ARRAY[]::TEXT[],
        captured_media = NULL,
        semantic_location = NULL,
        public_location_label = NULL,
        device_locale = NULL,
        device_time_zone = NULL,
        user_observation_context = NULL,
        custom_tags = ARRAY[]::TEXT[],
        human_intervention_notes = NULL
    WHERE scans.user_id = target_user_id;

    DELETE FROM public.users AS users
    WHERE users.id = target_user_id;
END;
$$;

COMMENT ON FUNCTION public.apply_user_tombstone(UUID) IS
    'Service-only account detachment. It removes account linkage, media, free-form notes, and device/semantic-location context while retaining the ownerless scientific observation, including exact coordinates and elevation.';

REVOKE ALL ON FUNCTION public.apply_user_tombstone(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.apply_user_tombstone(UUID)
    TO service_role;

-- A scan can already have a permanent individual-deletion generation fence
-- when durable account deletion claims it. Permit that one transition only.
-- Comparing complete rows after removing the fields that account deletion is
-- allowed to change makes the fence fail closed for every current and future
-- scientific field instead of maintaining an error-prone coordinate allowlist.
CREATE OR REPLACE FUNCTION internal.reject_deleted_scan_generation_mutation()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    account_detachment_columns CONSTANT TEXT[] := ARRAY[
        'user_id',
        'is_tombstoned',
        'image_storage_urls',
        'video_storage_urls',
        'audio_storage_urls',
        'captured_media',
        'semantic_location',
        'public_location_label',
        'device_locale',
        'device_time_zone',
        'user_observation_context',
        'custom_tags',
        'human_intervention_notes'
    ]::TEXT[];
BEGIN
    IF EXISTS (
        SELECT 1
        FROM internal.scan_deletion_tombstones AS tombstones
        WHERE tombstones.scan_id = NEW.id
    ) THEN
        -- Durable account deletion supersedes an incomplete individual
        -- deletion. Ordinary delayed scan writes, retries against an already
        -- detached row, and changes to retained scientific facts are rejected.
        IF TG_OP = 'UPDATE' THEN
            IF NEW.id IS NOT DISTINCT FROM OLD.id
               AND OLD.user_id IS NOT NULL
               AND NEW.user_id IS NULL
               AND NEW.is_tombstoned IS TRUE
               AND pg_catalog.CARDINALITY(
                    COALESCE(NEW.image_storage_urls, '{}'::TEXT[])
               ) = 0
               AND pg_catalog.CARDINALITY(
                    COALESCE(NEW.video_storage_urls, '{}'::TEXT[])
               ) = 0
               AND pg_catalog.CARDINALITY(
                    COALESCE(NEW.audio_storage_urls, '{}'::TEXT[])
               ) = 0
               AND NEW.captured_media IS NULL
               AND NEW.semantic_location IS NULL
               AND NEW.public_location_label IS NULL
               AND NEW.device_locale IS NULL
               AND NEW.device_time_zone IS NULL
               AND NEW.user_observation_context IS NULL
               AND pg_catalog.CARDINALITY(
                    COALESCE(NEW.custom_tags, '{}'::TEXT[])
               ) = 0
               AND NEW.human_intervention_notes IS NULL
               AND (
                    pg_catalog.TO_JSONB(NEW) - account_detachment_columns
               ) IS NOT DISTINCT FROM (
                    pg_catalog.TO_JSONB(OLD) - account_detachment_columns
               ) THEN
                RETURN NEW;
            END IF;
        END IF;

        RAISE EXCEPTION 'scan_generation_deleted'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION internal.reject_deleted_scan_generation_mutation() IS
    'Rejects writes to permanently deleted scan generations, except the single fail-closed account-detachment transition that leaves all scientific fields unchanged.';

REVOKE ALL ON FUNCTION internal.reject_deleted_scan_generation_mutation()
    FROM PUBLIC, anon, authenticated, service_role;

RESET statement_timeout;
RESET lock_timeout;

NOTIFY pgrst, 'reload schema';
