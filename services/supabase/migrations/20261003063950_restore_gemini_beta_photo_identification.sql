-- Product decision based on owner-reported beta quality; no benchmark superiority claim.
-- Restore the existing Gemini tier policy for new still-photo assignments only.
-- Saved attempts, completed results, consent receipts and quota policies stay immutable.
SET lock_timeout = '10s';
SET statement_timeout = '30s';

DO $migration$
DECLARE photo_count INTEGER; updated_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO photo_count
    FROM internal.identification_provider_bindings
    WHERE operation = 'scan_identification'
      AND input_profile = 'multimodal_photo_v1';
    IF photo_count = 0 OR EXISTS (
        SELECT 1 FROM internal.identification_provider_bindings
        WHERE operation = 'scan_identification'
          AND input_profile = 'multimodal_photo_v1'
          AND (provider <> 'openai' OR binding <> 'openai_photo_v1'
            OR processor_permission <> 'openai'
            OR provider_model IS DISTINCT FROM 'gpt-6-sol'
            OR minimum_identification_protocol <> 4)
    ) THEN
        RAISE EXCEPTION 'Gemini photo return source assignment drift';
    END IF;

    UPDATE internal.identification_provider_bindings
    SET provider = 'gemini',
        binding = 'gemini_baseline_v1',
        processor_permission = 'google_gemini',
        provider_model = NULL,
        minimum_identification_protocol = 0
    WHERE operation = 'scan_identification'
      AND input_profile = 'multimodal_photo_v1'
      AND provider = 'openai' AND binding = 'openai_photo_v1'
      AND processor_permission = 'openai' AND provider_model = 'gpt-6-sol'
      AND minimum_identification_protocol = 4;
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    IF updated_count <> photo_count THEN
        RAISE EXCEPTION 'Gemini photo return assignment count drift';
    END IF;
END;
$migration$;

COMMENT ON COLUMN internal.identification_provider_bindings.provider_model IS
    'Reviewed execution model per complete-input profile. Current Gemini assignments use NULL and the unchanged quota-selected model: Pro for Pro/complimentary scans, Flash for free fallback. Existing attempts retain their immutable provider snapshot.';

RESET lock_timeout;
RESET statement_timeout;
