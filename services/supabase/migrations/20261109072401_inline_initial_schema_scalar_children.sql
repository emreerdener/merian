-- Inline scalar children without changing depth, bounds, errors or tri-state
-- semantics. Containers still recurse; no validation or authority is cached.
SET lock_timeout='5s';
SET statement_timeout='2min';

CREATE OR REPLACE FUNCTION internal.initial_schema_matches(value JSONB, rule JSONB, depth INTEGER DEFAULT 0)
RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE field RECORD; item JSONB; scalar TEXT; number_value NUMERIC; child_value JSONB; child_rule JSONB; child_depth INTEGER; child_result BOOLEAN;
BEGIN
 IF depth>12 OR value IS NULL THEN RETURN FALSE; END IF;
 IF value='null'::JSONB THEN RETURN COALESCE((rule->>'nullable')::BOOLEAN,FALSE); END IF;
 CASE rule->>'type'
 WHEN 'object' THEN
  IF jsonb_typeof(value)<>'object' THEN RETURN FALSE; END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(value))<>(SELECT count(*) FROM jsonb_object_keys(rule->'properties')) THEN RETURN FALSE; END IF;
  FOR field IN SELECT * FROM jsonb_each(rule->'properties') LOOP
   child_value:=value->field.key; child_rule:=field.value;
   child_depth:=depth+1; child_result:=NULL;
   IF child_depth>12 OR child_value IS NULL THEN child_result:=FALSE;
   ELSIF child_value='null'::JSONB THEN child_result:=COALESCE((child_rule->>'nullable')::BOOLEAN,FALSE);
   ELSE
    CASE child_rule->>'type'
    WHEN 'object','array' THEN
     child_result:=internal.initial_schema_matches(child_value,child_rule,child_depth);
    WHEN 'boolean' THEN child_result:=jsonb_typeof(child_value)='boolean';
    WHEN 'integer' THEN
     IF jsonb_typeof(child_value)<>'number' THEN child_result:=FALSE;
     ELSE
      number_value:=(child_value::TEXT)::NUMERIC;
      child_result:=number_value=trunc(number_value) AND number_value BETWEEN (child_rule->>'minimum')::NUMERIC AND (child_rule->>'maximum')::NUMERIC;
     END IF;
    WHEN 'string','decimal' THEN
     IF jsonb_typeof(child_value)<>'string' THEN child_result:=FALSE;
     ELSE
      scalar:=child_value#>>'{}';
      IF octet_length(scalar)>(child_rule->>'max_bytes')::INTEGER THEN child_result:=FALSE;
      ELSIF child_rule->>'type'='decimal' THEN
       IF scalar !~ '^-?(0|[1-9][0-9]*)(\.[0-9]*[1-9])?$' OR scalar='-0' THEN child_result:=FALSE;
       ELSE child_result:=scalar::NUMERIC BETWEEN (child_rule->>'minimum')::NUMERIC AND (child_rule->>'maximum')::NUMERIC;
       END IF;
      ELSE
       child_result:=(NOT child_rule ? 'enum' OR child_rule->'enum' @> jsonb_build_array(scalar)) AND (NOT child_rule ? 'pattern' OR scalar ~ (child_rule->>'pattern'));
      END IF;
     END IF;
    ELSE child_result:=FALSE;
    END CASE;
   END IF;
   -- Preserve three-valued child semantics: NULL is not FALSE here.
   IF NOT child_result THEN RETURN FALSE; END IF;
  END LOOP; RETURN TRUE;
 WHEN 'array' THEN
  IF jsonb_typeof(value)<>'array' OR jsonb_array_length(value)>(rule->>'max_items')::INTEGER THEN RETURN FALSE; END IF;
  FOR item IN SELECT * FROM jsonb_array_elements(value) LOOP
   child_value:=item; child_rule:=rule->'items';
   child_depth:=depth+1; child_result:=NULL;
   IF child_depth>12 OR child_value IS NULL THEN child_result:=FALSE;
   ELSIF child_value='null'::JSONB THEN child_result:=COALESCE((child_rule->>'nullable')::BOOLEAN,FALSE);
   ELSE
    CASE child_rule->>'type'
    WHEN 'object','array' THEN
     child_result:=internal.initial_schema_matches(child_value,child_rule,child_depth);
    WHEN 'boolean' THEN child_result:=jsonb_typeof(child_value)='boolean';
    WHEN 'integer' THEN
     IF jsonb_typeof(child_value)<>'number' THEN child_result:=FALSE;
     ELSE
      number_value:=(child_value::TEXT)::NUMERIC;
      child_result:=number_value=trunc(number_value) AND number_value BETWEEN (child_rule->>'minimum')::NUMERIC AND (child_rule->>'maximum')::NUMERIC;
     END IF;
    WHEN 'string','decimal' THEN
     IF jsonb_typeof(child_value)<>'string' THEN child_result:=FALSE;
     ELSE
      scalar:=child_value#>>'{}';
      IF octet_length(scalar)>(child_rule->>'max_bytes')::INTEGER THEN child_result:=FALSE;
      ELSIF child_rule->>'type'='decimal' THEN
       IF scalar !~ '^-?(0|[1-9][0-9]*)(\.[0-9]*[1-9])?$' OR scalar='-0' THEN child_result:=FALSE;
       ELSE child_result:=scalar::NUMERIC BETWEEN (child_rule->>'minimum')::NUMERIC AND (child_rule->>'maximum')::NUMERIC;
       END IF;
      ELSE
       child_result:=(NOT child_rule ? 'enum' OR child_rule->'enum' @> jsonb_build_array(scalar)) AND (NOT child_rule ? 'pattern' OR scalar ~ (child_rule->>'pattern'));
      END IF;
     END IF;
    ELSE child_result:=FALSE;
    END CASE;
   END IF;
   -- Preserve three-valued child semantics: NULL is not FALSE here.
   IF NOT child_result THEN RETURN FALSE; END IF;
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

RESET statement_timeout;
RESET lock_timeout;
