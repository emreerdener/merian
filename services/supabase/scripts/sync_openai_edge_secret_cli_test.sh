#!/usr/bin/env bash
set -euo pipefail

sync_test_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$sync_test_root"
sync_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-openai-secret-sync.XXXXXX")"
sync_test_dir="$(cd -- "$sync_test_dir" && pwd -P)"
trap 'rm -rf -- "$sync_test_dir"' EXIT

# No network implementation: only the exact local credential protocol is allowed.
cat > "$sync_test_dir/supabase" <<'FAKE'
#!/usr/bin/env python3
import hashlib, json, os, pathlib, sys
root = pathlib.Path(__file__).parent
name = 'NATUREBOOK_OPENAI_API_KEY'
args = sys.argv[1:]
assert args in [
    ['secrets', 'set', '--output-format', 'json', '--project-ref', 'qlarqavoqhkuwzmevrmf'],
    ['secrets', 'list', '--output', 'json', '--output-format', 'json', '--project-ref', 'qlarqavoqhkuwzmevrmf'],
]
assert os.environ.get('SHOULD_NOT_REACH_CHILD') is None
assert os.environ.get('GITHUB_TOKEN') is None
assert os.environ.get('SUPABASE_TELEMETRY_DISABLED') == '1'
assert os.environ.get('SUPABASE_ACCESS_TOKEN') == 'synthetic-management-token'
assert sys.stdin.read() == ''
assert [line.strip() for line in (pathlib.Path.cwd() / 'supabase/config.toml').read_text().splitlines()
        if line.strip() and not line.lstrip().startswith('#')] == [
    'project_id = "merian-openai-secret-sync"',
    '[edge_runtime.secrets]',
    name + ' = "env(NATUREBOOK_OPENAI_API_KEY)"',
]
mode = (root / 'mode').read_text().strip()
value_file = root / 'synthetic-remote-value'
with (root / 'calls').open('a') as calls:
    calls.write(args[1] + '\n')
if args[1] == 'set':
    key = os.environ[name]
    assert key == 'synthetic-provider-credential'
    value_file.write_text(key)
    # Prove suppression of provider/CLI output on successful and failed writes.
    print(key)
    print(os.environ['SUPABASE_ACCESS_TOKEN'], file=sys.stderr)
    sys.exit(1 if mode == 'set_failure' else 0)
assert name not in os.environ
key = value_file.read_text()
if mode == 'list_failure':
    print(key)
    print(os.environ['SUPABASE_ACCESS_TOKEN'], file=sys.stderr)
    sys.exit(1)
if mode == 'invalid_json':
    print(key)
    sys.exit(0)
if mode == 'oversized_output':
    print('x' * 1_048_577)
    sys.exit(0)
digest = hashlib.sha256(key.encode()).hexdigest().upper()
rows = [{'name': name, 'value': digest}]
if mode == 'mismatch':
    rows[0]['value'] = 'a' * 64
elif mode == 'missing':
    rows = []
elif mode == 'duplicate':
    rows = rows * 2
elif mode == 'malformed_digest':
    rows[0]['value'] = key
print(json.dumps(rows))
FAKE
chmod 700 "$sync_test_dir/supabase"

export PATH="$sync_test_dir:$PATH"
export SHOULD_NOT_REACH_CHILD=synthetic-other-credential
export GITHUB_TOKEN=synthetic-github-token
export SUPABASE_ACCESS_TOKEN=synthetic-management-token
export NATUREBOOK_OPENAI_API_KEY=synthetic-provider-credential
printf 'success\n' > "$sync_test_dir/mode"

run_sync() {
  local sync_case="$1"
  shift
  deno run --quiet --frozen --no-prompt --deny-net \
    --config services/supabase/functions/deno.json \
    --allow-env=PATH,SUPABASE_ACCESS_TOKEN,NATUREBOOK_OPENAI_API_KEY \
    --allow-run=supabase \
    services/supabase/scripts/sync_openai_edge_secret.ts "$@" \
    > "$sync_test_dir/$sync_case.log" 2>&1
}
expect_failure() {
  if run_sync "$@"; then
    echo "Synthetic OpenAI secret synchronization unexpectedly succeeded." >&2
    exit 1
  fi
}

# Validation, invalid input and wrong-target rejection cannot reach the CLI.
run_sync validated --project-ref qlarqavoqhkuwzmevrmf --validate-only
expect_failure wrong_target --project-ref aaaaaaaaaaaaaaaaaaaa
expect_failure unknown_argument --project-ref qlarqavoqhkuwzmevrmf --unknown
NATUREBOOK_OPENAI_API_KEY=$'synthetic\ncredential' \
  expect_failure malformed --project-ref qlarqavoqhkuwzmevrmf --validate-only
SUPABASE_ACCESS_TOKEN='' expect_failure missing_token --project-ref qlarqavoqhkuwzmevrmf
NATUREBOOK_OPENAI_API_KEY='' run_sync absent --project-ref qlarqavoqhkuwzmevrmf
test ! -e "$sync_test_dir/calls"

run_sync synchronized --project-ref qlarqavoqhkuwzmevrmf
# Removing the GitHub value must neither delete nor overwrite the runtime copy.
NATUREBOOK_OPENAI_API_KEY='' run_sync absent_after_sync --project-ref qlarqavoqhkuwzmevrmf

for sync_mode in set_failure list_failure invalid_json oversized_output mismatch missing duplicate malformed_digest; do
  printf '%s\n' "$sync_mode" > "$sync_test_dir/mode"
  expect_failure "$sync_mode" --project-ref qlarqavoqhkuwzmevrmf
done

python3 - "$sync_test_dir" <<'CHECK'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
expected = {
    'validated': 'OpenAI deployment credential format validated.',
    'absent': 'OpenAI runtime secret skipped: no GitHub credential configured.',
    'absent_after_sync': 'OpenAI runtime secret skipped: no GitHub credential configured.',
    'synchronized': 'OpenAI runtime secret digest verified.',
}
failures = {
    'wrong_target': 'invalid_target_or_arguments',
    'unknown_argument': 'invalid_target_or_arguments',
    'malformed': 'invalid_credential_format',
    'missing_token': 'missing_supabase_access_token',
    'set_failure': 'set_failed',
    'list_failure': 'list_failed',
    'oversized_output': 'list_output_limit',
    **{case: 'digest_verification_failed' for case in [
        'invalid_json', 'mismatch', 'missing', 'duplicate', 'malformed_digest'
    ]},
}
expected.update({case: f'OpenAI runtime secret synchronization failed: {reason}.' for case, reason in failures.items()})
for case, output in expected.items():
    assert (root / (case + '.log')).read_text().strip() == output, case
assert (root / 'synthetic-remote-value').read_text() == 'synthetic-provider-credential'
assert (root / 'calls').read_text().splitlines() == ['set', 'list', 'set'] + ['set', 'list'] * 7
print('OpenAI secret synchronization: 16 local cases passed; zero network requests.')
CHECK
