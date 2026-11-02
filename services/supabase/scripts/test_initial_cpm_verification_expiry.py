"""Coherently aged, committed CPM fixtures on an owned disposable database.

No production clock change, real elapsed-time claim, media IO or admission.
The caller must retain evidence and dispose this database even after failure.
"""
import argparse
import hashlib
from pathlib import Path
import re
import sys
import time
import uuid

from initial_atomic_admission_test_support import Qualification, ROOT
from test_initial_cpm_photo_capacity import TEST, FIXTURE, create, finish_sessions
from test_initial_cpm_verification_start import start

BASE = "BEGIN;DO $$ BEGIN PERFORM set_config('request.jwt.claim.role','service_role',TRUE); END $$;"
TRIGGERS = """SELECT jsonb_agg(jsonb_build_array(tgrelid::regclass::TEXT,tgname,tgenabled,
 pg_get_triggerdef(oid)) ORDER BY tgrelid,tgname)::TEXT FROM pg_trigger
 WHERE tgrelid IN ('internal.initial_analysis_preparation_intents'::regclass,
 'internal.initial_cpm_photo_write_attempts'::regclass,'internal.initial_cpm_photo_write_closures'::regclass);"""


def denied(expression, code, message):
    return BASE + f"""DO $$ BEGIN BEGIN PERFORM {expression};
 EXCEPTION WHEN SQLSTATE '{code}' THEN IF SQLERRM='{message}' THEN RETURN; END IF; RAISE;
 END; RAISE EXCEPTION 'expected exact refusal was absent' USING ERRCODE='ZX711'; END $$;COMMIT;"""


def stable_image():
    # Preserve all data other than the explicitly translated clock/digest fields.
    tables = {
        'internal.initial_analysis_preparation_intents': "(to_jsonb(t)-ARRAY['created_at','expires_at','canonical_assignment','assignment_digest','cpm_verification_started_at','cpm_verification_snapshot_digest'])||jsonb_build_object('assignment_without_clocks',canonical_assignment::JSONB-ARRAY['created_at_ms','expires_at_ms'])",
        'internal.initial_cpm_photo_write_attempts': "to_jsonb(t)-ARRAY['created_at','admission_expires_at','capability_expires_at','issued_at','assignment_digest']",
        'internal.initial_cpm_photo_write_closures': "to_jsonb(t)-'observed_at'",
        'internal.initial_cpm_photo_role_mapping': 'to_jsonb(t)',
        'internal.initial_preparation_source_registry': 'to_jsonb(t)',
        'internal.initial_preparation_source_fences': 'to_jsonb(t)',
        'internal.initial_cpm_photo_capacity_reservations': 'to_jsonb(t)',
    }
    parts = [f"(SELECT jsonb_agg(image ORDER BY image::TEXT) FROM (SELECT {image} image FROM {table} t) s)"
             for table, image in tables.items()]
    return "SELECT encode(extensions.digest(convert_to(jsonb_build_array(" + ','.join(parts) + ")::TEXT,'UTF8'),'sha256'),'hex');"


def age_fixture():
    return BASE + """
LOCK TABLE internal.initial_analysis_preparation_intents, internal.initial_cpm_photo_write_attempts,
 internal.initial_cpm_photo_write_closures IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE claim_token IS NOT NULL)
 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_admissions)
 OR EXISTS(SELECT 1 FROM internal.identification_invocations)
 OR EXISTS(SELECT 1 FROM internal.initial_preparation_execution_grants)
 OR EXISTS(SELECT 1 FROM internal.initial_cpm_verification_start_context) THEN
  RAISE EXCEPTION 'fixture not unfunded and unclaimed'; END IF;
END $$;
CREATE TEMP TABLE old_intents AS SELECT * FROM internal.initial_analysis_preparation_intents;
CREATE TEMP TABLE old_attempts AS SELECT * FROM internal.initial_cpm_photo_write_attempts;
CREATE TEMP TABLE old_closures AS SELECT * FROM internal.initial_cpm_photo_write_closures;
ALTER TABLE internal.initial_analysis_preparation_intents DISABLE TRIGGER guard_initial_preparation_storage;
ALTER TABLE internal.initial_cpm_photo_write_attempts DISABLE TRIGGER initial_cpm_photo_write_attempt_guard;
ALTER TABLE internal.initial_cpm_photo_write_closures DISABLE TRIGGER initial_cpm_photo_write_closure_immutable;
UPDATE internal.initial_analysis_preparation_intents SET
 created_at=created_at-INTERVAL '1 hour',expires_at=expires_at-INTERVAL '1 hour',
 cpm_verification_started_at=cpm_verification_started_at-INTERVAL '1 hour',
 canonical_assignment=internal.initial_canonical(canonical_assignment::JSONB||jsonb_build_object(
  'created_at_ms',(canonical_assignment::JSONB->>'created_at_ms')::BIGINT-3600000,
  'expires_at_ms',(canonical_assignment::JSONB->>'expires_at_ms')::BIGINT-3600000)),
 assignment_digest=internal.initial_cpm_photo_digest('assignment',internal.initial_canonical(
  canonical_assignment::JSONB||jsonb_build_object(
   'created_at_ms',(canonical_assignment::JSONB->>'created_at_ms')::BIGINT-3600000,
   'expires_at_ms',(canonical_assignment::JSONB->>'expires_at_ms')::BIGINT-3600000)));
UPDATE internal.initial_cpm_photo_write_attempts w SET
 created_at=w.created_at-INTERVAL '1 hour',admission_expires_at=w.admission_expires_at-INTERVAL '1 hour',
 capability_expires_at=w.capability_expires_at-INTERVAL '1 hour',issued_at=w.issued_at-INTERVAL '1 hour',
 assignment_digest=i.assignment_digest FROM internal.initial_analysis_preparation_intents i WHERE i.scan_id=w.scan_id;
UPDATE internal.initial_cpm_photo_write_closures SET observed_at=observed_at-INTERVAL '1 hour';
UPDATE internal.initial_analysis_preparation_intents i SET cpm_verification_snapshot_digest=
 encode(extensions.digest(convert_to('merian.initial-analysis.cpm-verification-start.v1'||E'\n'||
 internal.initial_cpm_verification_start_snapshot(i.owner_id,i.scan_id),'UTF8'),'sha256'),'hex')
 WHERE cpm_verification_attempt_id IS NOT NULL;
-- Validate the queued cohort events before ALTER TABLE restores the guards.
-- PostgreSQL refuses trigger DDL while these events are pending (55006).
SET CONSTRAINTS ALL IMMEDIATE;
ALTER TABLE internal.initial_analysis_preparation_intents ENABLE TRIGGER guard_initial_preparation_storage;
ALTER TABLE internal.initial_cpm_photo_write_attempts ENABLE TRIGGER initial_cpm_photo_write_attempt_guard;
ALTER TABLE internal.initial_cpm_photo_write_closures ENABLE TRIGGER initial_cpm_photo_write_closure_immutable;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM old_intents o JOIN internal.initial_analysis_preparation_intents n USING(scan_id)
  WHERE n.created_at<>o.created_at-INTERVAL '1 hour' OR n.expires_at<>o.expires_at-INTERVAL '1 hour'
   OR n.cpm_verification_started_at IS DISTINCT FROM o.cpm_verification_started_at-INTERVAL '1 hour'
   OR n.expires_at>=clock_timestamp()
   OR n.assignment_digest<>internal.initial_cpm_photo_digest('assignment',n.canonical_assignment)
   OR NOT internal.initial_cpm_photo_cohort_complete(n.scan_id))
 OR EXISTS(SELECT 1 FROM old_attempts o JOIN internal.initial_cpm_photo_write_attempts n USING(attempt_id)
  WHERE n.created_at<>o.created_at-INTERVAL '1 hour' OR n.admission_expires_at<>o.admission_expires_at-INTERVAL '1 hour'
   OR n.capability_expires_at<>o.capability_expires_at-INTERVAL '1 hour'
   OR n.issued_at IS DISTINCT FROM o.issued_at-INTERVAL '1 hour')
 OR EXISTS(SELECT 1 FROM old_closures o JOIN internal.initial_cpm_photo_write_closures n USING(attempt_id,outcome)
  WHERE n.observed_at<>o.observed_at-INTERVAL '1 hour') THEN
  RAISE EXCEPTION 'incoherent fixture time translation'; END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;
"""


def run(q):
    for path in (TEST, FIXTURE, Path(__file__),
                 Path(__file__).with_name('test_initial_cpm_verification_start.py'),
                 Path(__file__).with_name('test_initial_cpm_photo_capacity.py')):
        q.record['source_manifest'][str(path.relative_to(ROOT))] = q.digest(path)
    q.record['scope'] = 'Recovery from coherently aged committed synthetic fixtures only; pre-aging acknowledgements are not byte-identical, no real elapsed transfer or physical IO qualification.'
    source = TEST.read_text()
    markers = ('CREATE TEMP TABLE cpm_saved AS', 'CREATE TEMP TABLE closure_policy AS',
               '-- END CPM CLOSURE POLICY FIXTURE')
    if any(source.count(marker) != 1 for marker in markers):
        raise ValueError('unique setup-only fixture boundaries required')
    setup = source.split(markers[0])[0] + markers[1] + source.split(markers[1])[1].split(markers[2])[0]
    identities = [(str(uuid.uuid4()), str(uuid.uuid4())) for _ in range(3)]
    for owner, scan in identities:
        setup += f"SELECT pg_temp.admission_owner('{owner}');SELECT {create(owner, scan)}->>'outcome';\n"
        setup += f"""DO $$ DECLARE m RECORD; w internal.initial_cpm_photo_write_attempts; a TEXT; p TEXT;
BEGIN
 SELECT assignment_digest INTO STRICT a FROM internal.initial_analysis_preparation_intents WHERE scan_id='{scan}';
 SELECT digest INTO STRICT p FROM internal.initial_cpm_photo_write_policies;
 FOR m IN SELECT object_id FROM internal.initial_cpm_photo_role_mapping WHERE scan_id='{scan}' ORDER BY object_id LOOP
  w:=internal.initial_cpm_photo_write_action('bind','{owner}','{scan}',a,m.object_id);
  PERFORM internal.bind_initial_cpm_photo_write_policy('{owner}',w.attempt_id,p);
  w:=internal.initial_cpm_photo_write_action('may_have_issued','{owner}','{scan}',a,m.object_id);
  PERFORM internal.settle_initial_cpm_photo_write_closure(w.attempt_id,p,'live_object',w.issued_at,NULL);
 END LOOP;
END; $$;
"""
    setup += f"SELECT {start(*identities[0])}->>'outcome';COMMIT;"
    q.record['setup_sha256'] = hashlib.sha256(setup.encode()).hexdigest()
    q.save()
    began = time.monotonic()
    try:
        output = q.execute('normally_create_close_and_commit_one_start', setup)
        if re.search(r'^(not ok|Bail out!)', output, re.M) or output.splitlines()[-1] != 'started':
            raise RuntimeError('normal fixture start failed')
        triggers_before = q.execute('capture_enabled_trigger_definitions', TRIGGERS)
        stable_before = q.execute('capture_nonclock_state', stable_image())
        q.execute('commit_coherent_local_clock_translation', age_fixture())
        if q.execute('verify_trigger_restoration', TRIGGERS) != triggers_before:
            raise RuntimeError('fixture changed trigger definitions or enablement')
        if q.execute('verify_submitted_content_and_identities_unchanged', stable_image()) != stable_before:
            raise RuntimeError('fixture changed nonclock state')
        owner, scan = identities[0]
        image = f"SELECT internal.initial_cpm_verification_intent_digest(i) FROM internal.initial_analysis_preparation_intents i WHERE scan_id='{scan}';"
        before = q.execute('capture_aged_committed_intent', image)
        if q.execute('recover_expired_start_from_new_connection', BASE + f"SELECT {start(owner, scan)}->>'outcome';COMMIT;").splitlines()[-1] != 'held':
            raise RuntimeError('expired committed start renewed authority')
        if q.execute('recovery_keeps_aged_intent_image', image) != before:
            raise RuntimeError('recovery mutated aged committed intent')
        owner, scan = identities[1]
        if q.execute('expired_unstarted_cohort_is_structurally_valid', BASE + f"SELECT internal.initial_cpm_photo_cohort_complete('{scan}') AND octet_length(internal.initial_cpm_verification_start_snapshot('{owner}','{scan}'))>0;COMMIT;").splitlines()[-1] != 't':
            raise RuntimeError('expiry fixture denied for incoherent cohort')
        q.execute('expired_unstarted_cannot_start', denied(start(owner, scan), '22023', 'initial_analysis_storage_immutable'))
        if q.execute('denied_start_leaves_all_start_fields_null', f"SELECT num_nonnulls(cpm_verification_attempt_id,cpm_verification_started_at,cpm_verification_snapshot_digest)=0 FROM internal.initial_analysis_preparation_intents WHERE scan_id='{scan}';") != 't':
            raise RuntimeError('expired refusal persisted start')
        owner, scan = identities[2]
        assignment = q.execute('capture_exact_assignment_before_retirement', f"SELECT assignment_digest FROM internal.initial_analysis_preparation_intents WHERE scan_id='{scan}';")
        object_id = q.execute('capture_exact_object_before_retirement', f"SELECT object_id FROM internal.initial_preparation_source_registry WHERE scan_id='{scan}' ORDER BY object_id LIMIT 1;")
        if q.execute('commit_status_expiry_retirement', BASE + f"SELECT public.get_initial_preparation_status('{owner}','{scan}')=jsonb_build_object('version',1,'variant','client_prepared_photo','outcome','terminal_held','authority','none','scan_id','{scan}','reason','expired');COMMIT;").splitlines()[-1] != 't':
            raise RuntimeError('expiry status did not hold and retire')
        # Exact saved identity remains the caller's input after intent erasure.
        q.execute('retirement_blocks_later_verification', denied(f"internal.begin_initial_cpm_photo_verification('{owner}','{scan}','{assignment}')", '55000', 'initial_analysis_cancelled'))
        q.execute('retirement_blocks_later_write_binding', denied(f"internal.initial_cpm_photo_write_action('bind','{owner}','{scan}','{assignment}','{object_id}')", '55000', 'initial_analysis_cancelled'))
        if q.execute('retired_source_liability_remains', f"SELECT count(*)=3 AND bool_and(retired) AND internal.initial_cpm_photo_retired_write_hold('{scan}') FROM internal.initial_preparation_source_registry WHERE scan_id='{scan}';") != 't':
            raise RuntimeError('expiry lost source liability')
        if q.execute('no_funding_execution_admission_or_context', "SELECT NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations) AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations) AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_admissions) AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_verification_start_context);") != 't':
            raise RuntimeError('expiry granted execution')
    finally:
        finish_sessions(q, [], sys.exc_info()[1])
    q.record['wall_seconds'] = time.monotonic() - began
    q.finish()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', type=Path, required=True)
    parser.add_argument('--replay-manifest', type=Path, required=True)
    args = parser.parse_args()
    run(Qualification(args.container, args.evidence_directory, 'cpm-verification-expiry', args.replay_manifest))
