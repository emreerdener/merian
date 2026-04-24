# Background Inference: Body-Safe Pattern

This document captures the current background inference body contract and the future two-phase audio upload design.

## Current State

- Images already use the staged-R2 path: background upload to `staging/{userId}/...`, then a tiny inference request carrying `r2ObjectKeys`.
- Audio does **not** use an `audio_r2_key` contract today.
- Both live audio submission and offline replay route through `/identify-multimodal` with inline `audioBase64s`.
- `dispatchInferenceDownloadTask` still uses a background `downloadTask(with:)` request body for audio, so the request is operationally safe in current use but not fully “by-the-book” for arbitrarily large audio bodies.

## Why This Is Acceptable Today

- Audio clips are short (15 s max) and persisted to `Documents/` before inference starts.
- The current replay path is retriable: if the background request fails, the scan returns to `.staged` and is retried on the next connectivity cycle.
- The active payload contract is simple and stable: `MerianNetworkClient.buildMultiModalRequest(...)` reads the WAV from disk, base64-encodes it off the main actor, and sends it as `audioBase64s`.

## Future Work: Two-Phase Audio Upload

If audio payload size or background-session reliability becomes a problem, the correct long-term shape is:

1. Upload the WAV to R2 via `uploadTask(with:fromFile:)`.
2. Dispatch `/identify-multimodal` with a tiny body containing an audio staging key.
3. Have the edge function fetch the staging object, process it, and clean it up after ingest.

That future contract is **not implemented today**. The current client/server pair does not ship an `audio_r2_key` or `audioR2Keys` request field.

## Triggers For Implementing The Two-Phase Path

| Trigger | Action |
|---|---|
| Audio bodies approach background-session reliability limits | Implement R2 staging for audio |
| Observed replay failures suggest body loss on OS task restart | Implement R2 staging for audio |
| Longer recordings or higher-quality capture materially increase payload size | Implement R2 staging for audio |
| Current inline `audioBase64s` path remains stable in production | Keep the simpler current path |

## Source Of Truth

- iOS request builder: `MerianNetworkClient.buildMultiModalRequest(...)`
- Replay dispatcher: `OfflineQueueManager+URLSession.dispatchInferenceDownloadTask(...)`
- Edge handler: `supabase/functions/identify-multimodal/index.ts`
