# Runtime quality and benchmark rules

Read this reference for iOS acceptance coverage, UI runtime checks, performance
measurements, benchmark baselines, or runtime-audit workflow changes. The
canonical contributor contract is
[`docs/development-guides/18-ios-runtime-quality-and-benchmarking.md`](../../../docs/development-guides/18-ios-runtime-quality-and-benchmarking.md).

## Reuse the executable audit

- `scripts/config/ios-runtime-audit.json` is the machine-readable selector and
  ownership manifest. Extend its existing `acceptance`, `ui`, or `performance`
  group instead of creating a competing list in prose or shell.
- `scripts/local-ios-build.py audit` owns package resolution, the single
  `build-for-testing`, ordered `test-without-building` phases, cache locking,
  cancellation, and retained evidence.
- `scripts/ios-runtime-audit.py` owns XCResult completeness checks, metric
  extraction, baseline validation, and report generation.
- `.github/workflows/ios-runtime-audit.yml` is a manual hardware-dependent audit
  lane. It supplements the required compiled iOS gate; it does not replace the
  complete `merianTests` target or authorize release.

## Choose the right layer

- Put deterministic state-machine, persistence, mapping, retry, cancellation,
  and ownership invariants in `acceptance`.
- Put only irreducibly process/UI behaviors in `ui`, using existing Debug seeds
  and production-shaped state transitions.
- Put repeatable XCTest measurements in `performance`. Keep assertions that
  establish correctness outside measured intervals where possible.
- Do not call real providers, production endpoints, or account-owned services
  from automated acceptance or benchmark tests.

## Measure honestly

- Treat timing, CPU, memory, launch, and hitch results as report-only until a
  stable dedicated runner, repeated matching samples, and a reviewed baseline
  support gating.
- Never add an arbitrary wall-clock or RSS threshold to make a benchmark look
  enforceable. Preserve raw samples, environment identity, source fingerprint,
  variance, and units from XCResult.
- Compare only matching hardware, Simulator model/runtime, Xcode, host OS,
  configuration, and workload. A toolchain or workload change requires a new
  reviewed baseline, not a silent threshold adjustment.
- Keep deterministic byte, count, retry, generation, and resource-admission caps
  in ordinary tests even when performance measurements remain report-only.

## Preserve production boundaries

- Reuse the existing test-support target and Debug/UI-test fixtures. Do not add
  release-visible launch arguments, mock providers, fake coordinates, or a
  second fixture framework.
- Use a concrete available Simulator for execution. Generic destinations prove
  compilation only.
- State explicitly which camera, microphone, codec, thermal, background,
  first-install, or retained-memory questions still require a physical device or
  Instruments.
- Retain the generated XCResult and audit report while they are needed for
  diagnosis or reviewed evidence. Never summarize an unrun phase as passed.

## Verify changes

Run the audit tooling tests for manifest, parser, evidence, and workflow
changes:

```bash
make test-ios-ci-tooling
```

For executable runtime evidence, use the checked-in wrapper and a real
destination exactly as documented in the canonical guide. Also run the focused
test directly while iterating and the complete affected target before handoff.
