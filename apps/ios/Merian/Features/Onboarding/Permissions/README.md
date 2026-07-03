# Onboarding Permissions

The `Permissions` directory contains specific core logic and potentially reusable UI elements for handling system permission prompts (such as Location). 

## Structure

- **Location**: Contains the logic and specialized UI for requesting location access, outlining the privacy rationale, and handling the system prompt outcomes. 

## Purpose
While the `Steps` directory defines the user-facing screens for the onboarding flow, the `Permissions` directory isolates the actual implementation of the permission requests, ensuring that the logic interfacing with iOS system permissions is decoupled from the pure UI steps.
