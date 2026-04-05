-- Migration: 20260405000005_add_gps_check_constraints.sql
-- Description: Add CHECK constraints on GPS columns in the scans table.
--
-- Without these, any value can be inserted for lat/lon/elevation — e.g., a
-- misconfigured iOS device could send lat=999, which would appear as a real
-- coordinate in DwC-A exports and the discovery feed, silently corrupting
-- scientific data. Constraints here act as the last line of defense after
-- client-side validation.
--
-- NOT VALID: skips a full-table scan on existing rows (zero downtime), but
-- all future INSERTs and UPDATEs are still validated. Existing malformed
-- rows (if any) are not retroactively rejected.

ALTER TABLE public.scans
  ADD CONSTRAINT chk_gps_lat_exact
    CHECK (gps_lat_exact IS NULL OR (gps_lat_exact >= -90 AND gps_lat_exact <= 90))
    NOT VALID,

  ADD CONSTRAINT chk_gps_long_exact
    CHECK (gps_long_exact IS NULL OR (gps_long_exact >= -180 AND gps_long_exact <= 180))
    NOT VALID,

  ADD CONSTRAINT chk_gps_lat_public
    CHECK (gps_lat_public IS NULL OR (gps_lat_public >= -90 AND gps_lat_public <= 90))
    NOT VALID,

  ADD CONSTRAINT chk_gps_long_public
    CHECK (gps_long_public IS NULL OR (gps_long_public >= -180 AND gps_long_public <= 180))
    NOT VALID,

  -- Elevation: -500m (well below Dead Sea at -430m) to 9500m (above Everest at 8849m).
  ADD CONSTRAINT chk_gps_elevation
    CHECK (gps_elevation IS NULL OR (gps_elevation >= -500 AND gps_elevation <= 9500))
    NOT VALID;
