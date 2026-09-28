# Capture Staging

`Capture/Staging` owns the ephemeral mixed-media draft that appears before one
Capture submission. It preserves user order across one physical item for Free or
two for Pro, plus one optional note. Staging owns neither network, queue, nor
file deletion work. Reanalysis keeps historical descriptions and its one current
supplement separately from the two-physical-item budget.

The tray shows every unused physical slot as an empty media node, including both
slots in a Pro Describe-first draft. The separate note never replaces a media
placeholder. All placeholders use the existing admitted photo-picker action and
its remaining-capacity selection limit.

## Ownership

- `Models/StagedCapturePolicy.swift` owns the current shared capacity constants.
- `Models/StagedCapture.swift` owns the aggregate draft, derived modality state,
  capacity queries, reference clearing, and local-file cleanup inventory.
- `Models/StagedCaptureNode.swift` is the single chronological ordering owner.
  It retains each modality's collection index and stable tray identity.
- `Models/StagedCaptureMedia.swift` owns the audio, video, and description
  wrappers plus their insertion times. `Models/StagedImage.swift` keeps the
  inference, display, thumbnail, original/crop, focus, and insertion-time values
  for one photo together.
- `Models/CaptureStagingToolbarPresentation.swift` projects the canonical staged
  order into renderable toolbar nodes, photo capacity, submit copy, and enabled
  state. It preserves the established behavior that a coverless video is hidden
  without consuming a visible tray slot.
- `Services/CaptureStagingToolbarDependencies.swift` is the sole Staging owner
  of the live Photo Library, keyboard dismissal, cancel feedback, and persisted
  once-per-install note and submit tooltip effects. The toolbar receives that
  small dependency value from Capture Shell.
- `Components/Toolbar/` owns the staged-media row, cancel and submit controls,
  private modality badges, tooltip, whole-node wrapping in
  `CaptureStagingMediaFlowLayout`, and complete `ActiveScanToolbar` composition.
  These components resolve no singleton or platform effect.
- `Views/CropSheetModifier.swift` owns the timing-sensitive crop presentation.
  It replaces the immediate thumbnail synchronously, fences its cancellable
  display-crop/focus task, and reports required-crop completion in the existing
  order. `Views/StagedDescriptionSheet.swift` retains its local draft, focus,
  dismissal, and destructive action timing.

Capture Shell remains the mutable owner of `StagedCapture`. Shell admits and
commits imports, appends completed modality values, owns required-crop and
automatic-submission presentation fences, removes items, and routes disposable
paths through `FileIOActor`. `ActiveScanToolbar` consumes canonical
`orderedNodes` through its deterministic presentation without sorting them
again. Its picker selection, presentation binding, admission task, tooltip
visibility remain component-local so extraction does not change focus,
animation, or cancellation behavior.

Finished recordings enter through Shell's identity-fenced audio handoff.
`StagedAudio.prefersBoostedPreview` carries the recording-start preview
preference only for this draft; it never enters submission or queue projections.
Successful handoff immediately returns Record to idle, and the audio node opens
playback.

The photo picker is attached to the stable outer toolbar, outside its compact
and expanded layout alternatives. Its selection limit is captured from the
admitted request before presentation, so a width or Dynamic Type change does not
move picker ownership between branches.

Capture Submission owns conversion out of staging:

- `CaptureSubmissionMediaTimeline.swift` owns the live/replay timeline and its
  legacy fallback ordering.
- `CaptureSubmissionMediaProjection.swift` emits aligned audio paths,
  descriptors, video paths, descriptions, and the complete owner timeline.
- `IdentifyMediaDescriptors.swift` owns the hand-written Codable request/replay
  descriptors and their exact network JSON projections.

Moving those declarations does not change their Swift names, initializer
signatures, enum raw values, Codable fields, payload keys, or queue behavior.
The canonical request is documented in
[API Contracts](../../../../../../docs/backend-and-data/05-api-contracts.md#deno-identify-multimodal-edge-node),
and durable ownership is documented in the
[offline synchronization pipeline](../../../../../../docs/backend-and-data/01-offline-sync-pipeline.md#2-scan-submission--immediate-durability-submitstagedcapture--enqueuecapture).

## Behavioral Contracts

Reanalysis uses the same physical-capacity policy for capture/import admission,
completed media, picker counts, and controls. Its supplementary description is
marked only in the ephemeral `StagedObservationContext`; the marker never enters
request or queue JSON. The shared root Describe editor can update it at full
media capacity. Historical descriptions remain separate and preserve original
evidence order. The glass tray adapts from a compact row to wrapped media above
its actions, keeping Discard and Analyze visible. The ordinary note tooltip
appears once per install.

Photo-library picks and one-photo document imports enter staging only after
caller-scoped admission and remain required-crop items until confirmed or
cancelled. Picker entry checks the minimum one-photo addition; selected imports
recheck the actual count before file preparation. A known denial presents the
paywall; queue-only admission may proceed, but final submission rechecks because
preview does not reserve quota.

An eligible automatic single capture suppresses the Identify tray from the same
mutation that stages its media until submission consumes the draft or fails.
Staged review, additional context, and refinement retain manual tray behavior.
Required crop has a separate chrome fence from commit through
completion/cancellation so staged controls cannot flash beneath the full-screen
cover.

The shared image cropper has left/right 90-degree rotation controls that
preserve zoom and rotate the selected area. Confirmed quarter-turns, scale, and
offset remain on the original image for reopening; cancellation leaves the
previous confirmed values intact. Inference and display crops both use the
original image and the same confirmed geometry, never the preceding display
crop. See
[bounded crop processing](../../../../../../docs/system-architecture/02-zero-oom-and-concurrency.md#bridging-ram-leaks-imagecropprocessor--localimageloader).

Every media replacement must retain its original `addedAt` value. Submission and
persistence derive chronology from that value; changing it during a crop would
reorder the user's evidence. Confirmed whole-draft discard deletes only
draft-owned files and invalidates its generation. Queue rejection preserves the
draft and its sources for manual retry. Queue admission copies media to unique
durable files; accepted live inference uses that exact mapped timeline. Only
after acceptance are staging sources released.

The supplementary marker is local to the refinement session and does not alter
`ObservationContext`, queue JSON, or the API. Supplement updates retain their
insertion time. Explicit supplementary tray edits/removal supersede its pending
Describe draft, while historical description edits preserve that draft. Starting
another refinement clears the old evidence before loading its own original.

## Verification

Mirrored tests live under `MerianTests/Features/Capture/Staging/`.
`CaptureStagingToolbarPresentationTests` also covers the refinement-only
supplement allowance, one remaining physical-media slot after adding text, and
three chronological tray items with no further photo slot. Shell's refinement
suite covers mutation, update/removal, and session reset. These model assertions
do not replace simulator verification of the tray's overflow, hit targets,
dictation, or mode switching. `StagedCaptureTests` covers aggregate state,
capacity, cleanup, ordering, stable node IDs, and image replacement.
`CaptureStagingToolbarPresentationTests` locks mixed-media ordering,
coverless-video filtering, the established filtered-tray capacity behavior, and
Identify/Analyze state. `CaptureStagingArchitectureTests` enforces the
Models/Services/Views/Components boundary, Submission ownership of wire/replay
declarations, the single toolbar ordering source, effect isolation, retired Core
path, and 600-line production-file guard. Paired Shell and Submission suites
cover admission/presentation fences and timeline/projection contracts.

The presentation suite also checks exact whole-node wrap boundaries and the
shared baseline/expanded clearance policy. UI checks cover compact 48 pt
circular submission buttons at standard and accessibility XXXL, note editing and
keyboard dismissal, and wrapped historical evidence with capture-control
clearance in Record and Scan. The
[testing matrix](../../../../../../docs/development-guides/08-testing-strategy.md#staged-review-and-shared-describe-validation)
owns selectors and manual acceptance; the
[adaptive-toolbar record](../../../../../../docs/rfcs/adaptive-staged-toolbar-2026-09-27.md)
records completed local runs and remaining checks.

## Review and shared text

The root Describe editor owns the one ordinary note. Note-node taps focus it
even at physical capacity. Historical descriptions alone retain the local-copy
sheet. Free has one physical slot plus a note; Pro has two physical slots plus a
note. The compact media-only capsule sits between floating Discard and
Identify/Analyze buttons, separated by 16 pt gaps. The tray uses 48 pt nodes
with 8 pt gaps; when the compact row does not fit, media wraps above the
always-visible Identify and confirmed Discard actions. Native glass respects
Expedition, thermal, and accessibility reductions. The tray follows app
appearance across capture modes. Identify uses the same accent blue as Share,
and the neutral discard control uses a contrasting semibold red icon.
`CaptureStagingNodeSurface` gives populated nodes opaque primary system
backgrounds (white in light appearance) and solid borders. Empty media and note
slots use transparent backgrounds and matching dashed borders, revealing the
tray's existing glass or reduced-effect surface. The empty note uses a plain
`bubble.left` outline without interior lines or a plus badge; a populated note
uses the filled symbol. Analyze matches Identify with a 48 pt blue circle and
white up arrow. Both retain their Identify/Analyze accessibility labels,
submission hints, and Large Content Viewer labels. The submit button gets a
separate once-per-install tooltip above its own trailing edge when physical
capacity is full and submission is ready. It waits for the note tooltip, lasts
four seconds, and says “Submit to identify” or “Submit to analyze.” See the
[staged-review contract](../../../../../../docs/features-and-hardware/29-staged-capture-review.md).

Reanalysis keeps historical descriptions alongside its existing primary-media
selection in original evidence order. Historical descriptions and the single
current supplement have separate text budgets; neither consumes a physical media
slot. Historical audio preparation is fenced by draft generation, even when
restarting reanalysis for the same original scan.
