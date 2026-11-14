\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- Candidate vector copied from the independent Python canonical/digest fixture.
-- Static cross-language checks compare these exact JSON values.
CREATE TEMP TABLE cpm_candidate_vector AS SELECT $candidate_vector${"candidate":{"version":1,"variant":"client_prepared_photo","content_canonical":"{\"contexts\":[{\"text_utf8_base64\":\"IO+7v2EAZcyB8J+mrQo=\"}],\"contract\":\"client_prepared_media_v1\",\"kind\":\"initial_photo\",\"package_id\":\"00000000-0000-4000-8000-000000000002\",\"photos\":[{\"ai\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000004\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"display\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000005\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"ordinal\":0,\"recipe\":{\"camera_vertical_center_bits\":null,\"crop_display_size_bits\":null,\"format\":\"nativeStillImageV1\",\"is_pro\":false,\"offset_x_bits\":\"8000000000000000\",\"offset_y_bits\":\"0000000000000000\",\"quarter_turns\":0,\"scale_bits\":\"3ff0000000000000\"},\"source\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000003\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}}],\"resource_profile\":\"P1-L1\",\"scan_id\":\"00000000-0000-4000-8000-000000000001\",\"version\":1}","admission":{"client_protocol":3,"identification_protocol":6,"expected_processor_permission":"google_gemini"}},"canonical":"{\"admission\":{\"client_protocol\":3,\"expected_processor_permission\":\"google_gemini\",\"identification_protocol\":6},\"content_canonical\":\"{\\\"contexts\\\":[{\\\"text_utf8_base64\\\":\\\"IO+7v2EAZcyB8J+mrQo=\\\"}],\\\"contract\\\":\\\"client_prepared_media_v1\\\",\\\"kind\\\":\\\"initial_photo\\\",\\\"package_id\\\":\\\"00000000-0000-4000-8000-000000000002\\\",\\\"photos\\\":[{\\\"ai\\\":{\\\"byte_count\\\":1,\\\"declared_content_type\\\":\\\"image/jpeg\\\",\\\"reference_id\\\":\\\"00000000-0000-4000-8000-000000000004\\\",\\\"sha256\\\":\\\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\"},\\\"display\\\":{\\\"byte_count\\\":1,\\\"declared_content_type\\\":\\\"image/jpeg\\\",\\\"reference_id\\\":\\\"00000000-0000-4000-8000-000000000005\\\",\\\"sha256\\\":\\\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\"},\\\"ordinal\\\":0,\\\"recipe\\\":{\\\"camera_vertical_center_bits\\\":null,\\\"crop_display_size_bits\\\":null,\\\"format\\\":\\\"nativeStillImageV1\\\",\\\"is_pro\\\":false,\\\"offset_x_bits\\\":\\\"8000000000000000\\\",\\\"offset_y_bits\\\":\\\"0000000000000000\\\",\\\"quarter_turns\\\":0,\\\"scale_bits\\\":\\\"3ff0000000000000\\\"},\\\"source\\\":{\\\"byte_count\\\":1,\\\"declared_content_type\\\":\\\"image/jpeg\\\",\\\"reference_id\\\":\\\"00000000-0000-4000-8000-000000000003\\\",\\\"sha256\\\":\\\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\"}}],\\\"resource_profile\\\":\\\"P1-L1\\\",\\\"scan_id\\\":\\\"00000000-0000-4000-8000-000000000001\\\",\\\"version\\\":1}\",\"variant\":\"client_prepared_photo\",\"version\":1}","digest":"d6386c57a8e3d67c5cb8566fc46dfa59378613ccd0494c85669905df25b2d57a"}$candidate_vector$::JSONB AS value;
CREATE TEMP TABLE cpm_content_vector AS SELECT $content_vector${"content":{"contract":"client_prepared_media_v1","version":1,"kind":"initial_photo","resource_profile":"P1-L1","scan_id":"00000000-0000-4000-8000-000000000001","package_id":"00000000-0000-4000-8000-000000000002","photos":[{"ordinal":0,"source":{"reference_id":"00000000-0000-4000-8000-000000000003","byte_count":1,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","declared_content_type":"image/jpeg"},"ai":{"reference_id":"00000000-0000-4000-8000-000000000004","byte_count":1,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","declared_content_type":"image/jpeg"},"display":{"reference_id":"00000000-0000-4000-8000-000000000005","byte_count":1,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","declared_content_type":"image/jpeg"},"recipe":{"format":"nativeStillImageV1","is_pro":false,"crop_display_size_bits":null,"quarter_turns":0,"scale_bits":"3ff0000000000000","offset_x_bits":"8000000000000000","offset_y_bits":"0000000000000000","camera_vertical_center_bits":null}}],"contexts":[{"text_utf8_base64":"IO+7v2EAZcyB8J+mrQo="}]},"canonical":"{\"contexts\":[{\"text_utf8_base64\":\"IO+7v2EAZcyB8J+mrQo=\"}],\"contract\":\"client_prepared_media_v1\",\"kind\":\"initial_photo\",\"package_id\":\"00000000-0000-4000-8000-000000000002\",\"photos\":[{\"ai\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000004\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"display\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000005\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"ordinal\":0,\"recipe\":{\"camera_vertical_center_bits\":null,\"crop_display_size_bits\":null,\"format\":\"nativeStillImageV1\",\"is_pro\":false,\"offset_x_bits\":\"8000000000000000\",\"offset_y_bits\":\"0000000000000000\",\"quarter_turns\":0,\"scale_bits\":\"3ff0000000000000\"},\"source\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000003\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}}],\"resource_profile\":\"P1-L1\",\"scan_id\":\"00000000-0000-4000-8000-000000000001\",\"version\":1}","digest":"d75caa6fdc3c9f374149c666cb2bb3b153934bc6dc4040589fa418ee7e41c806"}$content_vector$::JSONB AS value;
SELECT extensions.is(internal.parse_initial_cpm_photo_candidate(value->>'canonical'), value->'candidate', 'candidate matches independent canonical fixture') FROM cpm_candidate_vector;
SELECT extensions.is(internal.initial_cpm_photo_digest('candidate',value->>'canonical'),value->>'digest','candidate digest matches Deno/Python') FROM cpm_candidate_vector;
SELECT extensions.is(internal.parse_initial_cpm_photo_content(value->>'canonical'),value->'content','content matches independent canonical fixture') FROM cpm_content_vector;
SELECT extensions.is(internal.initial_cpm_photo_digest('content',value->>'canonical'),value->>'digest','content digest matches Deno/Swift/Python') FROM cpm_content_vector;
SELECT extensions.ok(NOT initial_analysis_lifecycle_enabled,'codec does not activate lifecycle') FROM internal.initial_analysis_rollout;
SELECT extensions.ok(NOT pg_catalog.has_function_privilege(role,signature,'EXECUTE'),'private codec ungranted: '||role||' '||signature)
FROM unnest(ARRAY['anon','authenticated','service_role']) role CROSS JOIN unnest(ARRAY[
 'internal.initial_cpm_photo_content_schema_v1()', 'internal.initial_cpm_photo_candidate_schema_v1()',
 'internal.initial_cpm_photo_text_units(text)', 'internal.assert_initial_cpm_photo_recipe(jsonb)',
 'internal.parse_initial_cpm_photo_content(text)', 'internal.parse_initial_cpm_photo_candidate(text)',
 'internal.initial_cpm_photo_digest(text,text)', 'internal.initial_cpm_photo_assignment_schema_v1()',
 'internal.initial_cpm_photo_recovery_schema_v1()', 'internal.parse_initial_cpm_photo_assignment(text,text)',
 'internal.parse_initial_cpm_photo_recovery(text,text,text)']) signature;

SELECT extensions.is(internal.initial_cpm_photo_text_units(encoded),units,label)
FROM (VALUES ('',0,'empty context'),('AA==',1,'NUL retained'),('77u/',1,'BOM retained'),('8J+mrQ==',2,'non-BMP UTF16 units')) v(encoded,units,label);
SELECT extensions.is(internal.initial_cpm_photo_text_units(replace(encode(convert_to(repeat('a',8192),'UTF8'),'base64'),E'\n','')),8192,'8192 scalar boundary');
SELECT extensions.is(internal.initial_cpm_photo_text_units(replace(encode(convert_to(repeat(chr(65536),8192),'UTF8'),'base64'),E'\n','')),16384,'16384 UTF16 boundary');
SELECT extensions.throws_ok(format('SELECT internal.initial_cpm_photo_text_units(%L)',encoded),'22023','initial_analysis_input_invalid','invalid UTF8/base64/scalar bound')
FROM (
 SELECT replace(encode(decode(bytes,'hex'),'base64'),E'\n','') AS encoded FROM unnest(ARRAY['80','c080','e08080','eda080','f0808080','f4908080','f5808080','e282','f09f80','f09f4141']) bytes
 UNION ALL SELECT unnest(ARRAY['AB==','YQ',E'YQ==\n',' ',NULL])
 UNION ALL SELECT replace(encode(convert_to(repeat('a',8193),'UTF8'),'base64'),E'\n','')
) v;

SELECT extensions.throws_ok(format('SELECT internal.parse_initial_cpm_photo_candidate(%L)',bad),'22023','initial_analysis_input_invalid','reject noncanonical candidate')
FROM cpm_candidate_vector CROSS JOIN LATERAL unnest(ARRAY[value->>'canonical'||E'\n','{"version":1,'||substr(value->>'canonical',2),'null','{',NULL]) bad;
SELECT extensions.throws_ok(format('SELECT internal.parse_initial_cpm_photo_candidate(%L)',internal.initial_canonical(bad)),'22023','initial_analysis_input_invalid','reject candidate protocol/options/embedded content')
FROM cpm_candidate_vector CROSS JOIN LATERAL (VALUES
 (jsonb_set(value->'candidate','{admission,client_protocol}','2')),
 (jsonb_set(value->'candidate','{admission,identification_protocol}','8')),
 (jsonb_set(value->'candidate','{admission,expected_processor_permission}','null')),
 (jsonb_set(value->'candidate','{admission,language}','"en"')),
 (jsonb_set(value->'candidate','{variant}','"media_sources"')),
 (jsonb_set(value->'candidate','{content_canonical}',to_jsonb(value#>>'{candidate,content_canonical}'||E'\n'))),
 (jsonb_set(value->'candidate','{content_canonical}',to_jsonb('{}'::TEXT)))
) v(bad);

SELECT extensions.throws_ok(format('SELECT internal.parse_initial_cpm_photo_content(%L)',internal.initial_canonical(bad)),'22023','initial_analysis_input_invalid','reject invalid content/recipe/role')
FROM cpm_content_vector CROSS JOIN LATERAL (VALUES
 (jsonb_set(value->'content','{photos}','[]')),
 (jsonb_set(value->'content','{photos,0,ordinal}','1')),
 (jsonb_set(value->'content','{photos,0,ai,reference_id}',value#>'{content,photos,0,source,reference_id}')),
 (jsonb_set(value->'content','{photos,0,source,byte_count}','33554433')),
 (jsonb_set(value->'content','{photos,0,ai,byte_count}','5242881')),
 (jsonb_set(value->'content','{photos,0,display,byte_count}','4194305')),
 (jsonb_set(value->'content','{photos,0,recipe,scale_bits}','"7ff0000000000000"')),
 (jsonb_set(value->'content','{photos,0,recipe,scale_bits}','"bff0000000000000"')),
 (jsonb_set(value->'content','{photos,0,recipe,offset_x_bits}','"fff8000000000000"')),
 (jsonb_set(value->'content','{photos,0,recipe,crop_display_size_bits}','"8000000000000000"')),
 (jsonb_set(value->'content','{photos,0,recipe,crop_display_size_bits}','"0000000000000000"')),
 (jsonb_set(value->'content','{photos,0,recipe,quarter_turns}','1')),
 (jsonb_set(value->'content','{photos,0,recipe,camera_vertical_center_bits}','"0000000000000000"')),
 (jsonb_set(value->'content','{contexts,0,text_utf8_base64}','"AB=="'))
) v(bad);

CREATE TEMP TABLE cpm_text_boundary AS SELECT jsonb_set(value->'content','{contexts}',
 (SELECT jsonb_agg(jsonb_build_object('text_utf8_base64',replace(encode(convert_to(repeat('a',8000),'UTF8'),'base64'),E'\n',''))) FROM generate_series(1,4))) AS value FROM cpm_content_vector;
SELECT extensions.lives_ok(format('SELECT internal.parse_initial_cpm_photo_content(%L)',internal.initial_canonical(value)),'32000 aggregate text boundary') FROM cpm_text_boundary;
SELECT extensions.throws_ok(format('SELECT internal.parse_initial_cpm_photo_content(%L)',internal.initial_canonical(
 jsonb_set(value,'{contexts,0,text_utf8_base64}',to_jsonb(replace(encode(convert_to(repeat('a',8001),'UTF8'),'base64'),E'\n',''))))),
 '22023','initial_analysis_input_invalid','32001 aggregate text denied') FROM cpm_text_boundary;
SELECT extensions.throws_ok(format('SELECT internal.initial_cpm_photo_digest(%L,%L)',domain,'{}'),'22023','initial_analysis_input_invalid','unknown digest domain') FROM unnest(ARRAY['Assignment','input','Content',NULL]) domain;
CREATE TEMP TABLE cpm_assignment_vector AS SELECT $assignment_vector${"synthetic_only":true,"assignment":{"version":1,"variant":"client_prepared_photo","candidate_digest":"d6386c57a8e3d67c5cb8566fc46dfa59378613ccd0494c85669905df25b2d57a","content_digest":"d75caa6fdc3c9f374149c666cb2bb3b153934bc6dc4040589fa418ee7e41c806","scan_id":"00000000-0000-4000-8000-000000000001","package_id":"00000000-0000-4000-8000-000000000002","created_at_ms":1793140000000,"expires_at_ms":1793141800000,"configuration":{"route":"identify","operation":"scan_identification","effective_plan":"pro_complimentary","effective_tier":"pro","flash_fallback_used":false,"quota_model":"synthetic-cpm-model","policy_version":1,"provider":"gemini","binding":"synthetic_cpm_binding_v1","processor_permission":"google_gemini","input_profile":"vision_compat_v1","provider_model":null,"effective_model":"synthetic-cpm-model","minimum_client_protocol":0,"accepted_client_protocol":3,"minimum_identification_protocol":0,"accepted_identification_protocol":6,"asset_manifest_digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_owner":"initial_engine_release_archive","resolver_id":"git_blob_sha256_v1","output_language":"en"},"preparation":{"resource_profile":"P1-L1","composition_policy":"cpm_photo_contexts_v1","profile_digest":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","installation_digest":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","selector_generation":"00000000-0000-4000-8000-000000000100","backend_generation":"00000000-0000-4000-8000-000000000101","backend_installation_digest":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","verifier_build_digest":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","role_mapping":[{"photo_ordinal":0,"role":"source","object_id":"00000000-0000-4000-8000-000000000200","declaration":{"byte_count":1,"declared_content_type":"image/jpeg","reference_id":"00000000-0000-4000-8000-000000000003","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}},{"photo_ordinal":0,"role":"ai","object_id":"00000000-0000-4000-8000-000000000201","declaration":{"byte_count":1,"declared_content_type":"image/jpeg","reference_id":"00000000-0000-4000-8000-000000000004","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}},{"photo_ordinal":0,"role":"display","object_id":"00000000-0000-4000-8000-000000000202","declaration":{"byte_count":1,"declared_content_type":"image/jpeg","reference_id":"00000000-0000-4000-8000-000000000005","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}]}},"canonical":"{\"candidate_digest\":\"d6386c57a8e3d67c5cb8566fc46dfa59378613ccd0494c85669905df25b2d57a\",\"configuration\":{\"accepted_client_protocol\":3,\"accepted_identification_protocol\":6,\"asset_manifest_digest\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"binding\":\"synthetic_cpm_binding_v1\",\"effective_model\":\"synthetic-cpm-model\",\"effective_plan\":\"pro_complimentary\",\"effective_tier\":\"pro\",\"flash_fallback_used\":false,\"input_profile\":\"vision_compat_v1\",\"minimum_client_protocol\":0,\"minimum_identification_protocol\":0,\"operation\":\"scan_identification\",\"output_language\":\"en\",\"policy_version\":1,\"processor_permission\":\"google_gemini\",\"provider\":\"gemini\",\"provider_model\":null,\"quota_model\":\"synthetic-cpm-model\",\"resolver_id\":\"git_blob_sha256_v1\",\"retention_owner\":\"initial_engine_release_archive\",\"route\":\"identify\"},\"content_digest\":\"d75caa6fdc3c9f374149c666cb2bb3b153934bc6dc4040589fa418ee7e41c806\",\"created_at_ms\":1793140000000,\"expires_at_ms\":1793141800000,\"package_id\":\"00000000-0000-4000-8000-000000000002\",\"preparation\":{\"backend_generation\":\"00000000-0000-4000-8000-000000000101\",\"backend_installation_digest\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"composition_policy\":\"cpm_photo_contexts_v1\",\"installation_digest\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"profile_digest\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"resource_profile\":\"P1-L1\",\"role_mapping\":[{\"declaration\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000003\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"object_id\":\"00000000-0000-4000-8000-000000000200\",\"photo_ordinal\":0,\"role\":\"source\"},{\"declaration\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000004\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"object_id\":\"00000000-0000-4000-8000-000000000201\",\"photo_ordinal\":0,\"role\":\"ai\"},{\"declaration\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000005\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"object_id\":\"00000000-0000-4000-8000-000000000202\",\"photo_ordinal\":0,\"role\":\"display\"}],\"selector_generation\":\"00000000-0000-4000-8000-000000000100\",\"verifier_build_digest\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"},\"scan_id\":\"00000000-0000-4000-8000-000000000001\",\"variant\":\"client_prepared_photo\",\"version\":1}","digest":"eb616665a5a98638d564ef78f6aa08899551c0f09b4284fe36bf4c1afa0f7886"}$assignment_vector$::JSONB AS value;
SELECT extensions.is(internal.parse_initial_cpm_photo_assignment(c.value->>'canonical',a.value->>'canonical'),a.value->'assignment','assignment canonical golden') FROM cpm_candidate_vector c CROSS JOIN cpm_assignment_vector a;
SELECT extensions.is(internal.initial_cpm_photo_digest('assignment',value->>'canonical'),value->>'digest','assignment independent golden digest') FROM cpm_assignment_vector;

SELECT extensions.throws_ok(format('SELECT internal.parse_initial_cpm_photo_assignment(%L,%L)',c.value->>'canonical',internal.initial_canonical(bad)),
 '22023','initial_analysis_input_invalid','saved assignment binding denied')
FROM cpm_candidate_vector c CROSS JOIN cpm_assignment_vector a CROSS JOIN LATERAL (VALUES
 (jsonb_set(a.value->'assignment','{candidate_digest}',to_jsonb(repeat('0',64)))),
 (jsonb_set(a.value->'assignment','{content_digest}',to_jsonb(repeat('0',64)))),
 (jsonb_set(a.value->'assignment','{scan_id}',a.value#>'{assignment,package_id}')),
 (jsonb_set(a.value->'assignment','{package_id}',a.value#>'{assignment,scan_id}')),
 (jsonb_set(a.value->'assignment','{expires_at_ms}','1793141800001')),
 (jsonb_set(a.value->'assignment','{expires_at_ms}','1793141799999')),
 (jsonb_set(a.value->'assignment','{owner_id}',a.value#>'{assignment,scan_id}')),
 (jsonb_set(a.value->'assignment','{preparation,role_mapping}','[]')),
 (jsonb_set(a.value->'assignment','{preparation,role_mapping,0,object_id}',a.value#>'{assignment,preparation,role_mapping,1,object_id}')),
 (jsonb_set(a.value->'assignment','{preparation,role_mapping,0,photo_ordinal}','1')),
 (jsonb_set(a.value->'assignment','{preparation,role_mapping,0,role}','"display"')),
 (jsonb_set(a.value->'assignment','{preparation,role_mapping,0,declaration,byte_count}','2')),
 (jsonb_set(a.value->'assignment','{preparation,role_mapping,0,declaration,sha256}',to_jsonb(repeat('0',64)))),
 (jsonb_set(a.value->'assignment','{preparation,role_mapping,0,declaration,reference_id}',a.value#>'{assignment,package_id}')),
 (jsonb_set(a.value->'assignment','{preparation,role_mapping,0,declaration,declared_content_type}','"image/png"')),
 (jsonb_set(a.value->'assignment','{preparation,composition_policy}','"legacy"')),
 (jsonb_set(a.value->'assignment','{configuration,processor_permission}','"openai"')),
 (jsonb_set(a.value->'assignment','{configuration,provider}','"openai"')),
 (jsonb_set(a.value->'assignment','{configuration,minimum_client_protocol}','4')),
 (jsonb_set(a.value->'assignment','{configuration,minimum_identification_protocol}','7')),
 (jsonb_set(a.value->'assignment','{configuration,effective_tier}','"free"')),
 (jsonb_set(a.value->'assignment','{configuration,effective_model}','"changed"')),
 (jsonb_set(a.value->'assignment','{configuration,route}','"identify-multimodal"')),
 (jsonb_set(a.value->'assignment','{configuration,output_language}','null'))
) x(bad);

SELECT extensions.throws_ok(format('SELECT internal.parse_initial_cpm_photo_assignment(%L,%L)',c.value->>'canonical',replace(a.value->>'canonical','1793140000000','1793140000000.5')),
 '22023','initial_analysis_input_invalid','fractional clock rejected at wire parser') FROM cpm_candidate_vector c CROSS JOIN cpm_assignment_vector a;

CREATE TEMP TABLE cpm_recovery_vector AS SELECT internal.initial_canonical(jsonb_build_object(
 'version',1,'variant','client_prepared_photo','outcome','allocated','authority','none',
 'assignment_canonical',value->>'canonical','assignment_digest',value->>'digest')) AS canonical FROM cpm_assignment_vector;
SELECT extensions.is(internal.parse_initial_cpm_photo_recovery(c.value->>'canonical',r.canonical,saved),r.canonical::JSONB,'exact saved allocation recovery')
FROM cpm_candidate_vector c CROSS JOIN cpm_recovery_vector r CROSS JOIN cpm_assignment_vector a CROSS JOIN LATERAL unnest(ARRAY[NULL,a.value->>'canonical']) saved;
SELECT extensions.throws_ok(format('SELECT internal.parse_initial_cpm_photo_recovery(%L,%L,%L)',c.value->>'canonical',internal.initial_canonical(bad),a.value->>'canonical'),
 '22023','initial_analysis_input_invalid','closed recovery denies authority and wire drift')
FROM cpm_candidate_vector c CROSS JOIN cpm_recovery_vector r CROSS JOIN cpm_assignment_vector a CROSS JOIN LATERAL (VALUES
 (jsonb_set(r.canonical::JSONB,'{authority}','"upload"')),
 (jsonb_set(r.canonical::JSONB,'{outcome}','"admitted"')),
 (jsonb_set(r.canonical::JSONB,'{assignment_digest}',to_jsonb(repeat('0',64)))),
 (jsonb_set(r.canonical::JSONB,'{assignment_canonical}',to_jsonb(a.value->>'canonical'||E'\n'))),
 (jsonb_set(r.canonical::JSONB,'{owner_id}',a.value#>'{assignment,scan_id}'))
) x(bad);

-- Changed but individually valid assignments may not replace a saved one.
CREATE TEMP TABLE cpm_recovery_changed AS SELECT internal.initial_canonical(changed) AS canonical
FROM cpm_assignment_vector a CROSS JOIN LATERAL (VALUES
 (jsonb_set(jsonb_set(a.value->'assignment','{created_at_ms}','1793140000001'),'{expires_at_ms}','1793141800001')),
 (jsonb_set(a.value->'assignment','{configuration,output_language}','"fr"')),
 (jsonb_set(a.value->'assignment','{preparation,backend_generation}',a.value#>'{assignment,package_id}')),
 (jsonb_set(a.value->'assignment','{preparation,role_mapping,0,object_id}',a.value#>'{assignment,package_id}'))
) x(changed);
SELECT extensions.lives_ok(format('SELECT internal.parse_initial_cpm_photo_assignment(%L,%L)',c.value->>'canonical',changed.canonical),'alternate allocation is structurally valid')
FROM cpm_candidate_vector c CROSS JOIN cpm_recovery_changed changed;
SELECT extensions.throws_ok(format('SELECT internal.parse_initial_cpm_photo_recovery(%L,%L,%L)',c.value->>'canonical',internal.initial_canonical(
 jsonb_build_object('version',1,'variant','client_prepared_photo','outcome','allocated','authority','none',
 'assignment_canonical',changed.canonical,'assignment_digest',internal.initial_cpm_photo_digest('assignment',changed.canonical))),a.value->>'canonical'),
 '22023','initial_analysis_input_invalid','recovery cannot renew original clock/config/destination/generation')
FROM cpm_candidate_vector c CROSS JOIN cpm_assignment_vector a CROSS JOIN cpm_recovery_changed changed;

SELECT extensions.lives_ok(format('SELECT internal.parse_initial_cpm_photo_recovery(%L,%L,NULL)',c.value->>'canonical',internal.initial_canonical(
 jsonb_build_object('version',1,'variant','client_prepared_photo','outcome','terminal_held','authority','none',
 'scan_id',a.value#>>'{assignment,scan_id}','reason',reason))),'terminal state conveys no new authority')
FROM cpm_candidate_vector c CROSS JOIN cpm_assignment_vector a CROSS JOIN unnest(ARRAY['not_found','expired','cancelled']) reason;
SELECT * FROM extensions.finish();
ROLLBACK;
