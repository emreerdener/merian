import importlib.util,json,pathlib,subprocess,time,sys
base=pathlib.Path(__file__).resolve().parent;root=base/'candidate'
spec=importlib.util.spec_from_file_location('build',root/'scripts/local-ios-build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def run_when_idle(arguments,logname):
    deadline=time.monotonic()+600
    while True:
        state=subprocess.run(['pgrep','-x','xcodebuild'],capture_output=True)
        if state.returncode==1: break
        if state.returncode!=0: raise RuntimeError('Process inspection failed')
        if time.monotonic()>=deadline: raise RuntimeError('No build window within ten minutes')
        time.sleep(15)
    print('Starting '+logname,flush=True)
    with (base/logname).open('w') as log:
        result=subprocess.run(['make','ios-local-build','ARGS='+arguments],cwd=root,stdout=log,stderr=subprocess.STDOUT)
    print(logname+' exit '+str(result.returncode),flush=True)
    return result.returncode
identity=m.Workspace(root).audit_source_identity()
(base/'validation-source-before.json').write_text(json.dumps(identity,indent=2)+'\n')
status=run_when_idle('audit --destination "platform=iOS Simulator,id=33E6776C-4639-4EE9-BDB6-994A3941FEE6" --environment-label "MacBookPro18-1-iOS27-final"','audit.log')
audits=list((root/'.artifacts/local-ios').glob('audit-*/audit.json'))
if not audits: sys.exit('Audit produced no retained report')
audit=max(audits,key=lambda p:p.stat().st_mtime);evidence=json.loads(audit.read_text())
(base/'audit-location.txt').write_text(str(audit)+'\n')
if any(p['name']=='build' and p['status']=='passed' for p in evidence['phases']) and m.Workspace(root).audit_source_identity()==identity:
    full=run_when_idle('simulator -- test-without-building -configuration Debug -destination "platform=iOS Simulator,id=33E6776C-4639-4EE9-BDB6-994A3941FEE6" -parallel-testing-enabled NO -only-testing:merianTests','complete-unit.log')
    status=status or full
else: print('Full target blocked: audit build/source identity not validated.',flush=True)
after=m.Workspace(root).audit_source_identity();(base/'validation-source-after.json').write_text(json.dumps(after,indent=2)+'\n')
print('Final source unchanged:',identity==after,flush=True)
sys.exit(status if identity==after else 1)
