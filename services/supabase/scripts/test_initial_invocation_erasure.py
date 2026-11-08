#!/usr/bin/env python3
"""Bounded S0 erasure/C1 checks; requires a fresh exact owned local replay.

Commits synthetic admission and injects the still-unavailable initial dispatch
row. Rollback assertions cover capture, stage/witness mechanics, real public C1
with retirement guards enabled, and selected scan/account erasure. Controlled
sessions select accounting/scan-erasure schedules by default or changed public
C1/accounting schedules with --c1-races; --assertions-only skips both.
--c1-races-only verifies funding and runs the C1 schedules without repeating
the rollback assertion suite. --public-c1-only selects integrated public C1
rollback cases; --media-vector selects an existing guarded media fixture. The C1
schedule commits pending/unknown cancellation and verifies late-report reuse
and fresh-session receipt/funding preservation. Only this owned database's
accounting cron is suspended and restored. Dispose on success or failure.

One family-rank scientific-retention fixture covers selected public account
composition. --complimentary selects a genuinely held complimentary credit
and verifies it before the same checks; the default verifies quota funding.
Selected injected private-result cancellation is covered; result production
and its semantic codec are not. --cpm-photo reuses the guarded committed CPM
fixture for focused C1 checks or --account-erasure. Account erasure verifies
actual service-role rollback/commit, original invocation retention, anonymized
usage and permanent media liability; it does not execute account races.
--account-reported first records synthetic successful usage through the existing
accounting owner and requires that exact event to survive anonymization.
--resource-case with --media-vector 6 or --cpm-photo records isolated capture, public C1 and
replay timing, memory-context snapshots and correlated Linux lifetime RSS
high-water; declared media maxima are metadata only, not measured media IO.
--report-witness selects dormant report adapters, real accounting and actual-role
deferred commit. Existing-winner mode additionally runs controlled event and
erasure contention; inserted-commit mode does not repeat those schedules.
No text/combined-state maximum or production resource acceptance is implied.
This does not qualify initial dispatch, all media
or all funding/account variants, the full concurrency graph, production resource budgets,
or an installed/hosted journey.
"""
import argparse
import json
import re
from pathlib import Path
from initial_atomic_admission_test_support import Qualification, ROOT
from initial_invocation_erasure_races import run as run_races, run_c1, run_report_witness, run_report_producer, run_result_producer, run_result_races
from initial_cpm_atomic_admission_committed import seed_committed_admission, account_erasure_cases

SCIENCE = Path(__file__).parents[1] / 'tests' / 'observation_scientific_retention.sql'
FIXTURE = Path(__file__).with_name('fixtures') / 'initial_invocation_erasure.sql'


def run(qualification, *, assertions_only=False, c1_races=False, complimentary=False, c1_races_only=False, public_c1_only=False, media_vector=2, cpm_photo=False, account_erasure=False, account_reported=False, size_preflight=False, resource_case=None, report_witness=None):
    for path in (Path(__file__), FIXTURE, SCIENCE, Path(__file__).with_name('initial_invocation_erasure_races.py'), Path(__file__).with_name('initial_cpm_atomic_admission_committed.py')):
        qualification.record['source_manifest'][str(path.relative_to(ROOT))] = qualification.digest(path)
    qualification.record['scope'] = __doc__
    qualification.record['assertions_only'] = assertions_only
    qualification.record['c1_races'] = c1_races or c1_races_only
    qualification.record['c1_races_only'] = c1_races_only
    qualification.record['rollback_assertions_executed'] = not (c1_races_only or report_witness)
    qualification.record['rollback_assertion_scope'] = 'report_witness' if report_witness else 'resource_observations' if resource_case else ('composite_size' if size_preflight else ('account_erasure' if account_erasure else ('integrated_public_c1' if public_c1_only else ('none' if c1_races_only else 'full'))))
    qualification.record['media_vector'] = None if cpm_photo else media_vector
    qualification.record['admission_variant'] = 'cpm_photo' if cpm_photo else 'media_sources'
    qualification.record['size_preflight'] = size_preflight
    qualification.record['resource_case'] = resource_case
    qualification.record['report_witness'] = report_witness
    if report_witness not in (None, 'existing', 'inserted-commit', 'producer', 'result', 'result-races'):
        raise ValueError('known report witness mode required')
    if report_witness and (cpm_photo or account_erasure or assertions_only or public_c1_only or c1_races or c1_races_only or size_preflight or resource_case):
        raise ValueError('report witness mode is exclusive')
    if resource_case not in (None, 'five_small', 'five_declared_max', 'cpm_photo'):
        raise ValueError('known resource fixture required')
    if resource_case == 'cpm_photo' and (not cpm_photo or media_vector != 2):
        raise ValueError('CPM resource observations require the existing CPM fixture and no media-vector override')
    if resource_case in ('five_small', 'five_declared_max') and (cpm_photo or media_vector != 6):
        raise ValueError('five-source resource observations require media vector 6 without CPM')
    qualification.record['account_reported'] = account_reported
    if account_reported and not account_erasure:
        raise ValueError('reported account mode requires account erasure')
    if account_erasure and not cpm_photo:
        raise ValueError('account erasure mode currently requires the CPM fixture')
    if cpm_photo and (not (public_c1_only or c1_races_only or account_erasure or size_preflight or resource_case == 'cpm_photo') or media_vector != 2):
        raise ValueError('CPM mode requires a focused public-C1, C1-race, account-erasure, size-preflight or CPM-resource mode and no media-vector override')
    qualification.record['funding_variant'] = 'complimentary_held' if complimentary else 'quota'
    # Prevent the installed minute cron from becoming an unobserved fourth
    # writer against deliberately old synthetic invocations. This exact job is
    # changed only after fresh-owned-local verification, never via a remote DSN.
    cron_state = qualification.execute('accounting_cron_prestate',
        "SELECT active FROM cron.job WHERE jobname='reconcile_identification_usage';")
    if cron_state not in ('t', 'f'):
        raise ValueError('one original accounting cron job required')
    qualification.record['accounting_cron_prior_active'] = cron_state == 't'
    try:
        qualification.execute('suspend_local_accounting_cron',
            "SELECT cron.alter_job(jobid,active:=false) FROM cron.job WHERE jobname='reconcile_identification_usage';")
        idle = qualification.execute('accounting_cron_has_no_inflight_run',
            "SELECT NOT EXISTS(SELECT 1 FROM cron.job_run_details r JOIN cron.job j USING(jobid) "
            "WHERE j.jobname='reconcile_identification_usage' AND r.end_time IS NULL "
            "AND r.status NOT IN ('succeeded','failed')); ")
        if idle != 't':
            raise RuntimeError('accounting cron is still running; no fixture seeded or job cancelled')
        run_cases(qualification, assertions_only=assertions_only, c1_races=c1_races, complimentary=complimentary, c1_races_only=c1_races_only, public_c1_only=public_c1_only, media_vector=media_vector, cpm_photo=cpm_photo, account_erasure=account_erasure, account_reported=account_reported, size_preflight=size_preflight, resource_case=resource_case, report_witness=report_witness)
    finally:
        qualification.execute('restore_local_accounting_cron',
            "SELECT cron.alter_job(jobid,active:=" + ('true' if cron_state == 't' else 'false') +
            ") FROM cron.job WHERE jobname='reconcile_identification_usage';")
        if qualification.execute('accounting_cron_restored',
            "SELECT active FROM cron.job WHERE jobname='reconcile_identification_usage';") != cron_state:
            raise RuntimeError('accounting cron restore mismatch')
    qualification.finish()


def seed_original_invocation(qualification, cases, scan='00000000-0000-4000-8000-000000000401'):
    if not re.fullmatch('[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', scan):
        raise ValueError('canonical synthetic scan identity required')
    provenance_start = 'CREATE FUNCTION pg_temp.invocation_provenance()'
    provenance_end = '-- The runner reuses the guarded admission fixture.'
    seed_start = 'CREATE FUNCTION pg_temp.seed_admitted_invocation('
    seed_end = '-- Admission seals intentionally outlive its composer'
    for marker in (provenance_start, provenance_end, seed_start, seed_end):
        if cases.count(marker) != 1:
            raise ValueError('unique erasure fixture boundaries required')
    injection = cases[cases.index(provenance_start):cases.index(provenance_end)]
    injection += cases[cases.index(seed_start):cases.index(seed_end)]
    qualification.execute('seed_original_invocation_for_contention', 'BEGIN;' + injection +
                          "SELECT pg_temp.seed_admitted_invocation('" + scan + "');COMMIT;")


def run_cases(qualification, *, assertions_only=False, c1_races=False, complimentary=False, c1_races_only=False, public_c1_only=False, media_vector=2, cpm_photo=False, account_erasure=False, account_reported=False, size_preflight=False, resource_case=None, report_witness=None):
    if account_erasure:
        before = seed_committed_admission(qualification, 'complimentary' if complimentary else 'absent')
        qualification.record['input_profile'] = 'vision_compat_v1'
        seed_original_invocation(qualification, FIXTURE.read_text(), '00000000-0000-4000-8000-00000000f101')
        qualification.execute('classified_account_fixture', """DO $$ BEGIN
 IF (SELECT count(*) FROM internal.identification_invocations WHERE is_initial_analysis AND event_id IS NULL
  AND scan_id='00000000-0000-4000-8000-00000000f101' AND initial_admission_receipt_id IS NOT NULL)<>1
 OR EXISTS(SELECT 1 FROM public.ai_usage_events) THEN RAISE EXCEPTION USING ERRCODE='ZX636'; END IF;
END $$;""")
        if account_reported:
            qualification.execute('complete_original_account_usage', """BEGIN;
SELECT internal.complete_identification_usage(id,'draft','{"input_tokens":21,"candidate_tokens":8,"total_tokens":29}'::JSONB)
 FROM internal.identification_invocations;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.ai_usage_events e JOIN internal.identification_invocations i ON i.event_id=e.id
     WHERE e.outcome='success' AND e.metadata->>'ai_outcome'='draft'
      AND e.prompt_tokens=21 AND e.candidate_tokens=8 AND e.total_tokens=29)<>1
 THEN RAISE EXCEPTION USING ERRCODE='ZX638'; END IF;
END $$;
COMMIT;""")
        account_erasure_cases(qualification, before, classified_invocation=True, reported_invocation=account_reported)
        return
    if cpm_photo:
        seed_committed_admission(qualification, 'complimentary' if complimentary else 'absent',
                                 scan_id='00000000-0000-4000-8000-000000000401')
        fixture = "BEGIN;SELECT set_config('request.jwt.claim.role','service_role',TRUE);"
        owner = '00000000-0000-4000-8000-00000000f001'
    else:
        fixture, owner, _ = qualification.fixture_prefix(held=complimentary)
    cases = FIXTURE.read_text().replace('00000000-0000-4000-8000-00000000f001', owner)
    vectors = json.loads((ROOT / 'services/supabase/tests/initial_atomic_admission_stage.sql').read_text().split('$vectors$')[1])
    if type(media_vector) is not int or not 1 <= media_vector <= len(vectors):
        raise ValueError('existing guarded media vector required')
    vector = vectors[media_vector - 1]
    # CPM's existing committed fixture explicitly selects vision_compat_v1;
    # it is not the legacy media-vector default (multimodal_photo_v1).
    profile = 'vision_compat_v1' if cpm_photo else vector['profile']['spec']['input_profile']
    if not re.fullmatch('[a-z0-9_]+', profile):
        raise ValueError('canonical fixture profile required')
    qualification.record['input_profile'] = profile
    admission = "SELECT pg_temp.admit_erasure_scan('00000000-0000-4000-8000-000000000401');"
    if cases.count(admission) != 1:
        raise ValueError('unique guarded admission call required')
    if cpm_photo:
        start = 'CREATE FUNCTION pg_temp.admit_erasure_scan('
        end = 'CREATE FUNCTION pg_temp.seed_admitted_invocation('
        if cases.count(start) != 1 or cases.count(end) != 1:
            raise ValueError('unique legacy admission helper boundaries required')
        cases = cases[:cases.index(start)] + cases[cases.index(end):]
        cases = cases.replace(admission, '')
    else:
        cases = cases.replace(admission, admission[:-2] + ',' + str(media_vector) + ');')
    marker = "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;"
    if cases.count(marker) != 1:
        raise ValueError('unique admission verification boundary required')
    expected = "q.complimentary_client_scan_id=q.request_id AND c.state='held'" if complimentary else "q.complimentary_client_scan_id IS NULL AND c.client_scan_id IS NULL"
    funding_check = f"""
SELECT extensions.ok((SELECT count(*)=1 AND bool_and({expected})
 FROM internal.ai_quota_reservations q
 LEFT JOIN internal.complimentary_scan_usage c ON c.user_id=q.user_id AND c.client_scan_id=q.request_id
 WHERE q.user_id='{owner}' AND q.request_id='00000000-0000-4000-8000-000000000401'),
 'fixture has the requested original funding variant');
SELECT extensions.is((SELECT accounting::JSONB#>>'{{attempt,input_profile}}'
 FROM internal.initial_preparation_admission_receipts WHERE scan_id='00000000-0000-4000-8000-000000000401'),
 '{profile}','guarded admission retains the requested media input profile');
"""
    cases = cases.replace(marker, funding_check + marker)
    if resource_case in ('five_small', 'five_declared_max'):
        from initial_atomic_admission_resource import cohort, canonical
        candidate = canonical(cohort(large=resource_case == 'five_declared_max'))
        fixture += "UPDATE media_vectors SET v=jsonb_set(v,'{candidate}',$resource_candidate$" + candidate + "$resource_candidate$::JSONB) WHERE i=6;"
        qualification.record['resource_fixture'] = {
            'canonical_candidate_bytes': len(candidate.encode()),
            'source_count': 5,
            'declared_media_maxima': resource_case == 'five_declared_max',
            'text_limit_reached': False,
            'actual_media_bytes_verified': False,
            'admission_budget_modified': False,
        }
    elif resource_case == 'cpm_photo':
        qualification.record['resource_fixture'] = {
            'cohort': 'guarded_committed_cpm_photo',
            'text_limit_reached': False,
            'actual_media_bytes_verified': False,
            'admission_budget_modified': False,
        }
    science = SCIENCE.read_text()
    begin = '-- BEGIN SCIENTIFIC RETENTION HELPERS'
    end = '-- END SCIENTIFIC RETENTION HELPERS'
    if science.count(begin) != 1 or science.count(end) != 1:
        raise ValueError('unique scientific retention fixture markers required')
    fixture += science.split(begin)[1].split(end)[0]
    selected_cases = cases
    count = 179
    if c1_races_only or size_preflight or resource_case or report_witness:
        boundary = 'BEGIN;\nCREATE TEMP TABLE fixture AS'
        if cases.count(boundary) != 1:
            raise ValueError('unique committed admission boundary required')
        selected_cases = cases.split(boundary)[0] + '\nSELECT extensions.finish();\n'
        count = 2
    elif public_c1_only:
        prefix_end = 'CREATE TEMP SEQUENCE prior_retirement_seen;'
        helper_start = 'CREATE FUNCTION pg_temp.suppress_invocation_row()'
        helper_end = 'CREATE FUNCTION pg_temp.extra_invocation_statement()'
        integrated_start = 'CREATE TEMP TABLE terminal_evidence('
        integrated_end = "SELECT extensions.is(pg_temp.erasure_probe('partial_clear')"
        for boundary in (prefix_end, helper_start, helper_end, integrated_start, integrated_end):
            if cases.count(boundary) != 1:
                raise ValueError('unique integrated C1 fixture boundaries required')
        selected_cases = (cases[:cases.index(prefix_end)] +
                          cases[cases.index(helper_start):cases.index(helper_end)] +
                          cases[cases.index(integrated_start):cases.index(integrated_end)] +
                          '\nSELECT extensions.finish();\nROLLBACK;\n')
        count = 31
    output = qualification.execute('guarded_funding_fixture' if (c1_races_only or size_preflight or resource_case or report_witness) else 'guarded_scan_and_owner_erasure', fixture +
                                   '\nSELECT extensions.no_plan();\n' + selected_cases)
    passed = (not re.search(r'^not ok\b', output, re.M)
              and len(re.findall(r'^ok \d+\b', output, re.M)) == count
              and re.search(r'^1\.\.' + str(count) + r'$', output, re.M) is not None)
    # Store assertion numbers/descriptions only, never pgtap diagnostic row data.
    qualification.record['assertion_results'] = re.findall(r'^(?:not )?ok \d+[^\n]*$', output, re.M)
    qualification.record['checks'].append({'case': 'all_pgtap_assertions', 'count': count, 'passed': passed})
    qualification.save()
    if not passed:
        raise RuntimeError('erasure assertions failed; sanitized receipt retained')
    if assertions_only or public_c1_only:
        return
    # The assertions rolled their invocation back but left the guarded admission
    # committed. Reuse that receipt; inject a single invocation for two real
    # concurrent connections, without reopening initial creation in production.
    seed_original_invocation(qualification, cases)
    if report_witness == 'result-races':
        run_result_races(qualification)
    elif report_witness == 'result':
        run_result_producer(qualification)
    elif report_witness == 'producer':
        run_report_producer(qualification)
    elif report_witness:
        run_report_witness(qualification, existing_winner=report_witness == 'existing')
    elif resource_case:
        from initial_atomic_admission_resource import accounted_resource_cases
        accounted_resource_cases(qualification, owner)
    elif size_preflight:
        path = Path(__file__).with_name('fixtures') / 'initial_cancellation_sizes.sql'
        qualification.record['source_manifest'][str(path.relative_to(ROOT))] = qualification.digest(path)
        sql = path.read_text()
        if not cpm_photo:
            sql = sql[:sql.index('-- CPM_ONLY_BEGIN')] + sql[sql.index('-- CPM_ONLY_END'):]
        output = qualification.execute('exact_composite_size_boundaries', sql)
        count = 3 if cpm_photo else 2
        passed = (not re.search(r'^not ok\b', output, re.M)
                  and len(re.findall(r'^ok \d+\b', output, re.M)) == count
                  and re.search(r'^1\.\.' + str(count) + r'$', output, re.M) is not None)
        qualification.record['size_assertions'] = re.findall(r'^(?:not )?ok \d+[^\n]*$', output, re.M)
        qualification.record['checks'].append({'case': 'all_size_assertions', 'count': count, 'passed': passed})
        qualification.save()
        if not passed:
            raise RuntimeError('size boundary assertions failed; sanitized receipt retained')
    elif c1_races or c1_races_only:
        run_c1(qualification)
    else:
        run_races(qualification)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-dir', required=True)
    parser.add_argument('--replay-manifest', required=True)
    parser.add_argument('--complimentary', action='store_true', help='Use and verify a real held complimentary credit instead of quota-only funding.')
    parser.add_argument('--account-reported', action='store_true', help='Before account erasure, complete original usage through the existing accounting owner and verify exact event preservation.')
    parser.add_argument('--cpm-photo', action='store_true', help='Reuse guarded CPM admission for focused C1 or account-erasure checks.')
    parser.add_argument('--media-vector', type=int, choices=range(1, 7), default=2, help='Existing guarded media vector: vision, photo, audio, photo/audio, video frames, video/audio.')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--report-witness', choices=('existing', 'inserted-commit', 'producer', 'result', 'result-races'), help='Test dormant report adapters with actual-role deferred commit; existing also runs controlled event and erasure schedules.')
    mode.add_argument('--resource-case', choices=('five_small', 'five_declared_max', 'cpm_photo'), help='Measure fresh-backend capture, actual accounted C1 and replay; select media vector 6 or the existing CPM photo fixture, without a production resource acceptance claim.')
    mode.add_argument('--size-preflight', action='store_true', help='Verify exact pre-aggregation composite limits using disposable structural padding, without race schedules.')
    mode.add_argument('--account-erasure', action='store_true', help='Verify actual account erasure with a classified CPM invocation, rollback, commit and retained liability.')
    mode.add_argument('--public-c1-only', action='store_true', help='Run integrated public C1 rollback cases without mechanical suites or race schedules.')
    mode.add_argument('--c1-races-only', action='store_true', help='Verify funding and run changed C1 schedules without repeating rollback assertions.')
    mode.add_argument('--c1-races', action='store_true', help='Run changed real public C1/accounting schedules instead of older scan-erasure schedules.')
    mode.add_argument('--assertions-only', action='store_true', help='Run changed boundary assertions without repeating unchanged race schedules.')
    args = parser.parse_args()
    run(Qualification(args.container, args.evidence_dir,
                      'initial-invocation-erasure', args.replay_manifest), assertions_only=args.assertions_only, c1_races=args.c1_races, complimentary=args.complimentary, c1_races_only=args.c1_races_only, public_c1_only=args.public_c1_only, media_vector=args.media_vector, cpm_photo=args.cpm_photo, account_erasure=args.account_erasure, account_reported=args.account_reported, size_preflight=args.size_preflight, resource_case=args.resource_case, report_witness=args.report_witness)
