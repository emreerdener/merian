# Merian App Documentation

Welcome to the Merian ecosystem documentation. This directory serves as the technical master reference for the native iOS application, Supabase PostgreSQL backend, Cloudflare R2 ephemeral networking, and hardware orchestration logic.

## Directory Structure

- **[`/architecture/system_overview.md`](./architecture/system_overview.md)** - Master philosophies, zero-OOM infrastructure strategy, and lazy-loading UX principles.
- **[`/services/core_managers.md`](./services/core_managers.md)** - Deep dive into singleton components: `HardwareOrchestrator`, `OfflineQueueManager`, `ViewfinderIntelligence`, `SupabaseManager`, etc.
- **[`/backend/edge_infrastructure.md`](./backend/edge_infrastructure.md)** - Supabase Edge Functions, Row-Level Security, Database Schema constraints, and Cloudflare R2 presigned routing.
- **[`/ui/components_guide.md`](./ui/components_guide.md)** - Native SwiftUI rendering logic for the Glassmorphic action bar, the `CameraRootView` full bleed, the DWC-A insights sheet, and the Rive Gamification (`TerrariumView`).

## About Merian

Merian is a zero-friction, native iOS and iPadOS application designed as an homage to the flawless user experience of Sky Guide. It identifies plants, animals, insects, fungi, and indoor ecology with scientific-grade accuracy in under 3 seconds using the Gemini 1.5 Vision API.
