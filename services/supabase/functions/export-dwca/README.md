# Export Darwin Core Archive

The heavy-lifting background worker responsible for assembling massive scientific datasets. Operating completely autonomously from the `.swift` iOS UI threads, this worker compiles Gigabytes of imagery, PostgreSQL relational taxonomy, and standardized Specimen formatting into a single `zip` artifact and natively emails it via the Resend API. 

## Architectural Separation

Because this worker performs multi-megabyte PostgREST fetches alongside crypto hashing and stream compression, all business components are strictly modularized to protect the V8 isolate from Memory Limit (`OOM`) crashes.

- **`index.ts`**: The strict Webhook Orchestrator. Blocks non-service-key callers, wraps the process in a top-level `try/catch` to emit fallback error updates to `export_jobs`, and invokes the abstraction pipeline sequentially.
- **`db.ts`**: Handles the massive `.range()` PostgreSQL iteration. During 1,000+ row fetches, it intentionally manually invokes the Edge garbage collector (`globalThis.gc?.()`) to dump processed SQL arrays out of the isolate's memory constraints.
- **`dwca.ts`**: Contains the massive `meta.xml` static string mappings and the exact array index mappers that format `generateDwcARow`. Houses the `encodeHex(crypto.subtle)` logic for safely anonymizing `user_id` attribution hashes during global academic exports.
- **`storage.ts`**: Configures the `JSZip` boundary, mapping the multi-CSV string output into a raw `Uint8Array` stream that natively streams into Cloudflare R2's `exports/` bucket without loading the full ZIP into Deno memory at once. It returns the 24-hour Presigned `GET` URL.
- **`mail.ts`**: Exclusively contains the exact HTML string payloads framing the Resend delivery API webhook.
