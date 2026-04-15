# Merian App Documentation

This directory is the technical master reference for the native iOS application, Supabase PostgreSQL backend, Cloudflare R2 ephemeral networking, and hardware orchestration logic.

## Directory Structure

### System Architecture

- **[`/system-architecture/01-system-architecture.md`](./system-architecture/01-system-architecture.md)** — Master architecture: zero-OOM infrastructure strategy and lazy-loading UX principles.
- **[`/system-architecture/system-overview.md`](./system-architecture/system-overview.md)** — High-level structural decoupling overview.
- **[`/system-architecture/02-zero-oom-and-concurrency.md`](./system-architecture/02-zero-oom-and-concurrency.md)** — iOS memory ceiling rules, Swift 6 concurrency constraints, and Supabase Edge optimizations.
- **[`/system-architecture/03-image-pipeline.md`](./system-architecture/03-image-pipeline.md)** — Capture → disk → cache → display image flow.
- **[`/system-architecture/04-ai-engineering.md`](./system-architecture/04-ai-engineering.md)** — LLMOps edge deployment constraints, `maxOutputTokens` limits, and API throttling behaviors.
- **[`/system-architecture/06-edge-modularization.md`](./system-architecture/06-edge-modularization.md)** — Domain-driven modular architecture for Supabase Edge Functions: `index.ts` / `db.ts` / `types.ts` separation rules and shared utility conventions.

### Backend & Data

- **[`/backend-and-data/01-offline-sync-pipeline.md`](./backend-and-data/01-offline-sync-pipeline.md)** — Zero-data-loss architecture, SwiftData queues, and AppDelegate background URLSession mappings.
- **[`/backend-and-data/02-supabase-edge-and-database.md`](./backend-and-data/02-supabase-edge-and-database.md)** — Supabase Postgres schemas, Edge Function runtime rules, and RLS.
- **[`/backend-and-data/03-database-actors.md`](./backend-and-data/03-database-actors.md)** — SwiftData actor model: `BackgroundDatabaseActor`, `HistoricalDatabaseActor`, and `FileIOActor`.
- **[`/backend-and-data/04-database-schema.md`](./backend-and-data/04-database-schema.md)** — Physical table maps for PostgreSQL and the SwiftData persistent schemas.
- **[`/backend-and-data/05-api-contracts.md`](./backend-and-data/05-api-contracts.md)** — JSON mapping contracts between the iOS client and Deno Edge functions.

### Features & Hardware

- **[`/features-and-hardware/01-camera-and-hardware.md`](./features-and-hardware/01-camera-and-hardware.md)** — AVFoundation bindings, LiDAR depth logic, and ViewfinderIntelligence constraints.
- **[`/features-and-hardware/02-revenue-and-identity.md`](./features-and-hardware/02-revenue-and-identity.md)** — RevenueCat integration, Pro entitlements, and Ghost Session identity model.
- **[`/features-and-hardware/03-gamification-and-telemetry.md`](./features-and-hardware/03-gamification-and-telemetry.md)** — Achievement system, scan telemetry capture, and PostHog analytics.
- **[`/features-and-hardware/04-onboarding.md`](./features-and-hardware/04-onboarding.md)** — Six-step permission flow, onboarding state machine, and the `hasCompletedOnboarding` gate.
- **[`/features-and-hardware/05-insight-sheet.md`](./features-and-hardware/05-insight-sheet.md)** — InsightSheet view architecture, species data rendering, and graceful degradation states.
- **[`/features-and-hardware/06-profile-and-gamification.md`](./features-and-hardware/06-profile-and-gamification.md)** — Profile heatmap, collections, and gamification award calculations.
- **[`/features-and-hardware/07-feature-modules-and-ui.md`](./features-and-hardware/07-feature-modules-and-ui.md)** — SwiftUI architectural views and modular extraction blocks.
- **[`/features-and-hardware/08-app-intents.md`](./features-and-hardware/08-app-intents.md)** — App Intents integration for Siri and Shortcuts.
- **[`/features-and-hardware/09-components-guide.md`](./features-and-hardware/09-components-guide.md)** — Shared UI components and design system primitives.
- **[`/features-and-hardware/10-watchos-integration.md`](./features-and-hardware/10-watchos-integration.md)** — watchOS companion target: acoustic capture pipeline, WatchConnectivity delivery, and iOS receiver status.
- **[`/features-and-hardware/11-describe-and-voice-dictation.md`](./features-and-hardware/11-describe-and-voice-dictation.md)** — Describe capture mode: `ObservationContext` state ownership, `SpeechManager` AVAudioEngine + SFSpeechRecognizer pipeline, dictation task lifecycle, and Swift 6 concurrency guarantees.
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
- **[`/development-guides/11-swiftdata-and-api-gotchas.md`](./development-guides/11-swiftdata-and-api-gotchas.md)** — SwiftData background synchronization drops and API envelope parsing constraints.

## About Merian

Merian is a native iOS and iPadOS application that identifies plants, animals, insects, fungi, and indoor ecology with scientific-grade accuracy in under 3 seconds. It uses dynamic routing between the Gemini 2.5 Flash and Pro APIs via Supabase Edge functions, with a full offline-first architecture backed by SwiftData and Cloudflare R2.
