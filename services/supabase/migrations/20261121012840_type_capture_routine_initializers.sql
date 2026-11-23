SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Preserve runtime behavior and ACLs while making PL/pgSQL initializer types
-- explicit. Strict plpgsql_check must not rely on assignment-only text casts.
DO $patch$
DECLARE signature TEXT; anchor TEXT; replacement TEXT; definition TEXT;
BEGIN
 FOR signature,anchor,replacement IN SELECT * FROM (VALUES
  ('public.claim_private_capture_finalizations(integer)', $a$output JSONB:='[]'$a$, $b$output JSONB:='[]'::JSONB$b$),
  ('internal.prepare_capture_source_admission(uuid,uuid,text,jsonb,jsonb,jsonb,text[],boolean,boolean,jsonb,integer)', $a$proofs JSONB := '[]'$a$, $b$proofs JSONB := '[]'::JSONB$b$),
  ('internal.prepare_capture_source_admission(uuid,uuid,text,jsonb,jsonb,jsonb,text[],boolean,boolean,jsonb,integer)', $a$expected JSONB := '[]'$a$, $b$expected JSONB := '[]'::JSONB$b$),
  ('internal.prepare_capture_source_admission(uuid,uuid,text,jsonb,jsonb,jsonb,text[],boolean,boolean,jsonb,integer)', $a$sessions UUID[] := '{}'$a$, $b$sessions UUID[] := '{}'::UUID[]$b$),
  ('internal.initial_capture_plan_contract(uuid,jsonb)', $a$items JSONB := '[]'$a$, $b$items JSONB := '[]'::JSONB$b$),
  ('internal.initial_capture_plan_contract(uuid,jsonb)', $a$uploads JSONB := '[]'$a$, $b$uploads JSONB := '[]'::JSONB$b$),
  ('internal.initial_capture_plan_contract(uuid,jsonb)', $a$audio JSONB := '[]'$a$, $b$audio JSONB := '[]'::JSONB$b$),
  ('internal.assert_initial_capture_audio_retention(uuid,jsonb)', $a$items JSONB:='[]'$a$, $b$items JSONB:='[]'::JSONB$b$),
  ('public.claim_initial_capture_stage_preparation(text,text,text,uuid)', $a$receipt:=public.initial_capture_audio_stage_action($a$, $b$PERFORM public.initial_capture_audio_stage_action($b$),
  ('public.claim_initial_capture_stage_preparation(text,text,text,uuid)', $a$scan UUID; receipt JSONB;$a$, $b$scan UUID;$b$)
 ) AS changes(signature,anchor,replacement)
 LOOP
  definition := pg_get_functiondef(signature::regprocedure);
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor) <> 1 THEN
   RAISE EXCEPTION 'capture_initializer_definition_drift: %',signature;
  END IF;
  EXECUTE replace(definition,anchor,replacement);
 END LOOP;
END;
$patch$;

RESET lock_timeout;
RESET statement_timeout;
