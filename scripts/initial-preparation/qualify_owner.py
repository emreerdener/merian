"""Explicit local synthetic owner/artifact integration; not installed runtime use."""
import argparse
import json
import pathlib
import platform
import shutil
import signal
import subprocess
import tempfile
import time
import artifact as a
from owner_protocol import OwnerExchange


def qualify(options):
    entry = a.select_version(a.VALIDATED)
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('unsupported_platform')
    output = a.private_output_directory(options.output)
    if shutil.disk_usage(a.ROOT).free <= 20 * 1024 ** 3 + 180 * 1024 ** 2:
        raise ValueError('disk_floor')
    deno = a.read_regular(options.deno, 180 * 1024 ** 2)
    if a.sha(deno) != a.DENO_HASH:
        raise ValueError('toolchain_identity')
    executable_bytes = a.read_regular(options.artifact, 100000)
    a.verify_artifact(executable_bytes, entry)
    manifest_raw = a.read_regular(a.ROOT / 'owner-source-files.json', 65536)
    manifest = json.loads(manifest_raw)
    if (not isinstance(manifest, list) or len(manifest) > 32 or manifest != sorted(set(manifest)) or
            any(not isinstance(name, str) or '..' in pathlib.PurePosixPath(name).parts or
                name.startswith('/') or not name.startswith(('scripts/initial-preparation/', 'services/supabase/functions/_shared/')) for name in manifest)):
        raise ValueError('owner_source_manifest')
    files = {name: a.read_regular(a.REPO / name, 262144) for name in manifest}
    if sum(map(len, files.values())) > 2 * 1024 ** 2:
        raise ValueError('owner_source_bound')
    if a.sha(files[a.VALIDATOR]) != entry['validator']['sha256']:
        raise ValueError('validator_identity')
    flags = ['run', '--no-config', '--no-lock', '--no-remote', '--no-npm', '--no-check', '--no-prompt',
             '--deny-read', '--deny-write', '--deny-net', '--deny-env', '--deny-run', '--deny-ffi', '--deny-import', '--v8-flags=--max-old-space-size=64']
    evidence = dict(scope='local_synthetic_owner_integration_only', activation=False, edge_eligible=False,
                    resource_status='sampled_local_only', hard_cpu_qualified=False, hard_native_memory_qualified=False,
                    supervisor_parent_death_qualified=False, manifest_sha256=a.sha(manifest_raw),
                    inputs=[dict(path=name, sha256=a.sha(value), byte_count=len(value)) for name, value in files.items()],
                    harness_sha256=a.sha(a.read_regular(a.ROOT / 'artifact.py', 150000)),
                    qualifier_sha256=a.sha(a.read_regular(pathlib.Path(__file__), 65536)),
                    protocol_sha256=a.sha(a.read_regular(a.ROOT / 'owner_protocol.py', 65536)), registry_entry=entry)
    try:
        with tempfile.TemporaryDirectory(prefix='merian-original-owner-') as temporary:
            root = pathlib.Path(temporary).resolve()
            executable = root / 'deno'
            executable.write_bytes(deno)
            executable.chmod(0o500)
            del deno
            tree = root / 'sources'
            tree.mkdir()
            for name, content in files.items():
                path = tree / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
                path.chmod(0o400)
            transform = root / 'transform'
            transform.mkdir()
            artifact = transform / 'artifact.js'
            artifact.write_bytes(executable_bytes)
            artifact.chmod(0o400)
            exchange = OwnerExchange([executable, *flags, 'artifact.js'], transform, root / 'transform-cache',
                                     {artifact: entry['artifact_sha256']}, tree / 'scripts/initial-preparation/owner-fixture.json')
            measured = {tree / name: a.sha(content) for name, content in files.items()}
            with a.locked_tree(tree), a.locked_tree(transform):
                call_start = time.monotonic()
                result, _ = a.run([executable, *flags, 'scripts/initial-preparation/owner-coordinator.ts'], tree,
                                  root / 'coordinator-cache', inputs=measured, profile=a.VALIDATED, exchange=exchange)
            # No raw media/process stdout or arbitrary errors persist, even on failure.
            result['stdout'] = '[fixed synthetic pipe frames omitted]'
            result['stderr'] = '[process diagnostic omitted]' if result['stderr'] else ''
            for child in result['exchange']['children']:
                child['stdout'] = '[synthetic output omitted]'
                child['stderr'] = '[process diagnostic omitted]' if child['stderr'] else ''
            evidence.update(result=result, outcome_digest=exchange.outcome_digest, input_sha256=a.sha(exchange.source),
                            output_sha256=a.sha(exchange.output) if exchange.output is not None else None)
            evidence['status'] = 'local_synthetic_qualified' if a.expected_exit(result, 0) and exchange.finished else 'failed'
            framed = json.dumps(evidence, indent=2).encode() + b'\n'
            if time.monotonic() - call_start >= 15:
                evidence['status'] = 'failed'
                evidence['failure'] = 'total_deadline'
                framed = json.dumps(evidence, indent=2).encode() + b'\n'
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        evidence.update(status='failed', failure_type=type(error).__name__)
        framed = json.dumps(evidence, indent=2).encode() + b'\n'
    a.publish(output, 'owner-qualification-' + a.sha(framed) + '.json', framed)
    return dict(status=evidence['status'], evidence_sha256=a.sha(framed))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['deno', 'artifact', 'output']:
        parser.add_argument('--' + name, type=pathlib.Path, required=True)
    options = parser.parse_args()
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    with a.execution_lock():
        result = qualify(options)
    print(json.dumps(result))
    raise SystemExit(0 if result['status'] == 'local_synthetic_qualified' else 1)


if __name__ == '__main__':
    main()
