#!/usr/bin/env bash
set -euo pipefail
gemini_baseline_test_repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
gemini_baseline_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-gemini-baseline-launcher.XXXXXX")"
trap 'rm -rf -- "$gemini_baseline_test_dir"' EXIT
python3 - "$gemini_baseline_test_repo" "$gemini_baseline_test_dir" <<'PY'
import errno, json, os, pty, select, signal, sys, time
from pathlib import Path
repo=Path(sys.argv[1]); root=Path(sys.argv[2]).resolve()
key='synthetic-gemini-credential'
fake=root/'deno'
fake.write_text('''#!/usr/bin/env python3
import json, os, pathlib, signal, sys
entry=sys.argv.index('services/supabase/scripts/evaluate_gemini_photo_baseline.ts')
mode=sys.argv[entry+1]; packet=pathlib.Path(sys.argv[entry+2])
assert 'synthetic-gemini-credential' not in ' '.join(sys.argv)
assert '--cached-only' in sys.argv and '--no-prompt' in sys.argv
assert all(k not in os.environ for k in ('SUPABASE_SERVICE_ROLE_KEY','OPENAI_API_KEY','GITHUB_TOKEN'))
with (packet/'calls').open('a') as f: f.write(mode+'\\n')
if mode=='prepare':
 assert 'GEMINI_PAID_API_KEY' not in os.environ
 assert '--deny-net' in sys.argv and '--deny-env' in sys.argv
 if packet.name=='bad-preflight': sys.exit(1)
else:
 assert os.environ['GEMINI_PAID_API_KEY']=='synthetic-gemini-credential'
 assert '--allow-env=GEMINI_PAID_API_KEY,GOOGLE_SDK_NODE_LOGGING,GOOGLE_GENAI_DEBUG,WS_NO_BUFFER_UTIL,WS_NO_UTF_8_VALIDATE,GOOGLE_GENAI_USE_ENTERPRISE,GOOGLE_GENAI_USE_VERTEXAI,GOOGLE_CLOUD_PROJECT,GOOGLE_CLOUD_LOCATION,GOOGLE_VERTEX_BASE_URL,GOOGLE_GEMINI_BASE_URL,GOOGLE_API_KEY,GEMINI_API_KEY' in sys.argv
 assert '--deny-env=SUPABASE_*,R2_*,GOOGLE_APPLICATION_CREDENTIALS,OPENAI_*' in sys.argv
 assert '--allow-net=generativelanguage.googleapis.com:443' in sys.argv
 assert '--allow-run=git' in sys.argv
 assert str(packet.parent/'.gemini-baseline-authorizations') in next(a for a in sys.argv if a.startswith('--allow-write='))
 print(os.environ['GEMINI_PAID_API_KEY'], flush=True)
 if packet.name=='interrupted':
  (packet/'started').touch(); signal.pause()
 if packet.name=='bad-live': sys.exit(1)
 (packet/'gemini-report.json').write_text(json.dumps({'version':'gemini_photo_baseline_report_v1',
  'complete':packet.name!='stopped','attempted':6 if packet.name!='stopped' else 1,'stop':None if packet.name!='stopped' else 'provider_failure'}))
''')
fake.chmod(0o700)
for scenario in ('ok','bad-preflight','bad-live','stopped','interrupted'):
 packet=root/scenario; packet.mkdir(mode=0o700)
 pid, master=pty.fork()
 if pid==0:
  env=dict(os.environ,PATH=str(root)+os.pathsep+os.environ['PATH'],OPENAI_API_KEY='excluded',SUPABASE_SERVICE_ROLE_KEY='excluded',GITHUB_TOKEN='excluded')
  os.execvpe('bash',['bash',str(repo/'services/supabase/scripts/run_gemini_photo_baseline.sh'),str(packet)],env)
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
   if b'Paste Naturebook Gemini key' in output and not entered:
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
print('Gemini baseline hidden-key launcher: 5 synthetic PTY scenarios passed; no network calls.')
PY
