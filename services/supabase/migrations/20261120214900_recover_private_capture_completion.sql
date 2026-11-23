SET lock_timeout='5s';
SET statement_timeout='2min';

-- Read-only completed recovery does not reopen admission or staging. Its full
-- client graph must match the sealed V9 manifest, including source/prepared IDs,
-- order, field notes and selection. It survives transient job/intent cleanup.
CREATE FUNCTION public.recover_private_capture_completion(p_owner UUID,p_plan JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE contract JSONB; scan UUID; generation UUID; saved internal.ordinary_initial_evidence;
 items JSONB; response JSONB;
BEGIN
 PERFORM internal.require_service_role();
 contract:=internal.initial_capture_plan_contract(p_owner,p_plan);
 scan:=(contract->>'scan_id')::UUID; generation:=(contract->>'generation')::UUID;
 PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_owner) THEN
  RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||scan::TEXT,0));
 SELECT * INTO saved FROM internal.ordinary_initial_evidence WHERE scan_id=scan FOR UPDATE;
 IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=scan)
  OR EXISTS(SELECT 1 FROM public.scans WHERE id=scan AND (user_id<>p_owner OR is_tombstoned))
  OR (saved.scan_id IS NOT NULL AND (saved.owner_id<>p_owner OR saved.retired_at IS NOT NULL)) THEN
  RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
 IF saved.scan_id IS NULL OR saved.sealed_at IS NULL THEN RETURN NULL; END IF;
 IF saved.generation IS DISTINCT FROM generation OR saved.evidence_manifest->'schema_version' IS DISTINCT FROM '9'::JSONB THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 SELECT jsonb_agg(CASE x->>'kind'
  WHEN 'audio' THEN jsonb_build_object('kind','audio','source',x->'source','prepared_media_id',x#>'{prepared,media_id}')
  WHEN 'video' THEN (x-'audio')||jsonb_build_object('audio',CASE WHEN x->'audio'='null'::JSONB THEN 'null'::JSONB
    ELSE jsonb_build_object('source',x#>'{audio,source}','prepared_media_id',x#>'{audio,prepared,media_id}') END)
  ELSE x END ORDER BY n) INTO items
  FROM jsonb_array_elements(saved.evidence_manifest->'items') WITH ORDINALITY AS nodes(x,n);
 IF items IS DISTINCT FROM p_plan->'items' THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 response:=public.recover_owned_initial_completion(p_owner,scan);
 IF response#>>'{initial_evidence,evidence_digest}' IS DISTINCT FROM saved.evidence_digest THEN
  RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
 RETURN response;
END;
$$;
REVOKE ALL ON FUNCTION public.recover_private_capture_completion(UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.recover_private_capture_completion(UUID,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.recover_private_capture_completion(uuid,jsonb)','Recover an exact owner sealed V9 completion only after comparing the complete client capture plan; no admission, provider or media authority.');
RESET statement_timeout;
RESET lock_timeout;
