# 🦋 Merian

**The Zero-Friction, Native AI-Powered Ecological Identification Engine**

Merian is a powerful, native iOS & iPadOS application designed for high-speed biological discovery. Built completely with strict architectural constraints in mind, it utilizes the Google Gemini API directly over Deno Edge Functions to analyze hardware-accelerated LiDAR depth maps while employing severe thermal throttling constraints to execute an "Instant-On" zero-OOM field-ready application.

## 🌟 Core Features

- 📸 **Instant-On Camera UI**: Drops straight into an `AVCaptureSession` in under 1 second. Utilizing a custom `.builtInLiDARDepthCamera` module quietly harvesting distances up to 5.0m max.
- 🌡️ **Hardware Orchestrator**: Dynamically throttles active iOS framerates via `ProcessInfo` down to as low as `1fps` behind UI Sheets or `24fps` dynamically inside Low Power Modes, aggressively protecting the hardware against heavy thermal rendering bottlenecks.
- 📡 **Zero-OOM Edge Architecture**: Employs completely Base64-free direct raw `Data` transfer endpoints using Supabase Edge Functions linking strictly onto the Gemini File URI protocols.
- 🗄️ **Zero-Data Loss Offline Queue**: Powered by `NWPathMonitor` & SwiftData mapping explicit `.sqlite` limits down to local endpoints so users never lose captures taken far off-grid.
- 🛡️ **Social Isolation Guard Graph**: Employs real-time Discovery Feeds explicitly blocking your specific uploads out globally while tracking blocklists locally to prevent adversarial toxicity organically.
- 📊 **Darwin Core Archives (DwC-A)**: Maps fully GDPA-Compliant data architectures securely using explicit PostgreSQL procedures enforcing _Ghost User Tombstones_ mapping your public discoveries backwards down to a robust `00000000-0000-0000-0000-000000000000` universally across our ecosystem securely preserving taxonomy bounds.
- ⌚️ **Apple Ecosystem Extensions**: Powered fully by native **Siri AppIntents**. Integrated directly onto watchOS utilizing background `.record` boundaries converting field acoustics effortlessly across WiFi natively dynamically.

## 🛠️ Stack

- **Frontend**: iOS 17+, Swift 5.9+, SwiftUI, SwiftData, AVFoundation, CoreLocation, Combine
- **Kinetic UX**: RiveRuntime (`.riv`), UIVisualEffectView
- **Backend Ecosystem**: Supabase (PostgreSQL, Deno Edge Functions)
- **Cloud Storage**: Cloudflare R2 Edge Storage Arrays
- **AI Engine**: Google Gemini 1.5 Flash (`generativelanguage.googleapis.com`)
- **DevOps/CI-CD**: GitHub Actions

## 🚀 Getting Started

Merian runs its configurations globally against `XcodeGen` parameters natively over iOS 17 variables.

### Prerequisites

- macOS 14.0+
- Xcode 15.0+
- `xcodegen` (Optional, easily installed via `brew install xcodegen`)
- Supabase CLI

### Installation

1.  **Clone the Project**

    ```bash
    git clone https://github.com/your-org/merian.git
    cd merian
    ```

2.  **Generate Xcode Project**
    Via XcodeGen parameters cleanly:

    ```bash
    xcodegen generate
    open Merian.xcodeproj
    ```

3.  **Local Backend Execution (Optional)**
    Boot the Supabase Deno endpoints locally testing directly via localhost arrays:
    ```bash
    supabase start
    # To run test boundaries against Gemini Edge Nodes natively
    supabase functions test identify
    ```

## 📜 Legal

Subject to all relevant terms regarding AI Inference platforms explicitly checking data payloads.
