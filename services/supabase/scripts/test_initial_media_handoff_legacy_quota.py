"""Local synthetic legacy quota isolation; no provider or physical media I/O."""
import argparse
from pathlib import Path
import time
import uuid

from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_sessions import BASE, PROJECTION, Session
from initial_atomic_admission_test_support import Qualification, ROOT


def reserve(owner, scan):
    uuid.UUID(owner)
    uuid.UUID(scan)
    return "public.reserve_ai_quota('" + owner + "','scan_identification','" + scan + "',repeat('a',64))"


def denied(call, state='55000', message='initial_analysis_admission_required', unchanged=True):
    before = 'before_state:=' + PROJECTION + ';' if unchanged else ''
    after = ' OR before_state IS DISTINCT FROM ' + PROJECTION if unchanged else ''
    return "DO $$ DECLARE failed BOOLEAN:=FALSE;before_state JSONB;BEGIN " + before + \
        'BEGIN SET LOCAL ROLE service_role;PERFORM * FROM ' + call + \
        ";EXCEPTION WHEN SQLSTATE '" + state + "' THEN IF SQLERRM<>'" + message + \
        "' THEN RAISE;END IF;failed:=TRUE;END;RESET ROLE;IF NOT failed" + after + \
        " THEN RAISE EXCEPTION USING ERRCODE='ZX870';END IF;END $$;"


def cancel(owner, scan, unknown=False):
    # The generic private cancellation owner deliberately lacks the explicit
    # unused-funding proof: it must retain unknown accounting after erasure.
    call = ('internal' if unknown else 'public') + ".cancel_initial_analysis('" + owner + "','" + scan + "')"
    role = '' if unknown else 'SET LOCAL ROLE service_role;'
    expected = 'dispatch_outcome_unknown' if unknown else 'dispatch_prevented'
    return "DO $$ DECLARE answer JSONB;BEGIN " + role + 'answer:=' + call + \
        ";RESET ROLE;IF answer->>'dispatch' IS DISTINCT FROM '" + expected + \
        "' THEN RAISE EXCEPTION USING ERRCODE='ZX871';END IF;END $$;"


def wait_for(q, observer, winner, waiter):
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        if waiter.process.poll() is not None:
            raise RuntimeError('waiter exited before observed serialization')
        if observer.run('observe_exact_blocker', f'SELECT {winner.pid}=ANY(pg_blocking_pids({waiter.pid}));') == ['t']:
            q.record.setdefault('observed_blockers', []).append({'winner': winner.name, 'waiter': waiter.name})
            q.save()
            return
        time.sleep(.04)
    raise RuntimeError('required serialization not observed')


def cases(q):
    fixture = AdmissionFixture(q)
    peers = []
    try:
        owner, foreign = fixture.owner, fixture.foreign
        # Unfenced legacy controls use a paid synthetic owner; initial cases
        # retain the fixture's held complimentary allocation.
        q.execute('legacy_paid_control_owner', "UPDATE public.users SET subscription_tier='pro',subscription_expires_at=NULL WHERE id='" + foreign + "';")
        for mode in ['positive', 'unknown']:
            a = fixture.admit_one()
            for who in [owner, foreign]:
                q.execute('active_' + mode + ('_owner' if who == owner else '_foreign'), BASE + denied(reserve(who, a.scan_id)) + 'ROLLBACK;')
            q.execute('cancel_' + mode, BASE + cancel(owner, a.scan_id, mode == 'unknown') + 'COMMIT;')
            q.execute('cancelled_' + mode + '_unchanged', BASE + denied(reserve(owner, a.scan_id)) + 'COMMIT;')
            q.execute('cancelled_' + mode + '_private_erasure', "DO $$ BEGIN IF EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "') OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id='" + a.scan_id + "') OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE request_id='" + a.scan_id + "' AND state='" + ('reserved' if mode == 'unknown' else 'refunded') + "' AND refund_count=" + ('0' if mode == 'unknown' else '1') + ") THEN RAISE EXCEPTION USING ERRCODE='ZX872';END IF;END $$;")

        empty = str(uuid.uuid4())
        q.execute('empty_cancel_retains_namespace', BASE + "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;SET LOCAL ROLE service_role;SELECT public.cancel_initial_analysis('" + owner + "','" + empty + "');RESET ROLE;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;COMMIT;")
        q.execute('fence_without_quota_denied', BASE + denied(reserve(owner, empty)) + "DO $$ BEGIN IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE request_id='" + empty + "') THEN RAISE EXCEPTION USING ERRCODE='ZX873';END IF;END $$;COMMIT;")

        # Non-read-committed callers must fail before their stale snapshot can
        # authorize a reservation, including when no fence is currently visible.
        for isolation in ['REPEATABLE READ', 'SERIALIZABLE']:
            q.execute('isolation_' + isolation.lower().replace(' ', '_'), 'BEGIN ISOLATION LEVEL ' + isolation + ";SELECT set_config('request.jwt.claim.role','service_role',TRUE);" + denied(reserve(foreign, str(uuid.uuid4())), message='ai_quota_isolation_unsupported') + 'ROLLBACK;')
        q.execute('invalid_input_precedes_locks', BASE + denied("public.reserve_ai_quota('" + foreign + "','INVALID',NULL,'bad')", '22023', 'ai_quota_invalid_request') + 'ROLLBACK;')
        for role in ['anon', 'authenticated']:
            q.execute(role + '_cannot_use_legacy_abi', 'BEGIN;SET LOCAL ROLE ' + role + ';SELECT * FROM ' + reserve(foreign, str(uuid.uuid4())) + ';ROLLBACK;', '42501')

        # The old generic ABI retains replay and renewal; compare the actual
        # returned lease/attempt and prove no second charge on exact replay.
        legacy = str(uuid.uuid4())
        call = reserve(foreign, legacy)
        q.execute('unfenced_legacy_fresh_replay_and_refund_renewal', BASE + "DO $$ DECLARE a RECORD;b RECORD;before_state JSONB;BEGIN SET LOCAL ROLE service_role;SELECT * INTO STRICT a FROM " + call + ';RESET ROLE;before_state:=' + PROJECTION + ';SET LOCAL ROLE service_role;SELECT * INTO STRICT b FROM ' + call + ";RESET ROLE;IF NOT b.is_replay OR a.reservation_id<>b.reservation_id OR a.lease_token<>b.lease_token OR a.attempt_count<>b.attempt_count OR before_state IS DISTINCT FROM " + PROJECTION + " THEN RAISE EXCEPTION USING ERRCODE='ZX874';END IF;PERFORM internal.finalize_ai_quota_reservation_core(a.reservation_id,'" + foreign + "',a.lease_token,'refunded');SET LOCAL ROLE service_role;SELECT * INTO STRICT b FROM " + call + ";RESET ROLE;IF b.is_replay OR a.lease_token=b.lease_token OR b.attempt_count<>a.attempt_count+1 THEN RAISE EXCEPTION USING ERRCODE='ZX875';END IF;END $$;ROLLBACK;")
        q.execute('unfenced_expired_renewal_replaces_charge', BASE + "DO $$ DECLARE a RECORD;b RECORD;charged BIGINT;BEGIN SET LOCAL ROLE service_role;SELECT * INTO STRICT a FROM " + call + ";RESET ROLE;SELECT sum(request_count) INTO charged FROM internal.ai_quota_counters;UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-INTERVAL '1 hour' WHERE id=a.reservation_id;SET LOCAL ROLE service_role;SELECT * INTO STRICT b FROM " + call + ";RESET ROLE;IF b.is_replay OR a.lease_token=b.lease_token OR b.attempt_count<>a.attempt_count+1 OR (SELECT sum(request_count) FROM internal.ai_quota_counters) IS DISTINCT FROM charged OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE id=a.reservation_id AND stale_recovery_count=1 AND refund_count=0 AND state='reserved') THEN RAISE EXCEPTION USING ERRCODE='ZX879';END IF;END $$;ROLLBACK;")
        unconsented = str(uuid.uuid4())
        q.execute('unconsented_owner_denied_without_accounting', BASE + "INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES('" + unconsented + "','authenticated','authenticated','{}','{}',now(),now());" + denied(reserve(unconsented, str(uuid.uuid4())), 'P0001', 'ai_consent_required') + 'ROLLBACK;')

        for phase in ['admission_first', 'cancel_first', 'legacy_first']:
            winner = Session(q, phase + '_winner')
            waiter = Session(q, phase + '_waiter')
            observer = Session(q, phase + '_observer')
            peers.extend([winner, waiter, observer])
            if phase == 'admission_first':
                scan = str(uuid.uuid4())
                fixture.bind_owner(owner)
                fixture.session.run('admission_uncommitted', BASE + fixture.prepare_admission(owner, scan, commit=False))
                waiter.run('begin_legacy', BASE)
                waiter.start('legacy_waits_for_admission', denied(reserve(foreign, scan), unchanged=False))
                wait_for(q, observer, fixture.session, waiter)
                fixture.commit_prepared()
                waiter.finish()
                waiter.run('commit_denial', 'COMMIT;')
                q.execute('retire_race_admission', BASE + cancel(owner, scan) + 'COMMIT;')
            elif phase == 'cancel_first':
                a = fixture.admit_one()
                winner.run('cancellation_uncommitted', BASE + cancel(owner, a.scan_id))
                waiter.run('begin_legacy', BASE)
                waiter.start('legacy_waits_for_cancellation', denied(reserve(owner, a.scan_id), unchanged=False))
                wait_for(q, observer, winner, waiter)
                winner.run('commit_cancellation', 'COMMIT;')
                waiter.finish()
                waiter.run('commit_denial', 'COMMIT;')
                q.execute('cancel_race_accounting_unchanged', BASE + denied(reserve(owner, a.scan_id)) + 'ROLLBACK;')
            else:
                scan = str(uuid.uuid4())
                winner.run('legacy_reservation_uncommitted', BASE + 'SET LOCAL ROLE service_role;SELECT * FROM ' + reserve(foreign, scan) + ';RESET ROLE;')
                # Cancellation must classify the now-occupied generic identity,
                # not create a conflicting permanent initial namespace.
                waiter.run('begin_cancel', BASE)
                waiter.start('cancel_waits_for_legacy', "DO $$ DECLARE failed BOOLEAN:=FALSE;BEGIN BEGIN SET LOCAL ROLE service_role;PERFORM public.cancel_initial_analysis('" + foreign + "','" + scan + "');EXCEPTION WHEN SQLSTATE 'P0002' THEN failed:=TRUE;END;RESET ROLE;IF NOT failed THEN RAISE EXCEPTION USING ERRCODE='ZX876';END IF;END $$;")
                wait_for(q, observer, winner, waiter)
                winner.run('commit_legacy', 'COMMIT;')
                waiter.finish()
                waiter.run('commit_cancel_denial', 'COMMIT;')
                q.execute('legacy_namespace_not_adopted', "DO $$ BEGIN IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id='" + scan + "') OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE request_id='" + scan + "' AND state='reserved' AND attempt_count=1) THEN RAISE EXCEPTION USING ERRCODE='ZX877';END IF;END $$;")
            for peer in [winner, waiter, observer]:
                peer.close()
                peers.remove(peer)
        q.execute('no_invocation_or_private_roots', "DO $$ BEGIN IF EXISTS(SELECT 1 FROM internal.identification_invocations) OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents) OR (SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout) THEN RAISE EXCEPTION USING ERRCODE='ZX878';END IF;END $$;")
    finally:
        for peer in peers:
            peer.close()
        fixture.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-legacy-quota', args.replay_manifest)
    q.record['source_manifest'][str(Path(__file__).relative_to(ROOT))] = q.digest(Path(__file__))
    q.record['scope'] = 'Synthetic local legacy service ABI, permanent identity exclusion, preserved generic accounting and observed transaction order. No provider/physical I/O or hosted activation.'
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()
