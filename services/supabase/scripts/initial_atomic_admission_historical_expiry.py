"""Historical expiry qualification; never a fresh no-media admission path."""
import uuid


def legacy_media_expiry_cases(qualification):
    execute = qualification.execute
    qualification.record['scope'] = ('Historical unadmitted media assignment-v2 fixture; trusted rollback-only timeline/codec projection before seven actual service wrappers. Fresh catalog setup is rolled back per case; no production legacy writer, funding or provider IO.')
    fixture, owner, _ = qualification.fixture_prefix(held=False)
    scan = str(uuid.uuid4())
    setup = "DO $$ DECLARE a JSONB;BEGIN\n PERFORM pg_temp.media_create('SCAN',1);SET CONSTRAINTS ALL IMMEDIATE;\n ALTER TABLE internal.initial_analysis_preparation_intents DISABLE TRIGGER guard_initial_preparation_storage;\n SELECT jsonb_set(canonical_assignment::JSONB-'handoff','{version}','2') INTO a FROM internal.initial_analysis_preparation_intents WHERE scan_id='SCAN';\n UPDATE internal.initial_analysis_preparation_intents SET canonical_assignment=internal.initial_canonical(a),assignment_digest=internal.initial_preparation_digest('assignment',internal.initial_canonical(a)),created_at=statement_timestamp()-INTERVAL '301 seconds',expires_at=statement_timestamp()-INTERVAL '1 second' WHERE scan_id='SCAN';\n ALTER TABLE internal.initial_analysis_preparation_intents ENABLE TRIGGER guard_initial_preparation_storage;\n SET CONSTRAINTS ALL IMMEDIATE;SET CONSTRAINTS ALL DEFERRED;\nEND $$;\n".replace('SCAN', scan)
    check = "RESET ROLE;\n IF result->>'outcome' IS DISTINCT FROM EXPECTED OR result->>'version' IS DISTINCT FROM VERSION\n OR (SELECT dispatch FROM internal.initial_analysis_cancellations WHERE scan_id='SCAN') IS DISTINCT FROM 'dispatch_prevented'\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id='SCAN')\n OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE request_id='SCAN')\n OR internal.initial_cancellation_sealed()\n THEN RAISE EXCEPTION USING ERRCODE='ZX471';END IF;\n UPDATE public.users SET id=id WHERE FALSE;\n".replace('SCAN', scan)
    for kind in ['create', 'status', 'sources', 'issue', 'output', 'outcome', 'execution_status']:
        start = "DO $$ DECLARE result JSONB;c TEXT;ad TEXT;BEGIN SELECT canonical_candidate,assignment_digest INTO STRICT c,ad FROM internal.initial_analysis_preparation_intents WHERE scan_id='" + scan + "';SET LOCAL ROLE service_role;"
        if kind == 'create':
            call = "result:=public.create_initial_preparation_intent('" + owner + "','" + scan + "',c);"
            expected = "'expired'"
        elif kind == 'status':
            call = "result:=public.get_initial_preparation_status('" + owner + "','" + scan + "');"
            expected = "'expired'"
        else:
            names = {'sources': 'settle_initial_preparation_sources', 'issue': 'issue_initial_preparation_execution', 'output': 'register_initial_preparation_output', 'outcome': 'settle_initial_preparation_outcome', 'execution_status': 'get_initial_preparation_execution_status'}
            action = 'status' if kind == 'execution_status' else kind
            call = 'result:=public.' + names[kind] + "('" + owner + "','" + scan + "',ad" + ('' if kind == 'execution_status' else ',NULL') + ');'
            expected = "'held'"
        execute('expired_v2_' + kind, fixture + setup + start + call + check.replace('EXPECTED', expected).replace('VERSION', "'2'" if kind in ['create', 'status'] else "'1'") + 'END $$;SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;')


class HistoricalNoMediaFixture:
    """Read exact historical vectors only; never construct a fresh admission."""

    def __init__(self):
        import json
        import re
        from initial_atomic_admission_test_support import ROOT

        source = ROOT / 'services/supabase/tests/initial_saved_assignment.sql'
        text = source.read_text()
        start = 'CREATE FUNCTION pg_temp.admission_owner('
        end = 'CREATE FUNCTION pg_temp.admission_input()'
        if text.count(start) != 1 or text.count(end) != 1:
            raise ValueError('historical helper boundaries changed')
        self.helper = text[text.index(start):text.index(end)]
        vectors = re.findall(r"CREATE TEMP TABLE v2_vectors AS SELECT '(.*?)'::JSONB v;", text)
        if len(vectors) != 1:
            raise ValueError('unique historical vector required')
        self.vector = vectors[0]
        value = json.loads(self.vector)
        if value['candidate']['variant'] != 'no_media' or value['candidate']['input']['media'] != []:
            raise ValueError('historical no-media vector required')
        self.owner = str(uuid.uuid4())
        self.scans = [str(uuid.uuid4()) for _ in range(3)]


def historical_no_media_expiry_cases(qualification):
    run = qualification.execute
    qualification.record['scope'] = ('Privileged insertion of three already-expired historical no-media v2 intents; actual service create/status/finalize and exact original cancellation recovery. No fresh text admission, funding, provider, concurrency or external IO; activation remains false throughout.')
    fixture = HistoricalNoMediaFixture()
    helper, vector, owner, scans = fixture.helper, fixture.vector, fixture.owner, fixture.scans
    accounting = ['internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts', 'internal.identification_invocations', 'public.users']
    def image(table, where='TRUE'):
        return 'COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT) FROM ' + table + ' t WHERE ' + where + "),'[]'::JSONB)"
    acct = 'jsonb_build_object(' + ','.join(("'" + t + "'," + image(t) for t in accounting)) + ')'
    tripwire = "CREATE FUNCTION pg_temp.no_accounting_write() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN RAISE EXCEPTION USING ERRCODE='ZX581'; END $$;\n" + ''.join(('CREATE TRIGGER historical_expiry_no_accounting BEFORE INSERT OR UPDATE OR DELETE ON ' + t + ' FOR EACH ROW EXECUTE FUNCTION pg_temp.no_accounting_write();\n' for t in accounting))
    setup = 'BEGIN;' + helper + "CREATE TEMP TABLE historic_vector AS SELECT '" + vector + "'::JSONB v; SELECT pg_temp.admission_owner('" + owner + "'); SET CONSTRAINTS ALL IMMEDIATE; ALTER TABLE internal.initial_analysis_preparation_intents DISABLE TRIGGER guard_initial_preparation_storage;"
    for scan in scans:
        setup += "INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES('" + scan + "'); INSERT INTO internal.initial_analysis_preparation_intents(scan_id,owner_id,canonical_candidate,candidate_digest,canonical_assignment,assignment_digest,created_at,expires_at) SELECT '" + scan + "','" + owner + "',v->>'candidate_canonical',v->>'candidate_digest',v->>'assignment_canonical',v->>'assignment_digest','2000-01-01T00:00:00Z','2000-01-01T00:05:00Z' FROM historic_vector;"
    setup += "ALTER TABLE internal.initial_analysis_preparation_intents ENABLE TRIGGER guard_initial_preparation_storage; DO $$ BEGIN IF (SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout) OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='internal.initial_analysis_preparation_intents'::REGCLASS AND tgname='guard_initial_preparation_storage' AND tgenabled='O') OR (SELECT count(*) FROM internal.initial_analysis_preparation_intents)<>3 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations) THEN RAISE EXCEPTION USING ERRCODE='ZX580';END IF;END $$; SET CONSTRAINTS ALL IMMEDIATE;COMMIT;"
    run('historical_expired_fixture_committed_with_gate_false', setup)
    for (kind, scan) in zip(['create', 'status', 'finalize'], scans):
        prefix = "BEGIN;SELECT set_config('request.jwt.claim.role','service_role',TRUE);CREATE TEMP TABLE before_accounting AS SELECT " + acct + ' value;CREATE TEMP TABLE before_peers AS SELECT ' + image('internal.initial_analysis_preparation_intents', "scan_id<>'" + scan + "'") + ' value;' + tripwire
        call = {'create': "public.create_initial_preparation_intent('" + owner + "','" + scan + "',candidate)", 'status': "public.get_initial_preparation_status('" + owner + "','" + scan + "')", 'finalize': "public.finalize_initial_preparation('" + owner + "','" + scan + "',repeat('a',64))"}[kind]
        body = "DO $$ DECLARE result JSONB;candidate TEXT;BEGIN SELECT canonical_candidate INTO STRICT candidate FROM internal.initial_analysis_preparation_intents WHERE scan_id='" + scan + "'; SET LOCAL ROLE service_role;result:=" + call + ';RESET ROLE;IF result IS DISTINCT FROM \'{"version":2,"outcome":"expired"}\'::JSONB THEN RAISE EXCEPTION USING ERRCODE=\'ZX582\';END IF;'
        body += "IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id='" + scan + "') OR (SELECT owner_id FROM internal.initial_analysis_cancellations WHERE scan_id='" + scan + "') IS DISTINCT FROM '" + owner + "'::UUID OR (SELECT dispatch FROM internal.initial_analysis_cancellations WHERE scan_id='" + scan + "') IS DISTINCT FROM 'dispatch_prevented' OR (SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='" + scan + "') IS DISTINCT FROM 'cancelled_pre_dispatch' OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id='" + scan + "') THEN RAISE EXCEPTION USING ERRCODE='ZX583';END IF;"
        body += 'IF (SELECT value FROM before_accounting) IS DISTINCT FROM ' + acct + ' OR (SELECT value FROM before_peers) IS DISTINCT FROM ' + image('internal.initial_analysis_preparation_intents', "scan_id<>'" + scan + "'") + " OR internal.initial_cancellation_sealed() OR (SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout) OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions) THEN RAISE EXCEPTION USING ERRCODE='ZX584';END IF; PERFORM internal.assert_initial_cancellation_transients_absent('" + scan + "');END $$;"
        postchecks = body[body.index('IF EXISTS'):]
        body += 'SET CONSTRAINTS ALL IMMEDIATE;DO $$ BEGIN ' + postchecks
        body += ''.join(('DROP TRIGGER historical_expiry_no_accounting ON ' + t + ';\n' for t in accounting))
        run('actual_service_' + kind + '_expired_commits_without_accounting', prefix + body + 'SET CONSTRAINTS ALL IMMEDIATE;COMMIT;')
        replay = "BEGIN;SELECT set_config('request.jwt.claim.role','service_role',TRUE);CREATE TEMP TABLE before_all AS SELECT jsonb_build_object('accounting'," + acct + ",'intents'," + image('internal.initial_analysis_preparation_intents') + ",'cancel'," + image('internal.initial_analysis_cancellations') + ",'lifecycle'," + image('internal.initial_analysis_lifecycle_fences') + ") value;DO $$ DECLARE reply JSONB;BEGIN SET LOCAL ROLE service_role;reply:=public.cancel_initial_analysis('" + owner + "','" + scan + '\');RESET ROLE;IF reply IS DISTINCT FROM \'{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}\'::JSONB OR (SELECT value FROM before_all) IS DISTINCT FROM jsonb_build_object(\'accounting\',' + acct + ",'intents'," + image('internal.initial_analysis_preparation_intents') + ",'cancel'," + image('internal.initial_analysis_cancellations') + ",'lifecycle'," + image('internal.initial_analysis_lifecycle_fences') + ") OR internal.initial_cancellation_sealed() OR (SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout) THEN RAISE EXCEPTION USING ERRCODE='ZX585';END IF;PERFORM internal.assert_initial_cancellation_transients_absent('" + scan + "');END $$;COMMIT;"
        run('fresh_original_cancellation_replay_after_' + kind, replay)
