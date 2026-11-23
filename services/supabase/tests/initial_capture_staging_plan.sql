BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT no_plan();

CREATE FUNCTION pg_temp.capture_artifact(n INTEGER,mime TEXT,bytes BIGINT) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('media_id','00000000-0000-4000-8000-'||lpad(n::TEXT,12,'0'),
   'content_type',mime,'byte_count',bytes,'sha256',repeat('a',64));
$$;
CREATE TEMP TABLE capture_plan_fixture(plan JSONB,owner UUID);
INSERT INTO capture_plan_fixture VALUES (jsonb_build_object('schema_version',1,
  'scan_id','00000000-0000-4000-8000-000000000002','generation','00000000-0000-4000-8000-000000000003',
  'items',jsonb_build_array(
    jsonb_build_object('kind','image','source',pg_temp.capture_artifact(10,'image/heic',33554432),
      'prepared',pg_temp.capture_artifact(11,'image/jpeg',100),'coordinate_basis','prepared_image_top_left_v1',
      'focus_region',NULL,'preparation',jsonb_build_object('schema_version',1,
      'coordinate_basis','upright_source_top_left_v1','format','nativeStillImageV1','crop_display_size',NULL,
      'quarter_turns',0,'scale',1,'offset_x',0,'offset_y',0,'camera_vertical_center',NULL,'source_selection',NULL)),
    jsonb_build_object('kind','audio','source',pg_temp.capture_artifact(20,'audio/wav',100),
      'prepared_media_id','00000000-0000-4000-8000-000000000021'))),
  '00000000-0000-4000-8000-000000000001');

SELECT is(jsonb_array_length(internal.initial_capture_plan_contract(owner,plan)->'uploads'),3,
  'full photo and raw audio upload inventory excludes server output') FROM capture_plan_fixture;
SELECT is(internal.initial_capture_plan_contract(owner,plan)#>>'{uploads,0,byte_count}','33554432',
  'source photo retains V9 original-size bound') FROM capture_plan_fixture;
SELECT is(internal.initial_capture_plan_contract(owner,plan)#>>'{audio,0,prepared_media_id}',
  '00000000-0000-4000-8000-000000000021','reserved prepared audio ID is distinct from upload input') FROM capture_plan_fixture;
SELECT is(internal.initial_capture_plan_contract(owner,plan)#>'{audio,0,companion}','false'::JSONB,
  'standalone audio never receives video fallback') FROM capture_plan_fixture;
SELECT is(internal.initial_capture_plan_contract(owner,plan)#>'{audio,0,source}',
  internal.initial_capture_plan_contract(owner,plan)#>'{uploads,2}','audio retains exact source association') FROM capture_plan_fixture;
SELECT ok(NOT internal.initial_capture_plan_contract(owner,plan) ? 'evidence_digest',
  'minimum placeholder digest cannot escape the descriptive contract') FROM capture_plan_fixture;

SELECT throws_ok(format('SELECT internal.initial_capture_plan_contract(%L,%L::jsonb)',owner,changed),
  '22023','invalid_analysis_history',description)
FROM capture_plan_fixture CROSS JOIN LATERAL (VALUES
  (plan||'{"extra":true}'::JSONB,'reject unknown plan field'),
  (plan||'{"evidence_digest":"client-invented"}'::JSONB,'reject client final evidence digest'),
  (jsonb_set(plan,'{items,1,prepared}',pg_temp.capture_artifact(21,'audio/wav',100)),'reject invented prepared facts'),
  (jsonb_set(plan,'{items,1,prepared_media_id}',to_jsonb(owner::TEXT)),'reject owner ID alias'),
  (jsonb_set(plan,'{items,1,prepared_media_id}',plan#>'{items,1,source,media_id}'),'reject source/prepared alias'),
  (jsonb_set(plan,'{items,1,source,content_type}','"audio/mp4"'),'historical M4A is not ordinary DSP input'),
  (jsonb_set(plan,'{items,0,prepared,byte_count}','5242881'),'provider image bound is unchanged'),
  (jsonb_set(plan,'{items,0,source,byte_count}','33554433'),'original source bound is unchanged'),
  (jsonb_set(plan,'{items,0,preparation,scale}','2'),'reject no-crop geometry drift'),
  (jsonb_set(plan,'{items}','[]'),'reject empty capture plan'),
  (jsonb_set(plan,'{items,1,prepared_media_id}','"not-an-id"'),'reject invalid reserved identity')
) rejected(changed,description);

UPDATE capture_plan_fixture SET plan=jsonb_set(plan,'{items,1}',jsonb_build_object('kind','video',
  'source',pg_temp.capture_artifact(30,'video/mp4',100),'playback',pg_temp.capture_artifact(31,'video/mp4',100),
  'frames',jsonb_build_array(pg_temp.capture_artifact(32,'image/jpeg',100)),
  'audio',jsonb_build_object('source',pg_temp.capture_artifact(40,'audio/wav',100),
    'prepared_media_id','00000000-0000-4000-8000-000000000041')));
SELECT is(jsonb_array_length(internal.initial_capture_plan_contract(owner,plan)->'uploads'),6,
  'video plan retains originals, playback, frame and source companion') FROM capture_plan_fixture;
SELECT is(internal.initial_capture_plan_contract(owner,plan)#>'{audio,0,companion}','true'::JSONB,
  'video companion carries server fallback association') FROM capture_plan_fixture;
SELECT is(internal.initial_capture_plan_contract(owner,plan)#>>'{audio,0,source,role}',
  'source_companion_audio','companion source role is preserved') FROM capture_plan_fixture;
SELECT is(jsonb_array_length(internal.initial_capture_plan_contract(owner,jsonb_set(plan,'{items,1,audio}','null'))->'audio'),0,
  'silent video does not invent prepared audio') FROM capture_plan_fixture;
SELECT ok(NOT has_function_privilege(role,'internal.initial_capture_plan_contract(uuid,jsonb)','EXECUTE'),
  role||' cannot use parser as allocation or upload authority') FROM (VALUES('anon'),('authenticated'),('service_role')) r(role);
SELECT ok(NOT prosecdef,'capture plan parser is invoker only') FROM pg_proc
  WHERE oid='internal.initial_capture_plan_contract(uuid,jsonb)'::regprocedure;
SELECT is(provolatile::TEXT,'s','capture plan parser preserves canonical stable validator') FROM pg_proc
  WHERE oid='internal.initial_capture_plan_contract(uuid,jsonb)'::regprocedure;
SELECT * FROM finish();
ROLLBACK;
