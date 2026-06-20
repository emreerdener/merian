# Changelog

Notable user-facing changes are collected here as release-note source material.
Keep detailed code history in git; keep this file focused on what matters for
TestFlight, App Store, support, and QA.

## Unreleased

### Added

- Added a Community tab to Explore for Ask the Community identification
  requests, with an Insight-sheet CTA, community request queue, taxonomy search,
  disagreement prompts, and backend consensus storage.
- Added durable 7-day Pro pass infrastructure that verifies purchases through
  RevenueCat while Merian tracks and expires the timed access window in
  Supabase.
- Added smart default Collections that suggest helpful scan groupings from your
  library, such as recent finds, places, review candidates, and common organism
  groups, plus an Explore posts collection, with local hide controls.
- Added the initial Next.js + Mantine web app scaffold for public Explore share pages.
- Added public Terms, Privacy Policy, Community Guidelines, Privacy Choices, Support, and Legal hub pages for `merian.earth`.
- Added an iOS-to-web theme bridge so Merian-opened web pages can follow the app's theme preference.
- Added AI-derived sex observation metadata to scan records, the Overview card, Supabase persistence, and Darwin Core exports.
- Added native Messages and Photos share extensions: Messages can insert cached scan images/cards/descriptions, and Photos can queue one shared image for Merian identification.
- Added custom public profile picture uploads for logged-in users, with
  R2-backed avatar storage, Profile picker support, and Explore/Profile
  identity refresh.
- Added a bundled in-app changelog in Settings for selected release notes,
  feature notes, and in-progress work.
- Added extra species dictionary data fetches so undiscovered species can still
  load dictionary pages when users navigate to them.
- Added an Explore bottom menu for Feed, Map, and Dictionary, with horizontal
  swiping across the same section order.
- Added a searchable Species Dictionary catalog with category browsing,
  Dictionary detail pages, and species reference imagery.
- Added Dictionary category browsing with a Recently Added featured species
  card, a full-width Your Region map card when local entries are available, an
  All row, plus region rows backed by dictionary-native range metadata. Region
  browsing stays hidden when no region records are available.
- Added high-level Dictionary group cards with custom graphics for broad browse
  paths such as Plants, Birds, Insects, Fungi, Mammals, and Reptiles &
  Amphibians, with toolbar search available inside those species lists.
- Added a common-name picker for Explore sharing and editing so posts use the
  known species name you choose.
- Added `@username` mentions in Explore comments, with scoped suggestions for
  post authors, visible thread participants, and followed users plus mention
  notifications.
- Added a one-time beta feedback survey with a warm intro screen, proactive
  prompt after meaningful use, Settings access, and private Supabase response
  storage. Manual survey access now resets after a 24-hour thank-you cooldown so
  testers can send fresh feedback again without being proactively re-prompted.
- Added a Catalog/Tree segmented control to the Explore Dictionary header,
  keeping the taxonomy tree inside Dictionary while the Explore bottom menu
  stays focused on Feed, Map, and Dictionary.

### Changed

- Removed search from the Explore Dictionary Tree view so the header toggle
  opens directly into the pan-and-zoom taxonomy canvas.
- Removed the filled top heading background from the Explore Dictionary Tree
  canvas for a cleaner full-canvas view.
- Updated the Explore Dictionary Tree zoom and locate controls with liquid-glass
  circular button chrome.
- Candidate review prompts now appear only for non-strong identifications or
  strong IDs with a competitive alternative, while Merian still keeps stored
  candidates available for recovery and future review flows. The Needs review
  smart collection now follows the same non-strong and competitive-alternative
  thresholds.
- Biological scan images are now durable for Free and Pro users; Merian no
  longer auto-purges successful biological sighting evidence based on age or
  tier, while temporary and non-biological cleanup remains in place.
- Refreshed the Pro paywall with an immersive visual layout, selectable plan
  cards, plan comparison rows, stronger restore/policy actions, and a persistent
  purchase button.
- Streamlined Explore post details so species education lives in the species
  dictionary, while reference images, observation context, alternate names, and
  a direct dictionary link remain easy to find.
- Simplified the in-app changelog to show dates without version/build labels
  until release versioning is finalized.
- Updated Explore posts to show usernames on feed cards and post detail headers.
- Updated Explore comment composers so mentions can be inserted from
  autocomplete and resolved mention spans open the user's public profile sheet.
- Added an independent Notifications setting for Explore comment mention pushes,
  while keeping mention activity visible in the in-app Explore notifications
  feed.
- Explore activity and comment mention push notifications now default on for new
  installs.
- Species dictionary galleries now admit more published Merian photos by
  lowering the Merian reference-image quality gate while keeping the species
  confidence gate in place.
- Explore Dictionary now uses already-granted location access to improve the
  Your Region category, while falling back to the device locale without showing
  a Dictionary-specific permission prompt.

### Fixed

- Fixed Species Dictionary catalog and overview surfaces so non-biological
  encyclopedia rows are filtered out before they can appear as dictionary
  records.
- Fixed the profile scan heatmap so brand-new or empty libraries still show the
  empty contribution cells instead of collapsing the grid.
- Fixed Explore Map geoprivacy so only open-location discoveries appear on the
  map; obscured and private posts stay off the map while other eligible Explore
  surfaces continue to respect their privacy-safe public fields.
- Added per-post Explore geoprivacy so share/edit options can keep a post
  private, show an obscured public label, or explicitly make that post open on
  the map without changing the underlying scan default.
- Fixed non-biological corrections so they now explain the result and start
  reanalysis instead of creating an unidentified biological scan with incorrect
  confidence, phantom reference media, or premature Explore sharing. These
  correction reanalyses are available from the Non-biological collection for
  free users while still following normal daily scan limits when submitted.
- Fixed non-biological insight titles so stored taxonomy placeholders now
  display as "Non-biological" instead of "Unknown Subject".
- Fixed non-biological correction reanalysis so the explanatory prompt no
  longer remains in the Describe text field as if it were user-entered notes.
- Fixed reanalysis submissions so Describe text entered for the current
  analysis is consumed into the submission and cleared from the input afterward.
- Fixed Needs review smart collections so they follow the shared non-strong and
  competitive-alternative thresholds instead of every scan that happens to have
  candidates.
- Fixed Explore posts so shared discoveries keep the selected common name from
  the composer instead of drifting to dictionary defaults.
- Fixed the Explore comment mention push toggle so it no longer appears enabled
  or disabled based on the separate Explore activity push setting.
- Fixed non-biological scans older than 30 days remaining on device by adding
  local foreground cleanup that mirrors the server purge window.
- Fixed geoprivacy so private scans hide location details across scan cards,
  sharing, achievements, Messages share captions, and public labels, while open
  and obscured scans restore location context at the expected precision.
- Fixed species observation charts timing out on first load by returning core
  public stats quickly while detailed life-stage and sex buckets refresh in the
  background.
- Fixed similar species so lookalike suggestions load reliably in insight
  sheets.
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
