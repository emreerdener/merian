# Capture Staging

The `Staging` directory manages the mixed-media queue before an observation is submitted.

## Purpose
This area powers the mixed-media staging mode, which allows users to queue multiple pieces of evidence (e.g., up to 2 total images, audio clips, or descriptions) for a single observation. It handles the UI for reviewing, editing, and deleting staged media before initiating the network request.

Photo-library picks and one-photo document imports are committed as
`StagedImage` values with `requiresCrop: true`. The pending-import inbox remains
the owner until the external item is successfully committed; after that point,
normal staging owns crop cancellation, removal, confirmation, submission, and
offline-queue handoff. A full tray must not consume the inbox receipt.
