# Changelog

Notable user-facing changes are collected here as release-note source material.
Keep detailed code history in git; keep this file focused on what matters for
TestFlight, App Store, support, and QA.

## Unreleased

### Capture

- Added automatic audio submission when a recording reaches the full time limit
  and confirm-before-submit is turned off.
- Added video recording controls so Pro video scans show remaining time, can be
  canceled before staging, and open staged clips in a full-screen preview where
  they can be removed before identifying.
- Added Pro short video scans from the visual shutter: tap still takes a photo,
  while a brief hold latches into a 5-second video recording with saved playback
  and image-based thumbnails.
- Added clearer haptic feedback for video recording start, finish, successful
  staging, and recording failures.
- Fixed a crash that could happen after tapping stop on a Pro video recording
  while Merian extracted the clip's audio.
- Pro video clips now prefer compression for lighter scan-library playback,
  Explore sharing, and cloud storage while keeping AI analysis frames sampled
  from the original recording.
- Improved Pro video staging so upload-safe clips still stage when playback
  compression is slow or unavailable.
- Fixed video scan submission so unusable video audio no longer blocks
  identification, and background replay keeps the staged video clip attached.
- Hardened video scan submission so saved video captures require a durable
  playback clip instead of silently falling back to sampled frames.
- Added server-tracked upload sessions for scan media so staged videos, images,
  and audio have lifecycle state before final scan persistence.
- Added server-side reconciliation for scan media uploads so stranded video
  staging objects can repair existing cloud scans and abandoned upload sessions
  are cleaned up automatically.
- Added server-side scan ingestion job tracking so accepted video and
  mixed-media scans expose processing, finalizing, retryable failure, and
  completion state for recovery.
- Hardened server scan recovery so ingestion jobs record the exact media
  manifest and reconciliation only abandons staged media after active leases and
  retry windows have expired.
- Added a sanitized server replay intent for staged scan ingestion so retry and
  repair tooling can recover accepted media requests without storing raw media
  bytes.
- Added scheduled server replay for resumable staged scan ingestion so image,
  video, audio, and description scans can recover after app exits or transient
  backend failures.
- Hardened legacy scan recovery so image, description, and audio compatibility
  endpoints now write the same server ingestion ledger before returning success.
- Added a media-ingestion contract test matrix so image, video, audio,
  description, replay, status, repair, and Explore sharing contracts are checked
  together before backend deploys.
- Improved scan media health monitoring with incident-action guidance for each
  detected issue code, including owner, next step, runbook, and sample-field
  hints.
- Updated iOS offline recovery so queued scans respect server ingestion job
  state instead of resubmitting while video/media finalization is still in
  progress.
- Fixed cloud-hydrated video scans so sampled analysis frames stay hidden behind
  the playable video instead of appearing as standalone Insight carousel images.
- Fixed video scan upload signing so five sampled inference frames plus the
  playback clip fit the staging contract, and repaired staged media rows that
  were blocked before the scan record existed.
- Improved camera shutter feedback so photo captures and video recording start
  with a stronger, prewarmed haptic cue, and video recording begins almost
  immediately after a brief hold.
- Updated video scan analysis so Pro video scans sample five ordered frames,
  treat accompanying audio as evidence from the same video, and are no longer
  described as images.
- Added a Pro paywall carousel slide for video scans and improved feature text
  wrapping.
- Added video scans to the Pro paywall comparison table.
- Fixed the Pro paywall purchase button so it stays anchored to the bottom of
  the sheet.
- Kept non-Pro long-presses photo-first so holding the shutter does not
  interrupt capture or open the paywall.
- Fixed non-biological scan saving so captures that omit ecology metadata are
  saved with an unknown ecology fallback instead of failing in the backend.
- Fixed network timeout results so they keep the "Network timeout" title,
  explain automatic retry, and no longer show non-biological collection or
  retention messaging.
- Hid live viewfinder hint pills once single-scan content is staged or
  multi-scan staging is full.

### Explore

- Added public video Explore posts: shared video scans can now appear in Explore
  and Ask the Community with muted playback in feed/detail and thumbnail play
  indicators on compact surfaces.
- Fixed video Explore sharing so composer-selected video clips publish, edit,
  and request Community ID from the server media source list, while failed media
  snapshots no longer leave the Share sheet showing a phantom Explore post.
- Improved video Explore sharing repair so scans with a surviving local `.mp4`
  can restore missing cloud video media before publishing.
- Hardened video media recovery so cloud scans keep ready-state image/video
  media records for future sharing and playback repairs.
- Added Explore post management actions to the Insight top menu so published
  scans can be edited or opened without returning to the Share sheet.
- Added a View insight action to your own Explore post menus, including posts
  opened from an Insight sheet or your Profile's published scans.
- Fixed notification-opened comment reply threads so parent comments and replies
  include the same emoji reaction controls as regular Explore comments.
- Hid reference images on shared human identifications so Explore pages show
  only the user's media.

### Scans

- Improved offline queue reliability so image, video, audio, and description
  scans keep retry state across app restarts, show retry/needs-attention status,
  and no longer discard user media after a fixed number of transient failures.
- Added redacted offline queue diagnostics for support, including queued job
  state and recent queue events without private media.
- Added Image and Video media filters to the Scans filter sheet.
- Restored the Explore posts scan filter so the Scans library can show scans
  that have already been shared to Explore.
- Hardened launch recovery so a damaged local scan library can be quarantined
  safely without signing the user out.
- Fixed recent TestFlight upgrades so existing local scan libraries open
  normally instead of launching in safe mode after a schema update.
- Fixed a startup safe-mode loop caused by a no-op historical schema version
  being included as a separate SwiftData migration stage.
- Fixed local libraries blocked by duplicate schema checksums by retrying
  startup with short, recent-only migration plans before safe mode.
- Improved launch migration selection so fresh and already-current local
  libraries open without validating the full historical migration plan, while
  recent older libraries use the smallest source-specific plan available.
- Fixed offline-queue schema upgrades so existing queued scans initialize their
  durable retry state instead of repeatedly reopening in safe mode.
- Added broader startup migration safety checks so queued image, video, audio,
  description, and mixed-media scans are tested together before release.
- Improved safe-mode diagnostics when a local library upgrade fails, keeping the
  store in place while reporting an upgrade-specific recovery reason.

### Insight Sheet

- Video scan media now starts muted playback once when its Insight sheet opens,
  with a bottom-left sound status toggle.
- Fixed account-library video scans whose cloud record still listed sampled
  frames so Insight opens the playable video instead of a thumbnail sequence.
- Video scans that only have sampled frames available now fall back to the
  middle frame instead of filling the Insight carousel with all five samples.
- Hid reference images for human identifications so Insight shows only the
  user's captured media.
- Added fullscreen playback for video scan media from the Insight carousel.
- Added field-note visibility controls to the Field notes edit sheet, with
  Published and Private badges on shared Insight and Explore note cards.
- Fixed empty Field notes cards so Published or Private badges only appear once
  there are saved notes.
- Added a Non-biological pill and retention notice to non-biological Insight
  results, and hid biological-only field notes, tags, and collection actions
  from those scans.
- Simplified dog and cat Insight subtitles so pet-label scans show only the
  scientific name in the taxonomy line.
- Replaced the local New discovery pill with a richer bottom milestone banner
  for achievements and scans that add a species to the shared species
  dictionary, while preventing foreground iOS achievement notifications from
  stacking over it.
- Seeded legacy domestic cat and dog achievement completions silently so older
  qualifying scans do not trigger surprise retroactive unlock banners.
- Updated video scans so Insight opens the saved clip as the primary media item
  while scan tiles and previews keep using the poster thumbnail.
- Fixed pending video scans so playback can resolve the saved local clip
  immediately after submission.
- Fixed Overview interactions so longer ecological interaction notes wrap fully
  instead of truncating.
- Improved Insight overviews with a compact, location-aware invasive status
  summary that can show the assessed region, confidence, and Merian's rationale
  when available.
- Hid the upgrade plan card from the confidence details sheet for Pro users.

### Insight Chat

- Added Field chat as a bottom-sheet experience from biological Insight
  toolbars, with one saved conversation per scan, prompt chips, typed
  follow-ups, safety guardrails, and server-side token tracking.
- Moved Add to collection into the Insight header menu below field notes,
  freeing the bottom toolbar for Chat.
- Expanded Field chat's private scan context so answers can use review
  provenance, observed traits, ecology metadata, species group tags, and
  image/capture-quality signals without sending image data or public Explore
  content.
- Improved Field chat recovery and trust cues with offline read-only messaging,
  in-thread failed-send retry/edit, safety guidance headers, answer actions,
  private answer feedback, and append-only field-notes handoff.
- Added a subtle, steady rainbow glow behind the Field chat toolbar button to
  make the AI entry point easier to notice without moving or restyling the
  native button label.
- Field notes cards now show up to 10 preview lines before truncating longer
  notes.
- Field chat summaries now use human-readable observation labels instead of
  internal scan IDs.
- Simplified Field chat answer actions to icon-only copy and inline feedback,
  with thread summaries and feature feedback in the sheet options menu.
- Field chat sheet feedback is now saved privately with the scan instead of
  being telemetry-only.
- Field chat quick prompts now refresh with AI-generated, scan-specific
  follow-up ideas based on the saved observation and recent chat.
- Field chat now checks scan availability before opening so scans owned by
  another signed-in account are hidden with a clear unavailable toast instead of
  launching into a 403 error.
- Increased Field chat message text size so questions and answers are easier to
  read.

### Image Viewer & Reference Gallery

- Added a full-screen Insight image viewer so tapping a scan image opens a
  fit-centered, swipeable carousel with zoom and reference attribution.
- Added the same full-screen image viewer to Species Dictionary reference
  galleries.
- Added swipe-down dismissal to the full-screen Insight image viewer.
- Fixed the full-screen Insight image viewer so fit-to-screen images stay
  vertically centered.

### Community Identification (Identify)

- Added an Identify tab to Explore for Ask the Community identification
  requests, with an Insight-sheet CTA, community request queue, taxonomy search,
  disagreement prompts, and backend consensus storage.
- Added Requests and Activity modes to the Identify header, with an All/Yours
  request filter and an Activity placeholder for future consensus updates.
- Added owner-only Community request options with an Edit Request sheet for
  updating request notes and location sharing.
- Added reporting to Community request detail menus for requests owned by other
  users.
- Replaced the Community request loading spinner with skeleton request cards.
- Unified Explore error states around the Dictionary unavailable layout and
  Retry action style.
- Added Community identification notifications for new IDs, resolved requests,
  and helped consensus outcomes, with a dedicated Profile push preference.
- Added a View action to the Ask the Community confirmation toast so new
  requests can open directly in the Community detail page.
- Added Ask the Community as the recovery path when users reject every
  identification candidate.
- Added AI-derived starting suggestions to the Community Suggest ID sheet.
- Fixed resolved Ask the Community publishing so owner-approved species
  consensus now confirms the scan species, creates a minimal Dictionary record
  for new GBIF-backed taxa, and makes eligible media available for species
  reference images.
- Fixed Ask the Community request ownership after account identity changes so
  requests stay associated with the signed-in user and remain visible under
  Yours.
- Fixed the Ask the community request sheet title casing and kept Send/Save in
  the sheet toolbar so create and edit requests use the same form style.
- Fixed Identify request cards so their submitted-ID badge refreshes after
  someone suggests, withdraws, or restores an ID from the detail screen.
- Fixed existing Ask the community request actions in the Insight share flow
  with Edit/View buttons plus a Publish to Explore option and visible review
  disclaimer.
- Updated Community request detail images to extend into the top edge of the
  sheet, matching the Insight image presentation.
- Updated open Identify request cards and loading skeletons to hide AI-derived
  names and show only the scan image with a compact submitted-ID count overlay.
- Rebuilt Community identification around versioned Merian taxonomy, queued
  consensus processing, and projection-driven Explore graduation so unresolved
  requests stay out of normal Explore until verified.
- Removed the unused identification-review action from Insight and candidate
  review flows.
- Polished Community identification sheets with icon close controls and a
  cleaner disagreement reason field.
- Kept internal Community identification consensus labels out of the public
  identification timeline.

### Profile & Guest Account Polish

- Added an Invite a friend card on Profile and a matching Settings resource so
  sharing Merian is ready for a future referral link.
- Added cat and dog scan achievements that unlock when you document your first
  domestic cat or dog.
- Added the cat and dog achievements to public Explore author profile sheets.
- Fixed achievements so deleting the qualifying scan from an achievement detail
  sheet refreshes the root Profile achievement card immediately.
- Matched Profile signed-out spacing below the sign-in buttons to the gap
  between the stat cards.
- Fixed Profile published-scan grids so partial rows keep rounded outer image
  corners instead of exposing sharp edges.
- Updated Pro plan card copy to match the current paywall value props for
  unlimited field scans, Pro AI vision, AI chat, multi-capture, Apple Watch
  logging, and expedition mode.
- Pro plan cards now use the intended launch prices and labels for Annual and
  the 7 Day Pass, even while App Store product metadata is settling.
- Added AI chat to the Pro paywall feature comparison table.
- Added guest profile customization: guests can now choose a public profile
  picture, display name, and username before signing in, and those choices carry
  into Apple or Google sign-in.
- Added custom public profile picture uploads for logged-in users, with
  R2-backed avatar storage, Profile picker support, and Explore/Profile identity
  refresh.
- Replaced Explore profile loading spinners with skeleton placeholders that
  match the profile layout.
- Fixed the profile scan heatmap so brand-new or empty libraries still show the
  empty contribution cells instead of collapsing the grid.
- Reordered Profile so identity and stats lead the page, followed by published
  scans, the non-Pro plan card, persona progress, the scan heatmap, and
  achievements.

### Explore Feed & Map Refinements

- Fixed Explore post web links so Universal Links open the matching native
  Explore post when Merian is installed.
- Updated Explore post sharing copy so shared links introduce the Merian public
  web preview more clearly.
- Added dynamic species-type filters to Explore Map, with horizontal filter
  pills, a detailed filter sheet, and backend-backed category counts for the
  current map region.
- Fixed Explore feed hashtag rows so long hashtag sets can scroll edge to edge
  without being clipped by card padding.
- Fixed the Explore edit-post sheet so the Save footer stays compact instead of
  expanding up the screen.
- Fixed Explore Map selected discoveries so the active waypoint appears above
  overlapping nearby waypoints.
- Fixed Explore Map overlay controls so bottom-anchored actions stay pinned near
  the tab bar when switching from Feed to Map.
- Fixed Explore Map geoprivacy so only open-location discoveries appear on the
  map; obscured and private posts stay off the map.
- Added per-post Explore geoprivacy so share/edit options can keep a post
  private, show an obscured public label, or explicitly make that post open on
  the map without changing the underlying scan default.
- Fixed Explore posts so shared discoveries keep the selected common name from
  the composer instead of drifting to dictionary defaults.
- Added a common-name picker for Explore sharing and editing so posts use the
  known species name you choose.
- Refined Explore hashtag pills with transparent backgrounds, gray borders, and
  blue text on feed cards, post detail pages, and the post composer.
- Updated Explore posts to show usernames on feed cards and post detail headers.
- Updated Explore comment composers so mentions can be inserted from
  autocomplete and resolved mention spans open the user's public profile sheet.
- Added `@username` mentions in Explore comments, with scoped suggestions for
  post authors, visible thread participants, and followed users plus mention
  notifications.
- Added an independent Notifications setting for Explore comment mention pushes,
  while keeping mention activity visible in the in-app Explore notifications
  feed.
- Explore activity and comment mention push notifications now default on for new
  installs.
- Streamlined Explore post details so species education lives in the species
  dictionary, while reference images, observation context, alternate names, and
  a direct dictionary link remain easy to find.
- Fixed Explore map count text so exactly one visible item says "1 discovery in
  view."

### Collections

- Moved built-in collection tiles below the main Collections content so
  first-collection guidance appears before Favorites and Non-biological.
- Added a little more top spacing to Collections so the first cards sit more
  comfortably below the Scans toolbar.
- Added a Scans-style Collections filter sheet with sorting plus User-created,
  Smart suggestions, and Built-in collection type filters.
- Added a taller full-width Featured scans collection at the top of Collections
  with a daily rotating set of up to 24 scans from your library.
- Moved collection creation into a blue plus button in the Collections toolbar
  and removed the unused Collections sort menu.
- Converted Favorites, Needs review, and Non-biological into gallery-style
  artwork collection tiles.
- Added smart default Collections that suggest helpful scan groupings from your
  library, such as recent finds, places, review candidates, and common organism
  groups, plus an Explore posts collection, with local hide controls while Needs
  review stays pinned.
- Smart Collection cards now use varied matching scan covers, except Recent
  finds, instead of always reusing the newest scan thumbnail.

### Scans Library

- Added a full Scans filter sheet for sorting, category, dates, location, tags,
  naturalist details, photo quality, identification state, weather, season, and
  taxonomy.
- Scans filters now stack with search and sorting, with a visible active-filter
  count and a clear action that keeps the current search text.
- Changed the Scans and Collections active-filter badge to red so it stands out
  from the blue filter button.

### Describe Modality Improvements

- Fixed Describe suggestions so tapping a prompt chip no longer leaves the
  bottom toolbar hidden.
- Updated the Describe add button so empty inputs show a secondary outline state
  and filled inputs show the active filled state.
- Fixed non-biological correction reanalysis so the explanatory prompt no longer
  remains in the Describe text field as if it were user-entered notes.
- Fixed reanalysis submissions so Describe text entered for the current analysis
  is consumed into the submission and cleared from the input afterward.
- Fixed capture bottom controls getting hidden by stale keyboard state after
  leaving Describe or canceling staged input.

### Species Dictionary & Taxonomy Tree

- Added an Explore Tree scope filter so the Tree defaults to All species and can
  be toggled to My scans for a personal scanned-species taxonomy.
- Added a scheduled species model-content worker so newly materialized
  Dictionary species can hydrate habitat, lookalikes, and group tags outside of
  user scan sessions.
- Added extra species dictionary data fetches so undiscovered species can still
  load dictionary pages when users navigate to them.
- Added an Explore bottom navigation for Observations, Identify, and Dictionary,
  with Feed and Map grouped inside the Observations header toggle.
- Added a searchable Species Dictionary catalog with category browsing,
  Dictionary detail pages, and species reference imagery.
- Added Dictionary category browsing with a Recently Added featured species
  card, a full-width Your Region map card when local entries are available, an
  All row, plus region rows backed by dictionary-native range metadata.
- Added high-level Dictionary group cards with custom graphics for broad browse
  paths such as Plants, Birds, Insects, Fungi, Mammals, and Reptiles &
  Amphibians, with toolbar search available inside those species lists.
- Added a Catalog/Tree segmented control to the Explore Dictionary header,
  keeping the taxonomy tree inside Dictionary while the Explore bottom menu
  stays focused on Observations, Identify, and Dictionary.
- Matched the main camera tab bar icon size, label size, and item spacing to the
  Explore bottom navigation.
- Removed search from the Explore Dictionary Tree view so the header toggle
  opens directly into the pan-and-zoom taxonomy canvas.
- Removed the filled top heading background from the Explore Dictionary Tree
  canvas for a cleaner full-canvas view.
- Updated the Explore Dictionary Tree zoom and locate controls with liquid-glass
  circular button chrome.
- Fixed the Explore Dictionary Recently Added row so its species count reflects
  the newest entries instead of duplicating the full All total.
- Fixed Species Dictionary catalog and overview surfaces so non-biological
  encyclopedia rows are filtered out before they can appear as dictionary
  records.
- Replaced species seasonality line charts with a unified month heatmap that
  shows represented totals, peak month detail, and a clearer unavailable state
  while buckets refresh.
- Fixed similar species so lookalike suggestions load reliably in insight
  sheets.
- Species dictionary galleries now admit more published Merian photos by
  lowering the Merian reference-image quality gate while keeping the species
  confidence gate in place.
- Explore Dictionary now uses already-granted location access to improve the
  Your Region category, while falling back to the device locale without showing
  a Dictionary-specific permission prompt.

### Community Taxonomy Indexing & Enrichment

- Added a GBIF-backed Community Taxonomy Index so Ask the Community search can
  suggest taxa that are not yet enriched in Merian's Dictionary, plus
  first-class species enrichment jobs and the first Birds coverage target for
  future Dictionary-completeness progress.
- Added an internal Community Taxonomy status endpoint so taxonomy coverage,
  GBIF import runs, and species enrichment queue health can be checked during
  rollout.
- Added a bounded GBIF Birds import worker so Merian can seed Community ID
  suggestions and future Dictionary coverage metrics without mirroring all of
  GBIF.
- Added safer Community Taxonomy import operations with database cursor
  tracking, lightweight coverage status checks, an operator script, and
  production deploy smoke checks.
- Added smarter dog and cat scan labels so pet results can show a likely breed,
  mix, coat pattern, or body type while keeping Merian's species taxonomy
  unchanged.

### Web Scaffolds & Legal Hub

- Added the initial Next.js + Mantine web app scaffold for public Explore share
  pages.
- Added public Terms, Privacy Policy, Community Guidelines, Privacy Choices,
  Support, and Legal hub pages for `merian.earth`.
- Added an iOS-to-web theme bridge so Merian-opened web pages can follow the
  app's theme preference.

### Offline Sync, Geoprivacy & Edge Functions

- Fixed Supabase Edge Function deploy reliability by routing runtime
  dependencies through the function import map and removing deploy-time
  deno.land/esm.sh runtime fetches from function graphs.
- Fixed Insight sharing and Ask the community requests for local scans whose
  cloud scan row was missing after background ingestion failed.
- Fixed non-biological corrections so they now explain the result and start
  reanalysis instead of creating an unidentified biological scan with incorrect
  confidence, phantom reference media, or premature Explore sharing.
- Fixed non-biological insight titles so stored taxonomy placeholders now
  display as "Non-biological" instead of "Unknown Subject".
- Fixed Needs review smart collections so they follow the shared non-strong and
  competitive-alternative thresholds instead of every scan that happens to have
  candidates.
- Fixed non-biological scans older than 30 days remaining on device by adding
  local foreground cleanup that mirrors the server purge window.
- Fixed geoprivacy so private scans hide location details across scan cards,
  sharing, achievements, Messages share captions, and public labels, while open
  and obscured scans restore location context at the expected precision.
- Fixed species observation charts timing out on first load by returning core
  public stats quickly while detailed life-stage and sex buckets refresh in the
  background.
- Hardened Edge media request/response handling so chunked or missing-length
  bodies are capped while streaming before V8 heap allocation can run away.
- Reduced share-import, expanded-original-image, local species-chart, APNs
  fanout, collection-sync, and audio-carousel resource usage to prevent OOMs,
  main-thread stalls, and idle battery drain.
- Hardened scan purge jobs so they cannot delete durable public avatar images.
- Added AI-derived sex observation metadata to scan records, the Overview card,
  Supabase persistence, and Darwin Core exports.
- Added native Messages extension groundwork for inserting cached scan images,
  cards, and descriptions into iMessage.

### Beta Feedback & Settings Changelog

- Fixed the proactive beta feedback survey so the third-scan prompt waits until
  the Insight sheet closes instead of competing with the result sheet.
- Added a one-time beta feedback survey with a warm intro screen, proactive
  prompt after meaningful use, Settings access, and private Supabase response
  storage. Manual survey access now resets after a 24-hour thank-you cooldown so
  testers can send fresh feedback again without being proactively re-prompted.
- Added a bundled in-app changelog in Settings for selected release notes,
  feature notes, and in-progress work.
- Simplified the in-app changelog to show dates without version/build labels
  until release versioning is finalized.
