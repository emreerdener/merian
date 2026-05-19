# Merian Documentation

This directory is the technical master reference for the native iOS application, public web frontend, Supabase PostgreSQL backend, Cloudflare R2 ephemeral networking, and hardware orchestration logic.

## Current Snapshot

- **App targets**: iOS app (`apps/ios/Merian/`), watchOS companion (`apps/watch/MerianWatch/`), Explore WidgetKit extension (`apps/ios/widgets/Explore/`), Messages extension (`apps/ios/messages/MerianMessagesExtension/`), paused Photos share extension source (`apps/ios/share/MerianShareExtension/`, not embedded in current app builds), unit tests, and UI tests.
- **Web frontend**: Next.js + Mantine app in `apps/web/`, initially serving public Explore share pages on `merian.earth`.
- **Deployment target**: iOS 17.2 for the app and widget; watchOS 10.0 for the companion target.
- **Project source of truth**: `project.yml` via XcodeGen. `Merian.xcodeproj` is committed for convenience and should be regenerated after project-structure changes.
- **Active SwiftData schema**: `MerianSchemaV43` via `typealias CurrentSchema = MerianSchemaV43` in `apps/ios/Merian/Models/Aliases.swift`.
- **Primary inference endpoint**: `/identify-multimodal` for visual, audio, describe, and mixed-media submissions. `/identify` remains documented for legacy/image-specific compatibility and shared backend primitives.

## Directory Structure

### Current Codebase Map

- **[`/codebase-map.md`](./codebase-map.md)** — Current target, folder, schema, SwiftData actor, feature, Edge Function, and testing inventory for this repo state.

### System Architecture

- **[`/system-architecture/01-system-architecture.md`](./system-architecture/01-system-architecture.md)** — Master architecture: zero-OOM infrastructure strategy and lazy-loading UX principles.
- **[`/system-architecture/system-overview.md`](./system-architecture/system-overview.md)** — High-level structural decoupling overview.
- **[`/system-architecture/02-zero-oom-and-concurrency.md`](./system-architecture/02-zero-oom-and-concurrency.md)** — iOS memory ceiling rules, Swift 6 concurrency constraints, and Supabase Edge optimizations.
- **[`/system-architecture/03-image-pipeline.md`](./system-architecture/03-image-pipeline.md)** — Capture → disk → cache → display image flow.
- **[`/system-architecture/04-ai-engineering.md`](./system-architecture/04-ai-engineering.md)** — LLMOps edge deployment constraints, `maxOutputTokens` limits, and API throttling behaviors.
- **[`/system-architecture/06-edge-modularization.md`](./system-architecture/06-edge-modularization.md)** — Domain-driven modular architecture for Supabase Edge Functions: `index.ts` / `db.ts` / `types.ts` separation rules and shared utility conventions.

### Backend & Data

- **[`/backend-and-data/01-offline-sync-pipeline.md`](./backend-and-data/01-offline-sync-pipeline.md)** — Zero-data-loss architecture, SwiftData queues, and AppDelegate background URLSession mappings.
- **[`/backend-and-data/02-supabase-edge-and-database.md`](./backend-and-data/02-supabase-edge-and-database.md)** — Supabase Postgres schemas, Edge Function runtime rules, RLS, public species dictionary workers, and cron/webhook boundaries.
- **[`/backend-and-data/03-database-actors.md`](./backend-and-data/03-database-actors.md)** — SwiftData actor model: `BackgroundDatabaseActor`, `HistoricalDatabaseActor`, and `FileIOActor`.
- **[`/backend-and-data/04-database-schema.md`](./backend-and-data/04-database-schema.md)** — Physical table maps for PostgreSQL and the SwiftData persistent schemas, including the V41 `CapturedMediaEntry` mixed-media model, V42 field-notes columns, and V43 sex observation metadata.
- **[`/backend-and-data/05-api-contracts.md`](./backend-and-data/05-api-contracts.md)** — JSON mapping contracts between the iOS client and Deno Edge functions, including `/identify-multimodal`, parked `/share-import-scan`, `/species-dictionary`, `/species-observation-stats`, Explore detail similar species, and internal cron workers such as Merian reference-image refresh.

### Features & Hardware

- **[`/features-and-hardware/01-camera-and-hardware.md`](./features-and-hardware/01-camera-and-hardware.md)** — AVFoundation bindings, LiDAR depth logic, and ViewfinderIntelligence constraints.
- **[`/features-and-hardware/02-revenue-and-identity.md`](./features-and-hardware/02-revenue-and-identity.md)** — RevenueCat integration, Pro entitlements, and Ghost Session identity model.
- **[`/features-and-hardware/03-gamification-and-telemetry.md`](./features-and-hardware/03-gamification-and-telemetry.md)** — Achievement system, scan telemetry capture, and PostHog analytics.
- **[`/features-and-hardware/04-onboarding.md`](./features-and-hardware/04-onboarding.md)** — Six-step permission flow, onboarding state machine, and the `hasCompletedOnboarding` gate.
- **[`/features-and-hardware/05-insight-sheet.md`](./features-and-hardware/05-insight-sheet.md)** — InsightSheet view architecture, mixed-media carousel handoff, species data rendering, and graceful degradation states.
- **[`/features-and-hardware/06-profile-and-gamification.md`](./features-and-hardware/06-profile-and-gamification.md)** — Profile heatmap, collections, and gamification award calculations.
- **[`/features-and-hardware/07-feature-modules-and-ui.md`](./features-and-hardware/07-feature-modules-and-ui.md)** — SwiftUI architectural views and modular extraction blocks.
- **[`/features-and-hardware/08-app-intents.md`](./features-and-hardware/08-app-intents.md)** — App Intents integration for Siri and Shortcuts.
- **[`/features-and-hardware/09-components-guide.md`](./features-and-hardware/09-components-guide.md)** — Shared UI components and design system primitives.
- **[`/features-and-hardware/10-watchos-integration.md`](./features-and-hardware/10-watchos-integration.md)** — watchOS companion target: acoustic capture pipeline, WatchConnectivity delivery, and iOS receiver status.
- **[`/features-and-hardware/11-describe-and-voice-dictation.md`](./features-and-hardware/11-describe-and-voice-dictation.md)** — Describe capture mode: `ObservationContext` state ownership, `SpeechManager` AVAudioEngine + SFSpeechRecognizer pipeline, dictation task lifecycle, and Swift 6 concurrency guarantees.
- **[`/features-and-hardware/12-audio-listen-mode.md`](./features-and-hardware/12-audio-listen-mode.md)** — Audio Listen Mode: `SpectrogramActor` FFT/mel-scale DSP, `AudioCaptureManager` 15-second recording pipeline, live `SpectrogramView` Canvas UI, SNR gauge, and the shared non-visual durability path.
- **[`/features-and-hardware/13-explore-home-screen-widget.md`](./features-and-hardware/13-explore-home-screen-widget.md)** — Explore Home Screen widget: image-only WidgetKit extension, App Group cache contract, timeline carousel behavior, and deep-link routing.
- **[`/features-and-hardware/14-explore-author-profiles.md`](./features-and-hardware/14-explore-author-profiles.md)** — Public Explore author profile sheets, privacy-scoped profile stats, non-opening public achievements, and the paginated published-scan library.
- **[`/features-and-hardware/15-explore-following.md`](./features-and-hardware/15-explore-following.md)** — Explore Follow relationships: Following feed filter, public profile counts, follow notifications, block cleanup, and ghost-merge repair.
- **[`/features-and-hardware/16-species-dictionary.md`](./features-and-hardware/16-species-dictionary.md)** — Standalone public species dictionary page, `species-dictionary` Edge Function contract, similar-species entry points from Insight and Explore detail, public cache rules, content quality, media attribution, and refresh provenance.
- **[`/features-and-hardware/17-public-web-share-pages.md`](./features-and-hardware/17-public-web-share-pages.md)** — Next.js public web share pages for `merian.earth`, including Explore post links, Supabase server reads, metadata, privacy boundaries, and the Universal Links roadmap.
- **[`/features-and-hardware/18-species-observation-charts.md`](./features-and-hardware/18-species-observation-charts.md)** — Reusable species observation charts, local-on-device aggregation, public iNaturalist stats cache, annotation mappings, privacy boundaries, and verification.
- **[`/features-and-hardware/19-native-share-extensions.md`](./features-and-hardware/19-native-share-extensions.md)** — Native iOS share extensions: shipped Messages scan library, paused Photos share-sheet import status, App Group cache/receipt contracts, shared keychain auth notes, backend queueing, privacy rules, and QA.
- **[`/rfcs/explore-page.md`](./rfcs/explore-page.md)** — Explore feed and map product/RPC architecture, including the shipped V1 map implementation and follow-up recommendations.
- **[`/rfcs/codebase-cleanup.md`](./rfcs/codebase-cleanup.md)** — Phased cleanup plan for repo hygiene, behavior-preserving file splits, and ownership cleanup.
- **[`/rfcs/species-dictionary-long-term-todo.md`](./rfcs/species-dictionary-long-term-todo.md)** — Long-term species dictionary TODO covering canonical identity, reference media normalization, public projections, provenance and refresh, caching, licensing, and analytics.
- **[`/rfcs/geological-expansions.md`](./rfcs/geological-expansions.md)** — Roadmap for extending inference to rocks, minerals, and fossils.

### Development Guides

- **[`/development-guides/01-zero-oom-onboarding.md`](./development-guides/01-zero-oom-onboarding.md)** — Banned APIs, approved patterns, and memory debugging guide for new contributors.
- **[`/development-guides/02-app-lifecycle.md`](./development-guides/02-app-lifecycle.md)** — `AppLifecycleManager` phase contracts and trigger ordering.
- **[`/development-guides/03-feature-architecture.md`](./development-guides/03-feature-architecture.md)** — Feature module structure and ViewModel conventions.
- **[`/development-guides/04-logging-and-debugging.md`](./development-guides/04-logging-and-debugging.md)** — `MerianLog` structured logging and Xcode debugging workflows.
- **[`/development-guides/05-keychain-and-secrets.md`](./development-guides/05-keychain-and-secrets.md)** — Storage decision matrix, API key rules, `KeychainManager`, and `DeviceIdentityManager`.
- **[`/development-guides/06-error-handling.md`](./development-guides/06-error-handling.md)** — `NetworkError` and `APIError` cases, offline fallback patterns, and UI error surface mapping.
- **[`/development-guides/07-ai-agent-guidelines.md`](./development-guides/07-ai-agent-guidelines.md)** — Architecture constraints and conventions for AI coding agents working on this codebase.
- **[`/development-guides/08-testing-strategy.md`](./development-guides/08-testing-strategy.md)** — Swift testing isolation using in-memory SwiftData and local context mocks.
- **[`/development-guides/09-core-managers.md`](./development-guides/09-core-managers.md)** — Deep dive into singleton instances across Merian (e.g. `HardwareOrchestrator`).
- **[`/development-guides/10-safety-and-moderation.md`](./development-guides/10-safety-and-moderation.md)** — Gemini safety rating evaluation, abuse strike system, shadowban logic, and R2 media promotion pipeline.
- **[`/development-guides/11-swiftdata-and-api-gotchas.md`](./development-guides/11-swiftdata-and-api-gotchas.md)** — SwiftData background synchronization drops, relationship fault boundaries, and API envelope parsing constraints.

## About Merian

Merian is a native iOS application that identifies plants, animals, insects, fungi, and indoor ecology with scientific-grade accuracy across visual, audio, and text-described observations. It uses dynamic routing between the Gemini 2.5 Flash and Pro APIs via Supabase Edge Functions, with a full offline-first architecture backed by SwiftData and Cloudflare R2.
