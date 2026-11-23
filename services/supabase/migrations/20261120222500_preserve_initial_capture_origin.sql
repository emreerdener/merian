SET lock_timeout='5s';
SET statement_timeout='2min';

-- V9 specifies evidence geometry, not its ingestion route. Keep the private
-- stage origin on the retained row so transient intent/witness deletion cannot
-- downgrade it, without reclassifying pre-existing direct V9 photo evidence.
ALTER TABLE internal.ordinary_initial_evidence
 ADD COLUMN private_capture_request_sha256 TEXT
 CHECK(private_capture_request_sha256 ~ '^[0-9a-f]{64}$');

ALTER TABLE internal.ordinary_initial_evidence DISABLE TRIGGER guard_ordinary_initial_evidence;
UPDATE internal.ordinary_initial_evidence evidence
 SET private_capture_request_sha256=stage.request_sha256
 FROM internal.initial_capture_audio_stages stage
 WHERE stage.scan_id=evidence.scan_id AND stage.owner_id=evidence.owner_id
 AND stage.generation=evidence.generation
 AND evidence.evidence_manifest->'schema_version'='9'::JSONB
 AND (stage.adopted_evidence_digest IS NULL OR stage.adopted_evidence_digest=evidence.evidence_digest);
ALTER TABLE internal.ordinary_initial_evidence ENABLE TRIGGER guard_ordinary_initial_evidence;

CREATE FUNCTION internal.bind_initial_capture_origin()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE request_hash TEXT;
BEGIN
 -- The reserve owner has already locked and validated this stage before insert.
 SELECT request_sha256 INTO request_hash FROM internal.initial_capture_audio_stages
 WHERE scan_id=NEW.scan_id AND owner_id=NEW.owner_id AND generation=NEW.generation
 AND NEW.evidence_manifest->'schema_version'='9'::JSONB;
 IF NEW.private_capture_request_sha256 IS NOT NULL AND NEW.private_capture_request_sha256 IS DISTINCT FROM request_hash THEN
    RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='55000';
 END IF;
 NEW.private_capture_request_sha256:=request_hash;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.bind_initial_capture_origin() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER bind_initial_capture_origin BEFORE INSERT
 ON internal.ordinary_initial_evidence FOR EACH ROW EXECUTE FUNCTION internal.bind_initial_capture_origin();

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('public.complete_scan_ingestion_finalization(uuid,uuid,jsonb,text[])'::regprocedure);
 anchor:='AND evidence_manifest->''schema_version''=''9''::JSONB) THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_origin_discriminator_drift'; END IF;
 EXECUTE replace(definition,anchor,'AND private_capture_request_sha256 IS NOT NULL) THEN');
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;
