# Merian App Documentation

This directory is the technical master reference for the native iOS application, Supabase PostgreSQL backend, Cloudflare R2 ephemeral networking, and hardware orchestration logic.

## Directory Structure

### System Architecture

- **[`/system-architecture/01-system-architecture.md`](./system-architecture/01-system-architecture.md)** — Master architecture: zero-OOM infrastructure strategy and lazy-loading UX principles.
- **[`/system-architecture/system-overview.md`](./system-architecture/system-overview.md)** — High-level structural decoupling overview.
- **[`/system-architecture/13-zero-oom-and-concurrency.md`](./system-architecture/13-zero-oom-and-concurrency.md)** — iOS memory ceiling rules, Swift 6 concurrency constraints, and Supabase Edge optimizations.
- **[`/system-architecture/14-image-pipeline.md`](./system-architecture/14-image-pipeline.md)** — Capture → disk → cache → display image flow.
- **[`/system-architecture/17-ai-engineering.md`](./system-architecture/17-ai-engineering.md)** — LLMOps edge deployment constraints, `maxOutputTokens` limits, and API throttling behaviors.

### Backend & Data

- **[`/backend-and-data/03-offline-sync-pipeline.md`](./backend-and-data/03-offline-sync-pipeline.md)** — Zero-data-loss architecture, SwiftData queues, and AppDelegate background URLSession mappings.
- **[`/backend-and-data/04-supabase-edge-and-database.md`](./backend-and-data/04-supabase-edge-and-database.md)** — Supabase Postgres schemas, Edge Function runtime rules, and RLS.
- **[`/backend-and-data/05-database-actors.md`](./backend-and-data/05-database-actors.md)** — SwiftData actor model: `BackgroundDatabaseActor`, `HistoricalDatabaseActor`, and `FileIOActor`.
- **[`/backend-and-data/07-database-schema.md`](./backend-and-data/07-database-schema.md)** — Physical table maps for PostgreSQL and the SwiftData persistent schemas.
- **[`/backend-and-data/08-api-contracts.md`](./backend-and-data/08-api-contracts.md)** — JSON mapping contracts between the iOS client and Deno Edge functions.

### Features & Hardware

- **[`/features-and-hardware/02-camera-and-hardware.md`](./features-and-hardware/02-camera-and-hardware.md)** — AVFoundation bindings, LiDAR depth logic, and ViewfinderIntelligence constraints.
- **[`/features-and-hardware/05-revenue-and-identity.md`](./features-and-hardware/05-revenue-and-identity.md)** — RevenueCat integration, Pro entitlements, and Ghost Session identity model.
- **[`/features-and-hardware/06-gamification-and-telemetry.md`](./features-and-hardware/06-gamification-and-telemetry.md)** — Achievement system, scan telemetry capture, and PostHog analytics.
- **[`/features-and-hardware/07-onboarding.md`](./features-and-hardware/07-onboarding.md)** — Six-step permission flow, onboarding state machine, and the `hasCompletedOnboarding` gate.
- **[`/features-and-hardware/08-insight-sheet.md`](./features-and-hardware/08-insight-sheet.md)** — InsightSheet view architecture, species data rendering, and graceful degradation states.
- **[`/features-and-hardware/09-profile-and-gamification.md`](./features-and-hardware/09-profile-and-gamification.md)** — Profile heatmap, collections, and gamification award calculations.
- **[`/features-and-hardware/11-feature-modules-and-ui.md`](./features-and-hardware/11-feature-modules-and-ui.md)** — SwiftUI architectural views and modular extraction blocks.
- **[`/features-and-hardware/12-geological-expansions.md`](./features-and-hardware/12-geological-expansions.md)** — Roadmap for extending inference to rocks, minerals, and fossils.

### Development Guides

- **[`/development-guides/01-zero-oom-onboarding.md`](./development-guides/01-zero-oom-onboarding.md)** — Banned APIs, approved patterns, and memory debugging guide for new contributors.
- **[`/development-guides/02-app-lifecycle.md`](./development-guides/02-app-lifecycle.md)** — `AppLifecycleManager` phase contracts and trigger ordering.
- **[`/development-guides/03-feature-architecture.md`](./development-guides/03-feature-architecture.md)** — Feature module structure and ViewModel conventions.
- **[`/development-guides/05-logging-and-debugging.md`](./development-guides/05-logging-and-debugging.md)** — `MerianLog` structured logging and Xcode debugging workflows.
- **[`/development-guides/06-keychain-and-secrets.md`](./development-guides/06-keychain-and-secrets.md)** — Storage decision matrix, API key rules, `KeychainManager`, and `DeviceIdentityManager`.
- **[`/development-guides/07-error-handling.md`](./development-guides/07-error-handling.md)** — `NetworkError` and `APIError` cases, offline fallback patterns, and UI error surface mapping.
- **[`/development-guides/09-ai-agent-guidelines.md`](./development-guides/09-ai-agent-guidelines.md)** — Architecture constraints and conventions for AI coding agents working on this codebase.
- **[`/development-guides/10-testing-strategy.md`](./development-guides/10-testing-strategy.md)** — Swift testing isolation using in-memory SwiftData and local context mocks.
- **[`/development-guides/core-managers.md`](./development-guides/core-managers.md)** — Deep dive into singleton instances across Merian (e.g. `HardwareOrchestrator`).

## About Merian

Merian is a native iOS and iPadOS application that identifies plants, animals, insects, fungi, and indoor ecology with scientific-grade accuracy in under 3 seconds. It uses dynamic routing between the Gemini 2.5 Flash and Pro APIs via Supabase Edge functions, with a full offline-first architecture backed by SwiftData and Cloudflare R2.
