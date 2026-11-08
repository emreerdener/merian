-- Private vocabulary/image composition only; no complete writer or new grant.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();

SELECT extensions.is(
 jsonb_array_length(internal.initial_completion_event_catalog_v1(media,funding,species)),
 12 + CASE WHEN media='cpm' THEN 4 ELSE 0 END
    + CASE WHEN funding='none' THEN 0 ELSE 8 END
    + CASE species WHEN 'new' THEN 16 WHEN 'existing' THEN 15 ELSE 0 END,
 'bounded closed event case: '||media||'/'||funding||'/'||species)
FROM unnest(ARRAY['legacy','cpm']) media
CROSS JOIN unnest(ARRAY['none','consumed','paid_release']) funding
CROSS JOIN unnest(ARRAY['none','new','existing']) species;

SELECT extensions.ok(NOT EXISTS(
 SELECT 1
 FROM jsonb_array_elements(internal.initial_completion_event_catalog_v1('cpm','consumed','new'))
 WITH ORDINALITY e(value,position)
 WHERE (value->>'ordinal')::INTEGER<>position-1
  OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(value) k)
   IS DISTINCT FROM ARRAY['action','level','ordinal','relation','slot','when']::TEXT[]
), 'event schema and ordinals are closed and contiguous');

SELECT extensions.is((
 SELECT count(*)::INTEGER
 FROM jsonb_array_elements(internal.initial_completion_event_catalog_v1('legacy','none','existing')) e
 WHERE e->>'slot'='species.insert' AND e->>'level'='ROW' AND e->>'when'='BEFORE'
),1,'conflicting species insert retains exactly one attempted row');
SELECT extensions.is((
 SELECT count(*)::INTEGER
 FROM jsonb_array_elements(internal.initial_completion_event_catalog_v1('legacy','none','existing')) e
 WHERE e->>'slot'='species.insert' AND e->>'level'='ROW' AND e->>'when'='AFTER'
),0,'conflicting species insert never claims a committed row');
SELECT extensions.is((
 SELECT count(*)::INTEGER
 FROM jsonb_array_elements(internal.initial_completion_event_catalog_v1('legacy','none','new')) e
 WHERE e->>'slot'='species.insert' AND e->>'level'='ROW' AND e->>'when'='AFTER'
),1,'new species insert requires its committed row');

SELECT extensions.ok(NOT has_function_privilege(role_name,
 'internal.initial_completion_event_catalog_v1(text,text,text)','EXECUTE'),
 'no API execution grant for '||role_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;

SELECT extensions.throws_ok($$SELECT internal.initial_completion_event_catalog_v1(NULL,'none','none')$$,
 '22023','initial_completion_event_case_invalid','null case is not inferred');
SELECT extensions.throws_ok($$SELECT internal.initial_completion_event_catalog_v1('legacy','released','none')$$,
 '22023','initial_completion_event_case_invalid','arbitrary settled credit is not a completion case');
SELECT extensions.throws_ok($$SELECT internal.initial_completion_event_catalog_v1('legacy','none','ambiguous')$$,
 '22023','initial_completion_event_case_invalid','caller cannot extend species cases');
SELECT extensions.throws_ok($$SELECT internal.initial_consuming_statement_catalog('completion')$$,
 '22023','initial_analysis_consuming_operation_unavailable','metadata does not enable completion business writes');

CREATE TEMP TABLE tail_cases AS
WITH original AS (
 SELECT species_case,
  jsonb_build_object('owner_id','00000000-0000-4000-8000-000000000001',
   'scan_id','00000000-0000-4000-8000-000000000002',
   'result_evidence_id','00000000-0000-4000-8000-000000000003',
   'media_case','legacy','species_case',species_case,
   'species',CASE WHEN species_case='none' THEN 'null'::JSONB ELSE
    '{"id":"00000000-0000-4000-8000-000000000004"}'::JSONB END,
   'species_count',CASE WHEN species_case='existing' THEN
    '{"user_id":"00000000-0000-4000-8000-000000000001","species_id":"00000000-0000-4000-8000-000000000004","scan_count":7}'::JSONB ELSE 'null'::JSONB END,
   'scan_final',jsonb_build_object('id','00000000-0000-4000-8000-000000000002',
    'user_id','00000000-0000-4000-8000-000000000001',
    'species_id',CASE WHEN species_case<>'none' THEN '00000000-0000-4000-8000-000000000004' END)) AS prestate
 FROM unnest(ARRAY['none','new','existing']) species_case
), credit AS (
 SELECT funding,jsonb_build_object('case',funding,'owner_after',
  '{"id":"00000000-0000-4000-8000-000000000001","total_species_discovered":11,"entitlement_version":19,"complimentary_entitlement_epoch":17,"other_fields_sha256":"synthetic-redacted-fingerprint"}'::JSONB,
  'events',CASE WHEN funding='none' THEN '[]'::JSONB ELSE '[{},{},{},{},{},{},{},{}]'::JSONB END) AS prefix
 FROM unnest(ARRAY['none','consumed','paid_release']) funding
), completion AS (
 SELECT '{"scan_id":"00000000-0000-4000-8000-000000000002","owner_id":"00000000-0000-4000-8000-000000000001","result_evidence_id":"00000000-0000-4000-8000-000000000003","receipt_version":1,"receipt_snapshot":{},"completion_projection_snapshot":{}}'::JSONB AS image
)
SELECT species_case,funding,prestate,prefix,image,
 internal.initial_completion_tail_images_v1(prestate,prefix,image) AS tail
FROM original CROSS JOIN credit CROSS JOIN completion;

SELECT extensions.is(jsonb_array_length(tail->'events'),
 12+CASE species_case WHEN 'new' THEN 16 WHEN 'existing' THEN 15 ELSE 0 END,
 'tail excludes consumed prefix: '||funding||'/'||species_case) FROM tail_cases;
SELECT extensions.ok(NOT EXISTS(
 SELECT 1 FROM tail_cases CROSS JOIN LATERAL jsonb_array_elements(tail->'events') WITH ORDINALITY e(value,position)
 WHERE (value->>'ordinal')::INTEGER<>position-1+CASE WHEN funding='none' THEN 0 ELSE 8 END
  OR (value->>'level'='STATEMENT' AND (value->'old'<>'null'::JSONB OR value->'new'<>'null'::JSONB))
), 'tail keeps absolute cursor ordinals and exact empty statement images');
SELECT extensions.ok(NOT EXISTS(
 SELECT 1 FROM tail_cases WHERE tail#>>'{owner_after,entitlement_version}'<>'19'
  OR tail#>>'{owner_after,complimentary_entitlement_epoch}'<>'17'
  OR tail#>>'{owner_after,other_fields_sha256}'<>'synthetic-redacted-fingerprint'
  OR (tail#>>'{owner_after,total_species_discovered}')::INTEGER<>CASE WHEN species_case='new' THEN 12 ELSE 11 END
), 'species effect changes only the exact owner total, preserving financial fields/fingerprint');
SELECT extensions.ok(NOT EXISTS(
 SELECT 1 FROM tail_cases WHERE species_case='existing'
  AND (tail#>>'{species_after,scan_count}'<>'8' OR tail#>>'{attempted_species_insert,scan_count}'<>'1')
), 'conflict winner has count8 while the attempted insertion remains count1');
SELECT extensions.ok(NOT EXISTS(
 SELECT 1 FROM tail_cases CROSS JOIN LATERAL jsonb_array_elements(tail->'events') e
 WHERE (e->>'slot'='scan.insert' AND e->>'level'='ROW' AND e->'new' IS DISTINCT FROM prestate->'scan_final')
  OR (e->>'slot'='completion.insert' AND e->>'level'='ROW' AND e->'new' IS DISTINCT FROM image)
  OR (species_case='existing' AND e->>'slot'='species.insert' AND e->>'level'='ROW' AND e->>'when'='AFTER')
), 'exact scan/completion images and no invented committed conflict row');
SELECT extensions.throws_ok($$SELECT internal.initial_completion_tail_images_v1(
 jsonb_set(prestate,'{media_case}','"cpm"'),prefix,image) FROM tail_cases LIMIT 1$$,
 '22023','initial_completion_tail_invalid','CPM adoption cannot borrow the legacy tail');
SELECT extensions.throws_ok($$SELECT internal.initial_completion_tail_images_v1(
 jsonb_set(prestate,'{media_case}','"cpm"'),prefix||'{"adoption":null}'::JSONB,image) FROM tail_cases LIMIT 1$$,
 '22023','initial_completion_tail_invalid','CPM null adoption cannot become an event row');
SELECT extensions.throws_ok($$SELECT internal.initial_completion_tail_images_v1(
 jsonb_set(prestate,'{media_case}','"cpm"'),prefix||'{"adoption":{}}'::JSONB,image) FROM tail_cases LIMIT 1$$,
 '22023','initial_completion_tail_invalid','CPM incomplete adoption cannot become an event row');
SELECT extensions.throws_ok($$SELECT internal.initial_completion_tail_images_v1(
 prestate,prefix,jsonb_set(image,'{scan_id}','"00000000-0000-4000-8000-000000000099"')) FROM tail_cases LIMIT 1$$,
 '22023','initial_completion_tail_invalid','completion identity must match the original');
SELECT extensions.throws_ok($$SELECT internal.initial_completion_tail_images_v1(
 prestate,prefix,image||'{"extra":true}') FROM tail_cases LIMIT 1$$,
 '22023','initial_completion_tail_invalid','completion row vocabulary is closed');
SELECT extensions.ok(NOT has_function_privilege(role_name,
 'internal.initial_completion_tail_images_v1(jsonb,jsonb,jsonb)','EXECUTE'),
 'no API tail compositor grant for '||role_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT * FROM extensions.finish();
ROLLBACK;
