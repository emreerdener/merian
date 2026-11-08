SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- IC-1 foundation only: no callable admission, dispatch, or completion writer.
-- These bounded containers are not proof of validated input/result/funding.
-- Fixed service operations must add canonical encoding and semantic validation
-- before they can write them. Nothing here changes an existing initial route.
CREATE TABLE internal.initial_analysis_rollout (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    initial_analysis_lifecycle_enabled BOOLEAN NOT NULL DEFAULT FALSE
);
INSERT INTO internal.initial_analysis_rollout(singleton) VALUES(TRUE);

CREATE TABLE internal.initial_analysis_submissions (
    scan_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    route TEXT NOT NULL CHECK(route IN ('identify-multimodal','identify','identify-describe')),
    input_schema_version INTEGER NOT NULL CHECK(input_schema_version=1),
    input_snapshot JSONB NOT NULL CHECK(jsonb_typeof(input_snapshot)='object' AND octet_length(input_snapshot::TEXT)<=1048576),
    ordered_descriptions JSONB NOT NULL CHECK(jsonb_typeof(ordered_descriptions)='array' AND octet_length(ordered_descriptions::TEXT)<=1048576),
    configuration_snapshot JSONB NOT NULL CHECK(jsonb_typeof(configuration_snapshot)='object' AND octet_length(configuration_snapshot::TEXT)<=65536),
    funding_snapshot JSONB NOT NULL CHECK(jsonb_typeof(funding_snapshot)='object' AND octet_length(funding_snapshot::TEXT)<=16384),
    UNIQUE(scan_id,owner_id)
);
CREATE INDEX initial_analysis_submissions_owner ON internal.initial_analysis_submissions(owner_id,scan_id);
CREATE TABLE internal.initial_analysis_results (
    scan_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    result_evidence_id UUID NOT NULL UNIQUE,
    result_schema_version INTEGER NOT NULL CHECK(result_schema_version=1),
    result_snapshot JSONB NOT NULL CHECK(jsonb_typeof(result_snapshot)='object' AND octet_length(result_snapshot::TEXT)<=1048576),
    provenance_snapshot JSONB NOT NULL CHECK(jsonb_typeof(provenance_snapshot)='object' AND octet_length(provenance_snapshot::TEXT)<=65536),
    FOREIGN KEY(scan_id,owner_id) REFERENCES internal.initial_analysis_submissions(scan_id,owner_id) ON DELETE CASCADE,
    UNIQUE(scan_id,owner_id,result_evidence_id)
);
CREATE TABLE internal.initial_analysis_completions (
    scan_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    result_evidence_id UUID NOT NULL,
    receipt_version INTEGER NOT NULL CHECK(receipt_version=1),
    receipt_snapshot JSONB NOT NULL CHECK(jsonb_typeof(receipt_snapshot)='object' AND octet_length(receipt_snapshot::TEXT)<=16384),
    FOREIGN KEY(scan_id,owner_id,result_evidence_id) REFERENCES internal.initial_analysis_results(scan_id,owner_id,result_evidence_id) ON DELETE CASCADE
);
ALTER TABLE internal.initial_analysis_rollout ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_analysis_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_analysis_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_analysis_completions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_analysis_rollout,internal.initial_analysis_submissions,
    internal.initial_analysis_results,internal.initial_analysis_completions FROM PUBLIC,anon,authenticated,service_role;

-- Preserve means hold a merge only when this source owner actually has rows.
-- A global "blocked" policy would disable every otherwise unrelated merge.
INSERT INTO internal.ghost_profile_merge_reference_policies
    (source_schema,source_table,source_column,referenced_schema,referenced_table,referenced_column,strategy,execution_order,handler_key,purpose)
VALUES('internal','initial_analysis_submissions','owner_id','public','users','id','preserve',900,NULL,
    'Hold identity transfer while immutable initial-analysis evidence exists; never rewrite original ownership.');

CREATE FUNCTION internal.guard_initial_analysis_storage()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE scan_owner UUID; scan_retired BOOLEAN;
BEGIN
    IF TG_OP='UPDATE' THEN
        RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
    END IF;
    IF TG_OP='DELETE' THEN
        IF EXISTS(SELECT 1 FROM public.users WHERE id=OLD.owner_id)
           AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.scan_id) THEN
            RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
        END IF;
        RETURN OLD;
    END IF;
    -- Later fixed operations must acquire this same outer scope before any
    -- accounting/private-row locks. Trigger enforcement is defense in depth.
    IF current_setting('transaction_isolation')<>'read committed' THEN
        RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled) THEN
        RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM id FROM public.users WHERE id=NEW.owner_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:' || NEW.scan_id::TEXT,0::BIGINT));
    SELECT user_id,is_tombstoned INTO scan_owner,scan_retired FROM public.scans WHERE id=NEW.scan_id FOR UPDATE;
    IF FOUND AND (TG_TABLE_NAME='initial_analysis_submissions' OR scan_owner IS DISTINCT FROM NEW.owner_id OR scan_retired) THEN
        RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023';
    END IF;
    PERFORM observation_id FROM internal.observation_histories WHERE observation_id=NEW.scan_id FOR UPDATE;
    IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=NEW.scan_id)
       OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=NEW.owner_id AND status IN ('pending','storage_pending','auth_pending')) THEN
        RAISE EXCEPTION 'initial_analysis_deleted' USING ERRCODE='55000';
    END IF;
    IF TG_TABLE_NAME='initial_analysis_submissions' THEN
      IF EXISTS(
        SELECT 1 FROM jsonb_array_elements(NEW.ordered_descriptions) item
        WHERE jsonb_typeof(item)<>'string' OR octet_length(item::TEXT)>65536
    ) THEN
        RAISE EXCEPTION 'initial_analysis_description_invalid' USING ERRCODE='22023';
      END IF;
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_initial_analysis_storage() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_initial_analysis_submission BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_analysis_submissions
    FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_analysis_storage();
CREATE TRIGGER guard_initial_analysis_result BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_analysis_results
    FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_analysis_storage();
CREATE TRIGGER guard_initial_analysis_completion BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_analysis_completions
    FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_analysis_storage();

-- A raw privileged tombstone insert must not miss an uncommitted pre-row
-- submission. Existing owner-first callers reenter; opposing scope fails fast.
CREATE FUNCTION internal.guard_initial_analysis_tombstone_scope()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE owned_by UUID;
BEGIN
    -- One snapshot: a visible legacy scan without initial evidence cannot gain
    -- a first submission (admission rejects existing scans; scan INSERT shares
    -- its owner/advisory scope). Preserve legacy-only tombstone wait semantics.
    IF EXISTS(SELECT 1 FROM public.scans WHERE id=NEW.scan_id)
       AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id) THEN
        RETURN NEW;
    END IF;
    SELECT owner_id INTO owned_by FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id;
    IF owned_by IS NULL THEN SELECT user_id INTO owned_by FROM public.scans WHERE id=NEW.scan_id; END IF;
    IF owned_by IS NOT NULL THEN
        PERFORM id FROM public.users WHERE id=owned_by FOR UPDATE NOWAIT;
    END IF;
    IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:' || NEW.scan_id::TEXT,0::BIGINT)) THEN
        RAISE EXCEPTION 'initial_analysis_erasure_busy' USING ERRCODE='55P03';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_initial_analysis_tombstone_scope() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_initial_analysis_tombstone_scope BEFORE INSERT ON internal.scan_deletion_tombstones
    FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_analysis_tombstone_scope();

CREATE FUNCTION internal.erase_initial_analysis_for_scan_fence()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    DELETE FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.erase_initial_analysis_for_scan_fence() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER erase_initial_analysis_for_scan_fence AFTER INSERT ON internal.scan_deletion_tombstones
    FOR EACH ROW EXECUTE FUNCTION internal.erase_initial_analysis_for_scan_fence();

-- Raw privileged scan-first writes must fail rather than wait on an outer
-- owner/advisory lock. Normal deletion APIs already own both, so this is
-- reentrant. It runs before any AFTER history/accounting cascade.
CREATE FUNCTION internal.guard_initial_analysis_scan_erasure_scope()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=OLD.id) THEN
        IF OLD.user_id IS NOT NULL THEN
            PERFORM id FROM public.users WHERE id=OLD.user_id FOR UPDATE NOWAIT;
        END IF;
        IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:' || OLD.id::TEXT,0::BIGINT)) THEN
            RAISE EXCEPTION 'initial_analysis_erasure_busy' USING ERRCODE='55P03';
        END IF;
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_initial_analysis_scan_erasure_scope() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_initial_analysis_scan_erasure_scope BEFORE UPDATE OF user_id,is_tombstoned OR DELETE ON public.scans
    FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_analysis_scan_erasure_scope();

CREATE FUNCTION internal.fence_initial_analysis_on_scan_change()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE identity UUID;
BEGIN
    identity:=OLD.id;
    IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=identity) THEN
        RETURN NULL;
    END IF;
    IF TG_OP='UPDATE' THEN
        IF NEW.user_id IS NOT NULL AND NOT NEW.is_tombstoned THEN
            IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
                RAISE EXCEPTION 'initial_analysis_owner_immutable' USING ERRCODE='22023';
            END IF;
            RETURN NULL;
        END IF;
    END IF;
    -- Caller already owns the scan row. Do not acquire the outer owner lock
    -- late here. The BEFORE scope guard has acquired or reentered them without
    -- waiting before existing history/accounting fanout can run.
    INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)
    VALUES(identity,NULL,clock_timestamp()) ON CONFLICT(scan_id) DO NOTHING;
    DELETE FROM internal.initial_analysis_submissions WHERE scan_id=identity;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.fence_initial_analysis_on_scan_change() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER fence_initial_analysis_on_scan_change AFTER UPDATE OF user_id,is_tombstoned OR DELETE ON public.scans
    FOR EACH ROW EXECUTE FUNCTION internal.fence_initial_analysis_on_scan_change();

CREATE FUNCTION internal.fence_initial_analysis_before_owner_delete()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE identity UUID;
BEGIN
    -- Existing scan/history cleanup can settle funding and update the owner.
    -- Doing that inside its BEFORE DELETE would mutate the deleting tuple.
    -- The supported apply_user_tombstone path detaches scans first; reject raw
    -- privileged deletion until it has done that work, without partial erasure.
    IF EXISTS(SELECT 1 FROM internal.initial_analysis_submissions AS submission
        JOIN public.scans AS scan ON scan.id=submission.scan_id
        WHERE submission.owner_id=OLD.id AND scan.user_id IS NOT NULL) THEN
        RAISE EXCEPTION 'initial_analysis_account_detachment_required' USING ERRCODE='55000';
    END IF;
    -- Pre-row evidence has no history/funding fanout. The deleting transaction
    -- owns this user row; sorted advisory locks precede private-row cascades.
    FOR identity IN SELECT scan_id FROM internal.initial_analysis_submissions WHERE owner_id=OLD.id ORDER BY scan_id LOOP
        PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:' || identity::TEXT,0::BIGINT));
        INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)
        VALUES(identity,NULL,clock_timestamp()) ON CONFLICT(scan_id) DO NOTHING;
        DELETE FROM internal.initial_analysis_submissions WHERE scan_id=identity;
    END LOOP;
    RETURN OLD;
END;
$$;
REVOKE ALL ON FUNCTION internal.fence_initial_analysis_before_owner_delete() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER fence_initial_analysis_before_owner_delete BEFORE DELETE ON public.users
    FOR EACH ROW EXECUTE FUNCTION internal.fence_initial_analysis_before_owner_delete();

COMMENT ON TABLE internal.initial_analysis_submissions IS 'IC-1 inactive private immutable container; exact ordered accepted text, input, configuration and original funding. No API writer or dispatch authority. Erased by scan/account fences before or after scan creation.';
COMMENT ON TABLE internal.initial_analysis_results IS 'IC-1 inactive private bounded result/provenance container; future fixed service operations must validate original dispatch and canonical identity before use.';
COMMENT ON TABLE internal.initial_analysis_completions IS 'IC-1 inactive private receipt container; storage alone does not prove atomic scan/accounting completion. No public/client receipt reader.';
COMMENT ON TABLE internal.initial_analysis_rollout IS 'Default-false server gate. Enabling this table alone installs no writer; S0, adapters, media and worker cutover acceptance remain mandatory.';
RESET statement_timeout;
RESET lock_timeout;
