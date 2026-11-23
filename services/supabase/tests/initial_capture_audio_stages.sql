BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SELECT set_config('request.jwt.claim.role','service_role',true);
CREATE FUNCTION pg_temp.new_audio_stage() RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE owner UUID:=gen_random_uuid(); scan UUID:=gen_random_uuid(); gen UUID:=gen_random_uuid(); body JSONB;
BEGIN
 INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(owner,'authenticated','authenticated','{}','{}',now(),now());
 body:=jsonb_build_object('owner_id',owner,'recipe','mono-pcm16-16000-trim-bandlimited-v1','plan',
 jsonb_build_object('schema_version',1,'scan_id',scan,'generation',gen,'items',jsonb_build_array(
 jsonb_build_object('kind','audio','source',jsonb_build_object('media_id',gen_random_uuid(),'content_type','audio/wav',
 'byte_count',100,'sha256',repeat('a',64)),'prepared_media_id',gen_random_uuid()),
 jsonb_build_object('kind','audio','source',jsonb_build_object('media_id',gen_random_uuid(),'content_type','audio/wav',
 'byte_count',100,'sha256',repeat('b',64)),'prepared_media_id',gen_random_uuid()))));
 RETURN jsonb_build_object('body',body,'attempt',gen_random_uuid(),'hash',encode(extensions.digest(convert_to(body::TEXT,'UTF8'),'sha256'),'hex'));
END;
$$;
CREATE FUNCTION pg_temp.stage(f JSONB,action TEXT,artifacts JSONB DEFAULT NULL,object UUID DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.initial_capture_audio_stage_action((f->'body')::TEXT,f->>'hash',repeat('a',64),action,
 CASE WHEN action IN('reserve','bind') THEN (f->>'attempt')::UUID ELSE NULL END,artifacts,object);
$$;
CREATE FUNCTION pg_temp.outputs(f JSONB) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_agg(jsonb_build_object('media_id',value->'prepared_media_id','content_type','audio/wav','byte_count',16044,'sha256',repeat('c',64)) ORDER BY ordinality)
 FROM jsonb_array_elements(f#>'{body,plan,items}') WITH ORDINALITY;
$$;
CREATE TEMP TABLE stage_fixture(name TEXT PRIMARY KEY,f JSONB,receipt JSONB);
INSERT INTO stage_fixture(name,f) SELECT name,pg_temp.new_audio_stage() FROM unnest(ARRAY['main','rollback','account','owner','scan','merge']) name;
GRANT ALL ON stage_fixture TO service_role;
GRANT EXECUTE ON FUNCTION pg_temp.stage(JSONB,TEXT,JSONB,UUID) TO service_role;
SET LOCAL ROLE service_role;
SELECT extensions.lives_ok($$UPDATE stage_fixture SET receipt=pg_temp.stage(f,'reserve')$$,'service reserves complete plan before DSP');
RESET ROLE;
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.scan_ingestion_jobs j JOIN stage_fixture f ON j.scan_id=f.f#>>'{body,plan,scan_id}'),0,'staging creates no ingestion job');
SELECT extensions.is(jsonb_array_length(receipt->'items'),2,'reserves both output identities') FROM stage_fixture WHERE name='main';
SELECT extensions.is(pg_temp.stage(f||jsonb_build_object('attempt',gen_random_uuid()),'reserve'),receipt,'retry recovers saved attempt and objects') FROM stage_fixture WHERE name='main';
SELECT extensions.throws_ok($$SELECT pg_temp.stage(f||jsonb_build_object('hash',repeat('0',64)),'reserve') FROM stage_fixture WHERE name='main'$$,'22023','invalid_analysis_history','hash must bind complete request bytes');
SELECT extensions.throws_ok($$SELECT public.initial_capture_audio_stage_action((f->'body')::TEXT,f->>'hash',repeat('b',64),'reserve',(f->>'attempt')::UUID,NULL,NULL) FROM stage_fixture WHERE name='main'$$,'55000','analysis_history_operation_conflict','backend cannot change on replay');
SELECT extensions.throws_ok($$SELECT pg_temp.stage(f,'read',pg_temp.outputs(f)->0,(receipt#>>'{items,0,object_id}')::UUID) FROM stage_fixture WHERE name='main'$$,'55000','analysis_history_operation_conflict','unbound object has no read authority');
SELECT extensions.throws_ok($$SELECT pg_temp.stage(f,'bind',jsonb_set(pg_temp.outputs(f),'{1,byte_count}','1')) FROM stage_fixture WHERE name='rollback'$$,'22023','invalid_analysis_history','invalid second output rolls back entire binding');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.initial_capture_audio_stage_objects o JOIN stage_fixture f ON o.scan_id=(f.f#>>'{body,plan,scan_id}')::UUID WHERE f.name='rollback' AND o.artifact IS NOT NULL),0,'no half-bound output survives');
SELECT extensions.throws_ok($$SELECT pg_temp.stage(f||jsonb_build_object('attempt',gen_random_uuid()),'bind',pg_temp.outputs(f)) FROM stage_fixture WHERE name='main'$$,'55000','analysis_history_operation_conflict','another attempt cannot bind');
UPDATE stage_fixture SET receipt=pg_temp.stage(f,'bind',pg_temp.outputs(f)) WHERE name='main';
SELECT extensions.throws_ok($$SELECT pg_temp.stage(f,'bind',pg_temp.outputs(f)) FROM stage_fixture WHERE name='main'$$,'55000','analysis_history_operation_conflict','binding is one-shot even if acknowledgement was lost');
SELECT extensions.throws_ok($$SELECT pg_temp.stage(f,'complete',pg_temp.outputs(f)->0,(receipt#>>'{items,0,object_id}')::UUID) FROM stage_fixture WHERE name='main'$$,'55000','analysis_history_unavailable','no readiness before issued write');
SELECT extensions.is(pg_temp.stage(f,'write',pg_temp.outputs(f)->0,(receipt#>>'{items,0,object_id}')::UUID),'true'::JSONB,'first write issued durably') FROM stage_fixture WHERE name='main';
SELECT extensions.is(pg_temp.stage(f,'write',pg_temp.outputs(f)->0,(receipt#>>'{items,0,object_id}')::UUID),'false'::JSONB,'lost write acknowledgement cannot grant another write') FROM stage_fixture WHERE name='main';
SELECT extensions.is(pg_temp.stage(f,'read',pg_temp.outputs(f)->0,(receipt#>>'{items,0,object_id}')::UUID),'true'::JSONB,'bound issued output supports exact recovery read') FROM stage_fixture WHERE name='main';
SELECT extensions.throws_ok($$SELECT pg_temp.stage(f,'read',jsonb_set(pg_temp.outputs(f)->0,'{sha256}',to_jsonb(repeat('d',64))),(receipt#>>'{items,0,object_id}')::UUID) FROM stage_fixture WHERE name='main'$$,'55000','analysis_history_operation_conflict','changed hash cannot obtain read authority');
UPDATE stage_fixture SET receipt=pg_temp.stage(f,'complete',pg_temp.outputs(f)->0,(receipt#>>'{items,0,object_id}')::UUID) WHERE name='main';
SELECT extensions.is(receipt#>'{items,0,ready}','true'::JSONB,'verified output marked ready') FROM stage_fixture WHERE name='main';
SELECT extensions.is(receipt#>'{items,1,ready}','false'::JSONB,'unverified output remains unready') FROM stage_fixture WHERE name='main';
SELECT extensions.is(pg_temp.stage(f,'complete',pg_temp.outputs(f)->0,(receipt#>>'{items,0,object_id}')::UUID),receipt,'readback completion retry preserves receipt') FROM stage_fixture WHERE name='main';

-- Account/scan deletion must cover prospective scans with no public scan row.
SELECT public.request_account_deletion((f#>>'{body,owner_id}')::UUID) FROM stage_fixture WHERE name='account';
DELETE FROM public.users WHERE id=(SELECT (f#>>'{body,owner_id}')::UUID FROM stage_fixture WHERE name='owner');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) SELECT (f#>>'{body,plan,scan_id}')::UUID,(f#>>'{body,owner_id}')::UUID FROM stage_fixture WHERE name='scan';
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.initial_capture_audio_stage_erasure e JOIN LATERAL jsonb_array_elements(receipt->'items') item ON e.object_id=(item->>'object_id')::UUID),2,'deletion retains every opaque stage erasure obligation: '||name)
 FROM stage_fixture WHERE name IN('account','owner','scan');
SELECT extensions.ok(s.request_body IS NULL AND s.retired_at IS NOT NULL,'deletion clears private plan and preserves no-reuse identity: '||name)
 FROM stage_fixture f JOIN internal.initial_capture_audio_stages s ON s.scan_id=(f.f#>>'{body,plan,scan_id}')::UUID WHERE name IN('account','owner','scan');
SELECT extensions.throws_ok(format('SELECT pg_temp.stage(%L::jsonb,''reserve'')',f),'55000','analysis_history_unavailable','deleted owner or scan cannot recreate stage: '||name)
 FROM stage_fixture WHERE name IN('account','owner','scan');
SELECT extensions.lives_ok($$SELECT internal.perform_ghost_profile_merge((SELECT (f#>>'{body,owner_id}')::UUID FROM stage_fixture WHERE name='merge'),(SELECT (f#>>'{body,owner_id}')::UUID FROM stage_fixture WHERE name='rollback'))$$,'settled merge retires pre-admission stage without a public scan');
SELECT extensions.ok(s.request_body IS NULL AND s.retired_at IS NOT NULL,'merge erases private stage plan without reparenting')
 FROM internal.initial_capture_audio_stages s JOIN stage_fixture f ON s.scan_id=(f.f#>>'{body,plan,scan_id}')::UUID WHERE name='merge';
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.initial_capture_audio_stage_erasure e JOIN LATERAL jsonb_array_elements(receipt->'items') item ON e.object_id=(item->>'object_id')::UUID),2,'merge retains both marker obligations') FROM stage_fixture WHERE name='merge';
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.scan_media_assets a JOIN stage_fixture f ON a.client_scan_id=(f.f#>>'{body,plan,scan_id}')::UUID),0,'no server output enters public asset or generic TTL sweep');
SELECT extensions.ok(relrowsecurity,'RLS on '||oid::regclass::TEXT) FROM pg_class WHERE oid IN(
 'internal.initial_capture_audio_stages'::regclass,'internal.initial_capture_audio_stage_objects'::regclass,'internal.initial_capture_audio_stage_erasure'::regclass);
SELECT extensions.ok(NOT has_table_privilege(role,tab,'SELECT,INSERT,UPDATE,DELETE'),role||' no direct access to '||tab)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role CROSS JOIN unnest(ARRAY[
 'internal.initial_capture_audio_stages','internal.initial_capture_audio_stage_objects','internal.initial_capture_audio_stage_erasure']) tab;
SELECT extensions.ok(NOT has_function_privilege(role,'public.initial_capture_audio_stage_action(text,text,text,text,uuid,jsonb,uuid)','EXECUTE'),role||' cannot acquire stage authority') FROM unnest(ARRAY['anon','authenticated']) role;
SELECT * FROM extensions.finish();
ROLLBACK;
