# 🦋 Merian

**The Zero-Friction, Native AI-Powered Ecological Identification Engine**

Designed as an homage to the flawless user experience of Sky Guide, Merian acts as a magical magnifying glass for the world around you. It identifies plants, animals, insects, fungi, and indoor ecology with scientific-grade accuracy.

Built completely with strict architectural constraints in mind, it utilizes the Google Gemini API directly over Deno Edge Functions to analyze hardware-accelerated LiDAR depth maps. By employing severe thermal throttling constraints, Merian executes an "Instant-On," zero-OOM field-ready application that bridges the gap between rigid academic tools and predatory commercial apps.

---

## 🌟 Core Features & Architecture

- 📸 **Instant-On Camera UI**: Drops straight into an `AVCaptureSession` in under 1 second. It utilizes a custom `.builtInLiDARDepthCamera` module, quietly harvesting absolute physical scale up to 5.0m max to prevent vision model hallucinations.
- 🌡️ **Hardware Orchestrator**: Dynamically throttles active iOS framerates via `ProcessInfo` down to as low as `1fps` behind UI Sheets or `24fps` dynamically inside Low Power Modes. This aggressively protects the hardware against heavy thermal rendering bottlenecks without the latency of a cold restart.
- 📡 **Zero-OOM Edge Architecture**: To protect Edge Function memory limits, the app posts pure `Data` securely to the Gemini File API, generating a lightweight `fileUri`. This completely bypasses the 20MB Base64 stringification payloads that reliably crash Edge functions worldwide.
- 🗄️ **Zero-Data Loss Offline Queue**: Powered by `NWPathMonitor` and SwiftData, it natively persists timestamps and networks attempts securely. Users never lose captures taken off-grid; payloads sync seamlessly in the background upon network restoration.
- 🛡️ **Isolation-First Social Guard**: Employs real-time Discovery Feeds explicitly blocking a user's specific uploads out globally, while tracking blocklists locally to organically prevent adversarial toxicity without administrative bloat.
- 📊 **Darwin Core Archives (DwC-A)**: Natively exports localized user data strictly formatted to the academic DwC-A standard. It maps fully GDPR-compliant data architectures securely, using explicit PostgreSQL procedures to enforce _Ghost User Tombstones_ that permanently anonymize geographical behaviors while preserving taxonomy bounds.
- ⌚️ **Apple Ecosystem Extensions**: Powered fully by native **Siri App Intents** (Apple Intelligence ready). Integrated directly onto watchOS, utilizing background `.record` boundaries to convert field acoustics effortlessly across Wi-Fi.
- 🔍 **On-Device Semantic Search**: Enables offline natural language searches through the user's "Life List" utilizing hidden, AI-generated semantic indexing via SwiftData predicates.

---

## 🛠️ Tech Stack

- **Frontend**: iOS 17+, Swift 5.9+, SwiftUI, SwiftData, AVFoundation, CoreLocation, Combine
- **Kinetic UX**: RiveRuntime (`.riv`), UIVisualEffectView
- **Backend Ecosystem**: Supabase (PostgreSQL, Deno Edge Functions)
- **Cloud Storage**: Cloudflare R2 Edge Storage Arrays (S3-Compatible)
- **AI Engine**: Google Gemini 1.5 Flash (`generativelanguage.googleapis.com`)
- **DevOps/CI-CD**: GitHub Actions

---

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
    git clone [https://github.com/your-org/merian.git](https://github.com/your-org/merian.git)
    cd merian
    ```

2.  **Generate Xcode Project**
    Via XcodeGen parameters cleanly:

    ```bash
    xcodegen generate
    open Merian.xcodeproj
    ```

3.  **Local Backend Execution (Optional)**
    Boot the Supabase Deno endpoints locally to test directly via localhost arrays:
    ```bash
    supabase start
    # To run test boundaries against Gemini Edge Nodes natively:
    supabase functions test identify
    ```

---

## 📜 Legal

Merian is a tool for education, discovery, and conservation. Subject to all relevant terms regarding AI Inference platforms explicitly checking data payloads.
