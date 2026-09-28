# Adaptive staged toolbar: implementation and validation

Recorded 27 September 2026. This follow-up records local implementation and
validation, not deployment or exact-commit release approval. The
[staged-review contract](../features-and-hardware/29-staged-capture-review.md)
owns current behavior, and the
[testing matrix](../development-guides/08-testing-strategy.md#staged-review-and-shared-describe-validation)
owns executable selectors and manual acceptance.

## Source state and scope

The reviewed changes are uncommitted work based on
`681d291e0cdd10b0d22201783436e1d39cccacbd`. This base SHA does not contain the
adaptive-toolbar implementation. The checkout also contains concurrent unrelated
work; the test results below are working-tree evidence, not a clean candidate
certificate. Record the final implementation SHA and its hosted results before
using this work for release.

This presentation follow-up supersedes the horizontal scrolling and retained
Analyze icon/color decisions in the
[September 26 implementation record](./staged-review-shared-describe-2026-09-26.md).
It adds no payload, entitlement, queue, persistence, or schema changes. The
earlier record's provider/provenance checkpoint and distribution gates remain in
force.

## Implemented behavior

- Identify and Analyze share a text-only primary-blue capsule. Standard text
  sizes retain a 48 pt button; accessibility sizes may grow vertically without
  shrinking labels. Disabled state and submission actions remain unchanged.
- Staged nodes keep 48 pt touch targets with 8 pt gaps. Compact layout is used
  only if every node and the submission button fit at their ideal sizes.
  Otherwise, media wraps above a separate Discard/submission action row.
  Historical evidence retains chronological order and the shared note is last.
- The tray retains 8 pt internal padding, 16 pt horizontal outer margins, and 24
  pt bottom padding. Complete media rows and the expanded action row use 8 pt
  vertical gaps. Discard remains visible and retains confirmation.
- The measured toolbar height drives `CaptureChromeLayout`: capture controls use
  the greater of their 124 pt baseline inset or toolbar height plus 16 pt.
  Describe, camera/audio overlays, and the composing center use the same
  clearance change. The layout has no reverse measurement from those consumers.
- Layout transitions, tray appearance, and note-tooltip dismissal honor Reduce
  Motion. Glass, material, opaque reduced-effect fallbacks, node review, note
  routing, draft locks, and keyboard suppression remain intact.
- Photo-picker presentation stays attached to the outer toolbar while its
  compact/expanded content changes. The admitted selection limit is captured
  before presenting the picker.

Review corrected two gaps: ordinary large text could grow submission buttons
past 48 pt because of unconditional vertical padding, and the older tray-entry
animation did not honor Reduce Motion. Regression checks now require visible
capture controls when capacity remains instead of conditionally skipping the
overlap assertion.

## Completed local validation

Final focused run: iPhone SE (3rd generation), iOS 18.0, Debug, through
`make ios-local-build`. All **21 checks passed**:

- Nine `CaptureShellArchitectureTests` checks.
- Nine `CaptureStagingToolbarPresentationTests` checks, including whole-node
  wrap boundaries and baseline/expanded clearance.
- `testStagedAudioBadgeOpensPlaybackReview`: compact layout at standard XXXL, 48
  pt submission height, accessible audio/note nodes, and playback review.
- `testNoteAtMediaCapacityWithLargerText`: accessibility XXXL, a taller
  submission button, reachable note/actions, and keyboard
  presentation/dismissal.
- `testWrappedReanalysisTrayKeepsEveryNodeAndActionVisible`: historical evidence
  wraps completely; Keep editing preserves it; Record and Scan retain visible
  capture controls at least 16 pt above the tray, within 1 pt rounding
  tolerance.

The retained local result is
`.artifacts/local-ios/b4585bd5544649969697ece753ee6ebf.xcresult`. Exported
screenshots and their manifest are in
`.artifacts/local-ios/adaptive-toolbar-review/`. These ignored local artifacts
are not bundled with the app or committed docs.

Earlier iOS 27.0 validation on an iPhone 17 Pro simulator passed four UI flows
covering compact review, accessibility text, shared Describe/confirmed discard,
and wrapped reanalysis. That broader run is retained as
`.artifacts/local-ios/aecf3ffaffd1444f9f84de37b855a6f4.xcresult`: 4,471 of 4,473
checks passed. Its shared-model SwiftUI-import failure was corrected by moving
the environment bridge into `Shared/Components`, and the final focused run
passed that architecture check. Its separate audio-preview timing failure
belonged to concurrent work. Do not describe that broader run as green.

The retained result bundle identifies that native-glass run as iOS 27.0. Earlier
chat summaries called it iOS 26; the bundle's environment metadata is the source
of truth. These runs cover iOS 18 material and the iOS 26+ native-glass code
path on iOS 27, not an actual iOS 26 runtime.

Project generation, project validation, SwiftLint, iOS CI-tooling tests, event
routing, privacy, transport-security and migration guardrails, Markdown
formatting, and `git diff --check` passed during implementation/review. The
wrapped reanalysis seed remains Debug/UI-test gated and appears in the Release
binary fixture denylist.

## Follow-up: node contrast and empty-note treatment

A later September 27 presentation adjustment replaces the note's plus badge with
an outlined `text.bubble` and a dashed border matching the empty media slot.
Populated notes use `text.bubble.fill` and a solid border. The shared
`CaptureStagingNodeSurface` gives populated evidence nodes opaque neutral
backgrounds; empty slots use 80% opacity, increasing to opaque under Reduce
Transparency or reduced effects. Thumbnail imagery, actions, capacity, and
adaptive layout remain unchanged.

Nine presentation checks and the two note-editing/audio-review UI flows passed
on the iPhone 17 Pro simulator with iOS 27.0. Empty and populated note
screenshots were inspected. The result is
`.artifacts/local-ios/7404e3f9e1c44cb7bcdeeb556298c431.xcresult`, with exported
screenshots in `.artifacts/local-ios/staged-node-surfaces/`. SwiftLint, project
validation, Markdown formatting, and `git diff --check` also passed. These
checks do not replace the outstanding physical-viewfinder and accessibility
acceptance below.

## Follow-up: transparent empty slots and floating submission

Later refinements use a plain `bubble.left` outline with no interior lines for
an empty note and remove empty-node background fills while preserving circular
tap targets. Populated nodes retain opaque backgrounds. In compact layout,
Identify/Analyze now floats outside the media-only capsule, with the same 16 pt
separation as Discard. Expanded media/action rows remain available when needed.

Nine presentation checks and the compact audio-review UI flow passed on the iOS
27 simulator. The UI check includes the 24 pt distance from the final node to
the submission button: 8 pt capsule padding plus 16 pt external separation. The
screenshot was visually reviewed. Result:
`.artifacts/local-ios/237057188f474cbba1f1bd6c3861211d.xcresult`; exported
screenshot:
`.artifacts/local-ios/floating-submit/2C89AE9A-899C-4A5D-8B56-5A2D78EB9997.png`.
Lint, project validation, Markdown formatting, and diff checks also passed.

## Follow-up: circular submission arrow

The next refinement replaces the floating text capsule with a 48 pt blue circle
and white up arrow for both Identify and Analyze. Their contextual accessibility
labels, hints, Large Content Viewer labels, and submission locks remain intact.
The existing 16 pt outer gaps now separate equally sized action controls from
the media capsule. Historical evidence still wraps when the compact row cannot
fit. Earlier text-capsule validation above describes the implementation at that
time; current icon buttons remain 48 pt even at accessibility text sizes.

A separate `hasShownCaptureSubmitTip` preference defaults to false and persists
the first-use submission hint independently of the note hint. The arrow hint
appears first, followed by the existing note hint if unseen; tooltip text wraps
above the toolbar. No payload or durable persistence schema changes are added.

Focused SwiftLint, iOS project validation, Markdown formatting, and diff checks
passed for this follow-up. The focused simulator run on the working tree based
at `681d291e0cdd10b0d22201783436e1d39cccacbd` stopped during compilation before
any tests ran: concurrent Explore changes in
`ExploreFeedViewModelDependencies.swift:116` call the main-actor
`ExploreContentVisibilityStore` initializer from a nonisolated initializer. That
unrelated source was left intact. The failed build result is retained at
`.artifacts/local-ios/0fbb5808b41544d399c1147935ab6a60.xcresult`.

The newly added hint-persistence test and updated circular-button UI assertions
remain unverified at runtime. Rerun AppSettings, UserDefaults key registry,
Staging presentation/architecture, Capture dependency suites, and the compact,
accessibility-size, and wrapped-reanalysis UI selectors after the concurrent
build blocker is resolved. Earlier screenshots above predate the circular
submission action; new screenshots remain outstanding.

## Follow-up: full-height action circles (superseded)

The action circles now use a 64 pt diameter, matching the single-row media
capsule’s 48 pt nodes plus 8 pt top and bottom padding. Their symbols increase
from 22 to 26 pt. Media nodes stay 48 pt; compact outer gaps stay 16 pt.
Expanded layouts retain 64 pt actions and use the existing measured toolbar
clearance. The compact UI assertions now compare both actions’ top/bottom
alignment and verify the action height equals a node plus 16 pt of capsule
padding.

SwiftLint and project/documentation checks are rerun for this size refinement.
Simulator validation remains blocked by the concurrent Explore compile error
recorded above; the new geometry assertions and screenshots remain pending.

## Follow-up: restore original action size

The full-height experiment above was reverted at user request. Both actions
again use 48 pt circles with 22 pt symbols, retaining the up arrow, colors,
spacing, accessibility labels, and confirmation/submission behavior. Current UI
assertions compare both actions with the 48 pt nodes. Documentation reflects the
restored size; previous simulator validation limitations remain unchanged.

## Follow-up: remove submission tooltip

The submission tooltip was removed at user request, along with its local state,
dependency callbacks, `hasShownCaptureSubmitTip` preference, and preference-only
test/setup. The earlier tooltip implementation record above is historical. The
once-per-install note tooltip remains. Identify/Analyze retain their VoiceOver
labels, accessibility hints, and Large Content Viewer labels.

## Remaining validation and release boundaries

- Obtain complete exact-SHA hosted iOS readiness for the final committed
  integration, including concurrent work. The focused run does not certify all
  unrelated checkout changes.
- Perform physical-device VoiceOver traversal, Reduce Motion/Reduce
  Transparency, Expedition/thermal appearance, live Free/Pro capacity, and
  camera/microphone interaction checks. Simulator screenshots and geometry
  assertions do not establish these device results.
- Repeat device coverage for compact and expanded glass layouts, light/dark mode
  switching, larger accessibility sizes, keyboard dismissal, and preserved
  disabled submission/discard behavior. iOS 17.2 runtime coverage remains
  unavailable in the local environment; iOS 18 exercised the material fallback.
  An actual iOS 26 runtime is also not covered by these retained runs.
- Preserve the earlier provider, database, and released-V51 install-over gates.
  This UI-only follow-up does not satisfy or reset them. TestFlight upload,
  distribution, and backend deployment remain separate operations.
