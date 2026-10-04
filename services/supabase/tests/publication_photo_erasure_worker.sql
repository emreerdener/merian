\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SELECT extensions.ok(NOT (SELECT publication_erasure_enabled FROM internal.observation_history_rollout),'external erasure activation defaults off');
SELECT extensions.throws_ok('SELECT public.claim_publication_photo_erasure(NULL)','55000','analysis_history_unavailable','closed cleanup gate prevents claiming');
UPDATE internal.observation_history_rollout SET publication_erasure_enabled=TRUE;
SELECT extensions.ok(has_function_privilege('service_role','public.claim_publication_photo_erasure(uuid)','EXECUTE'),'service worker may claim');
SELECT extensions.ok(has_function_privilege('service_role','public.finish_publication_photo_erasure(uuid,uuid,boolean)','EXECUTE'),'service worker may acknowledge');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated']) r CROSS JOIN unnest(ARRAY['public.claim_publication_photo_erasure(uuid)','public.finish_publication_photo_erasure(uuid,uuid,boolean)']) f WHERE has_function_privilege(r,f,'EXECUTE')),'users cannot invoke erasure');
SELECT extensions.ok(NOT has_function_privilege('service_role','internal.claim_publication_photo_erasure(uuid)','EXECUTE'),'private implementation stays ungranted');
INSERT INTO internal.publication_photo_objects(object_id,available_at,bound_at,revoked_at) VALUES
 ('00000000-0000-4000-8000-00000000fe01',clock_timestamp()+INTERVAL '1 hour',NULL,NULL),
 ('00000000-0000-4000-8000-00000000fe02',clock_timestamp()-INTERVAL '1 minute',NULL,NULL),
 ('00000000-0000-4000-8000-00000000fe03',clock_timestamp()-INTERVAL '1 minute',clock_timestamp(),NULL),
 ('00000000-0000-4000-8000-00000000fe04',clock_timestamp()-INTERVAL '1 minute',clock_timestamp(),clock_timestamp());
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SET LOCAL ROLE service_role;
SELECT extensions.ok(public.claim_publication_photo_erasure('00000000-0000-4000-8000-00000000fe01') IS NULL,'target cannot erase live staged upload');
SELECT extensions.ok(public.claim_publication_photo_erasure('00000000-0000-4000-8000-00000000fe03') IS NULL,'target cannot erase valid bound publication');
SELECT extensions.ok(public.claim_publication_photo_erasure('00000000-0000-4000-8000-00000000fe99') IS NULL,'unknown target never claims another object');
SELECT extensions.is(public.claim_publication_photo_erasure('00000000-0000-4000-8000-00000000fe04')->>'object_id','00000000-0000-4000-8000-00000000fe04','targeted revoked object survives without owner/history');
SELECT extensions.ok(public.claim_publication_photo_erasure('00000000-0000-4000-8000-00000000fe04') IS NULL,'live claim cannot be stolen');
SELECT extensions.ok(NOT public.finish_publication_photo_erasure('00000000-0000-4000-8000-00000000fe04',gen_random_uuid(),TRUE),'wrong claim cannot acknowledge');
RESET ROLE;
CREATE TEMP TABLE erasure_claim AS SELECT object_id,claim_token FROM internal.publication_photo_objects WHERE object_id='00000000-0000-4000-8000-00000000fe04';
GRANT SELECT ON erasure_claim TO service_role;
SET LOCAL ROLE service_role;
SELECT extensions.ok(public.finish_publication_photo_erasure(object_id,claim_token,FALSE),'failed write releases retry claim without erasure') FROM erasure_claim;
RESET ROLE;
TRUNCATE erasure_claim;
INSERT INTO erasure_claim SELECT (r->>'object_id')::UUID,(r->>'claim_token')::UUID FROM (SELECT public.claim_publication_photo_erasure('00000000-0000-4000-8000-00000000fe04') r) s;
UPDATE internal.observation_history_rollout SET publication_erasure_enabled=FALSE;
SET LOCAL ROLE service_role;
SELECT extensions.ok(public.finish_publication_photo_erasure(object_id,claim_token,TRUE),'verified marker completes erasure') FROM erasure_claim;
RESET ROLE;
UPDATE internal.observation_history_rollout SET publication_erasure_enabled=TRUE;
SET LOCAL ROLE service_role;
SELECT extensions.ok(public.claim_publication_photo_erasure('00000000-0000-4000-8000-00000000fe04') IS NULL,'completed marker never reclaims');
SELECT extensions.is(public.claim_publication_photo_erasure()->>'object_id','00000000-0000-4000-8000-00000000fe02','untargeted worker claims due unbound obligation only');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.claim_publication_photo_erasure(NULL)$$,'42501','permission denied for function claim_publication_photo_erasure','actual authenticated caller denied');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
