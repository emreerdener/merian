SET lock_timeout='5s';
SET statement_timeout='2min';

-- Equivalent scalar-child encoding avoids a SQL/PLpgSQL call per leaf. Every
-- existing receipt callback, canonical bound, node count and deadline remains.
-- Containers still recurse through the same owner. Signature, volatility,
-- search path and existing privileges are preserved by forward replacement.
CREATE OR REPLACE FUNCTION internal.initial_canonical_parts(value JSONB, depth INTEGER)
RETURNS TABLE(encoded TEXT,nodes INTEGER) LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE kind TEXT:=jsonb_typeof(value); item RECORD; child_encoded TEXT; child_nodes INTEGER; child_kind TEXT; child_depth INTEGER; parts TEXT[]:=ARRAY[]::TEXT[]; n NUMERIC;
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
   child_depth:=depth+1; child_kind:=jsonb_typeof(item.v);
   child_encoded:=NULL; child_nodes:=NULL;
   IF child_kind IN ('null','boolean','string','number') THEN
    -- Preserve the recursive leaf's depth, encoding, number and byte checks.
    IF child_depth>12 OR item.v IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    child_nodes:=1;
    IF child_kind='number' THEN
     n:=(item.v::TEXT)::NUMERIC;
     IF n<>trunc(n) OR abs(n)>9007199254740991 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
     child_encoded:=n::BIGINT::TEXT;
    ELSE child_encoded:=item.v::TEXT;
    END IF;
    IF octet_length(child_encoded)>1048576 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   ELSE
    SELECT child.encoded,child.nodes INTO child_encoded,child_nodes FROM internal.initial_canonical_parts(item.v,child_depth) child;
   END IF;
   nodes:=nodes+child_nodes; parts:=array_append(parts,child_encoded);
   IF nodes>4096 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  END LOOP;
  encoded:='['||array_to_string(parts,',')||']';
 WHEN 'object' THEN
  IF (SELECT count(*) FROM jsonb_object_keys(value))>128 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  FOR item IN SELECT key,v FROM jsonb_each(value) AS x(key,v) ORDER BY key COLLATE "C" LOOP
   IF item.key !~ '^[a-z][a-z0-9_]*$' OR length(item.key)>64 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   child_depth:=depth+1; child_kind:=jsonb_typeof(item.v);
   child_encoded:=NULL; child_nodes:=NULL;
   IF child_kind IN ('null','boolean','string','number') THEN
    -- Preserve the recursive leaf's depth, encoding, number and byte checks.
    IF child_depth>12 OR item.v IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    child_nodes:=1;
    IF child_kind='number' THEN
     n:=(item.v::TEXT)::NUMERIC;
     IF n<>trunc(n) OR abs(n)>9007199254740991 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
     child_encoded:=n::BIGINT::TEXT;
    ELSE child_encoded:=item.v::TEXT;
    END IF;
    IF octet_length(child_encoded)>1048576 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   ELSE
    SELECT child.encoded,child.nodes INTO child_encoded,child_nodes FROM internal.initial_canonical_parts(item.v,child_depth) child;
   END IF;
   nodes:=nodes+child_nodes; parts:=array_append(parts,to_jsonb(item.key)::TEXT||':'||child_encoded);
   IF nodes>4096 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  END LOOP;
  encoded:='{'||array_to_string(parts,',')||'}';
 ELSE RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END CASE;
 IF octet_length(encoded)>1048576 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN NEXT;
END;
$$;

RESET statement_timeout;
RESET lock_timeout;
