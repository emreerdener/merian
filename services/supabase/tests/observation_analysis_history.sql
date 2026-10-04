\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(30);

SELECT extensions.ok(
    NOT (SELECT enrollment_enabled FROM internal.observation_history_rollout WHERE singleton),
    'enrollment defaults closed until runtime gates are implemented');
SELECT extensions.ok(NOT EXISTS (
    SELECT 1 FROM pg_catalog.UNNEST(ARRAY['anon','authenticated','service_role']) role_name,
        pg_catalog.UNNEST(ARRAY['observation_history_rollout','observation_histories',
            'observation_analysis_results','observation_analysis_authorities','observation_selection_receipts']) table_name
    WHERE pg_catalog.HAS_TABLE_PRIVILEGE(role_name,'internal.' || table_name,'SELECT')
       OR pg_catalog.HAS_TABLE_PRIVILEGE(role_name,'internal.' || table_name,'INSERT')
       OR pg_catalog.HAS_TABLE_PRIVILEGE(role_name,'internal.' || table_name,'UPDATE')
       OR pg_catalog.HAS_TABLE_PRIVILEGE(role_name,'internal.' || table_name,'DELETE')
), 'all API roles lack direct history access even for publicly readable observations');
SELECT extensions.ok(NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='internal' AND c.relname IN ('observation_history_rollout','observation_histories',
        'observation_analysis_results','observation_analysis_authorities','observation_selection_receipts') AND NOT c.relrowsecurity
), 'history storage has default-deny RLS');

CREATE TEMP TABLE history_fixture AS SELECT
    '00000000-0000-4000-8000-00000000d101'::UUID owner_id,
    '00000000-0000-4000-8000-00000000d111'::UUID observation_id,
    '00000000-0000-4000-8000-00000000d112'::UUID second_observation_id,
    '00000000-0000-4000-8000-00000000d121'::UUID analysis_a,
    '00000000-0000-4000-8000-00000000d122'::UUID analysis_b;
DO $$ DECLARE f history_fixture%ROWTYPE; BEGIN
    SELECT * INTO f FROM history_fixture;
    INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    VALUES(f.owner_id,'authenticated','authenticated','history-fixture@example.invalid','{}','{}',NOW(),NOW());
    INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
    VALUES(f.observation_id::TEXT,f.owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted'),
        (f.second_observation_id::TEXT,f.owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
    INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture)
    VALUES(f.observation_id,f.owner_id,'{}',0.9,TRUE,'flash','open',TRUE),
        (f.second_observation_id,f.owner_id,'{}',0.9,TRUE,'flash','private',TRUE);
END $$;

SELECT extensions.throws_ok(
    'INSERT INTO internal.observation_histories(observation_id) SELECT observation_id FROM history_fixture',
    '55000','analysis_history_unavailable','closed rollout rejects enrollment at the storage boundary');

DELETE FROM internal.observation_history_rollout;
SELECT extensions.throws_ok(
    'INSERT INTO internal.observation_histories(observation_id) SELECT observation_id FROM history_fixture',
    '55000','analysis_history_unavailable','missing rollout configuration also fails closed');
INSERT INTO internal.observation_history_rollout(singleton) VALUES(TRUE);

-- Only this rollback-scoped database-owner fixture enables storage to exercise
-- its constraints. No live endpoint can change the rollout row.
UPDATE internal.observation_history_rollout SET enrollment_enabled=TRUE;
INSERT INTO internal.observation_histories(observation_id)
SELECT observation_id FROM history_fixture UNION ALL SELECT second_observation_id FROM history_fixture;
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,result_snapshot,evidence_manifest,completed_at)
SELECT analysis_a,observation_id,1,pg_catalog.REPEAT('a',64),'{"fixture":"A"}'::JSONB,'{"schema_version":1,"captured_media":[]}'::JSONB,NOW() FROM history_fixture
UNION ALL SELECT analysis_b,observation_id,2,pg_catalog.REPEAT('b',64),'{"fixture":"B"}'::JSONB,'{"schema_version":1,"captured_media":[]}'::JSONB,NOW() FROM history_fixture;
INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
SELECT observation_id,analysis_a,'{"fixture":"unreviewed"}'::JSONB FROM history_fixture
UNION ALL SELECT observation_id,analysis_b,'{"fixture":"unreviewed"}'::JSONB FROM history_fixture;
UPDATE internal.observation_histories h SET selected_analysis_id=f.analysis_a,selection_initialized=TRUE,state_revision=10
FROM history_fixture f WHERE h.observation_id=f.observation_id;

SELECT extensions.throws_ok(
    'UPDATE internal.observation_histories SET active_projection=pg_catalog.JSONB_BUILD_OBJECT(''oversized'',pg_catalog.REPEAT(''a'',32769))',
    '23514',NULL,'active projection is byte bounded');
UPDATE internal.observation_histories SET state_revision=2147483646 WHERE observation_id=(SELECT observation_id FROM history_fixture);
SELECT extensions.throws_ok(
    'UPDATE internal.observation_analysis_authorities SET review_revision=1,review_snapshot=''{}'' WHERE analysis_id=(SELECT analysis_b FROM history_fixture)',
    '55000','analysis_history_unavailable','revision exhaustion matches the wire failure contract');
UPDATE internal.observation_histories SET state_revision=10 WHERE observation_id=(SELECT observation_id FROM history_fixture);

SELECT extensions.throws_ok(
    'UPDATE internal.observation_analysis_results SET result_snapshot=''{}''',
    '22023','analysis_history_evidence_immutable','stored AI evidence cannot be overwritten');
SELECT extensions.throws_ok(
    'UPDATE internal.observation_analysis_authorities SET review_snapshot=''{}''',
    '40001','analysis_history_revision_conflict','authority edits require advancing the review revision');
UPDATE internal.observation_analysis_authorities a SET review_revision=1,review_snapshot='{"fixture":"rejected"}'
FROM history_fixture f WHERE a.analysis_id=f.analysis_b;
SELECT extensions.is((SELECT state_revision FROM internal.observation_histories WHERE observation_id=(SELECT observation_id FROM history_fixture)),11,
    'authority change to inactive B advances the observation revision while A stays selected');
SELECT extensions.is((SELECT selected_analysis_id FROM internal.observation_histories WHERE observation_id=(SELECT observation_id FROM history_fixture)),
    (SELECT analysis_a FROM history_fixture),'review change never selects another result');

DO $$ DECLARE f history_fixture%ROWTYPE; denied BOOLEAN := FALSE; BEGIN
    SELECT * INTO f FROM history_fixture;
    BEGIN
        UPDATE internal.observation_histories SET selected_analysis_id=f.analysis_a,selection_initialized=TRUE
        WHERE observation_id=f.second_observation_id;
        SET CONSTRAINTS internal.observation_history_selected_result_fk IMMEDIATE;
    EXCEPTION WHEN foreign_key_violation THEN denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'cross-observation selection accepted'; END IF;
END $$;
SELECT extensions.pass('selected result must belong to the same observation');

CREATE FUNCTION pg_temp.select_history(target UUID, revision INTEGER, operation_suffix TEXT DEFAULT 'd131', review_revision INTEGER DEFAULT 0)
RETURNS JSONB LANGUAGE SQL AS $$
    SELECT internal.select_observation_analysis(owner_id,pg_catalog.JSONB_BUILD_OBJECT(
        'schema_version',1,'observation_id',observation_id,'analysis_id',target,
        'operation_id','00000000-0000-4000-8000-00000000' || operation_suffix,
        'expected_observation_revision',revision,'expected_review_revision',review_revision))
    FROM history_fixture;
$$;
SELECT extensions.ok(NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('service_role','internal.select_observation_analysis(uuid,jsonb)','EXECUTE'),
    'selection remains private until connected consumer activation gates are complete');
SELECT extensions.throws_ok(
    'SELECT pg_temp.select_history(analysis_b,11,''d131'',1) FROM history_fixture',
    '55000','analysis_history_unavailable','selection defaults closed independently of retained reads');
UPDATE internal.observation_history_rollout SET selection_enabled=TRUE;
SELECT extensions.is((SELECT pg_temp.select_history(analysis_b,11,'d131',1) ->> 'observation_revision' FROM history_fixture),
    '12','selection commits target and advances revision');
SELECT extensions.is((SELECT pg_temp.select_history(analysis_a,12,'d132') ->> 'observation_revision' FROM history_fixture),
    '13','restoring A preserves monotonic revision across A to B to A');
SELECT extensions.is((SELECT pg_temp.select_history(analysis_b,11,'d131',1) ->> 'observation_revision' FROM history_fixture),
    '12','lost response replay returns the original receipt');
SELECT extensions.is((SELECT state_revision FROM internal.observation_histories WHERE observation_id=(SELECT observation_id FROM history_fixture)),
    13,'replayed revision 12 cannot restore obsolete selection over revision 13');
SELECT extensions.is((SELECT COUNT(*) FROM internal.observation_history_reconciliation WHERE observation_id=(SELECT observation_id FROM history_fixture)),
    3::BIGINT,'review and selections each persist one reconciliation obligation; replay adds none');
SELECT extensions.throws_ok(
    'SELECT pg_temp.select_history(analysis_a,11,''d131'') FROM history_fixture',
    '22023','analysis_history_operation_conflict','reused operation identity cannot carry another choice');
SELECT extensions.throws_ok(
    'SELECT pg_temp.select_history(analysis_b,12,''d133'',1) FROM history_fixture',
    '40001','analysis_history_revision_conflict','stale Undo cannot overwrite the newer state');
SELECT extensions.ok((SELECT active_projection IS NOT NULL FROM internal.observation_histories WHERE observation_id=(SELECT observation_id FROM history_fixture)),
    'selection, current authority projection and receipt commit together');
SELECT extensions.throws_ok(
    'SELECT internal.observation_analysis_projection(''{}'', ''{"ai_identification_review":{"community":{"rank":"species","species_id":"00000000-0000-4000-8000-00000000d199"}}}'')',
    '55000','analysis_history_unavailable','malformed stored community authority cannot confer a species');


DO $$ DECLARE f history_fixture%ROWTYPE; result TEXT; BEGIN
    SELECT * INTO f FROM history_fixture;
    SET LOCAL ROLE service_role;
    result := public.request_scan_deletion(f.observation_id, f.owner_id);
    RESET ROLE;
    IF result IS DISTINCT FROM 'legacy_observation_delete_requires_upgrade' THEN
        RAISE EXCEPTION 'legacy history deletion was not rejected';
    END IF;
END $$;
SELECT extensions.pass('queued legacy replacement deletion rejects before fencing history');
SELECT extensions.ok(NOT EXISTS (SELECT 1 FROM internal.scan_deletion_tombstones
    WHERE scan_id=(SELECT observation_id FROM history_fixture)), 'legacy rejection creates no tombstone');

DO $$ DECLARE f history_fixture%ROWTYPE; removed INTEGER; BEGIN
    SELECT * INTO f FROM history_fixture;
    INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
    VALUES('00000000-0000-4000-8000-00000000d113',f.owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
    INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture,timestamp)
    VALUES('00000000-0000-4000-8000-00000000d113',f.owner_id,'{}',0,FALSE,'flash','private',TRUE,NOW()-INTERVAL '31 days');
    UPDATE public.scans SET is_biological_subject=FALSE,timestamp=NOW()-INTERVAL '31 days'
    WHERE id IN (f.observation_id,f.second_observation_id);
    SET LOCAL ROLE service_role;
    removed := public.request_nonbiological_scan_retention_deletions(500);
    RESET ROLE;
    IF removed <> 1 THEN RAISE EXCEPTION 'retention did not exclusively fence legacy scan'; END IF;
END $$;
SELECT extensions.pass('non-biological expiry excludes retained observations while legacy expiry continues');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones
    WHERE scan_id IN (SELECT observation_id FROM history_fixture UNION ALL SELECT second_observation_id FROM history_fixture)),
    'selecting a non-biological result cannot authorize expiry of retained history');

DO $$ DECLARE f history_fixture%ROWTYPE; BEGIN
    SELECT * INTO f FROM history_fixture;
    INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES(f.second_observation_id,f.owner_id);
END $$;
SELECT extensions.throws_ok(
    'UPDATE internal.observation_histories SET state_revision=state_revision+1 WHERE observation_id=(SELECT second_observation_id FROM history_fixture)',
    'P0002','analysis_history_deleted','parent deletion fence prevents later history writes');

DELETE FROM public.scans WHERE id=(SELECT observation_id FROM history_fixture);
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results),
    'individual scan erasure cascades retained analyses and authority');

DO $$ DECLARE f history_fixture%ROWTYPE; BEGIN
    SELECT * INTO f FROM history_fixture;
    SET LOCAL ROLE service_role;
    PERFORM public.apply_user_tombstone(f.owner_id);
    RESET ROLE;
END $$;
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.observation_histories),
    'account detachment removes private history even when the scientific parent remains');

SELECT * FROM extensions.finish();
ROLLBACK;
