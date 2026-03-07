# Architectural System Overview

## Core System Philosophies

1. **Separation of Control and Insight**
   - **Control (Viewfinder)**: Opens instantly (<1s). Actions live strictly in a floating glassmorphic bar in the bottom 30% of the screen (the "Natural Thumb Zone").
   - **Insight (Sheet)**: The analytical payload (taxonomy, models, alerts) renders into a bottom sheet. Expanding the sheet intrinsically throttles camera physics down to 1fps to instantly cool down the Apple Neural Engine.

2. **Zero-OOM Edge Strategy (Ephemeral Networking)**
   Because high-resolution camera data can easily exceed Supabase Edge memory limits (resulting in Out-Of-Memory/OOM termination), Merian employs a direct upload pipeline:
   - Images are uploaded _directly_ to the Gemini File API and/or Cloudflare R2 using Pre-Signed URLs natively on the iPhone.
   - The Deno Edge node _only_ accepts lightweight Metadata JSON strings containing the transient `uri`, routing to Gemini instantly.

3. **Anonymous Identity Resolution (The Ghost User)**
   To fulfill Apple App Store mandates on zero-friction entry:
   - New downloads generate an immediate _Anonymous User_ via `SupabaseManager.initializeGhostSession()`.
   - No accounts are required to analyze ecology; limits (3 a day) are physically checked via un-logged UUID matching and Apple Store RevenueCat entitlements.
4. **Hardware Constraints (Heat & Battery)**
   - Managed by `HardwareOrchestrator`. Automatically downgrades physical sensor FPS matrices (`60 -> 45 -> 30 -> 15`) during extended thermal exposure.
   - Dynamic blinding: If the hardware runs dangerously hot, blur effects (`.ultraThinMaterial`) are natively stripped out and replaced with opaque black matrices to reduce GPU drawing.

5. **"Any Ecology" Evaluation**
   - Merian evaluates the user's subject regardless of biological status. It strictly categorizes results into: _Wild_, _Urban_, or _Domesticated_.
   - Coordinates are heavily obscured for _Wild_ hits to prevent poaching (IUCN constraints) naturally inside the Supabase DWC-A Export pipeline.
