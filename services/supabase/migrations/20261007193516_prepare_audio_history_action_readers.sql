SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Call only after canonical owner/ingestion/owned-parent locks. This is a
-- compatibility fence, not authorization, a dispatch grant or a retirement proof.
-- Completed history and the exact pending input are deliberately separate facts.
CREATE FUNCTION internal.require_observation_action_reader(
    p_observation UUID, p_reader INTEGER, p_analysis UUID
) RETURNS VOID LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
BEGIN
    IF p_reader IS NULL OR p_reader NOT IN (9,10) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
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

-- Exact source checks fail migration on upstream drift. Preserve the original
-- request, receipt, ownership, revision and fresh-gate semantics in every owner.
DO $patch$
DECLARE
    routine TEXT; definition TEXT; anchor TEXT; replacement TEXT;
    old_reader TEXT := 'p_reader IS DISTINCT FROM 9';
BEGIN
    FOR routine, anchor, replacement IN
        SELECT * FROM (VALUES
            ('public.select_owned_observation_analysis(jsonb,integer)','    SELECT * INTO saved FROM internal.observation_selection_receipts','    PERFORM internal.require_observation_action_reader(observation,p_reader,NULL);
    SELECT * INTO saved FROM internal.observation_selection_receipts'),
            ('public.review_owned_observation_analysis(jsonb,integer)','    SELECT * INTO saved FROM internal.observation_review_receipts','    PERFORM internal.require_observation_action_reader(observation,p_reader,NULL);
    SELECT * INTO saved FROM internal.observation_review_receipts'),
            ('public.get_owned_observation_confirmation_undo(jsonb,integer)','    IF (SELECT confirmation_undo_api_enabled AND reader_enabled AND state_reader_enabled','    PERFORM internal.require_observation_action_reader(observation,p_reader,NULL);
    IF (SELECT confirmation_undo_api_enabled AND reader_enabled AND state_reader_enabled'),
            ('public.get_owned_observation_rejection_undo(jsonb,integer)','    IF (SELECT rejection_api_enabled AND reader_enabled AND state_reader_enabled','    PERFORM internal.require_observation_action_reader(observation,p_reader,NULL);
    IF (SELECT rejection_api_enabled AND reader_enabled AND state_reader_enabled'),
            ('internal.confirm_observation_analysis(uuid,jsonb,integer,boolean,text,jsonb)','    SELECT * INTO saved FROM internal.observation_review_receipts','    PERFORM internal.require_observation_action_reader(observation,p_reader,NULL);
    SELECT * INTO saved FROM internal.observation_review_receipts'),
            ('public.get_owned_observation_analysis_execution(jsonb,integer)','    -- Query the globally unique child, then reject scope conflicts.','    PERFORM internal.require_observation_action_reader(observation,p_reader,analysis);
    -- Query the globally unique child, then reject scope conflicts.'),
            ('public.retire_owned_observation_analysis_execution(uuid,jsonb,integer)','    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(''merian-analysis-retirement:''','    PERFORM internal.require_observation_action_reader(observation,p_reader,analysis);
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(''merian-analysis-retirement:''')
        ) AS patches(routine,anchor,replacement)
    LOOP
        definition := pg_catalog.pg_get_functiondef(routine::pg_catalog.regprocedure);
        IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,old_reader,'')))/pg_catalog.length(old_reader)<>1
            OR (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,anchor,'')))/pg_catalog.length(anchor)<>1 THEN
            RAISE EXCEPTION 'audio_action_reader_source_drift';
        END IF;
        definition := pg_catalog.replace(definition,old_reader,'(p_reader IS NULL OR p_reader NOT IN (9,10))');
        EXECUTE pg_catalog.replace(definition,anchor,replacement);
    END LOOP;
END;
$patch$;

COMMENT ON FUNCTION internal.require_observation_action_reader(UUID,INTEGER,UUID) IS
    'Private lock-preconditioned compatibility guard: reader9 denies whole completed audio history and exact input3 operations; reader10 does not grant any action or replay.';
COMMENT ON FUNCTION public.get_owned_observation_analysis_execution(JSONB,INTEGER) IS
    'Readers9/10, exact owner operation status only. Reader9 denies completed audio history or the exact input3 operation. No dispatch, retry or retirement authority.';

RESET statement_timeout;
RESET lock_timeout;
