SET lock_timeout='5s';
SET statement_timeout='2min';

-- Dormant IC-1 outcome-ready owner. No catalog entries, admission or provider authority.
CREATE FUNCTION internal.initial_preparation_execution_schema() RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path='' AS $schema$ SELECT $json${"source_verification":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"validator_identity":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}},"facts":{"type":"object","properties":{"image":{"type":"object","properties":{"width":{"type":"integer","minimum":1,"maximum":65535},"height":{"type":"integer","minimum":1,"maximum":65535},"format":{"type":"string","max_bytes":128,"enum":["jpeg","png","webp","heic","heif"]}},"nullable":true},"wav":{"type":"object","properties":{"format":{"type":"string","max_bytes":128,"enum":["pcm16","float32"]},"sample_rate":{"type":"integer","minimum":1,"maximum":384000},"channels":{"type":"integer","minimum":1,"maximum":32},"frames":{"type":"integer","minimum":1,"maximum":12582912}},"nullable":true},"mp4":{"type":"object","properties":{"structure":{"type":"string","max_bytes":128,"enum":["bounded_mp4_accepted"]}},"nullable":true}}}}},"max_items":8}}},"output_manifest":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"prepared":{"type":"object","properties":{"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}},"transform":{"type":"string","max_bytes":128,"enum":["identity_v1","initial_audio_v1","video_frame_v1"]},"parameters":{"type":"object","nullable":true,"properties":{"target_sample_rate":{"type":"integer","minimum":16000,"maximum":16000},"preserve_short_video_context":{"type":"boolean"}}},"source_identity":{"type":"boolean"}},"nullable":true}}},"max_items":8}}},"resolved_manifest":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"request_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$","nullable":true}}},"max_items":8}}},"grant":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"artifact_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"issued_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"execution_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"registration_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"outcome_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"outcome":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"artifact_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"issued_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"execution_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"registration_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"outcome_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"source_verification":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"validator_identity":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}},"facts":{"type":"object","properties":{"image":{"type":"object","properties":{"width":{"type":"integer","minimum":1,"maximum":65535},"height":{"type":"integer","minimum":1,"maximum":65535},"format":{"type":"string","max_bytes":128,"enum":["jpeg","png","webp","heic","heif"]}},"nullable":true},"wav":{"type":"object","properties":{"format":{"type":"string","max_bytes":128,"enum":["pcm16","float32"]},"sample_rate":{"type":"integer","minimum":1,"maximum":384000},"channels":{"type":"integer","minimum":1,"maximum":32},"frames":{"type":"integer","minimum":1,"maximum":12582912}},"nullable":true},"mp4":{"type":"object","properties":{"structure":{"type":"string","max_bytes":128,"enum":["bounded_mp4_accepted"]}},"nullable":true}}}}},"max_items":8}}},"output_manifest":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"prepared":{"type":"object","properties":{"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}},"transform":{"type":"string","max_bytes":128,"enum":["identity_v1","initial_audio_v1","video_frame_v1"]},"parameters":{"type":"object","nullable":true,"properties":{"target_sample_rate":{"type":"integer","minimum":16000,"maximum":16000},"preserve_short_video_context":{"type":"boolean"}}},"source_identity":{"type":"boolean"}},"nullable":true}}},"max_items":8}}},"resolved_manifest":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"request_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$","nullable":true}}},"max_items":8}}},"profile":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"spec":{"type":"object","properties":{"profile_id":{"type":"string","max_bytes":64,"pattern":"^[a-z][a-z0-9_]{0,63}$"},"profile_version":{"type":"integer","minimum":1,"maximum":2147483647},"input_profile":{"type":"string","max_bytes":128,"enum":["vision_compat_v1","multimodal_photo_v1","multimodal_audio_v1","multimodal_photo_audio_v1","multimodal_video_frames_v1","multimodal_video_audio_v1"]},"route":{"type":"string","max_bytes":128,"enum":["identify","identify-multimodal"]},"focus_policy":{"type":"string","max_bytes":128,"enum":["input_v1_bounds"]},"runtime":{"type":"object","properties":{"engine":{"type":"string","max_bytes":128,"enum":["deno"]},"version":{"type":"string","max_bytes":64,"pattern":"^[0-9]+\\.[0-9]+\\.[0-9]+$"},"platform":{"type":"string","max_bytes":64,"pattern":"^[a-z][a-z0-9_]{0,63}$"},"abi":{"type":"string","max_bytes":64,"pattern":"^[a-z][a-z0-9_]{0,63}$"},"protocol":{"type":"integer","minimum":1,"maximum":2147483647}}},"artifact":{"type":"object","properties":{"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":67108864}}},"identities":{"type":"object","properties":{"source":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"validator":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"transform":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"configuration":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"rules":{"type":"array","items":{"type":"object","properties":{"role":{"type":"string","max_bytes":128,"enum":["photo","recording","video_frame","video_audio","raw_video"]},"source_types":{"type":"array","items":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]},"max_items":5},"transform":{"type":"string","max_bytes":128,"enum":["identity_v1","video_frame_v1","initial_audio_v1"]},"target_sample_rate":{"type":"integer","minimum":8000,"maximum":192000,"nullable":true},"preserve_short_video_context":{"type":"boolean","nullable":true},"max_count":{"type":"integer","minimum":1,"maximum":8},"limits":{"type":"object","properties":{"source_bytes":{"type":"integer","minimum":1,"maximum":20971520},"output_bytes":{"type":"integer","minimum":0,"maximum":20971520},"cpu_ms":{"type":"integer","minimum":1,"maximum":300000},"heap_bytes":{"type":"integer","minimum":1,"maximum":1073741824},"wall_ms":{"type":"integer","minimum":1,"maximum":300000}}}}},"max_items":5},"max_sources":{"type":"integer","minimum":1,"maximum":8},"limits":{"type":"object","properties":{"source_bytes":{"type":"integer","minimum":1,"maximum":20971520},"output_bytes":{"type":"integer","minimum":0,"maximum":20971520},"cpu_ms":{"type":"integer","minimum":1,"maximum":300000},"heap_bytes":{"type":"integer","minimum":1,"maximum":1073741824},"wall_ms":{"type":"integer","minimum":1,"maximum":300000}}}}},"qualification":{"type":"object","properties":{"spec_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"evidence_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"harness_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"source_revision":{"type":"string","max_bytes":40,"pattern":"^[0-9a-f]{40}$"}}}}},"retained":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}}}},"max_items":8}}},"reply_held":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"outcome":{"type":"string","max_bytes":64,"enum":["held"]},"reason":{"type":"string","max_bytes":64,"enum":["missing","expired","incoherent","preparation_issued","budget","phase_expired"]}}},"reply_status":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"outcome":{"type":"string","max_bytes":64,"enum":["status"]},"phase":{"type":"string","max_bytes":64,"enum":["allocated","verified","issued","output_registered","outcome_ready"]},"source":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"validator_identity":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}},"facts":{"type":"object","properties":{"image":{"type":"object","properties":{"width":{"type":"integer","minimum":1,"maximum":65535},"height":{"type":"integer","minimum":1,"maximum":65535},"format":{"type":"string","max_bytes":128,"enum":["jpeg","png","webp","heic","heif"]}},"nullable":true},"wav":{"type":"object","properties":{"format":{"type":"string","max_bytes":128,"enum":["pcm16","float32"]},"sample_rate":{"type":"integer","minimum":1,"maximum":384000},"channels":{"type":"integer","minimum":1,"maximum":32},"frames":{"type":"integer","minimum":1,"maximum":12582912}},"nullable":true},"mp4":{"type":"object","properties":{"structure":{"type":"string","max_bytes":128,"enum":["bounded_mp4_accepted"]}},"nullable":true}}}}},"max_items":8}},"nullable":true},"execution_reference":{"type":"object","properties":{"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}},"nullable":true},"output":{"type":"object","properties":{"request":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"prepared":{"type":"object","properties":{"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}},"transform":{"type":"string","max_bytes":128,"enum":["identity_v1","initial_audio_v1","video_frame_v1"]},"parameters":{"type":"object","nullable":true,"properties":{"target_sample_rate":{"type":"integer","minimum":16000,"maximum":16000},"preserve_short_video_context":{"type":"boolean"}}},"source_identity":{"type":"boolean"}},"nullable":true}}},"max_items":8}}},"resolved":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"request_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$","nullable":true}}},"max_items":8}}}},"nullable":true},"result":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"artifact_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"issued_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"execution_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"registration_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"outcome_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"source_verification":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"validator_identity":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}},"facts":{"type":"object","properties":{"image":{"type":"object","properties":{"width":{"type":"integer","minimum":1,"maximum":65535},"height":{"type":"integer","minimum":1,"maximum":65535},"format":{"type":"string","max_bytes":128,"enum":["jpeg","png","webp","heic","heif"]}},"nullable":true},"wav":{"type":"object","properties":{"format":{"type":"string","max_bytes":128,"enum":["pcm16","float32"]},"sample_rate":{"type":"integer","minimum":1,"maximum":384000},"channels":{"type":"integer","minimum":1,"maximum":32},"frames":{"type":"integer","minimum":1,"maximum":12582912}},"nullable":true},"mp4":{"type":"object","properties":{"structure":{"type":"string","max_bytes":128,"enum":["bounded_mp4_accepted"]}},"nullable":true}}}}},"max_items":8}}},"output_manifest":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"prepared":{"type":"object","properties":{"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}},"transform":{"type":"string","max_bytes":128,"enum":["identity_v1","initial_audio_v1","video_frame_v1"]},"parameters":{"type":"object","nullable":true,"properties":{"target_sample_rate":{"type":"integer","minimum":16000,"maximum":16000},"preserve_short_video_context":{"type":"boolean"}}},"source_identity":{"type":"boolean"}},"nullable":true}}},"max_items":8}}},"resolved_manifest":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"request_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$","nullable":true}}},"max_items":8}}},"profile":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"spec":{"type":"object","properties":{"profile_id":{"type":"string","max_bytes":64,"pattern":"^[a-z][a-z0-9_]{0,63}$"},"profile_version":{"type":"integer","minimum":1,"maximum":2147483647},"input_profile":{"type":"string","max_bytes":128,"enum":["vision_compat_v1","multimodal_photo_v1","multimodal_audio_v1","multimodal_photo_audio_v1","multimodal_video_frames_v1","multimodal_video_audio_v1"]},"route":{"type":"string","max_bytes":128,"enum":["identify","identify-multimodal"]},"focus_policy":{"type":"string","max_bytes":128,"enum":["input_v1_bounds"]},"runtime":{"type":"object","properties":{"engine":{"type":"string","max_bytes":128,"enum":["deno"]},"version":{"type":"string","max_bytes":64,"pattern":"^[0-9]+\\.[0-9]+\\.[0-9]+$"},"platform":{"type":"string","max_bytes":64,"pattern":"^[a-z][a-z0-9_]{0,63}$"},"abi":{"type":"string","max_bytes":64,"pattern":"^[a-z][a-z0-9_]{0,63}$"},"protocol":{"type":"integer","minimum":1,"maximum":2147483647}}},"artifact":{"type":"object","properties":{"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":67108864}}},"identities":{"type":"object","properties":{"source":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"validator":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"transform":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"configuration":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"rules":{"type":"array","items":{"type":"object","properties":{"role":{"type":"string","max_bytes":128,"enum":["photo","recording","video_frame","video_audio","raw_video"]},"source_types":{"type":"array","items":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]},"max_items":5},"transform":{"type":"string","max_bytes":128,"enum":["identity_v1","video_frame_v1","initial_audio_v1"]},"target_sample_rate":{"type":"integer","minimum":8000,"maximum":192000,"nullable":true},"preserve_short_video_context":{"type":"boolean","nullable":true},"max_count":{"type":"integer","minimum":1,"maximum":8},"limits":{"type":"object","properties":{"source_bytes":{"type":"integer","minimum":1,"maximum":20971520},"output_bytes":{"type":"integer","minimum":0,"maximum":20971520},"cpu_ms":{"type":"integer","minimum":1,"maximum":300000},"heap_bytes":{"type":"integer","minimum":1,"maximum":1073741824},"wall_ms":{"type":"integer","minimum":1,"maximum":300000}}}}},"max_items":5},"max_sources":{"type":"integer","minimum":1,"maximum":8},"limits":{"type":"object","properties":{"source_bytes":{"type":"integer","minimum":1,"maximum":20971520},"output_bytes":{"type":"integer","minimum":0,"maximum":20971520},"cpu_ms":{"type":"integer","minimum":1,"maximum":300000},"heap_bytes":{"type":"integer","minimum":1,"maximum":1073741824},"wall_ms":{"type":"integer","minimum":1,"maximum":300000}}}}},"qualification":{"type":"object","properties":{"spec_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"evidence_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"harness_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"source_revision":{"type":"string","max_bytes":40,"pattern":"^[0-9a-f]{40}$"}}}}},"retained":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}}}},"max_items":8}},"nullable":true},"server_now_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"expires_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"reply_verified":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"outcome":{"type":"string","max_bytes":64,"enum":["verified"]},"receipt":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"validator_identity":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}},"facts":{"type":"object","properties":{"image":{"type":"object","properties":{"width":{"type":"integer","minimum":1,"maximum":65535},"height":{"type":"integer","minimum":1,"maximum":65535},"format":{"type":"string","max_bytes":128,"enum":["jpeg","png","webp","heic","heif"]}},"nullable":true},"wav":{"type":"object","properties":{"format":{"type":"string","max_bytes":128,"enum":["pcm16","float32"]},"sample_rate":{"type":"integer","minimum":1,"maximum":384000},"channels":{"type":"integer","minimum":1,"maximum":32},"frames":{"type":"integer","minimum":1,"maximum":12582912}},"nullable":true},"mp4":{"type":"object","properties":{"structure":{"type":"string","max_bytes":128,"enum":["bounded_mp4_accepted"]}},"nullable":true}}}}},"max_items":8}}},"digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"reply_granted":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"outcome":{"type":"string","max_bytes":64,"enum":["granted"]},"grant":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"artifact_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"issued_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"execution_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"registration_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"outcome_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"server_now_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"expires_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"reply_registered":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"outcome":{"type":"string","max_bytes":64,"enum":["registered"]},"request":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"prepared":{"type":"object","properties":{"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}},"transform":{"type":"string","max_bytes":128,"enum":["identity_v1","initial_audio_v1","video_frame_v1"]},"parameters":{"type":"object","nullable":true,"properties":{"target_sample_rate":{"type":"integer","minimum":16000,"maximum":16000},"preserve_short_video_context":{"type":"boolean"}}},"source_identity":{"type":"boolean"}},"nullable":true}}},"max_items":8}}},"resolved":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"request_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$","nullable":true}}},"max_items":8}}}}},"reply_outcome_ready":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"outcome":{"type":"string","max_bytes":64,"enum":["outcome_ready"]},"result":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"artifact_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"issued_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"execution_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"registration_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"outcome_deadline_ms":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"source_verification":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"validator_identity":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}},"facts":{"type":"object","properties":{"image":{"type":"object","properties":{"width":{"type":"integer","minimum":1,"maximum":65535},"height":{"type":"integer","minimum":1,"maximum":65535},"format":{"type":"string","max_bytes":128,"enum":["jpeg","png","webp","heic","heif"]}},"nullable":true},"wav":{"type":"object","properties":{"format":{"type":"string","max_bytes":128,"enum":["pcm16","float32"]},"sample_rate":{"type":"integer","minimum":1,"maximum":384000},"channels":{"type":"integer","minimum":1,"maximum":32},"frames":{"type":"integer","minimum":1,"maximum":12582912}},"nullable":true},"mp4":{"type":"object","properties":{"structure":{"type":"string","max_bytes":128,"enum":["bounded_mp4_accepted"]}},"nullable":true}}}}},"max_items":8}}},"output_manifest":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"prepared":{"type":"object","properties":{"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}},"transform":{"type":"string","max_bytes":128,"enum":["identity_v1","initial_audio_v1","video_frame_v1"]},"parameters":{"type":"object","nullable":true,"properties":{"target_sample_rate":{"type":"integer","minimum":16000,"maximum":16000},"preserve_short_video_context":{"type":"boolean"}}},"source_identity":{"type":"boolean"}},"nullable":true}}},"max_items":8}}},"resolved_manifest":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"grant_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"request_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"entries":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$","nullable":true}}},"max_items":8}}},"profile":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"spec":{"type":"object","properties":{"profile_id":{"type":"string","max_bytes":64,"pattern":"^[a-z][a-z0-9_]{0,63}$"},"profile_version":{"type":"integer","minimum":1,"maximum":2147483647},"input_profile":{"type":"string","max_bytes":128,"enum":["vision_compat_v1","multimodal_photo_v1","multimodal_audio_v1","multimodal_photo_audio_v1","multimodal_video_frames_v1","multimodal_video_audio_v1"]},"route":{"type":"string","max_bytes":128,"enum":["identify","identify-multimodal"]},"focus_policy":{"type":"string","max_bytes":128,"enum":["input_v1_bounds"]},"runtime":{"type":"object","properties":{"engine":{"type":"string","max_bytes":128,"enum":["deno"]},"version":{"type":"string","max_bytes":64,"pattern":"^[0-9]+\\.[0-9]+\\.[0-9]+$"},"platform":{"type":"string","max_bytes":64,"pattern":"^[a-z][a-z0-9_]{0,63}$"},"abi":{"type":"string","max_bytes":64,"pattern":"^[a-z][a-z0-9_]{0,63}$"},"protocol":{"type":"integer","minimum":1,"maximum":2147483647}}},"artifact":{"type":"object","properties":{"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":67108864}}},"identities":{"type":"object","properties":{"source":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"validator":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"transform":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"configuration":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"rules":{"type":"array","items":{"type":"object","properties":{"role":{"type":"string","max_bytes":128,"enum":["photo","recording","video_frame","video_audio","raw_video"]},"source_types":{"type":"array","items":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]},"max_items":5},"transform":{"type":"string","max_bytes":128,"enum":["identity_v1","video_frame_v1","initial_audio_v1"]},"target_sample_rate":{"type":"integer","minimum":8000,"maximum":192000,"nullable":true},"preserve_short_video_context":{"type":"boolean","nullable":true},"max_count":{"type":"integer","minimum":1,"maximum":8},"limits":{"type":"object","properties":{"source_bytes":{"type":"integer","minimum":1,"maximum":20971520},"output_bytes":{"type":"integer","minimum":0,"maximum":20971520},"cpu_ms":{"type":"integer","minimum":1,"maximum":300000},"heap_bytes":{"type":"integer","minimum":1,"maximum":1073741824},"wall_ms":{"type":"integer","minimum":1,"maximum":300000}}}}},"max_items":5},"max_sources":{"type":"integer","minimum":1,"maximum":8},"limits":{"type":"object","properties":{"source_bytes":{"type":"integer","minimum":1,"maximum":20971520},"output_bytes":{"type":"integer","minimum":0,"maximum":20971520},"cpu_ms":{"type":"integer","minimum":1,"maximum":300000},"heap_bytes":{"type":"integer","minimum":1,"maximum":1073741824},"wall_ms":{"type":"integer","minimum":1,"maximum":300000}}}}},"qualification":{"type":"object","properties":{"spec_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"evidence_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"harness_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"source_revision":{"type":"string","max_bytes":40,"pattern":"^[0-9a-f]{40}$"}}}}},"retained":{"type":"array","items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":7},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"bytes":{"type":"object","properties":{"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}}}},"max_items":8}}},"digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}}}$json$::JSONB; $schema$;
CREATE FUNCTION internal.checked_initial_preparation_reply(p_value JSONB) RETURNS JSONB LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE shape JSONB; phase INTEGER;
BEGIN
 shape:=internal.initial_preparation_execution_schema()->('reply_'||(p_value->>'outcome'));
 IF shape IS NULL OR octet_length(internal.initial_canonical(p_value))>524288 OR NOT internal.initial_schema_matches(p_value,shape) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF p_value->>'outcome'='status' THEN
  phase:=array_position(ARRAY['allocated','verified','issued','output_registered','outcome_ready'],p_value->>'phase');
  IF (p_value->'source'<>'null'::JSONB)<>(phase>=2) OR (p_value->'execution_reference'<>'null'::JSONB)<>(phase>=3) OR (p_value->'output'<>'null'::JSONB)<>(phase>=4) OR (p_value->'result'<>'null'::JSONB)<>(phase>=5) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 END IF;
 RETURN p_value;
END; $$;
CREATE FUNCTION internal.initial_preparation_execution_digest(p_kind TEXT,p_text TEXT) RETURNS TEXT LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
BEGIN
 IF p_kind IS NULL OR p_kind NOT IN ('source_verification','output_manifest','outcome') OR p_text IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN encode(extensions.digest(convert_to('merian.initial-analysis.preparation-execution.'||p_kind||E'.v1\n'||p_text,'UTF8'),'sha256'),'hex');
END; $$;
CREATE FUNCTION internal.parse_initial_preparation_execution(p_kind TEXT,p_text TEXT) RETURNS JSONB LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE value JSONB; shape JSONB;
BEGIN
 shape:=internal.initial_preparation_execution_schema()->p_kind;
 IF shape IS NULL OR p_text IS NULL OR octet_length(p_text)>131072 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN value:=p_text::JSONB; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF internal.initial_canonical(value) IS DISTINCT FROM p_text OR NOT internal.initial_schema_matches(value,shape) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN value;
END; $$;
ALTER TABLE internal.initial_preparation_source_fences ADD COLUMN provider_barrier TEXT CHECK(provider_barrier='blocked_pre_admission');
ALTER TABLE internal.initial_preparation_source_fences DROP CONSTRAINT initial_preparation_source_fences_execution_state_check;
ALTER TABLE internal.initial_preparation_source_fences ADD CONSTRAINT initial_preparation_execution_state CHECK(execution_state IN ('unissued','issued'));
ALTER TABLE internal.initial_preparation_source_fences ALTER CONSTRAINT initial_preparation_source_fences_scan_id_fkey DEFERRABLE INITIALLY DEFERRED;
CREATE TABLE internal.initial_preparation_source_verifications(
 scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_preparation_intents(scan_id) ON DELETE CASCADE,
 canonical_receipt TEXT NOT NULL CHECK(internal.parse_initial_preparation_execution('source_verification',canonical_receipt) IS NOT NULL),
 digest TEXT NOT NULL CHECK(digest=internal.initial_preparation_execution_digest('source_verification',canonical_receipt))
);
CREATE TABLE internal.initial_preparation_execution_grants(
 scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_preparation_intents(scan_id) ON DELETE CASCADE,
 canonical_grant TEXT NOT NULL CHECK(internal.parse_initial_preparation_execution('grant',canonical_grant) IS NOT NULL)
);
CREATE TABLE internal.initial_preparation_output_manifests(
 scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_preparation_intents(scan_id) ON DELETE CASCADE,
 canonical_request TEXT NOT NULL CHECK(internal.parse_initial_preparation_execution('output_manifest',canonical_request) IS NOT NULL),
 request_digest TEXT NOT NULL CHECK(request_digest=internal.initial_preparation_execution_digest('output_manifest',canonical_request)),
 canonical_resolved TEXT NOT NULL CHECK(internal.parse_initial_preparation_execution('resolved_manifest',canonical_resolved) IS NOT NULL)
);
CREATE TABLE internal.initial_preparation_output_mapping(
 scan_id UUID NOT NULL REFERENCES internal.initial_preparation_output_manifests(scan_id) ON DELETE CASCADE,
 ordinal INTEGER NOT NULL CHECK(ordinal BETWEEN 0 AND 7),
 object_id UUID NOT NULL UNIQUE,
 PRIMARY KEY(scan_id,ordinal),
 FOREIGN KEY(scan_id,object_id) REFERENCES internal.initial_preparation_source_registry(scan_id,object_id)
);
CREATE INDEX initial_preparation_output_registry ON internal.initial_preparation_output_mapping(scan_id,object_id);
CREATE TABLE internal.initial_preparation_outcomes(
 scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_preparation_intents(scan_id) ON DELETE CASCADE,
 canonical_outcome TEXT NOT NULL CHECK(internal.parse_initial_preparation_execution('outcome',canonical_outcome) IS NOT NULL),
 digest TEXT NOT NULL CHECK(digest=internal.initial_preparation_execution_digest('outcome',canonical_outcome))
);
DO $privacy$ DECLARE name TEXT; BEGIN
 FOREACH name IN ARRAY ARRAY['initial_preparation_source_verifications','initial_preparation_execution_grants','initial_preparation_output_manifests','initial_preparation_output_mapping','initial_preparation_outcomes'] LOOP
  EXECUTE format('ALTER TABLE internal.%I ENABLE ROW LEVEL SECURITY',name);
  EXECUTE format('REVOKE ALL ON internal.%I FROM PUBLIC,anon,authenticated,service_role',name);
 END LOOP;
END; $privacy$;

-- A dedicated shared/exclusive admission fence preserves the established owner/
-- ingestion waits. Neither side waits backwards through an existing tuple/FK lock.
-- Reject stale-snapshot isolation: each post-lock query needs current visibility.
CREATE FUNCTION internal.reject_initial_preparation_provider_writer(p_ids UUID[]) RETURNS VOID LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
DECLARE identity UUID;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM unnest(p_ids) u WHERE u IS NOT NULL) THEN RETURN; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 FOREACH identity IN ARRAY ARRAY(SELECT DISTINCT u FROM unnest(p_ids) u WHERE u IS NOT NULL ORDER BY u) LOOP
  IF NOT pg_try_advisory_xact_lock_shared(hashtextextended('merian-initial-preparation-admission:'||identity::TEXT,0::BIGINT)) THEN RAISE EXCEPTION 'initial_analysis_scope_busy' USING ERRCODE='55000'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=ANY(p_ids) AND provider_barrier='blocked_pre_admission') THEN RAISE EXCEPTION 'initial_analysis_preparation_provider_blocked' USING ERRCODE='55000'; END IF;
END; $$;
CREATE FUNCTION internal.guard_initial_preparation_provider_writer() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE current_row JSONB:=to_jsonb(NEW); previous_row JSONB; key TEXT; identities UUID[]:=ARRAY[]::UUID[]; identity_changed BOOLEAN:=TG_OP='INSERT';
BEGIN
 IF TG_OP='UPDATE' THEN previous_row:=to_jsonb(OLD); END IF;
 -- Existing accounting anonymization can erase owner identity, never grant execution.
 IF TG_OP='UPDATE' AND TG_TABLE_NAME='identification_invocations' AND current_row->'user_id'='null'::JSONB AND current_row-'user_id'=previous_row-'user_id' THEN RETURN NEW; END IF;
 FOREACH key IN ARRAY TG_ARGV LOOP
  identity_changed:=identity_changed OR current_row->key IS DISTINCT FROM previous_row->key;
  identities:=array_append(identities,internal.source_child_uuid(current_row->>key));
  IF previous_row IS NOT NULL THEN identities:=array_append(identities,internal.source_child_uuid(previous_row->>key)); END IF;
 END LOOP;
 -- An existing row already excludes fresh allocation under its durable identity.
 -- Settlement/cleanup that cannot introduce a new identity keeps its old contract.
 IF NOT identity_changed THEN RETURN NEW; END IF;
 -- Preserve existing history ingress error identity even though this earlier
 -- trigger must reject the same stale snapshot before its own barrier lookup.
 IF current_setting('transaction_isolation')<>'read committed'
  AND TG_TABLE_NAME IN ('scans','scan_ingestion_jobs','scan_ingestion_intents','observation_analysis_source_bindings','observation_analysis_intents','observation_analysis_results','observation_histories')
  AND EXISTS(SELECT 1 FROM unnest(identities) u WHERE u IS NOT NULL) THEN RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;
 PERFORM internal.reject_initial_preparation_provider_writer(identities);
 RETURN NEW;
END; $$;
DO $writers$ DECLARE relation TEXT; fields TEXT; BEGIN
 FOR relation,fields IN SELECT * FROM (VALUES
 ('internal.ai_quota_reservations','''original_analysis_id'',''request_id'''),
 ('internal.identification_invocations','''scan_id'''),
 ('internal.complimentary_scan_usage','''client_scan_id'''),
 ('public.scans','''id'''),('public.scan_ingestion_jobs','''scan_id'''),('public.scan_ingestion_intents','''scan_id'''),
 ('internal.initial_analysis_submissions','''scan_id'''),('internal.initial_analysis_admissions','''scan_id'''),
 ('internal.initial_analysis_results','''scan_id'''),('internal.initial_analysis_completions','''scan_id'''),
 ('internal.initial_analysis_media_allocation_fences','''scan_id'''),('internal.initial_analysis_media_registry','''scan_id'''),
 ('internal.initial_analysis_media_cohorts','''scan_id'''),('internal.initial_analysis_media_preparations','''scan_id'''),('internal.initial_analysis_media_verifications','''scan_id'''),
 ('internal.observation_histories','''observation_id'''),('internal.observation_analysis_source_bindings','''analysis_id'''),
 ('internal.observation_analysis_intents','''analysis_id'''),('internal.observation_analysis_results','''analysis_id''')
 ) v(r,f) LOOP
  EXECUTE format('CREATE TRIGGER a0_initial_preparation_provider_barrier BEFORE INSERT OR UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_preparation_provider_writer(%s)',relation,fields);
 END LOOP;
END; $writers$;
CREATE FUNCTION internal.guard_initial_preparation_fresh_fence() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.state IS DISTINCT FROM 'allocated' OR NEW.execution_state IS DISTINCT FROM 'unissued' OR NEW.provider_barrier IS DISTINCT FROM 'blocked_pre_admission' THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended('merian-initial-preparation-admission:'||NEW.scan_id::TEXT,0::BIGINT)) THEN RAISE EXCEPTION 'initial_analysis_scope_busy' USING ERRCODE='55000'; END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=NEW.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id)
  OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=NEW.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=NEW.scan_id) THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 PERFORM internal.assert_initial_preparation_unfunded(NULL,NEW.scan_id);
 RETURN NEW;
END; $$;
CREATE TRIGGER initial_preparation_fresh_fence BEFORE INSERT ON internal.initial_preparation_source_fences FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_preparation_fresh_fence();
DO $fresh$ DECLARE definition TEXT; anchor TEXT; BEGIN
 SELECT pg_get_functiondef('internal.create_initial_media_preparation(uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' INSERT INTO internal.initial_preparation_source_fences(scan_id,state) VALUES(p_scan,''allocated'');';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation allocation insertion drift'; END IF;
 definition:=replace(definition,anchor,'');
 anchor:=' INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES(p_scan);';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation global insertion drift'; END IF;
 EXECUTE replace(definition,anchor,' INSERT INTO internal.initial_preparation_source_fences(scan_id,state,provider_barrier) VALUES(p_scan,''allocated'',''blocked_pre_admission'');'||E'\n'||anchor);
END; $fresh$;
CREATE FUNCTION internal.assert_initial_execution_identity(p_scan UUID,p_assignment TEXT,p_value JSONB) RETURNS VOID LANGUAGE PLPGSQL IMMUTABLE SET search_path='' AS $$
BEGIN
 IF p_value->>'scan_id' IS DISTINCT FROM p_scan::TEXT OR p_value->>'assignment_digest' IS DISTINCT FROM p_assignment OR p_value->'version' IS DISTINCT FROM '1'::JSONB THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
END; $$;
CREATE FUNCTION internal.validate_initial_execution_source(p_scan UUID,p_text TEXT) RETURNS VOID LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; value JSONB; a JSONB; profile JSONB; item JSONB; source JSONB; facts JSONB; mapping JSONB; n INTEGER;
BEGIN
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 value:=internal.parse_initial_preparation_execution('source_verification',p_text); a:=saved.canonical_assignment::JSONB;
 SELECT canonical_profile::JSONB INTO STRICT profile FROM internal.initial_preparation_profiles WHERE digest=a#>>'{preparation,profile_digest}';
 PERFORM internal.assert_initial_execution_identity(p_scan,saved.assignment_digest,value);
 IF value->>'profile_digest' IS DISTINCT FROM a#>>'{preparation,profile_digest}' OR value->>'backend_generation' IS DISTINCT FROM a#>>'{preparation,backend_generation}' OR value->>'validator_identity' IS DISTINCT FROM profile#>>'{spec,identities,validator}' OR jsonb_array_length(value->'entries')<>jsonb_array_length(a#>'{preparation,source_mapping}') THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 FOR item,n IN SELECT e,i::INTEGER-1 FROM jsonb_array_elements(value->'entries') WITH ORDINALITY v(e,i) LOOP
  mapping:=a#>ARRAY['preparation','source_mapping',n::TEXT]; source:=mapping->'source'; facts:=item->'facts';
  IF item->>'ordinal' IS DISTINCT FROM n::TEXT OR item->'object_id' IS DISTINCT FROM mapping->'object_id'
   OR item->'bytes' IS DISTINCT FROM jsonb_build_object('byte_count',source->'source_byte_count','sha256',source->'source_sha256','content_type',source->'source_content_type') THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  IF source->>'kind'='image' THEN
   IF facts->'image'='null'::JSONB OR facts->'wav'<>'null'::JSONB OR facts->'mp4'<>'null'::JSONB OR 'image/'||(facts#>>'{image,format}') IS DISTINCT FROM source->>'source_content_type' THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  ELSIF source->>'kind'='audio' THEN
   IF facts->'image'<>'null'::JSONB OR facts->'wav'='null'::JSONB OR facts->'mp4'<>'null'::JSONB OR (facts#>>'{wav,frames}')::BIGINT*(facts#>>'{wav,channels}')::BIGINT*(CASE facts#>>'{wav,format}' WHEN 'pcm16' THEN 2 ELSE 4 END)>(source->>'source_byte_count')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  ELSE
   IF facts->'image'<>'null'::JSONB OR facts->'wav'<>'null'::JSONB OR facts->'mp4'='null'::JSONB THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  END IF;
 END LOOP;
END; $$;
CREATE FUNCTION internal.initial_preparation_cohort_wall(p_assignment JSONB,p_profile JSONB) RETURNS BIGINT LANGUAGE PLPGSQL IMMUTABLE SET search_path='' AS $$
DECLARE wall BIGINT; matched INTEGER;
BEGIN
 SELECT sum((r#>>'{limits,wall_ms}')::BIGINT),count(*) INTO wall,matched
 FROM jsonb_array_elements(p_assignment#>'{preparation,source_mapping}') m
 JOIN jsonb_array_elements(p_profile#>'{spec,rules}') r ON r->>'role'=m->>'role';
 IF matched<>jsonb_array_length(p_assignment#>'{preparation,source_mapping}') OR wall IS NULL OR wall<=0 OR wall>(p_profile#>>'{spec,limits,wall_ms}')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN wall;
END; $$;
CREATE FUNCTION internal.validate_initial_execution_grant(p_scan UUID,p_text TEXT) RETURNS VOID LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; value JSONB; profile JSONB; source_digest TEXT; wall BIGINT; issue BIGINT;
BEGIN
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 value:=internal.parse_initial_preparation_execution('grant',p_text);
 PERFORM internal.assert_initial_execution_identity(p_scan,saved.assignment_digest,value);
 SELECT canonical_profile::JSONB INTO STRICT profile FROM internal.initial_preparation_profiles profile_row WHERE profile_row.digest=saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}';
 SELECT digest INTO STRICT source_digest FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan;
 wall:=internal.initial_preparation_cohort_wall(saved.canonical_assignment::JSONB,profile); issue:=(value->>'issued_at_ms')::BIGINT;
 IF value->>'source_digest' IS DISTINCT FROM source_digest OR value->>'profile_digest' IS DISTINCT FROM saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}' OR value->>'artifact_digest' IS DISTINCT FROM profile#>>'{spec,artifact,sha256}'
  OR (value->>'execution_deadline_ms')::BIGINT<>issue+5000+wall OR (value->>'registration_deadline_ms')::BIGINT<>issue+10000+wall OR (value->>'outcome_deadline_ms')::BIGINT<>issue+45000+wall
  OR issue<floor(extract(epoch FROM saved.created_at)*1000)::BIGINT OR issue+80000+wall>floor(extract(epoch FROM saved.expires_at)*1000)::BIGINT THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
END; $$;
CREATE FUNCTION internal.validate_initial_execution_output(p_scan UUID,p_text TEXT) RETURNS VOID LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; value JSONB; grant_value JSONB; a JSONB; profile JSONB; item JSONB; source JSONB; mapping JSONB; prepared JSONB; rule JSONB; n INTEGER; total BIGINT:=0;
BEGIN
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 value:=internal.parse_initial_preparation_execution('output_manifest',p_text); a:=saved.canonical_assignment::JSONB;
 PERFORM internal.assert_initial_execution_identity(p_scan,saved.assignment_digest,value);
 SELECT canonical_grant::JSONB INTO STRICT grant_value FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan;
 SELECT canonical_profile::JSONB INTO STRICT profile FROM internal.initial_preparation_profiles WHERE digest=a#>>'{preparation,profile_digest}';
 IF value->'grant_id' IS DISTINCT FROM grant_value->'grant_id' OR value->'source_digest' IS DISTINCT FROM grant_value->'source_digest' OR jsonb_array_length(value->'entries')<>jsonb_array_length(a#>'{preparation,source_mapping}') THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 FOR item,n IN SELECT e,i::INTEGER-1 FROM jsonb_array_elements(value->'entries') WITH ORDINALITY v(e,i) LOOP
  mapping:=a#>ARRAY['preparation','source_mapping',n::TEXT]; source:=mapping->'source'; prepared:=item->'prepared';
  IF item->>'ordinal' IS DISTINCT FROM n::TEXT OR ((mapping->>'role'='raw_video') IS DISTINCT FROM (prepared='null'::JSONB)) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  IF prepared='null'::JSONB THEN CONTINUE; END IF;
  SELECT r INTO STRICT rule FROM jsonb_array_elements(profile#>'{spec,rules}') r WHERE r->>'role'=mapping->>'role';
  IF prepared->'transform' IS DISTINCT FROM source->'transform' OR prepared->'parameters' IS DISTINCT FROM source->'transform_parameters'
   OR (prepared#>>'{bytes,byte_count}')::BIGINT>(rule#>>'{limits,output_bytes}')::BIGINT OR prepared#>>'{bytes,content_type}' IS DISTINCT FROM (CASE WHEN source->>'kind'='audio' THEN 'audio/wav' ELSE source->>'source_content_type' END) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  IF (prepared->>'source_identity')::BOOLEAN OR source->>'kind'='image' THEN
   IF prepared->'bytes' IS DISTINCT FROM jsonb_build_object('byte_count',source->'source_byte_count','sha256',source->'source_sha256','content_type',source->'source_content_type') OR NOT (prepared->>'source_identity')::BOOLEAN THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  END IF;
  total:=total+(prepared#>>'{bytes,byte_count}')::BIGINT;
 END LOOP;
 IF total>(profile#>>'{spec,limits,output_bytes}')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
END; $$;
CREATE FUNCTION internal.validate_initial_execution_resolved(p_scan UUID,p_text TEXT) RETURNS VOID LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; output internal.initial_preparation_output_manifests; value JSONB; entries JSONB; item JSONB; prepared JSONB; source_id UUID; n INTEGER; object UUID; seen UUID[]:=ARRAY[]::UUID[];
BEGIN
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 SELECT * INTO STRICT output FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan;
 value:=internal.parse_initial_preparation_execution('resolved_manifest',p_text); entries:=output.canonical_request::JSONB->'entries';
 PERFORM internal.assert_initial_execution_identity(p_scan,saved.assignment_digest,value);
 IF value->>'request_digest' IS DISTINCT FROM output.request_digest OR value->'grant_id' IS DISTINCT FROM output.canonical_request::JSONB->'grant_id' OR jsonb_array_length(value->'entries')<>jsonb_array_length(entries) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 FOR item,n IN SELECT e,i::INTEGER-1 FROM jsonb_array_elements(value->'entries') WITH ORDINALITY v(e,i) LOOP
  prepared:=entries->n->'prepared'; object:=(item->>'object_id')::UUID;
  IF item->>'ordinal' IS DISTINCT FROM n::TEXT OR ((prepared='null'::JSONB) IS DISTINCT FROM (object IS NULL)) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  IF object IS NULL THEN CONTINUE; END IF;
  SELECT object_id INTO STRICT source_id FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan AND ordinal=n;
  IF object=ANY(seen) OR ((prepared->>'source_identity')::BOOLEAN AND object<>source_id) OR (NOT (prepared->>'source_identity')::BOOLEAN AND EXISTS(SELECT 1 FROM internal.initial_preparation_source_mapping WHERE object_id=object)) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  seen:=array_append(seen,object);
 END LOOP;
END; $$;
CREATE FUNCTION internal.validate_initial_execution_outcome(p_scan UUID,p_text TEXT) RETURNS VOID LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; value JSONB; grant_value JSONB; source_value JSONB; output internal.initial_preparation_output_manifests; profile JSONB; retained JSONB;
BEGIN
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 value:=internal.parse_initial_preparation_execution('outcome',p_text); PERFORM internal.assert_initial_execution_identity(p_scan,saved.assignment_digest,value);
 SELECT canonical_grant::JSONB INTO STRICT grant_value FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan;
 SELECT canonical_receipt::JSONB INTO STRICT source_value FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan;
 SELECT * INTO STRICT output FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan;
 SELECT canonical_profile::JSONB INTO STRICT profile FROM internal.initial_preparation_profiles profile_row WHERE profile_row.digest=saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}';
 SELECT COALESCE(jsonb_agg(jsonb_build_object('ordinal',e->'ordinal','object_id',output.canonical_resolved::JSONB#>ARRAY['entries',(i-1)::TEXT,'object_id'],'bytes',e#>'{prepared,bytes}') ORDER BY i),'[]'::JSONB) INTO retained FROM jsonb_array_elements(output.canonical_request::JSONB->'entries') WITH ORDINALITY v(e,i) WHERE e->'prepared'<>'null'::JSONB;
 IF value->'grant' IS DISTINCT FROM grant_value OR value->'source_verification' IS DISTINCT FROM source_value OR value->'output_manifest' IS DISTINCT FROM output.canonical_request::JSONB OR value->'resolved_manifest' IS DISTINCT FROM output.canonical_resolved::JSONB OR value->'profile' IS DISTINCT FROM profile OR value->'retained' IS DISTINCT FROM retained THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
END; $$;
CREATE FUNCTION internal.initial_preparation_execution_coherent(p_scan UUID) RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; fence internal.initial_preparation_source_fences; a JSONB; source_proof TEXT; grant_value TEXT; output internal.initial_preparation_output_manifests; outcome TEXT; item JSONB; n INTEGER; ids UUID[];
BEGIN
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 SELECT * INTO fence FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan;
 IF saved.scan_id IS NULL OR fence.scan_id IS NULL OR fence.state<>'allocated' OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'media_sources' OR NOT internal.valid_initial_media_assignment_pair(saved.canonical_candidate,saved.canonical_assignment) THEN RETURN FALSE; END IF;
 a:=saved.canonical_assignment::JSONB;
 SELECT canonical_receipt INTO source_proof FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan;
 SELECT canonical_grant INTO grant_value FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan;
 SELECT * INTO output FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan;
 SELECT canonical_outcome INTO outcome FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan;
 IF (fence.execution_state='issued') IS DISTINCT FROM (grant_value IS NOT NULL) OR (source_proof IS NULL AND grant_value IS NOT NULL) OR (grant_value IS NULL AND output.scan_id IS NOT NULL) OR (output.scan_id IS NULL AND outcome IS NOT NULL)
  OR (fence.provider_barrier IS NULL AND (source_proof IS NOT NULL OR grant_value IS NOT NULL OR output.scan_id IS NOT NULL OR outcome IS NOT NULL)) THEN RETURN FALSE; END IF;
 IF source_proof IS NOT NULL THEN PERFORM internal.validate_initial_execution_source(p_scan,source_proof); END IF;
 IF grant_value IS NOT NULL THEN PERFORM internal.validate_initial_execution_grant(p_scan,grant_value); END IF;
 IF output.scan_id IS NOT NULL THEN
  PERFORM internal.validate_initial_execution_output(p_scan,output.canonical_request);
  PERFORM internal.validate_initial_execution_resolved(p_scan,output.canonical_resolved);
 END IF;
 IF outcome IS NOT NULL THEN PERFORM internal.validate_initial_execution_outcome(p_scan,outcome); END IF;
 IF (SELECT count(*) FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan)<>jsonb_array_length(a#>'{preparation,source_mapping}') THEN RETURN FALSE; END IF;
 FOR item,n IN SELECT e,i::INTEGER-1 FROM jsonb_array_elements(a#>'{preparation,source_mapping}') WITH ORDINALITY v(e,i) LOOP
  IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan AND ordinal=n AND object_id=(item->>'object_id')::UUID) THEN RETURN FALSE; END IF;
 END LOOP;
 IF (SELECT count(*) FROM internal.initial_preparation_output_mapping WHERE scan_id=p_scan)<>(SELECT count(*) FROM jsonb_array_elements(COALESCE(output.canonical_resolved::JSONB->'entries','[]'::JSONB)) e WHERE e->'object_id'<>'null'::JSONB) THEN RETURN FALSE; END IF;
 FOR item IN SELECT e FROM jsonb_array_elements(COALESCE(output.canonical_resolved::JSONB->'entries','[]'::JSONB)) e WHERE e->'object_id'<>'null'::JSONB LOOP
  IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_output_mapping WHERE scan_id=p_scan AND ordinal=(item->>'ordinal')::INTEGER AND object_id=(item->>'object_id')::UUID) THEN RETURN FALSE; END IF;
 END LOOP;
 SELECT array_agg(object_id ORDER BY object_id) INTO ids FROM (SELECT object_id FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan UNION SELECT object_id FROM internal.initial_preparation_output_mapping WHERE scan_id=p_scan) v;
 IF (SELECT array_agg(object_id ORDER BY object_id) FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan) IS DISTINCT FROM ids
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan AND (backend_generation<>(a#>>'{preparation,backend_generation}')::UUID OR retired OR marker_confirmed OR claim_token IS NOT NULL)) THEN RETURN FALSE; END IF;
 RETURN TRUE;
EXCEPTION WHEN check_violation OR invalid_parameter_value OR no_data_found OR too_many_rows THEN RETURN FALSE;
END; $$;
-- Keep the historical unissued helper's meaning; expanded cohort checks name the new predicate.
CREATE OR REPLACE FUNCTION internal.require_initial_source_cohort() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE identity UUID; candidate TEXT;
BEGIN
 identity:=CASE WHEN TG_OP='DELETE' THEN OLD.scan_id ELSE NEW.scan_id END;
 SELECT canonical_candidate INTO candidate FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;
 IF candidate IS NULL THEN
  IF EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=identity AND state<>'retired') OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=identity AND NOT retired) THEN RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 ELSIF candidate::JSONB->>'variant'='media_sources' THEN
  IF NOT internal.initial_preparation_execution_coherent(identity) THEN RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 ELSIF EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=identity) THEN RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 RETURN NULL;
END; $$;
CREATE FUNCTION internal.can_cancel_initial_preparation(p_owner UUID,p_scan UUID) RETURNS BOOLEAN LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND owner_id=p_owner)
  OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan)
  OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan AND state='allocated' AND provider_barrier='blocked_pre_admission')
  OR NOT internal.initial_preparation_execution_coherent(p_scan) THEN RETURN FALSE; END IF;
 BEGIN PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan); EXCEPTION WHEN invalid_parameter_value THEN RETURN FALSE; END;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_verifications WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN RETURN FALSE; END IF;
 RETURN TRUE;
END; $$;
CREATE FUNCTION internal.lock_initial_preparation_eligibility(p_scan UUID) RETURNS VOID LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
DECLARE a JSONB; pe internal.initial_preparation_profile_eligibility; be internal.initial_preparation_backend_eligibility;
BEGIN
 SELECT canonical_assignment::JSONB INTO STRICT a FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 PERFORM singleton FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO pe FROM internal.initial_preparation_profile_eligibility WHERE profile_digest=a#>>'{preparation,profile_digest}' FOR SHARE NOWAIT;
 SELECT * INTO be FROM internal.initial_preparation_backend_eligibility WHERE generation=(a#>>'{preparation,backend_generation}')::UUID FOR SHARE NOWAIT;
 IF pe.state IS DISTINCT FROM 'eligible' OR be.state IS DISTINCT FROM 'eligible' OR pe.installation_digest IS DISTINCT FROM a#>>'{preparation,installation_digest}' OR be.installation_digest IS DISTINCT FROM a#>>'{preparation,backend_installation_digest}' THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
END; $$;
CREATE FUNCTION internal.guard_initial_preparation_execution_private() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; grant_value JSONB; now_ms BIGINT; issue_ms BIGINT;
BEGIN
 IF TG_OP='DELETE' THEN
  IF EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=OLD.scan_id AND state='retired') THEN RETURN OLD; END IF;
 ELSIF TG_OP='INSERT' THEN
  SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id;
  PERFORM internal.lock_initial_preparation_scope(saved.owner_id,NEW.scan_id);
  PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id FOR UPDATE;
  IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=NEW.scan_id AND state='allocated' AND provider_barrier='blocked_pre_admission') THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
  now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
  IF now_ms>=floor(extract(epoch FROM saved.expires_at)*1000)::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
  SELECT canonical_grant::JSONB INTO grant_value FROM internal.initial_preparation_execution_grants WHERE scan_id=NEW.scan_id;
  IF TG_TABLE_NAME IN ('initial_preparation_source_verifications','initial_preparation_execution_grants') THEN
   PERFORM internal.lock_initial_preparation_eligibility(NEW.scan_id);
   IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=NEW.scan_id AND execution_state='unissued') THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
   IF TG_TABLE_NAME='initial_preparation_source_verifications' THEN PERFORM internal.validate_initial_execution_source(NEW.scan_id,NEW.canonical_receipt);
   ELSE
    PERFORM internal.validate_initial_execution_grant(NEW.scan_id,NEW.canonical_grant);
    issue_ms:=(NEW.canonical_grant::JSONB->>'issued_at_ms')::BIGINT;
    IF issue_ms>now_ms OR issue_ms<now_ms-5000 THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
   END IF;
  ELSE
   IF grant_value IS NULL OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=NEW.scan_id AND execution_state='issued') THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
   IF TG_TABLE_NAME IN ('initial_preparation_output_manifests','initial_preparation_output_mapping') THEN
    IF now_ms>=(grant_value->>'registration_deadline_ms')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
    IF TG_TABLE_NAME='initial_preparation_output_manifests' THEN PERFORM internal.validate_initial_execution_output(NEW.scan_id,NEW.canonical_request); END IF;
   ELSE
    IF now_ms>=(grant_value->>'outcome_deadline_ms')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
    PERFORM internal.validate_initial_execution_outcome(NEW.scan_id,NEW.canonical_outcome);
   END IF;
  END IF;
  RETURN NEW;
 END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END; $$;
DO $private$ DECLARE name TEXT; BEGIN
 FOREACH name IN ARRAY ARRAY['initial_preparation_source_verifications','initial_preparation_execution_grants','initial_preparation_output_manifests','initial_preparation_output_mapping','initial_preparation_outcomes'] LOOP
  EXECUTE format('CREATE TRIGGER guard_initial_execution_private BEFORE INSERT OR UPDATE OR DELETE ON internal.%I FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_preparation_execution_private()',name);
  EXECUTE format('CREATE CONSTRAINT TRIGGER initial_execution_cohort AFTER INSERT OR UPDATE OR DELETE ON internal.%I DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.require_initial_source_cohort()',name);
 END LOOP;
END; $private$;
DO $state$ DECLARE definition TEXT; anchor TEXT; BEGIN
 SELECT pg_get_functiondef('internal.guard_initial_source_storage()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='  IF TG_TABLE_NAME=''initial_preparation_source_fences'' THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation fence guard drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
   IF NEW.provider_barrier IS DISTINCT FROM OLD.provider_barrier THEN RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023'; END IF;
   IF NEW.scan_id=OLD.scan_id AND NEW.state='allocated' AND OLD.state='allocated' AND OLD.execution_state='unissued' AND NEW.execution_state='issued' AND NEW.provider_barrier='blocked_pre_admission'
    AND EXISTS(SELECT 1 FROM internal.initial_preparation_execution_grants WHERE scan_id=NEW.scan_id)
    AND EXISTS(SELECT 1 FROM internal.initial_preparation_source_verifications WHERE scan_id=NEW.scan_id) THEN RETURN NEW; END IF;
$body$);
 -- Replace both media C1 proofs; keep no-media behavior and terminal retirement order.
 SELECT pg_get_functiondef('internal.cancel_initial_analysis(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$   PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
   IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND canonical_candidate::JSONB->>'variant'='media_sources') AND
    (NOT internal.initial_preparation_sources_complete(p_scan) OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan)) THEN
    terminal:='cancelled_unknown';
   ELSE terminal:='cancelled_pre_dispatch'; END IF;$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation cancellation proof drift'; END IF;
 EXECUTE replace(definition,anchor,$body$
   IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND canonical_candidate::JSONB->>'variant'='media_sources') THEN
    terminal:=CASE WHEN internal.can_cancel_initial_preparation(p_owner,p_scan) THEN 'cancelled_pre_dispatch' ELSE 'cancelled_unknown' END;
   ELSE PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan); terminal:='cancelled_pre_dispatch'; END IF;
$body$);
 SELECT pg_get_functiondef('internal.guard_initial_lifecycle_fence()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='(NOT internal.initial_preparation_sources_complete(NEW.scan_id) OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=NEW.scan_id))';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation lifecycle proof drift'; END IF;
 EXECUTE replace(definition,anchor,'NOT internal.can_cancel_initial_preparation((SELECT owner_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id),NEW.scan_id)');
END; $state$;
CREATE FUNCTION internal.initial_preparation_execution_action(p_action TEXT,p_owner UUID,p_scan UUID,p_assignment_digest TEXT,p_text TEXT DEFAULT NULL) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; fence internal.initial_preparation_source_fences; source_proof internal.initial_preparation_source_verifications; grant_value JSONB; output internal.initial_preparation_output_manifests; outcome TEXT; value JSONB; digest TEXT; now_ms BIGINT; expiry_ms BIGINT; wall BIGINT; profile JSONB; resolved JSONB; entries JSONB:='[]'::JSONB; item JSONB; prepared JSONB; object UUID; identity UUID; backend UUID; n INTEGER;
BEGIN
 PERFORM internal.require_service_role();
 IF p_action IS NULL OR p_action NOT IN ('sources','issue','output','outcome','status') OR p_owner IS NULL OR p_scan IS NULL OR p_assignment_digest IS NULL OR p_assignment_digest !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','missing'); END IF;
 IF saved.owner_id IS DISTINCT FROM p_owner OR saved.assignment_digest IS DISTINCT FROM p_assignment_digest THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT; expiry_ms:=floor(extract(epoch FROM saved.expires_at)*1000)::BIGINT;
 IF now_ms>=expiry_ms THEN PERFORM internal.cancel_initial_analysis(p_owner,p_scan); RETURN jsonb_build_object('version',1,'outcome','held','reason','expired'); END IF;
 SELECT * INTO fence FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan;
 IF NOT internal.initial_preparation_execution_coherent(p_scan) THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','incoherent'); END IF;
 SELECT * INTO source_proof FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan;
 SELECT canonical_grant::JSONB INTO grant_value FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan;
 SELECT * INTO output FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan;
 SELECT canonical_outcome INTO outcome FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan;
 IF p_action='status' THEN
  RETURN jsonb_build_object('version',1,'outcome','status','phase',CASE WHEN outcome IS NOT NULL THEN 'outcome_ready' WHEN output.scan_id IS NOT NULL THEN 'output_registered' WHEN grant_value IS NOT NULL THEN 'issued' WHEN source_proof.scan_id IS NOT NULL THEN 'verified' ELSE 'allocated' END,
   'source',source_proof.canonical_receipt::JSONB,'execution_reference',CASE WHEN grant_value IS NOT NULL THEN jsonb_build_object('grant_id',grant_value->'grant_id','source_digest',grant_value->'source_digest') END,'output',CASE WHEN output.scan_id IS NOT NULL THEN jsonb_build_object('request',output.canonical_request::JSONB,'resolved',output.canonical_resolved::JSONB) END,'result',outcome::JSONB,'server_now_ms',now_ms,'expires_at_ms',expiry_ms);
 END IF;
 IF fence.provider_barrier IS DISTINCT FROM 'blocked_pre_admission' OR NOT internal.can_cancel_initial_preparation(p_owner,p_scan) THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','incoherent'); END IF;
 IF p_action='sources' THEN
  PERFORM internal.validate_initial_execution_source(p_scan,p_text);
  IF source_proof.scan_id IS NOT NULL THEN
   IF source_proof.canonical_receipt IS DISTINCT FROM p_text THEN RAISE EXCEPTION 'initial_analysis_conflict' USING ERRCODE='23505'; END IF;
  ELSE
   PERFORM internal.lock_initial_preparation_eligibility(p_scan);
   IF fence.execution_state<>'unissued' THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','preparation_issued'); END IF;
   INSERT INTO internal.initial_preparation_source_verifications(scan_id,canonical_receipt,digest) VALUES(p_scan,p_text,internal.initial_preparation_execution_digest('source_verification',p_text));
  END IF;
  RETURN jsonb_build_object('version',1,'outcome','verified','receipt',p_text::JSONB,'digest',internal.initial_preparation_execution_digest('source_verification',p_text));
 ELSIF p_action='issue' THEN
  IF fence.execution_state='issued' THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','preparation_issued'); END IF;
  IF source_proof.scan_id IS NULL OR source_proof.digest IS DISTINCT FROM p_text THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','missing'); END IF;
  PERFORM internal.lock_initial_preparation_eligibility(p_scan);
  SELECT canonical_profile::JSONB INTO STRICT profile FROM internal.initial_preparation_profiles profile_row WHERE profile_row.digest=saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}';
  wall:=internal.initial_preparation_cohort_wall(saved.canonical_assignment::JSONB,profile); now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
  IF now_ms+80000+wall>=expiry_ms THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','budget'); END IF;
  grant_value:=jsonb_build_object('version',1,'scan_id',p_scan,'assignment_digest',p_assignment_digest,'grant_id',gen_random_uuid(),'source_digest',source_proof.digest,'profile_digest',saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}','artifact_digest',profile#>>'{spec,artifact,sha256}',
   'issued_at_ms',now_ms,'execution_deadline_ms',now_ms+5000+wall,'registration_deadline_ms',now_ms+10000+wall,'outcome_deadline_ms',now_ms+45000+wall);
  INSERT INTO internal.initial_preparation_execution_grants(scan_id,canonical_grant) VALUES(p_scan,internal.initial_canonical(grant_value));
  UPDATE internal.initial_preparation_source_fences SET execution_state='issued' WHERE scan_id=p_scan;
  RETURN jsonb_build_object('version',1,'outcome','granted','grant',grant_value,'server_now_ms',floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT,'expires_at_ms',expiry_ms);
 ELSIF p_action='output' THEN
  PERFORM internal.validate_initial_execution_output(p_scan,p_text);
  IF output.scan_id IS NOT NULL THEN
   IF output.canonical_request IS DISTINCT FROM p_text THEN RAISE EXCEPTION 'initial_analysis_conflict' USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('version',1,'outcome','registered','request',output.canonical_request::JSONB,'resolved',output.canonical_resolved::JSONB);
  END IF;
  IF grant_value IS NULL OR floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT>=(grant_value->>'registration_deadline_ms')::BIGINT THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','phase_expired'); END IF;
  value:=p_text::JSONB; digest:=internal.initial_preparation_execution_digest('output_manifest',p_text);
  FOR item,n IN SELECT e,i::INTEGER-1 FROM jsonb_array_elements(value->'entries') WITH ORDINALITY v(e,i) LOOP
   prepared:=item->'prepared'; object:=NULL;
   IF prepared<>'null'::JSONB THEN
    IF (prepared->>'source_identity')::BOOLEAN THEN SELECT object_id INTO STRICT object FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan AND ordinal=n; ELSE object:=gen_random_uuid(); END IF;
   END IF;
   entries:=entries||jsonb_build_array(jsonb_build_object('ordinal',n,'object_id',object));
  END LOOP;
  resolved:=jsonb_build_object('version',1,'scan_id',p_scan,'assignment_digest',p_assignment_digest,'grant_id',grant_value->'grant_id','request_digest',digest,'entries',entries);
  INSERT INTO internal.initial_preparation_output_manifests(scan_id,canonical_request,request_digest,canonical_resolved) VALUES(p_scan,p_text,digest,internal.initial_canonical(resolved));
  backend:=(saved.canonical_assignment::JSONB#>>'{preparation,backend_generation}')::UUID;
  FOR identity IN SELECT id FROM (SELECT object_id id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan UNION SELECT (e->>'object_id')::UUID FROM jsonb_array_elements(entries) e WHERE e->>'object_id' IS NOT NULL) v ORDER BY id LOOP
   PERFORM object_id FROM internal.initial_preparation_source_registry WHERE object_id=identity FOR UPDATE;
   IF NOT FOUND THEN INSERT INTO internal.initial_preparation_source_registry(object_id,scan_id,backend_generation) VALUES(identity,p_scan,backend);
   ELSIF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE object_id=identity AND scan_id=p_scan AND backend_generation=backend AND NOT retired) THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
  END LOOP;
  FOR item IN SELECT e FROM jsonb_array_elements(entries) e WHERE e->>'object_id' IS NOT NULL ORDER BY (e->>'object_id')::UUID LOOP
   INSERT INTO internal.initial_preparation_output_mapping(scan_id,ordinal,object_id) VALUES(p_scan,(item->>'ordinal')::INTEGER,(item->>'object_id')::UUID);
  END LOOP;
  RETURN jsonb_build_object('version',1,'outcome','registered','request',value,'resolved',resolved);
 ELSE
  PERFORM internal.validate_initial_execution_outcome(p_scan,p_text);
  IF outcome IS NOT NULL THEN
   IF outcome IS DISTINCT FROM p_text THEN RAISE EXCEPTION 'initial_analysis_conflict' USING ERRCODE='23505'; END IF;
  ELSE
   IF floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT>=(grant_value->>'outcome_deadline_ms')::BIGINT THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','phase_expired'); END IF;
   INSERT INTO internal.initial_preparation_outcomes(scan_id,canonical_outcome,digest) VALUES(p_scan,p_text,internal.initial_preparation_execution_digest('outcome',p_text));
  END IF;
  RETURN jsonb_build_object('version',1,'outcome','outcome_ready','result',p_text::JSONB,'digest',internal.initial_preparation_execution_digest('outcome',p_text));
 END IF;
END; $$;
CREATE FUNCTION public.settle_initial_preparation_sources(p_owner UUID,p_scan UUID,p_assignment_digest TEXT,p_receipt TEXT) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$ BEGIN PERFORM internal.require_service_role(); RETURN internal.checked_initial_preparation_reply(internal.initial_preparation_execution_action('sources',p_owner,p_scan,p_assignment_digest,p_receipt)); END; $$;
CREATE FUNCTION public.issue_initial_preparation_execution(p_owner UUID,p_scan UUID,p_assignment_digest TEXT,p_source_digest TEXT) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$ BEGIN PERFORM internal.require_service_role(); RETURN internal.checked_initial_preparation_reply(internal.initial_preparation_execution_action('issue',p_owner,p_scan,p_assignment_digest,p_source_digest)); END; $$;
CREATE FUNCTION public.register_initial_preparation_output(p_owner UUID,p_scan UUID,p_assignment_digest TEXT,p_manifest TEXT) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$ BEGIN PERFORM internal.require_service_role(); RETURN internal.checked_initial_preparation_reply(internal.initial_preparation_execution_action('output',p_owner,p_scan,p_assignment_digest,p_manifest)); END; $$;
CREATE FUNCTION public.settle_initial_preparation_outcome(p_owner UUID,p_scan UUID,p_assignment_digest TEXT,p_outcome TEXT) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$ BEGIN PERFORM internal.require_service_role(); RETURN internal.checked_initial_preparation_reply(internal.initial_preparation_execution_action('outcome',p_owner,p_scan,p_assignment_digest,p_outcome)); END; $$;
CREATE FUNCTION public.get_initial_preparation_execution_status(p_owner UUID,p_scan UUID,p_assignment_digest TEXT) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$ BEGIN PERFORM internal.require_service_role(); RETURN internal.checked_initial_preparation_reply(internal.initial_preparation_execution_action('status',p_owner,p_scan,p_assignment_digest)); END; $$;
DO $entry$ DECLARE definition TEXT; anchor TEXT; BEGIN
 SELECT pg_get_functiondef('internal.initial_media_preparation_response(uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='internal.initial_preparation_sources_complete(p_scan)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial preparation metadata recovery drift'; END IF;
 EXECUTE replace(definition,anchor,'internal.initial_preparation_execution_coherent(p_scan)');
 SELECT pg_get_functiondef('internal.lock_initial_media_scope(uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(''merian-scan-ingestion:''||p_scan::TEXT,0::BIGINT));';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial M1/M2 barrier scope drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n PERFORM internal.reject_initial_preparation_provider_writer(ARRAY[p_scan]);');
 SELECT pg_get_functiondef('internal.guard_initial_lifecycle_fence()'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' IF TG_OP=''INSERT'' THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial C1 raw scope drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
  IF NEW.state='cancelled_pre_dispatch' AND EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id AND canonical_candidate::JSONB->>'variant'='media_sources') THEN
   PERFORM internal.lock_initial_preparation_scope((SELECT owner_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id),NEW.scan_id);
   PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id FOR UPDATE;
  END IF;
$body$);
END; $entry$;
DO $grants$ DECLARE signature TEXT; BEGIN
 FOREACH signature IN ARRAY ARRAY['public.settle_initial_preparation_sources(uuid,uuid,text,text)','public.issue_initial_preparation_execution(uuid,uuid,text,text)','public.register_initial_preparation_output(uuid,uuid,text,text)','public.settle_initial_preparation_outcome(uuid,uuid,text,text)','public.get_initial_preparation_execution_status(uuid,uuid,text)'] LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',signature);
  INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES('service_role',signature,'Inactive original preparation proof, sole grant or exact known-result recovery; never provider authority');
 END LOOP;
 FOREACH signature IN ARRAY ARRAY['internal.checked_initial_preparation_reply(jsonb)','internal.initial_preparation_cohort_wall(jsonb,jsonb)','internal.initial_preparation_execution_schema()','internal.initial_preparation_execution_digest(text,text)','internal.parse_initial_preparation_execution(text,text)','internal.reject_initial_preparation_provider_writer(uuid[])','internal.guard_initial_preparation_provider_writer()','internal.guard_initial_preparation_fresh_fence()','internal.assert_initial_execution_identity(uuid,text,jsonb)','internal.validate_initial_execution_source(uuid,text)','internal.validate_initial_execution_grant(uuid,text)','internal.validate_initial_execution_output(uuid,text)','internal.validate_initial_execution_resolved(uuid,text)','internal.validate_initial_execution_outcome(uuid,text)','internal.initial_preparation_execution_coherent(uuid)','internal.can_cancel_initial_preparation(uuid,uuid)','internal.lock_initial_preparation_eligibility(uuid)','internal.guard_initial_preparation_execution_private()','internal.initial_preparation_execution_action(text,uuid,uuid,text,text)'] LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',signature);
 END LOOP;
END; $grants$;
COMMENT ON COLUMN internal.initial_preparation_source_fences.provider_barrier IS 'Fresh-only immutable provider prohibition; no backfill, grant, funding or external in-flight execution claim. Erasure retains only this content-free fence.';
COMMENT ON TABLE internal.initial_preparation_outcomes IS 'Private immutable full preparation evidence, erased before scan/account terminal completion. Synthetic adapters only; no media admission, storage qualification or provider dispatch.';
RESET statement_timeout;
RESET lock_timeout;
