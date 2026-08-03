# Profile Shared

The `Shared` directory contains logic, utilities, and view models that are utilized across multiple product areas within the Profile feature (e.g., used by both `UserProfile` and `Settings`).

## Structure

- **ViewModels**: Contains shared view models like `ProfileViewModel.swift`.

## Purpose
Following the Merian iOS architecture, code is placed in `<Feature>/Shared` when it is reused by multiple product areas inside this specific feature but does not warrant promotion to the app-wide `Core`. The `ProfileViewModel` often serves as the source of truth for the active user's state, driving both the display in the user profile and the actionable toggles/forms in settings.

## Avatar upload contract

`ProfileViewModel` prepares one bounded square WebP/JPEG data item and requests
`/generate-upload-urls` with its exact positive `sizeBytes`. It accepts only a
matching signed response whose `requiredHeaders` map contains exactly the
declared `Content-Type` and decimal `Content-Length`, applies both to the data
PUT, then passes the returned owner-scoped staging key to
`/update-public-avatar`. The client never reconstructs a staging key or uses the
removed legacy no-size request. A malformed header map, wrong owner/key, upload
failure, or promotion failure does not update the visible avatar.
