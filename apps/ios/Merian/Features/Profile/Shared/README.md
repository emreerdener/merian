# Profile Shared

The `Shared` directory contains logic, utilities, and view models that are utilized across multiple product areas within the Profile feature (e.g., used by both `UserProfile` and `Settings`).

## Structure

- **ViewModels**: Contains shared view models like `ProfileViewModel.swift`.

## Purpose
Following the Merian iOS architecture, code is placed in `<Feature>/Shared` when it is reused by multiple product areas inside this specific feature but does not warrant promotion to the app-wide `Core`. The `ProfileViewModel` often serves as the source of truth for the active user's state, driving both the display in the user profile and the actionable toggles/forms in settings.
