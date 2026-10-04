SET lock_timeout='5s';
SET statement_timeout='2min';

-- Private preparation only. Staging TTL remains immutable; binding is a
-- separate lifetime transition, never an extension of an unbound upload.
ALTER TABLE internal.observation_history_rollout ADD COLUMN publication_binding_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE internal.publication_photo_objects ADD COLUMN bound_at TIMESTAMPTZ, ADD COLUMN revoked_at TIMESTAMPTZ;
-- Published objects can outlive the staging deadline indefinitely. Keep them
-- out of the worker's due index rather than rescanning the whole public corpus.
DROP INDEX internal.publication_photo_objects_pending;
CREATE INDEX publication_photo_objects_pending ON internal.publication_photo_objects(available_at,object_id)
    WHERE erased_at IS NULL AND (bound_at IS NULL OR revoked_at IS NOT NULL);
CREATE TABLE internal.publication_photo_bindings (
    object_id UUID PRIMARY KEY REFERENCES internal.publication_photo_objects(object_id),
    post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    order_index INTEGER NOT NULL CHECK(order_index BETWEEN 0 AND 5),
    UNIQUE(post_id,order_index)
);
ALTER TABLE internal.publication_photo_bindings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.publication_photo_bindings FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER reject_publication_photo_binding_update BEFORE UPDATE ON internal.publication_photo_bindings
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

-- Immutable receipt records the entire ordered cohort even after post removal.
CREATE TABLE internal.observation_photo_publications (
    operation_id UUID PRIMARY KEY REFERENCES internal.observation_publication_intents(operation_id) ON DELETE CASCADE,
    object_ids UUID[] NOT NULL CHECK(cardinality(object_ids) BETWEEN 1 AND 6),
    receipt JSONB NOT NULL CHECK(pg_catalog.octet_length(receipt::TEXT)<=4096)
);
ALTER TABLE internal.observation_photo_publications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_photo_publications FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER reject_observation_photo_publication_update BEFORE UPDATE ON internal.observation_photo_publications
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

CREATE OR REPLACE FUNCTION internal.guard_publication_photo_object() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF TG_OP='DELETE' OR NEW.object_id IS DISTINCT FROM OLD.object_id
        OR NEW.available_at>OLD.available_at OR OLD.erased_at IS NOT NULL
        OR (OLD.bound_at IS NOT NULL AND NEW.bound_at IS DISTINCT FROM OLD.bound_at)
        OR (OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at) THEN
        RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE='22023';
    END IF;
    IF OLD.bound_at IS NULL AND NEW.bound_at IS NOT NULL AND
        (OLD.available_at<=clock_timestamp() OR OLD.claim_token IS NOT NULL OR OLD.revoked_at IS NOT NULL
        OR NOT EXISTS(SELECT 1 FROM internal.publication_photo_bindings WHERE object_id=OLD.object_id)) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION internal.enqueue_publication_photo_erasure() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    UPDATE internal.publication_photo_objects SET available_at=LEAST(available_at,clock_timestamp()),
        revoked_at=COALESCE(revoked_at,clock_timestamp()) WHERE object_id=OLD.object_id AND erased_at IS NULL;
    RETURN OLD;
END;
$$;
CREATE TRIGGER enqueue_bound_publication_photo_erasure BEFORE DELETE ON internal.publication_photo_bindings
FOR EACH ROW EXECUTE FUNCTION internal.enqueue_publication_photo_erasure();

-- Post -> registry only, never post -> owner/history. Identification withdrawal,
-- private selection, hidden location and reversible health quarantine do not
-- revoke the public photo cohort.
CREATE FUNCTION internal.revoke_removed_publication_photos() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE object UUID; revoked BOOLEAN;
BEGIN
    IF NOT EXISTS(SELECT 1 FROM internal.publication_photo_bindings WHERE post_id=OLD.id) THEN RETURN NEW; END IF;
    SELECT EXISTS(SELECT 1 FROM internal.publication_photo_bindings b JOIN internal.publication_photo_objects r USING(object_id)
        WHERE b.post_id=OLD.id AND r.revoked_at IS NOT NULL) INTO revoked;
    IF revoked THEN
        -- Existing readers already honor these removal flags. Clearing both
        -- would republish erased URLs; only a new approved cohort may return.
        IF NEW.unshared_at IS NULL AND NEW.moderated_at IS NULL THEN
            IF OLD.unshared_at IS NOT NULL OR OLD.moderated_at IS NOT NULL THEN
                RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
            END IF;
            -- A private-history cascade can revoke before the account tombstone
            -- refreshes this post. Hide it without blocking deletion itself.
            NEW.unshared_at:=clock_timestamp();
        END IF;
    END IF;
    IF NEW.unshared_at IS NOT NULL OR NEW.moderated_at IS NOT NULL THEN
        FOR object IN SELECT object_id FROM internal.publication_photo_bindings WHERE post_id=OLD.id ORDER BY object_id LOOP
            UPDATE internal.publication_photo_objects SET available_at=LEAST(available_at,clock_timestamp()),
                revoked_at=COALESCE(revoked_at,clock_timestamp()) WHERE object_id=object AND erased_at IS NULL;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.revoke_removed_publication_photos() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER revoke_removed_publication_photos BEFORE UPDATE ON public.explore_posts
FOR EACH ROW EXECUTE FUNCTION internal.revoke_removed_publication_photos();

CREATE OR REPLACE FUNCTION internal.claim_publication_photo_erasure() RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.publication_photo_objects;
BEGIN
    PERFORM internal.require_service_role();
    SELECT * INTO saved FROM internal.publication_photo_objects WHERE erased_at IS NULL AND available_at<=clock_timestamp()
        AND (bound_at IS NULL OR revoked_at IS NOT NULL)
        AND (claim_expires_at IS NULL OR claim_expires_at<=clock_timestamp()) ORDER BY available_at,object_id LIMIT 1 FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN RETURN NULL; END IF;
    UPDATE internal.publication_photo_objects SET claim_token=extensions.gen_random_uuid(),claim_expires_at=clock_timestamp()+INTERVAL '2 minutes'
        WHERE object_id=saved.object_id RETURNING * INTO saved;
    RETURN to_jsonb(saved);
END;
$$;

CREATE OR REPLACE FUNCTION internal.abandon_publication_photo_copy(p_owner UUID,p_observation UUID,p_attempt UUID,p_object UUID,p_token UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_photo_copies; registry internal.publication_photo_objects;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO saved FROM internal.observation_photo_copies WHERE attempt_id=p_attempt FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF ROW(saved.object_id,saved.lease_token,saved.owner_id,saved.observation_id) IS DISTINCT FROM ROW(p_object,p_token,p_owner,p_observation) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    SELECT * INTO STRICT registry FROM internal.publication_photo_objects WHERE object_id=p_object FOR UPDATE;
    IF registry.bound_at IS NOT NULL THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    IF registry.erased_at IS NULL THEN
        UPDATE internal.publication_photo_objects SET available_at=LEAST(available_at,clock_timestamp()),revoked_at=COALESCE(revoked_at,clock_timestamp()) WHERE object_id=p_object;
    END IF;
END;
$$;

CREATE FUNCTION internal.bind_approved_publication_photo_cohort(p_owner UUID,p_observation UUID,p_operation UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE prepared JSONB; request JSONB; source_fact JSONB; ordinal BIGINT; attempt UUID;
    saved internal.observation_community_admissions; publication internal.observation_photo_publications; copy internal.observation_photo_copies;
    registry internal.publication_photo_objects; objects UUID[]:='{}'::UUID[]; object UUID;
    media JSONB:='[]'::JSONB; url TEXT; receipt JSONB; post UUID;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    -- Admission advances authority. Lost-response replay returns historical
    -- evidence without revalidating stale revisions or republishing removed posts.
    SELECT * INTO saved FROM internal.observation_community_admissions WHERE operation_id=p_operation;
    IF FOUND THEN
        SELECT * INTO publication FROM internal.observation_photo_publications WHERE operation_id=p_operation;
        IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
        IF publication.receipt IS DISTINCT FROM saved.receipt
            OR publication.object_ids IS DISTINCT FROM (SELECT array_agg(object_id ORDER BY order_index) FROM internal.publication_photo_bindings WHERE post_id=saved.post_id)
            OR ROW(saved.owner_id,saved.observation_id) IS DISTINCT FROM ROW(p_owner,p_observation)
            OR NOT EXISTS(SELECT 1 FROM internal.observation_publication_intents WHERE operation_id=p_operation AND owner_id=p_owner AND observation_id=p_observation)
            OR NOT EXISTS(SELECT 1 FROM internal.publication_photo_bindings WHERE post_id=saved.post_id) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN saved.receipt;
    END IF;
    IF (SELECT publication_binding_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    prepared:=internal.revalidate_observation_publication_intent(p_owner,p_observation,p_operation);
    request:=prepared->'request';
    FOR source_fact,ordinal IN SELECT value,ordinality FROM jsonb_array_elements(prepared->'sources') WITH ORDINALITY LOOP
        SELECT a.id INTO attempt FROM internal.observation_photo_moderation_attempts a
            JOIN internal.observation_photo_copies c ON c.attempt_id=a.id
            WHERE a.operation_id=p_operation AND a.media_id=(source_fact->>'media_id')::UUID AND a.state='approved';
        IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
        IF internal.authorize_publication_photo_copy(p_owner,p_observation,attempt) IS DISTINCT FROM source_fact THEN
            RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
        END IF;
        SELECT * INTO STRICT copy FROM internal.observation_photo_copies WHERE attempt_id=attempt FOR UPDATE;
        IF copy.source IS DISTINCT FROM source_fact OR copy.owner_id IS DISTINCT FROM p_owner OR copy.observation_id IS DISTINCT FROM p_observation
            OR copy.ready_at IS NULL OR copy.expires_at<=clock_timestamp() THEN
            RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
        END IF;
        objects:=array_append(objects,copy.object_id);
        url:='https://media.merian.app/publication_media/v1/'||copy.object_id::TEXT;
        media:=media||jsonb_build_array(jsonb_build_object('kind','image','url',url,'thumbnail_url',url,
            'order_index',ordinal-1,'duration_seconds',NULL,'has_audio',FALSE));
    END LOOP;
    -- Lock complete cohort in stable order before any publication writes.
    FOR object IN SELECT unnest(objects) ORDER BY 1 LOOP
        SELECT * INTO STRICT registry FROM internal.publication_photo_objects WHERE object_id=object FOR UPDATE;
        IF registry.available_at<=clock_timestamp() OR registry.bound_at IS NOT NULL OR registry.revoked_at IS NOT NULL
            OR registry.claim_token IS NOT NULL OR registry.erased_at IS NOT NULL THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
    END LOOP;
    receipt:=internal.admit_observation_community_request(p_owner,p_operation,p_observation,(request->>'analysis_id')::UUID,
        (request->>'expected_observation_revision')::INTEGER,(request->>'expected_review_revision')::INTEGER,
        (request->>'taxonomy_version_id')::UUID,(request->>'initial_taxon_id')::UUID,request->>'note',media);
    post:=(receipt->>'post_id')::UUID;
    IF EXISTS(SELECT 1 FROM public.explore_posts WHERE id=post AND (unshared_at IS NOT NULL OR moderated_at IS NOT NULL OR media_health_status='quarantined')) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    INSERT INTO internal.publication_photo_bindings(object_id,post_id,order_index)
        SELECT value,post,ordinality-1 FROM unnest(objects) WITH ORDINALITY AS o(value,ordinality);
    UPDATE internal.publication_photo_objects SET bound_at=clock_timestamp() WHERE object_id=ANY(objects);
    INSERT INTO internal.observation_photo_publications VALUES(p_operation,objects,receipt);
    RETURN receipt;
END;
$$;
REVOKE ALL ON FUNCTION internal.bind_approved_publication_photo_cohort(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

RESET statement_timeout;
RESET lock_timeout;
