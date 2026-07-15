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
The brackets fade and resolve once, then remain static while a soft low-opacity
illumination band sweeps only inside the accepted region. The treatment remains
noninteractive and replaces the old full-image laser. Reduce Motion disables the
interior sweep. Images without a clear isolated subject use the uniform
analyzing tint, status phrase, and original full-image scan sweep—there is
no centered or full-image focus box. The full-image sweep is omitted whenever
an accepted focus region exists, so it never competes with the isolated-region
animation. Video, audio, and description animations retain their existing
behavior.
