# Capture Staging

The `Staging` directory manages the mixed-media queue before an observation is submitted.

## Purpose
This area powers the mixed-media staging mode, which allows users to queue multiple pieces of evidence (e.g., up to 2 total images, audio clips, or descriptions) for a single observation. It handles the UI for reviewing, editing, and deleting staged media before initiating the network request.

Photo-library picks and one-photo document imports are committed as
`StagedImage` values with `requiresCrop: true`. The pending-import inbox remains
the owner until the external item is successfully committed; after that point,
normal staging owns crop cancellation, removal, confirmation, submission, and
offline-queue handoff. A full tray must not consume the inbox receipt.

Admission precedes that ownership transfer. The in-app photo-library control
awaits the caller-scoped preview before presenting `PhotosPicker`; durable
external-image imports await it before reading or preparing the file. A known
denial presents the paywall before selection/crop work and leaves an external
receipt in the inbox. An allowed or queue-only result may proceed into import,
but final submission rechecks because the advisory preview reserves no quota.

The tray is a manual-confirmation or recovery surface, not an intermediate
frame of automatic submission. An eligible single capture arms automatic
submission in the same mutation that stages its media, and
`CaptureWorkspaceView` suppresses `ActiveScanToolbar` until that attempt either
consumes the staging buffer or fails. On failure, the pending flag clears while
the media remains staged, making **Identify** available for an explicit retry.
Confirmation-enabled, multi-capture, mixed-media, and refinement flows never
arm this suppression and continue to present the toolbar normally.

Required gallery crop presentation has a separate chrome fence. The image must
enter `StagedCapture` before `CropSheetModifier` can edit it, but
`shouldSuppressCaptureChromeForCrop` becomes true from that commit until the
required crop is completed or cancelled. `CaptureWorkspaceView` therefore
hides both bottom-control layers before the full-screen cover begins animating.
The cover itself is the only full-screen owner: the workspace must not add a
transition canvas or input-blocking overlay that can outlive presentation when
the app changes scene phase. The staged thumbnail and **Identify** action remain
suppressed without covering the workspace.
