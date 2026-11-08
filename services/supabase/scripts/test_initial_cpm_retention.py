"""Disposable SQL qualification for the inactive terminal-retention reader.

Original guarded CPM admission/dispatch and synthetic result; no storage I/O,
policy installation, adoption, completion or execution authority is qualified.
"""
import argparse
import json
from pathlib import Path
import time

from initial_atomic_admission_test_support import Qualification, ROOT
from initial_cpm_atomic_admission_committed import seed_committed_admission
from initial_invocation_erasure_races import install_result_fixture
from test_initial_dispatch import FIXTURE, ROLE, CALL
from test_initial_completion_preparation import SNAPSHOT


def install_disposable_retention(q):
    q.execute('install_private_disposable_reader_adapter', """
CREATE FUNCTION public.test_cpm_terminal(p_proof JSONB DEFAULT NULL) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE a internal.initial_analysis_admissions; r internal.initial_analysis_results; policy TEXT;
BEGIN
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions;
 SELECT * INTO STRICT r FROM internal.initial_analysis_results;
 SELECT digest INTO policy FROM internal.initial_cpm_photo_retention_policies;
 IF p_proof IS NULL THEN
  RETURN internal.prepare_initial_cpm_retention_v1(a.owner_id,a.scan_id,a.submission_digest,r.result_evidence_id,encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex'),policy);
 END IF;
 RETURN internal.prepare_initial_cpm_adoption_candidate_v1(a.owner_id,a.scan_id,a.submission_digest,r.result_evidence_id,encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex'),policy,p_proof);
END $$;
REVOKE ALL ON FUNCTION public.test_cpm_terminal(JSONB) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_cpm_terminal(JSONB) TO service_role;
""")
    q.execute('no_policy_denies_reader', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_terminal(); COMMIT;', '55000')
    q.execute('install_disposable_synthetic_retention_policy', """
WITH document AS (
 SELECT jsonb_build_object('version',1,'write_policy_digest',digest,
  'retention_build_digest',repeat('a',64),'qualification_evidence_digest',repeat('b',64),
  'reviewed_revision',repeat('c',40),'protocol','cpm_in_place_adoption_v1',
  'verification_max_duration_ms',150000,'verification_max_age_ms',30000,'clock_skew_ms',1000) value
 FROM internal.initial_cpm_photo_write_policies
)
INSERT INTO internal.initial_cpm_photo_retention_policies
SELECT encode(extensions.digest(convert_to('merian.initial-analysis.cpm-retention-policy.v1'||chr(10)||internal.initial_canonical(value),'UTF8'),'sha256'),'hex'),
 value->>'write_policy_digest',value->>'retention_build_digest',value->>'qualification_evidence_digest',
 value->>'reviewed_revision',value->>'protocol',150000,30000,1000,'eligible' FROM document;
""")


def run(q):
    for p in [Path(__file__), FIXTURE,
              Path(__file__).with_name('initial_cpm_atomic_admission_committed.py'),
              Path(__file__).with_name('initial_invocation_erasure_races.py'),
              Path(__file__).with_name('test_initial_dispatch.py'),
              Path(__file__).with_name('test_initial_completion_preparation.py')]:
        q.record['source_manifest'][str(p.relative_to(ROOT))] = q.digest(p)
    q.record['scope'] = __doc__
    q.save()
    seed_committed_admission(q, 'complimentary')
    q.execute('install_synthetic_dispatch', FIXTURE.read_text())
    q.execute('original_dispatch', 'BEGIN;' + ROLE + CALL + 'COMMIT;')
    install_result_fixture(q, injected_dispatch=False)
    q.execute('retain_synthetic_original_result', 'BEGIN;' + ROLE + "SELECT public.s0_result_fixture('valid'); COMMIT;")
    install_disposable_retention(q)
    before = q.execute('original_state_before_reader', SNAPSHOT)
    q.execute('exact_original_roster_and_clock_candidate', 'BEGIN;' + ROLE + """
DO $$ DECLARE s JSONB; proof JSONB; candidate JSONB; now_ms BIGINT;
BEGIN
 s:=public.test_cpm_terminal();
 IF jsonb_array_length(s#>'{binding,objects}') NOT IN (3,6)
  OR jsonb_array_length(s->'reads')<>jsonb_array_length(s#>'{binding,objects}')
  OR s#>>'{binding,retention_build_digest}'<>repeat('a',64) THEN RAISE EXCEPTION USING ERRCODE='ZX821'; END IF;
 now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
 proof:=s->'binding'||jsonb_build_object('verification_started_at_ms',now_ms-10,'verified_at_ms',now_ms);
 candidate:=public.test_cpm_terminal(proof);
 IF (candidate-'adopted_at_ms') IS DISTINCT FROM proof
  OR (candidate->>'adopted_at_ms')::BIGINT<now_ms THEN RAISE EXCEPTION USING ERRCODE='ZX822'; END IF;
END $$; COMMIT;
""")
    after = q.execute('original_state_after_reader', SNAPSHOT)
    if before != after:
        raise ValueError('read-only terminal preparation changed original state')
    cases = {
        'extra_field': "proof||'{\"authority\":true}'::JSONB",
        'changed_result': "jsonb_set(proof,'{result_digest}',to_jsonb(repeat('d',64)))",
        'missing_role': "jsonb_set(proof,'{objects}',(proof->'objects')-0)",
        'changed_backend': "jsonb_set(proof,'{objects,0,backend_configuration_digest}',to_jsonb(repeat('d',64)))",
        'stale_finish': "proof||jsonb_build_object('verification_started_at_ms',now_ms-31001,'verified_at_ms',now_ms-31001)",
        'fresh_finish_old_start': "proof||jsonb_build_object('verification_started_at_ms',now_ms-150001)",
        'reversed_interval': "proof||jsonb_build_object('verification_started_at_ms',now_ms+1)",
        'future_clock': "proof||jsonb_build_object('verification_started_at_ms',now_ms+10000,'verified_at_ms',now_ms+10000)",
        'fractional_clock': "proof||jsonb_build_object('verified_at_ms',now_ms+0.5)",
        'missing_start': "proof-'verification_started_at_ms'",
        'string_start': "proof||jsonb_build_object('verification_started_at_ms',now_ms::TEXT)",
    }
    for name, expression in cases.items():
        q.execute('deny_' + name, 'BEGIN;' + ROLE + """
DO $$ DECLARE s JSONB; proof JSONB; now_ms BIGINT;
BEGIN
 s:=public.test_cpm_terminal(); now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
 proof:=s->'binding'||jsonb_build_object('verification_started_at_ms',now_ms,'verified_at_ms',now_ms);
 PERFORM public.test_cpm_terminal(""" + expression + "); END $$; COMMIT;", '22023')
    for table in ['initial_cpm_photo_retention_policies', 'initial_cpm_photo_write_policies', 'initial_preparation_backend_eligibility']:
        q.execute('deny_revoked_' + table, "BEGIN; UPDATE internal." + table + " SET state='revoked';" + ROLE + 'SELECT public.test_cpm_terminal(); COMMIT;', '55000')
    for mutation in ["UPDATE internal.initial_cpm_photo_retention_policies SET retention_build_digest=repeat('d',64)",
                     'DELETE FROM internal.initial_cpm_photo_retention_policies',
                     'TRUNCATE internal.initial_cpm_photo_retention_policies']:
        q.execute('deny_policy_mutation_' + mutation.split()[0].lower(), 'BEGIN; ' + mutation + '; COMMIT;', '22023')
    for role in ['anon', 'authenticated', 'service_role']:
        q.execute('deny_private_catalog_' + role, 'BEGIN; SET LOCAL ROLE ' + role + '; SELECT * FROM internal.initial_cpm_photo_retention_policies; COMMIT;', '42501')
        q.execute('deny_private_reader_' + role, 'BEGIN; SET LOCAL ROLE ' + role + '; SELECT internal.prepare_initial_cpm_retention_v1(NULL,NULL,NULL,NULL,NULL,NULL); COMMIT;', '42501')
    if q.execute('original_state_after_rejections', SNAPSHOT) != before:
        raise ValueError('denied terminal proof changed original state')
    q.execute('service_role_cannot_reach_completion_through_private_roots', 'BEGIN;' + ROLE + """
DO $$ DECLARE a internal.initial_analysis_admissions; r internal.initial_analysis_results;
BEGIN
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions;
 SELECT * INTO STRICT r FROM internal.initial_analysis_results;
 PERFORM internal.complete_initial_analysis_legacy_v1(a.owner_id,a.scan_id,a.submission_digest,r.result_evidence_id,encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex'));
END $$; COMMIT;
""", '42501')  # This adapter-free call is denied at private-root access, before completion.
    q.record['passed'] = True


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--container', required=True)
    p.add_argument('--evidence-directory', required=True)
    p.add_argument('--replay-manifest', required=True)
    a = p.parse_args()
    start = time.monotonic()
    q = Qualification(a.container, a.evidence_directory, 'initial-cpm-retention', a.replay_manifest)
    run(q)
    q.record['wall_seconds'] = time.monotonic() - start
    q.save()
    print(json.dumps({'passed': True, 'checks': len(q.record['checks'])}))


if __name__ == '__main__':
    main()
