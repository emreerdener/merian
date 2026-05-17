-- add environmental context columns to scans

ALTER TABLE public.scans
ADD COLUMN IF NOT EXISTS gps_elevation DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS weather_temperature_f DOUBLE PRECISION;
