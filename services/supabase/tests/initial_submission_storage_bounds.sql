\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- Copy the effective catalog CHECKs, without triggers, FKs or authority. These
-- are storage-container tests, not valid semantic assignments/admission. The
-- complete media composer/C1 resource harness covers actual guarded insertion.
CREATE TEMP TABLE storage_bound_probe
    (LIKE internal.initial_analysis_submissions INCLUDING CONSTRAINTS);
CREATE FUNCTION pg_temp.store_bound(input JSONB, descriptions JSONB DEFAULT '[]', configuration JSONB DEFAULT '{}')
RETURNS VOID LANGUAGE SQL AS $$
 INSERT INTO storage_bound_probe(scan_id,owner_id,route,input_schema_version,
    input_snapshot,ordered_descriptions,configuration_snapshot,funding_snapshot)
 VALUES(gen_random_uuid(),gen_random_uuid(),'identify',1,input,descriptions,configuration,'{}');
$$;
CREATE FUNCTION pg_temp.bound_string(encoded_bytes INTEGER, symbol TEXT) RETURNS TEXT LANGUAGE PLPGSQL AS $$
DECLARE unit_size INTEGER:=octet_length(to_jsonb(symbol)::TEXT)-2;
BEGIN
 RETURN repeat(symbol,encoded_bytes/unit_size)||repeat('a',encoded_bytes%unit_size);
END; $$;
CREATE TEMP TABLE bound_inputs AS
 SELECT label,jsonb_build_object('text',pg_temp.bound_string(1048576-11,symbol)) value
 FROM (VALUES('plain','a'),('escaped',chr(1)),('non_bmp',chr(128998))) v(label,symbol);
SELECT extensions.is(octet_length(internal.initial_canonical(value)),1048576,label||' exact canonical input container') FROM bound_inputs;
SELECT extensions.ok(octet_length(value::TEXT)>1048576,label||' PG rendering exceeds canonical cap') FROM bound_inputs;
SELECT extensions.lives_ok(format('SELECT pg_temp.store_bound(%L::JSONB)',value::TEXT),label||' exact-cap storage representation accepted') FROM bound_inputs;
SELECT extensions.throws_ok(format('SELECT internal.initial_canonical(%L::JSONB)',jsonb_set(value,'{text}',to_jsonb((value->>'text')||'a'))::TEXT),
 '22023','initial_analysis_input_invalid',label||' canonical cap+one still denied') FROM bound_inputs;

-- A maximally populated canonical tree: root + array + 511 objects, each with
-- seven scalar children + six additional root values = 4096 value nodes.
CREATE TEMP TABLE node_bound AS
 SELECT jsonb_build_object('items',(SELECT jsonb_agg(obj) FROM generate_series(1,511) x
   CROSS JOIN (SELECT jsonb_object_agg('k'||n,n) obj FROM generate_series(1,7) n) y),
   'a',chr(1),'b',chr(128998),'c','é','d','"','e',E'\\','f',9007199254740991) value;
SELECT extensions.is((SELECT nodes FROM node_bound, LATERAL internal.initial_canonical_parts(value,0)),4096,'renderer proof uses full node ceiling');
SELECT extensions.ok(octet_length(value::TEXT)-octet_length(internal.initial_canonical(value)) BETWEEN 0 AND 8190,
 'PG separator expansion bounded with control, non-BMP, quotes, slash and safe integer') FROM node_bound;

-- Combine both ceilings in one accepted canonical value without adding nodes.
UPDATE node_bound SET value=jsonb_set(value,'{a}',to_jsonb(repeat('a',
 1048576-octet_length(internal.initial_canonical(value))+6)));
SELECT extensions.is((SELECT nodes FROM node_bound, LATERAL internal.initial_canonical_parts(value,0)),4096,'combined witness retains full node ceiling');
SELECT extensions.is(octet_length(internal.initial_canonical(value)),1048576,'combined witness reaches full byte ceiling') FROM node_bound;
SELECT extensions.ok(octet_length(value::TEXT) BETWEEN 1048577 AND 1056766,'combined witness fits bounded renderer allowance') FROM node_bound;
SELECT extensions.lives_ok(format('SELECT pg_temp.store_bound(%L::JSONB)',value::TEXT),'combined node and byte ceiling persists') FROM node_bound;

CREATE TEMP TABLE description_bound AS
 SELECT jsonb_agg(value) value FROM (
  SELECT pg_temp.bound_string(CASE WHEN n=1 THEN 1048576-1537-511*2000 ELSE 2000 END,'a') value
  FROM generate_series(1,512) n) x;
SELECT extensions.is(octet_length(internal.initial_canonical(value)),1048576,'description array canonical ceiling') FROM description_bound;
SELECT extensions.is(octet_length(value::TEXT),1049087,'description array renderer adds 511 separator bytes') FROM description_bound;
SELECT extensions.lives_ok(format('SELECT pg_temp.store_bound(''{}'',%L::JSONB)',value::TEXT),'description container overhead accepted') FROM description_bound;

CREATE TEMP TABLE config_bound AS SELECT jsonb_build_object('version',2,'assignment',jsonb_build_object('payload',repeat('a',65536-14))) value;
SELECT extensions.is(octet_length(internal.initial_canonical(value->'assignment')),65536,'assignment component ceiling') FROM config_bound;
SELECT extensions.is(octet_length(internal.initial_canonical(value)),65563,'configuration adds exact 27-byte wrapper') FROM config_bound;
SELECT extensions.lives_ok(format('SELECT pg_temp.store_bound(''{}'',''[]'',%L::JSONB)',value::TEXT),'configuration wrapper and renderer overhead accepted') FROM config_bound;

SELECT extensions.throws_ok($$SELECT pg_temp.store_bound(jsonb_build_object('text',repeat('a',1056767-12)))$$,'23514',NULL,'input raw storage cap+one denied');
SELECT extensions.throws_ok($$SELECT pg_temp.store_bound('{}',jsonb_build_array(repeat('a',1056767-4)))$$,'23514',NULL,'description raw storage cap+one denied');
SELECT extensions.throws_ok($$SELECT pg_temp.store_bound('{}','[]',jsonb_build_object('text',repeat('a',73754-12)))$$,'23514',NULL,'configuration raw storage cap+one denied');
SELECT extensions.throws_ok($$SELECT pg_temp.store_bound('[]')$$,'23514',NULL,'input object shape retained');
SELECT extensions.throws_ok($$SELECT pg_temp.store_bound('{}','{}')$$,'23514',NULL,'description array shape retained');
SELECT extensions.throws_ok($$SELECT pg_temp.store_bound('{}','[]','[]')$$,'23514',NULL,'configuration object shape retained');
SELECT extensions.ok(pg_get_constraintdef(oid) LIKE '%16384%','funding legacy container unchanged') FROM pg_constraint
 WHERE conrelid='internal.initial_analysis_submissions'::REGCLASS AND conname='initial_analysis_submissions_funding_snapshot_check';
SELECT extensions.is((SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout),FALSE,'qualification leaves activation disabled');
SELECT * FROM extensions.finish();
ROLLBACK;
