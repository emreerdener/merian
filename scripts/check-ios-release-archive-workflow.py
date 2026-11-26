#!/usr/bin/env python3
"""Keep the consolidation archive lane identical to the standard archive job."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEADER = '''name: iOS Consolidation Release Archive

on:
  workflow_dispatch:
  push:
    branches: [codex/beta-release-preparation-20261126]

permissions:
  contents: read

concurrency:
  group: ios-consolidation-archive-${{ github.sha }}
  cancel-in-progress: false

jobs:
  archive-contract:
    name: Archive contract
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: Checkout reviewed source
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Verify standard archive job parity
        run: python3 -B scripts/check-ios-release-archive-workflow.py

'''


def expected(source):
    job = source.split('  ios-release-archive:\n', 1)[1].split('  production-readiness:\n', 1)[0]
    job = '  ios-release-archive:\n' + job
    assert job.count("    needs: scope\n    if: needs.scope.outputs.should_run == 'true'\n") == 1
    return HEADER + job.replace("    needs: scope\n    if: needs.scope.outputs.should_run == 'true'\n", '    needs: archive-contract\n')


def main():
    standard = (ROOT / '.github/workflows/ios-build-and-test.yml').read_text()
    candidate = (ROOT / '.github/workflows/ios-consolidation-release-archive.yml').read_text()
    if candidate != expected(standard):
        raise SystemExit('Consolidation archive differs from the exact standard archive job/header')
    print('Consolidation archive preserves standard toolchain, deadlines, assertions and artifact retention.')


if __name__ == '__main__':
    main()
