# Changelog

Notable user-facing changes are collected here as release-note source material.
Keep detailed code history in git; keep this file focused on what matters for
TestFlight, App Store, support, and QA.

## Unreleased

### Insight Chat
- Added Field chat as a bottom-sheet experience from biological Insight toolbars, with one saved conversation per scan, prompt chips, typed follow-ups, safety guardrails, and server-side token tracking.
- Moved Add to collection into the Insight header menu below field notes, freeing the bottom toolbar for Chat.
- Expanded Field chat's private scan context so answers can use review provenance, observed traits, ecology metadata, species group tags, and image/capture-quality signals without sending image data or public Explore content.
- Improved Field chat recovery and trust cues with offline read-only messaging, in-thread failed-send retry/edit, safety guidance headers, answer actions, private answer feedback, and append-only field-notes handoff.
- Added a subtle, steady rainbow glow behind the Field chat toolbar button to make the AI entry point easier to notice without moving or restyling the native button label.
- Field notes cards now show up to 10 preview lines before truncating longer notes.
- Field chat summaries now use human-readable observation labels instead of internal scan IDs.
- Simplified Field chat answer actions to icon-only copy and inline feedback, with thread summaries and feature feedback in the sheet options menu.
- Field chat sheet feedback is now saved privately with the scan instead of being telemetry-only.
- Field chat quick prompts now refresh with AI-generated, scan-specific follow-up ideas based on the saved observation and recent chat.
- Field chat now checks scan availability before opening so scans owned by another signed-in account are hidden with a clear unavailable toast instead of launching into a 403 error.

### Image Viewer & Reference Gallery
- Added a full-screen Insight image viewer so tapping a scan image opens a fit-centered, swipeable carousel with zoom and reference attribution.
- Added the same full-screen image viewer to Species Dictionary reference galleries.
- Added swipe-down dismissal to the full-screen Insight image viewer.
- Fixed the full-screen Insight image viewer so fit-to-screen images stay vertically centered.

### Community Identification (Identify)
- Added an Identify tab to Explore for Ask the Community identification requests, with an Insight-sheet CTA, community request queue, taxonomy search, disagreement prompts, and backend consensus storage.
- Added Requests and Activity modes to the Identify header, with an All/Yours request filter and an Activity placeholder for future consensus updates.
- Added owner-only Community request options with an Edit Request sheet for updating request notes and location sharing.
- Added reporting to Community request detail menus for requests owned by other users.
- Replaced the Community request loading spinner with skeleton request cards.
- Unified Explore error states around the Dictionary unavailable layout and Retry action style.
- Added Community identification notifications for new IDs, resolved requests, and helped consensus outcomes, with a dedicated Profile push preference.
- Added a View action to the Ask the Community confirmation toast so new requests can open directly in the Community detail page.
- Added Ask the Community as the recovery path when users reject every identification candidate.
- Added AI-derived starting suggestions to the Community Suggest ID sheet.
- Fixed resolved Ask the Community publishing so owner-approved species consensus now confirms the scan species, creates a minimal Dictionary record for new GBIF-backed taxa, and makes eligible media available for species reference images.
- Fixed Ask the Community request ownership after account identity changes so requests stay associated with the signed-in user and remain visible under Yours.
- Fixed the Ask the community request sheet title casing and kept Send/Save in the sheet toolbar so create and edit requests use the same form style.
- Fixed Identify request cards so their submitted-ID badge refreshes after someone suggests, withdraws, or restores an ID from the detail screen.
- Fixed existing Ask the community request actions in the Insight share flow with Edit/View buttons plus a Publish to Explore option and visible review disclaimer.
- Updated Community request detail images to extend into the top edge of the sheet, matching the Insight image presentation.
- Updated open Identify request cards and loading skeletons to hide AI-derived names and show only the scan image with a compact submitted-ID count overlay.
- Rebuilt Community identification around versioned Merian taxonomy, queued consensus processing, and projection-driven Explore graduation so unresolved requests stay out of normal Explore until verified.
- Removed the unused identification-review action from Insight and candidate review flows.
- Polished Community identification sheets with icon close controls and a cleaner disagreement reason field.
- Kept internal Community identification consensus labels out of the public identification timeline.

### Profile & Guest Account Polish
- Matched Profile signed-out spacing below the sign-in buttons to the gap between the stat cards.
- Fixed Profile published-scan grids so partial rows keep rounded outer image corners instead of exposing sharp edges.
- Added guest profile customization: guests can now choose a public profile picture, display name, and username before signing in, and those choices carry into Apple or Google sign-in.
- Added custom public profile picture uploads for logged-in users, with R2-backed avatar storage, Profile picker support, and Explore/Profile identity refresh.
- Replaced Explore profile loading spinners with skeleton placeholders that match the profile layout.
- Fixed the profile scan heatmap so brand-new or empty libraries still show the empty contribution cells instead of collapsing the grid.
- Reordered Profile so identity and stats lead the page, followed by published scans, the non-Pro plan card, persona progress, the scan heatmap, and achievements.

### Explore Feed & Map Refinements
- Fixed Explore post web links so Universal Links open the matching native Explore post when Merian is installed.
- Updated Explore post sharing copy so shared links introduce the Merian public web preview more clearly.
- Added dynamic species-type filters to Explore Map, with horizontal filter pills, a detailed filter sheet, and backend-backed category counts for the current map region.
- Fixed Explore feed hashtag rows so long hashtag sets can scroll edge to edge without being clipped by card padding.
- Fixed the Explore edit-post sheet so the Save footer stays compact instead of expanding up the screen.
- Fixed Explore Map selected discoveries so the active waypoint appears above overlapping nearby waypoints.
- Fixed Explore Map overlay controls so bottom-anchored actions stay pinned near the tab bar when switching from Feed to Map.
- Fixed Explore Map geoprivacy so only open-location discoveries appear on the map; obscured and private posts stay off the map.
- Added per-post Explore geoprivacy so share/edit options can keep a post private, show an obscured public label, or explicitly make that post open on the map without changing the underlying scan default.
- Fixed Explore posts so shared discoveries keep the selected common name from the composer instead of drifting to dictionary defaults.
- Added a common-name picker for Explore sharing and editing so posts use the known species name you choose.
- Refined Explore hashtag pills with transparent backgrounds, gray borders, and blue text on feed cards, post detail pages, and the post composer.
- Updated Explore posts to show usernames on feed cards and post detail headers.
- Updated Explore comment composers so mentions can be inserted from autocomplete and resolved mention spans open the user's public profile sheet.
- Added `@username` mentions in Explore comments, with scoped suggestions for post authors, visible thread participants, and followed users plus mention notifications.
- Added an independent Notifications setting for Explore comment mention pushes, while keeping mention activity visible in the in-app Explore notifications feed.
- Explore activity and comment mention push notifications now default on for new installs.
- Streamlined Explore post details so species education lives in the species dictionary, while reference images, observation context, alternate names, and a direct dictionary link remain easy to find.
- Fixed Explore map count text so exactly one visible item says "1 discovery in view."

### Collections
- Added a little more top spacing to Collections so the first cards sit more comfortably below the Scans toolbar.
- Added a taller full-width Featured scans collection at the top of Collections with a rotating cover image from your scan library.
- Moved Add collection out of the Collections menu and into a blue in-list button below the default rows, with the toolbar menu now shown as a filter-style sort button.
- Converted Favorites, Needs review, and Non-biological into gallery-style artwork collection tiles.
- Added smart default Collections that suggest helpful scan groupings from your library, such as recent finds, places, review candidates, and common organism groups, plus an Explore posts collection, with local hide controls.
- Smart Collection cards now use varied matching scan covers, except Recent finds, instead of always reusing the newest scan thumbnail.

### Describe Modality Improvements
- Fixed Describe suggestions so tapping a prompt chip no longer leaves the bottom toolbar hidden.
- Updated the Describe add button so empty inputs show a secondary outline state and filled inputs show the active filled state.
- Fixed non-biological correction reanalysis so the explanatory prompt no longer remains in the Describe text field as if it were user-entered notes.
- Fixed reanalysis submissions so Describe text entered for the current analysis is consumed into the submission and cleared from the input afterward.
- Fixed capture bottom controls getting hidden by stale keyboard state after leaving Describe or canceling staged input.

### Species Dictionary & Taxonomy Tree
- Added an Explore Tree scope filter so the Tree defaults to All species and can be toggled to My scans for a personal scanned-species taxonomy.
- Added a scheduled species model-content worker so newly materialized Dictionary species can hydrate habitat, lookalikes, and group tags outside of user scan sessions.
- Added extra species dictionary data fetches so undiscovered species can still load dictionary pages when users navigate to them.
- Added an Explore bottom navigation for Observations, Identify, and Dictionary, with Feed and Map grouped inside the Observations header toggle.
- Added a searchable Species Dictionary catalog with category browsing, Dictionary detail pages, and species reference imagery.
- Added Dictionary category browsing with a Recently Added featured species card, a full-width Your Region map card when local entries are available, an All row, plus region rows backed by dictionary-native range metadata.
- Added high-level Dictionary group cards with custom graphics for broad browse paths such as Plants, Birds, Insects, Fungi, Mammals, and Reptiles & Amphibians, with toolbar search available inside those species lists.
- Added a Catalog/Tree segmented control to the Explore Dictionary header, keeping the taxonomy tree inside Dictionary while the Explore bottom menu stays focused on Observations, Identify, and Dictionary.
- Matched the main camera tab bar icon size, label size, and item spacing to the Explore bottom navigation.
- Removed search from the Explore Dictionary Tree view so the header toggle opens directly into the pan-and-zoom taxonomy canvas.
- Removed the filled top heading background from the Explore Dictionary Tree canvas for a cleaner full-canvas view.
- Updated the Explore Dictionary Tree zoom and locate controls with liquid-glass circular button chrome.
- Fixed the Explore Dictionary Recently Added row so its species count reflects the newest entries instead of duplicating the full All total.
- Fixed Species Dictionary catalog and overview surfaces so non-biological encyclopedia rows are filtered out before they can appear as dictionary records.
- Replaced species seasonality line charts with a unified month heatmap that shows represented totals, peak month detail, and a clearer unavailable state while buckets refresh.
- Fixed similar species so lookalike suggestions load reliably in insight sheets.
- Species dictionary galleries now admit more published Merian photos by lowering the Merian reference-image quality gate while keeping the species confidence gate in place.
- Explore Dictionary now uses already-granted location access to improve the Your Region category, while falling back to the device locale without showing a Dictionary-specific permission prompt.

### Community Taxonomy Indexing & Enrichment
- Added a GBIF-backed Community Taxonomy Index so Ask the Community search can suggest taxa that are not yet enriched in Merian's Dictionary, plus first-class species enrichment jobs and the first Birds coverage target for future Dictionary-completeness progress.
- Added an internal Community Taxonomy status endpoint so taxonomy coverage, GBIF import runs, and species enrichment queue health can be checked during rollout.
- Added a bounded GBIF Birds import worker so Merian can seed Community ID suggestions and future Dictionary coverage metrics without mirroring all of GBIF.
- Added safer Community Taxonomy import operations with database cursor tracking, lightweight coverage status checks, an operator script, and production deploy smoke checks.
- Added smarter dog and cat scan labels so pet results can show a likely breed, mix, coat pattern, or body type while keeping Merian's species taxonomy unchanged.

### Web Scaffolds & Legal Hub
- Added the initial Next.js + Mantine web app scaffold for public Explore share pages.
- Added public Terms, Privacy Policy, Community Guidelines, Privacy Choices, Support, and Legal hub pages for `merian.earth`.
- Added an iOS-to-web theme bridge so Merian-opened web pages can follow the app's theme preference.

### Offline Sync, Geoprivacy & Edge Functions
- Fixed Supabase Edge Function deploy reliability by routing runtime dependencies through the function import map and removing deploy-time deno.land/esm.sh runtime fetches from function graphs.
- Fixed Insight sharing and Ask the community requests for local scans whose cloud scan row was missing after background ingestion failed.
- Fixed non-biological corrections so they now explain the result and start reanalysis instead of creating an unidentified biological scan with incorrect confidence, phantom reference media, or premature Explore sharing.
- Fixed non-biological insight titles so stored taxonomy placeholders now display as "Non-biological" instead of "Unknown Subject".
- Fixed Needs review smart collections so they follow the shared non-strong and competitive-alternative thresholds instead of every scan that happens to have candidates.
- Fixed non-biological scans older than 30 days remaining on device by adding local foreground cleanup that mirrors the server purge window.
- Fixed geoprivacy so private scans hide location details across scan cards, sharing, achievements, Messages share captions, and public labels, while open and obscured scans restore location context at the expected precision.
- Fixed species observation charts timing out on first load by returning core public stats quickly while detailed life-stage and sex buckets refresh in the background.
- Hardened Edge media request/response handling so chunked or missing-length bodies are capped while streaming before V8 heap allocation can run away.
- Reduced share-import, expanded-original-image, local species-chart, APNs fanout, collection-sync, and audio-carousel resource usage to prevent OOMs, main-thread stalls, and idle battery drain.
- Hardened scan purge jobs so they cannot delete durable public avatar images.
- Added AI-derived sex observation metadata to scan records, the Overview card, Supabase persistence, and Darwin Core exports.
- Added native Messages and Photos share extensions: Messages can insert cached scan images/cards/descriptions, and Photos can queue one shared image for Merian identification.

### Beta Feedback & Settings Changelog
- Fixed the proactive beta feedback survey so the third-scan prompt waits until the Insight sheet closes instead of competing with the result sheet.
- Added a one-time beta feedback survey with a warm intro screen, proactive prompt after meaningful use, Settings access, and private Supabase response storage. Manual survey access now resets after a 24-hour thank-you cooldown so testers can send fresh feedback again without being proactively re-prompted.
- Added a bundled in-app changelog in Settings for selected release notes, feature notes, and in-progress work.
- Simplified the in-app changelog to show dates without version/build labels until release versioning is finalized.
