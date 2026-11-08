\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();

-- Values are synthetic; no active configuration or policy row is changed.
CREATE FUNCTION pg_temp.check_admission_policy(overrides JSONB DEFAULT '{}'::JSONB)
RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE policy internal.ai_quota_policies;
BEGIN
    policy := jsonb_populate_record(NULL::internal.ai_quota_policies,
        jsonb_build_object('operation','scan_identification','effective_plan','free',
            'model','gemini-2.5-flash','allowed',TRUE,'enabled',TRUE,'policy_version',1,
            'daily_bucket','synthetic_daily','daily_limit',5,
            'user_rate_bucket','synthetic_user','user_window_seconds',60,'user_window_limit',5,
            'ip_rate_bucket','synthetic_ip','ip_window_seconds',60,'ip_window_limit',5,
            'created_at','2026-10-12T00:00:00Z','updated_at','2026-10-12T00:00:00Z') || overrides);
    PERFORM internal.assert_initial_admission_policy(policy);
END;
$$;
SELECT extensions.lives_ok('SELECT pg_temp.check_admission_policy()', 'bounded policy is eligible');
SELECT extensions.lives_ok($q$SELECT pg_temp.check_admission_policy('{"daily_bucket":null,"daily_limit":null}')$q$, 'unlimited daily branch is eligible');
SELECT extensions.lives_ok(format('SELECT pg_temp.check_admission_policy(%L::JSONB)', jsonb_build_object('effective_plan',plan)), 'eligible plan ' || plan)
FROM unnest(ARRAY['free','pro_paid','pro_trial','pro_complimentary']) plan;
SELECT extensions.lives_ok(format('SELECT pg_temp.check_admission_policy(%L::JSONB)', jsonb_build_object(key,bucket)), 'raw byte boundary accepted: ' || key || ' / ' || name)
FROM unnest(ARRAY['daily_bucket','user_rate_bucket','ip_rate_bucket']) key
CROSS JOIN (VALUES ('ascii',repeat('a',1024)),('nonBMP',repeat(chr(128512),256)),('escaped',repeat(chr(1),1024)),('Unicode whitespace',chr(160)),('ASCII tab',chr(9))) b(name,bucket);
SELECT extensions.throws_ok(format('SELECT pg_temp.check_admission_policy(%L::JSONB)', jsonb_build_object(key,bucket)), '55000','initial_analysis_assignment_changed', 'raw byte or blank boundary denied: ' || key || ' / ' || name)
FROM unnest(ARRAY['daily_bucket','user_rate_bucket','ip_rate_bucket']) key
CROSS JOIN (VALUES ('ascii overflow',repeat('a',1025)),('nonBMP overflow',repeat(chr(128512),256)||'a'),('empty',''),('ASCII spaces','   ')) b(name,bucket);
SELECT extensions.throws_ok(format('SELECT pg_temp.check_admission_policy(%L::JSONB)', override), '55000','initial_analysis_assignment_changed', 'ineligible closed policy: ' || name)
FROM (VALUES
 ('missing daily bucket','{"daily_bucket":null}'::JSONB),
 ('missing daily limit','{"daily_limit":null}'::JSONB),
 ('zero daily limit','{"daily_limit":0}'::JSONB),
 ('negative daily limit','{"daily_limit":-1}'::JSONB),
 ('missing user bucket','{"user_rate_bucket":null}'::JSONB),
 ('missing user window','{"user_window_seconds":null}'::JSONB),
 ('zero user window','{"user_window_seconds":0}'::JSONB),
 ('oversized user window','{"user_window_seconds":3601}'::JSONB),
 ('missing user limit','{"user_window_limit":null}'::JSONB),
 ('zero user limit','{"user_window_limit":0}'::JSONB),
 ('missing IP bucket','{"ip_rate_bucket":null}'::JSONB),
 ('missing IP window','{"ip_window_seconds":null}'::JSONB),
 ('zero IP window','{"ip_window_seconds":0}'::JSONB),
 ('oversized IP window','{"ip_window_seconds":3601}'::JSONB),
 ('missing IP limit','{"ip_window_limit":null}'::JSONB),
 ('negative IP limit','{"ip_window_limit":-1}'::JSONB),
 ('disabled','{"enabled":false}'::JSONB),('unknown enabled','{"enabled":null}'::JSONB),
 ('disallowed','{"allowed":false}'::JSONB),('unknown allowed','{"allowed":null}'::JSONB),
 ('wrong operation','{"operation":"chat"}'::JSONB),('missing operation','{"operation":null}'::JSONB),
 ('wrong plan','{"effective_plan":"unknown"}'::JSONB),('missing plan','{"effective_plan":null}'::JSONB),
 ('missing model','{"model":null}'::JSONB),('blank model','{"model":"   "}'::JSONB),
 ('missing version','{"policy_version":null}'::JSONB),('zero version','{"policy_version":0}'::JSONB),
 ('unsafe version','{"policy_version":9007199254740992}'::JSONB)
) b(name,override);
SELECT extensions.lives_ok($q$SELECT pg_temp.check_admission_policy('{"policy_version":9007199254740991,"user_window_seconds":1,"ip_window_seconds":3600}')$q$, 'safe integer and window endpoints accepted');
SELECT extensions.lives_ok($q$SELECT pg_temp.check_admission_policy('{"policy_version":1,"daily_bucket":"different exact bucket","user_window_seconds":31,"ip_window_limit":7}')$q$, 'same-version bounded policy changes are eligible');
SELECT extensions.throws_ok('SELECT internal.assert_initial_admission_policy(NULL::internal.ai_quota_policies)', '55000','initial_analysis_assignment_changed','null composite never passes');
SELECT extensions.ok(NOT has_function_privilege(role,'internal.assert_initial_admission_policy(internal.ai_quota_policies)','EXECUTE'),'API role denied: ' || role)
FROM unnest(ARRAY['anon','authenticated','service_role']) role;
SELECT extensions.is((SELECT (length(body)-length(replace(body,'PERFORM internal.assert_initial_admission_policy(policy);','')))/length('PERFORM internal.assert_initial_admission_policy(policy);') FROM (SELECT pg_get_functiondef('internal.resolve_initial_media_preparation_assignment(uuid,uuid,text,text,boolean,jsonb)'::REGPROCEDURE) body) d),1,'qualified resolver invokes policy check exactly once');
SELECT extensions.ok((SELECT body LIKE E'%SELECT * INTO policy FROM internal.resolve_quota_policy(''scan_identification'',p_plan);\n PERFORM internal.assert_initial_admission_policy(policy);%' FROM (SELECT pg_get_functiondef('internal.resolve_initial_media_preparation_assignment(uuid,uuid,text,text,boolean,jsonb)'::REGPROCEDURE) body) d),'policy check immediately follows locked resolution');
SELECT * FROM extensions.finish();
ROLLBACK;
