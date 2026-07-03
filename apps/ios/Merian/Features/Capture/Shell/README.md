# Capture Shell

The `Shell` directory acts as the root container for the entire Capture feature.

## Purpose
Following the Merian architecture guidelines, the `Shell` orchestrates the transitions between the different capture modes (`Scan`, `Record`, `Describe`). It acts as the routing layer, keeping the individual capture modes isolated and focused entirely on their specific hardware/input logic.
