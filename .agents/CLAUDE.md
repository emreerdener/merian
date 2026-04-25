# AI Agent Instructions for Merian

You are an advanced AI engineering assistant working on the Merian project. Merian is a high-performance biological classification and gamification platform built natively for iOS and watchOS, backed by Supabase PostgreSQL and scaled via Deno Edge Functions.

**📍 CRITICAL DOCUMENTATION DIRECTIVE:**
Before proposing structural changes or refactoring any code, you MUST review the associated documentation in the `/docs` repository to understand the master architectural constraints. 
**If you successfully merge a refactor, fix a bug affecting API payloads, or restructure a domain layer, *your final step before completing the task MUST be auditing and updating the `/docs` Markdown files to match your code changes.* Failure to keep the system documentation synchronized means you have failed the task.**

## 1. Supabase Edge & Deno Architecture (STRICT RULES)
- **Domain-Driven Modular Architecture**: Edge functions are written in TypeScript under `supabase/functions/` and are strictly decoupled. You MAY NOT build monolithic `index.ts` files. Before modifying backend functions, you MUST read **`docs/system-architecture/06-edge-modularization.md`**.
  - `index.ts`: Strict HTTP controller orchestrating JWT validation and IDOR guards. No PostgreSQL `.select()`/`.insert()` logic allowed here.
  - `db.ts`: The native data layer encapsulating all PostgREST operations. All queries pulling variable array fields must enforce mathematically safe bounds (e.g., `.limit(500)`) natively to protect V8 Isolates from memory crashes.
  - `types.ts`: Strict schema mapping bridging Swift `Codable` structs directly to Deno JSON payloads.
- **Shared Utilities**: The `supabase/functions/_shared/` folder contains exactly 9 pristine domains controlling CORS headers, telemetrics, AWS payloads, and the Gemini AI abstraction layer (see `_shared/README.md`). Do not hallucinate or create duplicate shared scripts.
- **Strict Typing**: TypeScript `any` types and `@ts-ignore` flags are forbidden. All modifications must natively pass a recursive `deno check` compilation before you declare a task complete.

## 2. iOS Frontend Stack (SwiftUI & SwiftData)
- **XcodeGen**: DO NOT modify the `Merian.xcodeproj` package natively. You must modify `project.yml` and execute `xcodegen generate`.
- **Offline-First Resilience**: All physical native captures MUST be enqueued into `OfflineQueueManager` (via SwiftData) before attempting a network boundary. Do not orchestrate raw `URLSession` calls from the UI layer. 
- **Thermal State & Zero-Latency**: iOS camera buffers run violently hot. `CameraManager` natively respects `HardwareOrchestrator` bounds. Do not override `targetFPS` bounds. Glassmorphism MUST gracefully degrade when the thermal state reaches `.serious`.
- **State Management**: Merian strictly rejects generic `@EnvironmentObject` usage for heavy singletons. Use `AppDIContainer.shared` for structured dependency injection to safely prevent SwiftUI redraw loops (e.g. `let cameraManager: CameraManager`).

## 3. Security Protocols
- **Zero-PII**: Merian is strictly zero-PII. Telemetry pipelines must NEVER log plain-text GPS coordinates, emails, or names.
- **Testing Hygiene**: Any temporary test script (Python, Node, Bash) written by an AI agent to validate endpoints MUST pull securely from localized execution environments natively. If a Supabase Service-Role key or Gemini API Key must be hardcoded for a one-off validation, that script MUST be physically purged from the file system the exact millisecond execution finishes so it never leaks into git bounds.
- **IDOR Defense**: All Edge Functions modifying data (e.g., `/delete-scan`, `/block-user`) must physically extract the anonymous Deno user UUID parsing out from the payload `Authorization` header and explicitly map it against a `.eq("user_id", user.id)` bounding query.

## 4. Execution Expectations
- Prioritize native implementation tools correctly. Do not pipe scripts out to `bash` for native file editing.
- Always verify your dependencies. If you need a new Swift file, ensure it compiles via `xcodebuild`.
- When communicating your implementation plan, logically explain *why* you are implementing a specific pattern, citing its impact on V8 isolator memory bounds, iOS battery limits, or Offline synchronization constraints.
