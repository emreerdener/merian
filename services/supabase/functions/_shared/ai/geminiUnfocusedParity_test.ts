import { assertEquals } from "@std/assert";
import type {
  GeminiAttemptSnapshot,
  MultimodalAIRequest,
} from "./contracts.ts";
import { buildGeminiRequestParameters } from "./geminiRequest.ts";
import fixtures from "./fixtures/unfocused-gemini-requests.json" with {
  type: "json",
};

// Full JSON serialization hashes captured from the pre-selection request builder
// at ac8f1737dadf2e7319681a2ae019ab806faf540d. These synthetic cases cover
// schema, instruction, generation options, media order and complete contents.
// No provider, network, credentials or live media are involved.
Deno.test("manual selection does not change complete unfocused Gemini requests", async () => {
  for (const fixture of fixtures) {
    const parameters = buildGeminiRequestParameters(
      fixture.request as MultimodalAIRequest,
      fixture.snapshot as GeminiAttemptSnapshot,
    );
    const bytes = new TextEncoder().encode(JSON.stringify(parameters));
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
    const hash = Array.from(
      digest,
      (value) => value.toString(16).padStart(2, "0"),
    ).join("");
    assertEquals(hash, fixture.sha256, fixture.name);
  }
});
