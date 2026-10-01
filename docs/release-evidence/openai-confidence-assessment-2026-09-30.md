# OpenAI confidence preparation — 30 September 2026

Later activation work is tracked separately in the
[30 September activation record](openai-confidence-activation-2026-09-30.md).
The inactive and local-only checkpoints below describe the assessment as run.

Status: local implementation and validation; development assessment completed
with no eligible cutoff; held-out not dispatched; no deployment or distribution.

Implementation checkpoint: local commit `e0f28db45`. A subsequent preparation
correction versions the corpus as `openai_confidence_corpus_v2` and records
source-supported automated image review explicitly. The initial implementation
had incorrectly inherited the separate formal Gemini baseline's two-person
review requirement. No live corpus or assessment existed under that version;
historical evaluator requirements are unchanged.

The
[assessment contract](../rfcs/identification-openai-confidence-assessment-2026-09-30.md)
introduces the prepared `openai_identify_vision_confidence_v1` prompt and a
separate 200-request assessment, initially capped at $10. A later owner-approved
$20 cumulative continuation is described below. Active backend selection remains
`openai_identify_vision_observed_traits_v1`. No production secret, response,
stored score or assignment was changed.

| Requirement                                               | Evidence/status                                                                                                                              |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Revised instructions/schema and production request parity | Local intercepted transport tests; historical request retained.                                                                              |
| Outcome/rank scoring and fixed decision protocol          | Synthetic tests, not biological calibration evidence.                                                                                        |
| Durable budget and interrupted resume                     | Offline runner tests; no provider calls.                                                                                                     |
| Historical/revised iOS recognition and explanatory copy   | Focused simulator tests passed, including decoded, persisted, reopened and restored boundaries.                                              |
| Confidence reference corpus                               | Frozen: 100 development and 100 held-out photos; exact category/rank quotas and offline preparation passed.                                  |
| Live collection and selected cutoff                       | 100 development attempts completed; no qualifying cutoff; 100 held-out cases unattempted. Fallback 0.95/0.60 retained without qualification. |
| Exact installed reader version/build                      | Pending owner archive/upload and device verification. Simulator tests do not satisfy this item.                                              |
| Restored historical + revised-profile device fixture      | Pending on the distributed reader with final mapping.                                                                                        |
| Backend activation                                        | Not requested by this implementation. Separate explicit target-specific deployment request required after reader evidence.                   |

Before a later activation, retain the frozen assessment/report hashes, selected
cutoff or explicit 0.95 retention decision, final candidate SHA, complete
same-SHA backend/contract/iOS CI and the installed-reader evidence above. The
existing capability header is not proof of prompt-reader support. Keep automatic
verification unqualified, preserve historical thresholds, and use the canonical
deployment runbook's recovery procedure. Audio remains outside this record.

## Local validation

The following full-surface checks cover implementation checkpoint `e0f28db45`,
without provider requests. They do not assert validation of later commits:

- Backend: `deno task test` passed 2,232 tests (11 existing ignored tests).
- Supabase tooling: `make test-supabase-tooling` passed the standard tooling,
  120 isolated evaluator tests, DTO validation and shell-contract suites. The
  seven confidence-scoring tests also passed after final report refinements.
- New transport tests passed with network and environment access explicitly
  denied; the candidate binding remains rejected by production admission and
  result handling.
- Complete `merianTests` target: 4,577 passed, zero failed/skipped, through
  `make ios-local-build`. The retained result is
  `.artifacts/local-ios/0f2dece357bb4728aa0bef31c011a733.xcresult` in the local
  checkout. It is not TestFlight or physical-device evidence.
- iOS project, event-routing, privacy, transport-security, versioning and
  migration source guardrails passed. Function config/dependency checks and the
  `identify-multimodal` entry-point type check passed. The generated deployment
  fingerprint was refreshed and diff-reviewed; active prompt selection did not
  change.
- Recursive backend/script formatting and lint passed. Markdown was formatted.

The subsequent corpus-v2 preparation correction changes scripts and their
documentation only. Its `make test-supabase-tooling` run passed 478 standard
tests, 120 isolated evaluator tests, DTO checks and shell-contract suites. After
tightening evidence-record separation, all seven confidence tests passed again
with network and environment access denied. No additional iOS or backend runtime
change was made in this correction.

An additional preparation correction binds the actual source, reference and
answerability records to their cases and image hashes in
`openai_confidence_manifest_v2`, instead of freezing only opaque record IDs. It
rechecks the evidence before each dispatch and requires reviewed prices no older
than seven days for new paid attempts. Reporting remains available after price
expiry; existing attempt claims and reservations are preserved. This does not
add an account, credential or human-review approval step.

That correction passed `make test-supabase-tooling`: 479 standard tests, 123
isolated evaluator tests, 20 inference DTO tests, 21 captured-media DTO tests
and the shell-contract suites. The eight confidence-scoring/protocol tests
passed with network and environment access denied. Recursive formatting checked
1,196 backend/script files and lint checked 998 files. These changes affect
assessment scripts and documentation, not production inference or the iOS
reader; the previously recorded iOS results have not been rerun for this
scripts-only correction.

## Reference freeze

The private packet `2026-09-30-openai-confidence-v1` passed the network-denied,
environment-denied `assign-splits` and `prepare` commands. Its implementation
source is local commit `9fad8e715`; later documentation-only changes do not
alter the frozen executable source digest. At this freeze checkpoint, no
identification requests had been made by this study.

The initial local launcher stopped at credential admission before creating a
request claim: its command omitted the required explicit denials for unrelated
environment credentials. The launcher and documented command now include the
same denied-variable set as the existing OpenAI evaluation launcher. A synthetic
credential check reproduced the missing-flag failure and passed with the
corrected flags without any network request. No key was stored and no attempt
budget was consumed by that startup failure.

Preparation inspected an intake of 504 downloaded candidate photos, excluding
identification-label leakage, edited textures, related photographic sequences
and unsupported source labels. The final 200 photos have source-supported
exact-image review, 674 linked evidence records and 74 independent diagnostic
sources. The reviewed taxonomy contains 91 canonical IDs/ranks and their frozen
synonyms. Automated review is disclosed; no independent human validation is
claimed. Source labels and provider answers were not accepted as sufficient
ground truth.

Each split contains 20 clear, 20 lookalike, 20 limited-evidence, 20 cultivated
and 20 nonbiological cases. Each of the first three categories has five plants,
five fungi, five invertebrates and five vertebrates. Limited-evidence cases
contain ten genus-only and ten reviewed unresolved references per split.
Reference totals are 120 species, 20 genus-only, 20 biological unresolved and 40
nonbiological controls. Inputs are metadata-free still photos without
description text; region/month are frozen as null. Related observation sequences
were excluded before the seeded split.

The independent-source packet retains reviewed factual cards and revision
references. Direct body-byte fingerprints were available for 64 of its 74
diagnostic sources; the other ten retain the reviewed source-card digest and
explicitly disclose unavailable later direct-body retrieval. No unavailable page
body is claimed to have been hashed. This diagnostic mixture does not represent
production traffic, and its reference readiness establishes no badge performance
or individual probability calibration.

| Frozen item        | SHA-256                                                            |
| ------------------ | ------------------------------------------------------------------ |
| Manifest           | `bccbe1811f6c45c065fe62ee79797351a7531bf2dea52180c8416487dae1db6d` |
| Corpus             | `aa6d31209cc693c1c163f2290dbd1f46996fe857169c6b1c95cedaebc6d61557` |
| Taxonomy           | `d8c63bb0b211286275c8d022c51ba4eee4af7f5b215781258beb54236c54c244` |
| Scoring protocol   | `1fa21cc7ad93be94c547894acee3f354e7abcffcd8ca2b26f91a505ba0ab948e` |
| Pricing            | `30279fcf35f293fac9185eb18a73a437f77f97d70db8d9bd979abd98a090ead7` |
| Executable source  | `e34da07fee3b9a43c0e66ccca85089b814f55a2e8000f193c93bbdeb3acca4d7` |
| Reference evidence | `73ec4a45c1df58ab99807cadc9cf5467e02dae5d99790648ade27004894e752c` |
| Request settings   | `8a87d2377868459eb55a375a2c8296efa05200d2ca64d73c9eecb9f368ff774f` |

All 200 actual request digests are retained privately. The readiness file has
`mode: live`, `referenceStatus: valid`, 200 scheduled cases and a first
reservation within budget; `dispatchAuthorized: false` records that offline
preparation itself sent no requests. It does not impose another human approval
step on the owner's approved bounded collection.

Reviewed pricing reserves $5.37288 before each sequential request, including
maximum input and reasoning/output allowances. Complete returned usage releases
unused reservation before the next request; unknown or contradictory usage
keeps it and stops dispatch. The 200-request/$10 limits are hard ceilings, not a
guarantee of complete collection. The initial prepared report recorded zero
attempts, zero settled cost, no cutoff selection and `development_incomplete`,
retaining 0.95. A stopped or incomplete assessment does not authorize budget
expansion, replacement cases or a production switch.

Remote exact-SHA CI, release archive/upload, installed-device verification and
completion of live confidence collection remain separate. This local record does
not assert that any of those steps happened.

## First attempt and accounting continuation

The first identification completed on September 30. Its normalized
identification matched the frozen reference with raw confidence 0.87. The v1
result retained no numeric usage; cost remained unknown, and the runner stopped
before a second request with `accounting_reconciliation_required`. The $5.37288
reservation is an upper allowance, not a claimed bill. Exactly one of the 200
attempts has been consumed, and no cutoff is selected.

Review found the assessment's zero-only cache-write condition rejected both
absent optional counts and valid positive counts. The actual first-response
usage cannot be reconstructed from its old journal record, so genuine provider
usage/billing evidence was required for reconciliation. The immutable result and
claim must not be rewritten or replayed.

The local correction accepts valid cache writes at the maximum reviewed input
rate, preserves absent optional counts as null, and rejects explicit malformed
or contradictory counts in the confidence-specific adapter. Historical
production adapters and identification behavior remain unchanged. New v2 results
retain numeric accounting evidence and are rechecked by the journal reader.

The owner then approved increasing the study budget. The bounded continuation
uses $20 cumulative and the original 200 attempts, cases, ordering, pricing,
prompt/settings and scoring protocol. It must bind the original manifest and
reconciled prefix to the reviewed corrected source before dispatch resumes. The
full original hashes above remain the authoritative freeze; the correction does
not silently regenerate them.

The supplied usage export and provider UI subsequently resolved the hold. The
matching UTC minute contained one request, 5,552 input tokens and 482 billed
output tokens. At the highest frozen input rate and the frozen output rate,
including reasoning, its conservative accounting allowance is **$0.03499**. This
is an upper estimate, not an invoice-exact charge or the cost of the other
requests in the daily export. The private review retains the export hash,
bounded numeric provider evidence and the original manifest/claim/result byte
hashes. All three original files remain unchanged.

At continuation preparation, the checkpoint was **one attempt consumed, no
outstanding reservation, ordinal 2 next, $20 cumulative and 200 total
attempts**. No second provider request had run at this checkpoint. Its hash is
`6db6523e63eb5dd21d882768025ad7d46503d34ea0a656a66d0c9be49e3d9772`. Replacement
executable digest:
`d7a91f633a5542b3a30d94d12cf1f578323f1a6bece1aa844f86f346983bdddd`. The source
identity records commit `9fad8e715` with the reviewed local correction present
(`dirty: true`); this is not a claim of pushed or remotely validated code.

Four focused no-network tests passed for real-adapter cache-write variants,
contradictory injected usage, continuation drift/no-replay checks and cumulative
budget accounting. The complete affected backend suite passed 2,232 tests (343
steps), with zero failures and 11 existing ignored tests.
`make test-supabase-tooling` passed 479 standard tests, 127 isolated evaluation
tests, 20 DTO tooling tests, 21 executable contract tests, and its shell checks.
The recursive formatting and lint gates, function configuration and dependency
graph checks, identification entry-point type check, changed-Markdown formatting
check, and `git diff --check` also passed. The deployment identity was
regenerated and reviewed locally; no deployment occurred. This correction
changes no Swift code; the earlier iOS evidence remains the separate reader
implementation checkpoint.

## Completed development assessment

The continuation completed the remaining 99 development attempts. The final
journal contains 100 claims/results: 99 normalized outcomes and one invalid
output, all cost-reconciled. There are no held-out claims, replacements or
retries. Conservative settled cost is **$3.512790008**, with **zero
outstanding** and the cumulative $20 ceiling unchanged.

No candidate cutoff met both the 40-Strong minimum and 95% correctness rule. The
runner stopped with `no_development_cutoff` and selected no cutoff. The 100
held-out cases were deliberately not dispatched; this is not a held-out failure.
All OpenAI display profiles retain **0.95/0.60** by fallback, without accuracy
qualification. The revised prompt remains inactive.

At 0.95, 33/37 Strong answers received correctness credit. The four other
outcomes comprise three frozen-taxonomy mapping failures and one mapped
biological identity error; they must not be described as four demonstrated
biological errors. The best precision among candidates with at least 40 Strong
answers was 40/44 (90.9%) at 0.94. See the
[results record](../rfcs/identification-openai-confidence-results-2026-09-30.md)
for Wilson intervals, fixed bins, category/rank metrics, coverage and
limitations.

An independent read-only audit reproduced the selection decision, cost sum,
denominators and continuation prefix, and verified preservation of the original
manifest/first claim/first result. Final report file-byte SHA-256:
`10e82d547acdf015df49ff100700dc5c77cf2817c80c038b0c33fffe8190e749`. The results
record retains the selection and continuation file hashes as well. No additional
paid collection is scheduled under this study. Reader archive, upload, exact
installed-version verification and separately requested backend activation
remain outstanding; the completed assessment does not authorize them.
