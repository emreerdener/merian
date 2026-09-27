-- Freeze metric interpretation at job creation; existing immutable exports remain unchanged.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE OR REPLACE VIEW internal.dwca_export_snapshot_source
WITH (security_invoker = TRUE)
AS
SELECT
    scans.id AS scan_id,
    scans.user_id,
    scans.is_live_capture,
    scans.is_tombstoned,
    scans.ecology_type,
    scans.geoprivacy,
    COALESCE(scans.confirmed_species_id, scans.species_id)
        AS effective_species_id,
    species.iucn_red_list_status,
    COALESCE(
        species.iucn_red_list_status IN (
            'vulnerable',
            'endangered',
            'critically_endangered',
            'near_threatened'
        ),
        FALSE
    ) AS coordinate_protection_required,
    pg_catalog.JSONB_BUILD_OBJECT(
        'user_id', scans.user_id,
        'is_live_capture', scans.is_live_capture,
        'is_tombstoned', scans.is_tombstoned,
        'ecology_type', scans.ecology_type,
        'geoprivacy', NULL,
        'coordinate_protection_required',
            COALESCE(
                species.iucn_red_list_status IN (
                    'vulnerable',
                    'endangered',
                    'critically_endangered',
                    'near_threatened'
                ),
                FALSE
            )
    ) AS personal_eligibility_payload,
    pg_catalog.JSONB_BUILD_OBJECT(
        'user_id', scans.user_id,
        'is_live_capture', scans.is_live_capture,
        'is_tombstoned', scans.is_tombstoned,
        'ecology_type', scans.ecology_type,
        'geoprivacy', scans.geoprivacy,
        'coordinate_protection_required',
            COALESCE(
                species.iucn_red_list_status IN (
                    'vulnerable',
                    'endangered',
                    'critically_endangered',
                    'near_threatened'
                ),
                FALSE
            )
    ) AS global_eligibility_payload,
    pg_catalog.JSONB_BUILD_OBJECT(
        'id', scans.id,
        'user_id', scans.user_id,
        'effective_species_id',
            COALESCE(scans.confirmed_species_id, scans.species_id),
        'timestamp', scans.timestamp,
        'gps_lat_exact', scans.gps_lat_exact,
        'gps_long_exact', scans.gps_long_exact,
        'gps_lat_public', scans.gps_lat_public,
        'gps_long_public', scans.gps_long_public,
        'coordinate_uncertainty_in_meters',
            scans.coordinate_uncertainty_in_meters,
        'life_stage', scans.life_stage,
        'reproductive_condition', scans.reproductive_condition,
        'sex', scans.sex,
        'individual_count', scans.individual_count,
        'ecological_interactions',
            COALESCE(scans.ecological_interactions, ARRAY[]::TEXT[]),
        'ai_confidence_score', scans.ai_confidence_score,
        'ai_confidence_qualified', internal.identification_metrics_are_gemini_compatible(
            scans.identification_provenance, scans.inference_tier),
        'species_dictionary', CASE
            WHEN species.id IS NULL THEN NULL
            ELSE pg_catalog.JSONB_BUILD_OBJECT(
                'scientific_name', species.scientific_name,
                'kingdom', species.kingdom,
                'phylum', species.phylum,
                'class', species.class,
                'order', species."order",
                'family', species.family,
                'genus', species.genus,
                'iucn_red_list_status', species.iucn_red_list_status
            )
        END
    ) AS occurrence_payload,
    pg_catalog.JSONB_BUILD_OBJECT(
        'id', scans.id,
        'user_id', scans.user_id,
        'image_storage_urls', scans.image_storage_urls
    ) AS multimedia_payload
FROM public.scans AS scans
LEFT JOIN public.species_dictionary AS species
    ON species.id = COALESCE(
        scans.confirmed_species_id,
        scans.species_id
    );

REVOKE ALL ON TABLE internal.dwca_export_snapshot_source
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON VIEW internal.dwca_export_snapshot_source IS
    'Private one-statement source projection used to materialize immutable authoritative DwC-A DTO rows and scope-aware privacy eligibility hashes.';


NOTIFY pgrst, 'reload schema';
RESET lock_timeout;
RESET statement_timeout;
