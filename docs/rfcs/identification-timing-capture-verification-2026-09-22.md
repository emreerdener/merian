# Identification timing capture verification

Date: 22 September 2026 (America/Chicago; observation timestamps are UTC)\
Status: Both recorder windows completed; provider/Edge timing verified for the
cat

The bounded repeat produced two finished app results and two complete
seven-event measurement sets. Both passive observers closed normally. The flower
exposed a timing-header parser limit; after a native diagnostic fix, the
remaining cat submission retained separate provider and Edge durations. Gemini
selection, prompts, generation settings and the deployed backend were unchanged.

The
[sanitized results](./identification-evaluation-evidence/2026-09-22-exploratory/production-app-timing-verification-results.json)
preserve each observation and its own app identity. The
[earlier partial measurements](./identification-measured-app-benchmark-2026-09-22.md)
and
[synthetic repair checkpoint](./identification-recorder-repair-2026-09-22.md)
remain dated historical evidence; their unknowns are not filled from this run.

## Observed results

| Case            | Visible result                      | Match label    | Total app pipeline | Provider call | Total Edge | Other Edge | Primary-attempt estimate |
| --------------- | ----------------------------------- | -------------- | -----------------: | ------------: | ---------: | ---------: | -----------------------: |
| `c0001`, flower | Rough Hawkbit, _Leontodon hispidus_ | Possible match |           27.610 s |       Unknown |    Unknown |    Unknown |            USD 0.0472475 |
| `c0002`, cat    | Long-Haired Tuxedo, _Felis catus_   | Strong match   |           23.487 s |      20.012 s |  21.3778 s |   1.3658 s |            USD 0.0413675 |

Both fresh HTTP 200 records identify the requested and returned model as
`gemini-2.5-pro`. The flower reported 2,711 prompt, 544 candidate and 2,154
thinking tokens, totaling 5,409. The cat reported 2,711 prompt, 605 candidate
and 1,701 thinking tokens, totaling 5,017. Cached and tool token counts were
unknown.

The flower's client transfer-plus-server interval was 25.635 s; the cat's was
21.930 s. Provider timing measures the awaited SDK call, including its
transport. Other Edge time is the difference between the total Edge and provider
spans, not client networking or rendering. For this cat observation, most
measured Edge time was spent awaiting the provider. One observation does not
establish a latency distribution or show that the parser fix made identification
faster.

The cost estimates are approximately 4.7 cents and 4.1 cents respectively. They
use the reviewed 22 September pricing snapshot, include thinking/output, and
apply the highest reviewed input rate without a cache discount. They cover only
the observed primary attempt. Other attempts, optional enrichment, storage,
transport, total scan spend and invoice cost remain outside this evidence.

The flower has no independently verified reference. The cat agrees with its
provisional _Felis catus_ species reference; its display name does not establish
a breed or pedigree. Neither result was manually confirmed or corrected. These
are collection checks and individual observations, not verified accuracy,
confidence calibration, p95 latency or a provider comparison.

## Recorder and timing repair

The flower observer retained all seven expected events and closed after 128.480
seconds; the cat did the same after 128.450 seconds. Each requested a 120-second
window with a bounded 30-second shutdown grace. Both reported
`window_completed`, `collector_exit`, exit code zero and no signal. This
verifies normal recorder closure on these two live windows; it does not prove
exhaustive OS logging or a complete provider invocation and billing ledger.

The flower's new `timingStatus` reported `too_many_metrics`. Its original parser
counted more than thirteen comma-separated entries and rejected the entire
projection. No raw header was retained, so the extra metric names, their source,
and whether quoted commas contributed to that count are unknown. Its provider
and Edge timings remain unknown, and the flower was not resubmitted.

The native parser now bounds the complete header to 2,048 UTF-8 bytes and 32
top-level entries. It recognizes quoted commas and escaped quotes, discards
unrelated metrics and descriptions, and validates only `provider` and
`edge_total`. Malformed or duplicate retained metrics still reject the
projection. The compact native log remains within 1,024 bytes, and the existing
record schema and backend response contract are unchanged. The cat's subsequent
record reported `timingStatus: valid` and retained both spans.

## Execution and source identity

Local Debug builds on the iPhone 18 Pro simulator running iOS 27.0 used the
ordinary production identification route. Execution used exactly two sequential
app submissions, one per approved photo, with no manual retries, provider
override or overlapping observer windows. Each recorder reported readiness
before crop confirmation. Original asset hashes were verified, and both photos
used the default crop. An original asset hash does not attest the final encoded
provider payload. The existing simulator account, consent, data and Photos
library were preserved.

Both apps were version 1.0.3, build 275, but the parser changed between cases:

- Flower: source revision `bcc7ef8de53cefaa04bed81cb32adf7de877bf9a`, dirty
  state, fingerprint
  `33d8197269dc7105ed6b42c3c52e85c33d8a3540c9b0a79346544ac7f76134b5`.
- Cat: source revision `6c7ba02ede0fa0884189f55b726bb4babf5966a5`, dirty state,
  fingerprint
  `3ad8e9f3c0e73234a78e743652cd9ac88fb93414f6e348c85148abddf213d812`.

Installed product and source hashes were checked before submission, and each
live record independently reported its matching app identity. Private source
snapshots preserve those inputs. Concurrent, separately owned CI/documentation
edits caused an initial cat build fingerprint mismatch; that build was
superseded without a scan. A stable cached rebuild was then verified. Those
unrelated files are included in the final build's whole-worktree fingerprint;
the native runtime source still matches the source tested below. Later evidence
edits and commits do not change either measured app's identity.

Both responses reported backend bundle fingerprint
`05aedfe76acc8d8bcee71f5ebf0f9de22590e79715e6cc80f1f4ab6032576558`, matching the
identification runtime source from the previously observed deployment of
`bcc7ef8de53cefaa04bed81cb32adf7de877bf9a`. This does not attest database or
environment state. No backend deployment occurred during this repeat.

## Validation and next milestone

The complete native unit target passed **4,281 tests**, with zero failures or
skips, on a disposable simulator. Regression fixtures cover extended headers,
quoted description injection, escaped quotes, the 32-entry boundary and
duplicate or malformed retained spans. Read-only parser review found no blocker.
The native test result is
`.artifacts/local-ios/4c43497f93bd413fbe11a90505d72bd2.xcresult`; the final cat
app build is `.artifacts/local-ios/1d72286bf18747d3a308079358bd52e2.xcresult`.
The disposable test device was removed. Project-resource validation, Markdown
formatting and diff checks passed. The unchanged backend and recorder were not
retested here; their complete prior checks remain in the repair checkpoint.

This closes the bounded live recorder/timing verification. The next evaluation
milestone is a reference-labeled pilot corpus using the
[collection procedure](../development-guides/20-identification-evaluation-pilot.md),
followed by repeated Gemini observations before comparing providers. More paid
submissions require their own bounded execution plan. Detailed private evidence
is retained through 22 October 2026; checked-in evidence contains no media, raw
headers, raw logs, response bodies, account identifiers, coordinates or
credentials. The
[measurement guide](../development-guides/21-identification-app-measurement.md)
owns the current recording procedure.
