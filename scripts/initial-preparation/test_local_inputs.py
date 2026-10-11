"""Explicit local retained-input checks; not part of the portable test target."""
import importlib.util
import copy
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('artifact', ROOT / 'artifact.py')
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)


class RetainedInputTests(unittest.TestCase):
    def test_retained_archive_and_source_commit(self):
        entry = a.select_version('wav-feasibility-darwin-arm64-v1')
        source = a.REPO / '.artifacts/initial-analysis-source-archive/archives' / (a.ARCHIVE_HASH + '.json')
        files = a.verify_archive(a.read_regular(source, 2097152), entry)
        self.assertTrue(all(item['path'] in files for item in entry['inputs']))
        self.assertEqual(a.sha(a.read_bootstrap(entry)), entry['bootstrap_sha256'])

    def test_actual_input_tampering_holds(self):
        entry = a.select_version('wav-feasibility-darwin-arm64-v1')
        source = a.REPO / '.artifacts/initial-analysis-source-archive/archives' / (a.ARCHIVE_HASH + '.json')
        archive = a.read_regular(source, 2097152)
        for index in range(len(entry['inputs'])):
            changed = copy.deepcopy(entry)
            changed['inputs'][index]['sha256'] = '0' * 64
            with self.subTest(input=changed['inputs'][index]['path']), self.assertRaises(ValueError):
                a.verify_archive(archive, changed)
        for key in ['configuration_digest', 'archive_revision', 'archive_sha256']:
            with self.subTest(identity=key), self.assertRaises(ValueError):
                a.verify_archive(archive, dict(entry, **{key: '0' * len(entry[key])}))
        changed_archive = json.loads(archive)
        prompt = next(item for item in changed_archive['files'] if 'prompt' in item['path'].lower())
        prompt['base64'] = ''
        with self.assertRaisesRegex(ValueError, 'archive_digest'):
            a.verify_archive(json.dumps(changed_archive).encode(), entry)
        with self.assertRaisesRegex(ValueError, 'bootstrap_digest'):
            a.read_bootstrap(dict(entry, bootstrap_sha256='0' * 64))
        with self.assertRaisesRegex(ValueError, 'unregistered_artifact'):
            a.verify_artifact(b'tampered artifact', entry)


if __name__ == '__main__':
    unittest.main()
