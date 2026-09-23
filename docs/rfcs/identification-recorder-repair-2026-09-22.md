# Identification recorder repair

Date: 22 September 2026\
Status: Synthetic recorder validation passed; live repeat awaits an unlocked Mac

The passive observer now allows the simulator logger to finish normally and
records readiness and the reason it stopped. Gemini selection, requests,
identification results and the production backend are unchanged. Native timing
diagnostics distinguish a missing header from a rejected header without
retaining its contents. The earlier
[partial live checkpoint](./identification-measured-app-benchmark-2026-09-22.md)
remains unchanged.

## Reproduced recorder failure

The original 120-second observer retained all seven synthetic benchmark events
but killed its collector after 125.033 seconds. A separate native collector
probe, with no identification or network request, emitted its readiness banner
after 0.382 seconds and exited successfully after 128.388 seconds. Its requested
timeout was also 120 seconds. The observer's five-second shutdown grace was too
short for this logger behavior.

The repaired observer uses a bounded 30-second grace, with the existing maximum
300-second requested window and 100-event cap. Its 120-second synthetic repeat
retained all seven events and closed successfully after 137.237 seconds, with
exit code zero and no forced stop. A watchdog stop remains a failure. This
explains the premature collector termination; it does not independently explain
the flower's missing events in the earlier live run.

The recorder emits `observer_ready` before UI submission, flushes each accepted
measurement, and saves fixed exit diagnostics and rejected-row counts. Raw log
rows, subprocess stderr and identifiers are discarded. A completed window still
does not establish a complete request or billing ledger.

## Timing capture

The backend and app agree on the complete thirteen-span `Server-Timing` header
in new regression fixtures. The previous live record cannot distinguish header
absence from parser rejection. The updated app therefore records an optional
fixed `timingStatus` reason; earlier records without it remain readable. The
strict header allowlist and the 1,024-byte native log budget remain enforced.
Actual provider/Edge timing capture still requires verification in the bounded
live repeat.

## Validation and evidence

The
[sanitized validation record](./identification-evaluation-evidence/2026-09-22-exploratory/recorder-validation-results.json)
retains collector outcomes and hashes. Synthetic events are excluded from every
live latency, model, cost and quality observation.

- Focused Deno tests: 41 passed across lifecycle, native-record projection and
  the Edge wrapper.
- Complete Edge suite: 2,048 passed, six database-dependent cases ignored
  because no disposable database was configured locally.
- Complete Supabase tooling, 101 deployable entry-point checks, dependency and
  configuration validation, DTO parity, formatting and lint passed.
- Complete native unit suite: 4,279 passed, zero failures or skips on a
  disposable simulator. Evidence is retained at
  `.artifacts/local-ios/75719c5ba2184e1abb2e6b3ce04d42d0.xcresult`. The existing
  benchmark simulator's account and consent state are preserved.

The diagnostic app was built and installed in place on the existing iPhone 18
Pro simulator. It is version 1.0.3, build 275, with source revision
`bcc7ef8de53cefaa04bed81cb32adf7de877bf9a`, `dirty` state, and fingerprint
`33d8197269dc7105ed6b42c3c52e85c33d8a3540c9b0a79346544ac7f76134b5`. Its build
evidence is `.artifacts/local-ios/e4d529a354b545ddbbf94d22bff11ce2.xcresult`. A
private source patch and new-file snapshot preserve the build inputs; later
evidence-document updates and the eventual commit do not change that installed
app's identity. The disposable test simulator was removed after the unit run.

No production deployment or new benchmark scan was submitted for this repair
checkpoint. Computer control reported that the Mac was locked, preventing the
live UI repeat. The authorized next operation remains one ordinary app
submission per approved photo after the Mac is unlocked, sequentially, with no
manual retries, preserving the prior runs. The missing live provider/Edge spans
remain unresolved until the new diagnostic record is observed. The
[measurement guide](../development-guides/21-identification-app-measurement.md)
owns the current recording procedure.
