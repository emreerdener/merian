# Fixed-context audio replay

Date: 23 September 2026\
Status: Implemented and verified locally

The Debug simulator replay menu now offers **Stage audio with fixed context**.
It prepares the same local audio through the existing replay path and attaches
`audio-minimal-v1` to that single staged item. The normal Identify action still
owns admission, durable queueing and authenticated Gemini dispatch. No provider
request or production deployment was made while implementing this slice.

The
[measurement guide](../development-guides/21-identification-app-measurement.md#fixed-context-for-foreground-audio-comparisons)
owns the exact context and operating limits. This follows the
[audio preprocessing deployment](../release-evidence/identification-audio-preprocessing-deployment-2026-09-23.md)
without changing its backend, frozen offline measurements or earlier app
results.

> **Follow-up — 23 September 2026:** The
> [profile provenance slice](./identification-audio-comparison-provenance-2026-09-23.md)
> adds measurement-v2 profile-only attestation and offline definitions of both
> processors. The original implementation and validation facts below remain
> historical. Live case/media/arm and completed-outcome binding were still
> pending at that checkpoint.

> **Subsequent follow-up — 23 September 2026:** The
> [app integration](./identification-audio-comparison-app-integration-2026-09-23.md)
> adds frozen native assignments, authenticated receipt collection and complete
> observation admission with finalization/render proof. The server configuration
> remains unset and no paid comparison has run.

## Request and lifecycle boundaries

- A staged audio item owns its profile. Admission snapshots include it, and
  mixed media, descriptions or refinement are rejected before submission.
  Clearing, replacing or cancelling a draft cannot set a global preference.
- Fixed replay clears stale context prefetch before preparation. Submission
  provides nil GPS, location, weather and capture measurements before enqueue,
  and creates no deferred-context task. Earlier already-started lookups cannot
  be undone, but their results are not consumed by this request.
- The immutable request path retains the authenticated owner and geoprivacy
  preference. It sends fixed `en`, `UTC`, month `1` and `12:00 PM` in existing
  fields. These are synthetic conditions, not an assertion about when or where
  the source was recorded. The profile name itself is not a wire field.
- Profile types and activation are gated by both Debug and simulator
  compilation. Ordinary capture, device/Release code, provider selection,
  consent, quota, timing/retry policy and server preprocessing remain unchanged.

## Recovery and comparison limits

The durable queue preserves the media and nil location/weather fields, but does
not persist the Debug context profile. Any offline, interrupted, failed or
recovered attempt is excluded from a controlled comparison, including a fresh
provider response dispatched by background recovery. Pre-dispatch queue
fallbacks say so; late pipeline failures retain the ordinary queued/error UI.

Existing measurement-v1 records cannot prove profile provenance. The next
measurement work must add tested admission of that provenance and define two
fresh, versioned processing arms before the proposed 12-attempt comparison. This
implementation alone does not make the current recorder a causal experiment.
There is no new identification-quality, provider cost or hosted-latency result.
Animal references and formal corpus counts remain unchanged.

## Verification

The focused test changes cover fixed-profile staging and cancellation, account
transition cleanup, admission snapshot changes, mixed-input rejection, nil
persisted context, ordinary capture after reset, and a fixed foreground request
through the normal live service into intercepted HTTP serialization. Payload
tests check exact fixed values and omission of accidental enrichment while
preserving ordinary request behavior. All test media and responses are
synthetic.

Verification uses Xcode 27.0 build `27A266a`, matching the repository pin, and
the checkout-local caches through `make ios-local-build`. The complete unit run
used an iPhone 18 Pro simulator on iOS 27.0 build `24A434`.

| Check                                                    | Result                                                                                                                              |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Corrected focused workspace/payload regression run       | 10 passed; zero failures or skips.                                                                                                  |
| Focused rerun after final lint-only cleanup              | 10 passed; zero failures or skips.                                                                                                  |
| Complete `merianTests` target                            | 4,299 passed; zero failures or skips. Parameterized cases produced 6,336 executions.                                                |
| Critical unit-suite and exact scan-flow result validator | Passed against the completed unit result tree.                                                                                      |
| Four existing capture UI smokes                          | All four passed on the isolated simulator; the exact-case result validator passed. See startup failures below.                      |
| Unsigned Release device compile                          | Passed with zero errors. The executable omits all four checked replay profile/type/menu markers.                                    |
| Generated project and source membership                  | `make xcodegen`, `make validate-ios-project`, and both source-membership scripts passed; generated project unchanged.               |
| Client contract and iOS guardrails                       | Edge DTO contract, event routing, privacy manifest, transport security, versioning, migration guardrails and iOS CI tooling passed. |
| Final SwiftLint run                                      | Zero violations across 1,397 files.                                                                                                 |

The first focused run had 112 passes and two failures in the new workspace tests
because they omitted the existing test-account funding setup. After correcting
that setup and synchronizing the foreground completion assertion, the focused
rerun and complete unit target passed. This changed test fixtures, not
application admission or funding rules. After the full unit and Release runs,
redundant explicit nil initializers were removed from the two
Debug-simulator-only optional profile properties. The final Debug app and all
test targets rebuilt, and the four UI smokes passed. The final focused payload
and workspace rerun also passed all ten tests.

The Release report contains three unreachable-branch compiler warnings from
constant live-context flags in the non-visual submission path, plus the two
optional-initializer lint warnings subsequently removed. The final Debug build
also reports the existing `ThreadCheckingAudioPlayer` unchecked-Sendable
warning. These diagnostics did not fail either build; this record does not claim
a warning-free compiler run.

Two runs of the UI smokes on the existing simulator failed before their seeded
screens appeared, including a run that rebuilt the UI target. A manual launch of
the same synthetic fixture showed a startup spinner matching the consent
restoration surface. Rebuilding alone did not resolve it. The same rebuilt app
and synthetic launch arguments opened the seeded analyzing Insight on a new
iPhone 18 Pro/iOS 27.0 simulator, supporting retained simulator state as the
startup blocker; the specific stored condition has not been established. All
four automated UI tests then passed on that isolated simulator. The existing
simulator's account state has not been cleared to obtain a passing result.

Local XCResult bundles are retained under `.artifacts/local-ios/`:

- First focused run: `1d10853f912549169dc4b45a7b6d8072.xcresult`.
- Corrected focused run: `99072d00db6d49d48b9f61347ccf75c7.xcresult`.
- Complete unit target: `49488d4cef294bf9af870f132e4fcd5a.xcresult`.
- Initial UI run: `59d89b6f6d0948c691e3f70e257acd20.xcresult`.
- Rebuilt UI run: `2c20fbb51ce24546bc41e4cd350faf84.xcresult`.
- Isolated UI run: `4fd5c91badf34c54b99d62e1fe40f3bd.xcresult`.
- Unsigned Release build: `7b275dee83644efb878bb39017b7b57e.xcresult`.
- Final focused run: `830cbf85ab774ba88a161ac560d9e398.xcresult`.

No physical-device test, live benchmark, hosted CI, iOS distribution or backend
deployment is claimed by this record.
