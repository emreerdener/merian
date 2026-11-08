"""Private completion delivery reader on fresh disposable all-media journeys.

No HTTP grant, native import, provider or physical blob claim. Test-only adapters
invoke the private reader with service claims. Synthetic responses cross the
existing transport in memory only; evidence retains booleans, never bodies.
"""
import argparse
import json
import subprocess
from pathlib import Path
import time

from initial_atomic_admission_test_support import Qualification, ROOT
from test_initial_completion_preparation import run as legacy, SNAPSHOT
from test_initial_cpm_completion import initialize
from test_initial_cpm_completion_replay import MEDIA_SNAPSHOT
from test_initial_dispatch import ROLE

ADAPTER = """
CREATE TABLE public.test_delivery_request AS
SELECT r.owner_id,r.scan_id,a.submission_digest,r.result_evidence_id,
 encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex') digest,
 jsonb_build_object('owner_id',r.owner_id,'scan_id',r.scan_id,'invocation_id',i.id,
  'result_evidence_id',r.result_evidence_id,'submission_digest',a.submission_digest,
  'config_digest',a.configuration_digest,'funding_binding_digest',a.funding_digest) reference,
 jsonb_build_object('route',s.route,'input_schema_version',s.input_schema_version,
  'funding_binding_id',a.funding_binding_id,'funding_binding_version',s.funding_snapshot->'version',
  'ordered_description_digest',a.descriptions_digest,'ordered_description_count',jsonb_array_length(s.ordered_descriptions)) binding,
 i.provenance original_provenance
FROM internal.initial_analysis_results r JOIN internal.initial_analysis_admissions a USING(scan_id)
JOIN internal.initial_analysis_submissions s USING(scan_id)
JOIN internal.identification_invocations i ON i.scan_id=r.scan_id AND i.is_initial_analysis;
REVOKE ALL ON public.test_delivery_request FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.test_delivery(fault TEXT DEFAULT NULL) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE request public.test_delivery_request; BEGIN
 SELECT * INTO STRICT request FROM public.test_delivery_request;
 IF fault='owner' THEN SELECT id INTO STRICT request.owner_id FROM public.users WHERE id<>request.owner_id ORDER BY id LIMIT 1; END IF;
 IF fault='missing_owner' THEN request.owner_id:='00000000-0000-4000-8000-00000000ffff'; END IF;
 IF fault='submission' THEN request.submission_digest:=repeat('f',64); END IF;
 IF fault='result' THEN request.result_evidence_id:='00000000-0000-4000-8000-00000000ffff'; END IF;
 IF fault='digest' THEN request.digest:=repeat('f',64); END IF;
 RETURN internal.read_initial_completion_v1(request.owner_id,request.scan_id,request.submission_digest,request.result_evidence_id,request.digest);
END $$;
REVOKE ALL ON FUNCTION public.test_delivery(TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_delivery(TEXT) TO service_role;
"""

DOCUMENTS = """
SELECT encode(extensions.digest(convert_to(jsonb_build_array(
 (SELECT jsonb_agg(to_jsonb(r) ORDER BY scan_id) FROM internal.initial_analysis_results r),
 (SELECT jsonb_agg(to_jsonb(c) ORDER BY scan_id) FROM internal.initial_analysis_completions c),
 (SELECT jsonb_agg(to_jsonb(s) ORDER BY scan_id) FROM internal.initial_analysis_submissions s)
)::TEXT,'UTF8'),'sha256'),'hex');
"""


def snapshot(q, label):
    return [q.execute(label + '/' + name, sql) for name, sql in
            [('financial_and_scan', SNAPSHOT), ('media', MEDIA_SNAPSHOT), ('documents', DOCUMENTS)]]


def verify_transport(q, outcome):
    # Expected facts are copied from admission/submission/invocation before any
    # delivery read, not inferred from the completion receipt or returned result.
    original = q.execute('original_' + outcome + '_request_in_memory', """
SELECT jsonb_build_object('reference',reference,'binding',binding,
 'provenance',original_provenance,'digest',digest)
FROM public.test_delivery_request;
""")
    reply = q.execute('original_' + outcome + '_delivery_in_memory', """
BEGIN; SET LOCAL "request.jwt.claim.role"='service_role'; SET LOCAL ROLE service_role;
SELECT public.test_delivery(); COMMIT;
""")
    packet = json.loads(original)
    packet['reply'] = json.loads(reply)
    result = subprocess.run([
        'deno', 'run', '--frozen', '--config',
        str(ROOT / 'services/supabase/functions/deno.json'),
        str(Path(__file__).with_name('validate_initial_completion_delivery.ts')), outcome,
    ], input=json.dumps(packet), text=True, capture_output=True, cwd=ROOT)
    passed = result.returncode == 0 and result.stdout.strip() == '{"passed":true}'
    q.record.setdefault('completion_delivery_transport', {})[outcome] = {
        'passed': passed, 'exit_code': result.returncode,
    }
    q.save()
    if not passed:
        raise ValueError('completion delivery transport rejected original SQL output')


def run(q, vector, acquisition_check=None):
    if vector == 0:
        initialize(q)
    else:
        legacy(q, 'complimentary', vector, journey_only=True)
    q.record.update(passed=False, scope=__doc__, media_vector=vector)
    for source in [Path(__file__), Path(__file__).with_name('test_initial_cpm_completion.py'),
                   Path(__file__).with_name('test_initial_completion_preparation.py'),
                   Path(__file__).with_name('test_initial_cpm_completion_replay.py'),
                   Path(__file__).with_name('validate_initial_completion_delivery.ts')]:
        q.record['source_manifest'][str(source.relative_to(ROOT))] = q.digest(source)
    for name in ['completionDelivery.ts', 'resultStore.ts', 'completionContract.ts',
                 'completion-schema-v1.json', 'resultEvidence.ts', 'resultEncoding.ts',
                 'resultSchemaV1.ts', 'canonical.ts', 'mediaBinding.ts', 'schema.ts', 'transport.ts']:
        source = ROOT / 'services/supabase/functions/_shared/initialAnalysis' / name
        q.record['source_manifest'][str(source.relative_to(ROOT))] = q.digest(source)
    q.save()
    owner_fixture = ROOT / 'services/supabase/tests/initial_cpm_photo_intents.sql'
    source = owner_fixture.read_text()
    begin = 'CREATE FUNCTION pg_temp.admission_owner('
    if source.count(begin) != 1:
        raise ValueError('unique existing synthetic owner fixture required')
    fixture = source[source.index(begin):].split('$$;', 1)[0] + '$$;'
    q.record['source_manifest'][str(owner_fixture.relative_to(ROOT))] = q.digest(owner_fixture)
    q.execute('seed_explicit_existing_foreign_owner', 'BEGIN;' + fixture + 'SELECT pg_temp.admission_owner(gen_random_uuid()); COMMIT;')
    q.execute('install_owned_local_delivery_adapter', ADAPTER)
    q.execute('private_reader_has_no_api_grants', """
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
  WHERE has_function_privilege(role_name,'internal.read_initial_completion_v1(uuid,uuid,text,uuid,text)','EXECUTE'))
 THEN RAISE EXCEPTION USING ERRCODE='ZX860'; END IF;
END $$;
""")
    if vector == 0:
        before = snapshot(q, 'before_absent_read')
        q.execute('absent_completion_does_not_finalize', 'BEGIN;' + ROLE + """
DO $$ DECLARE reply JSONB; BEGIN
 reply:=public.test_delivery();
 IF reply->>'outcome' IS DISTINCT FROM 'absent' OR reply->'completion' IS DISTINCT FROM 'null'::JSONB
  OR reply->'result' IS DISTINCT FROM 'null'::JSONB OR reply#>>'{reference,scan_id}' IS NULL
 THEN RAISE EXCEPTION USING ERRCODE='ZX861'; END IF;
END $$; COMMIT;
""")
        verify_transport(q, 'absent')
        if acquisition_check:
            acquisition_check(q, 'pending')
        if snapshot(q, 'after_absent_read') != before:
            raise ValueError('absent completion read changed original state')
        q.execute('complete_original_cpm_for_delivery', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_complete(); COMMIT;')
        q.execute('later_user_note', "UPDATE public.scans SET human_intervention_notes='synthetic later note';")
    before = snapshot(q, 'before_found_read')
    q.execute('exact_immutable_completed_delivery', 'BEGIN;' + ROLE + """
DO $$ DECLARE reply JSONB; saved internal.initial_analysis_completions; result internal.initial_analysis_results; BEGIN
 RESET ROLE;
 SELECT * INTO STRICT saved FROM internal.initial_analysis_completions;
 SELECT * INTO STRICT result FROM internal.initial_analysis_results;
 SET LOCAL ROLE service_role;
 reply:=public.test_delivery();
 RESET ROLE;
 IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(reply) key)
    IS DISTINCT FROM ARRAY['completion','outcome','reference','result','version']::TEXT[]
  OR reply->>'outcome' IS DISTINCT FROM 'found'
  OR reply#>>'{completion,receipt_canonical}' IS DISTINCT FROM internal.initial_canonical(saved.receipt_snapshot)
  OR reply#>>'{completion,projection_canonical}' IS DISTINCT FROM internal.initial_canonical(saved.completion_projection_snapshot)
  OR reply#>>'{result,result_canonical}' IS DISTINCT FROM internal.initial_canonical(result.result_snapshot)
  OR reply#>>'{result,provenance_canonical}' IS DISTINCT FROM internal.initial_canonical(result.provenance_snapshot)
  OR reply->'reference' IS DISTINCT FROM reply#>'{result,reference}'
 THEN RAISE EXCEPTION USING ERRCODE='ZX862'; END IF;
END $$; COMMIT;
""")
    verify_transport(q, 'found')
    if acquisition_check:
        acquisition_check(q, 'found')
    for fault in ['owner', 'missing_owner', 'submission', 'result', 'digest']:
        q.execute('wrong_' + fault + '_denied', 'BEGIN;' + ROLE + "SELECT public.test_delivery('" + fault + "'); COMMIT;", 'P0002' if fault in ['owner', 'missing_owner'] else '55000')
        if fault in ['owner', 'missing_owner'] and q.record['checks'][-1]['error_owners'][:1] != ['internal.lock_initial_preparation_scope']:
            q.record['checks'][-1].update(passed=False, wrong_denial_owner=True)
            q.save()
            raise ValueError('owner denial must reach the existing owner lock, not fail fixture lookup')
    if snapshot(q, 'after_found_and_denied_reads') != before:
        raise ValueError('completion read changed retained state or later selection')
    q.execute('committed_scan_erasure', """
BEGIN;
DO $$ DECLARE request public.test_delivery_request; BEGIN
 SELECT * INTO STRICT request FROM public.test_delivery_request;
 SET LOCAL ROLE service_role;
 IF public.request_scan_deletion(request.scan_id,request.owner_id) IS DISTINCT FROM 'accepted'
 THEN RAISE EXCEPTION USING ERRCODE='ZX863'; END IF;
END $$; COMMIT;
""")
    q.execute('erased_completion_cannot_be_delivered', 'BEGIN;' + ROLE + 'SELECT public.test_delivery(); COMMIT;', '55000')
    if acquisition_check:
        acquisition_check(q, 'deleted')
    q.record.update(passed=True)
    q.save()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--container', required=True)
    p.add_argument('--evidence-directory', required=True)
    p.add_argument('--replay-manifest', required=True)
    p.add_argument('--media-vector', type=int, choices=[0, 1, 3, 6], required=True)
    a = p.parse_args()
    started = time.monotonic()
    q = Qualification(a.container, a.evidence_directory, 'initial-completion-delivery', a.replay_manifest)
    run(q, a.media_vector)
    q.record['wall_seconds'] = time.monotonic() - started
    q.save()
    print(json.dumps({'passed': True, 'checks': len(q.record['checks'])}))


if __name__ == '__main__':
    main()
