"""Shared synthetic completion schema/byte vectors on an owned disposable replay.

Tests the existing SQL schema matcher and canonical digest, not a new SQL grant
or semantic admission authority. Every query is rollback-only; no fixture writes.
"""
import argparse
import json
from pathlib import Path
import time

from initial_atomic_admission_test_support import Qualification, ROOT


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    started = time.monotonic()
    q = Qualification(args.container, args.evidence_directory, 'initial-completion-contract', args.replay_manifest)
    fixture = ROOT / 'apps/ios/TestSupport/InitialCompletionFixtures.json'
    schema_path = ROOT / 'services/supabase/functions/_shared/initialAnalysis/completion-schema-v1.json'
    schema = json.loads(schema_path.read_text())
    vectors = json.loads(fixture.read_text())['documents']
    q.record['scope'] = __doc__
    for path in [Path(__file__), fixture, schema_path]:
        q.record['source_manifest'][str(path.relative_to(ROOT))] = q.digest(path)
    q.save()
    for vector in vectors:
        r, p = literal(vector['receipt']), literal(vector['projection'])
        receipt_rule = literal(json.dumps(schema['receipt']))
        projection_rule = literal(json.dumps(schema['projection']))
        checks = {
            'structural': (f'internal.initial_schema_matches({r}::jsonb,{receipt_rule}::jsonb) AND '
                           f'internal.initial_schema_matches({p}::jsonb,{projection_rule}::jsonb)', vector['structural']),
            'receipt_bytes': (f'internal.initial_canonical({r}::jsonb)={r}', True),
            'projection_bytes': (f'internal.initial_canonical({p}::jsonb)={p}', True),
            'jsonb_limit': (f'octet_length(({p}::jsonb)::text)<=65536', vector['name'] != 'jsonb_over_limit'),
            'projection_digest': (
                f"({r}::jsonb)->>'completion_projection_digest'=encode(extensions.digest(convert_to("
                f"'merian.initial-analysis.completion-projection.v1'||chr(10)||internal.initial_canonical({p}::jsonb),"
                "'UTF8'),'sha256'),'hex')", vector['name'] != 'digest'),
        }
        for label, (expression, expected) in checks.items():
            result = q.execute(vector['name'] + '/' + label, 'BEGIN; SELECT (' + expression + '); ROLLBACK;')
            if result != ('t' if expected else 'f'):
                q.record['checks'][-1].update(passed=False, result_mismatch=True)
                q.save()
                raise RuntimeError('completion SQL parity assertion failed; sanitized receipt retained')
    q.record.update(passed=True, vectors=len(vectors), wall_seconds=time.monotonic() - started)
    q.save()
    print(json.dumps({'passed': True, 'vectors': len(vectors), 'checks': len(q.record['checks'])}))


if __name__ == '__main__':
    main()
