SET lock_timeout='5s';
SET statement_timeout='2min';

-- Reader11 understands snapshot5 (video manifest4), as well as results1-4.
-- Only page/state reads change. Action readers and activation gates stay held.
DO $patch$
DECLARE routine TEXT; definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
 FOR routine,anchor,replacement IN SELECT * FROM (VALUES
 ('public.get_owned_observation_analysis_page(jsonb,integer)',
 'p_reader NOT IN (7,8,9,10)', 'p_reader NOT IN (7,8,9,10,11)'),
 ('public.get_owned_observation_analysis_state(jsonb,integer)',
 'p_reader NOT IN (9,10)', 'p_reader NOT IN (9,10,11)'),
 ('public.get_owned_observation_analysis_page(jsonb,integer)',
 'IF EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->''schema_version''=''4''::JSONB)',
 'IF p_reader<11 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->''schema_version''=''4''::JSONB)'),
 ('public.get_owned_observation_analysis_state(jsonb,integer)',
 'IF EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->''schema_version''=''4''::JSONB)',
 'IF p_reader<11 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->''schema_version''=''4''::JSONB)'),
 ('public.get_owned_observation_analysis_page(jsonb,integer)',
 '(p_reader=10 AND internal.is_audio_analysis_manifest(result_row.evidence_manifest))',
 '(p_reader>=10 AND internal.is_audio_analysis_manifest(result_row.evidence_manifest))
                OR (p_reader=11 AND result_row.evidence_manifest->''schema_version''=''4''::JSONB)')) patches(routine,anchor,replacement)
 LOOP
  definition:=pg_get_functiondef(routine::regprocedure);
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'video_reader_source_drift'; END IF;
  EXECUTE replace(definition,anchor,replacement);
 END LOOP;
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;
