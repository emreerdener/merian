# Merian

**Native AI-Powered Ecological Identification for iOS**

Merian is a field-ready biological identification app built around zero-friction capture and scientific-grade accuracy. Point the camera at any plant, animal, insect, fungus, or other organism, describe it in text, or capture a short sound clip and receive a structured identification in seconds — including taxonomy, ecology, conservation status, and diagnostic comparisons against lookalike species.

---

## Features

### Capture Workspace
- Instant-on `AVCaptureSession` with device priority: triple camera → LiDAR → dual → wide. Triple camera is preferred on Pro models to expose the full 0.5×–15× optical zoom range.
- LiDAR depth harvesting via `AVCaptureDepthDataOutput`, feeding absolute subject distance (up to ~5m) to the AI model to prevent scale hallucinations.
- Tap-to-focus, tap-to-expose, pinch zoom, vertical swipe zoom, and direct drag on the zoom meter.
- Native hardware button capture via `AVCaptureEventInteraction` (volume buttons, Action button, iPhone 16 Camera Control).
- Mixed-media staging mode — queue up to 2 total images, audio clips, or descriptions before submitting to inference.
- Audio Listen Mode records a 15-second WAV clip with live spectrogram and SNR feedback.
- Describe Mode supports typed observations and live voice dictation through `SpeechManager`.
- Real-time viewfinder intelligence hints (brightness, distance, motion blur) powered by on-device luma analysis at 3fps.
- Logarithmic zoom meter with optical stop indicators, haptic detents at each lens transition, and a tick-elongation animation around the active position.

### Identification
- Powered by **Google Gemini 2.5 Flash** (free tier) and **Gemini 2.5 Pro** (Pro tier), routed via Deno Edge Functions on Supabase. Private provider secrets never touch the client binary.
- Structured JSON output schema enforced server-side: common name, scientific name, full Linnaean taxonomy, ecology type, IUCN Red List status, invasiveness flag, confidence score, dominant colors, categorical group tags, and a lookalike diagnostic comparison.
- Concurrent on-device `VNClassifyImageRequest` drives the scanning overlay's status phrases while the network round-trip runs.
- Environmental telemetry attached to every inference call: GPS coordinates, elevation, LiDAR depth scale, weather condition and temperature, semantic location, zoom factor, time of day, month, and device locale.
- `/identify-multimodal` is the shared live and replay endpoint for visual, audio, describe, and mixed submissions; queued media uploads through R2 staging before inference.

### Scans Library
- Grid view of all personal captures, sorted by newest, oldest, or alphabetical.
- **Semantic search** across common name, scientific name, ecology type, AI-generated color tags, categorical group tags (e.g. "bird", "songbird"), and Latin taxonomy fields. Searching "bird" resolves via a taxonomy class → plain-English synonym mapping, so neither Latin knowledge nor exact species names are required.
- Category filter bar: All, Plants, Fungi, Insects, Birds, Mammals, Reptiles, Other.
- User-created collections (albums) with many-to-many scan relationships, synced to Supabase.
- Non-biological captures isolated in a dedicated view.
- Pending queued captures render above completed scans with state-aware upload/inference affordances.

### Insight Sheet
- Species header with common name, scientific name, and AI confidence spectrum (3-band visual scale).
- Full Linnaean taxonomy (kingdom → genus).
- Ecological description, Wikipedia extract, and in-app Safari link.
- Image carousel combining live captures, additional staged images, and GBIF/Wikipedia reference images.
- Scan Information Card: location name, elevation, zoom factor, weather, date, time, and a MapKit snapshot.
- Toxicity warning banner, IUCN conservation status, and species badges (invasive, ecology type).
- Diagnostic comparison: primary match rationale, confusing lookalike, and key visual differentiators.
- New species discovery celebration banner.
- Private field notes persist on `LocalScanRecord` / `OfflineQueuedScan` and can optionally be published to Explore posts.

### Explore
- Public feed, following feed, trending, nearby, and map views backed by Supabase RPCs and Edge Functions.
- Share/unshare scans to Explore with optional public hashtags, browse hashtag post collections, like posts, comment, react to comments, follow authors, and receive Explore notifications.
- Author profile sheets expose privacy-scoped public stats and non-opening public achievements.
- Home Screen widget caches image-only Explore snapshots through the shared App Group.
- Public Explore share pages render at `https://merian.earth/explore/post/{postId}` through the Next.js web app.

### Native Share Extensions
- Messages app extension surfaces a cached, searchable scan library inside iMessage and lets users insert a scan image, rich Merian card, or text description into the compose field.
- Photos share extension work is paused and de-shipped from current app builds. The `MerianShareExtension` target/source remain in the repo for a future rebuild, but the app does not embed the extension and no Photos share-sheet import surface is advertised.
- Shared App Group cache files keep shipped extensions lightweight while the main app owns SwiftData reconciliation. Some share-import App Group/keychain code remains parked with the de-shipped Photos extension.

### Profile & Gamification
- Running species count, current scan streak, and longest streak.
- 52-week rolling contribution heatmap (year and month viewports).
- 13 achievement awards across categories: observation milestones, taxonomy specializations, environmental conditions, conservation engagement, and capture technique. Awards surface with smart sort: recently unlocked → in-progress → legacy.

### Settings
**Camera** — zoom slider visibility, left-side placement, invert zoom direction, live viewfinder hints.
**Preferences** — theme (system/light/dark), multi-image scans, expedition mode, system haptics, save to camera roll.
**Geoprivacy** — open, obscured (~10km), or private; configurable per account and synced to Supabase.
**Notifications** — species discovery alerts, achievement milestone alerts.
**Changelog** — bundled feature notes, release notes, and selected in-progress work.
**Export** — Darwin Core Archive (DwC-A) formatted data export for academic/research use.
**Account** — Sign in with Apple or Google, anonymous Ghost Sessions, account deletion with full data wipe.

---

## Architecture

### Thermal & Memory Management
- `HardwareOrchestrator` monitors `ProcessInfo.thermalState` and `isLowPowerModeEnabled`, dynamically capping framerates (60fps → 24fps) and dropping glassmorphism shaders under thermal pressure.
- Expedition Mode allows users to force the 24fps/low-fidelity pipeline manually for off-grid battery conservation.
- `ViewfinderIntelligence` throttles frame analysis to 3fps via `NSLock` before any `@MainActor` context switch, preventing GPU thermal spikes from the luma evaluation loop.

### Offline-First Data Pipeline
- `OfflineQueuedScan` (SwiftData) persists captures with full telemetry when inference fails or connectivity is absent.
- `NWPathMonitor` triggers background `URLSession` retry on reconnection, respecting Swift 6 concurrency constraints and OS Watchdog limits.
- `HistoricalDatabaseActor` reconciles paginated cloud sync into SwiftData in a single pass, with push-before-pull ordering to prevent unsynced local collections from being treated as obsolete.

### Zero-OOM Design
- All heavy database work runs through `@ModelActor` isolation: `BackgroundDatabaseActor` (live saves), `HistoricalDatabaseActor` (cloud sync), `SearchDatabaseActor` (search index builds), `FileIOActor` (image I/O).
- 48MP ProRAW library imports route through `ImageIO` with explicit bounds, blocking RAM cache inflation that causes JetSam kills.
- Image pipeline produces a 1024px JPEG for inference and a 2048px JPEG for display in a single pass.
- Search index uses O(1) delta updates — only added/removed scans are reprocessed, never the full library.
- Edge media handlers use capped stream readers for request JSON and R2
  responses, so missing `Content-Length` and chunked bodies cannot allocate
  beyond the Deno isolate budget before rejection.

### Identity & Monetization
- Anonymous IDFV-backed Ghost Sessions (zero-friction, no sign-up required at launch).
- Sign in with Apple / Google OAuth merges Ghost identity via `linkIdentityWithIdToken` or the `/merge-ghost-profile` Edge RPC.
- RevenueCat webhook drives `free` ↔ `pro` tier migrations and triggers R2 storage moves between lifecycle buckets.
- Free tier: 2 scans/day. Pro: unlimited scans, Gemini 2.5 Pro model, offline queue.

### Archive Safety
- Cloudflare R2 free-tier objects expire after 90 days. `ArchiveManager` monitors scan age and downloads images to the local `Documents` directory in the 80–88 day window, storing only relative filenames (not full paths) to survive iOS container UUID randomization across reboots.

### Privacy
- Geoprivacy is enforced server-side: `obscured` rounds coordinates to ~10km; `private` strips location entirely. Endangered species coordinates are automatically offset by 50km regardless of user setting.
- DwC-A exports replace user IDs with SHA-256 pseudonyms via `crypto.subtle.digest`, preserving streak analytics without exposing Supabase tokens.

---

## Tech Stack

| Layer | Technology |
|---|---|
| iOS client | Swift 6, SwiftUI, SwiftData, AVFoundation, CoreLocation, Vision, MapKit |
| Web frontend | Next.js, React, Mantine |
| Animation | RiveRuntime |
| Backend | Supabase (PostgreSQL, Deno Edge Functions) |
| Cloud storage | Cloudflare R2 (S3-compatible) |
| AI model | Google Gemini 2.5 Flash / Pro |
| Payments | RevenueCat |
| Analytics | TelemetryDeck and PostHog |
| CI/CD | GitHub Actions |
| Email Services | Resend |

**Minimum deployment target**: iOS 17.2
**Current schema**: MerianSchemaV43

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
xcodegen generate
open Merian.xcodeproj
```

Set `MERIAN_DEVELOPMENT_TEAM` in `Signing.local.xcconfig` to your Apple Developer Team ID before opening the project. This file is ignored by git so your local signing choice survives `xcodegen generate`.

`Merian.xcodeproj` is committed for convenience, but `project.yml` remains the source of truth. Regenerate the project after target, package, build setting, entitlement, or source-group changes.

Configure the required app-facing client config in `Config.xcconfig`. Public client values like `SUPABASE_URL` and `SUPABASE_ANON_KEY` are used by the app at runtime; true backend secrets like `GEMINI_API_KEY` must stay server-side only.

### Common Shortcuts

From the repo root:

```bash
make xcodegen
make db-push
make functions-deploy
```

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

The initial web routes include `/explore/post/[postId]`, a server-rendered public Explore share page with Open Graph metadata for rich Messages/social previews, plus public policy/support pages at `/privacy`, `/terms`, `/guidelines`, `/privacy-choices`, `/support`, and `/legal`.

See `apps/web/README.md` and `docs/features-and-hardware/17-public-web-share-pages.md` for the web env contract, share URL strategy, and Universal Links roadmap.

For Vercel production, configure the project Root Directory as `apps/web` and
attach both `merian.earth` and `www.merian.earth` to that project. A plain Vercel
`404: NOT_FOUND` response means the request has not reached the Next.js app.

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

---

## Documentation

Extended architecture documentation lives in `docs/`:

| Directory | Contents |
|---|---|
| `docs/codebase-map.md` | Current target/module/function/schema map generated from this repo state |
| `docs/system-architecture/` | Data flow, concurrency model, zero-OOM patterns, AI engineering |
| `docs/features-and-hardware/` | Camera pipeline, hardware orchestration, feature module breakdowns |
| `docs/features-and-hardware/17-public-web-share-pages.md` | Public `merian.earth` share page contract and Universal Links roadmap |
| `docs/backend-and-data/` | Edge function contracts, database schema, offline sync, API contracts |
| `docs/development-guides/` | Core managers reference, app lifecycle, testing strategy |

---

## Legal

Merian is a tool for education, discovery, and conservation. Usage is subject to the terms of the Google Gemini API, Supabase, and Apple platform guidelines.
