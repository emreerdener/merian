# Changelog

Notable user-facing changes are collected here as release-note source material.
Keep detailed code history in git; keep this file focused on what matters for
TestFlight, App Store, support, and QA.

## Unreleased

### Brand

- Merian is now Naturebook. The name is new; your scans, account,
  subscriptions, and Explore content stay exactly where they are.

### Settings

- Renamed the Capture settings group to Workspace, keeping the Camera, Audio,
  **Reorder modes**, Field trip goal, and submission controls together.
- Added a default-off **Open Explore on launch** preference above Notifications.
  When enabled, a fresh ordinary launch opens the Explore feed; returning from
  the background does not reopen it, and shared photos, links, and tapped
  notifications still open their requested destination.

### Beta Operations

- Release and TestFlight builds now use the normal free/Pro scan meter and
  server-enforced quota. Unlimited local-meter bypasses remain available only
  in DEBUG; subscription testing is still available directly from Settings →
  Plan.
- Paywall diagnostics now distinguish a missing current offering, an empty
  package set, and missing required `pro_week` / `pro_annual` products so beta
  store-configuration failures are visible before release.
- Subscription synchronization now verifies RevenueCat's signed delivery,
  checks authoritative subscriber state, and ignores duplicate or delayed
  events that could otherwise roll a newer renewal or refund backward.
  RevenueCat account transfers now reconcile both the source and destination
  atomically instead of relying on a follow-up lifecycle event.

### Species Dictionary

- Temporarily hid the unfinished Tree of Life view from Explore’s Index while
  keeping the Species Dictionary catalog available.
- Hardened public observation charts against duplicate cold refreshes and
  provider outages. Charts now require a canonical Dictionary species, reuse
  negatively cached misses, and bound provider work with server-side rate
  limits, deadlines, and cross-server refresh leases. A failed refresh now
  keeps still-usable chart data stale instead of replacing it with an empty
  result, shared public caches are no longer fragmented by session token, and
  the app rejects legacy or mismatched responses before caching.
- Added sharing to Species Dictionary pages. Shared links open the matching
  Dictionary page in Naturebook when installed and otherwise show a rich public
  web reference with licensed imagery, attribution, taxonomy, conservation and
  safety details, habitat, overview, and linked similar species.
- Species share links now include a readable name slug after the stable UUID.
  Existing UUID-only links and links carrying an older name keep working and
  redirect to the current canonical URL in browsers.

### Media & Performance

- Fixed a scan's own photo appearing again as a reference image in Insight and
  Explore post galleries. Other Naturebook observations and eligible Wikipedia
  and GBIF references remain available.
- Hid third-party reference images for domestic cat and dog identifications
  across Insight and shared Explore pages, while keeping the user's captured
  media and retaining reference galleries for wild felids and canids.
- Added single-photo import from the iOS share sheet. Sharing an image from
  Photos to Naturebook now opens the app and routes the file through the existing
  gallery crop, confirmation, quota, metadata, analysis, and offline-queue flow.
  Included EXIF date/location is preserved online and offline; excluded Location
  never falls back to the device's current coordinates.
- Reduced live-camera still-image analysis wait time by starting inference after
  a bounded environmental-context grace period, avoiding duplicate live/background
  uploads and duplicate inference dispatch, and moving optional enrichment,
  awards, and Field trips work off the first-result path. Free and Pro Gemini models and quality settings are
  unchanged; gallery, audio-bearing, and video submission behavior is unchanged.
- Fixed Audio recording occasionally reporting unavailable hardware immediately
  after switching from Camera. Recording now waits for camera release and
  safely recovers while the microphone route settles.
- Fixed videos starting silently after capture or app launch. Audible playback
  now reactivates the shared media session across Scans, Insights, and Explore
  without requiring an audio post to be played first.
- Removed a priority-inversion hang risk from local and remote image decoding.
  Decode concurrency remains capped for memory safety, but excess work now
  suspends asynchronously instead of blocking user-initiated threads.
- Prevented delayed camera recording callbacks, timeouts, and automatic-stop
  tasks from completing or stopping a newer video after rapid cancel/retry
  sequences.
- Fixed rapid thermal or power-state changes occasionally leaving the camera at
  an older frame-rate limit after the device heated up or recovered.
- Prevented delayed offline upload, inference, retry, status-probe, and
  background-expiration callbacks from clearing or cancelling a newer sync
  attempt. Queue progress now remains accurate across rapid reconnects,
  retries, and app suspension.
- Prevented non-finite media geometry from reaching SwiftUI in Explore detail
  zoom and audio playmarkers, eliminating invalid-frame warnings and unstable
  offsets during transient layout/player states.
- Removed the Capture startup SwiftUI AttributeGraph cycle for every configurable
  first mode (Camera, Audio, and Description). The pager now builds pages lazily,
  Description isolates its vertical scroller and reactive lifecycle from the
  horizontal pager, and capture chrome uses a fixed layout reservation. Startup
  Field-trip goal loading also shares one freshness-gated refresh instead of
  repeating the same capture-context and introduction requests. Leaving
  Description or closing the workspace now also stops dictation that is active
  or still starting.
- Restored the camera hint badge's pre-regression position above the shutter;
  full-screen overlays now use their prior fixed 250 pt clearance without
  reintroducing capture-bar measurement or startup layout feedback, with a UI
  regression test that checks the rendered hint and shutter frames do not overlap.
- Center-aligned the primary and secondary capture controls across Scan, Record,
  and Describe, and restored the Describe editor's clearance above that row;
  expanded the editor to fill the available height instead of leaving blank
  space above the controls; removed Describe's duplicate top-safe-area padding;
  Describe UI coverage now bounds both surrounding gaps and verifies the shared
  control centerline.
- Release configuration now requests the production APNs entitlement.

### Explore

- Added the floating **Field chat** control to every visible Explore post
  detail, including the viewer's own posts. Each Pro viewer gets a private
  conversation visible only to them, grounded in the published observation and
  Species Dictionary.
- Simplified the Explore Field chat empty-state message to clearly say the
  conversation is private and visible only to the viewer.
- Field chat now hides when the sticky comment composer appears, keeping the
  public comment action visually primary at the bottom of an Explore post. A
  Field chat fallback moves into the post menu while the floating control is
  hidden.
- Fixed remote push-device registration failing with a Supabase 500 by replacing
  an unsupported PostgreSQL `{32,512}` regex bound with separate hex-format and
  length constraints; added static migration and executable database coverage,
  and clarified that the iOS token log records Apple's callback rather than a
  completed server registration.
- Reduced unread-badge network churn by sharing one in-flight count refresh,
  briefly reusing successful results, and using Realtime as the primary update
  path with a five-minute polling fallback.
- Fixed cross-device preferred species names repeatedly writing an already
  matching value or tombstone during cloud reconciliation.

- Fixed the Field notes editor so closing an unchanged note no longer republishes
  its existing visibility, shows a misleading public toast, or refreshes the
  Explore detail page. Real text edits still autosave with a **Field notes
  updated** confirmation, while public/private messages appear only after an
  actual visibility change.
- Released Field trips and standard Outings to every user. The Events segment
  remains a client-gated preview for the tester account and simulator builds so
  its seasonal challenge UI can continue iterating independently.
- Redesigned Outing catalog cards with a compact progress ring, current-level
  Backyard Safari copy, the existing scrolling goal thumbnails, and pills for
  access, difficulty, level, public/private status, and an available
  privacy-filtered location.
- Added **The Field Naturalist**, an Easy achievement earned by completing a
  first outing or Seasonal Challenge. Its completed Profile card and unlock
  notification reopen the Field trip that earned it.
- Standardized **Field trip** / **Field trips** as the feature label while using
  **outing** for contextual descriptions, actions, activity messages, and
  VoiceOver. Renamed the standard catalog segment from **Challenges** to
  **Outings**; Seasonal Challenge terminology is unchanged.
- Added `All`, `Starter`, `Easy`, `Moderate`, and `Hard` difficulty filters to
  the Field trips catalog, including an illustrated empty state for levels
  without a current trip.
- Moved Goals and Tips into pinned toolbar tabs on standard Field trip and
  Seasonal Challenge detail pages. Goals now owns the trip overview,
  progress, actions, checklist, and Community content, while Tips opens directly
  to the curated guide.
- Added the same circular progress treatment to the active outing level header.
  Completed goals now replace their illustration with the exact captured photo
  or video thumbnail in both outing cards and detail, keep the standard neutral
  border, and open that scan's Insight within the current Explore sheet with a
  back arrow.
- Added Field trip progress notifications after a saved scan counts toward an
  outing or Seasonal Challenge. Each notification names the species and trip,
  shows the credited level's progress ring, and opens the matching outing goal
  or challenge when tapped. Notifications from one scan now appear in a stable
  order: outings, Seasonal Challenges, achievements, then New to Naturebook.
  Re-identifying an older scan scopes feedback to completion rows added by that
  attempt, preventing a prior level or destination from being announced again.
- Added a persistent **Field trips** card to saved biological Insights. Its
  compact rows separate the uppercase completion state from the goal name and
  pair larger objective artwork with a prominent credited-level progress ring.
  It keeps every outing or visible Event credited by that scan together and
  now matches other Insight card headers, removes the redundant level subtitle,
  uses a smaller goal heading, and opens the outing/Event Goals overview in the
  same navigation stack. Back returns to the originating Insight without
  replaying milestone feedback.
- Standard outings now advance only after the user explicitly starts them, and
  Events only after the user joins. One scan can count toward several active
  experiences, but only one goal in each; a selected live Camera goal wins when
  it is still eligible, with deterministic server matching otherwise. The
  selection survives offline upload, and unfinished progress is re-evaluated
  after identification corrections.
- Fixed temporary scan-persistence and network failures being mistaken for
  completed Field trip processing. Naturebook now preserves the selected goal,
  retries progress automatically, and still shows other earned milestones once
  without duplicating them after recovery.
- Made Field trip attribution durable and transactional. Scan ingestion now
  applies standard outing progress, joined Event progress, the selected-goal
  preference, and first-outing achievement state in one database transaction;
  a private receipt lets later retries recover the original unlock result after
  app termination. The local selected-goal hint is kept until the server
  acknowledges progress.
- Hardened every Field trip and Event `SECURITY DEFINER` database function so
  direct anonymous/authenticated RPC calls cannot impersonate another user;
  authenticated clients now reach them only through the identity-verifying Edge
  API. Also fixed completed-outing publication item materialization and removed
  the profile-pin routine's fragile temporary-table dependency.
- Fixed saved Insight Field trip cards and the first-Field-trip Profile award
  remaining empty when a cached account session finished restoring after the
  screen appeared.
- Fixed ants counting toward Park Pollinators' **Bee or wasp** goal. The goal
  now requires a Hymenoptera identification categorized as a bee or wasp, so
  ants, sawflies, and other broader-order matches do not count, and any earlier
  invalid credit is removed from active progress.
- Tightened the rest of the active Outing checklist so labels and completion
  rules agree. Moths no longer count as Backyard **Butterfly**, ticks and
  scorpions no longer count as **Spider**, and animal/plant/ecology goals now
  require both the named organism group and the matching signal. Park goals
  that could not verify “near flowers” are now honestly labeled **Spider** and
  **Bird**, and the scene-based **Pollinator habitat** target is now the
  verifiable **Meadow plant** target. Earlier credit that fails the corrected
  rules is removed from active progress.
- Added a left-aligned, above-title **Private** / **Published** badge to standard outing detail.
  Published is shown only when the owner has an active public outing snapshot;
  completion alone remains Private.
- Added a compact active outing target beneath the visual Scan mode picker.
  It matches the picker width and centers an instructional `Look for: {target}`
  label and outing name between artwork and an AirPods-inspired circular
  progress ring. Swiping cycles through unfinished targets across active
  standard outings, and tapping opens and highlights the matching guide. The
  indicator stays out of staged captures, refinement, video recording, other
  capture modes, and Seasonal Challenges.
  Its capsule uses untinted interactive Liquid Glass on iOS 26 and a neutral
  material fallback on earlier supported versions.
  An on-by-default Field trip goals setting can hide the capsule without changing
  outing data or progress, and tapping the capsule now provides light haptic
  confirmation before opening its guide.
  Its shared goal context is source-agnostic, so future guided experiences can
  integrate without coupling their API models or ranking rules to the camera.
- Kept a linked standard outing available in the Scan target indicator after
  joining a Seasonal Challenge. Challenge-specific progress remains separate
  and does not enter the standard outing indicator.
- Retired the placeholder Forest Edges outing from catalogs, detail/start
  routes, and the Scan target indicator while preserving existing progress,
  scans, publications, and evidence.
- Refined standard and Seasonal Field trip card and detail-image rounding, moved
  template badges onto the cover image, allowed full-width card text, and
  removed the redundant Open guide row and active-trip Continue Scanning
  actions. Loading skeletons now mirror the updated card layouts.
- Added a Filters pill and sheet to the Explore feed. Species groups,
  image/audio/video media, shared date, and Nearby distance can now be combined
  without thinning paginated pages on the device.
- Separated Explore post reports from identification flags. Reporting public
  content now enters its own moderation queue without marking the underlying
  species identification for review; existing misrouted reports are repaired,
  and repeat submissions preserve completed moderator decisions.
- Kept AI identification reasoning visible on public Explore post pages when a
  scan is reported; reasoning is hidden only when the identification itself is
  replaced by a user override.
- Added an optional **Boost audio** control to public web audio posts. It makes
  quiet recordings easier to hear with browser-local gain, rumble filtering,
  and peak limiting while leaving the published recording unchanged.
- Updated the public web discovery grid to show the species reference image for
  audio posts while retaining the spectrogram and playback controls on post
  detail pages.
- Simplified public Explore post details by removing like and comment counts
  and moving **Report this post** below the Taxonomy card.
- Reworked public Explore audio posts so the recording spectrogram fills the
  square media carousel and playback controls sit directly over its lower edge,
  with species reference images following as normal carousel slides.
- Added video playback to public Explore post pages. The active carousel video
  now receives the canonical public video URL, autoplays muted with native
  controls on a continuous loop, and shares the same square frame as every
  other carousel item; the public discovery grid remains poster-only for fast
  browsing.
- Kept audio presentation scoped correctly: feed and post detail always show a
  persisted or locally generated spectrogram, while compact Map, profile, and
  grid thumbnails continue to use the species reference photo.
- Added real spectrogram artwork for standalone-audio public web post pages and
  social previews. New WAV shares persist a deterministic thumbnail beside the
  recording, and a bounded repair worker can backfill older posts; unsupported
  legacy formats keep normal playback and the volume-icon fallback.
- Added image, video, and audio filters to the Explore map filter sheet. Media
  filters can be combined with species groups and remain accurate for clustered
  map results.
- Fixed the Explore map becoming unavailable when an audio-only or other
  media-only discovery had no hero image. Map points now use media posters or
  species reference thumbnails and isolate missing-thumbnail data safely. Map
  discovery cards now keep the Map-specific reference poster when an older feed
  copy of the same post is cached, retain audio/video typing, and show the shared
  compact bottom-right waveform or play badge.
- Fixed the Explore author profile's full published-scans view so it shows one
  back button instead of overlapping the stack and profile-library controls.
- Fixed missing Explore location labels on audio-only and other non-visual
  discoveries by resolving their capture location before scan persistence.
  Existing affected posts can be repaired from their saved coordinates without
  changing the author’s post-level location-sharing choice.
- Fixed standalone-audio thumbnails in profile and compact Explore grids so
  they keep the species reference photo after remote post data loads, with a
  bottom-right waveform badge identifying the recording; video posts retain
  the matching play badge.
- Added tactile feedback to user-controlled audio and video playback, mute,
  seeking, and audio-boost actions while keeping autoplay and restored settings
  silent.
- Added tap-to-seek and drag-to-scrub playback directly on audio spectrograms
  in Explore post detail. Feed cards remain playback-only so their navigation
  gestures stay predictable.
- Smoothed standalone-audio playheads in Explore feed and post detail. The line
  now follows audible playback at the display refresh rate, stays fixed while
  audio is paused, waiting, or seeking, and preserves the exact pause position.
- Added a compact **Boost audio** control directly to standalone-audio feed
  posts. It transitions to the existing **Boosted audio** treatment when ready,
  toggles back to original audio when tapped again, and does not open post
  detail from its protected tap area.
- Updated Explore sharing to lead with the discovery itself: image and video
  posts now say “Check out this {species},” while audio posts say “Listen to
  this {species},” followed by the public post link.

### Insights

- Fixed successful scans revealing carousel pagination and completion feedback
  before the identification title and result content. The saved core result now
  appears as one synchronized transition while optional reference enrichment
  continues progressively in the background.
- Replaced the still-image laser sweep with a fast native focus treatment. When
  Naturebook isolates a clear subject, the analyzing image now uses Lens-style
  corner brackets, a dimmed exterior, and the full-strength laser sweep contained
  inside the selected area. Broad or ambiguous scenes show no fallback box and
  retain the original full-image scan animation. The two scan treatments never
  appear together, and the full cropped image is still analyzed.
- Improved fullscreen video viewing with the same streamlined custom play/pause
  and mute controls used elsewhere, while keeping carousel dots in their
  standard gallery position. Fullscreen videos now begin playing immediately
  and inherit the Insight carousel's current sound setting. Video playback now
  loops while the video remains selected in both carousel sizes.
- Added a protected center play/pause tap area to Insight video carousels so
  playback taps no longer open the fullscreen media viewer.
- Paused Insight-sheet video playback before opening the fullscreen media
  carousel so sound cannot continue from the covered sheet underneath.
- Replaced native Insight-sheet video chrome with the streamlined Explore-style
  player, removing skip controls and the progress bar while preserving the
  center play/pause target and mute control.
- Fixed candidate review so **Reanalyze species** remains available for
  cloud-backed and multi-image scans and reliably opens the reanalysis flow
  after the nested review sheet closes.
- Added consistent playback, seeking, mute, and audio-boost haptics to Insight
  media while avoiding repeated feedback from timers or playhead updates.
- Added tap-to-seek and playmarker dragging to completed scan audio pages.
  Dragging the rest of an Insight media page continues to move between carousel
  items.
- Smoothed completed-scan audio playmarkers and hardened first playback after an
  audio-boost source change. Prepared sources now wait for an idle handoff,
  rendered files are fully reopened and decoded before publication, and an
  unexpected decode stop falls back to the original recording at the last
  confirmed position instead of leaving playback frozen.

### Account & Billing

- Fixed logout so signing out on one simulator or device clears only that local
  session instead of revoking the same account everywhere, and linked RevenueCat
  customers with Supabase/public identity attributes so Test Store support
  lookups can match Pro status back to Naturebook accounts.

### Scans

- Updated standalone-audio tiles in the Scans library to use the species
  reference photo with a waveform badge. Opening the scan still presents the
  recording spectrogram and playback controls. Reference-photo loading now uses
  the standard media skeleton instead of a technical pending-state message.
- Updated collection cover cards to use the species reference photo when their
  selected cover scan contains audio without visual media.

### Analytics

- Consolidated product analytics under PostHog so app events, session funnels,
  and backend events share one tracking system, with clearer client event names
  for scan completion, queueing, thermal throttling, errors, and species
  dictionary page loads.

### Startup

- Fixed startup recovery for devices carrying the accidental optional-queue V48
  SwiftData store by migrating them forward to V49, and added redacted
  copy/share diagnostics when TestFlight/debug builds enter safe mode.
- Fixed startup recovery for devices with V42/V43 SwiftData stores by routing
  them through source-isolated migration plans instead of the full historical
  chain that can trigger SwiftData's equal-model-reference validator.
- Updated V42 startup recovery to skip the older V42→V43 bridge and repair
  directly to V49 after TestFlight devices still fell back to safe mode.
- Added a legacy-store rescue path so known older SwiftData stores that still
  cannot migrate are archived safely and replaced with a fresh persistent
  library instead of reopening in safe mode on every launch.

### Species Dictionary

- Fixed **Community sightings** so its initial request always starts when a
  species page appears, instead of silently skipping the section before loading.
- Added **Community sightings** after observation charts. Species pages now
  preview six exact-species public Explore posts and can open a paginated grid,
  while respecting each viewer's Explore visibility and privacy rules.
- Added durable species dictionary enrichment queueing so new and existing
  sparse species records can backfill Wikipedia, GBIF, reference image,
  habitat, lookalike, and group-tag details through the scheduled workers.

### Capture

- Upgraded audio spectrograms with denser detail, smoother rendering, and a
  shared polished palette across recording, review, Insight playback, and scan
  thumbnails.
- Improved large-photo handling so gallery scans, reanalysis images, and profile
  avatar previews are bounded before staging, reducing memory pressure when very
  large local photos are selected.
- Added automatic audio submission when a recording reaches the full time limit
  and confirm-before-submit is turned off.
- Added video recording controls so Pro video scans show remaining time, can be
  canceled before staging, and open staged clips in a full-screen preview that
  can be dismissed with a downward swipe or removed before identifying.
- Added Pro short video scans from the visual shutter: tap still takes a photo,
  while a brief hold latches into a 5-second video recording with saved playback
  and image-based thumbnails.
- Enabled native iOS stabilization for Pro video recordings, while resetting
  the prepared movie output after stop, cancel, or failure so still-photo
  capture keeps its normal resolution and latency.
- Added clearer haptic feedback for video recording start, finish, successful
  staging, and recording failures.
- Fixed a crash that could happen after tapping stop on a Pro video recording
  while Naturebook extracted the clip's audio.
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
- Fixed video scan upload signing for production tables that still required a
  public media URL before staged uploads were promoted.
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
- Hardened identification so processed materials like wool rugs, leather goods,
  wooden furniture, paper, textiles, prepared food, toys, and artwork are kept
  out of the species dictionary even when made from biological material.
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
- Fixed video staging cleanup so canceled or failed captures discard temporary
  playback/audio files, and visual analysis only starts after the offline queue
  has durable ownership.

### Explore

- Fixed feed audio and video controls so the center Play/Pause region controls
  playback without opening the post; taps outside it still open detail, and
  double taps continue to like.
- Changed Explore video transitions so feed autoplay always resumes muted;
  opening a post still inherits the feed video's current mute choice, while
  returning from detail resets the feed to muted.
- Fixed normalized audio media refresh so scans with durable recordings always
  receive ready audio asset rows, including a production backfill for audio
  shared before the database refresh contract supported standalone audio.
- Added a device-local, per-post “Boost audio” option to standalone Explore
  audio feed and detail menus, with adaptive gain, gentle rumble reduction,
  clipping protection, synchronized settings, and position-preserving switching
  while the original recording remains unchanged; active boosted clips show a
  small “Boosted audio” badge on the spectrogram, and saved boost settings restore quietly
  without showing action-progress messaging.

### Insights

- Added direct **Boost audio** and elapsed/total timestamp badges to Insight
  audio spectrograms, positioned above the overlapping result card using the
  carousel attribution-tag treatment.
- Added device-local, per-scan “Boost audio” controls to completed scan-library
  Insights with standalone audio. Mixed-media scans apply one setting to every
  audio page, preserve playback position while switching, restore quietly, and
  leave the original recording unchanged.
- Added an allowlisted Field trips preview to Explore: regional checklist quests can auto-start from
  new scans, unlock levels sequentially, show active checklist progress on
  public profiles, and publish Field trip pages with species snapshots, likes,
  and comments without creating Explore feed posts or map points.
- Expanded Field trips with guided trip detail pages, explicit Start, curated
  item tips, a Field trips-only Community segment with For You, Following, and
  Recent filters, template Community previews, and up to 3 pinned published
  trips on profiles.
- Added Field trip Seasonal Challenges: curated, explicit-join, non-competitive
  challenge pages with schedule/counts, after-join-only progress, completion
  badges, challenge-specific published entries, and optional Explore hashtag
  suggestions without auto-posting or auto-tagging.
- Added in-app Field trip activity for comments, replies, and followed-author
  publications without sending APNs or creating Explore post rows, map points,
  or widgets. Typed Field trip cards can appear in unfiltered Explore Recent and
  Following.
- Added public video Explore posts: shared video scans can now appear in Explore
  and Ask the Community with muted playback in feed/detail and in-app thumbnail
  play indicators on compact surfaces.
- Removed the play badge from Explore Home Screen widgets so video posts appear
  as clean still thumbnails there.
- Fixed Explore videos so opening an author profile from feed, post detail, or
  comments now stays inside the Explore navigation stack instead of layering a
  profile sheet over the active video surface, with profile-to-scan navigation
  capped so users cannot build an endlessly nested stack.
- Fixed Explore video playback so shared video posts autoplay when opened, fill
  their square preview, and use a centered play/pause control that fades during
  playback instead of a static marker; muting or unmuting one Explore video now
  applies to the rest.
- Fixed video Explore sharing so composer-selected video clips publish, edit,
  and request Community ID from the server media source list, while failed media
  snapshots no longer leave the Share sheet showing a phantom Explore post.
- Improved video Explore sharing repair so scans with a surviving local `.mp4`
  can restore missing cloud video media before publishing.
- Hardened video media recovery so cloud scans keep ready-state image/video
  media records for future sharing and playback repairs.
- Fixed Explore video audio metadata so posts only mark video as audio-backed
  when the captured video manifest actually includes an audio companion.
- Added standalone audio to Explore sharing with waveform playback and a
  fail-closed publication check: speech is transcribed and moderated before the
  share succeeds, so rejected or failed checks create no public post.
- Added approved Explore audio to public web share pages with native,
  user-initiated playback and audio-safe social metadata. Audio-only posts remain
  excluded from Home Screen widgets.
- Fixed standalone-audio R2 cleanup so user scan deletion, the 30-day
  non-biological purge, and failed-ingestion rollback do not orphan recordings.
- Added public-audio health checks, privacy-safe moderation telemetry, web
  reporting, and CI contracts for moderation and lifecycle behavior.
- Consolidated public-audio moderation on Gemini 2.5 Flash with structured
  speech and non-speech classification, removing the separate OpenAI dependency.
- Hardened Gemini audio moderation against media prompt injection, preserved MP4
  typing for audible videos, and added transport plus ingestion-owner CI checks.
- Added privacy-safe, content-addressed audio moderation attestations so
  unchanged clips reuse decisions while changed media, models, or policy rules
  automatically require a fresh Gemini check.
- Added legacy audio repair during Explore sharing: surviving local recordings
  upload to staging, become durable scan media, and are moderated before the
  post can become public; missing local recordings remain unavailable.
- Repaired early production `scan_media_assets` constraints so staged and
  durable standalone audio rows are accepted during legacy sharing recovery.
- Replaced raw database constraint text during media-upload preparation with a
  concise retry message while preserving technical details in structured Edge
  logs.
- Added Explore post management actions to the Insight top menu so published
  scans can be edited or opened without returning to the Share sheet.
- Added a View insight action to your own Explore post menus, including posts
  opened from an Insight sheet or your Profile's published scans.
- Fixed notification-opened comment reply threads so parent comments and replies
  include the same emoji reaction controls as regular Explore comments.
- Hid reference images on shared human identifications so Explore pages show
  only the user's media.

### Scans

- Fixed newly empty scan libraries showing a blank screen instead of the first-scan
  empty state, including after switching from a previously signed-in account to a
  ghost session.
- Improved offline queue reliability so image, video, audio, and description
  scans keep retry state across app restarts, show retry/needs-attention status,
  and no longer discard user media after a fixed number of transient failures.
- Fixed queued scan retry from Insight sheets so Retry now gives visible
  feedback, refreshes the open scan state, and no longer duplicates the existing
  cancel control.
- Capped automatic offline retries with jittered backoff so repeated scan
  upload, analysis, cloud-deletion, or collection-sync failures pause for
  attention, and repeated server replay failures turn terminal, instead of
  retrying indefinitely.
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
  startup with short, recent-only migration plans before legacy rescue or safe
  mode.
- Improved launch migration selection so fresh and already-current local
  libraries open without validating the full historical migration plan, while
  recent older libraries use the smallest source-specific plan available.
- Fixed offline-queue schema upgrades so existing queued scans initialize their
  durable retry state instead of repeatedly reopening in safe mode.

### Profile

- Added an Edit profile picture action to the Profile identity menu so the avatar
  picker is available alongside name and username editing.
- Fixed repeat observations moving an achievement's original unlock date
  forward. Repeat scans still update the latest-interaction date, while
  retroactive-notification decisions remain tied to the scan that earned the
  achievement.
- Made profile names optional; clearing a custom name now restores the public
  username as the author label across Profile and Explore.
- Fixed V47 queued-media library upgrades so queued scans are snapshotted and
  recreated with durable retry metadata, avoiding a SwiftData startup crash
  during TestFlight upgrade checks.
- Added broader startup migration safety checks so queued image, video, audio,
  description, and mixed-media scans are tested together before release.
- Improved safe-mode diagnostics when a local library upgrade fails, keeping the
  store in place while reporting an upgrade-specific recovery reason.

### Insight Sheet

- Video scan media now starts muted playback when its Insight sheet opens,
  loops while analysis is running, and keeps a bottom-left sound status toggle.
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
  summary that can show the assessed region, confidence, and Naturebook's rationale
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
- Field chat now offers Review alternatives and Reanalyze species actions when
  follow-up wording suggests the current ID is wrong, uncertain, a different
  species, mismatched to visible traits, or worth checking again.

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
- Rebuilt Community identification around versioned Naturebook taxonomy, queued
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
  sharing Naturebook is ready for a future referral link.
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
  Explore post when Naturebook is installed.
- Updated Explore post sharing copy so shared links introduce the Naturebook public
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

- Collection thumbnails now fall back to another scan when the selected cover's
  visuals have been archived.
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
- Species dictionary galleries now admit more published Naturebook photos by
  lowering the Naturebook reference-image quality gate while keeping the species
  confidence gate in place.
- Explore Dictionary now uses already-granted location access to improve the
  Your Region category, while falling back to the device locale without showing
  a Dictionary-specific permission prompt.

### Community Taxonomy Indexing & Enrichment

- Added a GBIF-backed Community Taxonomy Index so Ask the Community search can
  suggest taxa that are not yet enriched in Naturebook's Dictionary, plus
  first-class species enrichment jobs and the first Birds coverage target for
  future Dictionary-completeness progress.
- Added an internal Community Taxonomy status endpoint so taxonomy coverage,
  GBIF import runs, and species enrichment queue health can be checked during
  rollout.
- Added a bounded GBIF Birds import worker so Naturebook can seed Community ID
  suggestions and future Dictionary coverage metrics without mirroring all of
  GBIF.
- Added safer Community Taxonomy import operations with database cursor
  tracking, lightweight coverage status checks, an operator script, and
  production deploy smoke checks.
- Added smarter dog and cat scan labels so pet results can show a likely breed,
  mix, coat pattern, or body type while keeping Naturebook's species taxonomy
  unchanged.

### Web Scaffolds & Legal Hub

- Added the initial Next.js + Mantine web app scaffold for public Explore share
  pages.
- Added public Terms, Privacy Policy, Community Guidelines, Privacy Choices,
  Support, and Legal hub pages for `naturebook.earth`.
- Added an iOS-to-web theme bridge so Naturebook-opened web pages can follow the
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
