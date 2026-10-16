"""Run closed synthetic handoff suites on exclusively owned fresh local databases.

No resume/retry/reset, hosted endpoint, caller-selected database, or arbitrary
command mode exists. A failure leaves the fixed ownership receipt in place and
blocks subsequent runs pending original-outcome reconciliation by the owner.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / 'services/supabase/scripts'
STATE = ROOT / '.artifacts/initial-media-handoff-v2/runtime-implementation/committed-disposable-state.json'
GIB = 1024 ** 3
SUITES = {name: ('test_initial_media_handoff_' + name + '.py', ()) for name in (
    'state', 'owners', 'contention', 'expiry', 'recovery_contention',
    'account_contention', 'public_deletion', 'cleanup_contention',
    'callback_contention', 'pruning', 'io_readers', 'bridge', 'coordinator',
    'transferred_recovery_c1', 'completion')}
SUITES.update({
    'scan_delete': ('test_initial_media_handoff_scan_contention.py', ('--root', 'delete')),
    'scan_detach': ('test_initial_media_handoff_scan_contention.py', ('--root', 'detach')),
    'resource_photo_audio': ('test_initial_media_handoff_resources.py', ('--shape', 'photo_audio')),
    'resource_photo_images': ('test_initial_media_handoff_resources.py', ('--shape', 'photo_audio_images')),
    'resource_video_audio': ('test_initial_media_handoff_resources.py', ('--shape', 'video_audio')),
    'merge_funding': ('test_initial_merge_target_funding.py', ()),
    'legacy_quota': ('test_initial_media_handoff_legacy_quota.py', ()),
})
# These nonterminal fixtures intentionally retain exact synthetic roots. This
# check is not a per-row erasure claim; every other suite must have zero roots.
EXPECTED_RESIDUALS = {name: (0, 0) for name in SUITES}
EXPECTED_RESIDUALS.update(state=(1, 1), pruning=(1, 1), expiry=(1, 0), public_deletion=(1, 0))


class Stopped(Exception):
    """Only fixed diagnostic categories may reach persisted or console output."""


def require(value, category):
    if not value:
        raise Stopped(category)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def temporary_root(platform):
    require(platform in ('darwin', 'linux'), 'unsupported_platform')
    return Path('/private/tmp' if platform == 'darwin' else '/tmp')


def pinned_environment(ambient, context):
    host = context[0]['Endpoints']['docker']['Host']
    require(isinstance(host, str) and re.fullmatch(r'unix:///[A-Za-z0-9_./-]+', host), 'nonlocal_docker')
    require(not ambient.get('DOCKER_HOST') or ambient['DOCKER_HOST'] == host, 'docker_host_mismatch')
    require(not ambient.get('DOCKER_CONTEXT') or ambient['DOCKER_CONTEXT'] == context[0]['Name'], 'docker_context_mismatch')
    require(not any(ambient.get(k) for k in ('DOCKER_TLS', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH')), 'docker_tls_override')
    env = dict(ambient)
    for key in ('DOCKER_CONTEXT', 'DOCKER_TLS', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH'):
        env.pop(key, None)
    env.update(DOCKER_HOST=host, SUPABASE_TELEMETRY_DISABLED='1',
               SUPABASE_AUTH_EXTERNAL_APPLE_SECRET='ci-schema-validation-placeholder',
               PYTHONDONTWRITEBYTECODE='1')
    return host, env


def save(path, value):
    # Only the exclusive receipt owner calls this; replace is atomic for readers.
    staging = path.with_name(path.name + '.tmp')
    with os.fdopen(os.open(staging, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    staging.replace(path)


def ownership_projection(record):
    """Allowlisted metadata only, including when reading STATE after interruption."""
    allowed_states = ('reserving', 'starting', 'ready', 'disposing', 'stopped', 'disposal_failed', 'disposed')
    require(isinstance(record, dict), 'ownership_identity_invalid')
    require(record.get('state') in allowed_states, 'ownership_state_invalid')
    common = {'suite', 'docker_host', 'runner_sources'}
    identity = {'project', 'container', 'workdir'} if record['state'] != 'reserving' else set()
    require(common | identity <= record.keys(), 'ownership_identity_invalid')
    require(isinstance(record['runner_sources'], dict) and set(record['runner_sources']) == set(source_manifest()), 'ownership_identity_invalid')
    output = {'state': record['state']}
    if 'suite' in record:
        require(record['suite'] in SUITES, 'ownership_suite_invalid')
        output['suite'] = record['suite']
    if 'docker_host' in record:
        require(isinstance(record['docker_host'], str) and re.fullmatch(r'unix:///[A-Za-z0-9_./-]+', record['docker_host']), 'ownership_endpoint_invalid')
        output['docker_host'] = record['docker_host']
    if 'project' in record:
        project = record['project']
        require(isinstance(project, str) and re.fullmatch(r'merian-handoff-runtime-[a-z0-9_]{8}', project), 'ownership_project_invalid')
        require(record.get('container') == 'supabase_db_' + project
                and record.get('workdir') == str(temporary_root(sys.platform) / project), 'ownership_identity_invalid')
        output.update({key: record[key] for key in ('project', 'container', 'workdir')})
    for key in ('start_exit', 'stop_exit', 'disk_after_bytes'):
        if key in record:
            require(type(record[key]) is int and record[key] >= -255, 'ownership_number_invalid')
            output[key] = record[key]
    known_sources = set(source_manifest())
    known_migrations = {p.name for p in (ROOT / 'services/supabase/migrations').glob('*.sql')}
    for key, allowed in [('runner_sources', known_sources), ('migration_hashes', known_migrations)]:
        if key in record:
            values = record[key]
            require(isinstance(values, dict) and set(values) <= allowed and all(
                isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) for value in values.values()), 'ownership_hashes_invalid')
            output[key] = values
    if 'temporary_config_sha256' in record:
        value = record['temporary_config_sha256']
        require(isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value), 'ownership_config_invalid')
        output['temporary_config_sha256'] = value
    if 'reported_migrations' in record:
        values = record['reported_migrations']
        require(isinstance(values, list) and all(isinstance(value, str) and value in known_migrations for value in values), 'ownership_migrations_invalid')
        output['reported_migrations'] = values
    if 'before_disposal' in record:
        before = record['before_disposal']
        counts = ('invocations', 'private_receipts', 'preparation_intents')
        require(isinstance(before, dict) and type(before.get('activation_enabled')) is bool
                and all(type(before.get(k)) is int and before[k] >= 0 for k in counts), 'ownership_counts_invalid')
        output['before_disposal'] = {key: before[key] for key in ('activation_enabled', *counts)}
    if 'expected_residuals' in record:
        require(record['expected_residuals'] == list(EXPECTED_RESIDUALS[record['suite']]), 'ownership_residuals_invalid')
        output['expected_residuals'] = record['expected_residuals']
    return output


def checkpoint(record, directory):
    save(STATE, record)
    save(directory / 'ownership.json', ownership_projection(record))


def reserve_state(record, directory):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    with os.fdopen(os.open(STATE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as stream:
        json.dump(record, stream, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    save(directory / 'ownership.json', ownership_projection(record))


def snapshot_ownership(directory):
    """Read-only recovery of metadata; never provisions, queries or disposes."""
    directory.mkdir(parents=True, exist_ok=True)
    if not STATE.exists():
        result = {'state': 'absent', 'scope': 'No current ownership receipt; inspect per-suite mirrors and results.'}
    else:
        require(not STATE.is_symlink() and STATE.stat().st_size <= 131072, 'ownership_file_invalid')
        result = ownership_projection(json.loads(STATE.read_text()))
    save(directory / 'ownership-at-end.json', result)


def run(args, env, category, input=None):
    result = subprocess.run(args, input=input, env=env, cwd=ROOT, text=True, capture_output=True)
    require(result.returncode == 0, category)
    return result.stdout


def inspect_owned(record, env):
    rows = json.loads(run(['docker', '--host', record['docker_host'], 'container', 'inspect', record['container']], env, 'inspect_failed'))
    require(len(rows) == 1 and rows[0]['Name'] == '/' + record['container']
            and rows[0]['State']['Running'] is True
            and rows[0]['Config']['Labels'].get('com.supabase.cli.project') == record['project'], 'ownership_mismatch')


def sql(record, env, query):
    return run(['docker', '--host', record['docker_host'], 'exec', '-i', record['container'],
                'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'],
               env, 'original_state_query_failed', input=query)


def source_manifest():
    files = [Path(__file__), SCRIPTS / 'initial_media_handoff_bridge.ts',
             ROOT / 'services/supabase/config.toml', SCRIPTS / 'require_supabase_cli_version.sh']
    files.extend(SCRIPTS / name for name, _ in SUITES.values())
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(set(files))}


def provision(record, env, directory):
    require(shutil.disk_usage(ROOT).free >= 24 * GIB, 'start_disk_floor')
    # One fixed namespace; refuse competing users, never cancel them or choose a
    # different database to work around existing ownership.
    probes = []
    try:
        for port in range(57630, 57640):
            probe = socket.socket()
            probes.append(probe)
            probe.bind(('127.0.0.1', port))
        work = Path(tempfile.mkdtemp(prefix='merian-handoff-runtime-', dir=temporary_root(sys.platform)))
        require(re.fullmatch(r'merian-handoff-runtime-[a-z0-9_]{8}', work.name), 'project_name')
        record.update(project=work.name, container='supabase_db_' + work.name,
                      workdir=str(work), state='starting')
        checkpoint(record, directory)
        existing = subprocess.run(['docker', '--host', record['docker_host'], 'container', 'inspect', record['container']],
                                  env=env, capture_output=True)
        require(existing.returncode != 0, 'container_already_exists')
        migrations = work / 'supabase/migrations'
        migrations.mkdir(parents=True)
        config = (ROOT / 'services/supabase/config.toml').read_text()
        require(len(re.findall(r'^project_id = ', config, re.M)) == 1, 'config_project_ambiguous')
        config = re.sub(r'^project_id = .*$', 'project_id = "' + work.name + '"', config, count=1, flags=re.M)
        config = re.sub(r'\b5432([0-9])\b', r'5763\1', config)
        (work / 'supabase/config.toml').write_text(config)
        record['temporary_config_sha256'] = digest(work / 'supabase/config.toml')
        record['migration_hashes'] = {}
        for source in sorted((ROOT / 'services/supabase/migrations').glob('*.sql')):
            target = migrations / source.name
            target.write_bytes(source.read_bytes())
            require(digest(target) == digest(source), 'migration_copy_mismatch')
            record['migration_hashes'][source.name] = digest(target)
        require(record['migration_hashes'], 'no_migrations')
        checkpoint(record, directory)
    finally:
        for probe in probes:
            probe.close()
    result = subprocess.run(['supabase', '--workdir', str(work), 'db', 'start'], env=env, cwd=ROOT, capture_output=True, text=True)
    # Never retain raw CLI output: startup may print credentials. Only known
    # migration filenames and the exit status become evidence.
    record['start_exit'] = result.returncode
    record['reported_migrations'] = [name for name in re.findall(r'^Applying migration ([A-Za-z0-9_.-]+)\.\.\.', result.stdout + result.stderr, re.M)
                                     if name in record['migration_hashes']]
    checkpoint(record, directory)
    require(result.returncode == 0, 'fresh_replay_failed')
    inspect_owned(record, env)
    versions = sql(record, env, 'SELECT version FROM supabase_migrations.schema_migrations ORDER BY version;').splitlines()
    require(versions == [n.split('_', 1)[0] for n in record['migration_hashes']], 'migration_versions_mismatch')
    fresh = sql(record, env, 'SELECT NOT initial_analysis_lifecycle_enabled '
                'AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations) '
                'AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) '
                'AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents) '
                'AND NOT EXISTS(SELECT 1 FROM public.users) FROM internal.initial_analysis_rollout WHERE singleton;')
    require(fresh.strip() == 't', 'fresh_inactive_required')
    require(shutil.disk_usage(ROOT).free >= 20 * GIB, 'disk_floor')
    require(source_manifest() == record['runner_sources'], 'runner_source_drift')
    record.update(state='ready', disk_after_bytes=shutil.disk_usage(ROOT).free)
    checkpoint(record, directory)
    (directory / 'replay.json').write_bytes(STATE.read_bytes())


def dispose(record, env, directory):
    inspect_owned(record, env)
    before = json.loads(sql(record, env, "SELECT json_build_object('activation_enabled',(SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout WHERE singleton),'invocations',(SELECT count(*) FROM internal.identification_invocations),'private_receipts',(SELECT count(*) FROM internal.initial_preparation_admission_receipts),'preparation_intents',(SELECT count(*) FROM internal.initial_analysis_preparation_intents));"))
    require(before['activation_enabled'] is False and before['invocations'] == 0, 'disposal_inactive_required')
    expected = EXPECTED_RESIDUALS[record['suite']]
    require((before['private_receipts'], before['preparation_intents']) == expected, 'unexpected_disposal_residuals')
    work = Path(record['workdir'])
    require(work.parent == temporary_root(sys.platform) and work.name == record['project'] and not work.is_symlink(), 'disposal_path')
    record.update(state='disposing', before_disposal=before, expected_residuals=list(expected))
    checkpoint(record, directory)
    stop = subprocess.run(['supabase', '--workdir', str(work), 'stop', '--no-backup'],
                          env=env, cwd=ROOT, text=True, capture_output=True)
    record.update(stop_exit=stop.returncode,
                  state='stopped' if stop.returncode == 0 else 'disposal_failed')
    checkpoint(record, directory)
    require(stop.returncode == 0, 'owned_stop_failed')
    remaining = [json.loads(line) for line in run(['docker', '--host', record['docker_host'], 'container', 'ls', '-a', '--format', '{{json .Names}}'], env, 'container_list_failed').splitlines()]
    require(record['container'] not in remaining, 'owned_container_remains')
    shutil.rmtree(work)
    receipt = dict(record, state='disposed', before_disposal=before, container_absent=True,
                   temporary_workdir_removed=True, disk_after_bytes=shutil.disk_usage(ROOT).free)
    save(directory / 'disposal.json', receipt)
    save(directory / 'ownership.json', ownership_projection(receipt))
    STATE.unlink()


def qualify(suite, directory, host, env):
    directory.mkdir()
    record = dict(state='reserving', suite=suite, docker_host=host, runner_sources=source_manifest())
    reserve_state(record, directory)  # Before creating a project or invoking the CLI.
    try:
        provision(record, env, directory)
        script, extra = SUITES[suite]
        result = subprocess.run([sys.executable, str(SCRIPTS / script), '--container', record['container'],
                    '--evidence-directory', str(directory), '--replay-manifest', str(STATE), *extra],
                    cwd=ROOT, env=env, text=True, capture_output=True)
        # Harness JSON contains only reviewed synthetic evidence. Filter stdout;
        # do not save stderr, tracebacks, row output, or arbitrary CLI messages.
        lines = re.findall(r'^(?:PASS|FAIL) [A-Za-z0-9_ -]{1,180}$', result.stdout, re.M)
        (directory / 'checks.log').write_text('\n'.join(lines) + '\n')
        require(result.returncode == 0, 'suite_failed')
        receipts = list(directory.glob('initial-*.json'))
        require(len(receipts) == 1, 'suite_receipt_count')
        receipt = json.loads(receipts[0].read_text())
        require(receipt.get('passed') is True and receipt['replay_manifest_sha256'] == digest(directory / 'replay.json'), 'suite_evidence_mismatch')
        require(all(digest(ROOT / name) == value for name, value in receipt['source_manifest'].items()), 'suite_source_drift')
        require(source_manifest() == record['runner_sources'], 'runner_source_drift')
        dispose(record, env, directory)
        save(directory / 'result.json', dict(passed=True, suite=suite, runner_sources=record['runner_sources'],
             evidence={p.name: digest(p) for p in directory.iterdir() if p.is_file()}))
        print('PASS ' + suite, flush=True)
    except BaseException as error:
        category = str(error) if isinstance(error, Stopped) else 'runner_interrupted_or_failed'
        save(directory / 'failure.json', dict(passed=False, suite=suite, category=category,
             phase=record['state'], runner_sources=record['runner_sources'],
             migration_hashes=record.get('migration_hashes', {}),
             original_ownership_retained=STATE.exists(), stop_exit=record.get('stop_exit'),
             action=('Disposal incomplete; inspect owned resources only. No qualification retry.'
                     if record['state'] in ('disposing', 'stopped', 'disposal_failed')
                     else 'Stop; original outcome reconciliation only. No retry.')))
        raise Stopped(category) from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--suite', choices=['all', *SUITES])
    mode.add_argument('--snapshot-ownership', action='store_true')
    parser.add_argument('--evidence-directory', type=Path)
    args = parser.parse_args()
    if args.snapshot_ownership:
        require(args.evidence_directory is not None, 'snapshot_directory_required')
        snapshot_ownership(args.evidence_directory.resolve())
        return
    require(not STATE.exists(), 'existing_ownership_requires_reconciliation')
    temporary_root(sys.platform)
    context = json.loads(run(['docker', 'context', 'inspect'], os.environ, 'docker_context_failed'))
    host, env = pinned_environment(os.environ, context)
    run(['bash', str(SCRIPTS / 'require_supabase_cli_version.sh')], env, 'cli_pin_failed')
    directory = (args.evidence_directory or STATE.parent / ('portable-' + uuid.uuid4().hex)).resolve()
    directory.mkdir(parents=True, exist_ok=False)
    for suite in SUITES if args.suite == 'all' else [args.suite]:
        qualify(suite, directory / suite, host, env)


if __name__ == '__main__':
    try:
        main()
    except (Stopped, OSError, ValueError, KeyError, IndexError):
        print('Handoff qualification stopped; retain ownership and sanitized evidence for reconciliation.', file=sys.stderr)
        sys.exit(1)
