SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Trigger records have different row types. A CASE expression still resolves
-- both field references; branch before accessing the table-specific record.
CREATE OR REPLACE FUNCTION internal.retire_initial_capture_audio_stages_for_deletion()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE target UUID; scan UUID;
BEGIN
    IF TG_TABLE_NAME='scan_deletion_tombstones' THEN
        PERFORM internal.retire_initial_capture_audio_stage(NEW.scan_id); RETURN NEW;
    END IF;
    IF TG_TABLE_NAME='users' THEN target:=OLD.id;
    ELSE target:=NEW.user_id; END IF;
    FOR scan IN SELECT scan_id FROM internal.initial_capture_audio_stages WHERE owner_id=target ORDER BY scan_id LOOP
        PERFORM internal.retire_initial_capture_audio_stage(scan);
    END LOOP;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.retire_initial_capture_audio_stages_for_deletion() FROM PUBLIC,anon,authenticated,service_role;
RESET statement_timeout;
RESET lock_timeout;
