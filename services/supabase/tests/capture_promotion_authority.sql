BEGIN;
SELECT extensions.no_plan();
SELECT extensions.ok(relrowsecurity,'promotion authority has RLS') FROM pg_catalog.pg_class
    WHERE oid='internal.capture_promotion_operations'::regclass;
SELECT extensions.ok(NOT has_table_privilege(r,'internal.capture_promotion_operations','SELECT,INSERT,UPDATE,DELETE'),r||' has no direct authority')
    FROM unnest(ARRAY['anon','authenticated','service_role']) r;
SELECT extensions.ok(NOT has_function_privilege(r,f,'EXECUTE'),r||' denied '||f)
    FROM unnest(ARRAY['anon','authenticated']) r CROSS JOIN unnest(ARRAY[
        'public.register_capture_promotion_operation(jsonb)','public.authorize_capture_promotion_action(jsonb,text)',
        'public.retire_capture_promotion_operation(jsonb)','public.claim_capture_promotion_retirements(uuid,integer)',
        'public.observe_capture_promotion_retirement(uuid,uuid,boolean,text)']) f;
SELECT extensions.ok(NOT has_function_privilege(r,f,'EXECUTE'),r||' denied private owner')
    FROM unnest(ARRAY['anon','authenticated','service_role']) r CROSS JOIN unnest(ARRAY[
        'internal.parse_capture_promotion_binding(jsonb)',
        'internal.capture_promotion_binding(internal.capture_promotion_operations)',
        'internal.lock_capture_promotion_source(internal.capture_promotion_operations)',
        'internal.retire_capture_promotions_for_source()']) f;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
CREATE FUNCTION pg_temp.new_capture_promotion(mime TEXT DEFAULT 'image/webp',size INTEGER DEFAULT 100) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE owner UUID:=gen_random_uuid(); scan UUID:=gen_random_uuid(); asset UUID:=gen_random_uuid(); session UUID:=gen_random_uuid(); op UUID:=gen_random_uuid(); key TEXT;
BEGIN
    key:='staging/'||owner::TEXT||'/fixture';
    INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
        VALUES(owner,'authenticated','authenticated','{}','{}',now(),now());
    INSERT INTO public.scan_media_assets(id,user_id,client_scan_id,upload_session_id,kind,role,status,source,storage_key,order_index,content_type,byte_size,checksum_sha256)
        VALUES(asset,owner,scan,session,CASE WHEN mime LIKE 'image/%' THEN 'image' WHEN mime LIKE 'audio/%' THEN 'audio' ELSE 'video' END,
            CASE WHEN mime LIKE 'image/%' THEN 'display' WHEN mime LIKE 'audio/%' THEN 'audio' ELSE 'playback' END,
            'staged','capture_upload',key,0,mime,size,repeat('c',64));
    PERFORM public.register_capture_upload_capabilities(owner,repeat('a',64),jsonb_build_array(jsonb_build_object(
        'object_key',key,'expires_at',clock_timestamp()+interval '1 hour','scan_id',scan,'asset_id',asset,'session_id',session)));
    RETURN jsonb_build_object('operationId',op,'ownerId',owner,'scanId',scan,'assetId',asset,'sessionId',session,
        'backendSHA256',repeat('a',64),'sourceKey',key,'destinationKey','public_uploads/free/'||owner::TEXT||'/capture-promotion-'||op::TEXT,
        'contentType',mime,'byteCount',size,'sha256',repeat('c',64));
END;
$$;
CREATE TEMP TABLE promotion_fixture(name TEXT PRIMARY KEY,b JSONB,token UUID DEFAULT gen_random_uuid());
INSERT INTO promotion_fixture(name,b) VALUES('main',pg_temp.new_capture_promotion()),('merge',pg_temp.new_capture_promotion()),
    ('account',pg_temp.new_capture_promotion()),('abandon',pg_temp.new_capture_promotion()),('detached',pg_temp.new_capture_promotion()),
    ('audio',pg_temp.new_capture_promotion('audio/wav',2700000)),('video',pg_temp.new_capture_promotion('video/mp4',12582912));
GRANT SELECT ON promotion_fixture TO service_role;
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(b,'read_source') FROM promotion_fixture WHERE name='main'$$,
    '55000','capture_promotion_unavailable','unregistered operation cannot authorize source read');
SET LOCAL ROLE service_role;
SELECT extensions.ok(public.register_capture_promotion_operation(b),'service registers exact pre-scan '||name) FROM promotion_fixture;
SELECT extensions.ok(public.register_capture_promotion_operation(b),'exact registration replay '||name) FROM promotion_fixture;
RESET ROLE;
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.capture_promotion_operations),7,'registration retries create no replacements');
SELECT extensions.throws_ok($$SELECT public.register_capture_promotion_operation(b||'{"unexpected":true}') FROM promotion_fixture WHERE name='main'$$,
    '22023','capture_promotion_invalid','unknown field rejected');
SELECT extensions.throws_ok($$SELECT public.register_capture_promotion_operation(b||'{"byteCount":null}') FROM promotion_fixture WHERE name='main'$$,
    '22023','capture_promotion_invalid','null size rejected');
SELECT extensions.throws_ok($$SELECT public.register_capture_promotion_operation(b||'{"ownerId":null}') FROM promotion_fixture WHERE name='main'$$,
    '22023','capture_promotion_invalid','null owner rejected');
SELECT extensions.throws_ok($$SELECT public.register_capture_promotion_operation(b||'{"byteCount":12582913}') FROM promotion_fixture WHERE name='video'$$,
    '22023','capture_promotion_invalid','oversize video rejected');
SELECT extensions.throws_ok($$SELECT public.register_capture_promotion_operation(b||'{"destinationKey":"public_uploads/free/foreign"}') FROM promotion_fixture WHERE name='main'$$,
    '22023','capture_promotion_invalid','arbitrary destination rejected');
SELECT extensions.throws_ok($$SELECT public.register_capture_promotion_operation(b||jsonb_build_object('sha256',repeat('d',64))) FROM promotion_fixture WHERE name='main'$$,
    '55000','capture_promotion_unavailable','asset content identity mismatch rejected');
SELECT extensions.throws_ok($$SELECT public.register_capture_promotion_operation(b||jsonb_build_object('destinationKey',replace(b->>'destinationKey','/free/','/pro/'))) FROM promotion_fixture WHERE name='main'$$,
    '55000','capture_promotion_conflict','same operation cannot change target tier');
SELECT extensions.throws_ok($$SELECT public.register_capture_promotion_operation(b||jsonb_build_object('operationId',n,'destinationKey','public_uploads/free/'||(b->>'ownerId')||'/capture-promotion-'||n::TEXT)) FROM promotion_fixture CROSS JOIN (SELECT gen_random_uuid() n) x WHERE name='main'$$,
    '23505',NULL,'replacement operation cannot rebind the same source');
SELECT extensions.ok(NOT public.authorize_capture_promotion_action(b,'read_destination'),'destination read denied before write authorization') FROM promotion_fixture WHERE name='main';
SELECT extensions.ok(public.authorize_capture_promotion_action(b,'read_source'),'source read before write') FROM promotion_fixture WHERE name='main';
SELECT extensions.ok(public.authorize_capture_promotion_action(b,'write_destination'),'one durable PUT authorization') FROM promotion_fixture WHERE name='main';
SELECT extensions.ok(NOT public.authorize_capture_promotion_action(b,'write_destination'),'lost authorization cannot be retried') FROM promotion_fixture WHERE name='main';
SELECT extensions.ok(NOT public.authorize_capture_promotion_action(b,'read_source'),'transfer cannot restart after issued PUT authority') FROM promotion_fixture WHERE name='main';
SELECT extensions.ok(public.authorize_capture_promotion_action(b,'read_destination'),'fresh exact recovery read allowed') FROM promotion_fixture WHERE name='main';
SELECT extensions.ok(public.register_capture_promotion_operation(b),'registration retry does not reset consumed authority') FROM promotion_fixture WHERE name='main';
SELECT extensions.ok(NOT public.authorize_capture_promotion_action(b,'write_destination'),'registration retry preserves consumed authority') FROM promotion_fixture WHERE name='main';
UPDATE public.scan_media_assets SET byte_size=101 WHERE id=(SELECT (b->>'assetId')::UUID FROM promotion_fixture WHERE name='main');
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(b,'read_destination') FROM promotion_fixture WHERE name='main'$$,
    '55000','capture_promotion_unavailable','fresh metadata drift blocks every action');
UPDATE public.scan_media_assets SET byte_size=100 WHERE id=(SELECT (b->>'assetId')::UUID FROM promotion_fixture WHERE name='main');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.claim_capture_promotion_retirements(gen_random_uuid(),25)),0,'active destination cannot be erased');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) SELECT (b->>'scanId')::UUID,(b->>'ownerId')::UUID FROM promotion_fixture WHERE name='main';
SELECT extensions.ok(o.retired_at IS NOT NULL AND s.retired_at IS NOT NULL,'tombstone retires source and independent target')
    FROM promotion_fixture f JOIN internal.capture_promotion_operations o ON o.operation_id=(f.b->>'operationId')::UUID
    JOIN internal.capture_object_authorities s ON s.backend_sha256=o.backend_sha256 AND s.object_key=o.source_key WHERE f.name='main';
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(b,'read_destination') FROM promotion_fixture WHERE name='main'$$,
    '55000','capture_promotion_unavailable','retirement blocks recovery reads');
DELETE FROM public.scan_media_assets WHERE id=(SELECT (b->>'assetId')::UUID FROM promotion_fixture WHERE name='main');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.claim_capture_promotion_retirements((SELECT token FROM promotion_fixture WHERE name='main'),25)),1,'target survives asset deletion');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.claim_capture_promotion_retirements(gen_random_uuid(),25)),0,'second claim skips lease');
SELECT extensions.ok(NOT public.observe_capture_promotion_retirement((b->>'operationId')::UUID,gen_random_uuid(),true,NULL),'wrong target claim denied') FROM promotion_fixture WHERE name='main';
SELECT extensions.ok(public.observe_capture_promotion_retirement((b->>'operationId')::UUID,token,true,NULL),'exact target absence acknowledged') FROM promotion_fixture WHERE name='main';
SELECT extensions.ok(o.retired_at IS NOT NULL AND o.observed_absent_at IS NOT NULL AND o.next_check_at>clock_timestamp()
    AND s.observed_absent_at IS NULL,'target absence never acknowledges source absence')
    FROM promotion_fixture f JOIN internal.capture_promotion_operations o ON o.operation_id=(f.b->>'operationId')::UUID
    JOIN internal.capture_object_authorities s ON s.backend_sha256=o.backend_sha256 AND s.object_key=o.source_key WHERE f.name='main';
UPDATE internal.capture_promotion_operations SET next_check_at=clock_timestamp()-interval '1 second' WHERE operation_id=(SELECT (b->>'operationId')::UUID FROM promotion_fixture WHERE name='main');
UPDATE promotion_fixture SET token=gen_random_uuid() WHERE name='main';
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.claim_capture_promotion_retirements((SELECT token FROM promotion_fixture WHERE name='main'),25)),1,'observed absence preserves late-write recheck');
-- Each claim invocation must mint a fresh token. An old generation cannot
-- acknowledge absence after lease expiry and reacquisition with the new token.
CREATE TEMP TABLE expired_promotion_token AS SELECT token FROM promotion_fixture WHERE name='main';
UPDATE internal.capture_promotion_operations SET lease_expires_at=clock_timestamp()-interval '1 second',next_check_at=clock_timestamp()-interval '1 second'
    WHERE operation_id=(SELECT (b->>'operationId')::UUID FROM promotion_fixture WHERE name='main');
SELECT extensions.ok(NOT public.observe_capture_promotion_retirement((b->>'operationId')::UUID,token,true,NULL),'expired target lease cannot acknowledge absence') FROM promotion_fixture WHERE name='main';
UPDATE promotion_fixture SET token=gen_random_uuid() WHERE name='main';
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.claim_capture_promotion_retirements((SELECT token FROM promotion_fixture WHERE name='main'),25)),1,'fresh token reacquires expired target lease');
SELECT extensions.ok(NOT public.observe_capture_promotion_retirement((b->>'operationId')::UUID,(SELECT token FROM expired_promotion_token),true,NULL),'stale generation cannot observe after reacquisition') FROM promotion_fixture WHERE name='main';
SELECT extensions.ok(public.observe_capture_promotion_retirement((b->>'operationId')::UUID,token,false,'object_io_failed'),'unknown outcome remains recoverable') FROM promotion_fixture WHERE name='main';
SELECT extensions.ok(public.retire_capture_promotion_operation(b),'explicit target abandonment') FROM promotion_fixture WHERE name='abandon';
SELECT extensions.ok(o.retired_at IS NOT NULL AND s.retired_at IS NULL,'target abandonment does not retire original upload')
    FROM promotion_fixture f JOIN internal.capture_promotion_operations o ON o.operation_id=(f.b->>'operationId')::UUID
    JOIN internal.capture_object_authorities s ON s.backend_sha256=o.backend_sha256 AND s.object_key=o.source_key WHERE f.name='abandon';
SELECT extensions.ok(public.authorize_capture_promotion_action(b,'write_destination'),'detached fixture issued target write') FROM promotion_fixture WHERE name='detached';
DELETE FROM public.scan_media_assets WHERE id=(SELECT (b->>'assetId')::UUID FROM promotion_fixture WHERE name='detached');
SELECT extensions.ok(retired_at IS NULL,'asset deletion alone is not target-retirement authority') FROM internal.capture_promotion_operations
    WHERE operation_id=(SELECT (b->>'operationId')::UUID FROM promotion_fixture WHERE name='detached');
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(b,'read_destination') FROM promotion_fixture WHERE name='detached'$$,
    '55000','capture_promotion_unavailable','missing asset prevents further I/O authorization');
SELECT extensions.ok(public.retire_capture_promotion_operation(b),'explicit abandonment still works after asset deletion') FROM promotion_fixture WHERE name='detached';
SELECT extensions.ok(retired_at IS NOT NULL AND write_authorized_at IS NOT NULL,'abandonment preserves issued-write obligation') FROM internal.capture_promotion_operations
    WHERE operation_id=(SELECT (b->>'operationId')::UUID FROM promotion_fixture WHERE name='detached');
SELECT * FROM public.request_account_deletion((SELECT (b->>'ownerId')::UUID FROM promotion_fixture WHERE name='account'));
SELECT extensions.ok(retired_at IS NOT NULL,'account intake retires target') FROM internal.capture_promotion_operations
    WHERE operation_id=(SELECT (b->>'operationId')::UUID FROM promotion_fixture WHERE name='account');
DELETE FROM public.users WHERE id=(SELECT (b->>'ownerId')::UUID FROM promotion_fixture WHERE name='account');
SELECT extensions.ok(retired_at IS NOT NULL,'account cascade retains target') FROM internal.capture_promotion_operations
    WHERE operation_id=(SELECT (b->>'operationId')::UUID FROM promotion_fixture WHERE name='account');
CREATE TEMP TABLE promotion_merge_target AS SELECT gen_random_uuid() id;
INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    SELECT id,'authenticated','authenticated','{}','{}',now(),now() FROM promotion_merge_target;
SELECT extensions.lives_ok($$SELECT internal.perform_ghost_profile_merge((b->>'ownerId')::UUID,(SELECT id FROM promotion_merge_target)) FROM promotion_fixture WHERE name='merge'$$,'actual merge preserves metadata and retires both objects');
SELECT extensions.ok(o.retired_at IS NOT NULL AND s.retired_at IS NOT NULL AND m.user_id=t.id AND o.owner_id<>t.id,'merge never transfers old promotion authority')
    FROM promotion_fixture f JOIN internal.capture_promotion_operations o ON o.operation_id=(f.b->>'operationId')::UUID
    JOIN internal.capture_object_authorities s ON s.backend_sha256=o.backend_sha256 AND s.object_key=o.source_key
    JOIN public.scan_media_assets m ON m.id=o.asset_id CROSS JOIN promotion_merge_target t WHERE f.name='merge';
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(b,'write_destination') FROM promotion_fixture WHERE name='merge'$$,
    '55000','capture_promotion_unavailable','merged old owner cannot dispatch');
SET LOCAL ROLE anon;
SELECT extensions.throws_ok($$SELECT public.register_capture_promotion_operation('{}')$$,'42501',NULL,'anon runtime invocation denied');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action('{}','write_destination')$$,'42501',NULL,'authenticated runtime invocation denied');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
