"""Portable closed-reference and runtime-ineligibility contract tests."""
import copy
import hashlib
import json
import pathlib
import unittest
from unittest.mock import patch

import preparation_reference as p

ROOT = pathlib.Path(__file__).resolve().parent
VECTOR_DIGEST = '0a2c1459c49795284ff7dd4a130b82e5446761c8bbd0084c6550b35d4f0a4add'


def wire(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def leaves(value, path=()):
    if isinstance(value, dict):
        for key, child in value.items():
            yield from leaves(child, path + (key,))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from leaves(child, path + (index,))
    else:
        yield path, value


class ReferenceTests(unittest.TestCase):
    def setUp(self):
        self.raw = p.preparation_reference(p.VALIDATED)
        self.value = json.loads(self.raw)

    def test_fixed_canonical_vector_and_domain(self):
        self.assertEqual(self.raw, (ROOT / 'fixtures/validated-wav-reference-v1.canonical').read_bytes())
        self.assertEqual(len(self.raw), 2863)
        self.assertEqual(p.preparation_reference_digest(self.raw), VECTOR_DIGEST)
        self.assertNotEqual(hashlib.sha256(self.raw).hexdigest(), VECTOR_DIGEST)
        self.assertIs(type(self.raw), bytes)
        self.assertEqual(p.decode_preparation_reference(self.raw), self.raw)

    def test_only_registered_validated_profile_can_construct(self):
        for version in ['wav-feasibility-darwin-arm64-v1', 'latest', 'edge', '', None, 1, True, {}]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                p.preparation_reference(version)
        entry = copy.deepcopy(self.value['registry_entry'])
        entry.update(artifact_sha256=None, artifact_bytes=None)
        with patch.object(p, 'select_version', return_value=entry), self.assertRaisesRegex(ValueError, 'unregistered_artifact'):
            p.preparation_reference(p.VALIDATED)

    def test_every_identity_and_option_leaf_is_bound(self):
        for path, value in leaves(self.value):
            changed = copy.deepcopy(self.value)
            parent = changed
            for key in path[:-1]:
                parent = parent[key]
            parent[path[-1]] = value + 1 if type(value) is int else value + '-changed'
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'preparation_reference_identity'):
                p.decode_preparation_reference(wire(changed))
        changed = copy.deepcopy(self.value)
        changed['registry_entry']['inputs'].reverse()
        with self.assertRaises(ValueError):
            p.decode_preparation_reference(wire(changed))

    def test_noncanonical_spellings_types_and_nested_duplicates_reject(self):
        for raw in [self.raw + b'\n', b' ' + self.raw, b'\xef\xbb\xbf' + self.raw,
                    self.raw.replace(b'"version":1', b'"version":true'),
                    self.raw.replace(b'"version":1', b'"version":1.0'),
                    self.raw.replace(b'"version":1', b'"version":1e0'),
                    self.raw.replace(b'"version":1', b'"version":1,"version":1'),
                    self.raw.replace(b'"target_sample_rate":16000', b'"target_sample_rate":16000,"target_sample_rate":16000'),
                    self.raw.replace(b'"artifact_bytes":16647', b'"artifact_bytes":16647,"artifact_bytes":16647'),
                    self.raw.replace(b'"version":1', b'"version":"1"'),
                    self.raw.replace(b'"version":1', b'"version":NaN'),
                    self.raw.replace(b'"version":1', b'"version":null'),
                    b'\xff', b'{"__proto__":{}}', b'[' * 8000]:
            with self.subTest(raw_prefix=raw[:24]), self.assertRaises(ValueError):
                p.decode_preparation_reference(raw)
        for changed in [dict(self.value, edge_eligible=True), dict(self.value, scope='production')]:
            with self.assertRaises(ValueError):
                p.preparation_reference_edge_eligible(wire(changed))

    def test_bound_and_immutable_input_before_authority_read(self):
        with patch.object(p, 'select_version', side_effect=AssertionError('must reject before registry read')):
            for value in [None, {}, self.raw.decode(), bytearray(self.raw), b'', b'x' * (p.MAX_REFERENCE_BYTES + 1)]:
                with self.subTest(kind=type(value).__name__), self.assertRaisesRegex(ValueError, 'preparation_reference_bound'):
                    p.decode_preparation_reference(value)

    def test_no_execution_or_edge_eligibility(self):
        with patch('artifact.subprocess.run', side_effect=AssertionError('no subprocess')):
            self.assertFalse(p.preparation_reference_edge_eligible(self.raw))
            self.assertEqual(p.preparation_reference_digest(self.raw), VECTOR_DIGEST)
        changed = json.loads(self.raw)
        changed['options']['target_sample_rate'] = 1
        self.assertEqual(p.preparation_reference(p.VALIDATED), self.raw)


if __name__ == '__main__':
    unittest.main()
