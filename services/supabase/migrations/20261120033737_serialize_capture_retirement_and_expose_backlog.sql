SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Serialize account intake with capability issuance before either side can
-- publish durable state. INSERT ON CONFLICT also runs this BEFORE trigger.
CREATE FUNCTION internal.lock_capture_owner_before_account_retirement() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM id FROM public.users WHERE id = NEW.user_id FOR UPDATE;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.lock_capture_owner_before_account_retirement() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER lock_capture_owner_before_account_retirement BEFORE INSERT ON internal.account_deletion_jobs
    FOR EACH ROW EXECUTE FUNCTION internal.lock_capture_owner_before_account_retirement();

CREATE FUNCTION public.capture_object_retirement_health() RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
DECLARE result JSONB;
BEGIN
    PERFORM internal.require_service_role();
    SELECT jsonb_build_object(
        'unresolved_count',count(*),
        'due_count',count(*) FILTER (WHERE next_check_at <= clock_timestamp() AND (claim_token IS NULL OR lease_expires_at <= clock_timestamp())),
        'leased_count',count(*) FILTER (WHERE lease_expires_at > clock_timestamp()),
        'error_count',count(*) FILTER (WHERE last_error_code IS NOT NULL),
        'oldest_retired_age_seconds',COALESCE(floor(extract(epoch FROM clock_timestamp()-min(retired_at)))::BIGINT,0))
    INTO result FROM internal.capture_object_authorities WHERE retired_at IS NOT NULL;
    RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.capture_object_retirement_health() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.capture_object_retirement_health() TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.capture_object_retirement_health()','Aggregate unresolved exact-key retirement backlog without exposing owner or object identities.');

RESET statement_timeout;
RESET lock_timeout;
