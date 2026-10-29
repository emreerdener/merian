\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- Independent immutable-history oracle. Both entry point and recursive calls
-- use this original routine; none may redirect to the candidate.
-- BEGIN ORIGINAL CANONICAL ORACLE
CREATE FUNCTION pg_temp.original_canonical_parts(value JSONB, depth INTEGER)
RETURNS TABLE(encoded TEXT,nodes INTEGER) LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE kind TEXT:=jsonb_typeof(value); item RECORD; child RECORD; parts TEXT[]:=ARRAY[]::TEXT[]; n NUMERIC;
BEGIN
 IF depth>12 OR value IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 nodes:=1;
 CASE kind
 WHEN 'null','boolean','string' THEN encoded:=value::TEXT;
 WHEN 'number' THEN
  n:=(value::TEXT)::NUMERIC;
  IF n<>trunc(n) OR abs(n)>9007199254740991 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  encoded:=n::BIGINT::TEXT;
 WHEN 'array' THEN
  IF jsonb_array_length(value)>512 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  FOR item IN SELECT v FROM jsonb_array_elements(value) AS x(v) LOOP
   SELECT * INTO child FROM pg_temp.original_canonical_parts(item.v,depth+1);
   nodes:=nodes+child.nodes; parts:=array_append(parts,child.encoded);
   IF nodes>4096 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  END LOOP;
  encoded:='['||array_to_string(parts,',')||']';
 WHEN 'object' THEN
  IF (SELECT count(*) FROM jsonb_object_keys(value))>128 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  FOR item IN SELECT key,v FROM jsonb_each(value) AS x(key,v) ORDER BY key COLLATE "C" LOOP
   IF item.key !~ '^[a-z][a-z0-9_]*$' OR length(item.key)>64 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   SELECT * INTO child FROM pg_temp.original_canonical_parts(item.v,depth+1);
   nodes:=nodes+child.nodes; parts:=array_append(parts,to_jsonb(item.key)::TEXT||':'||child.encoded);
   IF nodes>4096 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  END LOOP;
  encoded:='{'||array_to_string(parts,',')||'}';
 ELSE RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END CASE;
 IF octet_length(encoded)>1048576 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN NEXT;
END;
$$;
-- END ORIGINAL CANONICAL ORACLE

CREATE FUNCTION pg_temp.codec_outcome(value JSONB,depth INTEGER,original BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE encoded TEXT; nodes INTEGER;
BEGIN
 IF original THEN
  SELECT r.encoded,r.nodes INTO encoded,nodes FROM pg_temp.original_canonical_parts(value,depth) r;
 ELSE
  SELECT r.encoded,r.nodes INTO encoded,nodes FROM internal.initial_canonical_parts(value,depth) r;
 END IF;
 RETURN jsonb_build_object('encoded',encoded,'nodes',nodes);
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('sqlstate',SQLSTATE,'message',SQLERRM);
END; $$;
CREATE FUNCTION pg_temp.codec_matches(value JSONB,depth INTEGER DEFAULT 0)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE expected JSONB:=pg_temp.codec_outcome(value,depth,TRUE);
 actual JSONB:=pg_temp.codec_outcome(value,depth,FALSE);
BEGIN
 RETURN expected=actual AND convert_to(expected->>'encoded','UTF8') IS NOT DISTINCT FROM convert_to(actual->>'encoded','UTF8');
END; $$;
CREATE FUNCTION pg_temp.nested_value(levels INTEGER,leaf JSONB DEFAULT 'null')
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE value JSONB:=leaf;
BEGIN
 FOR i IN 1..levels LOOP value:=jsonb_build_array(value); END LOOP;
 RETURN value;
END; $$;

SELECT extensions.ok(pg_temp.codec_matches(value),label) FROM (VALUES
 ('null','null'::JSONB),('true','true'::JSONB),('false','false'::JSONB),
 ('empty string','""'::JSONB),('empty array','[]'::JSONB),('empty object','{}'::JSONB),
 ('mixed children','[null,true,1,"x",[],{},[false,2],{"a":3},"tail"]'::JSONB),
 ('object C order and mixed children','{"z":null,"a":[1,{},"x"],"b":true}'::JSONB),
 ('escaped controls',to_jsonb(chr(1)||chr(9)||chr(10)||chr(13)||chr(34)||chr(92))),
 ('non BMP',to_jsonb(chr(128998))),('composed',to_jsonb(chr(233))),
 ('decomposed',to_jsonb('e'||chr(769))),('JSON SQL null',NULL::JSONB)
) cases(label,value);
SELECT extensions.is((pg_temp.codec_outcome('{"b":true,"a":[null,1,"x"]}',0,FALSE)->>'encoded'),
 '{"a":[null,1,"x"],"b":true}','independent exact canonical spelling');
SELECT extensions.is((pg_temp.codec_outcome('{"b":true,"a":[null,1,"x"]}',0,FALSE)->>'nodes')::INTEGER,6,'object keys contribute no nodes');
SELECT extensions.ok(internal.initial_canonical(to_jsonb(chr(233)))<>internal.initial_canonical(to_jsonb('e'||chr(769))),'normalization distinctions preserved');
SELECT extensions.ok(pg_temp.codec_matches(value::JSONB),'number '||value) FROM unnest(ARRAY[
 '0','-0','0.00','-0.0','1.0','1e3','1e-3','9007199254740991','-9007199254740991',
 '9007199254740992','-9007199254740992','1.25','-1.25','1e100'
]) value;
SELECT extensions.ok(pg_temp.codec_matches(jsonb_build_array(value::JSONB),'0'::INTEGER),'nested number '||value)
 FROM unnest(ARRAY['0','-0','1.0','1e3','1e-3','9007199254740991','-9007199254740991','9007199254740992','-9007199254740992','1.25','1e100']) value;
SELECT extensions.ok(pg_temp.codec_matches(pg_temp.nested_value(levels)),'depth '||levels)
 FROM generate_series(11,13) levels;
SELECT extensions.ok(pg_temp.codec_matches(pg_temp.nested_value(14),depth),'direct depth '||COALESCE(depth::TEXT,'NULL'))
 FROM unnest(ARRAY[NULL,-2147483648,-2,-1,0,12,13,2147483647]) depth;
SELECT extensions.ok(pg_temp.codec_matches(value,depth),'direct scalar depth '||COALESCE(depth::TEXT,'NULL'))
 FROM unnest(ARRAY[NULL,-2147483648,-1,0,12,13,2147483647]) depth CROSS JOIN (VALUES('1'::JSONB),('null'::JSONB),(NULL::JSONB)) x(value);
SELECT extensions.ok(pg_temp.codec_matches((SELECT jsonb_agg(0) FROM generate_series(1,n))),'array count '||n) FROM unnest(ARRAY[511,512,513]) n;
SELECT extensions.ok(pg_temp.codec_matches((SELECT jsonb_object_agg('k'||lpad(i::TEXT,3,'0'),i) FROM generate_series(1,n) i)),'object count '||n) FROM unnest(ARRAY[127,128,129]) n;
SELECT extensions.ok(pg_temp.codec_matches(jsonb_build_object(key,1)),'object key shape '||ordinality)
 FROM unnest(ARRAY['a',repeat('a',64),repeat('a',65),'','A','a-b','a b','a'||chr(233)]) WITH ORDINALITY x(key,ordinality);
SELECT extensions.ok(pg_temp.codec_matches((SELECT jsonb_agg(
 (SELECT jsonb_agg(0) FROM generate_series(1,CASE WHEN i=8 THEN tail ELSE 511 END))) FROM generate_series(1,8) i)),
 'node count '||(3586+tail)) FROM unnest(ARRAY[509,510,511]) tail;
SELECT extensions.is((pg_temp.codec_outcome((SELECT jsonb_agg((SELECT jsonb_agg(0) FROM generate_series(1,CASE WHEN i=8 THEN 510 ELSE 511 END))) FROM generate_series(1,8) i),0,FALSE)->>'nodes')::INTEGER,4096,'exact node ceiling accepted');
SELECT extensions.ok(pg_temp.codec_matches(to_jsonb(repeat('a',n))),'scalar bytes '||(n+2)) FROM generate_series(1048573,1048575) n;
SELECT extensions.ok(pg_temp.codec_matches(jsonb_build_object('a',repeat('a',n))),'container bytes '||(n+8)) FROM generate_series(1048567,1048569) n;
SELECT extensions.ok(pg_temp.codec_matches(to_jsonb(repeat(chr(1),174762)||repeat('a',padding))),'escape expansion bytes '||(1048574+padding)) FROM generate_series(1,3) padding;
SELECT extensions.ok(pg_temp.codec_matches(to_jsonb(repeat(chr(128998),262143)||repeat('a',padding))),'non BMP bytes '||(1048574+padding)) FROM generate_series(1,3) padding;
SELECT extensions.ok(pg_temp.codec_matches(jsonb_build_array(jsonb_build_object('k'||i,CASE i%4
 WHEN 0 THEN 'null'::JSONB WHEN 1 THEN to_jsonb(i) WHEN 2 THEN to_jsonb('x'||chr(1)||chr(128998)) ELSE jsonb_build_array(TRUE,FALSE,i) END),i%2=0,
 jsonb_build_object('nested',jsonb_build_array(i,'tail')))),'generated mixed tree '||i) FROM generate_series(1,64) i;
SELECT extensions.is((SELECT provolatile::TEXT FROM pg_proc WHERE oid='internal.initial_canonical_parts(jsonb,integer)'::REGPROCEDURE),'s','stable volatility retained');
SELECT extensions.ok((SELECT NOT prosecdef AND proconfig=ARRAY['search_path=""'] FROM pg_proc WHERE oid='internal.initial_canonical_parts(jsonb,integer)'::REGPROCEDURE),'invoker and empty search path retained');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 WHERE has_function_privilege(role_name,'internal.initial_canonical_parts(jsonb,integer)','EXECUTE')),'private codec grants unchanged');
SELECT * FROM extensions.finish();
ROLLBACK;
