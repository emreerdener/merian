ALTER TABLE "public"."scans"
DROP COLUMN IF EXISTS "is_flash_fired",
DROP COLUMN IF EXISTS "camera_pitch_degrees",
DROP COLUMN IF EXISTS "compass_heading",
DROP COLUMN IF EXISTS "relative_humidity",
DROP COLUMN IF EXISTS "uv_index";
