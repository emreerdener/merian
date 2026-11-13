SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Compatibility only, after the existing owner/observation/deletion locks.
-- Reader11 understands completed V5 selection/review authority. It grants no
-- input reuse, execution status, retirement, publication or chat capability.
CREATE OR REPLACE FUNCTION internal.require_observation_action_reader(
    p_observation UUID, p_reader INTEGER, p_analysis UUID
) RETURNS VOID LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
BEGIN
    IF p_reader IS NULL OR p_reader NOT IN (9,10,11)
        OR (p_reader=11 AND p_analysis IS NOT NULL) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF (p_reader<>11 AND EXISTS(
        SELECT 1 FROM internal.observation_analysis_results
        WHERE observation_id=p_observation AND evidence_manifest->'schema_version'='4'::JSONB))
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents
            WHERE observation_id=p_observation AND analysis_id=p_analysis
                AND input_snapshot->'schema_version'='4'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000';
    END IF;
    IF p_reader=9 AND (
        EXISTS(SELECT 1 FROM internal.observation_analysis_results
            WHERE observation_id=p_observation
                AND internal.is_audio_analysis_manifest(evidence_manifest))
        OR (p_analysis IS NOT NULL AND EXISTS(
            SELECT 1 FROM internal.observation_analysis_intents
            WHERE observation_id=p_observation AND analysis_id=p_analysis
                AND input_snapshot->'schema_version'='3'::JSONB))
    ) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.require_observation_action_reader(UUID,INTEGER,UUID)
    FROM PUBLIC,anon,authenticated,service_role;

-- Extend only existing selection/review/Undo entry points, preserving their
-- request validation, lock order, gates, receipts, CAS and replay semantics.
-- Execution/retirement wrappers deliberately retain readers9/10.
DO $patch$
DECLARE
    routine TEXT; definition TEXT;
    anchor TEXT := '(p_reader IS NULL OR p_reader NOT IN (9,10))';
BEGIN
    FOREACH routine IN ARRAY ARRAY[
        'public.select_owned_observation_analysis(jsonb,integer)',
        'public.review_owned_observation_analysis(jsonb,integer)',
        'public.get_owned_observation_confirmation_undo(jsonb,integer)',
        'public.get_owned_observation_rejection_undo(jsonb,integer)',
        'internal.confirm_observation_analysis(uuid,jsonb,integer,boolean,text,jsonb)'
    ] LOOP
        definition := pg_catalog.pg_get_functiondef(routine::pg_catalog.regprocedure);
        IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,anchor,'')))/pg_catalog.length(anchor)<>1 THEN
            RAISE EXCEPTION 'video_action_reader_source_drift';
        END IF;
        EXECUTE pg_catalog.replace(definition,anchor,'(p_reader IS NULL OR p_reader NOT IN (9,10,11))');
    END LOOP;
END;
$patch$;

COMMENT ON FUNCTION internal.require_observation_action_reader(UUID,INTEGER,UUID) IS
    'Private lock-preconditioned compatibility guard: reader11 permits completed V5 selection/review/Undo only (NULL operation scope); old readers still refuse whole video history. No action, execution, retirement or replay grant.';

RESET statement_timeout;
RESET lock_timeout;
