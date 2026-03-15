# Merian AI Code Conventions & Guidelines

When generating or modifying code for Merian, follow these explicit constraints to ensure optimal performance, hardware safety, and architectural consistency.

## 0. The Documentation Directory
The `docs/` folder contains the master reference for the application:
- Refer to `docs/07-Database-Schema.md` for PostgreSQL & SwiftData schemas.
- Refer to `docs/08-API-Contracts.md` for all network request/response shapes.
- Refer to `docs/01-System-Architecture.md` for overall logic.

## 1. Project Generation (XcodeGen)
- **NEVER** directly modify `Merian.xcodeproj`.
- **ALWAYS** update `project.yml` when adding new packages, frameworks, scopes, or entitlements.
- Run `xcodegen generate` explicitly before attempting to build.
- API Keys must be injected via `Config.xcconfig` or `MerianEnvironment.swift`. NEVER hardcode `GEMINI_API_KEY` or `SUPABASE_ANON_KEY` inside `.swift` files. 

## 2. Directory Structure
The workspace enforces this layout inside `merian/`:
- `Features/`: Complete user domains (`Camera`, `Insights`, `LifeList`, `Profile`).
- `Core/`: Foundational logic (`AI`, `Network`, `Security`, `Data`, `Hardware`, `Analytics`, `Intents`).
- `UIComponents/`: highly reusable generic building blocks.
- `Models/`: Standardized pure Data structures and `SwiftData` logic.
- `Configuration/`: `project.yml`, `Config.xcconfig`, App Intents, and Entrypoint metadata.

## 3. Application State & Dependency Injection
- **DO NOT** use scattered `@EnvironmentObject` implementations or rely heavily on SwiftUI environment scoping for heavy singletons.
- **ALWAYS** use `AppDIContainer.shared` for injecting business logic. This protects the SwiftUI View lifecycle from massive memory redraw loops.
- Pass required core managers cleanly (e.g., `let cameraManager: CameraManager`) into `Views` as `@Observable` bindings or `@ObservedObject` properties.

## 4. Hardware and Performance Limits
- iOS Background limitations severely constrain API requests. Any heavy file I/O operations must be cleanly decoupled via `Task.detached(priority: .background)`.
- Image conversions (e.g. `downsampleImage`) or large JSON parsing must occur off the Main thread to prevent 60FPS UI stutters.
- Avoid forcing `.isHighResolutionCaptureEnabled` without throttling image loads natively via `ImageIO` `CGImageSourceCreateThumbnailAtIndex` bounded logic. A full 12MP-48MP uncompressed capture explicitly forces iOS "Out of Memory" (OOM) crashes if repeatedly appended array buffers are allocated blindly.

## 5. UI and Glassmorphism (Aesthetics)
- **Stunning UIs are mandatory**: The user should be wowed at first glance.
- Implement `.ultraThinMaterial` backgrounds universally to merge UI elements organically over camera viewfinders.
- Avoid large opaque black or white overlay panes. Make components dynamic, animated with `.spring()` transitions, and highly responsive. Use `RiveRuntime` (`.riv` files) for complex interactive states.
- DO NOT use XIBs or custom rigid Storyboards. Write natively composed SwiftUI exclusively.

## 6. Supabase & Deno Edge
- The `identify` Edge node abstracts all `generativelanguage` (Google) calls natively.
- Never write direct Gemini inference code directly inside iOS Swift controllers, this leaks API keys and bypasses edge limits.
- Keep the Deno Edge `index.ts` files perfectly synchronized with the Swift `IdentifyResponse` API Contract mapped in `08-API-Contracts.md`.
- Ensure all unstructured display text (e.g. `common_name`) is locked via `systemInstruction` rigid rules to format cleanly as Title Case natively to prevent messy frontend lowercase UI outputs before it ever caches physically into the database.

## 7. Database Safeties
- Anonymous IDs (`DeviceIdentityManager.shared.deviceId`) exist solely to securely persist the `UsageManager` limits locally on iOS against reinstallations. Do not blindly use IDFV (`.deviceId`) for backend user records or analytics identifiers. Keep identity cleanly chained against the active Supabase Auth session `.uuidString` to natively sync RevenueCat.
- Follow RLS (Row Level Security) schemas logically by explicitly avoiding direct CRUD iOS modifications onto PostgreSQL. Instead, POST heavily via Edge REST points protected by Native JWT verification `supabaseAdmin.auth.getUser()`.
