# Asset Catalog Organization

Merian's app asset catalog lives at `apps/ios/Merian/Assets.xcassets`.

Organize assets by what kind of reusable asset they are, not by the first feature
that used them. Product-area folders such as Explore, Profile, Paywall, or
Onboarding should not be recreated inside the asset catalog.

## Top-Level Groups

| Group | Purpose |
|---|---|
| `App/` | Required app-level assets such as `AppIcon` and `AccentColor`. |
| `Brand/` | External or Merian brand marks, such as `google-logo`. |
| `Personas/` | User persona artwork used by profile progression. Keep the `persona-` prefix to avoid collisions with achievement graphics. |
| `Graphics3D/` | Reusable 3D artwork used across onboarding, capture, insights, profile, paywall, species index, widgets, and changelog surfaces. |

## Naming Rules

- Name the graphic itself, not its historic screen: use `blue-bird`, not `pw_bird`; use `fern`, not `dictionary-plant`.
- Keep `Graphics3D/` flat unless the folder becomes too large to scan quickly.
- Do not duplicate an image set for a new feature. Reuse the existing asset name from code.
- If two renders show the same subject but are visually distinct, give them distinct descriptive names such as `bird-cardinal`, `blue-bird`, or `bird-magnifier`.
- Keep asset set names and primary filenames aligned where practical, for example `Graphics3D/compass.imageset/compass.png`.
- Update Swift, JSON, and docs references whenever an asset set is renamed. Asset lookup uses the `.imageset` name, not the folder path.

## Adding Artwork

1. Decide whether the asset is app chrome, brand art, persona art, or reusable 3D art.
2. Add it to the matching top-level group.
3. Use a reusable descriptive asset name with hyphen separators.
4. Prefer SF Symbols or existing shared UI icons for interface controls before adding a static image.
5. Run a stale-name search before finishing when replacing an older asset name.
