"""Local synthetic merge-target funding qualification, without hosted operations.

Requires the exact fresh disposable replay manifest. Uses real committed media
admission/C1 and authenticated Ghost issue/consume. Corruption probes are
transactional privileged fixtures and are never used as success evidence.
"""
import argparse
import hashlib
from pathlib import Path
import uuid
import time

from initial_atomic_admission_ghost_order import GhostFixture, jwt
from initial_atomic_admission_sessions import BASE, RELATIONS, Session
from initial_atomic_admission_test_support import Qualification


def cases(q):
    fixture = GhostFixture(q)
    try:
        source, target = fixture.owner, fixture.destination
        admitted = fixture.admissions.admit_one(owner_id=target)
        scan = admitted.scan_id
        secret = uuid.uuid4().hex + uuid.uuid4().hex
        fixture.session.run('issue_target_test_handoff', 'BEGIN;' + jwt(source) +
            "SET LOCAL ROLE authenticated;DO $$ BEGIN PERFORM * FROM public.issue_ghost_profile_merge_handoff('" +
            secret + "','google','" + fixture.subject + "');END $$;RESET ROLE;COMMIT;")
        relations = RELATIONS + ['auth.users', 'auth.identities', 'internal.ghost_profile_merge_handoffs']
        projection = 'jsonb_build_array(' + ','.join(
            "(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + r + ' t)'
            for r in relations) + ')'
        invoke = ("SELECT * INTO STRICT h FROM internal.ghost_profile_merge_handoffs WHERE ghost_user_id='" + source +
                  "';SET LOCAL ROLE authenticated;PERFORM * FROM public.consume_ghost_profile_merge_handoff(h.id,h.secret_hash);RESET ROLE;")
        prefix = 'BEGIN;' + jwt(target)

        def denied(name, damage=''):
            q.execute(name, prefix + damage +
                'DO $$ DECLARE h internal.ghost_profile_merge_handoffs;before_image JSONB;rejected BOOLEAN:=FALSE;BEGIN before_image:=' + projection +
                ';BEGIN ' + invoke + "EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'ghost_merge_target_initial_analysis_requires_attention' THEN RAISE;END IF;rejected:=TRUE;END;RESET ROLE;" +
                'IF NOT rejected OR before_image IS DISTINCT FROM ' + projection +
                " OR internal.initial_admission_sealed() OR internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX601';END IF;END $$;ROLLBACK;")

        # Only local fixture DML bypasses guards; restore normal execution before
        # invoking the actual authenticated endpoint. Whole transaction rolls back.
        def corrupt(sql):
            return "SET LOCAL session_replication_role='replica';" + sql + "SET LOCAL session_replication_role='origin';"

        for isolation in ['REPEATABLE READ', 'SERIALIZABLE']:
            q.execute('deny_' + isolation.lower().replace(' ', '_'),
                'BEGIN ISOLATION LEVEL ' + isolation + ';' + jwt(target) +
                'DO $$ DECLARE h internal.ghost_profile_merge_handoffs;BEGIN ' + invoke + 'END $$;ROLLBACK;', '25000')
        denied('active_target_with_no_source_usage_rejects_unchanged')
        denied('damaged_receipt_still_blocks', 'ALTER TABLE internal.initial_preparation_admission_receipts DROP CONSTRAINT initial_preparation_admission_receipts_check;' + corrupt(
            "UPDATE internal.initial_preparation_admission_receipts SET receipt_digest=repeat('f',64) WHERE scan_id='" + scan + "';"))
        denied('missing_receipt_still_blocks', corrupt(
            "DELETE FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + scan + "';"))
        for role in ['anon', 'authenticated', 'service_role']:
            for signature in [
                'internal.initial_merge_target_admitted_scans(uuid)',
                'internal.lock_initial_merge_target_terminal(uuid,uuid)',
                'internal.assert_initial_merge_target_terminal(uuid,uuid,uuid)',
                'internal.assert_ghost_target_initial_funding(uuid,uuid)',
                'internal.perform_ghost_profile_merge(uuid,uuid)',
                'internal.merge_ghost_complimentary_scan_usage(uuid,uuid)',
                'internal.prepare_scan_ingestions_for_identity_merge(uuid,uuid)',
            ]:
                q.execute(role + '_no_direct_' + signature.split('(')[0],
                    "DO $$ BEGIN IF has_function_privilege('" + role + "','" + signature +
                    "','EXECUTE') THEN RAISE EXCEPTION USING ERRCODE='ZX602';END IF;END $$;")
        # Actual conservative cancellation erases private state but retains its
        # unresolved original hold; it cannot become merge eligibility.
        unknown = corrupt("DELETE FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='" + scan + "';")
        unknown += "SELECT set_config('request.jwt.claim.role','service_role',TRUE);SET LOCAL ROLE service_role;DO $$ DECLARE answer JSONB;BEGIN answer:=public.cancel_initial_analysis('" + target + "','" + scan + "');IF answer->>'dispatch'<>'dispatch_outcome_unknown' THEN RAISE EXCEPTION USING ERRCODE='ZX603';END IF;END $$;RESET ROLE;" + jwt(target)
        denied('unknown_after_private_erasure_still_blocks', unknown)
        denied('unknown_with_missing_quota_still_blocks', unknown + corrupt(
            "DELETE FROM internal.ai_quota_reservations WHERE user_id='" + target + "';"))

        # Hold a trusted relation scheduler until real consume owns both users.
        # The C1 waiter must block on consume, not merely on the scheduler.
        peers = []
        try:
            for name in ['target_relation_scheduler', 'target_merge_first', 'target_c1_waiter', 'target_observer']:
                peers.append(Session(q, name))
            gate, ghost, c1, observer = peers
            gate.run('hold_candidate_catalog', 'BEGIN;LOCK TABLE internal.initial_preparation_admission_receipts IN ACCESS EXCLUSIVE MODE;')
            ghost.run('begin_consume', prefix)
            ghost.start('consume_denied_after_wait',
                'DO $$ DECLARE h internal.ghost_profile_merge_handoffs;failed BOOLEAN:=FALSE;BEGIN BEGIN ' + invoke +
                "EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'ghost_merge_target_initial_analysis_requires_attention' THEN RAISE;END IF;failed:=TRUE;END;RESET ROLE;IF NOT failed THEN RAISE EXCEPTION USING ERRCODE='ZX606';END IF;END $$;")
            def blocked(first, second):
                until = time.monotonic() + 5
                while time.monotonic() < until:
                    if observer.run('observe_actual_blocker', f'SELECT {first.pid}=ANY(pg_blocking_pids({second.pid}));') == ['t']:
                        q.record.setdefault('observed_target_blockers', []).append({'blocker': first.name, 'waiter': second.name})
                        q.save()
                        return
                    time.sleep(0.04)
                raise RuntimeError('expected target funding blocker missing')
            blocked(gate, ghost)
            c1.run('begin_c1', BASE)
            cancel_sql = "SET LOCAL ROLE service_role;DO $$ DECLARE answer JSONB;BEGIN answer:=public.cancel_initial_analysis('" + target + "','" + scan + "');IF answer->>'dispatch' IS DISTINCT FROM 'dispatch_prevented' THEN RAISE EXCEPTION USING ERRCODE='ZX607';END IF;END $$;RESET ROLE;"
            c1.start('c1_waiting_on_merge', cancel_sql)
            blocked(ghost, c1)
            gate.run('release_catalog', 'COMMIT;')
            ghost.finish()
            ghost.run('finish_denied_merge', 'COMMIT;')
            c1.finish()
            c1.run('commit_after_denied_merge', 'COMMIT;')
        finally:
            for peer in reversed(peers):
                peer.close()

        q.execute('commit_positive_unused_c1', BASE +
            "SET LOCAL ROLE service_role;DO $$ DECLARE answer JSONB;BEGIN answer:=public.cancel_initial_analysis('" + target + "','" + scan +
            "');IF answer IS DISTINCT FROM '{\"version\":1,\"outcome\":\"cancelled\",\"dispatch\":\"dispatch_prevented\"}'::JSONB THEN RAISE EXCEPTION USING ERRCODE='ZX604';END IF;END $$;RESET ROLE;COMMIT;")
        denied('terminal_missing_original_quota_blocks', corrupt(
            "DELETE FROM internal.ai_quota_reservations WHERE user_id='" + target + "';"))
        denied('terminal_missing_attempt_blocks', corrupt(
            "DELETE FROM internal.identification_provider_attempts WHERE reservation_id IN(SELECT id FROM internal.ai_quota_reservations WHERE user_id='" + target + "');"))
        denied('terminal_consumed_credit_blocks', corrupt(
            "UPDATE internal.complimentary_scan_usage SET state='consumed' WHERE user_id='" + target + "';"))
        denied('terminal_nonretired_destination_blocks', corrupt(
            "UPDATE internal.initial_analysis_media_registry SET retired=FALSE WHERE scan_id='" + scan + "';"))
        denied('terminal_source_usage_collision_blocks', corrupt(
            "INSERT INTO internal.complimentary_scan_usage(user_id,client_scan_id) VALUES('" + source + "','" + scan + "');"))
        denied('terminal_bad_refund_count_blocks', corrupt(
            "UPDATE internal.ai_quota_reservations SET refund_count=2 WHERE user_id='" + target + "';"))
        for table, columns, values in [
            ('observation_analysis_source_bindings',
             'analysis_id,owner_id,observation_id,source_analysis_id,input_snapshot,fingerprint_version,fingerprint',
             "'" + scan + "','" + target + "',gen_random_uuid(),gen_random_uuid(),'{}',1,repeat('a',64)"),
            ('observation_analysis_intents', 'analysis_id,owner_id,observation_id,input_snapshot',
             "'" + scan + "','" + target + "',gen_random_uuid(),'{}'"),
            ('observation_analysis_results', 'analysis_id,observation_id,ordinal,result_snapshot,evidence_manifest',
             "'" + scan + "',gen_random_uuid(),1,'{}','{}'"),
        ]:
            # Independently inject each contradictory history alias. Check/FK
            # bypass exists only in this trusted rollback-only damage fixture.
            drop_checks = "DO $$ DECLARE c RECORD;BEGIN FOR c IN SELECT conname FROM pg_constraint WHERE conrelid='internal." + table + "'::REGCLASS AND contype='c' LOOP EXECUTE format('ALTER TABLE internal." + table + " DROP CONSTRAINT %I',c.conname);END LOOP;END $$;"
            denied('terminal_history_alias_' + table + '_blocks', drop_checks + corrupt(
                'INSERT INTO internal.' + table + '(' + columns + ') VALUES(' + values + ');'))
        # The terminal exception permits a real merge and leaves original funding,
        # attempt, cancellation and registry evidence byte-identical.
        terminal_relations = [r for r in RELATIONS if r != 'public.users']
        terminal_projection = 'jsonb_build_array(' + ','.join(
            "(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + r + ' t)'
            for r in terminal_relations) + ')'
        # Paid admission exercises the nullable original-credit branch. C1 owns
        # the target first; actual consume must wait, then preserve both terminal
        # histories after C1 commits. No private owner is called as an API role.
        fixture.session.run('set_synthetic_paid_target', BASE +
            "UPDATE public.users SET subscription_tier='pro',subscription_expires_at=now()+INTERVAL '1 day' WHERE id='" + target + "';COMMIT;")
        paid = fixture.admissions.admit_one(owner_id=target)
        q.execute('paid_original_funding_assertion',
            "DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE user_id='" + target + "' AND request_id='" + paid.scan_id + "' AND effective_plan='pro_paid' AND complimentary_client_scan_id IS NULL) THEN RAISE EXCEPTION USING ERRCODE='ZX608';END IF;END $$;")
        denied('active_paid_target_blocks_unchanged')
        peers = []
        try:
            for name in ['target_c1_first', 'target_merge_waiter', 'terminal_observer']:
                peers.append(Session(q, name))
            c1, ghost, observer = peers
            c1.run('paid_cancel_uncommitted', BASE +
                "SET LOCAL ROLE service_role;DO $$ DECLARE answer JSONB;BEGIN answer:=public.cancel_initial_analysis('" + target + "','" + paid.scan_id + "');IF answer->>'dispatch' IS DISTINCT FROM 'dispatch_prevented' THEN RAISE EXCEPTION USING ERRCODE='ZX609';END IF;END $$;RESET ROLE;")
            expected = c1.run('terminal_image_after_c1', 'SELECT md5((' + terminal_projection + ')::TEXT);')
            if len(expected) != 1 or len(expected[0]) != 32:
                raise RuntimeError('one synthetic terminal image required')
            ghost.run('begin_terminal_consume', prefix)
            ghost.start('positive_terminal_allows_actual_authenticated_merge',
                'DO $$ DECLARE h internal.ghost_profile_merge_handoffs;BEGIN ' + invoke +
                "IF md5((" + terminal_projection + ")::TEXT) IS DISTINCT FROM '" + expected[0] +
                "' OR EXISTS(SELECT 1 FROM public.users WHERE id='" + source + "') OR NOT EXISTS(SELECT 1 FROM public.users WHERE id='" + target + "') THEN RAISE EXCEPTION USING ERRCODE='ZX605';END IF;END $$;")
            blocked(c1, ghost)
            c1.run('paid_c1_commit', 'COMMIT;')
            ghost.finish()
            ghost.run('successful_merge_commit', 'COMMIT;')
        finally:
            for peer in reversed(peers):
                peer.close()

    finally:
        fixture.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-merge-target-funding', args.replay_manifest)
    path = Path(__file__).resolve()
    q.record['source_manifest'][str(path.relative_to(path.parents[3]))] = hashlib.sha256(path.read_bytes()).hexdigest()
    q.record['scope'] = ('Local synthetic target admission, corruption denials, real positive C1 and authenticated issue/consume; '
                         'both target merge/C1 orders observed; no provider/blob I/O, no installed/hosted qualification. Other runtime races remain open.')
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()
