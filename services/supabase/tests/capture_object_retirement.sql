BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SELECT extensions.ok(relrowsecurity, 'exact-key registry has RLS') FROM pg_catalog.pg_class
    WHERE oid = 'internal.capture_object_authorities'::REGCLASS;
SELECT extensions.ok(NOT has_table_privilege(role_name, 'internal.capture_object_authorities', 'SELECT,INSERT,UPDATE,DELETE'),
    role_name || ' has no direct registry access') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.ok(NOT has_function_privilege(role_name, routine, 'EXECUTE'), role_name || ' denied ' || routine)
    FROM unnest(ARRAY['anon','authenticated']) role_name CROSS JOIN unnest(ARRAY[
        'public.register_capture_upload_capabilities(uuid,text,jsonb)',
        'public.claim_capture_object_retirements(uuid,integer)',
        'public.capture_object_retirement_health()',
        'public.observe_capture_object_retirement(text,text,uuid,boolean,text)']) routine;

CREATE TEMP TABLE capture_fixture AS SELECT gen_random_uuid() owner, gen_random_uuid() scan,
    gen_random_uuid() asset, gen_random_uuid() session, gen_random_uuid() token, repeat('a',64) backend;
INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    SELECT owner,'authenticated','authenticated','{}','{}',now(),now() FROM capture_fixture;
INSERT INTO public.scan_media_assets(id,user_id,client_scan_id,upload_session_id,kind,role,status,source,storage_key,order_index,content_type,byte_size)
    SELECT asset,owner,scan,session,'image','display','staged','capture_upload','staging/'||owner::TEXT||'/fixture.webp',0,'image/webp',100 FROM capture_fixture;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
CREATE FUNCTION pg_temp.capture_registration(expiry INTERVAL DEFAULT interval '1 hour') RETURNS BOOLEAN LANGUAGE SQL AS $$
    SELECT public.register_capture_upload_capabilities(owner,backend,jsonb_build_array(jsonb_build_object(
        'object_key','staging/'||owner::TEXT||'/fixture.webp','expires_at',clock_timestamp()+expiry,
        'scan_id',scan,'asset_id',asset,'session_id',session))) FROM capture_fixture;
$$;
SELECT extensions.ok(pg_temp.capture_registration(), 'exact source capability persisted');
SELECT extensions.ok(pg_temp.capture_registration(interval '2 hours'), 'retry may extend outstanding PUT expiry');
SELECT extensions.ok(pg_temp.capture_registration(interval '1 hour'), 'shorter retry remains idempotent');
SELECT extensions.ok(issued_until > clock_timestamp()+interval '119 minutes', 'shorter retry cannot erase longer capability')
    FROM internal.capture_object_authorities WHERE owner_id=(SELECT owner FROM capture_fixture);
SELECT extensions.throws_ok($$SELECT pg_temp.capture_registration(interval '-1 hour')$$,'22023','capture_capability_invalid','expired issuance rejected');
SELECT extensions.throws_ok($$SELECT pg_temp.capture_registration(interval '25 hours')$$,'22023','capture_capability_invalid','unbounded issuance rejected');
SELECT extensions.throws_ok($$SELECT public.register_capture_upload_capabilities(owner,backend,'[]') FROM capture_fixture$$,
    '22023','capture_capability_invalid','empty batch rejected');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.claim_capture_object_retirements((SELECT token FROM capture_fixture),25)),
    0, 'active objects cannot be claimed for deletion');
SELECT extensions.throws_ok($$UPDATE public.scan_media_assets SET client_scan_id=gen_random_uuid() WHERE id=(SELECT asset FROM capture_fixture)$$,
    '55000','capture_object_retired_or_rebound','active exact identity cannot be rebound');

SELECT extensions.throws_ok($$UPDATE public.scan_media_assets SET source='manual' WHERE id=(SELECT asset FROM capture_fixture)$$,
    '55000','capture_object_retired_or_rebound','source reclassification cannot evade exact authority');
SELECT extensions.throws_ok($$UPDATE public.scan_media_assets SET storage_key='staging/'||user_id::TEXT||'/other.webp'
    WHERE id=(SELECT asset FROM capture_fixture)$$,'55000','capture_object_retired_or_rebound',
    'registered asset cannot move away from its issued key');
SELECT extensions.throws_ok($$INSERT INTO public.scan_media_assets(id,user_id,client_scan_id,upload_session_id,kind,role,status,source,storage_key,order_index)
    SELECT gen_random_uuid(),owner,scan,session,'image','display','staged','manual','staging/'||owner::TEXT||'/fixture.webp',1 FROM capture_fixture$$,
    '55000','capture_object_retired_or_rebound','manual source cannot reuse a registered key');

-- No scan row is needed: permanent deletion authority still retires the source.
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) SELECT scan,owner FROM capture_fixture;
SELECT extensions.ok(retired_at IS NOT NULL, 'scan tombstone retires capability before cascade') FROM internal.capture_object_authorities
    WHERE owner_id=(SELECT owner FROM capture_fixture);
SELECT extensions.throws_ok($$SELECT pg_temp.capture_registration()$$,'55000','scan_generation_deleted','deleted scan cannot renew signing');
DELETE FROM public.scan_media_assets WHERE id=(SELECT asset FROM capture_fixture);
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.claim_capture_object_retirements((SELECT token FROM capture_fixture),25)),
    1, 'retirement survives missing asset and scan rows');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.claim_capture_object_retirements(gen_random_uuid(),25)),
    0, 'concurrent lease cannot claim held work');
SELECT extensions.is(public.observe_capture_object_retirement(backend,'staging/'||owner::TEXT||'/fixture.webp',gen_random_uuid(),true,NULL),
    false,'wrong claim cannot acknowledge absence') FROM capture_fixture;
SELECT extensions.ok(public.observe_capture_object_retirement(backend,'staging/'||owner::TEXT||'/fixture.webp',token,true,NULL),
    'matching claim records a point-in-time observation') FROM capture_fixture;
SELECT extensions.ok(retired_at IS NOT NULL AND observed_absent_at IS NOT NULL AND next_check_at > issued_until
    AND claim_token IS NULL,'absence preserves fence and schedules post-expiry recheck') FROM internal.capture_object_authorities
    WHERE owner_id=(SELECT owner FROM capture_fixture);
SELECT extensions.throws_ok($$INSERT INTO public.scan_media_assets(id,user_id,client_scan_id,upload_session_id,kind,role,status,source,storage_key,order_index)
    SELECT gen_random_uuid(),owner,gen_random_uuid(),gen_random_uuid(),'image','display','staged','capture_upload','staging/'||owner::TEXT||'/fixture.webp',0 FROM capture_fixture$$,
    '55000','capture_object_retired_or_rebound','retired key cannot be reused by another scan');

UPDATE internal.capture_object_authorities SET next_check_at=clock_timestamp()-interval '1 second' WHERE owner_id=(SELECT owner FROM capture_fixture);
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.claim_capture_object_retirements((SELECT token FROM capture_fixture),25)),
    1, 'previous absence never removes late-write recovery work');
SELECT extensions.ok(public.observe_capture_object_retirement(backend,'staging/'||owner::TEXT||'/fixture.webp',token,false,'object_io_failed'),
    'unknown deletion outcome remains retryable') FROM capture_fixture;
SELECT extensions.ok(last_error_code='object_io_failed' AND next_check_at > clock_timestamp(), 'I/O failure retains bounded retry')
    FROM internal.capture_object_authorities WHERE owner_id=(SELECT owner FROM capture_fixture);
SELECT extensions.is((public.capture_object_retirement_health()->>'unresolved_count')::INTEGER, 1,
    'health counts unresolved obligations after absence');
SELECT extensions.is((public.capture_object_retirement_health()->>'error_count')::INTEGER, 1,
    'health exposes retry errors without object identities');
SELECT extensions.ok(NOT public.capture_object_retirement_health() ?| ARRAY['owner_id','object_key','scan_id'],
    'health omits private identities');
DELETE FROM public.users WHERE id=(SELECT owner FROM capture_fixture);
DELETE FROM auth.users WHERE id=(SELECT owner FROM capture_fixture);
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.capture_object_authorities WHERE owner_id=(SELECT owner FROM capture_fixture)),
    1, 'account cascade cannot erase outstanding exact-key obligation');
SELECT extensions.throws_ok($$SELECT pg_temp.capture_registration()$$,'55000','capture_owner_unavailable','deleted owner cannot issue again');
-- Exercise the actual schema-aware reparent owner, not a trigger-only bypass.
CREATE TEMP TABLE capture_merge_fixture AS SELECT gen_random_uuid() source_owner, gen_random_uuid() target_owner,
    gen_random_uuid() scan, gen_random_uuid() asset, gen_random_uuid() session;
INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    SELECT id,'authenticated','authenticated','{}','{}',now(),now()
    FROM capture_merge_fixture CROSS JOIN LATERAL unnest(ARRAY[source_owner,target_owner]) id;
INSERT INTO public.scan_media_assets(id,user_id,client_scan_id,upload_session_id,kind,role,status,source,storage_key,order_index)
    SELECT asset,source_owner,scan,session,'image','display','staged','capture_upload',
        'staging/'||source_owner::TEXT||'/merge.webp',0 FROM capture_merge_fixture;
SELECT extensions.ok(public.register_capture_upload_capabilities(source_owner,repeat('b',64),jsonb_build_array(jsonb_build_object(
    'object_key','staging/'||source_owner::TEXT||'/merge.webp','expires_at',clock_timestamp()+interval '1 hour',
    'scan_id',scan,'asset_id',asset,'session_id',session))), 'merge fixture has an issued exact capability') FROM capture_merge_fixture;
SELECT extensions.throws_ok($$UPDATE public.scan_media_assets SET user_id=(SELECT target_owner FROM capture_merge_fixture)
    WHERE id=(SELECT asset FROM capture_merge_fixture)$$,'55000','capture_object_retired_or_rebound',
    'unmarked metadata owner reassignment is rejected');
-- Use the complete private orchestrator, including conflict handlers and source deletion.
SELECT extensions.lives_ok($$SELECT internal.perform_ghost_profile_merge(source_owner,target_owner) FROM capture_merge_fixture$$,
    'existing schema-aware merge may reparent active staging metadata');
SELECT extensions.ok(m.user_id=f.target_owner AND a.owner_id=f.source_owner AND a.retired_at IS NOT NULL,
    'metadata moves while old-owner authority is permanently retired')
    FROM capture_merge_fixture f JOIN public.scan_media_assets m ON m.id=f.asset
    JOIN internal.capture_object_authorities a ON a.asset_id=f.asset;
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.capture_reparent_transactions),0,'merge leaves no authority marker');
SELECT extensions.ok(NOT has_table_privilege(role_name,'internal.capture_reparent_transactions','SELECT,INSERT,UPDATE,DELETE'),
    role_name||' cannot mint merge markers') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.ok(NOT has_function_privilege(role_name,routine,'EXECUTE'),role_name||' cannot invoke private reparent owner')
    FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY[
        'internal.reparent_ghost_user_foreign_keys(uuid,uuid)',
        'internal.reparent_ghost_user_foreign_keys_capture_base(uuid,uuid)']) routine;
SELECT extensions.throws_ok($$UPDATE public.scan_media_assets SET user_id=(SELECT source_owner FROM capture_merge_fixture)
    WHERE id=(SELECT asset FROM capture_merge_fixture)$$,'55000','capture_object_retired_or_rebound',
    'merged retired key cannot be moved back');
SELECT * FROM extensions.finish();
ROLLBACK;
