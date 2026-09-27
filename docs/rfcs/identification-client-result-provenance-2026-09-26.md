# Identification client result provenance — 26 September 2026

Status: implemented and locally verified. All assignments remain Gemini.

## Behavior

All four identification routes return the same immutable execution configuration
that they save with a successful scan. Completed requests replay their original
metadata; older completed rows reconstruct it from the immutable scan column.
Absent provenance stays absent, with no inference or reconstruction from today's
assignment. Model output and client requests cannot assert this metadata.

The executable wire contract owns the optional non-null field and generated
Swift DTO. Its required nullable settings preserve explicit null through
encoding and local storage; missing required keys fail decoding. The value
contains only bounded execution configuration, never evidence, account identity
or response text. Owner history selects the existing database column and retains
raw-row quarantine and pagination. Missing legacy metadata cannot erase already
saved provenance.

V52 adds only optional `LocalScanRecord.identificationProvenanceData`. V51 was
frozen and compiled before active-model edits. All forward plans add lightweight
V51→V52; installed V51 stores use a dedicated two-schema plan. Existing V50
source graphs, account partitioning, goal hints and recovery controls remain
intact.

## Confidence compatibility

Recognized exact Gemini profiles keep their existing Flash/Pro thresholds. This
includes the previously admitted Pro audio experiment, without claiming its
scores are empirically calibrated. Legacy absence keeps existing behavior.
Unknown provider, model, profile, version, altered generation settings or
damaged present metadata cannot inherit those bands. Insight uses neutral review
guidance; candidate review stays available, score-only upsells and rewards are
suppressed, and collection/prompt decisions cannot treat an unfamiliar score as
qualified. User confirmation remains distinct from model confidence.

Public Explore suggestion projections still lack execution metadata. They are a
separate remaining activation prerequisite. This slice does not enable OpenAI,
collect permission, change protocol 3, add pricing rules, or select a provider.

## Release order and remaining gates

The existing server provenance migration must precede these Edge producers.
Their added optional field is compatible with older native clients. New native
clients accept legacy omission, but any later provider assignment must require a
client protocol that includes its entire consent/result/accounting contract.
Distribute V52 only after the startup runbook's genuine released-V51
install-over and second-launch evidence. Simulator fixtures alone cannot satisfy
that gate. Rollback must preserve immutable server metadata and the additive
database schema; do not roll an installed V52 store back to a V51-only binary.

## Verification

Completed local checks:

- All four fresh producers and completed replay: 31 tests and 120 steps.
- Complete Edge suite: 2,109 tests and 265 steps passed; six database-dependent
  tests skipped because this wire/native slice did not start a disposable
  database. No SQL migration or privilege changed here; the previous admission
  slice owns its separate full database evidence.
- Supabase tooling: 438 tests and 32 steps, 58 isolated evaluator tests and 29
  steps, 19 DTO-generator tests, 21 contract tests and all ten shell suites.
- All 101 deploy-time Edge entrypoints, isolated dependency/config checks,
  recursive formatting/lint, native project/event/privacy/transport/versioning
  gates, complete iOS CI-tooling suite and migration source guards passed.
- Outgoing V51 freeze compiled for both simulator architectures before the
  active model changed. Focused native validation passed 30 XCTest and 100 Swift
  Testing cases, including disk migration, recovery, result replay, confidence
  presentation and both private achievement projections.
- The complete native run passed all 1,366 XCTest cases. Its 2,996-case Swift
  Testing run found three source inventory assertions that needed to recognize
  the frozen snapshot and explicit Foundation dependency. Those three suites
  were corrected and rerun: all ten tests passed. No runtime behavior test
  failed; the complete suite was not repeated after these test-only fixes.
- The complete migration and startup recovery suites also passed on the oldest
  installed runtime, iOS 18; iOS 27 supplied the required modern SwiftData
  migration evidence. The minimum iOS 17.2 runtime was unavailable. Genuine
  released-V51 install-over evidence remains a distribution gate.

Independent reviews corrected required-null preservation, the existing Pro audio
experiment's compatibility, schema guard coverage and stale current-schema
documentation. The first active V52 compile found a missing achievement protocol
projection; both summary/detail snapshots now carry provenance, with a
regression test for unfamiliar scores. No paid inference, hosted mutation,
deployment or external publication is part of this slice. The existing benchmark
findings and limitations are unchanged: Gemini's app baselines and OpenAI's
photo/text pilot demonstrate working paths, but their inputs and timing
boundaries do not establish a provider winner. The next selection milestone
remains a prospective matched, qualified comparison.

## Following slices

Continue without a provider-selection decision until the infrastructure is
ready:

1. Apply the same immutable-profile compatibility rule to public AI suggestions
   and server score decisions. Public community detail should expose only the
   minimum derived interpretation metadata, preserve candidate order for unknown
   scores, and suppress unsupported score/model claims. Cover Field Trip
   progress, automatic reference-image promotion and public confidence-based
   achievements; keep explicit user confirmation distinct from an AI score.
2. Carry provider-aware meaning into Field Chat and scientific export, and make
   usage attribution/pricing read the recorded provider/model rather than infer
   Gemini from a tier. Unknown units or price evidence must stay unknown. Review
   shared cache compatibility before assigning a different provider.
3. Complete deliberate recipient-permission collection and the corresponding
   client protocol as a coherent capability. Production assignment remains
   app-owned. Published disclosures, matched held-out qualification, exact
   pricing and the authorized release remain activation gates.

The first two are implementation and deterministic validation work; they do not
require another paid pilot or an end-user model chooser. Keep audio and sampled
video-plus-audio observations on their complete qualified path.
