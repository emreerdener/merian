import importlib.util
import json
import pathlib
import subprocess
import sys
import time

base = pathlib.Path(__file__).resolve().parent
root = base / 'candidate'
spec = importlib.util.spec_from_file_location('build', root / 'scripts/local-ios-build.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
deadline = time.monotonic() + 600
while True:
    state = subprocess.run(['pgrep', '-x', 'xcodebuild'], capture_output=True)
    if state.returncode == 1:
        break
    if state.returncode != 0:
        sys.exit('Process inspection failed')
    if time.monotonic() >= deadline:
        sys.exit('No idle build window within ten minutes; other builds left running')
    time.sleep(15)
before = module.Workspace(root).audit_source_identity()
(base / 'retry-source-before.json').write_text(json.dumps(before, indent=2) + '\n')
with (base / 'audit-retry.log').open('w') as log:
    result = subprocess.run([
        'make', 'ios-local-build',
        'ARGS=audit --destination "platform=iOS Simulator,id=33E6776C-4639-4EE9-BDB6-994A3941FEE6" --environment-label "MacBookPro18-1-iOS27-continuation"',
    ], cwd=root, stdout=log, stderr=subprocess.STDOUT)
after = module.Workspace(root).audit_source_identity()
(base / 'retry-source-after.json').write_text(json.dumps(after, indent=2) + '\n')
print('Audit exit:', result.returncode, 'Source unchanged:', before == after, flush=True)
sys.exit(result.returncode if before == after else 1)
