-- Storage union only. No CPM admission, funding, verifier or activation claim.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();

SELECT extensions.ok(internal.initial_admission_variant_fields_valid(
    'server_prepared_v3',array_fill('legacy'::TEXT,ARRAY[n]),NULL,NULL,NULL,NULL,NULL),
    'legacy stage/receipt shape '||n) FROM generate_series(6,7) n;
SELECT extensions.ok(NOT internal.initial_admission_variant_fields_valid(
    variant,array_fill('legacy'::TEXT,ARRAY[6]),NULL,NULL,NULL,NULL,NULL),
    'unknown or missing variant rejects') FROM (VALUES(NULL::TEXT),(''),('cpm')) t(variant);
SELECT extensions.ok(NOT internal.initial_admission_variant_fields_valid(
    'server_prepared_v3',legacy,NULL,NULL,NULL,NULL,NULL),
    'missing legacy proof cannot pass SQL NULL checks')
FROM (VALUES(NULL::TEXT[]),(ARRAY[]::TEXT[]),(array_fill('x'::TEXT,ARRAY[5])),
    (ARRAY['x','x','x','x','x',NULL]::TEXT[]),
    (ARRAY[['x','x','x'],['x','x','x']]::TEXT[])) t(legacy);

CREATE FUNCTION pg_temp.shape(p JSONB) RETURNS BOOLEAN LANGUAGE SQL AS $$
 SELECT internal.initial_admission_variant_fields_valid(
    p->>'variant',ARRAY(SELECT jsonb_array_elements_text(p->'legacy')),
    p->>'verification',p->>'digest',p->>'roles',p->'capacity',
    (p->>'expires')::TIMESTAMPTZ);
$$;
CREATE TEMP TABLE shape_fixture AS SELECT jsonb_build_object(
    'variant','client_prepared_photo_v1','legacy',array_fill(NULL::TEXT,ARRAY[7]),
    'verification','{}','digest',repeat('a',64),'roles','{}',
    'capacity',jsonb_build_object('state','pending'),'expires','2030-01-01T00:00:00Z') v;
SELECT extensions.ok(pg_temp.shape(v),'complete CPM storage shape only, not a proof') FROM shape_fixture;
SELECT extensions.ok(NOT pg_temp.shape(v-key),'each CPM field is mandatory: '||key)
FROM shape_fixture CROSS JOIN unnest(ARRAY['variant','verification','digest','roles','capacity','expires']) key;
SELECT extensions.ok(NOT pg_temp.shape(v||jsonb_build_object(key,changed)),label)
FROM shape_fixture CROSS JOIN (VALUES
    ('legacy',to_jsonb(ARRAY['fake','fake','fake','fake','fake','fake','fake']), 'fabricated legacy proofs reject'),
    ('verification',to_jsonb(''::TEXT),'empty verification rejects'),
    ('verification',to_jsonb(repeat('x',65537)),'verification byte cap'),
    ('roles',to_jsonb(repeat('é',32769)),'retained roles count UTF-8 bytes'),
    ('digest',to_jsonb(repeat('A',64)),'noncanonical digest rejects'),
    ('capacity','[]'::JSONB,'nonobject capacity rejects'),
    ('capacity',jsonb_build_object('value',repeat('x',16384)),'capacity encoded bytes cap'),
    ('expires',to_jsonb('infinity'::TEXT),'infinite deadline rejects'),
    ('expires',to_jsonb('-infinity'::TEXT),'negative infinite deadline rejects'),
    ('variant',to_jsonb('server_prepared_v3'::TEXT),'mixed legacy/CPM shape rejects')
) t(key,changed,label);

SELECT extensions.ok(NOT has_function_privilege(role_name,
    'internal.initial_admission_variant_fields_valid(text,text[],text,text,text,jsonb,timestamptz)','EXECUTE'),
    role_name||' cannot call private storage validation')
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.ok(NOT a.attnotnull,'closed variant shape owns legacy/CPM required fields: '||c.relname||'.'||a.attname)
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_attribute a ON a.attrelid=c.oid
WHERE n.nspname='internal' AND c.relname IN
    ('initial_preparation_admission_staging','initial_preparation_admission_receipts')
    AND a.attname IN ('outcome','installation','protocol','destination','mapping','media_binding');
SELECT extensions.ok(NOT initial_analysis_lifecycle_enabled,'ordinary activation remains disabled')
FROM internal.initial_analysis_rollout;
SELECT * FROM extensions.finish();
ROLLBACK;
