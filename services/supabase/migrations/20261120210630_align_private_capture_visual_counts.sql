SET lock_timeout='5s';
SET statement_timeout='2min';

-- Preserve the existing ingestion telemetry semantics: still photos and video
-- frames have separate counters. No inventory, digest or admission grants change.
CREATE OR REPLACE FUNCTION internal.private_capture_media_counts(p_manifest JSONB)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT jsonb_build_object(
  'image_count',count(*) FILTER(WHERE x->>'kind'='image'),
  'audio_count',count(*) FILTER(WHERE x->>'kind'='audio' OR (x->>'kind'='video' AND x->'audio'<>'null'::JSONB)),
  'video_count',count(*) FILTER(WHERE x->>'kind'='video'),
  'required_video_count',count(*) FILTER(WHERE x->>'kind'='video'),
  'video_frame_count',COALESCE(sum(jsonb_array_length(x->'frames')) FILTER(WHERE x->>'kind'='video'),0),
  'video_inference_frame_count',COALESCE(sum(jsonb_array_length(x->'frames')) FILTER(WHERE x->>'kind'='video'),0),
  'has_description',count(*) FILTER(WHERE x->>'kind'='description')>0)
 FROM jsonb_array_elements(p_manifest->'items') x;
$$;

RESET statement_timeout;
RESET lock_timeout;
