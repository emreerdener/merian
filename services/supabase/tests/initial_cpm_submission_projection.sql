-- Pure projection parity; no verified bytes, admission, funding or activation.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE TEMP TABLE projection_fixture AS SELECT $projection_vector${"assignment_canonical":"{\"candidate_digest\":\"d6386c57a8e3d67c5cb8566fc46dfa59378613ccd0494c85669905df25b2d57a\",\"configuration\":{\"accepted_client_protocol\":3,\"accepted_identification_protocol\":6,\"asset_manifest_digest\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"binding\":\"synthetic_cpm_binding_v1\",\"effective_model\":\"synthetic-cpm-model\",\"effective_plan\":\"pro_complimentary\",\"effective_tier\":\"pro\",\"flash_fallback_used\":false,\"input_profile\":\"vision_compat_v1\",\"minimum_client_protocol\":0,\"minimum_identification_protocol\":0,\"operation\":\"scan_identification\",\"output_language\":\"en\",\"policy_version\":1,\"processor_permission\":\"google_gemini\",\"provider\":\"gemini\",\"provider_model\":null,\"quota_model\":\"synthetic-cpm-model\",\"resolver_id\":\"git_blob_sha256_v1\",\"retention_owner\":\"initial_engine_release_archive\",\"route\":\"identify\"},\"content_digest\":\"d75caa6fdc3c9f374149c666cb2bb3b153934bc6dc4040589fa418ee7e41c806\",\"created_at_ms\":1793140000000,\"expires_at_ms\":1793141800000,\"package_id\":\"00000000-0000-4000-8000-000000000002\",\"preparation\":{\"backend_generation\":\"00000000-0000-4000-8000-000000000101\",\"backend_installation_digest\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"composition_policy\":\"cpm_photo_contexts_v1\",\"installation_digest\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"profile_digest\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"resource_profile\":\"P1-L1\",\"role_mapping\":[{\"declaration\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000003\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"object_id\":\"00000000-0000-4000-8000-000000000200\",\"photo_ordinal\":0,\"role\":\"source\"},{\"declaration\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000004\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"object_id\":\"00000000-0000-4000-8000-000000000201\",\"photo_ordinal\":0,\"role\":\"ai\"},{\"declaration\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000005\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"object_id\":\"00000000-0000-4000-8000-000000000202\",\"photo_ordinal\":0,\"role\":\"display\"}],\"selector_generation\":\"00000000-0000-4000-8000-000000000100\",\"verifier_build_digest\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"},\"scan_id\":\"00000000-0000-4000-8000-000000000001\",\"variant\":\"client_prepared_photo\",\"version\":1}","candidate_canonical":"{\"admission\":{\"client_protocol\":3,\"expected_processor_permission\":\"google_gemini\",\"identification_protocol\":6},\"content_canonical\":\"{\\\"contexts\\\":[{\\\"text_utf8_base64\\\":\\\"IO+7v2EAZcyB8J+mrQo=\\\"}],\\\"contract\\\":\\\"client_prepared_media_v1\\\",\\\"kind\\\":\\\"initial_photo\\\",\\\"package_id\\\":\\\"00000000-0000-4000-8000-000000000002\\\",\\\"photos\\\":[{\\\"ai\\\":{\\\"byte_count\\\":1,\\\"declared_content_type\\\":\\\"image/jpeg\\\",\\\"reference_id\\\":\\\"00000000-0000-4000-8000-000000000004\\\",\\\"sha256\\\":\\\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\"},\\\"display\\\":{\\\"byte_count\\\":1,\\\"declared_content_type\\\":\\\"image/jpeg\\\",\\\"reference_id\\\":\\\"00000000-0000-4000-8000-000000000005\\\",\\\"sha256\\\":\\\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\"},\\\"ordinal\\\":0,\\\"recipe\\\":{\\\"camera_vertical_center_bits\\\":null,\\\"crop_display_size_bits\\\":null,\\\"format\\\":\\\"nativeStillImageV1\\\",\\\"is_pro\\\":false,\\\"offset_x_bits\\\":\\\"8000000000000000\\\",\\\"offset_y_bits\\\":\\\"0000000000000000\\\",\\\"quarter_turns\\\":0,\\\"scale_bits\\\":\\\"3ff0000000000000\\\"},\\\"source\\\":{\\\"byte_count\\\":1,\\\"declared_content_type\\\":\\\"image/jpeg\\\",\\\"reference_id\\\":\\\"00000000-0000-4000-8000-000000000003\\\",\\\"sha256\\\":\\\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\"}}],\\\"resource_profile\\\":\\\"P1-L1\\\",\\\"scan_id\\\":\\\"00000000-0000-4000-8000-000000000001\\\",\\\"version\\\":1}\",\"variant\":\"client_prepared_photo\",\"version\":1}","projection":{"binding_version":4,"descriptions_canonical":"[{\"text_utf8_base64\":\"IO+7v2EAZcyB8J+mrQo=\"}]","descriptions_digest":"ed71b6ef5c0e7c95abe5c4e2839632f61d0f847276a8406d4cd6ee09f9a01695","input_schema_version":2,"submission_canonical":"{\"contexts\":[{\"text_utf8_base64\":\"IO+7v2EAZcyB8J+mrQo=\"}],\"contract\":\"client_prepared_media_v1\",\"kind\":\"initial_photo\",\"package_id\":\"00000000-0000-4000-8000-000000000002\",\"photos\":[{\"ai\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000004\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"display\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000005\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"ordinal\":0,\"recipe\":{\"camera_vertical_center_bits\":null,\"crop_display_size_bits\":null,\"format\":\"nativeStillImageV1\",\"is_pro\":false,\"offset_x_bits\":\"8000000000000000\",\"offset_y_bits\":\"0000000000000000\",\"quarter_turns\":0,\"scale_bits\":\"3ff0000000000000\"},\"source\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000003\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}}],\"resource_profile\":\"P1-L1\",\"scan_id\":\"00000000-0000-4000-8000-000000000001\",\"version\":1}","submission_digest":"d75caa6fdc3c9f374149c666cb2bb3b153934bc6dc4040589fa418ee7e41c806"},"synthetic_only":true}$projection_vector$::JSONB v;
SELECT extensions.is(internal.initial_cpm_admission_submission(v->>'candidate_canonical',v->>'assignment_canonical'),
 v->'projection','SQL projection equals independent frozen Deno/Python vector') FROM projection_fixture;
CREATE FUNCTION pg_temp.project_contexts(p_contexts JSONB) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE c JSONB; a JSONB; content TEXT; candidate TEXT;
BEGIN
 SELECT (v->>'candidate_canonical')::JSONB,(v->>'assignment_canonical')::JSONB INTO c,a FROM projection_fixture;
 content:=internal.initial_canonical(jsonb_set((c->>'content_canonical')::JSONB,'{contexts}',p_contexts));
 candidate:=internal.initial_canonical(jsonb_set(c,'{content_canonical}',to_jsonb(content)));
 a:=a||jsonb_build_object('candidate_digest',internal.initial_cpm_photo_digest('candidate',candidate),
  'content_digest',internal.initial_cpm_photo_digest('content',content));
 RETURN internal.initial_cpm_admission_submission(candidate,internal.initial_canonical(a));
END; $$;
CREATE TEMP TABLE context_cases(label TEXT,contexts JSONB);
INSERT INTO context_cases VALUES
 ('none','[]'),('empty','[{"text_utf8_base64":""}]'),
 ('nul','[{"text_utf8_base64":"YQBi"}]'),('plain','[{"text_utf8_base64":"YWI="}]'),
 ('bom','[{"text_utf8_base64":"77u/YQ=="}]'),('no bom','[{"text_utf8_base64":"YQ=="}]'),
 ('composed','[{"text_utf8_base64":"w6k="}]'),('decomposed','[{"text_utf8_base64":"ZcyB"}]'),
 ('order ab','[{"text_utf8_base64":"YQ=="},{"text_utf8_base64":"Yg=="}]'),
 ('order ba','[{"text_utf8_base64":"Yg=="},{"text_utf8_base64":"YQ=="}]');
SELECT extensions.is(pg_temp.project_contexts(contexts)->>'descriptions_canonical',
 internal.initial_canonical(contexts),'encoded text/order preserved: '||label) FROM context_cases;
SELECT extensions.is(count(DISTINCT pg_temp.project_contexts(contexts)->>'descriptions_digest'),10::BIGINT,
 'empty, NUL, BOM, normalization and order remain distinct') FROM context_cases;
SELECT extensions.ok(octet_length(pg_temp.project_contexts((SELECT jsonb_agg(jsonb_build_object(
 'text_utf8_base64',replace(encode(convert_to(repeat(chr(129419),4000),'UTF8'),'base64'),E'\n','')))
 FROM generate_series(1,4)))->>'descriptions_canonical')>65536,'accepted 32000 UTF16-unit context is not truncated to verifier-evidence cap');
SELECT extensions.throws_ok(format('SELECT internal.initial_cpm_admission_submission(%L,%L)',
 v->>'candidate_canonical',internal.initial_canonical((v->>'assignment_canonical')::JSONB||jsonb_build_object('content_digest',repeat('0',64)))),
 '22023','initial_analysis_input_invalid','mismatched saved assignment rejects') FROM projection_fixture;
SELECT extensions.ok(NOT has_function_privilege(role_name,'internal.initial_cpm_admission_submission(text,text)','EXECUTE'),
 role_name||' cannot call the private projection') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.ok(NOT initial_analysis_lifecycle_enabled,'projection installs no activation') FROM internal.initial_analysis_rollout;
-- Evaluate the actual attached variant CHECK, not obsolete column nullability.
-- These are prospective shape images only, not inserted valid admission proofs.
CREATE TEMP TABLE legacy_shapes AS
SELECT table_name, constraint_name, fields,
 jsonb_build_object('admission_variant','server_prepared_v3') ||
 (SELECT jsonb_object_agg(field,'legacy'::TEXT) FROM unnest(fields) field) image
FROM (VALUES
 ('initial_preparation_admission_staging','initial_admission_stage_variant_shape',
  ARRAY['outcome','installation','protocol','destination','phase_window','mapping','media_binding']),
 ('initial_preparation_admission_receipts','initial_admission_receipt_variant_shape',
  ARRAY['outcome','installation','protocol','destination','mapping','media_binding'])
) t(table_name,constraint_name,fields);
SELECT extensions.is((SELECT count(*) FROM pg_constraint c
 WHERE c.conrelid=format('internal.%I',table_name)::REGCLASS
 AND c.conname=constraint_name AND c.contype='c' AND c.convalidated),1::BIGINT,
 'validated variant constraint is attached: '||table_name) FROM legacy_shapes;
CREATE FUNCTION pg_temp.attached_variant_shape(p_table TEXT,p_image JSONB)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE expression TEXT; accepted BOOLEAN;
BEGIN
 SELECT pg_get_expr(c.conbin,c.conrelid) INTO STRICT expression
 FROM legacy_shapes s JOIN pg_constraint c
 ON c.conrelid=format('internal.%I',s.table_name)::REGCLASS
 AND c.conname=s.constraint_name AND c.contype='c' AND c.convalidated
 WHERE s.table_name=p_table;
 EXECUTE format('SELECT %s FROM jsonb_populate_record(NULL::internal.%I,$1)',expression,p_table)
 INTO accepted USING p_image;
 RETURN accepted;
END; $$;
SELECT extensions.is(pg_temp.attached_variant_shape(table_name,image),TRUE,
 'complete legacy shape remains accepted: '||table_name) FROM legacy_shapes;
SELECT extensions.is(pg_temp.attached_variant_shape(table_name,image-field),FALSE,
 'attached variant constraint requires legacy field: '||table_name||'.'||field)
FROM legacy_shapes CROSS JOIN LATERAL unnest(fields) field;
SELECT extensions.is(pg_temp.attached_variant_shape(table_name,image||
 jsonb_build_object('cpm_verification','{}')),FALSE,
 'attached variant constraint rejects mixed proof: '||table_name) FROM legacy_shapes;
SELECT extensions.is(pg_temp.attached_variant_shape(table_name,image-'admission_variant'),FALSE,
 'attached variant constraint rejects missing discriminator: '||table_name) FROM legacy_shapes;
SELECT * FROM extensions.finish();
ROLLBACK;
