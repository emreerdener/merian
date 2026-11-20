# Capture tools, review, and supporting details

Status: consolidated product and implementation proposal, 2026-10-18. This is
not an implementation, qualification, or release claim. It joins the
capture-tool simplification and media-review discussions into one proposed
delivery plan.

## Review outcome (2026-10-18)

The user approved the capture/import flow, contextual toolbar actions, combined
photo gestures and selection clearing, video/audio behavior, details Save versus
cancel semantics, and removal/discard rules in the step-by-step review.
Submission and purchase behavior are approved as the intended destination, with
allowance integration explicitly deferred. The delivery boundary is approved
conditional on alignment with the analysis engine defined in
[Scan ID History](codex://threads/01a0fe55-d9d3-77e0-90a5-b7eeeaaa74e1). This is
product and delivery-boundary approval, not an instruction to start
implementation or to message another chat.

## Authority and dependencies

This document owns the proposed capture UX. The
[current staged-capture contract](../features-and-hardware/29-staged-capture-review.md)
continues to describe existing behavior. Do not promote this proposal into that
contract until the corresponding implementation and checks land.

Planning context:

- [Capture review discussion](codex://threads/01a1333e-a13c-7ed3-812a-f836191c0cec):
  photo selection/crop, video/audio review, toolbar, settings, and deletion.
- [Simplify capture tools](codex://threads/01a12c47-6f54-7500-bab9-679c2babf9a0):
  Scan/Record only, supporting details sessions, media-required submission.
- [Consider review-step Add more](codex://threads/01a15127-6a15-7c50-ac8d-18296c86ef36):
  review as the default decision point and intentional additional capture.

The
[IC-1 agreement](../rfcs/initial-completion-history-interface-2026-10-11.md),
[history readiness roadmap](../rfcs/identification-history-alpha-readiness-2026-10-11.md),
and
[native media ownership agreement](../rfcs/client-prepared-media-native-ownership-agreement-2026-10-15.md)
retain authority over shared submission, source ownership, history, and
recovery. This proposal must consume their final interfaces rather than
introduce parallel owners or restore legacy queue assumptions. The latest
inspected coordination record still has prerequisite completion and explicit
ownership handoff pending.

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

The October 18 check of Scan ID History found native receiving locally committed
and queue/funding guards under review; Capture/Auth and retained-state
integration remain ongoing. These checkpoints are evidence of progress, not a
completed handoff. Before implementation, reconcile the exact final interfaces
and remaining qualification with the engine owner. Unfinished allowance UX is
not one of these prerequisites.

## Decisions and superseded alternatives

| Topic               | Consolidated direction                                                     |
| ------------------- | -------------------------------------------------------------------------- |
| Capture tools       | Scan for photo/video, Record for audio; remove standalone Describe         |
| Normal capture      | Prepare media, then open review                                            |
| Additional evidence | Review toolbar plus returns to capture with the draft preserved            |
| Submission          | Labeled Identify submits the whole ready observation                       |
| Settings            | One Identify automatically toggle, off by default                          |
| Photo editor        | One combined crop/subject view; no tabs                                    |
| Selection           | Tap and corner adjustment; no outline drawing or interior-box dragging     |
| Details             | Existing guided text/dictation experience in an isolated Add details sheet |
| Toolbar             | Shared draft capsule on capture and review, including labeled Identify     |
| Video               | Square fixed crop/rotation and playback; no subject tracking               |
| Audio               | Reuse shared spectrogram player; no new editing engine                     |

This supersedes the three-choice After capture setting, separate Subject/Crop
modes, default stage-first routing, standalone Use photo/video/audio completion
buttons, and icon-only submission in earlier review proposals. Add more is now
the toolbar plus action rather than a separate large button. Required imported
photo framing review remains.

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
5. Details opens the same session from capture or review and returns to the
   originating surface, selected item, and framing.
6. Identify commits current edits, validates the entire composition, and freezes
   all media and committed details for submission. It never means only the
   displayed item. Preparation or commit failure retains the draft and errors.

The plus disappears only when usable capacity is exhausted. Preserve the
existing Free/Pro, video, reanalysis, and upgrade-placeholder policies: ordinary
Free has one physical item and Pro two; text does not consume a media slot. Do
not change entitlements to fit a mockup. Preserve chronological order and
insertion times.

Keep the capsule and labeled Identify anchored consistently across capture and
review. At small widths or accessibility sizes, wrap complete nodes above the
action row using existing layout policy; do not shrink touch targets or clip
items. The selected thumbnail and all draft evidence must remain discoverable.

Imported photos always receive review, including when automatic identification
is enabled. Review the imported batch sequentially; intermediate confirmation
uses Next and the last enables Identify. Gate whole-draft submission until all
required reviews are complete. Switching to an existing thumbnail cannot mark
unreviewed imports complete. Adding more retains unfinished review requirements.

### Setting and automatic attempts

**Identify automatically** — default off.

> Identify immediately after taking a photo or finishing a recording, without
> reviewing first.

Preserve the existing explicit Auto-submit boolean preference; do not introduce
an enum migration. Eligibility is established only for a fresh capture with an
empty composition, not reanalysis. Existing media, pending details, or choosing
to add more keeps the composition manual. Turning the setting on never submits
an existing draft. Turning it off revokes a pending automatic attempt; turning
it back on does not rearm it. Imports still require explicit review
confirmation. Failures leave a manual retry. Playback, selection, and edits are
never required.

### Removal and discard

In review, trash offers Remove photo/video/audio and Discard observation… when
other media or details exist. With just one media item and no details, remove it
directly and return to empty capture. Removing an item from multiple items opens
the next chronological item, or the preceding item if the removed one was last.

Removing the last media item preserves details and returns to capture. The draft
cannot identify until replacement media is added; expose an Add media to
identify explanation. Never silently convert it to a text-only identification.

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

Top row: allowance, left/right quarter-turn rotation, trash. Title: Review
photo. A fixed square viewport represents the actual crop. No Subject/Crop
switch.

| State            | Subtitle                                             | Below photo                                |
| ---------------- | ---------------------------------------------------- | ------------------------------------------ |
| Automatic        | Naturebook will find the subject automatically.      | Pinch to zoom, drag to move, tap to select |
| Manual selection | Tap to reposition selection. Drag corners to adjust. | Clear selection                            |

Use thin rounded white corner brackets, without tint, dimming, automatic
brackets, or an additional label. Clear selection restores automatic detection.

- Tap creates an immediate box without AI, or recenters the existing box while
  retaining size. Initial dimensions are 40% of viewport width and height,
  clamped into the visible image.
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

## Add details session

Use Add details with the prompt What did you notice? Preserve the guided
walkthrough, category navigation, optional direct typing, and dictation. Users
may save without completing every prompt. The toolbar bubble shows the existing
empty/filled details state and remains reachable at full media capacity.

- The sheet owns an isolated text-and-prompt snapshot. Checkmark makes one
  Shell-validated commit; X or swipe cancels both. Returning to review restores
  its selection, crop, and item. Cancelled content never reaches submission.
- Replace Describe lifecycle assumptions tied to workspace bindings and
  .describe; moving only the view is insufficient. The prompt list is a
  navigation destination owned by the details session, not a sibling workspace
  sheet.
- Closing/resetting prompts returns to the unsaved session without committing,
  dismissing the outer sheet, resuming the camera, or releasing queued routes.
- Presentation occupancy lasts through matching outer dismissal completion.
  Block competing capture, physical-shutter callbacks, routes, imports, and
  submission. A valid Save must still pass the original draft mutation guards;
  do not make the sheet's own occupancy block its commit.
- Fence callbacks by session/draft/account identity. Stop dictation on session
  closure. Test background return and rapid dismiss/reopen explicitly.

Details support actual media. Fresh initial identification and reanalysis
require photo, video, or audio; original media satisfies reanalysis. Preserve
historical text records and exactly admitted recovery. Local-only legacy text
requests require remediation, not silent rewriting or fresh text-only admission.

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
no extra detection call, region image, or scan charge. Preserve first-photo
local-analysis behavior.

Freeze effective focus with final media and committed descriptions before
admission. Preserve it in the active request, durable representation, replay and
analysis overlay. Analysis shows the submitted rectangle without editing that
only changes presentation. Integrate with the final History/Hardening contract;
do not assume the earlier legacy descriptor-JSON-only design is still
sufficient. Dormant initial-analysis schema activation is not authorized by this
proposal.

### Deferred allowance integration

Allowance work will not be ready before this redesign starts and must not block
it. Initially use the existing funding/admission behavior and existing purchase
UI where available; preserve draft/editor state across that presentation. Do not
implement a substitute allowance service or weaken authoritative admission.
Existing funding guards inside the engine remain required even while the new
allowance experience is deferred.

The approved later integration permits zero-balance capture, import, review, and
editing while retaining permissions, account, capacity, and file checks. An
insufficient-allowance Identify attempt presents purchase options without losing
the draft. Purchase success or cancellation restores the same screen; purchase
alone never submits, and users tap Identify again. Prices in mockups are not
configuration. These zero-balance and purchase-to-retry changes receive separate
implementation and acceptance when allowance is available; initial redesign
qualification records the current behavior instead of claiming this target
works.

## Delivery and acceptance

| Phase                        | Deliverable and exit condition                                                                                           |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| 0. Reconcile prerequisites   | Explicit source revision, validation evidence, ownership handoff, and final-plan approval; no conflicting shared writer  |
| 1. Shared capture foundation | Scan/Record, isolated details session, media-required composition, setting copy, and draft guards                        |
| 2. Review and toolbar        | Default review, shared capsule, item switching, notes, plus, imports, discard/removal, and whole-draft Identify          |
| 3. Media editors             | Combined photo selection/crop, consistent video artifacts, reused audio playback, source integrity                       |
| 4. Submission integration    | Manual-focus request/recovery compatibility, frozen evidence, existing funding guards, and immutable analysis projection |
| 5. Qualification             | Focused and complete surface gates, device journeys, docs promotion, separately authorized release                       |

After core qualification, integrate the deferred allowance experience when its
owner is ready and run its separate acceptance cases. It is not a prerequisite
for phases 1–5.

Backend acceptance of manual focus must precede client exposure. Use gated
integration while compatibility is incomplete; older-server silent loss is not
acceptable. Phases describe dependencies, not permission to implement or deploy.

Acceptance must cover:

- Default/automatic fresh capture, existing drafts, imports and Next, required
  reviews, setting off/on races, whole-draft submit, and failed commit recovery.
- Toolbar selection/order, capacity/upgrade behavior, details indicator, wrapped
  accessibility layout, and media removal versus whole-draft discard.
- Details Save/X/swipe, text and prompt cancellation, nested prompt navigation,
  hardware shutter while editing, deferred routes/imports, background return,
  rapid reopen, stale callbacks, and dismissal-completion occupancy.
- Off-center camera fixture and byte equality for unchanged/selection-only
  edits; all rotations, viewport sizes, tap/resize/pan conflicts, and repeated
  edits.
- Video preview/export/inference agreement, seeking, audio sync, export failure,
  cancellation, size bounds, and retention. Audio shared-player behavior and
  Explore/Insight regression checks, boost semantics, and source leases.
- Source/account ownership, stale work, exact failed/ambiguous acceptance,
  media-required admission, immutable details/focus, recovery, and existing
  funding behavior. Deferred allowance acceptance separately covers zero
  balance, purchase return, explicit Identify after purchase, and preserved
  draft/editor state.
- VoiceOver, Dynamic Type, touch targets, smaller phones, Reduce Motion and
  transparency/thermal constraints. Physical-device playback/export/memory and
  interruption evidence remains separate from simulator tests.

Run appropriate focused tests then complete affected-surface gates, iOS builds
through make ios-local-build, and applicable Deno/contract checks. During
implementation synchronize the current staged-capture, camera, Describe/audio,
image pipeline, API/offline, Settings/owner README, and testing contracts.
Record actual results; do not claim planned checks passed. No source or runtime
checks are established by this documentation-only consolidation.

Location/field-data controls in review, new video/audio library imports, video
tracking, audio isolation/editing, avatar edits, and historical UI redesign are
outside this proposal. Existing historical records and evidence remain intact.
