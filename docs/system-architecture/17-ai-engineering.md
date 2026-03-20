# 17. AI Engineering & LLMOps

Merian's core inference engine leverages Google's Gemini 2.5 architecture (Flash/Pro) executed exclusively inside serverless Deno Edge closures to protect API keys and rigorously enforce output structures natively.

## Generation Configuration Guardrails

## Generation Configuration Guardrails

- **Tiered Token Strategy (Schema Truncation)**: To aggressively shield the core billing limit, the Gemini architecture dynamically evaluates context bounds across an `isProActive` boolean split from Swift. For `Pro Tier` users, the explicit `merianResponseSchema` structural map is heavily enforced dictating exact object nesting. However, because embedding a raw JSON Schema directly consumes around ~1,000 artificial tokens inherently, `Free Tier` requests natively execute dropping the `.responseSchema` requirement completely natively providing a lightweight `.txt` system prompt yielding identical shapes.
- **Token Throttling (`maxOutputTokens: 800`)**: To aggressively combat LLM hallucination, API cost overruns, and runaway "thinking/planning" tokens structurally introduced by hybrid reasoning models, all production Edge bindings must enforce an explicit `maxOutputTokens: 800` parameter. This statically guarantees the model focuses exclusively on populating the strict JSON output rather than generating lengthy, unbound internal reasoning chains that silently timeout the user's Edge execution limits.
- **Token Truncation Optimization (Telemetry Pruning)**: Employs an aggressive minification protocol specifically across context bounds sent up by `CaptureTelemetry`. Legacy ephemeral variables (like `cameraPitchDegrees`, `compassHeading`, `relativeHumidity`, `uvIndex`, and `isFlashFired`) were explicitly obliterated and pruned out of the JSON architecture statically saving hundreds of candidate tokens per physical shutter press natively. Structural nodes like `key_differentiators` and descriptive enum schemas inside Deno are forcefully compressed into flat String arrays dynamically formatting API sizes down cleanly.
- **Low Temperature Constraints (`temperature: 0.1`)**: Biological identification must remain rigorously deterministic. The model's entropy bounds are physically hardcoded to `0.1` natively preventing biological hallucination outputs natively.
