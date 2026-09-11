# Capture Staging

`Capture/Staging` owns the ephemeral mixed-media draft that appears before one
Capture submission. It preserves user order across up to two total photos,
videos, audio clips, or descriptions without owning network, queue, or file
deletion work.

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
  of the live Photo Library, keyboard dismissal, cancel feedback, and
  process-session tooltip effects. The toolbar receives that small dependency
  value from Capture Shell.
- `Components/Toolbar/` owns the staged-media row, cancel and submit controls,
  private modality badges, tooltip, and complete `ActiveScanToolbar`
  composition. These components resolve no singleton or platform effect.
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
visibility, and shimmer timing remain component-local so extraction does not
change focus, animation, or cancellation behavior.

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

Photo-library picks and one-photo document imports enter staging only after
caller-scoped admission and remain required-crop items until confirmed or
cancelled. A known denial presents the paywall before picker/file preparation;
queue-only admission may proceed, but final submission rechecks because preview
does not reserve quota.

An eligible automatic single capture suppresses the Identify tray from the same
mutation that stages its media until submission consumes the draft or fails.
Confirmation-enabled, multi-capture, mixed-media, and refinement flows retain
manual tray behavior. Required crop has a separate chrome fence from commit
through completion/cancellation so staged controls cannot flash beneath the
full-screen cover.

Every media replacement must retain its original `addedAt` value. Submission and
persistence derive chronology from that value; changing it during a crop would
reorder the user's evidence. Cancel, remove, replacement, timeout, and
queue-rejection paths delete temporary audio/video files. Successful queue/live
handoff clears references only because the durable owner has adopted them.

## Verification

Mirrored tests live under `MerianTests/Features/Capture/Staging/`.
`StagedCaptureTests` covers aggregate state, capacity, cleanup, ordering, stable
node IDs, and image replacement. `CaptureStagingToolbarPresentationTests` locks
mixed-media ordering, coverless-video filtering, the established filtered-tray
capacity behavior, and Identify/Analyze state. `CaptureStagingArchitectureTests`
enforces the Models/Services/Views/Components boundary, Submission ownership of
wire/replay declarations, the single toolbar ordering source, effect isolation,
retired Core path, and 600-line production-file guard. Paired Shell and
Submission suites cover admission/presentation fences and timeline/projection
contracts.
