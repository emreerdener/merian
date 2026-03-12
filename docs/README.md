# Merian App Documentation

Welcome to the Merian ecosystem documentation. This directory serves as the technical master reference for the native iOS application, Supabase PostgreSQL backend, Cloudflare R2 ephemeral networking, and hardware orchestration logic.

## Directory Structure

### Core Systems

- **[`01-System-Architecture.md`](./01-System-Architecture.md)** - Master philosophies, zero-OOM infrastructure strategy, and lazy-loading UX principles.
- **[`02-Camera-and-Hardware.md`](./02-Camera-and-Hardware.md)** - Native AVFoundation bindings, LiDAR depth logic, and ViewfinderIntelligence constraints.
- **[`03-Offline-Sync-Pipeline.md`](./03-Offline-Sync-Pipeline.md)** - Zero-data-loss architecture, SwiftData queues, and AppDelegate background URLSession mappings.
- **[`04-Supabase-Edge-and-Database.md`](./04-Supabase-Edge-and-Database.md)** - Supabase Postgres schemas, Edge Function runtime rules, and RLS bypasses.
- **[`05-Revenue-and-Identity.md`](./05-Revenue-and-Identity.md)** - IDFV Keychain bindings, anonymous onboarding, and RevenueCat entitlement structures.
- **[`06-Gamification-and-Telemetry.md`](./06-Gamification-and-Telemetry.md)** - PostHog anonymous telemetry mappings and Rive `.riv` interactive logic.
- **[`07-Database-Schema.md`](./07-Database-Schema.md)** - The physical table maps for PostgreSQL and the SwiftData persistent schemas.
- **[`08-API-Contracts.md`](./08-API-Contracts.md)** - Raw JSON mapping contracts bridging the iOS client and Edge Deno engines.
- **[`09-AI-Agent-Guidelines.md`](./09-AI-Agent-Guidelines.md)** - Master rules, architecture constraints, and explicit prompt boundaries for AI dev agents.

### Concept Spotlights

- **[`/architecture/system_overview.md`](./architecture/system_overview.md)** - High-level structural decoupling overview.
- **[`/services/core_managers.md`](./services/core_managers.md)** - Deep dive into singleton active instances across Merian (e.g. `HardwareOrchestrator`).
- **[`/ui/components_guide.md`](./ui/components_guide.md)** - Native SwiftUI rendering logics, `CameraRootView`, and the DWC-A insights sheet mechanics.

## About Merian

Merian is a zero-friction, native iOS and iPadOS application designed as an homage to the flawless user experience of Sky Guide. It identifies plants, animals, insects, fungi, and indoor ecology with scientific-grade accuracy in under 3 seconds using the Gemini 2.5 Flash API.
