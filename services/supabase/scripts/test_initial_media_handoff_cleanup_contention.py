"""Transferred-source cleanup leases/markers across actual C1 and finish owners.

Only service-role SQL metadata queues are exercised; no physical erasure occurs.
Each single-object cohort is drained before the next admission, with exact global
queue-empty and whole-state oracles. Sessions use real locks without clock seams.
"""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import time

from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_sessions import BASE, Session
from initial_atomic_admission_test_support import Qualification, ROOT
from test_initial_media_handoff_contention import CANCEL, PRIVATE, TERMINAL, TRANSFER
from test_initial_media_handoff_owners import OPERATIONS
from test_initial_media_handoff_scan_contention import FULL, PROJECTION_RELATIONS, projection

FAMILIES = {
    'source': ('internal.initial_preparation_source_registry', 'initial_preparation_source_erasure'),
    'media': ('internal.initial_analysis_media_registry', 'initial_analysis_media_erasure'),
}
SOURCE_PAIR = """ OR (SELECT jsonb_agg(to_jsonb(t)||'{"retired":true}'::JSONB ORDER BY object_id) FROM source_before t)
 IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id)
"""
assert TERMINAL.count(SOURCE_PAIR) == 1
SOURCE_ROWS = "(SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_preparation_source_registry t WHERE scan_id=(SELECT scan_id FROM target))"


def terminal(source_digest):
    assert re.fullmatch('[0-9a-f]{32}', source_digest)
    return TERMINAL.replace(SOURCE_PAIR, " OR md5((" + SOURCE_ROWS + ")::TEXT) IS DISTINCT FROM '" + source_digest + "'\n")


def empty(kind):
    _, function = FAMILIES[kind]
    return "DO $$ DECLARE b JSONB;v JSONB;BEGIN b:=" + FULL + ";SET LOCAL ROLE service_role;v:=public.claim_" + function + "();RESET ROLE;IF v IS DISTINCT FROM '{\"version\":1,\"outcome\":\"empty\"}'::JSONB OR b IS DISTINCT FROM " + FULL + " THEN RAISE EXCEPTION USING ERRCODE='ZX830';END IF;END $$;"


def claim(kind):
    table, function = FAMILIES[kind]
    others = projection([r for r in PROJECTION_RELATIONS if r != table])
    rows = "(SELECT coalesce(jsonb_object_agg(object_id,to_jsonb(t)),'{}'::JSONB) FROM " + table + ' t)'
    return """DO $$ DECLARE b JSONB;all_rows JSONB;v JSONB;old_row JSONB;new_row JSONB;o UUID;started TIMESTAMPTZ;BEGIN
b:=OTHERS;all_rows:=ROWS;started:=clock_timestamp();
SELECT object_id,to_jsonb(t) INTO STRICT o,old_row FROM REGISTRY t WHERE scan_id=(SELECT scan_id FROM target);
IF NOT (old_row->>'retired')::BOOLEAN OR (old_row->>'marker_confirmed')::BOOLEAN
 OR old_row->>'claim_token' IS NOT NULL OR old_row->>'claim_expires_at' IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='ZX831';END IF;
SET LOCAL ROLE service_role;v:=public.claim_FUNCTION();RESET ROLE;
SELECT to_jsonb(t) INTO STRICT new_row FROM REGISTRY t WHERE object_id=o;
IF v IS DISTINCT FROM jsonb_build_object('version',1,'outcome','claimed','object',jsonb_build_object(
 'scan_id',new_row->'scan_id','object_id',o,'backend_generation',new_row->'backend_generation',
 'claim_token',new_row->'claim_token','claim_expires_at',floor(extract(epoch FROM (new_row->>'claim_expires_at')::TIMESTAMPTZ)*1000)::BIGINT))
 OR new_row->>'claim_token' IS NULL OR (new_row->>'claim_expires_at')::TIMESTAMPTZ NOT BETWEEN started+INTERVAL '1 minute' AND clock_timestamp()+INTERVAL '1 minute'
 OR (new_row-'claim_token'-'claim_expires_at') IS DISTINCT FROM (old_row-'claim_token'-'claim_expires_at')
 OR ROWS IS DISTINCT FROM jsonb_set(all_rows,ARRAY[o::TEXT],new_row)
 OR b IS DISTINCT FROM OTHERS THEN RAISE EXCEPTION USING ERRCODE='ZX832';END IF;END $$;
CREATE TEMP TABLE KIND_claim AS SELECT * FROM REGISTRY WHERE scan_id=(SELECT scan_id FROM target);
""".replace('OTHERS', others).replace('ROWS', rows).replace('REGISTRY', table).replace('FUNCTION', function).replace('KIND', kind)


def finish(kind, success, outcome, *, saved=None, expected=None):
    table, function = FAMILIES[kind]
    saved = saved or kind + '_claim'
    others = projection([r for r in PROJECTION_RELATIONS if r != table])
    rows = "(SELECT coalesce(jsonb_object_agg(object_id,to_jsonb(t)),'{}'::JSONB) FROM " + table + ' t)'
    if expected is not None:
        assert outcome == 'stale' and re.fullmatch('[0-9a-f]{32}', expected)
        check = "md5((" + FULL + ")::TEXT) IS DISTINCT FROM '" + expected + "'"
    elif outcome == 'stale':
        check = 'whole IS DISTINCT FROM ' + FULL
    else:
        check = "b IS DISTINCT FROM " + others + " OR " + rows + " IS DISTINCT FROM jsonb_set(all_rows,ARRAY[o::TEXT],old_row||jsonb_build_object('marker_confirmed'," + ('TRUE' if success else 'FALSE') + ",'claim_token',NULL,'claim_expires_at',NULL))"
    return """DO $$ DECLARE b JSONB;whole JSONB;all_rows JSONB;old_row JSONB;v JSONB;o UUID;c UUID;BEGIN
b:=OTHERS;whole:=FULL;all_rows:=ROWS;SELECT object_id,claim_token INTO STRICT o,c FROM SAVED;
IF c IS NULL THEN RAISE EXCEPTION USING ERRCODE='ZX833';END IF;
SELECT to_jsonb(t) INTO STRICT old_row FROM REGISTRY t WHERE object_id=o;
SET LOCAL ROLE service_role;v:=public.finish_FUNCTION(o,c,SUCCESS);RESET ROLE;
IF v IS DISTINCT FROM jsonb_build_object('version',1,'outcome','OUTCOME') OR CHECK
 THEN RAISE EXCEPTION USING ERRCODE='ZX834';END IF;END $$;
""".replace('OTHERS', others).replace('FULL', FULL).replace('ROWS', rows).replace('SAVED', saved).replace('REGISTRY', table).replace('FUNCTION', function).replace('SUCCESS', 'TRUE' if success else 'FALSE').replace('OUTCOME', outcome).replace('CHECK', check)


def cases(q):
    sessions = []
    fixture = None
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    catalog = json.loads(q.execute('exact_private_catalog', 'SELECT json_agg(relation_name ORDER BY relation_name) FROM internal.initial_cancellation_private_catalog();'))
    if catalog != sorted('internal.' + x for x in PRIVATE):
        raise ValueError('private catalog drift')

    def peer(name):
        s = Session(q, name)
        sessions.append(s)
        q.record.setdefault('backend_correlation', []).append({'session': name, 'pid': s.pid})
        q.save()
        return s

    def digest(s, sql):
        rows = s.run('expected_state_digest', 'SELECT md5((' + sql + ')::TEXT);')
        if len(rows) != 1 or not re.fullmatch('[0-9a-f]{32}', rows[0]):
            raise ValueError('single exact-state digest required')
        return rows[0]

    def block(observer, first, second):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if second.process.poll() is not None:
                second.finish()
                raise RuntimeError('waiter exited before blocking')
            if observer.run('observe_exact_blocker', f'SELECT {first.pid}=ANY(pg_blocking_pids({second.pid}));') == ['t']:
                q.record.setdefault('observed_blockers', []).append({'blocker': first.name, 'waiter': second.name})
                q.save()
                return
            time.sleep(0.04)
        raise RuntimeError('required cleanup row wait not observed')

    def finish_race(kind, first, second, observer):
        table, _ = FAMILIES[kind]
        # The original committed claim remains live after C1. Both finishers
        # retain that exact token; false releases it before the waiting true
        # finisher rechecks its conditional UPDATE and returns stale.
        first.run(kind + '_finish_transaction', BASE)
        second.run(kind + '_capture_original_claim', BASE + 'CREATE TEMP TABLE ' + kind + '_claim AS SELECT * FROM ' + table + ' WHERE scan_id=(SELECT scan_id FROM target);')
        first.run(kind + '_release_uncommitted', finish(kind, False, 'released' if kind == 'source' else 'acknowledged'))
        expected = digest(first, FULL)
        second.start(kind + '_original_finish_waits_then_stale', finish(kind, True, 'stale', expected=expected))
        block(observer, first, second)
        first.run(kind + '_commit_release', 'COMMIT;')
        second.finish()
        second.run(kind + '_commit_stale', 'COMMIT;')
        first.run(kind + '_reclaim_old_token_stale_ack', BASE + 'ALTER TABLE ' + kind + '_claim RENAME TO old_' + kind + '_claim;' + claim(kind) + "DO $$ BEGIN IF (SELECT claim_token FROM " + kind + "_claim) IS NOT DISTINCT FROM (SELECT claim_token FROM old_" + kind + "_claim) THEN RAISE EXCEPTION USING ERRCODE='ZX835';END IF;END $$;" + finish(kind, True, 'stale', saved='old_' + kind + '_claim') + finish(kind, True, 'acknowledged') + 'COMMIT;')

    try:
        fixture = AdmissionFixture(q)
        for schedule in ['claim_before_c1', 'c1_before_claim', 'marker_before_c1']:
            # No old eligible rows can supply a false positive for global claims.
            q.execute(schedule + '_global_queues_empty', BASE + empty('source') + empty('media') + 'ROLLBACK;')
            a = fixture.admit_one()
            for name, args, _, _ in OPERATIONS[:-1]:
                q.execute(schedule + '_prepare_' + name, "BEGIN;SET LOCAL statement_timeout='45s';UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;DO $$ DECLARE r internal.initial_preparation_admission_receipts;BEGIN SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';PERFORM * FROM internal." + name + '(r.owner_id,r.scan_id,r.receipt_digest' + args + ');END $$;COMMIT;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            q.execute(schedule + '_enable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;')
            first, second, observer = [peer(schedule + '_' + x) for x in ['first', 'second', 'observer']]
            if len({s.pid for s in [first, second, observer]}) != 3:
                raise ValueError('distinct backends required')
            target = "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "' AND owner_id='" + a.owner_id + "';CREATE TEMP TABLE verification AS SELECT receipt_digest AS digest FROM internal.initial_media_verification_receipts_v2 WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE source_before AS SELECT * FROM internal.initial_preparation_source_registry WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE media_before AS SELECT * FROM internal.initial_analysis_media_registry WHERE scan_id='" + a.scan_id + "';DO $$ BEGIN IF (SELECT count(*) FROM target)<>1 OR (SELECT count(*) FROM verification)<>1 OR (SELECT count(*) FROM source_before)<>1 OR (SELECT count(*) FROM media_before)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX836';END IF;END $$;"
            first.run('save_original_identity', BASE + target)
            second.run('save_original_identity', BASE + target)
            second.run('pre_transfer_claims_empty', empty('source') + empty('media'))
            first.run('transfer_uncommitted', TRANSFER)
            # This statement must return while the transfer holder still owns
            # locks. No holder release or timeout catch can manufacture success.
            second.run('claims_return_empty_while_transfer_held', empty('source') + empty('media'))
            first.run('commit_transfer', 'COMMIT;')
            second.run('destination_not_retired_after_transfer', empty('media'))
            if schedule == 'claim_before_c1':
                first.run('source_claim_uncommitted', BASE + claim('source'))
                expected_source = digest(first, SOURCE_ROWS)
                second.start('c1_waits_for_source_claim', CANCEL + terminal(expected_source))
                block(observer, first, second)
                first.run('commit_original_source_claim', 'COMMIT;')
                second.finish()
                second.run('commit_c1', 'COMMIT;')
                finish_race('source', first, second, observer)
                first.run('claim_retired_destination', BASE + claim('media') + 'COMMIT;')
                finish_race('media', first, second, observer)
            elif schedule == 'c1_before_claim':
                first.run('c1_uncommitted', BASE + CANCEL + TERMINAL)
                second.run('claims_skip_c1_locked_retired_rows', empty('source') + empty('media'))
                first.run('commit_c1', 'COMMIT;')
                second.run('claim_after_c1_and_ack_both', claim('source') + finish('source', True, 'acknowledged') + claim('media') + finish('media', True, 'acknowledged') + 'COMMIT;')
            else:
                first.run('source_marker_before_c1', BASE + claim('source') + finish('source', True, 'acknowledged') + 'COMMIT;')
                expected_source = digest(first, SOURCE_ROWS)
                second.run('c1_preserves_acknowledged_source', CANCEL + terminal(expected_source) + 'COMMIT;')
                first.run('destination_claim_after_c1', BASE + claim('media') + finish('media', True, 'acknowledged') + 'COMMIT;')
            first.run('both_queues_drained', BASE + empty('source') + empty('media') + 'ROLLBACK;')
            for s in [first, second, observer]:
                s.close()
                sessions.remove(s)
            q.execute(schedule + '_disable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            q.record['checks'].append({'case': schedule, 'passed': True, 'actual_service_role_queues_and_c1': True, 'whole_state_claim_finish_oracles': True, 'exact_source_preimage_preserved_by_c1': True, 'global_queues_drained': True, 'physical_erasure': False})
            q.save()
    finally:
        errors = []
        for s in sessions:
            try:
                s.close()
            except Exception as error:
                errors.append(type(error).__name__)
        if fixture is not None:
            try:
                fixture.close()
            except Exception as error:
                errors.append(type(error).__name__)
        q.execute('restore_inactive', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
        logs = subprocess.run(['docker', 'logs', '--since', started, q.command[3]], text=True, capture_output=True)
        count = len(re.findall(r'ERROR:.*deadlock detected', logs.stdout + logs.stderr))
        q.record.update(server_log_read_exit=logs.returncode, deadlock_reports=count, cleanup_errors=errors)
        q.save()
        if errors or logs.returncode or count:
            raise RuntimeError('session cleanup or server diagnostics failed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-cleanup-contention', args.replay_manifest)
    for name in [Path(__file__), *[Path(__file__).with_name('test_initial_media_handoff_' + suffix + '.py') for suffix in ['contention', 'owners', 'scan_contention']]]:
        q.record['source_manifest'][str(name.resolve().relative_to(ROOT))] = q.digest(name)
    q.record['scope'] = 'Single-object transferred cohorts: service-role global claim SKIP LOCKED visibility around transfer/C1, C1 waits for live source lease and preserves it, already-acknowledged source preservation, two actual finish waiters become stale after committed release, release/reclaim/old-token stale/ack for source and destination with exact whole-state oracles. Synthetic private transfer only; no physical erasure, expired-lease clock cases, installed use, whole-cohort or five-second resource qualification.'
    q.record['projection_relations'] = PROJECTION_RELATIONS
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()
