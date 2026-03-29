# `_shared` Directory

The `_shared` repository contains the core abstraction domains that power the 11 globally isolated Deno Webhooks scaling Merian.

Rather than fragmenting logic recursively through standard HTTP proxies, the dependencies are strictly decoupled into 9 pure domain abstractions.

## Infrastructure Map

- **`biology.ts`**: The unified generative pipeline responsible for routing `Gemini Flash 2.5` payloads mapped directly into standard scientific JSON structures (`iucn_red_list_status`, `habitat_description`). Aggregates usage parameters manually extracting LLM LLM token telemetry logic via PostHog metrics logging.
- **`http.ts`**: The baremetal HTTP isolation boundary. Governs cross-origin policy headers (`corsHeaders`), exports JSON payload serialization natively (`jsonResponse`), and defends against standard payload tampering using `requireParams` checking and constant-time cryptography checks against timing attacks via `timingSafeCompare`.
- **`aws.ts`**: Maps generic logic controlling S3-compatible endpoints like Cloudflare R2 via `aws4fetch`. Generates natively pre-signed upload URL blocks, and natively powers explicit array deletion routines capable of efficiently batch-bypassing strict `1,000 Key` evaluation ceilings natively on `DeleteObjects`.
- **`edgeHandler.ts`**: Merian’s critical Edge isolation proxy. All user-facing functions invoke `withEdgeHandler()`, natively bypassing the complex `OPTIONS` preflight layer while explicitly parsing `JWT` validation securely prior to execution. Invokes `EdgeRuntime.waitUntil(task)` to bypass strict Deno V8 wall-clock bounds.
- **`external.ts`**: Drives parallel execution layers interacting directly with structured APIs natively, including Wikipedia and the GBIF (Global Biodiversity Information Facility). Safely wraps DaaS fetch blocks behind an aggressive `AbortSignal.timeout(2500)`.
- **`gemini.ts`**: Instantiates global `GoogleGenerativeAI` models directly behind the proxy. Contains `extractJson<T>(text)` logic designed expressly to rip Markdown fences securely off of corrupted Gemini LLM strings natively.
- **`auth.ts`**: Native Deno SDK integration mapped explicitly against the JSON Web Token lifecycle validating `Supabase` authentication payloads.
- **`posthog.ts`**: Wraps native HTTP payload logging executing directly to PostHog, decoupling Telemetry from the `identify` critical path.
- **`tierCache.ts`**: Natively provisions a generic `Map<string, { tier: string, ts: number }>` global executing locally in the V8 Isolate memory chunk natively preserving `5-minute TTL` validations to securely eliminate heavy Deno->Supabase Postgres roundtrip checks.
