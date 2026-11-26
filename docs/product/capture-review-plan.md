## November 26 — manual photo subject selection qualification

The next user journey is tap → optional corner resize/pan/zoom → Identify or
Reanalyze with the selected region preserved as evidence. Root starts from
`8c120c6e`, including the delivered Field notes and fixed toolbar geometry.

The existing submission owners already support selection: initial Capture
retains source-relative selection in its original-media journal; reanalysis
requires the composition owner and versioned focus evidence. Ordinary Debug
intentionally cannot expose this path. **HistoryTesting** is the existing
local-device scheme for the normal OAuth composition; no global flag, Auth
namespace, hosted switch, or deployment change is part of this work. Earlier
beta activation is historical evidence, not a fresh hosted compatibility
readback.

A source defect cleared selection during the transition from full-aspect preview
to crop, or after only one of overlapping pan/pinch recognizers ended. The
editor now waits for both recognizers to settle before testing crop exclusion.
Candidate results from before a framing gesture are invalidated immediately.

Final scoped validation covers 40 unique methods: 23 methods (31 expanded cases)
passed on the final gesture source, and 17 unchanged preparation, journal,
presentation, composition and prepared-pixel methods retain their direct earlier
passes. Source fingerprints match before and after each native run. Both
callback orders, overlapping recognizers, cancellation, stale candidates and
one-shot accessibility commands are covered. Normal and large-text rendered
selection states were inspected.

The initial run and diagnostic replay remain failed evidence: XCTest's requested
1.2 pinch produced an actual scale of about 2.70, correctly excluding the
selected region. The final UI fixture zooms before selecting, then verifies
source coordinates survive interior pan, rotation and zoom-out. Separately,
terminal callbacks are now idempotent after GestureState reset; their regression
tests cover both callback orders. The fixture correction is not proof that the
original requested pinch produced its nominal scale.

The Debug-only production-editor harness neither admits a submission nor changes
workspace availability. Physical-device candidate assistance and the complete
live Capture → Identify/Reanalyze journey remain device qualification, distinct
from the passing editor and durable-owner checks. Use the existing
HistoryTesting scheme and preserve the normal account/store configuration. No
hosted mutation or provider submission was performed.

Project generation/validation, strict lint, runtime audit tests and the portable
iOS CI tooling recipe passed across retained successes and focused recovery. The
device-scheme audit now tests the canonical project file rather than directory
entry casing; its configuration and entitlement assertions are unchanged. The
new Debug seed is included in the Release binary denylist. Exact receipts,
failed attempts, source manifests and reconciliation are retained under
`.artifacts/photo-selection-20261126/`.

## Current closeout — November 22, 2026

Local implementation and the authorized targeted validation are complete; the
work is ready for the user's manual-device review. No further Capture coding
blocker is known. Final reconciliation covers 80 distinct correction/consumer
methods (145 expanded cases), plus 18 retained UI journeys with explicit source
and dependency review. This is cumulative evidence, not a complete-target pass.
Installed selection gestures, physical capture and the complete release/CI gate
remain open. The successor remains inactive; no deployment or activation is
claimed.

Capture remains the sole implementation writer. History reports no additional
integration blocker; Hardening has reviewed the final endpoint, audit and
original-custody ownership changes. Earlier dated checkpoints below are retained
history, not a list of currently outstanding implementation tasks.

Native70 passed 44 tests in four suites, with all 3,476 source pins and 32
runtime fixtures unchanged. Archive SHA-256:
`aaac64f98571d784148fa2e09108a119503ac75ae91313e84fc8e564b7572010`. Native71
compiled the application but stopped on a duplicate variable in an architecture
test; zero tests ran. All 3,486 sources and 32 fixtures matched at exit; archive
SHA-256: `777c6700166b92bc49da3e315384eebdd61c9a8156e80f6298452a392d63c914`.

Native72 finished 113 tests in 18 suites with three issues: two escaped endpoint
checks exposed namespace lock retention, and one architecture assertion expected
an obsolete line break. The overall run failed. All 3,486 sources and 32
fixtures matched after exit; archive SHA-256:
`723f1e65b81bdc2c7690144cdb70d37cf196dc425e6b2f066b372921e6bfe520`. Recorder
custody, audio reappearance, result/History, execution recovery and
reverse-audit checks passed within that failed run.

The corrected endpoint object holds a weak reference to an invocation-owned
borrow. Callback success or failure revokes repository authority immediately,
cancels the exact entered child operation, then joins it before releasing
namespace files. Overlapping endpoint calls reject as busy. Hardening reviewed
this concrete implementation and found no additional source blocker. Native73
compiled the app but stopped on a throwing-expression test macro (zero tests);
all 3,486 sources and 32 fixtures matched at exit. Archive SHA-256:
`af120438ed2d3211d69b688a9aaa93e2b7ed47354221e9c190f7b3ed93ffa9e5`. Native74
completed 42 tests in eight suites with two issues: revocation blocked promotion
but did not cancel a suspended writer, allowing its next chunk to be written.
The overall run failed; all 3,486 sources and 32 fixtures matched at exit.
Archive SHA-256:
`db823d2c4a417136038b259cbb7df51220c6782544ae31d81b19fc071e9f0b4f`.

The successor registers one child operation before suspension. Callback exit
revokes authority, cancels that child and joins its termination; caller
cancellation targets the same child. Known-response settlement remains
independently joined before cancellation is reported. Hardening reviewed this
refinement. Native75 passed 10 tests in two suites (346.857 seconds), including
callback return, failure, caller cancellation, account drain, exact partial-file
recovery and known-response settlement. All 3,486 sources and 32 fixtures
matched after exit. Archive SHA-256:
`5a205ee00c0f8a3df4ea6e69a80e91f71666ea26285c904802a6db948b7faae2`. The
successor adds a combined History regression: first successful C becomes current
after A → B during execution; a later deliberate B selection survives C replay.
This follows the current approved contract and corrects stale October RFC
wording. Native76 compiled the new regression, but its individual-method filter
selected zero Swift tests. That run failed nine of 16 affected/critical UI
journeys; all 3,486 sources and 32 fixtures matched at exit. Archive SHA-256:
`42b3795175eaa63cb2f92c3bb411cd43984ff93a33471ed79b4d4600f44c7012`.

Native77 passed all eight `CompositionExecutionServiceTests`, including the
first-C/later-B replay regression. Ten of 16 UI journeys passed; the overall run
failed on six remaining UI issues. All 3,486 source and 32 fixture pins matched
at exit. Archive SHA-256:
`801eda660dff4f7af9bdacfd1c85a3e4431520beffaf423bf856da4c121251d9`. The failures
concern horizontal paging, recording completion, two Identify hit targets while
notes has the keyboard, a small notes control and empty Record goal restoration.
Native76/77 failures remain retained evidence.

Native78 qualified the single Field notes toolbar, keyboard/Identify and lower
text-area focus, both-mode goal restoration, and simulator vertical/horizontal
gesture arbitration. Fourteen of 18 UI journeys passed, as did all eight
Composition execution tests. Four UI checks failed: Finish recording did not
stage audio, the notes header still exposed 36-point native toolbar buttons, an
introduction swipe opened its destination, and a goal-navigation assertion
expected the obsolete Explore shell. Two unit tests retained old selector-width
expectations. The overall run failed; all 3,486 source and 32 fixture inputs
matched after exit. Archive SHA-256:
`fdc5bd4bba045d0ac2a414bc0fe56e2f8b701f041ff80e9c8680ff2438b35aa6`.

Native79 passed all 43 policy/Composition checks and 16 of 18 UI journeys,
including active and paused Finish recording through staging, reopening and
removal. Introduction swipes no longer navigate or page the workspace. Its
remaining assertions were floating-point noise at 44 points and an incomplete
return route: Back returns from the Field trip detail to Explore before Close
returns to Capture. The overall run failed; all 3,486 source and 32 fixture
inputs matched at exit. Archive SHA-256:
`535c8d5acc9084baf4b71b6a90ddcee19f9bc4a94a131a47e0c01548f3b452a2`.

Native80 corrects those assertions, using only a `1e-6` coordinate tolerance,
and gives the close handle, rotation and Clear selection actual 44-point button
labels. The rotation glyph remains 31 points. Both goal journeys verify the full
Back → Explore Close → hittable Capture route; this qualifies routing, not
hosted Field trip loading. Hardening reviewed the final delta without an
additional blocker. The complete `merianTests` pass found a migration registry
ordering defect and stale test expectations for UIKit ownership, canonical
sealed source ceilings, cleanup-marker ownership, exact field-note preservation,
final-media note clearing, notes-only readiness, and asynchronous original
retirement. It was deliberately interrupted after those findings to apply
corrections. It is partial failed evidence, not a complete target or UI pass.
The test process and app exited; all 3,486 source and 32 fixture pins matched.
Its archive SHA-256 is
`6acc7fcf09246048ab0d621dfcc742892e9489c50a94d46b752a48ed75a68f00`.

Native81 applies the independently reviewed corrections. Registry declaration
order is restored to V72 then V73 without changing raw values, schema shapes,
stages, or recovery dispatch. Architecture tests consume the existing canonical
physical-line policy and its explicit sealed-owner ceilings; no blanket ceiling
is raised. Draft tests retain the approved final-media clearing and
media-required submission behavior and await the existing retirement barrier
before checking file absence. Collision replacement preserves exact existing
notes. Screenshot review additionally found the Field notes heading truncated at
accessibility XXXL; it now wraps, with a focused UI assertion and visual review
still required. Strict SwiftLint on all eleven changed files, migration
guardrails, project validation, Markdown formatting and diff checks passed. Its
first launch was blocked at disk preflight before any build; removing the
disposable frame-module cache allowed the retry. Eleven focused unit suites plus
18 affected/critical UI journeys passed: 53 XCTest methods, 63 Swift Testing
tests in seven suites, and 18 UI tests, exit 0. All 3,486 source and 32 fixture
pins matched at exit. Its archive SHA-256 is
`08e687ce01718ea95be8d443decc1a3c0d98edcc0602022fa211b6103ea03864`; result:
`.artifacts/local-ios/4831c25868cc40dc9215db358a6062ea.xcresult`. Screenshot
inspection confirmed heading wrapping, standard notes/keyboard clearance and
wrapped Reanalyze layout, but exposed a clipped final typed line and caret at
accessibility XXXL despite the automated pass. Native82 gives only Field notes a
bounded internally scrolling editor within the actual available viewport,
preserving the dynamic font, bindings and legacy description editor. Its
strengthened UI assertion requires the entire focused input viewport to remain
visible and includes a longer multiline append and reopening retention. Two
Settings descriptions also stop referring to the retired Describe workspace.
Native82 passed 15 unit tests in two architecture suites and all five focused UI
journeys, exit 0. Its 3,486 source and 32 fixture pins matched after exit;
archive SHA-256:
`b05be002535a11c555cb1ac69f2a7757d6232df9cbc748bd39e1ec7f5e52311b`; result
`.artifacts/local-ios/449227cc8a6f48acb3b4ef3c95b6f294.xcresult`. The planned
`CaptureFieldNotesSessionTests` selector matched no suite: that file extends
`CaptureWorkspaceViewModelRefinementTests`. Its methods require the complete
target and are not claimed by native82. Screenshot inspection confirmed the
final typed line and caret are visible after longer multiline input at
accessibility XXXL; short wrapped input and standard keyboard layout also passed
visual inspection. Identify remains above the keyboard. Native83 attempted the
complete `merianTests` target and passed all 1,563 XCTest methods, including all
eight Field notes session methods. Later Swift Testing video checks failed; the
run was interrupted after confirmed failures. It is not a complete-target pass.
All 3,486 source and 32 fixture pins matched after actual exit; archive SHA-256:
`e0e8de8d5e4ff69f4157bda046789efca9bd0fccf83d42c23b2e9092a39d5a86`.

The successor fixes a real producer-output ownership gap: audio/video previously
minted cleanup receipts before AVFoundation created the files, and audio's
Documents output did not qualify as an existing temporary-root file. One private
producer directory now owns path-only output through actual producer exit. Audio
uses the existing bounded canonical converter directly and pins its descriptor
before streaming. Video export pins at terminal completion under an explicit
exclusive-private-writer assumption; this does not prove absence of replacement
before the first pin. Bounded exclusive promotion creates a flat staging file
with its exact descriptor-derived receipt. Failed copy/source cleanup retains
its first receipt, including same-inode mutation refusal; directory unlink and
parent sync have separate retry state. The existing FileIO owner retains failed
cleanup across caller exit, and account host shutdown waits for its retry drain.
Whole-prepare rollback uses the original receipts rather than raw path deletion.

The rotated-video test reference now renders UIImage orientation as the review
UI does; extracting cgImage alone lost EXIF orientation. The RGB tolerance
remains eight. Unsupported nested temporary-file test fixtures now use the
actual flat lease boundary. Hardening reviewed the concrete ownership
corrections. Native84 passed all 34 focused tests (seven XCTest methods plus 27
Swift Testing methods in four suites), zero failures/skips. All 3,489 source and
32 fixture pins matched after exit. Result:
`.artifacts/local-ios/16dbe758e88c49138ef4ef3a9f660e8b.xcresult`; archive
SHA-256: `8d574cc552a2d2b0d7528ff6c662bc6b445d299e7478e158da55ac3a6d4ce54d`.
Native85 was gracefully interrupted under the user's updated early-switch
direction in coordinating chat `01a12460-a2c6-7b21-abcf-d3be41331b45` (approval
turn `01a20695-45a6-7cf2-9726-2053c604734c`). The owned runner, wrapper and test
app exited before any edits. All 3,489 source, 32 fixture and 714
compiled-product pins matched. Its retained result is failed/interrupted: 7,184
methods passed, 13 had known assertion failures, one failed through
interruption, and eight were skipped. Of 6,731 recorded parameter cases, 6,730
passed and one was interrupted. Result:
`.artifacts/local-ios/5fddc4e67d6c47658248f45b5e9be75c.xcresult`.

Supported compiled enumeration identified 7,813 methods, of which 607 had not
executed. The changed-dependency review selected 41 of those for Capture
closeout: actual video Boost/extractor consumers, video upload admission and
cleanup paths, ordinary whole-observation acceptance and original holds, and
photo preparation account drain. The other 566 remain unexecuted broader
baseline evidence, including independent retained-photo/release graphs; they are
not claimed passed. The interrupted release-audit matrix has no changed
producer/legacy FileIO dependency and remains open baseline evidence. Seven
skips require iOS 27 while the simulator runs 26.5; the eighth requires the
separately enabled literal bridge. None qualifies as a pass.

Native86 applies the reviewed corrections to nine Swift test files, the exact
source-size inventory and three ownership/testing documents. Production Swift
and runtime fixtures are unchanged. Its targeted run selects 58 methods and 111
cases: the 13 failed methods, the new foreign-generation rejection, the expanded
version-7/8 nil-completion assertion, the 41 required missing methods, and two
video-to-result/History/relaunch UI journeys with and without Field notes.
Strict SwiftLint, project validation, Markdown formatting and diff checks
passed. Native86 completed with 57 of 58 methods passing, all 69 parameter cases
passing and zero skips. Both video History UI journeys passed. One Boost
composition test exposed a genuine lost soundtrack offset; the result remains
failed and all source/fixture pins matched at exit. Input archive SHA-256:
`f1ae660594b068e27b92ef1167c747c8ce5610e13537290f0017b349d9b610e6`.

The exact selection and every parameter value are retained in
`.artifacts/capture-source-admission-20261120/native86-expected-selection.json`;
the full absent/skipped/interrupted classification is in
`native85-remaining-coverage-classification.json` in the same directory.
Applicable native84/85 passes and the audited native81/82 UI evidence are reused
with explicit source/dependency mapping. There is no automatic complete-target
rerun. The mandatory complete-target release/CI gate remains open; cumulative
Capture implementation evidence is not an exact-clean release receipt.

The source review identified and corrected audio page reappearance: a reusable
page joins its retired readers before creating a new local lifetime; injected
disposable review lifetimes never reopen. Typed Capture endpoint authority now
expires at invocation exit. Recorder original custody and funding admission have
separate cohesive owners. Reviewed residual source ceilings are documented in
the
[ownership guide](../development-guides/19-code-ownership-and-refactoring.md).

The follow-up adds `CaptureScanVideoAudioTimeline`: asset-timed PCM extraction
preserves leading/internal silent edits relative to the original audio track
start, with bounded silence/copy writes, exact format validation and checked WAV
finalization. The producer remains pinned through actual native-handle disposal.
Standalone audio conversion is unchanged. New tests cover internal gaps,
oversized silence and nonzero-origin frame mapping; the original timing
tolerance and rotation assertions remain unchanged. Native87 executed 31
methods: 23 nonparameterized methods and eight parameterized methods with 20
argument children, giving 43 expanded cases. Thirty methods/42 expanded cases
passed, including the original timing regression, terminal acceptance with and
without text, and both video History UI journeys. One new oversized-silence
fixture failed during AVFoundation composition construction, before production
code; native87 remains failed. Its 3,491 source and 32 fixture pins matched at
exit.

Native88 changes only that test file: it retains the source asset, inserts two
clips around an internal gap, and asserts zero timeline origin and an oversized
actual range before invoking production. All three timeline tests passed, with
zero failures/skips; all 3,491 source and 32 fixture pins matched after exit.
Result: `.artifacts/local-ios/e90aa378e6e448abad1ffdecb7a09fb8.xcresult`; input
archive SHA-256:
`dedbba9d4c7e927740d12dbee3c93c1f4bd66c2b90f3d9379131f505c3aafbd2`. The
unchanged production preserves the native87 consumer passes. Exact method and
argument inventories, source deltas and matching simulator/configuration
identities are reconciled in
`.artifacts/capture-source-admission-20261120/final-targeted-closeout-reconciliation.json`.
The 80 distinct correction/consumer methods represent 145 expanded cases across
native86–88; this does not relabel the original failed receipts. Retained
lifecycle tests separately prove automatic History continuation; explicit
enrollment in the UI fixture is not that proof. A real nonzero-track-start asset
remains unqualified; its frame-offset arithmetic is tested.

The 18 affected/critical UI journeys passed native81; the five UI journeys
affected by the final editor change passed native82. Deployment, activation and
installed production/provider qualification are separate and have not occurred.

## Final validation and device handoff

Automated closeout requires the reconciled executed, absent, skipped and
interrupted inventory, passing targeted correction and required missing-coverage
checks, exact-source pins and an explicit dependency-based reconciliation of
reused evidence. Reassess UI coverage against subsequent changes and complete
any affected journeys or rendered comparison still missing. Do not automatically
repeat every passing test. Source and geometry tests alone do not establish
installed photo-selection gestures. The final report must name any UI path
without that evidence rather than treating a History result screenshot as
Capture review.

After automated closeout, the user may perform the physical-device checks:

- Capture a photo, record audio, and record video; switch Scan/Record without
  losing staged media. Finish recording must add one media item directly.
- Open optional photo review, tap a subject, drag selection corners, rotate,
  clear selection, and return through Field notes without losing committed
  edits. Repeat on a supported History reanalysis source.
- Submit the whole observation with Identify or Reanalyze without visiting every
  item. Check a photo-plus-audio observation and same-type multiple items within
  existing capacity; video and its companion remain one item.
- Verify notes autosave, dictation stop/return, large text, keyboard clearance,
  VoiceOver controls, confirmed discard, and goal restoration after clearing.
- Interrupt capture/playback with backgrounding and permissions; verify actual
  microphone/camera, codec, thermal and audio-session behavior on hardware.

Hosted provider/storage, deployment and activation checks remain separately
scoped. No real-provider call or deployment is authorized by this checklist.

## November 21 — live workspace handoff and preview retirement in progress

The successor connects disposable preview consumers to their retained resource
owner. Closing a preview now seals new work, joins cancellation-ignoring decode,
boost, composition and player tasks, then releases files. Confirmed removal and
submission wait for that barrier. Video-editor frame decoding also holds its
source through actual completion. Immutable source context preserves shutter and
import facts across draft restoration.

Native27 passed 35 tests in five suites covering preview lifetime, terminal
player retirement, video boost, captured source facts and the draft work host.
All 3,440 source pins and 32 runtime fixtures matched after exit. Native28
stopped at compilation on a missing SwiftUI import; that was corrected. Native29
then passed 117 XCTest workspace/review tests and seven Swift Testing
staging/reader-lifetime tests, with all 3,444 source pins and 32 runtime
fixtures verified afterward. Result:
`.artifacts/local-ios/f8429a8ace034924889d22dfa42a9e55.xcresult`. Its
exact-input archive SHA-256 is
`ead56d002cfbcaca2910e7e7a5539724f7cb537a9661025d1f087666f84afb58`.

The current successor adds awaitable recorder playback/boost drains and source
borrows that defer reset/discard deletion until the durable copy exits. It also
declares a video's original and companion together in the draft journal before
either source write, preventing interrupted retention from silently dropping
companion membership. Image ingestion converts the validated image identifier to
its actual wire MIME type. Native30 stopped at a test macro compilation error;
the corrected native31 ran 45 tests in five suites. Original-retention,
interrupted-batch recovery, playback-drain and source-reader tests passed. One
older recorder assertion expected immediate deletion instead of waiting for the
reader drain. The overall run failed; the successor corrects that expectation.
All 3,448 compiled-source pins matched before successor edits, and all 32
runtime fixtures matched after exit. Result:
`.artifacts/local-ios/d6e00e11177141ba93d2e440301c52fe.xcresult`. Archive
SHA-256: `095cd3e13b0182c5affb0de5a87602129e88ae81cc5fc02e364ea7ae480cd36e`.

Native32 and native33 failed the frozen-recovery fixture. Native33 passed seven
temporary-file lease XCTest checks and 78 of 79 Swift Testing checks. Its result
is `.artifacts/local-ios/33f37697d73b4bac9fe7390448589610.xcresult`; 3,450
source pins and 32 fixtures matched after linkage before successor edits, and
all fixtures matched after exit. Archive SHA-256:
`bc62303e048f7699caca48c2f973bb08e3becbc9de66a86fe75085f76b5e959f`.

Native34 stopped at SwiftLint before testing. Native35 compiled the connected
initial capture adapters and passed 124 XCTest checks and 79 of 80 Swift Testing
checks. The remaining frozen-projection failure exposed a read-only source-phase
omission: direct retained-original reads allowed editing, submitting and
accepted journals, but rejected preparing journals. The successor permits
preparing-phase reads with the same exact ready-source, profile, root and file
checks. It does not materialize evidence or alter frozen membership. Native36
passed all nine tests in three suites, including frozen photo/video projection
and exact Darwin descriptor ranges. All 3,453 source pins and 32 runtime
fixtures matched after exit. Result:
`.artifacts/local-ios/9989d74f88fe4c1cbdc80e0dd4e67e0b.xcresult`. Archive
SHA-256: `fad240070acb84d791625057d717771a5f98c093c5337491b2c9e8e38ab52e81`.

Native35 result:
`.artifacts/local-ios/d4f0d19cdd8e4e958ba6965f3b93683d.xcresult`. All 3,453
source pins and 32 runtime fixtures matched after exit. Archive SHA-256:
`0fea575ed7b2e332d167038c6b9da5dd9f24b9e9615fd34d062b9cc1cae60b10`. This is
retained failed-run evidence, not an aggregate pass.

The qualified composition now routes camera, picker, shared-photo inbox, video,
audio and whole-observation submission through the initial draft owner.
Account-refresh cleanup retains a complete video/audio item before retiring
producer files; restored retry bytes are retained under fresh authority before
presentation. Shared-photo inbox retirement verifies the exact original and
synchronizes unlink before manifest removal. Autosaved notes and prompt progress
are preserved across same-account presentation replacement with exact
observation identity; a real account change discards that memory snapshot. The
successor wakes a deferred external import after cold restoration exits. These
adapters compiled in native35, but their complete app journey still needs
end-to-end qualification. The ordinary-build qualification flag is unchanged.

Native aggregate account erasure remains an implementation gate. The bounded
manifest codec is descriptive evidence only. Frozen V73 compiled successfully in
freeze37 before adding V74 same-store header/page carrier storage; all 3,453
source and 32 fixture pins matched afterward. Native38 passed the full migration
suite (including both V73 disk paths), erasure graph and generic purge suites.
It failed one architecture expected-file list missing the new carrier; that list
is corrected in the successor. All 3,455 source pins and 32 fixtures matched
after exit; the overall run remains failed. Its archive SHA-256 is
`1fed41db26587dfcea2f76b4ee6b491c1764846ea56e6c651e7165ad942025f7`. Accepted
cleanup operation identity is now carried through outer coordinator scopes.
Physical retirement and terminal database cleanup remain unimplemented. Native36
passed exact Darwin descriptor-range checks using the same parser as Capture
receipts. No manifest test constitutes account-erasure completion. The automatic
History continuation has the separate native24b evidence below.

Native39 passed 19 Swift Testing checks and the sign-out/workflow XCTest suites,
but its deletion coordinator checks exposed a scope captured before the durable
accepted marker transition. The run failed (49 XCTest methods, 23 failed
assertions); all 3,456 source pins and 32 fixtures matched after exit. Result:
`.artifacts/local-ios/205511cf9a8e4b489885fe950c63d1e3.xcresult`. Archive
SHA-256: `0a0a3349a3907c204389568719b211e78288d68c8635211ca180d285a0c4d108`. The
successor commits the accepted phase before constructing an exact marker scope,
and coordinator fixtures now carry operation identities through all phases.
Native40 passed 50 XCTest methods and 13 Swift Testing tests. Native41 stopped
at new test-fixture compilation errors; native42 corrected those errors and
passed 37 XCTest methods plus 18 Swift Testing tests in four suites. All 3,459
source and 32 fixture pins matched after native42. Its archive SHA-256 is
`9f8d7d5ddcca640387a4eca8f33b17e6c16ae5bcc966381506931b90e3bc9874`. Native42
covers exact operation identity across server suspension and canonical erasure
header/page interruption recovery; it does not qualify physical erasure.
Sign-out also stops at a preexisting anonymous SDK session when no exact
destination is durably journaled. A lost destination journal write requires
recovery; it cannot adopt an arbitrary guest, link purchases, or claim fully
automatic resume. Hardening confirmed that no existing durable auth-operation
witness closes that ambiguity.

## November 21 — internal History continuation candidate

Identify remains the single whole-observation submission action. History and
Hardening found no approved requirement for a separate “Finish saving” action or
an independent consent boundary for saving that accepted result to History.
Internal enrollment and recovery therefore preserve the approved flow. This is
an implementation inference, not a new literal user approval or permission to
publish, spend on another inference, or activate the qualified build.

The successor uses the existing initial-History enrollment owner, original
baseline and durable intent. It discovers completed, funding-delivered
observations in bounded pages, retries independently of inference/funding, and
releases originals only after the native owner rechecks the acknowledged History
proof. A started release can resume offline. Account shutdown joins the actual
continuation before releasing its lease. Execution and funding timer completions
nudge recovery; scheduler startup/network sweeps also discover missed hints. The
coordinator preserves a nudge received during its active sweep. Retry sleeps
retain no account lease. Conflicts stay held without a fresh inference or silent
baseline replacement. Native24b compiled this successor and passed 39 tests in
four suites: completed History continuation, native account lifetime, erasure
graph and offline scheduler (6.656 seconds). All 3,435 source pins and 32
runtime fixtures matched afterward. Result:
`.artifacts/local-ios/43ca2541c2b945d8ac8572c3065c50b8.xcresult`. The exact
input archive SHA-256 is
`99249a11f09439483a8c670af9c4c2fb6cb7cac4b7bb1a9b2256c09e56b48423`. Native24
itself was refused by process-inspection sandboxing before Xcode; 24b used the
same pins through the authorized wrapper.

Native23 finished 38 tests with two assertions failing in one account-lifetime
fixture. The entire accepted-release suite passed, including the previous
native16 failures and all ten interrupted-release cases. The fixture incorrectly
expected native shutdown to be skipped while local cleanup failed. Shutdown
deliberately joins native work while retaining the account fence; native24b
passed the corrected expectations. Native23 evidence remains retained at
`.artifacts/local-ios/dd1410b4499a4f3196d0c0f1a0e56f01.xcresult`; its 32 runtime
fixtures matched at exit. The now-tested erasure graph fingerprint grants no
deletion authority and does not implement full-library cleanup.

## November 21 — whole-submission preparation validated; lifecycle integration open

Native20 passed 31 tests in four suites with zero issues (253.843 seconds),
including real retained-video preparation, exact companion preservation,
mixed-media ordering and selection, unchanged frozen retry, and bounded
playback-snapshot replacement rejection. Evidence is retained at
`.artifacts/local-ios/20baff91e0914ae0ad9f0d8a7ad21f6c.xcresult`. Its 3,427
source inputs and 32 runtime fixtures were verified after compilation before
successor source edits; all runtime fixtures still matched at exit. The exact
prebuild source archive remains retained.

The successor registers disposable review cleanup before preparation starts,
keeps it registered during idle review, and joins it during account shutdown.
File receipts bind the original root and exact file identity; replacement files
are preserved. Starting release permanently invalidates presentation access,
even when cleanup fails and needs retry. Independent review found that
invalidation race and verified the correction. Native21 stopped at compilation
on actor-isolated default construction. Native22 passed 37 tests across its
populated retained-resource, projection, retirement and FileIO suites. Its
individually selected account-lifetime methods did not execute: the suite was
empty. Account-lifetime coverage remains unverified. Native23 selects whole
accepted-release, account-lifetime, app-profile and erasure-state suites; it is
pending. These successor changes are not covered by native20.

**Remaining account-erasure scope is native full-library cleanup.** Source
inspection and independent History/Hardening review confirmed that
`SharedMediaInboxOwner.purgeWholeLibrary` and `SharedMediaPurgeState` support
only `p1InboxQualification`. They cannot certify the newer
`nativeAppContainerV2` inventory after Capture-only cleanup. Do not rewrite its
mode or route it through P1 mutation authority. The missing native owner must
cover photo/inbox/Capture roots and their complete ownership graph, including
V71–V73 journals, pending/retired pairs, original holds and interrupted root
creation. It needs cleanup-only accepted sign-out/deletion authority, durable
exact-identity retirement, cold recovery without a session, and an independent
typed completion verifier consumed before generic library row deletion. Keep the
existing P1 implementation unchanged. This owner is not implemented yet.

The next integrated journey remains: retain original media before producer
cleanup, restore the whole draft, optionally edit it, submit once with
Identify/Reanalyze, then recover the same accepted observation into History.
Live producer/UI wiring, native aggregate erasure, History-continuation
integration validation, and full end-to-end qualification remain open. The
native20 component pass does not establish a usable completed feature.

## November 21 — accepted funding and original-media integration in progress

Attempt 19 was refused before Xcode because sandbox process inspection was
unavailable. The authorized retry, attempt 19b, passed 36 Swift tests with no
issues, but two of its eight suite headers were empty: accepted-release and
account-lifetime individual-method selectors did not execute. The earlier claim
that it closed the two attempt-16 fixture failures is withdrawn. It qualifies
only the populated funding, restored editing, work-drain and staging suites. Its
3,425 source inputs and 32 runtime fixtures were verified and archived before
successor edits. The successor adds preparation directly from the saved
whole-observation journal and exact bounded playback-snapshot reads; those
additions are not covered by 19b.

Native attempts 13–15 stopped during compilation; their logs and result bundles
remain retained. Attempt 16 compiled and finished with 32 Swift tests in eight
suites and 11 issues across two accepted-release fixture methods. Ten cases
omitted root recovery after their intentional rejected upload closed the owner;
the successor explicitly resumes that owner before completion replay. The other
method constructed a draft-source handle from an accepted artifact before its
expected-throw assertion; the successor asserts that construction is denied.
Independent review confirmed both fixture corrections. They are not yet
runtime-qualified. Attempt 16's 3,415 source inputs and 32 runtime fixtures were
verified before archiving the compiled candidate; later source edits belong to
the unvalidated successor.

The successor separates native funding admission from the advisory meter. It
meters only owner-qualified accepted nonterminal work, including deferred Flash
and needs-attention jobs. Repeated restoration is idempotent and does not rearm
execution. Deferred resolution retains the original immutable context and saves
a separate write-once proof with effective funding; dispatch and completion
retain that proof's digest. Fresh Capture or legacy blocker custody is checked
across status/balance reads and at the save boundary. Unknown state remains
held. Waiting for funding occurs before claiming an execution attempt. Cold
restoration also reconciles the local advisory meter when a Pro resolution saved
but its acknowledgement was lost. This is no server refund, credit grant, or
purchase-policy change. Attempt 17 stopped during compilation on a missing
scan-lock argument; the successor uses the bounded settlement snapshot access.
Attempt 18 stopped during compilation in the restored-photo initializer; no
tests ran. Its 3,425 source and 32 runtime-fixture pins were verified and
archived before edits. The successor makes numeric conversion explicit and
restores a video companion from its exact retained bytes, discarding fresh
extraction. Focused funding, release, editable projection, execution-drain and
staging tests still require a passing successor run.

The candidate also requests recovery after every acceptance attempt, including
lost acknowledgement and cancellation. This is a wake hint, not submission
success or dispatch permission. Stable review item identities and explicit
journal ordering now have presentation-model support. The new editable-journal
projector reconstructs bounded upright photo previews, selected geometry, notes
and disposable audio/video copies in saved item order. Its session holds the
editing lock through reads and cleanup, and refuses frozen submissions rather
than reminting their evidence. This candidate awaits validation and live wiring.
Account erasure, automatic History continuation integration, and complete
end-to-end validation remain open. Installation and deployment are not
authorized by these component changes.

## November 21 — draft recovery and refund qualification in progress

The V72 outgoing schema was frozen and compiled before adding the V73 review
journal model; all 3,384 frozen-build source pins matched. V73 adds durable
composition storage, revision-checked edits, and source guardrails. The current
candidate atomically advances the journal with parent reservation and queue
acceptance, and persists pending/ready/discarding source state in the feature
session. A separate audited discard operation can acknowledge originals that
never reserved storage without inventing an artifact retirement. Video review
recipes now retain composing center for crop recovery; frozen video artifact
bytes remain authoritative.

Native attempts 01–03 found compile errors; attempt 04 stopped at SwiftLint
before test execution. Attempt 05 found a Swift actor-isolation error in the
session's nested source lookup, corrected by capturing an immutable source
snapshot. Attempt 06 ran journal, feature-session, migration, custody, and
History component tests against 3,392 pinned source inputs. It finished with 119
Swift tests in ten suites and three stale architecture-inventory failures; the
other selected components passed, as did 30 XCTest bootstrap/recovery tests. The
compiled source archive and all 32 runtime JSON fixtures were verified. This
failed archived candidate is distinct from the successor workspace. Exact
inventory corrections, cold journal discovery/ready promotion, final-media notes
clearing, and durable optional-review edits await successor validation. Producer
wiring, complete cold recovery, accepted-source release, and end-to-end journeys
remain open; this is not feature-completion evidence.

Attempt 07 stopped before tests at the SwiftLint `control_statement` rule; the
unnecessary guard parentheses were removed. The next candidate adds a local
`preparing` journal phase: exact final artifact IDs and output bytes are
retained under the existing Capture owner before V71 submission freeze. Cold
recovery reuses a complete ready cohort without rendering. Incomplete
preparation remains held without a parent or queue; explicit whole-attempt
retirement and repreparation are covered by the unvalidated successor below. No
provider permission comes from the preparing receipt.

Attempt 08 was intentionally stopped before tests when review found that the
revision-order check rejected prepared outputs written before their parent. The
correction binds each such member to exact immutable request and ready-stage
digests; members without that proof retain the existing revision-order rule.
Attempt 09 was refused before compilation at 19.8 GiB free; no tests ran.
Managed cleanup subsequently completed with dependency downloads and validation
evidence preserved.

The next candidate adds explicit whole-preparation abort. It records an
`abortingPreparation` journal before retiring only that attempt's derivative
files through a separate V2 authority. Originals, ordering, selection, and notes
remain held. Interrupted aborts resume the same intent; editing resumes only
after every reserved derivative is released and a full root audit proves absent
unreserved members. A compact attempt/member proof remains in the journal, so
later audits can verify old released outputs. New preparations use fresh output
identities. An unrecorded empty partial is available only through typed
abort-recovery discovery; it never becomes readable media. Cold recovery can
open an abort-only session, and lost final-save acknowledgements replay the
exact finished successor. These changes await native validation. Live producer
integration, accepted-source release/account cleanup, History retry integration,
and full end-to-end validation remain open.

Attempt 10 stopped during compilation: two new pagination helpers used the
optional SwiftData `fetchOffset` without supplying its initial zero. Both are
corrected. Its log and result bundle remain retained; no tests ran. The
successor still requires native validation.

Attempt 11 finished with 42 tests in ten suites and four issues in two methods.
Both source-reading architecture suites passed. The failed methods exposed
missing reverse validation of aborted preparation proofs and reuse of reserved
media identities before artifact rows existed. The successor validates
journal-to-member and member-to-journal abort joins and fences new reservations
against every existing parent's immutable media membership. Exact replay and
distinct drafts remain allowed. All 3,405 source inputs and 32 runtime fixtures
were verified before archiving the tested source; evidence is retained at
`.artifacts/local-ios/44d10446c7844bd9864aef9ef6cd62e8.xcresult`.

The successor also implements accepted-original release after completed result,
delivered funding and exact acknowledged V1 History baseline proof. It records a
complete parent intent before child unlink, checks completion/funding/deletion
custody on every continuation, and retains permanent member receipts. A later
selected analysis is preserved. Completed-result discovery finds pending History
or cleanup work without new inference authority. These changes passed focused
lint and independent source review; native validation remains pending. Account
erasure, live producer wiring, automatic History retry policy and end-to-end
qualification remain open.

Attempt 12 was refused before compilation at 19.2 GiB free after managed cache
cleanup. Three byte-identical immutable dependency packs in older validation
checkouts were deduplicated by verified hash, preserving every path, dependency
and validation artifact. Attempt 13 started with 3,412 distinct source inputs
and the same 32 runtime fixtures. Its selected checks cover both regressions,
accepted release, result/funding/execution recovery and source architecture.
This is an in-progress candidate, not passing or completion evidence.

The full Edge run after snapshot migration `20261121092320` exposed four
maintenance-refund regressions. Forward correction `20261121095704` preserves
only an unchanged, NULL-original, reserved-to-refunded transition under older
snapshots. All identity, token, attempt and committed-state guards still
execute. Clean migration replay passed. The refreshed catalog passed 221 files /
12,498 assertions (`capture-refund-catalog01.log`), and the complete Edge suite
passed 4,849 tests / 1,314 steps (`capture-refund-edge-full01.log`). Expanded
concurrent row-guard validation passed five tests / 17 steps
(`private-refund-race07.log`). Actual eight-argument quota-reservation versus
refund wrapper schedules passed six tests / 19 steps
(`private-refund-wrapper03.log`), including both lock orderings, stale-snapshot
refund rejection, ordinary reservation reopening, and denial of private aliases.
The preceding wrapper02 run exposed an incorrect expected error: a refunded
private alias is rejected by the earlier quota-availability guard. That test was
corrected; wrapper02 remains diagnostic evidence. The generic
privileged-routines Make target hit an inconsistent default local DB and failed;
it is diagnostic only. The complete catalog evidence above uses the explicit
clean disposable DB. No default database repair was attempted.

History and Hardening are coordinated; this chat remains the sole implementation
writer and holds the native build slot. No activation or deployment has
occurred.

## November 21 — execution recovery integration in progress

Source/session validation passed 15 tests in three suites
(`native-capture-session-tests02.log`,
`.artifacts/local-ios/8a9bb0e580f842f6806c5e033fb0c827.xcresult`); all 389
source pins matched. The accepted-Capture execution worker now has a durable
primary-dispatch marker. Once written, restart and uncertain acknowledgement can
only enter a separate completion-recovery dependency. It preserves the
observation generation and funding identity, joins account drain, and caps
automatic retries. The first execution test build found a missing optional
identity check; it was corrected. The successor native run passed 20 tests in
four suites (920.324 seconds), with all 394 source pins unchanged:
`.artifacts/local-ios/74de30dcf55d4e35845393a439e8b26f.xcresult`. The new native
completion transport passed 11 tests in three suites with 432 unchanged source
pins (`native-capture-completion-tests01.log`,
`.artifacts/local-ios/9c44e2fe65044a03a645542eb06a8529.xcresult`).

History and Hardening identified that the generic quota attempt key could allow
a second primary call after a private submission failure. The local correction
adds a permanent per-scan dispatch receipt and post-permit held behavior. The
receipt survives quota/invocation pruning; terminal source identities continue
to refuse dispatch after account/evidence erasure. Existing evidence without
this fence stays held. Clean migration replay and 26 focused catalog assertions
passed. Corrected real-SQL bridge tests cover four media combinations and prove
no new dispatch after accounting pruning. The earlier bridge used the quota
request ID instead of the original observation ID and is not dispatch-fence
evidence. The latest corrected bridge07 also exercises the actual quota-finalize
adapter and null-original/request-ID aliases. The clean current catalog passed
221 files / 12,484 assertions; 130 Edge entrypoints type-checked. Full Edge
validation against the explicit disposable database passed 4,842 tests / 1,297
steps (`capture-dispatch-edge-full02.log`). The earlier default-port run used an
older schema and is diagnostic only, as is the bridge06 timeout caused by
concurrent catalog locks. Dedicated primary-dispatch concurrency validation now
passes three tests / 11 steps (`private-dispatch-concurrency05.log`): duplicate
dispatch, both account/terminal retirement orders, and Repeatable
Read/Serializable snapshots established before private admission. Quota/commit
exercise the new entry guard; direct invocation insertion is rejected by the
earlier initial-analysis isolation guard. Fresh Read Committed controls still
dispatch once. Forward migration `20261121092320` requires a current statement
snapshot before private classification. Its clean replay/catalog passed 221
files / 12,490 assertions (`capture-snapshot-catalog01.log`). No rollout or
deployment is authorized by these changes.

`check-scan-status` now has a separate `capture-completion-v1` branch using only
the exact sealed V9 completion reader. Missing proof returns `held`, never retry
authority. Its 19 focused HTTP/status tests pass. Accepted unsealed results rely
on the existing finalization-only worker. The next native candidate connects a
single account-lifetime execution worker to the queue scheduler, stages the
accepted whole observation, reserves dispatch after authentication, and uses a
bounded joined primary transport. Recovery uses only the completion route. A
successful response settles in an explicitly joined task under the same
account/root/claim, independent of dispatch cancellation. Exact-account token
failure propagates without anonymous bootstrap, preventing recursive account
drain. Focused native validation passed 34 tests in seven suites with 3,352
unchanged source pins (`native-capture-primary-tests02.log`,
`.artifacts/local-ios/8f344a2476904de7a7308043d9dffe86.xcresult`). The
acknowledged V8 History continuation candidate reads the immutable original
association and independently validates the current selected child; it never
reenrolls or reselects the original. Its native verification remains pending.
Durable draft item/order/edit/Field Notes recovery is required before producer
wiring: source artifact recovery alone cannot reconstruct the review state.
Feature source/session composition, original-media release/account cleanup,
History enrollment policy and full end-to-end validation remain open; these
component results do not complete the feature.

## November 20 — native upload and ownership follow-through

Clean SQL replay/catalog through `20261120214900` passed 218 files / 12,432
assertions. The broader Edge suite found a route-discrimination regression:
direct V9 photo evidence was mistaken for private-stage input. Forward migration
`20261120222500` preserves an immutable private-stage origin on retained
evidence; 66 focused tests / four media steps pass after that correction. The
corrected full Edge gate passed 4,813 tests / 1,297 steps
(`private-edge-full04.log`). The subsequent catalog run encountered residual
integration fixtures; after resetting the task-owned disposable database, the
clean catalog passed 218 files / 12,432 assertions through migration
`20261120222500` (`private-catalog-clean05.log`). The earlier failed catalog is
not acceptance evidence.

The native plan codec preserves ordered roles, notes, photo geometry and actual
focus source. Server-audio IDs remain reservations, never invented local files
or hashes. The private upload transport uses one pinned account-bound attempt,
verifies exact bytes and bounded receipts, and joins task termination. Native
transport/migration and ownership validation passed 115 tests in nine suites
(`native-v72-tests08.log`; result bundle
`.artifacts/local-ios/332f3681747842b0b5d076cb434f52ee.xcresult`). V72 adds
artifact-liability storage after a successful frozen-V71 compilation; it does
not activate an owner. Artifact rows now fence legacy queue access, purge,
ordinary admission and whole-store audits, including orphaned and unsaved rows.
The later integrated recovery candidate passed 41 tests in five suites
(`native-root-integration-tests12.log`; result bundle
`.artifacts/local-ios/5eda1717d86846cca28922240a800139.xcresult`). All 13
tracked source inputs remained unchanged during that run. These checks cover
explicit feature admission, interrupted root recovery, cold reopen and artifact
request validation; they do not exercise a live mixed-media submission.

The additive capture-root journal and filesystem helper now preserve the base
profile, record exclusive directory creation and retain locks through handoff.
Missing creation receipts never authorize adopting an existing directory.
Control reads are bounded before allocation, and capture handoff checks both
held and named directory identities plus its separate marker. Interruption,
replacement, wrong-owner and oversized-control tests are included. Discovery now
retains provisional canonical prefix evidence under the existing parent/store
fence and rechecks its bytes and parent names at handoff. The base repository
can now retain the fixed extension as passive evidence and return a
recovery-only owner state. Normal inspection, mutation and dispatch remain
denied until explicit recovery uses a fresh operation grant, qualifies the empty
root and completes inspection. The base profile and markers remain unchanged.
Raw control writers are file-private alongside both filesystem owners.
Integrated crash/reopen/drain tests passed in the focused run above. Artifact
inventory, mixed-original runtime ownership, upload, atomic mixed admission and
qualified incomplete-root cleanup are still pending; root recovery alone does
not enable them.

The validated candidate adds strict per-artifact ledger reads for reserved,
writing and ready states. Saved partial and completed descriptors must retain
the same inode, and each artifact must join exactly one allocation, lease and
held reference under its original profile and root binding. Reverse aliases,
partial envelopes, unknown phases and dirty contexts are rejected. This reader
does not activate reservation, file I/O, ordinary inspection or cleanup. The
whole-store artifact audit now counts saved metadata, future stage/descriptor
headroom and reserved/materialized bytes, rejecting orphaned edges and P1
ownership aliases. `native-artifact-audit-tests04.log` passed all 12 test
methods in four suites (including parameterized cases); all six frozen source
hashes matched. Result:
`.artifacts/local-ios/58c64c9a77b345a685959398fb167a65.xcresult`. Whole-plan
persistence is still required before cohort acceptance, upload and restart can
prove complete observation membership.

The physical artifact audit passed 22 tests in four suites
(`native-artifact-files-tests04.log`; result bundle
`.artifacts/local-ios/95f85bb8948f4bbbb9b38f00d7f2abff.xcresult`). It checks
both ledger-to-file and file-to-ledger membership, hashes final bytes off the
main actor, rejects replacement, links, missing files and post-hash drift, and
preserves ambiguous empty partials without adopting them. A new invocation-local
capture accounting scope now brackets the complete app read audit with physical
verification and charges metadata/reservations once. Default ordinary/P1 and
mutation paths remain closed to capture artifacts. Scoped accounting passed 18
test methods in four suites (`native-artifact-inspection-tests02.log`; result
bundle `.artifacts/local-ios/177a68aa00674f23b335b1368edd055b.xcresult`). An
explicit repository inspection now acquires capture files under a fresh dispatch
grant and releases locks at operation exit. It leaves ordinary dispatch in
recovery-only state. Cold-reopen, repeated inspection, root-setup interruption,
account-drain and ordinary-hold regressions passed 39 tests in four suites
(`native-capture-repository-tests01.log`; result bundle
`.artifacts/local-ios/eba82c9f541143a5b63a0ed398d1cd02.xcresult`). All 20
tracked source hashes remained unchanged.

The next artifact-writer candidate saves a reservation before exclusive file
creation, saves its empty partial inode before copying, and records completion
after bounded off-main-actor I/O, exact hashing and exclusive rename. Recorded
partial/final files can resume; unrecorded partials remain held. The owner entry
is DEBUG-test-only until a durable whole-plan receipt derives exact artifact
membership. Physical byte custody does not prove media validity, source
provenance, queue acceptance or upload authority. Writer runtime03 passed 14
methods in three suites in 191.599 seconds, including eight interruption
boundaries, cold replay, changed bytes/plan refusal, duplicate role refusal and
mid-write cancellation/account drain. Evidence:
`native-capture-writer-tests03.log` and
`.artifacts/local-ios/48c9e630821549a7bab5a58de7c542a2.xcresult`; all 25 tracked
source hashes were unchanged. Attempts 01 and 02 stopped before runtime at lint
and a test-helper actor annotation respectively; both failed results are
retained.

The next `captureSubmissionV1` candidate retains the canonical complete plan,
ordered local artifact identities and root binding in V71's existing versioned
body. Its acceptance reader requires the exact complete ready cohort and later
inventory revision. The existing photo V1 codec is unchanged. Capture-aware read
audits dispatch explicitly by format, reserve missing-artifact and future
acceptance bytes, and reject unlisted children. Pending-package accounting now
includes parents with no artifact rows. Runtime02 passed 29 methods across seven
suites in 228.771 seconds, including the five-empty-parent limit,
artifact-writer interruptions and the actual legacy photo-hold
receipt/accounting host. Evidence: `native-capture-submission-tests02.log` and
`.artifacts/local-ios/39ffcafb07e4416d81867a88fb6eb10e.xcresult`; all 34 source
pins were unchanged.

The reservation implementation persists the full plan and existing durable queue
context before child writes: timestamp, persisted telemetry subset, preferred
goal, initial Field Notes and exact already-claimed funding/job metadata. It
advances the inventory revision atomically with the parent, refuses unequal
replay and reserves the entire pending package. Child writes validate saved
membership before insertion and consume the parent's missing-member reservation
without charging it twice. Both use the same capture-scoped budget owner. This
owner entry remains DEBUG-only pending producer validity and live worker
integration. Reservation runtime02 passed 20 methods across five suites in
151.135 seconds, with all 41 source pins unchanged. The later acceptance04 run
passed 28 methods across six suites in 527.525 seconds, with all 49 source pins
unchanged (`native-capture-acceptance-tests04.log`; result
`.artifacts/local-ios/41186294f99e4f388e08762281b734ec.xcresult`). It covers
atomic parent/queue/job/event/goal acceptance, interrupted-save and cold-reopen
recovery, the existing ordinary-photo acceptance regressions, exact Field Notes
seed parity, and private Identify request/preflight mapping. The common
queue-row writer retains each media owner's separate custody checks. Request
privacy and locale retain existing dispatch-time semantics; first server
ingestion freezes them for later recovery.

The next upload candidate persists a separately versioned remote acknowledgement
per artifact after local acceptance. Local queue acceptance remains available
offline. Exact saved request/file bindings and a shared server request checksum
are required; Identify readiness additionally requires every ordered member.
Remote receipts neither release originals nor prove inference completion. Future
receipt headroom is reserved for missing and locally ready artifacts. The worker
reads and rehashes the recorded inode, stages sequentially, and skips only saved
verified acknowledgements after restart. Upload runtime02 passed 23 methods
across six suites in 146.885 seconds, with all 57 source pins unchanged (result
`.artifacts/local-ios/c100b3e7f3544f3bbd7b78fcd3877eeb.xcresult`). Resume
runtime01 passed 49 methods across four suites in 326.429 seconds, with all 61
pins unchanged (result
`.artifacts/local-ios/32da5a8d00ae4ca19d4723f7a9e932b4.xcresult`). That run
qualified accepted-root reopening, exact funding and queue identity, and
capture-only dispatch readiness while ordinary operations stayed closed.

The validated composite local handoff now performs: reserve the frozen
observation, read only persisted members, materialize missing artifacts and
atomically accept the whole queue entry. Failed handoffs preserve their stable
plan and funding; a retry requalifies the retained owner. Valid reserved parents
have a separate `capturePending` role. This role can resume the same immutable
plan, but cannot upload or use ordinary/P1 mutation paths. Ready members are not
reread from draft sources. A process restart still requires an explicit
source-reader reattachment; missing source bytes are never reconstructed from
previews. Production source retention and pending-draft remediation remain open.

`NativeMediaLifetimeCoordinator` now owns the account-lifetime state previously
inside `AppDIContainer`; consumers use that owner directly. Its injected service
identities remain stable after first access. Composite handoff, pending recovery
and this ownership move passed draft runtime01: 66 methods across seven suites
in 394.325 seconds, with all 76 source pins unchanged (result
`.artifacts/local-ios/d435701618fd4ccdb867e0798130e9e3.xcresult`).

The next result candidate saves the library entry, immutable initial-result
proof and completed ingestion job in one transaction after verifying accepted
capture custody, every remote acknowledgement and the current account/attempt.
An exact replay compares the retained original proof without overwriting later
review, notes or selected analysis. History enrollment reads this proof through
an explicit capture-custody join. Queue, ingestion job and original artifacts
remain retained; ordinary cleanup cannot remove them. Result runtime02 passed 64
methods across eight suites in 366.550 seconds with 87 unchanged source pins
(`.artifacts/local-ios/d1cf8f5845dc4132985f806b858391c5.xcresult`). This
includes sealed History enrollment with retained queue custody and rejection of
custody or deletion changes during enrollment.

The follow-up candidate fences pending/malformed History selection before both
enrollment transactions. It durably retains the original funding settlement with
the result, applies effects only through a typed, expiring account-bound
handoff, and acknowledges delivery afterward. An interrupted acknowledgement can
recover from the saved receipt without a provider response, preserving later
notes, review and selected analysis. Test overrides are unavailable outside a
Debug test process. Result runtime06 passed 68 methods across nine suites in
652.051 seconds with all 94 source pins unchanged
(`.artifacts/local-ios/6c5e9dc4864b4da987e3f297c36c5a16.xcresult`). This covers
cold receipt recovery, retained user edits, and selection fencing before and
during History enrollment. Earlier compile/lint attempts supply no runtime
evidence.

The subsequent scheduler candidate adds bounded local receipt discovery and
retry before network eligibility, with a separate account-lifetime worker that
closes and joins before Auth drains. It permits exact completed-result
settlement alongside an unrelated reserved draft without widening
provider/upload dispatch. Network funding reconciliation remains separately
gated after native fences exit. Funding lifecycle runtime01 passed 49 methods
across eight suites in 178.140 seconds with 104 unchanged source pins
(`.artifacts/local-ios/7301b6c411c44fe5b370cbfb3ba0b26f.xcresult`). Production
draft-source retention, private History media hydration, cleanup and complete
end-to-end validation remain open. No production activation or end-to-end
submission is claimed.

The next source-retention candidate adds a strict `draftSourceV1` artifact
envelope using the existing V72 row fields (row schema discriminator 2). It
retains original bytes, media identity and initial camera framing before a final
submission plan exists. Ready originals bind atomically into the final ordered
plan without changing source ordinals, allocating another file or charging the
same physical bytes twice. A source-only root permits local draft recovery but
never provider dispatch. Source runtime04 passed 10 methods in three suites in
242.742 seconds with 379 unchanged source pins
(`.artifacts/local-ios/b97fee737f0649c99b10630b1193b14a.xcresult`). It covers
cold discovery and typed reads, interrupted source writes and parent binding,
mixed photo/audio adoption, final order and actual staging wire bytes.
Production producer integration, draft discard and account-erasure cleanup are
unfinished.

The next dispatch candidate permits an accepted observation to stage alongside
healthy unrelated draft sources. The canonical full-root audit runs within the
held namespace before transport and again before binding its response. The exact
target must still have accepted queue membership; pending siblings never receive
global dispatch permission. Malformed global liabilities or a changed target
remain blocked. Target runtime03 passed 11 methods in three suites in 749.076
seconds with all 380 recorded source hashes unchanged
(`.artifacts/local-ios/6d5e76471a084ef78fd166e94925fa2b.xcresult`). This covers
cold coexistence, exact target identity, changed global liabilities and target
membership before and during transport, and lost/divergent stage replies. It
grants no original release or purge authority.

The parentless-source discard candidate now records permanent exact-file
retirement intent before unlink, checks durable readback, synchronizes directory
removal and records absence before releasing physical liability. Normal source
readers, writers and final binding reject retired members. Accounting readers
retain tombstones; only released nonmembers may coexist with a later final plan.
Discard shares the scan serialization point with final binding. An unrecorded
empty partial is permitted only for inspection of the exact cleanup target,
never adoption. Native discard validation and independent review are pending.
Bound-original release, producer integration, full account purge and end-to-end
validation remain open.

The unchanged `CaptureInitialEvidencePlan` moved from the Capture feature into
Core/Data/AnalysisHistory because the network transport and storage receipt both
consume the domain contract. Its storage adapter moved into SharedMediaStorage.
The two moves preserve type names, initializers and wire bytes; no dependency or
visibility was widened. Production producer integration, History media hydration
and live submission ownership remain open.

Accepted-result pruning and dedicated server continuation are now connected in
source. Ordinary job/intent DELETE preserves accepted, unsealed, nonretired
evidence; explicit retirement and supported account/scan deletion remain valid.
The actual bind-before-prune race and V7/V8/V9 retention cases pass seven
database tests (`accepted-pruning-db05.log`). The replay scheduler's separate
private branch leases immutable accepted work without changing provider attempts
or funding. It reads an existing seal first, then recovers the accepted result
and uses the existing finalizer, with no inference dispatch. Missing evidence
stays held; lease expiry retries the same request. Four actual mixed-media
SQL/adapter journeys pass (`private-finalization-db02.log`), plus five focused
worker tests. Review identified a scan-insertion/account-retirement race;
`20261121004841` now fences the actual owned scan write and final completion.
Both race orderings and recovery/upsert after retirement pass. The complete Edge
suite passed 4,835 tests / 1,297 steps (`private-finalization-full-edge01.log`),
with recursive type checks, lint and candidate formatting passing. The clean SQL
catalog passed 220 files / 12,458 assertions through `20261121004841`, and the
privileged-routine audit passed. Tooling components passed: standard TypeScript
601 tests / 132 steps, isolated evaluator 157 / 47, isolated DTO suites 20 and
23, source-archive suite 6 / 26, and all shell suites (rerun outside the sandbox
after a PTY restriction). Strict database lint then found initializer
declarations in capture routines; the guarded follow-up `20261121012840` adds
explicit casts and removes an unused local without changing behavior or ACLs.
The final migration passed clean reset03 and catalog04: 220 files / 12,458
assertions in 394 seconds. Catalog02 exceeded the unchanged 140-second
preparation deadline during a concurrent native rebuild; the quiet final run
completed those cases in 53–57 seconds. Catalog03 selected no test files and is
not evidence. Strict lint and the privileged-routine audit pass on the final
database. Final security and performance advisors passed with warnings and no
errors. No rollout or deployment occurred.

History's read-only handoff confirms there is no existing qualified ordinary
audio/video original owner. History preparation is child-analysis-bound and must
not be used with fabricated children. Extend the registered shared-media owner
with typed source kinds, allocation/lease accounting, bootstrap/audit, account
switch/purge and release checks. The offline queue remains dispatch metadata;
its legacy Documents cleanup is not original custody. This owner integration,
submission/replay, History hydration and end-to-end validation remain open.

## November 20 integration checkpoint

The live private Identify branch now stages and retains the exact V9 graph
before provider authorization, binds the accepted result before insertion, and
completes through the existing entitlement finalizer. Frozen admission telemetry
controls first insertion; recovery preserves later privacy edits. Exact
completed-plan recovery precedes admission and survives transient job/intent
cleanup.

`private-live-db15.log` records six passing tests/four media steps: two photos,
two recordings, photo/audio and video/audio. The real handler and disposable SQL
exercise a synthetic provider, pre-bind failure/retry, strict completion, no
redispatch after sealing, changed-note/tombstone rejection, post-insert privacy
edits and cleanup recovery. No paid provider, hosted activation or native flow
was exercised. Finalization has its own bounded continuation budget; local
validation/cancellation before the bind RPC does not suppress quota retry.

The client-known capture plan now separates original/prepared image and video
uploads from reserved server-audio identities. The private SQL parser validates
that complete plan without admitting placeholder audio facts. Twenty-six focused
SQL assertions pass. The server audio staging composition reserves before
processing, binds actual output metadata before writing, and verifies all stored
outputs before marking readiness. Bound retries read the exact outputs without
reading or processing raw audio again. Sixteen focused Edge tests pass,
including plan/recipe binding, lost acknowledgements, cancellation, and stream
limits. The durable service repository and private storage adapters now exist.
Forty-six rollback SQL assertions cover reservation, binding and deletion; 48
focused Edge/monitor/adapter tests pass. The shared private-erasure worker now
accepts typed stage targets in its separate namespace; 40 rollback SQL
assertions cover ordering, namespace/backend settlement, pause and receipt
compatibility. A later clean catalog run passed 217 files / 12,385 assertions.
The retention adoption join now passes both mixed-media database cases: it
retires staging only after the exact complete retained manifest is ready.

The same private stage now has a separate client-artifact inventory. The
prepared authenticated `upload-capture-stage` route verifies client bytes and
private readback before readiness; client input cannot occupy a server-DSP role.
The database cases pass photo, photo/audio and video/audio, including consumed
writes, exact inventory, exclusive preparation and deletion. Thirty-five role
and catalog assertions pass. Eleven focused adapter/lifecycle tests and three
route tests pass. History and Hardening confirmed this private extension; public
`capture_upload` limits remain unchanged. The schema-4 begin successor and
private live Identify continuation are now connected in source. Native original
lifecycle and dispatch remain unfinished; these local checks do not activate
submission.

The isolated local database accepts nested initial manifest V9 and reader18. V9
adds the validated native photo preparation geometry, bound by the manifest
digest to both source and prepared artifact identities. V7/V8 retain their exact
meaning and digest. Seven focused SQL/Edge parity, retention, recovery and
erasure tests pass across all three versions; five reader/migration checks and
eight geometry/manifest checks pass. These are focused checks, not the complete
candidate gate. A full database run on the reused fixture database failed with
residual rows and an admission expiry; its clean disposable replay passed 214
files and 12,273 assertions. The full Edge suite then passed 4,774 tests / 1,285
steps against that owned local database. The focused V9 native run subsequently
passed 27 tests in four suites. The ordinary acceptance run also passed five
tests in three suites, including its parameterized cold-recovery,
interrupted-save, concurrent-drift and photo-hold binding cases. These passes do
not qualify the unconnected production path.

The authenticated ordinary artifact upload route uploads only one member of a
job already admitted by the existing ingestion owner. Streaming readback now
verifies hash and exact length without retaining another full original buffer;
28 focused storage/route tests with 12 steps passed. Mutable upload inputs still
require defensive snapshots. The 32 MiB artifact ceiling does not claim a 32 MiB
whole-worker memory bound; large-original memory qualification is open.

The live integration will stage client-known originals and prepared image/video
artifacts before admission, with an explicit role/association plan. The server
performs audio DSP once and binds the actual output bytes, lengths and hashes
into the final manifest before ingestion admission. Native must not invent a
prepared-audio digest. Private retention then follows admission and precedes
provider authorization. History and Hardening confirmed that no History contract
requires the new single-artifact upload route to become the client path. Public
staging describes provider inputs only. The private extension now binds
originals and prepared artifacts to one immutable generation and complete
inventory. The prepared upload route has not been deployed or connected to the
native submission path. Upload waiting must not hold a provider quota lease:
current same-request reservation replay returns in-progress until expiry. Stage
first, retain verified private artifacts under sealed admission, then authorize
inference. Already admitted work keeps its original funding and uncertainty; it
cannot be reset to pre-admission automatically.

Implementation remains open: qualified native mixed-original holds, upload,
atomic queue admission, foreground/replay dispatch, History display hydration,
terminal release, native geometry restoration and full end-to-end validation.
Native acceptance must persist funding, the exact initial-evidence expectation,
V70/V71 records, queue job/event and reference counters together under the
original owner. Legacy queue gates remain closed to these rows; do not bypass
them or add records after a legacy save.

Geometry preserves upright-source selection separately from prepared-image
focus. A still recipe with no crop means full-aspect preparation, not a centered
square. Camera-center framing has separate restore semantics. Unchanged review
must retain the exact prepared bytes and focus; source reframing must use a
qualified original owner. Do not infer missing transforms for existing V7/V8
results. These are technical corrections; no new product interaction is needed.

# Capture workspace, media review, and Field notes

Status: implementation authorized in the coordinating Capture chat on 2026-11-15
after the scoped History/Hardening handoff; successor work is in progress, not
qualified or released. Product intent was reconciled 2026-11-14 with the
[approved Notion capture plan](https://app.notion.com/p/b5fbf299f78083c3887381c13ff5ea5d).
Notion owns approved product intent; this document translates it into workspace
and review work packages, integration boundaries, and planned acceptance. It
does not establish implementation, qualification, ownership transfer, or
release.

## Continuation — ordinary original-size and reader parity

History confirmed the remaining size mismatch: native photo originals allow 32
MiB each and 64 MiB per cohort, while the prepared initial-evidence V7 contract
capped each source image at 5 MiB. The successor uses nested evidence manifest
V8, distinct from the existing outer baseline snapshot V8. It preserves V7
canonical digests and historical bounds. Prepared images and video frames still
share the 5 MiB provider budget; display derivatives stay local.

The candidate adds sequential source-owner retention, reader17 negotiation,
role-aware private media receipts, and native decoding of the shared fixtures.
Only verified V8 source-image membership admits the larger read. Reader16 stays
V7-only. Retention reservations, accepted-result recovery, original completion
proofs and erasure retain their existing owners. Unit checks pass; full SQL and
native qualification of this successor is pending. No live submission fence or
rollout gate has been opened.

Remaining implementation connects native atomic queue admission, qualified
original reads/uploads, whole-observation submission, strict finalization,
History readback and terminal original release. These prepared seams are not an
end-to-end completion claim.

## Continuation — durable source admission

The source-admission implementation now binds the whole observed media set to
locked asset/session ownership and retains its canonical retry identity outside
mutable job/intent rows. Alternate writers cannot downgrade or replace that
identity. Deletion erases the private recovery payload; settled account merge
preserves metadata while permanently retiring the old source admission. The
existing active-work merge restriction remains. Focused catalog and concurrent
writer checks pass; full candidate qualification is in progress under
`.artifacts/capture-source-admission-20261120/`.

The collector is still not installed in live submission. Remaining code joins
the canonical receipt to provider preparation, verified promotion, typed
finalization, History retention and original-media release. Native end-to-end
validation follows that integration and requires the shared build slot. This
remains implementation work, not a manual-testing handoff.

## Continuation — authenticated complete source collection

The prepared collector now reads the whole staged observation using the server's
read-only R2 signing configuration. It preserves exact image/audio/video order
and audio MP4/raw video parity, derives MIME/length/digest from bounded
responses, and returns the same retained bytes for later provider preparation.
No partial observation escapes on failure. It enforces request and operation
deadlines, actual streamed size and aggregate image limits, and cancels rejected
or late bodies. No live route or SQL admission uses it yet.

Focused validation passes 25 tests / 16 steps, including the existing snapshot,
intent and outbound-deadline checks. Independent review found no blocker. Full
backend validation passed 4,745 tests / 1,279 steps with zero failures on the
explicitly owned local replay on port 57742. Complete tooling, all four route
type checks, DTO/configuration/dependency, formatting and lint checks passed.
Evidence belongs to `.artifacts/capture-source-collector-20261120/`. SQL sealing
and all-writer replay protection are the next implementation step. Hardening and
the independent writer audit require a durable admission seal before
promotion-cohort creation: mutable job/intent rows can disappear and cannot be
the sole no-downgrade witness. Exact replay must recover the original canonical
proof; changed or omitted proof conflicts even after those rows are recreated.
Private recovery payload and minimal terminal identity have separate erasure
responsibilities, with explicit account/scan deletion and merge handling. A
freely settable transaction-local flag is not admission authority. Preserve
scheduler bookkeeping and contraction to non-resumable state without permitting
reseal. The source/lock map is retained with the evidence. Original-media
holds/release, finalization, History and native end-to-end validation remain
open. This is still code work, not a manual-testing handoff.

## Continuation — retained server source snapshots

Prepared `captureSourceEvidence.ts` now owns bounded private snapshots for
staged image, audio and raw-video bytes. It copies complete membership, backend
and bytes before yielding, derives SHA-256/length from those copies and exposes
photo/audio provider inputs from the same retained content. Returned audio
buffers are isolated copies. The internal intent builder accepts only the
process-local handle, verifies exact complete ordered image/audio/video keys,
rejects inline mixtures and freezes proof-bearing intent before awaits.
Snapshot-bound input rejects raw HTTP proof-shaped fields; legacy input still
ignores unknown fields and cannot populate this interface.

The transient observations envelope has its own version 1; the sanitized intent
remains version 3. This does not certify where caller-supplied bytes were read,
seal database ownership, or change persisted legacy versions. No route supplies
the new handle yet. The next code must connect bounded authenticated media
reads, SQL checksum/seal admission and every alternate intent writer, then
recover exact saved identities before fresh normalization. Preserve the existing
initial retention trigger, account/owner/scan and job-before-intent lock order,
and inline staged-asset finalization checks. Hardening accepted the separately
versioned envelope direction subject to those constraints.

Focused validation passes 13 tests / 16 steps. Independent review found no
blocker; canonical kind-order and exact subarray tests were added. The full
backend run passed 4,736 tests / 1,279 steps but failed one outbound-deadline
source check after the next collector was added during the run. It is retained
as failed evidence; the corrected collector and snapshot interface are being
validated together below. Tooling and all four route type checks passed.
Evidence and next SQL field/lock mapping belong to
`.artifacts/capture-source-evidence-20261120/`. No SQL or iOS source changed and
no native slot or hosted action occurred. Original holds/release, finalization,
History and full user journeys remain incomplete; continuation remains active.

## Continuation — bounded source transport cleanup

The live shared image resolver now applies remaining aggregate image capacity
while streaming each staged object and cancels every unread concurrent response
on early return or exception. The shared media-budget reader also cancels
header-rejected bodies, including audio. This closes a resource-ownership gap
before source-proof admission; it does not establish immutable source identity,
persist checksums, install the prepared promotion adapter, or lift any route
fence. No SQL, native build or hosted action is involved.

Focused synthetic validation passes 19 tests / nine steps, covering successful
ordered bytes, failed fetch/status/read, header/chunk/aggregate limits,
exhausted capacity with empty or nonempty next input, and cancellation failures.
Independent review found no blocker. Final full Edge validation passed 4,730
tests / 1,263 steps with zero failures on the explicitly selected owned replay;
complete tooling, route type checks, DTO/configuration/dependency, formatting,
lint and Markdown checks passed. The first full run used the default local
database by mistake, failed on missing schema and skipped proof suites; it is
retained as failed evidence. The clean rerun used port 57742. Evidence and
continuation belong to `.artifacts/capture-media-read-20261120/`. The existing
source-proof admission, original holds/release, finalization and History work
remain required. Capture remains the sole writer and automatic continuation is
active.

## Continuation — saved-result recovery before upload refresh

The live photo, audio and mixed-media handlers now attempt exact-owner completed
result recovery before rejecting retired staging keys after identity merge. This
avoids asking for new uploads when the original observation is already saved.
Without a saved result, the existing `scan_media_restage_required` rejection
still applies. Recovery failures and foreign sealed evidence fail closed; they
never fall through to storage, quota, admission or provider work. The current
result-reader protocol gate remains authoritative.

The actual handler regression matrix covers stored and reconstructed results,
sealed results after ingestion-job loss, missing results, unavailable recovery
and foreign sealed ownership across all three media handlers. Focused result
response tests pass (four tests / 77 steps, including 21 new cases). The full
Edge run passed 4,728 tests / 1,254 steps with zero failures. Type checks for
all three routes, DTO/configuration/dependency checks, formatting and lint
passed. The first tooling run correctly rejected stale generated bundle
fingerprints; they were regenerated with the checked-in generators and
diff-reviewed. Final tooling verification passed. Evidence belongs to
`.artifacts/capture-retry-recovery-20261120/`.

This is a live retry-path correction, not completion of submission integration.
Server byte proofs and checksum admission, finalizer/retirement integration,
original-media holds/release and full History/selection/mixed-media validation
still require code. No native build or hosted action is involved.

## Continuation — bounded promotion composition

The next November 20 increment implements `_shared/capturePromotionDb.ts`: fixed
service RPCs now compose complete-cohort registration, per-I/O authority, the
actual byte verifier and monotonic receipt persistence. A fresh operation
registers the complete ordered inventory before transferring one selected
member. Recovery uses only retained destination authority, a bounded GET and
receipt; it survives asset/job/intent loss without fresh registration or PUT.
Inputs, backend and dependency functions are captured before awaits. See the
[canonical composition contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md#november-20--prepared-promotion-service-composition).

Independent read-only review found no blocking issue. Focused validation passes
31 unit/storage tests and five actual-service-role SQL composition cases. The
latter uses a rollback-bound SQL shim and synthetic storage, not hosted S3,
PostgREST authentication or committed crash recovery. The first full Edge run
passed 4,725 tests but failed two existing outbound source-audit checks: the new
frozen fetch alias did not match the audited callback. The implementation now
freezes a copied dependency object while preserving the exact reviewed callback;
no safety audit was weakened. All 35 unit/storage/outbound-audit tests pass.
Full affected-surface validation passed: 4,727 Edge tests / 1,233 steps, zero
failures, plus the complete tooling, DTO, configuration/dependency, formatting
and lint gates. Exact source hashes and passing/failed logs are retained in
`.artifacts/capture-promotion-composition-20261120/`. All 565 source and owned
replay migration hashes remain unchanged from the preceding validated increment.
No database replay/catalog rerun is required by a schema change in this slice.

This closes the bounded adapter/byte-verifier composition step only. No route
imports it. The missing production staged checksum/source-proof admission is
still the first installation prerequisite; synthetic fixture checksums do not
solve it. Next: extend existing begin-ingestion with exact server source proofs
and retry equality, then typed logical finalizer binding versus retirement,
physical cleanup, original holds/release, atomic admission and full History,
restart, selection and mixed-media journeys. Capture remains the sole writer; no
iOS change or native slot is involved. Automation remains active, and no hosted
action or product-scope change occurred.

## Continuation — retained destination verification

The November 20 successor adds exact retained-cohort destination recovery after
source/job/intent loss and a monotonic verification receipt. It never reopens a
PUT or grants source deletion, binding or original release. Later target,
source, account or scan retirement preserves prior evidence while denying new
reads/receipts. The narrow registration wrapper resolves server job identity
without direct ledger SELECT grants. The
[canonical recovery contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md#november-20--retained-destination-verification)
owns the interfaces and limits.

Fresh byte-matched 565-migration local replay, 40 catalog assertions and nine
concurrency schedules pass. Independent review found no blocker. The initial
race harness incorrectly expected pre-scan tombstoning to wait; it now asserts
the existing exact busy rejection and retries after receipt commit. SQL behavior
was not changed for that correction. The clean full catalog rerun passed all 211
files / 12,198 assertions. The first catalog/Edge runs overlapped on one local
database and produced fixture deadlocks plus a synthetic activation conflict;
those failed runs remain retained and are not passing evidence. The sequential
full Edge rerun passed 4,710 tests / 1,233 steps, zero failures, in 5m12s. The
full tooling suite, 588 migration-contract tests across 152 files, strict
public/internal database lint, privileged-routine audit, DTO/config/ dependency
checks, Edge format/lint and Markdown checks also pass. Advisors retain 103
security and 79 performance warnings, with no errors. These results qualify the
prepared SQL increment, not end-to-end submission.

Exact source hashes, review disposition and passing/failed evidence are retained
at `.artifacts/capture-destination-verification-20261120/`. The final aggregate
logs are `catalog-full02.log` and `edge02.log`; the clean replay is
`replay02.log`. All work remains uncommitted on baseline
`ac8f1737dadf2e7319681a2ae019ab806faf540d`. Validation processes have exited;
the owned disposable database remains on port 57742. No native build slot was
acquired.

The runtime trace found a preceding admission gap: `createStagedScanMediaAssets`
does not populate `checksum_sha256`, while exact promotion registration requires
that saved checksum. Establish a server-verified immutable source content
receipt/checksum before installing the promotion adapter; a client-declared
checksum alone is not byte evidence. No ordinary upload-complete endpoint
currently owns this. The proposed integration point is the existing
`begin_scan_ingestion` boundary: collect bounded server image/audio/video proofs
before fresh begin/provider, persist them against complete locked staged rows
and require exact equality on retry. Confirm request/evidence identity and
legacy compatibility before changing this shared RPC. The ordinary
`identify-multimodal` caller still uses legacy `promoteSafeMedia` COPY and
staging deletion. Merely adding another helper would not change that flow.

Hardening's read-only review adds required installation constraints: recover
completed/uncertain operations before any fresh staging reads; the provider and
promotion must consume the verified snapshot or immutable version rather than
independently fetching a mutable key; acquire account-retirement before
owner/scan locks; atomically seal the complete source identity/length/type/role
and admission; reject changed retries without provider invocation. Versioned
requests missing proof fail closed, historical legacy records are not inferred,
and raw-video reads share the total request/retained-byte budget. A checksum
column alone does not close these requirements. Keep the strict route guard
until the integrated path is qualified.

Hardening confirmed that a separate promotion reread is acceptable when it
checks exact source/backend identity, length, type and the frozen digest, then
writes those same privately retained bytes with no later refetch or server COPY.
Provider preparation independently consumes its verified retained snapshot.
Mismatch/uncertainty holds the original operation without resealing, replacement
or provider retry. This permits separate buffers with identical verified bytes;
it does not require one shared buffer across both operations.

Next: close that source-receipt gap, then compose the narrow database RPCs with
the actual bounded byte verifier, including unknown write/receipt outcomes and
immutable input/backend snapshots. Complete typed logical cohort proof and
atomic binding versus retirement through the existing finalizer, physical
destination cleanup, original-media holds/release, atomic queue/job/event
admission and History/restart/mixed-media end-to-end qualification. No iOS
source changed or native slot was acquired. The automation remains active; no
hosted action or runtime activation occurred.

## Overnight continuation — immutable promotion cohort

The November 20 successor now seals complete ordered storage membership and
logical request identity before member writes. The prepared cohort stores the
exact job/intent IDs, server-owned manifest/request checksums, intent schema,
media keys/counts/sessions and each asset's kind/role/order. A partial/reordered
cohort cannot be registered, and an already-issued unbound write cannot be
adopted. Exact retries preserve the original seal and consumed write authority;
job/intent loss or replacement cannot erase or rebind that identity.

Every fresh member action locks and validates all member sources and operations.
A changed peer blocks the whole cohort. The expanded writer inventory confirms
that begin, legacy claim and legacy intent recording take owner/scan locks
before changing the projection. Unfenced replay/Edge lifecycle updates stay
within the eligible statuses; completion/terminal transitions use fenced
routines. Active ingestion blocks account merge; after fenced settlement, merge
preserves the old cohort and consumed write while retiring all old-owner
destinations.

The applied 563rd migration needed four explicit empty-value casts for strict
lint. The separate forward repair preserves its behavior; the fresh byte-matched
564-migration replay passes. Focused validation passes 67 catalog assertions,
six observed multi-session commit schedules, the runtime lifecycle writer
exclusion test, strict public/internal database lint and privileged-routine
audit. All 210 catalogs / 12,158 assertions passed. The complete tooling gate
passed on frozen source after an initial fingerprint failure caused by
concurrent test edits. The first full Edge run failed only the two new cohort
transport fixtures (JSON array encoding and privileged fixture inspection); all
four standalone/cohort acknowledged/lost-write cases pass after those fixture
repairs. The final full Edge rerun passed 4,709 tests / 1,233 steps with zero
failures in 5m12s. Security/performance advisors retain 103/79 warnings, with no
errors. Independent read-only review found no blocker. No iOS changes or native
build slot are involved. Evidence is retained at
`.artifacts/capture-promotion-cohort-20261120/`.

The real-role transport test also exposes an adapter prerequisite: ordinary
`begin_scan_ingestion` returns server checksums and sessions, but not the job
ID, and service role cannot directly SELECT the ledger. The future adapter needs
a narrow RPC-produced job identity or registration entry point under the
existing fences. Do not broaden table grants or use a mutating claim solely to
read. The fixture's administrative setup is not an installed runtime identity
provider.

This is prepared registration and freshness, not typed logical-slot proof,
durable verified outcomes, a finalizer, physical cleanup or installed runtime
submission. The seal cannot itself prove still-photo/video-frame or
standalone-audio/companion semantics. Next: persist exact destination
verification and provide retained-identity recovery after source/job loss
without another PUT, then integrate typed cohort binding versus retirement
through the existing finalizer. Original holds/release, atomic admission and
end-to-end History and mixed-media qualification remain open. Product decisions
and exclusions are unchanged.

## Overnight continuation — destination-only verification

The November 20 continuation adds `verifyCapturePromotionDestination` to the
prepared storage owner. After an issued write, a later invocation can
reauthorize and hash the exact destination without rereading mutable staging,
retrying PUT or deleting either object. It shares the transfer's immutable
binding/backend snapshot, bounded transport and strict length/MIME/SHA-256
validation. Missing, mismatched or uncertain reads remain held; late responses
are cancelled. The result is only point-in-time content evidence, with no
claimed write by this invocation and no durable completion, binding, visibility
or release authority.

This deliberately preserves SQL's live staged-asset requirement and consumed
write check. It is not historical recovery after asset promotion/deletion and is
not a runtime cutover. The focused 25-test run passes against the retained owned
replay, including actual SQL denial before write authorization, recovery of an
unknown PUT response without another write, and denial after retirement.
Independent read-only review found no blocker. The final full Edge suite passed
4,704 tests / 1,233 steps, zero failures, in 5m28s. The complete Supabase
tooling gate passed, including synthetic PTY tests with approved local access.
Edge format/lint, DTO contracts, 128 function configs/dependency graphs,
Markdown format and diff checks passed. SQL source is unchanged; this checkpoint
reuses the prior byte-matched 562-migration owned replay and its database
qualification. No iOS source changed and no native slot was acquired.

Evidence and exact source hashes are retained at
`.artifacts/capture-destination-recovery-20261120/`. `focused01.log`,
`edge01.log` and `tooling01.log` are the passing runs. All changes remain
uncommitted on baseline `ac8f1737dadf2e7319681a2ae019ab806faf540d`. The owned
database remains `/tmp/merian-capture-focus-cclz8208`, container
`supabase_db_merian-capture-focus-cclz8208`, port 57742. Validation processes
have exited. History and Hardening received the scoped checkpoint and reported
no competing operations. No hosted action or end-to-end completion is claimed.

The next schema increment remains the sequence below. Read-only tracing located
its authoritative pre-scan cohort in `scan_ingestion_jobs`: bind the exact job
ID and manifest checksum, media kind/ordinal in the ordered media-key arrays,
asset role/order and ordinary-ingestion consumer. Validate under the existing
scan advisory lock without adding a job-row lock after user locking. The
manifest must contain the source exactly once and the asset's session must
belong to the job. Copy the immutable logical request/cohort seal into durable
promotion authority; a replaceable job row is not that authority. Job expiry,
replacement, deletion or changed manifest must never reset write permission,
rebind an operation or discard recovery/retirement obligations. Validate the
server-owned stored checksum rather than substituting a caller-computed seal.
Finalization must validate the entire sealed cohort through its existing
transaction owner. Typed initial-evidence generation remains a later
admission/History concern, not a registration substitute.

## Overnight continuation — durable promotion authority

The November 20 successor adds the prepared database owner in
`20261120084313_prepare_capture_promotion_authority.sql`. Registration reserves
one immutable operation and destination per exact backend/source. Fresh service
RPC authorization rechecks the staged asset, checksum and unretired capability
under the account/user/scan/asset/source lock order, then permanently consumes
one destination-write authorization. A lost response, lease expiry or exact
registration retry cannot permit a second write. Source retirement propagates to
the separately retained destination obligation in the same transaction.

Destination claims/absence observations are independent of staging cleanup and
survive asset/owner cascades. Negative HEAD is only a point-in-time observation;
there is no completed/GC transition. Independent review identified that direct
asset deletion or status change alone does not retire either capability. The
catalog now proves fresh I/O is denied after deletion and exact explicit target
abandonment still works. Future draft-clear/failure integration must perform
that abandonment; this increment does not imply automatic physical cleanup.

The focused promotion catalog now passes 86 assertions, including stale-token
reacquisition, and the earlier focused storage/SQL run passed 21 Edge tests. The
five multi-session schedules cover duplicate write authorization, account intake
and target abandonment in both committed orders, observing exact backend
blocking. Review-requested source-retirement assertions are included. On the
corrected byte-matched 562-migration replay, all 209 catalogs / 12,091
assertions, the five schedules, strict database lint (zero findings),
privileged-routine audit and 585 migration-contract tests across 150 files pass.
The complete Supabase tooling suite passed with approved synthetic PTY access
after the sandbox-restricted attempt; no paid calls occurred.
Security/performance advisors passed the repository fail-on-error policy with
103/79 warnings, which remain visible rather than being described as clean. The
final full Edge run passed 4,699 tests / 1,233 steps with zero failures in
5m11s. The updated SQL/Edge evidence parity test passed, including all nine
session-setting combinations. Edge format/lint, Markdown format and diff checks
passed.

Evidence and final source hashes are retained at
`.artifacts/capture-promotion-authority-20261120/`. `db-lint01.log` retains the
original failed lint; `db-lint03.log` is the clean final replay. `tooling01.log`
retains the sandbox PTY failure and `tooling02.log` the successful suite.
`catalog-full02.log`, `races03.json` and `edge02.log` are the final corrected
candidate results. All changes are uncommitted on baseline
`ac8f1737dadf2e7319681a2ae019ab806faf540d`. The retained owned disposable
database is `/tmp/merian-capture-focus-cclz8208`, container
`supabase_db_merian-capture-focus-cclz8208`, port 57742. Its validation
processes have exited. No native slot was acquired; no hosted action occurred.

The first strict database lint run found nine pre-existing volatility warnings,
so that validation checkpoint was not clean. Forward migration
`20261120100002_correct_capture_validator_volatility.sql` replaces only the
constant V3 provenance JSON builder with an equivalent JSONB literal, preserving
its immutable validator and immutable metrics caller. It changes only
`initial_evidence_contract`'s volatility annotation to STABLE, matching its JSON
construction/encoding dependencies; its body and typed digest are unchanged.
Catalog dependency inspection found four provenance CHECK consumers and no
immutable/index/generated/constraint consumer of the evidence helper.
Independent review agreed with this scoped repair. Four focused catalogs (20
assertions) and strict lint with zero findings passed. The evidence parity test
now also checks nine timezone/DateStyle combinations. The migration contract
file was renamed to `capturePromotionAuthorityMigration.test.ts` so the required
migration gate discovers both new static contracts. Final validation uses a
fresh byte-matched 562-migration replay; the earlier 561-migration evidence is
superseded.

Hardening independently found no blocker in this prepared scope. Installation
still requires sealed role/ordinal/logical-consumer binding and transactional
bind-versus-retire arbitration. The current live staged-asset checks
intentionally cannot recover historical outcomes after asset promotion/deletion;
that needs a separate exact recovery owner. Cleanup adapters must mint a fresh
claim token on every invocation. The catalog additionally checks expired and
stale-token observations after reacquisition. The five race schedules do not
constitute a complete scan/merge/finalization lock inventory.

The next implementation is the durable runtime adapter and exact recovery,
physical destination erasure owner, and final binding that serializes with
retirement. Then complete prepared-derivative cleanup, draft-reference removal
while original holds remain, durable terminal release, atomic admission, and
result/History enrollment/restart. Existing live guards and diagnostic worker
quarantine remain intact. No native slot was acquired; iOS source is unchanged.
No deployment or end-to-end completion is claimed. The preceding storage-only
checkpoint below is historical evidence; its then-missing SQL owner is now
prepared, not installed into production composition.

### Next integration sequence

1. Prepared ordered storage cohort registration is implemented above. Before
   final binding, additionally validate typed logical media-slot semantics
   against the sealed request. Neither the eleven-field storage binding nor the
   request-identity seal alone is finalization authority.
2. Add monotonic verified-outcome persistence and a destination-only recovery
   path. Registration/source read/first write retain strict staged-source
   checks; post-write verification uses the stored operation identity and
   permanent retirement/owner/scan fences. It must never reread staging to issue
   another PUT, including after a lost authorization response.
3. Extend `complete_scan_ingestion_finalization` through its existing owner:
   validate the entire sealed promotion cohort and bind verified targets in the
   same transaction as scan/job/asset completion. Explicit abandonment must not
   erase a bound target; scan/account terminal retirement retains its authority.
   `initialEvidence` envelope sealing consumes this proof after finalization.
4. Connect failure/draft-clear asset lifecycle to explicit abandonment, with a
   narrowly defined exemption for the reviewed successful bind transition.
   Install bounded destination cleanup using independent fresh-token claims.
   Merge retires old-owner authority; it never transfers permission to continue.
5. Prove role/order/cohort mismatch denial, missing-asset exact recovery,
   unknown-write read-only recovery, incomplete/reordered cohort rejection, and
   scan/account/merge retirement versus late bind before runtime cutover. Then
   continue the client hold/admission/History work above.

This is a technical implementation sequence, not additional product scope or
activation approval. The next migration must be forward-only; the prepared
reservation migration has already been applied to the owned disposable replay.

## Overnight continuation — verified promotion bytes

The prepared `capturePromotionStorage.ts` primitive addresses the mutable
staging-key race: it verifies the exact bounded source length, MIME and SHA-256,
retains a private byte snapshot, and sends that snapshot through one conditional
destination PUT. It never invokes server-side COPY against a key that can still
receive issued PUTs. Fresh injected durable-operation authorization is required
before each GET/PUT. Backend and complete operation binding are frozen before
awaits. Destination readback verifies actual bytes; an uncertain write remains
held without retry, readback or deletion. One shared deadline bounds the work,
including dependencies that ignore cancellation and late response disposal.

Independent review found that unrestricted signer-added headers could change
ACLs, tags or retention despite correct content. The final source allows only
the immutable expected headers and the specific SigV4 transport headers, with an
exact Host check. It also reports HTTP acknowledgement/precondition failure
rather than claiming the backend proved conditional creation. Fourteen focused
tests pass, including source overwrite after verification, signer body/header
substitution, existing-target mismatch, denied authorization, malformed/oversize
input, actual-stream bounds and late signer/PUT responses. The reviewer verified
the fixes with no remaining source-level blocker.

The first full Edge run exposed a missing registration in the structural
outbound-deadline audit (4,693 passed, one failed). The successor registers only
the exact promotion callback, with mutation tests rejecting lost cancellation,
changed deadlines, bypasses and missing unknown-write accounting. Its 18-test
focused run passes. The production call now passes the caller signal and strict
redirect/cache policy explicitly through the existing deadline transport; no
guard was relaxed. A separate full-tooling failure occurred before hidden-key
prompting because the managed sandbox denied read-write access to the synthetic
PTY. The unchanged launcher passed all five synthetic cases with approved local
PTY access; no launcher or credential-handling source change was needed.
Independent review found no remaining source blocker in the audit correction.
The final full Edge run passed 4,695 tests / 1,233 steps, zero failures, in
5m16s against the owned local replay with all 560 migration files byte-matched.
The complete `make test-supabase-tooling` rerun passed with that approved local
PTY access, including unchanged Gemini and OpenAI hidden-key tests. Full Edge
format/lint and Markdown checks passed; the prior DTO, configuration and
dependency-graph checks remain applicable to those unchanged surfaces (128
isolated function graphs, 628 runtime files).

Evidence is retained in `.artifacts/capture-promotion-20261120/`, including the
source SHA-256 manifest and scoped independent-review receipt. `tooling01.log`
retains the sandbox-restricted failure and `tooling02.log` the complete passing
rerun. `edge03.log` retains the failed structural audit; `edge04.log` is the
final passing suite. Earlier `edge01`/`edge02` runs were interrupted, not
passed. `focused04.log` records a test invocation missing its Deno config; the
corrected invocation is `focused05.log`. These local, synthetic checks do not
qualify remote object storage or the unfinished submission-to-History journey.

This is an uninstalled storage prerequisite: there is no SQL reservation owner,
signer/environment composition, live route or source-retirement authority. The
authorization hook cannot be implemented by echoing the input or checking HEAD.
The next step must register immutable operation/source/destination/content
ownership before dispatch, qualify the backend's conditional-write behavior, and
bind the result to durable scan-media finalization and recovery. Merge,
retirement and late-write ownership remain mandatory. Existing Identify/audio,
restore/repair and Explore promotion callers are unchanged; no new public API,
migration, deployment or activation is included. Native50 remains applicable to
unchanged iOS source; no native slot was acquired or used during this step.

Read-only tracing identified the next implementation seam: a private immutable
promotion-operation row with a separately retained destination retirement
obligation. The existing staging-only authority cannot represent two physical
keys with one absence/lease record. Registration and fresh authorization must
reuse the account-intake advisory fence and ordered scan locking, accept the
legitimate pre-scan staged asset tuple, and reject retired, rebound or changed
bindings. Scan/account retirement and the private ghost-merge transaction must
retire both source and destination obligations; no cross-owner continuation is
implied. Preserve the forward no-reclassification trigger repair. Service-only
access, exact retry/mismatch, scan-not-yet-present, retirement/merge races and
independent source/target cleanup require executable qualification before
installation. This is the next technical handoff, not an implemented SQL owner.

## November 19 inspection integration continuation

Capture remains the sole writer. History and Hardening reconfirmed no ownership
or contract changes and no competing native reservation before native42. The
next observable journey remains whole-observation submission followed by durable
History/reanalysis; it is not yet available end to end.

The accepted-hold reader is now connected to the existing repository
`inspectApp` path used by opening and inspection. Its explicit invocation-local
scope checks the complete V71/V70 store, binds the exact
container/profile/header, expires after use and is passed only through clean
original, acquisition, consumer and budget readers. Ordinary metadata is charged
once, and originals shared by a pending draft and a hold are not counted twice.
Held sources outside pending membership retain their physical, acquisition
receipt and identity charges.

This lane supports plain P1 and frozen received consumers. Advanced receiving
allocation, initial application, releasing and terminal states remain explicitly
closed while ordinary holds exist. Generic audits, write/poststate owners and
original removal remain strict. Opening a readable store is not permission to
delete a held original or dispatch an ordinary queue. Native48 passed both
one/two-photo cases through actual cold owner reopen and inspection, including
frozen received consumers and continued removal rejection (one parameterized
function, 111.117 seconds). Final native50 passed all 69 functions in nine
suites after removal of temporary diagnostics: 149 expanded cases, zero
failures/skips and no structured runtime warnings, in 928.070 seconds. This
includes the actual cold-open/inspection cases, legacy-queue rejection, Core and
Offline Queue architecture, original lifecycle/accounting/liability, scoped
graph joins and existing-profile inspection. Native48 evidence is
`.artifacts/local-ios/a55fdc0a97dd420a8e2c67c508043916.xcresult`; final native50
evidence is `.artifacts/local-ios/4d27cc55d48d4b95b5c9277c4c4455bb.xcresult`.
These are local synthetic component/integration checks on the uncommitted
working tree based on `ac8f1737dadf2e7319681a2ae019ab806faf540d`, not full
Identify/Reanalyze-to-History acceptance. The coordinated build slot was
released after the managed wrapper exited successfully.

Earlier failures remain retained: native43 failed both parameterized cases with
`.stale`; native46 localized that failure to the accepted-budget/scope fixture
before cold reopen. The fixture had reused a cached model across rollback. It
now uses separate dirty and persisted contexts and restores the exact saved
revision; production guards were not relaxed. Native42 stopped at a Swift
predicate type-check error, corrected with five bounded predicates. Strict
SwiftLint, XcodeGen regeneration and project validation passed on the final
source. No backend source, deployment or activation changed in this
continuation.

The user-authorized storage cleanup removed obsolete caches, generated compiler
and index data, and completed synthetic fixture directories from disposable A21.
Current dependency downloads and retained `.artifacts` evidence were preserved.
The signed-in simulator was not used or cleaned. No cleanup ran during native50.

The next native removal slice also has a concrete reachability dependency:
accepted photo submissions still have prepared derivatives. Original removal
requires `Rows.noPair`, but the existing pair-retirement owner and its
save/readback accounting still reject V71. A removal-only helper cannot complete
this journey. Qualify accepted-ordinary pair retirement/cleanup and its physical
I/O first, then the non-final draft-reference removal, or establish and validate
an admission order that retires derivatives before acceptance without losing
required submitted evidence. Manual fixture teardown is not acceptance evidence.

Any removal successor must use its own typed write proof. It must bind complete
unchanged V71/V70 membership, phase and original-byte identity under the stable
store fence, including additions/removals; use bounded streaming comparison or a
canonical digest instead of an unbounded receipt vector. Its exact row changes
and budget projection must preserve the held physical source and be rechecked
from freshly persisted state. The read-only inspection scope cannot grant those
writes. Final hold release remains a separate transition. History acknowledged
this boundary; Hardening additionally reaffirmed exact promotion/COPY authority
and cleanup recovery as the priority before optional native expansion. These are
technical prerequisites, not new product decisions or passing end-to-end checks.

Promotion tracing found that the current exact-key registry accepts staging PUT
keys only. Extending its key pattern alone cannot authorize COPY or publication.
The successor needs a durable immutable source-to-destination operation and
registered destination before dispatch, transactional publication binding before
source retirement, and exact recovery for unknown COPY/publication outcomes.
Prepared destinations also need explicit abandonment/terminal retirement. Cover
all capture promotion callers and the moderation indirection; restore/repair
callers have different publication owners and cannot inherit that authority from
a URL update. Keep generic legacy behavior and the diagnostic worker quarantine
separate until those callers are qualified.

Here, publication binding means the private scan-media finalization transaction;
later Explore publication remains a different owner. The staging key can still
receive issued PUTs, so an operation ID, matching key or HEAD alone cannot prove
immutable content. Bind and verify the submitted byte identity before treating a
copy as recovered; preserve unknown late-copy obligations. Account merge also
retires old-owner staging authority, so reparented metadata alone cannot permit
copy continuation or bypass that retirement. A row trigger or finalizer wrapper
alone cannot recover a crash between remote COPY and its database
acknowledgement. These are unresolved technical contracts, not new product
decisions.

## November 19 late checkpoint — staging retirement and whole-store holds

Capture remains the sole implementation owner. History and Hardening confirmed
no competing native reservation before the managed A21 validation run. The
approved whole-observation Identify/Reanalyze interaction and scope exclusions
are unchanged. This checkpoint is source work and local qualification; the full
user journey is still incomplete and the live strict producer remains closed.

Newly signed staging PUTs now receive a private durable exact-backend/key record
before their URLs are returned. Registration binds owner, scan, asset, upload
session and the actual signed expiry. Scan/account retirement survives row
cascades, and a bounded DELETE/HEAD worker retains every exact late-write
obligation even after it observes absence. Aggregate health reports unresolved
obligations separately from scan-row cleanup. Account intake and signing share
an advisory fence without reversing the account worker's job/owner lock order.

Independent review found two compatibility/safety issues, both corrected. The
existing private account-merge orchestrator can reparent metadata only through
an exact transaction/old-owner/new-owner marker, with whole-row invariance apart
from owner and timestamp; the old staging capability retires in that
transaction. Changing source classification or moving a registered key cannot
evade the fence. The marker, registry and private reparent implementation have
no API-role grants. This qualifies new staging issuance only: promotion/COPY
recovery, publication dependencies, legacy capabilities and abandoned drafts
remain open. The diagnostic `reconcile-scan-media-assets` quarantine is
retained.

`SharedMediaOrdinaryStoreAudit` checks every accepted V71 submission and V70
hold, including foreign and unanchored rows, complete parent/cohort membership
and current original counts/seals. A source-ordered traversal audits each
original once with constant retained traversal state and bounded fetch pages. It
is a read-only prerequisite; app operation/budget routing and generic guards
have not been relaxed. The fixture covers wrong inventory,
reserved/corrupt/extra/orphan rows, persistence/reopen and an original held
after its last P1 reference is gone. It does not claim that an actual last-draft
removal or final release ran.

History's terminal handoff found no existing durable record proving the complete
owner/scan/submission-generation/job/event terminal outcome and original-media
dependency closure after job removal. `original_inference_completion_v1` binds
the inference generation; `initial_evidence_expectation_v1`,
`initial_evidence_completion_v1` and `initial_evidence_result_sha256_v1` bind
the submission and retained result. Enrollment must continue to consume those
proofs. Queue absence, a cancelled job/event, baseline8, or a result alone
cannot authorize final original deletion.

The next release successor must preserve an exact V71/body/hold-set terminal
receipt before any prerequisite job/proof can disappear, prove original byte
recoverability and local reader/writer/upload quiescence, and account for all
remaining drafts, History/reanalysis/export consumers and other holds. Releasing
one queue hold and physically deleting the source are separate transitions.
Hardening accepted success-first integration as an intermediate slice;
uncertain, missing-job and cancellation outcomes must remain held until
qualified terminal handling exists. That slice does not complete
cancellation/deletion/recovery acceptance. Existing V70/V71 retirement envelopes
are candidate storage, subject to bounded canonical receipt and lifecycle
review; no new schema need is assumed.

The remaining implementation order is: exact promotion/COPY authority and
rollback/recovery; qualified app audit/budget routing and held-original draft
removal; registered final release; atomic queue/job/event/V71/V70 admission with
fresh complete readback; durable result/enrollment/restart integration;
audio/video qualification; and the full Identify/Reanalyze/History failure and
end-to-end matrix. No hosted schedules or release state were queried or changed
in this checkpoint. Earlier hosted observations remain dated evidence only.

Validation for this checkpoint used the uncommitted working tree based on
`ac8f1737dadf2e7319681a2ae019ab806faf540d`. The final disposable database replay
contained 560 byte-matched migrations; its complete gate passed 207 files and
12,000 assertions. The final focused staging/registration/database adapter run
passed 12 Deno tests, and both account-intake/signing orders plus the
retry-worker lock-order race passed. The unchanged Edge source had already
passed the full 4,679-test/1,233-step suite and all 128 deployable entrypoint
type checks; the subsequently added database adapter test is covered by the
focused run. Supabase tooling passed, including the explicit PTY sandbox retry.
These checks used synthetic local data and fake R2 transport, not hosted
storage.

Native40 rebuilt the app and tests through the managed wrapper on disposable
simulator A21, passing 15 ordinary-hold and legacy-queue functions in 95.552
seconds. Evidence:
`.artifacts/local-ios/9be8c504b57e4a01889ec5e7cae17717.xcresult`. Its
architecture selectors did not select those suites; native41 corrected the
selectors and reused the same compiled product, passing all 13 Core/Offline
Queue architecture functions in 11.275 seconds. Evidence:
`.artifacts/local-ios/b44d473ad2f947ccb4987e0876d1f2b1.xcresult`. Strict scoped
SwiftLint, XcodeGen and generated-project validation passed. Authorized cleanup
removed obsolete clean package-cache copies while preserving current build
products, dependency downloads and retained evidence. Native39 stopped at disk
preflight and provides no runtime evidence. End-to-end submission, actual
last-draft removal and terminal original release remain unvalidated and
incomplete; no live route or quarantined worker was enabled.

## November 19 evening checkpoint — completion proof and legacy exclusion

Inspected November 19, 2026 (Chicago; November 20 UTC), against the uncommitted
working tree based on `ac8f1737dadf2e7319681a2ae019ab806faf540d`. The next
observable outcome remains a whole-observation Identify/Reanalyze round trip
with selected evidence retained through restart and History. That journey is not
yet available or qualified. Capture remains the sole implementation writer;
History and Hardening reviewed the handoff and received the validation results.

The completion proof now has a separate versioned envelope around the unchanged
frozen Identify result contract. Deno and generated Swift distinguish omitted
legacy proof from an explicitly null or malformed proof. Strict finalization
requires a caller-supplied verifier bound to the exact owner, scan, submission
generation and evidence digest; it cannot fall back to the legacy RPC. Recovery
uses the sealed result, including when the transient job is gone. History's V8
snapshot reader consumes the composed envelope. These source changes do not
provide a live strict submission producer or enable the closed route.

Legacy queue access now refuses any surviving V70/V71 liability, even when its
receipt is malformed or its queue row is missing. The V71 lookup also checks the
canonical job identity independently of the recipient scan field. This protects
new records from legacy deletion or dispatch; it grants no new execution or
release authority. The guard is tested before and after persistence for
reserved, accepted and retired rows, absent/present queues, and an unrelated
scan. Independent read-only review requested the job-identity case, which was
added.

Native37 passed 37 Swift Testing functions across three suites in 3.477 seconds
on the disposable A21 simulator through the managed build wrapper. Evidence:
`.artifacts/local-ios/8d37a04fc574471286d52e86764f8fc0.xcresult`. Native34
previously passed 23 response/completion functions; native36 exposed an optional
UUID predicate macro error, corrected before native37. The complete Edge suite
passed 4,667 tests and 1,233 steps; the final added proof vectors also passed in
a focused 33-test run. Full Supabase tooling and iOS CI tooling passed. The
Supabase tooling retry resolved a local PTY sandbox restriction; it made no
external provider calls. Scoped strict SwiftLint passed. Fast preflight cannot
qualify these Core files because its source-size domain policy does not cover
them; the owning native architecture tests provide that check. This is local
candidate evidence, not end-to-end or deployment evidence.

Native38 then reused the compiled native37 product with `test-without-building`
and passed all 13 functions in the Core and Offline Queue architecture suites
(11.091 seconds). Evidence:
`.artifacts/local-ios/5325bdb518454669b105516f9e3cf276.xcresult`. The managed
wrapper exited successfully and the coordinated build slot was released.

Remaining integration must proceed coherently: the app-specific storage audit
and budget reader must validate complete ordinary liabilities; draft removal
must preserve held originals; final release must have a registered durable
owner; only then may atomic queue/job/event/V71/V70 admission and exact readback
be enabled. Generic qualification and legacy authority must remain strict.
Audio/video original qualification, immutable submission/result continuation,
History enrollment and restart/race/end-to-end tests remain required. Backend
cleanup still needs durable exact-object retirement covering issued uploads,
late writes and all promotion callers. The diagnostic worker quarantine and
initial-evidence 503 fence remain in source. No hosted schedules were queried or
changed during this checkpoint; earlier paused-schedule observations are dated
historical evidence, not continuously verified status.

## November 19 continuation — accepted holds and cleanup handoff

The explicit ordinary accounting reader now checks complete accepted V71/V70
membership, original/acquisition/lease identity, and current inventory/count
revisions. It counts live P1 pairs plus accepted holds and can read an original
retained by a hold after its P1 pair is gone. The default P1 audit and generic
storage barriers still reject ordinary records. This read-only prerequisite is
not atomic admission, queue/job/event recovery, upload authority or final
ordinary release. Independent source review confirmed that distinction and
requested explicit partial/extra-set tests, which were added. The no-P1 fixture
seeds a persisted after-image; actual last-draft removal and final release still
need lifecycle implementation and tests.

The November 19 queue handoff trace found no production writer for
`initial_evidence_expectation_v1`, although completion requires that identity.
The atomic admission successor must preserve the existing inference generation
and unreleased funding metadata while adding the owner/scan/submission
generation expectation. It must save the queue, ingestion job, deterministic
queued event (`submission.eventID`), V71 body and complete V70 hold set
together, advancing inventory once and each distinct asset counter once by its
exact hold count. Existing job upsert and legacy enqueue saves cannot provide
that transaction. A fresh complete-set readback must validate those rows,
original file seals and accounting after either a successful or uncertain save;
a V71/V70 receipt alone is insufficient. This is remaining technical
integration, not an additional product decision or a qualified admission path.

History confirmed that submission generation, foreground inference generation
and draft generation are distinct identities. The expectation uses the exact
durable submission owner/scan/generation; no identity may be substituted to
satisfy completion. Equal retry requires the complete saved set, preserving
media order, V3 note seed and preparation binding. Server prepared-evidence
digests remain distinct from local body/preparation digests. Completion must
atomically retain its proof and accepted result digest with the local result,
preserving any existing result under `OrdinaryInferenceCompletion` before
baseline8 enrollment. Missing expectation or legacy baseline3 cannot be silently
upgraded. An uncertain save does not authorize funding or media release.

History and Hardening's November 19 review also identified a pre-I/O cleanup
gap: `reconcile-scan-media-assets` can delete staging or mutate/promote an
existing scan before the later terminal RPC rejects initial-evidence work. The
closed initial-evidence gates remain necessary. The correction must establish
durable authority before any of those effects, serialize with all initial
admission/binding paths, and protect retained intent/evidence when a transient
job is absent. Permanent scan protocol exclusion alone cannot authorize
arbitrary object keys: each destructive operation needs exact source/destination
binding, irreversible retirement, uncertain-outcome recovery and a discoverable
cleanup obligation for late PUT/COPY. Unknown/deleted owners fail closed outside
a separate retained erasure authority. The full retirement correction remains
unimplemented; a fetch-only filter or terminal check after deletion is
insufficient. The November 19 source safeguard now forces this reconciliation
worker into diagnostic-only evaluation, even for `dryRun: false`. Its actual
effect counts remain zero and all candidates pending; hypothetical
classification is separately labeled `preview`. Only HEAD/read diagnostics and a
`dry_run` audit row remain. This holds stranded-video recovery and abandonment
cleanup and does not protect other promotion callers, issued URLs, or old
deployed workers. No hosted state changed.

The existing private initial-analysis and History erasure registries are bound
to their own object UUIDs, immutable private namespaces and cohort contracts.
They do not authorize capture `staging/` or `public_uploads/` paths and must not
be widened to bypass those contracts. The capture correction needs its own
bounded operation/fence keyed by account, scan, asset/session and exact
source/destination identity, using existing retirement and recovery patterns
without reusing private-object authority.

Capture remains sole writer for both integration paths; History and Hardening
are read-only reviewers. Native28 was refused before compilation for free space,
then for a redundant scheme argument. Authorized cleanup removed only
regenerable old Xcode build/index/module caches, preserving validation evidence,
archives and dependency downloads, and restored 27.6 GiB. Native29 passed all
nine Swift Testing functions in two suites, including both photo counts and the
new accounting helper, in 93.275 seconds. Its result is retained at
`.artifacts/local-ios/f290d44f51fb4d9f916c4165eddca569.xcresult`. Native30
passed 17 existing app-original lifecycle tests and six P1 accounting tests but
failed the Core oversized-owner inventory check (30 functions total, one
failure). Independent review justified two sealed receiving-owner ceilings and a
pure uninserted queue-record constructor extraction; admission, persistence,
refund and dispatch remain with the manager. Native31 passed both architecture
suites but exposed old uppercase-ID test lookups in five admission tests. Live
Capture already supplies canonical lowercase IDs. The fixtures now use that
identity and explicitly test uppercase input normalization. Native32 also adds
visual/nonvisual record mapping coverage and passed all 22 functions across four
suites in 10.869 seconds. Its wrapper exited successfully and the A21 build slot
was released; result:
`.artifacts/local-ios/17b1c612d3c545178ab89abc663d2e4c.xcresult`. Source
parsing, strict scoped SwiftLint, project generation/validation, Markdown
formatting and diff checks passed. Neither the feature nor end-to-end validation
is complete, and no hosted state or activation gate changed.

## Product correction — 2026-11-16

The user confirmed that **Identify** (new observation) or **Reanalyze**
(reanalysis) submits the **whole staged observation**. Reviewing individual
items is optional. There is no Next button, per-item confirmation state, or
requirement to open every import. This supersedes the earlier intermediate-Next
and final-outstanding-import rules, including submission from Field notes.

The source correction removes the required-import queue and submission gate.
Imports receive centered-square default preparation; native originals receive a
stable normalized square recipe before staging. Optional edits to the displayed
item must commit successfully before the existing whole-observation submission
owner validates, freezes and admits all staged media and supporting text. An
edit/preparation failure retains the draft without submission. An admission
failure retains valid committed state for manual retry; an accepted request
keeps its existing saved identity and replay contract.

Focused validation passed on November 16 against the uncommitted working tree
based on `ac8f1737dadf2e7319681a2ae019ab806faf540d`: 132 XCTest cases, 18 Swift
Testing tests across three suites (including parameterized native camera/picker
cases), and the Field notes keyboard/return UI test. The canonical
`make ios-local-build` run completed with `TEST SUCCEEDED`; evidence is
`.artifacts/local-ios/fa507971f16848f5add97d63d98bdd48.xcresult`, with command
output at `/tmp/capture-review-whole-observation02.log`. The first attempt was
interrupted after stale camera fixtures assumed capture could resume before
review dismissal; the passing rerun exercises the real Add more and
outer-dismissal transitions. Focused SwiftLint, project/resource validation,
event-routing checks, Markdown formatting and scoped diff checks passed.
Independent read-only review found no remaining correctness blockers for this
correction. This qualifies the scoped correction locally, not the entire
successor feature or any deployment; earlier test counts below cover earlier
source only.

## November 16 — Figma alignment and initial notes successor

Figma was inspected on November 16 at review toolbar `2757:13630`, photo
selection `2694:24086`, Field notes `2757:13674` and keyboard `2757:14006`,
audio `2694:24050`, and video `2694:24002` in the
[Merian design file](https://www.figma.com/design/AVATuIm6rP8wxiYAJg1qGa/Merian?node-id=2694-23954).
No additional file comments were returned. The explicit whole-observation
submission decision and scope exclusions override older board variants. The
design uses document-and-pencil note states, a separate toolbar grabber, a
selected plus when adding media, and a square audio review that starts paused
with Play visible and retains the shared reveal/fade behavior while playing.
Video requires persistent playback controls and a shared square preparation
transform; displaying a cropped preview alone is insufficient.

The initial-note successor is being implemented and is not yet qualified.
Ordinary creation snapshots ordered canonical supporting descriptions into the
queued editable note. Existing local record presence, including a nil or empty
clear, wins during completion. Native fresh creation opts into an additive
`nativeConsumerV3` frozen cohort with the same canonical seed. Old
`nativeConsumerV2` bytes and nil-note behavior remain unchanged. Recovery reuses
the saved format and value, and later note edits never change submitted
evidence. The compact abandoned V3 value retains only a digest of the optional
seed, including the distinction between nil and nonempty, rather than another
plaintext copy. Restaging must preserve that seed or refuse recoverably.

The existing legacy Field Notes bridge does not establish exact draft/account
provenance or distinguish an absent note from a prior clear. It is therefore not
read and appended during new creation. A future caller with proven pre-existing
notes must supply a once-frozen merge at initial construction; replay must still
use the saved value and request identity. This narrows the implementation source
of pre-existing notes without changing the approved one-time merge contract.

History confirmed scoped successor ownership and reviewed the format/digest
approach on November 16; final concrete-diff review and native validation remain
pending. Capture remains the single implementation writer. This status is a
dated checkpoint, not release evidence or a statement that all workstreams are
complete.

## November 16 — manual selection parity and video follow-through

The user explicitly confirmed manual photo subject selection for both initial
identification and reanalysis. The selection is per-image submitted evidence,
including mixed-media reanalysis, and must survive exact retry and recovery.
History granted the scoped successor writer extension for the affected request,
preparation, source-selection, execution, validation and forward-migration
paths. History and Hardening remain read-only interface reviewers.

An enum-only change is insufficient: old ordinary queue readers can discard an
unrecognized descriptor array, native CPM v1 does not forward focus to the
provider, and existing History evidence has no manual-focus representation. The
successor needs versioned immutable evidence and explicit compatibility
boundaries. Old canonical bytes and accepted replay remain unchanged. New
unsupported evidence must be held or rejected without silently losing selection.
This contract work is in progress; the selection control is not qualified yet.

History's November 16 follow-up confirmed that initial mixed-media manual
selection needs versioned immutable evidence ownership. A subsequent source
review, following the older-beta compatibility waiver below, confirmed that the
existing ordinary queue and `identify-multimodal` owner can provide it. No new
queue, work-kind dispatcher or photo-only CPM expansion is required. Persist a
strict evidence-version marker atomically with the existing ordered descriptors
and exact prepared-media binding; preserve it through job refresh, recovery and
completed/source readback. Marker-bearing admission, extraction and live or
background dispatch must reject malformed descriptors, missing paths, changed
order/cardinality and failed timeline reconstruction rather than dropping them.
The server must verify the actual provider bytes, retain canonical evidence
without deduplicating ordered keys, and reject changed evidence under the same
admitted identity. Initial and History reanalysis keep separate contract
versions, identities and funding. This is reviewed implementation direction, not
completed contract or validation evidence.

The November 16 metadata foundation now parses optional per-image focus in
composition manifest V6, with shared Swift/Edge vectors for finite normalized
bounds, source tags and exact fields. Existing V5 admission and completed-V6
readers explicitly reject manifest V6; this parser work does not enable the new
submission contract. Nineteen focused Edge tests and entry-point type checks
passed. Independent read-only review found no concrete issues in that
foundation. Native validation remains pending while the earlier recovery suite
occupies the build slot. Ordinary queue admission serializes and validates
present visual descriptors before funding; background dispatch rejects malformed
or cardinality-mismatched saved descriptors instead of silently omitting them.
The saved draft is retained for attention. Initial completion/source readback
and the full History admission/execution contract remain required before
exposing manual selection.

On November 16, the user confirmed that older beta builds do not need to be
supported. Use a coordinated current-client/current-server contract for manual
selection; do not add older-build submission adapters or make downgrade
qualification a delivery gate. This does not authorize deleting existing data,
rewriting already-admitted operations, or silently dropping unsupported
evidence. Strict current readers, capability checks, immutable saved requests
and exact recovery remain required. Source-bound photo-selection coordinate
helpers and interaction regression cases have been added for rotation, viewport
resizing, crop exclusion, immediate fallback, candidate choice and
fixed-opposite-corner resizing; they await native qualification and are not
exposed in the UI yet.

The photo/video rotation controls now use the supplied Figma vector assets from
nodes `2694:24116` and `2694:24120`, at their original 31-point size inside
44-point minimum targets, instead of generic SF Symbol substitutes. Native
rendering and asset compilation are pending in the next sequential run.

Default video preparation now has a shared square composition for playback and
sampled frames in source, with no unframed-original fallback after export
failure. The video page is being aligned with persistent play/pause, seek,
elapsed time, and preview-only mute. Source retention and changed-edit commits
are now implemented in the unqualified successor source. Review renders the
retained source with the saved/current crop recipe so later edits do not
compound lossy crops; exported playback and sampled frames use that same recipe.
An unchanged review preserves prepared artifacts. A successful edit swaps the
playback, thumbnails/inference frames, companion audio and recipe together,
retains the original source, and removes only superseded draft derivatives.
Failure or stale session/account/generation retains the prior artifact set and
cleans candidates. Direct and automatic submission are blocked during commit.

A local deterministic preparation may finish while backgrounded only if its
matching review/draft/account owner remains current; it never resumes playback.
Dismissal or owner replacement rejects late results. Camera-roll saving finishes
before the recording becomes removable draft-owned media. History staging uses
its owned Documents basename, while live recording uses its owned absolute path;
editing does not grant authority over accepted-library originals. New
pixel-equivalence, repeated-edit, History-source, pending-playback, and
camera-roll-borrow tests await native execution. Native validation remains
pending; this paragraph does not claim video completion.

## Submission integration checkpoint — November 16, 2026, 21:06 UTC

This is a dated local working-tree checkpoint, not completion or release
evidence. The focused native History suite passed 34 tests in
`.artifacts/local-ios/802d0da8a4ab44e6a6c76e18a33be29c.xcresult`. It covers
typed initial-result V8 and focused-composition V7 review tickets, exact
selection retry, selection Undo and initial evidence decoding. Independent
read-only review found no blocking issue in these action changes.
Review/rejection/Undo and confirmation use reader 16. Legacy enrollment
reconciliation uses reader 15; legacy enrollment/recovery remains reader 9.
Initial evidence uses reader 16. Candidate choice and publication keep their
narrower independent contracts.

The initial completion path now validates an expected frozen submission
identity, owner, exact sealed evidence proof and original result digest before
retaining a completion; retries cannot rewrite admitted evidence or the selected
result. Production enqueue does not yet create that expectation. The remaining
work is the durable original-media handoff, production initial-evidence assembly
and retention, dispatch/replay propagation and accepted-result recovery. Manual
selection stays gated until those paths and their failure/restart cases pass.

Source inspection corrected an earlier assumption: ordinary queued photo
attachments are bounded display derivatives, not originals. Video has a separate
raw source in the draft, but the current ordinary queue persists prepared
playback. Native photo original access belongs exclusively to the registered
native owner; its existing receiving readback exports only derivatives. Do not
activate the full native CPM dispatcher or relabel these files as originals.

The original export bridge must reserve destination ownership and cleanup before
copying, hold the exact source revision, verify and synchronize the copy before
issuing a receipt, and atomically accept that receipt with the ordinary job.
Lost acknowledgements use exact durable lookup. Cancellation cannot release a
reservation while a writer may still finish. Both copies remain accounted for;
source cleanup cannot delete an accepted queue copy or an original referenced
elsewhere. Existing native acquisition, receiving and consumer records have
incompatible strict lifecycles; a distinct typed transfer record under the same
owner needs a reviewed forward migration and recovery/audit/removal integration.
Schema ownership coordination is pending at this checkpoint.

A full unfocused Gemini request/snapshot regression passes for photo, audio and
mixed media against the prior request bytes. This is a deterministic local test,
not a live provider experiment. Broader backend and final native/UI validation
remain separate gates. No schedules were resumed by this work; their current
scheduler state was not re-inspected at this checkpoint.

### Follow-up — November 16, 2026, schema ownership and validation

History, Hardening and the isolated integration chat explicitly released the
overlapping schema/storage paths to Capture as the sole implementation writer.
The original-acquisition seam is the existing registered owner obtained through
`AppDIContainer.nativeMediaOwnerForFeature()`, retaining its account, drain and
bootstrap discovery. It is not the full native CPM dispatcher. The V69 freeze
compiled successfully in
`.artifacts/local-ios/23d1b7386c0440f881accec7aa57b049.xcresult`; independent
read-only review found no persisted-shape or relationship discrepancy. V70 adds
separate transfer storage and source-isolated startup routing. Its presence does
not authorize transfer interpretation; existing owners remain closed to
populated rows while lifecycle integration and migration tests are in progress.

The full local Deno suite passed 4,651 tests and 1,182 steps after fixing
missing no-proof recovery mocks and classifying immutable initial-evidence
identity references as preserved during Ghost merge. The latter blocks only
source owners with retained evidence and never reparents an immutable proof.
These checks used the owned disposable database, with no live provider or
production mutation. Native/UI validation and the live initial-submission
integration above remain incomplete. This dated follow-up supersedes the earlier
pending schema ownership statement; it does not claim workstream completion or
schedule status.

### Follow-up — November 16, 2026, owner-retained originals

History and Hardening confirmed in read-only coordination that a separate
Documents copy is not required. The selected integration direction supersedes
the export/copy proposal above: keep each actual original with the registered
owner and give the ordinary queue an opaque durable hold. This avoids a second
physical storage owner and counts the physical allocation once, while preserving
per-reference logical liabilities and limits.

The hold binds account, scan, stable submission generation, original
asset/reference/generation/revision, byte facts and preparation recipe. Acquire
it before queue acceptance; save the job and its exact hold receipt atomically.
Uncertain acceptance must reconcile that saved receipt. Reads and upload remain
owner-mediated with identity, account and deletion checks. Restart recovery must
reopen the hold without reacquiring media. Queue cleanup releases only its own
hold through the owner; it never unlinks the original. Cancellation drains
active reads/uploads before release. Original eviction requires proof that the
exact original is durably retained and recoverable and that no other
History/export, lease or execution dependency remains; upload success or an
analysis receipt alone is insufficient. Missing/corrupt/uncertain references
remain held for explicit recovery. Photo qualification does not establish
audio/video support.

The V70 candidate storage/lifecycle vocabulary must follow this reference/hold
model before activation. Its currently conservative rejection guards remain
until typed audit, accounting, recovery and retirement are validated.

The accepted-result recovery RPC and strict TypeScript adapter are implemented
as an integration seam. Independent review and five focused tests passed,
including disposable-database null-versus-denial, request identity, missing
artifact, retirement/deletion and cancellation cases. The live identify handler
and replay worker do not yet call this seam; no claim of provider-free
end-to-end recovery or selection readiness follows from those tests. Migration
contract validation passed 581 tests across 148 discovered files.

### Follow-up — November 19, 2026, finalization recovery boundary

The legacy replay worker now refuses initial-evidence requests before provider
dispatch or proof-free existing-scan completion. Its claim RPC excludes both
versioned intents and retained evidence identities from normal claims and retry
exhaustion. Focused worker tests and disposable-database tests cover expired
finalization leases at replay counts 0, 9 and 10, before retention allocation
and after an accepted result, preserving the job, intent and held funding
exactly. This is a local safety boundary, not the dedicated continuation
implementation.

A matching live-handler fence rejects either initial-evidence marker, including
null or malformed values, before media, funding, provider or persistence work.
It returns `503 analysis_history_unavailable` until the complete continuation is
wired. Direct/internal handler tests cover both spellings and malformed values;
they do not replace outer replay-authentication qualification. Ordinary requests
without either marker retain their existing path.

A follow-up forward migration rejects in-place upgrades of legacy intents and
rechecks evidence ownership under the terminal orchestrator's job lock before
retry-exhaustion or TTL-abandonment settlement. Direct stale-RPC regression
cases also preserve held funding. External staging cleanup still requires its
own coordinated ownership fence; terminalization denial alone does not protect
an object already deleted by a worker.

The public-media promotion helper can preserve staging during durable
finalization; successful and failed-copy tests pass. The scan-insert seam now
resolves account defaults and owns nested input once, allowing a validated
frozen projection to be inserted without consulting changed preferences. Neither
seam is yet wired to an immutable finalization continuation. Public promotion
targets and cleanup obligations must be registered before writes, verified
before source release, and included in the existing scan/account erasure owners
even if no scan row was inserted. Private originals retain their separate
existing evidence erasure owner.

History and Hardening's November 19 read-only handoff requires binding the exact
accepted result before promotion. Missing continuation or uncertain
acknowledgement must preserve recovery state without redispatch. Current result
binding also freezes species identity, so taxonomy must be resolved before that
bind, or a separately versioned immutable provider-result stage must be
introduced. A temporary null species cannot later be replaced under the same
bound result.

The clean-catalog integration pass exposed a duplicate owner check in the
initial-evidence completion migration. The undeployed candidate now asserts and
reuses the established profile lock before the scan advisory lock, preserving
retired-owner `P0002` and null-input behavior. Catalog assertions also account
for the later reader and recovery-schema extensions without weakening the older
exclusion rules. Both actual two-session ordering tests pass: evidence admission
wins and rejects stale terminalization; terminalization wins and rejects late
evidence admission. Hardening independently inspected these tests and the
ownership correction and found no new blocker in this bounded scope.

The November 19 clean disposable catalog passed all 11,945 tests in 206 files
after replaying the complete candidate migration set. The full Edge suite passed
4,664 tests and 1,182 steps (`/tmp/capture-full-deno-tests-final05.log`). Its
preceding run exposed a stale textual coverage assertion for the renamed frozen
insert row; the exact scan/owner persistence boundary was intact, the assertion
was corrected, and the 28-test focused rerun also passed. Privileged routine ACL
audit, recursive type checks, formatting and lint checks passed. These are local
candidate results, not hosted deployment evidence.

The user approved keeping the iOS system font and matching Figma's size/weight.
The photo page uses scaled 26-point semibold heading and 16-point supporting
text. Its square preview now fits the space remaining after controls and text
instead of subtracting a fixed height. This preserves the supplied rotation
assets and optional white-corner selection. Clear selection uses white text as
shown in Figma. The final focused native layout test passed at standard and
accessibility text sizes; both synthetic renderings were inspected. Evidence is
`.artifacts/local-ios/825ba123b9d14e088f9c2f6f63f9abc7.xcresult`, with output at
`/tmp/capture-photo-layout-native15.log`. Earlier failed attempts exposed
missing test-host dependencies and a detached snapshot window; the passing test
injects the existing hardware environment and checks foreground-window
rendering.

The broader focused capture run passed 116 XCTest cases and 16 Swift Testing
tests (`/tmp/capture-review-native09.log`), and the Field Notes keyboard/return
UI test passed (`/tmp/capture-notes-ui10.log`). Its retained screenshot was
inspected with Identify above the keyboard. These qualify the named local UI
checks, not the disabled selection submission flow or all end-to-end journeys.

The original-hold transaction boundary is explicit: the existing native
`shareAppOriginal` API saves its own context and cannot be paired with ordinary
enqueue using two saves. The owner-mediated participant must validate and stage
the hold and accounting in the exact context saved by
`OfflineQueueManager.insertAndPersistRecord`. A saved job/hold with a lost
post-save acknowledgement must recover that committed state; an error alone must
never release its hold or delete its media. V70's conservative guards stay in
place until typed audit, accounting, read/upload and release are implemented and
validated. History independently confirmed that no existing ordinary
transaction-join API closes this gap.

History's additional read-only review confirms that a normal draft-share pair
cannot replace the typed V70 queue liability: it lacks recipient scan,
submission generation, immutable request/byte identity and acceptance/retirement
recovery. The participant must retain the existing owner operation lease and
store/file fences through a single synchronous save and fresh-context readback,
validate the same container and exact permitted row mutations, and return a
receipt rather than mutable rows or file authority. Async inspection precedes
queue mutation; final revalidation, staging and save have no intervening await.
Queue cleanup releases only its liability through the owner. This is a reviewed
interface direction, not a completed or qualified participant. Hardening's
independent read-only review found no architectural conflict and explicitly
requires fault coverage for save/readback uncertainty and account transition
immediately after commit. The owner wrapper may throw after the transaction
succeeds; cancellation or account change may suppress the returned result but
must not undo durable acceptance or initiate cleanup.

The November 19 continuation adds bounded canonical V70 hold-request and local
acceptance descriptions, an exact row/envelope reader, and registered-owner
read-only preparation from the audited source graph. The request preserves the
physical acquisition identity even when the current source is a legitimate
shared reference in another draft. It binds the whole-observation digest,
per-source preparation digest, recipient scan, dedicated submission generation,
queue event, current inventory/count revisions and writer epoch. A bounded
cohort derives exact per-asset count changes for one or two distinct references;
two references to one original do not create another physical allocation. These
values are descriptions, not a save participant, file capability or proof that
admission committed. V70's production rejection guards remain intact.

History reviewed reuse of the existing frozen photo cohort and per-source
derivative intent bytes. `SharedMediaOrdinaryPhotoHoldBinding` now validates the
complete membership, exact observation/preparation digests and original byte
identity, and returns held sources in the frozen entry order. Sorted hold IDs
never define media order. Hardening's independent read-only review found no
blocking issue in this bounded foundation after the per-source digest and
ordering clarifications. It did not qualify persistence, uploads, release or
mixed-media parity.

The registered-owner batch description now compares the complete submitted photo
cohort with current ready pairs, derivative reference revisions, completed
identities, source membership and exact supporting bytes. Receiving and ordinary
hold preparation share `SharedMediaNativeReadyPhotoCohort` for those joins. The
normal app preparation route remains persisted `draftOwned`; its UI freeze does
not imply a persisted `preparedHeld` package or receiving intent. This
description does not inspect current physical files or grant admission. Atomic
acceptance must repeat the graph checks and inspect/seal original files after
its last suspension, then persist the exact body and queue/hold set together.
History and Hardening confirmed this boundary in read-only coordination on
November 19. Capture remains the implementation owner for the outstanding
integration; this is unfinished engineering work, not a new product decision or
an unresolved ownership handoff.

The producer/consumer trace confirms that `CaptureNativePhotoSubmissionSnapshot`
and its selection already own native original references, prepared intents and
supporting bytes. Admission should reuse the existing canonical frozen cohort
format and retain the exact body, rather than create another observation DTO or
reconstruct it from mutable UI state. Its current photo-only restriction does
not establish audio/video parity. Ordinary queue rows, upload
selection/completion and deletion still use legacy derivative paths. They
require an explicit qualified-hold branch before originals can enter that queue.
The optional foreground-inference generation is task lifetime, not the durable
submission generation; the latter must be minted once with admission and
recovered from the same persisted hold.

History's November 19 persistence review identified the missing durable owner:
V70 holds retain per-source identity and digests, but cannot retain the complete
submission body and ordered membership after queue/job cleanup. Add a distinct
versioned ordinary-submission binding around the existing canonical body, with
its digest/format, account/scan/submission generation, job/event identity and
complete hold membership. Do not duplicate the body on each hold, overload
presentation or job metadata, or synthesize a receiving/P2 consumer. The
binding, queue/job/event, holds and counter changes must commit atomically.
Unequal replay conflicts; migration must not infer bodies for legacy rows. The
binding outlives queue cleanup and retires only through a defined terminal
retention/erasure transition after all upload/finalization/recovery and hold
dependencies end. Hardening's same-date review requires account and scan
deletion to cover the private body, with a durable terminal identity fence after
payload erasure so a late retry cannot recreate it. Enforce one immutable
binding per submission; missing/damaged records require recovery rather than
reconstruction. Uncertain saves must reconcile the binding and the entire
transaction's postconditions before cleanup or another admission. This requires
a schema freeze/migration and correlated inventory/audit/accounting support;
merely adding a model does not qualify held originals. The November 19
continuation now adds the dormant V71 binding after V70 was frozen,
independently reviewed for stored-shape parity, and compiled. Its canonical
wrapper retains the exact photo body and ordered hold/request hashes; unique
account/scan and account/scan/generation keys fence replacement identity.
Admission must still explicitly reject unequal replay before insertion rather
than relying on SwiftData upsert. Startup plans, additive migration and
conservative liability guards include the new record. Atomic acceptance,
correlated accounting, erasure and queue integration remain unimplemented and
unqualified.

The subsequent strict receipt reader now correlates the persisted V71 body and
every V70 member, including canonical ordered acceptance digests and all scalar
mirrors. It rejects partial/extra sets, altered identities, different-generation
replacement and erased bodies. Independent review prompted the combined metadata
cap and same-context parent check. This remains a historical read-only
description; current ownership, queue postconditions and the atomic writer are
not supplied by receipt decoding.

History's November 19 follow-up traces the ordinary handoff through
`OfflineQueueManager.insertAndPersistRecord`,
`OrdinaryInitialSubmissionIdentity`, `OrdinaryInferenceCompletion.retain`, and
the background/live finalization owners. The frozen photo body already carries
media order, preparation, context and notes; reuse those bytes. The adapter must
bind durable submission identity, actual funding/account and inference fences,
owner-mediated upload receipts and the server evidence manifest. Local hold
acceptance is not remote authorization. The server retention/result recovery and
prepared-insert continuation must finish before releasing originals or enrolling
the retained proof into History. The raw multimodal request fence remains closed
until that full path is qualified. Audio/video evidence and reanalysis lineage
require their existing typed contracts, not an inferred extension of the
photo-only cohort.

The accounting handoff must preserve the generic P1 reference/edge invariant.
Only a separately qualified ordinary reader may count accepted V70 holds,
requiring the asset counter to equal P1 live pairs plus accepted ordinary holds.
Add acceptance cases for removing the final draft reference while a hold remains
(the original stays materialized), followed by releasing the final ordinary hold
after restart with no surviving P1 pair. The existing P1 retirement reader
requires that pair and cannot serve as the ordinary final-release proof; use the
persisted hold/submission facts without recreating draft ownership. Unknown or
partial rows must continue to block generic cleanup and admission. Hardening
confirmed that final release must prove all ownership liabilities have ended,
persist irreversible retirement authority before deletion, prevent rebinding,
and retain exact recovery state across a crash or lost deletion acknowledgement.

Scoped local validation on November 19 passed 27 ordinary hold/lifecycle tests,
then 10 hold/binding/selection tests. Receiving's two regression functions and
all four parameterized cases passed, including complete-set recovery after
reopening without a second save. The frozen V70 app compile passed. Those runs
precede the V71 migration tests. The V71 run then passed all 47 XCTest startup
and recovery cases. Both recent/full V70 disk-migration cases and reopen/storage
checks also passed in the Swift Testing suites. That run had one failure among
85 Swift Testing functions: the architecture model allowlist omitted the new
submission record. The allowlist was corrected. A subsequent test-only compile
error (a missing `try` inside `#require`) was fixed; the final focused run
passed all 15 Swift Testing functions in three suites, including both
one/two-photo receipt cases and the corrected architecture check. The final
result is retained at
`.artifacts/local-ios/8ef6af59f8cd4abd9a2b3307b5a180fd.xcresult`; the failed
attempts remain retained separately. Strict scoped SwiftLint, project generation
and validation, migration guardrails and their tooling tests, and Markdown
formatting passed. None of these results establish end-to-end submission or
History parity.

Still open: owner-mediated original acquisition for ordinary photo/audio/video,
atomic queue/hold acceptance and restart recovery, live initial-evidence
retention and result binding, immutable promotion/insert continuation and
erasure fencing, then complete native/UI and end-to-end qualification. The
selection gate remains closed. The obsolete critical-test requirement for
mandatory per-item crop review was replaced with optional-review occupancy
protection; Identify and Reanalyze still submit the whole observation with no
Next or per-item confirmation. No schedule or hosted state was changed or
reverified by this checkpoint.

## Current implementation checkpoint — 2026-11-15

The human asked to begin after the effective November 15, 20:01 Central handoff.
Capture is the sequential writer for the 29 UI/caller paths, 34 tests, 14
document sections and conditional seams in the local
`.artifacts/history-capture-approved-ui-handoff.json`. All handed-off hashes
were verified. History retains adapter/execution/recovery, Core/Data/App
composition and backend contracts. Native12 passed 57/57 with no skips; native11
passed 170 methods. Native10's failed result remains preserved. These are
prerequisite reference results, not validation of the successor changes.

The next observable outcome is the two-mode workspace with guarded, autosaved
Field notes. Shared review/toolbar, media editors, focus integration and
one-time editable Field Notes initialization follow the approved delivery
sequence below. On November 15, PR consolidation released its bounded native
slot to Capture. Project generation and resource validation passed for the
foundation candidate, and the typed event-routing guard passed. The foundation
now includes two selectable modes, session-owned autosaved Field notes, final
dictation delivery before Identify, stable staged-item identities and the
top-left goal/trash placement. Independent review identified queued
discard/removal/preview actions and overlapping outer presentations; those entry
points are fenced in the model/caller, with dismissal occupancy retained until
the outer callback. The final read-only review reported no further blockers; it
is not native or visual qualification.

The first native attempt was refused below the 20 GiB storage floor; canonical
managed-cache cleanup restored capacity. Native04 stopped on a formatting error;
native05 compiled the app but stopped on a new test-fixture initializer error.
Both were corrected, and their failed evidence is retained. Native06 passed all
173 focused regression tests with zero failures or skips on November 15, 21:33
Central, recorded in
`.artifacts/local-ios/5da3805ac3c347af8419e30b59a3bcfa.xcresult`.

Native07 compiled but was interrupted after its first native-camera case had run
for five minutes without completing. Two stack samples showed retained
shared-media storage audit work; they do not establish its cause or a deadlock.
The managed command ended with error 75, and process inspection confirmed its
build and runner had stopped. Its log at `/tmp/capture-foundation-native07.log`
and samples at `/tmp/capture-native07-runner.sample.txt` and
`/tmp/capture-native07-runner-second.sample.txt` preserve the diagnostic
evidence. This broader integration check remains unresolved, not passed or
waived; the five-minute diagnostic cap is not a new acceptance threshold.
History was consulted without changing retained authority or timeout contracts.

On November 15, the Photo review UX chat reconfirmed the approved Notion source
(last edited November 14, 18:00 UTC), no newer decisions or Figma frame links,
and its read-only role. This chat remains the single implementation writer. The
newly supplied screenshot board is a visual reference; scan quantities and
purchase panels remain excluded.

The November 15 source increment added an imported-photo commit barrier with
intermediate Next and final-import confirmation. Those interaction rules are
superseded by the November 16 whole-observation decision above; its retained
evidence describes the historical source, not current acceptance. Independent
review found an account-transition occupancy gap; cancellation and commit
retirement now precede retained-owner transition branches. On November 15 at
22:06 Central, the focused native run passed 127 tests (116 XCTest cases and 11
Swift Testing cases), with zero failures. Evidence is
`.artifacts/local-ios/bd63d26b140b449a8c309078982144e1.xcresult`, with the
command log at `/tmp/capture-review-native01.log`. Project/resource validation,
typed event routing and Markdown formatting also passed. This does not resolve
the broader native07 integration check above. It still uses the existing crop
editor; the shared review capsule, combined focus editor, canonical media edits
and initial saved-note initialization remain subsequent implementation work.
Physical-device/live and HQ-020 qualification remain separate. No automatic
prompts were resumed during this November 15 checkpoint.

### Shared review source increment — 2026-11-15

The next increment replaces Capture's crop-only cover with a single stable-ID
photo/audio/video review session, shared capsule and nested autosaved Field
notes. Thumbnail changes commit optional photo edits; notes navigation does not
commit media. Review Add more commits and returns to capture. Unchanged photos
preserve prepared artifacts. The matching outer review dismissal owns hardware
and deferred-navigation release, including rapid pre-mount cancellation. Child
notes cannot release it. Retained frozen submission returns to existing root
retry/recovery actions without changing the saved request.

The supplied Figma toolbar, selection and notes frames have now been inspected
(the links below identify the exact nodes). Scan quantities, purchases and
analysis banners remain excluded. Independent read-only review found lifecycle
issues in pre-mount dismissal and notes navigation; these were corrected. The
follow-up review of frozen retry, removal and nested playback reported no
further concrete blockers. Focused SwiftLint passed. Native02 failed an
initializer rule; native03 compiled Swift but failed lint. Both failures were
corrected and retained in `/tmp/capture-review-native02.log` and
`/tmp/capture-review-native03.log`. Native04 passed 124 XCTest cases and 11
Swift Testing cases (135 total), with result bundle
`.artifacts/local-ios/845e887f2f0942338770ea1801edfcc8.xcresult` and log
`/tmp/capture-review-native04.log` on November 15. The audio boost UI test also
passed. Keyboard UI qualification remains pending: UI01 exposed duplicate root
toolbar accessibility behind review, now hidden for review's presentation
lifetime. UI02–UI04 then stalled before their first interaction. A UI04 process
sample traced startup to a synchronous Core Location authorization XPC read.

Following Hardening's interface review, the focused review UI test now
explicitly selects a DEBUG-only denied/no-location fixture before live hardware
construction. The fixture requires the UI-test environment, staged-audio seed,
and explicit mock-location argument together. Independent review found no
correctness or scope issue; deterministic tests cover avoiding live construction
and retaining live behavior when opt-ins are incomplete. This fixture cannot
qualify location behavior or close the broader startup concern. UI05 caught an
actor-isolation error in the fixture factory's default closure; the factory is
now explicitly MainActor-isolated and injected at the call site. The adapter was
extracted to `EnvironmentLocationHardware.swift` to preserve the controller's
existing file size ceiling, with ownership checks covering the new boundary.
Follow-up review found no code blocker. UI06 passed all 19 location-controller
and environment-architecture tests in
`.artifacts/local-ios/bd48f8f6e860493692b347caa4d4e737.xcresult`. Its UI test
reached review and reproduced duplicate root toolbar accessibility: the earlier
modifier alone did not resolve it. Root staging toolbar construction is now
suppressed while the matching review presentation owns the toolbar. UI07 passed
the unchanged keyboard and notes-return assertion in
`.artifacts/local-ios/5767b3f866734e2d98ef657aa96df9e9.xcresult` on November 15.
The retained screenshot confirms Identify above the keyboard and exposed a
floating editor Done accessory overlapping the toolbar edge. Field notes now
opts out of that accessory while other editor callers retain it. The augmented
UI08 rerun was refused before building at 19.6 GiB free, below the managed 20
GiB floor. This final visual adjustment passed focused lint but remains
unqualified by native validation; UI07 does not qualify the later adjustment. No
storage floor override, cache cleanup, signed-in simulator change or deployment
occurred.

History's November 15 interface reply reconfirmed that manual `user_selection`
is not supported by the current recipe/wire/recovery contract, and there is no
unified square playback/poster/inference commit API. Therefore manual selection
is not exposed and video currently provides paused playback only. Those approved
requirements, initial editable-note seeding, and the broader native07 check
remain incomplete. This increment does not claim the complete Figma journey or
engine qualification.

The older dated handoff snapshots below are historical evidence and are
superseded by this scoped release. No hosted deployment, activation,
publication, signed-in simulator reset or installation is authorized by
implementation approval.

## Approval history and precedence

On 2026-10-18 the user approved the capture/import flow, contextual toolbar
actions, combined photo gestures and selection clearing, video/audio behavior,
details Save versus cancel semantics, and removal/discard rules in the
step-by-step review. Submission and purchase behavior were recorded as the
intended destination, with allowance integration explicitly deferred at that
time. Purchase policy is now excluded from this proposal as clarified below. The
delivery boundary is approved conditional on alignment with the analysis engine
defined in
[Scan ID History](codex://threads/01a0fe55-d9d3-77e0-90a5-b7eeeaaa74e1). This is
product and delivery-boundary approval, not an instruction to start
implementation.

The November 3 decisions in Photo review UX supersede explicit Save/checkmark
and X/swipe-cancel with autosaved Field notes; clear supplementary notes and
prompt progress when the final media item is removed; and permit optional
on-device candidate-assisted tap selection with immediate fallback. The
then-approved final-import rule was superseded on November 16 by optional item
review and whole-observation Identify/Reanalyze. November 14 Notion
reconciliation and independent planning review clarified
final-input/validation/freeze ordering, immutable request retry, and ownership
gates. Historical approvals remain provenance, not current behavior.

On November 14, the user confirmed that Scans has already been renamed
**Naturebook**, with the **open-book icon** and the same existing library
destination. This is user-confirmed existing behavior, not a new implementation
claim from this review, and introduces no Journal functionality. The approved
top-left control shows goal/persona when capture is empty, replaces it with
trash while a draft exists, and restores goal/persona when the draft clears.
Purchase policies, scan packs, scan-quantity/balance buttons and analysis
banners are explicitly outside both workspace updates and review UX; they are
not remaining product questions, delivery phases or handoff prerequisites for
this work.

The November 14 parity correction explicitly treats mixed-media reanalysis as
existing functionality that History must preserve during its migration, not a
new optional Capture feature. The current History limitation does not redefine
approved product scope. Preserving existing supported combinations needs no new
product approval; a proposal to remove combinations or ship a restricted
experience would require an explicit user decision.

## Authority and dependencies

The linked Notion feature hub owns the approved successor UX. The
[current staged-capture contract](../features-and-hardware/29-staged-capture-review.md)
continues to describe existing behavior. Do not promote this proposal into that
contract until the corresponding implementation and checks land.

Planning context:

- [Capture review discussion](codex://threads/01a1333e-a13c-7ed3-812a-f836191c0cec):
  photo selection/crop, video/audio review, toolbar, settings, and deletion.
- [Simplify capture tools](codex://threads/01a12c47-6f54-7500-bab9-679c2babf9a0):
  Scan/Record only, supplementary Field notes, media-required submission.
- [Consider review-step Add more](codex://threads/01a15127-6a15-7c50-ac8d-18296c86ef36):
  review as the default decision point and intentional additional capture.

The
[IC-1 agreement](../rfcs/initial-completion-history-interface-2026-10-11.md),
[history readiness roadmap](../rfcs/identification-history-alpha-readiness-2026-10-11.md),
and
[native media ownership agreement](../rfcs/client-prepared-media-native-ownership-agreement-2026-10-15.md)
retain authority over shared submission, source ownership, history, and
recovery. This proposal consumes their final interfaces rather than introducing
parallel owners or restoring legacy queue assumptions. The dated handoff check
below records current evidence separately from the October coordination history.

History remains the shared implementation owner and Hardening the interface
reviewer under their agreement. Capture implementation requires the planned
handoff and explicit final-plan approval; this documentation change does not
start implementation, transfer ownership, or alter readiness schedules.

Capture review is an editing client of that engine: it must use its
authoritative original/derivative ownership, preparation recipes, ordered
immutable media and supporting-context freeze, receiving/admission identities,
and exact recovery. Manual selection must be bound to the exact prepared media
in that contract, not transported solely through an older mutable UI/queue
field. No second storage ledger, acceptance path, or reanalysis history writer
is introduced. Recovering an accepted operation must not regenerate evidence or
repeat identification.

The historical October 18 check of Scan ID History found native receiving
locally committed and queue/funding guards under review; Capture/Auth and
retained-state integration were ongoing. These checkpoints were evidence of
progress, not a completed handoff. Before implementation, reconcile the exact
final interfaces and remaining qualification with the engine owner. Unfinished
allowance UX is not one of these prerequisites.

Both relevant History and Hardening prerequisite workstreams must explicitly
complete, with exact source revisions, applicable validation and a safe handoff
of overlapping files. Later version deletion/export and broader
Identification/History redesign are not blanket dependencies or an undefined
full-chat completion endpoint. Active edits in shared files still prevent their
handoff, including when they belong to a later milestone. Require no conflicting
edits/builds and new explicit final-plan implementation approval in this chat.
Idleness, a schema checkpoint, or a planning review does not satisfy these
gates.

## Two overlapping scopes

| Scope             | Responsibility                                                                                                                                                                       | Shared boundary and exclusions                                                                                                                                                                                                                                                                                        |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Workspace updates | Scan/Record selector, goal/persona when empty and trash with a draft, shared toolbar, add-more, Field notes, existing library navigation and hardware visibility                     | Shell owns draft identity, presentation occupancy and routing. Existing funding, goal and navigation owners remain authoritative. Purchase policies, scan packs, scan-quantity/balance buttons, analysis banners and Journal functionality are excluded; retain Naturebook/open-book at the same library destination. |
| Review UX         | Default review after preparation; photo crop/rotation/selection; fixed-square video review; shared audio playback; whole-observation Identify/Reanalyze; optional item edits/removal | Editors return guarded commits to the same draft. They do not own a second toolbar, notes editor, queue, admission path or history writer.                                                                                                                                                                            |
| Joint integration | Stable media IDs/order, toolbar active/content states, autosaved notes, media readiness, whole-observation Identify, discard/reanalysis protection and dismissal barriers            | One implementation writer at a time for overlapping Shell/Staging/Submission files. Review owns its own lifetime; closing notes cannot release review's hardware or route restrictions.                                                                                                                               |

Photo review UX owns interaction-decision provenance, copy/gestures and later
Figma references. This coordinating chat owns the consolidated plan, shared
acceptance and engine handoff. Align at a shared decision/interface change and
at handoff, not through duplicate plans or recurring polling. Named engineering
owners and file assignments remain subject to that explicit handoff.

### Supplied mockups and adjacent workspace work

The five mockups supplied on November 14 illustrate the two scopes. They are
visual references, not a new approval of every state, entitlement, price or
adjacent feature drawn into them. On November 15, the user supplied the
[Identify UX Figma board](https://www.figma.com/design/AVATuIm6rP8wxiYAJg1qGa/Merian?node-id=2694-23954).
Direct Figma design context and screenshots were inspected for the
[review toolbar](https://www.figma.com/design/AVATuIm6rP8wxiYAJg1qGa/Merian?node-id=2757-13630),
[photo selection](https://www.figma.com/design/AVATuIm6rP8wxiYAJg1qGa/Merian?node-id=2694-24086),
[Field notes sheet](https://www.figma.com/design/AVATuIm6rP8wxiYAJg1qGa/Merian?node-id=2757-13674)
and its
[keyboard state](https://www.figma.com/design/AVATuIm6rP8wxiYAJg1qGa/Merian?node-id=2757-14006).
These establish visual references, not completed UI implementation or visual
qualification. The approved rules and exclusions below still take precedence.

- Shared approved direction: two capture modes, contextual trash on the left,
  centered mode/rotation controls, labeled Identify in the draft capsule, photo
  selection and supplementary Field notes. Empty capture shows the existing
  goal/persona control at top left and normal navigation, without a draft
  toolbar/trash. A draft replaces goal/persona with trash; clearing it restores
  goal/persona. Preserve the existing control's purpose; omitted mockup controls
  do not authorize their removal.
- Some frames show tall photo/video content or omit Identify when the keyboard
  is open. Implement the approved canonical square review framing and keep
  Identify accessible above the keyboard; these drawings do not override either
  requirement. Single and multiple imports must submit through
  Identify/Reanalyze without per-item confirmation, including when other
  thumbnails have never been opened.
- Purchase policies, scan packs, scan-quantity/balance buttons and analysis
  banners shown in the mockups are excluded. Their prices, pack counts, purchase
  flows, banner states and placement are not requirements or decisions to
  resolve in this plan. Separate feature records retain their own scope; this
  exclusion does not rescind their approvals or authorize their implementation.
- Retain the already-completed Naturebook label and open-book icon, pointing to
  the same library destination. This is not a new Book/Journal destination and
  does not resume or add Journal functionality.

## Engine interfaces and handoff check — 2026-11-14, 16:26 UTC

Read-only source inspection used local HEAD
`ac8f1737dadf2e7319681a2ae019ab806faf540d` plus explicitly dirty working-tree
files; it is not an exact clean qualification candidate. Notion was fetched
before this documentation update (previous edit November 14, 15:53 UTC). No
application tests, builds, providers or hosted checks ran for this
reconciliation. Earlier source receipts retain their own identities and limits;
this paragraph does not extend them to the moving working tree.

| Interface                                  | Existing owner / evidence                                                                                                                                                                                                                                                                                                                                       | Remaining integration or handoff requirement                                                                                                                                                                                                                                                                                         |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Ordered originals, context and preparation | `CaptureNativePhotoDraftSession.acquire` / `prepare` in [native photo draft session](../../apps/ios/Merian/Features/Capture/Submission/Services/CaptureNativePhotoDraftSession.swift) preserve ordered selection, original references, supporting contexts and prepared recipes                                                                                 | Reuse these immutable ownership rules. `CapturePhotoOriginalPreparationAccess` is local qualification composition, not evidence that the whole redesigned multimedia journey is enabled. Agree the final live adapters and editor commit contract.                                                                                   |
| Saved admission and recovery               | [CaptureNativePhotoSubmissionSession](../../apps/ios/Merian/Features/Capture/Submission/Services/CaptureNativePhotoSubmissionSession.swift), [IC-1](../rfcs/initial-completion-history-interface-2026-10-11.md) and [scan-to-History guide](../development-guides/25-scan-to-history.md) own saved identity, frozen selection and exact recovery                | Consume the tested final API; never recreate an accepted request from current UI state. Complete relevant all-media, account/deletion, uncertain admission and resource qualification. Historical IC-1 requirements are not a claim that every component remains unimplemented.                                                      |
| Shared workspace reanalysis                | History is actively connecting `CaptureReanalysisEditor`, `ActiveScanToolbar`, `CaptureStagingToolbarButtons` and `CaptureStagingToolbarPresentation` to History's version-preserving submission paths                                                                                                                                                          | Not handed off. Shell/Staging, History services/views/models and Insights routing plus tests/README are overlapping dirty surfaces. Preserve History's active writer and original-version protection.                                                                                                                                |
| Initial editable Field Notes               | [NativeInitialApplicationOperations](../../apps/ios/Merian/Core/Data/SharedMediaStorage/NativeInitialApplicationOperations.swift) currently creates scalars with `fieldNotes: nil`; [FieldNotesRepository](../../apps/ios/Merian/Core/Data/FieldNotes/FieldNotesRepository.swift) edits existing records/queued notes and conditionally promotes external notes | Add the approved creation-time, idempotent initialization through the existing initial-creation owner, preserving saved request value/identity and newer mutable notes. The mutable notes API alone does not implement initialization. This is a capture integration deliverable, not evidence that History has already supplied it. |
| Permission/receipt immutability            | Hardening's November 14 reply cites IC-1 revision 3 and reviewed native-media foundations, but keeps HQ-020 open                                                                                                                                                                                                                                                | Retained upload permissions must retain original immutable authority; cached mutable state must not refresh that authority, and ambiguous saves remain consumed. Require exact finding disposition/evidence from the owners before affected interface clearance.                                                                     |

The initial Field Notes integration above and these two additional interface
gaps are concrete successor work, not new product questions or requirements for
History to implement before handoff. Agree their interfaces and implementation
ownership at handoff; qualify them before the successor exposes the behavior:

- **Manual focus:**
  [NormalizedImageFocusRegion](../../apps/ios/Merian/Core/Models/NormalizedImageFocusRegion.swift)
  currently exposes only `vision_objectness` provenance. The native
  [submission selection](../../apps/ios/Merian/Features/Capture/Submission/Models/CaptureNativePhotoSubmissionSelection.swift)
  already binds focus to exact prepared AI bytes and frozen presentation, but
  `user_selection` still needs compatible client/backend/durable recovery
  representation and qualification before UI exposure. Reuse that freeze
  primitive rather than carrying manual focus only in mutable editor state.
- **Canonical video framing:**
  [ObservationVideoPreparation](../../apps/ios/Merian/Core/Data/AnalysisHistory/ObservationVideoPreparation.swift)
  and
  [ObservationVideoManifest](../../apps/ios/Merian/Core/Data/AnalysisHistory/ObservationVideoManifest.swift)
  retain the clip and ordered square inference frames;
  [CaptureScanVideoMediaPreparer](../../apps/ios/Merian/Features/Capture/Scan/Services/CaptureScanVideoMediaPreparer.swift)
  derives display/inference frames with the same composing center. This does not
  establish a shared square playback/poster artifact. The approved default and
  edited playback/thumbnail/inference agreement still requires an explicit
  preparation/commit interface and end-to-end framing evidence. Existing square
  inference frames alone cannot close that requirement.

The [Hardening chat](codex://threads/01a112ae-2c97-77a1-bd53-5a4434510d4c)
explicitly replied: planning can proceed, but capture-redesign implementation
handoff is **not cleared**. Its earlier scoped evidence includes completion416's
three Debug cases (313.788 seconds and repeated allocation audits); corrected
preparation helpers with 24 native tests plus one toolbar UI test, result
`ff5b914d11fa43bda59548f945cd176b`; completion417 review/selection Undo; and
completion419 signed phone installation with user confirmation that existing
scans appear. These are attributed owner reports, not tests rerun here. The
allocation concern does not establish the cause of the intermittent Undo freeze.

Hardening's refreshed reply in turn `01a1dadf-d531-76e1-b2fe-ad5cd12d4235`
supersedes the earlier "helpers remain unrouted" statement: protected photo
reanalysis now uses the shared Capture workspace. It reports Native04 passing
118 focused checks and corrected Native05 passing 28 Swift tests plus one
toolbar UI test, result `f7739d25d33e40a6b30bbb4ffffb3008`. Its inspected record
still had an optimized simulator build in progress, with live handoff
verification separate. This is scoped progress, not multimedia or cumulative
qualification. HQ-020 remains open without a cache shortcut; require a
documented disposition for the affected scope, not an automatic optimization
prerequisite for unrelated UI work.

The [History chat](codex://threads/01a0fe55-d9d3-77e0-90a5-b7eeeaaa74e1) is
actively implementing the separately authorized shared-workspace reanalysis
integration. Its latest progress in turn `01a1dac4-5278-79e3-b65f-5ce4fd51845f`
reports photo integration verified locally, but a remaining backend boundary:
photos, one audio recording and one video use separate request formats; a mixed
toolbar composition cannot yet be saved as one History version. Do not drop
staged media, silently convert sources or claim the full shared-workspace
replacement complete. The parity requirement below governs the multimedia gap:
technical finding disposition cannot silently approve reduced product behavior.
A bounded planning-only request asks for the exact prerequisite checkpoint and
safe file handoff at a natural response boundary. No ownership release has been
received. Do not wait for an undefined full-chat endpoint or interrupt its
current implementation; record the specific handoff when supplied.

The user's earlier schedule pause remains a direction to preserve. Current
scheduler configuration was not inspected or changed; dated continuation/status
records are not continuously verified state. The older October 18 continuation
snapshot is retained above only as history.

Before implementation, replace this snapshot with an explicit handoff naming the
exact integrated source, applicable evidence/finding disposition, live initial
and reanalysis interfaces, overlapping files and current writer, and absence of
conflicting edits/builds. Neither the current dirty tree nor Hardening's
completed response transfers ownership. New user approval of the final
implementation plan is still required.

## History mixed-media parity requirement — 2026-11-14

Mixed media means different physical media types in one observation, such as a
photo plus an audio recording. Two photos or two audio recordings are
multiple-item, same-type compositions. Preserve the previously supported
combinations and their existing capacity/entitlement rules; do not infer new
combinations or change limits merely because a payload uses arrays.

The read-only comparison at HEAD `ac8f1737dadf2e7319681a2ae019ab806faf540d` plus
the dirty working tree found:

- The ordinary initial-capture path still projects, queues and analyzes images,
  audio and video together through
  [submitStagedCapture](../../apps/ios/Merian/Features/Capture/Submission/ViewModels/CaptureWorkspaceViewModel+VisualSubmission.swift).
  [IdentificationPreflight](../../apps/ios/Merian/Core/Network/Inference/IdentificationPreflight.swift)
  explicitly recognizes photo plus audio. No live production assignments were
  found for the optional photo-only submission dependencies in that inspection.
  This is static evidence, not a new runtime or deployed-state qualification.
- The pre-History submission path at the parent of commit
  `2fed95a408692fffeb5d2752a37ac550f97afc2d` carried combined media through the
  existing refinement flow. In contrast, the current
  [CaptureReanalysisPreparation](../../apps/ios/Merian/Features/Capture/Submission/Models/CaptureReanalysisPreparation.swift)
  rejects audio/video, and the dirty
  [CaptureReanalysisEditor](../../apps/ios/Merian/Features/Capture/Shell/ViewModels/CaptureReanalysisEditor.swift)
  photo adapter requires those arrays to be empty. The new History route has an
  unfinished parity gap; this is not removal of fresh capture's general
  mixed-media contract or an approved product restriction.

History owns restoring this parity through its submission contract and native
adapters; Hardening owns interface review. The capture redesign consumes the
qualified interfaces after explicit handoff. The requirement is one ordered
composition, including its supporting context, producing one immutable History
version under one logical admission/execution, with saved request identity and
exact retry/recovery. Preserve original/derivative ownership, source provenance,
account/deletion fences and already-admitted operations. Do not omit media,
silently convert it, identify each item as a separate observation, or route
around History protection through the legacy mutation path.

Handoff must include a prior-versus-new supported-combination/capacity matrix,
starting with photo plus audio and distinguishing same-type multiple items from
mixed types. Qualify retained originals, added and edited media, ordered text,
reopening, submission, failures, uncertain admission, offline/restart recovery,
and account/deletion changes. Include fresh-capture nonregression and evidence
that retries do not duplicate execution or overwrite accepted evidence. Each row
needs exact source and applicable validation, not just staging or photo-route
tests. Unsupported combinations remain explicit; this requirement does not
invent additional capacity or capabilities.

The photo-only route remains an intermediate checkpoint. Full replacement and
the affected mixed-media handoff stay incomplete until parity is demonstrated,
unless the user explicitly approves a product-scope change. This is a relevant
History prerequisite, not an undefined wait for later export/redesign work.
Manual focus, canonical square video artifacts and one-time initial Field Notes
remain separate successor deliverables with agreed interfaces/ownership. This
planning correction authorizes no implementation or release; both workstream
handoffs and this chat's final implementation approval remain required.

Coordination checked November 14, 18:00 UTC: History acknowledged the correction
in turn `01a1db2e-5101-7531-b6f0-5d2753f2e917` and retained responsibility for
restoring supported compositions. Hardening acknowledged in turn
`01a1db35-f630-7a50-a9bd-33688c5cfb02`, finding no technical inconsistency and
confirming the parity matrix, one-version execution/recovery requirement and
explicit approval for reduced scope. These are planning acknowledgements, not
passing parity evidence, completion or ownership release.

## Decisions and superseded alternatives

| Topic               | Consolidated direction                                                        |
| ------------------- | ----------------------------------------------------------------------------- |
| Capture tools       | Scan for photo/video, Record for audio; remove standalone Describe            |
| Normal capture      | Prepare media, then open review                                               |
| Additional evidence | Review toolbar plus returns to capture with the draft preserved               |
| Submission          | Labeled Identify submits the whole ready observation                          |
| Settings            | One Identify automatically toggle, off by default                             |
| Photo editor        | One combined crop/subject view; no tabs                                       |
| Selection           | Tap and corner adjustment; no outline drawing or interior-box dragging        |
| Field notes         | Observation-wide autosaved text/prompt state in a guarded session-owned sheet |
| Toolbar             | Shared draft capsule on capture and review, including labeled Identify        |
| Video               | Square fixed crop/rotation and playback; no subject tracking                  |
| Audio               | Reuse shared spectrogram player; no new editing engine                        |

This supersedes the three-choice After capture setting, separate Subject/Crop
modes, default stage-first routing, standalone Use photo/video/audio completion
buttons, and icon-only submission in earlier review proposals. Add more is now
the toolbar plus action rather than a separate large button. Imported media uses
default preparation and optional review; Identify/Reanalyze submits the whole
staged observation.

## Capture and review flow

1. With an empty draft, show the normal capture controls and navigation.
2. Prepare a new photo, video, or audio recording and open its review, unless an
   eligible fresh automatic capture submits directly.
3. Show the current item in the draft toolbar immediately, with a distinct
   active ring. Thumbnail taps switch review items after committing valid
   pending edits.
4. The plus in review commits edits and returns to capture to add evidence to
   the same observation. The plus on capture retains the existing library-add
   action; camera shutter and Record remain available independently. Use a
   first-use Add more hint and destination-specific accessibility labels.
5. Field notes opens the same editor from capture or review and returns to the
   originating surface, selected item, and framing.
6. Identify finishes input/dictation, persists the final guarded draft state,
   commits valid media edits and validates the entire composition. Only then
   freeze immutable media/focus/supporting descriptions and construct the saved
   request. It never means only the displayed item. Finalization, persistence or
   preparation failure does not submit and retains the editable draft and valid
   committed state for review/retry. A preparing state blocks duplicate taps.

The plus disappears only when usable capacity is exhausted. Preserve the
existing Free/Pro, video, reanalysis, and upgrade-placeholder policies: ordinary
Free has one physical item and Pro two; text does not consume a media slot. Do
not change entitlements to fit a mockup. Preserve chronological order and
insertion times.

Keep the capsule and labeled Identify anchored consistently across capture and
review. At small widths or accessibility sizes, wrap complete nodes above the
action row using existing layout policy; do not shrink touch targets or clip
items. The selected thumbnail and all draft evidence must remain discoverable.

Imported photos open the shared review presentation and always require manual
submission, even when automatic identification is enabled. Individual item
review is optional: users need not visit, edit or confirm every thumbnail. There
is no outstanding-review queue or Next action.

Identify for a new observation, or Reanalyze for an existing one, submits the
whole staged observation from any selected item or from Field notes. Finalize
input/dictation and persist guarded text changes, commit pending displayed-media
edits, validate all staged media, then freeze and submit through the existing
submission owner. Unvisited imports use valid default prepared artifacts; native
photo originals use a stable normalized centered-square recipe. Failed edits or
preparation block submission while preserving the draft. Later admission failure
preserves committed state for manual retry; accepted operations retain exact
saved request identity. Thumbnail navigation may commit edits but is never
confirmation. Removing an item removes its evidence; adding more introduces no
review requirement. Actual media readiness, account, capacity and admission
guards still apply to the entire observation.

### Shared chrome and toolbar states

Trash is left and mode/rotation controls are centered across capture and review.
Preserve supported Scan/Record ordering when removing Describe. Empty capture
shows the existing goal/persona control at top left and hides trash and the
draft toolbar. A draft replaces goal/persona with trash at that position;
clearing the draft restores goal/persona. When a draft exists, the shared
capsule includes chronological media, plus, Field notes and Identify. Keep
Naturebook with the open-book icon routed to the existing library; no Journal
functionality is added.

| State                       | Appearance                                         |
| --------------------------- | -------------------------------------------------- |
| Notes empty, sheet closed   | Outline icon, dashed neutral border                |
| Notes present, sheet closed | Filled icon, solid neutral border                  |
| Notes sheet open            | Blue border; outline/filled still reflects content |
| Selected media destination  | Blue active ring                                   |
| Adding another capture      | Blue active ring on plus                           |

Only the active destination is blue. Field notes takes precedence while open;
closing restores the originating destination. Content and active state are
independent and need equivalent accessibility states, not color alone.

### Setting and automatic attempts

**Identify automatically** — default off.

> Identify immediately after taking a photo or finishing a recording, without
> reviewing first.

Preserve the existing explicit Auto-submit boolean preference; do not introduce
an enum migration. Eligibility is established only for a fresh capture with an
empty composition, not reanalysis. Existing media, pending Field notes, or
choosing to add more keeps the composition manual. Turning the setting on never
submits an existing draft. Turning it off revokes a pending automatic attempt;
turning it back on does not rearm it. Imports require manual whole-observation
submission, with no per-item confirmation. Failures leave a manual retry.
Playback, selection, and edits are never required.

### Removal and discard

In review, trash offers Remove photo/video/audio and Discard observation… when
other media or Field notes exist. With just one media item and no Field notes,
remove it directly and return to empty capture. Removing an item from multiple
items opens the next chronological item, or the preceding item if the removed
one was last.

Removing the final staged media item clears its supplementary Field notes and
prompt progress, stops dictation and invalidates pending saves/callbacks. Return
to default empty capture with normal navigation and no draft toolbar/trash.
Removing an item while other media remains preserves notes. No new confirmation
or Undo journey is introduced: retain the contextual menu and whole-discard
confirmation below. These fresh-draft rules do not delete accepted history or
override protected reanalysis cancellation.

On capture, with no selected media, trash discards the whole observation. Hide
it for an empty draft. Whole-draft discard asks:

> Discard observation? All added photos, recordings, and details will be
> removed.

Actions: Keep editing / Discard. Bind confirmation to the originating draft and
respect admission/ownership locks. Reanalysis retains its existing protected
cancel behavior and original observation. Removal never deletes source-library
media or accepted history.

## Review surfaces

### Photo

Top row: trash left and left/right quarter-turn rotation centered. No
scan-quantity/balance button is part of this work. Title: Review photo. A fixed
square viewport represents the actual crop. No Subject/Crop switch.

| State            | Subtitle                                             | Below photo                                |
| ---------------- | ---------------------------------------------------- | ------------------------------------------ |
| Automatic        | Naturebook will find the subject automatically.      | Pinch to zoom, drag to move, tap to select |
| Manual selection | Tap to reposition selection. Drag corners to adjust. | Clear selection                            |

Use thin rounded white corner brackets, without tint, dimming, automatic
brackets, or an additional label. Clear selection restores automatic detection.

- Run optional on-device candidate detection when review opens, keeping results
  invisible until a tap. Select the smallest suitable detected region containing
  the tap. If no suitable candidate is ready, immediately create an adjustable
  fallback box. Retapping selects a suitable candidate at the new location, or
  recenters the existing box while preserving its size. Initial fallback size is
  40% of viewport width/height, tunable rather than a fixed product requirement.
- Detection never blocks interaction or submission and introduces no network
  call or additional charge. Late results cannot replace user input. Fence
  candidates to source/item/revision and transforms, including dismissal and
  item changes. Candidate quality/latency is not a separate release gate; UI
  responsiveness, safe resource use and immediate fallback remain mandatory.
- Drag a corner changes that corner with the opposite corner fixed. Use at least
  44-point hit targets and prioritize them over one-finger photo panning.
- All other one-finger dragging, including inside the box, pans the photo.
  Two-finger pinch zooms it. Rotation transforms photo and selection together.
- Use a 10-point tap/drag threshold; pan/pinch/resize cannot emit a trailing
  tap. Minimum completed interactive box dimension is 64 points, bounded by
  viewport; prevent corners crossing. No drag-to-outline or interior movement
  gesture.
- Selection attaches to source content. Evaluate crop exclusion at gesture end;
  if selected content is excluded beyond numerical tolerance, clear selection
  and announce Selection cleared because the crop changed.

Provide accessible selection creation, movement, resizing, and crop adjustments.
The avatar cropper remains outside this change.

### Video

Title: Review video. Subtitle: Pinch to zoom, drag to move. Rotation buttons use
the same top-center placement as photos. A single fixed square crop/rotation
applies across the clip; no tracking, selection, trim, or animated crop.

Initial preparation produces playback, thumbnail/display and inference artifacts
using the same canonical square crop. Review without edits preserves those
artifacts. Changed commits regenerate matching artifacts from the original.

Start paused. Below the viewport show play/pause, scrubber, one elapsed timer,
and preview sound toggle. Use actual duration, including clips under five
seconds. Crop, rotation, or seeking pauses playback and leaves it paused. At
end, Play restarts. Sound toggle changes preview only. Keep controls outside the
crop gesture surface.

### Audio

Title: Review audio. Subtitle: Listen back before identifying.

Reuse AudioPlaybackCarouselPage and its spectrogram, centered fading play/pause,
seek behavior, elapsed/total timing, and boost states. Begin paused with Play
visible; use existing reveal/hide behavior while playing. Toolbar and shell do
not fade. Add no separate playback row, mute button, trimming, isolation, or
frequency selection. Boost is playback-only; original audio remains evidence.
Stop playback when leaving the item, confirming, removing, or dismissing, and
preserve shared audio-session, interruption, source-lease, and cleanup behavior.

## Field notes session and initialization

Use Field notes with the prompt What did you notice? and accessibility labels
Add field notes / Edit field notes. This is supplementary observation-wide
context, not a primary capture mode. Keep optional guided prompts, typing and
dictation; completing the walkthrough is not required. The toolbar entry remains
available at full media capacity.

- Open by tapping the notes icon or swiping up from the toolbar/handle only.
  Media gestures do not open the sheet. Open/reopen at initial partial height,
  keyboard hidden, restoring autosaved text and prompt progress. Keep some media
  visible and the toolbar accessible.
- Input tap expands and focuses; dragging up expands; the microphone starts the
  dictation flow. Identify remains accessible above the keyboard. A downward
  swipe within the text area dismisses the keyboard. Dragging the handle down or
  tapping outside closes the sheet, preserves notes and stops dictation.
- Text and prompt changes automatically save to the observation draft. There is
  no Save/checkmark or X/swipe-to-cancel. Clearing text clears supporting
  context; dismissing is not submission. Returning to review restores
  item/framing.
- Replace workspace-bound Describe and `.describe` lifecycle assumptions, not
  just the view. Prompts is navigation within the same notes session, not a
  sibling workspace sheet. Closing/resetting nested navigation neither dismisses
  the outer sheet nor releases camera, route or import ownership.
- Every write retains session/draft/account identity and original mutation
  guards. Occupancy blocks competing capture, queued hardware shutter callbacks,
  routes, imports and mode changes; the sheet's own guarded writes and explicit
  Identify remain permitted. Never bypass locks globally.
- Occupancy lasts through matching outer dismissal completion. Closing releases
  only that notes session. Shell reevaluates underlying review, account and
  draft guards before hardware or deferred navigation can resume. Review owns
  its own lifetime; stale callbacks cannot release a newer session or restore
  cleared notes after discard/final-media removal.
- Backgrounding stops dictation and fences stale work while retaining saved
  state. Returning does not automatically resume dictation or camera behind the
  sheet. Retain cancellation, account-change, rapid reopen and stale-callback
  coverage, adapting the old cancellation tests to autosave rather than reviving
  discarded Save/cancel semantics.
- Identify/Reanalyze directly from the open sheet follows the final-input,
  media-commit, whole-observation validation and freeze order above. Individual
  imports do not require review or confirmation. Failed dictation finalization
  leaves captured text for user review before retry. Other preparation/admission
  failures preserve retryable state.

### Three separate text values

1. Pre-submit supporting context and prompt progress autosave into the draft.
2. Identify freezes the submitted description as immutable evidence attached to
   the exact media/request; preserve it through History, Undo and recovery.
3. A new observation initializes editable Field Notes from that frozen
   description without a label. Snapshot and merge pre-existing notes once when
   constructing the initial creation request, saving the value and stable
   request identity. Retries/relaunch reuse that value and identity instead of
   rereading or appending to already-initialized notes. Later editable-note
   edits/clears win over stale initialization/completion through the existing
   notes owner; queue handoff carries the latest editable-note state separately.
   They never rewrite the saved request or immutable submitted evidence.

Field Notes initialization does not publish notes or change observation
visibility. Journal, historical backfill and reanalysis-note changes are
excluded. The final engine handoff must identify the concrete initial-request
and mutable notes interfaces; this plan does not invent a second persistence
system.

### Media-required submission and compatibility

Every newly requested initial identification and reanalysis requires actual
photo, video or audio media, with optional text. Existing original media is
sufficient for reanalysis; missing/removed source media requires replacement or
blocked submission. Video reanalysis is included without automatically enabling
unsupported video publication, review or other actions. Do not restore
standalone Describe or the standalone no-media text-history/editor/reanalysis
journey. Preserve historical text records and exact server-admitted operation
recovery. Locally queued text-only requests not yet server-admitted are not
accepted replays: preserve their drafts and require explicit media/remediation
for fresh admission, never silently rewrite a saved operation.

## Media integrity and submission integration

Use the final native media-ownership interface supplied by the prerequisite
work. Retain exact originals when that owner requires them; a bounded editor
derivative must not replace canonical evidence or establish a competing cleanup
owner.

- Initial camera review must reproduce the composing-center crop. Imported
  review likewise uses its prepared framing. Unchanged or selection-only
  confirmation preserves prepared inference/display bytes exactly.
- Save crop and selection relative to the upright immutable source, with
  quarter-turn rotation. Screen offsets are temporary. Reopening or resizing the
  viewport cannot shift framing. Use an immutable lossless editor source bounded
  by the display cap (currently 2,048 pixels), separate from tier-sized
  inference previews. Crop only from a suitable source, never prior crops.
- If editor source is unavailable, allow unchanged/selection-only confirmation
  with prepared media; disable crop changes with a recoverable error. Missing
  required canonical evidence still blocks submission under the source contract.
- Retain original video for editing. Preview transforms without per-gesture
  export. On changed commit, generate square playback, thumbnail, display and
  inference frames using one transform and sampling timeline. Preserve audio
  sync and evidence. Default prepared playback must match default framing too.
- Unchanged review does not export again. Respect existing size, duration,
  encoding, timeout, thermal, and cancellation limits. Failed export must not
  substitute an uncropped clip. Commit replacement artifacts atomically.
- Preparation owns provisional artifacts until adoption. Fence stale operations
  and active readers; failed commits retain prior state and retryable edits.
  Cleanup must use the handoff's source/derivative owner, with exact acceptance
  and recovery rules. Do not invent a second draft persistence system.

Extend the active focus contract with user_selection alongside
vision_objectness. Manual input overrides automatic detection; fence late
results by item/revision. Validate finite, positive, in-bounds final-image
rectangles. Reject malformed manual input rather than silently dropping it;
automatic saliency thresholds do not apply. Map source selections into top-left
normalized final-crop coordinates. Provider instructions prioritize the chosen
subject using the full crop for context; selection is not taxonomic proof. Add
no extra remote/provider detection call, region image, or scan charge. The
optional on-device candidate pass assists manual selection only. Preserve
first-photo local-analysis behavior.

Freeze effective focus with final media and the final supporting description
after guarded preparation/validation and before admission. Preserve it in the
active request, durable representation, replay and analysis overlay. Analysis
shows the submitted rectangle without editing that only changes presentation.
Integrate with the final History/Hardening contract; do not assume the earlier
legacy descriptor-JSON-only design is still sufficient. Dormant initial-analysis
schema activation is not authorized by this proposal.

### Scope exclusions and existing guards

Purchase policies, scan packs, scan-quantity/balance buttons and analysis
banners are excluded from both work packages. Do not design their flows,
reconcile their prices or banner placement, or schedule their integration as
part of capture delivery. Journal functionality is also excluded; Naturebook
retains the same existing library destination.

Preserve existing funding/admission, entitlements and capacity guards, including
existing draft-preservation behavior when current UI is presented. This is a
compatibility constraint, not a purchase-policy redesign or an allowance
readiness gate. No substitute allowance service or weakened admission is
authorized.

## Delivery and acceptance

| Phase                        | Deliverable and exit condition                                                                                                 |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| 0. Reconcile prerequisites   | Explicit source revision, validation evidence, ownership handoff, and final-plan approval; no conflicting shared writer        |
| 1. Shared capture foundation | Scan/Record, autosaved guarded Field notes, media-required composition, setting copy, and draft guards                         |
| 2. Review and toolbar        | Default review, shared capsule, item switching, notes, plus, imports, discard/removal, and whole-draft Identify                |
| 3. Media editors             | Combined photo selection/crop, consistent video artifacts, reused audio playback, source integrity                             |
| 4. Submission integration    | Manual-focus compatibility, frozen evidence, one-time editable Field Notes initialization, existing funding and exact recovery |
| 5. Qualification             | Focused and complete surface gates, device journeys, docs promotion, separately authorized release                             |

The authoritative freeze/admission/recovery interface must be established before
any submission path in phases 1–4; no phase permits an interim parallel owner.
Backend acceptance of manual focus must precede client exposure. Use gated
integration while compatibility is incomplete; older-server silent loss is not
acceptable. Phases describe dependencies, not permission to implement or deploy.

Acceptance must cover:

- History's supported-combination parity matrix, including photo plus audio as
  one version, ordered evidence, retained/new/edited media, reopening and exact
  recovery; fresh initial mixed-media capture remains unaffected. Photo-only
  verification cannot close this requirement.
- Empty capture shows goal/persona; creating a draft replaces it with trash;
  whole-draft clearing and final-media removal restore goal/persona. Retain
  Naturebook/open-book and the existing library route without Journal behavior.
- Default/automatic fresh capture, existing drafts, optional imported-item
  reviews, setting off/on races, whole-draft submit, and failed commit recovery.
- Toolbar selection/order, capacity/upgrade behavior, Field notes indicator,
  wrapped accessibility layout, and media removal versus whole-draft discard.
- Field notes autosave/empty clears, keyboard/handle/outside dismissal, final
  dictation, direct Identify and duplicate taps; nested prompt navigation,
  queued hardware shutter, deferred routes/imports, background return, rapid
  reopen, stale callbacks, account cancellation and layered dismissal occupancy.
- Single and multiple imports submit all staged media with Identify/Reanalyze
  from any thumbnail or the notes sheet, without visiting other items. Default
  square artifacts match review framing. Failed edits/preparation prevent
  admission; admission failure preserves committed state and accepted replay
  identity. No Next button or per-item confirmation gate exists.
- Final-media removal clears notes/prompt state and fences dictation/pending
  saves; other-item removal preserves notes. Initial Field Notes merge happens
  once across retry/restart; later edits/clears survive stale completion without
  changing evidence, publication or visibility.
- Invisible candidates, smallest suitable overlapping candidate, immediate
  fallback on delay/failure, retap with/without candidates and stale-result
  fencing after crop/rotation/item changes. Active/content states stay distinct.
- Off-center camera fixture and byte equality for unchanged/selection-only
  edits; all rotations, viewport sizes, tap/resize/pan conflicts, and repeated
  edits.
- Video preview/export/inference agreement, seeking, audio sync, export failure,
  cancellation, size bounds, and retention. Audio shared-player behavior and
  Explore/Insight regression checks, boost semantics, and source leases.
- Source/account ownership, stale work, exact failed/ambiguous acceptance,
  media-required admission, immutable submitted description/focus, recovery, and
  existing funding behavior. Purchase-policy, scan-pack and analysis-banner
  acceptance belongs outside this plan.
- VoiceOver, Dynamic Type, touch targets, smaller phones, Reduce Motion and
  transparency/thermal constraints. Physical-device playback/export/memory and
  interruption evidence remains separate from simulator tests.

Run appropriate focused tests then complete affected-surface gates, iOS builds
through make ios-local-build, and applicable Deno/contract checks. During
implementation synchronize the current staged-capture, camera,
Describe-to-Field-Notes/audio, image pipeline, API/offline, Settings/owner
README, and testing contracts. Record actual results; do not claim planned
checks passed. No source or runtime checks are established by this
documentation-only consolidation.

Location/field-data controls in review, new video/audio library imports, video
tracking, audio isolation/editing, avatar edits, and historical UI redesign are
outside this proposal. Existing historical records and evidence remain intact.

## November 21 — full-aspect manual selection correction

The review selector now receives an explicit image basis and the current
submission-owner capability. A verified prepared artifact uses a fitted
full-aspect preview and identity focus coordinates while preserving its bytes.
Native originals stay on the retained-source recipe path. Unknown bases cannot
enable selection by inference from nonempty bytes or disabled crop controls.
Selecting on a full-aspect native photo preserves its identity geometry and
aspect; an actual framing gesture enters square framing.

The coordinated local Swift/Deno/SQL acceptance extension permits
`nativeSelectedStillImageV2` with a null crop only for identity rotation, scale
and offsets, no camera center, and valid user selection. Existing V9 fingerprint
framing and older manifest semantics are unchanged. Deno unit and migration
static checks pass. Native43 passed 20 Swift Testing checks across four suites;
its 118 XCTest methods had one external-import test that observed staging before
the awaited inbox cleanup and draft completion. The successor waits for
completion while preserving the review/inbox assertions. All 3,459 source pins
and 32 fixtures matched after exit; archive SHA-256:
`7c83001648d5bf1067e9ee91586a28ef639668f5b928558e244a1e15b86ac41f`. The overall
native43 run remains failed.

Fresh disposable replay43 applied the current migrations and passed all 221 SQL
catalogs / 12,505 assertions. The subsequent Edge/SQL parity test stopped before
querying because its sandbox lacked the Postgres driver's `PGAPPNAME`
permission. The unique stack was removed. Replay44 repeats qualification with
explicit Postgres environment permissions and an explicit disposable database
target. The earlier broad Edge run's default-database schema failures do not
qualify the current schema. Its stale account-deletion source assertion was
corrected to check the operation-marker callbacks; all six focused contract
tests pass.

Replay44 completed against the explicit disposable target: all 221 SQL catalogs
/ 12,505 assertions, the actual initial-evidence database parity test, strict
database lint, and 4,851 Edge tests / 1,316 steps passed. All 1,829 copied Edge
source hashes matched after exit and the unique stack was removed. Supabase
tooling, recursive formatting/lint, and all 130 Edge entrypoint type checks also
passed. These results qualify the local backend candidate, not deployment.

Native44 passed the corrected import-completion regression but failed the
journal rollback check: store-level bulk deletion did not preserve source rows
before save. Native45's identifier-based successor crashed on SwiftData future
backing objects. Neither run is green. Native46 uses fetched model instances,
excludes pending changes from its persisted pagination, and checks stable unique
ordering and exact row counts. Native46 stopped at strict formatting checks;
native47 then passed disk/in-memory cross-page, rollback and lost-save
acknowledgement tests, cleanup-only audit scopes without reopening normal
capture admission, and camera selection coordinates when adding a photo during
reanalysis. Its overall result remains failed: two video cleanup tests used
nested temporary files outside the production cleanup namespace. The successor
fixtures use the same flat temporary paths as the camera and playback preparer;
production cleanup has not been broadened. Native47's 3,462 source pins and 32
fixtures matched at exit; archive SHA-256:
`9c6a66e25ff80f011f315c882b6023ae4bdfe590d6c26441d480234f883dd127`.

Native48 passed 32 methods across four suites, qualifying descriptor-only
physical manifest replay, interruption and retry, replacement/link/foreign-file
rejection, and revalidated absence proofs alongside the corrected video
fixtures. Native49 additionally passed retirement-phase fencing, failed-open
lock release, and cleanup journal tests, but the overall run failed four
receiving/ordinary-hold parameter cases. Its 3,464 source pins and 32 fixtures
matched after exit; archive SHA-256:
`43776c356497e3f6b604653391ad2bcf996cd59acb277ebc9c1a1f67d2e3a19e`.

Those cases use a shared metadata fixture that inserts an opaque unanchored
ordinary draft. The whole-store erasure audit correctly rejects that row;
current AppV2 producers create package and membership together. Native50 asserts
that rejection, removes only the exact synthetic row, and then checks the valid
receiving and ordinary-hold graph. It also checks that an existing V74 carrier
blocks new initial-erasure admission; cold continuation retains its separate
exact-operation journal route. Native50 passed all eight methods in two suites;
its 3,464 source pins and 32 fixtures matched at exit. Archive SHA-256:
`e97379f1a7daef781daf243ee3d5d87a836720e4be007b8fae0523d87b0e567d`.

Native51 stopped at compilation on a missing throwing-call annotation; no test
pass is claimed. Native52 corrected that annotation and passed 20 methods in two
suites, qualifying the descriptor-held terminal receipt, interrupted receipt
writes, atomic recovery-record retirement, lost acknowledgements, and cold
terminal recovery. All 3,464 sources and 32 fixtures matched at exit. Archive
SHA-256: `e614a7f1fe4ce273982abca99fec6f535b38ea0554a08e6fedda92a0e949d31f`.

Native53 passed 24 methods in three suites. All 3,466 source pins and 32
fixtures matched after exit; archive SHA-256:
`4427d7a438661e9d30de8bdc84c7a111a897a215b0db38dc3178159176428bb1`. The bounded
manifest spool candidate sorts at most 128 entries in memory and merges
anonymous scratch files into deterministic pages; scratch storage contains
metadata only and grants no deletion authority. Successful earlier native
removals can leave empty package directories after their rows are removed, so
manifest size cannot be inferred from row count. The production owner must
independently audit the exact marked namespace under the accepted whole-library
operation, reject foreign/noncanonical entries, and check both source-to-file
and file-to-source ownership before deletion.

Native54 stopped at a Swift Testing macro compiler diagnostic in its fixture; no
tests passed in that run. Native55 simplified the assertion and passed all 20
methods in three suites, including deletion-scope revocation and replacement of
the terminal receipt during recovery. All 3,468 source pins and 32 fixtures
matched after exit; archive SHA-256:
`df868ee97150da47fdba6bd5551cde62d2f65c2ae453f6d78152b78f5788559d`.

The typed cleanup-only parent opener and manifest yielding/large-empty-directory
regression are qualified as components. The opener retains existing startup
provenance and store fence, independently reads the Core Data store UUID, holds
the existing control parent and validates its creation receipt. Terminal
recovery matches the descriptor-held candidate to the exact accepted operation,
store and parent before requiring zero native rows and empty physical contents.
Accepted deletion authorizes its captured local library after verified sign-out;
it does not require a surviving signed-in user or library-owner marker. Sign-out
still checks its journal's source owner. These remain inactive integration
components, not passing end-to-end account cleanup.

At the native55 checkpoint the physical owner was disconnected from production
account cleanup. The November 21 integration update below supersedes that wiring
status; cumulative acceptance remains open. No deployment or installed-build
activation is implied.

Native56 stopped at the disk-space guard. Native57 compiled, but the three new
source-opening test methods failed during shared fixture initialization (13
cases); native58 localized that failure. The fixture had retained a parent URL
constructed before directory creation rather than forwarding the exact discovery
URL. Native59 corrected that transfer and passed 11 methods in one suite,
including Capture prefix refusal, post-open replacement, header/control binding,
and retained parent/lock lifetime. All 3,468 source pins and 32 runtime fixtures
matched after exit; archive SHA-256:
`115ac1d1be64f63eaed28b6b87316801eba4767592c56736374cd8988c96ff68`. The failed
attempts remain retained. Native58 and native59 also each retained an initial
disk-preflight refusal before their test reruns.

The cleanup owner opens and holds all five registered base directories, checks
the exact bootstrap chain and markers, and validates Capture creation prefixes
without completing them. Unreceipted paths remain blocked. The next candidate
adds an applied-retained derivative work/lease check and a fixed-depth photo
inventory visitor, including empty owner/package directories. That visitor is
read-only descriptive evidence; it does not prove a file's database ownership or
authorize deletion. Complete artifact ownership joins, production purge
integration and cumulative end-to-end validation remain open.

Authorized storage cleanup preserved dependencies and test evidence. Eight older
Capture XCResults now have lossless `.xcresult.tar.gz` archives next to their
original paths, with per-file SHA-256 verification manifests and restore
commands. The superseded iOS 27.0.1 device-symbol cache was removed; current iOS
27.2 symbols and device/simulator user data were preserved.

## November 21 — account cleanup production wiring candidate

The shared accepted whole-library owner is now called by sign-out, account
deletion and cold deletion recovery. It retains the exact accepted operation,
closed/joined runtime, startup admission, store and parent through native
manifest retirement and the existing generic purge. Its completion rechecks
physical absence and zero native rows before and after awaited cleanup, before
outer acknowledgement. An absent parent uses a retained store fence and exact
absence probe; an existing empty parent independently validates its creation
receipt and any terminal evidence. Neither route treats an old terminal receipt
as authorization for a new account operation.

History and Hardening confirmed the whole-library manifest may record an
interrupted original descriptor or reserved empty Capture partial after the
complete semantic audit and writer drain. The immutable raw graph binds the
request fingerprint; manifest directory/file identities bind its physical slots.
No normal admission, ready promotion or per-original abandonment proof is
inferred. Preparing recovery rebuilds the exact manifest header before
unlinking; replacement, nonempty unreceipted Capture partials and links are
rejected. Unreceipted directory prefixes remain blocked. The
[storage owner README](../../apps/ios/Merian/Core/Data/SharedMediaStorage/README.md)
records these implementation boundaries.

Native60 was interrupted and is not a full pass. Native61 passed 19 of 20 test
methods, including all three retained applied-derivative audit cases; its image
fixture used a MIME type where the validator requires a UTI. The fixture now
uses `public.png`. Native62 and native63 stopped at compilation; native64
stopped at SwiftLint before tests. Their successors correct actor isolation,
throwing-call annotations and a redundant switch break. Each run's source and
fixture hashes matched after exit, and the failed evidence is retained. Native65
stopped at a throwing-call annotation in a test. Native66 passed 32 of 34
methods but exposed the Capture initial-audit purpose omission and an invalid
Photo fixture. Native67 compiled the correction, but matched zero tests; it
provides no runtime qualification. Native68 passed 19 of 20 Parent methods,
including all four Capture empty-partial cases and the normal-admission
rejection. Its Photo fixture wrote bytes after preparing a request without
acquiring a reservation; the aggregate owner correctly refused those unowned
bytes. All 3,475 source and 32 fixture pins matched after each run.

The successor uses real acquisition reservation and failed-loader settlement,
asserts the exact held receipt/allocation and absent terminal proof, then adds
the bounded interrupted partial. The unreserved-file case remains a negative
regression; production Photo checks are unchanged. Native69 qualifies this
fixture and the actual deletion adapter through native-terminal/History-file
failure and a sessionless fresh-coordinator retry. It also checks parent
creation/replacement across the awaited generic cleanup. Fresh coordinator
recovery on the same ModelContainer is distinct from process/store-reopen
evidence. Hardening found no source blocker in the private initial-audit factory
or isolated DEBUG test seam; these reviews do not replace runtime results.
Delivery remains in progress and the successor remains inactive.

Native69 exited successfully: all 48 methods in five suites passed, including
the corrected Photo acquisition fixtures, both account-cleanup adapter joins,
Capture partial refusal and interrupted manifest recovery. All 3,475 source and
32 fixture pins remained unchanged; archive SHA-256:
`51b39852d02263944621ee89d83c4cceb2ab64d12ab2b0b8af67e070ebf79e97`.

The next candidate removes nested full-graph audits from completion checkpoints.
It retains physical/store/operation checks around one complete zero-row audit,
keeps the full public validation wrappers, and adds a deterministic graph-pass
count plus new-row rejection for absent, empty and retired libraries. The app
lifetime coordinator moves from the Core root to App Lifecycle; accepted library
cleanup has a separate cohesive owner, with private admission/runtime state
remaining in the coordinator. Hardening found no lost source fence in this
change. Updated UI checks follow two capture workspaces and autosaved Field
Notes. Architecture guard drift in other affected storage owners and final
UI/runtime qualification remain open; these changes are not yet a passing
successor.
