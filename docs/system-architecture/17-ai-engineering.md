# 17. AI Engineering & LLMOps

Merian's core inference engine leverages Google's Gemini 2.5 architecture (Flash/Pro) executed exclusively inside serverless Deno Edge closures to protect API keys and rigorously enforce output structures natively.

## Generation Configuration Guardrails

- **Token Throttling (`maxOutputTokens: 800`)**: To aggressively combat LLM hallucination, API cost overruns, and runaway "thinking/planning" tokens structurally introduced by hybrid reasoning models, all production Edge bindings (`supabase/functions/identify/index.ts`) must enforce an explicit `maxOutputTokens: 800` parameter embedded strictly inside the `generationConfig` payload constraint. This statically guarantees the model focuses exclusively on populating the strict `responseSchema` JSON dictionary mapping rather than generating lengthy, unbound internal reasoning chains that silently timeout the user's Edge execution limits waiting for recursive loops.
- **Low Temperature Constraints (`temperature: 0.1`)**: Biological identification must remain rigorously deterministic. The model's entropy bounds are physically hardcoded to `0.1` natively preventing biological hallucination outputs natively.
