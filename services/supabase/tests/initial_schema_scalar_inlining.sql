\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- Independent recursive historical implementation: it never calls the repair.
CREATE FUNCTION pg_temp.original_schema_matches(value JSONB, rule JSONB, depth INTEGER DEFAULT 0)
RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE field RECORD; item JSONB; scalar TEXT; number_value NUMERIC;
BEGIN
 IF depth>12 OR value IS NULL THEN RETURN FALSE; END IF;
 IF value='null'::JSONB THEN RETURN COALESCE((rule->>'nullable')::BOOLEAN,FALSE); END IF;
 CASE rule->>'type'
 WHEN 'object' THEN
  IF jsonb_typeof(value)<>'object' THEN RETURN FALSE; END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(value))<>(SELECT count(*) FROM jsonb_object_keys(rule->'properties')) THEN RETURN FALSE; END IF;
  FOR field IN SELECT * FROM jsonb_each(rule->'properties') LOOP
   IF NOT pg_temp.original_schema_matches(value->field.key,field.value,depth+1) THEN RETURN FALSE; END IF;
  END LOOP; RETURN TRUE;
 WHEN 'array' THEN
  IF jsonb_typeof(value)<>'array' OR jsonb_array_length(value)>(rule->>'max_items')::INTEGER THEN RETURN FALSE; END IF;
  FOR item IN SELECT * FROM jsonb_array_elements(value) LOOP
   IF NOT pg_temp.original_schema_matches(item,rule->'items',depth+1) THEN RETURN FALSE; END IF;
  END LOOP; RETURN TRUE;
 WHEN 'boolean' THEN RETURN jsonb_typeof(value)='boolean';
 WHEN 'integer' THEN
  IF jsonb_typeof(value)<>'number' THEN RETURN FALSE; END IF;
  number_value:=(value::TEXT)::NUMERIC;
  RETURN number_value=trunc(number_value) AND number_value BETWEEN (rule->>'minimum')::NUMERIC AND (rule->>'maximum')::NUMERIC;
 WHEN 'string','decimal' THEN
  IF jsonb_typeof(value)<>'string' THEN RETURN FALSE; END IF;
  scalar:=value#>>'{}';
  IF octet_length(scalar)>(rule->>'max_bytes')::INTEGER THEN RETURN FALSE; END IF;
  IF rule->>'type'='decimal' THEN
   IF scalar !~ '^-?(0|[1-9][0-9]*)(\.[0-9]*[1-9])?$' OR scalar='-0' THEN RETURN FALSE; END IF;
   RETURN scalar::NUMERIC BETWEEN (rule->>'minimum')::NUMERIC AND (rule->>'maximum')::NUMERIC;
  END IF;
  RETURN (NOT rule ? 'enum' OR rule->'enum' @> jsonb_build_array(scalar)) AND (NOT rule ? 'pattern' OR scalar ~ (rule->>'pattern'));
 ELSE RETURN FALSE;
 END CASE;
END;
$$;
CREATE FUNCTION pg_temp.schema_result(v JSONB,r JSONB,d INTEGER,original BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE result BOOLEAN; code TEXT; message TEXT;
BEGIN
 BEGIN
  IF original THEN result:=pg_temp.original_schema_matches(v,r,d);
  ELSE result:=internal.initial_schema_matches(v,r,d); END IF;
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;
 END;
 RETURN jsonb_build_object('result',result,'code',code,'message',message);
END; $$;
CREATE TEMP TABLE schema_values(id INTEGER GENERATED ALWAYS AS IDENTITY,v JSONB);
INSERT INTO schema_values(v) VALUES
 (NULL),('null'),('true'),('false'),('0'),('-1'),('1.5'),('9007199254740991'),('9007199254740992'),
 ('""'),('"a"'),('"é"'),('"😀"'),('"0"'),('"-0"'),('"1.5"'),('"1.0"'),('"1e2"'),('"01"'),('"-1.5"'),('"0.0001"'),
 ('[]'),('[1,null]'),('{}'),('{"x":1}');
CREATE TEMP TABLE schema_rules(id INTEGER GENERATED ALWAYS AS IDENTITY,r JSONB);
INSERT INTO schema_rules(r) VALUES
 (NULL),('null'),('{}'),('{"type":"unknown"}'),('{"type":"boolean"}'),
 ('{"type":"integer","minimum":-1,"maximum":9007199254740991}'),
 ('{"type":"integer"}'),('{"type":"integer","minimum":"bad","maximum":1}'),
 ('{"type":"string","max_bytes":3}'),('{"type":"string","max_bytes":4}'),
 ('{"type":"string","max_bytes":"bad"}'),('{"type":"string","enum":["a"]}'),
 ('{"type":"string","pattern":"^a$"}'),('{"type":"string","pattern":"["}'),
 ('{"type":"string","pattern":null}'),('{"type":"string","enum":null}'),
 ('{"type":"decimal","minimum":-2,"maximum":2,"max_bytes":20}'),
 ('{"type":"decimal"}'),('{"type":"decimal","minimum":"bad"}'),
 ('{"type":"array","items":{"type":"integer"},"max_items":2}'),
 ('{"type":"array","items":{"type":"boolean"},"max_items":0}'),
 ('{"type":"object","properties":{"x":{"type":"integer"}}}'),
 ('{"type":"object","properties":{}}'),('{"type":"object","properties":[]}'),
 ('{"nullable":true}'),('{"nullable":"bad"}'),('{"nullable":null}');
SELECT extensions.ok(pg_temp.schema_result(v,r,0,true) IS NOT DISTINCT FROM pg_temp.schema_result(v,r,0,false),
 'scalar/rule crossing '||v.id||'/'||r.id) FROM schema_values v CROSS JOIN schema_rules r;
-- Every scalar/rule crossing as a child, including SQL NULL becoming JSON null.
SELECT extensions.ok(pg_temp.schema_result(jsonb_build_array(v),jsonb_build_object('type','array','max_items',2,'items',r),0,true)
 IS NOT DISTINCT FROM pg_temp.schema_result(jsonb_build_array(v),jsonb_build_object('type','array','max_items',2,'items',r),0,false),
 'array child crossing '||v.id||'/'||r.id) FROM schema_values v CROSS JOIN schema_rules r;
SELECT extensions.ok(pg_temp.schema_result(jsonb_build_object('x',v),jsonb_build_object('type','object','properties',jsonb_build_object('x',r)),0,true)
 IS NOT DISTINCT FROM pg_temp.schema_result(jsonb_build_object('x',v),jsonb_build_object('type','object','properties',jsonb_build_object('x',r)),0,false),
 'object child crossing '||v.id||'/'||r.id) FROM schema_values v CROSS JOIN schema_rules r;
SELECT extensions.ok(pg_temp.schema_result(v,r,d,true) IS NOT DISTINCT FROM pg_temp.schema_result(v,r,d,false),
 'depth parity '||COALESCE(d::TEXT,'NULL')) FROM (VALUES
 ('[null]'::JSONB,'{"type":"array","items":{"type":"string","nullable":true},"max_items":1}'::JSONB),
 ('[[1]]','{"type":"array","max_items":1,"items":{"type":"array","max_items":1,"items":{"type":"integer"}}}'),
 ('{"x":{"x":1}}','{"type":"object","properties":{"x":{"type":"object","properties":{"x":{"type":"integer"}}}}}'),
 ('{}','{"type":"object","properties":{"x":{"type":"integer"}}}'),
 ('{"x":1,"extra":1}','{"type":"object","properties":{"x":{"type":"integer"}}}'),
 ('[1,"bad",2]','{"type":"array","max_items":3,"items":{"type":"integer"}}'),
 ('{"y":1}','{"type":"object","properties":{"x":{"type":"integer"}}}'),
 ('{"a":true,"b":1,"c":"bad"}','{"type":"object","properties":{"a":{"type":"boolean"},"b":{"type":"integer"},"c":{"type":"integer"}}}'),
 ('{"a":1,"b":true}','{"type":"object","properties":{"a":{"type":"integer"},"b":{"type":"boolean"}}}'),
 ('[1,"bad"]','{"type":"array","max_items":2,"items":{"type":"integer"}}'),
 ('["a","b","c"]','{"type":"array","max_items":3,"items":{"type":"string","pattern":null}}')
 ) p(v,r) CROSS JOIN unnest(ARRAY[NULL::INTEGER,0,11,12,13]) d;
SELECT extensions.ok(NOT has_function_privilege(role,'internal.initial_schema_matches(jsonb,jsonb,integer)','EXECUTE'),'API role denied '||role)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role;
SELECT extensions.is(provolatile::TEXT,'s','STABLE retained') FROM pg_proc WHERE oid='internal.initial_schema_matches(jsonb,jsonb,integer)'::regprocedure;
SELECT extensions.ok(NOT prosecdef,'invoker retained') FROM pg_proc WHERE oid='internal.initial_schema_matches(jsonb,jsonb,integer)'::regprocedure;
SELECT * FROM extensions.finish();
ROLLBACK;
