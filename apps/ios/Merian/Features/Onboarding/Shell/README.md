# Onboarding Shell

The `Shell` directory acts as the root container and state machine for the entire Onboarding feature.

## Structure

- **Views**: Contains the top-level container views that host the onboarding flow.
- **ViewModels**: Manages the state of the onboarding sequence, determining which step to show next, tracking completion status, and handling the transition out of onboarding once finished.

## Purpose
Following the Merian iOS architecture guidelines, the `Shell` isolates the orchestration and sequence state from the individual onboarding screens. It controls the progression from welcome, through permission requests, and into the final ready state, keeping the individual steps focused solely on their own presentation.
