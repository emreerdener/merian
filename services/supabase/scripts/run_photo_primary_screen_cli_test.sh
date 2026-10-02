#!/usr/bin/env bash
set -euo pipefail
photo_primary_screen_test_repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
photo_primary_screen_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-photo-primary-screen-launcher.XXXXXX")"
trap 'rm -rf -- "$photo_primary_screen_test_dir"' EXIT
python3 - "$photo_primary_screen_test_repo" "$photo_primary_screen_test_dir" <<'PY'
import os, subprocess, sys
from pathlib import Path
repo=Path(sys.argv[1]); root=Path(sys.argv[2]).resolve()
fake=root/'deno'
fake.write_text('''#!/usr/bin/env python3
import os,pathlib,sys
idx=sys.argv.index('services/supabase/scripts/evaluate_photo_primary_screen.ts'); mode=sys.argv[idx+1]; packet=pathlib.Path(sys.argv[idx+2])
assert '--no-prompt' in sys.argv and '--cached-only' in sys.argv
assert not any(k in os.environ for k in ('SUPABASE_SERVICE_ROLE_KEY','OPENAI_API_KEY','GITHUB_TOKEN'))
assert not any('synthetic-key' in x for x in sys.argv)
log=packet/'calls'; prior=log.read_text().splitlines() if log.exists() else []
with log.open('a') as f:f.write(mode+'\\n')
if mode!='--one-live':
 assert '--deny-net' in sys.argv and '--deny-env' in sys.argv
 assert not any(k in os.environ for k in ('GEMINI_PAID_API_KEY','OPENAI_EVALUATION_API_KEY'))
 if packet.name=='preflight' and mode=='report':sys.exit(1)
 if mode=='next':
  n=prior.count('--one-live')
  print('blocked' if packet.name=='blocked' else 'released' if n==0 else 'primary' if n==1 else 'complete')
else:
 arm=sys.argv[idx+3]
 assert arm in ('released','primary')
 assert os.environ['OPENAI_EVALUATION_API_KEY']=='synthetic-key-openai'
 assert 'GEMINI_PAID_API_KEY' not in os.environ
 assert '--allow-net=api.openai.com:443' in sys.argv
 print('synthetic-key-output-must-be-suppressed')
 if packet.name=='live-failure':sys.exit(1)
''');fake.chmod(0o700)
for scenario in ['ok','preflight','blocked','live-failure']:
 packet=root/scenario;packet.mkdir(mode=0o700);(packet/'screen-manifest.json').write_text('{}')
 env=dict(os.environ,PATH=str(root)+os.pathsep+os.environ['PATH'],OPENAI_EVALUATION_API_KEY='synthetic-key-openai',GEMINI_PAID_API_KEY='synthetic-key-gemini',SUPABASE_SERVICE_ROLE_KEY='excluded',OPENAI_API_KEY='excluded',GITHUB_TOKEN='excluded')
 r=subprocess.run(['bash',str(repo/'services/supabase/scripts/run_photo_primary_screen.sh'),str(packet)],env=env,capture_output=True,text=True,timeout=20)
 assert 'synthetic-key' not in r.stdout+r.stderr
 assert (r.returncode==0)==(scenario=='ok'),(scenario,r.stdout,r.stderr)
 calls=(packet/'calls').read_text().splitlines()
 assert calls.count('--one-live')==({'ok':2,'preflight':0,'blocked':0,'live-failure':1}[scenario])
print('Photo primary screen launcher: four synthetic isolation/no-retry scenarios passed; no network calls.')
PY
