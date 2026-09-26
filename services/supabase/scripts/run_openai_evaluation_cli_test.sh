#!/usr/bin/env bash
set -euo pipefail

evaluation_test_repository="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
evaluation_test_directory="$(mktemp -d "${TMPDIR:-/tmp}/merian-openai-launcher.XXXXXX")"
trap 'rm -rf -- "$evaluation_test_directory"' EXIT
python3 - "$evaluation_test_repository" "$evaluation_test_directory" <<'PYTHON'
import errno
import hashlib
import json
import os
from pathlib import Path
import pty
import select
import shutil
import stat
import subprocess
import sys
import time

repository = Path(sys.argv[1])
root = Path(sys.argv[2]).resolve()
launcher = repository / "services/supabase/scripts/run_openai_evaluation.sh"
key = "synthetic-local-launcher-value"
real_deno = shutil.which("deno")
assert real_deno, "the repository-pinned Deno is required"
# Synthetic credentials only; the real runtime probe checks admission without dispatch.
fake = root / "deno"
fake.write_text(r'''#!/usr/bin/env python3
import json, os, pathlib, signal, sys
packet = pathlib.Path(sys.argv[-1])
mode = sys.argv[-2]
assert mode in ('preflight', '--live')
assert '--cached-only' in sys.argv
assert all(name not in os.environ for name in ('SUPABASE_SERVICE_ROLE_KEY', 'GITHUB_TOKEN', 'OPENAI_API_KEY', 'GIT_CONFIG_COUNT', 'GEMINI_PAID_API_KEY'))
assert 'synthetic-local-launcher-value' not in ' '.join(sys.argv)
if mode == 'preflight':
    assert 'OPENAI_EVALUATION_API_KEY' not in os.environ
    assert '--deny-net' in sys.argv and '--deny-env' in sys.argv
else:
    assert os.environ.get('OPENAI_EVALUATION_API_KEY') == 'synthetic-local-launcher-value'
    assert '--allow-net=api.openai.com:443' in sys.argv
    assert '--allow-env=OPENAI_EVALUATION_API_KEY' in sys.argv
    assert '--allow-run=git' in sys.argv
with (packet / 'calls.jsonl').open('a') as output:
    output.write(json.dumps({'mode': mode}) + '\n')
if mode == '--live' and (packet / 'check-permissions').exists():
    flags = sys.argv[1:-3]
    # Use the actual launcher flags and actual permission gate; never invoke a provider.
    code = """
import { liveCredential } from "./services/supabase/scripts/identification_evaluation/admission.ts";
globalThis.fetch = () => { throw new Error("network_forbidden_in_permission_probe"); };
if (await liveCredential("openai") !== "synthetic-local-launcher-value") Deno.exit(1);
"""
    import subprocess
    check = subprocess.run([__REAL_DENO__, *flags, '-'], input=code, text=True,
                           env=os.environ, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    sys.exit(check.returncode)
if mode == '--live' and (packet / 'pause-live').exists():
    (packet / 'claim.marker').write_text('started')
    print(os.environ['OPENAI_EVALUATION_API_KEY'], flush=True)
    signal.pause()
if (packet / ('fail-' + mode.lstrip('-'))).exists():
    print(os.environ.get('OPENAI_EVALUATION_API_KEY', 'synthetic-upstream-private-output'))
    sys.exit(1)
'''.replace('__REAL_DENO__', repr(real_deno)))
fake.chmod(0o700)
environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'])
for name in ('SUPABASE_SERVICE_ROLE_KEY', 'GITHUB_TOKEN', 'OPENAI_API_KEY', 'GIT_CONFIG_COUNT', 'GEMINI_PAID_API_KEY', 'OPENAI_EVALUATION_API_KEY'):
    environment[name] = 'synthetic-unrelated-value'

def packet(name):
    path = root / name
    path.mkdir(mode=0o700)
    (path / 'spec.json').write_text(json.dumps({
        'version': 'identification_provider_run_spec_v1',
        'mode': 'live', 'profiles': ['openai_gpt_6_sol'],
    }))
    return path


def terminal(mode, path, cancel=False, cancel_live=False):
    pid, descriptor = pty.fork()
    if pid == 0:
        os.execvpe('bash', ['bash', '-x', str(launcher), mode, str(path)], environment)
    output = bytearray()
    sent = False
    interrupted = False
    deadline = time.monotonic() + 15
    try:
        while time.monotonic() < deadline:
            if cancel_live and sent and not interrupted and (path / 'claim.marker').exists():
                os.write(descriptor, b'\x03')
                interrupted = True
            ready, _, _ = select.select([descriptor], [], [], 0.2)
            if not ready:
                continue
            try:
                chunk = os.read(descriptor, 8192)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            output.extend(chunk)
            if b'Paste Naturebook OpenAI key (hidden; not saved): ' in output and not sent:
                os.write(descriptor, b'\x03' if cancel else key.encode() + b'\n')
                sent = True
        else:
            os.kill(pid, 9)
            raise AssertionError('launcher timeout')
    finally:
        os.close(descriptor)
    _, status = os.waitpid(pid, 0)
    assert key.encode() not in output, 'credential was echoed or logged'
    assert b'synthetic-unrelated-value' not in output
    assert b'synthetic-upstream-private-output' not in output
    return os.waitstatus_to_exitcode(status), sent

p = packet('fingerprint')
assert terminal('--credential-fingerprint', p) == (0, True)
record = p / 'openai-credential-fingerprint.json'
assert stat.S_IMODE(record.stat().st_mode) == 0o600
assert json.loads(record.read_text()) == {
    'version': 'openai_evaluation_credential_fingerprint_v1',
    'credentialSha256': hashlib.sha256(key.encode()).hexdigest(),
}
assert key not in record.read_text()
assert terminal('--credential-fingerprint', p) == (1, False), 'must not overwrite a prior fingerprint'
assert not (p / 'calls.jsonl').exists(), 'fingerprinting must never dispatch'

p = packet('live')
assert terminal('--live', p) == (0, True)
assert [json.loads(line)['mode'] for line in (p / 'calls.jsonl').read_text().splitlines()] == ['preflight', '--live']
assert not (p / 'openai-credential-fingerprint.json').exists()

p = packet('runtime-permissions')
(p / 'check-permissions').touch()
assert terminal('--live', p) == (0, True), 'actual launcher grants must satisfy the real Deno admission gate'
assert [json.loads(line)['mode'] for line in (p / 'calls.jsonl').read_text().splitlines()] == ['preflight', '--live']

p = packet('failed-preflight')
(p / 'fail-preflight').touch()
assert terminal('--live', p) == (1, False), 'preflight must finish before key entry'
assert len((p / 'calls.jsonl').read_text().splitlines()) == 1

p = packet('failed-live')
(p / 'fail-live').touch()
assert terminal('--live', p) == (1, True), 'failed live run must not look successful'

p = packet('cancelled-live')
(p / 'pause-live').touch()
assert terminal('--live', p, cancel_live=True) == (1, True)
assert (p / 'claim.marker').read_text() == 'started', 'interruption must preserve the durable claim'
assert [json.loads(line)['mode'] for line in (p / 'calls.jsonl').read_text().splitlines()] == ['preflight', '--live'], 'interruption must not retry'

p = packet('gemini')
(p / 'spec.json').write_text(json.dumps({'version': 'identification_provider_run_spec_v1', 'mode': 'live', 'profiles': ['gemini_pro']}))
assert terminal('--live', p) == (1, False)
assert not (p / 'calls.jsonl').exists()

p = packet('public-directory')
p.chmod(0o755)
assert terminal('--credential-fingerprint', p) == (1, False)
p.chmod(0o700)
link = root / 'linked-directory'
link.symlink_to(p, target_is_directory=True)
assert terminal('--credential-fingerprint', link) == (1, False)
assert terminal('--credential-fingerprint', root / 'x,--allow-env') == (1, False)
assert terminal('--credential-fingerprint', repository) == (1, False)
assert terminal('--unknown', p) == (1, False)

p = packet('cancelled')
assert terminal('--credential-fingerprint', p, cancel=True) == (1, True)
assert not (p / 'openai-credential-fingerprint.json').exists()
no_tty = subprocess.run(['bash', str(launcher), '--credential-fingerprint', str(p)],
                        env=environment, stdin=subprocess.DEVNULL, capture_output=True,
                        start_new_session=True, timeout=15)
assert no_tty.returncode == 1
assert key.encode() not in no_tty.stdout + no_tty.stderr
assert not (p / 'openai-credential-fingerprint.json').exists()
print('OpenAI local launcher: hidden terminal input, private fingerprint, real Deno admission, scoped child, and failure paths passed; zero API calls.')
PYTHON
