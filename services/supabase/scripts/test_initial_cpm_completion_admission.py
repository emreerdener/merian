"""Read-only original CPM admission before dispatch and across completion.
Fresh owned disposable databases only; no provider, HTTP grant or native pinning.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time
from initial_atomic_admission_test_support import Qualification, ROOT
from initial_cpm_atomic_admission_committed import seed_committed_admission
from test_initial_completion_delivery import run as delivery, snapshot

ROLE = 'BEGIN; SET LOCAL "request.jwt.claim.role"=\'service_role\'; SET LOCAL ROLE service_role;'
ADAPTER = """
CREATE TABLE public.test_cpm_ack_request AS
SELECT s.owner_id,s.scan_id,s.canonical_candidate,s.canonical_assignment,s.assignment_digest,
 (s.canonical_assignment::JSONB#>>'{preparation,backend_generation}')::UUID generation,
 r.cpm_retained_roles::JSONB->>'backend_configuration_digest' backend_digest,
 jsonb_build_object('version',1,'owner_id',a.owner_id,'scan_id',a.scan_id,'route',u.route,
 'input_schema_version',u.input_schema_version,'submission_digest',a.submission_digest,
 'config_digest',a.configuration_digest,'funding_binding_id',a.funding_binding_id,
 'funding_binding_digest',a.funding_digest,'funding_binding_version',u.funding_snapshot->'version',
 'ordered_description_digest',a.descriptions_digest,'ordered_description_count',jsonb_array_length(u.ordered_descriptions)) expected
FROM internal.initial_analysis_preparation_intents s JOIN internal.initial_preparation_admission_receipts r USING(scan_id)
JOIN internal.initial_analysis_admissions a USING(scan_id) JOIN internal.initial_analysis_submissions u USING(scan_id);
REVOKE ALL ON public.test_cpm_ack_request FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.test_cpm_ack(fault TEXT DEFAULT NULL) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.test_cpm_ack_request; BEGIN
 SELECT * INTO STRICT r FROM public.test_cpm_ack_request;
 IF fault='owner' THEN r.owner_id:='00000000-0000-4000-8000-00000000ffff'; END IF;
 IF fault='scan' THEN r.scan_id:='00000000-0000-4000-8000-00000000ffff'; END IF;
 IF fault='candidate' THEN r.canonical_candidate:=r.canonical_candidate||' '; END IF;
 IF fault='assignment' THEN r.canonical_assignment:=r.canonical_assignment||' '; END IF;
 IF fault='assignment_digest' THEN r.assignment_digest:=repeat('0',64); END IF;
 IF fault='backend_generation' THEN r.generation:='00000000-0000-4000-8000-00000000ffff'; END IF;
 IF fault='backend_configuration_digest' THEN r.backend_digest:=repeat('0',64); END IF;
 RETURN internal.read_initial_cpm_completion_admission_v1(r.owner_id,r.scan_id,r.canonical_candidate,
 r.canonical_assignment,r.assignment_digest,r.generation,r.backend_digest);
END $$;
REVOKE ALL ON FUNCTION public.test_cpm_ack(TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_cpm_ack(TEXT) TO service_role;

CREATE FUNCTION public.test_cpm_saved_ack(fault TEXT DEFAULT NULL) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.test_cpm_ack_request; candidate_digest TEXT; content_digest TEXT; BEGIN
 SELECT * INTO STRICT r FROM public.test_cpm_ack_request;
 candidate_digest:=r.canonical_assignment::JSONB->>'candidate_digest';
 content_digest:=r.canonical_assignment::JSONB->>'content_digest';
 IF fault='owner' THEN r.owner_id:='00000000-0000-4000-8000-00000000ffff'; END IF;
 IF fault='scan' THEN r.scan_id:='00000000-0000-4000-8000-00000000ffff'; END IF;
 IF fault='candidate' THEN r.canonical_candidate:=r.canonical_candidate||' '; END IF;
 IF fault='candidate_digest' THEN candidate_digest:=repeat('0',64); END IF;
 IF fault='content_digest' THEN content_digest:=repeat('0',64); END IF;
 IF fault='assignment_digest' THEN r.assignment_digest:=repeat('0',64); END IF;
 IF fault='backend_generation' THEN r.generation:='00000000-0000-4000-8000-00000000ffff'; END IF;
 IF fault='backend_configuration_digest' THEN r.backend_digest:=repeat('0',64); END IF;
 RETURN internal.read_initial_cpm_saved_admission_v1(r.owner_id,r.scan_id,r.canonical_candidate,
 candidate_digest,content_digest,r.assignment_digest,r.generation,r.backend_digest);
END $$;
REVOKE ALL ON FUNCTION public.test_cpm_saved_ack(TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_cpm_saved_ack(TEXT) TO service_role;

"""


def check(q, phase):
    if not q.record.get('ack_installed'):
        q.execute('install_owned_ack_adapter', ADAPTER)
        q.execute('ack_private_no_api_grants', """
DO $$ BEGIN IF EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 WHERE has_function_privilege(role_name,'internal.read_initial_cpm_completion_admission_v1(uuid,uuid,text,text,text,uuid,text)','EXECUTE')
 OR has_function_privilege(role_name,'internal.read_initial_cpm_saved_admission_v1(uuid,uuid,text,text,text,text,uuid,text)','EXECUTE'))
 THEN RAISE EXCEPTION USING ERRCODE='ZX870'; END IF; END $$;
""")
        q.record['ack_installed'] = True
    if phase == 'deleted':
        q.execute('ack_after_committed_deletion_denied', ROLE+'SELECT public.test_cpm_ack(); COMMIT;', '55000')
        q.execute('saved_ack_after_committed_deletion_denied', ROLE+'SELECT public.test_cpm_saved_ack(); COMMIT;', '55000')
        return
    before = snapshot(q,'ack_before_'+phase)
    packet = json.loads(q.execute('ack_independent_original_'+phase,"""
SELECT jsonb_build_object('binding',jsonb_build_object('owner_id',owner_id,'scan_id',scan_id,
 'candidate_canonical',canonical_candidate,'assignment_canonical',canonical_assignment,
 'assignment_digest',assignment_digest,'backend_generation',generation,'backend_configuration_digest',backend_digest),
 'expected',expected) FROM public.test_cpm_ack_request;
"""))
    reply = q.execute('ack_original_'+phase, ROLE+'SELECT public.test_cpm_ack(); COMMIT;')
    packet['reply'] = json.loads(reply)
    packet['saved_reply'] = json.loads(q.execute('saved_ack_original_'+phase, ROLE+'SELECT public.test_cpm_saved_ack(); COMMIT;'))
    if packet['saved_reply']['acknowledgement'] != packet['reply']: raise ValueError('saved acknowledgement differs from exact original reader')
    result = subprocess.run(['deno','run','--frozen','--allow-env','--config',str(ROOT/'services/supabase/functions/deno.json'),
        str(Path(__file__).with_name('validate_initial_cpm_completion_admission.ts'))],
        input=json.dumps(packet),text=True,capture_output=True,cwd=ROOT)
    passed=result.returncode==0 and result.stdout.strip()=='{"passed":true}'
    q.record.setdefault('ack_transport',{})[phase]={'passed':passed,'exit_code':result.returncode}
    q.save()
    if not passed: raise ValueError('SQL acknowledgement failed Deno contract')
    # Preserve original acknowledgement identity across real completion and later edits.
    import hashlib
    digest=hashlib.sha256(reply.encode()).hexdigest()
    prior=q.record.setdefault('ack_reply_digest',digest)
    if prior!=digest: raise ValueError('acknowledgement changed after completion')
    for fault in ['owner','scan','candidate','assignment','assignment_digest','backend_generation','backend_configuration_digest']:
        q.execute('ack_'+phase+'_reject_'+fault, ROLE+"SELECT public.test_cpm_ack('"+fault+"'); COMMIT;",
                  'P0002' if fault=='owner' else '22023')
    for fault in ['owner','scan','candidate','candidate_digest','content_digest','assignment_digest','backend_generation','backend_configuration_digest']:
        q.execute('saved_ack_'+phase+'_reject_'+fault, ROLE+"SELECT public.test_cpm_saved_ack('"+fault+"'); COMMIT;",
                  'P0002' if fault=='owner' else '22023')
    if before != snapshot(q,'ack_after_'+phase): raise ValueError('acknowledgement mutated original state')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--container',required=True);p.add_argument('--evidence-directory',required=True)
    p.add_argument('--replay-manifest',required=True);p.add_argument('--before-dispatch',action='store_true')
    a=p.parse_args();start=time.monotonic()
    q=Qualification(a.container,a.evidence_directory,'initial-cpm-completion-admission',a.replay_manifest)
    sources=[Path(__file__),Path(__file__).with_name('validate_initial_cpm_completion_admission.ts'),
             Path(__file__).with_name('test_initial_completion_delivery.py')]
    sources += list((ROOT/'services/supabase/functions/_shared/initialAnalysis').rglob('*.ts'))
    sources += list((ROOT/'services/supabase/functions/_shared/initialAnalysis').rglob('*.json'))
    for source in sources:q.record['source_manifest'][str(source.relative_to(ROOT))]=q.digest(source)
    q.save()
    if a.before_dispatch:
        seed_committed_admission(q,'complimentary')
        q.execute('no_dispatch_or_completion',"""
DO $$ BEGIN IF EXISTS(SELECT 1 FROM internal.identification_invocations)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions)
 OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE state='pending_pre_dispatch')
 THEN RAISE EXCEPTION USING ERRCODE='ZX871'; END IF; END $$;
""")
        check(q,'pre_dispatch')
    else: delivery(q,0,acquisition_check=check)
    q.record.update(passed=True,scope=__doc__,before_dispatch=a.before_dispatch,wall_seconds=time.monotonic()-start)
    q.save(); print(json.dumps({'passed':True,'checks':len(q.record['checks'])}))


if __name__=='__main__':main()
