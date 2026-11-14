# GAC-1 bounded local qualification result

October 15, 2026. **The approved local GAC-1 checkpoint passed.** The reviewed
loader fix, validation, single offline package, denial control and conditional
20-read serial campaign completed within the fresh 20:02:14–22:02:14 UTC window.
This closes this finite local checkpoint; no additional run is needed to close
it. Activation remains disabled; AWS/160 MiB unapproved; all other limits
unchanged; auto-prompts paused.

## Candidate and validation

Reviewed source: 120-file set
`5246e1b990dadab2ca1398698cda8f11b9c72cd45e26782416fe748e8f046e4a`. Sealed
executable: 125-file set
`dd9a608d5f79e7190c0d9f299eb79c866587bb9638188f06214053fc8d96954c`. All evidence
is retained under `.artifacts/client-prepared-media/gac-1/`.

The two identical local bundle loaders now capture the primary operation error,
attempt all acquired cleanup steps in order, ignore `BadResource` only for input
close, and throw after cleanup. Ordered aggregates preserve both primary and
cleanup failures, including an original `throw undefined`. Any unsuppressed
cleanup failure prevents bundle validation and successful return. The runtime
still uses fixed native filesystem, decompression and hash operations; an
injected port interface supports fabricated-resource tests. No verifier
measurement, GAC predicate, fixture, product contract or activation path
changed.

The previous 54 passing tests were reused after verifying unchanged relevant
source and dependencies. Four new tests exercised both loaders' primary and
cleanup failures, error ordering, narrow suppression, and bounds/length/hash
validation. All four passed. Formatting, the full explicit 60-file cached/frozen
no-run type gate and staged/main lint passed. Combined retained check output is
17,159 bytes, below 32 KiB. The earlier CLI and lint failures remain historical;
they were not erased or reclassified as passes.

The single network-disabled package attempt succeeded in 13.249 seconds. Raw
bundle: 8,452,966 bytes, SHA-256
`c78b49c9c6d73a4e60989baa9566e07c25eebdea95bf30f14f8bece2f7bcb1e1`. Compressed
bundle: 1,823,296 bytes. Both fit the unchanged raw, compressed and
temporary-storage bounds. Only the two loader length/hash literals changed when
sealing. Source, executable/control and campaign reviews were separate and
exact; the campaign concurrence bound the passing control outcome.

## Control, campaign and measurements

The denial control returned 403 with zero media activity and qualified. Outcome
SHA-256: `7130a543de331742d7325957c8898e154e35f4a02634de74a6e1be9fcf3b3065`.

The campaign completed exactly case 26 followed by cases 1–20: one denial and 20
verified media reads on one observed worker, with 20 closed media bodies and
zero cancels. Two 64 KiB controls and eighteen 32 MiB reads total 604,110,848
bytes. Every size/digest, ordering, spacing and ownership check passed. Campaign
outcome SHA-256:
`093faf29c1f9451e2cf68b1bf5dfc7a1d56ad7a16d77d8e9f06ce6bbe3a9bb7c`.

The handler, driver and independent offline assessment agree on GAC-1 `pass`.
Independent and IC-1 reviewers also recomputed the comparisons from retained raw
responses. Q is the original post-cleanup/pre-return partial-proxy sample; P is
the original co-timed request maximum. The comparison threshold remains 8 MiB,
inclusive for failure/hold.

| Comparison                                      | Exact bytes |       MiB |
| ----------------------------------------------- | ----------: | --------: |
| Cohort A last-three minus first-three Q median  |   4,194,304 |  4.000000 |
| Cohort A last-three minus first-three Q maximum |  -3,866,624 | -3.687500 |
| Cohort B last-three minus first-three Q median  |    -393,216 | -0.375000 |
| Cohort B last-three minus first-three Q maximum |  -2,097,152 | -2.000000 |
| Cross-cohort Q maximum increase                 |   8,192,000 |  7.812500 |
| Cross-cohort P maximum increase                 |   2,619,368 |  2.498024 |
| Whole-schedule endpoint Q median increase       |   3,473,408 |  3.312500 |

Peak P was 40,680,581 bytes (38.796025 MiB), below the unchanged 96 MiB
partial-proxy ceiling. The legacy four-point warning occurred at case 4 and is
retained. The cross-cohort Q comparison is only 196,608 bytes below its review
threshold: it passes this contract but does not establish a durable margin for
longer reuse. `campaign-metrics.json` retains all 20 raw Q/P pairs and warnings;
`campaign-run/outcome.json` remains the authoritative input.

## Cleanup, preservation and limits of the result

Campaign collection completed in 685.252 seconds with 33,318 log bytes, inside
900 seconds plus bounded cleanup and the 96 KiB campaign log allocation. There
were no operator, runtime, diagnostic or host-journal failures. Dispatch
closure, pool cleanup acknowledgment and pool-empty receipts were ordered; EOF
was complete, no partial line remained, and process exit was the expected 15.
Control and campaign teardown each recorded successful stop/remove commands and
confirmed absence. Packaging cleanup also succeeded.

Supplemental read-only inspection confirmed all three scope-owned container IDs
absent. Two ad hoc inspection-script mistakes are retained in
`final-container-check.json`: a case-sensitive match rejected Docker's lowercase
not-found response, and a runtime receipt lookup initially used the bundle's
`id` key instead of `container_id`. These did not alter candidate receipts,
cause another cleanup operation or launch any test/runtime again.

All 115 unrelated paths remain byte/status identical. Prior source, loader,
review, window and failed-check evidence is retained with exact hashes and
recovery recipes. The final status headers have their own prefix recovery
record, preserving the exact executable candidate's document bytes. Dependencies
and old evidence were not deleted to obtain storage headroom. The 20 GiB disk
floor and existing per-root/aggregate storage reservations remain satisfied.

This is **finite local partial-V8 proxy qualification**, using synthetic
transport and the pinned runtime. It is not a leak fix or proof of indefinite
reuse, whole-worker/RSS/native memory behavior, CPU attribution, physical worker
retirement, hosted warm affinity/concurrency or full product acceptance.
Positive application teardown and container absence do not prove when native
memory was physically reclaimed during the run.

The single package, control and campaign allowances are consumed. Further work
should use this result as evidence; another test requires a separately bounded
decision. Hosted and complete-verifier resource qualification, original-media
retention, audio quality, shared-asset/recovery/deletion, native/integrated and
IC-1 product acceptance remain open. Approved deletion/export then redesign
sequencing is unchanged. No hosted access, credentials, uploads, provisioning,
deployment, push, merge, device installation or provider invocation occurred.
