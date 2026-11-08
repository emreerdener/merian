#!/usr/bin/env python3
"""Offline staging only. Consumes `deno info --json` for this exact entrypoint.
No credentials, subprocesses, network, installation, or deployment.
"""
import hashlib
import json
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[5]
CANDIDATE = ROOT / 'services/supabase/tests/cpm_verifier_characterization'
SHARED = ROOT / 'services/supabase/functions/_shared'
ROUTE = 'cpm-verifier-characterization'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def project_lock(locked, selected):
    """Copy a closed subset of existing npm records without dependency resolution."""
    if locked['version'] != '5' or any(not v.startswith('npm:') or v not in locked['workspace']['dependencies'] for v in selected):
        raise ValueError('unlocked_workspace_dependency')
    packages = locked['npm']
    def resolve(name):
        matches = [key for key in packages if key == name or key.rsplit('@', 1)[0] == name]
        if len(matches) != 1:
            raise ValueError('ambiguous_locked_dependency')
        return matches[0]
    pending = [value[4:] for value in selected] + [resolve('@types/node')]
    keep = set()
    while pending:
        key = resolve(pending.pop())
        if key in keep:
            continue
        keep.add(key)
        pending.extend(packages[key].get('dependencies', []))
    return {'version': '5', 'specifiers': {v: locked['specifiers'][v] for v in selected},
            'npm': {key: packages[key] for key in sorted(keep)},
            'workspace': {'dependencies': selected}}


def verify(graph_path, output):
    """Require an immediately generated staged Deno graph plus unchanged bytes."""
    manifest = json.loads((output / 'manifest.json').read_text())
    graph = json.loads(graph_path.read_text())
    entry = output / f'supabase/functions/{ROUTE}/index.ts'
    if graph['roots'] != [entry.as_uri()]:
        raise ValueError('staged_root')
    expected = {(output / item['path']).as_uri() for item in manifest['files'] if item['path'].endswith('.ts')}
    actual = {m['specifier'] for m in graph['modules'] if m['specifier'].startswith('file:')}
    if expected != actual or any('error' in m for m in graph['modules']):
        raise ValueError('staged_graph_closure')
    for item in manifest['files']:
        target = output / item['path']
        if not target.resolve().is_relative_to(output) or target.is_symlink():
            raise ValueError('staged_path')
        data = target.read_bytes()
        if len(data) != item['bytes'] or digest(data) != item['sha256']:
            raise ValueError('staged_bytes_changed')
    packaged = {item['path']: item['sha256'] for item in manifest['files']}
    for item in manifest['provenance']:
        if item['target'] not in packaged or packaged[item['target']] != item['packaged_sha256']:
            raise ValueError('provenance_target')
        source = ROOT / item['source']
        if source.resolve() != source or not source.is_relative_to(ROOT / 'services/supabase'):
            raise ValueError('source_path')
        if digest(source.read_bytes()) != item['source_sha256']:
            raise ValueError('source_changed_since_staging')
    identity = digest(json.dumps(manifest['files'], separators=(',', ':'), sort_keys=True).encode())
    if identity != manifest['package_sha256']:
        raise ValueError('manifest_identity')
    print(json.dumps({'verified': True, 'package_sha256': identity, 'local_modules': len(actual)}))


def stage(graph_path, output):
    graph = json.loads(graph_path.read_text())
    expected = (CANDIDATE / 'runtime/entrypoint.ts').as_uri()
    if graph['roots'] != [expected]:
        raise ValueError('entrypoint_mismatch')
    if output.exists() or output.is_symlink():
        raise ValueError('output_must_be_new')
    files = {}
    provenance = []
    imports = set()
    for module in graph['modules']:
        if 'error' in module:
            raise ValueError('incomplete_graph')
        specifier = module['specifier']
        if not specifier.startswith('file:'):
            continue
        source = Path(unquote(urlparse(specifier).path))
        if source.is_symlink() or source.resolve() != source:
            raise ValueError('symlink_source')
        if source.is_relative_to(SHARED):
            target = Path('supabase/functions/_shared') / source.relative_to(SHARED)
        elif source.is_relative_to(CANDIDATE):
            target = Path('supabase/functions') / ROUTE / 'candidate' / source.relative_to(CANDIDATE)
        else:
            raise ValueError('unexpected_local_dependency')
        if source.suffix != '.ts' or source.name.endswith('_test.ts'):
            raise ValueError('unexpected_source_type')
        data = source.read_bytes()
        for dependency in module.get('dependencies', []):
            name = dependency['specifier']
            if not name.startswith(('.', 'node:')):
                imports.add(name)
        transformed = data.replace(b'../../functions/_shared/', b'../../_shared/')
        files[target.as_posix()] = transformed
        provenance.append({'source': source.relative_to(ROOT).as_posix(), 'target': target.as_posix(), 'source_sha256': digest(data), 'packaged_sha256': digest(transformed)})
    functions = ROOT / 'services/supabase/functions'
    root_config = json.loads((functions / 'deno.json').read_text())
    if root_config['lock'] != {'path': './dependencies.lock', 'frozen': True}:
        raise ValueError('lock_config')
    if root_config['minimumDependencyAge'] != 'P1D':
        raise ValueError('dependency_age')
    if not imports or not imports.issubset(root_config['imports']):
        raise ValueError('unmapped_dependency')
    # Standalone experimental package: only reachable aliases, exact fleet pins.
    # Reachable locked records are copied exactly, including integrity and dependency
    # lists. No resolver is run and the original shared lock is untouched.
    local = {'lock': {'path': '../dependencies.lock', 'frozen': True}, 'minimumDependencyAge': 'P1D', 'imports': {name: root_config['imports'][name] for name in sorted(imports)}}
    files[f'supabase/functions/{ROUTE}/deno.json'] = (json.dumps(local, indent=2) + '\n').encode()
    locked = json.loads((functions / 'dependencies.lock').read_text())
    selected = sorted(local['imports'].values())
    locked = project_lock(locked, selected)
    files['supabase/functions/dependencies.lock'] = (json.dumps(locked, indent=2) + '\n').encode()
    files[f'supabase/functions/{ROUTE}/index.ts'] = b'import "./candidate/runtime/entrypoint.ts";\n'
    for source_name, target_name in [('deno.json', f'supabase/functions/{ROUTE}/deno.json'), ('dependencies.lock', 'supabase/functions/dependencies.lock')]:
        source = functions / source_name
        provenance.append({'source': source.relative_to(ROOT).as_posix(), 'target': target_name, 'source_sha256': digest(source.read_bytes()), 'packaged_sha256': digest(files[target_name])})
    files['supabase/config.toml'] = f'project_id = "cpm-qualification-only"\n\n[functions.{ROUTE}]\nenabled = true\nverify_jwt = false\nentrypoint = "./functions/{ROUTE}/index.ts"\n'.encode()
    if sum(map(len, files.values())) > 8 * 1024 * 1024:
        raise ValueError('package_size')
    manifest = [{'path': path, 'bytes': len(data), 'sha256': digest(data)} for path, data in sorted(files.items())]
    identity = digest(json.dumps(manifest, separators=(',', ':'), sort_keys=True).encode())
    output.mkdir(parents=True, exist_ok=False)
    for name, data in files.items():
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as handle:
            handle.write(data)
    (output / 'manifest.json').write_text(json.dumps({'format': 1, 'package_sha256': identity, 'files': manifest, 'provenance': sorted(provenance, key=lambda p: p['source'])}, indent=2) + '\n')
    print(json.dumps({'package_sha256': identity, 'files': len(files), 'bytes': sum(map(len, files.values()))}))


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == '--verify':
        verify(Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve())
    elif len(sys.argv) == 3:
        stage(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
    else:
        raise SystemExit('usage: stage.py [--verify] GRAPH_JSON OUTPUT_DIRECTORY')
