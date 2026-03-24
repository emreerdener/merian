# 17. AI Engineering & LLMOps

Merian's inference engine uses Google's Gemini 2.5 architecture (Flash/Pro) running inside serverless Deno Edge functions to protect API keys and enforce structured output.

## Inference Layer Structure

The AI inference layer is split across three files under `merian/Core/AI/`:

- **`InferenceEngine.swift`**: The main engine. Coordinates upload confirmation, triggers the Edge function, and delivers results to `CameraViewModel`.
- **`InferenceProcessingActor.swift`**: An off-main-thread actor responsible for base64 encoding image data and parsing Edge responses.
- **`InferenceEdgeDTOs.swift`**: Codable DTOs used for Edge communication: `APIError`, `EdgeResponseWrapper`, and `EdgeResponse`.

## Generation Configuration Guardrails

- **Dynamic Token Truncation (Non-Biological Bounds)**: To reduce API costs and output token usage, the `merianResponseSchema` was relaxed. Nested biological objects (`taxonomy`, `insight_data`, `diagnostic_comparison`) were removed from the `required: []` array. A `systemInstruction` rule now tells Gemini to omit these structures entirely when `is_biological_subject = false`. Because the Swift `EdgeResponse` struct declares these sub-nodes as optionals (`?`), `JSONDecoder` collapses missing keys to `nil` without crashing, cutting token usage on non-biological payloads.
- **Universal Schema Enforcement**: The `merianResponseSchema` is applied across all `isProActive` tier boundaries, enforcing strict JSON compliance and consistent object nesting for both Free and Pro models.
- **Token Throttling (`maxOutputTokens: 800`)**: All production Edge bindings enforce `maxOutputTokens: 800`. This keeps the model focused on populating the JSON output rather than generating internal reasoning chains that can silently exhaust Edge execution time limits.
- **Telemetry Pruning**: Legacy ephemeral fields (`cameraPitchDegrees`, `compassHeading`, `relativeHumidity`, `uvIndex`, `isFlashFired`) have been removed from the `CaptureTelemetry` JSON payload, saving hundreds of tokens per request. Schema nodes like `key_differentiators` and descriptive enum schemas inside Deno are compressed into flat string arrays.
- **Low Temperature Constraints (`temperature: 0.1`)**: Biological identification requires deterministic output. The model temperature is hardcoded to `0.1` to minimize hallucination.
- **Multi-Image Context Fusion**: The `identify` Edge function accepts an array of `r2ObjectKeys: string[]`. Deno fetches multiple presigned S3 URLs concurrently via `Promise.all()`, encodes the results as base64, and injects them as distinct `inlineData` MIME parts into the Gemini prompt, supporting macro shots alongside wider environmental images without payload timeouts.
