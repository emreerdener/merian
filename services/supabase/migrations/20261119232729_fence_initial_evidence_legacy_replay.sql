SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Initial evidence is a separate recovery authority. Legacy replay must neither
-- redispatch its provider nor exhaust/settle its held funding. Exclude even an
-- allocated-but-unbound request: a missing/uncertain accepted-result read is not
-- permission for this worker to run inference. Dedicated continuation recovery
-- remains gated until its immutable projection and cleanup fences are wired.
DO $$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    SELECT pg_catalog.pg_get_functiondef(
        'public.claim_replayable_scan_ingestion_jobs(integer,integer)'::REGPROCEDURE
    ) INTO STRICT definition;
    anchor := '        WHERE jobs.endpoint = ''identify-multimodal''';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor) <> 2 THEN
        RAISE EXCEPTION 'Reviewed legacy replay and exhaustion candidates changed';
    END IF;
    EXECUTE replace(definition,anchor,anchor||$guard$
          AND NOT (intents.request_payload ? 'initialEvidence')
          AND NOT EXISTS (
              SELECT 1 FROM internal.ordinary_initial_evidence initial_evidence
              WHERE initial_evidence.scan_id = internal.source_child_uuid(jobs.scan_id)
          )
$guard$);
END;
$$;

RESET statement_timeout;
RESET lock_timeout;
