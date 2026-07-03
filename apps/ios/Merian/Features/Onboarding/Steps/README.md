# Onboarding Steps

The `Steps` directory contains the individual, user-facing screens that make up the onboarding flow.

## Structure

- **Welcome**: The initial greeting screen introducing the user to Merian.
- **CameraPermission**: The screen explaining the need for camera access to capture organisms.
- **LocationPermission**: The screen explaining the need for location access to provide accurate ecological context.
- **Ready**: The final confirmation screen before dropping the user into the main app experience.
- **Shared**: Common UI elements used across multiple steps (e.g., standard layout templates, primary action buttons).
- **Models**: Defines the data structures or enums representing the different onboarding steps.

## Purpose
This area houses the actual UI that the user interacts with during their first launch. Each step is designed to be a standalone view that communicates its specific purpose clearly, relying on the `Shell` to handle the transition between them.
