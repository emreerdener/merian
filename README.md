# Merian

**Native AI-Powered Ecological Identification for iOS**

Merian is a field-ready biological identification app built around zero-friction capture and scientific-grade accuracy. Point the camera at any plant, animal, insect, fungus, or other organism and receive a structured identification in seconds — including taxonomy, ecology, conservation status, and diagnostic comparisons against lookalike species.

---

## Features

### Camera
- Instant-on `AVCaptureSession` with device priority: triple camera → LiDAR → dual → wide. Triple camera is preferred on Pro models to expose the full 0.5×–15× optical zoom range.
- LiDAR depth harvesting via `AVCaptureDepthDataOutput`, feeding absolute subject distance (up to ~5m) to the AI model to prevent scale hallucinations.
- Tap-to-focus, tap-to-expose, pinch zoom, vertical swipe zoom, and direct drag on the zoom meter.
- Native hardware button capture via `AVCaptureEventInteraction` (volume buttons, Action button, iPhone 16 Camera Control).
- Multi-image staging mode — queue up to 2 images before submitting to inference.
- Real-time viewfinder intelligence hints (brightness, distance, motion blur) powered by on-device luma analysis at 3fps.
- Logarithmic zoom meter with optical stop indicators, haptic detents at each lens transition, and a tick-elongation animation around the active position.

### Identification
- Powered by **Google Gemini 2.5 Flash** (free tier) and **Gemini 2.5 Pro** (Pro tier), routed via Deno Edge Functions on Supabase. API keys never touch the client binary.
- Structured JSON output schema enforced server-side: common name, scientific name, full Linnaean taxonomy, ecology type, IUCN Red List status, invasiveness flag, confidence score, dominant colors, categorical group tags, and a lookalike diagnostic comparison.
- Concurrent on-device `VNClassifyImageRequest` drives the scanning overlay's status phrases while the network round-trip runs.
- Environmental telemetry attached to every inference call: GPS coordinates, elevation, LiDAR depth scale, weather condition and temperature, semantic location, zoom factor, time of day, month, and device locale.

### Scans Library
- Grid view of all personal captures, sorted by newest, oldest, or alphabetical.
- **Semantic search** across common name, scientific name, ecology type, AI-generated color tags, categorical group tags (e.g. "bird", "songbird"), and Latin taxonomy fields. Searching "bird" resolves via a taxonomy class → plain-English synonym mapping, so neither Latin knowledge nor exact species names are required.
- Category filter bar: All, Plants, Fungi, Insects, Birds, Mammals, Reptiles, Other.
- User-created collections (albums) with many-to-many scan relationships, synced to Supabase.
- Non-biological captures isolated in a dedicated view.

### Insight Sheet
- Species header with common name, scientific name, and AI confidence spectrum (3-band visual scale).
- Full Linnaean taxonomy (kingdom → genus).
- Ecological description, Wikipedia extract, and in-app Safari link.
- Image carousel combining live captures, additional staged images, and GBIF/Wikipedia reference images.
- Scan Information Card: location name, elevation, zoom factor, weather, date, time, and a MapKit snapshot.
- Toxicity warning banner, IUCN conservation status, and species badges (invasive, ecology type).
- Diagnostic comparison: primary match rationale, confusing lookalike, and key visual differentiators.
- New species discovery celebration banner.

### Profile & Gamification
- Running species count, current scan streak, and longest streak.
- 52-week rolling contribution heatmap (year and month viewports).
- 13 achievement awards across categories: observation milestones, taxonomy specializations, environmental conditions, conservation engagement, and capture technique. Awards surface with smart sort: recently unlocked → in-progress → legacy.

### Settings
**Camera** — zoom slider visibility, left-side placement, invert zoom direction, live viewfinder hints.
**Preferences** — theme (system/light/dark), multi-image scans, expedition mode, system haptics, save to camera roll.
**Geoprivacy** — open, obscured (~10km), or private; configurable per account and synced to Supabase.
**Notifications** — species discovery alerts, achievement milestone alerts.
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
| Animation | RiveRuntime |
| Backend | Supabase (PostgreSQL, Deno Edge Functions) |
| Cloud storage | Cloudflare R2 (S3-compatible) |
| AI model | Google Gemini 2.5 Flash / Pro |
| Payments | RevenueCat |
| CI/CD | GitHub Actions |

**Minimum deployment target**: iOS 17
**Current schema**: MerianSchemaV13

---

## Getting Started

### Prerequisites
- macOS 14+
- Xcode 15+
- `xcodegen` (`brew install xcodegen`)
- Supabase CLI

### Setup

```bash
git clone https://github.com/your-org/merian.git
cd merian
xcodegen generate
open Merian.xcodeproj
```

Configure the required API keys in your `.xcconfig` files (Supabase URL, anon key, Gemini API key). These are never bundled into the binary directly.

### Local Backend

```bash
supabase start
supabase functions serve identify
```

### Database Migrations

```bash
supabase db push
```

---

## Documentation

Extended architecture documentation lives in `docs/`:

| Directory | Contents |
|---|---|
| `docs/system-architecture/` | Data flow, concurrency model, zero-OOM patterns, AI engineering |
| `docs/features-and-hardware/` | Camera pipeline, hardware orchestration, feature module breakdowns |
| `docs/backend-and-data/` | Edge function contracts, database schema, offline sync, API contracts |
| `docs/development-guides/` | Core managers reference, app lifecycle, testing strategy |

---

## Legal

Merian is a tool for education, discovery, and conservation. Usage is subject to the terms of the Google Gemini API, Supabase, and Apple platform guidelines.
