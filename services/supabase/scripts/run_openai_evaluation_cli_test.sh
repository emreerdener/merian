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
entry_index = sys.argv.index('services/supabase/scripts/evaluate_identification.ts')
mode = sys.argv[entry_index + 1]
packet = pathlib.Path(sys.argv[entry_index + 2])
assert mode in ('preflight', '--live', 'experiment-preflight', '--experiment-live', 'preflight-free-pro-photo', '--photo-model-live', 'preflight-free-pro-photo-continuation', '--photo-model-continuation-live')
assert '--cached-only' in sys.argv
reviewed = mode in ('preflight-free-pro-photo', '--photo-model-live', 'preflight-free-pro-photo-continuation', '--photo-model-continuation-live') or mode in ('experiment-preflight', '--experiment-live') and json.loads((packet / 'experiment.json').read_text()).get('version') in ('identification_experiment_plan_v2', 'identification_experiment_plan_v3', 'identification_experiment_plan_v4')
assert all(name not in os.environ for name in ('SUPABASE_SERVICE_ROLE_KEY', 'GITHUB_TOKEN', 'OPENAI_API_KEY', 'GIT_CONFIG_COUNT', 'GEMINI_PAID_API_KEY'))
assert 'synthetic-local-launcher-value' not in ' '.join(sys.argv)
if mode in ('preflight', 'experiment-preflight', 'preflight-free-pro-photo', 'preflight-free-pro-photo-continuation'):
    assert 'OPENAI_EVALUATION_API_KEY' not in os.environ
    assert '--deny-net' in sys.argv and '--deny-env' in sys.argv
else:
    assert os.environ.get('OPENAI_EVALUATION_API_KEY') == 'synthetic-local-launcher-value'
    assert ('--allow-net=api.openai.com:443,127.0.0.1' if reviewed else '--allow-net=api.openai.com:443') in sys.argv
    assert '--allow-env=OPENAI_EVALUATION_API_KEY' in sys.argv
    assert ('--allow-run=git,/usr/bin/open' if reviewed else '--allow-run=git') in sys.argv
with (packet / 'calls.jsonl').open('a') as output:
    output.write(json.dumps({'mode': mode, 'runId': sys.argv[entry_index + 3] if mode == '--experiment-live' else None}) + '\n')
if mode in ('--live', '--experiment-live', '--photo-model-live', '--photo-model-continuation-live') and (packet / 'check-permissions').exists():
    flags = sys.argv[1:entry_index]
    # Use the actual launcher flags and actual permission gate; never invoke a provider.
    code = """
import { liveCredential } from "./services/supabase/scripts/identification_evaluation/admission.ts";
globalThis.fetch = () => { throw new Error("network_forbidden_in_permission_probe"); };
if (await liveCredential("openai") !== "synthetic-local-launcher-value") Deno.exit(1);
"""
    if reviewed:
        code += """
if ((await Deno.permissions.query({name: "net", host: "127.0.0.1"})).state !== "granted") Deno.exit(1);
if ((await Deno.permissions.query({name: "run", command: "/usr/bin/open"})).state !== "granted") Deno.exit(1);
"""
    import subprocess
    check = subprocess.run([__REAL_DENO__, *flags, '-'], input=code, text=True,
                           env=os.environ, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if check.returncode:
        sys.exit(check.returncode)
if mode in ('--live', '--experiment-live', '--photo-model-live', '--photo-model-continuation-live') and (packet / 'pause-live').exists():
    (packet / 'claim.marker').write_text('started')
    print(os.environ['OPENAI_EVALUATION_API_KEY'], flush=True)
    signal.pause()
if (packet / ('fail-' + mode.lstrip('-'))).exists():
    print(os.environ.get('OPENAI_EVALUATION_API_KEY', 'synthetic-upstream-private-output'))
    sys.exit(1)
if mode in ('preflight-free-pro-photo', 'preflight-free-pro-photo-continuation'):
    continuation = mode.endswith('-continuation')
    (packet / ('photo-model-continuation-preflight.json' if continuation else 'photo-model-preflight.json')).write_text(json.dumps({
        'version':'photo_model_continuation_preflight_v1' if continuation else 'photo_model_preflight_v1',
        'budgetFitsRegionalReservation': not (packet / 'insufficient-budget').exists(),
        'evidenceStatus':'provisional_reference_pilot','source':{'dirty':False},
        'inheritedCalls': 2 if (packet / 'bad-inherited-count').exists() else 1,
        'maxAdditionalCalls':17,'screeningPolicy':'reference_gaps_recorded_v1'}))
if mode in ('--photo-model-live', '--photo-model-continuation-live') and not (packet / 'missing-state').exists():
    continuation = mode == '--photo-model-continuation-live'
    directory = packet / ('photo-model-continuation' if continuation else 'photo-model-run')
    directory.mkdir(exist_ok=True)
    (directory / 'state.json').write_text(json.dumps({'version':'photo_model_state_v2' if continuation else 'photo_model_state_v1',
        'claimedCalls':18,'completedCalls':18,'inheritedCalls':1,
        'newlyClaimedCalls': 16 if (packet / 'bad-combined-count').exists() else 17,
        'screeningPolicy':'reference_gaps_recorded_v1','productionActivationAuthorized':False,
        'complete': not (packet / 'stop-after-run').exists(), 'stop': 'screen_failed' if (packet / 'stop-after-run').exists() else None}))
if mode == '--experiment-live':
    run_id = sys.argv[entry_index + 3]
    state_path = packet / 'experiment' / 'state.json'
    if not (packet / 'missing-state').exists():
        state_path.parent.mkdir(exist_ok=True)
        completed = json.loads(state_path.read_text())['completedRunIds'] if state_path.exists() else []
        state_path.write_text(json.dumps({'version': 'identification_experiment_state_v1',
            'stop': 'explanation_review_unassessable' if (packet / 'stop-after-run').exists() else None,
            'completedRunIds': completed + [run_id]}))
    if (packet / 'change-plan').exists():
        (packet / 'experiment.json').write_text('{}')
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


def terminal(mode, path, cancel=False, cancel_live=False, run_id=None):
    pid, descriptor = pty.fork()
    if pid == 0:
        os.execvpe('bash', ['bash', '-x', str(launcher), mode, str(path)] + ([run_id] if run_id is not None else []), environment)
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
    assert output.count(b'Paste Naturebook OpenAI key (hidden; not saved): ') <= 1, 'session prompted more than once'
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

def photo_packet(name):
    p = packet(name)
    (p / 'photo-model-plan.json').write_text(json.dumps({'version':'photo_model_plan_v2','maxCalls':18,'attemptsPerAssignment':1}))
    return p

p = photo_packet('photo-models')
(p / 'check-permissions').touch()
assert terminal('--photo-model-live', p) == (0, True)
assert [json.loads(line)['mode'] for line in (p / 'calls.jsonl').read_text().splitlines()] == ['preflight-free-pro-photo', '--photo-model-live']
for marker in ('stop-after-run','missing-state'):
    p = photo_packet('photo-models-' + marker)
    (p / marker).touch()
    assert terminal('--photo-model-live', p) == (1, True), 'a stopped comparison is never reported as complete'
p = photo_packet('photo-models-insufficient-budget')
(p / 'insufficient-budget').touch()
assert terminal('--photo-model-live', p) == (1, False), 'budget preflight must stop before prompting for a key'
p = photo_packet('photo-models-old-plan')
(p / 'photo-model-plan.json').write_text(json.dumps({'version':'photo_model_plan_v1','maxCalls':18,'attemptsPerAssignment':1}))
assert terminal('--photo-model-live', p) == (1, False), 'the original $5 proposal does not authorize an expanded run'

p = photo_packet('photo-continuation')
(p / 'check-permissions').touch()
assert terminal('--photo-model-continuation-live', p) == (0, True)
assert [json.loads(line)['mode'] for line in (p / 'calls.jsonl').read_text().splitlines()] == ['preflight-free-pro-photo-continuation', '--photo-model-continuation-live']
for marker in ('stop-after-run', 'missing-state', 'bad-combined-count'):
    p = photo_packet('photo-continuation-' + marker)
    (p / marker).touch()
    assert terminal('--photo-model-continuation-live', p) == (1, True)
for marker in ('insufficient-budget', 'bad-inherited-count', 'fail-preflight-free-pro-photo-continuation'):
    p = photo_packet('photo-continuation-' + marker)
    (p / marker).touch()
    assert terminal('--photo-model-continuation-live', p) == (1, False)

p = packet('controlled-experiment')
(p / 'experiment.json').write_text(json.dumps({'version': 'identification_experiment_plan_v1', 'mode': 'live',
    'runs': [{'runId': 'openai-baseline', 'profileId': 'openai_photo_text_v1'}, {'runId': 'gemini-baseline', 'profileId': 'gemini_photo_text_v1'}]}))
(p / 'check-permissions').touch()
assert terminal('--experiment-live', p, run_id='openai-baseline') == (0, True)
assert [json.loads(line)['mode'] for line in (p / 'calls.jsonl').read_text().splitlines()] == ['experiment-preflight', '--experiment-live']
assert terminal('--experiment-live', p, run_id='gemini-baseline') == (1, False)
assert terminal('--experiment-live', p, run_id='missing') == (1, False)
assert terminal('--experiment-live', p, run_id='../escape') == (1, False)
assert terminal('--experiment-live', p) == (1, False)

p = packet('reviewed-candidate')
(p / 'experiment.json').write_text(json.dumps({'version': 'identification_experiment_plan_v2', 'mode': 'live',
    'runs': [{'runId': 'uncached-control', 'profileId': 'openai_photo_text_uncached_v1'}, {'runId': 'concise-candidate', 'profileId': 'openai_photo_text_concise_uncached_v1'}]}))
(p / 'check-permissions').touch()
assert terminal('--experiment-live', p, run_id='uncached-control') == (0, True)
assert terminal('--experiment-live', p, run_id='concise-candidate') == (0, True)

p = packet('assistant-reviewed-candidate')
(p / 'experiment.json').write_text(json.dumps({'version': 'identification_experiment_plan_v3', 'mode': 'live',
    'runs': [{'runId': 'uncached-control', 'profileId': 'openai_photo_text_uncached_v1'},
             {'runId': 'concise-candidate', 'profileId': 'openai_photo_text_concise_uncached_v1'}]}))
(p / 'check-permissions').touch()
assert terminal('--experiment-live', p, run_id='uncached-control') == (0, True)
assert terminal('--experiment-live', p, run_id='concise-candidate') == (0, True)

p = packet('null-fields-reviewed-session')
(p / 'experiment.json').write_text(json.dumps({'version': 'identification_experiment_plan_v4', 'mode': 'live',
    'runs': [{'runId': 'unchanged-baseline', 'profileId': 'openai_photo_text_v1'},
             {'runId': 'null-fields-candidate', 'profileId': 'openai_photo_null_fields_v1'}]}))
(p / 'check-permissions').touch()
assert terminal('--experiment-session', p) == (0, True)
assert [json.loads(line)['runId'] for line in (p / 'calls.jsonl').read_text().splitlines()] == [None, 'unchanged-baseline', 'null-fields-candidate']
for version in ('identification_experiment_plan_v1', 'identification_experiment_plan_v2', 'identification_experiment_plan_v3'):
    p = packet('null-fields-invalid-' + version[-2:])
    (p / 'experiment.json').write_text(json.dumps({'version': version, 'mode': 'live',
        'runs': [{'runId': 'null-fields-candidate', 'profileId': 'openai_photo_null_fields_v1'}]}))
    assert terminal('--experiment-live', p, run_id='null-fields-candidate') == (1, False)
    assert not (p / 'calls.jsonl').exists()
p = packet('null-fields-reject-concise')
(p / 'experiment.json').write_text(json.dumps({'version': 'identification_experiment_plan_v4', 'mode': 'live',
    'runs': [{'runId': 'concise-candidate', 'profileId': 'openai_photo_text_concise_uncached_v1'}]}))
assert terminal('--experiment-live', p, run_id='concise-candidate') == (1, False)

def session_packet(name):
    path = packet(name)
    (path / 'experiment.json').write_text(json.dumps({'version': 'identification_experiment_plan_v3', 'mode': 'live',
        'runs': [{'runId': 'uncached-control', 'profileId': 'openai_photo_text_uncached_v1'},
                 {'runId': 'concise-candidate', 'profileId': 'openai_photo_text_concise_uncached_v1'}]}))
    return path

p = session_packet('single-key-session')
(p / 'check-permissions').touch()
assert terminal('--experiment-session', p) == (0, True)
calls = [json.loads(line) for line in (p / 'calls.jsonl').read_text().splitlines()]
assert calls == [{'mode': 'experiment-preflight', 'runId': None},
                 {'mode': '--experiment-live', 'runId': 'uncached-control'},
                 {'mode': '--experiment-live', 'runId': 'concise-candidate'}]
assert all(key not in f.read_text() for f in p.rglob('*') if f.is_file()), 'session saved its key'

for marker in ('stop-after-run', 'missing-state', 'change-plan', 'fail-experiment-live'):
    p = session_packet('session-' + marker)
    (p / marker).touch()
    assert terminal('--experiment-session', p) == (1, True)
    calls = [json.loads(line) for line in (p / 'calls.jsonl').read_text().splitlines()]
    assert len(calls) == 2 and calls[-1]['runId'] == 'uncached-control', 'session continued after a stop'

p = session_packet('session-preflight-failure')
(p / 'fail-experiment-preflight').touch()
assert terminal('--experiment-session', p) == (1, False)

p = session_packet('session-interruption')
(p / 'pause-live').touch()
assert terminal('--experiment-session', p, cancel_live=True) == (1, True)
assert (p / 'claim.marker').read_text() == 'started'
assert len((p / 'calls.jsonl').read_text().splitlines()) == 2, 'session retried after interruption'

for invalid in ('mixed-provider', 'duplicate-run', 'invalid-run'):
    p = session_packet('session-' + invalid)
    spec = json.loads((p / 'experiment.json').read_text())
    if invalid == 'mixed-provider':
        spec['runs'][1]['profileId'] = 'gemini_photo_text_v1'
    else:
        spec['runs'][1]['runId'] = 'uncached-control' if invalid == 'duplicate-run' else '../escape'
    (p / 'experiment.json').write_text(json.dumps(spec))
    assert terminal('--experiment-session', p) == (1, False)
    assert not (p / 'calls.jsonl').exists()
p = session_packet('session-extra-argument')
assert terminal('--experiment-session', p, run_id='uncached-control') == (1, False)

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
print('OpenAI local launcher: hidden terminal input, private fingerprint, real Deno admission, single-key ordered sessions, scoped child, and failure paths passed; zero API calls.')
PYTHON
