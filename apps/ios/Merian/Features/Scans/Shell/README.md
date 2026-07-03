# Scans Shell

The `Shell` directory acts as the root container and routing layer for the entire Scans feature.

## Structure

- **Views**: Contains the top-level container views that host the tab bar or navigation stack for the scans area.
- **Modifiers**: Navigation and routing modifiers that manage sheet presentations or full-screen covers within the context of the scans feature.

## Purpose
Following the Merian iOS architecture guidelines, the `Shell` isolates routing, layout chrome, and tab-level coordination. It seamlessly switches between the `Library`, `Collections`, and `NonBiological` areas, keeping those individual product areas focused strictly on their respective domain logic and UI.
