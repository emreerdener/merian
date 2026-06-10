# Changelog

Notable user-facing changes are collected here as release-note source material.
Keep detailed code history in git; keep this file focused on what matters for
TestFlight, App Store, support, and QA.

## Unreleased

### Added

- Added the initial Next.js + Mantine web app scaffold for public Explore share pages.
- Added public Terms, Privacy Policy, Community Guidelines, Privacy Choices, Support, and Legal hub pages for `merian.earth`.
- Added an iOS-to-web theme bridge so Merian-opened web pages can follow the app's theme preference.
- Added AI-derived sex observation metadata to scan records, the Overview card, Supabase persistence, and Darwin Core exports.
- Added native Messages and Photos share extensions: Messages can insert cached scan images/cards/descriptions, and Photos can queue one shared image for Merian identification.
- Added custom public profile pictures with R2-backed avatar uploads, Profile
  picker support, and Explore/Profile identity refresh.
- Added a bundled in-app changelog in Settings for selected release notes,
  feature notes, and in-progress work.

### Fixed

- Fixed species observation charts timing out on first load by returning core
  public stats quickly while detailed life-stage and sex buckets refresh in the
  background.
- Hardened Edge media request/response handling so chunked or missing-length
  bodies are capped while streaming before V8 heap allocation can run away.
- Reduced share-import, expanded-original-image, local species-chart, APNs
  fanout, collection-sync, and audio-carousel resource usage to prevent OOMs,
  main-thread stalls, and idle battery drain.
- Fixed capture bottom controls getting hidden by stale keyboard state after leaving Describe or canceling staged input.
- Fixed field notes dictation startup and kept the loading spinner from shifting the button label.
- Fixed Explore map count text so exactly one visible item says "1 discovery in view."
- Fixed audio insight carousel swiping when reference images load after the audio page is already visible.
- Hardened scan purge jobs so they cannot delete durable public avatar images.
