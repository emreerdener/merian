# Contributing to Merian 🦋

Thank you for your interest in contributing to Merian! Our goal is to build the world's fastest, most resilient native iOS ecological identification engine. Because Merian sits at the intersection of heavy edge-compute API inference, hardware-accelerated LiDAR processing, and robust GDPR compliance, we enforce stringent contribution guidelines.

## Code Architecture & Philosophy

Before contributing, please review our core architectural tenets. Refactoring code that violates these principles will not be merged.

1.  **Thermal Management is King**: iOS is hostile to apps that run the GPU and CPU concurrently at full load. Any feature added to the viewfinder MUST interface with `HardwareOrchestrator`. Frame rates must dynamically drop behind modals or when the device hits `.fair` or `.serious` thermal states.
2.  **Zero-OOM Edge Infrastructure**: Deno Edge Functions crash violently when handed 20MB Base64 strings. Merian processes media _exclusively_ via Gemini File URIs or Cloudflare R2 pointers. Do not attempt to reintroduce Base64 image bloat into the network payload arrays.
3.  **Offline-First Paradigm**: Network availability in the field is chaotic. Any user-generated action (e.g., snapping a photo) must first natively write to the `NWPathMonitor` SwiftData queue rather than awaiting network validations globally.
4.  **Accessibility (a11y)**: If a feature presents visual data natively, it must possess native SwiftUI `.accessibilityLabel` arrays explicitly reading components in a human-friendly format (e.g., using `.combine` on Grid tables).

## Setting Up the Development Environment

1.  **Xcode**: Ensure you are running Xcode 15 or later, as we exclusively target iOS 17+.
2.  **Supabase CLI**: For testing edge functions locally, you will need the Supabase CLI installed.
3.  **Project Generation**: We do not commit the `.xcodeproj` or `.xcworkspace`. Use XcodeGen to generate the project file natively:
    ```bash
    xcodegen generate
    open Merian.xcodeproj
    ```

## Testing Protocol

- **Swift/iOS**: All `@MainActor` lifecycle boundaries must not block the main thread.
- **Edge Functions**: You must write and validate code natively using Deno testing frameworks. Before opening a PR targeting `supabase/functions`, run:
  ```bash
  supabase functions test YOUR_MODULE_NAME
  ```

## Submitting a Pull Request 🚀

1.  Fork the repository and create your feature branch: `git checkout -b feature/my-amazing-feature`.
2.  Format your code. Swift code must naturally adhere to Apple's general styling limits. TypeScript should be linted natively before committing.
3.  Commit your changes following standard imperative structures.
4.  Push to the branch locally.
5.  Open a Pull Request describing the changes, explicitly mentioning if you changed any core network layer boundaries or AVFoundation settings.

We look forward to building this amazing open ecosystem with you!
