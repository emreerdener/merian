"""Local synthetic feasibility evidence, not a production artifact builder."""
import argparse
import base64
import hashlib
import contextlib
import fcntl
import json
import os
import pathlib
import platform
import re
import selectors
import shutil
import signal
import stat
import struct
import subprocess
import tarfile
import tempfile
import time
ROOT = pathlib.Path(__file__).resolve().parent
REPO = ROOT.parent.parent
BOOTSTRAP = 'scripts/initial-preparation/bootstrap.ts'
POLICY = 'local-preparation-darwin-arm64-v1'
DENO_HASH = '43c3a8b92c7a3755a2b9dfdb76235a90411604d469760ffffec044abd509afdc'
ARCHIVE_HASH = '542188de797cf0672e9751006917b44796353f140657de08601ec68df5027eb0'
PROVENANCE_HASH = '45e8f871377a4e9d1a9a128e96d86f40f7cede194fc03ee31eecb68d6b2b03f1'
ESBUILD_HASH = '58d144357454bca840167171380785b133b1e5e682d0c51afa8c80158bfd3f8a'
PREFIX = 'services/supabase/functions/'
LOCK = REPO / '.artifacts/initial-preparation-artifact/.harness.lock'
CLOSURE = [PREFIX + x for x in ['_shared/audioProcessing.ts', 'audio-spec/wav.ts', 'audio-spec/resample.ts', '_shared/encoding.ts', '_shared/mediaBudgets.ts', '_shared/http.ts']]

@contextlib.contextmanager
def execution_lock():
    """One local harness per checkout; never remove a live lock inode."""
    fd = os.open(LOCK, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
            raise ValueError('execution_lock')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('execution_busy') from None
        yield
    finally:
        os.close(fd)


def sha(b):
    return hashlib.sha256(b).hexdigest()

def read_regular(path, limit):
    """Bound reads and reject special files/links before allocating content."""
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), 'rb') as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise ValueError('input_file')
        data = source.read(limit + 1)
        if len(data) != info.st_size or len(data) > limit:
            raise ValueError('input_changed')
        return data

def select_version(version):
    registry = json.loads(read_regular(ROOT / 'registry.json', 65536))
    if not isinstance(registry, dict) or set(registry) != {'format_version', 'entries'} or type(registry['format_version']) is not int or registry['format_version'] != 1 or not isinstance(registry['entries'], list) or not 1 <= len(registry['entries']) <= 8:
        raise ValueError('registry_format')
    for candidate in registry['entries']:
        validate_entry(candidate)
    if len({entry['id'] for entry in registry['entries']}) != len(registry['entries']):
        raise ValueError('registry_duplicate')
    selected = [entry for entry in registry['entries'] if entry['id'] == version]
    if len(selected) != 1:
        raise ValueError('unknown_version')
    entry = selected[0]
    if entry['platform'] != 'darwin-arm64' or entry['build_policy'] != POLICY or entry['bootstrap_path'] != BOOTSTRAP or (entry['archive_sha256'] != ARCHIVE_HASH) or (entry['deno_sha256'] != DENO_HASH) or (entry['esbuild_sha256'] != ESBUILD_HASH):
        raise ValueError('unsupported_tuple')
    if not re.fullmatch('[0-9a-f]{40}', entry.get('bootstrap_commit') or ''):
        raise ValueError('bootstrap_revision')
    return entry

def validate_entry(entry):
    keys = {'id', 'platform', 'bootstrap_commit', 'bootstrap_path', 'bootstrap_blob_sha1', 'bootstrap_sha256', 'archive_sha256', 'archive_revision', 'configuration_digest', 'inputs', 'deno_sha256', 'esbuild_sha256', 'toolchain_provenance_sha256', 'build_policy', 'artifact_sha256', 'artifact_bytes'}
    if not isinstance(entry, dict) or set(entry) != keys:
        raise ValueError('registry_entry')
    for key in keys - {'inputs', 'artifact_sha256', 'artifact_bytes'}:
        if not isinstance(entry[key], str):
            raise ValueError('registry_type')
    for key in ['bootstrap_commit', 'bootstrap_blob_sha1', 'archive_revision']:
        if not re.fullmatch('[0-9a-f]{40}', entry[key]):
            raise ValueError('registry_revision')
    for key in ['bootstrap_sha256', 'archive_sha256', 'configuration_digest', 'deno_sha256', 'esbuild_sha256', 'toolchain_provenance_sha256']:
        if not re.fullmatch('[0-9a-f]{64}', entry[key]):
            raise ValueError('registry_digest')
    if entry['toolchain_provenance_sha256'] != PROVENANCE_HASH:
        raise ValueError('registry_provenance')
    if not isinstance(entry['inputs'], list) or len(entry['inputs']) != 8:
        raise ValueError('registry_inputs')
    for item in entry['inputs']:
        if not isinstance(item, dict) or set(item) != {'path', 'sha256', 'byte_count'} or not isinstance(item['path'], str) or not isinstance(item['sha256'], str) or not re.fullmatch('[0-9a-f]{64}', item['sha256']) or type(item['byte_count']) is not int or not 0 < item['byte_count'] <= 1048576:
            raise ValueError('registry_input')
    if entry['artifact_sha256'] is None and entry['artifact_bytes'] is None:
        return
    if not isinstance(entry['artifact_sha256'], str) or not re.fullmatch('[0-9a-f]{64}', entry['artifact_sha256']) or type(entry['artifact_bytes']) is not int or not 0 < entry['artifact_bytes'] < 100000:
        raise ValueError('registry_artifact')

def read_bootstrap(entry):
    """Read only the pre-existing regular Git blob selected by the saved tuple."""

    def git(*args):
        result = subprocess.run(['/usr/bin/git', '--no-replace-objects', '-C', str(REPO), *args], capture_output=True, timeout=5, env={'PATH': '/usr/bin:/bin'})
        if result.returncode or len(result.stdout) > 65536:
            raise ValueError('bootstrap_git')
        return result.stdout
    if not re.fullmatch('[0-9a-f]{40}', entry['bootstrap_blob_sha1']) or git('cat-file', '-t', entry['bootstrap_commit']) != b'commit\n':
        raise ValueError('bootstrap_commit')
    tree = git('ls-tree', '-z', entry['bootstrap_commit'], '--', BOOTSTRAP)
    expected = ('100644 blob ' + entry['bootstrap_blob_sha1'] + '\t' + BOOTSTRAP + '\x00').encode()
    if tree != expected or int(git('cat-file', '-s', entry['bootstrap_blob_sha1'])) > 65536:
        raise ValueError('bootstrap_blob')
    data = git('cat-file', 'blob', entry['bootstrap_blob_sha1'])
    if sha(data) != entry['bootstrap_sha256']:
        raise ValueError('bootstrap_digest')
    return data

def verify_archive(data, entry):
    """The exact accepted sourceArchive resolver output is the only admitted archive."""
    if len(data) > 2097152 or sha(data) != entry['archive_sha256']:
        raise ValueError('archive_digest')
    archive = json.loads(data)
    if archive['catalog']['digest'] != entry['configuration_digest'] or archive['catalog']['manifest']['repository_revision'] != entry['archive_revision']:
        raise ValueError('archive_identity')
    files = {}
    for member in archive['files']:
        path = member['path']
        if path in files or not path.startswith(PREFIX) or any((part in ['', '.', '..'] for part in path.split('/'))):
            raise ValueError('archive_path')
        content = base64.b64decode(member['base64'], validate=True)
        if len(content) != member['byte_count'] or sha(content) != member['sha256']:
            raise ValueError('archive_member')
        files[path] = content
    if len(entry['inputs']) != 8 or {item['path'] for item in entry['inputs']} != set(CLOSURE + [PREFIX + 'deno.json', PREFIX + 'dependencies.lock']):
        raise ValueError('input_closure')
    for item in entry['inputs']:
        content = files[item['path']]
        if len(content) != item['byte_count'] or sha(content) != item['sha256']:
            raise ValueError('input_digest')
    return files

def verify_artifact(data, entry):
    if sha(data) != entry['artifact_sha256'] or len(data) != entry['artifact_bytes']:
        raise ValueError('unregistered_artifact')

def validate_answer(answer, operation, source):
    keys = {'version', 'operation', 'input_bytes', 'input_sha256', 'output_bytes', 'output_sha256', 'base64', 'complete'}
    if not isinstance(answer, dict) or set(answer) != keys:
        raise ValueError('output_protocol')
    if type(answer['version']) is not int or answer['version'] != 1 or answer['operation'] != operation or answer['complete'] is not True or (type(answer['input_bytes']) is not int) or (answer['input_bytes'] != len(source)) or (answer['input_sha256'] != sha(source)) or (not isinstance(answer['base64'], str)) or (len(answer['base64']) > 100000):
        raise ValueError('output_identity')
    data = base64.b64decode(answer['base64'], validate=True)
    if type(answer['output_bytes']) is not int or answer['output_bytes'] != len(data) or answer['output_sha256'] != sha(data):
        raise ValueError('output_digest')
    return data

def private_output_directory(directory):
    directory = pathlib.Path(os.path.abspath(directory))
    for ancestor in [*reversed(directory.parents), directory]:
        if not stat.S_ISDIR(ancestor.lstat().st_mode):
            raise ValueError('output_directory')
    info = directory.stat()
    if stat.S_IMODE(info.st_mode) != 0o700 or info.st_uid != os.getuid():
        raise ValueError('output_privacy')
    return directory

def publish(directory, name, data):
    """No-replace, fsynced publication; interruption never replaces earlier evidence."""
    directory = private_output_directory(directory)
    if pathlib.Path(name).name != name or name in ['', '.', '..']:
        raise ValueError('output_name')
    (fd, temporary) = tempfile.mkstemp(prefix='.pending-', dir=directory)
    try:
        with os.fdopen(fd, 'wb') as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        try:
            os.link(temporary, directory / name)
        except FileExistsError:
            if read_regular(directory / name, len(data)) != data:
                raise ValueError('publication_conflict')
    finally:
        os.unlink(temporary)

def verify_regular(path, digest, mode):
    if not (not path.is_symlink() and path.is_file()):
        raise ValueError('qualification_check_failed')
    if not path.stat().st_mode & 511 == mode:
        raise ValueError('qualification_check_failed')
    if not sha(read_regular(path, 180 * 1024 ** 2)) == digest:
        raise ValueError('qualification_check_failed')

def validate_cache(items, cache, cwd, executable, phase):
    if not (len(items) <= 32 and sum((i.get('bytes', 0) for i in items)) <= 16 * 1024 ** 2):
        raise ValueError('qualification_check_failed')
    databases = {'dep_analysis_cache_v2', 'node_analysis_cache_v2'}
    if phase == 'runtime':
        databases.add('v8_code_cache_v2')
    allowed = {name + suffix for name in databases for suffix in ['', '-shm', '-wal']}
    generated = {'gen/file/' + str(cwd / path).lstrip('/') + '.js' for path in CLOSURE + [BOOTSTRAP]}
    for item in items:
        path = item['path']
        if item['type'] == 'symlink':
            if not (phase == 'runtime' and path == 'node_compat_bin/node'):
                raise ValueError('qualification_check_failed')
            if not (item['target'] == str(executable) and (cache / path).resolve() == executable):
                raise ValueError('qualification_check_failed')
            if not executable.parent.stat().st_mode & 511 == 448:
                raise ValueError('qualification_check_failed')
            verify_regular(executable, DENO_HASH, 320)
        elif path == 'dl/esbuild-0.25.5/esbuild-darwin-arm64':
            if not (phase == 'build' and item['sha256'] == ESBUILD_HASH):
                raise ValueError('qualification_check_failed')
        elif not (item['type'] == 'file' and (path in allowed or (phase == 'build' and path in generated))):
            raise ValueError('qualification_check_failed')

def inventory(root):
    """Never follow cache links, read special files, or allocate an unbounded cache."""
    result = []
    total = 0
    visited = 0
    for (directory, dirs, names) in os.walk(root, followlinks=False):
        for name in dirs[:] + names:
            path = pathlib.Path(directory) / name
            visited += 1
            if visited > 128:
                raise ValueError('cache_entries')
            if path.is_symlink():
                result.append({'path': str(path.relative_to(root)), 'type': 'symlink', 'target': os.readlink(path)})
                if name in dirs:
                    dirs.remove(name)
            elif path.is_dir():
                continue
            else:
                data = read_regular(path, 16 * 1024 ** 2)
                total += len(data)
                if total > 16 * 1024 ** 2 or len(result) >= 32:
                    raise ValueError('cache_size')
                result.append({'path': str(path.relative_to(root)), 'type': 'file', 'mode': oct(path.stat().st_mode & 511), 'bytes': len(data), 'sha256': sha(data)})
    return sorted(result, key=lambda item: item['path'])

def remaining_time(start, timeout):
    remaining = timeout - (time.monotonic() - start)
    if remaining <= 0:
        raise RuntimeError('timeout')
    return remaining


@contextlib.contextmanager
def locked_tree(root):
    """Private measured sources stay non-writable for the child's entire lifetime."""
    directories = [root, *(p for p in root.rglob('*') if p.is_dir())]
    for directory in directories:
        directory.chmod(0o500)
    try:
        yield
    finally:
        for directory in directories:
            directory.chmod(0o700)


def run(args, cwd, cache, data=b'', timeout=15, limit=1048576, inputs=None,
        cancelled=lambda: False, cancel_after_output=None):
    if not isinstance(data, bytes) or len(data) > 300000 or not 0 < timeout <= 15 or not 0 < limit <= 1048576:
        raise ValueError('process_bounds')
    for path, digest in (inputs or {}).items():
        verify_regular(path, digest, 0o400)
    verify_regular(pathlib.Path(args[0]), DENO_HASH, 0o500)
    seed = cache / 'dl/esbuild-0.25.5/esbuild-darwin-arm64'
    if seed.exists():
        verify_regular(seed, ESBUILD_HASH, 0o500)
    cmd = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', *map(str, args)]
    env = {'PATH': '/usr/bin:/bin', 'DENO_DIR': str(cache),
           'DENO_NO_UPDATE_CHECK': '1', 'NO_COLOR': '1', 'TZ': 'UTC', 'LANG': 'C'}
    start = time.monotonic()
    child = None
    peak, samples = 0, 0
    out, err = bytearray(), bytearray()
    failure, code, sel = None, None, None
    try:
        child = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 start_new_session=True)
        # Spawn and all partially completed setup share one cleanup boundary.
        sel = selectors.DefaultSelector()
        for stream in (child.stdin, child.stdout, child.stderr):
            os.set_blocking(stream.fileno(), False)
        sel.register(child.stdout, selectors.EVENT_READ, out)
        sel.register(child.stderr, selectors.EVENT_READ, err)
        if data:
            sel.register(child.stdin, selectors.EVENT_WRITE, None)
        else:
            child.stdin.close()
        offset = 0
        while sel.get_map() or child.poll() is None:
            remaining = remaining_time(start, timeout)
            if cancelled() or (cancel_after_output and cancel_after_output in out):
                raise RuntimeError('cancelled')
            if child.poll() is None:
                ps = subprocess.run(['/bin/ps', '-axo', 'pgid=,rss='],
                                    capture_output=True, text=True,
                                    timeout=min(2, remaining))
                remaining_time(start, timeout)
                if ps.returncode:
                    raise RuntimeError('rss_unavailable')
                rows = [row.split() for row in ps.stdout.splitlines()]
                values = [int(row[1]) * 1024 for row in rows
                          if len(row) == 2 and row[0] == str(child.pid)]
                if values:
                    samples += 1
                    peak = max(peak, sum(values))
                if peak > 256 * 1024 * 1024:
                    raise RuntimeError('sampled_rss_limit')
            for key, event in sel.select(min(0.02, remaining_time(start, timeout))):
                if event & selectors.EVENT_WRITE:
                    try:
                        offset += os.write(key.fd, data[offset:offset + 16384])
                    except BrokenPipeError:
                        offset = len(data)
                    if offset == len(data):
                        sel.unregister(key.fileobj)
                        key.fileobj.close()
                else:
                    room = limit - len(out) - len(err)
                    chunk = os.read(key.fd, min(65536, room + 1))
                    if not chunk:
                        sel.unregister(key.fileobj)
                        key.fileobj.close()
                    elif len(chunk) > room:
                        # Retain at most the declared cap; the overflow byte is discarded.
                        key.data.extend(chunk[:room])
                        raise RuntimeError('output_limit')
                    else:
                        key.data.extend(chunk)
            remaining_time(start, timeout)
        code = child.wait(timeout=remaining_time(start, timeout))
        remaining_time(start, timeout)
        if samples == 0:
            raise RuntimeError('rss_unobserved')
    except subprocess.TimeoutExpired:
        failure, code = 'timeout', None
    except RuntimeError as error:
        failure, code = str(error), None
    finally:
        try:
            if child is not None:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                child.wait(timeout=5)
        finally:
            if sel is not None:
                sel.close()
            if child is not None:
                for stream in (child.stdin, child.stdout, child.stderr):
                    if stream is not None and not stream.closed:
                        stream.close()
    # The direct child is reaped. Check that no process remains in its group.
    try:
        os.killpg(child.pid, 0)
    except ProcessLookupError:
        group_gone = True
    else:
        raise RuntimeError('process_group_survived')
    items = inventory(cache)
    validate_cache(items, cache, cwd, pathlib.Path(args[0]),
                   'runtime' if args[1] == 'run' else 'build')
    return ({'args': list(map(str, args)), 'exit': code, 'failure': failure,
             'elapsed_ms': round((time.monotonic() - start) * 1000),
             'sampled_peak_group_rss': peak, 'rss_samples': samples,
             'stdout': bytes(out).decode(), 'stderr': bytes(err).decode(),
             'cache': str(cache), 'cache_after': items,
             'reaped': child.returncode is not None, 'process_group_gone': group_gone}, bytes(out))

def verify_toolchain_report(raw):
    expected = (b'deno 2.9.4 (stable, release, aarch64-apple-darwin)\n'
                b'v8 15.0.245.2-rusty\ntypescript 6.0.3\n')
    if raw != expected:
        raise ValueError('toolchain_version')
    return dict(deno_version='2.9.4', deno_target='aarch64-apple-darwin',
                v8_version='15.0.245.2-rusty', typescript_version='6.0.3')


def expected_exit(result, code):
    return (result['exit'] == code and result['failure'] is None and
            result['reaped'] and result['process_group_gone'] and
            result['rss_samples'] > 0)


def wav(rate, samples):
    data = struct.pack('<' + 'h' * len(samples), *samples)
    return b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVEfmt ' + struct.pack('<IHHIIHH', 16, 1, 1, rate, rate * 2, 2, 16) + b'data' + struct.pack('<I', len(data)) + data

def qualify(options):
    entry = select_version(options.version)
    if not options.build_only and (not entry['artifact_sha256'] or not entry['artifact_bytes']):
        raise ValueError('unregistered_artifact')
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('unsupported_platform')
    toolchain = options.toolchain
    output_directory = private_output_directory(options.output)
    if shutil.disk_usage(ROOT).free <= 20 * 1024 ** 3 + 180 * 1024 ** 2:
        raise ValueError('disk_floor')
    provenance_bytes = read_regular(toolchain / 'provenance.json', 65536)
    if sha(provenance_bytes) != entry['toolchain_provenance_sha256']:
        raise ValueError('qualification_check_failed')
    provenance = json.loads(provenance_bytes)
    if not (provenance['package'], provenance['version'], provenance['platform'], provenance['license']) == ('@esbuild/darwin-arm64', '0.25.5', 'darwin-arm64', 'MIT'):
        raise ValueError('qualification_check_failed')
    if not set(provenance['files']) == {'LICENSE.md', 'README.md', 'bin/esbuild', 'deno-esbuild.rs', 'package.json', 'package.tgz', 'registry-metadata.json'}:
        raise ValueError('qualification_check_failed')
    for (name, record) in provenance['files'].items():
        path = toolchain / name
        if not not path.is_symlink():
            raise ValueError('qualification_check_failed')
        data = read_regular(path, 16 * 1024 ** 2)
        if not (len(data) == record['bytes'] and sha(data) == record['sha256']):
            raise ValueError('qualification_check_failed')
    esbuild = read_regular(toolchain / 'bin/esbuild', 12 * 1024 ** 2)
    if not sha(esbuild) == ESBUILD_HASH:
        raise ValueError('qualification_check_failed')
    deno = read_regular(options.deno, 180 * 1024 ** 2)
    if not sha(deno) == DENO_HASH:
        raise ValueError('qualification_check_failed')
    archive_bytes = read_regular(options.archive, 2097152)
    files = verify_archive(archive_bytes, entry)
    bootstrap = read_bootstrap(entry)
    evidence = {'scope': 'local synthetic preparation only; no hosted or provider integration', 'deno_sha256': DENO_HASH, 'esbuild_sha256': ESBUILD_HASH, 'archive_sha256': ARCHIVE_HASH, 'bootstrap_sha256': sha(bootstrap), 'network_policy': '(version 1)(allow default)(deny network*)', 'builds': [], 'executions': []}
    evidence.update({'receipt_format': 1, 'status': 'unqualified_build_only' if options.build_only else 'qualification_in_progress', 'selected_version': entry['id'], 'registry_entry': entry, 'harness_sha256': sha(read_regular(pathlib.Path(__file__), 100000))})
    pkg = read_regular(toolchain / 'package.tgz', 16 * 1024 ** 2)
    meta = json.loads(read_regular(toolchain / 'registry-metadata.json', 65536))
    if not meta['dist']['integrity'] == 'sha512-' + base64.b64encode(hashlib.sha512(pkg).digest()).decode():
        raise ValueError('qualification_check_failed')
    with tarfile.open(toolchain / 'package.tgz', 'r:gz') as t:
        members = t.getmembers()
        if not (len(members) == 3 and {m.name for m in members} == {'package/bin/esbuild', 'package/package.json', 'package/README.md'}):
            raise ValueError('qualification_check_failed')
        if not all((m.isfile() and m.size <= 12 * 1024 ** 2 for m in members)):
            raise ValueError('qualification_check_failed')
        if not t.extractfile('package/bin/esbuild').read() == esbuild:
            raise ValueError('qualification_check_failed')
        package = json.load(t.extractfile('package/package.json'))
        if not all((package[k] == meta[k] for k in ['name', 'version', 'os', 'cpu', 'license'])):
            raise ValueError('qualification_check_failed')
        if not meta['dist']['integrity'] == provenance['integrity']:
            raise ValueError('qualification_check_failed')
        if not (package['name'] == provenance['package'] and package['version'] == provenance['version'] and (package['os'] == ['darwin']) and (package['cpu'] == ['arm64'])):
            raise ValueError('qualification_check_failed')
        evidence['archive_member_allowlist'] = [{'path': m.name, 'type': 'regular', 'size': m.size, 'mode': oct(m.mode)} for m in members]
    with tempfile.TemporaryDirectory(prefix='merian-m3-qualified-') as tmp:
        p = pathlib.Path(tmp).resolve()
        executable = p / 'deno'
        executable.write_bytes(deno)
        executable.chmod(320)
        verify_regular(executable, DENO_HASH, 320)
        del deno
        report_root = p / 'toolchain-report'
        report_root.mkdir()
        with locked_tree(report_root):
            report, raw = run([executable, '--version'], report_root, p / 'version-cache')
        if not expected_exit(report, 0):
            raise ValueError('toolchain_report')
        evidence.update(verify_toolchain_report(raw))
        evidence['toolchain_version_probe'] = report
        artifacts = []
        for index in (1, 2):
            work = p / f'build{index}'
            work.mkdir()
            tree = work / 'source'
            tree.mkdir()
            cache = work / 'cache'
            seed = cache / 'dl/esbuild-0.25.5/esbuild-darwin-arm64'
            seed.parent.mkdir(parents=True)
            seed.write_bytes(esbuild)
            seed.chmod(320)
            before = inventory(cache)
            if not (len(before) == 1 and before[0]['sha256'] == ESBUILD_HASH):
                raise ValueError('qualification_check_failed')
            for path in CLOSURE + [PREFIX + 'deno.json', PREFIX + 'dependencies.lock']:
                target = tree / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(files[path])
                target.chmod(256)
            (tree / BOOTSTRAP).parent.mkdir(parents=True, exist_ok=True)
            (tree / BOOTSTRAP).write_bytes(bootstrap)
            (tree / BOOTSTRAP).chmod(256)
            measured_inputs = {tree / path: sha(files[path]) for path in CLOSURE + [PREFIX + 'deno.json', PREFIX + 'dependencies.lock']}
            measured_inputs[tree / BOOTSTRAP] = sha(bootstrap)
            config = ['--config', PREFIX + 'deno.json', '--frozen', '--no-remote', '--no-npm', '--deny-import']
            with locked_tree(tree):
                (graph, raw) = run([executable, 'info', '--json', *config, BOOTSTRAP], tree, cache, inputs=measured_inputs)
                if not graph['exit'] == 0:
                    raise ValueError('qualification_check_failed')
                modules = json.loads(raw)['modules']
                actual = {pathlib.Path(m['specifier'].removeprefix('file://')).relative_to(tree).as_posix() for m in modules}
                if not actual == set(CLOSURE + [BOOTSTRAP]):
                    raise ValueError('qualification_check_failed')
                graph['stdout'] = '[resolved local modules verified; lock-derived package metadata omitted]'
                graph['verified_modules'] = sorted(actual)
                (result, _) = run([executable, 'bundle', *config, '--packages', 'bundle', '--platform', 'deno', '--format', 'esm', '--output', str(work / 'artifact.js'), BOOTSTRAP], tree, cache, inputs=measured_inputs)
                if not result['exit'] == 0:
                    raise ValueError('qualification_check_failed')
            artifact = read_regular(work / 'artifact.js', 100000)
            if not len(artifact) < 100000:
                raise ValueError('qualification_check_failed')
            if not (b'import(' not in artifact and b'from "' not in artifact and (str(tree).encode() not in artifact)):
                raise ValueError('qualification_check_failed')
            artifacts.append(artifact)
            evidence['builds'].append({'seed_before': before, 'input_inventory': [{'path': path, 'bytes': len(files[path]), 'sha256': sha(files[path])} for path in CLOSURE + [PREFIX + 'deno.json', PREFIX + 'dependencies.lock']], 'graph': graph, 'bundle': result, 'artifact_sha256': sha(artifact), 'artifact_bytes': len(artifact)})
        if not artifacts[0] == artifacts[1]:
            raise ValueError('qualification_check_failed')
        if not options.build_only:
            verify_artifact(artifacts[0], entry)
        publish(output_directory, ('candidate-' if options.build_only else '') + sha(artifacts[0]) + '.js', artifacts[0])
        if options.build_only:
            publish(output_directory, 'candidate-' + sha(artifacts[0]) + '.json', (json.dumps(evidence, indent=2) + '\n').encode())
            return {'status': 'unqualified_build_only', 'artifact_sha256': sha(artifacts[0]), 'artifact_bytes': len(artifacts[0])}
        execution = p / 'execute'
        execution.mkdir()
        artifact = execution / 'artifact.js'
        artifact.write_bytes(artifacts[0])
        artifact.chmod(256)
        flags = ['run', '--no-config', '--no-lock', '--no-remote', '--no-npm', '--no-check', '--no-prompt', '--deny-read', '--deny-write', '--deny-net', '--deny-env', '--deny-run', '--deny-ffi', '--deny-import', '--v8-flags=--max-old-space-size=64']
        for (op, source, expected) in [('identity', b'synthetic-identity', b'synthetic-identity'), ('wav16k', wav(32000, [8192] * 32000), wav(16000, [8192] * 16000))]:
            req = json.dumps({'version': 1, 'operation': op, 'base64': base64.b64encode(source).decode()}).encode()
            with locked_tree(execution):
                (result, raw) = run([executable, *flags, 'artifact.js'], execution, p / f'cache-{op}', req, inputs={artifact: sha(artifacts[0])})
            if not result['exit'] == 0:
                raise ValueError('qualification_check_failed')
            answer = json.loads(raw)
            output = validate_answer(answer, op, source)
            if not output == expected:
                raise ValueError('qualification_check_failed')
            result['stdout'] = '[synthetic output verified; bytes omitted]'
            evidence['executions'].append({'operation': op, 'input_sha256': sha(source), 'output_sha256': sha(output), 'result': result})
        missing = p / 'missing'
        missing.mkdir()
        (missing / 'input.ts').write_text('export const probe=1;\n')
        # A synthetic ambient cache is separate from both private build caches.
        # Only the verified secondary bundler is cache-resident in this closure.
        ambient = p / 'synthetic-ambient-cache'
        ambient_seed = ambient / 'dl/esbuild-0.25.5/esbuild-darwin-arm64'
        ambient_seed.parent.mkdir(parents=True)
        ambient_seed.write_bytes(esbuild)
        ambient_seed.chmod(0o500)
        ambient_inventory = inventory(ambient)
        previous_cache = os.environ.get('DENO_DIR')
        os.environ['DENO_DIR'] = str(ambient)
        try:
            (result, _) = run([executable, 'bundle', '--no-config', '--no-lock', '--no-remote', '--no-npm', '--deny-import', '--output', 'output.js', 'input.ts'], missing, missing / 'cache')
        finally:
            if previous_cache is None:
                os.environ.pop('DENO_DIR', None)
            else:
                os.environ['DENO_DIR'] = previous_cache
        if inventory(ambient) != ambient_inventory:
            raise ValueError('ambient_cache_changed')
        result['synthetic_ambient_seed'] = ambient_inventory
        result['child_environment'] = 'replacement environment with fresh private DENO_DIR; ambient environment not merged'
        if not (expected_exit(result, 1) and not (missing / 'output.js').exists()):
            raise ValueError('qualification_check_failed')
        evidence['unseeded_denial'] = result
        evidence['negative_probes'] = []
        sentinel = execution / 'adjacent-sentinel'
        sentinel.write_text('synthetic-denied')
        policy = 'const tests=[\n()=>Deno.readTextFile("adjacent-sentinel"),\n()=>Deno.readTextFile(REPO_SENTINEL),\n()=>Deno.writeTextFile("forbidden-write","x"),\n()=>Promise.resolve(Deno.env.get("PATH")),\n()=>new Deno.Command("/usr/bin/true").output(),\n()=>Promise.resolve(Deno.dlopen("/usr/lib/libSystem.B.dylib",{})),\n()=>fetch("https://example.invalid/")];\nlet denied=0;for(const test of tests){try{await test();throw new Error("unexpected_permission");}catch(e){if(e.name!=="NotCapable")throw e;denied++;}}let importDenied=false;try{await import("https://example.invalid/module.js");}catch(e){if(!String(e).includes("Requires import access"))throw e;importDenied=true;}if(!importDenied)throw new Error("import_allowed");console.log(JSON.stringify({denied,importDenied}));'
        policy = policy.replace('REPO_SENTINEL', json.dumps(str(ROOT / 'bootstrap.ts')))
        cases = [('permission', policy, 0, None), ('nonzero', 'Deno.exit(23);', 23, None), ('timeout', 'while(true){}', None, 'timeout'), ('cancel', 'console.log("started");while(true){}', None, 'cancelled'), ('output', 'while(true){console.log("x".repeat(4096))}', None, 'output_limit')]
        for (name, code, wanted_exit, wanted_failure) in cases:
            testpath = execution / f'fixture-{name}.js'
            testpath.write_text(code)
            testpath.chmod(256)
            with locked_tree(execution):
                (result, raw) = run([executable, *flags, testpath.name], execution, p / f'cache-{name}', timeout=0.3 if name == 'timeout' else 5, limit=16384, inputs={testpath: sha(code.encode())}, cancel_after_output=b'started\n' if name == 'cancel' else None)
            if not (result['exit'] == wanted_exit and result['failure'] == wanted_failure and result['reaped'] and result['process_group_gone'] and result['rss_samples'] > 0):
                raise ValueError('qualification_check_failed')
            if name == 'cancel' and not raw.startswith(b'started\n'):
                raise ValueError('cancellation_not_running')
            if name == 'permission':
                if not (json.loads(raw) == {'denied': 7, 'importDenied': True} and (not (execution / 'forbidden-write').exists())):
                    raise ValueError('qualification_check_failed')
            evidence['negative_probes'].append({'name': name, 'fixture_sha256': sha(code.encode()), 'result': result})
        for (name, request) in [('unknown', {'version': 1, 'operation': 'newest', 'base64': ''}), ('extra', {'version': 1, 'operation': 'identity', 'base64': '', 'extra': True}), ('wav', {'version': 1, 'operation': 'wav16k', 'base64': ''}), ('version', {'version': 2, 'operation': 'identity', 'base64': ''}), ('excess', {'version': 1, 'operation': 'identity', 'base64': 'A' * 270000})]:
            with locked_tree(execution):
                (result, _) = run([executable, *flags, 'artifact.js'], execution, p / f'cache-invalid-{name}', json.dumps(request).encode(), inputs={artifact: sha(artifacts[0])})
            if not (expected_exit(result, 1) and not result['stdout']):
                raise ValueError('qualification_check_failed')
            evidence['negative_probes'].append({'name': name, 'result': result})
    evidence['status'] = 'local_synthetic_qualification_only'
    evidence['selected_version'] = entry['id']
    evidence['registry_entry'] = entry
    evidence['harness_sha256'] = sha(read_regular(pathlib.Path(__file__), 100000))
    evidence['memory_policy'] = '64MiB V8 heap; sampled 256MiB process-group RSS; no hard native memory bound'
    receipt = (json.dumps(evidence, indent=2) + '\n').encode()
    publish(output_directory, 'qualification-' + sha(receipt) + '.json', receipt)
    return {'status': evidence['status'], 'artifact_sha256': sha(artifacts[0]), 'receipt_sha256': sha(receipt)}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['archive', 'toolchain', 'deno', 'output']:
        parser.add_argument('--' + name, type=pathlib.Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build-only', action='store_true', help='Retain unqualified candidate bytes; never execute them')
    options = parser.parse_args()
    try:
        def interrupted(signum, frame):
            raise KeyboardInterrupt
        signal.signal(signal.SIGTERM, interrupted)
        with execution_lock():
            print(json.dumps(qualify(options)))
    except KeyboardInterrupt:
        print(json.dumps({'status': 'held', 'reason': 'cancelled'}))
        raise SystemExit(130)
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({'status': 'held', 'reason': str(error) if isinstance(error, ValueError) and str(error) in ['disk_floor', 'unknown_version', 'unsupported_platform', 'unregistered_artifact'] else type(error).__name__}))
        raise SystemExit(1)
if __name__ == '__main__':
    main()
