# Naturebook

**Native AI-Powered Ecological Identification for iOS**

Naturebook is a field-ready biological identification app built around zero-friction capture and scientific-grade accuracy. Point the camera at any plant, animal, insect, fungus, or other organism, describe it in text, or capture a short sound clip and receive a structured identification in seconds — including taxonomy, ecology, conservation status, and diagnostic comparisons against lookalike species. Merian remains the repository, target, and module codename.

Public branding and compatibility are governed by the
[Naturebook public-brand contract](docs/system-architecture/08-public-brand-compatibility.md).
Production domain, AASA, email, backend, App Store, verification, and rollback
steps are tracked in the
[Naturebook rebrand rollout runbook](docs/development-guides/15-naturebook-rebrand-rollout.md).

---

## Features

### Capture Workspace
- User-orderable Scan, Record, and Describe pages. The first configured mode is
  selected during workspace initialization, so Audio-first and Description-first
  launches do not briefly open Camera or start camera hardware.
- Instant-on `AVCaptureSession` with device priority: triple camera → LiDAR → dual → wide. Triple camera is preferred on Pro models to expose the full 0.5×–15× optical zoom range.
- LiDAR depth harvesting via `AVCaptureDepthDataOutput`, feeding absolute subject distance (up to ~5m) to the AI model to prevent scale hallucinations.
- Tap-to-focus, tap-to-expose, pinch zoom, vertical swipe zoom, and direct drag on the zoom meter.
- Native hardware button capture via `AVCaptureEventInteraction` (volume buttons, Action button, iPhone 16 Camera Control).
- Mixed-media staging mode — queue up to 2 total photos, short Pro video clips, audio clips, or descriptions before submitting to inference.
- Share one photo from iOS Photos directly to Naturebook. The app opens through its
  image document association, preserves included EXIF date/location context,
  requires the normal gallery crop, and continues through the existing quota,
  confirmation, inference, and offline-queue flow without a Share Extension or
  broad Photo Library access.
- Pro video scans let users briefly hold the visual shutter for a short stabilized clip, with an active countdown, cancel control, staged playback review, and image-based thumbnail; Naturebook analyzes five ordered sampled frames plus accompanying audio when available, then stores an upload-bounded playback clip for library review and Explore sharing while keeping sampled frames out of the user-visible media carousel.
- Audio Listen Mode records a 15-second WAV clip with live spectrogram and SNR feedback.
- Describe Mode supports typed observations and live voice dictation through `SpeechManager`.
- Real-time viewfinder intelligence hints (brightness, distance, motion blur) powered by on-device luma analysis at 3fps.
- Logarithmic zoom meter with optical stop indicators, haptic detents at each lens transition, and a tick-elongation animation around the active position.

### Identification
- Powered by **Google Gemini 2.5 Flash** (free tier) and **Gemini 2.5 Pro** (Pro tier), routed via Deno Edge Functions on Supabase. Private provider secrets never touch the client binary.
- Every public provider attempt first obtains an idempotent database reservation that verifies durable entitlement, selects the allowed model, and applies UTC-day plus per-user/IP cost ceilings. Entitlement/database failures fail closed.
- Structured JSON output schema enforced server-side: common name, scientific name, full Linnaean taxonomy, ecology type, IUCN Red List status, location-aware invasiveness flag with region/rationale/confidence, confidence score, dominant colors, categorical group tags, and a lookalike diagnostic comparison.
- Dog and cat scans keep species-grade taxonomy (`Canis lupus familiaris` / `Felis catus`) while optionally carrying a separate pet label for confident breed, mix, coat-pattern, or body-type display.
- Concurrent on-device `VNClassifyImageRequest` drives the scanning overlay's status phrases while the network round-trip runs.
- Environmental telemetry captured for each scan: shutter-time GPS, date/time,
  LiDAR depth scale, zoom, and cached device context travel with live inference.
  For eligible live-camera still scans, elevation, WeatherKit, and semantic
  location join within a 150 ms grace period or are patched into the owner scan
  afterward.
- `/identify-multimodal` is the shared live and replay endpoint for visual, audio, describe, and mixed submissions; queued media uploads through R2 staging before inference.
- Live-camera still-image analysis becomes eligible to start as soon as the
  durable local queue accepts the scan. WeatherKit/reverse geocoding receive a 150 ms grace period,
  late context is patched without re-identifying, and the live request hands the
  uplink to background recovery after its body finishes sending. Parsed and
  persisted results render before awards, Field trips, or cache-miss enrichment.
  Gallery, audio-bearing, and video submissions retain their existing context
  and upload behavior in this first optimization pass, while receiving timing
  instrumentation.
  Free remains on `gemini-2.5-flash` and Pro remains on `gemini-2.5-pro`; prompts,
  schema, thinking budgets, image resolution, output limits, and the single
  Gemini call per scan are unchanged.

### Scans Library
- Grid view of all personal captures, sorted by newest, oldest, or alphabetical.
- **Semantic search** across common name, scientific name, confident pet labels, ecology type, AI-generated color tags, categorical group tags (e.g. "bird", "songbird"), and Latin taxonomy fields. Searching "bird" resolves via a taxonomy class → plain-English synonym mapping, so neither Latin knowledge nor exact species names are required.
- Category filter bar: All, Plants, Fungi, Insects, Birds, Mammals, Reptiles, Other.
- User-created collections (albums) with many-to-many scan relationships, synced to Supabase.
- Non-biological captures isolated in a dedicated view.
- Pending queued captures render above completed scans with state-aware upload/inference affordances.

### Insight Sheet
- Species header with common name, scientific name, and AI confidence spectrum (3-band visual scale). Confident dog/cat pet labels can headline the sheet while the scientific name remains visible as taxonomy context.
- Full Linnaean taxonomy (kingdom → genus).
- Ecological description, Wikipedia extract, and in-app Safari link.
- Mixed-media carousel combining live captures, persisted image/video/audio/description pages, and GBIF/Wikipedia reference images.
- Scan Information Card: location name, elevation, zoom factor, weather, date, time, and a MapKit snapshot.
- Toxicity warning banner, IUCN conservation status, and species badges (invasive, ecology type).
- Diagnostic comparison: primary match rationale, confusing lookalike, and key visual differentiators.
- Shared scan milestone queue for Field trip progress, achievement unlocks, and
  global **New to Naturebook** dictionary contributions.
- Private field notes persist on `LocalScanRecord` / `OfflineQueuedScan` and can optionally be published to Explore posts.
- Pro-only Field chat lets users ask saved follow-up questions from completed biological insights without resending raw images, with AI-generated quick prompts grounded in the saved scan context.

### Explore
- Public feed, following feed, trending, nearby, and map views backed by Supabase RPCs and Edge Functions.
- Explore post details expose the same floating Field chat entry point as
  Insights. Each Pro viewer gets a private per-post conversation visible only
  to them—not to other viewers—grounded in the public observation and Species
  Dictionary context. Authors can use it on their own published posts too.
- Share/unshare scans to Explore with optional public hashtags and a selectable
  common-name snapshot, browse hashtag post collections, like posts, comment,
  react to comments, follow authors, and receive Explore notifications.
- Field trips are released for every user. They add guided regional checklist
  quests beside Explore, with Outings, Goals/Tips detail, explicit start,
  curated tips, profile pins, following-weighted Community discovery, and a
  compact account-cached visual Scan target that opens the
  relevant field trip guide. The active level shows a circular progress ring;
  completed standard goals use the exact device-local scan thumbnail and open
  that Insight inside the same Explore sheet when the record is available.
  Saved biological Insights also keep a persistent **Field trips** card listing
  every outing or visible Event credited by that scan. Its rows show the
  experience name without a redundant level label and open the owning Goals
  overview in the current navigation stack, with Back returning to the Insight.
  Standard outings require explicit start and Events require join; a scan may
  advance several active experiences but credits at most one goal in each.
  Scan ingestion applies standard/Event progress and first-outing achievement
  state atomically, retains a private idempotency receipt for recovery after
  termination, and keeps the durable Capture goal hint until acknowledgement.
  Field trip database routines are service-role-only behind the authenticated
  Edge API; direct client roles cannot call ownership-bearing RPCs.
  Saved scans still show contextual progress toasts with a credited ring and
  tap-through navigation before any achievement or New to Naturebook
  notification from the same scan.
  Publication storage stays separate from Explore posts; typed Field trip cards
  can appear in unfiltered Recent and Following, but not in Explore maps or the
  other post-only surfaces. Events remain a client-gated preview for
  `erdener.emre@gmail.com` and simulator builds; the preview includes curated
  seasonal challenges, completion badges, published entries, and optional
  challenge hashtag suggestions. DEBUG startup logs
  `TODO(field-trip-events-release)` while this state remains; the public Events
  checklist is in
  [`25-field-trips.md`](docs/features-and-hardware/25-field-trips.md#rollout-state-and-events-release-checklist).
- Explore cards and public share text can show confident dog/cat pet labels without replacing the stored species common/scientific names used for dictionary links and statistics.
- Explore posts support image, short-video, and standalone-audio media snapshots.
- Compact Explore/profile grids render standalone-audio posts with the species
  reference photo and a waveform badge; full post media remains the playable
  spectrogram.
- Explore feed videos autoplay muted whenever the feed is entered or resumed;
  post detail inherits the feed's current choice, then returning to the feed
  resets playback to muted.
- Feed audio and video use a dedicated center Play/Pause hit zone, while taps
  elsewhere on the media continue opening post detail and double taps like.
- Standalone-audio playheads in Explore feed, Explore post detail, and completed
  scan Insights follow the audible player clock smoothly and hold their exact
  position while playback is paused, buffering, or being repositioned.
- Standalone Explore audio posts offer an optional device-local “Boost audio”
  listening mode from feed and detail menus, remembered independently per post
  without changing the original recording.
- Completed scan-library Insights with standalone audio offer the same local
  listening boost, remembered separately per private scan and applied to every
  audio clip in that scan without changing stored media.
- The Scans library represents standalone-audio scans with their species
  reference photo and a waveform badge, while opening the scan retains the
  spectrogram-first playback experience.
  Audio shares are fail-closed: the server evaluates speech and non-speech
  sounds before creating or reactivating the Explore post, so only an approved
  share becomes public. Content-addressed attestations safely avoid repeat
  Gemini calls when the bytes, model, and policy contract are unchanged. Feed
  and detail reuse the shared AVPlayer host for video/audio, while
  maps, widgets, and compact profile previews stay thumbnail-first.
- Legacy audio scans can be shared when their original local recording still
  exists: the app repairs durable R2/scan media first, then runs the same
  fail-closed publication gate. Deleted legacy recordings remain unrecoverable.
- Author profiles open inside the Explore navigation stack, expose
  privacy-scoped public stats, non-opening public achievements, and
  active/published Field trip previews, and cap profile-to-scan nesting after
  one profile hop. A non-self visible profile can be reported from its overflow
  menu with a bounded reason/detail form; reporting opens a grouped internal
  review case and does not block the user automatically.
- Home Screen widget caches thumbnail-first visual Explore snapshots through the
  shared App Group, renders video posts as clean still thumbnails, and excludes
  audio-only posts.
- Public Explore share pages render visual posts at
  `https://naturebook.earth/explore/post/{postId}` through the Next.js web app.
  Detail pages use a square ordered image/video/audio carousel: videos autoplay
  muted on a loop while selected, and WAV audio fills the frame with its
  persisted spectrogram plus user-initiated controls and optional browser-local
  Boost Audio. The public home grid uses species reference thumbnails for audio
  posts, while social metadata retains the spectrogram. Legacy non-WAV posts
  keep playback plus the speaker fallback. Audio-only posts remain excluded
  from Home Screen widgets.
- Loaded Species Dictionary pages share readable UUID-first links at
  `https://naturebook.earth/species/{speciesId}/{slug}`. The UUID stays
  authoritative, while UUID-only and stale-slug browser links permanently
  redirect to the current readable canonical URL. Installed apps open Explore's
  Dictionary stack; browser recipients get the server-rendered public reference
  page with attribution-approved imagery and no scan- or user-specific data.

### Native Share Extensions
- Messages app extension surfaces a cached, searchable scan library inside iMessage and lets users insert a scan image, rich Naturebook card, or text description into the compose field.
- Shared App Group cache files keep shipped extensions lightweight while the main app owns SwiftData and scan reconciliation.
- Photos-to-Naturebook import is not an extension: the `public.image` document
  association opens the containing app and copies one shared file into its
  private pending-import inbox.

### Profile & Gamification
- Running species count, current scan streak, and longest streak.
- 52-week rolling contribution heatmap (year and month viewports).
- 13 achievement awards across categories: observation milestones, taxonomy specializations, environmental conditions, conservation engagement, and capture technique. Awards surface with smart sort: recently unlocked → in-progress → legacy.

### Settings
**General preferences** — theme (system/light/dark), an optional fresh-launch Explore destination, Notifications, system haptics, and geoprivacy.
**Pro** — multi-capture scans and expedition mode.
**Workspace** — camera and audio preferences, **Reorder modes**, the on-by-default Camera field trip-goal overlay and selected-goal preference, and scan-submission confirmation. This setting does not disable server-side progress or the persistent Insight card.
**Geoprivacy** — open, obscured (~10km), or private; configurable per account and synced to Supabase.
**Notifications** — species discovery alerts, achievement milestone alerts.
**Changelog** — bundled feature notes, release notes, and selected in-progress work.
**Export** — Darwin Core Archive (DwC-A) formatted data export for academic/research use.
**Account** — Sign in with Apple or Google, anonymous Ghost Sessions, account deletion with full data wipe.

---

## Architecture

### Thermal & Memory Management
- `HardwareOrchestrator` monitors `ProcessInfo.thermalState` and `isLowPowerModeEnabled`, dynamically capping framerates (60fps → 24fps) and dropping glassmorphism shaders under thermal pressure.
- Expedition Mode allows users to force the 24fps/low-fidelity pipeline manually for off-grid battery conservation. This is separate from Explore Field trips.
- `ViewfinderIntelligence` throttles frame analysis to 3fps via `NSLock` before any `@MainActor` context switch, preventing GPU thermal spikes from the luma evaluation loop.

### Offline-First Data Pipeline
- `OfflineQueuedScan` (SwiftData) persists captures with full telemetry when inference fails or connectivity is absent.
- `NWPathMonitor` triggers background `URLSession` retry on reconnection, respecting Swift 6 concurrency constraints and OS Watchdog limits.
- `HistoricalDatabaseActor` reconciles paginated cloud sync into SwiftData in a single pass, with push-before-pull ordering to prevent unsynced local collections from being treated as obsolete.

### Zero-OOM Design
- All heavy database work runs through `@ModelActor` isolation: `BackgroundDatabaseActor` (live saves), `HistoricalDatabaseActor` (cloud sync), `SearchDatabaseActor` (search index builds), `FileIOActor` (image I/O).
- 48MP ProRAW library imports route through `ImageIO` with explicit bounds, blocking RAM cache inflation that causes JetSam kills.
- Local and remote thumbnail decoding uses a cancellation-aware four-permit
  pool plus an explicitly QoS-tagged ImageIO queue. Excess work suspends without
  blocking user-initiated threads, preventing priority-inversion hangs while
  preserving the decode concurrency ceiling.
- Image pipeline produces a 1024px JPEG for inference and a 2048px JPEG for display in a single pass.
- Search index uses O(1) delta updates — only added/removed scans are reprocessed, never the full library.
- Edge media handlers use capped stream readers for request JSON and R2
  responses, so missing `Content-Length` and chunked bodies cannot allocate
  beyond the Deno isolate budget before rejection.

### Identity & Monetization
- Anonymous IDFV-backed Ghost Sessions (zero-friction, no sign-up required at launch).
- Sign in with Apple / Google OAuth preserves the Ghost UUID through
  `linkIdentityWithIdToken`; existing-account conflicts use a provider-bound,
  one-use `/merge-ghost-profile` handoff, an atomic database merge, and durable
  Auth cleanup. Pending proofs survive restarts in a device-only Keychain queue
  for the 30-day recovery window.
- RevenueCat webhook drives `free` ↔ `pro` tier updates while leaving existing scan media in place.
- Free receives one primary scan per UTC day. Pro removes the ordinary product
  cap and receives Gemini 2.5 Pro, video scans, AI chat, multi-capture, Apple
  Watch logging, expedition mode, and offline queue; database fair-use ceilings
  still bound automated provider traffic. Every public AI route atomically
  resolves entitlement, selects its model, and reserves per-user/IP quota
  before provider dispatch. The iOS `UserDefaults` meter is advisory, and its
  debug-only bypass cannot change server capacity.
- Pro follow-up chat is served by a Supabase Edge Function using Gemini 2.5 Flash against stored scan evidence only; the same function also generates short, scan-specific prompt chips from private text context.

### Evidence Retention
- Biological scan media is durable regardless of subscription tier. Temporary staging, quarantine, and export objects still expire quickly, and non-biological scans are cleaned up after the retention window.

### Privacy
- Geoprivacy is enforced server-side: `obscured` rounds coordinates to ~10km; `private` strips location entirely. Endangered species coordinates are automatically offset by 50km regardless of user setting.
- DwC-A exports replace user IDs with SHA-256 pseudonyms via `crypto.subtle.digest`, preserving streak analytics without exposing Supabase tokens.

---

## Tech Stack

| Layer | Technology |
|---|---|
| iOS client | Swift 6, SwiftUI, SwiftData, AVFoundation, CoreLocation, Vision, MapKit |
| Web frontend | Next.js, React, Mantine |
| Backend | Supabase (PostgreSQL, Deno Edge Functions) |
| Cloud storage | Cloudflare R2 (S3-compatible) |
| AI model | Google Gemini 2.5 Flash / Pro |
| Payments | RevenueCat |
| Analytics | PostHog |
| CI/CD | GitHub Actions |
| Email Services | Resend |

**Minimum deployment target**: iOS 17.2
**Current schema**: MerianSchemaV45

---

## Getting Started

### Prerequisites
- macOS 14+
- Xcode 16+ for Swift 6-era concurrency checks
- `xcodegen` (`brew install xcodegen`)
- Supabase CLI

### Setup

```bash
git clone https://github.com/your-org/merian.git
cd merian
cp Signing.local.example.xcconfig Signing.local.xcconfig
cp Config.local.example.xcconfig Config.local.xcconfig
xcodegen generate
open Merian.xcodeproj
```

Set `MERIAN_DEVELOPMENT_TEAM` in `Signing.local.xcconfig` to your Apple Developer Team ID before opening the project. This file is ignored by git so your local signing choice survives `xcodegen generate`.

`Merian.xcodeproj` is committed for convenience, but `project.yml` remains the source of truth. Regenerate the project after target, package, build setting, entitlement, or source-group changes.

Configure the required app-facing client config in `Config.xcconfig` or ignored
local overrides in `Config.local.xcconfig`. Public client values like
`SUPABASE_URL` and `SUPABASE_ANON_KEY` are used by the app at runtime; true
backend secrets like `GEMINI_API_KEY` must stay server-side only. Release
archives can still use the development RevenueCat `test_` key, but TestFlight
or App Store exports should override `REVENUECAT_API_KEY` with the production
iOS SDK key that begins with `appl_`.

### Common Shortcuts

From the repo root:

```bash
make xcodegen
make prepare-ios-release VERSION=1.0.1
make db-push
make functions-deploy
```

Run release prep only when preparing a TestFlight archive. Normal local builds
should not change the app version or build number.
If you are ready to use production RevenueCat, pass the real production key as
`REVENUECAT_API_KEY=appl_...`; release prep writes that public client key into
ignored `Config.local.xcconfig` so the following archive/export uses it.
Placeholder values such as the literal `appl_...` are blocked.

### Release Notes & Changelog

User-facing release notes live in two places:

- `CHANGELOG.md` for TestFlight, App Store, QA, support, and human release planning.
- `apps/ios/Merian/Resources/Changelog/changelog.json` for the bundled in-app Settings changelog.

See `docs/development-guides/12-in-app-changelog.md` before adding in-app notes, images, or deployment summaries.

### Local Web

The public web surface lives in `apps/web/`.

```bash
cd apps/web
cp .env.example .env.local
npm install
npm run dev
```

The web routes include `/explore/post/[postId]`, a server-rendered public Explore
share page with Open Graph metadata; `/species/[speciesId]/[slug]`, the licensed
public Species Dictionary page, with `/species/[speciesId]` retained as a
permanent compatibility redirect; and the allowlisted
`/api/explore/audio` stream used only for browser-local Boost Audio processing,
plus public policy/support pages at `/privacy`, `/terms`, `/guidelines`,
`/privacy-choices`, `/support`, and `/legal`.

See `apps/web/README.md`,
`docs/features-and-hardware/17-public-web-share-pages.md`, and
`docs/development-guides/15-naturebook-rebrand-rollout.md` for the web env
contract, share URL strategy, Universal Links, production verification, and
rollout steps.

For Vercel production, configure the project Root Directory as `apps/web` and
attach `naturebook.earth`, `naturebook.app`, their `www` aliases, and the legacy
`merian.earth` aliases to that project. A plain Vercel
`404: NOT_FOUND` response means the request has not reached the Next.js app.

### Local Internal Admin

The private operations application lives in `apps/admin/` and is deployed as a
separate project at `admin.naturebook.earth`.

```bash
cd apps/admin
cp .env.example .env.local
npm ci
npm run dev
```

The admin app accepts only the public Supabase URL/key and requires an existing
Google Auth user, private admin membership, and verified TOTP AAL2. Never add a
service-role key or analytics token to this deployment. See
`apps/admin/README.md`,
`docs/backend-and-data/10-internal-admin.md`, and
`docs/backend-and-data/11-internal-admin-operations.md` for setup, role,
security, bootstrap, deployment, and recovery procedures.

### Local Backend

From the repo root, point the Supabase CLI at the backend service directory:

```bash
supabase --workdir services start
supabase --workdir services functions serve identify
```

### Database Migrations

```bash
supabase --workdir services db push
```

### Edge Function Deploys

```bash
supabase --workdir services functions deploy
```

That is the manual full-fleet command. Production deployment runs through the
path-filtered GitHub workflow, which validates frozen function-local dependency
graphs, requires exact name parity with `services/supabase/config.toml`, and
deploys only transitive runtime consumers in bounded batches. The fleet size is
derived rather than hard-coded. See the
[Supabase deployment runbook](docs/backend-and-data/06-supabase-deployment-runbook.md).

---

## Documentation

Extended architecture documentation lives in `docs/`:

| Directory | Contents |
|---|---|
| `docs/codebase-map.md` | Current target/module/function/schema map generated from this repo state |
| `docs/system-architecture/` | Data flow, concurrency model, zero-OOM patterns, AI engineering |
| `docs/features-and-hardware/` | Camera pipeline, hardware orchestration, feature module breakdowns |
| `docs/features-and-hardware/17-public-web-share-pages.md` | Public Explore/species share-page contracts, media/privacy rules, and Universal Links compatibility |
| `docs/backend-and-data/` | Edge function contracts, database schema, offline sync, API contracts |
| `docs/backend-and-data/10-internal-admin.md` | Internal admin architecture, security boundary, roles, metrics, moderation, and AI ledger |
| `docs/backend-and-data/11-internal-admin-operations.md` | Internal admin setup, deployment, access recovery, pricing, and incident runbook |
| `docs/development-guides/` | Core managers reference, app lifecycle, testing strategy |
| `docs/rfcs/active-capture-goal-context.md` | Long-term source-agnostic Capture goal architecture and extension contract |

---

## Legal

Naturebook is a tool for education, discovery, and conservation. Usage is subject to the terms of the Google Gemini API, Supabase, and Apple platform guidelines.
