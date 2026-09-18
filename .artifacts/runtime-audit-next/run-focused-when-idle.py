import importlib.util,json,pathlib,subprocess,time,sys
base=pathlib.Path(__file__).resolve().parent
root=base/'candidate'
spec=importlib.util.spec_from_file_location('build',root/'scripts/local-ios-build.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
deadline=time.monotonic()+600
while True:
    state=subprocess.run(['pgrep','-x','xcodebuild'],capture_output=True)
    if state.returncode==1: break
    if state.returncode!=0: sys.exit('Process inspection failed; stopped.')
    if time.monotonic()>=deadline: sys.exit('No build window within ten minutes; stopped without interference.')
    time.sleep(15)
identity=m.Workspace(root).audit_source_identity()
(base/'focused-source-before.json').write_text(json.dumps(identity,indent=2)+'\n')
args='simulator -- test -configuration Debug -destination "platform=iOS Simulator,id=33E6776C-4639-4EE9-BDB6-994A3941FEE6" -parallel-testing-enabled NO -only-testing:merianTests/DiskBackedInferenceAcceptanceTests -only-testing:merianTests/InferenceLivePipelineCoordinatorTests -only-testing:merianTests/InferenceLivePipelineDurableVisualTests -only-testing:merianTests/AuthLocalSignOutCoordinatorTests'
print('Build window available; invoking managed wrapper.',flush=True)
with (base/'focused-final.log').open('w') as log:
    result=subprocess.run(['make','ios-local-build','ARGS='+args],cwd=root,stdout=log,stderr=subprocess.STDOUT)
after=m.Workspace(root).audit_source_identity()
(base/'focused-source-after.json').write_text(json.dumps(after,indent=2)+'\n')
print('Wrapper exit:',result.returncode,'source unchanged:',identity==after,flush=True)
sys.exit(result.returncode if identity==after else 1)
