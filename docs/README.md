# Merian App Documentation

Welcome to the Merian ecosystem documentation. This directory serves as the technical master reference for the native iOS application, Supabase PostgreSQL backend, Cloudflare R2 ephemeral networking, and hardware orchestration logic.

## Directory Structure

### Core Systems

- **[`/system-architecture/01-system-architecture.md`](./system-architecture/01-system-architecture.md)** - Master philosophies, zero-OOM infrastructure strategy, and lazy-loading UX principles.
- **[`/features-and-hardware/02-camera-and-hardware.md`](./features-and-hardware/02-camera-and-hardware.md)** - Native AVFoundation bindings, LiDAR depth logic, and ViewfinderIntelligence constraints.
- **[`/backend-and-data/03-offline-sync-pipeline.md`](./backend-and-data/03-offline-sync-pipeline.md)** - Zero-data-loss architecture, SwiftData queues, and AppDelegate background URLSession mappings.
- **[`/backend-and-data/04-supabase-edge-and-database.md`](./backend-and-data/04-supabase-edge-and-database.md)** - Supabase Postgres schemas, Edge Function runtime rules, and RLS bypasses.
- **[`/backend-and-data/07-database-schema.md`](./backend-and-data/07-database-schema.md)** - The physical table maps for PostgreSQL and the SwiftData persistent schemas.
- **[`/backend-and-data/08-api-contracts.md`](./backend-and-data/08-api-contracts.md)** - Raw JSON mapping contracts bridging the iOS client and Edge Deno engines.
- **[`/development-guides/09-ai-agent-guidelines.md`](./development-guides/09-ai-agent-guidelines.md)** - Master rules, architecture constraints, and explicit prompt boundaries for AI dev agents.
- **[`/development-guides/10-testing-strategy.md`](./development-guides/10-testing-strategy.md)** - Swift testing isolation via in-memory SwiftData constraints and local context mocks offline.
- **[`/features-and-hardware/11-feature-modules-and-ui.md`](./features-and-hardware/11-feature-modules-and-ui.md)** - SwiftUI architectural views mapping modular extraction blocks (ScanGridMatrix, BaseOnboardingStepView).
- **[`/system-architecture/13-zero-oom-and-concurrency.md`](./system-architecture/13-zero-oom-and-concurrency.md)** - Master philosophies mapping all iOS scale limitations and Supabase Edge optimizations.
- **[`/system-architecture/17-ai-engineering.md`](./system-architecture/17-ai-engineering.md)** - LLMOps edge deployment constraints, maxOutputTokens limits, and API throttling behaviors.

### Concept Spotlights

- **[`/system-architecture/system-overview.md`](./system-architecture/system-overview.md)** - High-level structural decoupling overview.
- **[`/development-guides/core-managers.md`](./development-guides/core-managers.md)** - Deep dive into singleton active instances across Merian (e.g. `HardwareOrchestrator`).

## About Merian

Merian is a zero-friction, native iOS and iPadOS application designed as an homage to the flawless user experience of Sky Guide. It identifies plants, animals, insects, fungi, and indoor ecology with scientific-grade accuracy in under 3 seconds using dynamic routing between the Gemini 2.5 Flash and Pro APIs.
