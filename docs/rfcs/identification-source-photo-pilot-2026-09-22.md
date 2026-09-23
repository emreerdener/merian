# Six-photo identification pilot preparation

Date: 22 September 2026\
Status: Six real photo observations prepared; offline preflight passed; no new
model calls

Subsequent execution on 22 September:
[the six-photo app benchmark](./identification-source-photo-app-benchmark-2026-09-22.md)
completed all six first submissions and measurement windows. The preparation
status and frozen records below describe the earlier offline checkpoint.

This packet prepares five source-backed provisional species references and one
non-biological control for a bounded pass through the existing app. It follows
the
[timing capture verification](./identification-timing-capture-verification-2026-09-22.md).
The
[preparation record](./identification-evaluation-evidence/2026-09-22-source-photo-pilot/preparation.json)
retains sanitized counts, hashes, exclusions and execution status. The
[pilot guide](../development-guides/20-identification-evaluation-pilot.md) owns
the collection procedure.

An automated eligibility and visual review does not provide independent
biological verification. All six references remain provisional. Formal corpus
progress remains 0/60 development and 0/240 held-out groups.

## Source evidence and coverage

The individual publisher pages identify these subjects and mark the selected
media as public domain:

- [Bison, National Park Service](https://npgallery.nps.gov/AssetDetail/aa23c7fd-4c51-4522-b0fa-120c696ecfc5).
- [Bald eagle, National Park Service](https://npgallery.nps.gov/AssetDetail/cb327339-082f-a5f5-7ba2-8ce268ff5a8a).
- [Monarch butterfly, U.S. Fish and Wildlife Service](https://www.fws.gov/media/monarch-butterfly).
- [Common sunflower, National Park Service](https://www.nps.gov/npgallery/AssetDetail/A66249F4-155D-4519-3E1F7A7361B1C110).
- [Saguaro, National Park Service](https://npgallery.nps.gov/AssetDetail/c1af9375-983c-4b1c-aa72-2feb54462a84).
- [Quartz specimen, U.S. Geological Survey](https://www.usgs.gov/media/images/quartz-crystal-3).

Private source records bind each prepared asset to its media page, permission
evidence and source-byte hash. Separate reference records bind species labels to
NPS/FWS name authorities before any prediction. The frozen taxonomy maps only
the five exact scientific names to local evaluation IDs. Other names remain
unmapped; a name lookup does not prove that the photographed features support
species identification. The mineral reference concerns non-biological handling,
not mineral naming.

| Photo coverage         | Independent groups |
| ---------------------- | -----------------: |
| Vertebrates            |                  2 |
| Invertebrates          |                  1 |
| Plants                 |                  2 |
| Non-biological control |                  1 |
| Other input groups     |                  0 |
| Held-out evidence      |                  0 |

These are mostly clear development examples. Fungi, rigorous lookalikes,
expected-unknown cases, descriptions, audio, sampled frames and paired inputs
remain uncovered. Prior training exposure to these public photographs is
unknown. This sample cannot establish formal accuracy, confidence calibration, a
reliable p95 or a provider-switch decision.

## Preparation and exclusions

Eight candidates were inspected; six were admitted. One cactus image contained
the answer printed in its pixels. One mineral image contained human hands that
confounded the non-biological control. Both were excluded before freezing; their
IDs, hashes and reasons remain in private intake history, their media was
removed, and replacements received new IDs.

Each admitted publisher derivative was decoded, oriented, converted to RGB and
re-encoded as a pixel-only PNG. No crop or resize was applied during
preparation. Published derivative dimensions vary; the 220-by-147 mineral image
is suitable only for the subject-class control, not detailed geological
identification. Raw downloaded bytes were not retained. Final decoded pixels
were inspected for people, personal data, answer text and near duplicates,
including comparison with the earlier two public-photo examples.

The six cases have separate development group IDs, opaque asset names, empty
observation text and null context. Source URLs, reference names and curation
notes are outside the model-input projection. Media and full source/reference
records remain outside Git and cloud-synchronized storage in a private folder
with mode 0700 and files with mode 0600. The owner role is `project-owner`;
retention is through 22 October 2026. Evaluation use grants no training
authorization.

## Offline verification

The existing evaluator's `preflight` passed with network and environment access
denied. It validated six groups and six provisional references, preparing twelve
native requests across the two existing Gemini profiles without dispatch.

| Frozen identity | Value                                                              |
| --------------- | ------------------------------------------------------------------ |
| Corpus          | `5bdf1624c8dd0461d571cbe1a04d30ec7a648a69465e150da0141c456cd7be2a` |
| Taxonomy        | `43ef2e7209c0ffbe008e25b3db05b63134bbd341dbd718714f53592be2cdc8c3` |
| Tooling commit  | `cb66ceb99cc018108944e0cac5654c27d21bfeba`                         |
| Source graph    | `423b50d77257f287e853a8a90b141dc7e1d14cac4d33dce0c37e0b2e116f2598` |

The checkout was dirty with unrelated CI changes. The retained source graph and
private file manifest identify the actual prepared inputs; they do not attest an
app submission's payload. A separate read-only technical review found no
contract, provenance, permission-mode or freeze-hash blockers. It does not count
as an independent biological reference review.

The twelve planned calls belong to the **direct evaluator's dry schedule**.
`dispatchAuthorized` is false, pricing and cost reservation are null, and no
live run specification or credential readiness was supplied. That runner retains
its separate source, processor, pricing and explicit budget controls.

## Next app pass

The private app plan uses the owner's existing app workflow and ordinary
charges: at most six sequential submissions, one per photo, with no manual
retries or provider override. The server selects its normal Gemini model. An
uncertain submission stops the pass rather than being silently repeated.

Use the timing-fix app and the
[passive measurement procedure](../development-guides/21-identification-app-measurement.md):
start a 120-second observer window with 30 seconds of shutdown grace, wait for
readiness, submit once, and avoid overlapping windows. Check that the intended
subject remains visible in the default app crop before confirming. If it does
not, stop before submission instead of silently changing the frozen evidence.
App crop, context and payload may differ from the prepared CLI requests.

Retain each first visible outcome alongside its separate numeric measurement,
including failures and unknown fields. Compare the five biological outcomes with
their provisional references; report contradictions and unmapped names without
treating them as verified errors. Assess the mineral control separately; a
network failure is not appropriate biological abstention. Count all six in
operational outcomes without claiming formal accuracy.

Six app submissions do not establish provider invocation counts or total billed
cost. Any primary-call estimate needs a fresh reviewed pricing snapshot under
the measurement guide; missing pricing or usage remains unknown. This
preparation made zero new app submissions or model calls and incurred no
inference spend. Repetitions require a separate recorded pass that preserves
these first outcomes.
