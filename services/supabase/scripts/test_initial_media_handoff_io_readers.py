"""Revoked private SQL readers on synthetic original admission; no blob I/O.

Each read transaction is READ COMMITTED with a five-second statement limit and
one-second lock limit. Fixture/writer setup is separately identified and is not
evidence that the future adapter's five-second write envelope has passed.
"""
import argparse
from pathlib import Path

from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_test_support import Qualification
from test_initial_media_handoff_owners import OPERATIONS

BASE = "BEGIN ISOLATION LEVEL READ COMMITTED;SET LOCAL statement_timeout='5s';SET LOCAL lock_timeout='1s';"
ON = 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;'


def cases(q):
    signatures = ['assert_initial_media_handoff_reader_idle(uuid)',
                  'read_initial_media_handoff_state(uuid,uuid,text)',
                  'load_initial_media_handoff_io(uuid,uuid,text,text,uuid)',
                  'load_initial_media_copy_io(uuid,uuid,text)',
                  'load_initial_media_verification_io(uuid,uuid,text,uuid)']
    for signature in signatures:
        for role in ['anon', 'authenticated', 'service_role']:
            q.execute(role + '_denied_' + signature.split('(')[0], "DO $$ BEGIN IF has_function_privilege('" + role +
                      "','internal." + signature + "','EXECUTE') THEN RAISE EXCEPTION USING ERRCODE='ZX750';END IF;END $$;")
    fixture = AdmissionFixture(q)
    try:
        a = fixture.admit_one()
        prefix = "DO $$ DECLARE r internal.initial_preparation_admission_receipts; answer RECORD; saved JSONB;BEGIN SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';"
        state = 'SELECT * INTO STRICT answer FROM internal.read_initial_media_handoff_state(r.owner_id,r.scan_id,r.receipt_digest);'
        copy = 'SELECT * INTO STRICT answer FROM internal.load_initial_media_copy_io(r.owner_id,r.scan_id,r.receipt_digest);'
        verify = "SELECT * INTO STRICT answer FROM internal.load_initial_media_verification_io(r.owner_id,r.scan_id,r.receipt_digest,(SELECT (claim::JSONB->>'claim_token')::UUID FROM internal.initial_media_verification_claims_v2 WHERE scan_id=r.scan_id));"
        save = 'saved:=internal.capture_initial_media_handoff_snapshot(r.owner_id,r.scan_id);'
        unchanged = "IF saved IS DISTINCT FROM internal.capture_initial_media_handoff_snapshot(r.owner_id,r.scan_id) OR internal.initial_media_handoff_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX751';END IF;"
        same_rows = """
IF to_jsonb(answer.admission) IS DISTINCT FROM to_jsonb(r)
 OR to_jsonb(answer.progress) IS DISTINCT FROM (SELECT to_jsonb(t) FROM internal.initial_media_copy_progress t WHERE scan_id=r.scan_id)
 OR to_jsonb(answer.claim) IS DISTINCT FROM (SELECT to_jsonb(t) FROM internal.initial_media_verification_claims_v2 t WHERE scan_id=r.scan_id)
 OR answer.observed_at_ms IS NULL
 THEN RAISE EXCEPTION USING ERRCODE='ZX752';END IF;
"""
        same_state = same_rows + """
IF answer.response->>'authority' IS DISTINCT FROM 'none'
 OR to_jsonb(answer.verification) IS DISTINCT FROM (SELECT to_jsonb(t) FROM internal.initial_media_verification_receipts_v2 t WHERE scan_id=r.scan_id)
 OR to_jsonb(answer."transfer") IS DISTINCT FROM (SELECT to_jsonb(t) FROM internal.initial_preparation_transfer_receipts t WHERE scan_id=r.scan_id)
 THEN RAISE EXCEPTION USING ERRCODE='ZX753';END IF;
"""
        same_backends = same_rows + """
IF to_jsonb(answer.destination_backend) IS DISTINCT FROM r.destination::JSONB
 OR (answer.source_backend).generation::TEXT IS DISTINCT FROM r.configuration::JSONB#>>'{assignment,handoff,profile,source_backend_generation}'
 OR (answer.source_backend).configuration_digest IS DISTINCT FROM r.configuration::JSONB#>>'{assignment,handoff,profile,source_backend_config_digest}'
 OR (answer.source_backend).namespace IS DISTINCT FROM 'initial-preparation/v2'
 OR (answer.destination_backend).namespace IS DISTINCT FROM 'initial-analysis/v1'
 THEN RAISE EXCEPTION USING ERRCODE='ZX754';END IF;
"""
        def read(label, body, expected=None, setup='', gate=False):
            q.execute(label, BASE + (ON if gate else '') + setup + prefix + body + 'END $$;ROLLBACK;', expected)

        # A known expired original remains recovery data, with no fresh grant.
        late_state = """DO $clock$ DECLARE definition TEXT; needle TEXT:='now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;';BEGIN
 definition:=pg_get_functiondef('internal.read_initial_media_handoff_state(uuid,uuid,text)'::regprocedure);
 IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX755';END IF;
 EXECUTE replace(definition,needle,'now_ms:=(r.media_binding::JSONB#>>''{phase_window,original_expires_at_ms}'')::BIGINT+1;');END $clock$;"""
        read('state_before_copy', save + state + same_state + unchanged)
        read('copy_before_start_denied', copy, '55000', gate=True)
        for index, (name, args, _, _) in enumerate(OPERATIONS):
            q.execute('fixture_commit_' + name, 'BEGIN;' + ON + prefix + 'PERFORM * FROM internal.' + name +
                      '(r.owner_id,r.scan_id,r.receipt_digest' + args + ');END $$;COMMIT;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            read('state_' + str(index), save + state + same_state + unchanged)
            if index in [0, 3]:
                read('expired_admitted_state_' + str(index), save + state + same_state + unchanged +
                     "IF answer.response->>'phase' IS DISTINCT FROM 'expired' THEN RAISE EXCEPTION USING ERRCODE='ZX756';END IF;", setup=late_state)
            read('state_changed_digest_' + str(index), state.replace('r.receipt_digest', "repeat('f',64)"), '55000')
            for label, call, allowed in [('copy', copy, index == 0), ('verification', verify, index == 3)]:
                # Absent claims are invalid inputs; use a syntactically valid
                # foreign token so non-verification states reach state checks.
                if label == 'verification' and index < 3:
                    call = call.replace("(SELECT (claim::JSONB->>'claim_token')::UUID FROM internal.initial_media_verification_claims_v2 WHERE scan_id=r.scan_id)", 'extensions.gen_random_uuid()')
                if not allowed:
                    read(label + '_wrong_stage_' + str(index), call, '55000', gate=True)
                    continue
                read(label + '_fresh_exact_unchanged', save + call + same_backends + unchanged, gate=True)
                # Rollback-only denial facts, not valid writer transitions.
                for reader_label, reader in [(label, call), ('state_at_' + label, state)]:
                    for seal_label, namespace in [('handoff', 1229801542), ('admission', 1229018189), ('cancellation', 1128353347)]:
                        read(reader_label + '_' + seal_label + '_seal', 'PERFORM pg_catalog.pg_advisory_xact_lock(' + str(namespace) + ',1);' + reader, '55000', gate=True)
                    stages = [
                        ('handoff', "INSERT INTO internal.initial_media_handoff_staging(scan_id,owner_id,action,admission_digest,transaction_id,authorized_at_ms,cutoff_ms,snapshot,events,frames,phase,next_root,active,after_seen,closed,cleanup_cursor) VALUES(extensions.gen_random_uuid(),r.owner_id,'start_copy',r.receipt_digest,pg_catalog.pg_current_xact_id(),1,2,'{}','[{}]','[{}]','applying',0,'{}','{}','{}',0);"),
                        ('admission', "INSERT INTO internal.initial_preparation_admission_staging(scan_id,owner_id,transaction_id,stage_token,phase,admission_receipt_id,candidate,assignment,outcome,input,installation,protocol,destination,phase_window,mapping,media_binding) VALUES(r.scan_id,r.owner_id,pg_catalog.pg_current_xact_id(),extensions.gen_random_uuid(),'validated',r.admission_receipt_id,'{}','{}','{}','{}','{}','{}','{}','{}','{}','{}');"),
                        ('cancellation', "INSERT INTO internal.initial_admitted_cancellation_staging(scan_id,owner_id,transaction_id,prestate) VALUES(extensions.gen_random_uuid(),r.owner_id,pg_catalog.pg_current_xact_id(),'{}');"),
                    ]
                    for stage_label, damage in stages:
                        read(reader_label + '_' + stage_label + '_stage', "SET LOCAL session_replication_role='replica';" + damage + "SET LOCAL session_replication_role='origin';" + reader, '55000', gate=True)
                aggregate_tripwire = """DO $tripwire$ DECLARE definition TEXT; needle TEXT:='    SELECT array_agg(object_id ORDER BY object_id) INTO original_sources FROM (';BEGIN
 definition:=pg_get_functiondef('internal.load_initial_media_handoff_io(uuid,uuid,text,text,uuid)'::regprocedure);
 IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX755';END IF;
 EXECUTE replace(definition,needle,'    RAISE EXCEPTION USING ERRCODE=''ZX757'';'||chr(10)||needle);END $tripwire$;"""
                read(label + '_ordinary_union_reaches_aggregate', call, 'ZX757', setup=aggregate_tripwire, gate=True)
                overfull = "SET LOCAL session_replication_role='replica';INSERT INTO internal.initial_preparation_source_registry(object_id,scan_id,backend_generation) SELECT extensions.gen_random_uuid(),r.scan_id,(r.configuration::JSONB#>>'{assignment,preparation,backend_generation}')::UUID FROM generate_series(1,17-(SELECT count(*)::INTEGER FROM internal.initial_preparation_source_registry WHERE scan_id=r.scan_id));SET LOCAL session_replication_role='origin';"
                read(label + '_overfull_union_denied_before_aggregate', overfull + call, '55000', setup=aggregate_tripwire, gate=True)
                read(label + '_disabled_gate', call, '55000')
                read(label + '_foreign_owner', call.replace('r.owner_id', "'" + fixture.foreign + "'::UUID"), '55000', gate=True)
                for damage_label, damage in [
                    ('revoked_handoff', "UPDATE internal.initial_preparation_handoff_eligibility SET state='revoked';"),
                    ('retired_source', 'UPDATE internal.initial_preparation_source_registry SET retired=TRUE WHERE scan_id=r.scan_id;'),
                    ('retired_destination', 'UPDATE internal.initial_analysis_media_registry SET retired=TRUE WHERE scan_id=r.scan_id;'),
                    ('missing_source', 'DELETE FROM internal.initial_preparation_source_registry WHERE scan_id=r.scan_id;'),
                    ('changed_backend', "UPDATE internal.initial_preparation_source_backends t SET private_bucket='changed-fixture-bucket',configuration_digest=internal.initial_media_contract_digest('backend',internal.initial_canonical((to_jsonb(t)-'configuration_digest')||jsonb_build_object('private_bucket','changed-fixture-bucket')));"),
                ]:
                    body = "SET LOCAL session_replication_role='replica';" + damage + "SET LOCAL session_replication_role='origin';" + call
                    read(label + '_' + damage_label, body, '55000', gate=True)
                for clock_label, expression in [('expired', "(r.media_binding::JSONB#>>ARRAY['phase_window','cutoffs',p_phase])::BIGINT"), ('regressed', 'c.started_at_ms-1')]:
                    seam = """DO $clock$ DECLARE definition TEXT; needle TEXT:='now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;';BEGIN
 definition:=pg_get_functiondef('internal.load_initial_media_handoff_io(uuid,uuid,text,text,uuid)'::regprocedure);
 IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX755';END IF;
 EXECUTE replace(definition,needle,$replace$now_ms:=""" + expression + ";$replace$);END $clock$;"
                    read(label + '_' + clock_label, call, '55000', setup=seam, gate=True)
                if index == 3:
                    read('verification_wrong_token', call.replace("(SELECT (claim::JSONB->>'claim_token')::UUID FROM internal.initial_media_verification_claims_v2 WHERE scan_id=r.scan_id)", 'extensions.gen_random_uuid()'), '55000', gate=True)
        read('expired_transferred_original_state', save + state + same_state + unchanged, setup=late_state)
        original_digest = q.execute('retain_exact_digest_for_erasure', "SELECT receipt_digest FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';")
        q.execute('actual_c1', "BEGIN;SET LOCAL ROLE service_role;SELECT public.cancel_initial_analysis('" + a.owner_id + "','" + a.scan_id + "');COMMIT;")
        q.execute('erased_state_denied', BASE + "SELECT * FROM internal.read_initial_media_handoff_state('" + a.owner_id + "','" + a.scan_id + "','" + original_digest + "');ROLLBACK;", '55000')
    finally:
        fixture.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-io-readers', args.replay_manifest)
    for source in [Path(__file__).resolve(), Path(__file__).with_name('test_initial_media_handoff_owners.py').resolve()]:
        q.record['source_manifest'][str(source.relative_to(source.parents[3]))] = q.digest(source)
    q.record['scope'] = 'Revoked private SQL readers only: actual six-owner fixture stages, exact typed rows/pinned backends, disabled/revoked/changed/missing/retired/late denial, unchanged snapshots, actual C1. Reads use five-second statement and one-second lock limits. Clock/corruption seams rollback only; no physical I/O, production adapter, writer deadline or installed acceptance.'
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()
