import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('qualification_stage', Path(__file__).with_name('stage.py'))
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


class PackageTests(unittest.TestCase):
    def test_only_declared_sources_relocated_and_existing_output_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            entry = stage.CANDIDATE / 'runtime/entrypoint.ts'
            auth = stage.CANDIDATE / 'runtime/auth.ts'
            graph = {'roots': [entry.as_uri()], 'modules': [{'specifier': entry.as_uri()}, {'specifier': auth.as_uri(), 'dependencies': [{'specifier': '@supabase/supabase-js'}]}]}
            source = temp / 'graph.json'
            source.write_text(json.dumps(graph))
            target = temp / 'package'
            stage.stage(source, target)
            manifest = json.loads((target / 'manifest.json').read_text())
            self.assertEqual(len(manifest['files']), 6)
            for item in manifest['files']:
                self.assertEqual(stage.digest((target / item['path']).read_bytes()), item['sha256'])
            auth_copy = target / f'supabase/functions/{stage.ROUTE}/candidate/runtime/auth.ts'
            self.assertNotIn('../../../functions/_shared/', auth_copy.read_text())
            self.assertNotIn('functions/_shared/', auth_copy.read_text())
            config = (target / 'supabase/config.toml').read_text()
            self.assertEqual(config.count('[functions.'), 1)
            self.assertIn('verify_jwt = false', config)
            self.assertFalse((target / 'supabase/migrations').exists())
            original_lock = json.loads((stage.ROOT / 'services/supabase/functions/dependencies.lock').read_text())
            projected_lock = json.loads((target / 'supabase/functions/dependencies.lock').read_text())
            self.assertEqual(projected_lock.pop('workspace')['dependencies'], ['npm:@supabase/supabase-js@2.117.2'])
            for key, value in projected_lock['npm'].items():
                self.assertEqual(value, original_lock['npm'][key])
            self.assertNotIn('@google/genai@2.24.0', projected_lock['npm'])
            self.assertIn('@types/node@26.6.3', projected_lock['npm'])
            for key, value in projected_lock['specifiers'].items():
                self.assertEqual(value, original_lock['specifiers'][key])
            with self.assertRaises(ValueError):
                stage.stage(source, target)

    def test_verify_rejects_partial_graph_and_modified_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp).resolve()
            entry = stage.CANDIDATE / 'runtime/entrypoint.ts'
            auth = stage.CANDIDATE / 'runtime/auth.ts'
            source = temp / 'graph.json'
            source.write_text(json.dumps({'roots': [entry.as_uri()], 'modules': [{'specifier': entry.as_uri()}, {'specifier': auth.as_uri(), 'dependencies': [{'specifier': '@supabase/supabase-js'}]}]}))
            target = temp / 'package'
            stage.stage(source, target)
            manifest = json.loads((target / 'manifest.json').read_text())
            staged_entry = target / f'supabase/functions/{stage.ROUTE}/index.ts'
            graph = {'roots': [staged_entry.as_uri()], 'modules': [{'specifier': (target / item['path']).as_uri()} for item in manifest['files'] if item['path'].endswith('.ts')]}
            source.write_text(json.dumps(graph))
            stage.verify(source, target)
            original_manifest = (target / 'manifest.json').read_text()
            for bad_target in ['not-packaged.ts', manifest['provenance'][0]['target']]:
                broken = json.loads(original_manifest)
                broken['provenance'][0]['target'] = bad_target
                broken['provenance'][0]['packaged_sha256'] = '0' * 64
                (target / 'manifest.json').write_text(json.dumps(broken))
                with self.assertRaisesRegex(ValueError, 'provenance_target'):
                    stage.verify(source, target)
            (target / 'manifest.json').write_text(original_manifest)
            partial = {**graph, 'modules': graph['modules'][:-1]}
            source.write_text(json.dumps(partial))
            with self.assertRaisesRegex(ValueError, 'staged_graph_closure'):
                stage.verify(source, target)
            source.write_text(json.dumps(graph))
            staged_entry.write_text('// changed')
            with self.assertRaisesRegex(ValueError, 'staged_bytes_changed'):
                stage.verify(source, target)

    def test_foreign_module_or_wrong_root_rejected_before_output(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            entry = stage.CANDIDATE / 'runtime/entrypoint.ts'
            for graph in [
                {'roots': ['file:///not-the-entrypoint'], 'modules': []},
                {'roots': [entry.as_uri()], 'modules': [{'specifier': (stage.ROOT / 'README.md').as_uri()}]},
                {'roots': [entry.as_uri()], 'modules': [{'specifier': entry.as_uri(), 'error': 'failed'}]},
            ]:
                source = temp / 'graph.json'
                source.write_text(json.dumps(graph))
                with self.assertRaises(ValueError):
                    stage.stage(source, temp / 'out')
                self.assertFalse((temp / 'out').exists())


if __name__ == '__main__':
    unittest.main()
