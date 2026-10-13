-- Synthetic preparation fixture mirrors initial_preparation_execution.sql; all changes roll back.
\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.admission_owner(owner_id UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT||'@example.invalid','{}','{}',NOW(),NOW());
 INSERT INTO public.user_adult_eligibility_receipts(id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'self_attestation','Synthetic adult attestation','ios','1.0.3','275');
 INSERT INTO public.user_terms_acceptance_receipts(id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'Synthetic terms acceptance','ios','1.0.3','275');
 INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'google_gemini','2026-08-03.1','granted',NOW(),'Synthetic disclosure','Synthetic agreement','ios','1.0.3','275');
END;
$$;
CREATE TEMP TABLE media_vectors AS SELECT value v,ordinality i FROM jsonb_array_elements($vectors$[{"name":"Vision with description","candidate":{"version":2,"variant":"media_sources","source_plan":{"schema_version":1,"route":"identify","ordered_descriptions":["Synthetic photo context"],"owner_timeline":[{"kind":"media","index":0},{"kind":"description","index":0}],"capture":{"has_video":false,"video_clip_count":0,"declared_video_frame_count":0,"video_inference_frame_count":0},"context":{"depth_scale_text":null,"semantic_location":null,"weather_condition":null,"device_locale":null,"device_time_zone":null,"device_region":null,"time_of_day":null,"gps_latitude":null,"gps_longitude":null,"gps_elevation":null,"zoom_factor":null,"estimated_size_cm":null,"weather_temperature_f":null,"current_month":null},"options":{"timestamp":null,"geoprivacy":"private","public_location_label":null,"preferred_goal":null,"observation_context":null},"admission":{"client_protocol":3,"identification_protocol":6,"expected_processor_permission":"google_gemini"},"experiment":null,"sources":[{"kind":"image","source_content_type":"image/png","source_byte_count":68,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":0,"clip_index":null,"frame_index":null,"focus_region":null,"transform":"identity_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}}]}},"profile":{"version":1,"spec":{"profile_id":"synthetic_test_only_0","profile_version":1,"input_profile":"vision_compat_v1","route":"identify","focus_policy":"input_v1_bounds","runtime":{"engine":"deno","version":"2.9.4","platform":"synthetic","abi":"test_only","protocol":1},"artifact":{"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byte_count":1},"identities":{"source":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","validator":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","transform":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","configuration":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"rules":[{"role":"photo","source_types":["image/png"],"transform":"identity_v1","target_sample_rate":null,"preserve_short_video_context":null,"max_count":5,"limits":{"source_bytes":5242880,"output_bytes":5242880,"cpu_ms":1000,"heap_bytes":1048576,"wall_ms":2000}}],"max_sources":8,"limits":{"source_bytes":20971520,"output_bytes":20971520,"cpu_ms":300000,"heap_bytes":1073741824,"wall_ms":300000}},"qualification":{"spec_digest":"666bf85d4996eab1ac4a393a376f0b78030820833951eea482eb4ab1c0e2d4e3","evidence_digest":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","harness_digest":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","source_revision":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}},"profile_canonical":"{\"qualification\":{\"evidence_digest\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"harness_digest\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"source_revision\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"spec_digest\":\"666bf85d4996eab1ac4a393a376f0b78030820833951eea482eb4ab1c0e2d4e3\"},\"spec\":{\"artifact\":{\"byte_count\":1,\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"focus_policy\":\"input_v1_bounds\",\"identities\":{\"configuration\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"source\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"transform\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"validator\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"input_profile\":\"vision_compat_v1\",\"limits\":{\"cpu_ms\":300000,\"heap_bytes\":1073741824,\"output_bytes\":20971520,\"source_bytes\":20971520,\"wall_ms\":300000},\"max_sources\":8,\"profile_id\":\"synthetic_test_only_0\",\"profile_version\":1,\"route\":\"identify\",\"rules\":[{\"limits\":{\"cpu_ms\":1000,\"heap_bytes\":1048576,\"output_bytes\":5242880,\"source_bytes\":5242880,\"wall_ms\":2000},\"max_count\":5,\"preserve_short_video_context\":null,\"role\":\"photo\",\"source_types\":[\"image/png\"],\"target_sample_rate\":null,\"transform\":\"identity_v1\"}],\"runtime\":{\"abi\":\"test_only\",\"engine\":\"deno\",\"platform\":\"synthetic\",\"protocol\":1,\"version\":\"2.9.4\"}},\"version\":1}","profile_digest":"7c07c47c47b6937699ea6d67b112bc7e83cde59546c0a237dd9b499fa4dffcf7","assignment":{"version":2,"candidate_digest":"3cc7181684bf006e6a7c6d84f789123d52e443834851661ccfd2401525a89e3f","route":"identify","operation":"scan_identification","effective_plan":"pro_complimentary","effective_tier":"pro","flash_fallback_used":false,"quota_model":"gemini-2.5-pro","policy_version":1,"provider":"gemini","binding":"gemini_baseline_v1","processor_permission":"google_gemini","input_profile":"vision_compat_v1","provider_model":null,"effective_model":"gemini-2.5-pro","minimum_client_protocol":0,"accepted_client_protocol":3,"minimum_identification_protocol":0,"accepted_identification_protocol":6,"asset_manifest_digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_owner":"initial_engine_release_archive","resolver_id":"git_blob_sha256_v1","preparation":{"kind":"media_sources","profile_digest":"7c07c47c47b6937699ea6d67b112bc7e83cde59546c0a237dd9b499fa4dffcf7","installation_digest":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","backend_installation_digest":"1111111111111111111111111111111111111111111111111111111111111111","selector_generation":"00000000-0000-4000-8000-000000000001","backend_generation":"00000000-0000-4000-8000-00000000b001","source_mapping":[{"ordinal":0,"source":{"kind":"image","source_content_type":"image/png","source_byte_count":68,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":0,"clip_index":null,"frame_index":null,"focus_region":null,"transform":"identity_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}},"role":"photo","object_id":"00000000-0000-4000-8000-000000001000","prepared_destination":null}]},"experiment":null,"variant":"media_sources","source_plan_digest":"8151351142c9547b5a50c7229c7181d35b1efc25971acb9d5e7aedaa8f3b04fd"},"assignment_canonical":"{\"accepted_client_protocol\":3,\"accepted_identification_protocol\":6,\"asset_manifest_digest\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"binding\":\"gemini_baseline_v1\",\"candidate_digest\":\"3cc7181684bf006e6a7c6d84f789123d52e443834851661ccfd2401525a89e3f\",\"effective_model\":\"gemini-2.5-pro\",\"effective_plan\":\"pro_complimentary\",\"effective_tier\":\"pro\",\"experiment\":null,\"flash_fallback_used\":false,\"input_profile\":\"vision_compat_v1\",\"minimum_client_protocol\":0,\"minimum_identification_protocol\":0,\"operation\":\"scan_identification\",\"policy_version\":1,\"preparation\":{\"backend_generation\":\"00000000-0000-4000-8000-00000000b001\",\"backend_installation_digest\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"installation_digest\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"kind\":\"media_sources\",\"profile_digest\":\"7c07c47c47b6937699ea6d67b112bc7e83cde59546c0a237dd9b499fa4dffcf7\",\"selector_generation\":\"00000000-0000-4000-8000-000000000001\",\"source_mapping\":[{\"object_id\":\"00000000-0000-4000-8000-000000001000\",\"ordinal\":0,\"prepared_destination\":null,\"role\":\"photo\",\"source\":{\"clip_index\":null,\"focus_region\":null,\"frame_index\":null,\"input_index\":0,\"kind\":\"image\",\"prepared_output\":{\"state\":\"unresolved\"},\"source_byte_count\":68,\"source_content_type\":\"image/png\",\"source_index\":0,\"source_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"transform\":\"identity_v1\",\"transform_parameters\":null}}]},\"processor_permission\":\"google_gemini\",\"provider\":\"gemini\",\"provider_model\":null,\"quota_model\":\"gemini-2.5-pro\",\"resolver_id\":\"git_blob_sha256_v1\",\"retention_owner\":\"initial_engine_release_archive\",\"route\":\"identify\",\"source_plan_digest\":\"8151351142c9547b5a50c7229c7181d35b1efc25971acb9d5e7aedaa8f3b04fd\",\"variant\":\"media_sources\",\"version\":2}","assignment_digest":"59aea56d4794f4c0ee864140dbc6245efb396777a7a37f7638617eb1dcd4f7a0"},{"name":"Multimodal photo","candidate":{"version":2,"variant":"media_sources","source_plan":{"schema_version":1,"route":"identify-multimodal","ordered_descriptions":["First synthetic context","Second synthetic context"],"owner_timeline":[{"kind":"description","index":0},{"kind":"media","index":0},{"kind":"description","index":1}],"capture":{"has_video":false,"video_clip_count":0,"declared_video_frame_count":0,"video_inference_frame_count":0},"context":{"depth_scale_text":null,"semantic_location":null,"weather_condition":null,"device_locale":null,"device_time_zone":null,"device_region":null,"time_of_day":null,"gps_latitude":null,"gps_longitude":null,"gps_elevation":null,"zoom_factor":null,"estimated_size_cm":null,"weather_temperature_f":null,"current_month":null},"options":{"timestamp":null,"geoprivacy":"private","public_location_label":null,"preferred_goal":null,"observation_context":null},"admission":{"client_protocol":3,"identification_protocol":6,"expected_processor_permission":"google_gemini"},"experiment":null,"sources":[{"kind":"image","source_content_type":"image/png","source_byte_count":68,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":0,"clip_index":null,"frame_index":null,"focus_region":null,"transform":"identity_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}}]}},"profile":{"version":1,"spec":{"profile_id":"synthetic_test_only_1","profile_version":1,"input_profile":"multimodal_photo_v1","route":"identify-multimodal","focus_policy":"input_v1_bounds","runtime":{"engine":"deno","version":"2.9.4","platform":"synthetic","abi":"test_only","protocol":1},"artifact":{"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byte_count":1},"identities":{"source":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","validator":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","transform":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","configuration":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"rules":[{"role":"photo","source_types":["image/png"],"transform":"identity_v1","target_sample_rate":null,"preserve_short_video_context":null,"max_count":5,"limits":{"source_bytes":5242880,"output_bytes":5242880,"cpu_ms":1000,"heap_bytes":1048576,"wall_ms":2000}}],"max_sources":8,"limits":{"source_bytes":20971520,"output_bytes":20971520,"cpu_ms":300000,"heap_bytes":1073741824,"wall_ms":300000}},"qualification":{"spec_digest":"ae4c5e0e86673b0f74d1e28e1a1316e7aa94df26af2f953618ac4385f36ab18f","evidence_digest":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","harness_digest":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","source_revision":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}},"profile_canonical":"{\"qualification\":{\"evidence_digest\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"harness_digest\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"source_revision\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"spec_digest\":\"ae4c5e0e86673b0f74d1e28e1a1316e7aa94df26af2f953618ac4385f36ab18f\"},\"spec\":{\"artifact\":{\"byte_count\":1,\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"focus_policy\":\"input_v1_bounds\",\"identities\":{\"configuration\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"source\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"transform\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"validator\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"input_profile\":\"multimodal_photo_v1\",\"limits\":{\"cpu_ms\":300000,\"heap_bytes\":1073741824,\"output_bytes\":20971520,\"source_bytes\":20971520,\"wall_ms\":300000},\"max_sources\":8,\"profile_id\":\"synthetic_test_only_1\",\"profile_version\":1,\"route\":\"identify-multimodal\",\"rules\":[{\"limits\":{\"cpu_ms\":1000,\"heap_bytes\":1048576,\"output_bytes\":5242880,\"source_bytes\":5242880,\"wall_ms\":2000},\"max_count\":5,\"preserve_short_video_context\":null,\"role\":\"photo\",\"source_types\":[\"image/png\"],\"target_sample_rate\":null,\"transform\":\"identity_v1\"}],\"runtime\":{\"abi\":\"test_only\",\"engine\":\"deno\",\"platform\":\"synthetic\",\"protocol\":1,\"version\":\"2.9.4\"}},\"version\":1}","profile_digest":"335b929ad85d254e6cc9115392d3fd9c1a04180e0b24edf252de03c910a4acf7","assignment":{"version":2,"candidate_digest":"f9cd42d5f45f8abc6d0d2bfbfde6ebd4ddcf1b4dca206887a62920134e1a30f4","route":"identify-multimodal","operation":"scan_identification","effective_plan":"pro_complimentary","effective_tier":"pro","flash_fallback_used":false,"quota_model":"gemini-2.5-pro","policy_version":1,"provider":"gemini","binding":"gemini_baseline_v1","processor_permission":"google_gemini","input_profile":"multimodal_photo_v1","provider_model":null,"effective_model":"gemini-2.5-pro","minimum_client_protocol":0,"accepted_client_protocol":3,"minimum_identification_protocol":0,"accepted_identification_protocol":6,"asset_manifest_digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_owner":"initial_engine_release_archive","resolver_id":"git_blob_sha256_v1","preparation":{"kind":"media_sources","profile_digest":"335b929ad85d254e6cc9115392d3fd9c1a04180e0b24edf252de03c910a4acf7","installation_digest":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","backend_installation_digest":"1111111111111111111111111111111111111111111111111111111111111111","selector_generation":"00000000-0000-4000-8000-000000000002","backend_generation":"00000000-0000-4000-8000-00000000b001","source_mapping":[{"ordinal":0,"source":{"kind":"image","source_content_type":"image/png","source_byte_count":68,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":0,"clip_index":null,"frame_index":null,"focus_region":null,"transform":"identity_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}},"role":"photo","object_id":"00000000-0000-4000-8000-000000001010","prepared_destination":null}]},"experiment":null,"variant":"media_sources","source_plan_digest":"351be2df44dafc1e1575c81e60b9a8a65810706eb4f22ba8f9e547dc00fcb2e6"},"assignment_canonical":"{\"accepted_client_protocol\":3,\"accepted_identification_protocol\":6,\"asset_manifest_digest\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"binding\":\"gemini_baseline_v1\",\"candidate_digest\":\"f9cd42d5f45f8abc6d0d2bfbfde6ebd4ddcf1b4dca206887a62920134e1a30f4\",\"effective_model\":\"gemini-2.5-pro\",\"effective_plan\":\"pro_complimentary\",\"effective_tier\":\"pro\",\"experiment\":null,\"flash_fallback_used\":false,\"input_profile\":\"multimodal_photo_v1\",\"minimum_client_protocol\":0,\"minimum_identification_protocol\":0,\"operation\":\"scan_identification\",\"policy_version\":1,\"preparation\":{\"backend_generation\":\"00000000-0000-4000-8000-00000000b001\",\"backend_installation_digest\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"installation_digest\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"kind\":\"media_sources\",\"profile_digest\":\"335b929ad85d254e6cc9115392d3fd9c1a04180e0b24edf252de03c910a4acf7\",\"selector_generation\":\"00000000-0000-4000-8000-000000000002\",\"source_mapping\":[{\"object_id\":\"00000000-0000-4000-8000-000000001010\",\"ordinal\":0,\"prepared_destination\":null,\"role\":\"photo\",\"source\":{\"clip_index\":null,\"focus_region\":null,\"frame_index\":null,\"input_index\":0,\"kind\":\"image\",\"prepared_output\":{\"state\":\"unresolved\"},\"source_byte_count\":68,\"source_content_type\":\"image/png\",\"source_index\":0,\"source_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"transform\":\"identity_v1\",\"transform_parameters\":null}}]},\"processor_permission\":\"google_gemini\",\"provider\":\"gemini\",\"provider_model\":null,\"quota_model\":\"gemini-2.5-pro\",\"resolver_id\":\"git_blob_sha256_v1\",\"retention_owner\":\"initial_engine_release_archive\",\"route\":\"identify-multimodal\",\"source_plan_digest\":\"351be2df44dafc1e1575c81e60b9a8a65810706eb4f22ba8f9e547dc00fcb2e6\",\"variant\":\"media_sources\",\"version\":2}","assignment_digest":"84cd1f19f9dd532e3a41d6a2f3a6c4cff78cd9448c837a0557e6a8c920e7a255"},{"name":"Multimodal audio","candidate":{"version":2,"variant":"media_sources","source_plan":{"schema_version":1,"route":"identify-multimodal","ordered_descriptions":["First synthetic context","Second synthetic context"],"owner_timeline":[{"kind":"description","index":0},{"kind":"media","index":0},{"kind":"description","index":1}],"capture":{"has_video":false,"video_clip_count":0,"declared_video_frame_count":0,"video_inference_frame_count":0},"context":{"depth_scale_text":null,"semantic_location":null,"weather_condition":null,"device_locale":null,"device_time_zone":null,"device_region":null,"time_of_day":null,"gps_latitude":null,"gps_longitude":null,"gps_elevation":null,"zoom_factor":null,"estimated_size_cm":null,"weather_temperature_f":null,"current_month":null},"options":{"timestamp":null,"geoprivacy":"private","public_location_label":null,"preferred_goal":null,"observation_context":null},"admission":{"client_protocol":3,"identification_protocol":6,"expected_processor_permission":"google_gemini"},"experiment":null,"sources":[{"kind":"audio","source_content_type":"audio/wav","source_byte_count":32044,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":0,"clip_index":null,"frame_index":null,"focus_region":null,"transform":"initial_audio_v1","transform_parameters":{"target_sample_rate":16000,"preserve_short_video_context":false},"prepared_output":{"state":"unresolved"}}]}},"profile":{"version":1,"spec":{"profile_id":"synthetic_test_only_2","profile_version":1,"input_profile":"multimodal_audio_v1","route":"identify-multimodal","focus_policy":"input_v1_bounds","runtime":{"engine":"deno","version":"2.9.4","platform":"synthetic","abi":"test_only","protocol":1},"artifact":{"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byte_count":1},"identities":{"source":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","validator":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","transform":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","configuration":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"rules":[{"role":"recording","source_types":["audio/wav"],"transform":"initial_audio_v1","target_sample_rate":16000,"preserve_short_video_context":false,"max_count":2,"limits":{"source_bytes":2700000,"output_bytes":2700000,"cpu_ms":1000,"heap_bytes":1048576,"wall_ms":2000}}],"max_sources":8,"limits":{"source_bytes":20971520,"output_bytes":20971520,"cpu_ms":300000,"heap_bytes":1073741824,"wall_ms":300000}},"qualification":{"spec_digest":"d878400bcc6ec4fa7943c574ef7159367b326d0f8d1fa269fb3910853b5c614c","evidence_digest":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","harness_digest":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","source_revision":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}},"profile_canonical":"{\"qualification\":{\"evidence_digest\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"harness_digest\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"source_revision\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"spec_digest\":\"d878400bcc6ec4fa7943c574ef7159367b326d0f8d1fa269fb3910853b5c614c\"},\"spec\":{\"artifact\":{\"byte_count\":1,\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"focus_policy\":\"input_v1_bounds\",\"identities\":{\"configuration\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"source\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"transform\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"validator\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"input_profile\":\"multimodal_audio_v1\",\"limits\":{\"cpu_ms\":300000,\"heap_bytes\":1073741824,\"output_bytes\":20971520,\"source_bytes\":20971520,\"wall_ms\":300000},\"max_sources\":8,\"profile_id\":\"synthetic_test_only_2\",\"profile_version\":1,\"route\":\"identify-multimodal\",\"rules\":[{\"limits\":{\"cpu_ms\":1000,\"heap_bytes\":1048576,\"output_bytes\":2700000,\"source_bytes\":2700000,\"wall_ms\":2000},\"max_count\":2,\"preserve_short_video_context\":false,\"role\":\"recording\",\"source_types\":[\"audio/wav\"],\"target_sample_rate\":16000,\"transform\":\"initial_audio_v1\"}],\"runtime\":{\"abi\":\"test_only\",\"engine\":\"deno\",\"platform\":\"synthetic\",\"protocol\":1,\"version\":\"2.9.4\"}},\"version\":1}","profile_digest":"2e69c3628e3ffc031742849d45f82c86610dc5d776808913bcf0ac7810ef65b2","assignment":{"version":2,"candidate_digest":"dea3d62576c33fc19ba315c6da2517655867ca709b513386f0a1128ca8ce4294","route":"identify-multimodal","operation":"scan_identification","effective_plan":"pro_complimentary","effective_tier":"pro","flash_fallback_used":false,"quota_model":"gemini-2.5-pro","policy_version":1,"provider":"gemini","binding":"gemini_baseline_v1","processor_permission":"google_gemini","input_profile":"multimodal_audio_v1","provider_model":null,"effective_model":"gemini-2.5-pro","minimum_client_protocol":0,"accepted_client_protocol":3,"minimum_identification_protocol":0,"accepted_identification_protocol":6,"asset_manifest_digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_owner":"initial_engine_release_archive","resolver_id":"git_blob_sha256_v1","preparation":{"kind":"media_sources","profile_digest":"2e69c3628e3ffc031742849d45f82c86610dc5d776808913bcf0ac7810ef65b2","installation_digest":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","backend_installation_digest":"1111111111111111111111111111111111111111111111111111111111111111","selector_generation":"00000000-0000-4000-8000-000000000003","backend_generation":"00000000-0000-4000-8000-00000000b001","source_mapping":[{"ordinal":0,"source":{"kind":"audio","source_content_type":"audio/wav","source_byte_count":32044,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":0,"clip_index":null,"frame_index":null,"focus_region":null,"transform":"initial_audio_v1","transform_parameters":{"target_sample_rate":16000,"preserve_short_video_context":false},"prepared_output":{"state":"unresolved"}},"role":"recording","object_id":"00000000-0000-4000-8000-000000001020","prepared_destination":null}]},"experiment":null,"variant":"media_sources","source_plan_digest":"2a8a52d0660ac1f2346ac9e38576f6163583182a3dc0c0c7cd0cbbcca66b1a8f"},"assignment_canonical":"{\"accepted_client_protocol\":3,\"accepted_identification_protocol\":6,\"asset_manifest_digest\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"binding\":\"gemini_baseline_v1\",\"candidate_digest\":\"dea3d62576c33fc19ba315c6da2517655867ca709b513386f0a1128ca8ce4294\",\"effective_model\":\"gemini-2.5-pro\",\"effective_plan\":\"pro_complimentary\",\"effective_tier\":\"pro\",\"experiment\":null,\"flash_fallback_used\":false,\"input_profile\":\"multimodal_audio_v1\",\"minimum_client_protocol\":0,\"minimum_identification_protocol\":0,\"operation\":\"scan_identification\",\"policy_version\":1,\"preparation\":{\"backend_generation\":\"00000000-0000-4000-8000-00000000b001\",\"backend_installation_digest\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"installation_digest\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"kind\":\"media_sources\",\"profile_digest\":\"2e69c3628e3ffc031742849d45f82c86610dc5d776808913bcf0ac7810ef65b2\",\"selector_generation\":\"00000000-0000-4000-8000-000000000003\",\"source_mapping\":[{\"object_id\":\"00000000-0000-4000-8000-000000001020\",\"ordinal\":0,\"prepared_destination\":null,\"role\":\"recording\",\"source\":{\"clip_index\":null,\"focus_region\":null,\"frame_index\":null,\"input_index\":0,\"kind\":\"audio\",\"prepared_output\":{\"state\":\"unresolved\"},\"source_byte_count\":32044,\"source_content_type\":\"audio/wav\",\"source_index\":0,\"source_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"transform\":\"initial_audio_v1\",\"transform_parameters\":{\"preserve_short_video_context\":false,\"target_sample_rate\":16000}}}]},\"processor_permission\":\"google_gemini\",\"provider\":\"gemini\",\"provider_model\":null,\"quota_model\":\"gemini-2.5-pro\",\"resolver_id\":\"git_blob_sha256_v1\",\"retention_owner\":\"initial_engine_release_archive\",\"route\":\"identify-multimodal\",\"source_plan_digest\":\"2a8a52d0660ac1f2346ac9e38576f6163583182a3dc0c0c7cd0cbbcca66b1a8f\",\"variant\":\"media_sources\",\"version\":2}","assignment_digest":"04cf62b7713f947ffecd5ee99edba83d5d5202a2253f3cab4a827fd7fd737e14"},{"name":"Multimodal blended","candidate":{"version":2,"variant":"media_sources","source_plan":{"schema_version":1,"route":"identify-multimodal","ordered_descriptions":["First synthetic context","Second synthetic context"],"owner_timeline":[{"kind":"description","index":0},{"kind":"media","index":0},{"kind":"media","index":1},{"kind":"description","index":1}],"capture":{"has_video":false,"video_clip_count":0,"declared_video_frame_count":0,"video_inference_frame_count":0},"context":{"depth_scale_text":null,"semantic_location":null,"weather_condition":null,"device_locale":null,"device_time_zone":null,"device_region":null,"time_of_day":null,"gps_latitude":null,"gps_longitude":null,"gps_elevation":null,"zoom_factor":null,"estimated_size_cm":null,"weather_temperature_f":null,"current_month":null},"options":{"timestamp":null,"geoprivacy":"private","public_location_label":null,"preferred_goal":null,"observation_context":null},"admission":{"client_protocol":3,"identification_protocol":6,"expected_processor_permission":"google_gemini"},"experiment":null,"sources":[{"kind":"image","source_content_type":"image/png","source_byte_count":68,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":0,"clip_index":null,"frame_index":null,"focus_region":null,"transform":"identity_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}},{"kind":"audio","source_content_type":"audio/wav","source_byte_count":32044,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":0,"clip_index":null,"frame_index":null,"focus_region":null,"transform":"initial_audio_v1","transform_parameters":{"target_sample_rate":16000,"preserve_short_video_context":false},"prepared_output":{"state":"unresolved"}}]}},"profile":{"version":1,"spec":{"profile_id":"synthetic_test_only_3","profile_version":1,"input_profile":"multimodal_photo_audio_v1","route":"identify-multimodal","focus_policy":"input_v1_bounds","runtime":{"engine":"deno","version":"2.9.4","platform":"synthetic","abi":"test_only","protocol":1},"artifact":{"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byte_count":1},"identities":{"source":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","validator":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","transform":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","configuration":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"rules":[{"role":"photo","source_types":["image/png"],"transform":"identity_v1","target_sample_rate":null,"preserve_short_video_context":null,"max_count":5,"limits":{"source_bytes":5242880,"output_bytes":5242880,"cpu_ms":1000,"heap_bytes":1048576,"wall_ms":2000}},{"role":"recording","source_types":["audio/wav"],"transform":"initial_audio_v1","target_sample_rate":16000,"preserve_short_video_context":false,"max_count":2,"limits":{"source_bytes":2700000,"output_bytes":2700000,"cpu_ms":1000,"heap_bytes":1048576,"wall_ms":2000}}],"max_sources":8,"limits":{"source_bytes":20971520,"output_bytes":20971520,"cpu_ms":300000,"heap_bytes":1073741824,"wall_ms":300000}},"qualification":{"spec_digest":"0b895e673b704c3115fbbdf00b0754e4cdc57854cfb63aed1df4db399d4079e7","evidence_digest":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","harness_digest":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","source_revision":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}},"profile_canonical":"{\"qualification\":{\"evidence_digest\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"harness_digest\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"source_revision\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"spec_digest\":\"0b895e673b704c3115fbbdf00b0754e4cdc57854cfb63aed1df4db399d4079e7\"},\"spec\":{\"artifact\":{\"byte_count\":1,\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"focus_policy\":\"input_v1_bounds\",\"identities\":{\"configuration\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"source\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"transform\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"validator\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"input_profile\":\"multimodal_photo_audio_v1\",\"limits\":{\"cpu_ms\":300000,\"heap_bytes\":1073741824,\"output_bytes\":20971520,\"source_bytes\":20971520,\"wall_ms\":300000},\"max_sources\":8,\"profile_id\":\"synthetic_test_only_3\",\"profile_version\":1,\"route\":\"identify-multimodal\",\"rules\":[{\"limits\":{\"cpu_ms\":1000,\"heap_bytes\":1048576,\"output_bytes\":5242880,\"source_bytes\":5242880,\"wall_ms\":2000},\"max_count\":5,\"preserve_short_video_context\":null,\"role\":\"photo\",\"source_types\":[\"image/png\"],\"target_sample_rate\":null,\"transform\":\"identity_v1\"},{\"limits\":{\"cpu_ms\":1000,\"heap_bytes\":1048576,\"output_bytes\":2700000,\"source_bytes\":2700000,\"wall_ms\":2000},\"max_count\":2,\"preserve_short_video_context\":false,\"role\":\"recording\",\"source_types\":[\"audio/wav\"],\"target_sample_rate\":16000,\"transform\":\"initial_audio_v1\"}],\"runtime\":{\"abi\":\"test_only\",\"engine\":\"deno\",\"platform\":\"synthetic\",\"protocol\":1,\"version\":\"2.9.4\"}},\"version\":1}","profile_digest":"2723c270466dd9c32af08058232c8983c6f549ff8f39c3c6c9fa59e51449c53e","assignment":{"version":2,"candidate_digest":"50bc212364ee71ec3d440fea5b53b84a741d26db3c16c056e03721d6fe9655f1","route":"identify-multimodal","operation":"scan_identification","effective_plan":"pro_complimentary","effective_tier":"pro","flash_fallback_used":false,"quota_model":"gemini-2.5-pro","policy_version":1,"provider":"gemini","binding":"gemini_baseline_v1","processor_permission":"google_gemini","input_profile":"multimodal_photo_audio_v1","provider_model":null,"effective_model":"gemini-2.5-pro","minimum_client_protocol":0,"accepted_client_protocol":3,"minimum_identification_protocol":0,"accepted_identification_protocol":6,"asset_manifest_digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_owner":"initial_engine_release_archive","resolver_id":"git_blob_sha256_v1","preparation":{"kind":"media_sources","profile_digest":"2723c270466dd9c32af08058232c8983c6f549ff8f39c3c6c9fa59e51449c53e","installation_digest":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","backend_installation_digest":"1111111111111111111111111111111111111111111111111111111111111111","selector_generation":"00000000-0000-4000-8000-000000000004","backend_generation":"00000000-0000-4000-8000-00000000b001","source_mapping":[{"ordinal":0,"source":{"kind":"image","source_content_type":"image/png","source_byte_count":68,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":0,"clip_index":null,"frame_index":null,"focus_region":null,"transform":"identity_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}},"role":"photo","object_id":"00000000-0000-4000-8000-000000001030","prepared_destination":null},{"ordinal":1,"source":{"kind":"audio","source_content_type":"audio/wav","source_byte_count":32044,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":0,"clip_index":null,"frame_index":null,"focus_region":null,"transform":"initial_audio_v1","transform_parameters":{"target_sample_rate":16000,"preserve_short_video_context":false},"prepared_output":{"state":"unresolved"}},"role":"recording","object_id":"00000000-0000-4000-8000-000000001031","prepared_destination":null}]},"experiment":null,"variant":"media_sources","source_plan_digest":"4d95b99be6b078ae64a833afa308c542e9ea203caac09045c68d1a372a97503b"},"assignment_canonical":"{\"accepted_client_protocol\":3,\"accepted_identification_protocol\":6,\"asset_manifest_digest\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"binding\":\"gemini_baseline_v1\",\"candidate_digest\":\"50bc212364ee71ec3d440fea5b53b84a741d26db3c16c056e03721d6fe9655f1\",\"effective_model\":\"gemini-2.5-pro\",\"effective_plan\":\"pro_complimentary\",\"effective_tier\":\"pro\",\"experiment\":null,\"flash_fallback_used\":false,\"input_profile\":\"multimodal_photo_audio_v1\",\"minimum_client_protocol\":0,\"minimum_identification_protocol\":0,\"operation\":\"scan_identification\",\"policy_version\":1,\"preparation\":{\"backend_generation\":\"00000000-0000-4000-8000-00000000b001\",\"backend_installation_digest\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"installation_digest\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"kind\":\"media_sources\",\"profile_digest\":\"2723c270466dd9c32af08058232c8983c6f549ff8f39c3c6c9fa59e51449c53e\",\"selector_generation\":\"00000000-0000-4000-8000-000000000004\",\"source_mapping\":[{\"object_id\":\"00000000-0000-4000-8000-000000001030\",\"ordinal\":0,\"prepared_destination\":null,\"role\":\"photo\",\"source\":{\"clip_index\":null,\"focus_region\":null,\"frame_index\":null,\"input_index\":0,\"kind\":\"image\",\"prepared_output\":{\"state\":\"unresolved\"},\"source_byte_count\":68,\"source_content_type\":\"image/png\",\"source_index\":0,\"source_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"transform\":\"identity_v1\",\"transform_parameters\":null}},{\"object_id\":\"00000000-0000-4000-8000-000000001031\",\"ordinal\":1,\"prepared_destination\":null,\"role\":\"recording\",\"source\":{\"clip_index\":null,\"focus_region\":null,\"frame_index\":null,\"input_index\":0,\"kind\":\"audio\",\"prepared_output\":{\"state\":\"unresolved\"},\"source_byte_count\":32044,\"source_content_type\":\"audio/wav\",\"source_index\":0,\"source_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"transform\":\"initial_audio_v1\",\"transform_parameters\":{\"preserve_short_video_context\":false,\"target_sample_rate\":16000}}}]},\"processor_permission\":\"google_gemini\",\"provider\":\"gemini\",\"provider_model\":null,\"quota_model\":\"gemini-2.5-pro\",\"resolver_id\":\"git_blob_sha256_v1\",\"retention_owner\":\"initial_engine_release_archive\",\"route\":\"identify-multimodal\",\"source_plan_digest\":\"4d95b99be6b078ae64a833afa308c542e9ea203caac09045c68d1a372a97503b\",\"variant\":\"media_sources\",\"version\":2}","assignment_digest":"c178e963c2f689d750d12233982a71f1c466508d6e22ddf6da129beacc384d53"},{"name":"frames","candidate":{"version":2,"variant":"media_sources","source_plan":{"schema_version":1,"route":"identify-multimodal","ordered_descriptions":[],"owner_timeline":[{"kind":"media","index":1}],"capture":{"has_video":true,"video_clip_count":1,"declared_video_frame_count":1,"video_inference_frame_count":1},"context":{"depth_scale_text":null,"semantic_location":null,"weather_condition":null,"device_locale":null,"device_time_zone":null,"device_region":null,"time_of_day":null,"gps_latitude":null,"gps_longitude":null,"gps_elevation":null,"zoom_factor":null,"estimated_size_cm":null,"weather_temperature_f":null,"current_month":null},"options":{"timestamp":null,"geoprivacy":"private","public_location_label":null,"preferred_goal":null,"observation_context":null},"admission":{"client_protocol":3,"identification_protocol":6,"expected_processor_permission":"google_gemini"},"experiment":null,"sources":[{"kind":"image","source_content_type":"image/png","source_byte_count":68,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":null,"clip_index":0,"frame_index":0,"focus_region":null,"transform":"video_frame_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}},{"kind":"video","source_content_type":"video/mp4","source_byte_count":24,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":null,"source_index":null,"clip_index":0,"frame_index":null,"focus_region":null,"transform":"identity_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}}]}},"profile":{"version":1,"spec":{"profile_id":"synthetic_test_only_4","profile_version":1,"input_profile":"multimodal_video_frames_v1","route":"identify-multimodal","focus_policy":"input_v1_bounds","runtime":{"engine":"deno","version":"2.9.4","platform":"synthetic","abi":"test_only","protocol":1},"artifact":{"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byte_count":1},"identities":{"source":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","validator":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","transform":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","configuration":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"rules":[{"role":"raw_video","source_types":["video/mp4"],"transform":"identity_v1","target_sample_rate":null,"preserve_short_video_context":null,"max_count":1,"limits":{"source_bytes":12582912,"output_bytes":0,"cpu_ms":1000,"heap_bytes":1048576,"wall_ms":2000}},{"role":"video_frame","source_types":["image/png"],"transform":"video_frame_v1","target_sample_rate":null,"preserve_short_video_context":null,"max_count":5,"limits":{"source_bytes":5242880,"output_bytes":5242880,"cpu_ms":1000,"heap_bytes":1048576,"wall_ms":2000}}],"max_sources":8,"limits":{"source_bytes":20971520,"output_bytes":20971520,"cpu_ms":300000,"heap_bytes":1073741824,"wall_ms":300000}},"qualification":{"spec_digest":"7b60ab43aa7e50de12f61e32286a23ee4b79536b7d3964c5ce75e55e3381fc8e","evidence_digest":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","harness_digest":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","source_revision":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}},"profile_canonical":"{\"qualification\":{\"evidence_digest\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"harness_digest\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"source_revision\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"spec_digest\":\"7b60ab43aa7e50de12f61e32286a23ee4b79536b7d3964c5ce75e55e3381fc8e\"},\"spec\":{\"artifact\":{\"byte_count\":1,\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"focus_policy\":\"input_v1_bounds\",\"identities\":{\"configuration\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"source\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"transform\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"validator\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"input_profile\":\"multimodal_video_frames_v1\",\"limits\":{\"cpu_ms\":300000,\"heap_bytes\":1073741824,\"output_bytes\":20971520,\"source_bytes\":20971520,\"wall_ms\":300000},\"max_sources\":8,\"profile_id\":\"synthetic_test_only_4\",\"profile_version\":1,\"route\":\"identify-multimodal\",\"rules\":[{\"limits\":{\"cpu_ms\":1000,\"heap_bytes\":1048576,\"output_bytes\":0,\"source_bytes\":12582912,\"wall_ms\":2000},\"max_count\":1,\"preserve_short_video_context\":null,\"role\":\"raw_video\",\"source_types\":[\"video/mp4\"],\"target_sample_rate\":null,\"transform\":\"identity_v1\"},{\"limits\":{\"cpu_ms\":1000,\"heap_bytes\":1048576,\"output_bytes\":5242880,\"source_bytes\":5242880,\"wall_ms\":2000},\"max_count\":5,\"preserve_short_video_context\":null,\"role\":\"video_frame\",\"source_types\":[\"image/png\"],\"target_sample_rate\":null,\"transform\":\"video_frame_v1\"}],\"runtime\":{\"abi\":\"test_only\",\"engine\":\"deno\",\"platform\":\"synthetic\",\"protocol\":1,\"version\":\"2.9.4\"}},\"version\":1}","profile_digest":"06b0f1a99c7996f093509ab9cf6a2e64fce2d34f6b750b30ac7e33fcfe7d6bdd","assignment":{"version":2,"candidate_digest":"27f4fd9a350bd625a458733203acc0f778ab9c0b8fb4c0196ea239214dda21d5","route":"identify-multimodal","operation":"scan_identification","effective_plan":"pro_complimentary","effective_tier":"pro","flash_fallback_used":false,"quota_model":"gemini-2.5-pro","policy_version":1,"provider":"gemini","binding":"gemini_baseline_v1","processor_permission":"google_gemini","input_profile":"multimodal_video_frames_v1","provider_model":null,"effective_model":"gemini-2.5-pro","minimum_client_protocol":0,"accepted_client_protocol":3,"minimum_identification_protocol":0,"accepted_identification_protocol":6,"asset_manifest_digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_owner":"initial_engine_release_archive","resolver_id":"git_blob_sha256_v1","preparation":{"kind":"media_sources","profile_digest":"06b0f1a99c7996f093509ab9cf6a2e64fce2d34f6b750b30ac7e33fcfe7d6bdd","installation_digest":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","backend_installation_digest":"1111111111111111111111111111111111111111111111111111111111111111","selector_generation":"00000000-0000-4000-8000-000000000005","backend_generation":"00000000-0000-4000-8000-00000000b001","source_mapping":[{"ordinal":0,"source":{"kind":"image","source_content_type":"image/png","source_byte_count":68,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":null,"clip_index":0,"frame_index":0,"focus_region":null,"transform":"video_frame_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}},"role":"video_frame","object_id":"00000000-0000-4000-8000-000000001040","prepared_destination":null},{"ordinal":1,"source":{"kind":"video","source_content_type":"video/mp4","source_byte_count":24,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":null,"source_index":null,"clip_index":0,"frame_index":null,"focus_region":null,"transform":"identity_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}},"role":"raw_video","object_id":"00000000-0000-4000-8000-000000001041","prepared_destination":null}]},"experiment":null,"variant":"media_sources","source_plan_digest":"7d2e6d5cf8b84f68fb27e6261c9f635cd2d36a2a36bb8150a31dcdbb1bda3188"},"assignment_canonical":"{\"accepted_client_protocol\":3,\"accepted_identification_protocol\":6,\"asset_manifest_digest\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"binding\":\"gemini_baseline_v1\",\"candidate_digest\":\"27f4fd9a350bd625a458733203acc0f778ab9c0b8fb4c0196ea239214dda21d5\",\"effective_model\":\"gemini-2.5-pro\",\"effective_plan\":\"pro_complimentary\",\"effective_tier\":\"pro\",\"experiment\":null,\"flash_fallback_used\":false,\"input_profile\":\"multimodal_video_frames_v1\",\"minimum_client_protocol\":0,\"minimum_identification_protocol\":0,\"operation\":\"scan_identification\",\"policy_version\":1,\"preparation\":{\"backend_generation\":\"00000000-0000-4000-8000-00000000b001\",\"backend_installation_digest\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"installation_digest\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"kind\":\"media_sources\",\"profile_digest\":\"06b0f1a99c7996f093509ab9cf6a2e64fce2d34f6b750b30ac7e33fcfe7d6bdd\",\"selector_generation\":\"00000000-0000-4000-8000-000000000005\",\"source_mapping\":[{\"object_id\":\"00000000-0000-4000-8000-000000001040\",\"ordinal\":0,\"prepared_destination\":null,\"role\":\"video_frame\",\"source\":{\"clip_index\":0,\"focus_region\":null,\"frame_index\":0,\"input_index\":0,\"kind\":\"image\",\"prepared_output\":{\"state\":\"unresolved\"},\"source_byte_count\":68,\"source_content_type\":\"image/png\",\"source_index\":null,\"source_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"transform\":\"video_frame_v1\",\"transform_parameters\":null}},{\"object_id\":\"00000000-0000-4000-8000-000000001041\",\"ordinal\":1,\"prepared_destination\":null,\"role\":\"raw_video\",\"source\":{\"clip_index\":0,\"focus_region\":null,\"frame_index\":null,\"input_index\":null,\"kind\":\"video\",\"prepared_output\":{\"state\":\"unresolved\"},\"source_byte_count\":24,\"source_content_type\":\"video/mp4\",\"source_index\":null,\"source_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"transform\":\"identity_v1\",\"transform_parameters\":null}}]},\"processor_permission\":\"google_gemini\",\"provider\":\"gemini\",\"provider_model\":null,\"quota_model\":\"gemini-2.5-pro\",\"resolver_id\":\"git_blob_sha256_v1\",\"retention_owner\":\"initial_engine_release_archive\",\"route\":\"identify-multimodal\",\"source_plan_digest\":\"7d2e6d5cf8b84f68fb27e6261c9f635cd2d36a2a36bb8150a31dcdbb1bda3188\",\"variant\":\"media_sources\",\"version\":2}","assignment_digest":"f481315622c453b35b061a165dd32eaa5b9303b28cde1120d3ff7d8a77bf209c"},{"name":"video audio","candidate":{"version":2,"variant":"media_sources","source_plan":{"schema_version":1,"route":"identify-multimodal","ordered_descriptions":[],"owner_timeline":[{"kind":"media","index":2}],"capture":{"has_video":true,"video_clip_count":1,"declared_video_frame_count":1,"video_inference_frame_count":1},"context":{"depth_scale_text":null,"semantic_location":null,"weather_condition":null,"device_locale":null,"device_time_zone":null,"device_region":null,"time_of_day":null,"gps_latitude":null,"gps_longitude":null,"gps_elevation":null,"zoom_factor":null,"estimated_size_cm":null,"weather_temperature_f":null,"current_month":null},"options":{"timestamp":null,"geoprivacy":"private","public_location_label":null,"preferred_goal":null,"observation_context":null},"admission":{"client_protocol":3,"identification_protocol":6,"expected_processor_permission":"google_gemini"},"experiment":null,"sources":[{"kind":"image","source_content_type":"image/png","source_byte_count":68,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":null,"clip_index":0,"frame_index":0,"focus_region":null,"transform":"video_frame_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}},{"kind":"audio","source_content_type":"audio/wav","source_byte_count":32044,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":null,"clip_index":0,"frame_index":null,"focus_region":null,"transform":"initial_audio_v1","transform_parameters":{"target_sample_rate":16000,"preserve_short_video_context":true},"prepared_output":{"state":"unresolved"}},{"kind":"video","source_content_type":"video/mp4","source_byte_count":24,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":null,"source_index":null,"clip_index":0,"frame_index":null,"focus_region":null,"transform":"identity_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}}]}},"profile":{"version":1,"spec":{"profile_id":"synthetic_test_only_5","profile_version":1,"input_profile":"multimodal_video_audio_v1","route":"identify-multimodal","focus_policy":"input_v1_bounds","runtime":{"engine":"deno","version":"2.9.4","platform":"synthetic","abi":"test_only","protocol":1},"artifact":{"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byte_count":1},"identities":{"source":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","validator":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","transform":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","configuration":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"rules":[{"role":"raw_video","source_types":["video/mp4"],"transform":"identity_v1","target_sample_rate":null,"preserve_short_video_context":null,"max_count":1,"limits":{"source_bytes":12582912,"output_bytes":0,"cpu_ms":1000,"heap_bytes":1048576,"wall_ms":2000}},{"role":"video_audio","source_types":["audio/wav"],"transform":"initial_audio_v1","target_sample_rate":16000,"preserve_short_video_context":true,"max_count":2,"limits":{"source_bytes":2700000,"output_bytes":2700000,"cpu_ms":1000,"heap_bytes":1048576,"wall_ms":2000}},{"role":"video_frame","source_types":["image/png"],"transform":"video_frame_v1","target_sample_rate":null,"preserve_short_video_context":null,"max_count":5,"limits":{"source_bytes":5242880,"output_bytes":5242880,"cpu_ms":1000,"heap_bytes":1048576,"wall_ms":2000}}],"max_sources":8,"limits":{"source_bytes":20971520,"output_bytes":20971520,"cpu_ms":300000,"heap_bytes":1073741824,"wall_ms":300000}},"qualification":{"spec_digest":"77899834e7f432f008b77bfa92aaf636e4e33052527a1cc87bbdaca1a36f22ad","evidence_digest":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","harness_digest":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","source_revision":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}},"profile_canonical":"{\"qualification\":{\"evidence_digest\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"harness_digest\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"source_revision\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"spec_digest\":\"77899834e7f432f008b77bfa92aaf636e4e33052527a1cc87bbdaca1a36f22ad\"},\"spec\":{\"artifact\":{\"byte_count\":1,\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"focus_policy\":\"input_v1_bounds\",\"identities\":{\"configuration\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"source\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"transform\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"validator\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"input_profile\":\"multimodal_video_audio_v1\",\"limits\":{\"cpu_ms\":300000,\"heap_bytes\":1073741824,\"output_bytes\":20971520,\"source_bytes\":20971520,\"wall_ms\":300000},\"max_sources\":8,\"profile_id\":\"synthetic_test_only_5\",\"profile_version\":1,\"route\":\"identify-multimodal\",\"rules\":[{\"limits\":{\"cpu_ms\":1000,\"heap_bytes\":1048576,\"output_bytes\":0,\"source_bytes\":12582912,\"wall_ms\":2000},\"max_count\":1,\"preserve_short_video_context\":null,\"role\":\"raw_video\",\"source_types\":[\"video/mp4\"],\"target_sample_rate\":null,\"transform\":\"identity_v1\"},{\"limits\":{\"cpu_ms\":1000,\"heap_bytes\":1048576,\"output_bytes\":2700000,\"source_bytes\":2700000,\"wall_ms\":2000},\"max_count\":2,\"preserve_short_video_context\":true,\"role\":\"video_audio\",\"source_types\":[\"audio/wav\"],\"target_sample_rate\":16000,\"transform\":\"initial_audio_v1\"},{\"limits\":{\"cpu_ms\":1000,\"heap_bytes\":1048576,\"output_bytes\":5242880,\"source_bytes\":5242880,\"wall_ms\":2000},\"max_count\":5,\"preserve_short_video_context\":null,\"role\":\"video_frame\",\"source_types\":[\"image/png\"],\"target_sample_rate\":null,\"transform\":\"video_frame_v1\"}],\"runtime\":{\"abi\":\"test_only\",\"engine\":\"deno\",\"platform\":\"synthetic\",\"protocol\":1,\"version\":\"2.9.4\"}},\"version\":1}","profile_digest":"3d388f7b0f2befb3e0de6c2d576b55e18a9128c1941561494a292e11cecc3a2c","assignment":{"version":2,"candidate_digest":"f512c40fce438e31f5bd2e196137397e5d17078e2ed65db5d35da04dd858d2c2","route":"identify-multimodal","operation":"scan_identification","effective_plan":"pro_complimentary","effective_tier":"pro","flash_fallback_used":false,"quota_model":"gemini-2.5-pro","policy_version":1,"provider":"gemini","binding":"gemini_baseline_v1","processor_permission":"google_gemini","input_profile":"multimodal_video_audio_v1","provider_model":null,"effective_model":"gemini-2.5-pro","minimum_client_protocol":0,"accepted_client_protocol":3,"minimum_identification_protocol":0,"accepted_identification_protocol":6,"asset_manifest_digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_owner":"initial_engine_release_archive","resolver_id":"git_blob_sha256_v1","preparation":{"kind":"media_sources","profile_digest":"3d388f7b0f2befb3e0de6c2d576b55e18a9128c1941561494a292e11cecc3a2c","installation_digest":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","backend_installation_digest":"1111111111111111111111111111111111111111111111111111111111111111","selector_generation":"00000000-0000-4000-8000-000000000006","backend_generation":"00000000-0000-4000-8000-00000000b001","source_mapping":[{"ordinal":0,"source":{"kind":"image","source_content_type":"image/png","source_byte_count":68,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":null,"clip_index":0,"frame_index":0,"focus_region":null,"transform":"video_frame_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}},"role":"video_frame","object_id":"00000000-0000-4000-8000-000000001050","prepared_destination":null},{"ordinal":1,"source":{"kind":"audio","source_content_type":"audio/wav","source_byte_count":32044,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":0,"source_index":null,"clip_index":0,"frame_index":null,"focus_region":null,"transform":"initial_audio_v1","transform_parameters":{"target_sample_rate":16000,"preserve_short_video_context":true},"prepared_output":{"state":"unresolved"}},"role":"video_audio","object_id":"00000000-0000-4000-8000-000000001051","prepared_destination":null},{"ordinal":2,"source":{"kind":"video","source_content_type":"video/mp4","source_byte_count":24,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","input_index":null,"source_index":null,"clip_index":0,"frame_index":null,"focus_region":null,"transform":"identity_v1","transform_parameters":null,"prepared_output":{"state":"unresolved"}},"role":"raw_video","object_id":"00000000-0000-4000-8000-000000001052","prepared_destination":null}]},"experiment":null,"variant":"media_sources","source_plan_digest":"46e62da1b7a1f782c811d5912e1e9a307e2a68180a4b034bb2b7187f9f03a7d3"},"assignment_canonical":"{\"accepted_client_protocol\":3,\"accepted_identification_protocol\":6,\"asset_manifest_digest\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"binding\":\"gemini_baseline_v1\",\"candidate_digest\":\"f512c40fce438e31f5bd2e196137397e5d17078e2ed65db5d35da04dd858d2c2\",\"effective_model\":\"gemini-2.5-pro\",\"effective_plan\":\"pro_complimentary\",\"effective_tier\":\"pro\",\"experiment\":null,\"flash_fallback_used\":false,\"input_profile\":\"multimodal_video_audio_v1\",\"minimum_client_protocol\":0,\"minimum_identification_protocol\":0,\"operation\":\"scan_identification\",\"policy_version\":1,\"preparation\":{\"backend_generation\":\"00000000-0000-4000-8000-00000000b001\",\"backend_installation_digest\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"installation_digest\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"kind\":\"media_sources\",\"profile_digest\":\"3d388f7b0f2befb3e0de6c2d576b55e18a9128c1941561494a292e11cecc3a2c\",\"selector_generation\":\"00000000-0000-4000-8000-000000000006\",\"source_mapping\":[{\"object_id\":\"00000000-0000-4000-8000-000000001050\",\"ordinal\":0,\"prepared_destination\":null,\"role\":\"video_frame\",\"source\":{\"clip_index\":0,\"focus_region\":null,\"frame_index\":0,\"input_index\":0,\"kind\":\"image\",\"prepared_output\":{\"state\":\"unresolved\"},\"source_byte_count\":68,\"source_content_type\":\"image/png\",\"source_index\":null,\"source_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"transform\":\"video_frame_v1\",\"transform_parameters\":null}},{\"object_id\":\"00000000-0000-4000-8000-000000001051\",\"ordinal\":1,\"prepared_destination\":null,\"role\":\"video_audio\",\"source\":{\"clip_index\":0,\"focus_region\":null,\"frame_index\":null,\"input_index\":0,\"kind\":\"audio\",\"prepared_output\":{\"state\":\"unresolved\"},\"source_byte_count\":32044,\"source_content_type\":\"audio/wav\",\"source_index\":null,\"source_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"transform\":\"initial_audio_v1\",\"transform_parameters\":{\"preserve_short_video_context\":true,\"target_sample_rate\":16000}}},{\"object_id\":\"00000000-0000-4000-8000-000000001052\",\"ordinal\":2,\"prepared_destination\":null,\"role\":\"raw_video\",\"source\":{\"clip_index\":0,\"focus_region\":null,\"frame_index\":null,\"input_index\":null,\"kind\":\"video\",\"prepared_output\":{\"state\":\"unresolved\"},\"source_byte_count\":24,\"source_content_type\":\"video/mp4\",\"source_index\":null,\"source_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"transform\":\"identity_v1\",\"transform_parameters\":null}}]},\"processor_permission\":\"google_gemini\",\"provider\":\"gemini\",\"provider_model\":null,\"quota_model\":\"gemini-2.5-pro\",\"resolver_id\":\"git_blob_sha256_v1\",\"retention_owner\":\"initial_engine_release_archive\",\"route\":\"identify-multimodal\",\"source_plan_digest\":\"46e62da1b7a1f782c811d5912e1e9a307e2a68180a4b034bb2b7187f9f03a7d3\",\"variant\":\"media_sources\",\"version\":2}","assignment_digest":"4ab94df2e4d69d64f9a4522474194ab2c6592fd3f50d21a87dd146be58f04a50"}]$vectors$::JSONB) WITH ORDINALITY;
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000f001');
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000f002');
CREATE FUNCTION pg_temp.media_create(scan UUID, vector BIGINT DEFAULT 3) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000f001',scan,(SELECT internal.initial_canonical(v->'candidate') FROM media_vectors WHERE i=vector));
$$;
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;
-- Smaller synthetic wall caps fit the unchanged 300-second operation envelope.
UPDATE media_vectors SET v=jsonb_set(v,'{profile,spec,limits,wall_ms}','30000'::JSONB);
UPDATE media_vectors SET v=jsonb_set(v,'{profile,qualification,spec_digest}',to_jsonb(internal.initial_media_contract_digest('profile_spec',internal.initial_canonical(v#>'{profile,spec}'))));
UPDATE media_vectors SET v=jsonb_set(v,'{profile_canonical}',to_jsonb(internal.initial_canonical(v->'profile')));
UPDATE media_vectors SET v=jsonb_set(v,'{profile_digest}',to_jsonb(internal.initial_media_contract_digest('profile',v->>'profile_canonical')));
-- Synthetic transaction-local installation is not storage/runtime qualification.
INSERT INTO internal.initial_preparation_profiles SELECT v->>'profile_digest',v->>'profile_canonical' FROM media_vectors;
INSERT INTO internal.initial_preparation_installations(digest,target_kind,target_digest,evidence_digest,reviewed_revision,installer_protocol)
SELECT internal.initial_media_contract_digest('installation',internal.initial_canonical(value)),value->>'target_kind',value->>'target_digest',value->>'evidence_digest',value->>'reviewed_revision',value->>'installer_protocol' FROM (
 SELECT jsonb_build_object('target_kind','profile','target_digest',v->>'profile_digest','evidence_digest',v#>>'{profile,qualification,evidence_digest}','reviewed_revision',v#>>'{profile,qualification,source_revision}','installer_protocol','reviewed_database_owner_install_v1') value FROM media_vectors) x;
INSERT INTO internal.initial_preparation_profile_eligibility(profile_digest,installation_digest,state) SELECT target_digest,digest,'eligible' FROM internal.initial_preparation_installations WHERE target_kind='profile';
CREATE TEMP TABLE backend_fixture AS SELECT jsonb_build_object('generation','00000000-0000-4000-8000-00000000fb01','provider','r2','direct_endpoint','https://'||repeat('0',32)||'.r2.cloudflarestorage.com','private_bucket','synthetic-only','namespace','initial-preparation/v2','credential_profile','synthetic_only','storage_protocol','conditional_create_permanent_same_key_marker_v1') value;
INSERT INTO internal.initial_preparation_source_backends(generation,configuration_digest,provider,direct_endpoint,private_bucket,namespace,credential_profile,storage_protocol)
SELECT (value->>'generation')::UUID,internal.initial_media_contract_digest('backend',internal.initial_canonical(value)),value->>'provider',value->>'direct_endpoint',value->>'private_bucket',value->>'namespace',value->>'credential_profile',value->>'storage_protocol' FROM backend_fixture;
INSERT INTO internal.initial_preparation_installations(digest,target_kind,target_digest,evidence_digest,reviewed_revision,installer_protocol)
SELECT internal.initial_media_contract_digest('installation',internal.initial_canonical(value)),value->>'target_kind',value->>'target_digest',value->>'evidence_digest',value->>'reviewed_revision',value->>'installer_protocol' FROM (
 SELECT jsonb_build_object('target_kind','backend','target_digest',configuration_digest,'evidence_digest',repeat('a',64),'reviewed_revision',repeat('b',40),'installer_protocol','reviewed_database_owner_install_v1') value FROM internal.initial_preparation_source_backends) x;
INSERT INTO internal.initial_preparation_backend_eligibility(generation,configuration_digest,installation_digest,state) SELECT b.generation,b.configuration_digest,i.digest,'eligible' FROM internal.initial_preparation_source_backends b JOIN internal.initial_preparation_installations i ON i.target_kind='backend' AND i.target_digest=b.configuration_digest;
-- BEGIN QUALIFIED HANDOFF FIXTURE (synthetic declarations, rollback/local only)
CREATE FUNCTION pg_temp.install_handoff(profile_digest TEXT,backend UUID) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE protocol JSONB:=$protocol${"deadline_protocol":{"schema_version":1,"sha256":"5555555555555555555555555555555555555555555555555555555555555555"},"input_projection":{"schema_version":1,"sha256":"1111111111111111111111111111111111111111111111111111111111111111"},"m1_mapping":{"schema_version":2,"sha256":"2222222222222222222222222222222222222222222222222222222222222222"},"m2_codec":{"schema_version":2,"sha256":"3333333333333333333333333333333333333333333333333333333333333333"},"response_codec":{"schema_version":2,"sha256":"6666666666666666666666666666666666666666666666666666666666666666"},"transfer_validator":{"schema_version":1,"sha256":"4444444444444444444444444444444444444444444444444444444444444444"},"version":1}$protocol$::JSONB; h JSONB:=$handoff${"cohort_limits":{"alias_policy":"same_ordinal_exact_bytes_only","content_type_pairs":[{"kind":"image","prepared_content_type":"image/png","source_content_type":"image/png"}],"max_ordinals":8,"max_unique_bytes":28625792,"max_unique_objects":10,"video_policy":"source_only"},"copy_adapter_digest":"9999999999999999999999999999999999999999999999999999999999999999","destination_backend_config_digest":"61feeb96c669da704f2b8bf0202bcd90ff929589cb2013d65dd05eb9d6d953a7","destination_backend_generation":"00000000-0000-4000-8000-00000000b002","execution_model":"sequential_whole_cohort","generation":"00000000-0000-4000-8000-000000000001","phase_ms":{"admission":10000,"copy":25000,"protocol_margin":5000,"reconciliation":10000,"transfer":5000,"verification":15000,"verification_claim":5000,"verification_settlement":5000},"protocol_artifact_digest":"b4c50d2dda319599a9e9968582e077d52c0cf8b391799d10724aa1dce1f3dc53","source_backend_config_digest":"9e5a79bd5260f1702ecdc8d4c7ede937f1997258e354f66f1b1e866b33deb82f","source_backend_generation":"00000000-0000-4000-8000-00000000b001","total_ms":80000,"verification_adapter_digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","version":1}$handoff$::JSONB; install JSONB:=$install${"copy_adapter_digest":"9999999999999999999999999999999999999999999999999999999999999999","destination_backend_generation":"00000000-0000-4000-8000-00000000b002","evidence_digest":"9999999999999999999999999999999999999999999999999999999999999999","installer_protocol":"reviewed_database_owner_install_v1","preparation_profile_digest":"0453660d5f231196cc9f81f101c749bbdf2b6e77f94065fbe9e019267a9a9ed6","profile_digest":"12974ed97b1e07938706c216c17f44de479145b0f56ed21329de7f594182293c","profile_generation":"00000000-0000-4000-8000-000000000001","protocol_artifact_digest":"b4c50d2dda319599a9e9968582e077d52c0cf8b391799d10724aa1dce1f3dc53","qualification_harness_digest":"7777777777777777777777777777777777777777777777777777777777777777","reviewed_source_revision":"8888888888888888888888888888888888888888","source_backend_generation":"00000000-0000-4000-8000-00000000b001","verification_adapter_digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","version":1}$install$::JSONB; profile JSONB; dest JSONB; source_digest TEXT; hd TEXT; id TEXT;
BEGIN
 -- Synthetic suite budget covers many serial rollback/corruption probes. Its
 -- canonical profile/digests are computed below; runtime cutoffs are unchanged.
 -- This is not a throughput/deadline qualification for an installed finalizer.
 h:=jsonb_set(h,'{phase_ms,admission}','60000'::JSONB);
 h:=jsonb_set(h,'{total_ms}',to_jsonb((h->>'total_ms')::INTEGER+50000));
 SELECT canonical_profile::JSONB INTO STRICT profile FROM internal.initial_preparation_profiles WHERE digest=profile_digest;
 SELECT configuration_digest INTO STRICT source_digest FROM internal.initial_preparation_source_backends WHERE generation=backend;
 dest:=jsonb_build_object('generation','00000000-0000-4000-8000-00000000fb02','provider','r2','direct_endpoint','https://'||repeat('0',32)||'.r2.cloudflarestorage.com','private_bucket','synthetic-only','namespace','initial-analysis/v1','credential_profile','synthetic_only');
 INSERT INTO internal.initial_analysis_media_backends(generation,provider,direct_endpoint,private_bucket,namespace,credential_profile) VALUES((dest->>'generation')::UUID,dest->>'provider',dest->>'direct_endpoint',dest->>'private_bucket',dest->>'namespace',dest->>'credential_profile') ON CONFLICT DO NOTHING;
 INSERT INTO internal.initial_preparation_handoff_protocol_artifacts VALUES(internal.initial_handoff_digest('protocol_artifact',internal.initial_canonical(protocol)),internal.initial_canonical(protocol)) ON CONFLICT DO NOTHING;
 h:=h||jsonb_build_object('generation',gen_random_uuid(),'source_backend_generation',backend,'source_backend_config_digest',source_digest,'destination_backend_generation',dest->>'generation','destination_backend_config_digest',internal.initial_handoff_catalog_digest('destination_backend',internal.initial_canonical(dest)));
 h:=jsonb_set(h,'{cohort_limits,content_type_pairs}',(SELECT jsonb_agg(DISTINCT jsonb_build_object('kind',CASE WHEN r->>'role'='raw_video' THEN 'video' WHEN r->>'role' IN ('recording','video_audio') THEN 'audio' ELSE 'image' END,'source_content_type',t,'prepared_content_type',CASE WHEN r->>'role'='raw_video' THEN NULL WHEN r->>'role' IN ('recording','video_audio') THEN 'audio/wav' ELSE t END)) FROM jsonb_array_elements(profile#>'{spec,rules}') r CROSS JOIN LATERAL jsonb_array_elements_text(r->'source_types') t));
 hd:=internal.initial_handoff_digest('profile',internal.initial_canonical(h));
 INSERT INTO internal.initial_preparation_handoff_profiles VALUES((h->>'generation')::UUID,hd,internal.initial_canonical(h),h->>'protocol_artifact_digest',backend,source_digest,(dest->>'generation')::UUID,h->>'destination_backend_config_digest');
 install:=install||jsonb_build_object('profile_generation',h->>'generation','profile_digest',hd,'preparation_profile_digest',profile_digest,'source_backend_generation',backend,'destination_backend_generation',dest->>'generation');
 id:=internal.initial_handoff_catalog_digest('installation',internal.initial_canonical(install));
 INSERT INTO internal.initial_preparation_handoff_installations VALUES(id,internal.initial_canonical(install),(h->>'generation')::UUID,hd,profile_digest,backend);
 INSERT INTO internal.initial_preparation_handoff_eligibility VALUES(id,'eligible');
 RETURN id;
END; $$;
-- END QUALIFIED HANDOFF FIXTURE
INSERT INTO internal.initial_preparation_selections(generation,profile_digest,backend_generation,handoff_installation_digest) SELECT ('00000000-0000-4000-8000-'||lpad((64000+i)::TEXT,12,'0'))::UUID,v->>'profile_digest','00000000-0000-4000-8000-00000000fb01',pg_temp.install_handoff(v->>'profile_digest','00000000-0000-4000-8000-00000000fb01') FROM media_vectors;
INSERT INTO internal.initial_preparation_current_selection SELECT v#>>'{profile,spec,input_profile}',s.generation FROM media_vectors JOIN internal.initial_preparation_selections s ON s.profile_digest=v->>'profile_digest';
CREATE FUNCTION pg_temp.funding_tripwire() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF current_setting('merian.test_funding_tripwire',TRUE)='on' THEN
  IF TG_TABLE_NAME<>'users' THEN RAISE EXCEPTION 'synthetic_funding_mutation' USING ERRCODE='P0001'; END IF;
  IF NEW.complimentary_entitlement_epoch IS DISTINCT FROM OLD.complimentary_entitlement_epoch THEN
   RAISE EXCEPTION 'synthetic_funding_mutation' USING ERRCODE='P0001'; END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END;
$$;
CREATE TRIGGER test_funding_tripwire BEFORE INSERT OR UPDATE OR DELETE ON internal.ai_quota_reservations FOR EACH ROW EXECUTE FUNCTION pg_temp.funding_tripwire();
CREATE TRIGGER test_funding_tripwire BEFORE INSERT OR UPDATE OR DELETE ON internal.ai_quota_counters FOR EACH ROW EXECUTE FUNCTION pg_temp.funding_tripwire();
CREATE TRIGGER test_funding_tripwire BEFORE INSERT OR UPDATE OR DELETE ON internal.complimentary_scan_usage FOR EACH ROW EXECUTE FUNCTION pg_temp.funding_tripwire();
CREATE TRIGGER test_funding_tripwire BEFORE INSERT OR UPDATE OR DELETE ON internal.identification_provider_attempts FOR EACH ROW EXECUTE FUNCTION pg_temp.funding_tripwire();
CREATE TRIGGER test_funding_tripwire BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION pg_temp.funding_tripwire();
SELECT set_config('merian.test_funding_tripwire','on',TRUE);
CREATE FUNCTION pg_temp.source_receipt(scan UUID) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE saved internal.initial_analysis_preparation_intents; a JSONB; profile JSONB; entries JSONB;
BEGIN
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=scan;
 a:=saved.canonical_assignment::JSONB;
 SELECT canonical_profile::JSONB INTO STRICT profile FROM internal.initial_preparation_profiles WHERE digest=a#>>'{preparation,profile_digest}';
 SELECT jsonb_agg(jsonb_build_object('ordinal',e->'ordinal','object_id',e->'object_id','bytes',jsonb_build_object('byte_count',e#>'{source,source_byte_count}','sha256',e#>'{source,source_sha256}','content_type',e#>'{source,source_content_type}'),'facts',
 jsonb_build_object('image',CASE WHEN e#>>'{source,kind}'='image' THEN jsonb_build_object('width',1,'height',1,'format',split_part(e#>>'{source,source_content_type}','/',2)) END,
 'wav',CASE WHEN e#>>'{source,kind}'='audio' THEN jsonb_build_object('format','pcm16','sample_rate',16000,'channels',1,'frames',1) END,
 'mp4',CASE WHEN e#>>'{source,kind}'='video' THEN jsonb_build_object('structure','bounded_mp4_accepted') END)) ORDER BY i) INTO entries FROM jsonb_array_elements(a#>'{preparation,source_mapping}') WITH ORDINALITY v(e,i);
 RETURN internal.initial_canonical(jsonb_build_object('version',1,'scan_id',scan,'assignment_digest',saved.assignment_digest,'profile_digest',a#>>'{preparation,profile_digest}','backend_generation',a#>>'{preparation,backend_generation}','validator_identity',profile#>>'{spec,identities,validator}','entries',entries));
END; $$;
CREATE FUNCTION pg_temp.execution_advance(scan UUID,phase INTEGER) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE saved internal.initial_analysis_preparation_intents; response JSONB; grant_value JSONB; entries JSONB; request JSONB; resolved JSONB; outcome JSONB; profile JSONB;
BEGIN
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=scan;
 IF phase=0 THEN RETURN '{}'::JSONB; END IF;
 response:=public.settle_initial_preparation_sources(saved.owner_id,scan,saved.assignment_digest,pg_temp.source_receipt(scan));
 IF phase=1 THEN RETURN response; END IF;
 response:=public.issue_initial_preparation_execution(saved.owner_id,scan,saved.assignment_digest,response->>'digest');
 IF phase=2 THEN RETURN response; END IF;
 grant_value:=response->'grant';
 IF grant_value IS NULL THEN SELECT canonical_grant::JSONB INTO STRICT grant_value FROM internal.initial_preparation_execution_grants WHERE scan_id=scan; END IF;
 SELECT jsonb_agg(jsonb_build_object('ordinal',e->'ordinal','prepared',CASE WHEN e->>'role'<>'raw_video' THEN jsonb_build_object('bytes',jsonb_build_object('byte_count',CASE WHEN e#>>'{source,kind}'='audio' THEN '32'::JSONB ELSE e#>'{source,source_byte_count}' END,'sha256',CASE WHEN e#>>'{source,kind}'='audio' THEN repeat('7',64) ELSE e#>>'{source,source_sha256}' END,'content_type',e#>'{source,source_content_type}'),'transform',e#>'{source,transform}','parameters',e#>'{source,transform_parameters}','source_identity',e#>>'{source,kind}'<>'audio') END) ORDER BY i) INTO entries FROM jsonb_array_elements(saved.canonical_assignment::JSONB#>'{preparation,source_mapping}') WITH ORDINALITY v(e,i);
 request:=jsonb_build_object('version',1,'scan_id',scan,'assignment_digest',saved.assignment_digest,'grant_id',grant_value->'grant_id','source_digest',grant_value->'source_digest','entries',entries);
 IF phase=13 THEN RETURN request; END IF;
 response:=public.register_initial_preparation_output(saved.owner_id,scan,saved.assignment_digest,internal.initial_canonical(request));
 IF phase=3 THEN RETURN response; END IF;
 resolved:=response->'resolved';
 SELECT canonical_profile::JSONB INTO STRICT profile FROM internal.initial_preparation_profiles WHERE digest=saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}';
 SELECT jsonb_agg(jsonb_build_object('ordinal',e->'ordinal','object_id',resolved#>ARRAY['entries',(i-1)::TEXT,'object_id'],'bytes',e#>'{prepared,bytes}') ORDER BY i) INTO entries FROM jsonb_array_elements(request->'entries') WITH ORDINALITY v(e,i) WHERE e->'prepared'<>'null'::JSONB;
 outcome:=jsonb_build_object('version',(grant_value->>'version')::INTEGER,'scan_id',scan,'assignment_digest',saved.assignment_digest,'grant',grant_value,'source_verification',pg_temp.source_receipt(scan)::JSONB,'output_manifest',request,'resolved_manifest',resolved,'profile',profile,'retained',entries);
 IF phase=14 THEN RETURN outcome; END IF;
 RETURN public.settle_initial_preparation_outcome(saved.owner_id,scan,saved.assignment_digest,internal.initial_canonical(outcome));
END; $$;

-- END ATOMIC ADMISSION COMPOSER FIXTURE
-- Durable exact-boundary regression through the complete guarded private owner.
-- Synthetic preparation and privileged composition do not enable a public
-- admission/dispatch lane. Each case rolls back all rows and local settings.
CREATE FUNCTION pg_temp.storage_bound_admission(symbol TEXT) RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
DECLARE scan UUID:=gen_random_uuid(); owner_id UUID:='00000000-0000-4000-8000-00000000f001';
 candidate JSONB; plan JSONB; media JSONB; input_value JSONB; descriptions JSONB;
 unit_bytes INTEGER:=octet_length(to_jsonb(symbol)::TEXT)-2; pad INTEGER; remaining INTEGER;
 stage internal.initial_preparation_admission_staging; receipt internal.initial_preparation_admission_receipts;
 response JSONB; before_replay JSONB; result BOOLEAN:=FALSE; fixture_definition TEXT;
 selected_profile TEXT; new_install TEXT; expected_handoff TEXT; new_selection UUID:=gen_random_uuid(); original_selection UUID;
BEGIN
 SELECT generation INTO STRICT original_selection FROM internal.initial_preparation_current_selection WHERE input_profile='multimodal_video_audio_v1';
 BEGIN
  SELECT v->'candidate' INTO STRICT candidate FROM media_vectors WHERE i=6;
  -- Fresh immutable test-only installation; preserve all seven other phases.
  SELECT pg_get_functiondef('pg_temp.install_handoff(text,uuid)'::REGPROCEDURE) INTO fixture_definition;
  fixture_definition:=replace(replace(replace(fixture_definition,'.install_handoff(','.install_boundary_handoff('),
   '''{phase_ms,admission}'',''60000''','''{phase_ms,admission}'',''140000'''),
   '(h->>''total_ms'')::INTEGER+50000','(h->>''total_ms'')::INTEGER+130000');
  EXECUTE fixture_definition;
  SELECT v->>'profile_digest' INTO STRICT selected_profile FROM media_vectors WHERE i=6;
  new_install:=pg_temp.install_boundary_handoff(selected_profile,'00000000-0000-4000-8000-00000000fb01');
  SELECT profile_digest INTO STRICT expected_handoff FROM internal.initial_preparation_handoff_installations WHERE digest=new_install;
  INSERT INTO internal.initial_preparation_selections(generation,profile_digest,backend_generation,handoff_installation_digest)
   VALUES(new_selection,selected_profile,'00000000-0000-4000-8000-00000000fb01',new_install);
  UPDATE internal.initial_preparation_current_selection SET generation=new_selection WHERE input_profile='multimodal_video_audio_v1';
  IF NOT FOUND THEN RAISE EXCEPTION 'synthetic boundary selector missing'; END IF;
  IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_handoff_eligibility WHERE installation_digest=new_install AND state='eligible') THEN RAISE EXCEPTION 'synthetic boundary installation not eligible'; END IF;
  candidate:=jsonb_set(candidate,'{source_plan,sources}',
   (SELECT jsonb_agg((candidate#>'{source_plan,sources,0}')||jsonb_build_object('input_index',i,'frame_index',i) ORDER BY i) FROM generate_series(0,2) i)
   ||jsonb_build_array(candidate#>'{source_plan,sources,1}',candidate#>'{source_plan,sources,2}'));
  candidate:=jsonb_set(candidate,'{source_plan,capture,declared_video_frame_count}','3');
  candidate:=jsonb_set(candidate,'{source_plan,capture,video_inference_frame_count}','3');
  SELECT jsonb_agg('xx'::TEXT ORDER BY i) INTO descriptions FROM generate_series(1,32) i;
  candidate:=jsonb_set(candidate,'{source_plan,ordered_descriptions}',descriptions);
  candidate:=jsonb_set(candidate,'{source_plan,owner_timeline}',
   jsonb_build_array(jsonb_build_object('kind','media','index',4))||
   (SELECT jsonb_agg(jsonb_build_object('kind','description','index',i) ORDER BY i) FROM generate_series(0,31) i));
  plan:=candidate->'source_plan';
  SELECT jsonb_agg((s-'prepared_output')||jsonb_build_object(
   'content_type',s->'source_content_type','byte_count',CASE WHEN s->>'kind'='audio' THEN '32'::JSONB ELSE s->'source_byte_count' END,
   'sha256',CASE WHEN s->>'kind'='audio' THEN repeat('7',64) ELSE s->>'source_sha256' END) ORDER BY i)
   INTO media FROM jsonb_array_elements(plan->'sources') WITH ORDINALITY x(s,i);
  input_value:=(plan-'sources')||jsonb_build_object('media',media);
  pad:=(1048576-octet_length(internal.initial_canonical(input_value)))/(32*unit_bytes);
  SELECT jsonb_agg('x'||repeat(symbol,pad)||'x' ORDER BY i) INTO descriptions FROM generate_series(1,32) i;
  input_value:=jsonb_set(input_value,'{ordered_descriptions}',descriptions);
  remaining:=1048576-octet_length(internal.initial_canonical(input_value));
  descriptions:=jsonb_set(descriptions,'{31}',to_jsonb((descriptions->>31)||repeat('a',remaining)));
  input_value:=jsonb_set(input_value,'{ordered_descriptions}',descriptions);
  candidate:=jsonb_set(candidate,'{source_plan,ordered_descriptions}',descriptions);
  IF octet_length(internal.initial_canonical(input_value))<>1048576 OR octet_length(internal.initial_canonical(candidate))>1048576 THEN RAISE EXCEPTION 'synthetic boundary construction failed'; END IF;
  UPDATE media_vectors SET v=jsonb_set(v,'{candidate}',candidate) WHERE i=6;
  PERFORM set_config('merian.test_funding_tripwire','off',TRUE);
  UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
  PERFORM pg_temp.media_create(scan,6);
  PERFORM pg_temp.execution_advance(scan,4);
  PERFORM internal.create_initial_admission_stage(owner_id,scan);
  SELECT * INTO STRICT stage FROM internal.initial_preparation_admission_staging WHERE scan_id=scan;
  IF stage.assignment::JSONB#>>'{handoff,installation_digest}' IS DISTINCT FROM new_install
   OR stage.assignment::JSONB#>>'{handoff,profile_digest}' IS DISTINCT FROM expected_handoff
   OR stage.assignment::JSONB#>>'{handoff,profile,phase_ms,admission}' IS DISTINCT FROM '140000'
   OR stage.assignment::JSONB#>>'{handoff,profile,total_ms}' IS DISTINCT FROM '210000'
   OR (stage.phase_window::JSONB#>>'{cutoffs,admission}')::BIGINT-(stage.phase_window::JSONB->>'anchor_ms')::BIGINT<>140000
   OR internal.initial_preparation_cohort_wall(stage.assignment::JSONB,(SELECT canonical_profile::JSONB FROM internal.initial_preparation_profiles WHERE digest=selected_profile))<>10000
   THEN RAISE EXCEPTION 'synthetic boundary budget mismatch'; END IF;
  PERFORM set_config('merian.initial_admission_stage',stage.stage_token::TEXT,TRUE);
  PERFORM set_config('merian.initial_preparation_funding',owner_id::TEXT||':'||scan::TEXT,TRUE);
  PERFORM set_config('merian.initial_analysis_admission',owner_id::TEXT||':'||scan::TEXT,TRUE);
  PERFORM * FROM public.reserve_identification_quota(owner_id,'scan_identification',scan,repeat('a',64),scan,FALSE,3,FALSE,'multimodal_video_audio_v1','google_gemini',6);
  PERFORM internal.materialize_initial_admission(scan);
  PERFORM internal.freeze_initial_admission_ledger(scan);
  PERFORM internal.begin_initial_admission_consumption(scan);
  receipt:=internal.finish_initial_admission(scan);
  SET CONSTRAINTS ALL IMMEDIATE;
  IF receipt.input IS DISTINCT FROM internal.initial_canonical(input_value)
   OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions s WHERE s.scan_id=scan
    AND s.input_snapshot=input_value AND octet_length(s.input_snapshot::TEXT) BETWEEN 1048577 AND 1056766)
   OR (SELECT count(*) FROM internal.initial_analysis_submissions s WHERE s.scan_id=scan)<>1
   OR (SELECT count(*) FROM internal.initial_analysis_admissions a WHERE a.scan_id=scan)<>1
   OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=scan)
   OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id=scan)
   THEN RAISE EXCEPTION 'synthetic boundary persistence mismatch'; END IF;
  before_replay:=to_jsonb(receipt);
  UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;
  SET LOCAL ROLE service_role;
  response:=public.get_initial_preparation_status(owner_id,scan);
  RESET ROLE;
  IF response->>'outcome' IS DISTINCT FROM 'admitted' OR response->>'authority' IS DISTINCT FROM 'none'
   OR response->>'admission_receipt_digest' IS DISTINCT FROM receipt.receipt_digest
   OR before_replay IS DISTINCT FROM (SELECT to_jsonb(r) FROM internal.initial_preparation_admission_receipts r WHERE r.scan_id=scan)
   OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=scan)
   THEN RAISE EXCEPTION 'synthetic boundary recovery mismatch'; END IF;
  result:=TRUE;
  RAISE EXCEPTION 'rollback successful boundary fixture' USING ERRCODE='ZX731';
 EXCEPTION WHEN SQLSTATE 'ZX731' THEN NULL;
 END;
 RETURN result AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=scan)
  AND (SELECT generation FROM internal.initial_preparation_current_selection WHERE input_profile='multimodal_video_audio_v1')=original_selection
  AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_selections WHERE generation=new_selection)
  AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_handoff_installations WHERE digest=new_install)
  AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_handoff_profiles WHERE digest=expected_handoff);
END; $$;
SELECT extensions.ok(pg_temp.storage_bound_admission(symbol),label||' exact input ceiling materializes and recovers original status metadata')
 FROM (VALUES ('plain','a'),('escaped',chr(1)),('non-BMP',chr(128998))) x(label,symbol);

-- Start the ordinary seed after long boundary cases so its original lifetime
-- covers its own preparation/stage assertions. No production cutoff is changed.
SELECT extensions.lives_ok($q$SELECT pg_temp.media_create('00000000-0000-4000-8000-000000005522',1)$q$,'synthetic media preparation');
SELECT extensions.lives_ok($q$SELECT pg_temp.execution_advance('00000000-0000-4000-8000-000000005522',4)$q$,'synthetic qualified preparation outcome');
CREATE FUNCTION pg_temp.flush_partial_admission() RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 PERFORM internal.create_initial_admission_stage('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-000000005522');
 SET CONSTRAINTS internal.require_complete_initial_admission IMMEDIATE;
END; $$;
SELECT extensions.throws_ok('SELECT pg_temp.flush_partial_admission()',
 '55000','initial_analysis_admission_incomplete','early constraint flush cannot accept partial stage');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_admission_staging),0::BIGINT,
 'failed complete-state check rolls back the inserted stage');
-- Remaining helper/owner-image probes deliberately retain incomplete stages and
-- corrupt them in rollback subtransactions. Disable only the incomplete-owner
-- commit sentinel before any stage exists; permanent row guards stay active.
ALTER TABLE internal.initial_preparation_admission_staging DISABLE TRIGGER require_complete_initial_admission;
SELECT extensions.lives_ok($q$SELECT internal.create_initial_admission_stage('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-000000005522')$q$,'stage constructor validates original proof');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005522'),1::BIGINT,'one private stage');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-000000005522' OR original_analysis_id='00000000-0000-4000-8000-000000005522'),0::BIGINT,'constructor supplies no funding');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id='00000000-0000-4000-8000-000000005522'),0::BIGINT,'constructor supplies no M1 allocation');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_admission_receipts WHERE scan_id='00000000-0000-4000-8000-000000005522'),0::BIGINT,'constructor supplies no receipt authority');

-- Permanent private-row guards: these run without disabling any guard.
SELECT extensions.throws_ok($q$UPDATE internal.initial_preparation_admission_staging SET candidate=candidate||' ' WHERE scan_id='00000000-0000-4000-8000-000000005522'$q$,
 '55000','initial_analysis_preparation_required','immutable stage proof cannot be rewritten');
SELECT extensions.throws_ok($q$DELETE FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005522'$q$,
 '55000','initial_analysis_preparation_required','raw stage deletion cannot recycle operation');
SELECT extensions.throws_ok('TRUNCATE internal.initial_preparation_admission_staging CASCADE',
 '55000','initial_analysis_preparation_required','stage truncate cannot bypass row guard');
CREATE FUNCTION pg_temp.private_admission_role_denial(role_name TEXT,command TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
BEGIN
 EXECUTE format('SET LOCAL ROLE %I',role_name);
 EXECUTE command;
 RAISE EXCEPTION 'synthetic_unexpected_role_access';
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE;
END; $$;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,command),'42501',role_name||' denied private admission '||label)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
CROSS JOIN (VALUES
 ('stage read','SELECT * FROM internal.initial_preparation_admission_staging'),
 ('stage write','DELETE FROM internal.initial_preparation_admission_staging'),
 ('expectation read','SELECT * FROM internal.initial_preparation_admission_writes'),
 ('expectation write','DELETE FROM internal.initial_preparation_admission_writes'),
 ('receipt read','SELECT * FROM internal.initial_preparation_admission_receipts'),
 ('constructor','SELECT internal.create_initial_admission_stage(NULL,NULL)'),
 ('expectation consumption','SELECT internal.initial_admission_expected_write(NULL,NULL,NULL,NULL,NULL,TRUE)')
) commands(label,command);

CREATE FUNCTION pg_temp.freeze_actual_stage() RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE actual RECORD; sampled TIMESTAMPTZ:=clock_timestamp();
BEGIN
 SELECT * INTO STRICT actual FROM internal.resolve_fresh_quota_entitlement('00000000-0000-4000-8000-00000000f001','scan_identification','00000000-0000-4000-8000-000000005522',FALSE,sampled);
 PERFORM internal.freeze_initial_admission_policy('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-000000005522',actual.effective_plan,actual.flash_fallback_used,actual.complimentary_client_scan_id,actual.acquire_complimentary_hold,sampled);
END; $$;
SELECT extensions.throws_ok('SELECT pg_temp.freeze_actual_stage()','55000','initial_analysis_preparation_required','missing stage token denies freeze');
SELECT set_config('merian.initial_admission_stage',(SELECT stage_token::TEXT FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005522'),TRUE);
-- Trusted rollback-only fixture removes otherwise immutable synthetic receipts.
-- The exception subtransaction restores both rows and trigger definitions.
CREATE FUNCTION pg_temp.freeze_without_receipt(relation_name REGCLASS) RETURNS TEXT LANGUAGE PLPGSQL AS $$
BEGIN
 EXECUTE format('ALTER TABLE %s DISABLE TRIGGER USER',relation_name);
 EXECUTE format('DELETE FROM %s WHERE user_id=%L',relation_name,'00000000-0000-4000-8000-00000000f001');
 PERFORM pg_temp.freeze_actual_stage();
 RAISE EXCEPTION 'synthetic_missing_receipt_accepted';
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE||':'||SQLERRM;
END; $$;
SELECT extensions.is(pg_temp.freeze_without_receipt(relation_name::REGCLASS),
 '55000:initial_analysis_configuration_unavailable','missing prelocked receipt denied: '||relation_name)
FROM unnest(ARRAY['public.user_adult_eligibility_receipts','public.user_terms_acceptance_receipts','public.user_ai_consent_events']) relation_name;
SELECT extensions.is((SELECT phase FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005522'),'validated','missing-receipt failures do not advance stage');
SELECT extensions.lives_ok('SELECT pg_temp.freeze_actual_stage()','actual original entitlement projection freezes policy');
SELECT extensions.throws_ok('SELECT pg_temp.freeze_actual_stage()','55000','initial_analysis_preparation_required','second freeze denied');

SELECT extensions.throws_ok($q$UPDATE internal.initial_preparation_admission_staging SET policy=NULL WHERE scan_id='00000000-0000-4000-8000-000000005522'$q$,
 '55000','initial_analysis_preparation_required','frozen policy cannot be cleared');
SELECT extensions.throws_ok($q$UPDATE internal.initial_preparation_admission_staging SET core4_at=clock_timestamp(),input=input||' ' WHERE scan_id='00000000-0000-4000-8000-000000005522'$q$,
 '55000','initial_analysis_preparation_required','one-time clock write cannot conceal input mutation');
SELECT extensions.throws_ok($q$UPDATE internal.initial_preparation_admission_staging SET phase='reserved' WHERE scan_id='00000000-0000-4000-8000-000000005522'$q$,
 '55000','initial_analysis_preparation_required','phase advancement stays closed without complete finalizer');

SELECT set_config('merian.quota_v2_fence','on',TRUE);
SELECT set_config('merian.entitlement_plan_override',(SELECT (policy).effective_plan FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005522'),TRUE);
SELECT extensions.lives_ok($q$SELECT internal.initial_admission_frozen_policy('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-000000005522',current_setting('merian.entitlement_plan_override'))$q$,'core4 seam reads original frozen policy');
SELECT extensions.throws_ok($q$SELECT internal.initial_admission_frozen_policy('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-000000005522','invalid')$q$,'55000','initial_analysis_preparation_required','mismatched override denied');
UPDATE internal.ai_quota_policies SET user_rate_bucket='synthetic_after_freeze' WHERE operation='scan_identification';
SELECT extensions.ok((SELECT (internal.initial_admission_frozen_policy('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-000000005522',current_setting('merian.entitlement_plan_override'))).user_rate_bucket)<>'synthetic_after_freeze','core4 seam does not reselect mutable policy');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-000000005522'),0::BIGINT,'comparison acquires no hold');


-- Exercise the actual counter owner and PostgreSQL UPSERT trigger ordering.
-- This verifies write expectations only, not the unimplemented funded owner.
SELECT set_config('merian.test_funding_tripwire','off',TRUE);
CREATE FUNCTION pg_temp.counter_expected(consume BOOLEAN) RETURNS BOOLEAN LANGUAGE SQL AS $$
 SELECT internal.initial_admission_expected_write('00000000-0000-4000-8000-000000005522',
  'internal.ai_quota_counters','INSERT',NULL,jsonb_build_object('scope_type','user_rate',
   'scope_key','synthetic_atomic_counter','bucket','synthetic_atomic_counter',
   'window_start',date_trunc('minute',now()),'window_seconds',60,'request_count',1,'updated_at',now()),consume)
$$;
CREATE FUNCTION pg_temp.counter_write_guard() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF NEW.scope_key='synthetic_atomic_counter' AND NOT internal.initial_admission_expected_write(
    '00000000-0000-4000-8000-000000005522','internal.ai_quota_counters',TG_OP,
    CASE WHEN TG_OP='UPDATE' THEN to_jsonb(OLD) END,to_jsonb(NEW),TG_WHEN='AFTER') THEN
  RAISE EXCEPTION 'synthetic_counter_write_denied' USING ERRCODE='55000';
 END IF;
 RETURN NEW;
END; $$;
CREATE FUNCTION pg_temp.register_counter_expectation() RETURNS VOID LANGUAGE SQL AS $$
 SELECT internal.register_initial_admission_write('00000000-0000-4000-8000-000000005522',
  'Counter.user.upsert','internal.ai_quota_counters','UPSERT',NULL,
  jsonb_build_object('scope_type','user_rate','scope_key','synthetic_atomic_counter','bucket','synthetic_atomic_counter',
   'window_start',date_trunc('minute',now()),'window_seconds',60,'limit',5,'updated_at',now()))
$$;
CREATE FUNCTION pg_temp.charge_expected_counter() RETURNS INTEGER LANGUAGE SQL AS $$
 SELECT internal.consume_ai_quota_counter('user_rate','synthetic_atomic_counter','synthetic_atomic_counter',
  date_trunc('minute',now()),60,5,'synthetic_counter_limit')
$$;
SELECT extensions.throws_ok('SELECT pg_temp.charge_expected_counter()','55000','initial_analysis_preparation_required','counter cannot charge without expectation');
SELECT extensions.lives_ok('SELECT pg_temp.register_counter_expectation()','closed counter expectation registered');
SELECT extensions.throws_ok('SELECT pg_temp.register_counter_expectation()','23505',NULL,'duplicate expected statement denied');
SELECT extensions.ok(pg_temp.counter_expected(FALSE),'BEFORE insert projection accepted without consumption');
SELECT extensions.ok(NOT consumed,'BEFORE projection retains expectation') FROM internal.initial_preparation_admission_writes WHERE statement_key='Counter.user.upsert';
SELECT extensions.is(pg_temp.charge_expected_counter(),1,'actual counter owner inserts one original charge');
SELECT extensions.ok(consumed,'winning AFTER insert consumes exactly once') FROM internal.initial_preparation_admission_writes WHERE statement_key='Counter.user.upsert';
SELECT extensions.ok(observed_operation='INSERT' AND observed_old_image IS NULL AND (observed_new_image->>'request_count')::INTEGER=1,
 'actual INSERT retains winning new counter image without old image') FROM internal.initial_preparation_admission_writes WHERE statement_key='Counter.user.upsert';

SELECT extensions.throws_ok($q$UPDATE internal.initial_preparation_admission_writes SET consumed=FALSE WHERE statement_key='Counter.user.upsert'$q$,
 '55000','initial_analysis_preparation_required','consumed expectation cannot be reopened');
SELECT extensions.throws_ok($q$DELETE FROM internal.initial_preparation_admission_writes WHERE statement_key='Counter.user.upsert'$q$,
 '55000','initial_analysis_preparation_required','raw expectation deletion is denied');
SELECT extensions.throws_ok('TRUNCATE internal.initial_preparation_admission_writes',
 '55000','initial_analysis_preparation_required','expectation truncate cannot bypass row guard');
SELECT extensions.throws_ok($q$UPDATE internal.initial_preparation_admission_writes SET new_image=new_image||'{"limit":6}'::JSONB WHERE statement_key='Counter.user.upsert'$q$,
 '55000','initial_analysis_preparation_required','expected charge image is immutable');

SELECT extensions.throws_ok('SELECT pg_temp.charge_expected_counter()','55000','initial_analysis_preparation_required','consumed expectation cannot be replayed');
-- Trusted fixture resets only the private test expectation to exercise conflict
-- UPDATE on the same real counter owner; production stage guards must deny this.
ALTER TABLE internal.initial_preparation_admission_writes DISABLE TRIGGER guard_initial_admission_expectation;
 ALTER TABLE internal.initial_preparation_admission_writes DISABLE TRIGGER advance_initial_admission_cleanup;
DELETE FROM internal.initial_preparation_admission_writes WHERE statement_key='Counter.user.upsert';
ALTER TABLE internal.initial_preparation_admission_writes ENABLE TRIGGER guard_initial_admission_expectation;
 ALTER TABLE internal.initial_preparation_admission_writes ENABLE TRIGGER advance_initial_admission_cleanup;
-- Trusted reset of a synthetic expectation also resets its event counter. No
-- runtime delete/reset path is enabled by this fixture-only guard suspension.
ALTER TABLE internal.initial_preparation_admission_staging DISABLE TRIGGER guard_initial_admission_stage;
UPDATE internal.initial_preparation_admission_staging st SET completion_event_seq=(SELECT count(*) FROM internal.initial_preparation_admission_writes w WHERE w.scan_id=st.scan_id AND w.consumed);
ALTER TABLE internal.initial_preparation_admission_staging ENABLE TRIGGER guard_initial_admission_stage;

SELECT pg_temp.register_counter_expectation();
SELECT extensions.is(pg_temp.charge_expected_counter(),2,'actual UPSERT conflict executes BEFORE insert/update and one winning AFTER update');
SELECT extensions.ok(consumed,'winning AFTER update consumes once') FROM internal.initial_preparation_admission_writes WHERE statement_key='Counter.user.upsert';
SELECT extensions.ok(observed_operation='UPDATE' AND (observed_old_image->>'request_count')::INTEGER=1 AND (observed_new_image->>'request_count')::INTEGER=2,
 'actual conflict UPDATE retains old and new counts, not BEFORE INSERT probe') FROM internal.initial_preparation_admission_writes WHERE statement_key='Counter.user.upsert';
ALTER TABLE internal.initial_preparation_admission_writes DISABLE TRIGGER guard_initial_admission_expectation;
 ALTER TABLE internal.initial_preparation_admission_writes DISABLE TRIGGER advance_initial_admission_cleanup;
DELETE FROM internal.initial_preparation_admission_writes WHERE statement_key='Counter.user.upsert';
ALTER TABLE internal.initial_preparation_admission_writes ENABLE TRIGGER guard_initial_admission_expectation;
 ALTER TABLE internal.initial_preparation_admission_writes ENABLE TRIGGER advance_initial_admission_cleanup;
-- Trusted reset of a synthetic expectation also resets its event counter. No
-- runtime delete/reset path is enabled by this fixture-only guard suspension.
ALTER TABLE internal.initial_preparation_admission_staging DISABLE TRIGGER guard_initial_admission_stage;
UPDATE internal.initial_preparation_admission_staging st SET completion_event_seq=(SELECT count(*) FROM internal.initial_preparation_admission_writes w WHERE w.scan_id=st.scan_id AND w.consumed);
ALTER TABLE internal.initial_preparation_admission_staging ENABLE TRIGGER guard_initial_admission_stage;

SELECT pg_temp.register_counter_expectation();
SELECT extensions.throws_ok($q$UPDATE internal.ai_quota_counters SET request_count=request_count+2 WHERE scope_key='synthetic_atomic_counter'$q$,
 '55000','initial_analysis_preparation_required','counter delta greater than one denied');
SELECT extensions.throws_ok($q$UPDATE internal.ai_quota_counters SET bucket='different',request_count=request_count+1 WHERE scope_key='synthetic_atomic_counter'$q$,
 '55000','initial_analysis_preparation_required','counter key rewrite denied');
SELECT extensions.throws_ok($q$UPDATE internal.initial_preparation_admission_writes SET consumed=TRUE WHERE statement_key='Counter.user.upsert'$q$,
 '55000','initial_analysis_preparation_required','raw expectation consumption cannot mint a member event');
SELECT extensions.throws_ok($q$UPDATE internal.initial_preparation_admission_staging SET completion_event_seq=completion_event_seq+1 WHERE scan_id='00000000-0000-4000-8000-000000005522'$q$,
 '55000','initial_analysis_admission_incomplete','raw sequence update cannot forge a deferred member event');
SELECT extensions.ok(NOT consumed,'rejected writes preserve expectation for original statement') FROM internal.initial_preparation_admission_writes WHERE statement_key='Counter.user.upsert';
SELECT extensions.is((SELECT request_count FROM internal.ai_quota_counters WHERE scope_key='synthetic_atomic_counter'),2,'rejected writes preserve original charge');
SELECT set_config('merian.initial_admission_stage','00000000-0000-4000-8000-000000000000',TRUE);
SELECT extensions.ok(NOT pg_temp.counter_expected(FALSE),'wrong stage token rejects matching expected image');
SELECT set_config('merian.initial_admission_stage',(SELECT stage_token::TEXT FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005522'),TRUE);
-- Trusted phase-corruption probe tests the expected-image defense independently.
ALTER TABLE internal.initial_preparation_admission_staging DISABLE TRIGGER guard_initial_admission_stage;
UPDATE internal.initial_preparation_admission_staging SET phase='reserved' WHERE scan_id='00000000-0000-4000-8000-000000005522';
SELECT extensions.ok(NOT pg_temp.counter_expected(FALSE),'funding image cannot authorize a later admission phase');
UPDATE internal.initial_preparation_admission_staging SET phase='compared' WHERE scan_id='00000000-0000-4000-8000-000000005522';
ALTER TABLE internal.initial_preparation_admission_staging ENABLE TRIGGER guard_initial_admission_stage;
SELECT extensions.ok(NOT pg_temp.counter_expected(NULL),'null consumption mode cannot authorize a write');
SELECT set_config('merian.test_funding_tripwire','on',TRUE);

-- The public finalizer stays closed while the private owner stages are assembled.
SELECT extensions.lives_ok($q$SELECT pg_temp.media_create('00000000-0000-4000-8000-000000005533',1)$q$,'second synthetic preparation for original-owner boundary');
SELECT extensions.lives_ok($q$SELECT pg_temp.execution_advance('00000000-0000-4000-8000-000000005533',4)$q$,'second synthetic prepared outcome');
SELECT internal.create_initial_admission_stage('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-000000005533');
SELECT set_config('merian.initial_admission_stage',(SELECT stage_token::TEXT FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005533'),TRUE);
SELECT set_config('merian.initial_preparation_funding','00000000-0000-4000-8000-00000000f001:00000000-0000-4000-8000-000000005533',TRUE);
SELECT set_config('merian.initial_analysis_admission','00000000-0000-4000-8000-00000000f001:00000000-0000-4000-8000-000000005533',TRUE);
SELECT extensions.throws_ok($q$SELECT public.finalize_initial_preparation('00000000-0000-4000-8000-00000000f001',
 '00000000-0000-4000-8000-000000005533',repeat('a',64))$q$,
 '55000','initial_analysis_preparation_required','public finalizer stays closed until coherent cutover');
SELECT extensions.is((SELECT phase FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005533'),'validated','blocked original owner rolls back comparison stage');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-000000005533'),0::BIGINT,'blocked original owner leaves no reservation');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_admission_writes WHERE scan_id='00000000-0000-4000-8000-000000005533'),0::BIGINT,'blocked original owner leaves no expected writes');

-- All permanent source/member guards remain enabled. The incomplete-stage
-- sentinel is disabled above only to probe private phases inside rollback.
SELECT set_config('merian.test_funding_tripwire','off',TRUE);
SELECT set_config('merian.test_atomic_scan','00000000-0000-4000-8000-000000005533',TRUE);
CREATE TEMP TABLE nested_owner_probes(kind TEXT,denial TEXT,expectations_unchanged BOOLEAN);
CREATE FUNCTION pg_temp.nested_original_owner_probe() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
DECLARE before_writes JSONB; after_writes JSONB; failure TEXT; owner UUID; kind TEXT;
BEGIN
 IF pg_trigger_depth()<>1 THEN RETURN NEW; END IF;
 SELECT owner_id INTO owner FROM internal.initial_preparation_admission_staging
  WHERE stage_token::TEXT=current_setting('merian.initial_admission_stage',TRUE);
 IF owner IS NULL THEN RETURN NEW; END IF;
 SELECT jsonb_agg(to_jsonb(w) ORDER BY scan_id,statement_key) INTO before_writes FROM internal.initial_preparation_admission_writes w;
 BEGIN
  IF TG_TABLE_NAME='ai_quota_counters' THEN
   kind:='counter:'||NEW.scope_type;
   PERFORM * FROM internal.reserve_ai_quota_core(owner,'scan_identification',
    '00000000-0000-4000-8000-000000005590',repeat('a',64));
  ELSE
   kind:='epoch';
   PERFORM * FROM internal.reserve_ai_quota_core(owner,'scan_identification',
    '00000000-0000-4000-8000-000000005591',repeat('a',64),
    '00000000-0000-4000-8000-000000005591',FALSE,3,FALSE);
  END IF;
  failure:='unexpected_nested_owner_accepted';
 EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM;
 END;
 SELECT jsonb_agg(to_jsonb(w) ORDER BY scan_id,statement_key) INTO after_writes FROM internal.initial_preparation_admission_writes w;
 INSERT INTO nested_owner_probes VALUES(kind,failure,before_writes IS NOT DISTINCT FROM after_writes);
 RETURN NEW;
END; $$;
-- Inject the unrelated real owner immediately before the legitimate shared-row
-- write. Same xid/user/IP/transaction now() and a live stage expectation apply.
CREATE TRIGGER aa_test_nested_original_owner BEFORE INSERT OR UPDATE ON internal.ai_quota_counters
 FOR EACH ROW EXECUTE FUNCTION pg_temp.nested_original_owner_probe();
CREATE TRIGGER aa_test_nested_original_owner BEFORE UPDATE OF complimentary_entitlement_epoch ON public.users
 FOR EACH ROW EXECUTE FUNCTION pg_temp.nested_original_owner_probe();

CREATE FUNCTION pg_temp.probe_original_owner_images(p_scan UUID DEFAULT '00000000-0000-4000-8000-000000005533', input_profile TEXT DEFAULT 'vision_compat_v1', processor_permission TEXT DEFAULT 'google_gemini') RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 PERFORM * FROM public.reserve_identification_quota('00000000-0000-4000-8000-00000000f001','scan_identification',
  p_scan,repeat('a',64),p_scan,FALSE,3,FALSE,
  input_profile,processor_permission,6);
END; $$;
SELECT extensions.throws_ok($q$SELECT * FROM public.reserve_identification_quota('00000000-0000-4000-8000-00000000f001','scan_identification',
 '00000000-0000-4000-8000-000000005533',repeat('a',64),'00000000-0000-4000-8000-000000005533',FALSE,2,FALSE,
 'vision_compat_v1','google_gemini',6)$q$,'55000','initial_analysis_preparation_required','provider owner rejects mismatched saved client protocol before funding');
SELECT extensions.lives_ok('SELECT pg_temp.probe_original_owner_images()','original funding and provider statements match exact expected images');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-000000005533'),1::BIGINT,'one original reservation in rollback-only image probe');
SELECT extensions.lives_ok($q$SELECT internal.build_initial_admission_accounting('00000000-0000-4000-8000-000000005533')$q$,'trial accounting proof is constructed from actual original rows');
SELECT extensions.is(internal.build_initial_admission_accounting('00000000-0000-4000-8000-000000005533')::JSONB->'complimentary','null'::JSONB,'trial accounting has no complimentary witness');

SELECT extensions.lives_ok($q$SELECT internal.build_initial_admission_receipt('00000000-0000-4000-8000-000000005533')$q$,
 'trial receipt assembly validates all components without a complimentary hold');
SELECT extensions.throws_ok($q$SELECT internal.build_initial_admission_receipt('00000000-0000-4000-8000-000000005522')$q$,
 '55000','initial_analysis_preparation_required','receipt assembly denies a different stage token and incomplete funding');


SELECT extensions.is((SELECT count(*) FROM internal.identification_provider_attempts a JOIN internal.ai_quota_reservations r ON r.id=a.reservation_id WHERE r.request_id='00000000-0000-4000-8000-000000005533'),1::BIGINT,'one original provider assignment in rollback-only image probe');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_admission_writes WHERE scan_id='00000000-0000-4000-8000-000000005533' AND NOT consumed),0::BIGINT,'every original owner expectation consumed once');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_admission_receipts WHERE scan_id='00000000-0000-4000-8000-000000005533'),0::BIGINT,'owner image probe is not a durable admitted receipt');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id='00000000-0000-4000-8000-000000005533'),0::BIGINT,'owner image probe supplies no M1 objects');
SELECT extensions.is((SELECT count(*) FROM internal.identification_invocations WHERE scan_id='00000000-0000-4000-8000-000000005533'),0::BIGINT,'owner image probe supplies no provider dispatch');
SELECT extensions.throws_ok('SELECT pg_temp.probe_original_owner_images()','55000','initial_analysis_preparation_required','used owner stage cannot repeat funding');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
SELECT extensions.lives_ok($q$SELECT pg_temp.media_create('00000000-0000-4000-8000-000000005544',1)$q$,'complimentary preparation');
SELECT extensions.lives_ok($q$SELECT pg_temp.execution_advance('00000000-0000-4000-8000-000000005544',4)$q$,'complimentary prepared outcome');
SELECT internal.create_initial_admission_stage('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-000000005544');
SELECT set_config('merian.initial_admission_stage',(SELECT stage_token::TEXT FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005544'),TRUE);
SELECT set_config('merian.initial_preparation_funding','00000000-0000-4000-8000-00000000f001:00000000-0000-4000-8000-000000005544',TRUE);
SELECT set_config('merian.initial_analysis_admission','00000000-0000-4000-8000-00000000f001:00000000-0000-4000-8000-000000005544',TRUE);
SELECT set_config('merian.test_atomic_scan','00000000-0000-4000-8000-000000005544',TRUE);
CREATE TEMP TABLE before_atomic_hold AS SELECT complimentary_entitlement_epoch epoch,entitlement_version version FROM public.users WHERE id='00000000-0000-4000-8000-00000000f001';
SELECT extensions.lives_ok($q$SELECT pg_temp.probe_original_owner_images('00000000-0000-4000-8000-000000005544')$q$,'original complimentary owner hold and entitlement trigger match expected images');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_admission_writes WHERE scan_id='00000000-0000-4000-8000-000000005544' AND NOT consumed),0::BIGINT,'complimentary owner consumes every expected statement');
SELECT extensions.ok((SELECT consumed FROM internal.initial_preparation_admission_writes WHERE scan_id='00000000-0000-4000-8000-000000005544' AND statement_key='C8.hold.insert'),'original hold insert consumed');
SELECT extensions.ok((SELECT consumed FROM internal.initial_preparation_admission_writes WHERE scan_id='00000000-0000-4000-8000-000000005544' AND statement_key='C8.epoch.update'),'post-entitlement-trigger user image consumed');
SELECT extensions.is((SELECT complimentary_entitlement_epoch FROM public.users WHERE id='00000000-0000-4000-8000-00000000f001'),(SELECT epoch+1 FROM before_atomic_hold),'hold increments complimentary epoch exactly once');
SELECT extensions.is((SELECT entitlement_version FROM public.users WHERE id='00000000-0000-4000-8000-00000000f001'),(SELECT version+1 FROM before_atomic_hold),'original BEFORE trigger increments entitlement version exactly once');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-000000005544'),'held','original complimentary charge stays held');
SELECT extensions.lives_ok($q$SELECT internal.build_initial_admission_accounting('00000000-0000-4000-8000-000000005544')$q$,'complimentary accounting proof is constructed from actual original rows');
SELECT extensions.is(internal.build_initial_admission_accounting('00000000-0000-4000-8000-000000005544')::JSONB#>>'{complimentary,state_at_admission}','held','complimentary proof retains original held-at-admission witness');

CREATE TEMP TABLE prospective_receipt AS SELECT r.* FROM internal.build_initial_admission_receipt('00000000-0000-4000-8000-000000005544') r;
SELECT extensions.is(receipt_digest,internal.validate_initial_admitted_proof(candidate,input,configuration,funding,outcome,
 installation,protocol,destination,mapping,media_binding,accounting,manifest),'assembled actual-owner receipt passes complete accepted SQL parity') FROM prospective_receipt;
SELECT extensions.is((SELECT count(*) FROM jsonb_each((SELECT manifest::JSONB->'proof' FROM prospective_receipt))),9::BIGINT,'manifest commits all nine proof components');
SELECT extensions.is((SELECT count(*) FROM jsonb_each((SELECT manifest::JSONB->'metadata' FROM prospective_receipt))),2::BIGINT,'manifest commits both exact metadata components');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_admission_receipts),0::BIGINT,'prospective receipt assembly creates no durable admission');
SELECT extensions.is((SELECT phase FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005544'),'compared','receipt assembly cannot advance stage');
SELECT extensions.is(r.input,s.input,'receipt preserves exact original projected input bytes') FROM prospective_receipt r JOIN internal.initial_preparation_admission_staging s USING(scan_id);
SELECT extensions.is(r.accounting::JSONB#>>'{reservation,lease_token}',s.lease_token::TEXT,'receipt binds original lease without renewal') FROM prospective_receipt r JOIN internal.initial_preparation_admission_staging s USING(scan_id);
SELECT extensions.is(r.funding::JSONB#>>'{original,reservation_id}',s.reservation_id::TEXT,'funding component binds original owner reservation') FROM prospective_receipt r JOIN internal.initial_preparation_admission_staging s USING(scan_id);

SELECT extensions.is((SELECT count(*) FROM prospective_receipt r CROSS JOIN LATERAL jsonb_each_text(to_jsonb(r)) x(k,v)
 WHERE k=ANY(ARRAY['candidate','input','configuration','funding','outcome','installation','protocol','destination','mapping','media_binding','accounting','manifest']) AND v IS NOT NULL),12::BIGINT,
 'prospective receipt co-retains all twelve canonical components');
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,
 'SELECT internal.build_initial_admission_receipt(NULL)'),'42501',role_name||' denied prospective receipt builder')
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
CREATE FUNCTION pg_temp.expired_prospective_receipt() RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 -- Corrupt only the time boundary in this rollback subtransaction to isolate
 -- the runtime expiry check from immutable-stage enforcement.
 ALTER TABLE internal.initial_preparation_admission_staging DISABLE TRIGGER guard_initial_admission_stage;
 UPDATE internal.initial_preparation_admission_staging SET phase_window=internal.initial_canonical(
  jsonb_set(phase_window::JSONB,'{cutoffs,admission}','0'::JSONB)) WHERE scan_id='00000000-0000-4000-8000-000000005544';
 PERFORM internal.build_initial_admission_receipt('00000000-0000-4000-8000-000000005544');
END; $$;
SELECT extensions.throws_ok('SELECT pg_temp.expired_prospective_receipt()','55000','initial_analysis_preparation_expired',
 'receipt builder checks current admission cutoff rather than extending the lease');


SELECT extensions.is(internal.initial_admission_timestamp('2026-10-12T00:01:02.123456Z'::TIMESTAMPTZ),'2026-10-12T00:01:02.123456Z','timestamp encoder preserves all six fractional digits');
SELECT extensions.throws_ok($q$SELECT internal.initial_admission_timestamp('infinity'::TIMESTAMPTZ)$q$,'22023','initial_analysis_input_invalid','timestamp encoder rejects infinity');
SELECT extensions.throws_ok($q$SELECT internal.initial_admission_timestamp('10000-01-01'::TIMESTAMPTZ)$q$,'22023','initial_analysis_input_invalid','timestamp encoder rejects extended year');
CREATE FUNCTION pg_temp.accounting_fault(fault TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE rid UUID;
BEGIN
 -- Deliberate corruption is independent defense-in-depth evidence. The
 -- exception subtransaction restores the rows and both permanent guards.
 ALTER TABLE internal.initial_preparation_admission_staging DISABLE TRIGGER guard_initial_admission_stage;
 ALTER TABLE internal.initial_preparation_admission_writes DISABLE TRIGGER guard_initial_admission_expectation;
 ALTER TABLE internal.initial_preparation_admission_writes DISABLE TRIGGER advance_initial_admission_cleanup;
 SELECT reservation_id INTO STRICT rid FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005544';
 IF fault='null_policy' THEN
  UPDATE internal.initial_preparation_admission_staging SET policy=NULL WHERE scan_id='00000000-0000-4000-8000-000000005544';
 ELSIF fault='missing_reserve_clock' THEN
  UPDATE internal.initial_preparation_admission_staging SET core4_at=NULL WHERE scan_id='00000000-0000-4000-8000-000000005544';
 ELSIF fault='changed_policy' THEN
  UPDATE internal.initial_preparation_admission_staging SET policy=jsonb_populate_record(policy,jsonb_build_object('policy_version',(policy).policy_version+1)) WHERE scan_id='00000000-0000-4000-8000-000000005544';
 ELSIF fault='unconsumed' THEN
  UPDATE internal.initial_preparation_admission_writes SET consumed=FALSE,observed_operation=NULL,observed_old_image=NULL,observed_new_image=NULL WHERE scan_id='00000000-0000-4000-8000-000000005544' AND statement_key='Provider.attempt.insert';
 ELSIF fault='missing_expectation' THEN
  DELETE FROM internal.initial_preparation_admission_writes WHERE scan_id='00000000-0000-4000-8000-000000005544' AND statement_key='C4.user.link';
 ELSIF fault='missing_link' THEN
  ALTER TABLE internal.ai_quota_reservation_counters DISABLE TRIGGER zz_initial_admission_member_before;
  ALTER TABLE internal.ai_quota_reservation_counters DISABLE TRIGGER zz_initial_admission_member_after;
  DELETE FROM internal.ai_quota_reservation_counters WHERE reservation_id=rid AND scope_type='user_rate';
 ELSIF fault='changed_lease' THEN
  ALTER TABLE internal.ai_quota_reservations DISABLE TRIGGER zz_initial_admission_member_before;
  ALTER TABLE internal.ai_quota_reservations DISABLE TRIGGER zz_initial_admission_member_after;
  UPDATE internal.ai_quota_reservations SET lease_token=gen_random_uuid() WHERE id=rid;
 ELSIF fault='changed_window' THEN
  ALTER TABLE internal.ai_quota_counters DISABLE TRIGGER zz_initial_admission_member_before;
  ALTER TABLE internal.ai_quota_counters DISABLE TRIGGER zz_initial_admission_member_after;
  UPDATE internal.ai_quota_counters c SET window_seconds=window_seconds+1 FROM internal.ai_quota_reservation_counters l
   WHERE l.reservation_id=rid AND l.scope_type='user_rate' AND c.scope_type=l.scope_type AND c.scope_key=l.scope_key AND c.bucket=l.bucket AND c.window_start=l.window_start;
 END IF;
 PERFORM internal.build_initial_admission_accounting('00000000-0000-4000-8000-000000005544');
 RAISE EXCEPTION 'synthetic_accounting_fault_accepted';
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE||':'||SQLERRM;
END; $$;
SELECT extensions.is(pg_temp.accounting_fault(fault),'55000:initial_analysis_preparation_required','incomplete original expectation set denied: '||fault)
FROM unnest(ARRAY['unconsumed','missing_expectation','null_policy','missing_reserve_clock']) fault;
SELECT extensions.is(pg_temp.accounting_fault(fault),'22023:initial_analysis_identity_conflict','changed original accounting row denied: '||fault)
FROM unnest(ARRAY['missing_link','changed_lease','changed_window','changed_policy']) fault;
CREATE FUNCTION pg_temp.accounting_shared_counter() RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
DECLARE before_text TEXT; after_text TEXT; rid UUID;
BEGIN
 before_text:=internal.build_initial_admission_accounting('00000000-0000-4000-8000-000000005544');
 SELECT reservation_id INTO STRICT rid FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005544';
 ALTER TABLE internal.ai_quota_counters DISABLE TRIGGER zz_initial_admission_member_before;
 ALTER TABLE internal.ai_quota_counters DISABLE TRIGGER zz_initial_admission_member_after;
 UPDATE internal.ai_quota_counters c SET request_count=request_count+1 FROM internal.ai_quota_reservation_counters l
  WHERE l.reservation_id=rid AND l.scope_type='user_rate' AND c.scope_type=l.scope_type AND c.scope_key=l.scope_key AND c.bucket=l.bucket AND c.window_start=l.window_start;
 after_text:=internal.build_initial_admission_accounting('00000000-0000-4000-8000-000000005544');
 -- Restore the fixture in its exception subtransaction after proving identity.
 IF before_text=after_text THEN RAISE EXCEPTION 'synthetic_shared_counter_unchanged'; END IF;
 RAISE EXCEPTION 'synthetic_shared_counter_changed';
EXCEPTION WHEN OTHERS THEN RETURN SQLERRM='synthetic_shared_counter_unchanged';
END; $$;
SELECT extensions.ok(pg_temp.accounting_shared_counter(),'another shared-counter increment does not rewrite original charge proof');

SELECT extensions.throws_ok($q$DELETE FROM internal.ai_quota_reservation_counters WHERE reservation_id=(SELECT reservation_id FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005544') AND scope_type='user_rate'$q$,
 '55000','initial_analysis_preparation_required','permanent member guard blocks raw charge-link deletion');
SELECT set_config('merian.initial_admission_stage','',TRUE);
SELECT extensions.throws_ok($q$UPDATE internal.ai_quota_reservations SET request_id=gen_random_uuid(),original_analysis_id=NULL WHERE request_id='00000000-0000-4000-8000-000000005544'$q$,
 '55000','initial_analysis_preparation_provider_blocked','cleared token cannot remove OLD reservation aliases');
SELECT extensions.throws_ok($q$UPDATE internal.identification_provider_attempts SET model=model WHERE reservation_id=(SELECT reservation_id FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005544')$q$,
 '55000','initial_analysis_preparation_required','cleared token cannot hide provider attempt membership');
SELECT extensions.throws_ok($q$UPDATE public.users SET complimentary_entitlement_epoch=complimentary_entitlement_epoch+1 WHERE id='00000000-0000-4000-8000-00000000f001'$q$,
 '55000','initial_analysis_preparation_required','cleared token cannot bypass original owner epoch guard');
SELECT set_config('merian.initial_admission_stage',(SELECT stage_token::TEXT FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005544'),TRUE);




-- All source/member/private-row guards stay enabled for this nested owner
-- probe. The enclosing test transaction still has the incomplete-stage sentinel
-- disabled; every materialized member below is rolled back, not committed.
CREATE TEMP TABLE materialization_order(ordinal BIGINT GENERATED ALWAYS AS IDENTITY, member TEXT NOT NULL);
CREATE FUNCTION pg_temp.record_materialization_order() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO materialization_order(member) VALUES(TG_TABLE_NAME||CASE WHEN TG_TABLE_NAME='initial_analysis_media_registry' THEN ':'||(to_jsonb(NEW)->>'object_id') ELSE '' END);
 RETURN NEW;
END; $$;
DO $order_probe$
DECLARE relation_name TEXT;
BEGIN
 FOREACH relation_name IN ARRAY ARRAY['initial_preparation_admission_receipts','initial_analysis_media_allocation_fences','initial_analysis_media_cohorts','initial_analysis_media_registry'] LOOP
  EXECUTE format('CREATE TRIGGER zzy_test_materialization_order AFTER INSERT ON internal.%I FOR EACH ROW EXECUTE FUNCTION pg_temp.record_materialization_order()',relation_name);
 END LOOP;
END; $order_probe$;
CREATE FUNCTION pg_temp.materialization_probe(p_scan UUID) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE result JSONB; r internal.initial_preparation_admission_receipts; before_proof JSONB;
BEGIN
 BEGIN
  PERFORM set_config('merian.initial_admission_stage',(SELECT stage_token::TEXT FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan),TRUE);
  PERFORM internal.materialize_initial_admission(p_scan);
  SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
  SELECT jsonb_build_object('phase',s.phase,'receipt_equal',s.prospective_receipt=to_jsonb(r),
    'binding_version',a.binding_version,'outcome_bound',a.preparation_outcome_digest=r.manifest::JSONB#>>'{proof,outcome,digest}',
    'receipt_bound',a.preparation_receipt_digest=r.receipt_digest,'submission_exact',u.input_snapshot=r.input::JSONB
      AND u.configuration_snapshot=r.configuration::JSONB AND u.funding_snapshot=r.funding::JSONB,
    'lifecycle',f.state,'media_binding_exact',c.binding=r.media_binding::JSONB,
    'objects',(SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan),
    'expected_objects',jsonb_array_length(r.mapping::JSONB->'objects'),
    'unconsumed',(SELECT count(*) FROM internal.initial_preparation_admission_writes WHERE scan_id=p_scan AND NOT consumed),
    'member_events',s.completion_event_seq,'consumed_writes',(SELECT count(*) FROM internal.initial_preparation_admission_writes WHERE scan_id=p_scan AND consumed),
    'provider_calls',(SELECT count(*) FROM internal.identification_invocations WHERE scan_id=p_scan),
    'member_order',(SELECT jsonb_agg(member ORDER BY ordinal) FROM materialization_order),
    'expected_order',jsonb_build_array('initial_preparation_admission_receipts','initial_analysis_media_allocation_fences','initial_analysis_media_cohorts')
      ||(SELECT jsonb_agg('initial_analysis_media_registry:'||(e->>'object_id') ORDER BY e->>'object_id' COLLATE "C") FROM jsonb_array_elements(r.mapping::JSONB->'objects') e)) INTO result
   FROM internal.initial_preparation_admission_staging s JOIN internal.initial_analysis_admissions a USING(scan_id)
    JOIN internal.initial_analysis_submissions u USING(scan_id) JOIN internal.initial_analysis_lifecycle_fences f USING(scan_id)
    JOIN internal.initial_analysis_media_cohorts c USING(scan_id) WHERE s.scan_id=p_scan;
  RAISE EXCEPTION 'synthetic probe rollback' USING ERRCODE='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN RETURN result;
 END;
END; $$;
CREATE FUNCTION pg_temp.funding_entitlement_tamper() RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE r internal.initial_preparation_admission_receipts; funding_value JSONB; manifest_value JSONB;
BEGIN
 r:=internal.build_initial_admission_receipt('00000000-0000-4000-8000-000000005544');
 funding_value:=jsonb_set(r.funding::JSONB,'{original,entitlement_version}',
  to_jsonb((r.funding::JSONB#>>'{original,entitlement_version}')::BIGINT+1));
 r.funding:=internal.initial_canonical(funding_value);
 manifest_value:=jsonb_set(r.manifest::JSONB,'{proof,funding}',jsonb_build_object('byte_count',octet_length(r.funding),
  'digest',internal.initial_digest('funding',r.funding)));
 manifest_value:=jsonb_set(manifest_value,'{proof_digest}',to_jsonb(encode(extensions.digest(convert_to(
  'merian.initial-analysis.handoff.admitted-proof.v1'||chr(10)||internal.initial_canonical(manifest_value->'proof'),'UTF8'),'sha256'),'hex')));
 r.manifest:=internal.initial_canonical(manifest_value);
 -- Recompute a fully valid self-contained proof; live funding association is a
 -- separate requirement and must reject this apparently self-consistent value.
 r.receipt_digest:=internal.validate_initial_admitted_proof(r.candidate,r.input,r.configuration,r.funding,r.outcome,
  r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest);
 UPDATE internal.initial_preparation_admission_staging SET phase='reserved',prospective_receipt=to_jsonb(r)
  WHERE scan_id=r.scan_id;
END; $$;
SELECT extensions.throws_ok('SELECT pg_temp.funding_entitlement_tamper()','22023','initial_analysis_identity_conflict',
 'recommitted entitlement version cannot differ from original locked funding');
SELECT extensions.is((SELECT phase FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005544'),
 'compared','funding tamper leaves stage and prospective receipt unfrozen');

CREATE TEMP TABLE materialized_probe AS SELECT pg_temp.materialization_probe('00000000-0000-4000-8000-000000005544') value;
SELECT extensions.is(value->>'phase','allocated','private owner reaches allocated only after all durable members exist') FROM materialized_probe;
SELECT extensions.ok((value->>'receipt_equal')::BOOLEAN,'one prospective receipt is copied without rebuilding bytes') FROM materialized_probe;
SELECT extensions.is(value->>'binding_version','3','new admission uses closed v3 binding') FROM materialized_probe;
SELECT extensions.ok((value->>'outcome_bound')::BOOLEAN AND (value->>'receipt_bound')::BOOLEAN,'v3 binds original outcome and complete receipt') FROM materialized_probe;
SELECT extensions.ok((value->>'submission_exact')::BOOLEAN,'submission retains exact original input configuration and funding') FROM materialized_probe;
SELECT extensions.is(value->>'lifecycle','pending_pre_dispatch','existing lifecycle AFTER owner inserts pending state') FROM materialized_probe;
SELECT extensions.ok((value->>'media_binding_exact')::BOOLEAN,'M1 uses exact original v2 binding') FROM materialized_probe;
SELECT extensions.is(value->'objects',value->'expected_objects','M1 registry has exactly the preallocated mapping union') FROM materialized_probe;
SELECT extensions.is(value->'member_order',value->'expected_order','actual insertion order is receipt then fence/cohort then sorted registry') FROM materialized_probe;
SELECT extensions.is(value->'member_events',value->'consumed_writes','every successful member AFTER write queues exactly one stage event') FROM materialized_probe;
SELECT extensions.is(value->>'unconsumed','0','every finalizer lifecycle receipt and M1 expectation consumed once') FROM materialized_probe;
SELECT extensions.is(value->>'provider_calls','0','materialization never dispatches provider') FROM materialized_probe;
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_admission_receipts),0::BIGINT,'materialization probe rolls back receipt');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_submissions),0::BIGINT,'materialization probe rolls back submission');
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.materialize_initial_admission(NULL)'),
 '42501',role_name||' denied private materialization owner') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;

CREATE FUNCTION pg_temp.materialization_fault() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF current_setting('merian.test_materialization_fault',TRUE)=TG_WHEN||':'||TG_TABLE_NAME THEN
  RAISE EXCEPTION 'synthetic_materialization_fault';
 END IF;
 RETURN NEW;
END; $$;
DO $fault_triggers$
DECLARE relation_name TEXT;
BEGIN
 FOREACH relation_name IN ARRAY ARRAY['initial_analysis_submissions','initial_analysis_admissions','initial_analysis_lifecycle_fences',
  'initial_preparation_admission_receipts','initial_analysis_media_allocation_fences','initial_analysis_media_registry','initial_analysis_media_cohorts'] LOOP
  EXECUTE format('CREATE TRIGGER zzz_test_materialization_before BEFORE INSERT ON internal.%I FOR EACH ROW EXECUTE FUNCTION pg_temp.materialization_fault()',relation_name);
  EXECUTE format('CREATE TRIGGER zzz_test_materialization_after AFTER INSERT ON internal.%I FOR EACH ROW EXECUTE FUNCTION pg_temp.materialization_fault()',relation_name);
 END LOOP;
END; $fault_triggers$;
CREATE FUNCTION pg_temp.materialization_state(p_scan UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('stage',(SELECT to_jsonb(s) FROM internal.initial_preparation_admission_staging s WHERE scan_id=p_scan),
  'writes',(SELECT jsonb_agg(to_jsonb(w) ORDER BY statement_key) FROM internal.initial_preparation_admission_writes w WHERE scan_id=p_scan),
  'submission',(SELECT to_jsonb(t) FROM internal.initial_analysis_submissions t WHERE scan_id=p_scan),
  'admission',(SELECT to_jsonb(t) FROM internal.initial_analysis_admissions t WHERE scan_id=p_scan),
  'lifecycle',(SELECT to_jsonb(t) FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=p_scan),
  'receipt',(SELECT to_jsonb(t) FROM internal.initial_preparation_admission_receipts t WHERE scan_id=p_scan),
  'fence',(SELECT to_jsonb(t) FROM internal.initial_analysis_media_allocation_fences t WHERE scan_id=p_scan),
  'registry',(SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_analysis_media_registry t WHERE scan_id=p_scan),
  'cohort',(SELECT to_jsonb(t) FROM internal.initial_analysis_media_cohorts t WHERE scan_id=p_scan));
$$;
CREATE FUNCTION pg_temp.materialization_failure(point TEXT) RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
DECLARE before_value JSONB; failed BOOLEAN:=FALSE; scan UUID:='00000000-0000-4000-8000-000000005544';
BEGIN
 before_value:=pg_temp.materialization_state(scan);
 BEGIN
  PERFORM set_config('merian.test_materialization_fault',point,TRUE);
  PERFORM internal.materialize_initial_admission(scan);
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'synthetic_materialization_fault' THEN RAISE; END IF;
  failed:=TRUE;
 END;
 RETURN failed AND before_value IS NOT DISTINCT FROM pg_temp.materialization_state(scan);
END; $$;
SELECT extensions.ok(pg_temp.materialization_failure(moment||':'||relation_name),moment||' '||relation_name||' failure restores all admission/M1 rows and expectations')
 FROM unnest(ARRAY['BEFORE','AFTER']) moment CROSS JOIN unnest(ARRAY['initial_analysis_submissions','initial_analysis_admissions','initial_analysis_lifecycle_fences',
  'initial_preparation_admission_receipts','initial_analysis_media_allocation_fences','initial_analysis_media_registry','initial_analysis_media_cohorts']) relation_name;
CREATE FUNCTION pg_temp.member_event_gap_fault() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF current_setting('merian.test_member_event_fault',TRUE)='gap' AND NEW.consumed THEN
  RAISE EXCEPTION 'synthetic_member_event_gap';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER test_member_event_gap AFTER UPDATE OF consumed ON internal.initial_preparation_admission_writes
 FOR EACH ROW EXECUTE FUNCTION pg_temp.member_event_gap_fault();
CREATE FUNCTION pg_temp.member_event_skip_fault() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF current_setting('merian.test_member_event_fault',TRUE)='skip' AND NEW.completion_event_seq<>OLD.completion_event_seq THEN RETURN NULL; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER a00_test_member_event_skip BEFORE UPDATE ON internal.initial_preparation_admission_staging
 FOR EACH ROW EXECUTE FUNCTION pg_temp.member_event_skip_fault();
CREATE FUNCTION pg_temp.member_event_failure(mode TEXT) RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
DECLARE before_value JSONB; failure TEXT; scan UUID:='00000000-0000-4000-8000-000000005544';
BEGIN
 before_value:=pg_temp.materialization_state(scan);
 BEGIN
  PERFORM set_config('merian.test_member_event_fault',mode,TRUE);
  IF mode='overflow' THEN
   -- Trusted corruption tests the runtime no-event guard; all fixture changes
   -- and guard toggles roll back with the failed member statement.
   ALTER TABLE internal.initial_preparation_admission_staging DISABLE TRIGGER guard_initial_admission_stage;
   UPDATE internal.initial_preparation_admission_staging SET completion_event_seq=9223372036854775807 WHERE scan_id=scan;
   ALTER TABLE internal.initial_preparation_admission_staging ENABLE TRIGGER guard_initial_admission_stage;
  END IF;
  PERFORM internal.materialize_initial_admission(scan);
 EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM;
 END;
 RETURN failure=CASE mode WHEN 'gap' THEN 'P0001:synthetic_member_event_gap' WHEN 'skip' THEN '55000:initial_analysis_admission_incomplete' WHEN 'overflow' THEN '55000:initial_analysis_admission_incomplete' END
  AND before_value IS NOT DISTINCT FROM pg_temp.materialization_state(scan);
END; $$;
SELECT extensions.ok(pg_temp.member_event_failure('gap'),'fault after expectation consumption before event increment rolls back entire member and phase');
SELECT extensions.ok(pg_temp.member_event_failure('skip'),'missing sequence update rolls back member rather than returning success without deferred event');
SELECT extensions.ok(pg_temp.member_event_failure('overflow'),'exhausted event sequence cannot leave an admitted member without a final event');

-- Freeze exact winning images in the private stage, never the durable receipt.
CREATE FUNCTION pg_temp.ledger_probe(p_scan UUID) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE s internal.initial_preparation_admission_staging; result JSONB;
BEGIN
 BEGIN
  PERFORM internal.materialize_initial_admission(p_scan);
  PERFORM internal.freeze_initial_admission_ledger(p_scan);
  SELECT * INTO STRICT s FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan;
  PERFORM set_config('merian.initial_admission_stage','',TRUE);
  PERFORM internal.assert_initial_admission_ledger(s);
  result:=jsonb_build_object('exact',s.completion_ledger=(SELECT jsonb_agg(to_jsonb(w) ORDER BY statement_key COLLATE "C")
    FROM internal.initial_preparation_admission_writes w WHERE scan_id=p_scan),
   'count',jsonb_array_length(s.completion_ledger),'sequence',s.completion_event_seq,
   'users_private',NOT EXISTS(SELECT 1 FROM jsonb_array_elements(s.completion_ledger) e WHERE e->>'relation_name'='public.users'
    AND ((e->'observed_old_image')-ARRAY['id','complimentary_entitlement_epoch','entitlement_version']<>'{}'::JSONB
      OR (e->'observed_new_image')-ARRAY['id','complimentary_entitlement_epoch','entitlement_version']<>'{}'::JSONB)),
   'receipt_private',NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts r WHERE r.scan_id=p_scan
     AND (to_jsonb(r)?'completion_ledger' OR to_jsonb(r)?'completion_event_seq')));
  RAISE EXCEPTION 'synthetic ledger rollback' USING ERRCODE='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN RETURN result;
 END;
END; $$;
CREATE TEMP TABLE frozen_ledger_probe AS SELECT pg_temp.ledger_probe('00000000-0000-4000-8000-000000005544') value;
SELECT extensions.ok((value->>'exact')::BOOLEAN,'frozen ledger preserves complete ordered expectation and winning-event tuples') FROM frozen_ledger_probe;
SELECT extensions.is(value->'count',value->'sequence','full frozen ledger count equals atomic winning event sequence') FROM frozen_ledger_probe;
SELECT extensions.ok((value->>'users_private')::BOOLEAN,'ledger retains only closed entitlement projection, never full user data') FROM frozen_ledger_probe;
SELECT extensions.ok((value->>'receipt_private')::BOOLEAN,'durable receipt has no ledger or transaction event fields') FROM frozen_ledger_probe;
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_admission_staging WHERE completion_ledger IS NOT NULL),0::BIGINT,'rollback retains no frozen ledger');

CREATE FUNCTION pg_temp.ledger_fault(fault TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE s internal.initial_preparation_admission_staging; i INTEGER; v JSONB;
BEGIN
 BEGIN
  PERFORM internal.materialize_initial_admission('00000000-0000-4000-8000-000000005544');
  IF fault='missing_token' THEN
   PERFORM set_config('merian.initial_admission_stage','',TRUE);
   PERFORM internal.freeze_initial_admission_ledger('00000000-0000-4000-8000-000000005544');
  END IF;
  PERFORM internal.freeze_initial_admission_ledger('00000000-0000-4000-8000-000000005544');
  SELECT * INTO STRICT s FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005544';
  IF fault='repeat' THEN
   PERFORM internal.freeze_initial_admission_ledger(s.scan_id);
  ELSIF fault='rewrite' THEN
   UPDATE internal.initial_preparation_admission_staging SET completion_ledger=completion_ledger WHERE scan_id=s.scan_id;
  ELSIF fault='missing' THEN s.completion_ledger:=s.completion_ledger-0;
  ELSIF fault='extra' THEN s.completion_ledger:=s.completion_ledger||jsonb_build_array(s.completion_ledger->0);
  ELSIF fault='duplicate' THEN s.completion_ledger:=jsonb_set(s.completion_ledger,'{1}',s.completion_ledger->0);
  ELSIF fault='null_entry' THEN s.completion_ledger:=jsonb_set(s.completion_ledger,'{0}','null');
  ELSIF fault='unconsumed' THEN s.completion_ledger:=jsonb_set(s.completion_ledger,'{0,consumed}','false');
  ELSIF fault='unobserved' THEN s.completion_ledger:=jsonb_set(s.completion_ledger,'{0,observed_new_image}','null');
  ELSIF fault='extra_field' THEN s.completion_ledger:=jsonb_set(s.completion_ledger,'{0,extra}','true');
  ELSIF fault='wrong_operation' THEN s.completion_ledger:=jsonb_set(s.completion_ledger,'{0,observed_operation}','"DELETE"');
  ELSIF fault='wrong_receipt' THEN s.admission_receipt_id:=gen_random_uuid();
  ELSIF fault='wrong_phase_window' THEN s.phase_window:='{}';
  ELSIF fault='wrong_sequence' THEN s.completion_event_seq:=s.completion_event_seq+1;
  ELSIF fault='unsorted' THEN SELECT jsonb_agg(e ORDER BY n DESC) INTO s.completion_ledger FROM jsonb_array_elements(s.completion_ledger) WITH ORDINALITY t(e,n);
  ELSIF fault='counter_delta' THEN
   SELECT (n-1)::INTEGER,e INTO i,v FROM jsonb_array_elements(s.completion_ledger) WITH ORDINALITY t(e,n) WHERE e->>'statement_key'='Counter.user.upsert';
   s.completion_ledger:=jsonb_set(s.completion_ledger,ARRAY[i::TEXT,'observed_new_image','request_count'],to_jsonb((v#>>'{observed_new_image,request_count}')::INTEGER+1));
  ELSIF fault='user_extra' THEN
   SELECT (n-1)::INTEGER,e INTO i,v FROM jsonb_array_elements(s.completion_ledger) WITH ORDINALITY t(e,n) WHERE e->>'statement_key'='C8.epoch.update';
   v:=jsonb_set(v,'{new_image,unapproved_field}','true'); v:=jsonb_set(v,'{observed_new_image,unapproved_field}','true');
   s.completion_ledger:=jsonb_set(s.completion_ledger,ARRAY[i::TEXT],v);
  END IF;
  PERFORM internal.assert_initial_admission_ledger(s);
  RAISE EXCEPTION 'unexpected ledger acceptance' USING ERRCODE='ZX001';
 EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE||':'||SQLERRM;
 END;
END; $$;
SELECT extensions.is(pg_temp.ledger_fault(fault),'55000:initial_analysis_admission_incomplete','terminal ledger rejects '||fault)
 FROM unnest(ARRAY['missing_token','repeat','missing','extra','duplicate','null_entry','unconsumed','unobserved',
  'extra_field','wrong_operation','wrong_receipt','wrong_phase_window','wrong_sequence','unsorted','counter_delta','user_extra']) fault;
SELECT extensions.is(pg_temp.ledger_fault('rewrite'),'55000:initial_analysis_preparation_required','frozen ledger cannot be rewritten');
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.freeze_initial_admission_ledger(NULL)'),
 '42501',role_name||' denied ledger freeze') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;

-- The snapshot verifier is read-only and has no dependency on surviving stage
-- rows or caller settings. The test-only deletion below is rolled back and is
-- not a production terminal-consumption path.
CREATE FUNCTION pg_temp.live_snapshot_probe(p_scan UUID) RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
DECLARE s internal.initial_preparation_admission_staging;
BEGIN
 BEGIN
  PERFORM set_config('merian.initial_admission_stage',(SELECT stage_token::TEXT FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan),TRUE);
  PERFORM internal.materialize_initial_admission(p_scan);
  PERFORM internal.freeze_initial_admission_ledger(p_scan);
  SELECT * INTO STRICT s FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan;
  PERFORM set_config('merian.initial_admission_stage','forged-no-authority',TRUE);
  PERFORM internal.assert_initial_admission_live_snapshot(s);
  ALTER TABLE internal.initial_preparation_admission_writes DISABLE TRIGGER guard_initial_admission_expectation;
 ALTER TABLE internal.initial_preparation_admission_writes DISABLE TRIGGER advance_initial_admission_cleanup;
  ALTER TABLE internal.initial_preparation_admission_staging DISABLE TRIGGER guard_initial_admission_stage;
  DELETE FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan;
  PERFORM internal.assert_initial_admission_live_snapshot(s);
  PERFORM internal.assert_initial_admission_live_receipt(s.owner_id,s.scan_id,s.admission_receipt_id);
  IF EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id=p_scan) THEN RAISE EXCEPTION 'expected cascade'; END IF;
  RAISE EXCEPTION 'synthetic snapshot rollback' USING ERRCODE='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN RETURN TRUE;
 END;
END; $$;
SELECT extensions.ok(pg_temp.live_snapshot_probe(scan),'full live snapshot passes without GUC or surviving stage/expectations: '||kind)
 FROM (VALUES('00000000-0000-4000-8000-000000005533'::UUID,'trial'),('00000000-0000-4000-8000-000000005544'::UUID,'complimentary')) v(scan,kind);

-- Discharge valid original source events before test-only trigger suspension;
-- a pending deferred event otherwise prevents ALTER TABLE before the probe.
SET CONSTRAINTS internal.initial_source_registry_cohort,internal.initial_execution_cohort IMMEDIATE;
SET CONSTRAINTS internal.initial_source_registry_cohort,internal.initial_execution_cohort DEFERRED;
-- Trusted fault injection drops only the relevant FK constraints transactionally;
-- ordinary postgres cannot disable system RI triggers. Every caller below rolls
-- back the entire corruption block, restoring constraints and original rows.
CREATE FUNCTION pg_temp.retained_fixture_foreign_keys() RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE fk RECORD;
BEGIN
 FOR fk IN SELECT conrelid::REGCLASS AS relation_name,conname FROM pg_constraint
  WHERE contype='f' AND (conrelid IN ('internal.initial_preparation_admission_receipts'::REGCLASS,
    'internal.initial_analysis_submissions'::REGCLASS,'internal.initial_analysis_admissions'::REGCLASS)
   OR confrelid IN ('internal.initial_analysis_submissions'::REGCLASS,'internal.initial_analysis_admissions'::REGCLASS))
  ORDER BY conrelid,conname
 LOOP EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I',fk.relation_name,fk.conname); END LOOP;
END $$;
CREATE FUNCTION pg_temp.live_snapshot_fault(fault TEXT,receipt_only BOOLEAN DEFAULT FALSE,retained_only BOOLEAN DEFAULT FALSE) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE s internal.initial_preparation_admission_staging; i INTEGER; member internal.initial_analysis_media_registry;
BEGIN
 BEGIN
  PERFORM internal.materialize_initial_admission('00000000-0000-4000-8000-000000005544');
  PERFORM internal.freeze_initial_admission_ledger('00000000-0000-4000-8000-000000005544');
  SELECT * INTO STRICT s FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005544';
  IF fault='missing_receipt' THEN
   ALTER TABLE internal.initial_preparation_admission_receipts DISABLE TRIGGER USER;
   DELETE FROM internal.initial_preparation_admission_receipts WHERE scan_id=s.scan_id;
  ELSIF fault IN ('receipt_header_owner','receipt_header_scan') THEN
   PERFORM pg_temp.retained_fixture_foreign_keys();
   -- Trusted corruption only: move all typed immutable associations together,
   -- leaving canonical proof intact. This isolates manifest-to-row binding from
   -- member association checks; no ordinary erasure/reparenting is authorized.
   ALTER TABLE internal.initial_preparation_admission_receipts DISABLE TRIGGER USER;
   ALTER TABLE internal.initial_analysis_submissions DISABLE TRIGGER USER;
   ALTER TABLE internal.initial_analysis_admissions DISABLE TRIGGER USER;
   IF fault='receipt_header_owner' THEN
    s.owner_id:=gen_random_uuid();
    UPDATE internal.initial_preparation_admission_receipts SET owner_id=s.owner_id WHERE scan_id=s.scan_id;
    UPDATE internal.initial_analysis_submissions SET owner_id=s.owner_id WHERE scan_id=s.scan_id;
    UPDATE internal.initial_analysis_admissions SET owner_id=s.owner_id WHERE scan_id=s.scan_id;
   ELSE
    member.scan_id:=gen_random_uuid();
    UPDATE internal.initial_preparation_admission_receipts SET scan_id=member.scan_id WHERE scan_id=s.scan_id;
    UPDATE internal.initial_analysis_submissions SET scan_id=member.scan_id WHERE scan_id=s.scan_id;
    UPDATE internal.initial_analysis_admissions SET scan_id=member.scan_id WHERE scan_id=s.scan_id;
    s.scan_id:=member.scan_id;
   END IF;
  ELSIF fault='missing_submission' THEN
   PERFORM pg_temp.retained_fixture_foreign_keys();
   -- Leave the receipt present to exercise the loader's own association check.
   ALTER TABLE internal.initial_analysis_submissions DISABLE TRIGGER USER;
   DELETE FROM internal.initial_analysis_submissions WHERE scan_id=s.scan_id;
  ELSIF fault='missing_admission' THEN
   PERFORM pg_temp.retained_fixture_foreign_keys();
   ALTER TABLE internal.initial_analysis_admissions DISABLE TRIGGER USER;
   DELETE FROM internal.initial_analysis_admissions WHERE scan_id=s.scan_id;
  ELSIF fault='receipt_header_identity' THEN
   ALTER TABLE internal.initial_preparation_admission_receipts DISABLE TRIGGER USER;
   s.admission_receipt_id:=gen_random_uuid();
   UPDATE internal.initial_preparation_admission_receipts SET admission_receipt_id=s.admission_receipt_id WHERE scan_id=s.scan_id;
  ELSIF fault='submission_route' THEN
   ALTER TABLE internal.initial_analysis_submissions DISABLE TRIGGER USER;
   UPDATE internal.initial_analysis_submissions SET route='identify-describe' WHERE scan_id=s.scan_id;
  ELSIF fault='admission_digest' THEN
   ALTER TABLE internal.initial_analysis_admissions DISABLE TRIGGER USER;
   UPDATE internal.initial_analysis_admissions SET descriptions_digest=repeat('0',64) WHERE scan_id=s.scan_id;
  ELSIF fault='entitlement' THEN
   ALTER TABLE internal.ai_quota_reservations DISABLE TRIGGER USER;
   UPDATE internal.ai_quota_reservations SET entitlement_version=entitlement_version+1 WHERE id=s.reservation_id;
  ELSIF fault='missing_attempt' THEN
   ALTER TABLE internal.identification_provider_attempts DISABLE TRIGGER USER;
   DELETE FROM internal.identification_provider_attempts WHERE reservation_id=s.reservation_id;
  ELSIF fault='missing_link' THEN
   ALTER TABLE internal.ai_quota_reservation_counters DISABLE TRIGGER USER;
   DELETE FROM internal.ai_quota_reservation_counters WHERE reservation_id=s.reservation_id AND scope_type='user_rate';
  ELSIF fault='missing_hold' THEN
   ALTER TABLE internal.complimentary_scan_usage DISABLE TRIGGER USER;
   DELETE FROM internal.complimentary_scan_usage WHERE client_scan_id=s.scan_id;
  ELSIF fault='source_retired' THEN
   ALTER TABLE internal.initial_preparation_source_registry DISABLE TRIGGER USER;
   UPDATE internal.initial_preparation_source_registry SET retired=TRUE WHERE scan_id=s.scan_id;
  ELSIF fault='missing_outcome' THEN
   ALTER TABLE internal.initial_preparation_outcomes DISABLE TRIGGER USER;
   DELETE FROM internal.initial_preparation_outcomes WHERE scan_id=s.scan_id;
  ELSIF fault='extra_destination' THEN
   ALTER TABLE internal.initial_analysis_media_registry DISABLE TRIGGER USER;
   SELECT * INTO STRICT member FROM internal.initial_analysis_media_registry WHERE scan_id=s.scan_id LIMIT 1;
   member.object_id:=gen_random_uuid(); INSERT INTO internal.initial_analysis_media_registry SELECT member.*;
  ELSIF fault='destination_retired' THEN
   ALTER TABLE internal.initial_analysis_media_registry DISABLE TRIGGER USER;
   UPDATE internal.initial_analysis_media_registry SET retired=TRUE WHERE scan_id=s.scan_id;
  ELSIF fault='counter_window' THEN
   ALTER TABLE internal.ai_quota_counters DISABLE TRIGGER USER;
   UPDATE internal.ai_quota_counters c SET window_seconds=window_seconds+1 FROM internal.ai_quota_reservation_counters l
    WHERE l.reservation_id=s.reservation_id AND l.scope_type='user_rate' AND (c.scope_type,c.scope_key,c.bucket,c.window_start)=(l.scope_type,l.scope_key,l.bucket,l.window_start);
  ELSIF fault='quota_model' THEN
   ALTER TABLE internal.ai_quota_reservations DISABLE TRIGGER USER;
   UPDATE internal.ai_quota_reservations SET model='gemini-2.5-flash' WHERE id=s.reservation_id;
  ELSIF fault='missing_counter' THEN
   ALTER TABLE internal.ai_quota_counters DISABLE TRIGGER USER;
   DELETE FROM internal.ai_quota_counters c USING internal.ai_quota_reservation_counters l
    WHERE l.reservation_id=s.reservation_id AND l.scope_type='user_rate'
     AND (c.scope_type,c.scope_key,c.bucket,c.window_start)=(l.scope_type,l.scope_key,l.bucket,l.window_start);
  ELSIF fault='captured_owner' THEN s.owner_id:=gen_random_uuid();
  ELSIF fault='captured_scan' THEN s.scan_id:=gen_random_uuid();
  ELSIF fault='captured_receipt' THEN s.admission_receipt_id:=gen_random_uuid();
  ELSIF fault='null_receipt' THEN s.admission_receipt_id:=NULL;
  ELSIF fault='write_chain' THEN
   SELECT (n-1)::INTEGER INTO i FROM jsonb_array_elements(s.completion_ledger) WITH ORDINALITY t(e,n) WHERE e->>'statement_key'='C4.reservation.insert';
   s.completion_ledger:=jsonb_set(s.completion_ledger,ARRAY[i::TEXT,'new_image','entitlement_version'],'99999');
   s.completion_ledger:=jsonb_set(s.completion_ledger,ARRAY[i::TEXT,'observed_new_image','entitlement_version'],'99999');
  ELSE RAISE EXCEPTION 'unknown test fault'; END IF;
  PERFORM set_config('merian.initial_admission_stage','',TRUE);
  IF retained_only THEN PERFORM internal.initial_admission_retained_receipt(s.owner_id,s.scan_id,s.admission_receipt_id);
  ELSIF receipt_only THEN PERFORM internal.assert_initial_admission_live_receipt(s.owner_id,s.scan_id,s.admission_receipt_id);
  ELSE PERFORM internal.assert_initial_admission_live_snapshot(s); END IF;
  RAISE EXCEPTION 'unexpected snapshot acceptance' USING ERRCODE='ZX001';
 EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE||':'||SQLERRM;
 END;
END; $$;
SELECT extensions.is(pg_temp.live_snapshot_fault(fault),'55000:initial_analysis_admission_incomplete','live snapshot rejects '||fault)
 FROM unnest(ARRAY['missing_receipt','entitlement','missing_attempt','missing_link','missing_hold','source_retired','missing_outcome',
  'extra_destination','destination_retired','counter_window','write_chain']) fault;
SELECT extensions.is(pg_temp.live_snapshot_fault(fault,TRUE),'55000:initial_analysis_admission_incomplete','receipt-only live predicate rejects '||fault)
 FROM unnest(ARRAY['missing_receipt','entitlement','missing_attempt','missing_link','missing_hold','source_retired','missing_outcome',
  'extra_destination','destination_retired','counter_window','quota_model','missing_counter',
  'captured_owner','captured_scan','captured_receipt','null_receipt']) fault;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.assert_initial_admission_live_receipt(NULL,NULL,NULL)'),
 '42501',role_name||' denied private receipt-only live predicate') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
-- These trusted corruption fixtures separate durable integrity from current
-- eligibility. Acceptance below is never a recovery grant or refund witness.
SELECT extensions.is(pg_temp.live_snapshot_fault(fault,FALSE,TRUE),'55000:initial_analysis_admission_incomplete','retained proof rejects '||fault)
 FROM unnest(ARRAY['missing_receipt','missing_submission','missing_admission','receipt_header_identity','receipt_header_owner','receipt_header_scan','submission_route','admission_digest','captured_owner','captured_scan','captured_receipt','null_receipt']) fault;
SELECT extensions.is(pg_temp.live_snapshot_fault(fault,FALSE,TRUE),'ZX001:unexpected snapshot acceptance','retained integrity does not reinterpret current '||fault)
 FROM unnest(ARRAY['entitlement','missing_attempt','missing_link','missing_hold','source_retired','missing_outcome',
  'destination_retired','counter_window','quota_model','missing_counter']) fault;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.initial_admission_retained_receipt(NULL,NULL,NULL)'),
 '42501',role_name||' denied private retained receipt') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.assert_initial_admission_live_snapshot(NULL)'),
 '42501',role_name||' denied private live snapshot verifier') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;

CREATE FUNCTION pg_temp.ledger_preflight_overflow() RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 ALTER TABLE internal.initial_preparation_admission_writes DISABLE TRIGGER guard_initial_admission_expectation;
 ALTER TABLE internal.initial_preparation_admission_writes DISABLE TRIGGER advance_initial_admission_cleanup;
 INSERT INTO internal.initial_preparation_admission_writes(scan_id,statement_key,relation_name,operation,new_image)
  SELECT '00000000-0000-4000-8000-000000005544','M1.object.'||md5(i::TEXT)::UUID::TEXT,
   'internal.initial_analysis_media_registry','INSERT','{}'::JSONB FROM generate_series(1,65) i;
 PERFORM internal.initial_admission_ledger_snapshot('00000000-0000-4000-8000-000000005544');
END; $$;
SELECT extensions.throws_ok('SELECT pg_temp.ledger_preflight_overflow()','55000','initial_analysis_admission_incomplete',
 'ledger rejects oversized statement set before JSON aggregation');
SELECT extensions.throws_ok($q$SELECT internal.initial_admission_ledger_snapshot('00000000-0000-4000-8000-000000009999')$q$,
 '55000','initial_analysis_admission_incomplete','ledger rejects empty snapshot');

CREATE FUNCTION pg_temp.cleanup_state(scan UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('stage',(SELECT to_jsonb(s) FROM internal.initial_preparation_admission_staging s WHERE scan_id=scan),
  'writes',(SELECT COALESCE(jsonb_agg(to_jsonb(w) ORDER BY statement_key COLLATE "C"),'[]') FROM internal.initial_preparation_admission_writes w WHERE scan_id=scan))
$$;
\if :{?seal_lock_peer}
\else
CREATE FUNCTION pg_temp.cleanup_probe() RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
DECLARE s internal.initial_preparation_admission_staging; before_state JSONB; scan UUID:='00000000-0000-4000-8000-000000005544'; valid BOOLEAN;
BEGIN
 before_state:=pg_temp.cleanup_state(scan);
 BEGIN
  PERFORM internal.materialize_initial_admission(scan);
  PERFORM internal.freeze_initial_admission_ledger(scan);
  PERFORM internal.begin_initial_admission_consumption(scan);
  PERFORM internal.consume_initial_admission_writes(scan);
  SELECT * INTO STRICT s FROM internal.initial_preparation_admission_staging WHERE scan_id=scan;
  PERFORM internal.assert_initial_admission_live_snapshot(s);
  valid:=s.phase='consuming' AND s.cleanup_cursor=jsonb_array_length(s.completion_ledger)
   AND s.completion_event_seq=jsonb_array_length(s.completion_ledger)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id=scan);
  RAISE EXCEPTION 'synthetic cleanup rollback' USING ERRCODE='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
 END;
 RETURN valid AND before_state IS NOT DISTINCT FROM pg_temp.cleanup_state(scan);
END; $$;
SELECT extensions.ok(pg_temp.cleanup_probe(),'ordered child consumption completes separate cursor, preserves proof/member count, and fully rolls back');

CREATE FUNCTION pg_temp.cleanup_gap() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF current_setting('merian.test_cleanup_fault',TRUE)='gap' THEN RAISE EXCEPTION 'synthetic_cleanup_gap'; END IF;
 IF current_setting('merian.test_cleanup_fault',TRUE)='duplicate' THEN
  UPDATE internal.initial_preparation_admission_staging SET cleanup_cursor=cleanup_cursor+1 WHERE scan_id=OLD.scan_id;
 END IF;
 RETURN OLD;
END; $$;
CREATE TRIGGER aaa_test_cleanup_gap AFTER DELETE ON internal.initial_preparation_admission_writes
 FOR EACH ROW EXECUTE FUNCTION pg_temp.cleanup_gap();
CREATE FUNCTION pg_temp.cleanup_skip() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF current_setting('merian.test_cleanup_fault',TRUE)='skip' AND NEW.cleanup_cursor<>OLD.cleanup_cursor THEN RETURN NULL; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER a00_test_cleanup_skip BEFORE UPDATE ON internal.initial_preparation_admission_staging
 FOR EACH ROW EXECUTE FUNCTION pg_temp.cleanup_skip();
CREATE TEMP TABLE nested_cleanup_probe(scan UUID);
CREATE FUNCTION pg_temp.nested_cleanup_delete() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 DELETE FROM internal.initial_preparation_admission_writes WHERE scan_id=NEW.scan
  AND statement_key=(SELECT completion_ledger->cleanup_cursor::INTEGER->>'statement_key' FROM internal.initial_preparation_admission_staging WHERE scan_id=NEW.scan);
 RETURN NEW;
END; $$;
CREATE TRIGGER nested_cleanup_delete BEFORE INSERT ON nested_cleanup_probe FOR EACH ROW EXECUTE FUNCTION pg_temp.nested_cleanup_delete();
CREATE FUNCTION pg_temp.cleanup_fault(fault TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE s internal.initial_preparation_admission_staging; scan UUID:='00000000-0000-4000-8000-000000005544'; before_state JSONB; failure TEXT;
BEGIN
 before_state:=pg_temp.cleanup_state(scan);
 BEGIN
  PERFORM internal.materialize_initial_admission(scan);
  PERFORM internal.freeze_initial_admission_ledger(scan);
  PERFORM internal.begin_initial_admission_consumption(scan);
  SELECT * INTO STRICT s FROM internal.initial_preparation_admission_staging WHERE scan_id=scan;
  IF fault='repeat_entry' THEN PERFORM internal.begin_initial_admission_consumption(scan);
  ELSIF fault='raw_cursor' THEN UPDATE internal.initial_preparation_admission_staging SET cleanup_cursor=1 WHERE scan_id=scan;
  ELSIF fault='out_of_order' THEN DELETE FROM internal.initial_preparation_admission_writes WHERE scan_id=scan AND statement_key=s.completion_ledger->1->>'statement_key';
  ELSIF fault='nested_direct' THEN INSERT INTO nested_cleanup_probe VALUES(scan);
  ELSIF fault='wrong_token' THEN
   PERFORM set_config('merian.initial_admission_stage','forged',TRUE);
   PERFORM internal.consume_initial_admission_writes(scan);
  ELSIF fault='other_scan' THEN DELETE FROM internal.initial_preparation_admission_writes WHERE scan_id='00000000-0000-4000-8000-000000005533';
  ELSIF fault='changed_child' THEN
   ALTER TABLE internal.initial_preparation_admission_writes DISABLE TRIGGER guard_initial_admission_expectation;
   UPDATE internal.initial_preparation_admission_writes SET new_image=new_image||'{"unapproved":true}'::JSONB
    WHERE scan_id=scan AND statement_key=s.completion_ledger->0->>'statement_key';
   ALTER TABLE internal.initial_preparation_admission_writes ENABLE TRIGGER guard_initial_admission_expectation;
   PERFORM internal.consume_initial_admission_writes(scan);
  ELSIF fault='extra_child' THEN
   ALTER TABLE internal.initial_preparation_admission_writes DISABLE TRIGGER guard_initial_admission_expectation;
   INSERT INTO internal.initial_preparation_admission_writes(scan_id,statement_key,relation_name,operation,new_image)
    VALUES(scan,'M1.object.'||gen_random_uuid()::TEXT,'internal.initial_analysis_media_registry','INSERT','{}');
   ALTER TABLE internal.initial_preparation_admission_writes ENABLE TRIGGER guard_initial_admission_expectation;
   PERFORM internal.consume_initial_admission_writes(scan);
  ELSIF fault='cursor_jump' THEN UPDATE internal.initial_preparation_admission_staging SET cleanup_cursor=2 WHERE scan_id=scan;
  ELSIF fault='gap' OR fault='skip' OR fault='duplicate' THEN
   PERFORM set_config('merian.test_cleanup_fault',fault,TRUE);
   PERFORM internal.consume_initial_admission_writes(scan);
  ELSIF fault='parent_delete' THEN
   DELETE FROM internal.initial_preparation_admission_writes WHERE scan_id=scan AND statement_key=s.completion_ledger->0->>'statement_key';
   DELETE FROM internal.initial_preparation_admission_staging WHERE scan_id=scan;
  ELSIF fault='member_write' THEN
   UPDATE internal.ai_quota_reservations SET daily_remaining_after_reservation=daily_remaining_after_reservation WHERE id=s.reservation_id;
  ELSE RAISE EXCEPTION 'unknown cleanup fault'; END IF;
  RAISE EXCEPTION 'unexpected cleanup acceptance' USING ERRCODE='ZX001';
 EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM;
 END;
 IF before_state IS DISTINCT FROM pg_temp.cleanup_state(scan) THEN RAISE EXCEPTION 'cleanup fault failed rollback'; END IF;
 RETURN failure;
END; $$;
SELECT extensions.is(pg_temp.cleanup_fault(fault),'55000:initial_analysis_admission_incomplete','cleanup rejects '||fault||' and rolls back')
 FROM unnest(ARRAY['repeat_entry','raw_cursor','wrong_token','skip','duplicate','changed_child','extra_child','parent_delete']) fault;
SELECT extensions.is(pg_temp.cleanup_fault(fault),'55000:initial_analysis_preparation_required','cleanup rejects '||fault||' and rolls back')
 FROM unnest(ARRAY['out_of_order','nested_direct','other_scan','cursor_jump']) fault;
SELECT extensions.is(pg_temp.cleanup_fault('member_write'),'55000:initial_analysis_admission_sealed','entry seal rejects member writes without optional seal helper');
SELECT extensions.is(pg_temp.cleanup_fault('gap'),'P0001:synthetic_cleanup_gap','child DELETE/cursor gap fault restores full admission state');
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.consume_initial_admission_writes(NULL)'),
 '42501',role_name||' denied private child consumption') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;

\endif

-- One materialized fixture for the whole seal matrix; all member/source guards
-- remain enabled. Nested exception blocks model statement failure/savepoints.
CREATE FUNCTION pg_temp.seal_role_write(role_name TEXT,command TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
BEGIN
 EXECUTE format('SET LOCAL ROLE %I',role_name);
 EXECUTE command;
 RAISE EXCEPTION 'allowed' USING ERRCODE='ZX001';
EXCEPTION WHEN SQLSTATE 'ZX001' THEN RETURN 'allowed';
 WHEN OTHERS THEN RETURN SQLSTATE||':'||SQLERRM;
END $$;
SELECT extensions.is(pg_temp.seal_role_write('authenticated','UPDATE public.scans SET custom_tags=custom_tags WHERE FALSE'),'allowed',
 'unsealed authenticated scan writes keep existing access without private helper grants');
SELECT extensions.is(pg_temp.seal_role_write('authenticated','UPDATE public.users SET marketing_opt_in=marketing_opt_in WHERE FALSE'),'allowed',
 'unsealed authenticated user writes keep existing access without private helper grants');
CREATE FUNCTION pg_temp.seal_matrix() RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE scan UUID:='00000000-0000-4000-8000-000000005544'; before_state JSONB;
 results JSONB:='[]'; rel TEXT; verb TEXT; command TEXT; failure TEXT; first_column TEXT; valid BOOLEAN; token TEXT;
BEGIN
 before_state:=pg_temp.cleanup_state(scan);
 BEGIN
  PERFORM internal.materialize_initial_admission(scan);
  PERFORM internal.freeze_initial_admission_ledger(scan);
  UPDATE internal.initial_preparation_admission_staging SET phase='consuming' WHERE scan_id=scan;
  results:=results||jsonb_build_array(jsonb_build_object('case','direct phase UPDATE acquires actual seal before cleanup','pass',internal.initial_admission_sealed()));
  -- A matching session lock can over-deny but the owner still acquires its
  -- xact lock. Release all session locks immediately to prove the distinction.
  PERFORM pg_advisory_lock(1229018189,hashtext(scan::TEXT));
  PERFORM internal.seal_initial_admission(scan);
  PERFORM pg_advisory_unlock_all();
  results:=results||jsonb_build_array(jsonb_build_object('case','unlock-all retains actual transaction seal','pass',internal.initial_admission_sealed()));
  FOR rel IN SELECT t.tgrelid::REGCLASS::TEXT FROM pg_trigger t
   WHERE t.tgname='a00_initial_admission_seal' ORDER BY t.tgrelid::REGCLASS::TEXT LOOP
   SELECT attname INTO STRICT first_column FROM pg_attribute WHERE attrelid=rel::REGCLASS
    AND attnum>0 AND NOT attisdropped ORDER BY attnum LIMIT 1;
   FOREACH verb IN ARRAY ARRAY['INSERT','UPDATE','DELETE'] LOOP
    command:=CASE verb WHEN 'INSERT' THEN format('INSERT INTO %s SELECT * FROM %s WHERE FALSE',rel,rel)
     WHEN 'UPDATE' THEN format('UPDATE %s SET %I=%I WHERE FALSE',rel,first_column,first_column)
     ELSE format('DELETE FROM %s WHERE FALSE',rel) END;
    failure:=NULL;
    BEGIN EXECUTE command; EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
    results:=results||jsonb_build_array(jsonb_build_object('case',verb||' sealed '||rel,'pass',failure IS NOT DISTINCT FROM '55000:initial_analysis_admission_sealed','failure',failure));
   END LOOP;
  END LOOP;
  FOREACH rel IN ARRAY ARRAY['public.scans','public.users'] LOOP
   command:=CASE rel WHEN 'public.scans' THEN 'UPDATE public.scans SET custom_tags=custom_tags WHERE FALSE'
    ELSE 'UPDATE public.users SET marketing_opt_in=marketing_opt_in WHERE FALSE' END;
   failure:=pg_temp.seal_role_write('authenticated',command);
   results:=results||jsonb_build_array(jsonb_build_object('case','direct authenticated caller sealed: '||rel,
    'pass',failure IS NOT DISTINCT FROM '55000:initial_analysis_admission_sealed','failure',failure));
  END LOOP;
  FOREACH command IN ARRAY ARRAY[
   'UPDATE internal.initial_preparation_admission_staging SET cleanup_cursor=1 WHERE scan_id=''00000000-0000-4000-8000-000000005544''',
   'UPDATE internal.initial_preparation_admission_writes SET consumed=consumed',
   'INSERT INTO internal.initial_preparation_admission_writes SELECT * FROM internal.initial_preparation_admission_writes LIMIT 1',
   'INSERT INTO internal.initial_preparation_admission_staging SELECT * FROM internal.initial_preparation_admission_staging LIMIT 1'
  ] LOOP
   failure:=NULL;
   BEGIN EXECUTE command; EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
   results:=results||jsonb_build_array(jsonb_build_object('case','private mutation under seal: '||command,
    'pass',failure IS NOT DISTINCT FROM CASE WHEN command LIKE '%cleanup_cursor=1%' THEN '55000:initial_analysis_admission_incomplete'
     ELSE '55000:initial_analysis_admission_sealed' END,'failure',failure));
  END LOOP;
  -- Cleanup remains exact and provenance-bound while sealed, then survives
  -- cleared caller state for ordinary member-denial after every child is gone.
  DELETE FROM internal.initial_preparation_admission_writes WHERE scan_id=scan AND statement_key=
   (SELECT completion_ledger->0->>'statement_key' FROM internal.initial_preparation_admission_staging WHERE scan_id=scan);
  token:=current_setting('merian.initial_admission_stage',TRUE);
  PERFORM set_config('merian.initial_admission_stage','',TRUE);
  PERFORM pg_advisory_unlock_all();
  failure:=NULL;
  BEGIN UPDATE internal.ai_quota_counters SET request_count=request_count+1;
  EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
  results:=results||jsonb_build_array(jsonb_build_object('case','partial cleanup plus cleared GUC/unlock-all retains counter denial',
   'pass',failure IS NOT DISTINCT FROM '55000:initial_analysis_admission_sealed'));
  PERFORM set_config('merian.initial_admission_stage',token,TRUE);
  PERFORM internal.consume_initial_admission_writes(scan);
  results:=results||jsonb_build_array(jsonb_build_object('case','proven cleanup allowed under seal','pass',
   NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id=scan)));
  PERFORM set_config('merian.initial_admission_stage','',TRUE);
  FOREACH command IN ARRAY ARRAY[
   'UPDATE public.users SET complimentary_entitlement_epoch=complimentary_entitlement_epoch+1',
   'UPDATE internal.ai_quota_counters SET request_count=request_count+1',
   'DELETE FROM internal.initial_preparation_source_registry',
   'DELETE FROM internal.initial_analysis_preparation_intents',
   'DELETE FROM internal.initial_analysis_admissions',
   'TRUNCATE internal.ai_quota_counters CASCADE',
   'TRUNCATE internal.scan_deletion_tombstones',
   'TRUNCATE internal.initial_analysis_completions CASCADE'
  ] LOOP
   failure:=NULL;
   BEGIN EXECUTE command; EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
   results:=results||jsonb_build_array(jsonb_build_object('case','after cleanup / cleared GUC: '||command,
    'pass',failure IS NOT DISTINCT FROM '55000:initial_analysis_admission_sealed','failure',failure));
  END LOOP;
  failure:=NULL;
  BEGIN DELETE FROM internal.initial_preparation_admission_staging WHERE scan_id=scan;
  EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
  results:=results||jsonb_build_array(jsonb_build_object('case','seal gives no parent deletion authority',
   'pass',failure IS NOT DISTINCT FROM '55000:initial_analysis_preparation_required'));
  RAISE EXCEPTION 'synthetic seal rollback' USING ERRCODE='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
 END;
 valid:=before_state IS NOT DISTINCT FROM pg_temp.cleanup_state(scan) AND NOT internal.initial_admission_sealed();
 results:=results||jsonb_build_array(jsonb_build_object('case','rollback removing xact seal restores all stage/child progress','pass',valid));
 RETURN results;
EXCEPTION WHEN OTHERS THEN
 PERFORM pg_advisory_unlock_all(); RAISE;
END; $$;
\if :{?seal_lock_peer}
CREATE FUNCTION pg_temp.seal_peer_conflict() RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE scan UUID:='00000000-0000-4000-8000-000000005544'; before_state JSONB; failure TEXT;
BEGIN
 before_state:=pg_temp.cleanup_state(scan);
 BEGIN
  PERFORM internal.materialize_initial_admission(scan);
  PERFORM internal.freeze_initial_admission_ledger(scan);
  PERFORM internal.begin_initial_admission_consumption(scan);
  PERFORM internal.seal_initial_admission(scan);
  RAISE EXCEPTION 'unexpected peer seal acceptance' USING ERRCODE='ZX001';
 EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM;
 END;
 IF before_state IS DISTINCT FROM pg_temp.cleanup_state(scan) OR internal.initial_admission_sealed() THEN
  RAISE EXCEPTION 'peer conflict failed rollback';
 END IF;
 RETURN failure;
END $$;
SELECT extensions.ok(NOT internal.initial_admission_sealed(),'other backend seal does not deny unrelated current-backend work');
SELECT extensions.is(pg_temp.seal_peer_conflict(),'55000:initial_analysis_admission_sealed',
 'competing seal key fails without waiting or granting authority; rolls back all consumption progress');
\else
SELECT extensions.is((SELECT count(*) FROM pg_trigger WHERE tgname='a00_initial_admission_seal'),38::BIGINT,
 'seal inventory includes every ordinary source/member/alias/erasure root');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='a00_initial_admission_seal'
 AND (tgtype<>62 OR tgenabled<>'O')),'all seal guards are BEFORE STATEMENT INSERT UPDATE DELETE TRUNCATE');
CREATE TEMP TABLE seal_matrix_results AS SELECT e FROM jsonb_array_elements(pg_temp.seal_matrix()) e;
SELECT extensions.ok((e->>'pass')::BOOLEAN,e->>'case') FROM seal_matrix_results;

CREATE FUNCTION pg_temp.entry_after_failure() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF OLD.phase='allocated' AND NEW.phase='consuming' AND current_setting('merian.test_entry_fault',TRUE)='after' THEN
  RAISE EXCEPTION 'synthetic_entry_after_failure';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER zz_test_entry_failure AFTER UPDATE ON internal.initial_preparation_admission_staging
 FOR EACH ROW EXECUTE FUNCTION pg_temp.entry_after_failure();
CREATE TEMP TABLE nested_entry_probe(scan UUID);
CREATE FUNCTION pg_temp.nested_entry_update() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 UPDATE internal.initial_preparation_admission_staging SET phase='consuming' WHERE scan_id=NEW.scan;
 RETURN NEW;
END $$;
CREATE TRIGGER nested_entry_update BEFORE INSERT ON nested_entry_probe FOR EACH ROW EXECUTE FUNCTION pg_temp.nested_entry_update();
CREATE FUNCTION pg_temp.entry_seal_fault(fault TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE scan UUID:='00000000-0000-4000-8000-000000005544'; before_state JSONB; failure TEXT;
BEGIN
 before_state:=pg_temp.cleanup_state(scan);
 BEGIN
  PERFORM internal.materialize_initial_admission(scan);
  PERFORM internal.freeze_initial_admission_ledger(scan);
  IF fault='session' THEN PERFORM pg_advisory_lock(1229018189,hashtext(scan::TEXT)); END IF;
  BEGIN
   IF fault='immutable' THEN
    UPDATE internal.initial_preparation_admission_staging SET phase='consuming',stage_token=gen_random_uuid() WHERE scan_id=scan;
   ELSIF fault='after' THEN
    PERFORM set_config('merian.test_entry_fault','after',TRUE);
    PERFORM internal.begin_initial_admission_consumption(scan);
   ELSIF fault='nested' THEN
    INSERT INTO nested_entry_probe VALUES(scan);
    IF NOT internal.initial_admission_sealed() THEN RAISE EXCEPTION 'nested entry missing seal'; END IF;
    PERFORM pg_advisory_unlock_all();
    PERFORM internal.consume_initial_admission_writes(scan);
    IF NOT internal.initial_admission_sealed() THEN RAISE EXCEPTION 'nested cleanup lost seal'; END IF;
    failure:='nested_proven_cleanup';
   ELSE PERFORM internal.begin_initial_admission_consumption(scan);
   END IF;
  EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM;
  END;
  PERFORM pg_advisory_unlock_all();
  IF fault<>'nested' AND (internal.initial_admission_sealed() OR NOT EXISTS(
   SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=scan AND phase='allocated' AND cleanup_cursor=0)) THEN
   RAISE EXCEPTION 'failed entry retained phase or seal';
  END IF;
  RAISE EXCEPTION 'entry test rollback' USING ERRCODE='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
 END;
 IF before_state IS DISTINCT FROM pg_temp.cleanup_state(scan) OR internal.initial_admission_sealed() THEN
  RAISE EXCEPTION 'entry fault failed rollback';
 END IF;
 RETURN failure;
EXCEPTION WHEN OTHERS THEN PERFORM pg_advisory_unlock_all(); RAISE;
END $$;
SELECT extensions.is(pg_temp.entry_seal_fault('immutable'),'55000:initial_analysis_preparation_required',
 'immutable entry rejection acquires no seal and preserves phase');
SELECT extensions.is(pg_temp.entry_seal_fault('after'),'P0001:synthetic_entry_after_failure',
 'AFTER phase failure rolls back actual acquired xact seal and phase together');
SELECT extensions.is(pg_temp.entry_seal_fault('session'),'55000:initial_analysis_admission_sealed',
 'forged session lock rejects entry rather than substituting for xact acquisition');
SELECT extensions.is(pg_temp.entry_seal_fault('nested'),'nested_proven_cleanup',
 'nested private phase transition acquires seal and cleans up without optional seal helper');
DROP TRIGGER zz_test_entry_failure ON internal.initial_preparation_admission_staging;

-- Real SQL savepoint/release boundaries supplement PL/pgSQL exception rollback.
-- Assertions inside rolled-back savepoints use DO, preserving pgTAP numbering.
SAVEPOINT before_terminal_phase;
SELECT internal.materialize_initial_admission('00000000-0000-4000-8000-000000005544');
SELECT internal.freeze_initial_admission_ledger('00000000-0000-4000-8000-000000005544');
SAVEPOINT before_terminal_entry;
SELECT internal.begin_initial_admission_consumption('00000000-0000-4000-8000-000000005544');
SAVEPOINT after_terminal_seal;
SELECT internal.consume_initial_admission_writes('00000000-0000-4000-8000-000000005544');
ROLLBACK TO after_terminal_seal;
DO $$ BEGIN
 IF NOT internal.initial_admission_sealed() OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging
  WHERE scan_id='00000000-0000-4000-8000-000000005544' AND cleanup_cursor=0) THEN RAISE EXCEPTION 'after-seal savepoint rollback lost seal or cursor'; END IF;
END $$;
RELEASE SAVEPOINT after_terminal_seal;
ROLLBACK TO before_terminal_entry;
DO $$ BEGIN
 IF internal.initial_admission_sealed() OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging
  WHERE scan_id='00000000-0000-4000-8000-000000005544' AND phase='allocated' AND cleanup_cursor=0) THEN RAISE EXCEPTION 'before-entry rollback mismatch'; END IF;
END $$;
SELECT internal.begin_initial_admission_consumption('00000000-0000-4000-8000-000000005544');
RELEASE SAVEPOINT before_terminal_entry;
DO $$ BEGIN IF NOT internal.initial_admission_sealed() THEN RAISE EXCEPTION 'release lost seal'; END IF; END $$;
ROLLBACK TO before_terminal_phase;
RELEASE SAVEPOINT before_terminal_phase;
SELECT extensions.ok(NOT internal.initial_admission_sealed() AND EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging
 WHERE scan_id='00000000-0000-4000-8000-000000005544' AND phase='compared' AND completion_ledger IS NULL),
 'savepoint rollback/release retains or removes seal with associated cleanup progress');

CREATE FUNCTION pg_temp.seal_lock_filters() RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
DECLARE valid BOOLEAN; failure TEXT;
BEGIN
 PERFORM pg_advisory_lock_shared(1229018189,7);
 valid:=NOT internal.initial_admission_sealed(); PERFORM pg_advisory_unlock_all();
 PERFORM pg_advisory_lock(1229018188,7);
 valid:=valid AND NOT internal.initial_admission_sealed(); PERFORM pg_advisory_unlock_all();
 PERFORM pg_advisory_lock(1229018189::BIGINT*4294967296+7);
 valid:=valid AND NOT internal.initial_admission_sealed(); PERFORM pg_advisory_unlock_all();
 PERFORM pg_advisory_lock(1229018189,7);
 valid:=valid AND internal.initial_admission_sealed();
 BEGIN UPDATE public.users SET marketing_opt_in=marketing_opt_in WHERE FALSE;
 EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
 valid:=valid AND failure IS NOT DISTINCT FROM '55000:initial_analysis_admission_sealed';
 PERFORM pg_advisory_unlock_all();
 RETURN valid AND NOT internal.initial_admission_sealed();
EXCEPTION WHEN OTHERS THEN PERFORM pg_advisory_unlock_all(); RAISE;
END $$;
SELECT extensions.ok(pg_temp.seal_lock_filters(),'seal filters lock mode, exact two-int namespace and objsubid; forged lock only over-denies');
SELECT extensions.throws_ok('SELECT internal.seal_initial_admission(NULL)','55000','initial_analysis_admission_incomplete','seal requires an original consuming-stage proof');
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.seal_initial_admission(NULL)'),
 '42501',role_name||' denied private seal acquisition') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;

\endif

CREATE FUNCTION pg_temp.cross_registry_collision(reverse_order BOOLEAN) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE source_value internal.initial_preparation_source_registry; destination_value internal.initial_analysis_media_registry;
BEGIN
 BEGIN
  PERFORM internal.materialize_initial_admission('00000000-0000-4000-8000-000000005544');
  SELECT * INTO STRICT source_value FROM internal.initial_preparation_source_registry WHERE scan_id='00000000-0000-4000-8000-000000005544' ORDER BY object_id LIMIT 1;
  SELECT * INTO STRICT destination_value FROM internal.initial_analysis_media_registry WHERE scan_id='00000000-0000-4000-8000-000000005544' ORDER BY object_id LIMIT 1;
  IF reverse_order THEN
   source_value.object_id:=destination_value.object_id;
   INSERT INTO internal.initial_preparation_source_registry SELECT source_value.*;
  ELSE
   destination_value.object_id:=source_value.object_id;
   INSERT INTO internal.initial_analysis_media_registry SELECT destination_value.*;
  END IF;
  RAISE EXCEPTION 'unexpected cross-registry acceptance' USING ERRCODE='ZX001';
 EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE||':'||SQLERRM;
 END;
END; $$;
SELECT extensions.is(pg_temp.cross_registry_collision(FALSE),'22023:initial_analysis_identity_conflict','destination insertion cannot reuse source/output UUID');
SELECT extensions.is(pg_temp.cross_registry_collision(TRUE),'22023:initial_analysis_identity_conflict','source insertion cannot reuse destination UUID');

-- The runner can hold this exact namespace in a second local database
-- transaction. Raw malformed insert shape intentionally proves the namespace
-- collision fails before any later owner/row check, never by reaching storage.
\if :{?namespace_lock_peer}
SELECT extensions.throws_ok($q$INSERT INTO internal.initial_preparation_source_registry(object_id)
 VALUES('00000000-0000-4000-8000-000000005566')$q$,'55000','initial_analysis_scope_busy',
 'source registry fails fast against the other transaction namespace lock');
SELECT extensions.throws_ok($q$INSERT INTO internal.initial_analysis_media_registry(object_id)
 VALUES('00000000-0000-4000-8000-000000005566')$q$,'55000','initial_analysis_scope_busy',
 'destination registry fails fast against the other transaction namespace lock');
\else
SELECT extensions.skip('requires disposable runner second-session namespace lock',2);
\endif

-- Exercise the actual owners with distinct quota and execution model identities.
-- Provider routing is synthetic and local to this rollback-only transaction.
UPDATE internal.identification_provider_bindings SET provider='openai',binding='openai_photo_v1',
 processor_permission='openai',provider_model='gpt-6-sol',minimum_identification_protocol=4
 WHERE operation='scan_identification' AND input_profile='multimodal_photo_v1';
UPDATE media_vectors SET v=jsonb_set(v,'{candidate,source_plan,admission,expected_processor_permission}','"openai"'::JSONB) WHERE i=2;
SELECT extensions.lives_ok($q$SELECT pg_temp.media_create('00000000-0000-4000-8000-000000005555',2)$q$,'OpenAI photo preparation with preserved provider policy');
SELECT extensions.lives_ok($q$SELECT pg_temp.execution_advance('00000000-0000-4000-8000-000000005555',4)$q$,'OpenAI photo prepared original outcome');
SELECT internal.create_initial_admission_stage('00000000-0000-4000-8000-00000000f001','00000000-0000-4000-8000-000000005555');
SELECT set_config('merian.initial_admission_stage',(SELECT stage_token::TEXT FROM internal.initial_preparation_admission_staging WHERE scan_id='00000000-0000-4000-8000-000000005555'),TRUE);
SELECT set_config('merian.initial_preparation_funding','00000000-0000-4000-8000-00000000f001:00000000-0000-4000-8000-000000005555',TRUE);
SELECT set_config('merian.initial_analysis_admission','00000000-0000-4000-8000-00000000f001:00000000-0000-4000-8000-000000005555',TRUE);
SELECT set_config('merian.test_atomic_scan','00000000-0000-4000-8000-000000005555',TRUE);
SELECT extensions.lives_ok($q$SELECT * FROM public.reserve_identification_quota('00000000-0000-4000-8000-00000000f001','scan_identification',
 '00000000-0000-4000-8000-000000005555',repeat('a',64),'00000000-0000-4000-8000-000000005555',FALSE,3,FALSE,
 'multimodal_photo_v1','openai',6)$q$,'OpenAI original funding and attempt match exact expected images');
CREATE TEMP TABLE prospective_openai AS SELECT r.* FROM internal.build_initial_admission_receipt('00000000-0000-4000-8000-000000005555') r;
SELECT extensions.is(funding::JSONB#>>'{original,model}','gpt-6-sol','OpenAI funding proof freezes actual execution model') FROM prospective_openai;
SELECT extensions.is(accounting::JSONB#>>'{attempt,model}','gemini-2.5-pro','OpenAI attempt preserves base quota model') FROM prospective_openai;
SELECT extensions.is(accounting::JSONB#>>'{attempt,provider_model}','gpt-6-sol','OpenAI attempt separately retains provider model') FROM prospective_openai;
SELECT extensions.is(q.model,'gemini-2.5-pro','OpenAI reservation stays on original quota policy') FROM prospective_openai r
 JOIN internal.ai_quota_reservations q ON q.id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID;
SELECT extensions.is(receipt_digest,internal.validate_initial_admitted_proof(candidate,input,configuration,funding,outcome,
 installation,protocol,destination,mapping,media_binding,accounting,manifest),'complete proof accepts exact quota/execution model split') FROM prospective_openai;
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_admission_receipts),0::BIGINT,'OpenAI probe does not persist a receipt or invoke a provider');
SELECT extensions.ok(pg_temp.live_snapshot_probe('00000000-0000-4000-8000-000000005555'),'OpenAI live snapshot preserves original quota versus execution model split');


SELECT extensions.ok(EXISTS(SELECT 1 FROM nested_owner_probes WHERE kind LIKE 'counter:%'),'nested C4 injection exercised actual shared counter writes');
SELECT extensions.ok(EXISTS(SELECT 1 FROM nested_owner_probes WHERE kind='epoch'),'nested C8 injection exercised actual same-owner epoch writes');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM nested_owner_probes WHERE denial<>'55000:initial_analysis_preparation_required'),'nested unrelated original owners are denied before shared mutation');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM nested_owner_probes WHERE NOT expectations_unchanged),'nested unrelated owners consume no stage expectations');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE request_id IN ('00000000-0000-4000-8000-000000005590','00000000-0000-4000-8000-000000005591')),0::BIGINT,'nested owners leave no unrelated reservation');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-000000005591'),0::BIGINT,'nested owner leaves no unrelated complimentary hold');
DROP TRIGGER aa_test_nested_original_owner ON internal.ai_quota_counters;
DROP TRIGGER aa_test_nested_original_owner ON public.users;

-- Unlike the private phase probes above, this fresh lifecycle keeps every
-- permanent admission/source/member/deferred guard enabled from stage INSERT.
ALTER TABLE internal.initial_preparation_admission_staging ENABLE TRIGGER require_complete_initial_admission;
CREATE TEMP TABLE terminal_unrelated_failure(value BOOLEAN);
CREATE FUNCTION pg_temp.terminal_unrelated_fail() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN RAISE EXCEPTION 'synthetic_unrelated_deferred_failure'; END $$;
CREATE CONSTRAINT TRIGGER terminal_unrelated_fail AFTER INSERT ON terminal_unrelated_failure
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION pg_temp.terminal_unrelated_fail();
CREATE TEMP TABLE terminal_cutoff_failure(scan_id UUID);
CREATE FUNCTION pg_temp.terminal_cutoff_wait() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
DECLARE cutoff NUMERIC; remaining NUMERIC;
BEGIN
 SELECT (media_binding::JSONB#>>'{phase_window,cutoffs,admission}')::NUMERIC INTO STRICT cutoff
 FROM internal.initial_preparation_admission_receipts WHERE scan_id=NEW.scan_id;
 remaining:=(cutoff-floor(extract(epoch FROM clock_timestamp())*1000))/1000;
 IF remaining>61 THEN RAISE EXCEPTION 'unexpected synthetic cutoff budget'; END IF;
 PERFORM pg_sleep(greatest(remaining,0)+0.01);
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER terminal_cutoff_wait AFTER INSERT ON terminal_cutoff_failure
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION pg_temp.terminal_cutoff_wait();
CREATE FUNCTION pg_temp.terminal_state(scan UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('members',pg_temp.materialization_state(scan),
  'operation',(SELECT to_jsonb(t) FROM internal.initial_analysis_operation_fences t WHERE scan_id=scan),
  'intent',(SELECT to_jsonb(t) FROM internal.initial_analysis_preparation_intents t WHERE scan_id=scan),
  'source',(SELECT to_jsonb(t) FROM internal.initial_preparation_source_fences t WHERE scan_id=scan),
  'funding',(SELECT jsonb_agg(to_jsonb(t) ORDER BY id) FROM internal.ai_quota_reservations t),
  'holds',(SELECT jsonb_agg(to_jsonb(t) ORDER BY user_id,client_scan_id) FROM internal.complimentary_scan_usage t),
  'counters',(SELECT jsonb_agg(to_jsonb(t) ORDER BY scope_type,scope_key,bucket,window_start) FROM internal.ai_quota_counters t),
  'user',(SELECT to_jsonb(t) FROM public.users t WHERE id='00000000-0000-4000-8000-00000000f001'))
$$;
CREATE FUNCTION pg_temp.terminal_early_flush() RETURNS TEXT LANGUAGE PLPGSQL AS $$
BEGIN
 SET CONSTRAINTS internal.require_complete_initial_admission IMMEDIATE;
 RETURN 'unexpected early acceptance';
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE||':'||SQLERRM;
END $$;
CREATE FUNCTION pg_temp.public_recovery(role_name TEXT,command TEXT,owner_id UUID,scan UUID,candidate TEXT) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE original_role TEXT:=current_setting('role'); result JSONB;
BEGIN
 EXECUTE format('SET LOCAL ROLE %I',role_name);
 EXECUTE command INTO result USING owner_id,scan,candidate;
 PERFORM set_config('role',original_role,TRUE);
 RETURN result;
END $$;
-- Trusted corruption/precedence probes only; every mutation and trigger override
-- is rolled back inside its subtransaction. No authorized deletion is simulated.
CREATE FUNCTION pg_temp.recovery_fault(owner_id UUID,scan UUID,mode TEXT,public_action TEXT DEFAULT NULL,public_identity TEXT DEFAULT NULL) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE result JSONB; saved_candidate TEXT; original_retained TEXT; original_security JSONB; fixture_receipt UUID;
BEGIN
 SELECT candidate INTO saved_candidate FROM internal.initial_preparation_admission_receipts WHERE scan_id=scan;
 IF mode='missing_admission' AND public_action IS NOT NULL THEN
  SELECT pg_get_functiondef(p.oid),jsonb_build_array(p.proowner,p.prosecdef,p.proconfig,p.proacl)
   INTO STRICT original_retained,original_security FROM pg_proc p
   WHERE p.oid='internal.initial_admission_retained_receipt(uuid,uuid,uuid)'::REGPROCEDURE;
  SELECT admission_receipt_id INTO STRICT fixture_receipt
   FROM internal.initial_preparation_admission_receipts r WHERE r.scan_id=scan AND r.owner_id=recovery_fault.owner_id;
  IF fixture_receipt IS NULL OR (length(original_retained)-length(replace(original_retained,E'BEGIN\n','')))/length(E'BEGIN\n')<>1 THEN
   RAISE EXCEPTION 'retained receipt fixture seam changed';
  END IF;
 END IF;
 BEGIN
  IF mode='missing_receipt' THEN
   ALTER TABLE internal.initial_preparation_admission_receipts DISABLE TRIGGER USER;
   DELETE FROM internal.initial_preparation_admission_receipts WHERE scan_id=scan;
  ELSIF mode='missing_admission' AND public_action IS NOT NULL THEN
   -- Wrapper routing only: the actual missing-row integrity case remains above.
   -- Exact identity, distinct error and rollback checks prevent an earlier generic
   -- failure from being mistaken for propagation through the retained boundary.
   EXECUTE replace(original_retained,E'BEGIN\n',E'BEGIN\n'||format(
    ' IF p_owner=%L::UUID AND p_scan=%L::UUID AND p_receipt=%L::UUID THEN RAISE EXCEPTION %L USING ERRCODE=%L; END IF;',
    owner_id,scan,fixture_receipt,'synthetic_retained_admission_unavailable','55000')||E'\n');
  ELSIF mode='missing_admission' THEN
   PERFORM pg_temp.retained_fixture_foreign_keys();
   ALTER TABLE internal.initial_analysis_admissions DISABLE TRIGGER USER;
   DELETE FROM internal.initial_analysis_admissions WHERE scan_id=scan;
  ELSIF mode='missing_lifecycle' THEN
   ALTER TABLE internal.initial_analysis_lifecycle_fences DISABLE TRIGGER USER;
   DELETE FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=scan;
  ELSIF mode IN ('cancelled_pre_dispatch','cancelled_dispatched','cancelled_unknown') THEN
   ALTER TABLE internal.initial_analysis_lifecycle_fences DISABLE TRIGGER USER;
   UPDATE internal.initial_analysis_lifecycle_fences SET state=mode WHERE scan_id=scan;
   -- Missing receipt makes precedence observable: cancellation must win.
   ALTER TABLE internal.initial_preparation_admission_receipts DISABLE TRIGGER USER;
   DELETE FROM internal.initial_preparation_admission_receipts WHERE scan_id=scan;
  ELSIF mode='unknown_owner' THEN
   ALTER TABLE internal.initial_preparation_admission_receipts DISABLE TRIGGER USER;
   -- A missing caller owner must fail before private receipt lookup.
   owner_id:='00000000-0000-4000-8000-000000009999';
  ELSIF mode='deleted' THEN
   ALTER TABLE internal.scan_deletion_tombstones DISABLE TRIGGER USER;
   INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES(scan,owner_id);
   ALTER TABLE internal.initial_preparation_admission_receipts DISABLE TRIGGER USER;
   DELETE FROM internal.initial_preparation_admission_receipts WHERE scan_id=scan;
  ELSIF mode='dispatch_authorized' THEN
   ALTER TABLE internal.initial_analysis_lifecycle_fences DISABLE TRIGGER USER;
   UPDATE internal.initial_analysis_lifecycle_fences SET state=mode WHERE scan_id=scan;
  ELSE RAISE EXCEPTION 'unknown recovery fixture'; END IF;
  IF public_action IS NULL THEN result:=internal.recover_initial_admitted_media(owner_id,scan);
  ELSE result:=pg_temp.public_recovery('service_role',public_action,owner_id,scan,COALESCE(public_identity,saved_candidate)); END IF;
  IF result->>'authority'<>'none' OR result->>'outcome'<>'admitted' THEN RAISE EXCEPTION 'unexpected recovery response'; END IF;
  RAISE EXCEPTION 'synthetic recovery acceptance' USING ERRCODE='ZX003';
 EXCEPTION WHEN OTHERS THEN
  -- Exception entry rolled back the entire override before these comparisons.
  IF original_retained IS NOT NULL AND (
   pg_get_functiondef('internal.initial_admission_retained_receipt(uuid,uuid,uuid)'::REGPROCEDURE) IS DISTINCT FROM original_retained
   OR (SELECT jsonb_build_array(p.proowner,p.prosecdef,p.proconfig,p.proacl) FROM pg_proc p
    WHERE p.oid='internal.initial_admission_retained_receipt(uuid,uuid,uuid)'::REGPROCEDURE) IS DISTINCT FROM original_security
  ) THEN RAISE EXCEPTION 'retained receipt fixture not restored'; END IF;
  RETURN SQLSTATE||':'||SQLERRM;
 END;
END $$;
-- Clock substitution and C1 tripwire are trusted, transaction-local test
-- instrumentation. Restore exact installed definitions; no input/receipt is
-- rewritten. The admitted guard must return before the legacy intent clock.
CREATE FUNCTION pg_temp.admitted_execution_denials(owner_id UUID,scan UUID,digest TEXT) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE original_action TEXT; original_cancel TEXT; clock_anchor TEXT;
 command TEXT; boundary INTEGER; fault TEXT; failure TEXT; reply JSONB; rows JSONB:='[]';
BEGIN
 SELECT pg_get_functiondef('internal.initial_preparation_execution_action(text,uuid,uuid,text,text)'::REGPROCEDURE) INTO STRICT original_action;
 SELECT pg_get_functiondef('internal.cancel_initial_analysis(uuid,uuid)'::REGPROCEDURE) INTO STRICT original_cancel;
 clock_anchor:='now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT; expiry_ms:=';
 IF (length(original_action)-length(replace(original_action,clock_anchor,'')))/length(clock_anchor)<>1 THEN RAISE EXCEPTION 'fixture clock seam changed'; END IF;
 EXECUTE $tripwire$CREATE OR REPLACE FUNCTION internal.cancel_initial_analysis(p_owner UUID,p_scan UUID) RETURNS JSONB
 LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $body$ BEGIN RAISE EXCEPTION 'unexpected legacy cancellation' USING ERRCODE='ZX004'; END $body$;$tripwire$;
 FOREACH boundary IN ARRAY ARRAY[-1,0,1] LOOP
  EXECUTE replace(original_action,clock_anchor,'now_ms:=floor(extract(epoch FROM saved.expires_at)*1000)::BIGINT+'||boundary::TEXT||'; expiry_ms:=');
  FOREACH command IN ARRAY ARRAY[
   'SELECT public.get_initial_preparation_execution_status($1,$2,$3)',
   'SELECT public.settle_initial_preparation_sources($1,$2,$3,NULL)',
   'SELECT public.issue_initial_preparation_execution($1,$2,$3,NULL)',
   'SELECT public.register_initial_preparation_output($1,$2,$3,NULL)',
   'SELECT public.settle_initial_preparation_outcome($1,$2,$3,NULL)'
  ] LOOP
   failure:=NULL;reply:=NULL;
   BEGIN reply:=pg_temp.public_recovery('service_role',command,owner_id,scan,digest);
   EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
   rows:=rows||jsonb_build_array(jsonb_build_object('case','admitted old action denied without C1 at expiry offset '||boundary||': '||command,
    'pass',failure IS NULL AND reply IS NOT DISTINCT FROM jsonb_build_object('version',2,'outcome','held','reason','incoherent','authority','none'),'failure',failure));
   IF boundary=0 THEN
    FOREACH fault IN ARRAY ARRAY['missing_receipt','missing_admission'] LOOP
     failure:=pg_temp.recovery_fault(owner_id,scan,fault,command,digest);
     rows:=rows||jsonb_build_array(jsonb_build_object('case','admitted old action rejects '||fault||CASE WHEN fault='missing_admission' THEN ' retained-boundary seam' ELSE '' END||': '||command,
      'pass',failure IS NOT DISTINCT FROM CASE WHEN fault='missing_admission' THEN '55000:synthetic_retained_admission_unavailable' ELSE '55000:initial_analysis_admission_incomplete' END,'failure',failure));
    END LOOP;
    failure:=NULL;
    BEGIN PERFORM pg_temp.public_recovery('service_role',command,'00000000-0000-4000-8000-00000000f002',scan,digest);
    EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
    rows:=rows||jsonb_build_array(jsonb_build_object('case','admitted old action denies different existing owner: '||command,
     'pass',failure IS NOT DISTINCT FROM '55000:initial_analysis_admission_incomplete','failure',failure));
    failure:=NULL;
    BEGIN PERFORM pg_temp.public_recovery('service_role',command,owner_id,scan,repeat('f',64));
    EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
    rows:=rows||jsonb_build_array(jsonb_build_object('case','admitted old action denies different assignment: '||command,
     'pass',failure IS NOT DISTINCT FROM '22023:initial_analysis_identity_conflict','failure',failure));
   END IF;
  END LOOP;
 END LOOP;
 EXECUTE original_action; EXECUTE original_cancel;
 RETURN rows;
END $$;
CREATE FUNCTION pg_temp.terminal_probe(mode TEXT) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE scan UUID:='00000000-0000-4000-8000-000000006655'; owner_id UUID:='00000000-0000-4000-8000-00000000f001';
 before_state JSONB; results JSONB:='[]'; saved_id UUID; s internal.initial_preparation_admission_staging;
 receipt internal.initial_preparation_admission_receipts; failure TEXT; command TEXT; original_guard TEXT; n INTEGER:=0; recovered JSONB; clock_value NUMERIC; cutoff NUMERIC; phase_name TEXT; replay_state JSONB; changed_candidate TEXT;
BEGIN
 before_state:=pg_temp.terminal_state(scan);
 BEGIN
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('merian.initial_admission_stage','',TRUE);
  -- Multimodal photo has two genuine ordered descriptions for retry-order checks.
  PERFORM pg_temp.media_create(scan,2);
  PERFORM pg_temp.execution_advance(scan,4);
  IF mode='early_insert_identity' THEN
   -- Capture a corrupt INSERT identity, then restore the intended identity from
   -- the unchanged canonical window before running any actual funding owners.
   SELECT pg_get_functiondef('internal.guard_initial_admission_stage()'::REGPROCEDURE) INTO original_guard;
   EXECUTE $override$CREATE OR REPLACE FUNCTION internal.guard_initial_admission_stage()
    RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
    BEGIN IF TG_OP='INSERT' THEN NEW.admission_receipt_id:=pg_catalog.gen_random_uuid(); END IF;
    RETURN NEW; END $body$; $override$;
  END IF;
  PERFORM internal.create_initial_admission_stage(owner_id,scan);
  SELECT * INTO STRICT s FROM internal.initial_preparation_admission_staging WHERE scan_id=scan;
  saved_id:=(s.phase_window::JSONB->>'admission_receipt_id')::UUID;
  IF mode='early_insert_identity' THEN
   UPDATE internal.initial_preparation_admission_staging SET admission_receipt_id=saved_id WHERE scan_id=scan;
   EXECUTE original_guard;
  END IF;
  PERFORM set_config('merian.initial_admission_stage',s.stage_token::TEXT,TRUE);
  PERFORM set_config('merian.initial_preparation_funding',owner_id::TEXT||':'||scan::TEXT,TRUE);
  PERFORM set_config('merian.initial_analysis_admission',owner_id::TEXT||':'||scan::TEXT,TRUE);
  PERFORM set_config('merian.test_atomic_scan',scan::TEXT,TRUE);
  IF mode='normal' THEN
   failure:=pg_temp.terminal_early_flush();
   results:=results||jsonb_build_array(jsonb_build_object('case','validated INSERT early flush rejects','pass',failure='55000:initial_analysis_admission_incomplete'));
  ELSIF mode='early_update_identity' THEN
   -- Trusted corruption fixture changes captured event identity, then makes the
   -- final live state otherwise coherent. No production guard is bypassed later.
   -- Pending deferred events prohibit ALTER TABLE trigger toggling. A trusted,
   -- transactional test-only function override injects the captured bad image;
   -- restore the exact production guard before continuing the real lifecycle.
   SELECT pg_get_functiondef('internal.guard_initial_admission_stage()'::REGPROCEDURE) INTO original_guard;
   EXECUTE $override$CREATE OR REPLACE FUNCTION internal.guard_initial_admission_stage()
    RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
    BEGIN IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END $body$; $override$;
   UPDATE internal.initial_preparation_admission_staging SET admission_receipt_id=gen_random_uuid() WHERE scan_id=scan;
   IF mode='early_update_identity' THEN
    UPDATE internal.initial_preparation_admission_staging SET admission_receipt_id=saved_id WHERE scan_id=scan;
   END IF;
   EXECUTE original_guard;
  END IF;
  IF mode='unrelated' THEN INSERT INTO terminal_unrelated_failure VALUES(TRUE); END IF;
  PERFORM pg_temp.probe_original_owner_images(scan,'multimodal_photo_v1','openai');
  IF mode='normal' THEN
   failure:=pg_temp.terminal_early_flush();
   results:=results||jsonb_build_array(jsonb_build_object('case','funding member events early flush rejects','pass',failure='55000:initial_analysis_admission_incomplete'));
  END IF;
  PERFORM internal.materialize_initial_admission(scan);
  PERFORM internal.freeze_initial_admission_ledger(scan);
  IF mode='normal' THEN
   failure:=pg_temp.terminal_early_flush();
   results:=results||jsonb_build_array(jsonb_build_object('case','allocated receipt early flush rejects','pass',failure='55000:initial_analysis_admission_incomplete'));
   failure:=NULL;
   BEGIN PERFORM internal.recover_initial_admitted_media(owner_id,scan);
   EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
   results:=results||jsonb_build_array(jsonb_build_object('case','recovery rejects allocated receipt while original stage still exists',
    'pass',failure IS NOT DISTINCT FROM '55000:initial_analysis_admission_incomplete'));

  END IF;
  PERFORM internal.begin_initial_admission_consumption(scan);
  IF mode='normal' THEN
   failure:=pg_temp.terminal_early_flush();
   results:=results||jsonb_build_array(jsonb_build_object('case','consuming entry early flush rejects','pass',failure='55000:initial_analysis_admission_incomplete'));
   LOOP
    SELECT * INTO STRICT s FROM internal.initial_preparation_admission_staging WHERE scan_id=scan;
    EXIT WHEN s.cleanup_cursor=jsonb_array_length(s.completion_ledger);
    DELETE FROM internal.initial_preparation_admission_writes WHERE scan_id=scan
     AND statement_key=s.completion_ledger->s.cleanup_cursor::INTEGER->>'statement_key';
    n:=n+1;
    failure:=pg_temp.terminal_early_flush();
    results:=results||jsonb_build_array(jsonb_build_object('case','cleanup step '||n||' early flush rejects','pass',failure='55000:initial_analysis_admission_incomplete'));
   END LOOP;
  ELSIF mode='delete_old_cursor' THEN
   PERFORM internal.consume_initial_admission_writes(scan);
   -- Trusted corruption fixture only; function replacement is rolled back with
   -- this failing subtransaction. The deferred verifier itself stays unmodified.
   EXECUTE $override$CREATE OR REPLACE FUNCTION internal.guard_initial_admission_stage()
    RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
    BEGIN IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END $body$; $override$;
   UPDATE internal.initial_preparation_admission_staging SET cleanup_cursor=cleanup_cursor-1 WHERE scan_id=scan;
   DELETE FROM internal.initial_preparation_admission_staging WHERE scan_id=scan;
   SET CONSTRAINTS ALL IMMEDIATE;
   RAISE EXCEPTION 'unexpected corrupt DELETE OLD acceptance';
  END IF;
  IF mode='cutoff' THEN
   -- Queue last: real admission deferred callbacks run first. The trusted fixture
   -- waits only to the original cutoff; no production clocks or rows are changed.
   INSERT INTO terminal_cutoff_failure VALUES(scan);
  END IF;
  IF mode='normal' THEN
   SELECT * INTO STRICT s FROM internal.initial_preparation_admission_staging WHERE scan_id=scan;
   BEGIN
    receipt:=internal.finish_initial_admission(scan);
    RAISE EXCEPTION 'rollback after terminal parent deletion' USING ERRCODE='ZX002';
   EXCEPTION WHEN SQLSTATE 'ZX002' THEN NULL;
   END;
   results:=results||jsonb_build_array(jsonb_build_object('case','rollback after forced terminal completion restores complete consuming stage and retains earlier seal',
    'pass',(SELECT to_jsonb(t)=to_jsonb(s) FROM internal.initial_preparation_admission_staging t WHERE scan_id=scan)
     AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id=scan)
     AND internal.initial_admission_sealed()));
  END IF;
  BEGIN
   receipt:=internal.finish_initial_admission(scan);
  EXCEPTION WHEN OTHERS THEN
   IF mode='cutoff' AND SQLSTATE='55000' AND SQLERRM='initial_analysis_preparation_expired' THEN
    failure:=pg_temp.terminal_early_flush();
    results:=results||jsonb_build_array(jsonb_build_object('case','caught final cutoff restores incomplete stage and cannot commit funding',
     'pass',failure='55000:initial_analysis_admission_incomplete'
      AND EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=scan)
      AND internal.initial_admission_sealed()));
   END IF;
   RAISE;
  END;
  IF mode<>'normal'  THEN RAISE EXCEPTION 'unexpected terminal fault acceptance'; END IF;
  results:=results||jsonb_build_array(jsonb_build_object('case','fresh original INSERT/funding/member/cleanup/DELETE event queue accepts complete receipt',
   'pass',receipt.scan_id=scan AND receipt.admission_receipt_id=saved_id
    AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=scan)
    AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id=scan)));
  PERFORM set_config('merian.initial_admission_stage','',TRUE);
  PERFORM pg_advisory_unlock_all();
  FOREACH command IN ARRAY ARRAY[
   'UPDATE public.users SET complimentary_entitlement_epoch=complimentary_entitlement_epoch+1',
   'UPDATE internal.ai_quota_counters SET request_count=request_count+1',
   'DELETE FROM internal.initial_preparation_admission_receipts WHERE scan_id=''00000000-0000-4000-8000-000000006655''',
   'DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=''00000000-0000-4000-8000-000000006655''',
   'UPDATE internal.initial_analysis_media_registry SET retired=TRUE WHERE scan_id=''00000000-0000-4000-8000-000000006655''',
   'TRUNCATE internal.ai_quota_counters CASCADE'
  ] LOOP
   failure:=NULL;
   BEGIN EXECUTE command; EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
   results:=results||jsonb_build_array(jsonb_build_object('case','after stage deletion/forced constraints/cleared GUC: '||command,
    'pass',failure IS NOT DISTINCT FROM '55000:initial_analysis_admission_sealed','failure',failure));
  END LOOP;
  SET CONSTRAINTS ALL IMMEDIATE;
  PERFORM internal.assert_initial_admission_live_receipt(owner_id,scan,receipt.admission_receipt_id);
  results:=results||jsonb_build_array(jsonb_build_object('case','retained proof returns exact complete receipt after terminal consumption',
   'pass',to_jsonb(internal.initial_admission_retained_receipt(owner_id,scan,receipt.admission_receipt_id))=to_jsonb(receipt)));
  recovered:=internal.recover_initial_admitted_media(owner_id,scan);
  results:=results||jsonb_build_array(jsonb_build_object('case','locked recovery returns original retained binding and digest without action authority',
   'pass',recovered->>'authority'='none' AND recovered->>'outcome'='admitted'
    AND recovered->'binding'=receipt.media_binding::JSONB AND recovered->>'admission_receipt_digest'=receipt.receipt_digest));
  failure:=NULL;
  BEGIN PERFORM internal.initial_admitted_recovery_response(receipt,(receipt.media_binding::JSONB#>>'{phase_window,anchor_ms}')::NUMERIC-1);
  EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
  results:=results||jsonb_build_array(jsonb_build_object('case','pre-anchor recovery rejects rather than labelling chronological expiry',
   'pass',failure IS NOT DISTINCT FROM '55000:initial_analysis_admission_incomplete'));
  replay_state:=pg_temp.terminal_state(scan);
  FOREACH command IN ARRAY ARRAY[
   'SELECT public.get_initial_preparation_status($1,$2)',
   'SELECT public.finalize_initial_preparation($1,$2,NULL)',
   'SELECT public.create_initial_preparation_intent($1,$2,$3)'
  ] LOOP
   recovered:=pg_temp.public_recovery('service_role',command,owner_id,scan,receipt.candidate);
   results:=results||jsonb_build_array(jsonb_build_object('case','actual service-role original recovery: '||command,
    'pass',recovered->>'outcome'='admitted' AND recovered->>'authority'='none'
     AND recovered->'binding'=receipt.media_binding::JSONB AND recovered->>'admission_receipt_digest'=receipt.receipt_digest));
   failure:=NULL;
   BEGIN PERFORM pg_temp.public_recovery('service_role',command,'00000000-0000-4000-8000-00000000f002',scan,receipt.candidate);
   EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
   results:=results||jsonb_build_array(jsonb_build_object('case','existing different owner receives no private recovery envelope: '||command,
    'pass',failure IS NOT DISTINCT FROM '55000:initial_analysis_admission_incomplete','failure',failure));
   FOREACH phase_name IN ARRAY ARRAY['missing_receipt','missing_admission'] LOOP
    failure:=pg_temp.recovery_fault(owner_id,scan,phase_name,command);
    results:=results||jsonb_build_array(jsonb_build_object('case','public recovery rejects '||phase_name||CASE WHEN phase_name='missing_admission' THEN ' retained-boundary seam' ELSE '' END||': '||command,
     'pass',failure IS NOT DISTINCT FROM CASE WHEN phase_name='missing_admission' THEN '55000:synthetic_retained_admission_unavailable' ELSE '55000:initial_analysis_admission_incomplete' END,'failure',failure));
   END LOOP;
   FOREACH phase_name IN ARRAY ARRAY['anon','authenticated'] LOOP
    failure:=NULL;
    BEGIN PERFORM pg_temp.public_recovery(phase_name,command,owner_id,scan,receipt.candidate);
    EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE; END;
    results:=results||jsonb_build_array(jsonb_build_object('case',phase_name||' cannot invoke '||command,'pass',failure='42501'));
   END LOOP;
  END LOOP;
  FOREACH changed_candidate IN ARRAY ARRAY[
   internal.initial_canonical(jsonb_set(receipt.candidate::JSONB,'{source_plan,ordered_descriptions,0}',to_jsonb('changed supporting context'::TEXT))),
   internal.initial_canonical(jsonb_set(receipt.candidate::JSONB,'{source_plan,sources,0,source_sha256}',to_jsonb(repeat('f',64)))),
   internal.initial_canonical(jsonb_set(receipt.candidate::JSONB,'{source_plan,ordered_descriptions}',
    jsonb_build_array(receipt.candidate::JSONB#>'{source_plan,ordered_descriptions,1}',receipt.candidate::JSONB#>'{source_plan,ordered_descriptions,0}')))
  ] LOOP
   failure:=NULL;
   BEGIN PERFORM pg_temp.public_recovery('service_role','SELECT public.create_initial_preparation_intent($1,$2,$3)',owner_id,scan,changed_candidate);
   EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
   results:=results||jsonb_build_array(jsonb_build_object('case','changed complete original candidate cannot recover or fund',
    'pass',failure IS NOT DISTINCT FROM '22023:initial_analysis_identity_conflict','failure',failure));
  END LOOP;
  results:=results||pg_temp.admitted_execution_denials(owner_id,scan,receipt.media_binding::JSONB->>'assignment_digest');
  recovered:=pg_temp.public_recovery('service_role','SELECT public.finalize_initial_preparation($1,$2,repeat(''b'',64))',owner_id,scan,NULL);
  results:=results||jsonb_build_array(jsonb_build_object('case','changed retry IP cannot replace original funding/binding',
   'pass',recovered->'binding'=receipt.media_binding::JSONB AND recovered->>'authority'='none'));
  changed_candidate:=internal.initial_canonical(jsonb_build_object('version',2,'variant','no_media','input',
   ((receipt.candidate::JSONB->'source_plan')-'sources')||jsonb_build_object('route','identify-multimodal','media','[]'::JSONB,
    'owner_timeline','[{"kind":"description","index":0},{"kind":"description","index":1}]'::JSONB)));
  -- Validate the alternate codec first so the denial cannot be a malformed-input false positive.
  PERFORM internal.parse_initial_preparation_candidate(changed_candidate);
  failure:=NULL;
  BEGIN PERFORM pg_temp.public_recovery('service_role','SELECT public.create_initial_preparation_intent($1,$2,$3)',owner_id,scan,changed_candidate);
  EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
  results:=results||jsonb_build_array(jsonb_build_object('case','valid changed variant cannot recover a media admission',
   'pass',failure IS NOT DISTINCT FROM '55000:initial_analysis_preparation_required','failure',failure));
  results:=results||jsonb_build_array(jsonb_build_object('case','all public exact/conflicting replays leave funding/source/member state identical',
   'pass',replay_state IS NOT DISTINCT FROM pg_temp.terminal_state(scan)));
  cutoff:=(receipt.media_binding::JSONB#>>'{phase_window,cutoffs,copy}')::NUMERIC;
  FOR clock_value IN SELECT x FROM unnest(ARRAY[
   (receipt.media_binding::JSONB#>>'{phase_window,anchor_ms}')::NUMERIC,cutoff-1,cutoff]) x LOOP
   recovered:=internal.initial_admitted_recovery_response(receipt,clock_value);
   results:=results||jsonb_build_array(jsonb_build_object('case','original copy cutoff boundary '||clock_value::TEXT,
    'pass',recovered->>'phase'=CASE WHEN clock_value>=(receipt.media_binding::JSONB#>>'{phase_window,anchor_ms}')::NUMERIC
     AND clock_value<cutoff THEN 'copy' ELSE 'expired' END AND recovered->>'authority'='none'));
  END LOOP;
  FOREACH phase_name IN ARRAY ARRAY['verification_claim','verification','verification_settlement','transfer','reconciliation','protocol_margin'] LOOP
   recovered:=internal.initial_admitted_recovery_response(receipt,(receipt.media_binding::JSONB#>>ARRAY['phase_window','cutoffs',phase_name])::NUMERIC);
   results:=results||jsonb_build_array(jsonb_build_object('case','elapsed '||phase_name||' never invents progress','pass',recovered->>'phase'='expired'));
  END LOOP;
  FOREACH command IN ARRAY ARRAY['NULL','-1','1.5','9007199254740992','''NaN''::NUMERIC','''Infinity''::NUMERIC'] LOOP
   failure:=NULL;
   BEGIN EXECUTE 'SELECT internal.initial_admitted_recovery_response($1,'||command||')' USING receipt;
   EXCEPTION WHEN OTHERS THEN failure:=SQLSTATE||':'||SQLERRM; END;
   results:=results||jsonb_build_array(jsonb_build_object('case','reject invalid observed clock '||command,
    'pass',failure IS NOT DISTINCT FROM '22023:initial_analysis_input_invalid'));
  END LOOP;
  FOREACH command IN ARRAY ARRAY['missing_receipt','missing_lifecycle','cancelled_pre_dispatch','cancelled_dispatched','cancelled_unknown','unknown_owner','deleted','dispatch_authorized'] LOOP
   failure:=pg_temp.recovery_fault(owner_id,scan,command);
   results:=results||jsonb_build_array(jsonb_build_object('case','locked recovery fault/precedence '||command,'failure',failure,
    'pass',failure IS NOT DISTINCT FROM CASE
     WHEN command LIKE 'cancelled_%' THEN '55000:initial_analysis_cancelled'
     WHEN command='unknown_owner' THEN 'P0002:initial_analysis_owner_unavailable'
     WHEN command='deleted' THEN '55000:initial_analysis_deleted'
     WHEN command='dispatch_authorized' THEN 'ZX003:synthetic recovery acceptance'
     ELSE '55000:initial_analysis_admission_incomplete' END));
  END LOOP;
  RAISE EXCEPTION 'synthetic terminal rollback' USING ERRCODE='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
  WHEN OTHERS THEN
   failure:=SQLSTATE||':'||SQLERRM;
   IF mode='normal' THEN RAISE; END IF;
   results:=results||jsonb_build_array(jsonb_build_object('case','terminal fault '||mode,'failure',failure,
    'pass',failure IS NOT DISTINCT FROM CASE WHEN mode='unrelated' THEN 'P0001:synthetic_unrelated_deferred_failure'
     WHEN mode='cutoff' THEN '55000:initial_analysis_preparation_expired'
     ELSE '55000:initial_analysis_admission_incomplete' END));
 END;
 results:=results||jsonb_build_array(jsonb_build_object('case',mode||' restores source/funding/hold/entitlement/counters/member/cleanup/seal on rollback',
  'pass',before_state IS NOT DISTINCT FROM pg_temp.terminal_state(scan) AND NOT internal.initial_admission_sealed()));
 RETURN results;
END $$;
SELECT extensions.ok(position('admitted_recovery:=internal.recover_initial_admitted_media' IN definition)>
 position('internal.lock_initial_preparation_scope' IN definition)
 AND position('admitted_recovery:=internal.recover_initial_admitted_media' IN definition)<position('SELECT * INTO saved FROM internal.initial_analysis_preparation_intents' IN definition),
 'all old preparation actions intercept admitted scope before intent lookup and expiry')
 FROM (SELECT pg_get_functiondef('internal.initial_preparation_execution_action(text,uuid,uuid,text,text)'::REGPROCEDURE) definition) d;
-- Inspect expanded installed definitions, not only migration replacement anchors.
SELECT extensions.ok(position('internal.recover_initial_admitted_media' IN definition)>
 position('internal.lock_initial_preparation_scope' IN definition)
 AND position('internal.recover_initial_admitted_media' IN definition)<position('internal.recover_initial_preparation_admission' IN definition),
 'expanded public recovery branch follows scope and precedes legacy recovery: '||signature)
 FROM unnest(ARRAY['public.get_initial_preparation_status(uuid,uuid)','public.finalize_initial_preparation(uuid,uuid,text)']) signature
 CROSS JOIN LATERAL (SELECT pg_get_functiondef(signature::REGPROCEDURE) definition) d;
SELECT extensions.ok(has_function_privilege('service_role',signature,'EXECUTE')
 AND NOT has_function_privilege('anon',signature,'EXECUTE') AND NOT has_function_privilege('authenticated',signature,'EXECUTE'),
 'expanded public recovery ACL remains service only: '||signature)
 FROM unnest(ARRAY['public.get_initial_preparation_status(uuid,uuid)','public.finalize_initial_preparation(uuid,uuid,text)',
 'public.create_initial_preparation_intent(uuid,uuid,text)']) signature;
CREATE TEMP TABLE terminal_results AS SELECT mode,e FROM unnest(ARRAY['normal','early_insert_identity','early_update_identity','delete_old_cursor','unrelated','cutoff']) mode
 CROSS JOIN LATERAL jsonb_array_elements(pg_temp.terminal_probe(mode)) e;
SELECT extensions.ok((e->>'pass')::BOOLEAN,e->>'case') FROM terminal_results;
SELECT extensions.diag(e::TEXT) FROM terminal_results WHERE NOT COALESCE((e->>'pass')::BOOLEAN,FALSE);
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'INSERT INTO internal.initial_admitted_cancellation_staging(scan_id,owner_id) VALUES(NULL,NULL)'),
 '42501',role_name||' denied private cancellation entry table') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.sample_initial_cancellation_quota_clock(NULL,NULL,NULL,NULL)'),
 '42501',role_name||' denied private cancellation quota clock') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.ok(position('internal.initial_admitted_settlement_blocked' IN definition)<position('quota_now := internal.sample_initial_cancellation_quota_clock' IN definition)
 AND position('FOR UPDATE;' IN definition)<position('quota_now := internal.sample_initial_cancellation_quota_clock' IN definition),
 'original finalizer lock and admitted defensive fence still precede sampling hook')
 FROM (SELECT pg_get_functiondef('internal.finalize_ai_quota_reservation_core(uuid,uuid,uuid,text)'::REGPROCEDURE) definition) d;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.guard_initial_admitted_cancellation_entry()'),
 '42501',role_name||' denied private cancellation entry trigger') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.require_complete_initial_admitted_cancellation()'),
 '42501',role_name||' denied private cancellation completion trigger') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,sql),
 '42501',role_name||' denied C1 quota protocol: '||label)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 CROSS JOIN (VALUES
 ('begin','SELECT internal.begin_initial_cancellation_quota_statement(NULL,NULL,NULL)'),
 ('end','SELECT internal.end_initial_cancellation_quota_statement(NULL,NULL)'),
 ('ledger','SELECT * FROM internal.initial_cancellation_quota_statements')) cases(label,sql);
SELECT extensions.throws_ok($q$TRUNCATE internal.initial_cancellation_quota_statements$q$,
 '55000','initial_analysis_cancellation_incomplete','C1 quota statement ledger cannot truncate');
SELECT extensions.ok((SELECT relrowsecurity FROM pg_class WHERE oid='internal.initial_cancellation_quota_statements'::REGCLASS),
 'C1 quota statement ledger has RLS and no API grants');
SELECT extensions.ok(position('begin_initial_cancellation_quota_statement' IN definition)>0
 AND position('end_initial_cancellation_quota_statement' IN definition)>0,
 'installed original accounting owner has closed statement hooks: '||signature)
 FROM unnest(ARRAY['internal.release_ai_quota_reservation_counters(uuid)',
 'internal.finalize_ai_quota_reservation_core(uuid,uuid,uuid,text)']) signature
 CROSS JOIN LATERAL (SELECT pg_get_functiondef(signature::REGPROCEDURE) definition) d;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,sql),
 '42501',role_name||' denied C1 credit protocol: '||label)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 CROSS JOIN (VALUES
 ('sample','SELECT internal.sample_initial_cancellation_credit_clock(NULL,NULL,NULL)'),
 ('advance','SELECT internal.advance_initial_cancellation_credit(NULL,NULL,NULL)'),
 ('finish','SELECT internal.finish_initial_cancellation_credit(NULL,NULL,NULL,NULL)'),
 ('witness','SELECT * FROM internal.initial_cancellation_credit_witness')) cases(label,sql);
SELECT extensions.throws_ok($q$TRUNCATE internal.initial_cancellation_credit_witness$q$,
 '55000','initial_analysis_cancellation_incomplete','C1 credit witness cannot truncate');
SELECT extensions.ok((SELECT relrowsecurity FROM pg_class WHERE oid='internal.initial_cancellation_credit_witness'::REGCLASS),
 'C1 credit witness has RLS enabled');
SELECT extensions.ok(position('usage_found:=FOUND;' IN definition)>0
 AND position('usage_found:=FOUND;' IN definition)<position('settled:=internal.sample_initial_cancellation_credit_clock' IN definition)
 AND position('IF usage_found AND usage_row.state=''held''' IN definition)>0
 AND position('ELSIF usage_found AND usage_row.state=''consumed''' IN definition)>0,
 'original credit owner explicitly preserves lookup FOUND for both legacy branches')
 FROM (SELECT pg_get_functiondef('internal.settle_complimentary_analysis(uuid,uuid,text)'::REGPROCEDURE) definition) d;
SELECT extensions.ok((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc
 WHERE oid='internal.guard_initial_cancellation_credit_member()'::REGPROCEDURE)
 AND NOT has_function_privilege('service_role','internal.guard_initial_cancellation_credit_member()','EXECUTE')
 AND NOT has_function_privilege('authenticated','internal.guard_initial_cancellation_credit_member()','EXECUTE')
 AND NOT has_function_privilege('anon','internal.guard_initial_cancellation_credit_member()','EXECUTE'),
 'fixed credit trigger can inspect private stage without granting API access');
SELECT extensions.ok('bump_user_entitlement_version' COLLATE "C" < 'z9_initial_cancellation_credit' COLLATE "C"
 AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.users'::REGCLASS AND tgname='z9_initial_cancellation_credit'),
 'C1 user BEFORE guard sorts after original entitlement-version trigger');
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,sql),
 '42501',role_name||' denied C1 lifecycle protocol: '||label)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 CROSS JOIN (VALUES
 ('advance','SELECT internal.advance_initial_cancellation_lifecycle(NULL,NULL,NULL,NULL)'),
 ('witness','SELECT * FROM internal.initial_cancellation_lifecycle_witness'),
 ('trigger','SELECT internal.guard_initial_cancellation_lifecycle_member()')) cases(label,sql);
SELECT extensions.throws_ok($q$TRUNCATE internal.initial_cancellation_lifecycle_witness$q$,
 '55000','initial_analysis_cancellation_incomplete','C1 lifecycle witness cannot truncate');
SELECT extensions.ok((SELECT relrowsecurity FROM pg_class WHERE oid='internal.initial_cancellation_lifecycle_witness'::REGCLASS),
 'C1 lifecycle witness has RLS enabled');
SELECT extensions.ok(position('internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,terminal,''begin'')' IN definition)
 <position('UPDATE internal.initial_analysis_lifecycle_fences SET state=terminal' IN definition)
 AND position('internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,terminal,''end'')' IN definition)
 >position('UPDATE internal.initial_analysis_lifecycle_fences SET state=terminal' IN definition),
 'existing cancellation UPDATE alone is bracketed by lifecycle event hooks')
 FROM (SELECT pg_get_functiondef('internal.cancel_initial_analysis(uuid,uuid)'::REGPROCEDURE) definition) d;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,sql),
 '42501',role_name||' denied C1 retirement protocol: '||label)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 CROSS JOIN (VALUES
 ('advance','SELECT internal.advance_initial_cancellation_retirement(NULL,NULL,NULL)'),
 ('witness','SELECT * FROM internal.initial_cancellation_retirement_witness'),
 ('trigger','SELECT internal.guard_initial_cancellation_retirement_member()')) cases(label,sql);
SELECT extensions.throws_ok($q$TRUNCATE internal.initial_cancellation_retirement_witness$q$,
 '55000','initial_analysis_cancellation_incomplete','C1 retirement witness cannot truncate');
SELECT extensions.ok((SELECT relrowsecurity FROM pg_class WHERE oid='internal.initial_cancellation_retirement_witness'::REGCLASS),
 'C1 retirement witness has RLS enabled');
SELECT extensions.ok(position('advance_initial_cancellation_retirement' IN definition)>0
 AND position('''begin''' IN definition)<position(' SET state=''retired''' IN definition)
 AND position('''end''' IN definition)>position(' END LOOP;' IN definition),
 'original retirement owner brackets fence and ordered registry events: '||signature)
 FROM unnest(ARRAY['internal.retire_initial_preparation_source_objects(uuid)','internal.retire_initial_media_objects(uuid)']) signature
 CROSS JOIN LATERAL (SELECT pg_get_functiondef(signature::REGPROCEDURE) definition) d;
-- Isolated stored-registry contract, not an allocator/admission qualification.
-- User-trigger suspension is fixture-only; each subtransaction restores all rows/settings.
CREATE FUNCTION pg_temp.retirement_destination_bound(n INTEGER) RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
DECLARE s internal.initial_admitted_cancellation_staging; backend UUID:=gen_random_uuid();
 fence JSONB; rows JSONB; events JSONB; i INTEGER; guards JSONB; g JSONB;
BEGIN
 BEGIN
  s.scan_id:=gen_random_uuid();
  INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES(s.scan_id);
  INSERT INTO internal.initial_analysis_media_backends(generation,provider,direct_endpoint,private_bucket,namespace,credential_profile)
  VALUES(backend,'r2','https://'||repeat('0',32)||'.r2.cloudflarestorage.com','synthetic-bound-only','initial-analysis/v1','synthetic_only');
  SELECT jsonb_agg(jsonb_build_object('table',tgrelid::REGCLASS::TEXT,'name',tgname,'mode',tgenabled)) INTO guards FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN ('internal.initial_analysis_media_registry'::REGCLASS,'internal.initial_analysis_media_allocation_fences'::REGCLASS);
  ALTER TABLE internal.initial_analysis_media_registry DISABLE TRIGGER USER;
  ALTER TABLE internal.initial_analysis_media_allocation_fences DISABLE TRIGGER USER;
  INSERT INTO internal.initial_analysis_media_allocation_fences(scan_id,state) VALUES(s.scan_id,'allocated');
  FOR i IN 1..n LOOP
   INSERT INTO internal.initial_analysis_media_registry(object_id,scan_id,backend_generation)
   VALUES(gen_random_uuid(),s.scan_id,backend);
  END LOOP;
  FOR g IN SELECT value FROM jsonb_array_elements(guards) LOOP
   EXECUTE format('ALTER TABLE %s %s TRIGGER %I',g->>'table',CASE g->>'mode' WHEN 'D' THEN 'DISABLE' WHEN 'A' THEN 'ENABLE ALWAYS' WHEN 'R' THEN 'ENABLE REPLICA' ELSE 'ENABLE' END,g->>'name');
  END LOOP;
  SELECT to_jsonb(f) INTO fence FROM internal.initial_analysis_media_allocation_fences f WHERE scan_id=s.scan_id;
  SELECT jsonb_agg(to_jsonb(r) ORDER BY object_id) INTO rows FROM internal.initial_analysis_media_registry r WHERE scan_id=s.scan_id;
  s.prestate:=jsonb_build_object('media_fence',fence,'destination_registry',rows);
  IF n<=10 THEN
   events:=internal.initial_cancellation_retirement_events(s,'destination');
   IF jsonb_array_length(events)<>n+1 OR events->0->'old' IS DISTINCT FROM fence
    OR (SELECT jsonb_agg(v->'old' ORDER BY ordinal) FROM jsonb_array_elements(events) WITH ORDINALITY e(v,ordinal) WHERE ordinal>1) IS DISTINCT FROM rows THEN
    RAISE EXCEPTION USING ERRCODE='ZX201'; END IF;
   PERFORM internal.assert_initial_cancellation_retirement_images(s.scan_id,'destination',events,FALSE);
   ALTER TABLE internal.initial_analysis_media_registry DISABLE TRIGGER USER;
   ALTER TABLE internal.initial_analysis_media_allocation_fences DISABLE TRIGGER USER;
   UPDATE internal.initial_analysis_media_allocation_fences SET state='retired' WHERE scan_id=s.scan_id;
   UPDATE internal.initial_analysis_media_registry SET retired=TRUE WHERE scan_id=s.scan_id;
   FOR g IN SELECT value FROM jsonb_array_elements(guards) LOOP
   EXECUTE format('ALTER TABLE %s %s TRIGGER %I',g->>'table',CASE g->>'mode' WHEN 'D' THEN 'DISABLE' WHEN 'A' THEN 'ENABLE ALWAYS' WHEN 'R' THEN 'ENABLE REPLICA' ELSE 'ENABLE' END,g->>'name');
  END LOOP;
   PERFORM internal.assert_initial_cancellation_retirement_images(s.scan_id,'destination',events,TRUE);
  ELSE
   BEGIN
    PERFORM internal.initial_cancellation_retirement_events(s,'destination');
    RAISE EXCEPTION USING ERRCODE='ZX202';
   EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
   -- Construct all 11 exact images independently so only live membership fails.
   events:=jsonb_build_array(jsonb_build_object('old',fence,'new',fence||jsonb_build_object('state','retired')))
    ||(SELECT jsonb_agg(jsonb_build_object('old',v,'new',v||jsonb_build_object('retired',TRUE)) ORDER BY ordinal) FROM jsonb_array_elements(rows) WITH ORDINALITY e(v,ordinal));
   BEGIN
    PERFORM internal.assert_initial_cancellation_retirement_images(s.scan_id,'destination',events,FALSE);
    RAISE EXCEPTION USING ERRCODE='ZX203';
   EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
  END IF;
  RAISE EXCEPTION USING ERRCODE='ZX204';
 EXCEPTION WHEN SQLSTATE 'ZX204' THEN NULL; END;
 RETURN TRUE;
END; $$;
SELECT extensions.ok(pg_temp.retirement_destination_bound(n),
 'isolated destination stored-registry bound '||n||': ordered events and exact live images; 11 denied') FROM generate_series(9,11) n;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,sql),
 '42501',role_name||' denied C1 private image protocol: '||label)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 CROSS JOIN (VALUES
 ('catalog','SELECT * FROM internal.initial_cancellation_private_catalog()'),
 ('capture','SELECT internal.capture_initial_cancellation_private_images(NULL)'),
 ('trigger','SELECT internal.guard_initial_cancellation_private_member()')) cases(label,sql);
WITH RECURSIVE owned(oid) AS (
 SELECT unnest(ARRAY['internal.initial_analysis_submissions'::REGCLASS,'internal.initial_analysis_preparation_intents'::REGCLASS])::OID
 UNION
 SELECT c.conrelid FROM pg_constraint c JOIN owned p ON p.oid=c.confrelid WHERE c.contype='f' AND c.confdeltype='c'
)
SELECT extensions.is((SELECT array_agg(oid::REGCLASS::TEXT ORDER BY oid::REGCLASS::TEXT) FROM owned),
 (SELECT array_agg(relation_name ORDER BY relation_name) FROM internal.initial_cancellation_private_catalog()),
 'C1 private catalog exactly covers installed cascade closures of both roots');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.initial_cancellation_private_catalog()),15,
 'C1 private catalog includes explicit empty downstream relations and excludes shared assets');
SELECT extensions.ok(position('initial_preparation_source_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE' IN definition)
 <position('''erasure_images'',internal.capture_initial_cancellation_private_images(p_scan)' IN definition),
 'C1 captures source mapping under original lock scope before private-image aggregation')
 FROM (SELECT pg_get_functiondef('internal.capture_initial_admitted_cancellation_prestate(uuid,uuid)'::REGPROCEDURE) definition) d;
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM pg_constraint c
 WHERE c.contype='f' AND c.confrelid IN
 (SELECT relation_name::REGCLASS FROM internal.initial_cancellation_private_catalog()) AND c.confdeltype<>'c'),
 'private erasure closure has no incoming noncascade FK action');
-- Prepared erasure owners remain inaccessible to every API role.
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'private erasure helper denied: '||role_name||' / '||signature)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
CROSS JOIN unnest(ARRAY[
 'internal.erase_initial_cancellation_private_root(uuid,text)',
 'internal.guard_initial_cancellation_erasure_witness()',
 'internal.assert_initial_cancellation_erasure_boundary(internal.initial_admitted_cancellation_staging)',
 'internal.capture_initial_cancellation_accounting_images(internal.initial_admitted_cancellation_staging)',
 'internal.assert_initial_cancellation_private_progress(internal.initial_admitted_cancellation_staging,text[])',
 'internal.guard_initial_cancellation_erased_attempt()'
]) signature;
SELECT extensions.ok(NOT has_table_privilege(role_name,'internal.initial_cancellation_erasure_witness',privilege_name),
 'private erasure witness denied: '||role_name||' / '||privilege_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) privilege_name;
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'private cancellation receipt helper denied: '||role_name||' / '||signature)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
CROSS JOIN unnest(ARRAY[
 'internal.assert_initial_cancellation_erasure_boundary(internal.initial_admitted_cancellation_staging,jsonb)',
 'internal.initial_cancellation_receipt_image(internal.initial_admitted_cancellation_staging)',
 'internal.assert_initial_cancellation_receipt_boundary(internal.initial_admitted_cancellation_staging,boolean)',
 'internal.guard_initial_cancellation_receipt_witness()',
 'internal.guard_initial_cancellation_receipt_member()',
 'internal.write_initial_cancellation_receipt(uuid)'
]) signature;
SELECT extensions.ok(NOT has_table_privilege(role_name,'internal.initial_cancellation_receipt_witness',privilege_name),
 'private cancellation receipt witness denied: '||role_name||' / '||privilege_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) privilege_name;
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'private terminal snapshot helper denied: '||role_name||' / '||signature)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
CROSS JOIN unnest(ARRAY[
 'internal.initial_cancellation_terminal_catalog()',
 'internal.assert_initial_cancellation_terminal_predecessors(uuid)',
 'internal.capture_initial_cancellation_terminal_snapshot(uuid)',
 'internal.guard_initial_cancellation_terminal_snapshot()',
 'internal.assert_initial_cancellation_terminal_snapshot(uuid)'
]) signature;
SELECT extensions.ok(NOT has_table_privilege(role_name,'internal.initial_cancellation_terminal_snapshot',privilege_name),
 'private terminal snapshot table denied: '||role_name||' / '||privilege_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) privilege_name;
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'), 'private C1 consumption helper denied: '||role_name||' / '||signature)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY[
 'internal.check_initial_cancellation_cleanup_statement()',
 'internal.initial_cancellation_cleanup_catalog()',
 'internal.initial_cancellation_cleanup_count(jsonb)',
 'internal.initial_cancellation_cleanup_entry(jsonb,integer)',
 'internal.assert_initial_cancellation_cleanup_suffix(uuid,jsonb,integer)',
 'internal.assert_initial_cancellation_terminal_survivors(jsonb)',
 'internal.initial_cancellation_sealed()',
 'internal.check_initial_cancellation_cleanup_member(text,jsonb,boolean)',
 'internal.advance_initial_cancellation_cleanup()',
 'internal.assert_initial_cancellation_transients_absent(uuid)',
 'internal.require_complete_initial_cancellation_snapshot()',
 'internal.guard_initial_cancellation_seal()',
 'internal.finish_initial_cancellation_consumption(uuid)',
 'internal.initial_cancellation_seal_catalog()']) signature;
SELECT extensions.is((SELECT array_agg(relation_name ORDER BY relation_name) FROM internal.initial_cancellation_seal_catalog()), ARRAY[
 'internal.account_deletion_jobs',
 'internal.ai_quota_counters',
 'internal.ai_quota_reservation_counters',
 'internal.ai_quota_reservations',
 'internal.complimentary_scan_usage',
 'internal.identification_invocations',
 'internal.identification_provider_attempts',
 'internal.initial_admitted_cancellation_staging',
 'internal.initial_analysis_admissions',
 'internal.initial_analysis_cancellations',
 'internal.initial_analysis_completions',
 'internal.initial_analysis_lifecycle_fences',
 'internal.initial_analysis_media_allocation_fences',
 'internal.initial_analysis_media_cohorts',
 'internal.initial_analysis_media_preparations',
 'internal.initial_analysis_media_registry',
 'internal.initial_analysis_media_verifications',
 'internal.initial_analysis_operation_fences',
 'internal.initial_analysis_preparation_intents',
 'internal.initial_analysis_results',
 'internal.initial_analysis_submissions',
 'internal.initial_cancellation_credit_witness',
 'internal.initial_cancellation_erasure_witness',
 'internal.initial_cancellation_lifecycle_witness',
 'internal.initial_cancellation_quota_statements',
 'internal.initial_cancellation_receipt_witness',
 'internal.initial_cancellation_retirement_witness',
 'internal.initial_cancellation_terminal_snapshot',
 'internal.initial_preparation_admission_receipts',
 'internal.initial_preparation_admission_staging',
 'internal.initial_preparation_admission_writes',
 'internal.initial_preparation_execution_grants',
 'internal.initial_preparation_outcomes',
 'internal.initial_preparation_output_manifests',
 'internal.initial_preparation_output_mapping',
 'internal.initial_preparation_source_fences',
 'internal.initial_preparation_source_mapping',
 'internal.initial_preparation_source_registry',
 'internal.initial_preparation_source_verifications',
 'internal.observation_analysis_intents',
 'internal.observation_analysis_results',
 'internal.observation_analysis_source_bindings',
 'internal.observation_histories',
 'internal.scan_deletion_tombstones',
 'public.scan_ingestion_intents',
 'public.scan_ingestion_jobs',
 'public.scans',
 'public.users']::TEXT[], 'C1 version1 exact seal catalog');
SELECT extensions.ok(EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=relation_name::REGCLASS AND tgname='a00_initial_cancellation_seal' AND NOT tgisinternal AND tgenabled='O' AND tgtype=62), 'C1 seal covers four statement operations: '||relation_name) FROM internal.initial_cancellation_seal_catalog();
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_cancellation_private_catalog() p WHERE NOT EXISTS(SELECT 1 FROM internal.initial_cancellation_seal_catalog() s WHERE s.relation_name=p.relation_name)), 'all private cascade catalog relations have statement seal coverage');
SELECT extensions.throws_ok($q$TRUNCATE internal.initial_admitted_cancellation_staging$q$,
 '55000','initial_analysis_cancellation_incomplete','private cancellation stage cannot truncate even when empty');
SELECT extensions.throws_ok($q$INSERT INTO internal.initial_admitted_cancellation_staging(scan_id,owner_id)
 VALUES(NULL,NULL)$q$,'55000','initial_analysis_cancellation_incomplete','private cancellation stage rejects missing identity');
SELECT extensions.throws_ok($q$INSERT INTO internal.initial_admitted_cancellation_staging(scan_id,owner_id,prestate)
 VALUES('00000000-0000-4000-8000-000000005511','00000000-0000-4000-8000-00000000f001','{}')$q$,
 '55000','initial_analysis_cancellation_incomplete','private cancellation stage rejects caller snapshot before capture');
SELECT extensions.throws_ok($q$INSERT INTO internal.initial_admitted_cancellation_staging(scan_id,owner_id,transaction_id)
 VALUES('00000000-0000-4000-8000-000000005511','00000000-0000-4000-8000-00000000f001',pg_current_xact_id())$q$,
 '55000','initial_analysis_cancellation_incomplete','private cancellation stage rejects caller current xid before capture');
SELECT extensions.ok((SELECT relrowsecurity FROM pg_class WHERE oid='internal.initial_admitted_cancellation_staging'::REGCLASS),
 'private cancellation staging has RLS enabled and no external grants');
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.assert_initial_admitted_cancellation_settlement(NULL,NULL,NULL)'),
 '42501',role_name||' denied private cancellation settlement comparison') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.capture_initial_admitted_cancellation_prestate(NULL,NULL)'),
 '42501',role_name||' denied private cancellation prestate capture') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.finish_initial_admission(NULL)'),
 '42501',role_name||' denied private terminal completion') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.recover_initial_admitted_media(NULL,NULL)'),
 '42501',role_name||' denied private locked recovery') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.is(pg_temp.private_admission_role_denial(role_name,'SELECT internal.initial_admitted_recovery_response(NULL,0)'),
 '42501',role_name||' denied private response constructor') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
ALTER TABLE internal.initial_preparation_admission_staging DISABLE TRIGGER require_complete_initial_admission;

ALTER TABLE internal.ai_quota_reservations ENABLE TRIGGER a0_initial_preparation_provider_barrier;
ALTER TABLE internal.complimentary_scan_usage ENABLE TRIGGER a0_initial_preparation_provider_barrier;
SELECT set_config('merian.test_funding_tripwire','on',TRUE);

CREATE FUNCTION pg_temp.no_allocation_write() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN RAISE EXCEPTION 'unexpected_allocation_write'; END; $$;
CREATE TRIGGER test_no_allocation BEFORE INSERT ON internal.initial_analysis_operation_fences FOR EACH ROW EXECUTE FUNCTION pg_temp.no_allocation_write();
CREATE TRIGGER test_no_allocation BEFORE INSERT ON internal.initial_preparation_source_fences FOR EACH ROW EXECUTE FUNCTION pg_temp.no_allocation_write();
CREATE TRIGGER test_no_allocation BEFORE INSERT ON internal.initial_analysis_preparation_intents FOR EACH ROW EXECUTE FUNCTION pg_temp.no_allocation_write();
CREATE TRIGGER test_no_allocation BEFORE INSERT ON internal.initial_preparation_source_registry FOR EACH ROW EXECUTE FUNCTION pg_temp.no_allocation_write();
UPDATE internal.ai_quota_policies SET user_rate_bucket=repeat('a',1025) WHERE operation='scan_identification' AND allowed AND enabled;
SELECT extensions.throws_ok($q$SELECT pg_temp.media_create('00000000-0000-4000-8000-000000005511',1)$q$,'55000','initial_analysis_assignment_changed','invalid current policy rejected before allocation tripwires');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_operation_fences WHERE scan_id='00000000-0000-4000-8000-000000005511'),0::BIGINT,'no permanent operation fence');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_source_fences WHERE scan_id='00000000-0000-4000-8000-000000005511'),0::BIGINT,'no source fence');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-000000005511'),0::BIGINT,'no intent');
SELECT extensions.is((SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id='00000000-0000-4000-8000-000000005511'),0::BIGINT,'no source registry');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-000000005511' OR original_analysis_id='00000000-0000-4000-8000-000000005511'),0::BIGINT,'no quota reservation');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-000000005511'),0::BIGINT,'no complimentary hold');
SELECT extensions.ok(p.prosecdef AND p.proowner='postgres'::REGROLE AND p.proconfig=ARRAY['search_path=""']::TEXT[],
 'deferred C1 validator uses trusted fixed-path owner: '||p.proname)
 FROM pg_proc p WHERE p.oid IN ('internal.require_complete_initial_admitted_cancellation()'::REGPROCEDURE,
 'internal.require_complete_initial_cancellation_snapshot()'::REGPROCEDURE);
SELECT * FROM extensions.finish();
ROLLBACK;
