#!/usr/bin/env bash
set -euo pipefail

comparison_test_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$comparison_test_root"
comparison_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-comparison-control.XXXXXX")"
comparison_test_dir="$(cd -- "$comparison_test_dir" && pwd -P)"
trap 'rm -rf -- "$comparison_test_dir"' EXIT

# This executable is a local fake. It has no network implementation and rejects
# every operation/target except the exact controller protocol under test.
cat > "$comparison_test_dir/supabase" <<'PY'
#!/usr/bin/env python3
import hashlib, json, os, pathlib, sys
root = pathlib.Path(__file__).parent
args = sys.argv[1:]
assert os.environ.get('SHOULD_NOT_REACH_CHILD') is None
assert os.environ.get('IDENTIFICATION_AUDIO_PROMPT_COMPARISON_V1') is None
assert os.environ.get('GITHUB_TOKEN') is None
assert os.environ.get('SUPABASE_TELEMETRY_DISABLED') == '1'
assert args[-2:] == ['--project-ref', 'qlarqavoqhkuwzmevrmf']
args = args[:-2]
assert args[-2:] == ['--output-format', 'json']
args = args[:-2]
stored = root / 'synthetic-remote-value'
name = 'IDENTIFICATION_AUDIO_PROMPT_COMPARISON_V1'
template = (pathlib.Path.cwd() / 'supabase/config.toml').read_text()
assert [line.strip() for line in template.splitlines() if line.strip() and not line.lstrip().startswith('#')] == [
    'project_id = "merian-audio-prompt-comparison-control"',
    '[edge_runtime.secrets]',
    name + ' = "env(MERIAN_AUDIO_PROMPT_COMPARISON_VALUE)"',
]
assert sys.stdin.read() == ''
config = os.environ.get('MERIAN_AUDIO_PROMPT_COMPARISON_VALUE')
if args != ['secrets', 'set']:
    assert config is None
if args == ['secrets', 'list', '--output', 'json']:
    rows = [] if not stored.exists() else [{'name': name, 'value': hashlib.sha256(stored.read_bytes()).hexdigest()}]
    print(json.dumps(rows))
elif args == ['secrets', 'set']:
    assert config is not None
    assert len(config.encode()) <= 1024
    json.loads(config)
    stored.write_text(config)
    stored.chmod(0o600)
    with (root / 'set-count').open('a') as f:
        f.write('set\n')
    if (root / 'fail-after-set').exists():
        # Exercise suppression of upstream output containing private data.
        print(json.dumps({'_tag':'Error','error':{'code':'LegacySecretsSetUnexpectedStatusError','message':config,'detail':config}}))
        print(config, file=sys.stderr)
        sys.exit(1)
elif args == ['secrets', 'unset', name, '--yes']:
    stored.unlink(missing_ok=True)
else:
    sys.exit(2)
PY
chmod 700 "$comparison_test_dir/supabase"

export PATH="$comparison_test_dir:$PATH"
export GITHUB_ACTIONS=true
export GITHUB_REPOSITORY=emreerdener/merian
export GITHUB_REF=refs/heads/main
export GITHUB_EVENT_NAME=workflow_dispatch
export GITHUB_WORKFLOW_REF=emreerdener/merian/.github/workflows/identification-audio-prompt-comparison.yml@refs/heads/main
export GITHUB_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export SUPABASE_ACCESS_TOKEN=synthetic-controller-test-value
export SHOULD_NOT_REACH_CHILD=synthetic-private-marker
export GITHUB_TOKEN=synthetic-other-credential

# Use a fixed time only in the isolated child under test so the retained
# historical plan can be regression-tested after its real eligibility window.
cat > "$comparison_test_dir/entry.ts" <<TS
import { runAudioPromptComparisonControl } from "file://$comparison_test_root/services/supabase/scripts/control_audio_prompt_comparison.ts";
Date.now = () => Date.parse("2026-09-24T18:00:00.000Z");
await runAudioPromptComparisonControl();
TS
export IDENTIFICATION_AUDIO_PROMPT_COMPARISON_V1="$(python3 - <<'PY'
import json,re,pathlib
base=pathlib.Path('services/supabase/functions/identify-multimodal')
plan=re.search(r'AUDIO_PROMPT_COMPARISON_PLAN_SHA256\s*=\s*"([a-f0-9]{64})"', (base/'comparison/promptPlan.ts').read_text()).group(1)
bundle=re.search(r'IDENTIFICATION_BUNDLE_SHA256\s*=\s*"([a-f0-9]{64})"', (base/'deploymentIdentity.ts').read_text()).group(1)
print(json.dumps(dict(version=1,block=1,ownerId='11111111-1111-4111-8111-111111111111',planSha256=plan,backendBundleSha256=bundle,startsAt='2026-09-24T18:00:00.000Z',expiresAt='2026-09-24T20:00:00.000Z'),indent=2))
PY
)"

run_control() {
  local comparison_operation="$1"
  local comparison_output="$2"
  deno run --frozen --no-prompt --deny-net \
    --config services/supabase/functions/deno.json \
    --allow-env=GITHUB_ACTIONS,GITHUB_REPOSITORY,GITHUB_REF,GITHUB_EVENT_NAME,GITHUB_WORKFLOW_REF,GITHUB_SHA,PATH,SUPABASE_ACCESS_TOKEN,IDENTIFICATION_AUDIO_PROMPT_COMPARISON_V1 \
    --allow-run=supabase --allow-write="$comparison_test_dir" \
    "$comparison_test_dir/entry.ts" \
    --operation "$comparison_operation" --deployed-sha bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
    --evidence "$comparison_test_dir/$comparison_output.json" \
    > "$comparison_test_dir/$comparison_output.log" 2>&1
}

run_control inspect before
run_control activate enabled
run_control activate unchanged
run_control deactivate disabled
touch "$comparison_test_dir/fail-after-set"
if run_control activate failed; then
  echo "The synthetic failed activation unexpectedly succeeded." >&2
  exit 1
fi
python3 - "$comparison_test_dir" <<'PY'
import json,pathlib,stat,sys
root=pathlib.Path(sys.argv[1])
for name,status in [('before','disabled'),('enabled','active'),('unchanged','already_active'),('disabled','disabled'),('failed','activation_failed')]:
    path=root/(name+'.json')
    record=json.loads(path.read_text())
    assert record['status']==status
    assert record['automaticIdentificationRequests']==0
    assert stat.S_IMODE(path.stat().st_mode)==0o600
    for retained in [path,root/(name+'.log')]:
        text=retained.read_text()
        assert '11111111-1111-4111-8111-111111111111' not in text
        assert 'synthetic-controller-test-value' not in text
        assert 'ownerId' not in text
assert json.loads((root/'failed.json').read_text())['cleanup']=='verified_absent'
assert json.loads((root/'failed.json').read_text())['failure']=={'stage':'set','kind':'remote_rejected'}
assert json.loads((root/'enabled.json').read_text())['failure'] is None
assert not (root/'synthetic-remote-value').exists()
assert (root/'set-count').read_text().splitlines()==['set','set']
print('Audio prompt comparison CLI lifecycle and private transport passed with a local fake; zero network requests.')
PY
