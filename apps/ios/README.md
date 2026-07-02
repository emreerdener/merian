# Merian iOS Structure

The iOS workspace is organized around product ownership first, then implementation type. A developer should be able to find a user-facing area by the name a user would use in the app before seeing folders such as `Views`, `Models`, or `Components`.

## Top-Level Areas

```text
apps/ios/
  Merian/          Main iPhone app
  MerianTests/     Unit tests for the main app
  MerianUITests/   UI tests for the main app
  messages/        Messages extension and shared message-scan code
  photos/          Photos import extension and shared import code
  widgets/         Widget extension sources
```

The main app is organized as:

```text
Merian/
  App/              App entry point, launch screen, root lifecycle wiring
  Assets.xcassets/  App, brand, persona, and reusable visual assets
  Configuration/    Entitlements, Info.plist, environment configuration
  Core/             Cross-feature services, infrastructure, and UI primitives
  Features/         User-facing product areas
  Models/           SwiftData schemas and app-wide persisted models
  Resources/        Bundled JSON, release notes, and static app resources
```

## Feature Folders

Feature folders are product-area-first. If a feature contains multiple user-facing areas, those areas get their own folders before implementation buckets appear.

```text
Features/<FeatureName>/
  Shell/          Root container, routing, tabs, pagers, and feature chrome
  <ProductArea>/  User-recognizable area such as Feed, Map, Settings, or Scan
  Shared/         Helpers shared only inside this feature
```

Inside a product area, use focused implementation folders only when they are needed:

```text
<ProductArea>/
  Views/
  Components/
  Models/
  ViewModels/
  Services/
  Utilities/
```

Avoid parallel concepts such as `Screens/` and `Views/`. In SwiftUI, sheets, detail routes, and full-screen pages are all views; folder nesting should explain ownership.

## Core Versus Shared

Use the narrowest owner that fits:

- Put code in `<Feature>/Shared` when it is reused by multiple product areas inside one feature.
- Promote code to `Core` only when it is reused across features or represents app infrastructure.
- Keep feature-specific business rules out of `Core` even if the code feels reusable.

Examples:

- `Features/Scans/Shared` can own scan-only thumbnails, grids, and deletion dialogs.
- `Core/UI` can own generic controls or modifiers reused by Explore, Scans, Profile, and Capture.
- `Core/Data/OfflineSync` owns sync infrastructure rather than a feature-specific scan screen.

## Tests

Unit tests should mirror the production owner:

```text
MerianTests/
  Core/<CoreArea>/
  Features/<Feature>/<ProductArea>/
```

If a test primarily exercises a Core manager, place it under `MerianTests/Core`, even if the behavior appears in a feature screen. If it exercises a product area's view model, policy, or local helper, place it under that feature product area.

## Assets

Asset folders describe what the asset is, not where it was first used:

```text
Assets.xcassets/
  App/
  Brand/
  Graphics3D/
  Personas/
```

Avoid prefixes such as `pw_`, `desc_`, or `dictionary-` when artwork is reusable. Prefer stable descriptive names such as `bird-cardinal`, `camera-lens`, or `persona-naturalist`.
