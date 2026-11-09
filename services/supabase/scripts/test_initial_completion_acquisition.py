"""Admission-bound first acquisition on owned disposable journeys; no provider,
HTTP serving route, native persistence or execution from absence.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time
from initial_atomic_admission_test_support import Qualification, ROOT
from test_initial_completion_delivery import run as delivery, snapshot
from test_initial_dispatch import qualify

ADAPTER = """
CREATE TABLE public.test_acquisition_request AS
SELECT a.owner_id,a.scan_id,internal.initial_canonical(jsonb_build_object(
 'version',1,'owner_id',a.owner_id,'scan_id',a.scan_id,'route',s.route,'input_schema_version',s.input_schema_version,
 'submission_digest',a.submission_digest,'config_digest',a.configuration_digest,
 'funding_binding_id',a.funding_binding_id,'funding_binding_digest',a.funding_digest,
 'funding_binding_version',s.funding_snapshot->'version','ordered_description_digest',a.descriptions_digest,
 'ordered_description_count',jsonb_array_length(s.ordered_descriptions))) admission
FROM internal.initial_analysis_admissions a JOIN internal.initial_analysis_submissions s USING(scan_id);
REVOKE ALL ON public.test_acquisition_request FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.test_acquisition(fault TEXT DEFAULT NULL) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.test_acquisition_request; value JSONB; wire TEXT;
BEGIN
 SELECT * INTO STRICT r FROM public.test_acquisition_request;
 value:=r.admission::JSONB;
 IF fault='route' THEN value:=jsonb_set(value,'{route}',to_jsonb('changed_route'::TEXT)); END IF;
 IF fault IN ('config_digest','submission_digest','funding_binding_digest','ordered_description_digest')
  THEN value:=jsonb_set(value,ARRAY[fault],to_jsonb(repeat('f',64))); END IF;
 IF fault IN ('funding_binding_id','owner_id','scan_id')
  THEN value:=jsonb_set(value,ARRAY[fault],to_jsonb('00000000-0000-4000-8000-00000000ffff'::TEXT)); END IF;
 IF fault='input_schema_version' THEN value:=jsonb_set(value,'{input_schema_version}',to_jsonb(3-(value->>'input_schema_version')::INTEGER)); END IF;
 IF fault IN ('version','funding_binding_version','ordered_description_count')
  THEN value:=jsonb_set(value,ARRAY[fault],to_jsonb((value->>fault)::INTEGER+1)); END IF;
 IF fault='choose_result' THEN value:=value||jsonb_build_object('result_evidence_id','00000000-0000-4000-8000-00000000ffff'); END IF;
 wire:=internal.initial_canonical(value);
 IF fault='noncanonical' THEN wire:=wire||' '; END IF;
 RETURN public.discover_initial_completion_v1(r.owner_id,r.scan_id,wire);
END $$;
REVOKE ALL ON FUNCTION public.test_acquisition(TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_acquisition(TEXT) TO service_role;
"""
ROLE = 'BEGIN; SET LOCAL "request.jwt.claim.role"=\'service_role\'; SET LOCAL ROLE service_role;'


def check(q, outcome):
    if 'acquisition_installed' not in q.record:
        q.execute('install_owned_acquisition_adapter', ADAPTER)
        q.execute('acquisition_no_api_grants', """
DO $$ BEGIN IF EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 WHERE has_function_privilege(role_name,'internal.discover_initial_completion_v1(uuid,uuid,text)','EXECUTE'))
 THEN RAISE EXCEPTION USING ERRCODE='ZX865'; END IF; END $$;
""")
        q.record['acquisition_installed'] = True
    if outcome == 'deleted':
        q.execute('acquisition_denied_after_committed_deletion', ROLE + 'SELECT public.test_acquisition(); COMMIT;', '55000')
        return
    original = json.loads(q.execute('independent_acquisition_admission_' + outcome, """
SELECT jsonb_build_object('admission',r.admission::JSONB,
 'expected_result_id',(SELECT result_evidence_id FROM internal.initial_analysis_results WHERE scan_id=r.scan_id),
 'expected_invocation_id',(SELECT id FROM internal.identification_invocations WHERE scan_id=r.scan_id AND is_initial_analysis))
FROM public.test_acquisition_request r;
"""))
    reply = json.loads(q.execute('private_acquisition_' + outcome, ROLE + 'SELECT public.test_acquisition(); COMMIT;'))
    original['reply'] = reply
    result = subprocess.run(['deno','run','--frozen','--config',str(ROOT/'services/supabase/functions/deno.json'),
        str(Path(__file__).with_name('validate_initial_completion_acquisition.ts')),outcome],
        input=json.dumps(original),text=True,capture_output=True,cwd=ROOT)
    passed = result.returncode == 0 and result.stdout.strip() == '{"passed":true}'
    q.record.setdefault('first_acquisition',{})[outcome] = dict(passed=passed,exit_code=result.returncode)
    q.save()
    if not passed:
        raise ValueError('first acquisition rejected original SQL output')
    for fault in ['route','config_digest','submission_digest','funding_binding_digest','ordered_description_digest',
                  'funding_binding_id','owner_id','scan_id','input_schema_version','version','funding_binding_version',
                  'ordered_description_count','choose_result','noncanonical']:
        q.execute('acquisition_' + outcome + '_reject_' + fault,
                  ROLE + "SELECT public.test_acquisition('" + fault + "'); COMMIT;",
                  '22023' if fault in ['owner_id','scan_id','noncanonical'] else '55000')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--container',required=True);p.add_argument('--evidence-directory',required=True)
    p.add_argument('--replay-manifest',required=True);p.add_argument('--media-vector',type=int,choices=[0,1,3,6],required=True)
    p.add_argument('--before-result',action='store_true');a=p.parse_args();start=time.monotonic()
    q=Qualification(a.container,a.evidence_directory,'initial-completion-acquisition',a.replay_manifest)
    sources=[Path(__file__),Path(__file__).with_name('test_initial_completion_delivery.py'),
             Path(__file__).with_name('validate_initial_completion_acquisition.ts')]
    sources += [ROOT/'services/supabase/functions/_shared/initialAnalysis'/name for name in
                ['completionAcquisition.ts','completionDelivery.ts','resultStore.ts','resultEvidence.ts','resultEncoding.ts',
                 'resultSchemaV1.ts','completionContract.ts','completion-schema-v1.json','canonical.ts','transport.ts','mediaBinding.ts','schema.ts']]
    sources += [ROOT/'services/supabase/functions/check-scan-status/initialRecovery.ts',
                ROOT/'services/supabase/functions/_shared/initialAnalysis/completionStatusRequest.ts',
                ROOT/'services/supabase/functions/_shared/initialAnalysis/completionStatusResponse.ts']
    for source in sources:q.record['source_manifest'][str(source.relative_to(ROOT))]=q.digest(source)
    q.save()
    if a.before_result:
        if a.media_vector != 1:raise ValueError('before-result fixture explicitly legacy photo only')
        qualify(q,'complimentary',1,journey=False)
        q.execute('no_result_or_completion_exists',"""
DO $$ BEGIN IF EXISTS(SELECT 1 FROM internal.initial_analysis_results)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions) THEN RAISE EXCEPTION USING ERRCODE='ZX866'; END IF; END $$;
""")
        before=snapshot(q,'before_first_acquisition')
        check(q,'pending')
        if before != snapshot(q,'after_first_acquisition'):raise ValueError('pending acquisition changed original state')
    else:
        delivery(q,a.media_vector,acquisition_check=check)
    q.record.update(passed=True,scope=__doc__,before_result=a.before_result,media_vector=a.media_vector,wall_seconds=time.monotonic()-start)
    q.save();print(json.dumps({'passed':True,'checks':len(q.record['checks'])}))


if __name__=='__main__':main()
