import importlib.util,json,pathlib,subprocess
root=pathlib.Path('/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-closure/candidate');out=root.parent/'frozen-retry'
out.mkdir(exist_ok=True)
s=importlib.util.spec_from_file_location('runner',root/'scripts/local-ios-build.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);workspace=m.Workspace(root)
before=workspace.audit_source_identity();(out/'final-source-before.json').write_text(json.dumps(before,indent=2)+'\n')
old=set(workspace.reports.glob('audit-*'))
print('START audit',flush=True)
with (out/'audit.log').open('w') as log:
 result=subprocess.run(['make','ios-local-build','ARGS=audit --destination "platform=iOS Simulator,id=33E6776C-4639-4EE9-BDB6-994A3941FEE6" --environment-label "MacBookPro18-1-iOS27-closure"'],cwd=root,stdout=log,stderr=subprocess.STDOUT)
after=workspace.audit_source_identity();audit_dirs=set(workspace.reports.glob('audit-*'))-old
(out/'audit-execution.json').write_text(json.dumps({'exit_code':result.returncode,'audit_directories':[str(p) for p in audit_dirs],'source_unchanged':before==after},indent=2)+'\n')
print('FINISHED audit',result.returncode,'source_unchanged',before==after,flush=True)
if before!=after:raise RuntimeError('Source changed during final audit')
old=set(workspace.reports.glob('*.xcresult'))
print('START complete merianTests',flush=True)
with (out/'complete-unit.log').open('w') as log:
 result=subprocess.run(['make','ios-local-build','ARGS=simulator -- test-without-building -configuration Debug -destination "platform=iOS Simulator,id=33E6776C-4639-4EE9-BDB6-994A3941FEE6" -parallel-testing-enabled NO -only-testing:merianTests'],cwd=root,stdout=log,stderr=subprocess.STDOUT)
bundles=set(workspace.reports.glob('*.xcresult'))-old;after=workspace.audit_source_identity()
evidence={'exit_code':result.returncode,'bundles':[str(p) for p in bundles],'source_unchanged':before==after}
if len(bundles)==1:
 dest=out/'complete-unit';dest.mkdir(exist_ok=True)
 for kind in ['summary','tests']:
  extracted=subprocess.run(['xcrun','xcresulttool','get','test-results',kind,'--path',str(next(iter(bundles)))],text=True,capture_output=True)
  (dest/(kind+'.json')).write_text(extracted.stdout)
(out/'complete-execution.json').write_text(json.dumps(evidence,indent=2)+'\n')
(out/'final-source-after.json').write_text(json.dumps(after,indent=2)+'\n')
print('FINISHED complete',result.returncode,'source_unchanged',before==after,flush=True)
