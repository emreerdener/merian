-- Mechanical witness tests only. The transaction temporarily isolates the real
-- result table from legacy admission triggers (FKs remain active), then attaches the dormant
-- adapter. This does NOT qualify original authority or the business write graph.
-- Every change, synthetic row and trigger alteration rolls back.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES('00000000-0000-4000-8000-000000000202','authenticated','authenticated','s0-stage-synthetic@example.invalid','{}','{}',now(),now());
ALTER TABLE internal.initial_analysis_submissions DISABLE TRIGGER USER;
INSERT INTO internal.initial_analysis_submissions VALUES('00000000-0000-4000-8000-000000000201','00000000-0000-4000-8000-000000000202','identify-multimodal',1,'{}','[]','{}','{}');
ALTER TABLE internal.initial_analysis_submissions ENABLE TRIGGER USER;
ALTER TABLE internal.initial_analysis_results DISABLE TRIGGER USER;
CREATE TRIGGER s0_test_statement_before BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON internal.initial_analysis_results
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member();
CREATE TRIGGER s0_test_statement_after AFTER INSERT OR UPDATE OR DELETE ON internal.initial_analysis_results
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member();
CREATE TRIGGER s0_test_row_before BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_analysis_results
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member();
CREATE TRIGGER s0_test_row_after AFTER INSERT OR UPDATE OR DELETE ON internal.initial_analysis_results
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member();
CREATE FUNCTION pg_temp.result_image() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT '{"scan_id":"00000000-0000-4000-8000-000000000201","owner_id":"00000000-0000-4000-8000-000000000202","result_evidence_id":"00000000-0000-4000-8000-000000000203","result_schema_version":1,"result_snapshot":{},"provenance_snapshot":{}}'::JSONB
$$;
CREATE FUNCTION pg_temp.stage_result() RETURNS VOID LANGUAGE SQL AS $$
 INSERT INTO internal.initial_consuming_staging(transaction_id,scan_id,owner_id,operation,admission_receipt_id,
 admission_receipt_digest,reservation_id,invocation_id,result_evidence_id,expected_writes)
 SELECT pg_current_xact_id(),'00000000-0000-4000-8000-000000000201','00000000-0000-4000-8000-000000000202','result',
 '00000000-0000-4000-8000-000000000204',repeat('a',64),'00000000-0000-4000-8000-000000000205',
 '00000000-0000-4000-8000-000000000206','00000000-0000-4000-8000-000000000203',
 jsonb_build_array(jsonb_build_array(jsonb_build_object('old',NULL,'new',pg_temp.result_image())))
$$;
CREATE FUNCTION pg_temp.write_result(image JSONB) RETURNS VOID LANGUAGE SQL AS $$
 INSERT INTO internal.initial_analysis_results SELECT * FROM jsonb_populate_record(NULL::internal.initial_analysis_results,image)
$$;
CREATE FUNCTION pg_temp.suppress_result() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END $$;
CREATE FUNCTION pg_temp.change_result() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN NEW.result_snapshot:='{"changed":true}'; RETURN NEW; END $$;
CREATE FUNCTION pg_temp.stage_case(mode TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
 BEGIN
  IF mode='rolled_back_entry' THEN
   BEGIN
    PERFORM pg_temp.stage_result();
    RAISE EXCEPTION 'rollback entry' USING ERRCODE='Z0002';
   EXCEPTION WHEN SQLSTATE 'Z0002' THEN NULL; END;
  END IF;
  IF mode='already_immediate' THEN SET CONSTRAINTS ALL IMMEDIATE; END IF;
  PERFORM pg_temp.stage_result();
  CASE mode
   WHEN 'leftover' THEN SET CONSTRAINTS ALL IMMEDIATE;
   WHEN 'early_delete' THEN DELETE FROM internal.initial_consuming_staging;
   WHEN 'direct_progress' THEN UPDATE internal.initial_consuming_staging SET statement_active=TRUE;
   WHEN 'identity_change' THEN UPDATE internal.initial_consuming_staging SET owner_id='00000000-0000-4000-8000-000000000299';
   WHEN 'expected_change' THEN UPDATE internal.initial_consuming_staging SET expected_writes='[]';
   WHEN 'nested' THEN PERFORM pg_temp.stage_result();
   WHEN 'stage_truncate' THEN TRUNCATE internal.initial_consuming_staging;
   WHEN 'member_truncate' THEN TRUNCATE internal.initial_analysis_results CASCADE;
   WHEN 'wrong_operation' THEN UPDATE internal.initial_analysis_results SET result_schema_version=1 WHERE FALSE;
   WHEN 'wrong_image' THEN PERFORM pg_temp.write_result(pg_temp.result_image()||'{"result_snapshot":{"changed":true}}');
   WHEN 'duplicate_before' THEN INSERT INTO internal.initial_analysis_results SELECT r.* FROM jsonb_populate_record(NULL::internal.initial_analysis_results,pg_temp.result_image()) r CROSS JOIN generate_series(1,2);
   WHEN 'zero_rows' THEN INSERT INTO internal.initial_analysis_results SELECT * FROM jsonb_populate_record(NULL::internal.initial_analysis_results,pg_temp.result_image()) WHERE FALSE;
   WHEN 'missing_after' THEN ALTER TABLE internal.initial_analysis_results DISABLE TRIGGER s0_test_row_after;
   WHEN 'missing_before' THEN ALTER TABLE internal.initial_analysis_results DISABLE TRIGGER s0_test_row_before;
   WHEN 'suppressed_row' THEN CREATE TRIGGER zzzz_suppress BEFORE INSERT ON internal.initial_analysis_results FOR EACH ROW EXECUTE FUNCTION pg_temp.suppress_result();
   WHEN 'changed_after_before' THEN CREATE TRIGGER zzzz_change BEFORE INSERT ON internal.initial_analysis_results FOR EACH ROW EXECUTE FUNCTION pg_temp.change_result();
   WHEN 'caught_statement' THEN
    BEGIN
     PERFORM pg_temp.write_result(pg_temp.result_image()||'{"result_snapshot":{"changed":true}}');
    EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
    IF EXISTS(SELECT 1 FROM internal.initial_consuming_staging WHERE statement_active OR pending_rows<>'{}'::INTEGER[] OR observed_rows<>'{}'::INTEGER[] OR next_statement<>0) THEN
     RAISE EXCEPTION 'partial progress survived'; END IF;
   ELSE NULL;
  END CASE;
  PERFORM pg_temp.write_result(pg_temp.result_image());
  IF NOT (SELECT sealed AND NOT statement_active AND pending_rows='{}'::INTEGER[] AND next_statement=1 FROM internal.initial_consuming_staging) THEN
   RAISE EXCEPTION 'stage not sealed'; END IF;
  IF mode='extra_statement' THEN PERFORM pg_temp.write_result(pg_temp.result_image()); END IF;
  DELETE FROM internal.initial_consuming_staging;
  IF mode='reuse' THEN PERFORM pg_temp.stage_result(); END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE EXCEPTION 'success rollback' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN RETURN 'ok';
 END;
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE||':'||SQLERRM;
END $$;
SELECT extensions.is(pg_temp.stage_case(mode),expected,mode) FROM (VALUES
 ('valid','ok'),('caught_statement','ok'),('rolled_back_entry','ok'),
 ('already_immediate','55000:initial_analysis_consuming_stage_incomplete'),
 ('leftover','55000:initial_analysis_consuming_stage_incomplete'),
 ('early_delete','55000:initial_analysis_consuming_stage_incomplete'),
 ('direct_progress','55000:initial_analysis_consuming_stage_invalid'),
 ('identity_change','55000:initial_analysis_consuming_stage_invalid'),
 ('expected_change','55000:initial_analysis_consuming_stage_invalid'),
 ('nested','55000:initial_analysis_consuming_stage_reused'),
 ('reuse','55000:initial_analysis_consuming_stage_reused'),
 ('stage_truncate','55006:cannot TRUNCATE "initial_consuming_staging" because it has pending trigger events'),
 ('member_truncate','55000:initial_analysis_consuming_statement_invalid'),
 ('wrong_operation','55000:initial_analysis_consuming_statement_invalid'),
 ('wrong_image','55000:initial_analysis_consuming_row_invalid'),
 ('duplicate_before','55000:initial_analysis_consuming_row_invalid'),
 ('zero_rows','55000:initial_analysis_consuming_stage_incomplete'),
 ('missing_after','55000:initial_analysis_consuming_stage_incomplete'),
 ('missing_before','55000:initial_analysis_consuming_row_invalid'),
 ('suppressed_row','55000:initial_analysis_consuming_stage_incomplete'),
 ('changed_after_before','55000:initial_analysis_consuming_row_invalid'),
 ('extra_statement','55000:initial_analysis_consuming_statement_invalid')) cases(mode,expected);
SELECT extensions.is((SELECT count(*) FROM internal.initial_consuming_staging),0::BIGINT,'all isolated cases roll back their stage');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_results),0::BIGINT,'all isolated result writes roll back');
SELECT extensions.throws_ok($$SELECT internal.assert_initial_consuming_expectations('report','[[],[]]')$$,'22023','initial_analysis_consuming_expectations_invalid','report requires one exact attempted image and invocation linkage');
SELECT extensions.throws_ok($$SELECT internal.assert_initial_consuming_expectations('complete','[]')$$,'22023','initial_analysis_consuming_operation_unavailable','completion remains closed');
SELECT extensions.throws_ok($$SELECT internal.assert_initial_consuming_expectations('result','[[]]')$$,'22023','initial_analysis_consuming_expectations_invalid','result requires exactly one row');
SELECT extensions.throws_ok($$SELECT internal.assert_initial_consuming_expectations('result','[[{"old":null,"new":{}}]]')$$,'22023','initial_analysis_consuming_image_invalid','result image must have exact columns');
SELECT extensions.ok(NOT has_table_privilege(role_name,'internal.initial_consuming_staging',privilege),role_name||' denied stage '||privilege)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) privilege;
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),role_name||' denied '||signature)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY[
 'internal.assert_initial_consuming_expectations(text,jsonb)','internal.guard_initial_consuming_stage()',
 'internal.require_complete_initial_consuming_stage()','internal.guard_initial_consuming_member()']) signature;
SELECT extensions.ok(relrowsecurity,'stage RLS enabled') FROM pg_class WHERE oid='internal.initial_consuming_staging'::regclass;
SELECT extensions.throws_ok($$TRUNCATE internal.initial_consuming_staging$$,'55000','initial_analysis_consuming_stage_invalid','empty stage truncation denied by its trigger');
CREATE FUNCTION pg_temp.api_stage_denied(role_name TEXT,write_attempt BOOLEAN) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
 EXECUTE format('SET LOCAL ROLE %I',role_name);
 IF write_attempt THEN
  INSERT INTO internal.initial_consuming_staging(transaction_id) VALUES(pg_current_xact_id());
 ELSE
  PERFORM * FROM internal.initial_consuming_staging;
 END IF;
 RESET ROLE;
 RETURN FALSE;
EXCEPTION WHEN insufficient_privilege THEN RETURN TRUE;
END $$;
SELECT extensions.ok(pg_temp.api_stage_denied(role_name,write_attempt),role_name||' actual stage access denied, write='||write_attempt)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY[FALSE,TRUE]) write_attempt;
-- Isolate existing business guards only; retain real row checks and FKs. The
-- dispatch fixture stops after the original-link group and rolls back. It does
-- not claim invocation creation, live dispatch authority or terminal proof.
ALTER TABLE internal.ai_quota_reservations DISABLE TRIGGER USER;
ALTER TABLE internal.ai_quota_reservation_counters DISABLE TRIGGER USER;
INSERT INTO internal.ai_quota_reservations(id,user_id,operation,request_id,model,effective_plan,effective_tier,subscription_tier,trial_active,entitlement_version,policy_version,lease_token)
 VALUES('00000000-0000-4000-8000-000000000205','00000000-0000-4000-8000-000000000202','scan_identification','00000000-0000-4000-8000-000000000201','synthetic','free','free','free',FALSE,1,1,'00000000-0000-4000-8000-000000000207');
INSERT INTO internal.ai_quota_reservation_counters VALUES
 ('00000000-0000-4000-8000-000000000205','user_daily','synthetic','daily','2000-01-01Z'),
 ('00000000-0000-4000-8000-000000000205','user_rate','synthetic','minute','2000-01-01Z');
DO $$ DECLARE relation_name TEXT; BEGIN
 FOREACH relation_name IN ARRAY ARRAY['internal.ai_quota_reservations','internal.ai_quota_reservation_counters'] LOOP
  EXECUTE format('CREATE TRIGGER s0_test_statement_before BEFORE INSERT OR UPDATE OR DELETE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member()',relation_name);
  EXECUTE format('CREATE TRIGGER s0_test_statement_after AFTER INSERT OR UPDATE OR DELETE ON %s FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_consuming_member()',relation_name);
  EXECUTE format('CREATE TRIGGER s0_test_row_before BEFORE INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member()',relation_name);
  EXECUTE format('CREATE TRIGGER s0_test_row_after AFTER INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_consuming_member()',relation_name);
 END LOOP;
END $$;
CREATE TEMP TABLE pending_peak(value INTEGER);
CREATE FUNCTION pg_temp.observe_link_pending() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO pending_peak SELECT cardinality(pending_rows) FROM internal.initial_consuming_staging;
 RETURN OLD;
END $$;
CREATE TRIGGER zzzz_observe BEFORE DELETE ON internal.ai_quota_reservation_counters FOR EACH ROW EXECUTE FUNCTION pg_temp.observe_link_pending();
CREATE FUNCTION pg_temp.link_case(mode TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE quota JSONB; links JSONB; invocation JSONB;
BEGIN
 BEGIN
  SELECT internal.initial_consuming_row_image('internal.ai_quota_reservations',to_jsonb(q)) INTO quota FROM internal.ai_quota_reservations q
   WHERE id='00000000-0000-4000-8000-000000000205';
  SELECT jsonb_agg(jsonb_build_object('old',to_jsonb(l),'new',NULL) ORDER BY scope_type) INTO links FROM internal.ai_quota_reservation_counters l;
  SELECT to_jsonb(jsonb_populate_record(NULL::internal.identification_invocations,'{}')) INTO invocation;
  INSERT INTO internal.initial_consuming_staging(transaction_id,scan_id,owner_id,operation,admission_receipt_id,admission_receipt_digest,reservation_id,invocation_id,expected_writes)
  VALUES(pg_current_xact_id(),'00000000-0000-4000-8000-000000000201','00000000-0000-4000-8000-000000000202','dispatch',
   '00000000-0000-4000-8000-000000000204',repeat('a',64),'00000000-0000-4000-8000-000000000205','00000000-0000-4000-8000-000000000206',
   jsonb_build_array(jsonb_build_array(jsonb_build_object('old',quota,'new',quota||'{"state":"committed"}')),links,
    jsonb_build_array(jsonb_build_object('old',NULL,'new',invocation)),
    jsonb_build_array(jsonb_build_object('old','{"scan_id":null,"state":"pending_pre_dispatch"}'::JSONB,'new','{"scan_id":null,"state":"dispatch_authorized"}'::JSONB))));
  UPDATE internal.ai_quota_reservations SET state='committed' WHERE id='00000000-0000-4000-8000-000000000205';
  IF mode='suppressed' THEN
   CREATE TRIGGER zzzz_suppress BEFORE DELETE ON internal.ai_quota_reservation_counters FOR EACH ROW EXECUTE FUNCTION pg_temp.suppress_result();
  END IF;
  DELETE FROM internal.ai_quota_reservation_counters WHERE mode<>'missing' OR scope_type='user_daily';
  IF NOT (SELECT next_statement=2 AND NOT sealed AND NOT statement_active AND pending_rows='{}'::INTEGER[] FROM internal.initial_consuming_staging)
     OR (SELECT max(value) FROM pending_peak)<>2 THEN RAISE EXCEPTION 'multiple pending rows were not paired'; END IF;
  RAISE EXCEPTION 'success rollback' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN RETURN 'ok'; END;
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE||':'||SQLERRM;
END $$;
SELECT extensions.is(pg_temp.link_case('valid'),'ok','two BEFORE deletes queue before paired AFTER consumption');
SELECT extensions.is(pg_temp.link_case('missing'),'55000:initial_analysis_consuming_stage_incomplete','missing original link denies statement completion');
SELECT extensions.is(pg_temp.link_case('suppressed'),'55000:initial_analysis_consuming_stage_incomplete','suppressed original link leaves pending evidence and denies completion');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservation_counters),2::BIGINT,'link changes roll back');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id='00000000-0000-4000-8000-000000000205'),'reserved','quota transition rolls back with incomplete dispatch');

SELECT * FROM extensions.finish();
ROLLBACK;
