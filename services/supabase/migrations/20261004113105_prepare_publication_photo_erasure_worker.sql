SET lock_timeout='5s';
SET statement_timeout='2min';

-- Independent activation gate: deployable source cannot begin irreversible I/O
-- before dedicated credentials and managed-cache behavior are qualified.
ALTER TABLE internal.observation_history_rollout ADD COLUMN publication_erasure_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Registry-only authorization survives account/history deletion. A targeted
-- claim is also used after failed copy completion; local errors alone never
-- authorize erasing another worker's committed publication.
CREATE FUNCTION internal.claim_publication_photo_erasure(p_object UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.publication_photo_objects;
BEGIN
    PERFORM internal.require_service_role();
    SELECT * INTO saved FROM internal.publication_photo_objects WHERE erased_at IS NULL AND available_at<=clock_timestamp()
        AND (bound_at IS NULL OR revoked_at IS NOT NULL)
        AND (p_object IS NULL OR object_id=p_object)
        AND (claim_expires_at IS NULL OR claim_expires_at<=clock_timestamp())
        ORDER BY available_at,object_id LIMIT 1 FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN RETURN NULL; END IF;
    UPDATE internal.publication_photo_objects SET claim_token=extensions.gen_random_uuid(),claim_expires_at=clock_timestamp()+INTERVAL '2 minutes'
        WHERE object_id=saved.object_id RETURNING * INTO saved;
    RETURN to_jsonb(saved);
END;
$$;
REVOKE ALL ON FUNCTION internal.claim_publication_photo_erasure(UUID) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION internal.claim_publication_photo_erasure()
RETURNS JSONB LANGUAGE SQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
    SELECT internal.claim_publication_photo_erasure(NULL::UUID);
$$;
CREATE FUNCTION public.claim_publication_photo_erasure(p_object UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF (SELECT publication_erasure_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN internal.claim_publication_photo_erasure(p_object);
END;
$$;
CREATE FUNCTION public.finish_publication_photo_erasure(p_object UUID,p_claim UUID,p_success BOOLEAN)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    RETURN internal.finish_publication_photo_erasure(p_object,p_claim,p_success);
END;
$$;
REVOKE ALL ON FUNCTION public.claim_publication_photo_erasure(UUID),public.finish_publication_photo_erasure(UUID,UUID,BOOLEAN)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_publication_photo_erasure(UUID),public.finish_publication_photo_erasure(UUID,UUID,BOOLEAN) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.claim_publication_photo_erasure(uuid)','Bounded registry-only public-photo erasure claim; excludes valid bound publications and survives private history deletion.'),
    ('service_role','public.finish_publication_photo_erasure(uuid,uuid,boolean)','Acknowledge verified permanent public-photo erasure marker using the exact unexpired claim token.');

RESET statement_timeout;
RESET lock_timeout;
