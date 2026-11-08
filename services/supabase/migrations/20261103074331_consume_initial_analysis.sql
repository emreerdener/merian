SET lock_timeout='5s';
SET statement_timeout='2min';

-- Keep replay paths that apply one statement at a time inside the same atomic
-- installation boundary. Timeout guards remain outside the running DO statement.
DO $s0_migration$
BEGIN
 EXECUTE $s0_statements$

-- INTEGRATION DRAFT: no callable grant; private report/result witnesses only.
-- The complete dispatch/result/adoption/completion chain must be integrated and
-- reviewed before this candidate is committed. Existing writer denials remain.
-- BEGIN FROZEN RESULT_V1_SCHEMA
CREATE FUNCTION internal.initial_result_schema_v1() RETURNS JSONB
LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $result_v1_schema$
 SELECT $result_v1_json${"data":{"kind":"object","fields":{"scan_id":{"contract":{"kind":"string","minLength":1,"maxLength":128},"required":true},"identification_provenance":{"contract":{"kind":"union","discriminator":"version","variants":{"1":{"kind":"object","fields":{"version":{"contract":{"kind":"integer","minimum":1,"maximum":1},"required":true},"provider":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"binding":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"model":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"variant":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"operation":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"policy_version":{"contract":{"kind":"integer","minimum":1,"maximum":999999999},"required":true},"prompt":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"schema":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"confidence":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"diagnostic_trigger":{"contract":{"kind":"number","minimum":0,"maximum":1,"nullable":true},"required":true},"prompt_diagnostic_trigger":{"contract":{"kind":"number","minimum":0,"maximum":1,"nullable":true},"required":true},"safety":{"contract":{"kind":"string","nullable":true,"minLength":1,"maxLength":80},"required":true},"timeout_ms":{"contract":{"kind":"integer","minimum":1,"maximum":999999},"required":true},"generation":{"contract":{"kind":"object","fields":{"temperature":{"contract":{"kind":"number","minimum":0,"maximum":2},"required":true},"seed":{"contract":{"kind":"integer","minimum":0,"maximum":999999999,"nullable":true},"required":true},"top_k":{"contract":{"kind":"integer","minimum":1,"maximum":999999999,"nullable":true},"required":true},"max_output_tokens":{"contract":{"kind":"integer","minimum":1,"maximum":999999999},"required":true},"thinking_budget":{"contract":{"kind":"integer","minimum":0,"maximum":999999999,"nullable":true},"required":true}},"unknownKeys":"reject"},"required":true}},"unknownKeys":"reject"},"2":{"kind":"object","fields":{"version":{"contract":{"kind":"integer","minimum":2,"maximum":2},"required":true},"provider":{"contract":{"kind":"string","enum":["openai"],"maxLength":80},"required":true},"binding":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true},"model":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true},"variant":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$","enum":["multimodal","description_compat","vision_compat","audio_compat"]},"required":true},"operation":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$","enum":["scan_identification","scan_audio_identification"]},"required":true},"policy_version":{"contract":{"kind":"integer","minimum":1,"maximum":999999999},"required":true},"prompt":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true},"schema":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true},"confidence":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true},"diagnostic_trigger":{"contract":{"kind":"number","minimum":0,"maximum":1,"nullable":true},"required":true},"prompt_diagnostic_trigger":{"contract":{"kind":"number","minimum":0,"maximum":1,"nullable":true},"required":true},"safety":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$","nullable":true},"required":true},"timeout_ms":{"contract":{"kind":"integer","minimum":1,"maximum":999999},"required":true},"generation":{"contract":{"kind":"object","fields":{"max_output_tokens":{"contract":{"kind":"integer","minimum":1,"maximum":999999999},"required":true},"reasoning_effort":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true},"image_detail":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true}},"unknownKeys":"reject"},"required":true}},"unknownKeys":"reject"}},"swift":{"name":"IdentificationProvenanceDTO","declarationOrder":34}},"required":false},"primary_identification":{"contract":{"kind":"object","fields":{"version":{"contract":{"kind":"integer","minimum":1,"maximum":1},"required":true},"resolution":{"contract":{"kind":"string","enum":["species","genus","family","unresolved_biological","non_biological"]},"required":true},"scientific_name":{"contract":{"kind":"string","nullable":true,"minLength":1,"maxLength":255},"required":true},"common_name":{"contract":{"kind":"string","nullable":true,"minLength":1,"maxLength":255},"required":true}},"unknownKeys":"reject"},"required":false},"is_biological_subject":{"contract":{"kind":"boolean"},"required":true},"is_live_capture":{"contract":{"kind":"boolean"},"required":true},"ecology_type":{"contract":{"kind":"string","nullable":true,"enum":["wild","urban","domesticated","unknown"],"maxLength":12},"required":false},"is_invasive":{"contract":{"kind":"boolean","nullable":true},"required":false},"invasive_status_region":{"contract":{"kind":"string","nullable":true,"minLength":1,"maxLength":160},"required":false},"invasive_rationale":{"contract":{"kind":"string","nullable":true,"minLength":1,"maxLength":500},"required":false},"invasive_confidence":{"contract":{"kind":"number","minimum":0,"maximum":1,"nullable":true},"required":false},"scientific_name":{"contract":{"kind":"string","nullable":true,"minLength":1,"maxLength":255},"required":false},"common_name":{"contract":{"kind":"string","nullable":true,"minLength":1,"maxLength":255},"required":false},"confidence_score":{"contract":{"kind":"number","minimum":0,"maximum":1},"required":true},"blur_score":{"contract":{"kind":"number","minimum":0,"maximum":1},"required":true},"colors":{"contract":{"kind":"array","items":{"kind":"string","minLength":1,"maxLength":160},"minItems":0,"maxItems":20},"required":true},"group_tags":{"contract":{"kind":"array","items":{"kind":"string","minLength":1,"maxLength":160},"nullable":true,"minItems":0,"maxItems":32},"required":false},"is_new_to_merian_dictionary":{"contract":{"kind":"boolean"},"required":false},"estimated_size_cm":{"contract":{"kind":"number","minimum":0,"maximum":50000,"nullable":true},"required":true},"life_stage":{"contract":{"kind":"string","nullable":true,"enum":["egg","larva","pupa","nymph","juvenile","subadult","adult","seedling","sapling","unknown"],"maxLength":16},"required":false},"reproductive_condition":{"contract":{"kind":"string","nullable":true,"enum":["flowering","fruiting","budding","vegetative","sporing","pregnant","gravid","mating","spawning","nesting","dormant","not_applicable"],"maxLength":20},"required":false},"sex":{"contract":{"kind":"string","nullable":true,"enum":["female","male","hermaphrodite","mixed","cannot_determine","not_applicable"],"maxLength":20},"required":false},"sex_confidence":{"contract":{"kind":"number","minimum":0,"maximum":1,"nullable":true},"required":false},"sex_evidence":{"contract":{"kind":"string","nullable":true,"minLength":1,"maxLength":500},"required":false},"individual_count":{"contract":{"kind":"integer","minimum":1,"maximum":99999,"nullable":true},"required":false},"ecological_interactions":{"contract":{"kind":"array","items":{"kind":"string","minLength":1,"maxLength":500},"nullable":true,"minItems":0,"maxItems":10},"required":false},"taxonomy":{"contract":{"kind":"object","fields":{"kingdom":{"contract":{"kind":"string","minLength":1,"maxLength":160},"required":false},"phylum":{"contract":{"kind":"string","minLength":1,"maxLength":160},"required":false},"class":{"contract":{"kind":"string","minLength":1,"maxLength":160},"required":false},"order":{"contract":{"kind":"string","minLength":1,"maxLength":160},"required":false},"family":{"contract":{"kind":"string","minLength":1,"maxLength":160},"required":false},"genus":{"contract":{"kind":"string","minLength":1,"maxLength":160},"required":false}},"unknownKeys":"strip"},"required":false},"insight_data":{"contract":{"kind":"object","fields":{"ai_reasoning":{"contract":{"kind":"string","minLength":1,"maxLength":2000},"required":false},"hazard_type":{"contract":{"kind":"string","enum":["none","poisonous","venomous","allergenic","irritant"],"maxLength":16},"required":false}},"unknownKeys":"strip"},"required":false},"species_insights":{"contract":{"kind":"object","fields":{"habitat_description":{"contract":{"kind":"string","minLength":1,"maxLength":10000},"required":false}},"unknownKeys":"strip"},"required":false},"gbif_taxon_key":{"contract":{"kind":"integer","minimum":0,"maximum":9007199254740991,"nullable":true},"required":false},"wikipedia_url":{"contract":{"kind":"string","minLength":1,"maxLength":4096,"nullable":true},"required":false},"wikipedia_overview":{"contract":{"kind":"string","nullable":true,"minLength":1,"maxLength":20000},"required":false},"reference_image_url":{"contract":{"kind":"string","minLength":1,"maxLength":4096,"nullable":true},"required":false},"iucn_red_list_status":{"contract":{"kind":"string","minLength":1,"maxLength":160},"required":false},"inference_tier":{"contract":{"kind":"string","enum":["flash","pro"],"maxLength":5},"required":true},"alternative_common_names":{"contract":{"kind":"array","items":{"kind":"string","minLength":1,"maxLength":255},"nullable":true,"minItems":0,"maxItems":100},"required":false},"pet_identification":{"contract":{"kind":"object","fields":{"species_group":{"contract":{"kind":"string","enum":["dog","cat"],"maxLength":3},"required":true},"label":{"contract":{"kind":"string","minLength":1,"maxLength":160},"required":true},"label_type":{"contract":{"kind":"string","enum":["breed","breed_mix","coat_pattern","body_type"],"maxLength":20},"required":true},"confidence_score":{"contract":{"kind":"number","minimum":0,"maximum":1},"required":true},"evidence":{"contract":{"kind":"array","items":{"kind":"string","minLength":1,"maxLength":500},"minItems":1,"maxItems":3},"required":true}},"nullable":true,"unknownKeys":"strip"},"required":true},"candidates":{"contract":{"kind":"array","items":{"kind":"object","fields":{"taxon_rank":{"contract":{"kind":"string","enum":["species"]},"required":false},"scientific_name":{"contract":{"kind":"string","minLength":1,"maxLength":255},"required":true},"confidence_score":{"contract":{"kind":"number","minimum":0,"maximum":1},"required":true},"distinguishing_feature":{"contract":{"kind":"string","minLength":1,"maxLength":500},"required":true},"common_name":{"contract":{"kind":"string","minLength":1,"maxLength":255},"required":false}},"unknownKeys":"strip"},"nullable":true,"minItems":0,"maxItems":5},"required":true},"image_quality":{"contract":{"kind":"object","fields":{"sharpness":{"contract":{"kind":"integer","minimum":0,"maximum":10},"required":true},"framing":{"contract":{"kind":"integer","minimum":0,"maximum":10},"required":true},"diagnostic_utility":{"contract":{"kind":"integer","minimum":0,"maximum":10},"required":true},"overall_score":{"contract":{"kind":"integer","minimum":0,"maximum":100},"required":true}},"unknownKeys":"strip"},"required":true},"ai_reasoning":{"contract":{"kind":"string","minLength":1,"maxLength":2000},"required":true},"extracted_visual_traits":{"contract":{"kind":"array","items":{"kind":"string","minLength":1,"maxLength":500},"minItems":1,"maxItems":10},"required":true}},"unknownKeys":"strip"},"provenance":{"kind":"union","discriminator":"version","variants":{"1":{"kind":"object","fields":{"version":{"contract":{"kind":"integer","minimum":1,"maximum":1},"required":true},"provider":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"binding":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"model":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"variant":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"operation":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"policy_version":{"contract":{"kind":"integer","minimum":1,"maximum":999999999},"required":true},"prompt":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"schema":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"confidence":{"contract":{"kind":"string","minLength":1,"maxLength":80},"required":true},"diagnostic_trigger":{"contract":{"kind":"number","minimum":0,"maximum":1,"nullable":true},"required":true},"prompt_diagnostic_trigger":{"contract":{"kind":"number","minimum":0,"maximum":1,"nullable":true},"required":true},"safety":{"contract":{"kind":"string","nullable":true,"minLength":1,"maxLength":80},"required":true},"timeout_ms":{"contract":{"kind":"integer","minimum":1,"maximum":999999},"required":true},"generation":{"contract":{"kind":"object","fields":{"temperature":{"contract":{"kind":"number","minimum":0,"maximum":2},"required":true},"seed":{"contract":{"kind":"integer","minimum":0,"maximum":999999999,"nullable":true},"required":true},"top_k":{"contract":{"kind":"integer","minimum":1,"maximum":999999999,"nullable":true},"required":true},"max_output_tokens":{"contract":{"kind":"integer","minimum":1,"maximum":999999999},"required":true},"thinking_budget":{"contract":{"kind":"integer","minimum":0,"maximum":999999999,"nullable":true},"required":true}},"unknownKeys":"reject"},"required":true}},"unknownKeys":"reject"},"2":{"kind":"object","fields":{"version":{"contract":{"kind":"integer","minimum":2,"maximum":2},"required":true},"provider":{"contract":{"kind":"string","enum":["openai"],"maxLength":80},"required":true},"binding":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true},"model":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true},"variant":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$","enum":["multimodal","description_compat","vision_compat","audio_compat"]},"required":true},"operation":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$","enum":["scan_identification","scan_audio_identification"]},"required":true},"policy_version":{"contract":{"kind":"integer","minimum":1,"maximum":999999999},"required":true},"prompt":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true},"schema":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true},"confidence":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true},"diagnostic_trigger":{"contract":{"kind":"number","minimum":0,"maximum":1,"nullable":true},"required":true},"prompt_diagnostic_trigger":{"contract":{"kind":"number","minimum":0,"maximum":1,"nullable":true},"required":true},"safety":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$","nullable":true},"required":true},"timeout_ms":{"contract":{"kind":"integer","minimum":1,"maximum":999999},"required":true},"generation":{"contract":{"kind":"object","fields":{"max_output_tokens":{"contract":{"kind":"integer","minimum":1,"maximum":999999999},"required":true},"reasoning_effort":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true},"image_detail":{"contract":{"kind":"string","minLength":1,"maxLength":80,"pattern":"^[a-z][a-z0-9_.-]{0,79}$"},"required":true}},"unknownKeys":"reject"},"required":true}},"unknownKeys":"reject"}},"swift":{"name":"IdentificationProvenanceDTO","declarationOrder":34}}}$result_v1_json$::JSONB;
$result_v1_schema$;
-- END FROZEN RESULT_V1_SCHEMA


-- Closed structural interpretation of the frozen private v1 ContractNode.
-- Fractional numbers are decimal strings. SQL validates spelling/range; trusted
-- Deno additionally enforces IEEE round-trip identity. This is not authority.
CREATE FUNCTION internal.initial_result_node_matches_v1(value JSONB, rule JSONB, depth INTEGER DEFAULT 0)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE field RECORD; item JSONB; scalar TEXT; numeric_value NUMERIC; units BIGINT; variant JSONB;
BEGIN
 IF depth<0 OR depth>12 OR value IS NULL OR rule IS NULL THEN RETURN FALSE; END IF;
 IF value='null'::JSONB THEN RETURN COALESCE((rule->>'nullable')::BOOLEAN,FALSE); END IF;
 CASE rule->>'kind'
 WHEN 'union' THEN
  IF jsonb_typeof(value)<>'object' OR jsonb_typeof(value->(rule->>'discriminator'))<>'number' THEN RETURN FALSE; END IF;
  numeric_value:=(value->>(rule->>'discriminator'))::NUMERIC;
  IF numeric_value<>trunc(numeric_value) OR abs(numeric_value)>9007199254740991 THEN RETURN FALSE; END IF;
  variant:=rule->'variants'->(numeric_value::BIGINT::TEXT);
  RETURN variant IS NOT NULL AND internal.initial_result_node_matches_v1(value,variant,depth);
 WHEN 'object' THEN
  IF jsonb_typeof(value)<>'object' OR (SELECT count(*) FROM jsonb_object_keys(value))>128 THEN RETURN FALSE; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(value) k WHERE NOT (rule->'fields') ? k) THEN RETURN FALSE; END IF;
  FOR field IN SELECT * FROM jsonb_each(rule->'fields') LOOP
   IF NOT value ? field.key THEN
    IF (field.value->>'required')::BOOLEAN THEN RETURN FALSE; END IF;
   ELSIF NOT internal.initial_result_node_matches_v1(value->field.key,field.value->'contract',depth+1) THEN RETURN FALSE;
   END IF;
  END LOOP;
  RETURN TRUE;
 WHEN 'array' THEN
  IF jsonb_typeof(value)<>'array' THEN RETURN FALSE; END IF;
  IF jsonb_array_length(value)<COALESCE((rule->>'minItems')::INTEGER,0)
    OR jsonb_array_length(value)>LEAST(COALESCE((rule->>'maxItems')::INTEGER,512),512) THEN RETURN FALSE; END IF;
  FOR item IN SELECT * FROM jsonb_array_elements(value) LOOP
   IF NOT internal.initial_result_node_matches_v1(item,rule->'items',depth+1) THEN RETURN FALSE; END IF;
  END LOOP;
  RETURN TRUE;
 WHEN 'boolean' THEN
  RETURN jsonb_typeof(value)='boolean' AND (NOT rule ? 'const' OR value=rule->'const');
 WHEN 'integer' THEN
  IF jsonb_typeof(value)<>'number' THEN RETURN FALSE; END IF;
  numeric_value:=(value::TEXT)::NUMERIC;
  RETURN numeric_value=trunc(numeric_value) AND abs(numeric_value)<=9007199254740991
    AND numeric_value BETWEEN (rule->>'minimum')::NUMERIC AND (rule->>'maximum')::NUMERIC;
 WHEN 'number' THEN
  IF jsonb_typeof(value)<>'string' THEN RETURN FALSE; END IF;
  scalar:=value#>>'{}';
  IF length(scalar)>327 OR scalar='-0' OR scalar !~ '^-?(0|[1-9][0-9]*)(\.[0-9]*[1-9])?$' THEN RETURN FALSE; END IF;
  numeric_value:=scalar::NUMERIC;
  RETURN numeric_value BETWEEN (rule->>'minimum')::NUMERIC AND (rule->>'maximum')::NUMERIC;
 WHEN 'string' THEN
  IF jsonb_typeof(value)<>'string' THEN RETURN FALSE; END IF;
  scalar:=value#>>'{}';
  -- PostgreSQL characters are Unicode scalars; JS limits count UTF-16 units.
  SELECT COALESCE(sum(CASE WHEN ascii(c)>65535 THEN 2 ELSE 1 END),0) INTO units
    FROM regexp_split_to_table(scalar,'') c;
  RETURN units>=COALESCE((rule->>'minLength')::INTEGER,0)
    AND units<=COALESCE((rule->>'maxLength')::INTEGER,1048576)
    AND (NOT rule ? 'enum' OR rule->'enum' @> jsonb_build_array(scalar))
    AND (NOT rule ? 'pattern' OR substring(scalar FROM (rule->>'pattern')) IS NOT DISTINCT FROM scalar);
 ELSE RETURN FALSE;
 END CASE;
END;
$body$;

-- Version-one semantic rules match the frozen Edge validator, not current DTOs.
CREATE FUNCTION internal.initial_result_primary_matches_v1(data JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE primary_value JSONB:=data->'primary_identification'; resolution TEXT; name TEXT; key TEXT; candidates JSONB;
 whitespace TEXT:=U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF';
BEGIN
 IF internal.initial_result_node_matches_v1(data,internal.initial_result_schema_v1()->'data') IS NOT TRUE THEN RETURN FALSE; END IF;
 IF COALESCE(data#>>'{identification_provenance,schema}'='merian_identify_primary_v1',FALSE)
   IS DISTINCT FROM (data ? 'primary_identification') THEN RETURN FALSE; END IF;
 candidates:=CASE WHEN jsonb_typeof(data->'candidates')='array' THEN data->'candidates' ELSE '[]'::JSONB END;
 IF primary_value IS NULL THEN
  RETURN NOT EXISTS(SELECT 1 FROM jsonb_array_elements(candidates) c WHERE c ? 'taxon_rank');
 END IF;
 -- Object field bounds and sanitized names keep this snapshot below4096 bytes.
 FOREACH key IN ARRAY ARRAY['scientific_name','common_name'] LOOP
  name:=primary_value->>key;
  IF name IS NOT NULL AND (name<>btrim(name,whitespace)
    OR EXISTS(SELECT 1 FROM regexp_split_to_table(name,'') c WHERE ascii(c)<=31 OR ascii(c)=127)) THEN RETURN FALSE; END IF;
 END LOOP;
 resolution:=primary_value->>'resolution';
 IF (resolution IN ('species','genus','family') AND primary_value->'scientific_name'='null'::JSONB)
   OR (resolution='unresolved_biological' AND primary_value->'scientific_name'<>'null'::JSONB)
   OR data->'is_biological_subject' IS DISTINCT FROM to_jsonb(resolution<>'non_biological')
   OR data->'scientific_name' IS DISTINCT FROM primary_value->'scientific_name'
   OR data->'common_name' IS DISTINCT FROM primary_value->'common_name' THEN RETURN FALSE; END IF;
 IF resolution='species' THEN
  RETURN jsonb_array_length(candidates)<=2 AND NOT EXISTS(
    SELECT 1 FROM jsonb_array_elements(candidates) c WHERE c->>'taxon_rank' IS DISTINCT FROM 'species');
 END IF;
 IF data->'candidates' IS DISTINCT FROM 'null'::JSONB OR data->'pet_identification' IS DISTINCT FROM 'null'::JSONB
   OR data->'is_new_to_merian_dictionary' IS DISTINCT FROM 'false'::JSONB THEN RETURN FALSE; END IF;
 FOREACH key IN ARRAY ARRAY['gbif_taxon_key','reference_image_url','wikipedia_url','wikipedia_overview','species_insights','iucn_red_list_status','alternative_common_names'] LOOP
  IF data ? key AND data->key<>'null'::JSONB THEN RETURN FALSE; END IF;
 END LOOP;
 RETURN resolution<>'family' OR data#>'{taxonomy,genus}' IS NULL OR data#>'{taxonomy,genus}'='null'::JSONB;
END;
$body$;

CREATE FUNCTION internal.initial_result_usage_matches_v1(value JSONB,provider TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE key TEXT; n NUMERIC; categories JSONB; category JSONB; member RECORD;
 counters TEXT[]:=ARRAY['input_tokens','cached_tokens','cache_write_tokens','output_tokens','candidate_tokens','thinking_tokens','tool_tokens','total_tokens'];
BEGIN
 IF value IS NULL OR jsonb_typeof(value)<>'object' OR provider IS NULL OR provider NOT IN ('gemini','openai') THEN RETURN FALSE; END IF;
 IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(value) k) IS DISTINCT FROM
   (SELECT array_agg(k ORDER BY k) FROM unnest(counters||ARRAY['service_tier','modality_breakdown']) k) THEN RETURN FALSE; END IF;
 IF octet_length(internal.initial_canonical(value))>2048 THEN RETURN FALSE; END IF;
 FOREACH key IN ARRAY counters LOOP
  IF value->key='null'::JSONB THEN CONTINUE; END IF;
  IF jsonb_typeof(value->key)<>'number' THEN RETURN FALSE; END IF;
  n:=(value->>key)::NUMERIC;
  IF n<>trunc(n) OR n<0 OR n>100000000 THEN RETURN FALSE; END IF;
 END LOOP;
 IF value->'service_tier' NOT IN ('null'::JSONB,'"default"'::JSONB) THEN RETURN FALSE; END IF;
 categories:=value->'modality_breakdown';
 IF jsonb_typeof(categories)<>'object' THEN RETURN FALSE; END IF;
 IF provider='openai' THEN RETURN categories='{}'::JSONB; END IF;
 IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(categories) k) IS DISTINCT FROM ARRAY['cached','candidates','prompt','tool']::TEXT[] THEN RETURN FALSE; END IF;
 FOR category IN SELECT v FROM jsonb_each(categories) c(k,v) LOOP
  IF jsonb_typeof(category)<>'object' THEN RETURN FALSE; END IF;
  FOR member IN SELECT * FROM jsonb_each(category) LOOP
   IF member.key NOT IN ('text','image','audio','video') OR jsonb_typeof(member.value)<>'number' THEN RETURN FALSE; END IF;
   n:=(member.value::TEXT)::NUMERIC;
   IF n<>trunc(n) OR n<0 OR n>100000000 THEN RETURN FALSE; END IF;
  END LOOP;
 END LOOP;
 RETURN TRUE;
END;
$body$;

-- Pure parser for fixed data/provenance and primary semantics. The consuming
-- writer must still enforce original authority and exact witness consumption.
CREATE FUNCTION internal.parse_initial_result_data_v1(p_data TEXT,p_provenance TEXT)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE data JSONB; provenance JSONB; schema JSONB:=internal.initial_result_schema_v1();
BEGIN
 IF p_data IS NULL OR p_provenance IS NULL OR octet_length(p_data)>1048576 OR octet_length(p_provenance)>65536 THEN
  RAISE EXCEPTION 'initial_analysis_result_invalid' USING ERRCODE='22023'; END IF;
 data:=p_data::JSONB; provenance:=p_provenance::JSONB;
 IF octet_length(data::TEXT)>1048576 OR octet_length(provenance::TEXT)>65536
  OR internal.initial_canonical(data) IS DISTINCT FROM p_data
  OR internal.initial_canonical(provenance) IS DISTINCT FROM p_provenance
  OR internal.initial_result_node_matches_v1(data,schema->'data') IS NOT TRUE
  OR internal.initial_result_node_matches_v1(provenance,schema->'provenance') IS NOT TRUE
  OR internal.initial_result_primary_matches_v1(data) IS NOT TRUE
  OR data->'identification_provenance' IS DISTINCT FROM provenance THEN
  RAISE EXCEPTION 'initial_analysis_result_invalid' USING ERRCODE='22023'; END IF;
 RETURN data;
END;
$body$;
-- Exact content/digest validation, not ownership or dispatch authority. The
-- consuming writer must compare these identities/provenance with locked original
-- facts, then consume its exact transaction witness before inserting a result.
CREATE FUNCTION internal.parse_initial_result_evidence_v1(
 p_result TEXT,p_provenance TEXT,p_result_digest TEXT,p_provenance_digest TEXT)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE result JSONB; data JSONB; key TEXT;
BEGIN
 IF p_result IS NULL OR p_provenance IS NULL OR p_result_digest IS NULL OR p_provenance_digest IS NULL
   OR octet_length(p_result)>1048576 OR octet_length(p_provenance)>65536
   OR p_result_digest !~ '^[0-9a-f]{64}$' OR p_provenance_digest !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_analysis_result_invalid' USING ERRCODE='22023'; END IF;
 result:=p_result::JSONB;
 IF jsonb_typeof(result)<>'object' OR octet_length(result::TEXT)>1048576
   OR internal.initial_canonical(result) IS DISTINCT FROM p_result THEN
  RAISE EXCEPTION 'initial_analysis_result_invalid' USING ERRCODE='22023'; END IF;
 IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(result) k) IS DISTINCT FROM
   ARRAY['config_digest','data','funding_binding_digest','invocation_id','provider_usage','scan_id','state','submission_digest','version']::TEXT[]
   OR result->'version' IS DISTINCT FROM '1'::JSONB OR result->'state' IS DISTINCT FROM '"validated_success"'::JSONB THEN
  RAISE EXCEPTION 'initial_analysis_result_invalid' USING ERRCODE='22023'; END IF;
 FOREACH key IN ARRAY ARRAY['scan_id','invocation_id'] LOOP
  IF jsonb_typeof(result->key)<>'string' OR result->>key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
   RAISE EXCEPTION 'initial_analysis_result_invalid' USING ERRCODE='22023'; END IF;
 END LOOP;
 FOREACH key IN ARRAY ARRAY['submission_digest','config_digest','funding_binding_digest'] LOOP
  IF jsonb_typeof(result->key)<>'string' OR result->>key !~ '^[0-9a-f]{64}$' THEN
   RAISE EXCEPTION 'initial_analysis_result_invalid' USING ERRCODE='22023'; END IF;
 END LOOP;
 data:=internal.parse_initial_result_data_v1(internal.initial_canonical(result->'data'),p_provenance);
 IF data->'scan_id' IS DISTINCT FROM result->'scan_id'
   OR internal.initial_result_usage_matches_v1(result->'provider_usage',data#>>'{identification_provenance,provider}') IS NOT TRUE
   OR p_result_digest IS DISTINCT FROM encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||p_result,'UTF8'),'sha256'),'hex')
   OR p_provenance_digest IS DISTINCT FROM encode(extensions.digest(convert_to('merian.initial-analysis.result-provenance.v1'||chr(10)||p_provenance,'UTF8'),'sha256'),'hex') THEN
  RAISE EXCEPTION 'initial_analysis_result_invalid' USING ERRCODE='22023'; END IF;
 RETURN result;
END;
$body$;
-- Fixed dispatch/report/result statement skeleton derived from effective508
-- writers. Dispatch remains unrecognized. Compositors derive exact images and
-- link cardinality from locked original facts; completion is intentionally absent.
CREATE FUNCTION internal.initial_consuming_statement_catalog(p_operation TEXT)
RETURNS JSONB LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
BEGIN
 CASE p_operation
 WHEN 'dispatch' THEN RETURN '[
  {"key":"quota.commit","relation":"internal.ai_quota_reservations","action":"UPDATE","rows":"one"},
  {"key":"quota.links.delete","relation":"internal.ai_quota_reservation_counters","action":"DELETE","rows":"original_links"},
  {"key":"invocation.insert","relation":"internal.identification_invocations","action":"INSERT","rows":"one"},
  {"key":"lifecycle.dispatch","relation":"internal.initial_analysis_lifecycle_fences","action":"UPDATE","rows":"one"}
 ]'::JSONB;
 WHEN 'report' THEN RETURN '[
  {"key":"usage.insert","relation":"public.ai_usage_events","action":"INSERT","rows":"zero_or_one"},
  {"key":"invocation.account","relation":"internal.identification_invocations","action":"UPDATE","rows":"one"}
 ]'::JSONB;
 WHEN 'result' THEN RETURN '[
  {"key":"result.insert","relation":"internal.initial_analysis_results","action":"INSERT","rows":"one"}
 ]'::JSONB;
 ELSE RAISE EXCEPTION 'initial_analysis_consuming_operation_unavailable' USING ERRCODE='22023';
 END CASE;
END;
$body$;

-- Exact comparison of a secret-redacted row projection, not a literal row.
-- Shared expected-image and OLD/NEW paths must call this same private function.
-- SQL NULL means no row; JSON null lease remains null, never a placeholder hash.
CREATE FUNCTION internal.initial_consuming_row_image(p_relation TEXT,p_row JSONB)
RETURNS JSONB LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE expected TEXT[]; token TEXT;
BEGIN
 CASE p_relation
 WHEN 'internal.ai_quota_reservations' THEN expected:=ARRAY['attempt_count','client_protocol','committed_at','complimentary_client_scan_id','created_at','daily_limit','daily_remaining_after_reservation','effective_plan','effective_tier','entitlement_version','failed_at','flash_fallback_used','id','lease_expires_at','lease_token','model','operation','original_analysis_id','policy_version','refund_count','refunded_at','request_id','reserved_at','stale_recovery_count','state','subscription_tier','trial_active','updated_at','user_id']::TEXT[];
 WHEN 'internal.ai_quota_reservation_counters' THEN expected:=ARRAY['bucket','reservation_id','scope_key','scope_type','window_start']::TEXT[];
 WHEN 'internal.identification_invocations' THEN expected:=ARRAY['attempt_count','binding','effective_plan','event_id','id','initial_admission_receipt_id','input_profile','is_initial_analysis','lease_sha256','model','native_price','occurred_at','policy_version','provenance','provider','reservation_id','scan_id','user_id']::TEXT[];
 WHEN 'public.ai_usage_events' THEN expected:=ARRAY['cached_tokens','candidate_tokens','conversation_id','coverage_scope','created_at','effective_plan','estimated_cost_microusd','id','input_modality','is_backfilled','message_id','metadata','model','occurred_at','operation','outcome','pricing_version','prompt_tokens','prompt_tokens_by_modality','scan_id','source_id','source_type','thinking_tokens','tool_tokens','total_tokens','user_id']::TEXT[];
 WHEN 'internal.initial_analysis_results' THEN expected:=ARRAY['owner_id','provenance_snapshot','result_evidence_id','result_schema_version','result_snapshot','scan_id']::TEXT[];
 WHEN 'internal.initial_analysis_lifecycle_fences' THEN expected:=ARRAY['scan_id','state']::TEXT[];
 ELSE RAISE EXCEPTION 'initial_analysis_consuming_relation_unavailable' USING ERRCODE='22023';
 END CASE;
 IF p_row IS NULL THEN RETURN NULL; END IF;
 IF jsonb_typeof(p_row)<>'object' OR octet_length(p_row::TEXT)>2097152
   OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_row) k) IS DISTINCT FROM expected THEN
  RAISE EXCEPTION 'initial_analysis_consuming_image_invalid' USING ERRCODE='22023'; END IF;
 IF p_relation='internal.ai_quota_reservations' THEN
  IF p_row->'lease_token'='null'::JSONB THEN
   RETURN (p_row-'lease_token')||jsonb_build_object('lease_sha256',NULL);
  END IF;
  IF jsonb_typeof(p_row->'lease_token')<>'string' THEN
   RAISE EXCEPTION 'initial_analysis_consuming_image_invalid' USING ERRCODE='22023'; END IF;
  token:=p_row->>'lease_token';
  IF token !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
   RAISE EXCEPTION 'initial_analysis_consuming_image_invalid' USING ERRCODE='22023'; END IF;
  RETURN (p_row-'lease_token')||jsonb_build_object('lease_sha256',encode(extensions.digest(convert_to((token::UUID)::TEXT,'UTF8'),'sha256'),'hex'));
 END IF;
 RETURN p_row;
END;
$body$;
REVOKE ALL ON FUNCTION internal.initial_result_schema_v1(),
 internal.initial_result_node_matches_v1(JSONB,JSONB,INTEGER),internal.parse_initial_result_data_v1(TEXT,TEXT),
 internal.initial_result_primary_matches_v1(JSONB),internal.initial_result_usage_matches_v1(JSONB,TEXT),
 internal.parse_initial_result_evidence_v1(TEXT,TEXT,TEXT,TEXT),
 internal.initial_consuming_statement_catalog(TEXT),internal.initial_consuming_row_image(TEXT,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;
-- Transaction-local witness mechanics. Private report/result observers recognize
-- their bound variants; dispatch remains unrecognized. Fixed compositors must construct expectations from
-- locked original facts; API callers cannot create or mutate a stage.
CREATE TABLE internal.initial_consuming_staging (
 transaction_id XID8 PRIMARY KEY,
 scan_id UUID NOT NULL,
 owner_id UUID NOT NULL,
 operation TEXT NOT NULL CHECK(operation IN ('dispatch','report','result')),
 admission_receipt_id UUID NOT NULL,
 admission_receipt_digest TEXT NOT NULL CHECK(admission_receipt_digest ~ '^[0-9a-f]{64}$'),
 reservation_id UUID NOT NULL,
 invocation_id UUID NOT NULL,
 result_evidence_id UUID,
 expected_writes JSONB NOT NULL,
 report_invocation JSONB,
 result_invocation JSONB,
 CHECK(operation='result' OR result_invocation IS NULL),
 report_winner JSONB,
 report_inserted BOOLEAN,
 CHECK((operation='report')=(report_invocation IS NOT NULL)),
 CHECK(operation='report' OR (report_winner IS NULL AND report_inserted IS NULL)),
 next_statement INTEGER NOT NULL DEFAULT 0,
 statement_active BOOLEAN NOT NULL DEFAULT FALSE,
 pending_rows INTEGER[] NOT NULL DEFAULT '{}',
 observed_rows INTEGER[] NOT NULL DEFAULT '{}',
 sealed BOOLEAN NOT NULL DEFAULT FALSE,
 CHECK((operation='result')=(result_evidence_id IS NOT NULL))
);
ALTER TABLE internal.initial_consuming_staging ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_consuming_staging FROM PUBLIC,anon,authenticated,service_role;

-- Validate only the closed witness representation here. This is deliberately
-- not a substitute for a compositor's original-authority/live-fence checks.
CREATE FUNCTION internal.assert_initial_consuming_expectations(p_operation TEXT,p_writes JSONB)
RETURNS VOID LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE catalog JSONB:=internal.initial_consuming_statement_catalog(p_operation); group_value JSONB;
 entry JSONB; image JSONB; projected JSONB; spec JSONB; side TEXT; idx INTEGER; row_count INTEGER;
BEGIN
 IF p_writes IS NULL OR jsonb_typeof(p_writes)<>'array' OR octet_length(p_writes::TEXT)>8388608
   OR jsonb_array_length(p_writes)<>jsonb_array_length(catalog) THEN
  RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
 FOR idx IN 0..jsonb_array_length(catalog)-1 LOOP
  spec:=catalog->idx; group_value:=p_writes->idx;
  IF jsonb_typeof(group_value)<>'array' THEN
   RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
  row_count:=jsonb_array_length(group_value);
  IF row_count>256 OR (p_operation='report' AND row_count<>1) OR (spec->>'rows'='one' AND row_count<>1)
    OR (spec->>'rows'='zero_or_one' AND row_count>1)
    OR (SELECT count(DISTINCT v) FROM jsonb_array_elements(group_value) v)<>row_count THEN
   RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
  FOR entry IN SELECT * FROM jsonb_array_elements(group_value) LOOP
   IF jsonb_typeof(entry)<>'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(entry) k)
      IS DISTINCT FROM ARRAY['new','old']::TEXT[] THEN
    RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
   IF (spec->>'action'='INSERT' AND (entry->'old'<>'null'::JSONB OR jsonb_typeof(entry->'new')<>'object'))
     OR (spec->>'action'='DELETE' AND (entry->'new'<>'null'::JSONB OR jsonb_typeof(entry->'old')<>'object'))
     OR (spec->>'action'='UPDATE' AND (jsonb_typeof(entry->'old')<>'object' OR jsonb_typeof(entry->'new')<>'object')) THEN
    RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
   FOREACH side IN ARRAY ARRAY['old','new'] LOOP
    image:=entry->side;
    IF image='null'::JSONB THEN CONTINUE; END IF;
    IF spec->>'relation'='internal.ai_quota_reservations' THEN
     IF image ? 'lease_token' OR NOT image ? 'lease_sha256'
       OR (image->'lease_sha256'<>'null'::JSONB AND (jsonb_typeof(image->'lease_sha256')<>'string'
           OR image->>'lease_sha256' !~ '^[0-9a-f]{64}$')) THEN
      RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
     projected:=internal.initial_consuming_row_image(spec->>'relation',(image-'lease_sha256')||'{"lease_token":null}'::JSONB);
     IF projected-'lease_sha256' IS DISTINCT FROM image-'lease_sha256' THEN
      RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
    ELSE
     PERFORM internal.initial_consuming_row_image(spec->>'relation',image);
    END IF;
   END LOOP;
  END LOOP;
 END LOOP;
END;
$body$;

-- Report keeps the once-prepared candidate separate from the actual winner.
-- These private mechanics confer no original authority or business-guard bypass.
CREATE FUNCTION internal.initial_report_expected_writes(p_invocation JSONB,p_candidate JSONB)
RETURNS JSONB LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
BEGIN
 PERFORM internal.initial_consuming_row_image('internal.identification_invocations',p_invocation);
 PERFORM internal.initial_consuming_row_image('public.ai_usage_events',p_candidate);
 IF p_invocation IS NULL OR p_candidate IS NULL OR p_invocation->'event_id' IS DISTINCT FROM 'null'::JSONB
  OR p_candidate->>'id' IS NULL OR p_candidate->>'source_type' IS DISTINCT FROM 'identification_invocation'
  OR p_candidate->'source_id' IS DISTINCT FROM p_invocation->'id'
  OR p_candidate->>'operation' IS DISTINCT FROM 'scan_identification'
  OR p_candidate->'user_id' IS DISTINCT FROM p_invocation->'user_id'
  OR p_candidate->'scan_id' IS DISTINCT FROM p_invocation->'scan_id' THEN
  RAISE EXCEPTION 'initial_analysis_report_candidate_invalid' USING ERRCODE='55000'; END IF;
 RETURN jsonb_build_array(jsonb_build_array(jsonb_build_object('old',NULL,'new',p_candidate)),
  jsonb_build_array(jsonb_build_object('old',p_invocation,'new',p_invocation||jsonb_build_object('event_id',p_candidate->'id'))));
END;
$body$;
CREATE FUNCTION internal.initial_consuming_expected_group(p_stage internal.initial_consuming_staging)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
 SELECT CASE WHEN p_stage.operation='report' AND p_stage.next_statement=1 THEN
  jsonb_build_array(jsonb_build_object('old',p_stage.report_invocation,
   'new',p_stage.report_invocation||jsonb_build_object('event_id',p_stage.report_winner->'id')))
 ELSE p_stage.expected_writes->p_stage.next_statement END
$body$;
CREATE FUNCTION internal.assert_initial_report_terminal(p_stage internal.initial_consuming_staging)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
BEGIN
 IF p_stage.operation<>'report' THEN RETURN; END IF;
 IF p_stage.report_winner IS NULL OR p_stage.report_inserted IS NULL OR NOT p_stage.sealed
  OR p_stage.next_statement<>2 OR p_stage.statement_active OR p_stage.pending_rows<>'{}'::INTEGER[]
  OR p_stage.observed_rows<>'{}'::INTEGER[]
  OR p_stage.expected_writes IS DISTINCT FROM internal.initial_report_expected_writes(p_stage.report_invocation,p_stage.expected_writes#>'{0,0,new}')
  OR p_stage.report_winner->>'source_type' IS DISTINCT FROM 'identification_invocation'
  OR p_stage.report_winner->>'operation' IS DISTINCT FROM 'scan_identification'
  OR p_stage.report_winner->>'source_id' IS DISTINCT FROM p_stage.invocation_id::TEXT
  OR (p_stage.report_inserted AND p_stage.report_winner IS DISTINCT FROM p_stage.expected_writes#>'{0,0,new}')
  OR (SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE id=(p_stage.report_winner->>'id')::UUID) IS DISTINCT FROM p_stage.report_winner
  OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=p_stage.invocation_id)
    IS DISTINCT FROM p_stage.report_invocation||jsonb_build_object('event_id',p_stage.report_winner->'id') THEN
  RAISE EXCEPTION 'initial_analysis_report_incomplete' USING ERRCODE='55000'; END IF;
END;
$body$;
REVOKE ALL ON FUNCTION internal.initial_report_expected_writes(JSONB,JSONB),
 internal.initial_consuming_expected_group(internal.initial_consuming_staging),
 internal.assert_initial_report_terminal(internal.initial_consuming_staging) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_initial_consuming_stage()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE immutable_old JSONB; immutable_new JSONB; total INTEGER; count_rows INTEGER; lock_key INTEGER; row_index INTEGER;
BEGIN
 IF TG_OP='TRUNCATE' THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 IF (CASE WHEN TG_OP='DELETE' THEN OLD.transaction_id ELSE NEW.transaction_id END)
     IS DISTINCT FROM pg_catalog.pg_current_xact_id() THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 IF TG_OP='DELETE' THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR NOT OLD.sealed OR OLD.statement_active OR OLD.pending_rows<>'{}'::INTEGER[]
    OR OLD.observed_rows<>'{}'::INTEGER[] OR OLD.next_statement<>jsonb_array_length(OLD.expected_writes) THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_incomplete' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_report_terminal(OLD);
  PERFORM internal.assert_initial_result_terminal(OLD);
  RETURN OLD;
 END IF;
 IF TG_OP='INSERT' THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR current_setting('transaction_isolation')<>'read committed'
    OR NEW.next_statement<>0 OR NEW.statement_active OR NEW.pending_rows<>'{}'::INTEGER[]
    OR NEW.observed_rows<>'{}'::INTEGER[] OR NEW.sealed THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
  IF NEW.operation='report' THEN
   PERFORM internal.initial_consuming_row_image('internal.identification_invocations',NEW.report_invocation);
   IF NEW.expected_writes<>'[]'::JSONB OR NEW.report_winner IS NOT NULL OR NEW.report_inserted IS NOT NULL
    OR NEW.report_invocation->>'id' IS DISTINCT FROM NEW.invocation_id::TEXT
    OR NEW.report_invocation->>'user_id' IS DISTINCT FROM NEW.owner_id::TEXT
    OR NEW.report_invocation->>'scan_id' IS DISTINCT FROM NEW.scan_id::TEXT
    OR NEW.report_invocation->>'reservation_id' IS DISTINCT FROM NEW.reservation_id::TEXT
    OR NEW.report_invocation->>'initial_admission_receipt_id' IS DISTINCT FROM NEW.admission_receipt_id::TEXT
    OR NEW.report_invocation->'is_initial_analysis' IS DISTINCT FROM 'true'::JSONB
    OR NEW.report_invocation->'event_id' IS DISTINCT FROM 'null'::JSONB
    OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=NEW.invocation_id) IS DISTINCT FROM NEW.report_invocation THEN
    RAISE EXCEPTION 'initial_analysis_report_stage_invalid' USING ERRCODE='55000'; END IF;
  ELSE
   PERFORM internal.assert_initial_consuming_expectations(NEW.operation,NEW.expected_writes);
   IF NEW.operation='result' AND NEW.result_invocation IS NOT NULL THEN
    PERFORM internal.assert_initial_result_origin(NEW,TRUE);
   END IF;
  END IF;
  -- Denial-only transaction latch survives successful stage removal. A fully
  -- rolled-back subtransaction also rolls back its latch and all SQL effects.
  -- No lock/setting is ever accepted as original authority.
  lock_key:=pg_catalog.hashtext(NEW.transaction_id::TEXT);
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_locks l WHERE l.locktype='advisory' AND l.pid=pg_catalog.pg_backend_pid()
      AND l.classid=1396920143::OID AND l.objid::BIGINT=(lock_key::BIGINT & 4294967295) AND l.objsubid=2 AND l.granted)
    OR NOT pg_catalog.pg_try_advisory_xact_lock(1396920143,lock_key) THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_reused' USING ERRCODE='55000'; END IF;
  RETURN NEW;
 END IF;
 -- Only this one-way attachment may change expected_writes. The writer
 -- supplies its already-prepared row; validation never calls pricing again.
 IF OLD.operation='report' AND OLD.expected_writes='[]'::JSONB THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR OLD.statement_active OR OLD.next_statement<>0 OR OLD.sealed
   OR to_jsonb(OLD)-'expected_writes' IS DISTINCT FROM to_jsonb(NEW)-'expected_writes'
   OR NEW.expected_writes IS DISTINCT FROM internal.initial_report_expected_writes(OLD.report_invocation,NEW.expected_writes#>'{0,0,new}')
   OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=OLD.invocation_id) IS DISTINCT FROM OLD.report_invocation THEN
   RAISE EXCEPTION 'initial_analysis_report_attachment_invalid' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_consuming_expectations('report',NEW.expected_writes);
  RETURN NEW;
 END IF;
 -- One statement-resolution transition binds the actual locked event once.
 IF OLD.operation='report' AND OLD.next_statement=0 AND OLD.statement_active AND NOT NEW.statement_active THEN
  IF pg_catalog.pg_trigger_depth()<>2 OR OLD.report_winner IS NOT NULL OR OLD.report_inserted IS NOT NULL
   OR NEW.report_winner IS NULL OR NEW.report_inserted IS NULL OR NEW.next_statement<>1 OR NEW.sealed
   OR NEW.pending_rows<>'{}'::INTEGER[] OR NEW.observed_rows<>'{}'::INTEGER[]
   OR to_jsonb(OLD)-ARRAY['report_winner','report_inserted','statement_active','next_statement','pending_rows','observed_rows']
     IS DISTINCT FROM to_jsonb(NEW)-ARRAY['report_winner','report_inserted','statement_active','next_statement','pending_rows','observed_rows']
   OR NOT ((OLD.pending_rows='{}'::INTEGER[] AND OLD.observed_rows=ARRAY[0] AND NEW.report_inserted)
     OR (OLD.pending_rows=ARRAY[0] AND OLD.observed_rows='{}'::INTEGER[] AND NOT NEW.report_inserted))
   OR NEW.report_winner->>'source_type' IS DISTINCT FROM 'identification_invocation'
   OR NEW.report_winner->>'operation' IS DISTINCT FROM 'scan_identification'
   OR NEW.report_winner->>'source_id' IS DISTINCT FROM OLD.invocation_id::TEXT
   OR (NEW.report_inserted AND NEW.report_winner IS DISTINCT FROM OLD.expected_writes#>'{0,0,new}')
   OR (NOT NEW.report_inserted AND NEW.report_winner->'id'=OLD.expected_writes#>'{0,0,new,id}')
   OR (SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE id=(NEW.report_winner->>'id')::UUID) IS DISTINCT FROM NEW.report_winner THEN
   RAISE EXCEPTION 'initial_analysis_report_resolution_invalid' USING ERRCODE='55000'; END IF;
  PERFORM internal.initial_consuming_row_image('public.ai_usage_events',NEW.report_winner);
  RETURN NEW;
 END IF;
 immutable_old:=to_jsonb(OLD)-ARRAY['next_statement','statement_active','pending_rows','observed_rows','sealed'];
 immutable_new:=to_jsonb(NEW)-ARRAY['next_statement','statement_active','pending_rows','observed_rows','sealed'];
 IF pg_catalog.pg_trigger_depth()<>2 OR OLD.sealed OR immutable_old IS DISTINCT FROM immutable_new THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 total:=jsonb_array_length(OLD.expected_writes);
 count_rows:=jsonb_array_length(OLD.expected_writes->OLD.next_statement);
 IF NOT OLD.statement_active AND NEW.statement_active THEN
  IF to_jsonb(OLD)-'statement_active' IS DISTINCT FROM to_jsonb(NEW)-'statement_active' THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 ELSIF OLD.statement_active AND NEW.statement_active AND cardinality(NEW.pending_rows)=cardinality(OLD.pending_rows)+1 THEN
  row_index:=NEW.pending_rows[cardinality(NEW.pending_rows)];
  IF row_index IS NULL OR row_index<0 OR row_index>=count_rows OR row_index=ANY(OLD.observed_rows||OLD.pending_rows)
    OR NEW.pending_rows IS DISTINCT FROM OLD.pending_rows||row_index
    OR to_jsonb(OLD)-'pending_rows' IS DISTINCT FROM to_jsonb(NEW)-'pending_rows' THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 ELSIF OLD.statement_active AND NEW.statement_active AND cardinality(NEW.observed_rows)=cardinality(OLD.observed_rows)+1 THEN
  row_index:=NEW.observed_rows[cardinality(NEW.observed_rows)];
  IF row_index IS NULL OR NOT row_index=ANY(OLD.pending_rows) OR NEW.observed_rows IS DISTINCT FROM OLD.observed_rows||row_index
    OR NEW.pending_rows IS DISTINCT FROM array_remove(OLD.pending_rows,row_index)
    OR to_jsonb(OLD)-ARRAY['pending_rows','observed_rows'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['pending_rows','observed_rows'] THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 ELSIF OLD.statement_active AND NOT NEW.statement_active THEN
  IF OLD.pending_rows<>'{}'::INTEGER[] OR cardinality(OLD.observed_rows)<>count_rows
    OR NEW.pending_rows<>'{}'::INTEGER[] OR NEW.observed_rows<>'{}'::INTEGER[] OR NEW.next_statement<>OLD.next_statement+1
    OR NEW.sealed IS DISTINCT FROM (NEW.next_statement=total) THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_incomplete' USING ERRCODE='55000'; END IF;
 ELSE RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000';
 END IF;
 RETURN NEW;
END;
$body$;
CREATE TRIGGER guard_initial_consuming_stage BEFORE INSERT OR UPDATE OR DELETE
 ON internal.initial_consuming_staging FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_stage();
CREATE TRIGGER guard_initial_consuming_stage_truncate BEFORE TRUNCATE
 ON internal.initial_consuming_staging FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_stage();

CREATE FUNCTION internal.require_complete_initial_consuming_stage()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $body$
DECLARE captured internal.initial_consuming_staging;
BEGIN
 captured:=CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
 IF captured.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
   OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging WHERE transaction_id=captured.transaction_id)
   OR (TG_OP='DELETE' AND (NOT captured.sealed OR captured.statement_active OR captured.pending_rows<>'{}'::INTEGER[]
     OR captured.observed_rows<>'{}'::INTEGER[] OR captured.next_statement<>jsonb_array_length(captured.expected_writes))) THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_incomplete' USING ERRCODE='55000'; END IF;
 IF TG_OP='DELETE' THEN
  PERFORM internal.assert_initial_report_terminal(captured);
  PERFORM internal.assert_initial_result_terminal(captured);
 END IF;
 -- Dispatch still requires its operation-specific terminal assertion before
 -- any business guard recognizes that mechanical witness.
 RETURN NULL;
END;
$body$;
-- Entry and terminal deletion are sufficient sentinels: immediate UPDATE guards
-- preserve immutable facts and progression. Avoid retaining a full expectation
-- snapshot per row-progress update in the deferred event queue.
CREATE CONSTRAINT TRIGGER require_complete_initial_consuming_stage
 AFTER INSERT OR DELETE ON internal.initial_consuming_staging
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.require_complete_initial_consuming_stage();

-- Paired adapter: resolve the real trigger relation, never a caller alias.
-- Only reviewed report/result graphs are installed; dispatch remains unattached.
CREATE FUNCTION internal.guard_initial_consuming_member()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE stage internal.initial_consuming_staging; spec JSONB; images JSONB; idx INTEGER; winner JSONB;
 relation_name TEXT:=TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME;
BEGIN
 SELECT * INTO stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_catalog.pg_current_xact_id();
 IF NOT FOUND OR (TG_NARGS=1 AND stage.operation IS DISTINCT FROM TG_ARGV[0]) THEN
  IF TG_LEVEL='STATEMENT' OR TG_WHEN='AFTER' THEN RETURN NULL; END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
 END IF;
 spec:=internal.initial_consuming_statement_catalog(stage.operation)->stage.next_statement;
 IF stage.sealed OR (stage.operation='report' AND stage.expected_writes='[]'::JSONB) OR TG_OP='TRUNCATE' OR spec->>'relation' IS DISTINCT FROM relation_name
   OR spec->>'action' IS DISTINCT FROM TG_OP THEN
  RAISE EXCEPTION 'initial_analysis_consuming_statement_invalid' USING ERRCODE='55000'; END IF;
 IF TG_LEVEL='STATEMENT' THEN
  IF TG_WHEN='BEFORE' THEN
   IF stage.statement_active OR stage.pending_rows<>'{}'::INTEGER[] OR stage.observed_rows<>'{}'::INTEGER[] THEN
    RAISE EXCEPTION 'initial_analysis_consuming_statement_invalid' USING ERRCODE='55000'; END IF;
   UPDATE internal.initial_consuming_staging SET statement_active=TRUE WHERE transaction_id=stage.transaction_id;
  ELSE
   IF stage.operation='report' AND stage.next_statement=0 THEN
    IF NOT stage.statement_active OR NOT ((stage.pending_rows=ARRAY[0] AND stage.observed_rows='{}'::INTEGER[])
      OR (stage.pending_rows='{}'::INTEGER[] AND stage.observed_rows=ARRAY[0])) THEN
     RAISE EXCEPTION 'initial_analysis_report_resolution_invalid' USING ERRCODE='55000'; END IF;
    -- Invocation is already locked. Only the fixed source event is acquired
    -- here; no parent, receipt or owner lookup follows this lock.
    SELECT to_jsonb(e) INTO winner FROM public.ai_usage_events e
     WHERE source_type='identification_invocation' AND source_id=stage.invocation_id AND operation='scan_identification' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_report_winner_missing' USING ERRCODE='55000'; END IF;
    UPDATE internal.initial_consuming_staging SET statement_active=FALSE,next_statement=1,
     pending_rows='{}',observed_rows='{}',report_winner=winner,report_inserted=(stage.observed_rows=ARRAY[0])
     WHERE transaction_id=stage.transaction_id;
    RETURN NULL;
   END IF;
   IF NOT stage.statement_active OR stage.pending_rows<>'{}'::INTEGER[]
     OR cardinality(stage.observed_rows)<>jsonb_array_length(stage.expected_writes->stage.next_statement) THEN
    RAISE EXCEPTION 'initial_analysis_consuming_stage_incomplete' USING ERRCODE='55000'; END IF;
   UPDATE internal.initial_consuming_staging SET statement_active=FALSE,next_statement=next_statement+1,
     observed_rows='{}',sealed=(next_statement+1=jsonb_array_length(expected_writes)) WHERE transaction_id=stage.transaction_id;
  END IF;
  RETURN NULL;
 END IF;
 IF NOT stage.statement_active THEN
  RAISE EXCEPTION 'initial_analysis_consuming_statement_invalid' USING ERRCODE='55000'; END IF;
 images:=jsonb_build_object('old',internal.initial_consuming_row_image(relation_name,CASE WHEN TG_OP='INSERT' THEN NULL ELSE to_jsonb(OLD) END),
   'new',internal.initial_consuming_row_image(relation_name,CASE WHEN TG_OP='DELETE' THEN NULL ELSE to_jsonb(NEW) END));
 IF TG_WHEN='BEFORE' THEN
  SELECT (ordinality-1)::INTEGER INTO idx FROM jsonb_array_elements(internal.initial_consuming_expected_group(stage)) WITH ORDINALITY e(value,ordinality)
    WHERE value=images AND NOT (ordinality-1)::INTEGER=ANY(stage.observed_rows||stage.pending_rows);
  IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_consuming_row_invalid' USING ERRCODE='55000'; END IF;
  UPDATE internal.initial_consuming_staging SET pending_rows=pending_rows||idx WHERE transaction_id=stage.transaction_id;
 ELSE
  SELECT (ordinality-1)::INTEGER INTO idx FROM jsonb_array_elements(internal.initial_consuming_expected_group(stage)) WITH ORDINALITY e(value,ordinality)
    WHERE value=images AND (ordinality-1)::INTEGER=ANY(stage.pending_rows);
  IF NOT FOUND THEN
   RAISE EXCEPTION 'initial_analysis_consuming_row_invalid' USING ERRCODE='55000'; END IF;
  UPDATE internal.initial_consuming_staging SET observed_rows=observed_rows||idx,pending_rows=array_remove(pending_rows,idx) WHERE transaction_id=stage.transaction_id;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION internal.assert_initial_consuming_expectations(TEXT,JSONB),
 internal.guard_initial_consuming_stage(),internal.require_complete_initial_consuming_stage(),
 internal.guard_initial_consuming_member() FROM PUBLIC,anon,authenticated,service_role;

-- Original receipt correlation has no FK: row-first accounting must never
-- acquire receipt/owner locks. Initial creation remains unavailable until the
-- complete dispatch AND C1 cancellation/erasure paths are integrated.
-- Fail before assigning ordinary defaults to any detectable legacy overlap.
-- Already-anonymized historical rows cannot be classified by this check.
-- Serialize both sides of the overlap check through column/guard installation.
-- Fence writers take their conflicting lock first; ordinary invocation writers
-- only read fences, so their AccessShare reads remain compatible with SHARE.
-- Initial admission can read invocations before inserting its fence. NOWAIT on
-- the second lock avoids waiting back on that reader while holding its fence
-- write lock; contention aborts this entire migration transaction.
DO $classification_isolation$
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'initial_analysis_classification_isolation_unavailable' USING ERRCODE='25000'; END IF;
END;
$classification_isolation$;
LOCK TABLE internal.initial_analysis_operation_fences IN SHARE MODE;
LOCK TABLE internal.identification_invocations IN ACCESS EXCLUSIVE MODE NOWAIT;
DO $preflight$
BEGIN
 IF EXISTS(SELECT 1 FROM internal.identification_invocations i
   JOIN internal.initial_analysis_operation_fences f ON f.scan_id=i.scan_id) THEN
  RAISE EXCEPTION 'initial_analysis_invocation_classification_required' USING ERRCODE='55000'; END IF;
END;
$preflight$;
ALTER TABLE internal.identification_invocations
 ADD COLUMN initial_admission_receipt_id UUID,
 ADD COLUMN is_initial_analysis BOOLEAN NOT NULL DEFAULT FALSE,
 ADD CONSTRAINT identification_invocations_initial_receipt_classification
 CHECK(is_initial_analysis OR initial_admission_receipt_id IS NULL);

-- Terminal accounting classification is row-local and one-way. It never
-- restores execution authority and does not depend on a missing receipt alone.
CREATE FUNCTION internal.initial_invocation_retired(p_row internal.identification_invocations)
RETURNS BOOLEAN LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
 SELECT COALESCE(p_row.is_initial_analysis AND p_row.event_id IS NOT NULL
  AND p_row.user_id IS NULL AND p_row.scan_id IS NULL AND p_row.reservation_id IS NULL
  AND p_row.lease_sha256 IS NULL AND p_row.initial_admission_receipt_id IS NULL,FALSE)
$body$;
CREATE FUNCTION internal.initial_invocation_retirement_transition(p_old internal.identification_invocations,p_new internal.identification_invocations)
RETURNS BOOLEAN LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
 SELECT COALESCE(p_old.is_initial_analysis AND p_old.event_id IS NOT NULL
  AND p_old.user_id IS NOT NULL AND p_old.scan_id IS NOT NULL AND p_old.reservation_id IS NOT NULL
  AND p_old.lease_sha256 IS NOT NULL AND p_old.initial_admission_receipt_id IS NOT NULL
  AND internal.initial_invocation_retired(p_new)
  AND to_jsonb(p_old)-ARRAY['user_id','scan_id','reservation_id','lease_sha256','initial_admission_receipt_id']
    =to_jsonb(p_new)-ARRAY['user_id','scan_id','reservation_id','lease_sha256','initial_admission_receipt_id'],FALSE)
$body$;

-- A direct UPDATE already holds its invocation row. All outer acquisitions in
-- this backstop are nonblocking, so it cannot wait back on an erasure owner.
CREATE FUNCTION internal.assert_initial_invocation_retirement(p_old internal.identification_invocations)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 PERFORM id FROM public.users WHERE id=p_old.user_id FOR UPDATE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_invocation_erasure_unavailable' USING ERRCODE='55000'; END IF;
 IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_old.scan_id::TEXT,0::BIGINT)) THEN
  RAISE EXCEPTION 'initial_analysis_erasure_busy' USING ERRCODE='55P03'; END IF;
 IF NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_old.scan_id)
   OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_old.scan_id) THEN
  RAISE EXCEPTION 'initial_analysis_invocation_erasure_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM scan_id FROM internal.initial_preparation_admission_receipts
  WHERE scan_id=p_old.scan_id AND owner_id=p_old.user_id AND admission_receipt_id=p_old.initial_admission_receipt_id
  FOR UPDATE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_invocation_erasure_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM id FROM internal.ai_quota_reservations WHERE id=p_old.reservation_id FOR UPDATE NOWAIT;
END;
$body$;

CREATE FUNCTION internal.require_initial_invocation_erasure()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
BEGIN
 IF NOT internal.initial_invocation_retirement_transition(OLD,NEW)
   OR NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.scan_id)
   OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=OLD.scan_id)
   OR EXISTS(SELECT 1 FROM internal.identification_invocations i WHERE id=OLD.id AND NOT internal.initial_invocation_retired(i))
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=OLD.scan_id)
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id=OLD.scan_id)
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=OLD.scan_id)
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=OLD.scan_id)
   OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=OLD.scan_id OR admission_receipt_id=OLD.initial_admission_receipt_id)
   OR EXISTS(SELECT 1 FROM internal.initial_preparation_execution_grants WHERE scan_id=OLD.scan_id) THEN
  RAISE EXCEPTION 'initial_analysis_invocation_erasure_incomplete' USING ERRCODE='55000'; END IF;
 RETURN NULL;
END;
$body$;
CREATE CONSTRAINT TRIGGER require_initial_invocation_erasure
 AFTER UPDATE ON internal.identification_invocations DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW WHEN (OLD.is_initial_analysis AND OLD.initial_admission_receipt_id IS NOT NULL AND NEW.initial_admission_receipt_id IS NULL)
 EXECUTE FUNCTION internal.require_initial_invocation_erasure();
REVOKE ALL ON FUNCTION internal.initial_invocation_retired(internal.identification_invocations),
 internal.initial_invocation_retirement_transition(internal.identification_invocations,internal.identification_invocations),
 internal.assert_initial_invocation_retirement(internal.identification_invocations),internal.require_initial_invocation_erasure()
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_initial_invocation_authority()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
BEGIN
 IF TG_OP='TRUNCATE' THEN
  IF EXISTS(SELECT 1 FROM internal.identification_invocations WHERE is_initial_analysis AND NOT internal.initial_invocation_retired(identification_invocations)) THEN
   RAISE EXCEPTION 'initial_analysis_invocation_retained' USING ERRCODE='55000'; END IF;
  RETURN NULL;
 END IF;
 IF TG_OP='DELETE' THEN
  IF OLD.is_initial_analysis AND NOT internal.initial_invocation_retired(OLD) THEN
   RAISE EXCEPTION 'initial_analysis_invocation_retained' USING ERRCODE='55000'; END IF;
  RETURN OLD;
 END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.is_initial_analysis OR NEW.initial_admission_receipt_id IS NOT NULL
    OR EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=NEW.scan_id) THEN
   RAISE EXCEPTION 'initial_analysis_dispatch_unavailable' USING ERRCODE='55000'; END IF;
  RETURN NEW;
 END IF;
 IF internal.initial_invocation_retirement_transition(OLD,NEW) THEN
  PERFORM internal.assert_initial_invocation_retirement(OLD);
  RETURN NEW;
 END IF;
 IF NEW.is_initial_analysis IS DISTINCT FROM OLD.is_initial_analysis
   OR NEW.initial_admission_receipt_id IS DISTINCT FROM OLD.initial_admission_receipt_id THEN
  RAISE EXCEPTION 'initial_analysis_invocation_immutable' USING ERRCODE='55000'; END IF;
 IF OLD.is_initial_analysis THEN
  -- The five-minute reconciler remains invocation-row-first. This exact fast
  -- path performs no receipt, user, lifecycle or other relation lookup/lock.
  IF to_jsonb(NEW)-'event_id' IS DISTINCT FROM to_jsonb(OLD)-'event_id'
    OR (OLD.event_id IS NOT NULL AND NEW.event_id IS DISTINCT FROM OLD.event_id) THEN
   RAISE EXCEPTION 'initial_analysis_invocation_immutable' USING ERRCODE='55000'; END IF;
 END IF;
 RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION internal.guard_initial_invocation_authority() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER a00_initial_invocation_authority BEFORE INSERT OR UPDATE OR DELETE ON internal.identification_invocations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_invocation_authority();
CREATE TRIGGER a00_initial_invocation_authority_truncate BEFORE TRUNCATE ON internal.identification_invocations
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_invocation_authority();

-- Only the thirty-day prune selection changes. Initial records require the
-- complete guarded retirement predicate; a missing receipt alone never suffices.
-- The five-minute unknown-usage loop remains byte-for-byte intact.
CREATE OR REPLACE FUNCTION internal.reconcile_identification_usage(p_limit integer DEFAULT 1000)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
 SET statement_timeout TO '15s'
AS $function$
DECLARE pending RECORD; reconciled INTEGER := 0;
BEGIN
    FOR pending IN SELECT id FROM internal.identification_invocations
        WHERE event_id IS NULL AND occurred_at < clock_timestamp() - INTERVAL '5 minutes'
        ORDER BY occurred_at LIMIT LEAST(GREATEST(COALESCE(p_limit, 1000), 1), 1000)
        FOR UPDATE SKIP LOCKED LOOP
        PERFORM internal.complete_identification_usage(pending.id, 'unknown_execution', '{}'::JSONB);
        reconciled := reconciled + 1;
    END LOOP;
    DELETE FROM internal.identification_invocations WHERE id IN (
        SELECT id FROM internal.identification_invocations
        WHERE (NOT is_initial_analysis OR internal.initial_invocation_retired(identification_invocations)) AND event_id IS NOT NULL AND occurred_at < clock_timestamp() - INTERVAL '30 days'
        ORDER BY occurred_at LIMIT LEAST(GREATEST(COALESCE(p_limit, 1000), 1), 1000)
        FOR UPDATE SKIP LOCKED
    );
    RETURN reconciled;
END;
$function$;


-- Preserve existing erasure owners and their shared member order.
CREATE OR REPLACE FUNCTION internal.lock_initial_media_handoff_erasure_rows(p_scan uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
    IF p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    PERFORM id FROM public.scans WHERE id=p_scan FOR UPDATE;
    PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
    -- Prelock original receipt/accounting before the shared media tail. Its
    -- later receipt acquisition is reentrant under the same owner/advisory scope.
    PERFORM scan_id FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan FOR UPDATE;
    PERFORM id FROM internal.ai_quota_reservations WHERE id IN (
      SELECT reservation_id FROM internal.identification_invocations WHERE scan_id=p_scan AND is_initial_analysis
    ) ORDER BY id FOR UPDATE;
    PERFORM id FROM internal.identification_invocations WHERE scan_id=p_scan AND is_initial_analysis ORDER BY id FOR UPDATE;
    PERFORM internal.lock_initial_media_handoff_members(p_scan);
END; $function$;

-- Private scan/account erasure only. C1 cancellation without a scan tombstone
-- is deliberately excluded until its exact cancellation write catalog is extended.
CREATE FUNCTION internal.retire_initial_invocation_authority(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE owner_id UUID; invocation internal.identification_invocations;
BEGIN
 IF p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan AND is_initial_analysis) THEN RETURN; END IF;
 SELECT user_id INTO STRICT owner_id FROM internal.identification_invocations WHERE scan_id=p_scan AND is_initial_analysis GROUP BY user_id;
 IF owner_id IS NULL OR current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'initial_analysis_invocation_erasure_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM id FROM public.users WHERE id=owner_id FOR UPDATE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_invocation_erasure_unavailable' USING ERRCODE='55000'; END IF;
 IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_scan::TEXT,0::BIGINT)) THEN
  RAISE EXCEPTION 'initial_analysis_erasure_busy' USING ERRCODE='55P03'; END IF;
 PERFORM internal.lock_initial_media_handoff_erasure_rows(p_scan);
 FOR invocation IN SELECT * FROM internal.identification_invocations WHERE scan_id=p_scan AND is_initial_analysis ORDER BY id FOR UPDATE LOOP
  PERFORM internal.assert_initial_invocation_retirement(invocation);
  PERFORM internal.complete_identification_usage(invocation.id,'unknown_execution','{}'::JSONB);
  UPDATE internal.identification_invocations SET user_id=NULL,scan_id=NULL,reservation_id=NULL,lease_sha256=NULL,initial_admission_receipt_id=NULL
   WHERE id=invocation.id;
 END LOOP;
END;
$body$;
REVOKE ALL ON FUNCTION internal.retire_initial_invocation_authority(UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.initial_media_handoff_erasure_identities(p_owner uuid)
 RETURNS TABLE(scan_id uuid)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
    SELECT scan_id FROM internal.initial_analysis_submissions WHERE owner_id=p_owner
    UNION SELECT scan_id FROM internal.identification_invocations WHERE user_id=p_owner AND is_initial_analysis AND scan_id IS NOT NULL
    UNION SELECT scan_id FROM internal.initial_analysis_preparation_intents WHERE owner_id=p_owner
    UNION SELECT candidates.scan_id FROM (
        SELECT id AS scan_id FROM public.scans WHERE user_id=p_owner
        UNION SELECT scan_id FROM internal.initial_analysis_cancellations WHERE owner_id=p_owner
        UNION SELECT scan_id FROM internal.initial_analysis_admissions WHERE owner_id=p_owner
        UNION SELECT scan_id FROM internal.initial_preparation_admission_receipts WHERE owner_id=p_owner
        UNION SELECT scan_id FROM internal.initial_media_copy_progress WHERE owner_id=p_owner
        UNION SELECT scan_id FROM internal.initial_media_verification_claims_v2 WHERE owner_id=p_owner
        UNION SELECT scan_id FROM internal.initial_media_verification_receipts_v2 WHERE owner_id=p_owner
        UNION SELECT scan_id FROM internal.initial_preparation_transfer_receipts WHERE owner_id=p_owner
        UNION SELECT original_analysis_id FROM internal.ai_quota_reservations WHERE user_id=p_owner
        UNION SELECT request_id FROM internal.ai_quota_reservations WHERE user_id=p_owner
        UNION SELECT client_scan_id FROM internal.complimentary_scan_usage WHERE user_id=p_owner
    ) AS candidates WHERE candidates.scan_id IS NOT NULL
        AND internal.initial_admitted_settlement_blocked(candidates.scan_id);
$function$;

CREATE OR REPLACE FUNCTION internal.guard_initial_preparation_provider_writer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE current_row JSONB:=to_jsonb(NEW); previous_row JSONB; key TEXT; identities UUID[]:=ARRAY[]::UUID[]; identity_changed BOOLEAN:=TG_OP='INSERT';
BEGIN
 IF TG_OP='UPDATE' THEN previous_row:=to_jsonb(OLD); END IF;
 IF TG_OP='UPDATE' AND TG_TABLE_SCHEMA='internal' AND TG_TABLE_NAME='identification_invocations'
   AND internal.initial_invocation_retirement_transition(
     jsonb_populate_record(NULL::internal.identification_invocations,previous_row),
     jsonb_populate_record(NULL::internal.identification_invocations,current_row)) THEN
  PERFORM internal.assert_initial_invocation_retirement(jsonb_populate_record(NULL::internal.identification_invocations,previous_row));
  RETURN NEW;
 END IF;
 -- Existing accounting anonymization can erase owner identity, never grant execution.
 IF TG_OP='UPDATE' AND TG_TABLE_NAME='identification_invocations' AND current_row->'user_id'='null'::JSONB AND current_row-'user_id'=previous_row-'user_id' THEN RETURN NEW; END IF;
 FOREACH key IN ARRAY TG_ARGV LOOP
  identity_changed:=identity_changed OR current_row->key IS DISTINCT FROM previous_row->key;
  identities:=array_append(identities,internal.source_child_uuid(current_row->>key));
  IF previous_row IS NOT NULL THEN identities:=array_append(identities,internal.source_child_uuid(previous_row->>key)); END IF;
 END LOOP;
 -- An existing row already excludes fresh allocation under its durable identity.
 -- Settlement/cleanup that cannot introduce a new identity keeps its old contract.
 IF NOT identity_changed THEN RETURN NEW; END IF;
 -- Preserve existing history ingress error identity even though this earlier
 -- trigger must reject the same stale snapshot before its own barrier lookup.
 IF current_setting('transaction_isolation')<>'read committed'
  AND TG_TABLE_NAME IN ('scans','scan_ingestion_jobs','scan_ingestion_intents','observation_analysis_source_bindings','observation_analysis_intents','observation_analysis_results','observation_histories')
  AND EXISTS(SELECT 1 FROM unnest(identities) u WHERE u IS NOT NULL) THEN RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;

 IF EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging s
  WHERE s.transaction_id=pg_catalog.pg_current_xact_id()
   AND s.stage_token::TEXT=current_setting('merian.initial_admission_stage',TRUE)
   AND internal.initial_admission_expected_write(s.scan_id,TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,TG_OP,previous_row,current_row,FALSE)) THEN
  RETURN NEW;
 END IF;
 PERFORM internal.reject_initial_preparation_provider_writer(identities);
 RETURN NEW;
END; $function$;

CREATE OR REPLACE FUNCTION internal.erase_initial_analysis_for_scan_fence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF internal.initial_admitted_settlement_blocked(NEW.scan_id)
   OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=NEW.scan_id AND is_initial_analysis) THEN
  PERFORM internal.lock_initial_media_handoff_erasure_rows(NEW.scan_id);
 END IF;
 PERFORM internal.fence_initial_analysis_erasure(NEW.scan_id);
 PERFORM internal.retire_initial_invocation_authority(NEW.scan_id);
 IF internal.initial_admitted_settlement_blocked(NEW.scan_id) THEN
     PERFORM internal.retire_initial_preparation_source_objects(NEW.scan_id);
     IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id) THEN
         PERFORM internal.retire_initial_media_objects(NEW.scan_id);
     END IF;
     DELETE FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id;
     DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id;
 ELSE
 DELETE FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id;
 PERFORM internal.retire_initial_preparation_source_objects(NEW.scan_id);
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id;
 END IF;
 DELETE FROM internal.initial_analysis_cancellations WHERE scan_id=NEW.scan_id;
 RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.fence_initial_analysis_before_owner_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE identity UUID;
BEGIN
    -- Existing scan/history cleanup can settle funding and update the owner.
    -- Doing that inside its BEFORE DELETE would mutate the deleting tuple.
    -- The supported apply_user_tombstone path detaches scans first; reject raw
    -- privileged deletion until it has done that work, without partial erasure.
    IF EXISTS(SELECT 1 FROM internal.initial_media_handoff_erasure_identities(OLD.id) AS candidate
        JOIN public.scans AS scan ON scan.id=candidate.scan_id
        WHERE scan.user_id IS NOT NULL) THEN
        RAISE EXCEPTION 'initial_analysis_account_detachment_required' USING ERRCODE='55000';
    END IF;
    -- Pre-row evidence has no history/funding fanout. The deleting transaction
    -- owns this user row; sorted advisory locks precede private-row cascades.
    FOR identity IN SELECT scan_id FROM internal.initial_media_handoff_erasure_identities(OLD.id) ORDER BY scan_id LOOP
        PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:' || identity::TEXT,0::BIGINT));
        IF internal.initial_admitted_settlement_blocked(identity)
          OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=identity AND is_initial_analysis) THEN
            PERFORM internal.lock_initial_media_handoff_erasure_rows(identity);
        END IF;
        INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)
        VALUES(identity,NULL,clock_timestamp()) ON CONFLICT(scan_id) DO NOTHING;
        -- Existing tombstones do not rerun their callback. Invocation-only
        -- leftovers must still retire even when both private roots are absent.
        PERFORM internal.fence_initial_analysis_erasure(identity);
        PERFORM internal.retire_initial_invocation_authority(identity);
        IF internal.initial_admitted_settlement_blocked(identity) THEN
            -- A new tombstone already ran the callback; no second erasure
            -- is needed. Existing tombstones still require the locked fallback.
            IF EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=identity)
              OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity)
          OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=identity AND state<>'retired')
          OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=identity AND NOT retired)
          OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=identity AND state<>'retired')
          OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=identity AND NOT retired) THEN
            PERFORM internal.retire_initial_preparation_source_objects(identity);
            IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=identity) THEN
                PERFORM internal.retire_initial_media_objects(identity);
            END IF;
            DELETE FROM internal.initial_analysis_submissions WHERE scan_id=identity;
            DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;
            END IF;
        ELSE
        DELETE FROM internal.initial_analysis_submissions WHERE scan_id=identity;
        PERFORM internal.retire_initial_preparation_source_objects(identity);
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;
        END IF;
    END LOOP;
    RETURN OLD;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.fence_initial_analysis_erasure(p_scan uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan AND is_initial_analysis)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan) THEN
  INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES(p_scan) ON CONFLICT(scan_id) DO NOTHING;
  INSERT INTO internal.initial_analysis_lifecycle_fences(scan_id,state) VALUES(p_scan,'cancelled_unknown')
   ON CONFLICT(scan_id) DO UPDATE SET state=CASE
    WHEN initial_analysis_lifecycle_fences.state='dispatch_authorized' THEN 'cancelled_dispatched' ELSE 'cancelled_unknown' END
   WHERE initial_analysis_lifecycle_fences.state IN ('pending_pre_dispatch','dispatch_authorized');
 END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.guard_initial_analysis_tombstone_scope()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE owned_by UUID;
BEGIN
    -- One snapshot: a visible legacy scan without initial evidence cannot gain
    -- a first submission (admission rejects existing scans; scan INSERT shares
    -- its owner/advisory scope). Preserve legacy-only tombstone wait semantics.
    IF EXISTS(SELECT 1 FROM public.scans WHERE id=NEW.scan_id)
       AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id)
       AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id)
       AND NOT internal.initial_admitted_settlement_blocked(NEW.scan_id)
       AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=NEW.scan_id AND is_initial_analysis) THEN
        RETURN NEW;
    END IF;
    SELECT owner_id INTO owned_by FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id;
    IF owned_by IS NULL THEN SELECT owner_id INTO owned_by FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id; END IF;
    IF owned_by IS NULL THEN SELECT owner_id INTO owned_by FROM internal.initial_analysis_cancellations WHERE scan_id=NEW.scan_id; END IF;
    IF owned_by IS NULL THEN SELECT user_id INTO owned_by FROM internal.identification_invocations WHERE scan_id=NEW.scan_id AND is_initial_analysis LIMIT 1; END IF;
    IF owned_by IS NULL THEN SELECT user_id INTO owned_by FROM public.scans WHERE id=NEW.scan_id; END IF;
    IF owned_by IS NOT NULL THEN
        PERFORM id FROM public.users WHERE id=owned_by FOR UPDATE NOWAIT;
    END IF;
    IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:' || NEW.scan_id::TEXT,0::BIGINT)) THEN
        RAISE EXCEPTION 'initial_analysis_erasure_busy' USING ERRCODE='55P03';
    END IF;
    RETURN NEW;
END;
$function$;

-- Hold generic and early account cancellation until classified invocation
-- retirement composes with its non-refunding cancellation proof.
CREATE OR REPLACE FUNCTION internal.cancel_initial_analysis(p_owner uuid, p_scan uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
DECLARE owned_by UUID; scan_exists BOOLEAN; saved internal.initial_analysis_cancellations;
 submission internal.initial_analysis_submissions; admission internal.initial_analysis_admissions;
 quota internal.ai_quota_reservations; funding JSONB; allocation internal.complimentary_scan_usage;
 lifecycle TEXT; terminal TEXT:='cancelled_unknown'; classification TEXT; proven BOOLEAN:=FALSE; settlement JSONB;
BEGIN
 PERFORM internal.require_service_role();
 IF p_owner IS NULL OR p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_scan::TEXT,0::BIGINT));
 SELECT user_id INTO owned_by FROM public.scans WHERE id=p_scan FOR UPDATE;
 scan_exists:=FOUND;
 IF scan_exists AND owned_by IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_scan FOR UPDATE;
 SELECT state INTO lifecycle FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan FOR UPDATE;

 PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND owner_id<>p_owner) THEN
  RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 SELECT * INTO submission FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND submission.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND saved.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 -- Classified invocations require a non-refunding retirement witness before
 -- their original receipt can be erased. Until that composition is integrated,
 -- fail before saved-receipt replay or any cancellation mutation. The locked
 -- admission supplies the original reservation even for a mismatched scan row.
 SELECT * INTO admission FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
 IF EXISTS(SELECT 1 FROM internal.identification_invocations
   WHERE is_initial_analysis AND (scan_id=p_scan OR reservation_id=admission.funding_binding_id)) THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
 END IF;
 IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan) THEN RAISE EXCEPTION 'initial_analysis_deleted' USING ERRCODE='55000'; END IF;
 IF scan_exists OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_already_complete' USING ERRCODE='55000'; END IF;
 IF saved.scan_id IS NOT NULL THEN
  IF saved.dispatch IS DISTINCT FROM internal.initial_cancellation_dispatch(lifecycle) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
  RETURN jsonb_build_object('version',1,'outcome','cancelled','dispatch',saved.dispatch);
 END IF;
 IF internal.initial_cancellation_dispatch(lifecycle) IS NOT NULL THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 IF submission.scan_id IS NULL THEN
  -- First-writer-wins namespace claim, never proof of absent legacy execution.
  IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan)
    AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND owner_id=p_owner)
   OR EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_scan)
   OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
   OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
   OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=p_scan OR request_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=p_scan) THEN
   RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;

  IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND owner_id=p_owner) THEN


   IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan AND canonical_candidate::JSONB->>'variant' IN ('media_sources','client_prepared_photo')) THEN
    terminal:=CASE WHEN internal.can_cancel_initial_preparation(p_owner,p_scan) THEN 'cancelled_pre_dispatch' ELSE 'cancelled_unknown' END;
   ELSE PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan); terminal:='cancelled_pre_dispatch'; END IF;


  ELSIF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled)

   OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_owner AND status IN ('pending','storage_pending','auth_pending')) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 ELSE
  SELECT * INTO admission FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
  SELECT * INTO quota FROM internal.ai_quota_reservations WHERE id=admission.funding_binding_id AND user_id=p_owner FOR UPDATE;
  -- The owner is already locked. Do not take the usage row before the quota
  -- counter order; the existing settlement owner locks/rechecks it below.
  SELECT * INTO allocation FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_scan;
  funding:=jsonb_build_object('version',1,'original',jsonb_build_object(
   'reservation_id',quota.id,'request_id',quota.request_id,'original_analysis_id',quota.original_analysis_id,
   'operation',quota.operation,'attempt_count',quota.attempt_count,'effective_plan',quota.effective_plan,
   'effective_tier',quota.effective_tier,'entitlement_version',quota.entitlement_version,'policy_version',quota.policy_version,
   'model',quota.model,'complimentary_client_scan_id',quota.complimentary_client_scan_id,'flash_fallback_used',quota.flash_fallback_used));
  proven:=NOT internal.initial_admitted_settlement_blocked(p_scan)
   AND lifecycle='pending_pre_dispatch' AND admission.owner_id=p_owner AND quota.user_id=p_owner
   AND quota.request_id=p_scan AND quota.original_analysis_id=p_scan AND quota.operation='scan_identification'
   AND quota.attempt_count=1 AND quota.state='reserved' AND quota.committed_at IS NULL AND quota.failed_at IS NULL
   AND quota.refunded_at IS NULL AND quota.refund_count=0 AND quota.stale_recovery_count=0
   AND submission.funding_snapshot=funding
   AND admission.funding_digest=internal.initial_digest('funding',internal.initial_canonical(funding))
   AND ((quota.complimentary_client_scan_id IS NULL AND allocation.client_scan_id IS NULL)
    OR (quota.complimentary_client_scan_id=p_scan AND allocation.state='held'))
   AND NOT EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
   AND NOT EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
   AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan OR reservation_id=quota.id)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id=p_scan)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan);
  IF proven IS TRUE THEN
   IF NOT internal.finalize_ai_quota_reservation_core(quota.id,p_owner,quota.lease_token,'refunded') THEN
    RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000'; END IF;
   settlement:=internal.settle_complimentary_analysis(p_owner,p_scan,'cancelled_before_dispatch');
   IF (settlement->>'credit_released')::BOOLEAN IS DISTINCT FROM (quota.complimentary_client_scan_id IS NOT NULL) THEN
    RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000'; END IF;
   terminal:='cancelled_pre_dispatch';
  ELSIF lifecycle='dispatch_authorized' THEN terminal:='cancelled_dispatched';
  END IF;
 END IF;
 INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES(p_scan) ON CONFLICT(scan_id) DO NOTHING;
 IF lifecycle IS NULL THEN
  INSERT INTO internal.initial_analysis_lifecycle_fences(scan_id,state) VALUES(p_scan,terminal);
 ELSE
  PERFORM internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,terminal,'begin');
  UPDATE internal.initial_analysis_lifecycle_fences SET state=terminal WHERE scan_id=p_scan;
  PERFORM internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,terminal,'end');
 END IF;
 classification:=internal.initial_cancellation_dispatch(terminal);
 IF internal.initial_admitted_settlement_blocked(p_scan) THEN
  PERFORM internal.lock_initial_media_handoff_members(p_scan);
 END IF;
 IF internal.initial_admitted_settlement_blocked(p_scan) THEN
     PERFORM internal.retire_initial_preparation_source_objects(p_scan);
     IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=p_scan) THEN
         PERFORM internal.retire_initial_media_objects(p_scan);
     END IF;
     DELETE FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
     DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 ELSE
 DELETE FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
 PERFORM internal.retire_initial_preparation_source_objects(p_scan);
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 END IF;
 INSERT INTO internal.initial_analysis_cancellations(scan_id,owner_id,dispatch) VALUES(p_scan,p_owner,classification);
 RETURN jsonb_build_object('version',1,'outcome','cancelled','dispatch',classification);
END;
$function$;

CREATE OR REPLACE FUNCTION public.apply_user_tombstone(target_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE observation UUID; original public.scans; retained public.scans; facts JSONB; columns TEXT; values_sql TEXT; admission internal.initial_analysis_admissions;
BEGIN
    PERFORM internal.require_service_role();
    IF target_user_id IS NULL OR target_user_id='00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'account_deletion_invalid_user' USING ERRCODE='22023';
    END IF;
    PERFORM users.id FROM public.users AS users WHERE users.id=target_user_id FOR UPDATE;
    -- Preserve the publication/consensus lock order and fail without waiting.
    BEGIN
        PERFORM request.id FROM public.explore_community_requests request
        JOIN internal.observation_community_bindings binding ON binding.request_id=request.id
        WHERE binding.owner_id=target_user_id ORDER BY request.id FOR UPDATE OF request NOWAIT;
        PERFORM published.post_id FROM public.explore_analysis_public_projection published
        JOIN public.explore_posts post ON post.id=published.post_id
        WHERE post.user_id=target_user_id ORDER BY published.post_id FOR UPDATE OF published NOWAIT;
    EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END;
    -- Scientific columns are not SET, so coordinate triggers cannot recompute
    -- the preserved location. Existing review guards clear review on detach.
    -- Dynamic column assignment copies only the NULL-initialized allowlist
    -- record, never the original/private JSON. It also clears future nullable
    -- columns by default; a new required field fails until explicitly reviewed.
    SELECT pg_catalog.string_agg(pg_catalog.quote_ident(attname),',' ORDER BY attnum),
           pg_catalog.string_agg('($1).'||pg_catalog.quote_ident(attname),',' ORDER BY attnum)
    INTO columns,values_sql FROM pg_catalog.pg_attribute
    WHERE attrelid='public.scans'::REGCLASS AND attnum>0 AND NOT attisdropped AND attgenerated=''
      AND attname<>ALL(ARRAY['id','species_id','timestamp','gps_lat_exact','gps_long_exact','gps_lat_public','gps_long_public','geoprivacy','coordinate_uncertainty_in_meters','gps_elevation','weather_condition','weather_temperature_f','ai_confidence_score','ecology_type','is_invasive','is_live_capture','is_verified','blur_score','current_month','time_of_day','life_stage','reproductive_condition','individual_count','estimated_size_cm','inference_tier','image_quality_score','is_biological_subject','sex','sex_confidence','zoom_factor','invasive_confidence','identification_provenance','primary_identification','confirmed_species_identity_revision','confirmed_species_id','confirmed_species_identity','ai_identification_review','user_identification_override','user_confirmed_identification','user_review_state']::TEXT[]);

    -- Permanent account erasure can retire classified pre-row work through
    -- tombstone authority. Explicit cancellation keeps its separate C1 hold.
    FOR observation IN SELECT s.scan_id FROM (
        SELECT scan_id,owner_id FROM internal.initial_analysis_submissions
        UNION SELECT scan_id,owner_id FROM internal.initial_analysis_preparation_intents
        UNION SELECT scan_id,user_id FROM internal.identification_invocations
            WHERE is_initial_analysis AND scan_id IS NOT NULL
    ) s WHERE s.owner_id=target_user_id ORDER BY s.scan_id LOOP
        PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||observation::TEXT,0::BIGINT));
        PERFORM id FROM public.scans WHERE id=observation FOR UPDATE;
        -- Public observations are detached by the unchanged scientific owner.
        IF FOUND OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=observation) THEN CONTINUE; END IF;
        PERFORM observation_id FROM internal.observation_histories WHERE observation_id=observation FOR UPDATE;
        PERFORM scan_id FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=observation FOR UPDATE;
        PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=observation FOR UPDATE;
        PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=observation FOR UPDATE;
        PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=observation FOR UPDATE;
        SELECT * INTO admission FROM internal.initial_analysis_admissions WHERE scan_id=observation FOR UPDATE;
        IF NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE is_initial_analysis
            AND (scan_id=observation OR reservation_id=admission.funding_binding_id)) THEN
            PERFORM internal.cancel_initial_analysis(target_user_id,observation);
            CONTINUE;
        END IF;
        -- Never erase another operation through an aliased reservation or owner.
        IF (admission.scan_id IS NOT NULL AND admission.owner_id IS DISTINCT FROM target_user_id)
            OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=observation AND owner_id IS DISTINCT FROM target_user_id)
            OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=observation AND owner_id IS DISTINCT FROM target_user_id)
            OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE is_initial_analysis
                AND (scan_id=observation OR reservation_id=admission.funding_binding_id)
                AND (scan_id IS DISTINCT FROM observation OR user_id IS DISTINCT FROM target_user_id)) THEN
            RAISE EXCEPTION 'initial_analysis_invocation_erasure_unavailable' USING ERRCODE='55000';
        END IF;
        PERFORM internal.lock_initial_media_handoff_erasure_rows(observation);
        INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)
        VALUES(observation,NULL,clock_timestamp()) ON CONFLICT(scan_id) DO NOTHING;
        -- Existing tombstones do not rerun their callback. Invocation-only
        -- leftovers must still retire even when both private roots are absent.
        PERFORM internal.fence_initial_analysis_erasure(observation);
        PERFORM internal.retire_initial_invocation_authority(observation);
        IF internal.initial_admitted_settlement_blocked(observation) THEN
            -- A new tombstone already ran the callback; no second erasure
            -- is needed. Existing tombstones still require the locked fallback.
            IF EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=observation)
              OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=observation)
          OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=observation AND state<>'retired')
          OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=observation AND NOT retired)
          OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=observation AND state<>'retired')
          OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=observation AND NOT retired) THEN
            PERFORM internal.retire_initial_preparation_source_objects(observation);
            IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=observation) THEN
                PERFORM internal.retire_initial_media_objects(observation);
            END IF;
            DELETE FROM internal.initial_analysis_submissions WHERE scan_id=observation;
            DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=observation;
            END IF;
        ELSE
        DELETE FROM internal.initial_analysis_submissions WHERE scan_id=observation;
        PERFORM internal.retire_initial_preparation_source_objects(observation);
 DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id=observation;
        END IF;
    END LOOP;
    FOR observation IN SELECT id FROM public.scans WHERE user_id=target_user_id ORDER BY id LOOP
        PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||observation::TEXT,0::BIGINT));
        SELECT * INTO original FROM public.scans WHERE id=observation AND user_id=target_user_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'scientific_retention_state_invalid' USING ERRCODE='55000'; END IF;
        PERFORM observation_id FROM internal.observation_histories WHERE observation_id=observation FOR UPDATE;
        IF FOUND THEN
            IF EXISTS(SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid='public.scans'::REGCLASS
                AND attnum>0 AND NOT attisdropped AND attgenerated<>'') THEN
                RAISE EXCEPTION 'scientific_retention_schema_unclassified' USING ERRCODE='55000';
            END IF;
            PERFORM r.analysis_id FROM internal.observation_analysis_results r
                JOIN internal.observation_histories h ON h.observation_id=r.observation_id AND h.selected_analysis_id=r.analysis_id
                WHERE r.observation_id=observation FOR SHARE OF r;
            PERFORM a.analysis_id FROM internal.observation_analysis_authorities a
                JOIN internal.observation_histories h ON h.observation_id=a.observation_id AND h.selected_analysis_id=a.analysis_id
                WHERE a.observation_id=observation FOR SHARE OF a;
            facts := internal.observation_retained_identification(observation);
            retained := internal.scientific_detached_observation(original,facts);
            EXECUTE 'UPDATE public.scans SET ('||columns||')=(SELECT '||values_sql||') WHERE id=$2'
                USING retained,observation;
        ELSE
            UPDATE public.scans SET user_id=NULL,is_tombstoned=TRUE,
                image_storage_urls='{}',video_storage_urls='{}',audio_storage_urls='{}',captured_media=NULL,
                semantic_location=NULL,public_location_label=NULL,device_locale=NULL,device_time_zone=NULL,
                user_observation_context=NULL,custom_tags='{}',human_intervention_notes=NULL WHERE id=observation;
        END IF;
    END LOOP;
    DELETE FROM public.users WHERE id=target_user_id;
END;
$function$;

-- Exact serialized-size preflight; these private helpers grant no mutation authority.
CREATE FUNCTION internal.measure_initial_cancellation_private_images(p_scan UUID)
RETURNS TABLE(relation_name TEXT,row_count BIGINT,row_bytes BIGINT,array_bytes BIGINT)
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE member RECORD;
BEGIN
 IF p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 FOR member IN SELECT * FROM internal.initial_cancellation_private_catalog() LOOP
  relation_name:=member.relation_name;
  EXECUTE format('SELECT count(*) FROM (SELECT 1 FROM %s WHERE scan_id=$1 LIMIT %s) bounded',relation_name,member.row_limit+1)
   INTO row_count USING p_scan;
  IF row_count>member.row_limit THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
  EXECUTE format('SELECT COALESCE(sum(octet_length(to_jsonb(t)::TEXT)),0) FROM %s t WHERE scan_id=$1',relation_name)
   INTO row_bytes USING p_scan;
  IF row_bytes>33554432 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
  array_bytes:=2+row_bytes+greatest(row_count-1,0)*2;
  RETURN NEXT;
 END LOOP;
END; $$;

CREATE OR REPLACE FUNCTION internal.capture_initial_cancellation_private_images(p_scan UUID)
RETURNS JSONB LANGUAGE plpgsql SET search_path='' AS $$
DECLARE member RECORD; estimated BIGINT:=2; members INTEGER:=0; images JSONB; result JSONB:='{}';
BEGIN
 FOR member IN SELECT * FROM internal.measure_initial_cancellation_private_images(p_scan) LOOP
  estimated:=estimated+octet_length(to_jsonb(member.relation_name)::TEXT)+2+member.array_bytes
   +CASE WHEN members>0 THEN 2 ELSE 0 END;
  members:=members+1;
  IF estimated>67108864 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 END LOOP;
 FOR member IN SELECT * FROM internal.initial_cancellation_private_catalog() LOOP
  EXECUTE format('SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY (to_jsonb(t)->>''ordinal'')::INTEGER, (to_jsonb(t)->>''photo_ordinal'')::INTEGER, (to_jsonb(t)->>''role'') COLLATE "C"),''[]''::JSONB) FROM %s t WHERE scan_id=$1',member.relation_name)
   INTO images USING p_scan;
  result:=result||jsonb_build_object(member.relation_name,images);
 END LOOP;
 IF octet_length(result::TEXT) IS DISTINCT FROM estimated THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 RETURN result;
END; $$;

-- One mapping supplies both duplicated-component sizing and construction.
CREATE FUNCTION internal.initial_accounted_cancellation_components()
RETURNS TABLE(component TEXT,relation_name TEXT,is_array BOOLEAN)
LANGUAGE SQL IMMUTABLE SET search_path='' AS $$ VALUES
 ('admission','internal.initial_analysis_admissions',FALSE),
 ('receipt','internal.initial_preparation_admission_receipts',FALSE),
 ('intent','internal.initial_analysis_preparation_intents',FALSE),
 ('submission','internal.initial_analysis_submissions',FALSE),
 ('source_verification','internal.initial_preparation_source_verifications',FALSE),
 ('execution_grant','internal.initial_preparation_execution_grants',FALSE),
 ('output_manifest','internal.initial_preparation_output_manifests',FALSE),
 ('output_mapping','internal.initial_preparation_output_mapping',TRUE),
 ('outcome','internal.initial_preparation_outcomes',FALSE)
$$;

-- Normalize one retained row, shared by measurement and construction.
CREATE FUNCTION internal.initial_cpm_cancellation_retained_row(p_kind TEXT,p_row JSONB,p_after BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
BEGIN
 IF p_after IS NULL THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 CASE p_kind
 WHEN 'capacity' THEN RETURN to_jsonb(jsonb_populate_record(NULL::internal.initial_cpm_photo_capacity_reservations,p_row))||jsonb_build_object('state','admitted');
 WHEN 'attempt' THEN RETURN to_jsonb(jsonb_populate_record(NULL::internal.initial_cpm_photo_write_attempts,p_row))||jsonb_build_object('retired',p_after);
 WHEN 'closure' THEN RETURN to_jsonb(jsonb_populate_record(NULL::internal.initial_cpm_photo_write_closures,p_row));
 ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
 END CASE;
END; $$;

CREATE FUNCTION internal.measure_initial_cpm_cancellation_retained_images(
 p_receipt internal.initial_preparation_admission_receipts,p_after BOOLEAN)
RETURNS BIGINT LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE member JSONB; n INTEGER:=0; estimated BIGINT;
BEGIN
 IF p_after IS NULL OR p_receipt.receipt_digest IS DISTINCT FROM internal.validate_initial_cpm_admitted_proof(p_receipt) THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 estimated:=octet_length(jsonb_build_object('capacity',NULL,'attempts','[]'::JSONB,'closures','[]'::JSONB)::TEXT)-4
  +octet_length(internal.initial_cpm_cancellation_retained_row('capacity',p_receipt.cpm_capacity_predecessor,p_after)::TEXT);
 FOR member IN SELECT value FROM jsonb_array_elements(p_receipt.cpm_retained_roles::JSONB->'members') LOOP
  n:=n+1;
  IF n>6 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
  estimated:=estimated+octet_length(internal.initial_cpm_cancellation_retained_row('attempt',member->'attempt',p_after)::TEXT)
   +octet_length(internal.initial_cpm_cancellation_retained_row('closure',member->'closure',p_after)::TEXT)
   +CASE WHEN n>1 THEN 4 ELSE 0 END;
  IF estimated>67108864 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 END LOOP;
 IF n=0 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 RETURN estimated;
END; $$;

CREATE OR REPLACE FUNCTION internal.initial_cpm_cancellation_retained_images(
 p_receipt internal.initial_preparation_admission_receipts,p_after BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE estimated BIGINT; attempts JSONB; closures JSONB; result JSONB;
BEGIN
 estimated:=internal.measure_initial_cpm_cancellation_retained_images(p_receipt,p_after);
 SELECT jsonb_agg(internal.initial_cpm_cancellation_retained_row('attempt',m->'attempt',p_after)
  ORDER BY (m#>>'{attempt,object_id}')::UUID),
  jsonb_agg(internal.initial_cpm_cancellation_retained_row('closure',m->'closure',p_after)
  ORDER BY (m#>>'{closure,attempt_id}')::UUID) INTO attempts,closures
 FROM jsonb_array_elements(p_receipt.cpm_retained_roles::JSONB->'members') m;
 result:=jsonb_build_object('capacity',internal.initial_cpm_cancellation_retained_row('capacity',p_receipt.cpm_capacity_predecessor,p_after),
  'attempts',attempts,'closures',closures);
 IF octet_length(result::TEXT) IS DISTINCT FROM estimated THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION internal.measure_initial_cancellation_private_images(UUID),
 internal.initial_accounted_cancellation_components(),
 internal.initial_cpm_cancellation_retained_row(TEXT,JSONB,BOOLEAN),
 internal.measure_initial_cpm_cancellation_retained_images(internal.initial_preparation_admission_receipts,BOOLEAN)
 FROM PUBLIC,anon,authenticated,service_role;

-- Same original attribution check for report and accounted cancellation.
-- It validates the saved outcome against its own provenance, never the incoming
-- replay outcome, and performs no pricing lookup or write.
CREATE FUNCTION internal.identification_usage_matches_invocation(
 p_invocation internal.identification_invocations,p_event public.ai_usage_events)
RETURNS BOOLEAN LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
 SELECT COALESCE(NOT (p_invocation.id IS NULL OR p_event.id IS NULL OR
p_event.source_type IS DISTINCT FROM 'identification_invocation'
        OR p_event.source_id IS DISTINCT FROM p_invocation.id OR p_event.operation IS DISTINCT FROM 'scan_identification'
        OR p_event.user_id IS DISTINCT FROM p_invocation.user_id OR p_event.scan_id IS DISTINCT FROM p_invocation.scan_id
        OR p_event.occurred_at IS DISTINCT FROM p_invocation.occurred_at OR p_event.model IS DISTINCT FROM p_invocation.model
        OR p_event.effective_plan IS DISTINCT FROM p_invocation.effective_plan
        OR p_event.input_modality IS DISTINCT FROM (CASE p_invocation.input_profile
            WHEN 'multimodal_text_v1' THEN 'text' WHEN 'multimodal_photo_v1' THEN 'image'
            WHEN 'multimodal_audio_v1' THEN 'audio' WHEN 'multimodal_video_frames_v1' THEN 'video' ELSE 'mixed' END)
        OR p_event.metadata->>'writer' IS DISTINCT FROM 'identification_invocation'
        OR p_event.metadata->>'ai_provider' IS DISTINCT FROM p_invocation.provider
        OR p_event.metadata->>'ai_binding' IS DISTINCT FROM p_invocation.binding
        OR p_event.metadata->>'ai_policy_version' IS DISTINCT FROM p_invocation.policy_version::TEXT
        OR p_event.metadata->>'ai_input_profile' IS DISTINCT FROM p_invocation.input_profile
        OR p_event.metadata->>'ai_attribution' IS DISTINCT FROM 'attempt_snapshot'
        OR p_event.metadata->>'ai_prompt' IS DISTINCT FROM p_invocation.provenance->>'prompt'
        OR p_event.metadata->>'ai_schema' IS DISTINCT FROM p_invocation.provenance->>'schema'
        OR p_event.metadata->'ai_provenance' IS DISTINCT FROM p_invocation.provenance
        OR p_event.metadata->>'ai_usage_contract' IS DISTINCT FROM (CASE p_invocation.provider
            WHEN 'openai' THEN 'openai_responses_tokens_v1' WHEN 'gemini' THEN 'gemini_token_counts_v1' END)
        OR p_event.metadata->>'ai_outcome' IS NULL
        OR p_event.metadata->>'ai_outcome' NOT IN ('draft','refusal','invalid_output','operational_failure','unknown_execution')
        OR p_event.outcome IS DISTINCT FROM (CASE p_event.metadata->>'ai_outcome'
            WHEN 'draft' THEN 'success' WHEN 'refusal' THEN 'refusal' WHEN 'unknown_execution' THEN 'unknown' ELSE 'error' END)),FALSE)
$body$;
REVOKE ALL ON FUNCTION internal.identification_usage_matches_invocation(internal.identification_invocations,public.ai_usage_events)
 FROM PUBLIC,anon,authenticated,service_role;

-- Non-refunding C1 capture; no public composer/retirement authority is enabled.
CREATE OR REPLACE FUNCTION internal.capture_initial_accounted_cancellation_prestate(p_owner uuid, p_scan uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE admitted internal.initial_analysis_admissions;
    receipt internal.initial_preparation_admission_receipts;
    quota internal.ai_quota_reservations;
    attempt internal.identification_provider_attempts;
    charge internal.ai_quota_reservation_counters;
    counter_row internal.ai_quota_counters;
    usage_row internal.complimentary_scan_usage;
    invocation internal.identification_invocations;
    event_row public.ai_usage_events;
    event_id UUID; invocation_count INTEGER:=0; member RECORD; member_count BIGINT;
    member_bytes BIGINT; total_bytes BIGINT:=2; private_images JSONB;
    image_sizes JSONB:='{}'; field_sizes JSONB; components JSONB:='{}';
    component_bytes BIGINT:=2; private_bytes BIGINT:=2; member_number INTEGER:=0; field_name TEXT; field_bytes TEXT;
    charges JSONB:='[]'::JSONB; source_rows JSONB; destination_rows JSONB;
    source_fence JSONB; media_fence JSONB; media_cohort JSONB; owner_epoch JSONB; cpm_prestate JSONB;
BEGIN
    PERFORM internal.require_service_role();
    -- This capture is a private prerequisite, not cancellation authority. The
    -- composer remains held until the statement witness and terminal chain land.
    IF current_setting('transaction_isolation')<>'read committed' THEN
        RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
    IF internal.initial_admission_sealed() OR internal.initial_cancellation_sealed()
        OR EXISTS(SELECT 1 FROM pg_catalog.pg_locks l WHERE l.locktype='advisory'
            AND l.pid=pg_catalog.pg_backend_pid() AND l.classid=1396920143::OID
            AND l.objid::BIGINT=(pg_catalog.hashtext(pg_catalog.pg_current_xact_id()::TEXT)::BIGINT & 4294967295)
            AND l.objsubid=2 AND l.granted)
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE transaction_id=pg_catalog.pg_current_xact_id())
        OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_catalog.pg_current_xact_id())
        OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging WHERE transaction_id=pg_catalog.pg_current_xact_id()) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
    PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
    SELECT * INTO admitted FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
    IF NOT FOUND OR admitted.owner_id IS DISTINCT FROM p_owner OR (admitted.binding_version IS NULL OR admitted.binding_version IS NULL OR admitted.binding_version NOT IN (3,4))
        OR internal.initial_admission_sealed()
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan)
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan AND state IN ('pending_pre_dispatch','dispatch_authorized')) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan FOR UPDATE;
    IF NOT FOUND OR receipt.owner_id IS DISTINCT FROM p_owner THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.initial_admission_retained_receipt(p_owner,p_scan,receipt.admission_receipt_id);
    SELECT * INTO quota FROM internal.ai_quota_reservations WHERE id=admitted.funding_binding_id FOR UPDATE;
    IF NOT FOUND OR quota.user_id IS DISTINCT FROM p_owner OR quota.request_id IS DISTINCT FROM p_scan
        OR quota.original_analysis_id IS DISTINCT FROM p_scan THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO attempt FROM internal.identification_provider_attempts
        WHERE reservation_id=quota.id AND attempt_count=1 FOR UPDATE;
    IF NOT FOUND OR (SELECT count(*) FROM internal.identification_provider_attempts WHERE reservation_id=quota.id)<>1
        OR (SELECT count(*) FROM internal.ai_quota_reservation_counters WHERE reservation_id=quota.id)>3 THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
    -- Match release_ai_quota_reservation_counters' daily -> user -> IP order.
    -- The reservation lock precedes link/counter locks and usage follows them.
    FOR charge IN SELECT * FROM internal.ai_quota_reservation_counters l WHERE l.reservation_id=quota.id
        ORDER BY CASE l.scope_type WHEN 'user_daily' THEN 1 WHEN 'user_rate' THEN 2 WHEN 'ip_rate' THEN 3 ELSE 4 END,
            l.scope_key,l.bucket,l.window_start FOR UPDATE LOOP
        SELECT * INTO counter_row FROM internal.ai_quota_counters c
            WHERE c.scope_type=charge.scope_type AND c.scope_key=charge.scope_key
                AND c.bucket=charge.bucket AND c.window_start=charge.window_start FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        charges:=charges||jsonb_build_array(jsonb_build_object('link',to_jsonb(charge),'counter',to_jsonb(counter_row),'release_delta',0));
    END LOOP;
    SELECT * INTO usage_row FROM internal.complimentary_scan_usage
        WHERE user_id=p_owner AND client_scan_id=p_scan FOR UPDATE;
    SELECT jsonb_build_object('id',u.id,'entitlement_version',u.entitlement_version,
        'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch) INTO owner_epoch
        FROM public.users u WHERE u.id=p_owner;
    -- Lock every scan/reservation match in ID order, including ordinary or
    -- aliased rows; none may be hidden by filtering on initial classification.
    FOR invocation IN SELECT * FROM internal.identification_invocations
        WHERE scan_id=p_scan OR reservation_id=quota.id ORDER BY id FOR UPDATE LOOP
        invocation_count:=invocation_count+1;
        IF invocation_count<>1 OR NOT invocation.is_initial_analysis
            OR invocation.user_id IS DISTINCT FROM p_owner OR invocation.scan_id IS DISTINCT FROM p_scan
            OR invocation.reservation_id IS DISTINCT FROM quota.id OR invocation.attempt_count IS DISTINCT FROM 1
            OR invocation.initial_admission_receipt_id IS DISTINCT FROM receipt.admission_receipt_id
            OR invocation.lease_sha256 IS DISTINCT FROM encode(extensions.digest(convert_to(
                receipt.accounting::JSONB#>>'{reservation,lease_token}','UTF8'),'sha256'),'hex')
            OR invocation.provider IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,provider}'
            OR invocation.binding IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,binding}'
            OR invocation.input_profile IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,input_profile}'
            OR invocation.effective_plan IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,effective_plan}'
            OR invocation.policy_version::TEXT IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,policy_version}'
            OR invocation.model IS DISTINCT FROM COALESCE(receipt.accounting::JSONB#>>'{attempt,provider_model}',
                receipt.accounting::JSONB#>>'{attempt,model}') THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END LOOP;
    IF invocation_count<>1 THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    -- The existing producer is the sole renderer. It may return early for an
    -- existing event, so independently validate the locked association below.
    event_id:=internal.complete_identification_usage(invocation.id,'unknown_execution','{}'::JSONB);
    SELECT * INTO STRICT invocation FROM internal.identification_invocations WHERE id=invocation.id FOR UPDATE;
    SELECT * INTO event_row FROM public.ai_usage_events WHERE id=event_id FOR UPDATE;
    IF NOT FOUND OR invocation.event_id IS DISTINCT FROM event_row.id
        OR NOT internal.identification_usage_matches_invocation(invocation,event_row)
        OR octet_length(to_jsonb(invocation)::TEXT)*2+octet_length(to_jsonb(event_row)::TEXT)>261120 THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    -- No quota, counter or complimentary mutation occurs on this branch. The
    -- original lease is checked above; current lease/deadline is not authority.
    IF admitted.binding_version=4 THEN
        PERFORM internal.lock_initial_cpm_photo_capacity();
        PERFORM scan_id FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan FOR UPDATE;
    END IF;
    -- All preparation source and prepared-output objects share this registry.
    PERFORM scan_id FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
    PERFORM object_id FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=p_scan ORDER BY photo_ordinal,role COLLATE "C" FOR UPDATE;
    IF admitted.binding_version=4 THEN
        PERFORM attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
        PERFORM c.attempt_id FROM internal.initial_cpm_photo_write_closures c
            JOIN internal.initial_cpm_photo_write_attempts w USING(attempt_id)
            WHERE w.scan_id=p_scan ORDER BY c.attempt_id FOR UPDATE OF c;
    END IF;
    PERFORM scan_id FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_output_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan FOR UPDATE;
    -- Transfer is locked before M1; new private rows join exact C1 images.
    PERFORM scan_id FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_verifications WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_media_copy_progress WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_media_verification_claims_v2 WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
    -- Known execution uses retained integrity, never the live unused proof.
    IF admitted.binding_version=3 THEN
        PERFORM internal.assert_initial_media_handoff_chain(p_owner,p_scan);
    ELSIF receipt.admission_variant IS DISTINCT FROM 'client_prepared_photo_v1' THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM scan_id FROM internal.initial_analysis_results WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_completions WHERE scan_id=p_scan FOR UPDATE;
    IF EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
        OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
        OR EXISTS(SELECT 1 FROM public.scans WHERE id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    -- Size each occurrence before constructing any private/registry/CPM array.
    -- Locks above hold membership stable; only small numeric measurements accumulate.
    FOR member IN SELECT * FROM internal.measure_initial_cancellation_private_images(p_scan) LOOP
        image_sizes:=image_sizes||jsonb_build_object(member.relation_name,
            jsonb_build_object('count',member.row_count,'rows',member.row_bytes,'array',member.array_bytes));
        private_bytes:=private_bytes+octet_length(to_jsonb(member.relation_name)::TEXT)+2+member.array_bytes
            +CASE WHEN member_number>0 THEN 2 ELSE 0 END;
        member_number:=member_number+1;
        IF private_bytes>67108864 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END LOOP;
    member_number:=0;
    FOR member IN SELECT * FROM internal.initial_accounted_cancellation_components() LOOP
        IF NOT image_sizes ? member.relation_name
            OR (NOT member.is_array AND (image_sizes#>>ARRAY[member.relation_name,'count'])::BIGINT>1) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        member_bytes:=CASE WHEN member.is_array THEN (image_sizes#>>ARRAY[member.relation_name,'array'])::BIGINT
            WHEN (image_sizes#>>ARRAY[member.relation_name,'count'])::BIGINT=0 THEN 4
            ELSE (image_sizes#>>ARRAY[member.relation_name,'rows'])::BIGINT END;
        component_bytes:=component_bytes+octet_length(to_jsonb(member.component)::TEXT)+2+member_bytes
            +CASE WHEN member_number>0 THEN 2 ELSE 0 END;
        member_number:=member_number+1;
    END LOOP;
    field_sizes:=jsonb_build_object(
        'version',COALESCE(octet_length((to_jsonb(1))::TEXT),4),
        'authority',COALESCE(octet_length((to_jsonb('none'::TEXT))::TEXT),4),
        'transaction_id',COALESCE(octet_length((to_jsonb(pg_catalog.pg_current_xact_id()::TEXT))::TEXT),4),
        'variant',COALESCE(octet_length((to_jsonb('accounted_invocation'::TEXT))::TEXT),4),
        'invocation',COALESCE(octet_length((to_jsonb(invocation))::TEXT),4),
        'event',COALESCE(octet_length((to_jsonb(event_row))::TEXT),4),
        'owner_id',COALESCE(octet_length((to_jsonb(p_owner))::TEXT),4),
        'scan_id',COALESCE(octet_length((to_jsonb(p_scan))::TEXT),4),
        'admission_receipt_id',COALESCE(octet_length((to_jsonb(receipt.admission_receipt_id))::TEXT),4),
        'admission_receipt_digest',COALESCE(octet_length((to_jsonb(receipt.receipt_digest))::TEXT),4),
        'quota',COALESCE(octet_length((to_jsonb(quota))::TEXT),4),
        'attempt',COALESCE(octet_length((to_jsonb(attempt))::TEXT),4),
        'charges',COALESCE(octet_length((charges)::TEXT),4),
        'complimentary',COALESCE(octet_length((CASE WHEN usage_row.client_scan_id IS NULL THEN 'null'::JSONB ELSE to_jsonb(usage_row) END)::TEXT),4),
        'owner_epoch',COALESCE(octet_length((owner_epoch)::TEXT),4),
        'private_components',component_bytes,'erasure_images',private_bytes);
    FOR member IN SELECT * FROM (VALUES
        ('source_registry','internal.initial_preparation_source_registry',8,TRUE),
        ('destination_registry','internal.initial_analysis_media_registry',8,TRUE),
        ('source_fence','internal.initial_preparation_source_fences',1,FALSE),
        ('media_fence','internal.initial_analysis_media_allocation_fences',1,FALSE),
        ('media_cohort','internal.initial_analysis_media_cohorts',1,FALSE),
        ('lifecycle','internal.initial_analysis_lifecycle_fences',1,FALSE)
    ) AS m(component,relation_name,row_limit,is_array) LOOP
        EXECUTE format('SELECT count(*) FROM (SELECT 1 FROM %s WHERE scan_id=$1 LIMIT %s) bounded',member.relation_name,member.row_limit+1)
            INTO member_count USING p_scan;
        IF member_count>member.row_limit THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        EXECUTE format('SELECT COALESCE(sum(octet_length(to_jsonb(t)::TEXT)),0) FROM %s t WHERE scan_id=$1',member.relation_name)
            INTO member_bytes USING p_scan;
        IF member_bytes>33554432 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        field_sizes:=field_sizes||jsonb_build_object(member.component,
            CASE WHEN member.is_array THEN 2+member_bytes+greatest(member_count-1,0)*2
            WHEN member_count=0 THEN 4 ELSE member_bytes END);
    END LOOP;
    IF admitted.binding_version=4 THEN
        field_sizes:=field_sizes||jsonb_build_object('cpm_retained',internal.measure_initial_cpm_cancellation_retained_images(receipt,FALSE));
    END IF;
    member_number:=0;
    FOR field_name,field_bytes IN SELECT key,value FROM jsonb_each_text(field_sizes) LOOP
        IF field_bytes IS NULL OR field_bytes::BIGINT<1 THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        total_bytes:=total_bytes+octet_length(to_jsonb(field_name)::TEXT)+2+field_bytes::BIGINT
            +CASE WHEN member_number>0 THEN 2 ELSE 0 END;
        member_number:=member_number+1;
        IF total_bytes>67108864 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END LOOP;
    private_images:=internal.capture_initial_cancellation_private_images(p_scan);
    FOR member IN SELECT * FROM internal.initial_accounted_cancellation_components() LOOP
        components:=components||jsonb_build_object(member.component,CASE WHEN member.is_array
            THEN private_images->member.relation_name ELSE private_images->member.relation_name->0 END);
    END LOOP;
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY object_id),'[]') INTO source_rows
        FROM internal.initial_preparation_source_registry r WHERE scan_id=p_scan;
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY object_id),'[]') INTO destination_rows
        FROM internal.initial_analysis_media_registry r WHERE scan_id=p_scan;
    SELECT to_jsonb(f) INTO source_fence FROM internal.initial_preparation_source_fences f WHERE scan_id=p_scan;
    SELECT to_jsonb(f) INTO media_fence FROM internal.initial_analysis_media_allocation_fences f WHERE scan_id=p_scan;
    SELECT to_jsonb(c) INTO media_cohort FROM internal.initial_analysis_media_cohorts c WHERE scan_id=p_scan;
    cpm_prestate:=jsonb_build_object('version',1,'authority','none','transaction_id',pg_catalog.pg_current_xact_id()::TEXT,
        'variant','accounted_invocation','invocation',to_jsonb(invocation),'event',to_jsonb(event_row),
        'owner_id',p_owner,'scan_id',p_scan,'admission_receipt_id',receipt.admission_receipt_id,
        'admission_receipt_digest',receipt.receipt_digest,'quota',to_jsonb(quota),'attempt',to_jsonb(attempt),
        'charges',charges,'complimentary',CASE WHEN usage_row.client_scan_id IS NULL THEN 'null'::JSONB ELSE to_jsonb(usage_row) END,'owner_epoch',owner_epoch,
        'source_fence',source_fence,'source_registry',source_rows,'media_fence',media_fence,
        'media_cohort',media_cohort,'destination_registry',destination_rows,
        'private_components',components,
        'erasure_images',private_images,
        'lifecycle',(SELECT to_jsonb(t) FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=p_scan));
    IF admitted.binding_version=4 THEN
        cpm_prestate:=cpm_prestate||jsonb_build_object('cpm_retained',internal.initial_cpm_cancellation_retained_images(receipt,FALSE));
        PERFORM internal.assert_initial_cpm_cancellation_images(p_scan,cpm_prestate,FALSE);
        PERFORM internal.assert_initial_cpm_cancellation_empty_destination(p_scan,cpm_prestate);
    END IF;
    IF octet_length(cpm_prestate::TEXT) IS DISTINCT FROM total_bytes OR octet_length(cpm_prestate::TEXT)>67108864 THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    RETURN cpm_prestate;
END;
$function$;
REVOKE ALL ON FUNCTION internal.capture_initial_accounted_cancellation_prestate(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

-- C1 closed variant entry. Accounted stages cannot commit until the complete
-- invocation/lifecycle/terminal witness chain is implemented below this hold.
DO $preflight$ BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging) THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
END; $preflight$;
ALTER TABLE internal.initial_admitted_cancellation_staging
 ADD COLUMN variant TEXT NOT NULL CHECK(variant IN ('unused','accounted_invocation')),
 DROP CONSTRAINT initial_admitted_cancellation_staging_phase_check,
 ADD CONSTRAINT initial_admitted_cancellation_staging_phase_check CHECK(phase IN ('captured','quota','accounted')),
 ADD CONSTRAINT initial_admitted_cancellation_staging_variant_phase_check CHECK(
  (variant='unused' AND ((phase='captured' AND quota_at IS NULL) OR (phase='quota' AND quota_at IS NOT NULL)))
  OR (variant='accounted_invocation' AND phase='accounted' AND quota_at IS NULL));

CREATE OR REPLACE FUNCTION internal.guard_initial_admitted_cancellation_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE admitted internal.initial_analysis_admissions;
BEGIN
    IF TG_OP='DELETE' THEN
        PERFORM internal.check_initial_cancellation_cleanup_member(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,to_jsonb(OLD),FALSE);
        RETURN OLD;
    END IF;
    PERFORM internal.require_service_role();
    IF TG_OP='UPDATE' THEN
        IF OLD.variant IS DISTINCT FROM 'unused' OR NEW.variant IS DISTINCT FROM OLD.variant
            OR OLD.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
            OR OLD.phase IS DISTINCT FROM 'captured' OR NEW.phase IS DISTINCT FROM 'quota'
            OR OLD.quota_at IS NOT NULL OR NEW.quota_at IS NOT NULL
            OR to_jsonb(OLD)-'phase' IS DISTINCT FROM to_jsonb(NEW)-'phase'
            OR OLD.prestate IS DISTINCT FROM internal.capture_initial_admitted_cancellation_prestate(OLD.owner_id,OLD.scan_id) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        -- The existing finalizer's sampling expression enters this transition.
        -- No caller timestamp is accepted; every derived field remains frozen.
        NEW.quota_at:=pg_catalog.clock_timestamp();
        RETURN NEW;
    ELSIF TG_OP<>'INSERT' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    -- Only owner/scan are inputs. Neither correct-looking JSON nor a current xid
    -- may be supplied. Capture itself obtains/rechecks the complete lock scope.
    IF NEW.variant IS NOT NULL OR NEW.scan_id IS NULL OR NEW.owner_id IS NULL OR NEW.transaction_id IS NOT NULL
        OR NEW.prestate IS NOT NULL OR NEW.phase IS DISTINCT FROM 'captured' OR NEW.quota_at IS NOT NULL OR EXISTS(
            SELECT 1 FROM internal.initial_admitted_cancellation_staging
            WHERE transaction_id=pg_catalog.pg_current_xact_id()) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    -- Obtain the original scope before choosing a branch. Never select only by
    -- invocation.scan_id: an aliased original reservation must still fail closed.
    IF internal.initial_admission_sealed() OR internal.initial_cancellation_sealed()
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE transaction_id=pg_catalog.pg_current_xact_id())
        OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging WHERE transaction_id=pg_catalog.pg_current_xact_id())
        OR EXISTS(SELECT 1 FROM pg_catalog.pg_locks l WHERE l.locktype='advisory'
            AND l.pid=pg_catalog.pg_backend_pid() AND l.classid=1396920143::OID
            AND l.objid::BIGINT=(pg_catalog.hashtext(pg_catalog.pg_current_xact_id()::TEXT)::BIGINT & 4294967295)
            AND l.objsubid=2 AND l.granted) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    PERFORM internal.lock_initial_preparation_scope(NEW.owner_id,NEW.scan_id);
    PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=NEW.scan_id FOR UPDATE;
    SELECT * INTO admitted FROM internal.initial_analysis_admissions WHERE scan_id=NEW.scan_id FOR UPDATE;
    IF EXISTS(SELECT 1 FROM internal.identification_invocations
        WHERE is_initial_analysis AND (scan_id=NEW.scan_id OR reservation_id=admitted.funding_binding_id)) THEN
        -- Capture reconciles before NEW becomes visible. Any statement/composer
        -- failure must propagate so that reconciliation rolls back with it.
        NEW.prestate:=internal.capture_initial_accounted_cancellation_prestate(NEW.owner_id,NEW.scan_id);
        NEW.variant:='accounted_invocation';
        NEW.phase:='accounted';
    ELSE
        NEW.prestate:=internal.capture_initial_admitted_cancellation_prestate(NEW.owner_id,NEW.scan_id);
        NEW.variant:='unused';
    END IF;
    NEW.transaction_id:=pg_catalog.pg_current_xact_id();
    RETURN NEW;
END;
$function$;

CREATE FUNCTION internal.begin_initial_cancellation_stage(p_owner UUID,p_scan UUID)
RETURNS internal.initial_admitted_cancellation_staging
LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE stage internal.initial_admitted_cancellation_staging; inserted BIGINT;
BEGIN
 PERFORM internal.require_service_role();
 INSERT INTO internal.initial_admitted_cancellation_staging(owner_id,scan_id)
  VALUES(p_owner,p_scan) RETURNING * INTO stage;
 GET DIAGNOSTICS inserted=ROW_COUNT;
 IF inserted<>1 OR stage.owner_id IS DISTINCT FROM p_owner OR stage.scan_id IS DISTINCT FROM p_scan
   OR stage.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
   OR stage.variant NOT IN ('unused','accounted_invocation')
   OR NOT EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging actual
     WHERE actual.scan_id=p_scan AND to_jsonb(actual)=to_jsonb(stage)) THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 RETURN stage;
END;
$body$;
REVOKE ALL ON FUNCTION internal.begin_initial_cancellation_stage(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Ledger mutation is never part of a visible C1 stage. Accounting finishes in
-- its BEFORE INSERT capture; unchanged row-local early-return replay is safe.
CREATE FUNCTION internal.guard_initial_cancellation_usage_freeze()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $body$
BEGIN
 IF EXISTS(
   SELECT 1 FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_catalog.pg_current_xact_id()) THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 RETURN NULL;
END;
$body$;
REVOKE ALL ON FUNCTION internal.guard_initial_cancellation_usage_freeze() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER a00_initial_cancellation_usage_freeze
 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.ai_usage_events
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_usage_freeze();

CREATE OR REPLACE FUNCTION internal.cancel_initial_analysis_explicit(p_owner uuid, p_scan uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
DECLARE owned_by UUID; scan_exists BOOLEAN; submission internal.initial_analysis_submissions;
 saved internal.initial_analysis_cancellations; lifecycle TEXT;
 q internal.ai_quota_reservations; settlement JSONB; stage internal.initial_admitted_cancellation_staging;
BEGIN
 PERFORM internal.require_service_role();
 IF p_owner IS NULL OR p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||p_scan::TEXT,0::BIGINT));
 SELECT user_id INTO owned_by FROM public.scans WHERE id=p_scan FOR UPDATE; scan_exists:=FOUND;
 IF scan_exists AND owned_by IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_scan FOR UPDATE;
 SELECT state INTO lifecycle FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan FOR UPDATE;
 IF internal.initial_admitted_settlement_blocked(p_scan) THEN
  PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 END IF;
 SELECT * INTO submission FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND submission.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND saved.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan) THEN RAISE EXCEPTION 'initial_analysis_deleted' USING ERRCODE='55000'; END IF;
 IF scan_exists OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_already_complete' USING ERRCODE='55000'; END IF;
 -- Saved terminal classification precedes any fresh proof inspection; erased
 -- evidence cannot upgrade unknown/dispatched into a prevented/refunded result.
 IF saved.scan_id IS NOT NULL OR lifecycle IS DISTINCT FROM 'pending_pre_dispatch'
  OR NOT internal.initial_admitted_settlement_blocked(p_scan) THEN
  RETURN internal.cancel_initial_analysis(p_owner,p_scan);
 END IF;
 -- Any admitted footprint, including paired permanent fences after damage or
 -- erasure, requires the complete positive proof. Invalid proof fails closed;
 -- no caught preflight/stage error may enter the generic erasure owner.
 stage:=internal.begin_initial_cancellation_stage(p_owner,p_scan);
 -- Accounted retirement/shared-owner/terminal integration is not yet complete.
 -- Never let the existing refundable composer consume this new stage variant.
 IF stage.variant IS DISTINCT FROM 'unused' THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 SELECT (jsonb_populate_record(NULL::internal.ai_quota_reservations,prestate->'quota')).* INTO STRICT q
  FROM internal.initial_admitted_cancellation_staging WHERE scan_id=p_scan;
 IF NOT internal.finalize_ai_quota_reservation_core(q.id,p_owner,q.lease_token,'refunded') THEN
  RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000'; END IF;
 settlement:=internal.settle_complimentary_analysis(p_owner,p_scan,'cancelled_before_dispatch');
 IF (settlement->>'credit_released')::BOOLEAN IS DISTINCT FROM (q.complimentary_client_scan_id IS NOT NULL)
  OR (settlement->>'credit_consumed')::BOOLEAN IS DISTINCT FROM FALSE THEN
  RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,'cancelled_pre_dispatch','begin');
 UPDATE internal.initial_analysis_lifecycle_fences SET state='cancelled_pre_dispatch' WHERE scan_id=p_scan;
 PERFORM internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,'cancelled_pre_dispatch','end');
 PERFORM internal.retire_initial_preparation_source_objects(p_scan);
 PERFORM internal.retire_initial_media_objects(p_scan);
 PERFORM internal.erase_initial_cancellation_private_root(p_scan,'submission');
 PERFORM internal.erase_initial_cancellation_private_root(p_scan,'intent');
 PERFORM internal.write_initial_cancellation_receipt(p_scan);
 INSERT INTO internal.initial_cancellation_terminal_snapshot(scan_id) VALUES(p_scan);
 PERFORM internal.finish_initial_cancellation_consumption(p_scan);
 SELECT * INTO STRICT saved FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan AND owner_id=p_owner;
 RETURN jsonb_build_object('version',1,'outcome','cancelled','dispatch',saved.dispatch);
END; $function$;

CREATE OR REPLACE FUNCTION internal.require_complete_initial_admitted_cancellation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE stage internal.initial_admitted_cancellation_staging;
BEGIN
    IF TG_TABLE_SCHEMA<>'internal' OR TG_TABLE_NAME<>'initial_admitted_cancellation_staging'
        OR TG_WHEN<>'AFTER' OR TG_LEVEL<>'ROW' OR TG_OP NOT IN ('INSERT','DELETE') THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    stage:=CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
    -- Temporary fail-closed barrier until exact accounted terminal survivors
    -- are integrated. No accounted stage may escape a transaction unfinished.
    IF stage.variant IS DISTINCT FROM 'unused'
        OR stage.transaction_id IS DISTINCT FROM pg_current_xact_id() OR NOT internal.initial_cancellation_sealed()
        OR (SELECT to_jsonb(c) FROM internal.initial_analysis_cancellations c WHERE scan_id=stage.scan_id)
            IS DISTINCT FROM internal.initial_cancellation_receipt_image(stage)
        OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=stage.scan_id)
            IS DISTINCT FROM internal.initial_cancellation_lifecycle_event(stage)->'new'
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=stage.scan_id) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_cancellation_transients_absent(stage.scan_id);
    RETURN NULL;
END; $function$;

CREATE OR REPLACE FUNCTION internal.initial_cancellation_seal_catalog()
 RETURNS TABLE(relation_name text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
    VALUES ('public.ai_usage_events'),
        ('internal.ai_quota_reservations'),
        ('internal.complimentary_scan_usage'),
        ('internal.identification_provider_attempts'),
        ('internal.ai_quota_counters'),
        ('internal.ai_quota_reservation_counters'),
        ('public.users'),
        ('internal.initial_analysis_submissions'),
        ('internal.initial_analysis_admissions'),
        ('internal.initial_analysis_lifecycle_fences'),
        ('internal.initial_preparation_admission_receipts'),
        ('internal.initial_media_copy_progress'),
        ('internal.initial_media_verification_claims_v2'),
        ('internal.initial_media_verification_receipts_v2'),
        ('internal.initial_preparation_transfer_receipts'),
        ('internal.initial_analysis_media_allocation_fences'),
        ('internal.initial_analysis_media_registry'),
        ('internal.initial_analysis_media_cohorts'),
        ('internal.initial_analysis_operation_fences'),
        ('internal.initial_analysis_preparation_intents'),
        ('internal.initial_preparation_source_fences'),
        ('internal.initial_preparation_source_registry'),
        ('internal.initial_preparation_source_mapping'),
        ('internal.initial_cpm_photo_role_mapping'),
        ('internal.initial_preparation_source_verifications'),
        ('internal.initial_preparation_execution_grants'),
        ('internal.initial_preparation_output_manifests'),
        ('internal.initial_preparation_output_mapping'),
        ('internal.initial_preparation_outcomes'),
        ('public.scans'),
        ('public.scan_ingestion_jobs'),
        ('public.scan_ingestion_intents'),
        ('internal.observation_histories'),
        ('internal.observation_analysis_source_bindings'),
        ('internal.observation_analysis_intents'),
        ('internal.observation_analysis_results'),
        ('internal.identification_invocations'),
        ('internal.initial_analysis_results'),
        ('internal.initial_analysis_completions'),
        ('internal.initial_analysis_media_preparations'),
        ('internal.initial_analysis_media_verifications'),
        ('internal.initial_analysis_cancellations'),
        ('internal.scan_deletion_tombstones'),
        ('internal.account_deletion_jobs'),
        ('internal.initial_preparation_admission_staging'),
        ('internal.initial_media_handoff_staging'),
        ('internal.initial_media_handoff_writes'),
        ('internal.initial_preparation_admission_writes'),
        ('internal.initial_admitted_cancellation_staging'),
        ('internal.initial_cancellation_quota_statements'),
        ('internal.initial_cancellation_credit_witness'),
        ('internal.initial_cancellation_lifecycle_witness'),
        ('internal.initial_cancellation_retirement_witness'),
        ('internal.initial_cancellation_erasure_witness'),
        ('internal.initial_cancellation_receipt_witness'),
        ('internal.initial_cancellation_terminal_snapshot');
$function$;
CREATE TRIGGER a00_initial_cancellation_seal BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.ai_usage_events
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_seal();

-- Mechanical C1 invocation witness. Original retirement authority and accounted
-- completion holds remain unchanged until the full terminal chain is installed.
CREATE TABLE internal.initial_cancellation_invocation_witness (
 scan_id UUID PRIMARY KEY,
 phase TEXT NOT NULL DEFAULT 'pending' CHECK(phase IN ('pending','writing','observed','complete')),
 expected JSONB NOT NULL,
 event_image JSONB NOT NULL,
 CHECK(jsonb_typeof(expected)='object' AND jsonb_typeof(event_image)='object'
  AND octet_length(expected::TEXT)+octet_length(event_image::TEXT)<=262144)
);
ALTER TABLE internal.initial_cancellation_invocation_witness ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_cancellation_invocation_witness FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_cancellation_invocation_event(p_stage internal.initial_admitted_cancellation_staging)
RETURNS JSONB LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE original internal.identification_invocations; retired internal.identification_invocations;
BEGIN
 original:=jsonb_populate_record(NULL::internal.identification_invocations,p_stage.prestate->'invocation');
 retired:=original;
 retired.user_id:=NULL; retired.scan_id:=NULL; retired.reservation_id:=NULL;
 retired.lease_sha256:=NULL; retired.initial_admission_receipt_id:=NULL;
 IF p_stage.variant IS DISTINCT FROM 'accounted_invocation' OR p_stage.phase IS DISTINCT FROM 'accounted'
  OR p_stage.quota_at IS NOT NULL OR p_stage.prestate->>'variant' IS DISTINCT FROM p_stage.variant
  OR p_stage.prestate->>'scan_id' IS DISTINCT FROM p_stage.scan_id::TEXT
  OR p_stage.prestate->>'owner_id' IS DISTINCT FROM p_stage.owner_id::TEXT
  OR p_stage.prestate->'invocation' IS DISTINCT FROM to_jsonb(original)
  OR original.user_id IS DISTINCT FROM p_stage.owner_id OR original.scan_id IS DISTINCT FROM p_stage.scan_id
  OR original.reservation_id::TEXT IS DISTINCT FROM p_stage.prestate#>>'{quota,id}'
  OR original.initial_admission_receipt_id::TEXT IS DISTINCT FROM p_stage.prestate->>'admission_receipt_id'
  OR original.event_id::TEXT IS DISTINCT FROM p_stage.prestate#>>'{event,id}'
  OR NOT internal.initial_invocation_retirement_transition(original,retired) THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 RETURN jsonb_build_object('relation','internal.identification_invocations','operation','UPDATE',
  'old',to_jsonb(original),'new',to_jsonb(retired));
END;
$body$;

-- Frozen accounting is checked by immutable original identities even after
-- invocation correlation is cleared. This is not a second usage renderer.
CREATE FUNCTION internal.assert_initial_cancellation_accounted_images(
 p_stage internal.initial_admitted_cancellation_staging,p_retired BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE expected_event JSONB; original_id UUID; event_id UUID; reservation UUID;
 charge JSONB; actual_link JSONB; actual_counter JSONB;
BEGIN
 expected_event:=internal.initial_cancellation_invocation_event(p_stage);
 original_id:=(expected_event#>>'{old,id}')::UUID;
 event_id:=(expected_event#>>'{old,event_id}')::UUID;
 reservation:=(p_stage.prestate#>>'{quota,id}')::UUID;
 IF p_retired IS NULL OR p_stage.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
  OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=original_id)
   IS DISTINCT FROM (CASE WHEN p_retired THEN expected_event->'new' ELSE expected_event->'old' END)
  OR (SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE id=event_id) IS DISTINCT FROM p_stage.prestate->'event'
  OR (SELECT to_jsonb(q) FROM internal.ai_quota_reservations q WHERE id=reservation) IS DISTINCT FROM p_stage.prestate->'quota'
  OR (SELECT count(*) FROM internal.identification_provider_attempts WHERE reservation_id=reservation)<>1
  OR (SELECT to_jsonb(a) FROM internal.identification_provider_attempts a WHERE reservation_id=reservation AND attempt_count=1)
   IS DISTINCT FROM p_stage.prestate->'attempt'
  OR (SELECT count(*) FROM internal.ai_quota_reservation_counters WHERE reservation_id=reservation)
   <>jsonb_array_length(p_stage.prestate->'charges')
  OR (SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id=p_stage.scan_id)
   <> (CASE WHEN p_stage.prestate->'complimentary'='null'::JSONB THEN 0 ELSE 1 END)
  OR COALESCE((SELECT to_jsonb(h) FROM internal.complimentary_scan_usage h
    WHERE user_id=p_stage.owner_id AND client_scan_id=p_stage.scan_id),'null'::JSONB)
   IS DISTINCT FROM p_stage.prestate->'complimentary'
  OR (SELECT jsonb_build_object('id',u.id,'entitlement_version',u.entitlement_version,
    'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch) FROM public.users u WHERE u.id=p_stage.owner_id)
   IS DISTINCT FROM p_stage.prestate->'owner_epoch' THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 FOR charge IN SELECT value FROM jsonb_array_elements(p_stage.prestate->'charges') LOOP
  SELECT to_jsonb(l) INTO actual_link FROM internal.ai_quota_reservation_counters l
   WHERE l.reservation_id=reservation AND l.scope_type=charge#>>'{link,scope_type}'
    AND l.scope_key=charge#>>'{link,scope_key}' AND l.bucket=charge#>>'{link,bucket}'
    AND l.window_start=(charge#>>'{link,window_start}')::TIMESTAMPTZ;
  SELECT to_jsonb(c) INTO actual_counter FROM internal.ai_quota_counters c
   WHERE c.scope_type=charge#>>'{counter,scope_type}' AND c.scope_key=charge#>>'{counter,scope_key}'
    AND c.bucket=charge#>>'{counter,bucket}' AND c.window_start=(charge#>>'{counter,window_start}')::TIMESTAMPTZ;
  IF actual_link IS DISTINCT FROM charge->'link' OR actual_counter IS DISTINCT FROM charge->'counter' THEN
   RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 END LOOP;
END;
$body$;

CREATE FUNCTION internal.guard_initial_cancellation_invocation_witness()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE stage internal.initial_admitted_cancellation_staging; expected_event JSONB; retired BOOLEAN;
BEGIN
 IF TG_OP='DELETE' THEN
  PERFORM internal.check_initial_cancellation_cleanup_member(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,to_jsonb(OLD),FALSE);
  RETURN OLD;
 END IF;
 IF TG_LEVEL<>'ROW' OR TG_OP NOT IN ('INSERT','UPDATE') THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 PERFORM internal.require_service_role();
 SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging
  WHERE scan_id=NEW.scan_id AND transaction_id=pg_catalog.pg_current_xact_id();
 IF NOT FOUND OR stage.variant IS DISTINCT FROM 'accounted_invocation'
  OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements WHERE scan_id=stage.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_cancellation_credit_witness WHERE scan_id=stage.scan_id)
  OR (SELECT to_jsonb(r) FROM internal.initial_preparation_admission_receipts r WHERE scan_id=stage.scan_id)
    IS DISTINCT FROM stage.prestate#>'{private_components,receipt}' THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 expected_event:=internal.initial_cancellation_invocation_event(stage);
 IF TG_OP='INSERT' THEN
  IF NEW.phase IS DISTINCT FROM 'pending' OR NEW.expected IS NOT NULL OR NEW.event_image IS NOT NULL
   OR EXISTS(SELECT 1 FROM internal.initial_cancellation_invocation_witness WHERE scan_id=NEW.scan_id) THEN
   RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
  NEW.expected:=expected_event; NEW.event_image:=stage.prestate->'event'; retired:=FALSE;
 ELSE
  IF pg_catalog.pg_trigger_depth()<>2 OR to_jsonb(NEW)-'phase' IS DISTINCT FROM to_jsonb(OLD)-'phase'
   OR OLD.expected IS DISTINCT FROM expected_event OR OLD.event_image IS DISTINCT FROM stage.prestate->'event' THEN
   RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
  IF OLD.phase='pending' AND NEW.phase='writing' THEN retired:=FALSE;
  ELSIF OLD.phase='writing' AND NEW.phase='observed' THEN retired:=TRUE;
  ELSIF OLD.phase='observed' AND NEW.phase='complete' THEN retired:=TRUE;
  ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 END IF;
 IF octet_length(to_jsonb(NEW)::TEXT)>262144 THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 PERFORM internal.assert_initial_cancellation_accounted_images(stage,retired);
 RETURN NEW;
END;
$body$;
CREATE TRIGGER guard_initial_cancellation_invocation_witness
 BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_cancellation_invocation_witness
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_invocation_witness();
CREATE TRIGGER guard_initial_cancellation_invocation_witness_truncate
 BEFORE TRUNCATE ON internal.initial_cancellation_invocation_witness
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_invocation_witness();

CREATE FUNCTION internal.guard_initial_cancellation_invocation_member()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $body$
DECLARE stage internal.initial_admitted_cancellation_staging; witness internal.initial_cancellation_invocation_witness;
 observed_event JSONB; affected BIGINT;
BEGIN
 SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_catalog.pg_current_xact_id();
 IF NOT FOUND THEN
  IF TG_LEVEL='STATEMENT' THEN RETURN NULL; ELSIF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
 END IF;
 IF TG_TABLE_SCHEMA<>'internal' OR TG_TABLE_NAME<>'identification_invocations' OR TG_OP<>'UPDATE'
  OR stage.variant IS DISTINCT FROM 'accounted_invocation' OR stage.phase IS DISTINCT FROM 'accounted' THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 SELECT * INTO witness FROM internal.initial_cancellation_invocation_witness WHERE scan_id=stage.scan_id;
 IF NOT FOUND OR witness.expected IS DISTINCT FROM internal.initial_cancellation_invocation_event(stage)
  OR witness.event_image IS DISTINCT FROM stage.prestate->'event' THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 IF TG_LEVEL='STATEMENT' THEN
  IF TG_WHEN='BEFORE' AND witness.phase='pending' THEN
   UPDATE internal.initial_cancellation_invocation_witness SET phase='writing' WHERE scan_id=stage.scan_id;
  ELSIF TG_WHEN='AFTER' AND witness.phase='observed' THEN
   UPDATE internal.initial_cancellation_invocation_witness SET phase='complete' WHERE scan_id=stage.scan_id;
  ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected<>1 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
  RETURN NULL;
 END IF;
 observed_event:=jsonb_build_object('relation',TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,'operation',TG_OP,
  'old',to_jsonb(OLD),'new',to_jsonb(NEW));
 IF witness.phase IS DISTINCT FROM 'writing' OR observed_event IS DISTINCT FROM witness.expected THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 IF TG_WHEN='AFTER' THEN
  UPDATE internal.initial_cancellation_invocation_witness SET phase='observed' WHERE scan_id=stage.scan_id;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected<>1 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 END IF;
 RETURN NEW;
END;
$body$;
CREATE TRIGGER a00_initial_cancellation_invocation_statement
 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.identification_invocations
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_invocation_member();
CREATE TRIGGER z999_initial_cancellation_invocation_statement
 AFTER UPDATE ON internal.identification_invocations
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_invocation_member();
CREATE TRIGGER a00_initial_cancellation_invocation_row
 BEFORE UPDATE ON internal.identification_invocations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_invocation_member();
CREATE TRIGGER z999_initial_cancellation_invocation_row
 AFTER UPDATE ON internal.identification_invocations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation_invocation_member();

CREATE FUNCTION internal.guard_initial_cancellation_accounted_funding()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $body$
BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging
  WHERE transaction_id=pg_catalog.pg_current_xact_id() AND variant='accounted_invocation') THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 RETURN NULL;
END;
$body$;
DO $funding$ DECLARE relation_name TEXT; BEGIN
 FOREACH relation_name IN ARRAY ARRAY['internal.ai_quota_reservations','internal.identification_provider_attempts',
  'internal.ai_quota_reservation_counters','internal.ai_quota_counters','internal.complimentary_scan_usage','public.users'] LOOP
  EXECUTE format('CREATE TRIGGER a00_initial_cancellation_accounted_funding BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON %s
   FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_accounted_funding()',relation_name);
 END LOOP;
END; $funding$;
REVOKE ALL ON FUNCTION
 internal.initial_cancellation_invocation_event(internal.initial_admitted_cancellation_staging),
 internal.assert_initial_cancellation_accounted_images(internal.initial_admitted_cancellation_staging,BOOLEAN),
 internal.guard_initial_cancellation_invocation_witness(),internal.guard_initial_cancellation_invocation_member(),
 internal.guard_initial_cancellation_accounted_funding() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.initial_cancellation_seal_catalog()
 RETURNS TABLE(relation_name text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
    VALUES ('internal.initial_cancellation_invocation_witness'),
        ('public.ai_usage_events'),
        ('internal.ai_quota_reservations'),
        ('internal.complimentary_scan_usage'),
        ('internal.identification_provider_attempts'),
        ('internal.ai_quota_counters'),
        ('internal.ai_quota_reservation_counters'),
        ('public.users'),
        ('internal.initial_analysis_submissions'),
        ('internal.initial_analysis_admissions'),
        ('internal.initial_analysis_lifecycle_fences'),
        ('internal.initial_preparation_admission_receipts'),
        ('internal.initial_media_copy_progress'),
        ('internal.initial_media_verification_claims_v2'),
        ('internal.initial_media_verification_receipts_v2'),
        ('internal.initial_preparation_transfer_receipts'),
        ('internal.initial_analysis_media_allocation_fences'),
        ('internal.initial_analysis_media_registry'),
        ('internal.initial_analysis_media_cohorts'),
        ('internal.initial_analysis_operation_fences'),
        ('internal.initial_analysis_preparation_intents'),
        ('internal.initial_preparation_source_fences'),
        ('internal.initial_preparation_source_registry'),
        ('internal.initial_preparation_source_mapping'),
        ('internal.initial_cpm_photo_role_mapping'),
        ('internal.initial_preparation_source_verifications'),
        ('internal.initial_preparation_execution_grants'),
        ('internal.initial_preparation_output_manifests'),
        ('internal.initial_preparation_output_mapping'),
        ('internal.initial_preparation_outcomes'),
        ('public.scans'),
        ('public.scan_ingestion_jobs'),
        ('public.scan_ingestion_intents'),
        ('internal.observation_histories'),
        ('internal.observation_analysis_source_bindings'),
        ('internal.observation_analysis_intents'),
        ('internal.observation_analysis_results'),
        ('internal.identification_invocations'),
        ('internal.initial_analysis_results'),
        ('internal.initial_analysis_completions'),
        ('internal.initial_analysis_media_preparations'),
        ('internal.initial_analysis_media_verifications'),
        ('internal.initial_analysis_cancellations'),
        ('internal.scan_deletion_tombstones'),
        ('internal.account_deletion_jobs'),
        ('internal.initial_preparation_admission_staging'),
        ('internal.initial_media_handoff_staging'),
        ('internal.initial_media_handoff_writes'),
        ('internal.initial_preparation_admission_writes'),
        ('internal.initial_admitted_cancellation_staging'),
        ('internal.initial_cancellation_quota_statements'),
        ('internal.initial_cancellation_credit_witness'),
        ('internal.initial_cancellation_lifecycle_witness'),
        ('internal.initial_cancellation_retirement_witness'),
        ('internal.initial_cancellation_erasure_witness'),
        ('internal.initial_cancellation_receipt_witness'),
        ('internal.initial_cancellation_terminal_snapshot');
$function$;
CREATE TRIGGER a00_initial_cancellation_seal BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.initial_cancellation_invocation_witness
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_seal();


-- C1 lifecycle shares exact row witnesses across exclusive settlement variants.
-- Phase recognition is not authority: callers must prove the corresponding
-- completed accounting witness and frozen images before mutation.
CREATE FUNCTION internal.initial_cancellation_shared_phase(p_stage internal.initial_admitted_cancellation_staging)
RETURNS BOOLEAN LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
 SELECT COALESCE((p_stage.variant='unused' AND p_stage.phase='quota' AND p_stage.quota_at IS NOT NULL)
  OR (p_stage.variant='accounted_invocation' AND p_stage.phase='accounted' AND p_stage.quota_at IS NULL),FALSE)
$body$;

-- This prerequisite is receipt-dependent. Call only before submission erasure;
-- later terminal owners must use captured accounting images and survivor proof.
CREATE FUNCTION internal.assert_initial_cancellation_settlement_prerequisite(p_stage internal.initial_admitted_cancellation_staging)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE credit internal.initial_cancellation_credit_witness; invocation internal.initial_cancellation_invocation_witness;
BEGIN
 IF NOT internal.initial_cancellation_shared_phase(p_stage)
  OR p_stage.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id() THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 IF p_stage.variant='unused' THEN
  SELECT * INTO credit FROM internal.initial_cancellation_credit_witness WHERE scan_id=p_stage.scan_id;
  IF NOT FOUND OR credit.phase IS DISTINCT FROM 'complete'
   OR EXISTS(SELECT 1 FROM internal.initial_cancellation_invocation_witness WHERE scan_id=p_stage.scan_id)
   OR (SELECT count(*) FROM internal.initial_cancellation_quota_statements WHERE scan_id=p_stage.scan_id AND closed)
      <>2*jsonb_array_length(p_stage.prestate->'charges')+2
   OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements WHERE scan_id=p_stage.scan_id AND NOT closed) THEN
   RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_admitted_cancellation_settlement(p_stage.prestate,p_stage.quota_at,credit.credit_at);
 ELSE
  SELECT * INTO invocation FROM internal.initial_cancellation_invocation_witness WHERE scan_id=p_stage.scan_id;
  IF NOT FOUND OR invocation.phase IS DISTINCT FROM 'complete'
   OR invocation.expected IS DISTINCT FROM internal.initial_cancellation_invocation_event(p_stage)
   OR invocation.event_image IS DISTINCT FROM p_stage.prestate->'event'
   OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements WHERE scan_id=p_stage.scan_id)
   OR EXISTS(SELECT 1 FROM internal.initial_cancellation_credit_witness WHERE scan_id=p_stage.scan_id)
   OR (SELECT to_jsonb(r) FROM internal.initial_preparation_admission_receipts r WHERE scan_id=p_stage.scan_id)
    IS DISTINCT FROM p_stage.prestate#>'{private_components,receipt}' THEN
   RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_cancellation_accounted_images(p_stage,TRUE);
 END IF;
END;
$body$;
CREATE OR REPLACE FUNCTION internal.initial_cancellation_lifecycle_event(p_stage internal.initial_admitted_cancellation_staging)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE terminal_state TEXT;
BEGIN
    terminal_state:=CASE
      WHEN p_stage.variant='unused' AND p_stage.prestate#>>'{lifecycle,state}'='pending_pre_dispatch' THEN 'cancelled_pre_dispatch'
      WHEN p_stage.variant='accounted_invocation' AND p_stage.prestate#>>'{lifecycle,state}'='pending_pre_dispatch' THEN 'cancelled_unknown'
      WHEN p_stage.variant='accounted_invocation' AND p_stage.prestate#>>'{lifecycle,state}'='dispatch_authorized' THEN 'cancelled_dispatched'
      ELSE NULL END;
    -- Deferred INSERT evidence retains captured phase; derive only immutable facts.
    IF terminal_state IS NULL
        OR p_stage.prestate#>>'{lifecycle,scan_id}' IS DISTINCT FROM p_stage.scan_id::TEXT THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    RETURN jsonb_build_object('relation','internal.initial_analysis_lifecycle_fences','operation','UPDATE',
        'old',p_stage.prestate->'lifecycle',
        'new',(p_stage.prestate->'lifecycle')||jsonb_build_object('state',terminal_state));
END; $function$
;
CREATE OR REPLACE FUNCTION internal.advance_initial_cancellation_lifecycle(p_owner uuid, p_scan uuid, p_terminal text, p_step text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE stage internal.initial_admitted_cancellation_staging;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND THEN RETURN; END IF;
    IF stage.owner_id IS DISTINCT FROM p_owner OR stage.scan_id IS DISTINCT FROM p_scan
        OR p_terminal IS DISTINCT FROM internal.initial_cancellation_lifecycle_event(stage)#>>'{new,state}' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF p_step='begin' THEN
        IF EXISTS(SELECT 1 FROM internal.initial_cancellation_lifecycle_witness WHERE scan_id=stage.scan_id) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        INSERT INTO internal.initial_cancellation_lifecycle_witness(scan_id) VALUES(stage.scan_id);
    ELSIF p_step='end' THEN
        UPDATE internal.initial_cancellation_lifecycle_witness SET phase='complete' WHERE scan_id=stage.scan_id AND phase='observed';
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
END; $function$
;
CREATE OR REPLACE FUNCTION internal.guard_initial_cancellation_lifecycle_witness()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE stage internal.initial_admitted_cancellation_staging;
    expected_event JSONB; actual JSONB;
BEGIN
    IF TG_OP='DELETE' THEN
        PERFORM internal.check_initial_cancellation_cleanup_member(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,to_jsonb(OLD),FALSE);
        RETURN OLD;
    END IF;
    PERFORM internal.require_service_role();
    IF TG_OP NOT IN ('INSERT','UPDATE') THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging
        WHERE scan_id=NEW.scan_id AND transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND OR NOT internal.initial_cancellation_shared_phase(stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_cancellation_settlement_prerequisite(stage);
    expected_event:=internal.initial_cancellation_lifecycle_event(stage);
    SELECT to_jsonb(f) INTO actual FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=stage.scan_id;
    IF TG_OP='INSERT' THEN
        IF NEW.phase IS DISTINCT FROM 'pending' OR NEW.event IS NOT NULL
            OR actual IS DISTINCT FROM expected_event->'old'
            OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=stage.scan_id) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
    ELSE
        IF NEW.scan_id IS DISTINCT FROM OLD.scan_id OR actual IS DISTINCT FROM expected_event->'new' THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        IF OLD.phase='pending' AND NEW.phase='observed' THEN
            IF pg_trigger_depth()<2 OR OLD.event IS NOT NULL OR NEW.event IS DISTINCT FROM expected_event THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
        ELSIF OLD.phase='observed' AND NEW.phase='complete' THEN
            IF OLD.event IS DISTINCT FROM expected_event OR NEW.event IS DISTINCT FROM OLD.event THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
        ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
    RETURN NEW;
END; $function$
;
CREATE OR REPLACE FUNCTION internal.initial_cancellation_lifecycle_authorized(p_old jsonb, p_new jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE s internal.initial_admitted_cancellation_staging; w internal.initial_cancellation_lifecycle_witness;
 event JSONB;
BEGIN
 SELECT * INTO s FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR NOT internal.initial_cancellation_shared_phase(s) THEN RETURN FALSE; END IF;
 SELECT * INTO w FROM internal.initial_cancellation_lifecycle_witness WHERE scan_id=s.scan_id;
 IF NOT FOUND OR w.phase IS DISTINCT FROM 'pending' OR w.event IS NOT NULL THEN RETURN FALSE; END IF;
 event:=internal.initial_cancellation_lifecycle_event(s);
 IF event->'old' IS DISTINCT FROM p_old OR event->'new' IS DISTINCT FROM p_new THEN RETURN FALSE; END IF;
 PERFORM internal.assert_initial_cancellation_settlement_prerequisite(s);
 RETURN TRUE;
END; $function$
;
CREATE OR REPLACE FUNCTION internal.guard_initial_cancellation_lifecycle_member()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE stage internal.initial_admitted_cancellation_staging; witness internal.initial_cancellation_lifecycle_witness; observed_event JSONB;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_catalog.pg_current_xact_id();
    IF NOT FOUND THEN
        IF TG_OP='TRUNCATE' THEN RETURN NULL; ELSIF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    IF TG_OP<>'UPDATE' OR NOT internal.initial_cancellation_shared_phase(stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_cancellation_settlement_prerequisite(stage);
    SELECT * INTO witness FROM internal.initial_cancellation_lifecycle_witness WHERE scan_id=stage.scan_id;
    IF NOT FOUND OR witness.phase IS DISTINCT FROM 'pending' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    observed_event:=jsonb_build_object('relation',TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,'operation',TG_OP,'old',to_jsonb(OLD),'new',to_jsonb(NEW));
    IF observed_event IS DISTINCT FROM internal.initial_cancellation_lifecycle_event(stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_WHEN='AFTER' THEN
        UPDATE internal.initial_cancellation_lifecycle_witness SET phase='observed',event=observed_event WHERE scan_id=stage.scan_id;
    END IF;
    RETURN NEW;
END; $function$
;

REVOKE ALL ON FUNCTION
 internal.initial_cancellation_shared_phase(internal.initial_admitted_cancellation_staging),
 internal.assert_initial_cancellation_settlement_prerequisite(internal.initial_admitted_cancellation_staging)
 FROM PUBLIC,anon,authenticated,service_role;


-- Shared media/private owners preserve the existing exact image and root order.
-- Accounted settlement is checked before receipt deletion; after that boundary
-- only captured identity, surviving accounting and observed witnesses are used.
CREATE OR REPLACE FUNCTION internal.guard_initial_cancellation_retirement_witness()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE stage internal.initial_admitted_cancellation_staging;
    lifecycle internal.initial_cancellation_lifecycle_witness; source_witness internal.initial_cancellation_retirement_witness;
BEGIN
    IF TG_OP='DELETE' THEN
        PERFORM internal.check_initial_cancellation_cleanup_member(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,to_jsonb(OLD),FALSE);
        RETURN OLD;
    END IF;
    PERFORM internal.require_service_role();
    IF TG_OP NOT IN ('INSERT','UPDATE') THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE scan_id=NEW.scan_id AND transaction_id=pg_current_xact_id();
    IF NOT FOUND OR NOT internal.initial_cancellation_shared_phase(stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO lifecycle FROM internal.initial_cancellation_lifecycle_witness WHERE scan_id=stage.scan_id;
    IF NOT FOUND OR lifecycle.phase IS DISTINCT FROM 'complete'
        OR lifecycle.event IS DISTINCT FROM internal.initial_cancellation_lifecycle_event(stage)
        OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=stage.scan_id)
            IS DISTINCT FROM lifecycle.event->'new' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_OP='INSERT' THEN
        IF NEW.expected IS NOT NULL OR NEW.observed IS DISTINCT FROM '[]'::JSONB OR NEW.phase IS DISTINCT FROM 'pending'
            OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=stage.scan_id) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_cancellation_settlement_prerequisite(stage);
        IF NEW.side='source' THEN
            -- Check both original sets before the first permanent retirement.
            PERFORM internal.assert_initial_cancellation_retirement_images(stage.scan_id,'destination',
                internal.initial_cancellation_retirement_events(stage,'destination'),FALSE,stage.prestate);
        ELSIF NEW.side='destination' THEN
            SELECT * INTO source_witness FROM internal.initial_cancellation_retirement_witness WHERE scan_id=stage.scan_id AND side='source';
            IF NOT FOUND OR source_witness.phase IS DISTINCT FROM 'complete' OR source_witness.observed IS DISTINCT FROM source_witness.expected THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            PERFORM internal.assert_initial_cancellation_retirement_images(stage.scan_id,'source',source_witness.expected,TRUE,stage.prestate);
        END IF;
        NEW.expected:=internal.initial_cancellation_retirement_events(stage,NEW.side);
        PERFORM internal.assert_initial_cancellation_retirement_images(stage.scan_id,NEW.side,NEW.expected,FALSE,stage.prestate);
    ELSE
        IF OLD.phase='complete' OR to_jsonb(OLD)-ARRAY['phase','observed'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['phase','observed'] THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        IF NEW.phase='pending' THEN
            IF pg_trigger_depth()<2 OR jsonb_array_length(OLD.observed)>=jsonb_array_length(OLD.expected)
                OR NEW.observed IS DISTINCT FROM OLD.observed||jsonb_build_array(OLD.expected->jsonb_array_length(OLD.observed)) THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
        ELSIF NEW.phase='complete' THEN
            IF OLD.observed IS DISTINCT FROM OLD.expected OR NEW.observed IS DISTINCT FROM OLD.observed THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            PERFORM internal.assert_initial_cancellation_retirement_images(stage.scan_id,NEW.side,NEW.expected,TRUE,stage.prestate);
        ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
    RETURN NEW;
END; $function$
;
CREATE OR REPLACE FUNCTION internal.guard_initial_cancellation_retirement_member()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE stage internal.initial_admitted_cancellation_staging; witness internal.initial_cancellation_retirement_witness; side_name TEXT; observed_event JSONB;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
    IF NOT FOUND THEN
        IF TG_OP='TRUNCATE' THEN RETURN NULL; ELSIF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    IF TG_OP<>'UPDATE' OR NOT internal.initial_cancellation_shared_phase(stage) THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    side_name:=CASE WHEN TG_TABLE_NAME IN ('initial_preparation_source_fences','initial_preparation_source_registry') THEN 'source' ELSE 'destination' END;
    SELECT * INTO witness FROM internal.initial_cancellation_retirement_witness WHERE scan_id=stage.scan_id AND side=side_name;
    IF NOT FOUND OR witness.phase IS DISTINCT FROM 'pending' THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    observed_event:=jsonb_build_object('relation',TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,'operation',TG_OP,'old',to_jsonb(OLD),'new',to_jsonb(NEW));
    IF observed_event IS DISTINCT FROM witness.expected->jsonb_array_length(witness.observed) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_WHEN='AFTER' THEN
        UPDATE internal.initial_cancellation_retirement_witness SET observed=observed||jsonb_build_array(observed_event)
            WHERE scan_id=stage.scan_id AND side=side_name;
    END IF;
    RETURN NEW;
END; $function$
;
CREATE OR REPLACE FUNCTION internal.guard_initial_cancellation_private_member()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE stage internal.initial_admitted_cancellation_staging; witness internal.initial_cancellation_erasure_witness;
    event_value JSONB; event_index INTEGER; matches INTEGER;
BEGIN
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id();
    IF NOT FOUND THEN
        IF TG_OP='TRUNCATE' THEN RETURN NULL; ELSIF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    IF TG_OP<>'DELETE' OR NOT internal.initial_cancellation_shared_phase(stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO witness FROM internal.initial_cancellation_erasure_witness WHERE scan_id=stage.scan_id AND phase='pending';
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    event_value:=jsonb_build_object('relation',TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,'operation','DELETE','old',to_jsonb(OLD));
    SELECT count(*),min(ordinal-1)::INTEGER INTO matches,event_index
        FROM jsonb_array_elements(witness.expected) WITH ORDINALITY e(value,ordinal) WHERE value=event_value;
    IF matches<>1 OR event_index=ANY(witness.observed) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF TG_WHEN='AFTER' THEN
        UPDATE internal.initial_cancellation_erasure_witness SET observed=array_append(observed,event_index)
            WHERE scan_id=stage.scan_id AND root_name=witness.root_name;
    END IF;
    RETURN OLD;
END; $function$
;
CREATE OR REPLACE FUNCTION internal.capture_initial_cancellation_accounting_images(p_stage internal.initial_admitted_cancellation_staging)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE reservation UUID:=(p_stage.prestate#>>'{quota,id}')::UUID;
    charge JSONB; counter_image JSONB; link_image JSONB; result JSONB; counters JSONB:='[]'::JSONB;
BEGIN
    IF p_stage.variant='accounted_invocation' THEN
        PERFORM internal.assert_initial_cancellation_accounted_images(p_stage,TRUE);
    END IF;
    FOR charge IN SELECT value FROM jsonb_array_elements(p_stage.prestate->'charges') LOOP
        SELECT to_jsonb(c) INTO counter_image FROM internal.ai_quota_counters c
            WHERE c.scope_type=charge#>>'{counter,scope_type}' AND c.scope_key=charge#>>'{counter,scope_key}'
                AND c.bucket=charge#>>'{counter,bucket}' AND c.window_start=(charge#>>'{counter,window_start}')::TIMESTAMPTZ;
        link_image:=charge->'link';
        IF p_stage.variant='accounted_invocation' THEN
            SELECT to_jsonb(l) INTO link_image FROM internal.ai_quota_reservation_counters l
                WHERE l.reservation_id=reservation AND l.scope_type=charge#>>'{link,scope_type}'
                    AND l.scope_key=charge#>>'{link,scope_key}' AND l.bucket=charge#>>'{link,bucket}'
                    AND l.window_start=(charge#>>'{link,window_start}')::TIMESTAMPTZ;
        END IF;
        counters:=counters||jsonb_build_array(jsonb_build_object('link',link_image,'counter',counter_image));
    END LOOP;
    result:=jsonb_build_object(
        'quota',(SELECT to_jsonb(q) FROM internal.ai_quota_reservations q WHERE id=reservation),
        'link_count',(SELECT count(*) FROM internal.ai_quota_reservation_counters WHERE reservation_id=reservation),
        'attempt_count',(SELECT count(*) FROM internal.identification_provider_attempts WHERE reservation_id=reservation),
        'attempt',(SELECT to_jsonb(a) FROM internal.identification_provider_attempts a WHERE reservation_id=reservation AND attempt_count=1),
        'counters',counters,
        'hold_count',(SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id=p_stage.scan_id),
        'hold',(SELECT to_jsonb(h) FROM internal.complimentary_scan_usage h WHERE user_id=p_stage.owner_id AND client_scan_id=p_stage.scan_id),
        'owner_epoch',(SELECT jsonb_build_object('id',u.id,'entitlement_version',u.entitlement_version,
            'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch) FROM public.users u WHERE id=p_stage.owner_id));
    IF p_stage.variant='accounted_invocation' THEN
        result:=result||jsonb_build_object(
            'invocation',(SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=(p_stage.prestate#>>'{invocation,id}')::UUID),
            'event',(SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE id=(p_stage.prestate#>>'{event,id}')::UUID));
    END IF;
    RETURN result;
END; $function$
;
CREATE OR REPLACE FUNCTION internal.initial_cancellation_receipt_image(p_stage internal.initial_admitted_cancellation_staging)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SET search_path='' AS $body$
DECLARE dispatch_state TEXT;
BEGIN
 dispatch_state:=CASE internal.initial_cancellation_lifecycle_event(p_stage)#>>'{new,state}'
  WHEN 'cancelled_pre_dispatch' THEN 'dispatch_prevented'
  WHEN 'cancelled_unknown' THEN 'dispatch_outcome_unknown'
  WHEN 'cancelled_dispatched' THEN 'dispatch_already_authorized'
  ELSE NULL END;
 IF dispatch_state IS NULL THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 RETURN jsonb_build_object('scan_id',p_stage.scan_id,'owner_id',p_stage.owner_id,'dispatch',dispatch_state);
END;
$body$;
CREATE OR REPLACE FUNCTION internal.assert_initial_cancellation_erasure_boundary(p_stage internal.initial_admitted_cancellation_staging, p_receipt jsonb)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE lifecycle internal.initial_cancellation_lifecycle_witness;
    retirement internal.initial_cancellation_retirement_witness; invocation internal.initial_cancellation_invocation_witness; side_name TEXT; accounting JSONB;
BEGIN
    IF (p_receipt IS NOT NULL AND p_receipt IS DISTINCT FROM internal.initial_cancellation_receipt_image(p_stage))
        OR p_stage.transaction_id IS DISTINCT FROM pg_current_xact_id() OR NOT internal.initial_cancellation_shared_phase(p_stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    -- Receipt may already be erased. Never use the receipt-dependent settlement
    -- prerequisite here. Retained invocation/event/funding are checked by ID.
    IF p_stage.variant='accounted_invocation' THEN
        SELECT * INTO invocation FROM internal.initial_cancellation_invocation_witness WHERE scan_id=p_stage.scan_id;
        IF NOT FOUND OR invocation.phase IS DISTINCT FROM 'complete'
            OR invocation.expected IS DISTINCT FROM internal.initial_cancellation_invocation_event(p_stage)
            OR invocation.event_image IS DISTINCT FROM p_stage.prestate->'event'
            OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements WHERE scan_id=p_stage.scan_id)
            OR EXISTS(SELECT 1 FROM internal.initial_cancellation_credit_witness WHERE scan_id=p_stage.scan_id) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        PERFORM internal.assert_initial_cancellation_accounted_images(p_stage,TRUE);
    ELSIF EXISTS(SELECT 1 FROM internal.initial_cancellation_invocation_witness WHERE scan_id=p_stage.scan_id) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO lifecycle FROM internal.initial_cancellation_lifecycle_witness WHERE scan_id=p_stage.scan_id;
    IF NOT FOUND OR lifecycle.phase IS DISTINCT FROM 'complete'
        OR lifecycle.event IS DISTINCT FROM internal.initial_cancellation_lifecycle_event(p_stage)
        OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=p_stage.scan_id)
            IS DISTINCT FROM lifecycle.event->'new'
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_stage.scan_id)
        OR (SELECT to_jsonb(c) FROM internal.initial_analysis_cancellations c WHERE scan_id=p_stage.scan_id)
            IS DISTINCT FROM p_receipt THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    FOREACH side_name IN ARRAY ARRAY['source','destination'] LOOP
        SELECT * INTO retirement FROM internal.initial_cancellation_retirement_witness
            WHERE scan_id=p_stage.scan_id AND side=side_name;
        IF NOT FOUND OR retirement.phase IS DISTINCT FROM 'complete' OR retirement.observed IS DISTINCT FROM retirement.expected
            OR retirement.expected IS DISTINCT FROM internal.initial_cancellation_retirement_events(p_stage,side_name) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_cancellation_retirement_images(p_stage.scan_id,side_name,retirement.expected,TRUE,p_stage.prestate);
    END LOOP;
    SELECT accounting_images INTO accounting FROM internal.initial_cancellation_erasure_witness
        WHERE scan_id=p_stage.scan_id AND root_name='submission';
    IF FOUND AND accounting IS DISTINCT FROM internal.capture_initial_cancellation_accounting_images(p_stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
END; $function$
;
CREATE OR REPLACE FUNCTION internal.guard_initial_cancellation_erasure_witness()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE stage internal.initial_admitted_cancellation_staging;
    previous internal.initial_cancellation_erasure_witness; member RECORD; item JSONB;
    event_value JSONB; event_count INTEGER; appended INTEGER; complete_indexes INTEGER[];
BEGIN
    IF TG_OP='DELETE' THEN
        PERFORM internal.check_initial_cancellation_cleanup_member(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,to_jsonb(OLD),FALSE);
        RETURN OLD;
    END IF;
    PERFORM internal.require_service_role();
    IF TG_OP NOT IN ('INSERT','UPDATE') THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE scan_id=NEW.scan_id AND transaction_id=pg_current_xact_id();
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    IF TG_OP='INSERT' THEN
        IF NEW.root_name IS NULL OR NEW.root_name NOT IN ('submission','intent') OR NEW.phase IS DISTINCT FROM 'pending'
            OR NEW.expected IS NOT NULL OR NEW.accounting_images IS NOT NULL OR NEW.observed IS DISTINCT FROM '{}'::INTEGER[]
            OR EXISTS(SELECT 1 FROM internal.initial_cancellation_erasure_witness WHERE scan_id=stage.scan_id AND phase='pending') THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_cancellation_erasure_boundary(stage);
        IF NEW.root_name='submission' THEN
            IF EXISTS(SELECT 1 FROM internal.initial_cancellation_erasure_witness WHERE scan_id=stage.scan_id) THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            -- Last receipt-dependent comparison; later phases use frozen images.
            PERFORM internal.assert_initial_cancellation_settlement_prerequisite(stage);
            NEW.accounting_images:=internal.capture_initial_cancellation_accounting_images(stage);
            PERFORM internal.assert_initial_cancellation_private_progress(stage,'{}');
        ELSE
            SELECT * INTO previous FROM internal.initial_cancellation_erasure_witness WHERE scan_id=stage.scan_id AND root_name='submission';
            IF NOT FOUND OR previous.phase IS DISTINCT FROM 'complete' THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            NEW.accounting_images:=previous.accounting_images;
            PERFORM internal.assert_initial_cancellation_private_progress(stage,ARRAY['submission']);
        END IF;
        NEW.expected:='[]';
        FOR member IN SELECT * FROM internal.initial_cancellation_private_catalog() WHERE root_name=NEW.root_name ORDER BY relation_name LOOP
            FOR item IN SELECT value FROM jsonb_array_elements(stage.prestate->'erasure_images'->member.relation_name) LOOP
                IF item->>'scan_id' IS DISTINCT FROM stage.scan_id::TEXT THEN
                    RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
                END IF;
                event_value:=jsonb_build_object('relation',member.relation_name,'operation','DELETE','old',item);
                IF NEW.expected @> jsonb_build_array(event_value) THEN
                    RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
                END IF;
                NEW.expected:=NEW.expected||jsonb_build_array(event_value);
            END LOOP;
        END LOOP;
    ELSE
        IF OLD.phase IS DISTINCT FROM 'pending' OR to_jsonb(OLD)-ARRAY['phase','observed'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['phase','observed'] THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        event_count:=jsonb_array_length(OLD.expected);
        IF NEW.phase='pending' THEN
            appended:=NEW.observed[cardinality(NEW.observed)];
            IF pg_trigger_depth()<2 OR cardinality(NEW.observed)<>cardinality(OLD.observed)+1
                OR appended IS NULL OR appended<0 OR appended>=event_count OR appended=ANY(OLD.observed)
                OR NEW.observed IS DISTINCT FROM array_append(OLD.observed,appended) THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
        ELSIF NEW.phase='complete' THEN
            SELECT array_agg(i ORDER BY i) INTO complete_indexes FROM generate_series(0,event_count-1) i;
            IF NEW.observed IS DISTINCT FROM OLD.observed
                OR (SELECT array_agg(i ORDER BY i) FROM unnest(OLD.observed) i) IS DISTINCT FROM complete_indexes THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
            END IF;
            PERFORM internal.assert_initial_cancellation_erasure_boundary(stage);
            PERFORM internal.assert_initial_cancellation_private_progress(stage,
                CASE WHEN NEW.root_name='submission' THEN ARRAY['submission'] ELSE ARRAY['submission','intent'] END);
        ELSE RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
    RETURN NEW;
END; $function$
;


-- Complete C1 terminal consumption uses exclusive witness families under the
-- existing16-row cursor bound. Captured tuples independently prove survivors.
CREATE OR REPLACE FUNCTION internal.initial_cancellation_terminal_catalog()
 RETURNS TABLE(relation_name text, row_limit integer, order_key text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
    VALUES ('internal.initial_admitted_cancellation_staging',1,'scan_id'),
        ('internal.initial_cancellation_quota_statements',8,'ordinal'),
        ('internal.initial_cancellation_credit_witness',1,'scan_id'),
        ('internal.initial_cancellation_invocation_witness',1,'scan_id'),
        ('internal.initial_cancellation_lifecycle_witness',1,'scan_id'),
        ('internal.initial_cancellation_retirement_witness',2,'side'),
        ('internal.initial_cancellation_erasure_witness',2,'root_name'),
        ('internal.initial_cancellation_receipt_witness',1,'scan_id');
$function$
;
CREATE OR REPLACE FUNCTION internal.initial_cancellation_cleanup_catalog()
 RETURNS TABLE(cleanup_order integer, relation_name text, order_key text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
    VALUES (1,'internal.initial_cancellation_quota_statements','ordinal'),
        (2,'internal.initial_cancellation_credit_witness','scan_id'),
        (3,'internal.initial_cancellation_invocation_witness','scan_id'),
        (4,'internal.initial_cancellation_lifecycle_witness','scan_id'),
        (5,'internal.initial_cancellation_retirement_witness','side'),
        (6,'internal.initial_cancellation_erasure_witness','root_name'),
        (7,'internal.initial_cancellation_receipt_witness','scan_id'),
        (8,'internal.initial_admitted_cancellation_staging','scan_id');
$function$
;
CREATE FUNCTION internal.assert_initial_cancellation_terminal_shape(p_proof JSONB)
RETURNS VOID LANGUAGE PLPGSQL IMMUTABLE SET search_path='' AS $body$
DECLARE stage internal.initial_admitted_cancellation_staging; member RECORD; n INTEGER; total INTEGER:=0; item JSONB;
BEGIN
 IF jsonb_typeof(p_proof->'rows') IS DISTINCT FROM 'object'
  OR (SELECT count(*) FROM jsonb_object_keys(p_proof->'rows'))<>8 THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 FOR member IN SELECT * FROM internal.initial_cancellation_terminal_catalog() LOOP
  IF jsonb_typeof(p_proof->'rows'->member.relation_name) IS DISTINCT FROM 'array' THEN
   RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
  n:=jsonb_array_length(p_proof->'rows'->member.relation_name);
  IF n>member.row_limit THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
  IF member.relation_name NOT IN ('internal.initial_cancellation_quota_statements','internal.initial_cancellation_credit_witness','internal.initial_cancellation_invocation_witness')
   AND n<>member.row_limit THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_proof->'rows'->member.relation_name) LOOP
   IF jsonb_typeof(item) IS DISTINCT FROM 'object' OR item->>'scan_id' IS DISTINCT FROM p_proof->>'scan_id' THEN
    RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
  END LOOP;
  total:=total+n;
 END LOOP;
 stage:=jsonb_populate_record(NULL::internal.initial_admitted_cancellation_staging,p_proof#>'{rows,internal.initial_admitted_cancellation_staging,0}');
 IF NOT internal.initial_cancellation_shared_phase(stage) OR total>16 THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 IF stage.variant='unused' THEN
  n:=jsonb_array_length(p_proof#>'{rows,internal.initial_cancellation_quota_statements}');
  IF n<2 OR n>8 OR n<>2*jsonb_array_length(stage.prestate->'charges')+2
   OR jsonb_array_length(p_proof#>'{rows,internal.initial_cancellation_credit_witness}')<>1
   OR jsonb_array_length(p_proof#>'{rows,internal.initial_cancellation_invocation_witness}')<>0
   OR total<>n+8 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 ELSE
  IF jsonb_array_length(p_proof#>'{rows,internal.initial_cancellation_quota_statements}')<>0
   OR jsonb_array_length(p_proof#>'{rows,internal.initial_cancellation_credit_witness}')<>0
   OR jsonb_array_length(p_proof#>'{rows,internal.initial_cancellation_invocation_witness}')<>1
   OR total<>8 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 END IF;
END;
$body$;
CREATE OR REPLACE FUNCTION internal.initial_cancellation_cleanup_count(p_proof JSONB)
RETURNS INTEGER LANGUAGE PLPGSQL IMMUTABLE SET search_path='' AS $body$
DECLARE total INTEGER;
BEGIN
 PERFORM internal.assert_initial_cancellation_terminal_shape(p_proof);
 SELECT sum(jsonb_array_length(p_proof->'rows'->c.relation_name))::INTEGER INTO total
  FROM internal.initial_cancellation_cleanup_catalog() c;
 RETURN total;
END;
$body$;
CREATE OR REPLACE FUNCTION internal.assert_initial_cancellation_cleanup_suffix(p_scan uuid, p_proof jsonb, p_cursor integer)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE member RECORD; item JSONB; actual JSONB; total INTEGER; n INTEGER;
    offset_value INTEGER:=0; remaining INTEGER; actual_count INTEGER;
BEGIN
    total:=internal.initial_cancellation_cleanup_count(p_proof);
    IF total IS NULL OR total<8 OR total>16 OR p_cursor IS NULL OR p_cursor<0 OR p_cursor>total THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    FOR member IN SELECT * FROM internal.initial_cancellation_cleanup_catalog() ORDER BY cleanup_order LOOP
        n:=jsonb_array_length(p_proof->'rows'->member.relation_name);
        remaining:=greatest(0,offset_value+n-greatest(offset_value,p_cursor));
        EXECUTE format('SELECT count(*) FROM (SELECT 1 FROM %s WHERE scan_id=$1 LIMIT 17) bounded',member.relation_name)
            INTO actual_count USING p_scan;
        IF actual_count<>remaining THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        FOR i IN 0..n-1 LOOP
            IF offset_value+i>=p_cursor THEN
                item:=(p_proof->'rows'->member.relation_name)->i;
                EXECUTE format('SELECT to_jsonb(t) FROM %s t WHERE scan_id=$1 AND %I::TEXT=$2',member.relation_name,member.order_key)
                    INTO actual USING p_scan,item->>member.order_key;
                IF actual IS DISTINCT FROM item THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
            END IF;
        END LOOP;
        offset_value:=offset_value+n;
    END LOOP;
END; $function$
;
CREATE OR REPLACE FUNCTION internal.assert_initial_cancellation_terminal_predecessors(p_scan uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE stage internal.initial_admitted_cancellation_staging; quota internal.initial_cancellation_quota_statements;
    credit internal.initial_cancellation_credit_witness; receipt internal.initial_cancellation_receipt_witness;
    erasure internal.initial_cancellation_erasure_witness; contract RECORD; member RECORD;
    n INTEGER; events JSONB; item JSONB;
BEGIN
    PERFORM internal.require_service_role();
    SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging WHERE scan_id=p_scan AND transaction_id=pg_current_xact_id();
    IF NOT FOUND OR stage.prestate->>'scan_id' IS DISTINCT FROM stage.scan_id::TEXT
        OR stage.prestate->>'owner_id' IS DISTINCT FROM stage.owner_id::TEXT
        OR stage.prestate->>'transaction_id' IS DISTINCT FROM stage.transaction_id::TEXT THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_cancellation_receipt_boundary(stage,TRUE);
    IF stage.variant='unused' THEN
        IF EXISTS(SELECT 1 FROM internal.initial_cancellation_invocation_witness WHERE scan_id=p_scan) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    n:=2*jsonb_array_length(stage.prestate->'charges')+2;
    IF n<2 OR n>8 OR (SELECT count(*) FROM internal.initial_cancellation_quota_statements WHERE scan_id=p_scan)<>n THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    FOR i IN 0..n-1 LOOP
        SELECT * INTO quota FROM internal.initial_cancellation_quota_statements WHERE scan_id=p_scan AND ordinal=i;
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        SELECT * INTO STRICT contract FROM internal.initial_cancellation_quota_contract(stage,i);
        IF NOT quota.closed OR quota.statement_key IS DISTINCT FROM contract.statement_key
            OR quota.link_identity IS DISTINCT FROM contract.link_identity OR quota.expected IS DISTINCT FROM contract.expected
            OR jsonb_array_length(quota.observed)<>jsonb_array_length(quota.expected)
            OR NOT quota.observed @> quota.expected OR NOT quota.expected @> quota.observed THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
    SELECT * INTO credit FROM internal.initial_cancellation_credit_witness WHERE scan_id=p_scan;
    IF NOT FOUND OR credit.phase IS DISTINCT FROM 'complete'
        OR credit.held IS DISTINCT FROM (stage.prestate->'complimentary'<>'null'::JSONB)
        OR (credit.held AND (credit.credit_at IS NULL OR NOT isfinite(credit.credit_at) OR credit.credit_at<stage.quota_at))
        OR (NOT credit.held AND credit.credit_at IS NOT NULL) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    events:='[]';
    IF credit.held THEN events:=jsonb_build_array(internal.initial_cancellation_credit_event(stage,credit,'hold.release'),
        internal.initial_cancellation_credit_event(stage,credit,'owner.epoch')); END IF;
    IF credit.events IS DISTINCT FROM events THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    ELSE
        -- Receipt boundary already independently checked the completed invocation
        -- witness and exact surviving event/funding without the erased receipt.
        IF stage.variant IS DISTINCT FROM 'accounted_invocation'
            OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements WHERE scan_id=p_scan)
            OR EXISTS(SELECT 1 FROM internal.initial_cancellation_credit_witness WHERE scan_id=p_scan) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
    -- Reconstruct every OLD deletion event from the frozen original catalog.
    -- Earlier guarded capture supplies provenance; current root absence is
    -- independently checked above without reading erased receipt rows.
    FOR erasure IN SELECT * FROM internal.initial_cancellation_erasure_witness WHERE scan_id=p_scan LOOP
        events:='[]';
        FOR member IN SELECT * FROM internal.initial_cancellation_private_catalog() WHERE root_name=erasure.root_name ORDER BY relation_name LOOP
            FOR item IN SELECT value FROM jsonb_array_elements(stage.prestate->'erasure_images'->member.relation_name) LOOP
                IF item->>'scan_id' IS DISTINCT FROM p_scan::TEXT THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
                events:=events||jsonb_build_array(jsonb_build_object('relation',member.relation_name,'operation','DELETE','old',item));
            END LOOP;
        END LOOP;
        IF erasure.expected IS DISTINCT FROM events THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END LOOP;
    SELECT * INTO receipt FROM internal.initial_cancellation_receipt_witness WHERE scan_id=p_scan;
    IF NOT FOUND OR receipt.phase IS DISTINCT FROM 'complete' OR NOT receipt.observed
        OR receipt.expected IS DISTINCT FROM internal.initial_cancellation_receipt_image(stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
END; $function$
;
CREATE FUNCTION internal.assert_initial_cancellation_accounted_final(p_stage internal.initial_admitted_cancellation_staging)
RETURNS VOID LANGUAGE PLPGSQL SET search_path='' AS $body$
BEGIN
 PERFORM internal.assert_initial_cancellation_accounted_images(p_stage,TRUE);
 IF p_stage.prestate->>'transaction_id' IS DISTINCT FROM pg_current_xact_id()::TEXT
  OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM public.scans WHERE id=p_stage.scan_id)
  OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=p_stage.scan_id)
    IS DISTINCT FROM internal.initial_cancellation_lifecycle_event(p_stage)->'new'
  OR (SELECT to_jsonb(c) FROM internal.initial_analysis_cancellations c WHERE scan_id=p_stage.scan_id)
    IS DISTINCT FROM internal.initial_cancellation_receipt_image(p_stage) THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 PERFORM internal.assert_initial_cancellation_private_progress(p_stage,ARRAY['submission','intent']);
END;
$body$;
CREATE OR REPLACE FUNCTION internal.assert_initial_cancellation_terminal_survivors(p_proof jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE stage internal.initial_admitted_cancellation_staging;
    lifecycle internal.initial_cancellation_lifecycle_witness;
    retirement internal.initial_cancellation_retirement_witness;
    erasure internal.initial_cancellation_erasure_witness;
    receipt internal.initial_cancellation_receipt_witness;
    invocation internal.initial_cancellation_invocation_witness; accounting JSONB; indexes INTEGER[]; side_name TEXT;
BEGIN
    PERFORM internal.assert_initial_cancellation_terminal_shape(p_proof);
    SELECT * INTO stage FROM jsonb_populate_record(NULL::internal.initial_admitted_cancellation_staging,
        p_proof#>'{rows,internal.initial_admitted_cancellation_staging,0}');
    IF p_proof->>'version' IS DISTINCT FROM '1' OR p_proof->>'authority' IS DISTINCT FROM 'none'
        OR p_proof->>'scan_id' IS DISTINCT FROM stage.scan_id::TEXT
        OR p_proof->>'owner_id' IS DISTINCT FROM stage.owner_id::TEXT
        OR p_proof->>'transaction_id' IS DISTINCT FROM pg_current_xact_id()::TEXT
        OR stage.transaction_id IS DISTINCT FROM pg_current_xact_id() OR NOT internal.initial_cancellation_shared_phase(stage)
        OR (stage.variant='unused' AND NOT isfinite(stage.quota_at)) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF stage.variant='accounted_invocation' THEN
        SELECT * INTO invocation FROM jsonb_populate_record(NULL::internal.initial_cancellation_invocation_witness,
            p_proof#>'{rows,internal.initial_cancellation_invocation_witness,0}');
        IF invocation.scan_id IS DISTINCT FROM stage.scan_id OR invocation.phase IS DISTINCT FROM 'complete'
            OR invocation.expected IS DISTINCT FROM internal.initial_cancellation_invocation_event(stage)
            OR invocation.event_image IS DISTINCT FROM stage.prestate->'event' THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        PERFORM internal.assert_initial_cancellation_accounted_final(stage);
    END IF;
    SELECT * INTO lifecycle FROM jsonb_populate_record(NULL::internal.initial_cancellation_lifecycle_witness,
        p_proof#>'{rows,internal.initial_cancellation_lifecycle_witness,0}');
    IF lifecycle.phase IS DISTINCT FROM 'complete' OR lifecycle.scan_id IS DISTINCT FROM stage.scan_id
        OR lifecycle.event IS DISTINCT FROM internal.initial_cancellation_lifecycle_event(stage)
        OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=stage.scan_id) IS DISTINCT FROM lifecycle.event->'new'
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=stage.scan_id)
        OR (SELECT to_jsonb(c) FROM internal.initial_analysis_cancellations c WHERE scan_id=stage.scan_id)
            IS DISTINCT FROM internal.initial_cancellation_receipt_image(stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    FOREACH side_name IN ARRAY ARRAY['source','destination'] LOOP
        SELECT * INTO retirement FROM jsonb_populate_record(NULL::internal.initial_cancellation_retirement_witness,
            (SELECT value FROM jsonb_array_elements(p_proof#>'{rows,internal.initial_cancellation_retirement_witness}') WHERE value->>'side'=side_name));
        IF retirement.scan_id IS DISTINCT FROM stage.scan_id OR retirement.phase IS DISTINCT FROM 'complete'
            OR retirement.observed IS DISTINCT FROM retirement.expected
            OR retirement.expected IS DISTINCT FROM internal.initial_cancellation_retirement_events(stage,side_name) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_initial_cancellation_retirement_images(stage.scan_id,side_name,retirement.expected,TRUE,stage.prestate);
    END LOOP;
    accounting:=internal.capture_initial_cancellation_accounting_images(stage);
    FOREACH side_name IN ARRAY ARRAY['submission','intent'] LOOP
        SELECT * INTO erasure FROM jsonb_populate_record(NULL::internal.initial_cancellation_erasure_witness,
            (SELECT value FROM jsonb_array_elements(p_proof#>'{rows,internal.initial_cancellation_erasure_witness}') WHERE value->>'root_name'=side_name));
        SELECT array_agg(i ORDER BY i) INTO indexes FROM generate_series(0,jsonb_array_length(erasure.expected)-1) i;
        IF erasure.scan_id IS DISTINCT FROM stage.scan_id OR erasure.phase IS DISTINCT FROM 'complete'
            OR (SELECT array_agg(i ORDER BY i) FROM unnest(erasure.observed) i) IS DISTINCT FROM indexes
            OR erasure.accounting_images IS DISTINCT FROM accounting THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
        END IF;
    END LOOP;
    SELECT * INTO receipt FROM jsonb_populate_record(NULL::internal.initial_cancellation_receipt_witness,
        p_proof#>'{rows,internal.initial_cancellation_receipt_witness,0}');
    IF receipt.scan_id IS DISTINCT FROM stage.scan_id OR receipt.phase IS DISTINCT FROM 'complete' OR receipt.observed IS DISTINCT FROM TRUE
        OR receipt.expected IS DISTINCT FROM internal.initial_cancellation_receipt_image(stage) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_cancellation_private_progress(stage,ARRAY['submission','intent']);
END; $function$
;
CREATE OR REPLACE FUNCTION internal.require_complete_initial_admitted_cancellation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE stage internal.initial_admitted_cancellation_staging;
BEGIN
    IF TG_TABLE_SCHEMA<>'internal' OR TG_TABLE_NAME<>'initial_admitted_cancellation_staging'
        OR TG_WHEN<>'AFTER' OR TG_LEVEL<>'ROW' OR TG_OP NOT IN ('INSERT','DELETE') THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    stage:=CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
    IF stage.transaction_id IS DISTINCT FROM pg_current_xact_id() OR NOT internal.initial_cancellation_sealed()
        OR (SELECT to_jsonb(c) FROM internal.initial_analysis_cancellations c WHERE scan_id=stage.scan_id)
            IS DISTINCT FROM internal.initial_cancellation_receipt_image(stage)
        OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=stage.scan_id)
            IS DISTINCT FROM internal.initial_cancellation_lifecycle_event(stage)->'new'
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=stage.scan_id) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    IF stage.variant='accounted_invocation' THEN
        PERFORM internal.assert_initial_cancellation_accounted_final(stage);
    ELSIF stage.variant IS DISTINCT FROM 'unused' THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_initial_cancellation_transients_absent(stage.scan_id);
    RETURN NULL;
END; $function$
;
CREATE TRIGGER z9_initial_cancellation_cleanup AFTER DELETE ON internal.initial_cancellation_invocation_witness
 FOR EACH ROW EXECUTE FUNCTION internal.advance_initial_cancellation_cleanup();
CREATE TRIGGER z99_initial_cancellation_cleanup_statement AFTER DELETE ON internal.initial_cancellation_invocation_witness
 REFERENCING OLD TABLE AS c1_old_rows FOR EACH STATEMENT EXECUTE FUNCTION internal.check_initial_cancellation_cleanup_statement();
REVOKE ALL ON FUNCTION internal.assert_initial_cancellation_terminal_shape(JSONB),
 internal.assert_initial_cancellation_accounted_final(internal.initial_admitted_cancellation_staging)
 FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION internal.assert_initial_invocation_retirement(p_old internal.identification_invocations)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE stage internal.initial_admitted_cancellation_staging; witness internal.initial_cancellation_invocation_witness;
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 PERFORM id FROM public.users WHERE id=p_old.user_id FOR UPDATE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_invocation_erasure_unavailable' USING ERRCODE='55000'; END IF;
 IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_old.scan_id::TEXT,0::BIGINT)) THEN
  RAISE EXCEPTION 'initial_analysis_erasure_busy' USING ERRCODE='55P03'; END IF;
 PERFORM scan_id FROM internal.initial_preparation_admission_receipts
  WHERE scan_id=p_old.scan_id AND owner_id=p_old.user_id AND admission_receipt_id=p_old.initial_admission_receipt_id
  FOR UPDATE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_invocation_erasure_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM id FROM internal.ai_quota_reservations WHERE id=p_old.reservation_id FOR UPDATE NOWAIT;
 IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_old.scan_id) THEN
  RAISE EXCEPTION 'initial_analysis_invocation_erasure_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO stage FROM internal.initial_admitted_cancellation_staging
  WHERE scan_id=p_old.scan_id AND transaction_id=pg_current_xact_id();
 IF FOUND THEN
  SELECT * INTO witness FROM internal.initial_cancellation_invocation_witness WHERE scan_id=stage.scan_id;
  IF NOT FOUND OR stage.variant IS DISTINCT FROM 'accounted_invocation'
   OR witness.phase IS DISTINCT FROM 'writing'
   OR witness.expected IS DISTINCT FROM internal.initial_cancellation_invocation_event(stage)
   OR witness.expected->'old' IS DISTINCT FROM to_jsonb(p_old)
   OR witness.event_image IS DISTINCT FROM stage.prestate->'event'
   OR (SELECT to_jsonb(r) FROM internal.initial_preparation_admission_receipts r WHERE scan_id=stage.scan_id)
    IS DISTINCT FROM stage.prestate#>'{private_components,receipt}'
   OR EXISTS(SELECT 1 FROM internal.initial_cancellation_quota_statements WHERE scan_id=stage.scan_id)
   OR EXISTS(SELECT 1 FROM internal.initial_cancellation_credit_witness WHERE scan_id=stage.scan_id) THEN
   RAISE EXCEPTION 'initial_analysis_invocation_erasure_unavailable' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_cancellation_accounted_images(stage,FALSE);
 ELSIF NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_old.scan_id) THEN
  RAISE EXCEPTION 'initial_analysis_invocation_erasure_unavailable' USING ERRCODE='55000';
 END IF;
END;
$body$;
-- Deferred execution uses the transaction caller, after the public definer has
-- returned. Only this private validator retains trusted read authority.
CREATE OR REPLACE FUNCTION internal.require_initial_invocation_erasure()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $body$
BEGIN
 IF NOT internal.initial_invocation_retirement_transition(OLD,NEW)
   OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=OLD.scan_id)
   OR EXISTS(SELECT 1 FROM internal.identification_invocations i WHERE id=OLD.id AND NOT internal.initial_invocation_retired(i))
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=OLD.scan_id)
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id=OLD.scan_id)
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=OLD.scan_id)
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=OLD.scan_id)
   OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=OLD.scan_id OR admission_receipt_id=OLD.initial_admission_receipt_id)
   OR EXISTS(SELECT 1 FROM internal.initial_preparation_execution_grants WHERE scan_id=OLD.scan_id) THEN
  RAISE EXCEPTION 'initial_analysis_invocation_erasure_incomplete' USING ERRCODE='55000'; END IF;
 IF NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.scan_id) THEN
  -- The immediate exact writing witness and mandatory captured stage/terminal
  -- proofs supply provenance. A seal or saved receipt alone is not authority.
  IF NOT internal.initial_cancellation_sealed()
   OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=OLD.id) IS DISTINCT FROM to_jsonb(NEW)
   OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations c
    JOIN internal.initial_analysis_lifecycle_fences f USING(scan_id)
    WHERE c.scan_id=OLD.scan_id AND c.owner_id=OLD.user_id
     AND f.state IN ('cancelled_unknown','cancelled_dispatched')
     AND c.dispatch=internal.initial_cancellation_dispatch(f.state)) THEN
   RAISE EXCEPTION 'initial_analysis_invocation_erasure_incomplete' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_cancellation_transients_absent(OLD.scan_id);
 END IF;
 RETURN NULL;
END;
$body$;
CREATE OR REPLACE FUNCTION internal.cancel_initial_analysis_explicit(p_owner uuid, p_scan uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
DECLARE owned_by UUID; scan_exists BOOLEAN; submission internal.initial_analysis_submissions;
 saved internal.initial_analysis_cancellations; lifecycle TEXT;
 q internal.ai_quota_reservations; settlement JSONB; stage internal.initial_admitted_cancellation_staging; terminal_state TEXT; affected INTEGER;
BEGIN
 PERFORM internal.require_service_role();
 IF p_owner IS NULL OR p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||p_scan::TEXT,0::BIGINT));
 SELECT user_id INTO owned_by FROM public.scans WHERE id=p_scan FOR UPDATE; scan_exists:=FOUND;
 IF scan_exists AND owned_by IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_scan FOR UPDATE;
 SELECT state INTO lifecycle FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan FOR UPDATE;
 IF internal.initial_admitted_settlement_blocked(p_scan) THEN
  PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 END IF;
 SELECT * INTO submission FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND submission.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND saved.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan) THEN RAISE EXCEPTION 'initial_analysis_deleted' USING ERRCODE='55000'; END IF;
 IF scan_exists OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_already_complete' USING ERRCODE='55000'; END IF;
 -- Saved terminal classification precedes any fresh proof inspection; erased
 -- evidence cannot upgrade unknown/dispatched into a prevented/refunded result.
 IF saved.scan_id IS NOT NULL OR (lifecycle IS DISTINCT FROM 'pending_pre_dispatch' AND lifecycle IS DISTINCT FROM 'dispatch_authorized')
  OR NOT internal.initial_admitted_settlement_blocked(p_scan) THEN
  RETURN internal.cancel_initial_analysis(p_owner,p_scan);
 END IF;
 -- Any admitted footprint, including paired permanent fences after damage or
 -- erasure, requires the complete positive proof. Invalid proof fails closed;
 -- no caught preflight/stage error may enter the generic erasure owner.
 stage:=internal.begin_initial_cancellation_stage(p_owner,p_scan);
 IF stage.variant='unused' THEN
 SELECT (jsonb_populate_record(NULL::internal.ai_quota_reservations,prestate->'quota')).* INTO STRICT q
  FROM internal.initial_admitted_cancellation_staging WHERE scan_id=p_scan;
 IF NOT internal.finalize_ai_quota_reservation_core(q.id,p_owner,q.lease_token,'refunded') THEN
  RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000'; END IF;
 settlement:=internal.settle_complimentary_analysis(p_owner,p_scan,'cancelled_before_dispatch');
 IF (settlement->>'credit_released')::BOOLEAN IS DISTINCT FROM (q.complimentary_client_scan_id IS NOT NULL)
  OR (settlement->>'credit_consumed')::BOOLEAN IS DISTINCT FROM FALSE THEN
  RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000'; END IF;
 ELSE
  INSERT INTO internal.initial_cancellation_invocation_witness(scan_id) VALUES(p_scan);
  UPDATE internal.identification_invocations SET user_id=NULL,scan_id=NULL,reservation_id=NULL,
   lease_sha256=NULL,initial_admission_receipt_id=NULL WHERE id=(stage.prestate#>>'{invocation,id}')::UUID;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected<>1 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 END IF;
 terminal_state:=internal.initial_cancellation_lifecycle_event(stage)#>>'{new,state}';
 PERFORM internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,terminal_state,'begin');
 UPDATE internal.initial_analysis_lifecycle_fences SET state=terminal_state WHERE scan_id=p_scan;
 PERFORM internal.advance_initial_cancellation_lifecycle(p_owner,p_scan,terminal_state,'end');
 PERFORM internal.retire_initial_preparation_source_objects(p_scan);
 PERFORM internal.retire_initial_media_objects(p_scan);
 PERFORM internal.erase_initial_cancellation_private_root(p_scan,'submission');
 PERFORM internal.erase_initial_cancellation_private_root(p_scan,'intent');
 PERFORM internal.write_initial_cancellation_receipt(p_scan);
 INSERT INTO internal.initial_cancellation_terminal_snapshot(scan_id) VALUES(p_scan);
 PERFORM internal.finish_initial_cancellation_consumption(p_scan);
 SELECT * INTO STRICT saved FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan AND owner_id=p_owner;
 RETURN jsonb_build_object('version',1,'outcome','cancelled','dispatch',saved.dispatch);
END; $function$;

-- Full candidate-row derivation shared by the existing accounting writer and
-- its future consuming witness. This is VOLATILE, not pure: pricing is resolved
-- once and server defaults are generated once. Callers must reuse this row,
-- never rederive a second image. No invocation/owner/receipt lookup or write.
CREATE FUNCTION internal.prepare_identification_usage_event(
 p_invocation internal.identification_invocations,p_outcome TEXT,p_usage JSONB)
RETURNS public.ai_usage_events LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $body$
DECLARE
    invocation internal.identification_invocations:=p_invocation;
    input_count BIGINT; cached BIGINT; writes BIGINT; output_count BIGINT;
    candidates BIGINT; thinking BIGINT; tools BIGINT; total BIGINT;
    cost BIGINT; price_version TEXT; modality TEXT; metadata JSONB;
    breakdown JSONB := '{}'::JSONB; category TEXT; unit TEXT; units JSONB; value BIGINT;
BEGIN
    IF p_outcome IS NULL OR p_outcome NOT IN ('draft', 'refusal', 'invalid_output', 'operational_failure', 'unknown_execution')
        OR jsonb_typeof(p_usage) IS DISTINCT FROM 'object' OR octet_length(p_usage::TEXT) > 2048
        OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_usage) k WHERE k NOT IN (
            'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens',
            'candidate_tokens', 'thinking_tokens', 'tool_tokens', 'total_tokens', 'service_tier', 'modality_breakdown')) THEN
        RAISE EXCEPTION 'identification_usage_invalid' USING ERRCODE = '22023';
    END IF;
    IF invocation.provider = 'gemini' THEN
        FOREACH category IN ARRAY ARRAY['prompt','cached','candidates','tool'] LOOP
            units := '{}'::JSONB;
            FOREACH unit IN ARRAY ARRAY['text','image','audio','video'] LOOP
                value := internal.identification_usage_count(p_usage -> 'modality_breakdown' -> category, unit);
                IF value IS NOT NULL THEN units := units || jsonb_build_object(unit, value); END IF;
            END LOOP;
            breakdown := breakdown || jsonb_build_object(category, units);
        END LOOP;
    END IF;
    input_count := internal.identification_usage_count(p_usage, 'input_tokens');
    cached := internal.identification_usage_count(p_usage, 'cached_tokens');
    writes := internal.identification_usage_count(p_usage, 'cache_write_tokens');
    output_count := internal.identification_usage_count(p_usage, 'output_tokens');
    candidates := internal.identification_usage_count(p_usage, 'candidate_tokens');
    thinking := internal.identification_usage_count(p_usage, 'thinking_tokens');
    tools := internal.identification_usage_count(p_usage, 'tool_tokens');
    total := internal.identification_usage_count(p_usage, 'total_tokens');
    modality := CASE invocation.input_profile
        WHEN 'multimodal_text_v1' THEN 'text'
        WHEN 'multimodal_photo_v1' THEN 'image'
        WHEN 'multimodal_audio_v1' THEN 'audio'
        WHEN 'multimodal_video_frames_v1' THEN 'video'
        ELSE 'mixed' END;
    metadata := jsonb_build_object('writer', 'identification_invocation', 'ai_provider', invocation.provider,
        'ai_binding', invocation.binding, 'ai_policy_version', invocation.policy_version,
        'ai_input_profile', invocation.input_profile, 'ai_attribution', 'attempt_snapshot', 'ai_outcome', p_outcome,
        'ai_prompt', invocation.provenance ->> 'prompt', 'ai_schema', invocation.provenance ->> 'schema',
        'ai_provenance', invocation.provenance,
        'ai_usage_contract', CASE invocation.provider WHEN 'openai' THEN 'openai_responses_tokens_v1'
            WHEN 'gemini' THEN 'gemini_token_counts_v1' END);
    IF invocation.provider = 'openai' THEN
        metadata := metadata || jsonb_build_object('ai_output_tokens', output_count, 'ai_cache_write_tokens', writes,
            'ai_service_tier', CASE WHEN p_usage ->> 'service_tier' = 'default' THEN 'default' ELSE NULL END);
        IF invocation.model = 'gpt-6-sol' AND invocation.binding = 'openai_photo_v1'
            AND modality = 'image' AND invocation.native_price IS NOT NULL
            AND p_usage ->> 'service_tier' = 'default'
            AND input_count IS NOT NULL AND cached IS NOT NULL AND writes IS NOT NULL AND output_count IS NOT NULL
            AND cached + writes <= input_count
            AND input_count <= (invocation.native_price ->> 'max_input_tokens')::BIGINT
            AND tools = 0 AND (thinking IS NULL OR thinking <= output_count)
            AND (total IS NULL OR total = input_count + output_count)
            AND (candidates IS NULL OR thinking IS NULL OR candidates + thinking = output_count) THEN
            cost := round((input_count - cached - writes) * (invocation.native_price ->> 'input_usd_per_million')::NUMERIC
                + cached * (invocation.native_price ->> 'cached_usd_per_million')::NUMERIC
                + writes * (invocation.native_price ->> 'cache_write_usd_per_million')::NUMERIC
                + output_count * (invocation.native_price ->> 'output_usd_per_million')::NUMERIC)::BIGINT;
            price_version := invocation.native_price ->> 'version';
        END IF;
    ELSIF invocation.provider = 'gemini' AND input_count IS NOT NULL AND candidates IS NOT NULL
        AND (cached IS NULL OR cached <= input_count) THEN
        SELECT pricing.cost_microusd, pricing.pricing_version INTO cost, price_version
        FROM internal.estimate_ai_cost_microusd(invocation.model, modality, invocation.occurred_at,
            input_count, cached, candidates, thinking, tools) pricing;
    END IF;
    RETURN ROW(gen_random_uuid(), invocation.occurred_at, invocation.user_id, 'scan_identification',
        invocation.model, invocation.effective_plan, modality,
        input_count, cached, candidates, thinking, tools, total, breakdown,
        CASE p_outcome WHEN 'draft' THEN 'success' WHEN 'refusal' THEN 'refusal'
            WHEN 'unknown_execution' THEN 'unknown' ELSE 'error' END,
        invocation.scan_id, NULL::UUID, NULL::UUID, 'identification_invocation', invocation.id,
        FALSE, 'complete', cost, price_version, metadata, now())::public.ai_usage_events;
END;
$body$;
REVOKE ALL ON FUNCTION internal.prepare_identification_usage_event(internal.identification_invocations,TEXT,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.attach_initial_report_candidate(p_invocation internal.identification_invocations,p_candidate public.ai_usage_events)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE stage internal.initial_consuming_staging;
BEGIN
 SELECT * INTO stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND THEN RETURN; END IF;
 IF stage.operation<>'report' OR stage.invocation_id IS DISTINCT FROM p_invocation.id
   OR stage.report_invocation IS DISTINCT FROM to_jsonb(p_invocation) OR stage.expected_writes<>'[]'::JSONB THEN
  RAISE EXCEPTION 'initial_analysis_report_attachment_invalid' USING ERRCODE='55000'; END IF;
 UPDATE internal.initial_consuming_staging SET expected_writes=internal.initial_report_expected_writes(to_jsonb(p_invocation),to_jsonb(p_candidate))
  WHERE transaction_id=stage.transaction_id;
END;
$body$;
REVOKE ALL ON FUNCTION internal.attach_initial_report_candidate(internal.identification_invocations,public.ai_usage_events)
 FROM PUBLIC,anon,authenticated,service_role;

-- Preserve row-first accounting, zero-write replay and the existing conflict
-- winner. Report-stage admission remains denied until exact witness integration.
CREATE OR REPLACE FUNCTION internal.complete_identification_usage(p_invocation_id UUID,p_outcome TEXT,p_usage JSONB)
RETURNS UUID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $body$
DECLARE invocation internal.identification_invocations;
 event_candidate public.ai_usage_events; event_uuid UUID;
BEGIN
 SELECT * INTO invocation FROM internal.identification_invocations WHERE id=p_invocation_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'identification_invocation_not_found' USING ERRCODE='P0001'; END IF;
 IF invocation.event_id IS NOT NULL THEN RETURN invocation.event_id; END IF;
 event_candidate:=internal.prepare_identification_usage_event(invocation,p_outcome,p_usage);
 PERFORM internal.attach_initial_report_candidate(invocation,event_candidate);
 INSERT INTO public.ai_usage_events SELECT (event_candidate).*
 ON CONFLICT (source_type,source_id,operation) DO NOTHING RETURNING id INTO event_uuid;
 IF event_uuid IS NULL THEN
  SELECT id INTO STRICT event_uuid FROM public.ai_usage_events
   WHERE source_type='identification_invocation' AND source_id=invocation.id AND operation='scan_identification';
 END IF;
 UPDATE internal.identification_invocations SET event_id=event_uuid WHERE id=invocation.id;
 RETURN event_uuid;
END;
$body$;


-- Report observers only restrict the new private report stage. Other accounting
-- paths return immediately; dispatch/result still have no installed adapters.
CREATE TRIGGER s0_report_statement_before BEFORE INSERT ON public.ai_usage_events
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('report');
CREATE TRIGGER s0_report_statement_after AFTER INSERT ON public.ai_usage_events
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('report');
CREATE TRIGGER s0_report_row_before BEFORE INSERT ON public.ai_usage_events
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('report');
CREATE TRIGGER s0_report_row_after AFTER INSERT ON public.ai_usage_events
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('report');
CREATE TRIGGER s0_report_statement_before BEFORE UPDATE ON internal.identification_invocations
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('report');
CREATE TRIGGER s0_report_statement_after AFTER UPDATE ON internal.identification_invocations
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('report');
CREATE TRIGGER s0_report_row_before BEFORE UPDATE ON internal.identification_invocations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('report');
CREATE TRIGGER s0_report_row_after AFTER UPDATE ON internal.identification_invocations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('report');

-- Fixed original-authority producer. No public RPC or API execution grant is
-- installed. This cannot create an invocation, dispatch or settle funding.
-- Shared original authority for post-dispatch effects. Both callers acquire
-- this outer scope before invocation/event/result rows; ordinary accounting
-- continues to own only its existing row-first lock order.
CREATE FUNCTION internal.lock_initial_dispatched_original(p_owner UUID,p_scan UUID,p_submission_digest TEXT,
 p_invocation UUID,p_lease_token UUID,p_operation TEXT)
RETURNS TABLE(receipt_row internal.initial_preparation_admission_receipts,
 admission_row internal.initial_analysis_admissions,invocation_row internal.identification_invocations)
LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE receipt internal.initial_preparation_admission_receipts;
 admitted internal.initial_analysis_admissions; original internal.identification_invocations; n INTEGER:=0;
BEGIN
 IF p_operation NOT IN ('report','result','read') OR p_operation IS NULL THEN
  RAISE EXCEPTION 'initial_analysis_consuming_operation_unavailable' USING ERRCODE='22023'; END IF;
 PERFORM internal.require_service_role();
 IF p_owner IS NULL OR p_scan IS NULL OR (p_operation<>'read' AND (p_invocation IS NULL OR p_lease_token IS NULL))
  OR p_submission_digest IS NULL OR p_submission_digest !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION USING MESSAGE='initial_analysis_'||p_operation||'_invalid', ERRCODE='22023'; END IF;
 IF internal.initial_admission_sealed() OR internal.initial_cancellation_sealed()
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE transaction_id=pg_current_xact_id())
  OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id())
  OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id()) THEN
  RAISE EXCEPTION USING MESSAGE='initial_analysis_'||p_operation||'_unavailable', ERRCODE='55000'; END IF;
 -- Preserve owner -> scan/advisory -> lifecycle -> retained roots -> invocation
 -- -> event order. No outer lookups or locks are added to ordinary accounting.
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
 SELECT * INTO admitted FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR admitted.owner_id IS DISTINCT FROM p_owner OR admitted.binding_version IS NULL OR admitted.binding_version NOT IN (3,4)
  OR (SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan) IS DISTINCT FROM 'dispatch_authorized' THEN
  RAISE EXCEPTION USING MESSAGE='initial_analysis_'||p_operation||'_unavailable', ERRCODE='55000'; END IF;
 SELECT * INTO receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING MESSAGE='initial_analysis_'||p_operation||'_unavailable', ERRCODE='55000'; END IF;
 receipt:=internal.initial_admission_retained_receipt(p_owner,p_scan,receipt.admission_receipt_id);
 IF receipt.manifest::JSONB#>>'{proof,input,digest}' IS DISTINCT FROM p_submission_digest
  OR admitted.funding_binding_id::TEXT IS DISTINCT FROM receipt.funding::JSONB#>>'{original,reservation_id}' THEN
  RAISE EXCEPTION USING MESSAGE='initial_analysis_'||p_operation||'_conflict', ERRCODE='55000'; END IF;
 -- Include aliases in the locked set; no row may hide behind classification.
 FOR original IN SELECT * FROM internal.identification_invocations
  WHERE scan_id=p_scan OR reservation_id=admitted.funding_binding_id ORDER BY id FOR UPDATE LOOP
  n:=n+1;
  IF n<>1 OR (p_operation<>'read' AND original.id IS DISTINCT FROM p_invocation) OR NOT original.is_initial_analysis
   OR original.user_id IS DISTINCT FROM p_owner OR original.scan_id IS DISTINCT FROM p_scan
   OR original.reservation_id IS DISTINCT FROM admitted.funding_binding_id OR original.attempt_count IS DISTINCT FROM 1
   OR original.initial_admission_receipt_id IS DISTINCT FROM receipt.admission_receipt_id
   OR (p_operation<>'read' AND original.lease_sha256 IS DISTINCT FROM encode(extensions.digest(convert_to(p_lease_token::TEXT,'UTF8'),'sha256'),'hex'))
   OR original.lease_sha256 IS DISTINCT FROM encode(extensions.digest(convert_to(receipt.accounting::JSONB#>>'{reservation,lease_token}','UTF8'),'sha256'),'hex')
   OR original.provider IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,provider}'
   OR original.binding IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,binding}'
   OR original.input_profile IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,input_profile}'
   OR original.effective_plan IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,effective_plan}'
   OR original.policy_version::TEXT IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,policy_version}'
   OR original.model IS DISTINCT FROM COALESCE(receipt.accounting::JSONB#>>'{attempt,provider_model}',receipt.accounting::JSONB#>>'{attempt,model}') THEN
   RAISE EXCEPTION USING MESSAGE='initial_analysis_'||p_operation||'_conflict', ERRCODE='55000'; END IF;
 END LOOP;
 IF n<>1 THEN RAISE EXCEPTION USING MESSAGE='initial_analysis_'||p_operation||'_conflict', ERRCODE='55000'; END IF;
 RETURN QUERY SELECT receipt,admitted,original;
END;
$body$;
REVOKE ALL ON FUNCTION internal.lock_initial_dispatched_original(UUID,UUID,TEXT,UUID,UUID,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.report_initial_analysis_usage(p_owner UUID,p_scan UUID,p_submission_digest TEXT,
 p_invocation UUID,p_lease_token UUID,p_outcome TEXT,p_usage TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE receipt internal.initial_preparation_admission_receipts;
 admitted internal.initial_analysis_admissions; original internal.identification_invocations;
 usage_value JSONB; event_uuid UUID; event_row public.ai_usage_events; context RECORD;
BEGIN
 SELECT * INTO STRICT context
 FROM internal.lock_initial_dispatched_original(p_owner,p_scan,p_submission_digest,p_invocation,p_lease_token,'report');
 receipt:=context.receipt_row;admitted:=context.admission_row;original:=context.invocation_row;
 IF original.event_id IS NULL THEN
  IF p_usage IS NULL OR octet_length(p_usage)>2048 THEN
   RAISE EXCEPTION 'identification_usage_invalid' USING ERRCODE='22023'; END IF;
  BEGIN usage_value:=p_usage::JSONB;
  EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'identification_usage_invalid' USING ERRCODE='22023'; END;
  IF internal.initial_canonical(usage_value) IS DISTINCT FROM p_usage THEN
   RAISE EXCEPTION 'identification_usage_invalid' USING ERRCODE='22023'; END IF;
  INSERT INTO internal.initial_consuming_staging(transaction_id,scan_id,owner_id,operation,admission_receipt_id,
   admission_receipt_digest,reservation_id,invocation_id,expected_writes,report_invocation)
   VALUES(pg_current_xact_id(),p_scan,p_owner,'report',receipt.admission_receipt_id,receipt.receipt_digest,
    original.reservation_id,original.id,'[]',to_jsonb(original));
  event_uuid:=internal.complete_identification_usage(original.id,p_outcome,usage_value);
  DELETE FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 ELSE
  -- Authenticated exact-original replay ignores new usage, including malformed
  -- text, and creates no witness or new accounting image.
  event_uuid:=internal.complete_identification_usage(original.id,NULL,NULL);
 END IF;
 SELECT * INTO event_row FROM public.ai_usage_events WHERE id=event_uuid FOR UPDATE;
 IF NOT FOUND OR NOT internal.identification_usage_matches_invocation(original,event_row)
  OR (SELECT event_id FROM internal.identification_invocations WHERE id=original.id) IS DISTINCT FROM event_row.id THEN
  RAISE EXCEPTION 'initial_analysis_report_conflict' USING ERRCODE='55000'; END IF;
 RETURN jsonb_build_object('version',1,'owner_id',p_owner,'scan_id',p_scan,
  'submission_digest',p_submission_digest,'invocation_id',original.id,'event_id',event_uuid);
END;
$body$;
REVOKE ALL ON FUNCTION internal.report_initial_analysis_usage(UUID,UUID,TEXT,UUID,UUID,TEXT,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

-- Decode only frozen fractional-number nodes for original-provenance equality.
-- Schema validation happens first; this is exact NUMERIC/JSONB conversion, not
-- an IEEE round-trip validator and not permission to convert numeric strings.
CREATE FUNCTION internal.decode_initial_result_numbers_v1(p_value JSONB,p_rule JSONB)
RETURNS JSONB LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE answer JSONB; member RECORD;
BEGIN
 IF p_value='null'::JSONB THEN RETURN p_value; END IF;
 CASE p_rule->>'kind'
 WHEN 'number' THEN RETURN to_jsonb((p_value#>>'{}')::NUMERIC);
 WHEN 'union' THEN RETURN internal.decode_initial_result_numbers_v1(p_value,p_rule->'variants'->(p_value->> (p_rule->>'discriminator')));
 WHEN 'object' THEN
  answer:='{}';
  FOR member IN SELECT * FROM jsonb_each(p_value) LOOP
   answer:=answer||jsonb_build_object(member.key,internal.decode_initial_result_numbers_v1(member.value,p_rule->'fields'->member.key->'contract'));
  END LOOP;
  RETURN answer;
 WHEN 'array' THEN
  SELECT COALESCE(jsonb_agg(internal.decode_initial_result_numbers_v1(value,p_rule->'items') ORDER BY ordinality),'[]') INTO answer
   FROM jsonb_array_elements(p_value) WITH ORDINALITY;
  RETURN answer;
 ELSE RETURN p_value;
 END CASE;
END;
$body$;

-- No locks are acquired here. The fixed producer already owns the shared outer
-- scope and original invocation. The entry guard validates the complete candidate;
-- the terminal check repeats original identity and retained-proof checks without
-- reparsing the immutable candidate or acquiring locks after the result row.
CREATE FUNCTION internal.assert_initial_result_origin(p_stage internal.initial_consuming_staging,p_validate_content BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE row_image JSONB:=p_stage.expected_writes#>'{0,0,new}'; result JSONB:=row_image->'result_snapshot';
 provenance JSONB:=row_image->'provenance_snapshot'; receipt internal.initial_preparation_admission_receipts;
 admitted internal.initial_analysis_admissions; original internal.identification_invocations;
BEGIN
 IF p_stage.operation IS DISTINCT FROM 'result' OR p_stage.result_invocation IS NULL THEN
  RAISE EXCEPTION 'initial_analysis_result_origin_invalid' USING ERRCODE='55000'; END IF;
 SELECT * INTO original FROM internal.identification_invocations WHERE id=p_stage.invocation_id;
 IF NOT FOUND OR to_jsonb(original) IS DISTINCT FROM p_stage.result_invocation
  OR original.user_id IS DISTINCT FROM p_stage.owner_id OR original.scan_id IS DISTINCT FROM p_stage.scan_id
  OR original.initial_admission_receipt_id IS DISTINCT FROM p_stage.admission_receipt_id
  OR original.reservation_id IS DISTINCT FROM p_stage.reservation_id OR NOT original.is_initial_analysis
  OR original.attempt_count IS DISTINCT FROM 1
  OR (SELECT count(*) FROM internal.identification_invocations WHERE scan_id=p_stage.scan_id OR reservation_id=p_stage.reservation_id)<>1
  OR (SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_stage.scan_id) IS DISTINCT FROM 'dispatch_authorized'
  OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_stage.owner_id)
  OR EXISTS(SELECT 1 FROM public.scans WHERE id=p_stage.scan_id AND (user_id IS DISTINCT FROM p_stage.owner_id OR is_tombstoned))
  OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_stage.owner_id AND status IN ('pending','storage_pending','auth_pending'))
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=p_stage.scan_id) THEN
  RAISE EXCEPTION 'initial_analysis_result_origin_invalid' USING ERRCODE='55000'; END IF;
 receipt:=internal.initial_admission_retained_receipt(p_stage.owner_id,p_stage.scan_id,p_stage.admission_receipt_id);
 SELECT * INTO STRICT admitted FROM internal.initial_analysis_admissions WHERE scan_id=p_stage.scan_id;
 IF receipt.receipt_digest IS DISTINCT FROM p_stage.admission_receipt_digest
  OR admitted.funding_binding_id IS DISTINCT FROM p_stage.reservation_id
  OR row_image->>'scan_id' IS DISTINCT FROM p_stage.scan_id::TEXT
  OR row_image->>'owner_id' IS DISTINCT FROM p_stage.owner_id::TEXT
  OR row_image->>'result_evidence_id' IS DISTINCT FROM p_stage.result_evidence_id::TEXT
  OR row_image->'result_schema_version' IS DISTINCT FROM '1'::JSONB
  OR result->>'scan_id' IS DISTINCT FROM p_stage.scan_id::TEXT
  OR result->>'invocation_id' IS DISTINCT FROM original.id::TEXT
  OR result->>'submission_digest' IS DISTINCT FROM admitted.submission_digest
  OR result->>'config_digest' IS DISTINCT FROM admitted.configuration_digest
  OR result->>'funding_binding_digest' IS DISTINCT FROM admitted.funding_digest THEN
  RAISE EXCEPTION 'initial_analysis_result_conflict' USING ERRCODE='55000'; END IF;
 IF p_validate_content THEN
  PERFORM internal.parse_initial_result_evidence_v1(internal.initial_canonical(result),internal.initial_canonical(provenance),
   encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(result),'UTF8'),'sha256'),'hex'),
   encode(extensions.digest(convert_to('merian.initial-analysis.result-provenance.v1'||chr(10)||internal.initial_canonical(provenance),'UTF8'),'sha256'),'hex'));
  IF internal.decode_initial_result_numbers_v1(provenance,internal.initial_result_schema_v1()->'provenance') IS DISTINCT FROM original.provenance THEN
   RAISE EXCEPTION 'initial_analysis_result_conflict' USING ERRCODE='55000'; END IF;
 END IF;
END;
$body$;

CREATE FUNCTION internal.assert_initial_result_terminal(p_stage internal.initial_consuming_staging)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
BEGIN
 IF p_stage.operation<>'result' THEN RETURN; END IF;
 IF NOT p_stage.sealed OR p_stage.next_statement<>1 OR p_stage.statement_active
  OR p_stage.pending_rows<>'{}'::INTEGER[] OR p_stage.observed_rows<>'{}'::INTEGER[]
  OR (SELECT to_jsonb(r) FROM internal.initial_analysis_results r WHERE scan_id=p_stage.scan_id)
    IS DISTINCT FROM p_stage.expected_writes#>'{0,0,new}' THEN
  RAISE EXCEPTION 'initial_analysis_result_incomplete' USING ERRCODE='55000'; END IF;
 -- Unbound stages exercise mechanics only; both business guards require the
 -- original snapshot. They can never authorize an actual production INSERT.
 IF p_stage.result_invocation IS NOT NULL THEN PERFORM internal.assert_initial_result_origin(p_stage,FALSE); END IF;
END;
$body$;

CREATE FUNCTION internal.initial_result_expected_insert(p_row JSONB)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY INVOKER SET search_path='' AS $body$
 SELECT EXISTS(SELECT 1 FROM internal.initial_consuming_staging s
  WHERE s.transaction_id=pg_current_xact_id() AND s.operation='result' AND s.result_invocation IS NOT NULL
   AND s.statement_active AND NOT s.sealed AND s.next_statement=0
   AND s.pending_rows='{}'::INTEGER[] AND s.observed_rows='{}'::INTEGER[]
   AND s.expected_writes=jsonb_build_array(jsonb_build_array(jsonb_build_object('old',NULL,'new',p_row))))
$body$;

CREATE FUNCTION internal.record_initial_analysis_result(p_owner UUID,p_scan UUID,p_submission_digest TEXT,
 p_invocation UUID,p_lease_token UUID,p_result_evidence UUID,p_result TEXT,p_provenance TEXT,p_result_digest TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE receipt internal.initial_preparation_admission_receipts; admitted internal.initial_analysis_admissions;
 original internal.identification_invocations; candidate internal.initial_analysis_results; existing internal.initial_analysis_results;
 stage internal.initial_consuming_staging; reference JSONB; provenance_digest TEXT; outcome TEXT:='recorded'; context RECORD;
BEGIN
 SELECT * INTO STRICT context
 FROM internal.lock_initial_dispatched_original(p_owner,p_scan,p_submission_digest,p_invocation,p_lease_token,'result');
 receipt:=context.receipt_row;admitted:=context.admission_row;original:=context.invocation_row;
 IF p_result_evidence IS NULL OR p_result IS NULL OR p_provenance IS NULL OR p_result_digest IS NULL
  OR octet_length(p_result)>1048576 OR octet_length(p_provenance)>65536
  OR p_result_digest !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_analysis_result_invalid' USING ERRCODE='22023'; END IF;
 candidate.scan_id:=p_scan; candidate.owner_id:=p_owner; candidate.result_evidence_id:=p_result_evidence;
 candidate.result_schema_version:=1;
 BEGIN candidate.result_snapshot:=p_result::JSONB; candidate.provenance_snapshot:=p_provenance::JSONB;
 EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'initial_analysis_result_invalid' USING ERRCODE='22023'; END;
 IF internal.initial_canonical(candidate.result_snapshot) IS DISTINCT FROM p_result
  OR internal.initial_canonical(candidate.provenance_snapshot) IS DISTINCT FROM p_provenance
  OR p_result_digest IS DISTINCT FROM encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||p_result,'UTF8'),'sha256'),'hex') THEN
  RAISE EXCEPTION 'initial_analysis_result_invalid' USING ERRCODE='22023'; END IF;
 provenance_digest:=encode(extensions.digest(convert_to('merian.initial-analysis.result-provenance.v1'||chr(10)||p_provenance,'UTF8'),'sha256'),'hex');
 stage.transaction_id:=pg_current_xact_id();stage.owner_id:=p_owner;stage.scan_id:=p_scan;stage.operation:='result';
 stage.admission_receipt_id:=receipt.admission_receipt_id;stage.admission_receipt_digest:=receipt.receipt_digest;
 stage.reservation_id:=original.reservation_id;stage.invocation_id:=original.id;stage.result_evidence_id:=p_result_evidence;
 stage.result_invocation:=to_jsonb(original);
 stage.expected_writes:=jsonb_build_array(jsonb_build_array(jsonb_build_object('old',NULL,'new',to_jsonb(candidate))));
 SELECT * INTO existing FROM internal.initial_analysis_results WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND THEN
  IF existing IS DISTINCT FROM candidate THEN RAISE EXCEPTION 'initial_analysis_result_conflict' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_result_origin(stage,TRUE);
  outcome:='replay';
 ELSE
  INSERT INTO internal.initial_consuming_staging(transaction_id,scan_id,owner_id,operation,admission_receipt_id,
   admission_receipt_digest,reservation_id,invocation_id,result_evidence_id,expected_writes,result_invocation)
  VALUES(stage.transaction_id,stage.scan_id,stage.owner_id,stage.operation,stage.admission_receipt_id,
   stage.admission_receipt_digest,stage.reservation_id,stage.invocation_id,stage.result_evidence_id,stage.expected_writes,stage.result_invocation);
  INSERT INTO internal.initial_analysis_results SELECT (candidate).*;
  DELETE FROM internal.initial_consuming_staging WHERE transaction_id=stage.transaction_id;
 END IF;
 reference:=jsonb_build_object('owner_id',p_owner,'scan_id',p_scan,'invocation_id',original.id,
  'result_evidence_id',p_result_evidence,'submission_digest',admitted.submission_digest,
  'config_digest',admitted.configuration_digest,'funding_binding_digest',admitted.funding_digest);
 RETURN jsonb_build_object('version',1,'outcome',outcome,'reference',reference,'result_digest',p_result_digest,'provenance_digest',provenance_digest);
END;
$body$;
REVOKE ALL ON FUNCTION internal.decode_initial_result_numbers_v1(JSONB,JSONB),
 internal.assert_initial_result_origin(internal.initial_consuming_staging,BOOLEAN),
 internal.assert_initial_result_terminal(internal.initial_consuming_staging),internal.initial_result_expected_insert(JSONB),
 internal.record_initial_analysis_result(UUID,UUID,TEXT,UUID,UUID,UUID,TEXT,TEXT,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

-- Read-only recovery has no lease and never creates result, accounting or
-- dispatch authority. Original membership still comes from retained proof.
CREATE FUNCTION internal.read_initial_analysis_result(p_owner UUID,p_scan UUID,p_submission_digest TEXT,
 p_result_evidence UUID,p_result_digest TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE context RECORD; admitted internal.initial_analysis_admissions; original internal.identification_invocations;
 receipt internal.initial_preparation_admission_receipts; saved internal.initial_analysis_results;
 reference JSONB; evidence JSONB; result_text TEXT; provenance_text TEXT; actual_digest TEXT; provenance_digest TEXT;
 stage internal.initial_consuming_staging;
BEGIN
 SELECT * INTO STRICT context FROM internal.lock_initial_dispatched_original(p_owner,p_scan,p_submission_digest,NULL,NULL,'read');
 admitted:=context.admission_row;original:=context.invocation_row;receipt:=context.receipt_row;
 IF p_result_evidence IS NULL OR p_result_digest IS NULL OR p_result_digest !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_analysis_result_invalid' USING ERRCODE='22023'; END IF;
 reference:=jsonb_build_object('owner_id',p_owner,'scan_id',p_scan,'invocation_id',original.id,
  'result_evidence_id',p_result_evidence,'submission_digest',admitted.submission_digest,
  'config_digest',admitted.configuration_digest,'funding_binding_digest',admitted.funding_digest);
 SELECT * INTO saved FROM internal.initial_analysis_results WHERE scan_id=p_scan FOR SHARE;
 IF NOT FOUND THEN
  RETURN jsonb_build_object('version',1,'outcome','absent','reference',reference,'result_digest',p_result_digest,'evidence',NULL);
 END IF;
 result_text:=internal.initial_canonical(saved.result_snapshot);provenance_text:=internal.initial_canonical(saved.provenance_snapshot);
 actual_digest:=encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||result_text,'UTF8'),'sha256'),'hex');
 provenance_digest:=encode(extensions.digest(convert_to('merian.initial-analysis.result-provenance.v1'||chr(10)||provenance_text,'UTF8'),'sha256'),'hex');
 IF saved.owner_id IS DISTINCT FROM p_owner OR saved.result_evidence_id IS DISTINCT FROM p_result_evidence
  OR actual_digest IS DISTINCT FROM p_result_digest THEN
  RAISE EXCEPTION 'initial_analysis_result_conflict' USING ERRCODE='55000'; END IF;
 -- Validate recovered content against the same frozen original contract without
 -- inserting a witness or requiring new execution eligibility/accounting success.
 stage.operation:='result';stage.owner_id:=p_owner;stage.scan_id:=p_scan;
 stage.admission_receipt_id:=receipt.admission_receipt_id;stage.admission_receipt_digest:=receipt.receipt_digest;
 stage.reservation_id:=original.reservation_id;stage.invocation_id:=original.id;stage.result_evidence_id:=p_result_evidence;
 stage.result_invocation:=to_jsonb(original);
 stage.expected_writes:=jsonb_build_array(jsonb_build_array(jsonb_build_object('old',NULL,'new',to_jsonb(saved))));
 PERFORM internal.assert_initial_result_origin(stage,TRUE);
 evidence:=jsonb_build_object('reference',reference,'result_canonical',result_text,'provenance_canonical',provenance_text,
  'result_digest',actual_digest,'provenance_digest',provenance_digest);
 RETURN jsonb_build_object('version',1,'outcome','found','reference',reference,'result_digest',actual_digest,'evidence',evidence);
END;
$body$;
REVOKE ALL ON FUNCTION internal.read_initial_analysis_result(UUID,UUID,TEXT,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;

-- Fixed INSERT graph: provider barrier and immutable-storage guard read the
-- same exact current statement before the paired BEFORE observer consumes it.
-- No grant, rollout toggle or legacy/other-operation exception is installed.
DO $result_guards$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_get_functiondef('internal.guard_initial_analysis_storage()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled) THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed result storage guard changed'; END IF;
 EXECUTE replace(definition,anchor,$insert$
    IF TG_OP='INSERT' AND TG_TABLE_NAME='initial_analysis_results'
      AND internal.initial_result_expected_insert(to_jsonb(NEW)) THEN RETURN NEW; END IF;
$insert$||anchor);
 SELECT pg_get_functiondef('internal.guard_initial_preparation_provider_writer()'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' PERFORM internal.reject_initial_preparation_provider_writer(identities);';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed result provider guard changed'; END IF;
 EXECUTE replace(definition,anchor,$insert$
 IF TG_OP='INSERT' AND TG_TABLE_SCHEMA='internal' AND TG_TABLE_NAME='initial_analysis_results'
  AND internal.initial_result_expected_insert(current_row) THEN RETURN NEW; END IF;
$insert$||anchor);
END;
$result_guards$;
CREATE TRIGGER s0_result_statement_before BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.initial_analysis_results
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('result');
CREATE TRIGGER s0_result_statement_after AFTER INSERT OR UPDATE OR DELETE ON internal.initial_analysis_results
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('result');
CREATE TRIGGER s0_result_row_before BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_analysis_results
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('result');
CREATE TRIGGER s0_result_row_after AFTER INSERT OR UPDATE OR DELETE ON internal.initial_analysis_results
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('result');

-- Dispatch preparation is private and read-only. These helpers grant no quota,
-- invocation or lifecycle authority without the complete bound compositor.
CREATE FUNCTION internal.initial_dispatch_root_images(p_scan UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE member RECORD; row_count BIGINT; row_bytes BIGINT; total_bytes BIGINT:=0;
 images JSONB; result JSONB:='{}'::JSONB;
BEGIN
 IF p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_dispatch_invalid' USING ERRCODE='22023'; END IF;
 -- Fixed existing retained relations only; no caller relation or executable SQL.
 -- Hash full canonical row images so private receipt leases are not duplicated
 -- into the transaction witness. Counts preserve missing/duplicate distinctions.
 FOR member IN
  SELECT relation_name,row_limit FROM internal.initial_cancellation_private_catalog()
  UNION ALL SELECT * FROM (VALUES
   ('internal.initial_analysis_operation_fences',1),
   ('internal.initial_preparation_source_fences',1),
   ('internal.initial_preparation_source_registry',8),
   ('internal.initial_analysis_media_allocation_fences',1),
   ('internal.initial_analysis_media_registry',8),
   ('internal.initial_cpm_photo_capacity_reservations',1),
   ('internal.initial_cpm_photo_write_attempts',6)
  ) AS additional(relation_name,row_limit)
 LOOP
  EXECUTE format('SELECT count(*) FROM (SELECT 1 FROM %s WHERE scan_id=$1 LIMIT %s) bounded',member.relation_name,member.row_limit+1)
   INTO row_count USING p_scan;
  IF row_count>member.row_limit THEN RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
  EXECUTE format('SELECT COALESCE(sum(octet_length(to_jsonb(t)::TEXT)),0) FROM %s t WHERE scan_id=$1',member.relation_name)
   INTO row_bytes USING p_scan;
  total_bytes:=total_bytes+row_bytes;
  IF row_bytes>33554432 OR total_bytes>67108864 THEN
   RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
  EXECUTE format('SELECT COALESCE(jsonb_agg(digest ORDER BY digest),''[]''::JSONB) FROM (SELECT encode(extensions.digest(convert_to(to_jsonb(t)::TEXT,''UTF8''),''sha256''),''hex'') AS digest FROM %s t WHERE scan_id=$1) members',member.relation_name)
   INTO images USING p_scan;
  result:=result||jsonb_build_object(member.relation_name,images);
 END LOOP;
 -- Closures use their existing write-attempt parent, not a replacement scan key.
 SELECT count(*),COALESCE(sum(octet_length(to_jsonb(c)::TEXT)),0) INTO row_count,row_bytes
  FROM internal.initial_cpm_photo_write_closures c JOIN internal.initial_cpm_photo_write_attempts a USING(attempt_id)
  WHERE a.scan_id=p_scan;
 IF row_count>6 OR row_bytes>33554432 OR total_bytes+row_bytes>67108864 THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
 SELECT COALESCE(jsonb_agg(digest ORDER BY digest),'[]'::JSONB) INTO images FROM (
  SELECT encode(extensions.digest(convert_to(to_jsonb(c)::TEXT,'UTF8'),'sha256'),'hex') AS digest
  FROM internal.initial_cpm_photo_write_closures c JOIN internal.initial_cpm_photo_write_attempts a USING(attempt_id)
  WHERE a.scan_id=p_scan) members;
 RETURN result||jsonb_build_object('internal.initial_cpm_photo_write_closures',images);
END;
$body$;

CREATE FUNCTION internal.capture_initial_dispatch_prestate(p_owner UUID,p_scan UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE admitted internal.initial_analysis_admissions; receipt internal.initial_preparation_admission_receipts;
 quota internal.ai_quota_reservations; attempt internal.identification_provider_attempts;
 charge internal.ai_quota_reservation_counters; counter_row internal.ai_quota_counters;
 usage_row internal.complimentary_scan_usage; charges JSONB:='[]'::JSONB; n INTEGER:=0; roots JSONB;
BEGIN
 PERFORM internal.require_service_role();
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
 SELECT * INTO admitted FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR admitted.owner_id IS DISTINCT FROM p_owner OR admitted.binding_version IS NULL OR admitted.binding_version NOT IN (3,4)
  OR internal.initial_admission_sealed() OR internal.initial_cancellation_sealed()
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE transaction_id=pg_current_xact_id())
  OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_current_xact_id())
  OR (SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan) IS DISTINCT FROM 'pending_pre_dispatch' THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO quota FROM internal.ai_quota_reservations WHERE id=admitted.funding_binding_id FOR UPDATE;
 IF NOT FOUND OR quota.user_id IS DISTINCT FROM p_owner OR quota.request_id IS DISTINCT FROM p_scan
  OR quota.original_analysis_id IS DISTINCT FROM p_scan OR quota.state IS DISTINCT FROM 'reserved' THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO attempt FROM internal.identification_provider_attempts WHERE reservation_id=quota.id AND attempt_count=1 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 -- Exactly the existing C1/release counter order, after the reservation lock.
 FOR charge IN SELECT * FROM internal.ai_quota_reservation_counters l WHERE l.reservation_id=quota.id
  ORDER BY CASE l.scope_type WHEN 'user_daily' THEN 1 WHEN 'user_rate' THEN 2 WHEN 'ip_rate' THEN 3 ELSE 4 END,
   l.scope_key,l.bucket,l.window_start FOR UPDATE LOOP
  n:=n+1;
  IF n>256 THEN RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
  SELECT * INTO counter_row FROM internal.ai_quota_counters c WHERE c.scope_type=charge.scope_type
   AND c.scope_key=charge.scope_key AND c.bucket=charge.bucket AND c.window_start=charge.window_start FOR UPDATE;
  IF NOT FOUND OR counter_row.request_count<1 THEN RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
  charges:=charges||jsonb_build_array(jsonb_build_object('link',to_jsonb(charge),'counter',to_jsonb(counter_row)));
 END LOOP;
 SELECT * INTO usage_row FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_scan FOR UPDATE;
 IF admitted.binding_version=4 THEN
  PERFORM internal.lock_initial_cpm_photo_capacity();
  PERFORM scan_id FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan FOR UPDATE;
 END IF;
 PERFORM scan_id FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan FOR UPDATE;
 PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 PERFORM object_id FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
 PERFORM object_id FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=p_scan ORDER BY photo_ordinal,role COLLATE "C" FOR UPDATE;
 IF admitted.binding_version=4 THEN
  PERFORM attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
  PERFORM c.attempt_id FROM internal.initial_cpm_photo_write_closures c JOIN internal.initial_cpm_photo_write_attempts w USING(attempt_id)
   WHERE w.scan_id=p_scan ORDER BY c.attempt_id FOR UPDATE OF c;
 END IF;
 SELECT * INTO receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR receipt.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM scan_id FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan FOR UPDATE;
 PERFORM object_id FROM internal.initial_preparation_output_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
 PERFORM scan_id FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_media_verifications WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_media_copy_progress WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_media_verification_claims_v2 WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=p_scan FOR UPDATE;
 PERFORM object_id FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 PERFORM internal.initial_admission_retained_receipt(p_owner,p_scan,receipt.admission_receipt_id);
 -- Includes exact original link-set/count and its zero-link funding policy.
 PERFORM internal.assert_initial_admission_live_receipt(p_owner,p_scan,receipt.admission_receipt_id);
 IF admitted.binding_version=3 THEN PERFORM internal.assert_initial_media_handoff_chain(p_owner,p_scan);
 ELSIF receipt.admission_variant IS DISTINCT FROM 'client_prepared_photo_v1' THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 IF EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan OR reservation_id=quota.id)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
  OR EXISTS(SELECT 1 FROM public.scans WHERE id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 roots:=internal.initial_dispatch_root_images(p_scan);
 RETURN jsonb_build_object('version',1,'owner_id',p_owner,'scan_id',p_scan,
  'admission_receipt_id',receipt.admission_receipt_id,'admission_receipt_digest',receipt.receipt_digest,
  'admission',to_jsonb(admitted)-'canonical_input',
  'route',(SELECT route FROM internal.initial_analysis_submissions WHERE scan_id=p_scan),
  'quota',internal.initial_consuming_row_image('internal.ai_quota_reservations',to_jsonb(quota)),
  'attempt',to_jsonb(attempt),'charges',charges,'roots',roots,
  'hold',CASE WHEN usage_row.client_scan_id IS NULL THEN 'null'::JSONB ELSE to_jsonb(usage_row) END,
  'owner_epoch',(SELECT jsonb_build_object('id',u.id,'entitlement_version',u.entitlement_version,
    'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch) FROM public.users u WHERE u.id=p_owner),
  'lifecycle',(SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=p_scan));
END;
$body$;
REVOKE ALL ON FUNCTION internal.initial_dispatch_root_images(UUID),
 internal.capture_initial_dispatch_prestate(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE internal.initial_consuming_staging
 ALTER COLUMN invocation_id DROP NOT NULL,
 ADD COLUMN dispatch_prestate JSONB,
 ADD COLUMN dispatch_invocation JSONB,
 ADD CONSTRAINT initial_dispatch_stage_fields CHECK(
  (operation='dispatch' OR (dispatch_prestate IS NULL AND dispatch_invocation IS NULL))
  AND (invocation_id IS NOT NULL OR (operation='dispatch' AND dispatch_prestate IS NOT NULL AND dispatch_invocation IS NULL AND expected_writes='[]'::JSONB))
  AND (dispatch_invocation IS NULL OR (dispatch_prestate IS NOT NULL AND invocation_id IS NOT NULL)));

CREATE FUNCTION internal.initial_dispatch_invocation_matches(p_original JSONB,p_invocation JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE q JSONB:=p_original->'quota'; a JSONB:=p_original->'attempt'; provenance JSONB:=p_invocation->'provenance'; variant TEXT;
BEGIN
 IF p_original IS NULL OR p_invocation IS NULL THEN RETURN FALSE; END IF;
 PERFORM internal.initial_consuming_row_image('internal.identification_invocations',p_invocation);
 variant:=CASE WHEN a->>'input_profile'='vision_compat_v1' AND p_original->>'route'='identify' THEN 'vision_compat'
  WHEN a->>'input_profile' LIKE 'multimodal_%' AND p_original->>'route'='identify-multimodal' THEN 'multimodal' END;
 RETURN variant IS NOT NULL
  AND p_invocation->>'id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND p_invocation->'event_id'='null'::JSONB AND p_invocation->'is_initial_analysis'='true'::JSONB
  AND p_invocation->'initial_admission_receipt_id'=p_original->'admission_receipt_id'
  AND p_invocation->'reservation_id'=q->'id' AND p_invocation->'attempt_count'='1'::JSONB
  AND p_invocation->'lease_sha256'=q->'lease_sha256' AND p_invocation->'user_id'=p_original->'owner_id'
  AND p_invocation->'scan_id'=p_original->'scan_id'
  AND p_invocation->'provider'=a->'provider' AND p_invocation->'binding'=a->'binding'
  AND p_invocation->'model'=COALESCE(NULLIF(a->'provider_model','null'::JSONB),a->'model')
  AND p_invocation->'input_profile'=a->'input_profile' AND p_invocation->'effective_plan'=a->'effective_plan'
  AND p_invocation->'policy_version'=a->'policy_version'
  AND p_invocation->>'occurred_at' IS NOT NULL AND pg_catalog.isfinite((p_invocation->>'occurred_at')::TIMESTAMPTZ)
  AND internal.identification_provenance_is_valid(provenance)
  AND provenance->>'variant'=variant AND provenance->>'operation'='scan_identification'
  AND provenance->'provider'=a->'provider' AND provenance->'binding'=a->'binding'
  AND provenance->'model'=p_invocation->'model' AND provenance->'policy_version'=a->'policy_version'
  AND CASE WHEN a->>'provider'='openai' AND a->>'binding'='openai_photo_v1'
    THEN jsonb_typeof(p_invocation->'native_price')='object' ELSE p_invocation->'native_price'='null'::JSONB END;
END;
$body$;

-- The actual quota writer supplies its one sampled clock. This pure builder
-- never samples time, allocates identities or consults current pricing.
CREATE FUNCTION internal.initial_dispatch_expected_writes(p_original JSONB,p_invocation JSONB,p_quota_at TIMESTAMPTZ)
RETURNS JSONB LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE links JSONB; quota_after JSONB; result JSONB;
BEGIN
 IF internal.initial_dispatch_invocation_matches(p_original,p_invocation) IS DISTINCT FROM TRUE
  OR p_quota_at IS NULL OR NOT pg_catalog.isfinite(p_quota_at)
  OR p_original#>>'{quota,state}' IS DISTINCT FROM 'reserved'
  OR (p_original#>>'{quota,lease_expires_at}')::TIMESTAMPTZ<=p_quota_at
  OR p_original->'lifecycle' IS DISTINCT FROM jsonb_build_object('scan_id',p_original->'scan_id','state','pending_pre_dispatch')
  OR jsonb_typeof(p_original->'charges') IS DISTINCT FROM 'array' OR jsonb_array_length(p_original->'charges')>256 THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('old',c->'link','new',NULL) ORDER BY ordinality),'[]'::JSONB)
  INTO links FROM jsonb_array_elements(p_original->'charges') WITH ORDINALITY AS charges(c,ordinality);
 quota_after:=(p_original->'quota')||jsonb_build_object('state','committed','committed_at',p_quota_at,'updated_at',p_quota_at);
 result:=jsonb_build_array(
  jsonb_build_array(jsonb_build_object('old',p_original->'quota','new',quota_after)),links,
  jsonb_build_array(jsonb_build_object('old',NULL,'new',p_invocation)),
  jsonb_build_array(jsonb_build_object('old',p_original->'lifecycle','new',jsonb_build_object('scan_id',p_original->'scan_id','state','dispatch_authorized'))));
 PERFORM internal.assert_initial_consuming_expectations('dispatch',result);
 RETURN result;
END;
$body$;

-- Used only before quota mutation; never turn a committed replay into a grant.
CREATE FUNCTION internal.initial_dispatch_entry_authorized(p_reservation UUID,p_owner UUID,p_lease UUID,p_attempt INTEGER,p_provenance JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE s internal.initial_consuming_staging; assigned JSONB; variant TEXT;
BEGIN
 SELECT * INTO s FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR s.operation IS DISTINCT FROM 'dispatch' OR s.dispatch_prestate IS NULL
  OR s.owner_id IS DISTINCT FROM p_owner OR s.reservation_id IS DISTINCT FROM p_reservation
  OR s.statement_active OR s.sealed OR s.next_statement<>0 OR s.pending_rows<>'{}'::INTEGER[] OR s.observed_rows<>'{}'::INTEGER[]
  OR s.expected_writes<>'[]'::JSONB OR p_lease IS NULL OR p_attempt IS DISTINCT FROM 1
  OR s.dispatch_prestate#>>'{quota,lease_sha256}' IS DISTINCT FROM encode(extensions.digest(convert_to(p_lease::TEXT,'UTF8'),'sha256'),'hex')
  OR s.dispatch_prestate#>>'{quota,state}' IS DISTINCT FROM 'reserved'
  OR s.dispatch_prestate IS DISTINCT FROM internal.capture_initial_dispatch_prestate(s.owner_id,s.scan_id) THEN RETURN FALSE; END IF;
 assigned:=s.dispatch_prestate->'attempt';
 variant:=CASE WHEN assigned->>'input_profile'='vision_compat_v1' AND s.dispatch_prestate->>'route'='identify' THEN 'vision_compat'
  WHEN assigned->>'input_profile' LIKE 'multimodal_%' AND s.dispatch_prestate->>'route'='identify-multimodal' THEN 'multimodal' END;
 RETURN variant IS NOT NULL AND internal.identification_provenance_is_valid(p_provenance)
  AND p_provenance->>'variant'=variant AND p_provenance->>'operation'='scan_identification'
  AND p_provenance->'provider'=assigned->'provider' AND p_provenance->'binding'=assigned->'binding'
  AND p_provenance->'model'=COALESCE(NULLIF(assigned->'provider_model','null'::JSONB),assigned->'model')
  AND p_provenance->'policy_version'=assigned->'policy_version'
  AND (s.dispatch_invocation IS NULL OR s.dispatch_invocation->'provenance'=p_provenance);
END;
$body$;

CREATE FUNCTION internal.attach_initial_dispatch_invocation(p_invocation internal.identification_invocations)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE s internal.initial_consuming_staging;
BEGIN
 SELECT * INTO s FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR s.operation<>'dispatch' OR s.dispatch_prestate IS NULL THEN
  IF p_invocation.is_initial_analysis THEN RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
  RETURN;
 END IF;
 IF s.dispatch_invocation IS NOT NULL OR s.invocation_id IS NOT NULL OR s.expected_writes<>'[]'::JSONB
  OR internal.initial_dispatch_invocation_matches(s.dispatch_prestate,to_jsonb(p_invocation)) IS DISTINCT FROM TRUE THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
 UPDATE internal.initial_consuming_staging SET invocation_id=p_invocation.id,dispatch_invocation=to_jsonb(p_invocation)
  WHERE transaction_id=s.transaction_id;
END;
$body$;

CREATE FUNCTION internal.attach_initial_dispatch_quota(p_reservation UUID,p_owner UUID,p_lease UUID,p_final TEXT,p_quota_at TIMESTAMPTZ)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE s internal.initial_consuming_staging;
BEGIN
 SELECT * INTO s FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR s.operation<>'dispatch' OR s.dispatch_prestate IS NULL THEN RETURN; END IF;
 IF p_final IS DISTINCT FROM 'committed' OR s.dispatch_invocation IS NULL
  OR internal.initial_dispatch_entry_authorized(p_reservation,p_owner,p_lease,1,s.dispatch_invocation->'provenance') IS DISTINCT FROM TRUE THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
 UPDATE internal.initial_consuming_staging SET expected_writes=internal.initial_dispatch_expected_writes(
  s.dispatch_prestate,s.dispatch_invocation,p_quota_at) WHERE transaction_id=s.transaction_id;
END;
$body$;
REVOKE ALL ON FUNCTION internal.initial_dispatch_invocation_matches(JSONB,JSONB),
 internal.initial_dispatch_expected_writes(JSONB,JSONB,TIMESTAMPTZ),
 internal.initial_dispatch_entry_authorized(UUID,UUID,UUID,INTEGER,JSONB),
 internal.attach_initial_dispatch_invocation(internal.identification_invocations),
 internal.attach_initial_dispatch_quota(UUID,UUID,UUID,TEXT,TIMESTAMPTZ)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.assert_initial_dispatch_terminal(p_stage internal.initial_consuming_staging)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE charge JSONB; counter_image JSONB; original JSONB:=p_stage.dispatch_prestate; actual JSONB;
BEGIN
 IF p_stage.operation<>'dispatch' OR original IS NULL THEN RETURN; END IF;
 IF NOT p_stage.sealed OR p_stage.next_statement<>4 OR p_stage.statement_active
  OR p_stage.pending_rows<>'{}'::INTEGER[] OR p_stage.observed_rows<>'{}'::INTEGER[]
  OR p_stage.invocation_id IS NULL OR p_stage.dispatch_invocation IS NULL
  OR p_stage.dispatch_invocation->>'id' IS DISTINCT FROM p_stage.invocation_id::TEXT
  OR p_stage.expected_writes IS DISTINCT FROM internal.initial_dispatch_expected_writes(original,p_stage.dispatch_invocation,
    (p_stage.expected_writes#>>'{0,0,new,committed_at}')::TIMESTAMPTZ)
  OR internal.initial_dispatch_root_images(p_stage.scan_id) IS DISTINCT FROM original->'roots'
  OR (SELECT internal.initial_consuming_row_image('internal.ai_quota_reservations',to_jsonb(q)) FROM internal.ai_quota_reservations q
    WHERE id=p_stage.reservation_id) IS DISTINCT FROM p_stage.expected_writes#>'{0,0,new}'
  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters WHERE reservation_id=p_stage.reservation_id)
  OR (SELECT count(*) FROM internal.identification_provider_attempts WHERE reservation_id=p_stage.reservation_id)<>1
  OR (SELECT to_jsonb(a) FROM internal.identification_provider_attempts a WHERE reservation_id=p_stage.reservation_id AND attempt_count=1)
    IS DISTINCT FROM original->'attempt'
  OR (SELECT count(*) FROM internal.identification_invocations WHERE scan_id=p_stage.scan_id OR reservation_id=p_stage.reservation_id)<>1
  OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=p_stage.invocation_id) IS DISTINCT FROM p_stage.dispatch_invocation
  OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=p_stage.scan_id) IS DISTINCT FROM p_stage.expected_writes#>'{3,0,new}'
  OR (SELECT jsonb_build_object('id',u.id,'entitlement_version',u.entitlement_version,
    'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch) FROM public.users u WHERE u.id=p_stage.owner_id) IS DISTINCT FROM original->'owner_epoch'
  OR (SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id=p_stage.scan_id)
    <>(CASE WHEN original->'hold'='null'::JSONB THEN 0 ELSE 1 END)
  OR COALESCE((SELECT to_jsonb(h) FROM internal.complimentary_scan_usage h WHERE user_id=p_stage.owner_id AND client_scan_id=p_stage.scan_id),'null'::JSONB)
    IS DISTINCT FROM original->'hold'
  OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_stage.owner_id AND status IN ('pending','storage_pending','auth_pending')) THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
 FOR charge IN SELECT value FROM jsonb_array_elements(original->'charges') LOOP
  SELECT to_jsonb(c) INTO counter_image FROM internal.ai_quota_counters c
   WHERE c.scope_type=charge#>>'{counter,scope_type}' AND c.scope_key=charge#>>'{counter,scope_key}'
    AND c.bucket=charge#>>'{counter,bucket}' AND c.window_start=(charge#>>'{counter,window_start}')::TIMESTAMPTZ;
  IF counter_image IS DISTINCT FROM charge->'counter' THEN
   RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
 END LOOP;
END;
$body$;

-- Only exact rows of a completely prepared dispatch are recognized. This adds
-- no authority to mechanical/unbound stage fixtures or other operations.
CREATE FUNCTION internal.initial_dispatch_expected_member(p_relation TEXT,p_action TEXT,p_old JSONB,p_new JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE s internal.initial_consuming_staging; spec JSONB; event JSONB;
BEGIN
 SELECT * INTO s FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR s.operation IS DISTINCT FROM 'dispatch' OR s.dispatch_prestate IS NULL OR s.dispatch_invocation IS NULL
  OR s.invocation_id IS NULL OR s.sealed OR NOT s.statement_active OR s.next_statement NOT BETWEEN 0 AND 3
  OR jsonb_array_length(s.expected_writes)<>4 THEN RETURN FALSE; END IF;
 spec:=internal.initial_consuming_statement_catalog('dispatch')->s.next_statement;
 IF spec->>'relation' IS DISTINCT FROM p_relation OR spec->>'action' IS DISTINCT FROM p_action THEN RETURN FALSE; END IF;
 event:=jsonb_build_object('old',internal.initial_consuming_row_image(p_relation,p_old),'new',internal.initial_consuming_row_image(p_relation,p_new));
 RETURN EXISTS(SELECT 1 FROM jsonb_array_elements(s.expected_writes->s.next_statement) WITH ORDINALITY e(value,ordinality)
  WHERE e.value=event AND NOT (ordinality-1)::INTEGER=ANY(s.observed_rows));
END;
$body$;

CREATE FUNCTION internal.commit_initial_analysis_dispatch(p_owner UUID,p_scan UUID,p_submission TEXT,p_configuration TEXT,
 p_funding TEXT,p_assets TEXT,p_lease UUID,p_provenance JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE original JSONB; s internal.initial_consuming_staging; result RECORD; lifecycle_after internal.initial_analysis_lifecycle_fences;
BEGIN
 PERFORM internal.require_service_role();
 IF p_owner IS NULL OR p_scan IS NULL OR p_lease IS NULL
  OR p_submission IS NULL OR p_submission !~ '^[0-9a-f]{64}$'
  OR p_configuration IS NULL OR p_configuration !~ '^[0-9a-f]{64}$'
  OR p_funding IS NULL OR p_funding !~ '^[0-9a-f]{64}$'
  OR p_assets IS NULL OR p_assets !~ '^[0-9a-f]{64}$'
  OR p_provenance IS NULL OR octet_length(p_provenance::TEXT)>65536
  OR internal.identification_provenance_is_valid(p_provenance) IS DISTINCT FROM TRUE THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_invalid' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id()) THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 original:=internal.capture_initial_dispatch_prestate(p_owner,p_scan);
 IF original#>>'{admission,submission_digest}' IS DISTINCT FROM p_submission
  OR original#>>'{admission,configuration_digest}' IS DISTINCT FROM p_configuration
  OR original#>>'{admission,funding_digest}' IS DISTINCT FROM p_funding
  OR original#>>'{admission,assets_digest}' IS DISTINCT FROM p_assets
  OR original#>>'{quota,lease_sha256}' IS DISTINCT FROM encode(extensions.digest(convert_to(p_lease::TEXT,'UTF8'),'sha256'),'hex') THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_conflict' USING ERRCODE='55000'; END IF;
 INSERT INTO internal.initial_consuming_staging(transaction_id,scan_id,owner_id,operation,admission_receipt_id,
  admission_receipt_digest,reservation_id,invocation_id,expected_writes,dispatch_prestate)
 VALUES(pg_current_xact_id(),p_scan,p_owner,'dispatch',(original->>'admission_receipt_id')::UUID,
  original->>'admission_receipt_digest',(original#>>'{quota,id}')::UUID,NULL,'[]',original) RETURNING * INTO s;
 SELECT * INTO STRICT result FROM public.commit_identification_invocation(s.reservation_id,p_owner,p_lease,1,p_provenance);
 SELECT * INTO STRICT s FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF result.may_dispatch IS DISTINCT FROM TRUE OR result.invocation_id IS DISTINCT FROM s.invocation_id
  OR s.next_statement<>3 OR s.statement_active OR s.sealed OR s.pending_rows<>'{}'::INTEGER[] OR s.observed_rows<>'{}'::INTEGER[] THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
 lifecycle_after:=jsonb_populate_record(NULL::internal.initial_analysis_lifecycle_fences,s.expected_writes#>'{3,0,new}');
 UPDATE internal.initial_analysis_lifecycle_fences SET state=lifecycle_after.state WHERE scan_id=lifecycle_after.scan_id;
 SELECT * INTO STRICT s FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 PERFORM internal.assert_initial_dispatch_terminal(s);
 DELETE FROM internal.initial_consuming_staging WHERE transaction_id=s.transaction_id;
 RETURN jsonb_build_object('version',1,'outcome','fresh','invocation_id',s.invocation_id);
END;
$body$;
REVOKE ALL ON FUNCTION internal.assert_initial_dispatch_terminal(internal.initial_consuming_staging),
 internal.initial_dispatch_expected_member(TEXT,TEXT,JSONB,JSONB),
 internal.commit_initial_analysis_dispatch(UUID,UUID,TEXT,TEXT,TEXT,TEXT,UUID,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.guard_initial_consuming_stage()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE immutable_old JSONB; immutable_new JSONB; total INTEGER; count_rows INTEGER; lock_key INTEGER; row_index INTEGER;
BEGIN
 IF TG_OP='TRUNCATE' THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 IF (CASE WHEN TG_OP='DELETE' THEN OLD.transaction_id ELSE NEW.transaction_id END)
     IS DISTINCT FROM pg_catalog.pg_current_xact_id() THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 IF TG_OP='DELETE' THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR NOT OLD.sealed OR OLD.statement_active OR OLD.pending_rows<>'{}'::INTEGER[]
    OR OLD.observed_rows<>'{}'::INTEGER[] OR OLD.next_statement<>jsonb_array_length(OLD.expected_writes) THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_incomplete' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_report_terminal(OLD);
  PERFORM internal.assert_initial_result_terminal(OLD);
  PERFORM internal.assert_initial_dispatch_terminal(OLD);
  RETURN OLD;
 END IF;
 IF TG_OP='INSERT' THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR current_setting('transaction_isolation')<>'read committed'
    OR NEW.next_statement<>0 OR NEW.statement_active OR NEW.pending_rows<>'{}'::INTEGER[]
    OR NEW.observed_rows<>'{}'::INTEGER[] OR NEW.sealed THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
  IF NEW.operation='report' THEN
   PERFORM internal.initial_consuming_row_image('internal.identification_invocations',NEW.report_invocation);
   IF NEW.expected_writes<>'[]'::JSONB OR NEW.report_winner IS NOT NULL OR NEW.report_inserted IS NOT NULL
    OR NEW.report_invocation->>'id' IS DISTINCT FROM NEW.invocation_id::TEXT
    OR NEW.report_invocation->>'user_id' IS DISTINCT FROM NEW.owner_id::TEXT
    OR NEW.report_invocation->>'scan_id' IS DISTINCT FROM NEW.scan_id::TEXT
    OR NEW.report_invocation->>'reservation_id' IS DISTINCT FROM NEW.reservation_id::TEXT
    OR NEW.report_invocation->>'initial_admission_receipt_id' IS DISTINCT FROM NEW.admission_receipt_id::TEXT
    OR NEW.report_invocation->'is_initial_analysis' IS DISTINCT FROM 'true'::JSONB
    OR NEW.report_invocation->'event_id' IS DISTINCT FROM 'null'::JSONB
    OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=NEW.invocation_id) IS DISTINCT FROM NEW.report_invocation THEN
    RAISE EXCEPTION 'initial_analysis_report_stage_invalid' USING ERRCODE='55000'; END IF;
  ELSIF NEW.operation='dispatch' AND NEW.dispatch_prestate IS NOT NULL THEN
   IF NEW.invocation_id IS NOT NULL OR NEW.dispatch_invocation IS NOT NULL OR NEW.expected_writes<>'[]'::JSONB
    OR octet_length(NEW.dispatch_prestate::TEXT)>1048576
    OR NEW.dispatch_prestate IS DISTINCT FROM internal.capture_initial_dispatch_prestate(NEW.owner_id,NEW.scan_id)
    OR NEW.dispatch_prestate->>'admission_receipt_id' IS DISTINCT FROM NEW.admission_receipt_id::TEXT
    OR NEW.dispatch_prestate->>'admission_receipt_digest' IS DISTINCT FROM NEW.admission_receipt_digest
    OR NEW.dispatch_prestate#>>'{quota,id}' IS DISTINCT FROM NEW.reservation_id::TEXT THEN
    RAISE EXCEPTION 'initial_analysis_dispatch_stage_invalid' USING ERRCODE='55000'; END IF;
  ELSE
   PERFORM internal.assert_initial_consuming_expectations(NEW.operation,NEW.expected_writes);
   IF NEW.operation='result' AND NEW.result_invocation IS NOT NULL THEN
    PERFORM internal.assert_initial_result_origin(NEW,TRUE);
   END IF;
  END IF;
  -- Denial-only transaction latch survives successful stage removal. A fully
  -- rolled-back subtransaction also rolls back its latch and all SQL effects.
  -- No lock/setting is ever accepted as original authority.
  lock_key:=pg_catalog.hashtext(NEW.transaction_id::TEXT);
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_locks l WHERE l.locktype='advisory' AND l.pid=pg_catalog.pg_backend_pid()
      AND l.classid=1396920143::OID AND l.objid::BIGINT=(lock_key::BIGINT & 4294967295) AND l.objsubid=2 AND l.granted)
    OR NOT pg_catalog.pg_try_advisory_xact_lock(1396920143,lock_key) THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_reused' USING ERRCODE='55000'; END IF;
  RETURN NEW;
 END IF;
 IF OLD.operation='dispatch' AND OLD.dispatch_prestate IS NOT NULL AND OLD.expected_writes='[]'::JSONB THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR OLD.statement_active OR OLD.next_statement<>0 OR OLD.sealed
   OR OLD.pending_rows<>'{}'::INTEGER[] OR OLD.observed_rows<>'{}'::INTEGER[]
   OR OLD.dispatch_prestate IS DISTINCT FROM internal.capture_initial_dispatch_prestate(OLD.owner_id,OLD.scan_id) THEN
   RAISE EXCEPTION 'initial_analysis_dispatch_attachment_invalid' USING ERRCODE='55000'; END IF;
  IF OLD.dispatch_invocation IS NULL THEN
   IF OLD.invocation_id IS NOT NULL OR NEW.dispatch_invocation IS NULL OR NEW.invocation_id IS NULL
    OR NEW.dispatch_invocation->>'id' IS DISTINCT FROM NEW.invocation_id::TEXT
    OR to_jsonb(OLD)-ARRAY['invocation_id','dispatch_invocation'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['invocation_id','dispatch_invocation']
    OR internal.initial_dispatch_invocation_matches(OLD.dispatch_prestate,NEW.dispatch_invocation) IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'initial_analysis_dispatch_attachment_invalid' USING ERRCODE='55000'; END IF;
  ELSE
   IF to_jsonb(OLD)-'expected_writes' IS DISTINCT FROM to_jsonb(NEW)-'expected_writes'
    OR NEW.expected_writes IS DISTINCT FROM internal.initial_dispatch_expected_writes(OLD.dispatch_prestate,OLD.dispatch_invocation,
      (NEW.expected_writes#>>'{0,0,new,committed_at}')::TIMESTAMPTZ) THEN
    RAISE EXCEPTION 'initial_analysis_dispatch_attachment_invalid' USING ERRCODE='55000'; END IF;
  END IF;
  RETURN NEW;
 END IF;
 -- Only this one-way attachment may change expected_writes. The writer
 -- supplies its already-prepared row; validation never calls pricing again.
 IF OLD.operation='report' AND OLD.expected_writes='[]'::JSONB THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR OLD.statement_active OR OLD.next_statement<>0 OR OLD.sealed
   OR to_jsonb(OLD)-'expected_writes' IS DISTINCT FROM to_jsonb(NEW)-'expected_writes'
   OR NEW.expected_writes IS DISTINCT FROM internal.initial_report_expected_writes(OLD.report_invocation,NEW.expected_writes#>'{0,0,new}')
   OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=OLD.invocation_id) IS DISTINCT FROM OLD.report_invocation THEN
   RAISE EXCEPTION 'initial_analysis_report_attachment_invalid' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_consuming_expectations('report',NEW.expected_writes);
  RETURN NEW;
 END IF;
 -- One statement-resolution transition binds the actual locked event once.
 IF OLD.operation='report' AND OLD.next_statement=0 AND OLD.statement_active AND NOT NEW.statement_active THEN
  IF pg_catalog.pg_trigger_depth()<>2 OR OLD.report_winner IS NOT NULL OR OLD.report_inserted IS NOT NULL
   OR NEW.report_winner IS NULL OR NEW.report_inserted IS NULL OR NEW.next_statement<>1 OR NEW.sealed
   OR NEW.pending_rows<>'{}'::INTEGER[] OR NEW.observed_rows<>'{}'::INTEGER[]
   OR to_jsonb(OLD)-ARRAY['report_winner','report_inserted','statement_active','next_statement','pending_rows','observed_rows']
     IS DISTINCT FROM to_jsonb(NEW)-ARRAY['report_winner','report_inserted','statement_active','next_statement','pending_rows','observed_rows']
   OR NOT ((OLD.pending_rows='{}'::INTEGER[] AND OLD.observed_rows=ARRAY[0] AND NEW.report_inserted)
     OR (OLD.pending_rows=ARRAY[0] AND OLD.observed_rows='{}'::INTEGER[] AND NOT NEW.report_inserted))
   OR NEW.report_winner->>'source_type' IS DISTINCT FROM 'identification_invocation'
   OR NEW.report_winner->>'operation' IS DISTINCT FROM 'scan_identification'
   OR NEW.report_winner->>'source_id' IS DISTINCT FROM OLD.invocation_id::TEXT
   OR (NEW.report_inserted AND NEW.report_winner IS DISTINCT FROM OLD.expected_writes#>'{0,0,new}')
   OR (NOT NEW.report_inserted AND NEW.report_winner->'id'=OLD.expected_writes#>'{0,0,new,id}')
   OR (SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE id=(NEW.report_winner->>'id')::UUID) IS DISTINCT FROM NEW.report_winner THEN
   RAISE EXCEPTION 'initial_analysis_report_resolution_invalid' USING ERRCODE='55000'; END IF;
  PERFORM internal.initial_consuming_row_image('public.ai_usage_events',NEW.report_winner);
  RETURN NEW;
 END IF;
 immutable_old:=to_jsonb(OLD)-ARRAY['next_statement','statement_active','pending_rows','observed_rows','sealed'];
 immutable_new:=to_jsonb(NEW)-ARRAY['next_statement','statement_active','pending_rows','observed_rows','sealed'];
 IF pg_catalog.pg_trigger_depth()<>2 OR OLD.sealed OR immutable_old IS DISTINCT FROM immutable_new THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 total:=jsonb_array_length(OLD.expected_writes);
 count_rows:=jsonb_array_length(OLD.expected_writes->OLD.next_statement);
 IF NOT OLD.statement_active AND NEW.statement_active THEN
  IF to_jsonb(OLD)-'statement_active' IS DISTINCT FROM to_jsonb(NEW)-'statement_active' THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 ELSIF OLD.statement_active AND NEW.statement_active AND cardinality(NEW.pending_rows)=cardinality(OLD.pending_rows)+1 THEN
  row_index:=NEW.pending_rows[cardinality(NEW.pending_rows)];
  IF row_index IS NULL OR row_index<0 OR row_index>=count_rows OR row_index=ANY(OLD.observed_rows||OLD.pending_rows)
    OR NEW.pending_rows IS DISTINCT FROM OLD.pending_rows||row_index
    OR to_jsonb(OLD)-'pending_rows' IS DISTINCT FROM to_jsonb(NEW)-'pending_rows' THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 ELSIF OLD.statement_active AND NEW.statement_active AND cardinality(NEW.observed_rows)=cardinality(OLD.observed_rows)+1 THEN
  row_index:=NEW.observed_rows[cardinality(NEW.observed_rows)];
  IF row_index IS NULL OR NOT row_index=ANY(OLD.pending_rows) OR NEW.observed_rows IS DISTINCT FROM OLD.observed_rows||row_index
    OR NEW.pending_rows IS DISTINCT FROM array_remove(OLD.pending_rows,row_index)
    OR to_jsonb(OLD)-ARRAY['pending_rows','observed_rows'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['pending_rows','observed_rows'] THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 ELSIF OLD.statement_active AND NOT NEW.statement_active THEN
  IF OLD.pending_rows<>'{}'::INTEGER[] OR cardinality(OLD.observed_rows)<>count_rows
    OR NEW.pending_rows<>'{}'::INTEGER[] OR NEW.observed_rows<>'{}'::INTEGER[] OR NEW.next_statement<>OLD.next_statement+1
    OR NEW.sealed IS DISTINCT FROM (NEW.next_statement=total) THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_incomplete' USING ERRCODE='55000'; END IF;
 ELSE RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000';
 END IF;
 RETURN NEW;
END;
$body$;
CREATE OR REPLACE FUNCTION internal.require_complete_initial_consuming_stage()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE captured internal.initial_consuming_staging;
BEGIN
 captured:=CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
 IF captured.transaction_id IS DISTINCT FROM pg_catalog.pg_current_xact_id()
   OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging WHERE transaction_id=captured.transaction_id)
   OR (TG_OP='DELETE' AND (NOT captured.sealed OR captured.statement_active OR captured.pending_rows<>'{}'::INTEGER[]
     OR captured.observed_rows<>'{}'::INTEGER[] OR captured.next_statement<>jsonb_array_length(captured.expected_writes))) THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_incomplete' USING ERRCODE='55000'; END IF;
 IF TG_OP='DELETE' THEN
  PERFORM internal.assert_initial_report_terminal(captured);
  PERFORM internal.assert_initial_result_terminal(captured);
  PERFORM internal.assert_initial_dispatch_terminal(captured);
 END IF;
 -- Dispatch still requires its operation-specific terminal assertion before
 -- any business guard recognizes that mechanical witness.
 RETURN NULL;
END;
$function$
;
CREATE OR REPLACE FUNCTION internal.guard_initial_consuming_member()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE stage internal.initial_consuming_staging; spec JSONB; images JSONB; idx INTEGER; winner JSONB;
 relation_name TEXT:=TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME;
BEGIN
 SELECT * INTO stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_catalog.pg_current_xact_id();
 IF NOT FOUND OR (TG_NARGS=1 AND stage.operation IS DISTINCT FROM TG_ARGV[0]) THEN
  IF TG_LEVEL='STATEMENT' OR TG_WHEN='AFTER' THEN RETURN NULL; END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
 END IF;
 spec:=internal.initial_consuming_statement_catalog(stage.operation)->stage.next_statement;
 IF stage.sealed OR (stage.operation IN ('report','dispatch') AND stage.expected_writes='[]'::JSONB) OR TG_OP='TRUNCATE' OR spec->>'relation' IS DISTINCT FROM relation_name
   OR spec->>'action' IS DISTINCT FROM TG_OP THEN
  RAISE EXCEPTION 'initial_analysis_consuming_statement_invalid' USING ERRCODE='55000'; END IF;
 IF TG_LEVEL='STATEMENT' THEN
  IF TG_WHEN='BEFORE' THEN
   IF stage.statement_active OR stage.pending_rows<>'{}'::INTEGER[] OR stage.observed_rows<>'{}'::INTEGER[] THEN
    RAISE EXCEPTION 'initial_analysis_consuming_statement_invalid' USING ERRCODE='55000'; END IF;
   UPDATE internal.initial_consuming_staging SET statement_active=TRUE WHERE transaction_id=stage.transaction_id;
  ELSE
   IF stage.operation='report' AND stage.next_statement=0 THEN
    IF NOT stage.statement_active OR NOT ((stage.pending_rows=ARRAY[0] AND stage.observed_rows='{}'::INTEGER[])
      OR (stage.pending_rows='{}'::INTEGER[] AND stage.observed_rows=ARRAY[0])) THEN
     RAISE EXCEPTION 'initial_analysis_report_resolution_invalid' USING ERRCODE='55000'; END IF;
    -- Invocation is already locked. Only the fixed source event is acquired
    -- here; no parent, receipt or owner lookup follows this lock.
    SELECT to_jsonb(e) INTO winner FROM public.ai_usage_events e
     WHERE source_type='identification_invocation' AND source_id=stage.invocation_id AND operation='scan_identification' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_report_winner_missing' USING ERRCODE='55000'; END IF;
    UPDATE internal.initial_consuming_staging SET statement_active=FALSE,next_statement=1,
     pending_rows='{}',observed_rows='{}',report_winner=winner,report_inserted=(stage.observed_rows=ARRAY[0])
     WHERE transaction_id=stage.transaction_id;
    RETURN NULL;
   END IF;
   IF NOT stage.statement_active OR stage.pending_rows<>'{}'::INTEGER[]
     OR cardinality(stage.observed_rows)<>jsonb_array_length(stage.expected_writes->stage.next_statement) THEN
    RAISE EXCEPTION 'initial_analysis_consuming_stage_incomplete' USING ERRCODE='55000'; END IF;
   UPDATE internal.initial_consuming_staging SET statement_active=FALSE,next_statement=next_statement+1,
     observed_rows='{}',sealed=(next_statement+1=jsonb_array_length(expected_writes)) WHERE transaction_id=stage.transaction_id;
  END IF;
  RETURN NULL;
 END IF;
 IF NOT stage.statement_active THEN
  RAISE EXCEPTION 'initial_analysis_consuming_statement_invalid' USING ERRCODE='55000'; END IF;
 images:=jsonb_build_object('old',internal.initial_consuming_row_image(relation_name,CASE WHEN TG_OP='INSERT' THEN NULL ELSE to_jsonb(OLD) END),
   'new',internal.initial_consuming_row_image(relation_name,CASE WHEN TG_OP='DELETE' THEN NULL ELSE to_jsonb(NEW) END));
 IF TG_WHEN='BEFORE' THEN
  SELECT (ordinality-1)::INTEGER INTO idx FROM jsonb_array_elements(internal.initial_consuming_expected_group(stage)) WITH ORDINALITY e(value,ordinality)
    WHERE value=images AND NOT (ordinality-1)::INTEGER=ANY(stage.observed_rows||stage.pending_rows);
  IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_consuming_row_invalid' USING ERRCODE='55000'; END IF;
  UPDATE internal.initial_consuming_staging SET pending_rows=pending_rows||idx WHERE transaction_id=stage.transaction_id;
 ELSE
  SELECT (ordinality-1)::INTEGER INTO idx FROM jsonb_array_elements(internal.initial_consuming_expected_group(stage)) WITH ORDINALITY e(value,ordinality)
    WHERE value=images AND (ordinality-1)::INTEGER=ANY(stage.pending_rows);
  IF NOT FOUND THEN
   RAISE EXCEPTION 'initial_analysis_consuming_row_invalid' USING ERRCODE='55000'; END IF;
  UPDATE internal.initial_consuming_staging SET observed_rows=observed_rows||idx,pending_rows=array_remove(pending_rows,idx) WHERE transaction_id=stage.transaction_id;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.commit_identification_invocation(p_reservation_id uuid, p_user_id uuid, p_lease_token uuid, p_attempt_count integer, p_provenance jsonb)
 RETURNS TABLE(invocation_id uuid, may_dispatch boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '5s'
AS $function$
DECLARE
    reserved internal.ai_quota_reservations%ROWTYPE;
    assigned internal.identification_provider_attempts%ROWTYPE;
    invocation internal.identification_invocations%ROWTYPE;
    price JSONB;
    started TIMESTAMPTZ;
    initial_dispatch BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();
    initial_dispatch:=internal.initial_dispatch_entry_authorized(p_reservation_id,p_user_id,p_lease_token,p_attempt_count,p_provenance);
    IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations q JOIN internal.initial_analysis_operation_fences f ON f.scan_id IN (q.original_analysis_id,q.request_id) WHERE q.id=p_reservation_id) AND NOT initial_dispatch THEN
      RAISE EXCEPTION 'initial_analysis_execution_required' USING ERRCODE='55000'; END IF;

    IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations r JOIN internal.observation_analysis_intents i ON i.analysis_id=r.original_analysis_id
        WHERE r.id=p_reservation_id AND current_setting('merian.observation_analysis_provider',TRUE) IS DISTINCT FROM i.owner_id::TEXT || ':' || i.analysis_id::TEXT) THEN
        RAISE EXCEPTION 'analysis_history_dispatch_required' USING ERRCODE='55000';
    END IF;

    IF p_reservation_id IS NULL OR p_user_id IS NULL OR p_lease_token IS NULL
        OR p_attempt_count IS NULL OR p_attempt_count < 1 OR p_provenance IS NULL
        OR NOT internal.identification_provenance_is_valid(p_provenance) THEN
        RAISE EXCEPTION 'identification_invocation_invalid' USING ERRCODE = '22023';
    END IF;
    -- Same user -> reservation lock order as admission/identity transitions.
    PERFORM id FROM public.users WHERE id = p_user_id FOR KEY SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'identification_invocation_unavailable' USING ERRCODE = 'P0001'; END IF;
    SELECT * INTO reserved FROM internal.ai_quota_reservations
        WHERE id = p_reservation_id AND user_id = p_user_id FOR UPDATE;
    IF NOT FOUND OR reserved.lease_token <> p_lease_token OR reserved.attempt_count <> p_attempt_count
        OR reserved.operation <> 'scan_identification' OR reserved.original_analysis_id IS NULL THEN
        RAISE EXCEPTION 'identification_invocation_conflict' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO invocation FROM internal.identification_invocations
        WHERE reservation_id = p_reservation_id AND attempt_count = p_attempt_count;
    IF FOUND THEN
        RETURN QUERY SELECT invocation.id, FALSE;
        RETURN;
    END IF;

    IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
        RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-scan-ingestion:' || reserved.original_analysis_id::TEXT,0::BIGINT));

    IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=reserved.original_analysis_id) THEN
        RAISE EXCEPTION 'scan_generation_deleted' USING ERRCODE='55000';
    END IF;
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=reserved.original_analysis_id)
        AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_dispatch_witnesses w
            WHERE w.analysis_id=reserved.original_analysis_id AND w.owner_id=p_user_id
                AND w.reservation_id=p_reservation_id AND w.attempt_count=p_attempt_count
                AND w.lease_sha256=encode(extensions.digest(p_lease_token::TEXT,'sha256'),'hex')
                AND w.provenance=p_provenance AND w.dispatch_transaction=pg_catalog.pg_current_xact_id()) THEN
        RAISE EXCEPTION 'analysis_history_dispatch_required' USING ERRCODE='55000';
    END IF;

    IF reserved.state <> 'reserved' THEN
        RAISE EXCEPTION 'identification_invocation_conflict' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO assigned FROM internal.identification_provider_attempts
        WHERE reservation_id = p_reservation_id AND attempt_count = p_attempt_count;
    IF NOT FOUND OR (assigned.input_profile NOT LIKE 'multimodal_%' AND NOT initial_dispatch)
        OR assigned.operation <> reserved.operation THEN
        RAISE EXCEPTION 'identification_invocation_unqualified' USING ERRCODE = 'P0001';
    END IF;
    IF p_provenance ->> 'provider' IS DISTINCT FROM assigned.provider
        OR p_provenance ->> 'binding' IS DISTINCT FROM assigned.binding
        OR p_provenance ->> 'model' IS DISTINCT FROM COALESCE(assigned.provider_model, assigned.model)
        OR p_provenance ->> 'operation' IS DISTINCT FROM assigned.operation
        OR p_provenance ->> 'variant' IS DISTINCT FROM (CASE WHEN initial_dispatch AND assigned.input_profile='vision_compat_v1' THEN 'vision_compat' ELSE 'multimodal' END)
        OR p_provenance ->> 'policy_version' IS DISTINCT FROM assigned.policy_version::TEXT THEN
        RAISE EXCEPTION 'identification_invocation_provenance_conflict' USING ERRCODE = 'P0001';
    END IF;
    started := clock_timestamp();
    IF assigned.provider = 'openai' AND assigned.binding = 'openai_photo_v1' THEN
        SELECT to_jsonb(pricing) - 'id' INTO price FROM internal.ai_native_token_prices pricing
        WHERE pricing.provider = assigned.provider AND pricing.model = assigned.provider_model
          AND pricing.usage_contract = 'openai_responses_tokens_v1'
          AND pricing.service_tier = 'default' AND pricing.endpoint_profile = 'openai_responses_global_v1'
          AND pricing.input_modality = 'image'
          AND pricing.effective_from <= started AND (pricing.effective_to IS NULL OR pricing.effective_to > started);
        IF price IS NULL THEN RAISE EXCEPTION 'identification_pricing_unavailable' USING ERRCODE = 'P0001'; END IF;
    END IF;

    invocation:=jsonb_populate_record(NULL::internal.identification_invocations,jsonb_build_object(
        'id',gen_random_uuid(),'reservation_id',reserved.id,'attempt_count',reserved.attempt_count,
        'lease_sha256',encode(extensions.digest(p_lease_token::TEXT,'sha256'),'hex'),
        'user_id',p_user_id,'scan_id',reserved.original_analysis_id,'provider',assigned.provider,
        'model',COALESCE(assigned.provider_model,assigned.model),'binding',assigned.binding,
        'input_profile',assigned.input_profile,'effective_plan',assigned.effective_plan,
        'policy_version',assigned.policy_version,'occurred_at',started,'native_price',price,
        'provenance',p_provenance,'event_id',NULL,'is_initial_analysis',initial_dispatch,
        'initial_admission_receipt_id',CASE WHEN initial_dispatch THEN
            (SELECT admission_receipt_id FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id()) END));
    PERFORM internal.attach_initial_dispatch_invocation(invocation);

    IF initial_dispatch OR EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=reserved.original_analysis_id) THEN
        PERFORM internal.finalize_ai_quota_reservation_core(p_reservation_id,p_user_id,p_lease_token,'committed');
    ELSE
        PERFORM public.finalize_ai_quota_reservation(p_reservation_id,p_user_id,p_lease_token,'committed');
    END IF;

    INSERT INTO internal.identification_invocations SELECT (invocation).* RETURNING id INTO invocation_id;
    may_dispatch := TRUE;
    RETURN NEXT;
END;
$function$
;
CREATE FUNCTION internal.initial_dispatch_quota_authorized(p_reservation UUID,p_owner UUID,p_lease UUID,p_final TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE s internal.initial_consuming_staging;
BEGIN
 SELECT * INTO s FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR p_final IS DISTINCT FROM 'committed' OR s.dispatch_invocation IS NULL THEN RETURN FALSE; END IF;
 RETURN internal.initial_dispatch_entry_authorized(p_reservation,p_owner,p_lease,1,s.dispatch_invocation->'provenance');
END;
$body$;
REVOKE ALL ON FUNCTION internal.initial_dispatch_quota_authorized(UUID,UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION internal.finalize_ai_quota_reservation_core(p_reservation_id uuid, p_user_id uuid, p_lease_token uuid, p_final_state text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '5s'
AS $function$
DECLARE
    reservation_row internal.ai_quota_reservations%ROWTYPE;
    quota_now TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();
    IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations r JOIN internal.observation_analysis_intents i ON i.analysis_id=r.original_analysis_id
        WHERE r.id=p_reservation_id AND current_setting('merian.observation_analysis_provider',TRUE) IS DISTINCT FROM i.owner_id::TEXT || ':' || i.analysis_id::TEXT) THEN
        RAISE EXCEPTION 'analysis_history_dispatch_required' USING ERRCODE='55000';
    END IF;


    IF p_reservation_id IS NULL
       OR p_user_id IS NULL
       OR p_lease_token IS NULL
       OR p_final_state IS NULL
       OR p_final_state NOT IN ('committed', 'failed', 'refunded') THEN
        RAISE EXCEPTION 'ai_quota_invalid_finalization'
            USING ERRCODE = '22023';
    END IF;

    SELECT reservations.*
    INTO reservation_row
    FROM internal.ai_quota_reservations AS reservations
    WHERE reservations.id = p_reservation_id
      AND reservations.user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_quota_reservation_not_found'
            USING ERRCODE = 'P0001';
    END IF;

    IF (internal.initial_admitted_settlement_blocked(reservation_row.original_analysis_id)
       OR internal.initial_admitted_settlement_blocked(reservation_row.request_id))
       AND NOT internal.initial_cancellation_quota_authorized(p_reservation_id,p_user_id,p_lease_token,p_final_state)
       AND NOT internal.initial_dispatch_quota_authorized(p_reservation_id,p_user_id,p_lease_token,p_final_state) THEN
        RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000';
    END IF;

    -- Read the wall clock only after the row-lock wait. Otherwise a finalizer
    -- that started before expiry could wait behind cleanup and commit after the
    -- lease boundary using a stale timestamp.
    quota_now := internal.sample_initial_cancellation_quota_clock(p_reservation_id,p_user_id,p_lease_token,p_final_state);
    PERFORM internal.attach_initial_dispatch_quota(p_reservation_id,p_user_id,p_lease_token,p_final_state,quota_now);

    -- A new token is generated for every retry. This fencing check prevents a
    -- delayed commit/refund from an older attempt from mutating the newer
    -- reservation (the classic ABA race).
    IF reservation_row.lease_token <> p_lease_token THEN
        RAISE EXCEPTION 'ai_quota_finalization_conflict'
            USING ERRCODE = 'P0001';
    END IF;

    IF reservation_row.state = p_final_state THEN
        RETURN TRUE;
    END IF;

    IF p_final_state = 'committed' THEN
        IF reservation_row.state <> 'reserved'
           OR reservation_row.lease_expires_at <= quota_now THEN
            RAISE EXCEPTION 'ai_quota_finalization_conflict'
                USING ERRCODE = 'P0001';
        END IF;
        UPDATE internal.ai_quota_reservations AS reservations
        SET
            state = 'committed',
            committed_at = quota_now,
            updated_at = quota_now
        WHERE reservations.id = p_reservation_id;

        -- Committed counters remain consumed, so only their mutable links are
        -- removed.
        DELETE FROM internal.ai_quota_reservation_counters AS links
        WHERE links.reservation_id = p_reservation_id;
    ELSIF p_final_state = 'failed' THEN
        IF reservation_row.state <> 'committed' THEN
            RAISE EXCEPTION 'ai_quota_finalization_conflict'
                USING ERRCODE = 'P0001';
        END IF;
        UPDATE internal.ai_quota_reservations AS reservations
        SET
            state = 'failed',
            failed_at = quota_now,
            updated_at = quota_now
        WHERE reservations.id = p_reservation_id;
    ELSE
        IF reservation_row.state <> 'reserved' THEN
            RAISE EXCEPTION 'ai_quota_finalization_conflict'
                USING ERRCODE = 'P0001';
        END IF;
        PERFORM internal.release_ai_quota_reservation_counters(
            p_reservation_id
        );
        PERFORM internal.begin_initial_cancellation_quota_statement(p_reservation_id,'quota.refund',NULL);
        UPDATE internal.ai_quota_reservations AS reservations
        SET
            state = 'refunded',
            refund_count = reservations.refund_count + 1,
            refunded_at = quota_now,
            updated_at = quota_now
        WHERE reservations.id = p_reservation_id;
        PERFORM internal.end_initial_cancellation_quota_statement(p_reservation_id,'quota.refund');
    END IF;

    RETURN TRUE;
END;
$function$
;
CREATE OR REPLACE FUNCTION internal.guard_initial_invocation_authority()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
 IF TG_OP='TRUNCATE' THEN
  IF EXISTS(SELECT 1 FROM internal.identification_invocations WHERE is_initial_analysis AND NOT internal.initial_invocation_retired(identification_invocations)) THEN
   RAISE EXCEPTION 'initial_analysis_invocation_retained' USING ERRCODE='55000'; END IF;
  RETURN NULL;
 END IF;
 IF TG_OP='DELETE' THEN
  IF OLD.is_initial_analysis AND NOT internal.initial_invocation_retired(OLD) THEN
   RAISE EXCEPTION 'initial_analysis_invocation_retained' USING ERRCODE='55000'; END IF;
  RETURN OLD;
 END IF;
 IF TG_OP='INSERT' THEN
  IF internal.initial_dispatch_expected_member('internal.identification_invocations','INSERT',NULL,to_jsonb(NEW)) THEN RETURN NEW; END IF;
  IF NEW.is_initial_analysis OR NEW.initial_admission_receipt_id IS NOT NULL
    OR EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=NEW.scan_id) THEN
   RAISE EXCEPTION 'initial_analysis_dispatch_unavailable' USING ERRCODE='55000'; END IF;
  RETURN NEW;
 END IF;
 IF internal.initial_invocation_retirement_transition(OLD,NEW) THEN
  PERFORM internal.assert_initial_invocation_retirement(OLD);
  RETURN NEW;
 END IF;
 IF NEW.is_initial_analysis IS DISTINCT FROM OLD.is_initial_analysis
   OR NEW.initial_admission_receipt_id IS DISTINCT FROM OLD.initial_admission_receipt_id THEN
  RAISE EXCEPTION 'initial_analysis_invocation_immutable' USING ERRCODE='55000'; END IF;
 IF OLD.is_initial_analysis THEN
  -- The five-minute reconciler remains invocation-row-first. This exact fast
  -- path performs no receipt, user, lifecycle or other relation lookup/lock.
  IF to_jsonb(NEW)-'event_id' IS DISTINCT FROM to_jsonb(OLD)-'event_id'
    OR (OLD.event_id IS NOT NULL AND NEW.event_id IS DISTINCT FROM OLD.event_id) THEN
   RAISE EXCEPTION 'initial_analysis_invocation_immutable' USING ERRCODE='55000'; END IF;
 END IF;
 RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION internal.guard_initial_preparation_provider_writer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE current_row JSONB:=to_jsonb(NEW); previous_row JSONB; key TEXT; identities UUID[]:=ARRAY[]::UUID[]; identity_changed BOOLEAN:=TG_OP='INSERT';
BEGIN
 IF TG_OP='UPDATE' THEN previous_row:=to_jsonb(OLD); END IF;
 IF TG_OP='UPDATE' AND TG_TABLE_SCHEMA='internal' AND TG_TABLE_NAME='identification_invocations'
   AND internal.initial_invocation_retirement_transition(
     jsonb_populate_record(NULL::internal.identification_invocations,previous_row),
     jsonb_populate_record(NULL::internal.identification_invocations,current_row)) THEN
  PERFORM internal.assert_initial_invocation_retirement(jsonb_populate_record(NULL::internal.identification_invocations,previous_row));
  RETURN NEW;
 END IF;
 -- Existing accounting anonymization can erase owner identity, never grant execution.
 IF TG_OP='UPDATE' AND TG_TABLE_NAME='identification_invocations' AND current_row->'user_id'='null'::JSONB AND current_row-'user_id'=previous_row-'user_id' THEN RETURN NEW; END IF;
 FOREACH key IN ARRAY TG_ARGV LOOP
  identity_changed:=identity_changed OR current_row->key IS DISTINCT FROM previous_row->key;
  identities:=array_append(identities,internal.source_child_uuid(current_row->>key));
  IF previous_row IS NOT NULL THEN identities:=array_append(identities,internal.source_child_uuid(previous_row->>key)); END IF;
 END LOOP;
 -- An existing row already excludes fresh allocation under its durable identity.
 -- Settlement/cleanup that cannot introduce a new identity keeps its old contract.
 IF NOT identity_changed THEN RETURN NEW; END IF;
 -- Preserve existing history ingress error identity even though this earlier
 -- trigger must reject the same stale snapshot before its own barrier lookup.
 IF current_setting('transaction_isolation')<>'read committed'
  AND TG_TABLE_NAME IN ('scans','scan_ingestion_jobs','scan_ingestion_intents','observation_analysis_source_bindings','observation_analysis_intents','observation_analysis_results','observation_histories')
  AND EXISTS(SELECT 1 FROM unnest(identities) u WHERE u IS NOT NULL) THEN RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;

 IF EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging s
  WHERE s.transaction_id=pg_catalog.pg_current_xact_id()
   AND s.stage_token::TEXT=current_setting('merian.initial_admission_stage',TRUE)
   AND internal.initial_admission_expected_write(s.scan_id,TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,TG_OP,previous_row,current_row,FALSE)) THEN
  RETURN NEW;
 END IF;

 IF TG_OP='INSERT' AND TG_TABLE_SCHEMA='internal' AND TG_TABLE_NAME='initial_analysis_results'
  AND internal.initial_result_expected_insert(current_row) THEN RETURN NEW; END IF;
 IF TG_OP='INSERT' AND TG_TABLE_SCHEMA='internal' AND TG_TABLE_NAME='identification_invocations'
  AND internal.initial_dispatch_expected_member('internal.identification_invocations','INSERT',NULL,current_row) THEN RETURN NEW; END IF;
 PERFORM internal.reject_initial_preparation_provider_writer(identities);
 RETURN NEW;
END; $function$
;
CREATE OR REPLACE FUNCTION internal.guard_initial_lifecycle_fence()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW.state='cancelled_pre_dispatch' AND EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id AND canonical_candidate::JSONB->>'variant' IN ('media_sources','client_prepared_photo')) THEN
   PERFORM internal.lock_initial_preparation_scope((SELECT owner_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id),NEW.scan_id);
   PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id FOR UPDATE;
  END IF;

  IF NEW.state='cancelled_pre_dispatch' AND EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id AND canonical_candidate::JSONB->>'variant' IN ('media_sources','client_prepared_photo'))
   AND NOT internal.can_cancel_initial_preparation((SELECT owner_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id),NEW.scan_id) THEN
   RAISE EXCEPTION 'initial_analysis_lifecycle_immutable' USING ERRCODE='22023'; END IF;

  IF NEW.state='cancelled_pre_dispatch' AND EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id)
   AND NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=NEW.scan_id OR request_id=NEW.scan_id)
   AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=NEW.scan_id) THEN RETURN NEW; END IF;

  IF NEW.state='cancelled_unknown' OR (NEW.state='pending_pre_dispatch' AND EXISTS(
   SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=NEW.scan_id)) THEN RETURN NEW; END IF;
 ELSIF TG_OP='UPDATE' THEN
  IF internal.initial_dispatch_expected_member('internal.initial_analysis_lifecycle_fences','UPDATE',to_jsonb(OLD),to_jsonb(NEW)) THEN RETURN NEW; END IF;
  IF OLD.state='pending_pre_dispatch' AND NEW.state='cancelled_pre_dispatch'
   AND internal.initial_admitted_settlement_blocked(OLD.scan_id)
   AND NOT internal.initial_cancellation_lifecycle_authorized(to_jsonb(OLD),to_jsonb(NEW)) THEN
   RAISE EXCEPTION 'initial_analysis_lifecycle_immutable' USING ERRCODE='22023';
  END IF;

  IF NEW.scan_id=OLD.scan_id AND
   ((OLD.state='pending_pre_dispatch' AND NEW.state IN ('cancelled_pre_dispatch','cancelled_unknown'))
    OR (OLD.state='dispatch_authorized' AND NEW.state='cancelled_dispatched')) THEN RETURN NEW; END IF;
 END IF;
 -- No callable or direct initial transition to dispatch_authorized exists.
 RAISE EXCEPTION 'initial_analysis_lifecycle_immutable' USING ERRCODE='22023';
END;
$function$
;
CREATE TRIGGER s0_dispatch_statement_before BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.ai_quota_reservations
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_statement_after AFTER INSERT OR UPDATE OR DELETE ON internal.ai_quota_reservations
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_row_before BEFORE INSERT OR UPDATE OR DELETE ON internal.ai_quota_reservations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_row_after AFTER INSERT OR UPDATE OR DELETE ON internal.ai_quota_reservations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_statement_before BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.ai_quota_reservation_counters
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_statement_after AFTER INSERT OR UPDATE OR DELETE ON internal.ai_quota_reservation_counters
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_row_before BEFORE INSERT OR UPDATE OR DELETE ON internal.ai_quota_reservation_counters
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_row_after AFTER INSERT OR UPDATE OR DELETE ON internal.ai_quota_reservation_counters
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_statement_before BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.identification_invocations
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_statement_after AFTER INSERT OR UPDATE OR DELETE ON internal.identification_invocations
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_row_before BEFORE INSERT OR UPDATE OR DELETE ON internal.identification_invocations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_row_after AFTER INSERT OR UPDATE OR DELETE ON internal.identification_invocations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_statement_before BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.initial_analysis_lifecycle_fences
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_statement_after AFTER INSERT OR UPDATE OR DELETE ON internal.initial_analysis_lifecycle_fences
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_row_before BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_analysis_lifecycle_fences
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE TRIGGER s0_dispatch_row_after AFTER INSERT OR UPDATE OR DELETE ON internal.initial_analysis_lifecycle_fences
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member('dispatch');
CREATE FUNCTION internal.guard_initial_dispatch_counter_freeze()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id()
  AND operation='dispatch' AND dispatch_prestate IS NOT NULL) THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_counter_mutation' USING ERRCODE='55000'; END IF;
 RETURN NULL;
END;
$body$;
REVOKE ALL ON FUNCTION internal.guard_initial_dispatch_counter_freeze() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER s0_dispatch_counter_freeze BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.ai_quota_counters
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_dispatch_counter_freeze();

$s0_statements$;
END;
$s0_migration$;

RESET statement_timeout;
RESET lock_timeout;

-- Inactive completion event vocabulary. No stage or business guard recognizes
-- completion yet. This closed metadata function is not execution authority.
-- Existing dispatch/report/result mechanics and grants remain unchanged.
CREATE FUNCTION internal.initial_completion_event_catalog_v1(
 p_media TEXT,p_funding TEXT,p_species TEXT
) RETURNS JSONB LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE events JSONB:='[]'::JSONB;
BEGIN
 IF p_media IS NULL OR p_media NOT IN ('legacy','cpm')
  OR p_funding IS NULL OR p_funding NOT IN ('none','consumed','paid_release')
  OR p_species IS NULL OR p_species NOT IN ('none','new','existing') THEN
  RAISE EXCEPTION 'initial_completion_event_case_invalid' USING ERRCODE='22023'; END IF;
 IF p_funding<>'none' THEN events:=events||'[{"relation":"internal.complimentary_scan_usage","action":"UPDATE","when":"BEFORE","level":"STATEMENT","slot":"credit.settle"},{"relation":"internal.complimentary_scan_usage","action":"UPDATE","when":"BEFORE","level":"ROW","slot":"credit.settle"},{"relation":"internal.complimentary_scan_usage","action":"UPDATE","when":"AFTER","level":"ROW","slot":"credit.settle"},{"relation":"internal.complimentary_scan_usage","action":"UPDATE","when":"AFTER","level":"STATEMENT","slot":"credit.settle"},{"relation":"public.users","action":"UPDATE","when":"BEFORE","level":"STATEMENT","slot":"credit.epoch"},{"relation":"public.users","action":"UPDATE","when":"BEFORE","level":"ROW","slot":"credit.epoch"},{"relation":"public.users","action":"UPDATE","when":"AFTER","level":"ROW","slot":"credit.epoch"},{"relation":"public.users","action":"UPDATE","when":"AFTER","level":"STATEMENT","slot":"credit.epoch"}]'::JSONB; END IF;
 IF p_media='cpm' THEN events:=events||'[{"relation":"internal.initial_preparation_transfer_receipts","action":"INSERT","when":"BEFORE","level":"STATEMENT","slot":"media.adopt"},{"relation":"internal.initial_preparation_transfer_receipts","action":"INSERT","when":"BEFORE","level":"ROW","slot":"media.adopt"},{"relation":"internal.initial_preparation_transfer_receipts","action":"INSERT","when":"AFTER","level":"ROW","slot":"media.adopt"},{"relation":"internal.initial_preparation_transfer_receipts","action":"INSERT","when":"AFTER","level":"STATEMENT","slot":"media.adopt"}]'::JSONB; END IF;
 events:=events||'[{"relation":"public.scans","action":"INSERT","when":"BEFORE","level":"STATEMENT","slot":"scan.insert"},{"relation":"public.scans","action":"INSERT","when":"BEFORE","level":"ROW","slot":"scan.insert"},{"relation":"public.scan_media_assets","action":"DELETE","when":"BEFORE","level":"STATEMENT","slot":"media.visual.empty"},{"relation":"public.scan_media_assets","action":"DELETE","when":"AFTER","level":"STATEMENT","slot":"media.visual.empty"},{"relation":"public.scan_media_assets","action":"DELETE","when":"BEFORE","level":"STATEMENT","slot":"media.audio.empty"},{"relation":"public.scan_media_assets","action":"DELETE","when":"AFTER","level":"STATEMENT","slot":"media.audio.empty"},{"relation":"public.scans","action":"INSERT","when":"AFTER","level":"ROW","slot":"scan.insert"}]'::JSONB;
 IF p_species='new' THEN events:=events||'[{"relation":"internal.user_species_scan_counts","action":"UPDATE","when":"BEFORE","level":"STATEMENT","slot":"species.increment"},{"relation":"internal.user_species_scan_counts","action":"UPDATE","when":"AFTER","level":"STATEMENT","slot":"species.increment"},{"relation":"public.users","action":"UPDATE","when":"BEFORE","level":"STATEMENT","slot":"species.new_total"},{"relation":"internal.user_species_scan_counts","action":"INSERT","when":"BEFORE","level":"STATEMENT","slot":"species.insert"},{"relation":"internal.user_species_scan_counts","action":"INSERT","when":"BEFORE","level":"ROW","slot":"species.insert"},{"relation":"public.users","action":"UPDATE","when":"BEFORE","level":"ROW","slot":"species.new_total"},{"relation":"internal.user_species_scan_counts","action":"INSERT","when":"AFTER","level":"ROW","slot":"species.insert"},{"relation":"internal.user_species_scan_counts","action":"INSERT","when":"AFTER","level":"STATEMENT","slot":"species.insert"},{"relation":"public.users","action":"UPDATE","when":"AFTER","level":"ROW","slot":"species.new_total"},{"relation":"public.users","action":"UPDATE","when":"AFTER","level":"STATEMENT","slot":"species.new_total"},{"relation":"public.users","action":"UPDATE","when":"BEFORE","level":"STATEMENT","slot":"species.remove_total"},{"relation":"internal.user_species_scan_counts","action":"DELETE","when":"BEFORE","level":"STATEMENT","slot":"species.remove"},{"relation":"internal.user_species_scan_counts","action":"DELETE","when":"AFTER","level":"STATEMENT","slot":"species.remove"},{"relation":"public.users","action":"UPDATE","when":"AFTER","level":"STATEMENT","slot":"species.remove_total"},{"relation":"internal.user_species_scan_counts","action":"UPDATE","when":"BEFORE","level":"STATEMENT","slot":"species.decrement"},{"relation":"internal.user_species_scan_counts","action":"UPDATE","when":"AFTER","level":"STATEMENT","slot":"species.decrement"}]'::JSONB; END IF;
 IF p_species='existing' THEN events:=events||'[{"relation":"internal.user_species_scan_counts","action":"UPDATE","when":"BEFORE","level":"STATEMENT","slot":"species.increment"},{"relation":"internal.user_species_scan_counts","action":"UPDATE","when":"BEFORE","level":"ROW","slot":"species.increment"},{"relation":"internal.user_species_scan_counts","action":"UPDATE","when":"AFTER","level":"ROW","slot":"species.increment"},{"relation":"internal.user_species_scan_counts","action":"UPDATE","when":"AFTER","level":"STATEMENT","slot":"species.increment"},{"relation":"public.users","action":"UPDATE","when":"BEFORE","level":"STATEMENT","slot":"species.new_total"},{"relation":"internal.user_species_scan_counts","action":"INSERT","when":"BEFORE","level":"STATEMENT","slot":"species.insert"},{"relation":"internal.user_species_scan_counts","action":"INSERT","when":"BEFORE","level":"ROW","slot":"species.insert"},{"relation":"internal.user_species_scan_counts","action":"INSERT","when":"AFTER","level":"STATEMENT","slot":"species.insert"},{"relation":"public.users","action":"UPDATE","when":"AFTER","level":"STATEMENT","slot":"species.new_total"},{"relation":"public.users","action":"UPDATE","when":"BEFORE","level":"STATEMENT","slot":"species.remove_total"},{"relation":"internal.user_species_scan_counts","action":"DELETE","when":"BEFORE","level":"STATEMENT","slot":"species.remove"},{"relation":"internal.user_species_scan_counts","action":"DELETE","when":"AFTER","level":"STATEMENT","slot":"species.remove"},{"relation":"public.users","action":"UPDATE","when":"AFTER","level":"STATEMENT","slot":"species.remove_total"},{"relation":"internal.user_species_scan_counts","action":"UPDATE","when":"BEFORE","level":"STATEMENT","slot":"species.decrement"},{"relation":"internal.user_species_scan_counts","action":"UPDATE","when":"AFTER","level":"STATEMENT","slot":"species.decrement"}]'::JSONB; END IF;
 events:=events||'[{"relation":"public.scans","action":"INSERT","when":"AFTER","level":"STATEMENT","slot":"scan.insert"},{"relation":"internal.initial_analysis_completions","action":"INSERT","when":"BEFORE","level":"STATEMENT","slot":"completion.insert"},{"relation":"internal.initial_analysis_completions","action":"INSERT","when":"BEFORE","level":"ROW","slot":"completion.insert"},{"relation":"internal.initial_analysis_completions","action":"INSERT","when":"AFTER","level":"ROW","slot":"completion.insert"},{"relation":"internal.initial_analysis_completions","action":"INSERT","when":"AFTER","level":"STATEMENT","slot":"completion.insert"}]'::JSONB;
 IF jsonb_array_length(events)>64 THEN
  RAISE EXCEPTION 'initial_completion_event_bound_invalid' USING ERRCODE='22023'; END IF;
 RETURN (SELECT jsonb_agg(value||jsonb_build_object('ordinal',ordinality-1) ORDER BY ordinality)
  FROM jsonb_array_elements(events) WITH ORDINALITY);
END; $body$;
REVOKE ALL ON FUNCTION internal.initial_completion_event_catalog_v1(TEXT,TEXT,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

-- Original read-only completion preparation. This produces no stage, settlement,
-- scan, adoption receipt or completion authority. The consuming producer must
-- bind these locked values before any business write.
CREATE FUNCTION internal.prepare_initial_completion_v1(p_owner UUID,p_scan UUID,p_submission TEXT,
 p_result UUID,p_result_digest TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' SET timezone='UTC' AS $body$
DECLARE recovered JSONB; saved internal.initial_analysis_results; submitted internal.initial_analysis_submissions;
 admitted internal.initial_analysis_admissions; receipt internal.initial_preparation_admission_receipts;
 invocation internal.identification_invocations; quota internal.ai_quota_reservations; hold internal.complimentary_scan_usage;
 species RECORD; selected_species JSONB:='null'::JSONB; matches INTEGER:=0; species_count JSONB;
 data JSONB; image public.scans; final_image public.scans; completed TIMESTAMPTZ; capture_time TEXT;
 context JSONB; options JSONB; source_kind TEXT; state_kind TEXT; owner_image JSONB;
BEGIN
 -- Reuses the original result reader's owner/scan, retained receipt, invocation,
 -- cancellation/deletion and exact result/digest checks, without a lease.
 recovered:=internal.read_initial_analysis_result(p_owner,p_scan,p_submission,p_result,p_result_digest);
 IF recovered->>'outcome' IS DISTINCT FROM 'found' THEN
  RAISE EXCEPTION 'initial_completion_result_unavailable' USING ERRCODE='55000'; END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM public.scans WHERE id=p_scan)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
  OR EXISTS(SELECT 1 FROM public.scan_deferred_context_updates WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=p_scan)
  OR EXISTS(SELECT 1 FROM public.field_trip_scan_progress_receipts WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM public.user_field_trip_item_completions WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM public.field_trip_challenge_item_completions WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM public.scan_media_assets WHERE scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_completion_conflict' USING ERRCODE='55000'; END IF;
 SELECT * INTO STRICT saved FROM internal.initial_analysis_results WHERE scan_id=p_scan FOR UPDATE;
 SELECT * INTO STRICT submitted FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
 SELECT * INTO STRICT admitted FROM internal.initial_analysis_admissions WHERE scan_id=p_scan;
 SELECT * INTO STRICT receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
 SELECT * INTO STRICT invocation FROM internal.identification_invocations WHERE scan_id=p_scan;
 SELECT * INTO quota FROM internal.ai_quota_reservations WHERE id=admitted.funding_binding_id FOR UPDATE;
 IF NOT FOUND OR quota.state IS DISTINCT FROM 'committed' OR quota.user_id IS DISTINCT FROM p_owner
  OR quota.request_id IS DISTINCT FROM p_scan OR quota.original_analysis_id IS DISTINCT FROM p_scan
  OR quota.attempt_count IS DISTINCT FROM 1 OR quota.effective_plan IS DISTINCT FROM invocation.effective_plan
  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters WHERE reservation_id=quota.id) THEN
  RAISE EXCEPTION 'initial_completion_funding_conflict' USING ERRCODE='55000'; END IF;
 SELECT * INTO hold FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_scan FOR UPDATE;
 IF (quota.complimentary_client_scan_id IS NULL AND FOUND)
  OR (quota.complimentary_client_scan_id IS NOT NULL AND
    (quota.complimentary_client_scan_id IS DISTINCT FROM p_scan OR NOT FOUND OR hold.state IS DISTINCT FROM 'held')) THEN
  RAISE EXCEPTION 'initial_completion_funding_reconciliation_required' USING ERRCODE='55000'; END IF;
 source_kind:=CASE admitted.binding_version WHEN 3 THEN 'legacy' WHEN 4 THEN 'cpm' END;
 IF source_kind IS NULL THEN RAISE EXCEPTION 'initial_completion_input_unavailable' USING ERRCODE='55000'; END IF;
 -- Retain the established source/capacity/role lock order before projection.
 -- The root hashes are reused by the eventual terminal assertion; they grant
 -- no adoption or ordinary cleanup authority.
 IF admitted.binding_version=4 THEN
  PERFORM internal.lock_initial_cpm_photo_capacity();
  PERFORM scan_id FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan FOR UPDATE;
 END IF;
 PERFORM scan_id FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan FOR UPDATE;
 PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 PERFORM object_id FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
 PERFORM object_id FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=p_scan ORDER BY photo_ordinal,role COLLATE "C" FOR UPDATE;
 IF admitted.binding_version=4 THEN
  PERFORM attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
  PERFORM c.attempt_id FROM internal.initial_cpm_photo_write_closures c JOIN internal.initial_cpm_photo_write_attempts w USING(attempt_id)
   WHERE w.scan_id=p_scan ORDER BY c.attempt_id FOR UPDATE OF c;
 END IF;
 SELECT * INTO receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR receipt.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_completion_input_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM scan_id FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan FOR UPDATE;
 PERFORM object_id FROM internal.initial_preparation_output_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
 PERFORM scan_id FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_media_verifications WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_media_copy_progress WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_media_verification_claims_v2 WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=p_scan FOR UPDATE;
 PERFORM object_id FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 PERFORM internal.initial_admission_retained_receipt(p_owner,p_scan,receipt.admission_receipt_id);
 IF source_kind='legacy' THEN
  PERFORM internal.assert_initial_media_handoff_chain(p_owner,p_scan);
  IF submitted.input_schema_version<>1 THEN RAISE EXCEPTION 'initial_completion_input_unavailable' USING ERRCODE='55000'; END IF;
  context:=submitted.input_snapshot->'context'; options:=submitted.input_snapshot->'options';
  IF options->'preferred_goal' IS DISTINCT FROM 'null'::JSONB THEN
   RAISE EXCEPTION 'initial_completion_preferred_goal_unavailable' USING ERRCODE='55000'; END IF;
 ELSE
  IF submitted.input_schema_version<>2 OR receipt.admission_variant IS DISTINCT FROM 'client_prepared_photo_v1'
   OR EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan) THEN
   RAISE EXCEPTION 'initial_completion_input_unavailable' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_cpm_receipt_cohort(receipt,TRUE);
  context:='{}';options:='{}';
 END IF;
 data:=internal.parse_initial_result_data_v1(internal.initial_canonical(saved.result_snapshot->'data'),
   internal.initial_canonical(saved.provenance_snapshot));
 data:=internal.decode_initial_result_numbers_v1(data,internal.initial_result_schema_v1()->'data');
 IF data->>'scan_id' IS DISTINCT FROM p_scan::TEXT THEN
  RAISE EXCEPTION 'initial_completion_result_conflict' USING ERRCODE='55000'; END IF;
 IF (data->>'is_biological_subject')::BOOLEAN AND NULLIF(data->>'scientific_name','') IS NOT NULL THEN
  FOR species IN SELECT id,scientific_name,iucn_red_list_status FROM public.species_dictionary
    WHERE scientific_name=data->>'scientific_name' ORDER BY id FOR SHARE LOOP
   matches:=matches+1;
   IF matches=1 THEN selected_species:=to_jsonb(species); END IF;
  END LOOP;
  IF matches<>1 THEN selected_species:='null'; END IF;
 END IF;
 IF selected_species<>'null'::JSONB THEN
  SELECT to_jsonb(c) INTO species_count FROM internal.user_species_scan_counts c
   WHERE user_id=p_owner AND species_id=(selected_species->>'id')::UUID FOR UPDATE;
  state_kind:=CASE WHEN FOUND THEN 'existing' ELSE 'new' END;
 ELSE state_kind:='none'; END IF;
 completed:=clock_timestamp();
 image:=jsonb_populate_record(NULL::public.scans,jsonb_build_object(
  'id',p_scan,'user_id',p_owner,'species_id',selected_species->'id',
  'timestamp',completed,'geoprivacy',COALESCE(options->>'geoprivacy','private'),
  'image_storage_urls','[]'::JSONB,'video_storage_urls','[]'::JSONB,'audio_storage_urls','[]'::JSONB,
  'colors',data->'colors','custom_tags','[]'::JSONB,
  'is_offline_queued',FALSE,'is_verified',FALSE,'is_tombstoned',FALSE,'is_flagged',FALSE,
  'user_confirmed_identification',FALSE,'user_review_state','unreviewed','confirmed_species_identity_revision',0,
  'llm_usage_metadata',jsonb_build_object('accounting_contract','identification_invocation_v1'),
  'ai_confidence_score',data->'confidence_score','is_biological_subject',data->'is_biological_subject',
  'is_live_capture',data->'is_live_capture','blur_score',data->'blur_score',
  'ecology_type',CASE WHEN data->>'ecology_type' IN ('wild','urban','domesticated','unknown') THEN data->>'ecology_type' ELSE 'unknown' END,
  'is_invasive',COALESCE((data->>'is_invasive')::BOOLEAN,FALSE),
  'invasive_status_region',data->'invasive_status_region','invasive_rationale',data->'invasive_rationale',
  'invasive_confidence',data->'invasive_confidence','ai_reasoning',data->'ai_reasoning',
  'extracted_visual_traits',data->'extracted_visual_traits','candidates',data->'candidates',
  'image_quality_score',data#>'{image_quality,overall_score}','inference_tier',data->'inference_tier',
  'identification_provenance',data->'identification_provenance','primary_identification',data->'primary_identification',
  'pet_identification',data->'pet_identification','sex',data->'sex','sex_confidence',data->'sex_confidence',
  'sex_evidence',data->'sex_evidence','individual_count',data->'individual_count',
  'ecological_interactions',COALESCE(data->'ecological_interactions','[]'::JSONB),
  -- Do not reconstruct the discarded audio-subject side channel from a name.
  -- Frozen explicit null/absence remains null; the executor must freeze any
  -- intended normalized defaults before the result becomes immutable.
  'life_stage',data->'life_stage','reproductive_condition',data->'reproductive_condition'));
 capture_time:=options->>'timestamp';
 IF capture_time IS NOT NULL THEN
  BEGIN image.timestamp:=capture_time::TIMESTAMPTZ;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
   RAISE EXCEPTION 'initial_completion_capture_time_invalid' USING ERRCODE='22023'; END;
  IF NOT isfinite(image.timestamp) THEN RAISE EXCEPTION 'initial_completion_capture_time_invalid' USING ERRCODE='22023'; END IF;
 END IF;
 image.gps_lat_exact:=(context->>'gps_latitude')::DOUBLE PRECISION;
 image.gps_long_exact:=(context->>'gps_longitude')::DOUBLE PRECISION;
 image.gps_elevation:=(context->>'gps_elevation')::DOUBLE PRECISION;
 image.zoom_factor:=(context->>'zoom_factor')::DOUBLE PRECISION;
 image.weather_temperature_f:=(context->>'weather_temperature_f')::DOUBLE PRECISION;
 image.weather_condition:=context->>'weather_condition';image.semantic_location:=context->>'semantic_location';
 image.device_locale:=context->>'device_locale';image.device_time_zone:=context->>'device_time_zone';
 image.current_month:=(context->>'current_month')::INTEGER;image.time_of_day:=context->>'time_of_day';
 image.depth_scale_text:=context->>'depth_scale_text';image.public_location_label:=options->>'public_location_label';
 image.estimated_size_cm:=COALESCE((context->>'estimated_size_cm')::DOUBLE PRECISION,(data->>'estimated_size_cm')::DOUBLE PRECISION);
 IF image.estimated_size_cm>0 AND image.estimated_size_cm<'Infinity'::DOUBLE PRECISION THEN
  image.estimated_size_cm:=LEAST(image.estimated_size_cm,50000);
 ELSE image.estimated_size_cm:=NULL; END IF;
 final_image:=image;
 final_image.public_location_label:=CASE WHEN image.geoprivacy='private' THEN NULL ELSE
   public.resolve_explore_location_label(image.public_location_label,image.semantic_location) END;
 final_image.gps_lat_public:=public.derive_public_scan_coordinate(image.gps_lat_exact,NULL,image.geoprivacy,NULL,selected_species->>'iucn_red_list_status');
 final_image.gps_long_public:=public.derive_public_scan_coordinate(image.gps_long_exact,NULL,image.geoprivacy,NULL,selected_species->>'iucn_red_list_status');
 final_image.coordinate_uncertainty_in_meters:=CASE
  WHEN image.geoprivacy='private' OR final_image.gps_lat_public IS NULL OR final_image.gps_long_public IS NULL THEN NULL
  WHEN public.is_explore_location_obscured(image.geoprivacy,NULL,selected_species->>'iucn_red_list_status') THEN 10000 ELSE 0 END;
 SELECT jsonb_build_object('id',u.id,'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch,
  'entitlement_version',u.entitlement_version,'total_species_discovered',u.total_species_discovered,
  'other_fields_sha256',encode(extensions.digest(convert_to((to_jsonb(u)-ARRAY['complimentary_entitlement_epoch','entitlement_version','total_species_discovered'])::TEXT,'UTF8'),'sha256'),'hex'))
 INTO owner_image FROM public.users u WHERE u.id=p_owner;
 RETURN jsonb_build_object('version',1,'owner_id',p_owner,'scan_id',p_scan,'media_case',source_kind,'species_case',state_kind,
  'completed_at',completed,'timestamp_basis',CASE WHEN capture_time IS NULL THEN 'completion' ELSE 'capture' END,
  'capture_context',jsonb_build_object('source',CASE source_kind WHEN 'legacy' THEN 'legacy_input_v1' ELSE 'cpm_absent_v1' END,'submission_digest',p_submission),
  'admission_receipt_id',receipt.admission_receipt_id,'admission_receipt_digest',receipt.receipt_digest,
  'admission',to_jsonb(admitted)-'canonical_input','invocation',to_jsonb(invocation),
  'quota',internal.initial_consuming_row_image('internal.ai_quota_reservations',to_jsonb(quota)),
  'hold',CASE WHEN hold.client_scan_id IS NULL THEN 'null'::JSONB ELSE to_jsonb(hold) END,
  'result_evidence_id',p_result,'result_digest',p_result_digest,'result',to_jsonb(saved),
  'owner',owner_image,'species',selected_species,'species_count',species_count,
  'accounting_event',internal.initial_completion_accounting_image_v1(p_owner,p_scan,invocation.id),
  'roots',internal.initial_dispatch_root_images(p_scan),
  'scan_input',to_jsonb(image),'scan_final',to_jsonb(final_image),
  'description_reference',jsonb_build_object('version',1,'input_schema_version',submitted.input_schema_version,
    'ordered_description_digest',admitted.descriptions_digest,'ordered_description_count',jsonb_array_length(submitted.ordered_descriptions)));
END; $body$;
REVOKE ALL ON FUNCTION internal.prepare_initial_completion_v1(UUID,UUID,TEXT,UUID,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

-- Bind the original completion preparation to the existing transaction stage.
-- Consumption remains denied until settlement/suffix attachments, observers and
-- immediate/deferred terminal checks are integrated together.
ALTER TABLE internal.initial_consuming_staging
 DROP CONSTRAINT initial_consuming_staging_operation_check,
 ADD CONSTRAINT initial_consuming_staging_operation_check CHECK(operation IN ('dispatch','report','result','completion')),
 ADD COLUMN completion_prestate JSONB,
 ADD CONSTRAINT initial_consuming_completion_prestate CHECK(
  (operation='completion')=(completion_prestate IS NOT NULL)
  AND (completion_prestate IS NULL OR (jsonb_typeof(completion_prestate)='object' AND octet_length(completion_prestate::TEXT)<=8388608)));

CREATE FUNCTION internal.assert_initial_completion_prestate_v1(p_prestate JSONB)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' SET timezone='UTC' AS $body$
DECLARE expected JSONB; completed TIMESTAMPTZ;
BEGIN
 PERFORM internal.require_service_role();
 IF p_prestate IS NULL OR jsonb_typeof(p_prestate) IS DISTINCT FROM 'object'
  OR octet_length(p_prestate::TEXT)>8388608 THEN
  RAISE EXCEPTION 'initial_completion_prestate_invalid' USING ERRCODE='55000'; END IF;
 -- Validation's clock is only a freshness bound; it never replaces the one
 -- original completion timestamp used by the prepared scan and later receipt.
 completed:=(p_prestate->>'completed_at')::TIMESTAMPTZ;
 IF completed IS NULL OR NOT isfinite(completed) OR completed<transaction_timestamp() OR completed>clock_timestamp()
  OR p_prestate->'completed_at' IS DISTINCT FROM to_jsonb(completed) THEN
  RAISE EXCEPTION 'initial_completion_prestate_invalid' USING ERRCODE='55000'; END IF;
 expected:=internal.prepare_initial_completion_v1((p_prestate->>'owner_id')::UUID,
  (p_prestate->>'scan_id')::UUID,p_prestate#>>'{capture_context,submission_digest}',
  (p_prestate->>'result_evidence_id')::UUID,p_prestate->>'result_digest');
 expected:=jsonb_set(expected,'{completed_at}',to_jsonb(completed));
 IF expected->>'timestamp_basis'='completion' THEN
  expected:=jsonb_set(jsonb_set(expected,'{scan_input,timestamp}',to_jsonb(completed)),
   '{scan_final,timestamp}',to_jsonb(completed));
 END IF;
 IF expected IS DISTINCT FROM p_prestate THEN
  RAISE EXCEPTION 'initial_completion_prestate_invalid' USING ERRCODE='55000'; END IF;
END; $body$;
REVOKE ALL ON FUNCTION internal.assert_initial_completion_prestate_v1(JSONB)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.begin_initial_completion_stage_v1(p_owner UUID,p_scan UUID,p_submission TEXT,
 p_result UUID,p_result_digest TEXT)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' SET timezone='UTC' AS $body$
DECLARE original JSONB;
BEGIN
 PERFORM internal.require_service_role();
 original:=internal.prepare_initial_completion_v1(p_owner,p_scan,p_submission,p_result,p_result_digest);
 INSERT INTO internal.initial_consuming_staging(transaction_id,scan_id,owner_id,operation,
  admission_receipt_id,admission_receipt_digest,reservation_id,invocation_id,expected_writes,completion_prestate)
 VALUES(pg_current_xact_id(),p_scan,p_owner,'completion',
  (original->>'admission_receipt_id')::UUID,original->>'admission_receipt_digest',
  (original#>>'{quota,id}')::UUID,(original#>>'{invocation,id}')::UUID,'[]',original);
END; $body$;
REVOKE ALL ON FUNCTION internal.begin_initial_completion_stage_v1(UUID,UUID,TEXT,UUID,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.guard_initial_consuming_stage()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE immutable_old JSONB; immutable_new JSONB; total INTEGER; count_rows INTEGER; lock_key INTEGER; row_index INTEGER;
BEGIN
 IF TG_OP='TRUNCATE' THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 IF (CASE WHEN TG_OP='DELETE' THEN OLD.transaction_id ELSE NEW.transaction_id END)
     IS DISTINCT FROM pg_catalog.pg_current_xact_id() THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 IF TG_OP='DELETE' THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR NOT OLD.sealed OR OLD.statement_active OR OLD.pending_rows<>'{}'::INTEGER[]
    OR OLD.observed_rows<>'{}'::INTEGER[] OR OLD.next_statement<>jsonb_array_length(OLD.expected_writes) THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_incomplete' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_report_terminal(OLD);
  PERFORM internal.assert_initial_result_terminal(OLD);
  PERFORM internal.assert_initial_dispatch_terminal(OLD);
  RETURN OLD;
 END IF;
 IF TG_OP='INSERT' THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR current_setting('transaction_isolation')<>'read committed'
    OR NEW.next_statement<>0 OR NEW.statement_active OR NEW.pending_rows<>'{}'::INTEGER[]
    OR NEW.observed_rows<>'{}'::INTEGER[] OR NEW.sealed THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
  IF NEW.operation='report' THEN
   PERFORM internal.initial_consuming_row_image('internal.identification_invocations',NEW.report_invocation);
   IF NEW.expected_writes<>'[]'::JSONB OR NEW.report_winner IS NOT NULL OR NEW.report_inserted IS NOT NULL
    OR NEW.report_invocation->>'id' IS DISTINCT FROM NEW.invocation_id::TEXT
    OR NEW.report_invocation->>'user_id' IS DISTINCT FROM NEW.owner_id::TEXT
    OR NEW.report_invocation->>'scan_id' IS DISTINCT FROM NEW.scan_id::TEXT
    OR NEW.report_invocation->>'reservation_id' IS DISTINCT FROM NEW.reservation_id::TEXT
    OR NEW.report_invocation->>'initial_admission_receipt_id' IS DISTINCT FROM NEW.admission_receipt_id::TEXT
    OR NEW.report_invocation->'is_initial_analysis' IS DISTINCT FROM 'true'::JSONB
    OR NEW.report_invocation->'event_id' IS DISTINCT FROM 'null'::JSONB
    OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=NEW.invocation_id) IS DISTINCT FROM NEW.report_invocation THEN
    RAISE EXCEPTION 'initial_analysis_report_stage_invalid' USING ERRCODE='55000'; END IF;
  ELSIF NEW.operation='dispatch' AND NEW.dispatch_prestate IS NOT NULL THEN
   IF NEW.invocation_id IS NOT NULL OR NEW.dispatch_invocation IS NOT NULL OR NEW.expected_writes<>'[]'::JSONB
    OR octet_length(NEW.dispatch_prestate::TEXT)>1048576
    OR NEW.dispatch_prestate IS DISTINCT FROM internal.capture_initial_dispatch_prestate(NEW.owner_id,NEW.scan_id)
    OR NEW.dispatch_prestate->>'admission_receipt_id' IS DISTINCT FROM NEW.admission_receipt_id::TEXT
    OR NEW.dispatch_prestate->>'admission_receipt_digest' IS DISTINCT FROM NEW.admission_receipt_digest
    OR NEW.dispatch_prestate#>>'{quota,id}' IS DISTINCT FROM NEW.reservation_id::TEXT THEN
    RAISE EXCEPTION 'initial_analysis_dispatch_stage_invalid' USING ERRCODE='55000'; END IF;
  ELSIF NEW.operation='completion' THEN
   IF NEW.expected_writes<>'[]'::JSONB OR NEW.result_evidence_id IS NOT NULL
    OR NEW.completion_prestate->>'owner_id' IS DISTINCT FROM NEW.owner_id::TEXT
    OR NEW.completion_prestate->>'scan_id' IS DISTINCT FROM NEW.scan_id::TEXT
    OR NEW.completion_prestate->>'admission_receipt_id' IS DISTINCT FROM NEW.admission_receipt_id::TEXT
    OR NEW.completion_prestate->>'admission_receipt_digest' IS DISTINCT FROM NEW.admission_receipt_digest
    OR NEW.completion_prestate#>>'{quota,id}' IS DISTINCT FROM NEW.reservation_id::TEXT
    OR NEW.completion_prestate#>>'{invocation,id}' IS DISTINCT FROM NEW.invocation_id::TEXT THEN
    RAISE EXCEPTION 'initial_completion_prestate_invalid' USING ERRCODE='55000'; END IF;
   PERFORM internal.assert_initial_completion_prestate_v1(NEW.completion_prestate);
  ELSE
   PERFORM internal.assert_initial_consuming_expectations(NEW.operation,NEW.expected_writes);
   IF NEW.operation='result' AND NEW.result_invocation IS NOT NULL THEN
    PERFORM internal.assert_initial_result_origin(NEW,TRUE);
   END IF;
  END IF;
  -- Denial-only transaction latch survives successful stage removal. A fully
  -- rolled-back subtransaction also rolls back its latch and all SQL effects.
  -- No lock/setting is ever accepted as original authority.
  lock_key:=pg_catalog.hashtext(NEW.transaction_id::TEXT);
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_locks l WHERE l.locktype='advisory' AND l.pid=pg_catalog.pg_backend_pid()
      AND l.classid=1396920143::OID AND l.objid::BIGINT=(lock_key::BIGINT & 4294967295) AND l.objsubid=2 AND l.granted)
    OR NOT pg_catalog.pg_try_advisory_xact_lock(1396920143,lock_key) THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_reused' USING ERRCODE='55000'; END IF;
  RETURN NEW;
 END IF;
 IF OLD.operation='completion' THEN
  -- No mutable event cursor or business-write permission exists in this phase.
  RAISE EXCEPTION 'initial_completion_consumption_unavailable' USING ERRCODE='55000'; END IF;
 IF OLD.operation='dispatch' AND OLD.dispatch_prestate IS NOT NULL AND OLD.expected_writes='[]'::JSONB THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR OLD.statement_active OR OLD.next_statement<>0 OR OLD.sealed
   OR OLD.pending_rows<>'{}'::INTEGER[] OR OLD.observed_rows<>'{}'::INTEGER[]
   OR OLD.dispatch_prestate IS DISTINCT FROM internal.capture_initial_dispatch_prestate(OLD.owner_id,OLD.scan_id) THEN
   RAISE EXCEPTION 'initial_analysis_dispatch_attachment_invalid' USING ERRCODE='55000'; END IF;
  IF OLD.dispatch_invocation IS NULL THEN
   IF OLD.invocation_id IS NOT NULL OR NEW.dispatch_invocation IS NULL OR NEW.invocation_id IS NULL
    OR NEW.dispatch_invocation->>'id' IS DISTINCT FROM NEW.invocation_id::TEXT
    OR to_jsonb(OLD)-ARRAY['invocation_id','dispatch_invocation'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['invocation_id','dispatch_invocation']
    OR internal.initial_dispatch_invocation_matches(OLD.dispatch_prestate,NEW.dispatch_invocation) IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'initial_analysis_dispatch_attachment_invalid' USING ERRCODE='55000'; END IF;
  ELSE
   IF to_jsonb(OLD)-'expected_writes' IS DISTINCT FROM to_jsonb(NEW)-'expected_writes'
    OR NEW.expected_writes IS DISTINCT FROM internal.initial_dispatch_expected_writes(OLD.dispatch_prestate,OLD.dispatch_invocation,
      (NEW.expected_writes#>>'{0,0,new,committed_at}')::TIMESTAMPTZ) THEN
    RAISE EXCEPTION 'initial_analysis_dispatch_attachment_invalid' USING ERRCODE='55000'; END IF;
  END IF;
  RETURN NEW;
 END IF;
 -- Only this one-way attachment may change expected_writes. The writer
 -- supplies its already-prepared row; validation never calls pricing again.
 IF OLD.operation='report' AND OLD.expected_writes='[]'::JSONB THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR OLD.statement_active OR OLD.next_statement<>0 OR OLD.sealed
   OR to_jsonb(OLD)-'expected_writes' IS DISTINCT FROM to_jsonb(NEW)-'expected_writes'
   OR NEW.expected_writes IS DISTINCT FROM internal.initial_report_expected_writes(OLD.report_invocation,NEW.expected_writes#>'{0,0,new}')
   OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=OLD.invocation_id) IS DISTINCT FROM OLD.report_invocation THEN
   RAISE EXCEPTION 'initial_analysis_report_attachment_invalid' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_consuming_expectations('report',NEW.expected_writes);
  RETURN NEW;
 END IF;
 -- One statement-resolution transition binds the actual locked event once.
 IF OLD.operation='report' AND OLD.next_statement=0 AND OLD.statement_active AND NOT NEW.statement_active THEN
  IF pg_catalog.pg_trigger_depth()<>2 OR OLD.report_winner IS NOT NULL OR OLD.report_inserted IS NOT NULL
   OR NEW.report_winner IS NULL OR NEW.report_inserted IS NULL OR NEW.next_statement<>1 OR NEW.sealed
   OR NEW.pending_rows<>'{}'::INTEGER[] OR NEW.observed_rows<>'{}'::INTEGER[]
   OR to_jsonb(OLD)-ARRAY['report_winner','report_inserted','statement_active','next_statement','pending_rows','observed_rows']
     IS DISTINCT FROM to_jsonb(NEW)-ARRAY['report_winner','report_inserted','statement_active','next_statement','pending_rows','observed_rows']
   OR NOT ((OLD.pending_rows='{}'::INTEGER[] AND OLD.observed_rows=ARRAY[0] AND NEW.report_inserted)
     OR (OLD.pending_rows=ARRAY[0] AND OLD.observed_rows='{}'::INTEGER[] AND NOT NEW.report_inserted))
   OR NEW.report_winner->>'source_type' IS DISTINCT FROM 'identification_invocation'
   OR NEW.report_winner->>'operation' IS DISTINCT FROM 'scan_identification'
   OR NEW.report_winner->>'source_id' IS DISTINCT FROM OLD.invocation_id::TEXT
   OR (NEW.report_inserted AND NEW.report_winner IS DISTINCT FROM OLD.expected_writes#>'{0,0,new}')
   OR (NOT NEW.report_inserted AND NEW.report_winner->'id'=OLD.expected_writes#>'{0,0,new,id}')
   OR (SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE id=(NEW.report_winner->>'id')::UUID) IS DISTINCT FROM NEW.report_winner THEN
   RAISE EXCEPTION 'initial_analysis_report_resolution_invalid' USING ERRCODE='55000'; END IF;
  PERFORM internal.initial_consuming_row_image('public.ai_usage_events',NEW.report_winner);
  RETURN NEW;
 END IF;
 immutable_old:=to_jsonb(OLD)-ARRAY['next_statement','statement_active','pending_rows','observed_rows','sealed'];
 immutable_new:=to_jsonb(NEW)-ARRAY['next_statement','statement_active','pending_rows','observed_rows','sealed'];
 IF pg_catalog.pg_trigger_depth()<>2 OR OLD.sealed OR immutable_old IS DISTINCT FROM immutable_new THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 total:=jsonb_array_length(OLD.expected_writes);
 count_rows:=jsonb_array_length(OLD.expected_writes->OLD.next_statement);
 IF NOT OLD.statement_active AND NEW.statement_active THEN
  IF to_jsonb(OLD)-'statement_active' IS DISTINCT FROM to_jsonb(NEW)-'statement_active' THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 ELSIF OLD.statement_active AND NEW.statement_active AND cardinality(NEW.pending_rows)=cardinality(OLD.pending_rows)+1 THEN
  row_index:=NEW.pending_rows[cardinality(NEW.pending_rows)];
  IF row_index IS NULL OR row_index<0 OR row_index>=count_rows OR row_index=ANY(OLD.observed_rows||OLD.pending_rows)
    OR NEW.pending_rows IS DISTINCT FROM OLD.pending_rows||row_index
    OR to_jsonb(OLD)-'pending_rows' IS DISTINCT FROM to_jsonb(NEW)-'pending_rows' THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 ELSIF OLD.statement_active AND NEW.statement_active AND cardinality(NEW.observed_rows)=cardinality(OLD.observed_rows)+1 THEN
  row_index:=NEW.observed_rows[cardinality(NEW.observed_rows)];
  IF row_index IS NULL OR NOT row_index=ANY(OLD.pending_rows) OR NEW.observed_rows IS DISTINCT FROM OLD.observed_rows||row_index
    OR NEW.pending_rows IS DISTINCT FROM array_remove(OLD.pending_rows,row_index)
    OR to_jsonb(OLD)-ARRAY['pending_rows','observed_rows'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['pending_rows','observed_rows'] THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 ELSIF OLD.statement_active AND NOT NEW.statement_active THEN
  IF OLD.pending_rows<>'{}'::INTEGER[] OR cardinality(OLD.observed_rows)<>count_rows
    OR NEW.pending_rows<>'{}'::INTEGER[] OR NEW.observed_rows<>'{}'::INTEGER[] OR NEW.next_statement<>OLD.next_statement+1
    OR NEW.sealed IS DISTINCT FROM (NEW.next_statement=total) THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_incomplete' USING ERRCODE='55000'; END IF;
 ELSE RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000';
 END IF;
 RETURN NEW;
END;
$body$;

-- Completion-only original settlement prefix. The stage cannot be sealed or
-- removed yet, so no partial settlement can commit without full completion.
ALTER TABLE internal.initial_consuming_staging
 ADD COLUMN completion_credit JSONB,
 ADD COLUMN completion_next_event INTEGER NOT NULL DEFAULT 0 CHECK(completion_next_event BETWEEN 0 AND 64),
 ADD CONSTRAINT initial_completion_credit_shape CHECK(
  (operation='completion' OR (completion_credit IS NULL AND completion_next_event=0))
  AND (completion_credit IS NULL OR (jsonb_typeof(completion_credit)='object' AND octet_length(completion_credit::TEXT)<=65536)));

CREATE FUNCTION internal.initial_completion_owner_image_v1(p_row JSONB)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
 SELECT jsonb_build_object('id',p_row->'id','complimentary_entitlement_epoch',p_row->'complimentary_entitlement_epoch',
  'entitlement_version',p_row->'entitlement_version','total_species_discovered',p_row->'total_species_discovered',
  'other_fields_sha256',encode(extensions.digest(convert_to((p_row-ARRAY['complimentary_entitlement_epoch','entitlement_version','total_species_discovered'])::TEXT,'UTF8'),'sha256'),'hex'));
$body$;

CREATE FUNCTION internal.initial_completion_credit_prefix_v1(p_original JSONB,p_clock TIMESTAMPTZ)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' SET timezone='UTC' AS $body$
DECLARE app_user public.users; usage internal.complimentary_scan_usage; hold_image JSONB; owner_image JSONB;
 hold_after JSONB; owner_after JSONB; funding TEXT; events JSONB:='[]'; spec JSONB; before_image JSONB; after_image JSONB;
BEGIN
 IF p_clock IS NULL OR NOT isfinite(p_clock) OR p_clock<transaction_timestamp() OR p_clock>clock_timestamp() THEN
  RAISE EXCEPTION 'initial_completion_credit_invalid' USING ERRCODE='55000'; END IF;
 -- Validate here as well as through the settlement caller: the stage guard
 -- independently recomputes this prefix for every direct attachment attempt.
 -- No prepared credit events may exist before finalized original media.
 IF p_original->>'media_case'='legacy' THEN
  PERFORM internal.assert_initial_transferred_preparation(
   (p_original->>'owner_id')::UUID,(p_original->>'scan_id')::UUID);
 ELSIF p_original->>'media_case'='cpm' THEN
  PERFORM internal.assert_initial_completion_adoption_stage_v1(p_original);
 ELSE
  RAISE EXCEPTION 'initial_completion_adoption_unavailable' USING ERRCODE='55000';
 END IF;
 SELECT * INTO STRICT app_user FROM public.users WHERE id=(p_original->>'owner_id')::UUID;
 SELECT * INTO usage FROM internal.complimentary_scan_usage
  WHERE user_id=app_user.id AND client_scan_id=(p_original->>'scan_id')::UUID;
 hold_image:=CASE WHEN FOUND THEN to_jsonb(usage) ELSE 'null'::JSONB END;
 owner_image:=internal.initial_completion_owner_image_v1(to_jsonb(app_user));
 IF hold_image IS DISTINCT FROM p_original->'hold' OR owner_image IS DISTINCT FROM p_original->'owner'
  OR internal.initial_dispatch_root_images((p_original->>'scan_id')::UUID) IS DISTINCT FROM p_original->'roots' THEN
  RAISE EXCEPTION 'initial_completion_credit_invalid' USING ERRCODE='55000'; END IF;
 owner_after:=owner_image;hold_after:=hold_image;
 IF hold_image='null'::JSONB THEN funding:='none';
 ELSE
  IF usage.state IS DISTINCT FROM 'held' THEN RAISE EXCEPTION 'initial_completion_credit_invalid' USING ERRCODE='55000'; END IF;
  funding:=CASE WHEN app_user.subscription_tier='pro' AND (app_user.subscription_expires_at IS NULL OR app_user.subscription_expires_at>p_clock)
   THEN 'paid_release' ELSE 'consumed' END;
  hold_after:=hold_image||jsonb_build_object('state',CASE funding WHEN 'consumed' THEN 'consumed' ELSE 'released' END,
   'settled_at',p_clock,'updated_at',p_clock,'settlement_reason',CASE funding WHEN 'consumed' THEN 'durable_result_complete' ELSE 'paid_before_completion' END);
  owner_after:=owner_image||jsonb_build_object('complimentary_entitlement_epoch',app_user.complimentary_entitlement_epoch+1,
   'entitlement_version',app_user.entitlement_version+1);
  FOR spec IN SELECT value FROM jsonb_array_elements(internal.initial_completion_event_catalog_v1(
   p_original->>'media_case',funding,p_original->>'species_case')) WHERE (value->>'ordinal')::INTEGER<8 LOOP
   before_image:='null';after_image:='null';
   IF spec->>'level'='ROW' THEN
    before_image:=CASE spec->>'slot' WHEN 'credit.settle' THEN hold_image ELSE owner_image END;
    after_image:=CASE spec->>'slot' WHEN 'credit.settle' THEN hold_after ELSE owner_after END;
   END IF;
   events:=events||jsonb_build_array(spec||jsonb_build_object('old',before_image,'new',after_image));
  END LOOP;
 END IF;
 RETURN jsonb_build_object('clock',p_clock,'case',funding,'hold_after',hold_after,'owner_after',owner_after,'events',events)
  ||CASE WHEN p_original->>'media_case'='cpm' THEN jsonb_build_object('adoption',
   (SELECT completion_adoption FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id())) ELSE '{}'::JSONB END;
END; $body$;

CREATE FUNCTION internal.attach_initial_completion_credit_v1(p_owner UUID,p_scan UUID,p_failure TEXT,p_clock TIMESTAMPTZ)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' SET timezone='UTC' AS $body$
DECLARE stage internal.initial_consuming_staging;
BEGIN
 SELECT * INTO stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR stage.operation<>'completion' THEN RETURN; END IF;
 IF stage.owner_id IS DISTINCT FROM p_owner OR stage.scan_id IS DISTINCT FROM p_scan OR p_failure IS NOT NULL
  OR stage.completion_credit IS NOT NULL OR stage.completion_next_event<>0 OR stage.sealed THEN
  RAISE EXCEPTION 'initial_completion_credit_invalid' USING ERRCODE='55000'; END IF;
 -- The prefix constructor enforces original finalized media both here and in
 -- the independent stage-attachment guard. CPM remains held until adoption
 -- evidence can be bound before this phase.
 UPDATE internal.initial_consuming_staging SET completion_credit=internal.initial_completion_credit_prefix_v1(stage.completion_prestate,p_clock)
  WHERE transaction_id=stage.transaction_id;
END; $body$;

CREATE FUNCTION internal.initial_completion_credit_authorized_v1(p_owner UUID,p_scan UUID,p_failure TEXT)
RETURNS BOOLEAN LANGUAGE SQL VOLATILE SECURITY INVOKER SET search_path='' AS $body$
 SELECT p_failure IS NULL AND EXISTS(SELECT 1 FROM internal.initial_consuming_staging s
  WHERE s.transaction_id=pg_current_xact_id() AND s.operation='completion'
   AND s.owner_id=p_owner AND s.scan_id=p_scan AND NOT s.sealed AND s.completion_next_event=0
   AND s.completion_credit->>'case' IN ('consumed','paid_release')
   AND jsonb_array_length(s.completion_credit->'events')=8);
$body$;

CREATE FUNCTION internal.guard_initial_completion_credit_event_v1()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET timezone='UTC' AS $body$
DECLARE stage internal.initial_consuming_staging; expected JSONB; old_image JSONB:='null'; new_image JSONB:='null'; observed JSONB;
BEGIN
 SELECT * INTO stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR stage.operation<>'completion' THEN
  IF TG_LEVEL='STATEMENT' OR TG_WHEN='AFTER' THEN RETURN NULL; END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
 END IF;
 expected:=stage.completion_credit->'events'->stage.completion_next_event;
 IF stage.sealed OR expected IS NULL THEN RAISE EXCEPTION 'initial_completion_credit_event_invalid' USING ERRCODE='55000'; END IF;
 IF TG_LEVEL='ROW' THEN
  IF TG_OP<>'INSERT' THEN old_image:=to_jsonb(OLD); END IF;
  IF TG_OP<>'DELETE' THEN new_image:=to_jsonb(NEW); END IF;
  IF TG_TABLE_SCHEMA='public' AND TG_TABLE_NAME='users' THEN
   old_image:=internal.initial_completion_owner_image_v1(old_image);
   new_image:=internal.initial_completion_owner_image_v1(new_image);
  END IF;
 END IF;
 observed:=jsonb_build_object('relation',TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,'action',TG_OP,'when',TG_WHEN,'level',TG_LEVEL,
  'slot',expected->'slot','ordinal',stage.completion_next_event,'old',old_image,'new',new_image);
 IF observed IS DISTINCT FROM expected THEN RAISE EXCEPTION 'initial_completion_credit_event_invalid' USING ERRCODE='55000'; END IF;
 UPDATE internal.initial_consuming_staging SET completion_next_event=completion_next_event+1 WHERE transaction_id=stage.transaction_id;
 IF TG_LEVEL='STATEMENT' OR TG_WHEN='AFTER' THEN RETURN NULL; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END; $body$;

CREATE FUNCTION internal.finish_initial_completion_credit_v1(p_owner UUID,p_scan UUID,p_consumed BOOLEAN,p_released BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' SET timezone='UTC' AS $body$
DECLARE stage internal.initial_consuming_staging; actual_hold JSONB; actual_owner JSONB;
BEGIN
 SELECT * INTO stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR stage.operation<>'completion' THEN RETURN; END IF;
 SELECT to_jsonb(u) INTO actual_hold FROM internal.complimentary_scan_usage u WHERE user_id=p_owner AND client_scan_id=p_scan;
 SELECT internal.initial_completion_owner_image_v1(to_jsonb(u)) INTO actual_owner FROM public.users u WHERE id=p_owner;
 IF stage.owner_id IS DISTINCT FROM p_owner OR stage.scan_id IS DISTINCT FROM p_scan OR stage.sealed
  OR stage.completion_credit IS NULL OR stage.completion_next_event<>jsonb_array_length(stage.completion_credit->'events')
  OR COALESCE(actual_hold,'null'::JSONB) IS DISTINCT FROM stage.completion_credit->'hold_after'
  OR actual_owner IS DISTINCT FROM stage.completion_credit->'owner_after'
  OR p_consumed IS DISTINCT FROM (stage.completion_credit->>'case'='consumed')
  OR p_released IS DISTINCT FROM (stage.completion_credit->>'case'='paid_release') THEN
  RAISE EXCEPTION 'initial_completion_credit_incomplete' USING ERRCODE='55000'; END IF;
END; $body$;

REVOKE ALL ON FUNCTION internal.initial_completion_owner_image_v1(JSONB),
 internal.initial_completion_credit_prefix_v1(JSONB,TIMESTAMPTZ),
 internal.attach_initial_completion_credit_v1(UUID,UUID,TEXT,TIMESTAMPTZ),
 internal.initial_completion_credit_authorized_v1(UUID,UUID,TEXT),
 internal.guard_initial_completion_credit_event_v1(),
 internal.finish_initial_completion_credit_v1(UUID,UUID,BOOLEAN,BOOLEAN)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.guard_initial_consuming_stage()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE immutable_old JSONB; immutable_new JSONB; total INTEGER; count_rows INTEGER; lock_key INTEGER; row_index INTEGER;
BEGIN
 IF TG_OP='TRUNCATE' THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 IF (CASE WHEN TG_OP='DELETE' THEN OLD.transaction_id ELSE NEW.transaction_id END)
     IS DISTINCT FROM pg_catalog.pg_current_xact_id() THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 IF TG_OP='DELETE' THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR NOT OLD.sealed OR OLD.statement_active OR OLD.pending_rows<>'{}'::INTEGER[]
    OR OLD.observed_rows<>'{}'::INTEGER[] OR OLD.next_statement<>jsonb_array_length(OLD.expected_writes) THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_incomplete' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_report_terminal(OLD);
  PERFORM internal.assert_initial_result_terminal(OLD);
  PERFORM internal.assert_initial_dispatch_terminal(OLD);
  RETURN OLD;
 END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.completion_credit IS NOT NULL OR NEW.completion_next_event<>0 THEN
   RAISE EXCEPTION 'initial_completion_credit_invalid' USING ERRCODE='55000'; END IF;
  IF pg_catalog.pg_trigger_depth()<>1 OR current_setting('transaction_isolation')<>'read committed'
    OR NEW.next_statement<>0 OR NEW.statement_active OR NEW.pending_rows<>'{}'::INTEGER[]
    OR NEW.observed_rows<>'{}'::INTEGER[] OR NEW.sealed THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
  IF NEW.operation='report' THEN
   PERFORM internal.initial_consuming_row_image('internal.identification_invocations',NEW.report_invocation);
   IF NEW.expected_writes<>'[]'::JSONB OR NEW.report_winner IS NOT NULL OR NEW.report_inserted IS NOT NULL
    OR NEW.report_invocation->>'id' IS DISTINCT FROM NEW.invocation_id::TEXT
    OR NEW.report_invocation->>'user_id' IS DISTINCT FROM NEW.owner_id::TEXT
    OR NEW.report_invocation->>'scan_id' IS DISTINCT FROM NEW.scan_id::TEXT
    OR NEW.report_invocation->>'reservation_id' IS DISTINCT FROM NEW.reservation_id::TEXT
    OR NEW.report_invocation->>'initial_admission_receipt_id' IS DISTINCT FROM NEW.admission_receipt_id::TEXT
    OR NEW.report_invocation->'is_initial_analysis' IS DISTINCT FROM 'true'::JSONB
    OR NEW.report_invocation->'event_id' IS DISTINCT FROM 'null'::JSONB
    OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=NEW.invocation_id) IS DISTINCT FROM NEW.report_invocation THEN
    RAISE EXCEPTION 'initial_analysis_report_stage_invalid' USING ERRCODE='55000'; END IF;
  ELSIF NEW.operation='dispatch' AND NEW.dispatch_prestate IS NOT NULL THEN
   IF NEW.invocation_id IS NOT NULL OR NEW.dispatch_invocation IS NOT NULL OR NEW.expected_writes<>'[]'::JSONB
    OR octet_length(NEW.dispatch_prestate::TEXT)>1048576
    OR NEW.dispatch_prestate IS DISTINCT FROM internal.capture_initial_dispatch_prestate(NEW.owner_id,NEW.scan_id)
    OR NEW.dispatch_prestate->>'admission_receipt_id' IS DISTINCT FROM NEW.admission_receipt_id::TEXT
    OR NEW.dispatch_prestate->>'admission_receipt_digest' IS DISTINCT FROM NEW.admission_receipt_digest
    OR NEW.dispatch_prestate#>>'{quota,id}' IS DISTINCT FROM NEW.reservation_id::TEXT THEN
    RAISE EXCEPTION 'initial_analysis_dispatch_stage_invalid' USING ERRCODE='55000'; END IF;
  ELSIF NEW.operation='completion' THEN
   IF NEW.expected_writes<>'[]'::JSONB OR NEW.result_evidence_id IS NOT NULL
    OR NEW.completion_prestate->>'owner_id' IS DISTINCT FROM NEW.owner_id::TEXT
    OR NEW.completion_prestate->>'scan_id' IS DISTINCT FROM NEW.scan_id::TEXT
    OR NEW.completion_prestate->>'admission_receipt_id' IS DISTINCT FROM NEW.admission_receipt_id::TEXT
    OR NEW.completion_prestate->>'admission_receipt_digest' IS DISTINCT FROM NEW.admission_receipt_digest
    OR NEW.completion_prestate#>>'{quota,id}' IS DISTINCT FROM NEW.reservation_id::TEXT
    OR NEW.completion_prestate#>>'{invocation,id}' IS DISTINCT FROM NEW.invocation_id::TEXT THEN
    RAISE EXCEPTION 'initial_completion_prestate_invalid' USING ERRCODE='55000'; END IF;
   PERFORM internal.assert_initial_completion_prestate_v1(NEW.completion_prestate);
  ELSE
   PERFORM internal.assert_initial_consuming_expectations(NEW.operation,NEW.expected_writes);
   IF NEW.operation='result' AND NEW.result_invocation IS NOT NULL THEN
    PERFORM internal.assert_initial_result_origin(NEW,TRUE);
   END IF;
  END IF;
  -- Denial-only transaction latch survives successful stage removal. A fully
  -- rolled-back subtransaction also rolls back its latch and all SQL effects.
  -- No lock/setting is ever accepted as original authority.
  lock_key:=pg_catalog.hashtext(NEW.transaction_id::TEXT);
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_locks l WHERE l.locktype='advisory' AND l.pid=pg_catalog.pg_backend_pid()
      AND l.classid=1396920143::OID AND l.objid::BIGINT=(lock_key::BIGINT & 4294967295) AND l.objsubid=2 AND l.granted)
    OR NOT pg_catalog.pg_try_advisory_xact_lock(1396920143,lock_key) THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_reused' USING ERRCODE='55000'; END IF;
  RETURN NEW;
 END IF;
 IF OLD.operation='completion' THEN
  IF OLD.completion_credit IS NULL AND NEW.completion_credit IS NOT NULL
   AND pg_catalog.pg_trigger_depth()=1 AND OLD.completion_next_event=0 AND NOT OLD.sealed
   AND to_jsonb(OLD)-'completion_credit' IS NOT DISTINCT FROM to_jsonb(NEW)-'completion_credit'
   AND NEW.completion_credit IS NOT DISTINCT FROM internal.initial_completion_credit_prefix_v1(
     OLD.completion_prestate,(NEW.completion_credit->>'clock')::TIMESTAMPTZ) THEN RETURN NEW; END IF;
  IF OLD.completion_credit IS NOT NULL AND NOT OLD.sealed AND pg_catalog.pg_trigger_depth()=2
   AND OLD.completion_next_event<jsonb_array_length(OLD.completion_credit->'events')
   AND NEW.completion_next_event=OLD.completion_next_event+1
   AND to_jsonb(OLD)-'completion_next_event' IS NOT DISTINCT FROM to_jsonb(NEW)-'completion_next_event' THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'initial_completion_consumption_unavailable' USING ERRCODE='55000'; END IF;
 IF OLD.operation='dispatch' AND OLD.dispatch_prestate IS NOT NULL AND OLD.expected_writes='[]'::JSONB THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR OLD.statement_active OR OLD.next_statement<>0 OR OLD.sealed
   OR OLD.pending_rows<>'{}'::INTEGER[] OR OLD.observed_rows<>'{}'::INTEGER[]
   OR OLD.dispatch_prestate IS DISTINCT FROM internal.capture_initial_dispatch_prestate(OLD.owner_id,OLD.scan_id) THEN
   RAISE EXCEPTION 'initial_analysis_dispatch_attachment_invalid' USING ERRCODE='55000'; END IF;
  IF OLD.dispatch_invocation IS NULL THEN
   IF OLD.invocation_id IS NOT NULL OR NEW.dispatch_invocation IS NULL OR NEW.invocation_id IS NULL
    OR NEW.dispatch_invocation->>'id' IS DISTINCT FROM NEW.invocation_id::TEXT
    OR to_jsonb(OLD)-ARRAY['invocation_id','dispatch_invocation'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['invocation_id','dispatch_invocation']
    OR internal.initial_dispatch_invocation_matches(OLD.dispatch_prestate,NEW.dispatch_invocation) IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'initial_analysis_dispatch_attachment_invalid' USING ERRCODE='55000'; END IF;
  ELSE
   IF to_jsonb(OLD)-'expected_writes' IS DISTINCT FROM to_jsonb(NEW)-'expected_writes'
    OR NEW.expected_writes IS DISTINCT FROM internal.initial_dispatch_expected_writes(OLD.dispatch_prestate,OLD.dispatch_invocation,
      (NEW.expected_writes#>>'{0,0,new,committed_at}')::TIMESTAMPTZ) THEN
    RAISE EXCEPTION 'initial_analysis_dispatch_attachment_invalid' USING ERRCODE='55000'; END IF;
  END IF;
  RETURN NEW;
 END IF;
 -- Only this one-way attachment may change expected_writes. The writer
 -- supplies its already-prepared row; validation never calls pricing again.
 IF OLD.operation='report' AND OLD.expected_writes='[]'::JSONB THEN
  IF pg_catalog.pg_trigger_depth()<>1 OR OLD.statement_active OR OLD.next_statement<>0 OR OLD.sealed
   OR to_jsonb(OLD)-'expected_writes' IS DISTINCT FROM to_jsonb(NEW)-'expected_writes'
   OR NEW.expected_writes IS DISTINCT FROM internal.initial_report_expected_writes(OLD.report_invocation,NEW.expected_writes#>'{0,0,new}')
   OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=OLD.invocation_id) IS DISTINCT FROM OLD.report_invocation THEN
   RAISE EXCEPTION 'initial_analysis_report_attachment_invalid' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_consuming_expectations('report',NEW.expected_writes);
  RETURN NEW;
 END IF;
 -- One statement-resolution transition binds the actual locked event once.
 IF OLD.operation='report' AND OLD.next_statement=0 AND OLD.statement_active AND NOT NEW.statement_active THEN
  IF pg_catalog.pg_trigger_depth()<>2 OR OLD.report_winner IS NOT NULL OR OLD.report_inserted IS NOT NULL
   OR NEW.report_winner IS NULL OR NEW.report_inserted IS NULL OR NEW.next_statement<>1 OR NEW.sealed
   OR NEW.pending_rows<>'{}'::INTEGER[] OR NEW.observed_rows<>'{}'::INTEGER[]
   OR to_jsonb(OLD)-ARRAY['report_winner','report_inserted','statement_active','next_statement','pending_rows','observed_rows']
     IS DISTINCT FROM to_jsonb(NEW)-ARRAY['report_winner','report_inserted','statement_active','next_statement','pending_rows','observed_rows']
   OR NOT ((OLD.pending_rows='{}'::INTEGER[] AND OLD.observed_rows=ARRAY[0] AND NEW.report_inserted)
     OR (OLD.pending_rows=ARRAY[0] AND OLD.observed_rows='{}'::INTEGER[] AND NOT NEW.report_inserted))
   OR NEW.report_winner->>'source_type' IS DISTINCT FROM 'identification_invocation'
   OR NEW.report_winner->>'operation' IS DISTINCT FROM 'scan_identification'
   OR NEW.report_winner->>'source_id' IS DISTINCT FROM OLD.invocation_id::TEXT
   OR (NEW.report_inserted AND NEW.report_winner IS DISTINCT FROM OLD.expected_writes#>'{0,0,new}')
   OR (NOT NEW.report_inserted AND NEW.report_winner->'id'=OLD.expected_writes#>'{0,0,new,id}')
   OR (SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE id=(NEW.report_winner->>'id')::UUID) IS DISTINCT FROM NEW.report_winner THEN
   RAISE EXCEPTION 'initial_analysis_report_resolution_invalid' USING ERRCODE='55000'; END IF;
  PERFORM internal.initial_consuming_row_image('public.ai_usage_events',NEW.report_winner);
  RETURN NEW;
 END IF;
 immutable_old:=to_jsonb(OLD)-ARRAY['next_statement','statement_active','pending_rows','observed_rows','sealed'];
 immutable_new:=to_jsonb(NEW)-ARRAY['next_statement','statement_active','pending_rows','observed_rows','sealed'];
 IF pg_catalog.pg_trigger_depth()<>2 OR OLD.sealed OR immutable_old IS DISTINCT FROM immutable_new THEN
  RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 total:=jsonb_array_length(OLD.expected_writes);
 count_rows:=jsonb_array_length(OLD.expected_writes->OLD.next_statement);
 IF NOT OLD.statement_active AND NEW.statement_active THEN
  IF to_jsonb(OLD)-'statement_active' IS DISTINCT FROM to_jsonb(NEW)-'statement_active' THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 ELSIF OLD.statement_active AND NEW.statement_active AND cardinality(NEW.pending_rows)=cardinality(OLD.pending_rows)+1 THEN
  row_index:=NEW.pending_rows[cardinality(NEW.pending_rows)];
  IF row_index IS NULL OR row_index<0 OR row_index>=count_rows OR row_index=ANY(OLD.observed_rows||OLD.pending_rows)
    OR NEW.pending_rows IS DISTINCT FROM OLD.pending_rows||row_index
    OR to_jsonb(OLD)-'pending_rows' IS DISTINCT FROM to_jsonb(NEW)-'pending_rows' THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 ELSIF OLD.statement_active AND NEW.statement_active AND cardinality(NEW.observed_rows)=cardinality(OLD.observed_rows)+1 THEN
  row_index:=NEW.observed_rows[cardinality(NEW.observed_rows)];
  IF row_index IS NULL OR NOT row_index=ANY(OLD.pending_rows) OR NEW.observed_rows IS DISTINCT FROM OLD.observed_rows||row_index
    OR NEW.pending_rows IS DISTINCT FROM array_remove(OLD.pending_rows,row_index)
    OR to_jsonb(OLD)-ARRAY['pending_rows','observed_rows'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['pending_rows','observed_rows'] THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000'; END IF;
 ELSIF OLD.statement_active AND NOT NEW.statement_active THEN
  IF OLD.pending_rows<>'{}'::INTEGER[] OR cardinality(OLD.observed_rows)<>count_rows
    OR NEW.pending_rows<>'{}'::INTEGER[] OR NEW.observed_rows<>'{}'::INTEGER[] OR NEW.next_statement<>OLD.next_statement+1
    OR NEW.sealed IS DISTINCT FROM (NEW.next_statement=total) THEN
   RAISE EXCEPTION 'initial_analysis_consuming_stage_incomplete' USING ERRCODE='55000'; END IF;
 ELSE RAISE EXCEPTION 'initial_analysis_consuming_stage_invalid' USING ERRCODE='55000';
 END IF;
 RETURN NEW;
END;
$body$;

DO $completion_credit_owner$
DECLARE definition TEXT; original TEXT; replacement TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.settle_complimentary_analysis(uuid,uuid,text)'::REGPROCEDURE);
 original:=$anchor$    settled:=internal.sample_initial_cancellation_credit_clock(p_owner,p_analysis,p_failure);$anchor$;
 replacement:=$replacement$    settled:=internal.sample_initial_cancellation_credit_clock(p_owner,p_analysis,p_failure);
    PERFORM internal.attach_initial_completion_credit_v1(p_owner,p_analysis,p_failure,settled);$replacement$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial completion settlement source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$AND NOT internal.initial_cancellation_credit_authorized(p_owner,p_analysis,p_failure,'settle') THEN$anchor$;
 replacement:=$replacement$AND NOT internal.initial_cancellation_credit_authorized(p_owner,p_analysis,p_failure,'settle')
          AND NOT internal.initial_completion_credit_authorized_v1(p_owner,p_analysis,p_failure) THEN$replacement$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial completion settlement source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$    RETURN jsonb_build_object('credit_consumed',consumed,'credit_released',released);$anchor$;
 replacement:=$replacement$    PERFORM internal.finish_initial_completion_credit_v1(p_owner,p_analysis,consumed,released);
    RETURN jsonb_build_object('credit_consumed',consumed,'credit_released',released);$replacement$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial completion settlement source drift'; END IF;
 definition:=replace(definition,original,replacement);
 EXECUTE definition;
END; $completion_credit_owner$;
CREATE TRIGGER a0000_initial_completion_credit_statement BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.users FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1();
CREATE TRIGGER zzzz_initial_completion_credit_statement AFTER INSERT OR UPDATE OR DELETE ON public.users FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1();
CREATE TRIGGER zzzz_initial_completion_credit_row_before BEFORE INSERT OR UPDATE OR DELETE ON public.users FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1();
CREATE TRIGGER zzzz_initial_completion_credit_row_after AFTER INSERT OR UPDATE OR DELETE ON public.users FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1();
CREATE TRIGGER a0000_initial_completion_credit_statement BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.complimentary_scan_usage FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1();
CREATE TRIGGER zzzz_initial_completion_credit_statement AFTER INSERT OR UPDATE OR DELETE ON internal.complimentary_scan_usage FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1();
CREATE TRIGGER zzzz_initial_completion_credit_row_before BEFORE INSERT OR UPDATE OR DELETE ON internal.complimentary_scan_usage FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1();
CREATE TRIGGER zzzz_initial_completion_credit_row_after AFTER INSERT OR UPDATE OR DELETE ON internal.complimentary_scan_usage FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1();

-- Read-only completion media preparation. This does not attach a completion
-- suffix, grant tickets, settle funding or enable a scan/adoption write.
CREATE FUNCTION internal.initial_completion_legacy_media_image_v1(
 p_owner UUID,p_scan UUID,p_roots JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE admitted internal.initial_preparation_admission_receipts;
 transfer internal.initial_preparation_transfer_receipts; input JSONB; mapping JSONB;
 owner_item JSONB; source_item JSONB; mapped JSONB; chosen JSONB; poster JSONB;
 result JSONB; items JSONB:='[]'; source_index INTEGER; frame_source_index INTEGER;
BEGIN
 PERFORM internal.assert_initial_transferred_preparation(p_owner,p_scan);
 SELECT * INTO STRICT admitted FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
 SELECT * INTO STRICT transfer FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan;
 input:=admitted.input::JSONB;mapping:=admitted.mapping::JSONB;
 -- Owner timeline order is authoritative. Frames and companion audio belong
 -- to their video owner and must not become extra History media items.
 FOR owner_item IN SELECT value FROM jsonb_array_elements(input->'owner_timeline') LOOP
  IF owner_item->>'kind'<>'media' THEN CONTINUE; END IF;
  source_index:=(owner_item->>'index')::INTEGER;
  source_item:=input->'media'->source_index;
  mapped:=mapping->'items'->source_index;
  IF (mapped->>'index')::INTEGER IS DISTINCT FROM source_index THEN
   RAISE EXCEPTION 'initial_completion_media_unavailable' USING ERRCODE='55000'; END IF;
  chosen:=CASE WHEN source_item->>'kind'='video' OR mapped->'prepared'='null'::JSONB
    THEN mapped->'source' ELSE mapped->'prepared' END;
  poster:=NULL;
  IF source_item->>'kind'='video' THEN
   -- First original frame in source order, regardless of inference selection.
   SELECT (ordinality-1)::INTEGER INTO frame_source_index
    FROM jsonb_array_elements(input->'media') WITH ORDINALITY AS f(value,ordinality)
    WHERE value->>'kind'='image' AND value->'clip_index'=source_item->'clip_index'
    ORDER BY ordinality LIMIT 1;
   IF FOUND THEN
    poster:=mapping->'items'->frame_source_index;
    poster:=CASE WHEN poster->'prepared'='null'::JSONB THEN poster->'source' ELSE poster->'prepared' END;
   END IF;
  END IF;
  items:=items||jsonb_build_array(jsonb_build_object(
   'ordinal',jsonb_array_length(items),'kind',source_item->'kind',
   'media_id',(chosen->>'destination_object_id')::UUID,
   'content_type',chosen#>'{bytes,content_type}','byte_count',chosen#>'{bytes,byte_count}',
   'sha256',chosen#>'{bytes,sha256}','poster_media_id',(poster->>'destination_object_id')::UUID));
 END LOOP;
 result:=jsonb_build_object('kind','legacy_transfer_v1','receipt_digest',transfer.receipt_digest,'items',items);
 IF jsonb_array_length(items) NOT BETWEEN 1 AND 64
  OR octet_length(result::TEXT)>65536 OR octet_length(internal.initial_canonical(result))>65536
  OR internal.initial_dispatch_root_images(p_scan) IS DISTINCT FROM p_roots THEN
  RAISE EXCEPTION 'initial_completion_media_unavailable' USING ERRCODE='55000'; END IF;
 RETURN result;
END; $body$;
REVOKE ALL ON FUNCTION internal.initial_completion_legacy_media_image_v1(UUID,UUID,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.prepare_initial_completion_legacy_media_v1(
 p_owner UUID,p_scan UUID,p_submission TEXT,p_result UUID,p_result_digest TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE original JSONB;
BEGIN
 original:=internal.prepare_initial_completion_v1(p_owner,p_scan,p_submission,p_result,p_result_digest);
 IF original->>'media_case' IS DISTINCT FROM 'legacy' THEN
  RAISE EXCEPTION 'initial_completion_media_unavailable' USING ERRCODE='55000'; END IF;
 RETURN internal.initial_completion_legacy_media_image_v1(p_owner,p_scan,original->'roots');
END; $body$;
REVOKE ALL ON FUNCTION internal.prepare_initial_completion_legacy_media_v1(UUID,UUID,TEXT,UUID,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

-- Closed completion-tail image composition. Inputs must later come from the
-- original-bound stage and its once-prepared completion row. This pure helper
-- is not attachment authority and enables no business guard or stage removal.
CREATE FUNCTION internal.initial_completion_tail_images_v1(
 p_original JSONB,p_credit JSONB,p_completion JSONB)
RETURNS JSONB LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE events JSONB:='[]'; spec JSONB; before_image JSONB; after_image JSONB;
 owner_before JSONB; owner_after JSONB; count_before JSONB; count_after JSONB;
 attempted_insert JSONB:='null'; funding TEXT; species_case TEXT; prefix_length INTEGER;
BEGIN
 funding:=p_credit->>'case';species_case:=p_original->>'species_case';
 IF p_original->>'media_case' IS NULL OR p_original->>'media_case' NOT IN ('legacy','cpm')
  OR funding IS NULL OR funding NOT IN ('none','consumed','paid_release')
  OR species_case IS NULL OR species_case NOT IN ('none','new','existing')
  OR p_original#>>'{scan_final,id}' IS DISTINCT FROM p_original->>'scan_id'
  OR p_original#>>'{scan_final,user_id}' IS DISTINCT FROM p_original->>'owner_id'
  OR p_credit#>>'{owner_after,id}' IS DISTINCT FROM p_original->>'owner_id'
  OR p_original->>'owner_id' IS NULL OR p_original->>'scan_id' IS NULL
  OR p_completion->>'scan_id' IS DISTINCT FROM p_original->>'scan_id'
  OR p_completion->>'owner_id' IS DISTINCT FROM p_original->>'owner_id'
  OR p_completion->>'result_evidence_id' IS DISTINCT FROM p_original->>'result_evidence_id'
  OR p_original->>'result_evidence_id' IS NULL
  OR p_completion->'receipt_version' IS DISTINCT FROM '1'::JSONB
  OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_completion) key)
   IS DISTINCT FROM ARRAY['completion_projection_snapshot','owner_id','receipt_snapshot','receipt_version','result_evidence_id','scan_id']::TEXT[]
  OR jsonb_typeof(p_completion->'receipt_snapshot') IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_completion->'completion_projection_snapshot') IS DISTINCT FROM 'object'
  OR octet_length((p_completion->'receipt_snapshot')::TEXT)>16384
  OR octet_length((p_completion->'completion_projection_snapshot')::TEXT)>65536 THEN
  RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
 -- A CPM event image must carry its own closed adoption row. A legacy
 -- credit prefix cannot manufacture an empty media.adopt event.
 IF p_original->>'media_case'='cpm' THEN
  IF jsonb_typeof(p_credit->'adoption') IS DISTINCT FROM 'object' THEN
   RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_credit->'adoption') key)
    IS DISTINCT FROM ARRAY['owner_id','receipt','receipt_digest','scan_id']::TEXT[]
   OR p_credit#>>'{adoption,owner_id}' IS DISTINCT FROM p_original->>'owner_id'
   OR p_credit#>>'{adoption,scan_id}' IS DISTINCT FROM p_original->>'scan_id'
   OR NOT internal.initial_cpm_adoption_shape_v1((p_original->>'owner_id')::UUID,(p_original->>'scan_id')::UUID,
    p_credit#>>'{adoption,receipt}',p_credit#>>'{adoption,receipt_digest}') THEN
   RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
  IF (p_credit#>>'{adoption,receipt}')::JSONB->>'result_evidence_id' IS DISTINCT FROM p_original->>'result_evidence_id' THEN
   RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
 END IF;
 prefix_length:=CASE WHEN funding='none' THEN 0 ELSE 8 END;
 IF jsonb_array_length(p_credit->'events') IS DISTINCT FROM prefix_length THEN
  RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
 owner_before:=p_credit->'owner_after';owner_after:=owner_before;
 count_before:=COALESCE(p_original->'species_count','null'::JSONB);count_after:=count_before;
 IF species_case='none' THEN
  IF p_original->'species' IS DISTINCT FROM 'null'::JSONB OR count_before<>'null'::JSONB THEN
   RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
 ELSE
  IF p_original#>>'{species,id}' IS NULL
   OR p_original#>>'{scan_final,species_id}' IS DISTINCT FROM p_original#>>'{species,id}' THEN
   RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
  attempted_insert:=jsonb_build_object('user_id',p_original->'owner_id',
   'species_id',p_original#>'{species,id}','scan_count',1);
  IF species_case='new' THEN
   IF count_before<>'null'::JSONB THEN RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
   count_after:=attempted_insert;
   owner_after:=jsonb_set(owner_before,'{total_species_discovered}',
    to_jsonb((owner_before->>'total_species_discovered')::INTEGER+1));
  ELSE
   IF count_before->>'user_id' IS DISTINCT FROM p_original->>'owner_id'
    OR count_before->>'species_id' IS DISTINCT FROM p_original#>>'{species,id}'
    OR (count_before->>'scan_count')::BIGINT IS NULL OR (count_before->>'scan_count')::BIGINT<1 THEN
    RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
   count_after:=jsonb_set(count_before,'{scan_count}',to_jsonb((count_before->>'scan_count')::BIGINT+1));
  END IF;
 END IF;
 FOR spec IN SELECT value FROM jsonb_array_elements(
  internal.initial_completion_event_catalog_v1(p_original->>'media_case',funding,species_case))
  WHERE (value->>'ordinal')::INTEGER>=prefix_length LOOP
  before_image:='null';after_image:='null';
  IF spec->>'level'='ROW' THEN
   CASE spec->>'slot'
    WHEN 'media.adopt' THEN after_image:=p_credit->'adoption';
    WHEN 'scan.insert' THEN after_image:=p_original->'scan_final';
    WHEN 'species.increment' THEN before_image:=count_before;after_image:=count_after;
    WHEN 'species.insert' THEN after_image:=attempted_insert;
    WHEN 'species.new_total' THEN before_image:=owner_before;after_image:=owner_after;
    WHEN 'completion.insert' THEN after_image:=p_completion;
    ELSE RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023';
   END CASE;
  END IF;
  events:=events||jsonb_build_array(spec||jsonb_build_object('old',before_image,'new',after_image));
 END LOOP;
 -- The attempted ON CONFLICT row is distinct from the actual winner. The
 -- eventual observer must compare the locked winner at INSERT AFTER STATEMENT.
 RETURN jsonb_build_object('events',events,'owner_after',owner_after,
  'species_after',count_after,'attempted_species_insert',attempted_insert,
  'scan_after',p_original->'scan_final','completion_after',p_completion)
  ||CASE WHEN p_original->>'media_case'='cpm' THEN jsonb_build_object('adoption_after',p_credit->'adoption') ELSE '{}'::JSONB END;
END; $body$;
REVOKE ALL ON FUNCTION internal.initial_completion_tail_images_v1(JSONB,JSONB,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;

-- The stage guard, rather than its caller, prepares the suffix. This samples
-- the existing entitlement resolver once after original settlement; validation
-- never re-resolves a potentially changed rollout snapshot. Still no scan or
-- completion write, seal, removal or API grant is authorized by this phase.
ALTER TABLE internal.initial_consuming_staging
 ADD COLUMN completion_prepared BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN completion_suffix JSONB,
 ADD CONSTRAINT initial_completion_suffix_shape CHECK(
  completion_prepared=(completion_suffix IS NOT NULL)
  AND (operation='completion' OR NOT completion_prepared)
  AND (completion_suffix IS NULL OR (jsonb_typeof(completion_suffix)='object'
   AND octet_length(completion_suffix::TEXT)<=8388608)));

CREATE FUNCTION internal.prepare_initial_completion_suffix_v1(p_stage internal.initial_consuming_staging)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' SET timezone='UTC' AS $body$
DECLARE original JSONB:=p_stage.completion_prestate; credit JSONB:=p_stage.completion_credit;
 submitted internal.initial_analysis_submissions; entitlement JSONB; media JSONB;
 projection JSONB; receipt JSONB; completion JSONB; species JSONB; result JSONB;
 outcome TEXT; member TEXT;
BEGIN
 IF p_stage.transaction_id IS DISTINCT FROM pg_current_xact_id() OR p_stage.operation IS DISTINCT FROM 'completion'
  OR p_stage.sealed OR p_stage.completion_prepared OR p_stage.completion_suffix IS NOT NULL
  OR credit IS NULL OR original->>'media_case' IS NULL OR original->>'media_case' NOT IN ('legacy','cpm')
  OR p_stage.completion_next_event IS DISTINCT FROM jsonb_array_length(credit->'events')
  OR (SELECT to_jsonb(s) FROM internal.initial_consuming_staging s WHERE transaction_id=p_stage.transaction_id)
    IS DISTINCT FROM to_jsonb(p_stage) THEN
  RAISE EXCEPTION 'initial_completion_suffix_invalid' USING ERRCODE='55000'; END IF;
 PERFORM internal.finish_initial_completion_credit_v1(p_stage.owner_id,p_stage.scan_id,
  credit->>'case'='consumed',credit->>'case'='paid_release');
 IF internal.initial_dispatch_root_images(p_stage.scan_id) IS DISTINCT FROM original->'roots'
  OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=p_stage.invocation_id)
    IS DISTINCT FROM original->'invocation'
  OR (SELECT internal.initial_consuming_row_image('internal.ai_quota_reservations',to_jsonb(q))
    FROM internal.ai_quota_reservations q WHERE id=p_stage.reservation_id) IS DISTINCT FROM original->'quota'
  OR (SELECT to_jsonb(r) FROM internal.initial_analysis_results r WHERE scan_id=p_stage.scan_id)
    IS DISTINCT FROM original->'result'
  OR (SELECT to_jsonb(a)-'canonical_input' FROM internal.initial_analysis_admissions a WHERE scan_id=p_stage.scan_id)
    IS DISTINCT FROM original->'admission'
  OR COALESCE((SELECT to_jsonb(c) FROM internal.user_species_scan_counts c
    WHERE user_id=p_stage.owner_id AND species_id=(original#>>'{species,id}')::UUID),'null'::JSONB)
    IS DISTINCT FROM COALESCE(original->'species_count','null'::JSONB)
  OR COALESCE((SELECT jsonb_build_object('id',d.id,'scientific_name',d.scientific_name,'iucn_red_list_status',d.iucn_red_list_status)
    FROM public.species_dictionary d WHERE id=(original#>>'{species,id}')::UUID),'null'::JSONB)
    IS DISTINCT FROM original->'species'
  OR EXISTS(SELECT 1 FROM public.scans WHERE id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_stage.scan_id) THEN
  RAISE EXCEPTION 'initial_completion_suffix_invalid' USING ERRCODE='55000'; END IF;
 SELECT * INTO STRICT submitted FROM internal.initial_analysis_submissions WHERE scan_id=p_stage.scan_id;
 IF original->>'media_case'='cpm' THEN
  IF p_stage.completion_adoption IS NULL OR credit->'adoption' IS DISTINCT FROM p_stage.completion_adoption THEN
   RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_cpm_adoption_fresh_v1(p_stage.completion_adoption);
  media:=internal.initial_cpm_completion_media_v1(p_stage.completion_adoption);
 ELSE
  media:=internal.initial_completion_legacy_media_image_v1(p_stage.owner_id,p_stage.scan_id,original->'roots');
 END IF;
 SELECT to_jsonb(e) INTO STRICT entitlement FROM internal.resolve_effective_entitlement(p_stage.owner_id) e;
 IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(entitlement) key)
   IS DISTINCT FROM ARRAY['current_plan','current_tier','entitlement_version','in_flight_count','is_paid','scans_available_to_start','scans_remaining']::TEXT[]
  OR entitlement->>'current_plan' IS NULL OR entitlement->>'current_plan' NOT IN ('free','pro_trial','pro_paid','pro_complimentary')
  OR entitlement->>'current_tier' IS NULL OR entitlement->>'current_tier' NOT IN ('free','pro')
  OR jsonb_typeof(entitlement->'is_paid') IS DISTINCT FROM 'boolean' THEN
  RAISE EXCEPTION 'initial_completion_entitlement_invalid' USING ERRCODE='55000'; END IF;
 FOREACH member IN ARRAY ARRAY['scans_remaining','scans_available_to_start','in_flight_count','entitlement_version'] LOOP
  IF jsonb_typeof(entitlement->member) IS DISTINCT FROM 'number'
   OR (entitlement->>member)::NUMERIC<>trunc((entitlement->>member)::NUMERIC)
   OR (entitlement->>member)::NUMERIC NOT BETWEEN (CASE WHEN member='entitlement_version' THEN 1 ELSE 0 END)
     AND (CASE WHEN member IN ('scans_remaining','scans_available_to_start') THEN 3 ELSE 9007199254740991 END) THEN
   RAISE EXCEPTION 'initial_completion_entitlement_invalid' USING ERRCODE='55000'; END IF;
 END LOOP;
 outcome:=CASE credit->>'case' WHEN 'none' THEN 'none' WHEN 'consumed' THEN 'consumed_durable_result'
  WHEN 'paid_release' THEN 'released_paid_before_completion' END;
 IF outcome IS NULL THEN RAISE EXCEPTION 'initial_completion_suffix_invalid' USING ERRCODE='55000'; END IF;
 species:=CASE WHEN original->'species'='null'::JSONB THEN 'null'::JSONB ELSE
  jsonb_build_object('species_id',original#>'{species,id}','scientific_name',original#>'{species,scientific_name}') END;
 projection:=jsonb_build_object('version',1,'completed_at',original->'completed_at',
  'scan_id',p_stage.scan_id,'owner_id',p_stage.owner_id,'result_evidence_id',original->'result_evidence_id',
  'result_digest',original->'result_digest','plan_used',original#>'{invocation,effective_plan}',
  'settlement',jsonb_build_object('outcome',outcome,'settled_at',credit#>'{hold_after,settled_at}'),
  'credit_consumed',credit->>'case'='consumed','entitlement_after',entitlement,'species_association',species,
  'scan_timestamp',original#>'{scan_final,timestamp}','timestamp_basis',original->'timestamp_basis',
  'geoprivacy',original#>'{scan_final,geoprivacy}','capture_context',original->'capture_context','media',media);
 receipt:=jsonb_build_object('version',1,'owner_id',p_stage.owner_id,'operation_id',p_stage.scan_id,
  'scan_id',p_stage.scan_id,'route',submitted.route,'submission_digest',original#>'{admission,submission_digest}',
  'input_schema_version',submitted.input_schema_version,'config_digest',original#>'{admission,configuration_digest}',
  'funding_binding_id',original#>'{admission,funding_binding_id}',
  'funding_binding_digest',original#>'{admission,funding_digest}',
  'funding_binding_version',submitted.funding_snapshot->'version',
  'result_evidence_id',original->'result_evidence_id','result_digest',original->'result_digest',
  'result_schema_version',original#>'{result,result_schema_version}',
  'ordered_description_digest',original#>'{description_reference,ordered_description_digest}',
  'ordered_description_count',original#>'{description_reference,ordered_description_count}',
  'finalized_media_binding_digest',media->'receipt_digest',
  'completion_projection_digest',encode(extensions.digest(convert_to(
   'merian.initial-analysis.completion-projection.v1'||chr(10)||internal.initial_canonical(projection),'UTF8'),'sha256'),'hex'));
 IF octet_length(projection::TEXT)>65536 OR octet_length(internal.initial_canonical(projection))>65536
  OR octet_length(receipt::TEXT)>16384 OR octet_length(internal.initial_canonical(receipt))>16384
  OR receipt->'funding_binding_version' IS DISTINCT FROM '1'::JSONB
  OR receipt->'result_schema_version' IS DISTINCT FROM '1'::JSONB THEN
  RAISE EXCEPTION 'initial_completion_suffix_invalid' USING ERRCODE='55000'; END IF;
 completion:=jsonb_build_object('scan_id',p_stage.scan_id,'owner_id',p_stage.owner_id,
  'result_evidence_id',original->'result_evidence_id','receipt_version',1,
  'receipt_snapshot',receipt,'completion_projection_snapshot',projection);
 result:=internal.initial_completion_tail_images_v1(original,credit,completion);
 RETURN result;
END; $body$;
REVOKE ALL ON FUNCTION internal.prepare_initial_completion_suffix_v1(internal.initial_consuming_staging)
 FROM PUBLIC,anon,authenticated,service_role;

DO $completion_suffix_guard$
DECLARE definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.guard_initial_consuming_stage()'::REGPROCEDURE);
 anchor:=$anchor$ IF TG_OP='INSERT' THEN$anchor$;
 replacement:=$replacement$ IF TG_OP='INSERT' THEN
  IF NEW.completion_prepared OR NEW.completion_suffix IS NOT NULL THEN
   RAISE EXCEPTION 'initial_completion_suffix_invalid' USING ERRCODE='55000'; END IF;$replacement$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'initial completion suffix guard source drift'; END IF;
 definition:=replace(definition,anchor,replacement);
 anchor:=$anchor$ IF OLD.operation='completion' THEN$anchor$;
 replacement:=$replacement$ IF OLD.operation='completion' THEN
  IF NOT OLD.completion_prepared AND NEW.completion_prepared
   AND OLD.completion_suffix IS NULL AND NEW.completion_suffix IS NULL
   AND pg_catalog.pg_trigger_depth()=1 AND NOT OLD.sealed
   AND to_jsonb(OLD)-'completion_prepared' IS NOT DISTINCT FROM to_jsonb(NEW)-'completion_prepared' THEN
   NEW.completion_suffix:=internal.prepare_initial_completion_suffix_v1(OLD);
   RETURN NEW;
  END IF;$replacement$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'initial completion suffix guard source drift'; END IF;
 EXECUTE replace(definition,anchor,replacement);
END; $completion_suffix_guard$;

-- Private legacy completion integration. Ordinary API grants remain closed.
-- A preexisting completion without this projection is a migration conflict,
-- never permission to retrofit a newly calculated historical snapshot.
ALTER TABLE internal.initial_analysis_completions
 ADD COLUMN completion_projection_snapshot JSONB NOT NULL
 CHECK(jsonb_typeof(completion_projection_snapshot)='object'
  AND octet_length(completion_projection_snapshot::TEXT)<=65536
  AND octet_length(internal.initial_canonical(completion_projection_snapshot))<=65536);

CREATE FUNCTION internal.initial_completion_accounting_image_v1(p_owner UUID,p_scan UUID,p_invocation UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE event public.ai_usage_events; result JSONB:='null'; count_rows INTEGER:=0;
BEGIN
 -- Invocation is already locked before this event lock, preserving accounting
 -- order. Keep only a bounded digest in the stage, never copied metadata.
 FOR event IN SELECT * FROM public.ai_usage_events
  WHERE scan_id=p_scan OR (source_type='identification_invocation' AND source_id=p_invocation)
  ORDER BY id FOR SHARE LOOP
  count_rows:=count_rows+1;
  IF count_rows<>1 OR event.user_id IS DISTINCT FROM p_owner OR event.scan_id IS DISTINCT FROM p_scan
   OR event.source_type IS DISTINCT FROM 'identification_invocation' OR event.source_id IS DISTINCT FROM p_invocation
   OR event.operation IS DISTINCT FROM 'scan_identification' THEN
   RAISE EXCEPTION 'initial_completion_accounting_conflict' USING ERRCODE='55000'; END IF;
  result:=jsonb_build_object('id',event.id,'sha256',encode(extensions.digest(convert_to(
   internal.initial_consuming_row_image('public.ai_usage_events',to_jsonb(event))::TEXT,'UTF8'),'sha256'),'hex'));
 END LOOP;
 RETURN result;
END; $body$;

CREATE FUNCTION internal.initial_completion_current_event_v1(p_stage internal.initial_consuming_staging)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
 SELECT CASE WHEN p_stage.completion_next_event<jsonb_array_length(p_stage.completion_credit->'events')
  THEN p_stage.completion_credit->'events'->p_stage.completion_next_event
  WHEN p_stage.completion_prepared THEN p_stage.completion_suffix->'events'->
   (p_stage.completion_next_event-jsonb_array_length(p_stage.completion_credit->'events')) END;
$body$;

CREATE FUNCTION internal.initial_completion_expected_insert_v1(p_relation TEXT,p_row JSONB,p_after BOOLEAN DEFAULT FALSE)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE stage internal.initial_consuming_staging; event JSONB;
BEGIN
 SELECT * INTO stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR stage.operation IS DISTINCT FROM 'completion' OR stage.sealed
  OR NOT stage.completion_prepared OR stage.completion_prestate->>'media_case' NOT IN ('legacy','cpm') THEN RETURN FALSE; END IF;
 event:=internal.initial_completion_current_event_v1(stage);
 IF p_relation='internal.initial_preparation_transfer_receipts' AND stage.completion_prestate->>'media_case'='cpm' THEN
  RETURN pg_trigger_depth()=1 AND event->>'slot'='media.adopt'
   AND event->>'when'=CASE WHEN p_after THEN 'AFTER' ELSE 'BEFORE' END AND event->>'level'='ROW'
   AND p_row IS NOT DISTINCT FROM stage.completion_adoption
   AND p_row IS NOT DISTINCT FROM stage.completion_suffix->'adoption_after';
 ELSIF p_relation='public.scans' THEN
  IF p_after THEN
   -- AFTER-row scientific copy owners precede the existing empty media
   -- refresh. No row mutation or legacy job write is authorized here.
   RETURN pg_trigger_depth()=1 AND p_row IS NOT DISTINCT FROM stage.completion_suffix->'scan_after'
    AND event->>'slot'='media.visual.empty' AND event->>'when'='BEFORE' AND event->>'level'='STATEMENT';
  END IF;
  RETURN pg_trigger_depth()=1 AND event->>'slot'='scan.insert'
   AND event->>'when'='BEFORE' AND event->>'level'='ROW'
   AND p_row IS NOT DISTINCT FROM stage.completion_prestate->'scan_input';
 ELSIF p_relation='internal.initial_analysis_completions' AND NOT p_after THEN
  RETURN pg_trigger_depth()=1 AND event->>'slot'='completion.insert'
   AND event->>'when'='BEFORE' AND event->>'level'='ROW'
   AND p_row IS NOT DISTINCT FROM stage.completion_suffix->'completion_after';
 END IF;
 RETURN FALSE;
END; $body$;

-- Permanent classification only skips obsolete normal-ingestion backups. All
-- existing scientific, review, ownership and deletion guards still execute.
CREATE FUNCTION internal.initial_completed_scan_v1(p_owner UUID,p_scan UUID)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY INVOKER SET search_path='' AS $body$
 SELECT p_owner IS NOT NULL AND p_scan IS NOT NULL AND EXISTS(
  SELECT 1 FROM internal.initial_analysis_completions c
  JOIN internal.initial_analysis_results r USING(scan_id,owner_id,result_evidence_id)
  WHERE c.scan_id=p_scan AND c.owner_id=p_owner AND c.receipt_version=1
   AND c.receipt_snapshot->>'scan_id'=p_scan::TEXT AND c.receipt_snapshot->>'owner_id'=p_owner::TEXT
   AND c.receipt_snapshot->>'result_evidence_id'=r.result_evidence_id::TEXT
   AND c.receipt_snapshot->>'result_digest'=encode(extensions.digest(convert_to(
    'merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex')
   AND c.receipt_snapshot->>'completion_projection_digest'=encode(extensions.digest(convert_to(
    'merian.initial-analysis.completion-projection.v1'||chr(10)||internal.initial_canonical(c.completion_projection_snapshot),'UTF8'),'sha256'),'hex'));
$body$;

CREATE FUNCTION internal.assert_initial_completion_terminal_v1(p_stage internal.initial_consuming_staging)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' SET timezone='UTC' AS $body$
DECLARE original JSONB:=p_stage.completion_prestate; tail JSONB:=p_stage.completion_suffix;
 credit JSONB:=p_stage.completion_credit; roots JSONB; hold_image JSONB;
BEGIN
 IF p_stage.operation IS DISTINCT FROM 'completion' THEN RETURN; END IF;
 IF NOT p_stage.sealed OR NOT p_stage.completion_prepared OR tail IS NULL OR credit IS NULL
  OR p_stage.completion_next_event IS DISTINCT FROM jsonb_array_length(credit->'events')+jsonb_array_length(tail->'events')
  OR p_stage.statement_active OR p_stage.expected_writes<>'[]'::JSONB OR p_stage.next_statement<>0
  OR p_stage.pending_rows<>'{}'::INTEGER[] OR p_stage.observed_rows<>'{}'::INTEGER[]
  OR tail IS DISTINCT FROM internal.initial_completion_tail_images_v1(original,credit,tail->'completion_after')
  OR (SELECT to_jsonb(s) FROM public.scans s WHERE id=p_stage.scan_id) IS DISTINCT FROM tail->'scan_after'
  OR (SELECT to_jsonb(c) FROM internal.initial_analysis_completions c WHERE scan_id=p_stage.scan_id) IS DISTINCT FROM tail->'completion_after'
  OR (SELECT internal.initial_completion_owner_image_v1(to_jsonb(u)) FROM public.users u WHERE id=p_stage.owner_id)
    IS DISTINCT FROM tail->'owner_after'
  OR COALESCE((SELECT to_jsonb(c) FROM internal.user_species_scan_counts c WHERE user_id=p_stage.owner_id
    AND species_id=(original#>>'{species,id}')::UUID),'null'::JSONB) IS DISTINCT FROM tail->'species_after'
  OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=p_stage.invocation_id) IS DISTINCT FROM original->'invocation'
  OR (SELECT count(*) FROM internal.identification_invocations WHERE scan_id=p_stage.scan_id OR reservation_id=p_stage.reservation_id)<>1
  OR internal.initial_completion_accounting_image_v1(p_stage.owner_id,p_stage.scan_id,p_stage.invocation_id)
    IS DISTINCT FROM original->'accounting_event'
  OR (SELECT internal.initial_consuming_row_image('internal.ai_quota_reservations',to_jsonb(q))
    FROM internal.ai_quota_reservations q WHERE id=p_stage.reservation_id) IS DISTINCT FROM original->'quota'
  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters WHERE reservation_id=p_stage.reservation_id)
  OR (SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_stage.scan_id) IS DISTINCT FROM 'dispatch_authorized'
  OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_stage.owner_id AND status IN ('pending','storage_pending','auth_pending'))
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM public.scan_deferred_context_updates WHERE scan_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM public.field_trip_scan_progress_receipts WHERE scan_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM public.user_field_trip_item_completions WHERE scan_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM public.field_trip_challenge_item_completions WHERE scan_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM public.scan_media_assets WHERE scan_id=p_stage.scan_id)
  OR internal.initial_completed_scan_v1(p_stage.owner_id,p_stage.scan_id) IS DISTINCT FROM TRUE THEN
  RAISE EXCEPTION 'initial_completion_incomplete' USING ERRCODE='55000'; END IF;
 roots:=internal.initial_dispatch_root_images(p_stage.scan_id);
 IF (roots-ARRAY['internal.initial_analysis_completions']-CASE WHEN original->>'media_case'='cpm' THEN ARRAY['internal.initial_preparation_transfer_receipts'] ELSE '{}'::TEXT[] END)
  IS DISTINCT FROM ((original->'roots')-ARRAY['internal.initial_analysis_completions']-CASE WHEN original->>'media_case'='cpm' THEN ARRAY['internal.initial_preparation_transfer_receipts'] ELSE '{}'::TEXT[] END)
  OR (SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id=p_stage.scan_id)
    <>(CASE WHEN credit->'hold_after'='null'::JSONB THEN 0 ELSE 1 END) THEN
  RAISE EXCEPTION 'initial_completion_incomplete' USING ERRCODE='55000'; END IF;
 SELECT to_jsonb(h) INTO hold_image FROM internal.complimentary_scan_usage h WHERE user_id=p_stage.owner_id AND client_scan_id=p_stage.scan_id;
 IF COALESCE(hold_image,'null'::JSONB) IS DISTINCT FROM credit->'hold_after' THEN
  RAISE EXCEPTION 'initial_completion_incomplete' USING ERRCODE='55000'; END IF;
 IF original->>'media_case'='cpm' THEN
  IF (SELECT to_jsonb(t) FROM internal.initial_preparation_transfer_receipts t WHERE scan_id=p_stage.scan_id) IS DISTINCT FROM tail->'adoption_after'
   OR p_stage.completion_adoption IS DISTINCT FROM tail->'adoption_after' THEN
   RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_cpm_completed_v1(p_stage.owner_id,p_stage.scan_id);
 ELSE
  PERFORM internal.assert_initial_transferred_preparation(p_stage.owner_id,p_stage.scan_id);
 END IF;
END; $body$;

-- Extend the existing exact observer, including its original credit prefix.
CREATE OR REPLACE FUNCTION internal.guard_initial_completion_credit_event_v1()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET timezone='UTC' AS $body$
DECLARE stage internal.initial_consuming_staging; expected JSONB; old_image JSONB:='null'; new_image JSONB:='null'; observed JSONB; winner JSONB;
BEGIN
 SELECT * INTO stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR stage.operation<>'completion' THEN
  IF TG_LEVEL='STATEMENT' OR TG_WHEN='AFTER' THEN RETURN NULL; END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
 END IF;
 expected:=internal.initial_completion_current_event_v1(stage);
 IF stage.sealed OR expected IS NULL OR pg_trigger_depth()<>(CASE
   WHEN expected->>'slot' LIKE 'species.%' OR expected->>'slot' IN ('media.visual.empty','media.audio.empty') THEN 2 ELSE 1 END) THEN
  RAISE EXCEPTION 'initial_completion_credit_event_invalid' USING ERRCODE='55000'; END IF;
 IF TG_LEVEL='ROW' THEN
  IF TG_OP<>'INSERT' THEN old_image:=to_jsonb(OLD); END IF;
  IF TG_OP<>'DELETE' THEN new_image:=to_jsonb(NEW); END IF;
  IF TG_TABLE_SCHEMA='public' AND TG_TABLE_NAME='users' THEN
   old_image:=internal.initial_completion_owner_image_v1(old_image);new_image:=internal.initial_completion_owner_image_v1(new_image);
  END IF;
 END IF;
 observed:=jsonb_build_object('relation',TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,'action',TG_OP,'when',TG_WHEN,'level',TG_LEVEL,
  'slot',expected->'slot','ordinal',stage.completion_next_event,'old',old_image,'new',new_image);
 IF observed IS DISTINCT FROM expected THEN RAISE EXCEPTION 'initial_completion_credit_event_invalid' USING ERRCODE='55000'; END IF;
 IF expected->>'slot'='species.insert' AND TG_WHEN='AFTER' AND TG_LEVEL='STATEMENT' THEN
  SELECT to_jsonb(c) INTO winner FROM internal.user_species_scan_counts c WHERE user_id=stage.owner_id
   AND species_id=(stage.completion_prestate#>>'{species,id}')::UUID FOR UPDATE;
  IF NOT FOUND OR winner IS DISTINCT FROM stage.completion_suffix->'species_after' THEN
   RAISE EXCEPTION 'initial_completion_species_winner_invalid' USING ERRCODE='55000'; END IF;
 END IF;
 UPDATE internal.initial_consuming_staging SET completion_next_event=completion_next_event+1 WHERE transaction_id=stage.transaction_id;
 IF TG_LEVEL='STATEMENT' OR TG_WHEN='AFTER' THEN RETURN NULL; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END; $body$;

DO $completion_observers$
DECLARE relation_name TEXT;
BEGIN
 FOREACH relation_name IN ARRAY ARRAY['public.scans','public.scan_media_assets',
  'internal.user_species_scan_counts','internal.initial_analysis_completions'] LOOP
  EXECUTE format('CREATE TRIGGER a0000_initial_completion_statement BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1()',relation_name);
  EXECUTE format('CREATE TRIGGER zzzzzz_initial_completion_statement AFTER INSERT OR UPDATE OR DELETE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1()',relation_name);
  EXECUTE format('CREATE TRIGGER zzzzzz_initial_completion_row_before BEFORE INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1()',relation_name);
  EXECUTE format('CREATE TRIGGER zzzzzz_initial_completion_row_after AFTER INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1()',relation_name);
 END LOOP;
END; $completion_observers$;

DO $completion_integrated_guards$
DECLARE definition TEXT; anchor TEXT; replacement TEXT; routine TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.guard_initial_consuming_stage()'::REGPROCEDURE);
 anchor:=$anchor$  IF OLD.completion_credit IS NOT NULL AND NOT OLD.sealed AND pg_catalog.pg_trigger_depth()=2
   AND OLD.completion_next_event<jsonb_array_length(OLD.completion_credit->'events')
   AND NEW.completion_next_event=OLD.completion_next_event+1
   AND to_jsonb(OLD)-'completion_next_event' IS NOT DISTINCT FROM to_jsonb(NEW)-'completion_next_event' THEN RETURN NEW; END IF;$anchor$;
 replacement:=$replacement$  IF OLD.completion_credit IS NOT NULL AND NOT OLD.sealed
   AND internal.initial_completion_current_event_v1(OLD) IS NOT NULL
   AND pg_trigger_depth()=(CASE WHEN internal.initial_completion_current_event_v1(OLD)->>'slot' LIKE 'species.%'
      OR internal.initial_completion_current_event_v1(OLD)->>'slot' IN ('media.visual.empty','media.audio.empty') THEN 3 ELSE 2 END)
   AND NEW.completion_next_event=OLD.completion_next_event+1
   AND to_jsonb(OLD)-'completion_next_event' IS NOT DISTINCT FROM to_jsonb(NEW)-'completion_next_event' THEN RETURN NEW; END IF;
  IF NOT OLD.sealed AND NEW.sealed AND pg_trigger_depth()=1
   AND to_jsonb(OLD)-'sealed' IS NOT DISTINCT FROM to_jsonb(NEW)-'sealed' THEN
   PERFORM internal.assert_initial_completion_terminal_v1(NEW); RETURN NEW; END IF;$replacement$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'completion stage source drift'; END IF;
 definition:=replace(definition,anchor,replacement);
 anchor:='  PERFORM internal.assert_initial_dispatch_terminal(OLD);';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'completion terminal source drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||chr(10)||'  PERFORM internal.assert_initial_completion_terminal_v1(OLD);');
 definition:=pg_get_functiondef('internal.require_complete_initial_consuming_stage()'::REGPROCEDURE);
 anchor:='  PERFORM internal.assert_initial_dispatch_terminal(captured);';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'completion deferred source drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||chr(10)||'  PERFORM internal.assert_initial_completion_terminal_v1(captured);');

 definition:=pg_get_functiondef('internal.guard_initial_preparation_provider_writer()'::REGPROCEDURE);
 anchor:=' PERFORM internal.reject_initial_preparation_provider_writer(identities);';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'completion provider source drift'; END IF;
 EXECUTE replace(definition,anchor,$replacement$ IF TG_OP='INSERT'
  AND ((TG_TABLE_SCHEMA='public' AND TG_TABLE_NAME='scans') OR (TG_TABLE_SCHEMA='internal' AND TG_TABLE_NAME='initial_analysis_completions'))
  AND internal.initial_completion_expected_insert_v1(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,current_row) THEN RETURN NEW; END IF;
$replacement$||anchor);
 definition:=pg_get_functiondef('internal.guard_initial_analysis_storage()'::REGPROCEDURE);
 anchor:='    IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled) THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'completion storage source drift'; END IF;
 EXECUTE replace(definition,anchor,$replacement$    IF TG_OP='INSERT' AND TG_TABLE_NAME='initial_analysis_completions'
      AND internal.initial_completion_expected_insert_v1('internal.initial_analysis_completions',to_jsonb(NEW)) THEN RETURN NEW; END IF;
$replacement$||anchor);
 FOREACH routine IN ARRAY ARRAY['guard_scan_ai_identification_review','guard_scan_verified_species_review'] LOOP
  definition:=pg_get_functiondef(('internal.'||routine||'()')::REGPROCEDURE);
  anchor:=E'BEGIN\n';
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'completion review source drift'; END IF;
  EXECUTE replace(definition,anchor,anchor||$replacement$    IF TG_OP='INSERT' AND internal.initial_completion_expected_insert_v1('public.scans',to_jsonb(NEW)) THEN RETURN NEW; END IF;
$replacement$);
 END LOOP;
 FOREACH routine IN ARRAY ARRAY['copy_scan_ai_identification_review','copy_scan_identification_provenance','copy_scan_verified_species_review'] LOOP
  definition:=pg_get_functiondef(('internal.'||routine||'()')::REGPROCEDURE);anchor:=E'BEGIN\n';
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'completion copy source drift'; END IF;
  EXECUTE replace(definition,anchor,anchor||$replacement$    IF TG_OP='INSERT' AND internal.initial_completion_expected_insert_v1('public.scans',to_jsonb(NEW),TRUE) THEN RETURN NULL; END IF;
    IF TG_OP='DELETE' THEN
      IF internal.initial_completed_scan_v1(OLD.user_id,OLD.id) THEN RETURN NULL; END IF;
    ELSIF TG_OP='UPDATE' THEN
      IF internal.initial_completed_scan_v1(OLD.user_id,OLD.id) THEN RETURN NULL; END IF;
    END IF;
$replacement$);
 END LOOP;
END; $completion_integrated_guards$;

-- Later legacy review retains the existing review owners and revision checks.
-- A completion-backed scan is authoritative without a second ingestion job.
DO $completion_review_owners$
DECLARE definition TEXT; first_anchor TEXT; last_anchor TEXT; start_at INTEGER; end_at INTEGER; original_block TEXT;
BEGIN
 definition:=pg_get_functiondef('public.apply_scan_identification_review(UUID,UUID,INTEGER,UUID,TEXT,TEXT,JSONB,INTEGER,UUID,INTEGER)'::REGPROCEDURE);
 first_anchor:='    -- Older saved observations may predate the ingestion ledger.';
 last_anchor:='    digest := pg_catalog.MD5(';
 IF (length(definition)-length(replace(definition,first_anchor,'')))/length(first_anchor)<>1
  OR (length(definition)-length(replace(definition,last_anchor,'')))/length(last_anchor)<>1 THEN
  RAISE EXCEPTION 'completion identification review source drift'; END IF;
 start_at:=strpos(definition,first_anchor);end_at:=strpos(definition,last_anchor);
 IF end_at<=start_at THEN RAISE EXCEPTION 'completion identification review source order'; END IF;
 original_block:=substring(definition FROM start_at FOR end_at-start_at);
 EXECUTE replace(definition,original_block,
  E'    IF internal.initial_completed_scan_v1(p_user_id,p_scan_id) THEN\n        saved:=scan.ai_identification_review;\n    ELSE\n'
  ||original_block||E'    END IF;\n');

 definition:=pg_get_functiondef('public.apply_verified_scan_species_review(UUID,UUID,INTEGER,TEXT,TEXT,JSONB)'::REGPROCEDURE);
 first_anchor:='    SELECT * INTO backup FROM public.scan_ingestion_jobs WHERE scan_id = p_scan_id::TEXT AND user_id = p_user_id FOR UPDATE;';
 last_anchor:='    IF scan.confirmed_species_identity_revision NOT IN';
 IF (length(definition)-length(replace(definition,first_anchor,'')))/length(first_anchor)<>1
  OR (length(definition)-length(replace(definition,last_anchor,'')))/length(last_anchor)<>1 THEN
  RAISE EXCEPTION 'completion verified review source drift'; END IF;
 start_at:=strpos(definition,first_anchor);end_at:=strpos(definition,last_anchor);
 IF end_at<=start_at THEN RAISE EXCEPTION 'completion verified review source order'; END IF;
 original_block:=substring(definition FROM start_at FOR end_at-start_at);
 EXECUTE replace(definition,original_block,
  E'    IF NOT internal.initial_completed_scan_v1(p_user_id,p_scan_id) THEN\n'||original_block||E'    END IF;\n');
END; $completion_review_owners$;

-- Completed initial scans already settled their original funding. Deletion
-- must not enter the legacy failure/settlement owner, which correctly refuses
-- initial operations. Capture classification under the existing owner/scan
-- locks before tombstone cleanup can erase the completion association.
DO $completion_scan_deletion_owner$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('public.request_scan_deletion(UUID,UUID)'::REGPROCEDURE);
 anchor:=E'    tombstone_owner UUID;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'completion deletion declaration drift'; END IF;
 definition:=replace(definition,anchor,anchor||E'\n    initial_completed BOOLEAN:=FALSE;');
 anchor:=E'    INSERT INTO internal.scan_deletion_tombstones (';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'completion deletion classification drift'; END IF;
 definition:=replace(definition,anchor,$replacement$    -- A committed initial deletion request may already have erased result
    -- and completion evidence while the physical scan deletion is pending.
    -- Its same-owner tombstone is the durable authorization for exact replay.
    IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan_id) THEN
        SELECT user_id INTO tombstone_owner FROM internal.scan_deletion_tombstones
        WHERE scan_id=p_scan_id FOR UPDATE;
        IF FOUND THEN
            IF tombstone_owner IS DISTINCT FROM p_user_id THEN RETURN 'forbidden'; END IF;
            RETURN 'accepted';
        END IF;
    END IF;
    initial_completed:=internal.initial_completed_scan_v1(p_user_id,p_scan_id);

$replacement$||anchor);
 anchor:=E'    PERFORM public.fail_scan_ingestion_terminal(';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'completion deletion failure owner drift'; END IF;
 definition:=replace(definition,anchor,E'    IF NOT initial_completed THEN\n'||anchor);
 anchor:=E'    RETURN ''accepted'';\nEND;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'completion deletion return drift'; END IF;
 EXECUTE replace(definition,anchor,E'    END IF;\n\n'||anchor);
END; $completion_scan_deletion_owner$;

CREATE FUNCTION internal.complete_initial_analysis_legacy_v1(p_owner UUID,p_scan UUID,p_submission TEXT,p_result UUID,p_result_digest TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' SET timezone='UTC' AS $body$
DECLARE recovered JSONB; saved internal.initial_analysis_completions; stage internal.initial_consuming_staging;
 scan_row public.scans; completion_row internal.initial_analysis_completions;
BEGIN
 -- Replay takes original owner/deletion locks and validates exact retained
 -- result before any fresh funding preparation; later user choices are kept.
 recovered:=internal.read_initial_analysis_result(p_owner,p_scan,p_submission,p_result,p_result_digest);
 IF recovered->>'outcome' IS DISTINCT FROM 'found' THEN RAISE EXCEPTION 'initial_completion_result_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_completions WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND THEN
  IF saved.owner_id IS DISTINCT FROM p_owner OR saved.result_evidence_id IS DISTINCT FROM p_result
   OR saved.receipt_snapshot->>'submission_digest' IS DISTINCT FROM p_submission
   OR saved.receipt_snapshot->>'result_digest' IS DISTINCT FROM p_result_digest
   OR internal.initial_completed_scan_v1(p_owner,p_scan) IS DISTINCT FROM TRUE
   OR NOT EXISTS(SELECT 1 FROM public.scans WHERE id=p_scan AND user_id=p_owner AND NOT is_tombstoned) THEN
   RAISE EXCEPTION 'initial_completion_conflict' USING ERRCODE='55000'; END IF;
  IF saved.completion_projection_snapshot#>>'{media,kind}'='cpm_adoption_v1' THEN
   PERFORM internal.assert_initial_cpm_completed_v1(p_owner,p_scan);
  END IF;
  RETURN jsonb_build_object('version',1,'outcome','replay','receipt',saved.receipt_snapshot,'projection',saved.completion_projection_snapshot);
 END IF;
 PERFORM internal.begin_initial_completion_stage_v1(p_owner,p_scan,p_submission,p_result,p_result_digest);
 PERFORM internal.settle_complimentary_analysis(p_owner,p_scan,NULL);
 UPDATE internal.initial_consuming_staging SET completion_prepared=TRUE WHERE transaction_id=pg_current_xact_id();
 SELECT * INTO STRICT stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 scan_row:=jsonb_populate_record(NULL::public.scans,stage.completion_prestate->'scan_input');
 INSERT INTO public.scans SELECT scan_row.*;
 completion_row:=jsonb_populate_record(NULL::internal.initial_analysis_completions,stage.completion_suffix->'completion_after');
 INSERT INTO internal.initial_analysis_completions SELECT completion_row.*;
 UPDATE internal.initial_consuming_staging SET sealed=TRUE WHERE transaction_id=stage.transaction_id;
 SELECT * INTO STRICT stage FROM internal.initial_consuming_staging WHERE transaction_id=stage.transaction_id;
 PERFORM internal.assert_initial_completion_terminal_v1(stage);
 DELETE FROM internal.initial_consuming_staging WHERE transaction_id=stage.transaction_id;
 RETURN jsonb_build_object('version',1,'outcome','fresh','receipt',completion_row.receipt_snapshot,'projection',completion_row.completion_projection_snapshot);
END; $body$;
REVOKE ALL ON FUNCTION internal.initial_completion_current_event_v1(internal.initial_consuming_staging),
 internal.initial_completion_accounting_image_v1(UUID,UUID,UUID),
 internal.initial_completion_expected_insert_v1(TEXT,JSONB,BOOLEAN),internal.initial_completed_scan_v1(UUID,UUID),
 internal.assert_initial_completion_terminal_v1(internal.initial_consuming_staging),
 internal.complete_initial_analysis_legacy_v1(UUID,UUID,TEXT,UUID,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

-- Terminal retention qualification is distinct from upload observation and
-- the pre-admission verifier. No entries, API grants or adoption writes are
-- installed here. The existing transfer receipt remains the ownership record.
CREATE TABLE internal.initial_cpm_photo_retention_policies(
 digest TEXT PRIMARY KEY CHECK(digest ~ '^[0-9a-f]{64}$'),
 write_policy_digest TEXT NOT NULL REFERENCES internal.initial_cpm_photo_write_policies(digest),
 retention_build_digest TEXT NOT NULL CHECK(retention_build_digest ~ '^[0-9a-f]{64}$'),
 qualification_evidence_digest TEXT NOT NULL CHECK(qualification_evidence_digest ~ '^[0-9a-f]{64}$'),
 reviewed_revision TEXT NOT NULL CHECK(reviewed_revision ~ '^[0-9a-f]{40}$'),
 protocol TEXT NOT NULL CHECK(protocol='cpm_in_place_adoption_v1'),
 verification_max_duration_ms INTEGER NOT NULL CHECK(verification_max_duration_ms BETWEEN 1 AND 150000),
 verification_max_age_ms INTEGER NOT NULL CHECK(verification_max_age_ms BETWEEN 1 AND 30000),
 clock_skew_ms INTEGER NOT NULL CHECK(clock_skew_ms BETWEEN 0 AND 1000),
 state TEXT NOT NULL CHECK(state IN ('eligible','revoked')),
 CHECK(digest=encode(extensions.digest(convert_to('merian.initial-analysis.cpm-retention-policy.v1'||chr(10)||
  internal.initial_canonical(jsonb_build_object('version',1,'write_policy_digest',write_policy_digest,
   'retention_build_digest',retention_build_digest,'qualification_evidence_digest',qualification_evidence_digest,
   'reviewed_revision',reviewed_revision,'protocol',protocol,
   'verification_max_duration_ms',verification_max_duration_ms,'verification_max_age_ms',verification_max_age_ms,
   'clock_skew_ms',clock_skew_ms)), 'UTF8'),'sha256'),'hex'))
);
CREATE INDEX initial_cpm_photo_retention_write_policy ON internal.initial_cpm_photo_retention_policies(write_policy_digest);
ALTER TABLE internal.initial_cpm_photo_retention_policies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_cpm_photo_retention_policies FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER initial_cpm_photo_retention_immutable BEFORE UPDATE OR DELETE ON internal.initial_cpm_photo_retention_policies
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_preparation_eligibility();
CREATE TRIGGER initial_cpm_photo_retention_no_truncate BEFORE TRUNCATE ON internal.initial_cpm_photo_retention_policies
 FOR EACH STATEMENT EXECUTE FUNCTION internal.reject_initial_permanent_mutation();

-- Six sequential reads retain their existing 20s per-read ceiling. The 150s
-- whole-verification ceiling adds at most 30s for control/inspection work; an
-- installed policy may only narrow it. These ceilings are not qualification.
-- The build digest must cover terminal reader/inspector code, dependencies and
-- fixed configuration plus compatibility with the saved reader/marker protocol.
-- Installation requires evidence for that exact build and write policy; a
-- source revision, pre-admission verifier hash or Boolean cannot replace it.
CREATE FUNCTION internal.assert_initial_cpm_retention_interval_v1(
 p_policy internal.initial_cpm_photo_retention_policies,p_started JSONB,p_verified JSONB,p_adopted BIGINT)
RETURNS VOID LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE started NUMERIC; verified NUMERIC;
BEGIN
 IF jsonb_typeof(p_started) IS DISTINCT FROM 'number' OR jsonb_typeof(p_verified) IS DISTINCT FROM 'number'
  OR p_adopted IS NULL OR p_adopted NOT BETWEEN 1 AND 9007199254740991
  OR p_policy.verification_max_duration_ms IS NULL OR p_policy.verification_max_duration_ms NOT BETWEEN 1 AND 150000
  OR p_policy.verification_max_age_ms IS NULL OR p_policy.verification_max_age_ms NOT BETWEEN 1 AND 30000
  OR p_policy.clock_skew_ms IS NULL OR p_policy.clock_skew_ms NOT BETWEEN 0 AND 1000 THEN
  RAISE EXCEPTION 'initial_completion_retention_verification_invalid' USING ERRCODE='22023'; END IF;
 started:=(p_started#>>'{}')::NUMERIC; verified:=(p_verified#>>'{}')::NUMERIC;
 IF started<>trunc(started) OR verified<>trunc(verified)
  OR started NOT BETWEEN 1 AND 9007199254740991 OR verified NOT BETWEEN 1 AND 9007199254740991
  OR verified<started OR verified-started>p_policy.verification_max_duration_ms
  OR verified-p_adopted>p_policy.clock_skew_ms
  OR p_adopted-verified>p_policy.verification_max_age_ms THEN
  RAISE EXCEPTION 'initial_completion_retention_verification_invalid' USING ERRCODE='22023'; END IF;
END; $body$;

-- Post-dispatch authorization snapshot: do not relax the pre-admission reader.
-- Caller releases this transaction before byte I/O, and rechecks it after I/O.
-- Expired write capabilities are not renewed. Already admitted positive/live
-- cohorts can be checked after that expiry; retirement/marker wins deny this
-- read. No state, funding, expiry or ownership is changed by this function.
CREATE FUNCTION internal.prepare_initial_cpm_retention_v1(p_owner UUID,p_scan UUID,p_submission TEXT,
 p_result UUID,p_result_digest TEXT,p_policy TEXT)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $body$
DECLARE original JSONB; receipt internal.initial_preparation_admission_receipts;
 policy internal.initial_cpm_photo_retention_policies; saved JSONB; member JSONB;
 objects JSONB:='[]'; reads JSONB:='[]'; result JSONB; object JSONB;
BEGIN
 original:=internal.prepare_initial_completion_v1(p_owner,p_scan,p_submission,p_result,p_result_digest);
 IF original->>'media_case' IS DISTINCT FROM 'cpm' THEN
  RAISE EXCEPTION 'initial_completion_media_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO STRICT receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
 saved:=receipt.cpm_retained_roles::JSONB;
 SELECT p.* INTO policy FROM internal.initial_cpm_photo_retention_policies p
 JOIN internal.initial_cpm_photo_write_policies w ON w.digest=p.write_policy_digest
 JOIN internal.initial_preparation_backend_eligibility b ON b.generation=w.backend_generation
 WHERE p.digest=p_policy AND p.state='eligible' AND w.state='eligible' AND b.state='eligible'
  AND w.backend_generation::TEXT=saved->>'backend_generation'
  AND w.backend_configuration_digest=saved->>'backend_configuration_digest'
  AND b.configuration_digest=w.backend_configuration_digest
 FOR SHARE OF p,w,b NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_completion_retention_policy_unavailable' USING ERRCODE='55000'; END IF;
 FOR member IN SELECT value FROM jsonb_array_elements(saved->'members') LOOP
  IF member#>>'{attempt,write_policy_digest}' IS DISTINCT FROM policy.write_policy_digest
   OR member#>>'{closure,policy_digest}' IS DISTINCT FROM policy.write_policy_digest THEN
   RAISE EXCEPTION 'initial_completion_retention_policy_unavailable' USING ERRCODE='55000'; END IF;
  object:=jsonb_build_object('photo_ordinal',member#>'{role,photo_ordinal}','role',member#>'{role,role}',
   'reference_id',member#>'{role,declaration,reference_id}','object_id',member#>'{role,object_id}',
   'backend_generation',saved->'backend_generation','backend_configuration_digest',saved->'backend_configuration_digest',
   'namespace','initial-preparation/v2','byte_count',member#>'{role,declaration,byte_count}',
   'sha256',member#>'{role,declaration,sha256}','content_type',member#>'{role,declaration,declared_content_type}');
  objects:=objects||jsonb_build_array(object);
  reads:=reads||jsonb_build_array(jsonb_build_object('attempt_id',member#>'{attempt,attempt_id}',
   'scan_id',p_scan,'object_id',object->'object_id','assignment_digest',saved->'assignment_digest',
   'backend_generation',saved->'backend_generation','backend_configuration_digest',saved->'backend_configuration_digest',
   'issued_at_ms',floor(extract(epoch FROM (member#>>'{attempt,issued_at}')::TIMESTAMPTZ)*1000)::BIGINT,
   'verification_policy_digest',policy.write_policy_digest));
 END LOOP;
 result:=jsonb_build_object('version',1,'variant','cpm_in_place_adoption_v1','owner_id',p_owner,'scan_id',p_scan,
  'admission_receipt_id',receipt.admission_receipt_id,'admission_receipt_digest',receipt.receipt_digest,
  'cpm_verification_digest',receipt.cpm_verification_digest,
  'retained_roles_digest',encode(extensions.digest(convert_to('merian.initial-analysis.cpm-verification-start.v1'||chr(10)||receipt.cpm_retained_roles,'UTF8'),'sha256'),'hex'),
  'result_evidence_id',p_result,'result_digest',p_result_digest,'retention_policy_digest',policy.digest,
  'retention_build_digest',policy.retention_build_digest,'objects',objects);
 result:=jsonb_build_object('binding',result,'reads',reads,'profile_digest',saved->'profile_digest',
  'verifier_build_digest',saved->'verifier_build_digest','policy',to_jsonb(policy)-ARRAY['digest','state']);
 IF octet_length(result::TEXT)>65536 OR octet_length(internal.initial_canonical(result))>65536 THEN
  RAISE EXCEPTION 'initial_completion_retention_verification_invalid' USING ERRCODE='22023'; END IF;
 RETURN result;
END; $body$;

-- Candidate only, not an ownership receipt or settlement grant. The eventual
-- completion stage must consume the exact fresh candidate and recheck interval
-- freshness at its adoption event. All current CPM completion denials remain.
CREATE FUNCTION internal.prepare_initial_cpm_adoption_candidate_v1(p_owner UUID,p_scan UUID,p_submission TEXT,
 p_result UUID,p_result_digest TEXT,p_policy TEXT,p_verification JSONB)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $body$
DECLARE snapshot JSONB; policy internal.initial_cpm_photo_retention_policies; adopted BIGINT;
BEGIN
 IF p_verification IS NULL OR jsonb_typeof(p_verification)<>'object'
  OR octet_length(p_verification::TEXT)>65536 OR octet_length(internal.initial_canonical(p_verification))>65536 THEN
  RAISE EXCEPTION 'initial_completion_retention_verification_invalid' USING ERRCODE='22023'; END IF;
 snapshot:=internal.prepare_initial_cpm_retention_v1(p_owner,p_scan,p_submission,p_result,p_result_digest,p_policy);
 IF p_verification-ARRAY['verification_started_at_ms','verified_at_ms'] IS DISTINCT FROM snapshot->'binding' THEN
  RAISE EXCEPTION 'initial_completion_retention_verification_invalid' USING ERRCODE='22023'; END IF;
 SELECT * INTO STRICT policy FROM internal.initial_cpm_photo_retention_policies WHERE digest=p_policy;
 adopted:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
 PERFORM internal.assert_initial_cpm_retention_interval_v1(policy,p_verification->'verification_started_at_ms',p_verification->'verified_at_ms',adopted);
 RETURN p_verification||jsonb_build_object('adopted_at_ms',adopted);
END; $body$;
REVOKE ALL ON FUNCTION internal.assert_initial_cpm_retention_interval_v1(internal.initial_cpm_photo_retention_policies,JSONB,JSONB,BIGINT),
 internal.prepare_initial_cpm_retention_v1(UUID,UUID,TEXT,UUID,TEXT,TEXT),
 internal.prepare_initial_cpm_adoption_candidate_v1(UUID,UUID,TEXT,UUID,TEXT,TEXT,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;

-- CPM adoption uses the same completion transaction and transfer owner. The
-- immutable admitted roles remain live; the legacy copy/retire path stays v3.
ALTER TABLE internal.initial_consuming_staging
 ADD COLUMN completion_adoption JSONB,
 ADD CONSTRAINT initial_completion_adoption_shape CHECK(completion_adoption IS NULL OR
  (operation='completion' AND jsonb_typeof(completion_adoption)='object'
   AND octet_length(completion_adoption::TEXT)<=65536));

CREATE FUNCTION internal.initial_cpm_adoption_shape_v1(p_owner UUID,p_scan UUID,p_text TEXT,p_digest TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE v JSONB; m JSONB; n INTEGER:=0; k TEXT; ids UUID[]:='{}'; refs UUID[]:='{}';
BEGIN
 IF p_owner IS NULL OR p_scan IS NULL OR p_text IS NULL OR octet_length(p_text)>65536 OR p_digest IS NULL THEN RETURN FALSE; END IF;
 v:=p_text::JSONB;
 IF internal.initial_canonical(v) IS DISTINCT FROM p_text OR octet_length(v::TEXT)>65536
  OR v->'version' IS DISTINCT FROM '1'::JSONB OR v->>'variant' IS DISTINCT FROM 'cpm_in_place_adoption_v1'
  OR v->>'owner_id' IS DISTINCT FROM p_owner::TEXT OR v->>'scan_id' IS DISTINCT FROM p_scan::TEXT
  OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v) key) IS DISTINCT FROM
   ARRAY['admission_receipt_digest','admission_receipt_id','adopted_at_ms','cpm_verification_digest','objects','owner_id','result_digest','result_evidence_id','retained_roles_digest','retention_build_digest','retention_policy_digest','scan_id','variant','verification_started_at_ms','verified_at_ms','version']::TEXT[]
  OR p_digest IS DISTINCT FROM encode(extensions.digest(convert_to('merian.initial-analysis.cpm-adoption.v1'||chr(10)||p_text,'UTF8'),'sha256'),'hex') THEN RETURN FALSE; END IF;
 FOREACH k IN ARRAY ARRAY['admission_receipt_id','result_evidence_id'] LOOP
  IF jsonb_typeof(v->k) IS DISTINCT FROM 'string' OR v->>k !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN FALSE; END IF;
 END LOOP;
 FOREACH k IN ARRAY ARRAY['admission_receipt_digest','cpm_verification_digest','result_digest','retained_roles_digest','retention_build_digest','retention_policy_digest'] LOOP
  IF jsonb_typeof(v->k) IS DISTINCT FROM 'string' OR v->>k !~ '^[0-9a-f]{64}$' THEN RETURN FALSE; END IF;
 END LOOP;
 FOREACH k IN ARRAY ARRAY['verification_started_at_ms','verified_at_ms','adopted_at_ms'] LOOP
  IF jsonb_typeof(v->k) IS DISTINCT FROM 'number' OR (v->>k)::NUMERIC<>trunc((v->>k)::NUMERIC)
   OR (v->>k)::NUMERIC NOT BETWEEN 1 AND 9007199254740991 THEN RETURN FALSE; END IF;
 END LOOP;
 IF jsonb_typeof(v->'objects') IS DISTINCT FROM 'array' OR jsonb_array_length(v->'objects') NOT IN (3,6) THEN RETURN FALSE; END IF;
 FOR m IN SELECT value FROM jsonb_array_elements(v->'objects') LOOP
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(m) key) IS DISTINCT FROM
   ARRAY['backend_configuration_digest','backend_generation','byte_count','content_type','namespace','object_id','photo_ordinal','reference_id','role','sha256']::TEXT[]
   OR m->'photo_ordinal' IS DISTINCT FROM to_jsonb(n/3) OR m->>'role' IS DISTINCT FROM (ARRAY['source','ai','display'])[n%3+1]
   OR m->>'namespace' IS DISTINCT FROM 'initial-preparation/v2' THEN RETURN FALSE; END IF;
  FOREACH k IN ARRAY ARRAY['object_id','reference_id','backend_generation'] LOOP
   IF jsonb_typeof(m->k) IS DISTINCT FROM 'string' OR m->>k !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN FALSE; END IF;
  END LOOP;
  FOREACH k IN ARRAY ARRAY['sha256','backend_configuration_digest'] LOOP
   IF jsonb_typeof(m->k) IS DISTINCT FROM 'string' OR m->>k !~ '^[0-9a-f]{64}$' THEN RETURN FALSE; END IF;
  END LOOP;
  IF (m->>'object_id')::UUID=ANY(ids) OR (m->>'reference_id')::UUID=ANY(refs)
   OR jsonb_typeof(m->'byte_count') IS DISTINCT FROM 'number' OR (m->>'byte_count')::NUMERIC<>trunc((m->>'byte_count')::NUMERIC)
   OR (m->>'byte_count')::NUMERIC NOT BETWEEN 1 AND (CASE m->>'role' WHEN 'source' THEN 33554432 WHEN 'ai' THEN 5242880 ELSE 4194304 END)
   OR jsonb_typeof(m->'content_type') IS DISTINCT FROM 'string'
   OR NOT (m->>'content_type'='image/jpeg' OR (m->>'role'='source' AND m->>'content_type' IN ('image/png','image/webp','image/heic','image/heif')))
   THEN RETURN FALSE; END IF;
  ids:=ids||(m->>'object_id')::UUID;refs:=refs||(m->>'reference_id')::UUID;n:=n+1;
 END LOOP;
 RETURN TRUE;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR invalid_parameter_value THEN RETURN FALSE;
END; $body$;

-- Reconstruct exact receipt bindings without new eligibility or clock
-- decisions. Historical recovery uses this immutable image after revocation.
CREATE FUNCTION internal.assert_initial_cpm_adoption_binding_v1(p_row JSONB)
RETURNS VOID LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE v JSONB; r internal.initial_preparation_admission_receipts; result internal.initial_analysis_results;
 policy internal.initial_cpm_photo_retention_policies; original JSONB; objects JSONB:='[]'; m JSONB; expected JSONB;
BEGIN
 IF NOT internal.initial_cpm_adoption_shape_v1((p_row->>'owner_id')::UUID,(p_row->>'scan_id')::UUID,p_row->>'receipt',p_row->>'receipt_digest')
  OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_row) key) IS DISTINCT FROM ARRAY['owner_id','receipt','receipt_digest','scan_id']::TEXT[] THEN
  RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
 v:=(p_row->>'receipt')::JSONB;
 SELECT * INTO r FROM internal.initial_preparation_admission_receipts WHERE scan_id=(p_row->>'scan_id')::UUID;
 IF NOT FOUND OR r.owner_id::TEXT IS DISTINCT FROM p_row->>'owner_id'
  OR r.admission_variant IS DISTINCT FROM 'client_prepared_photo_v1'
  OR r.receipt_digest IS DISTINCT FROM internal.validate_initial_cpm_admitted_proof(r) THEN
  RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
 SELECT * INTO result FROM internal.initial_analysis_results WHERE scan_id=r.scan_id;
 IF NOT FOUND OR result.owner_id IS DISTINCT FROM r.owner_id THEN
  RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
 SELECT * INTO policy FROM internal.initial_cpm_photo_retention_policies WHERE digest=v->>'retention_policy_digest';
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
 original:=r.cpm_retained_roles::JSONB;
 FOR m IN SELECT value FROM jsonb_array_elements(original->'members') LOOP
  IF m#>>'{attempt,write_policy_digest}' IS DISTINCT FROM policy.write_policy_digest
   OR m#>>'{closure,policy_digest}' IS DISTINCT FROM policy.write_policy_digest THEN
   RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
  objects:=objects||jsonb_build_array(jsonb_build_object('photo_ordinal',m#>'{role,photo_ordinal}','role',m#>'{role,role}',
   'reference_id',m#>'{role,declaration,reference_id}','object_id',m#>'{role,object_id}',
   'backend_generation',original->'backend_generation','backend_configuration_digest',original->'backend_configuration_digest',
   'namespace','initial-preparation/v2','byte_count',m#>'{role,declaration,byte_count}',
   'sha256',m#>'{role,declaration,sha256}','content_type',m#>'{role,declaration,declared_content_type}'));
 END LOOP;
 expected:=jsonb_build_object('version',1,'variant','cpm_in_place_adoption_v1','owner_id',r.owner_id,'scan_id',r.scan_id,
  'admission_receipt_id',r.admission_receipt_id,'admission_receipt_digest',r.receipt_digest,'cpm_verification_digest',r.cpm_verification_digest,
  'retained_roles_digest',encode(extensions.digest(convert_to('merian.initial-analysis.cpm-verification-start.v1'||chr(10)||r.cpm_retained_roles,'UTF8'),'sha256'),'hex'),
  'result_evidence_id',result.result_evidence_id,'result_digest',encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(result.result_snapshot),'UTF8'),'sha256'),'hex'),
  'retention_policy_digest',policy.digest,'retention_build_digest',policy.retention_build_digest,'objects',objects);
 IF v-ARRAY['verification_started_at_ms','verified_at_ms','adopted_at_ms'] IS DISTINCT FROM expected THEN
  RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
 PERFORM internal.assert_initial_cpm_retention_interval_v1(policy,v->'verification_started_at_ms',v->'verified_at_ms',(v->>'adopted_at_ms')::BIGINT);
END; $body$;

CREATE FUNCTION internal.assert_initial_cpm_adoption_fresh_v1(p_row JSONB)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $body$
DECLARE v JSONB:=(p_row->>'receipt')::JSONB; policy internal.initial_cpm_photo_retention_policies;
 now_ms BIGINT:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
BEGIN
 PERFORM internal.assert_initial_cpm_adoption_binding_v1(p_row);
 SELECT p.* INTO policy FROM internal.initial_cpm_photo_retention_policies p
 JOIN internal.initial_cpm_photo_write_policies w ON w.digest=p.write_policy_digest
 JOIN internal.initial_preparation_backend_eligibility b ON b.generation=w.backend_generation AND b.configuration_digest=w.backend_configuration_digest
 WHERE p.digest=v->>'retention_policy_digest' AND p.state='eligible' AND w.state='eligible' AND b.state='eligible'
  AND w.backend_generation::TEXT=v#>>'{objects,0,backend_generation}'
  AND w.backend_configuration_digest=v#>>'{objects,0,backend_configuration_digest}' FOR SHARE OF p,w,b NOWAIT;
 IF NOT FOUND OR (v->>'adopted_at_ms')::BIGINT<floor(extract(epoch FROM transaction_timestamp())*1000)::BIGINT
  OR (v->>'adopted_at_ms')::BIGINT>now_ms THEN
  RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
 PERFORM internal.assert_initial_cpm_retention_interval_v1(policy,v->'verification_started_at_ms',v->'verified_at_ms',now_ms);
END; $body$;

CREATE FUNCTION internal.initial_cpm_completion_media_v1(p_row JSONB)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $body$
 SELECT jsonb_build_object('kind','cpm_adoption_v1','receipt_digest',p_row->'receipt_digest','items',
  (SELECT jsonb_agg(jsonb_build_object('ordinal',m->'photo_ordinal','kind','image','media_id',m->'object_id',
   'content_type',m->'content_type','byte_count',m->'byte_count','sha256',m->'sha256','poster_media_id',NULL)
   ORDER BY (m->>'photo_ordinal')::INTEGER)
   FROM jsonb_array_elements((p_row->>'receipt')::JSONB->'objects') m WHERE m->>'role'='display'));
$body$;

-- Variant-aware CHECK preserves the original v3 parser and digest unchanged.
DO $adoption_check$
DECLARE constraint_name TEXT;
BEGIN
 SELECT conname INTO STRICT constraint_name FROM pg_constraint WHERE conrelid='internal.initial_preparation_transfer_receipts'::REGCLASS
  AND contype='c' AND pg_get_constraintdef(oid) LIKE '%initial_media_handoff_document_shape%';
 EXECUTE format('ALTER TABLE internal.initial_preparation_transfer_receipts DROP CONSTRAINT %I',constraint_name);
 ALTER TABLE internal.initial_preparation_transfer_receipts ADD CONSTRAINT initial_transfer_receipt_variants CHECK(
  CASE WHEN receipt::JSONB->>'variant'='cpm_in_place_adoption_v1'
   THEN internal.initial_cpm_adoption_shape_v1(owner_id,scan_id,receipt,receipt_digest)
   ELSE internal.initial_media_handoff_document_shape('transfer_receipt',owner_id,scan_id,receipt,receipt_digest) END);
END; $adoption_check$;

-- Post-insert live assertion has a separate name: pre-insert admission and
-- fresh completion preparation still require transfer absence verbatim.
DO $adopted_cohort$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.assert_initial_cpm_receipt_cohort(internal.initial_preparation_admission_receipts,boolean)'::REGPROCEDURE);
 definition:=replace(definition,'FUNCTION internal.assert_initial_cpm_receipt_cohort(', 'FUNCTION internal.assert_initial_cpm_adopted_cohort_v1(');
 anchor:='  OR EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=r.scan_id)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'adopted cohort source drift'; END IF;
 definition:=replace(definition,anchor,'');
 anchor:=' snapshot:=internal.initial_cpm_verification_start_snapshot(r.owner_id,r.scan_id);';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'adopted cohort snapshot drift'; END IF;
 definition:=replace(definition,anchor,$insert$ IF p_admitted IS DISTINCT FROM TRUE OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=r.scan_id AND owner_id=r.owner_id) THEN
  RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
 PERFORM internal.assert_initial_cpm_adoption_binding_v1((SELECT to_jsonb(t) FROM internal.initial_preparation_transfer_receipts t WHERE scan_id=r.scan_id));
$insert$||anchor);
 EXECUTE definition;
END; $adopted_cohort$;
REVOKE ALL ON FUNCTION internal.initial_cpm_adoption_shape_v1(UUID,UUID,TEXT,TEXT),
 internal.assert_initial_cpm_adoption_binding_v1(JSONB),internal.assert_initial_cpm_adoption_fresh_v1(JSONB),
 internal.initial_cpm_completion_media_v1(JSONB),internal.assert_initial_cpm_adopted_cohort_v1(internal.initial_preparation_admission_receipts,BOOLEAN)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.assert_initial_completion_adoption_stage_v1(p_original JSONB)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $body$
DECLARE stage internal.initial_consuming_staging; r internal.initial_preparation_admission_receipts;
BEGIN
 SELECT * INTO stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF NOT FOUND OR stage.operation IS DISTINCT FROM 'completion' OR stage.sealed OR stage.completion_prepared
  OR stage.completion_next_event<>0 OR stage.completion_credit IS NOT NULL
  OR stage.completion_prestate IS DISTINCT FROM p_original OR stage.completion_adoption IS NULL
  OR stage.completion_adoption->>'owner_id' IS DISTINCT FROM stage.owner_id::TEXT
  OR stage.completion_adoption->>'scan_id' IS DISTINCT FROM stage.scan_id::TEXT
  OR internal.initial_dispatch_root_images(stage.scan_id) IS DISTINCT FROM p_original->'roots' THEN
  RAISE EXCEPTION 'initial_completion_adoption_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id=stage.scan_id;
 PERFORM internal.assert_initial_cpm_receipt_cohort(r,TRUE);
 PERFORM internal.assert_initial_cpm_adoption_fresh_v1(stage.completion_adoption);
END; $body$;

CREATE FUNCTION internal.assert_initial_cpm_completed_v1(p_owner UUID,p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $body$
DECLARE r internal.initial_preparation_admission_receipts; t internal.initial_preparation_transfer_receipts;
 c internal.initial_analysis_completions;
BEGIN
 -- Caller owns the original owner/scan/lifecycle/invocation scope. Use the
 -- existing capacity -> ordered registry/attempt/closure -> receipt order.
 PERFORM internal.lock_initial_cpm_photo_capacity();
 PERFORM scan_id FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan FOR UPDATE;
 PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 PERFORM object_id FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=p_scan ORDER BY photo_ordinal,role COLLATE "C" FOR UPDATE;
 PERFORM attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 PERFORM w.attempt_id FROM internal.initial_cpm_photo_write_closures w JOIN internal.initial_cpm_photo_write_attempts a USING(attempt_id)
  WHERE a.scan_id=p_scan ORDER BY w.attempt_id FOR UPDATE OF w;
 SELECT * INTO r FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan FOR UPDATE;
 SELECT * INTO t FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan FOR UPDATE;
 SELECT * INTO c FROM internal.initial_analysis_completions WHERE scan_id=p_scan;
 IF r.owner_id IS DISTINCT FROM p_owner OR t.owner_id IS DISTINCT FROM p_owner OR c.owner_id IS DISTINCT FROM p_owner
  OR r.scan_id IS NULL OR t.scan_id IS NULL OR c.scan_id IS NULL
  OR NOT internal.initial_completed_scan_v1(p_owner,p_scan)
  OR c.receipt_snapshot->>'finalized_media_binding_digest' IS DISTINCT FROM t.receipt_digest
  OR c.completion_projection_snapshot->'media' IS DISTINCT FROM internal.initial_cpm_completion_media_v1(to_jsonb(t)) THEN
  RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
 PERFORM internal.assert_initial_cpm_adopted_cohort_v1(r,TRUE);
END; $body$;

-- Only a fresh original-bound INSERT may carry prepared adoption. Every later
-- stage transition's whole-row comparison preserves it unchanged.
DO $completion_adoption_stage$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.guard_initial_consuming_stage()'::REGPROCEDURE);
 anchor:=$anchor$ IF TG_OP='INSERT' THEN$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'adoption stage source drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$insert$
  IF NEW.completion_adoption IS NOT NULL THEN
   IF NEW.operation IS DISTINCT FROM 'completion' OR NEW.completion_prestate->>'media_case' IS DISTINCT FROM 'cpm'
    OR NEW.completion_adoption->>'owner_id' IS DISTINCT FROM NEW.owner_id::TEXT
    OR NEW.completion_adoption->>'scan_id' IS DISTINCT FROM NEW.scan_id::TEXT
    OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_staging WHERE transaction_id=pg_current_xact_id()) THEN
    RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
   PERFORM internal.assert_initial_cpm_adoption_fresh_v1(NEW.completion_adoption);
  END IF;
$insert$);

 -- Both BEFORE and AFTER exact-row guards consume the same completion event;
 -- ordinary v3 writes still require the original handoff stage verbatim.
 definition:=pg_get_functiondef('internal.guard_initial_media_handoff_domain_row()'::REGPROCEDURE);
 anchor:=$anchor$    scan:=(COALESCE(prior_image,next_image)->>'scan_id')::UUID;$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'adoption transfer guard drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$insert$
    IF relation='internal.initial_preparation_transfer_receipts' AND TG_OP='INSERT'
     AND internal.initial_completion_expected_insert_v1(relation,next_image,TG_WHEN='AFTER') THEN RETURN NEW; END IF;
    IF relation='internal.initial_preparation_transfer_receipts' AND TG_OP='DELETE'
     AND (prior_image->>'receipt')::JSONB->>'variant'='cpm_in_place_adoption_v1' THEN
     IF EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=scan AND state='retired')
      AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=scan AND NOT retired)
      AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=scan AND NOT retired)
      AND (EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=scan)
       OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=(prior_image->>'owner_id')::UUID)) THEN RETURN OLD; END IF;
     RAISE EXCEPTION 'initial_completion_adoption_erasure_required' USING ERRCODE='55000';
    END IF;
$insert$);
END; $completion_adoption_stage$;

CREATE TRIGGER a0000_initial_completion_statement BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.initial_preparation_transfer_receipts
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1();
CREATE TRIGGER zzzzzz_initial_completion_statement AFTER INSERT OR UPDATE OR DELETE ON internal.initial_preparation_transfer_receipts
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1();
CREATE TRIGGER zzzzzz_initial_completion_row_before BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_preparation_transfer_receipts
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1();
CREATE TRIGGER zzzzzz_initial_completion_row_after AFTER INSERT OR UPDATE OR DELETE ON internal.initial_preparation_transfer_receipts
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_completion_credit_event_v1();

-- Freshness is checked again at the actual adoption statement, after original
-- settlement. A timeout/revocation here rolls back the entire transaction.
CREATE FUNCTION internal.guard_initial_cpm_adoption_clock_v1()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE stage internal.initial_consuming_staging; r internal.initial_preparation_admission_receipts;
BEGIN
 SELECT * INTO stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 IF FOUND AND stage.operation='completion' AND stage.completion_prestate->>'media_case'='cpm' THEN
  IF TG_OP<>'INSERT' OR stage.completion_suffix->'adoption_after' IS DISTINCT FROM stage.completion_adoption THEN
   RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_cpm_adoption_fresh_v1(stage.completion_adoption);
  SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id=stage.scan_id;
  PERFORM internal.assert_initial_cpm_receipt_cohort(r,TRUE);
 END IF;
 RETURN NULL;
END; $body$;
CREATE TRIGGER a00000_initial_adoption_clock BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.initial_preparation_transfer_receipts
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cpm_adoption_clock_v1();

-- Adoption survives ordinary expiry and write-policy revocation. Only a real
-- scan/account erasure fence can retire its original roles; C1 is not erasure.
CREATE FUNCTION internal.guard_initial_cpm_adopted_retirement_v1()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE identity UUID:=OLD.scan_id; owner UUID;
BEGIN
 SELECT owner_id INTO owner FROM internal.initial_preparation_transfer_receipts
  WHERE scan_id=identity AND receipt::JSONB->>'variant'='cpm_in_place_adoption_v1';
 IF FOUND AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=identity)
  AND EXISTS(SELECT 1 FROM public.users WHERE id=owner) THEN
  RAISE EXCEPTION 'initial_completion_adoption_erasure_required' USING ERRCODE='55000'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END; $body$;
CREATE TRIGGER a00000_initial_adopted_retirement BEFORE UPDATE OR DELETE ON internal.initial_preparation_source_fences
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cpm_adopted_retirement_v1();
CREATE TRIGGER a00000_initial_adopted_retirement BEFORE UPDATE OR DELETE ON internal.initial_preparation_source_registry
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cpm_adopted_retirement_v1();
CREATE TRIGGER a00000_initial_adopted_retirement BEFORE DELETE ON internal.initial_analysis_preparation_intents
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cpm_adopted_retirement_v1();

CREATE FUNCTION internal.complete_initial_analysis_cpm_v1(p_owner UUID,p_scan UUID,p_submission TEXT,
 p_result UUID,p_result_digest TEXT,p_policy TEXT,p_verification JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' SET timezone='UTC' AS $body$
DECLARE recovered JSONB; candidate JSONB; original JSONB; adoption JSONB; receipt_text TEXT;
 stage internal.initial_consuming_staging; scan_row public.scans; completion_row internal.initial_analysis_completions;
 transfer_row internal.initial_preparation_transfer_receipts;
BEGIN
 recovered:=internal.read_initial_analysis_result(p_owner,p_scan,p_submission,p_result,p_result_digest);
 IF recovered->>'outcome' IS DISTINCT FROM 'found' THEN RAISE EXCEPTION 'initial_completion_result_unavailable' USING ERRCODE='55000'; END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN
  RETURN internal.complete_initial_analysis_legacy_v1(p_owner,p_scan,p_submission,p_result,p_result_digest);
 END IF;
 candidate:=internal.prepare_initial_cpm_adoption_candidate_v1(p_owner,p_scan,p_submission,p_result,p_result_digest,p_policy,p_verification);
 receipt_text:=internal.initial_canonical(candidate);
 adoption:=jsonb_build_object('scan_id',p_scan,'owner_id',p_owner,'receipt',receipt_text,
  'receipt_digest',encode(extensions.digest(convert_to('merian.initial-analysis.cpm-adoption.v1'||chr(10)||receipt_text,'UTF8'),'sha256'),'hex'));
 original:=internal.prepare_initial_completion_v1(p_owner,p_scan,p_submission,p_result,p_result_digest);
 INSERT INTO internal.initial_consuming_staging(transaction_id,scan_id,owner_id,operation,
  admission_receipt_id,admission_receipt_digest,reservation_id,invocation_id,expected_writes,completion_prestate,completion_adoption)
 VALUES(pg_current_xact_id(),p_scan,p_owner,'completion',(original->>'admission_receipt_id')::UUID,
  original->>'admission_receipt_digest',(original#>>'{quota,id}')::UUID,(original#>>'{invocation,id}')::UUID,'[]',original,adoption);
 PERFORM internal.settle_complimentary_analysis(p_owner,p_scan,NULL);
 UPDATE internal.initial_consuming_staging SET completion_prepared=TRUE WHERE transaction_id=pg_current_xact_id();
 SELECT * INTO STRICT stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 transfer_row:=jsonb_populate_record(NULL::internal.initial_preparation_transfer_receipts,stage.completion_adoption);
 INSERT INTO internal.initial_preparation_transfer_receipts SELECT transfer_row.*;
 scan_row:=jsonb_populate_record(NULL::public.scans,stage.completion_prestate->'scan_input');
 INSERT INTO public.scans SELECT scan_row.*;
 completion_row:=jsonb_populate_record(NULL::internal.initial_analysis_completions,stage.completion_suffix->'completion_after');
 INSERT INTO internal.initial_analysis_completions SELECT completion_row.*;
 UPDATE internal.initial_consuming_staging SET sealed=TRUE WHERE transaction_id=stage.transaction_id;
 SELECT * INTO STRICT stage FROM internal.initial_consuming_staging WHERE transaction_id=stage.transaction_id;
 PERFORM internal.assert_initial_completion_terminal_v1(stage);
 DELETE FROM internal.initial_consuming_staging WHERE transaction_id=stage.transaction_id;
 RETURN jsonb_build_object('version',1,'outcome','fresh','receipt',completion_row.receipt_snapshot,'projection',completion_row.completion_projection_snapshot);
END; $body$;
REVOKE ALL ON FUNCTION internal.assert_initial_completion_adoption_stage_v1(JSONB),
 internal.assert_initial_cpm_completed_v1(UUID,UUID),internal.guard_initial_cpm_adoption_clock_v1(),
 internal.guard_initial_cpm_adopted_retirement_v1(),internal.complete_initial_analysis_cpm_v1(UUID,UUID,TEXT,UUID,TEXT,TEXT,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;

-- Private delivery preparation. This reader never invokes either finalizer or
-- settlement. Original result recovery supplies the existing owner/deletion
-- locks before completion is inspected; a missing completion stays absent.
CREATE FUNCTION internal.read_initial_completion_v1(p_owner UUID,p_scan UUID,p_submission TEXT,p_result UUID,p_result_digest TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE recovered JSONB; saved internal.initial_analysis_completions;
BEGIN
 recovered:=internal.read_initial_analysis_result(p_owner,p_scan,p_submission,p_result,p_result_digest);
 SELECT * INTO saved FROM internal.initial_analysis_completions WHERE scan_id=p_scan FOR SHARE;
 IF NOT FOUND THEN
  RETURN jsonb_build_object('version',1,'outcome','absent','reference',recovered->'reference','completion',NULL,'result',NULL);
 END IF;
 IF recovered->>'outcome' IS DISTINCT FROM 'found'
  OR saved.owner_id IS DISTINCT FROM p_owner OR saved.result_evidence_id IS DISTINCT FROM p_result
  OR saved.receipt_snapshot->>'submission_digest' IS DISTINCT FROM p_submission
  OR saved.receipt_snapshot->>'result_digest' IS DISTINCT FROM p_result_digest
  OR internal.initial_completed_scan_v1(p_owner,p_scan) IS DISTINCT FROM TRUE
  OR NOT EXISTS(SELECT 1 FROM public.scans WHERE id=p_scan AND user_id=p_owner AND NOT is_tombstoned) THEN
  RAISE EXCEPTION 'initial_completion_conflict' USING ERRCODE='55000'; END IF;
 IF saved.completion_projection_snapshot#>>'{media,kind}'='cpm_adoption_v1' THEN
  PERFORM internal.assert_initial_cpm_completed_v1(p_owner,p_scan);
 END IF;
 RETURN jsonb_build_object('version',1,'outcome','found','reference',recovered->'reference',
  'completion',jsonb_build_object('receipt_canonical',internal.initial_canonical(saved.receipt_snapshot),
   'projection_canonical',internal.initial_canonical(saved.completion_projection_snapshot)),
  'result',recovered->'evidence');
END; $body$;
REVOKE ALL ON FUNCTION internal.read_initial_completion_v1(UUID,UUID,TEXT,UUID,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

-- First acquisition is admission-bound. Result identity comes from the original
-- retained result under the same outer locks, never from a completion reply or
-- the caller. This operation cannot admit, dispatch, settle or repair anything.
CREATE FUNCTION internal.discover_initial_completion_v1(p_owner UUID,p_scan UUID,p_admission TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE requested JSONB; expected JSONB; context RECORD;
 admitted internal.initial_analysis_admissions; submitted internal.initial_analysis_submissions;
 original internal.identification_invocations; saved internal.initial_analysis_results;
 reference JSONB; result_digest TEXT; delivery JSONB;
BEGIN
 PERFORM internal.require_service_role();
 IF p_admission IS NULL OR octet_length(p_admission)>4096 THEN
  RAISE EXCEPTION 'initial_completion_admission_invalid' USING ERRCODE='22023'; END IF;
 requested:=p_admission::JSONB;
 IF jsonb_typeof(requested) IS DISTINCT FROM 'object'
  OR internal.initial_canonical(requested) IS DISTINCT FROM p_admission
  OR requested->>'owner_id' IS DISTINCT FROM p_owner::TEXT
  OR requested->>'scan_id' IS DISTINCT FROM p_scan::TEXT THEN
  RAISE EXCEPTION 'initial_completion_admission_invalid' USING ERRCODE='22023'; END IF;
 SELECT * INTO STRICT context FROM internal.lock_initial_dispatched_original(
  p_owner,p_scan,requested->>'submission_digest',NULL,NULL,'read');
 admitted:=context.admission_row; original:=context.invocation_row;
 -- The existing lock owner already holds this original submission FOR UPDATE.
 SELECT * INTO STRICT submitted FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
 expected:=jsonb_build_object('version',1,'owner_id',p_owner,'scan_id',p_scan,
  'route',submitted.route,'input_schema_version',submitted.input_schema_version,
  'submission_digest',admitted.submission_digest,'config_digest',admitted.configuration_digest,
  'funding_binding_id',admitted.funding_binding_id,'funding_binding_digest',admitted.funding_digest,
  'funding_binding_version',submitted.funding_snapshot->'version',
  'ordered_description_digest',admitted.descriptions_digest,
  'ordered_description_count',jsonb_array_length(submitted.ordered_descriptions));
 IF requested IS DISTINCT FROM expected OR submitted.input_schema_version NOT IN (1,2)
  OR submitted.owner_id IS DISTINCT FROM p_owner THEN
  RAISE EXCEPTION 'initial_completion_admission_conflict' USING ERRCODE='55000'; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_results WHERE scan_id=p_scan FOR SHARE;
 IF NOT FOUND THEN
  RETURN jsonb_build_object('version',1,'outcome','pending','admission_canonical',p_admission,
   'reference',NULL,'result_digest',NULL,'original_provenance',NULL,'delivery',NULL);
 END IF;
 result_digest:=encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||
  internal.initial_canonical(saved.result_snapshot),'UTF8'),'sha256'),'hex');
 reference:=jsonb_build_object('owner_id',p_owner,'scan_id',p_scan,'invocation_id',original.id,
  'result_evidence_id',saved.result_evidence_id,'submission_digest',admitted.submission_digest,
  'config_digest',admitted.configuration_digest,'funding_binding_digest',admitted.funding_digest);
 delivery:=internal.read_initial_completion_v1(p_owner,p_scan,admitted.submission_digest,saved.result_evidence_id,result_digest);
 IF delivery->>'outcome'='absent' THEN
  RETURN jsonb_build_object('version',1,'outcome','pending','admission_canonical',p_admission,
   'reference',NULL,'result_digest',NULL,'original_provenance',NULL,'delivery',NULL);
 END IF;
 RETURN jsonb_build_object('version',1,'outcome','found','admission_canonical',p_admission,
  'reference',reference,'result_digest',result_digest,'original_provenance',original.provenance,'delivery',delivery);
END; $body$;
REVOKE ALL ON FUNCTION internal.discover_initial_completion_v1(UUID,UUID,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

-- Original CPM admission acknowledgement, separate from the older boolean
-- bridge. Retained admission is recoverable before dispatch and after adoption;
-- neither elapsed eligibility nor a lost reply can authorize another execution.
CREATE FUNCTION internal.read_initial_cpm_completion_admission_v1(
 p_owner UUID,p_scan UUID,p_candidate TEXT,p_assignment TEXT,p_assignment_digest TEXT,
 p_backend_generation UUID,p_backend_configuration_digest TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE saved internal.initial_analysis_preparation_intents;
 admitted internal.initial_analysis_admissions; submitted internal.initial_analysis_submissions;
 receipt internal.initial_preparation_admission_receipts; retained JSONB; admission JSONB;
BEGIN
 PERFORM internal.require_service_role();
 IF p_candidate IS NULL OR octet_length(p_candidate) NOT BETWEEN 1 AND 1048576
  OR p_assignment IS NULL OR octet_length(p_assignment) NOT BETWEEN 1 AND 65536
  OR p_assignment_digest IS NULL OR p_assignment_digest !~ '^[0-9a-f]{64}$'
  OR p_backend_generation IS NULL OR p_backend_configuration_digest IS NULL
  OR p_backend_configuration_digest !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_completion_admission_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner
  OR saved.canonical_candidate IS DISTINCT FROM p_candidate OR saved.canonical_assignment IS DISTINCT FROM p_assignment
  OR saved.assignment_digest IS DISTINCT FROM p_assignment_digest
  OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'client_prepared_photo' THEN
  RAISE EXCEPTION 'initial_completion_admission_conflict' USING ERRCODE='22023'; END IF;
 PERFORM internal.parse_initial_cpm_photo_assignment(saved.canonical_candidate,saved.canonical_assignment);
 IF saved.assignment_digest IS DISTINCT FROM internal.initial_cpm_photo_digest('assignment',saved.canonical_assignment)
  OR saved.candidate_digest IS DISTINCT FROM internal.initial_cpm_photo_digest('candidate',saved.canonical_candidate)
  OR saved.canonical_assignment::JSONB#>>'{preparation,backend_generation}' IS DISTINCT FROM p_backend_generation::TEXT THEN
  RAISE EXCEPTION 'initial_completion_admission_conflict' USING ERRCODE='22023'; END IF;
 SELECT * INTO submitted FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
 SELECT * INTO admitted FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
 IF admitted.owner_id IS DISTINCT FROM p_owner OR admitted.binding_version IS DISTINCT FROM 4
  OR submitted.owner_id IS DISTINCT FROM p_owner OR submitted.input_schema_version IS DISTINCT FROM 2
  OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan
   AND state IN ('pending_pre_dispatch','dispatch_authorized')) THEN
  RAISE EXCEPTION 'initial_completion_admission_unavailable' USING ERRCODE='55000'; END IF;
 -- Hold any original invocation before checking completed history. Absence here
 -- is legal for a pre-dispatch acknowledgement; no invocation is created.
 PERFORM id FROM internal.identification_invocations
  WHERE scan_id=p_scan OR reservation_id=admitted.funding_binding_id ORDER BY id FOR UPDATE;
 PERFORM internal.lock_initial_cpm_photo_capacity();
 PERFORM scan_id FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan FOR UPDATE;
 PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 PERFORM object_id FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=p_scan ORDER BY photo_ordinal,role COLLATE "C" FOR UPDATE;
 PERFORM attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 PERFORM w.attempt_id FROM internal.initial_cpm_photo_write_closures w JOIN internal.initial_cpm_photo_write_attempts a USING(attempt_id)
  WHERE a.scan_id=p_scan ORDER BY w.attempt_id FOR UPDATE OF w;
 SELECT * INTO receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR receipt.owner_id IS DISTINCT FROM p_owner OR receipt.admission_variant IS DISTINCT FROM 'client_prepared_photo_v1'
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_cpm_verification_start_context WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging WHERE scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_completion_admission_unavailable' USING ERRCODE='55000'; END IF;
 receipt:=internal.initial_admission_retained_receipt(p_owner,p_scan,receipt.admission_receipt_id);
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN
  PERFORM internal.assert_initial_cpm_completed_v1(p_owner,p_scan);
 ELSE
  PERFORM internal.assert_initial_cpm_receipt_cohort(receipt,TRUE);
 END IF;
 retained:=receipt.cpm_retained_roles::JSONB;
 IF retained->>'backend_generation' IS DISTINCT FROM p_backend_generation::TEXT
  OR retained->>'backend_configuration_digest' IS DISTINCT FROM p_backend_configuration_digest THEN
  RAISE EXCEPTION 'initial_completion_admission_conflict' USING ERRCODE='22023'; END IF;
 admission:=jsonb_build_object('version',1,'owner_id',p_owner,'scan_id',p_scan,
  'route',submitted.route,'input_schema_version',submitted.input_schema_version,
  'submission_digest',admitted.submission_digest,'config_digest',admitted.configuration_digest,
  'funding_binding_id',admitted.funding_binding_id,'funding_binding_digest',admitted.funding_digest,
  'funding_binding_version',submitted.funding_snapshot->'version',
  'ordered_description_digest',admitted.descriptions_digest,
  'ordered_description_count',jsonb_array_length(submitted.ordered_descriptions));
 RETURN jsonb_build_object('version',1,'variant','cpm_completion_admission_v1','authority','none',
  'owner_id',p_owner,'scan_id',p_scan,'candidate_digest',saved.candidate_digest,
  'assignment_digest',saved.assignment_digest,'backend_generation',p_backend_generation,
  'backend_configuration_digest',p_backend_configuration_digest,
  'admission_receipt_id',receipt.admission_receipt_id,'admission_receipt_digest',receipt.receipt_digest,
  'admission_canonical',internal.initial_canonical(admission));
END; $body$;
REVOKE ALL ON FUNCTION internal.read_initial_cpm_completion_admission_v1(UUID,UUID,TEXT,TEXT,TEXT,UUID,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

-- Native retains candidate/content/assignment digests, not the full server
-- assignment. Resolve that original only under the same lifecycle locks, then
-- delegate every admission/cohort check to the existing exact reader. The full
-- assignment is private decoder context and must not be sent to native clients.
CREATE FUNCTION internal.read_initial_cpm_saved_admission_v1(
 p_owner UUID,p_scan UUID,p_candidate TEXT,p_candidate_digest TEXT,p_content_digest TEXT,
 p_assignment_digest TEXT,p_backend_generation UUID,p_backend_configuration_digest TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE saved internal.initial_analysis_preparation_intents; acknowledgement JSONB;
BEGIN
 PERFORM internal.require_service_role();
 IF p_candidate IS NULL OR octet_length(p_candidate) NOT BETWEEN 1 AND 1048576
  OR p_candidate_digest IS NULL OR p_candidate_digest !~ '^[0-9a-f]{64}$'
  OR p_content_digest IS NULL OR p_content_digest !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_completion_admission_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner
  OR saved.canonical_candidate IS DISTINCT FROM p_candidate
  OR saved.candidate_digest IS DISTINCT FROM p_candidate_digest
  OR saved.canonical_assignment::JSONB->>'content_digest' IS DISTINCT FROM p_content_digest THEN
  RAISE EXCEPTION 'initial_completion_admission_conflict' USING ERRCODE='22023'; END IF;
 acknowledgement:=internal.read_initial_cpm_completion_admission_v1(p_owner,p_scan,
  p_candidate,saved.canonical_assignment,p_assignment_digest,p_backend_generation,p_backend_configuration_digest);
 RETURN jsonb_build_object('version',1,'assignment_canonical',saved.canonical_assignment,
  'acknowledgement',acknowledgement);
END; $body$;
REVOKE ALL ON FUNCTION internal.read_initial_cpm_saved_admission_v1(UUID,UUID,TEXT,TEXT,TEXT,TEXT,UUID,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;
