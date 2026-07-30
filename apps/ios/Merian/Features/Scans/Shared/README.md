# Scans Shared

The `Shared` directory contains logic, UI components, and modifiers utilized across multiple product areas within the Scans feature.

## Structure

- **Components**: Reusable views such as scan thumbnails, grid layouts, deletion dialogs, or scan summary cards.
- **Modifiers**: View modifiers that apply consistent styling or behaviors (e.g., sheet presentation logic, common context menus) across the scan feature.

## Purpose
Following the Merian iOS architecture, code is placed in `<Feature>/Shared` when it is reused by multiple product areas inside this specific feature (such as `Library`, `Collections`, and `NonBiological`) but does not represent app-wide infrastructure that would belong in `Core`.

`QueuedScanSnapshot` is the detached value boundary for queued grid rows. Its
automatic-recovery eligibility distinguishes durable queue state from live
network policy: offline/constrained rows and pending playback video blocked by
the large-upload policy cannot drive Library polling, while an explicit video
retry and already-staged lightweight recovery remain eligible.
