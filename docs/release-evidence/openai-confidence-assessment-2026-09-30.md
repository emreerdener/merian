# OpenAI confidence preparation — 30 September 2026

Status: local implementation and validation; no deployment or distribution.

Implementation checkpoint: local commit `e0f28db45`. A subsequent preparation
correction versions the corpus as `openai_confidence_corpus_v2` and records
source-supported automated image review explicitly. The initial implementation
had incorrectly inherited the separate formal Gemini baseline's two-person
review requirement. No live corpus or assessment existed under that version;
historical evaluator requirements are unchanged.

The
[assessment contract](../rfcs/identification-openai-confidence-assessment-2026-09-30.md)
introduces the prepared `openai_identify_vision_confidence_v1` prompt and a
separate 200-request/$10 assessment. Active backend selection remains
`openai_identify_vision_observed_traits_v1`. No production secret, response,
stored score or assignment was changed.

| Requirement                                               | Evidence/status                                                                                                              |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Revised instructions/schema and production request parity | Local intercepted transport tests; historical request retained.                                                              |
| Outcome/rank scoring and fixed decision protocol          | Synthetic tests, not biological calibration evidence.                                                                        |
| Durable budget and interrupted resume                     | Offline runner tests; no provider calls.                                                                                     |
| Historical/revised iOS recognition and explanatory copy   | Focused simulator tests passed, including decoded, persisted, reopened and restored boundaries.                              |
| Formal reference corpus                                   | Pending: 0/100 eligible development and 0/100 eligible validation observations. Existing provisional packets do not qualify. |
| Live collection and selected cutoff                       | Not run. Revised mapping remains 0.95/0.60.                                                                                  |
| Exact installed reader version/build                      | Pending owner archive/upload and device verification. Simulator tests do not satisfy this item.                              |
| Restored historical + revised-profile device fixture      | Pending on the distributed reader with final mapping.                                                                        |
| Backend activation                                        | Not requested by this implementation. Separate explicit target-specific deployment request required after reader evidence.   |

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

Reference preparation has downloaded 193 candidate photos into a private
200-slot intake packet. None is counted as a frozen eligible reference yet.
Initial image review found caption leakage, near-duplicates and source labels
that do not establish species-level answerability; these require resolution
before collection. The private packet contains draft taxonomy and review
records, not a runnable frozen corpus. No identification requests or costs have
been incurred by this study.

Remote exact-SHA CI, release archive/upload, installed-device verification and
live confidence collection remain separate. This local record does not assert
that any of those steps happened.
