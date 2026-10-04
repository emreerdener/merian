-- Private notes and Favorites follow the stable scan through an authorized
-- guest merge. Tags retain their existing public scan projection contract.
SET lock_timeout = '5s';
SET statement_timeout = '30s';
CREATE TABLE internal.scan_library_details (
    scan_id UUID PRIMARY KEY REFERENCES public.scans(id) ON DELETE CASCADE,
    field_notes TEXT CHECK (pg_catalog.char_length(field_notes) <= 10000),
    is_favorite BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE TABLE internal.scan_library_detail_receipts (
    operation_id UUID PRIMARY KEY,
    scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
    payload_hash TEXT NOT NULL
);
CREATE INDEX scan_library_detail_receipts_scan_idx ON internal.scan_library_detail_receipts(scan_id);
ALTER TABLE internal.scan_library_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.scan_library_detail_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.scan_library_details, internal.scan_library_detail_receipts FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION internal.set_owned_scan_library_details(
    p_scan_id UUID, p_operation_id UUID, p_field_notes TEXT, p_is_favorite BOOLEAN, p_custom_tags TEXT[]
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    caller UUID := auth.uid();
    payload_hash TEXT;
    receipt internal.scan_library_detail_receipts%ROWTYPE;
BEGIN
    IF caller IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
    IF p_scan_id IS NULL OR p_operation_id IS NULL OR p_is_favorite IS NULL
       OR pg_catalog.char_length(p_field_notes) > 10000 OR p_custom_tags IS NULL
       OR NOT internal.text_array_elements_are_bounded(p_custom_tags, 50, 256) THEN
        RAISE EXCEPTION 'invalid_library_details' USING ERRCODE = '22023';
    END IF;
    PERFORM id FROM public.users WHERE id = caller FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'scan_not_owned_or_missing' USING ERRCODE = '42501'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:' || p_scan_id::TEXT, 0::BIGINT));
    PERFORM id FROM public.scans WHERE id = p_scan_id AND user_id = caller AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS (SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id = p_scan_id) THEN
        RAISE EXCEPTION 'scan_not_owned_or_missing' USING ERRCODE = '42501';
    END IF;
    payload_hash := pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
        pg_catalog.jsonb_build_object('scan', p_scan_id, 'notes', p_field_notes, 'favorite', p_is_favorite, 'tags', p_custom_tags)::TEXT,
        'UTF8'), 'sha256'), 'hex');
    SELECT * INTO receipt FROM internal.scan_library_detail_receipts WHERE operation_id = p_operation_id;
    IF FOUND THEN
        IF receipt.scan_id <> p_scan_id OR receipt.payload_hash <> payload_hash THEN
            RAISE EXCEPTION 'library_operation_conflict' USING ERRCODE = '22023';
        END IF;
        RETURN;
    END IF;
    INSERT INTO internal.scan_library_details(scan_id, field_notes, is_favorite)
        VALUES (p_scan_id, p_field_notes, p_is_favorite)
        ON CONFLICT (scan_id) DO UPDATE SET field_notes = EXCLUDED.field_notes, is_favorite = EXCLUDED.is_favorite;
    UPDATE public.scans SET custom_tags = p_custom_tags WHERE id = p_scan_id AND user_id = caller;
    INSERT INTO internal.scan_library_detail_receipts(operation_id, scan_id, payload_hash)
        VALUES (p_operation_id, p_scan_id, payload_hash);
END;
$$;
CREATE FUNCTION public.set_owned_scan_library_details(
    p_scan_id UUID, p_operation_id UUID, p_field_notes TEXT, p_is_favorite BOOLEAN, p_custom_tags TEXT[]
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
    PERFORM internal.set_owned_scan_library_details(p_scan_id, p_operation_id, p_field_notes, p_is_favorite, p_custom_tags);
END;
$$;
CREATE FUNCTION internal.get_owned_scan_library_details(p_scan_ids UUID[])
RETURNS TABLE(scan_id UUID, field_notes TEXT, is_favorite BOOLEAN, owner_id UUID)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
    IF p_scan_ids IS NULL OR pg_catalog.cardinality(p_scan_ids) > 100 THEN
        RAISE EXCEPTION 'invalid_library_lookup' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY SELECT scan.id, details.field_notes, COALESCE(details.is_favorite, FALSE), scan.user_id
        FROM public.scans scan LEFT JOIN internal.scan_library_details details ON details.scan_id = scan.id
        WHERE scan.id = ANY(p_scan_ids) AND scan.user_id = auth.uid() AND NOT scan.is_tombstoned
          AND NOT EXISTS (SELECT 1 FROM internal.scan_deletion_tombstones deleted WHERE deleted.scan_id = scan.id);
END;
$$;
CREATE FUNCTION public.get_owned_scan_library_details(p_scan_ids UUID[])
RETURNS TABLE(scan_id UUID, field_notes TEXT, is_favorite BOOLEAN, owner_id UUID)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
    RETURN QUERY SELECT * FROM internal.get_owned_scan_library_details(p_scan_ids);
END;
$$;
REVOKE ALL ON FUNCTION internal.set_owned_scan_library_details(UUID,UUID,TEXT,BOOLEAN,TEXT[]),
    public.set_owned_scan_library_details(UUID,UUID,TEXT,BOOLEAN,TEXT[]),
    internal.get_owned_scan_library_details(UUID[]), public.get_owned_scan_library_details(UUID[])
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_owned_scan_library_details(UUID,UUID,TEXT,BOOLEAN,TEXT[]),
    public.get_owned_scan_library_details(UUID[]) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('authenticated','public.set_owned_scan_library_details(uuid,uuid,text,boolean,text[])','Owner-locked private library mutation with durable operation receipt.'),
 ('authenticated','public.get_owned_scan_library_details(uuid[])','Bounded owner-only private library restoration.');
RESET statement_timeout;
RESET lock_timeout;
