-- add all newly implemented telemetry context columns to scans

ALTER TABLE public.scans
ADD COLUMN IF NOT EXISTS semantic_location TEXT,
ADD COLUMN IF NOT EXISTS device_locale TEXT,
ADD COLUMN IF NOT EXISTS current_month INTEGER,
ADD COLUMN IF NOT EXISTS time_of_day TEXT,
ADD COLUMN IF NOT EXISTS is_flash_fired BOOLEAN,
ADD COLUMN IF NOT EXISTS camera_pitch_degrees DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS compass_heading DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS relative_humidity DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS uv_index INTEGER,
ADD COLUMN IF NOT EXISTS depth_scale_text TEXT;
