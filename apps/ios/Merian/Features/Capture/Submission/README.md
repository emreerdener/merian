# Capture Submission

The `Submission` directory handles the visual transition between capturing data and viewing the result.

## Purpose
This area manages the UI and state during the network round-trip. It displays
the scanning overlay, animates status phrases driven by the concurrent on-device
`VNClassifyImageRequest`, handles local SwiftData queuing (`OfflineQueuedScan`)
if connectivity fails, and orchestrates the presentation of the final Insight
sheet.

Still images use the accepted `NormalizedImageFocusRegion` to render four
detached white corner brackets and a dimmed exterior in the Insight carousel.
The treatment fades and resolves once, remains noninteractive, and replaces the
old still-image laser. Images without a clear isolated subject show only the
uniform analyzing tint and status phrase—there is no centered or full-image
fallback. Video, audio, and description animations retain their existing
behavior.
