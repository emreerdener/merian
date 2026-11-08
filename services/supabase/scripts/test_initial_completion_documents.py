"""Decode real local SQL completion documents across retained media variants.

Uses existing guarded synthetic journeys; no physical IO or native/API grant.
"""
import argparse
import json
from pathlib import Path
import time

from initial_atomic_admission_test_support import Qualification, ROOT
from test_initial_completion_preparation import run as legacy
from test_initial_cpm_completion import initialize
from test_initial_cpm_completion_replay import verify_documents
from test_initial_dispatch import ROLE


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--container', required=True)
    p.add_argument('--evidence-directory', required=True)
    p.add_argument('--replay-manifest', required=True)
    p.add_argument('--media-vector', type=int, choices=[0, 1, 3, 6], required=True)
    a = p.parse_args()
    started = time.monotonic()
    q = Qualification(a.container, a.evidence_directory, 'initial-completion-documents', a.replay_manifest)
    if a.media_vector == 0:
        initialize(q)
        q.execute('original_cpm_completion_for_decoder', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_complete(); COMMIT;')
    else:
        legacy(q, 'complimentary', a.media_vector, journey_only=True)
    q.record.update(passed=False, scope=__doc__, document_media_vector=a.media_vector)
    for path in [Path(__file__), Path(__file__).with_name('test_initial_cpm_completion_replay.py'),
                 Path(__file__).with_name('validate_initial_completion_documents.ts'),
                 ROOT / 'services/supabase/functions/_shared/initialAnalysis/completionContract.ts',
                 ROOT / 'services/supabase/functions/_shared/initialAnalysis/completion-schema-v1.json']:
        q.record['source_manifest'][str(path.relative_to(ROOT))] = q.digest(path)
    q.save()
    verify_documents(q)
    q.record.update(passed=True, wall_seconds=time.monotonic() - started)
    q.save()
    print(json.dumps({'passed': True, 'checks': len(q.record['checks'])}))


if __name__ == '__main__':
    main()
