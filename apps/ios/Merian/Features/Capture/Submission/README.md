# Capture Submission

The `Submission` directory handles the visual transition between capturing data and viewing the result.

## Purpose
This area manages the UI and state during the network round-trip. It displays the scanning overlay, animates status phrases driven by the concurrent on-device `VNClassifyImageRequest`, handles local SwiftData queuing (`OfflineQueuedScan`) if connectivity fails, and orchestrates the presentation of the final Insight sheet.
