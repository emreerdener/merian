#!/usr/bin/env bash
set -euo pipefail
reasoning_test_repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
reasoning_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-reasoning-launcher.XXXXXX")"
trap 'rm -rf -- "$reasoning_test_dir"' EXIT
python3 - "$reasoning_test_repo" "$reasoning_test_dir" <<'PY'
import errno, json, os, pty, select, signal, sys, time
from pathlib import Path
repo=Path(sys.argv[1]); root=Path(sys.argv[2]).resolve()
key='synthetic-reasoning-credential'
fake=root/'deno'
fake.write_text('''#!/usr/bin/env python3
import json, os, pathlib, signal, sys
entry=sys.argv.index('services/supabase/scripts/evaluate_openai_reasoning.ts')
mode=sys.argv[entry+1]; packet=pathlib.Path(sys.argv[entry+2])
assert 'synthetic-reasoning-credential' not in ' '.join(sys.argv)
assert '--cached-only' in sys.argv and '--no-prompt' in sys.argv
assert all(k not in os.environ for k in ('SUPABASE_SERVICE_ROLE_KEY','OPENAI_API_KEY','GITHUB_TOKEN'))
with (packet/'calls').open('a') as f: f.write(mode+'\\n')
if mode=='prepare':
 assert 'OPENAI_EVALUATION_API_KEY' not in os.environ
 assert '--deny-net' in sys.argv and '--deny-env' in sys.argv
 if packet.name=='bad-preflight': sys.exit(1)
else:
 assert os.environ['OPENAI_EVALUATION_API_KEY']=='synthetic-reasoning-credential'
 assert '--allow-env=OPENAI_EVALUATION_API_KEY' in sys.argv
 assert '--deny-env=SUPABASE_*,R2_*,GOOGLE_*,GEMINI_*,WS_*,OPENAI_API_KEY' in sys.argv
 assert '--allow-net=api.openai.com:443,127.0.0.1' in sys.argv
 assert '--allow-run=git,/usr/bin/open' in sys.argv
 assert str(packet.parent/'.reasoning-authorizations') in next(a for a in sys.argv if a.startswith('--allow-write='))
 print(os.environ['OPENAI_EVALUATION_API_KEY'], flush=True)
 if packet.name=='interrupted':
  (packet/'started').touch(); signal.pause()
 if packet.name=='bad-live': sys.exit(1)
 (packet/'reasoning-report.json').write_text(json.dumps({'version':'openai_photo_reasoning_report_v1',
  'complete':packet.name!='stopped','attempted':12 if packet.name!='stopped' else 1,'stop':None if packet.name!='stopped' else 'provider_failure'}))
''')
fake.chmod(0o700)
for scenario in ('ok','bad-preflight','bad-live','stopped','interrupted'):
 packet=root/scenario; packet.mkdir(mode=0o700)
 pid, master=pty.fork()
 if pid==0:
  env=dict(os.environ,PATH=str(root)+os.pathsep+os.environ['PATH'],OPENAI_API_KEY='excluded',SUPABASE_SERVICE_ROLE_KEY='excluded',GITHUB_TOKEN='excluded')
  os.execvpe('bash',['bash',str(repo/'services/supabase/scripts/run_openai_reasoning.sh'),str(packet)],env)
 output=b''; entered=False; cancelled=False; status=None; deadline=time.monotonic()+12
 try:
  while time.monotonic()<deadline:
   ready,_,_=select.select([master],[],[],0.05)
   if ready:
    try: chunk=os.read(master,65536)
    except OSError as e:
     if e.errno==errno.EIO: chunk=b''
     else: raise
    output+=chunk
   if b'Paste Naturebook OpenAI key' in output and not entered:
    os.write(master,(key+'\n').encode()); entered=True
   if scenario=='interrupted' and (packet/'started').exists() and not cancelled:
    os.write(master,b'\x03'); cancelled=True
   ended, result=os.waitpid(pid,os.WNOHANG)
   if ended: status=result; break
  assert status is not None, 'launcher timeout'
  assert key.encode() not in output, 'credential leaked'
  calls=(packet/'calls').read_text().splitlines()
  assert calls==(['prepare'] if scenario=='bad-preflight' else ['prepare','--live']), (scenario,calls,output)
  assert entered==(scenario!='bad-preflight'), scenario
  assert (os.waitstatus_to_exitcode(status)==0)==(scenario=='ok'), (scenario,status,output)
  assert (b'Comparison complete:' in output)==(scenario=='ok')
 finally:
  if status is None:
   os.killpg(pid,signal.SIGKILL); os.waitpid(pid,0)
  os.close(master)
print('Reasoning hidden-key launcher: 5 synthetic PTY scenarios passed; no network calls.')
PY
