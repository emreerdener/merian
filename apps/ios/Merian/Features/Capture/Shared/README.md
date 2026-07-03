# Capture Shared

The `Shared` directory contains reusable components and state managers used across the capture modes.

## Purpose
Code lives here when it is utilized by multiple capture modalities (e.g., `Scan`, `Record`, and `Describe`) but is specific enough to the capture domain that it shouldn't be promoted to the app-wide `Core` layer. This might include shared camera overlays, shutter button components, or unified telemetry state.
