-- Prepared service-only reads for the existing immutable original owner.
-- No admission, dispatch, settlement, legacy repair or client grant is added.
SET statement_timeout = '10s';
SET lock_timeout = '2s';

CREATE FUNCTION public.discover_initial_completion_v1(
 p_owner UUID, p_scan UUID, p_admission TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' SET statement_timeout = '5s' AS $body$
BEGIN
 PERFORM internal.require_service_role();
 RETURN internal.discover_initial_completion_v1(p_owner, p_scan, p_admission);
END;
$body$;

CREATE FUNCTION public.read_initial_cpm_saved_admission_v1(
 p_owner UUID, p_scan UUID, p_candidate TEXT, p_candidate_digest TEXT,
 p_content_digest TEXT, p_assignment_digest TEXT, p_backend_generation UUID,
 p_backend_configuration_digest TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' SET statement_timeout = '5s' AS $body$
BEGIN
 PERFORM internal.require_service_role();
 RETURN internal.read_initial_cpm_saved_admission_v1(
  p_owner, p_scan, p_candidate, p_candidate_digest, p_content_digest,
  p_assignment_digest, p_backend_generation, p_backend_configuration_digest);
END;
$body$;

ALTER FUNCTION public.discover_initial_completion_v1(UUID,UUID,TEXT) OWNER TO postgres;
ALTER FUNCTION public.read_initial_cpm_saved_admission_v1(UUID,UUID,TEXT,TEXT,TEXT,TEXT,UUID,TEXT) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.discover_initial_completion_v1(UUID,UUID,TEXT),
 public.read_initial_cpm_saved_admission_v1(UUID,UUID,TEXT,TEXT,TEXT,TEXT,UUID,TEXT)
 FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.discover_initial_completion_v1(UUID,UUID,TEXT),
 public.read_initial_cpm_saved_admission_v1(UUID,UUID,TEXT,TEXT,TEXT,TEXT,UUID,TEXT)
 TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.discover_initial_completion_v1(uuid,uuid,text)',
  'Prepared exact original completion read; delegates immutable admission, original dispatch, deletion and accounting locks; no execution authority'),
 ('service_role','public.read_initial_cpm_saved_admission_v1(uuid,uuid,text,text,text,text,uuid,text)',
  'Prepared saved CPM acknowledgement read; private assignment remains service-only; no admission, execution or repair authority');

RESET lock_timeout;
RESET statement_timeout;
