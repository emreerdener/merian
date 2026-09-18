import importlib.util,json,pathlib,subprocess,time
root=pathlib.Path('/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-next/candidate')
out=pathlib.Path('/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-verification')
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
runner=load('runner',root/'scripts/local-ios-build.py')
reporter=load('reporter',root/'scripts/ios-runtime-audit.py')
workspace=runner.Workspace(root)
config=json.loads((root/'scripts/config/ios-runtime-audit.json').read_text())
before=workspace.audit_source_identity()
(out/'source-before.json').write_text(json.dumps(before,indent=2)+'\n')
environment=workspace.audit_environment('platform=iOS Simulator,id=33E6776C-4639-4EE9-BDB6-994A3941FEE6','MacBookPro18-1-iOS27-continuation')
(out/'environment.json').write_text(json.dumps(environment,indent=2)+'\n')
for phase in ['ui','performance']:
    if workspace.audit_source_identity()!=before: raise RuntimeError('Source changed; stop')
    existing=set(workspace.reports.glob('*.xcresult'))
    args=['simulator','--','test-without-building','-configuration','Debug','-destination','platform=iOS Simulator,id=33E6776C-4639-4EE9-BDB6-994A3941FEE6','-parallel-testing-enabled','NO']
    if phase=='performance':args+=['-test-iterations','3']
    args+=['-only-testing:'+item['selector'] for item in config[phase]]
    command=['make','ios-local-build','ARGS='+' '.join('"'+v+'"' if ' ' in v else v for v in args)]
    print('START',phase,flush=True)
    with (out/(phase+'.log')).open('w') as log: result=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT)
    bundles=set(workspace.reports.glob('*.xcresult'))-existing
    after=workspace.audit_source_identity()
    evidence={'phase':phase,'exit_code':result.returncode,'source_unchanged':before==after,'bundles':[str(p) for p in bundles],'command':command,'source':before,'environment':environment,'metric_expectations':config['performance']}
    if len(bundles)==1:
        try: evidence['execution']=reporter.extract(next(iter(bundles)),out/phase,config[phase],performance=phase=='performance')
        except Exception as error:evidence['extraction_error']=str(error)
    (out/(phase+'-evidence.json')).write_text(json.dumps(evidence,indent=2)+'\n')
    print('FINISHED',phase,result.returncode,'source_unchanged',before==after,flush=True)
    if result.returncode or before!=after:break
(out/'source-after.json').write_text(json.dumps(workspace.audit_source_identity(),indent=2)+'\n')
