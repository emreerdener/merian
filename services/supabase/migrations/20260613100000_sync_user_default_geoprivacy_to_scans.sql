CREATE OR REPLACE FUNCTION public.set_scan_public_location_label()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.geoprivacy = 'private' THEN
        NEW.public_location_label := NULL;
    ELSE
        NEW.public_location_label := public.resolve_explore_location_label(
            NEW.public_location_label,
            NEW.semantic_location
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_scan_public_location_label ON public.scans;
CREATE TRIGGER trg_set_scan_public_location_label
BEFORE INSERT OR UPDATE OF public_location_label, semantic_location, geoprivacy
ON public.scans
FOR EACH ROW
EXECUTE FUNCTION public.set_scan_public_location_label();

CREATE OR REPLACE FUNCTION public.trg_sync_user_default_geoprivacy_to_scans()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.default_geoprivacy IS DISTINCT FROM OLD.default_geoprivacy THEN
        UPDATE public.scans
        SET geoprivacy = NEW.default_geoprivacy
        WHERE user_id = NEW.id
          AND geoprivacy IS DISTINCT FROM NEW.default_geoprivacy;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_user_default_geoprivacy_to_scans ON public.users;
CREATE TRIGGER trg_sync_user_default_geoprivacy_to_scans
AFTER UPDATE OF default_geoprivacy
ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.trg_sync_user_default_geoprivacy_to_scans();
