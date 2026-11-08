-- Disposable-only structural stress: extra synthetic columns exercise protocol
-- ceilings without changing production limits or pretending to be valid media.
BEGIN;
SET LOCAL statement_timeout='30s';
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.size_state_digest() RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE member TEXT; value TEXT; state TEXT:='';
BEGIN
 FOR member IN SELECT relation_name FROM internal.initial_cancellation_private_catalog()
  UNION SELECT unnest(ARRAY['public.ai_usage_events','internal.identification_invocations',
   'internal.ai_quota_reservations','internal.ai_quota_reservation_counters','internal.ai_quota_counters',
   'internal.complimentary_scan_usage','internal.initial_admitted_cancellation_staging',
   'internal.initial_analysis_lifecycle_fences']) LOOP
  EXECUTE format('SELECT COALESCE(string_agg(encode(extensions.digest(to_jsonb(t)::TEXT,''sha256''),''hex''),'''' ORDER BY to_jsonb(t)::TEXT),'''') FROM %s t',member) INTO value;
  state:=state||member||value;
 END LOOP;
 RETURN encode(extensions.digest(state,'sha256'),'hex');
END; $$;
CREATE FUNCTION pg_temp.size_probe(mode TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE scan CONSTANT UUID:='00000000-0000-4000-8000-000000000401'; owner_id UUID;
 baseline BIGINT; cpm_bytes BIGINT:=0; target BIGINT; per_row BIGINT; unit_bytes INTEGER;
 payload TEXT; state_before TEXT; result JSONB; code TEXT; message TEXT; measured BIGINT;
BEGIN
 SELECT user_id INTO STRICT owner_id FROM internal.identification_invocations WHERE scan_id=scan;
 BEGIN
  -- Structural padding alone bypasses seed-time guards. Restore every trigger
  -- before capture/public cancellation; no provider or result is produced.
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid IN ('internal.initial_analysis_preparation_intents'::REGCLASS,
   'internal.initial_preparation_admission_receipts'::REGCLASS) AND NOT tgisinternal AND tgenabled<>'O') THEN
   RAISE EXCEPTION USING ERRCODE='ZX641'; END IF;
  ALTER TABLE internal.initial_analysis_preparation_intents ADD COLUMN qualification_padding TEXT;
  ALTER TABLE internal.initial_preparation_admission_receipts ADD COLUMN qualification_padding TEXT;
  ALTER TABLE internal.initial_analysis_preparation_intents DISABLE TRIGGER USER;
  ALTER TABLE internal.initial_preparation_admission_receipts DISABLE TRIGGER USER;
  UPDATE internal.initial_analysis_preparation_intents SET qualification_padding='' WHERE scan_id=scan;
  UPDATE internal.initial_preparation_admission_receipts SET qualification_padding='' WHERE scan_id=scan;
  ALTER TABLE internal.initial_analysis_preparation_intents ENABLE TRIGGER USER;
  ALTER TABLE internal.initial_preparation_admission_receipts ENABLE TRIGGER USER;
  BEGIN
   result:=internal.capture_initial_accounted_cancellation_prestate(owner_id,scan);
   baseline:=octet_length(result::TEXT);
   IF result ? 'cpm_retained' THEN
    cpm_bytes:=octet_length((result->'cpm_retained')::TEXT)+octet_length(to_jsonb('cpm_retained'::TEXT)::TEXT)+4;
   END IF;
   result:=NULL;
   RAISE EXCEPTION USING ERRCODE='Z0001';
  EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
  target:=CASE WHEN mode='accepted_escaped' THEN 67108864 ELSE 67108868 END;
  per_row:=(target-baseline)/4; -- both rows occur twice in the final snapshot
  IF mode='accepted_escaped' THEN
   unit_bytes:=octet_length(to_jsonb(E'\001🟩'::TEXT)::TEXT)-2;
   payload:=repeat(E'\001🟩',(per_row/unit_bytes)::INTEGER)||repeat('a',(per_row%unit_bytes)::INTEGER);
  ELSE payload:=repeat('a',per_row::INTEGER); END IF;
  ALTER TABLE internal.initial_analysis_preparation_intents DISABLE TRIGGER USER;
  ALTER TABLE internal.initial_preparation_admission_receipts DISABLE TRIGGER USER;
  UPDATE internal.initial_analysis_preparation_intents SET qualification_padding=payload WHERE scan_id=scan;
  UPDATE internal.initial_preparation_admission_receipts SET qualification_padding=payload WHERE scan_id=scan;
  ALTER TABLE internal.initial_analysis_preparation_intents ENABLE TRIGGER USER;
  ALTER TABLE internal.initial_preparation_admission_receipts ENABLE TRIGGER USER;
  payload:=NULL;
  IF EXISTS(SELECT 1 FROM internal.measure_initial_cancellation_private_images(scan) WHERE row_bytes>33554432)
   OR (SELECT sum(array_bytes) FROM internal.measure_initial_cancellation_private_images(scan))>=67108864 THEN
   RAISE EXCEPTION USING ERRCODE='ZX642'; END IF;
  IF mode='cpm_overflow' AND (cpm_bytes=0 OR baseline+4*per_row-cpm_bytes>67108864) THEN
   RAISE EXCEPTION USING ERRCODE='ZX643'; END IF;
  state_before:=pg_temp.size_state_digest();
  IF mode='accepted_escaped' THEN
   result:=internal.capture_initial_accounted_cancellation_prestate(owner_id,scan);
   measured:=octet_length(result::TEXT);
   IF measured<>baseline+4*per_row OR measured NOT BETWEEN 67108861 AND 67108864 THEN
    RAISE EXCEPTION USING ERRCODE='ZX644'; END IF;
   result:=NULL;
  ELSE
   -- Reaching the first aggregate is an explicit failure, even if a later
   -- final-size check would reject. This replacement is rolled back below.
   EXECUTE $replace$CREATE OR REPLACE FUNCTION internal.capture_initial_cancellation_private_images(p_scan UUID)
    RETURNS JSONB LANGUAGE plpgsql SET search_path='' AS $body$ BEGIN
     RAISE EXCEPTION 'aggregate reached before size rejection' USING ERRCODE='ZX645'; END; $body$;$replace$;
   BEGIN
    SET LOCAL ROLE service_role;
    PERFORM public.cancel_initial_analysis(owner_id,scan);
    RESET ROLE;
    RAISE EXCEPTION USING ERRCODE='ZX646';
   EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;
    RESET ROLE;
   END;
   IF code<>'55000' OR message<>'initial_analysis_cancellation_incomplete'
    OR pg_temp.size_state_digest() IS DISTINCT FROM state_before
    OR EXISTS(SELECT 1 FROM public.ai_usage_events)
    OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE event_id IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='ZX647'; END IF;
  END IF;
  RAISE EXCEPTION 'pass' USING ERRCODE='Z0001';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;
  RETURN code||':'||message;
 END;
END; $$;
SELECT extensions.is(pg_temp.size_probe('duplicated_overflow'),'Z0001:pass','individually bounded duplicated rows reject before aggregation and undo accounting');
SELECT extensions.is(pg_temp.size_probe('accepted_escaped'),'Z0001:pass','escaped multibyte near-limit composite matches exact serialized estimate');
-- The runner includes this final assertion only for CPM admission.
-- CPM_ONLY_BEGIN
SELECT extensions.is(pg_temp.size_probe('cpm_overflow'),'Z0001:pass','retained CPM bytes push an otherwise-fitting composite over the unchanged limit');
-- CPM_ONLY_END
SELECT extensions.finish();
ROLLBACK;
