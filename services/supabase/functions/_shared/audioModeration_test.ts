import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  classifyExploreAudio,
  parseGeminiAudioClassification,
} from "./audioModeration.ts";

function response(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    transcript: "A robin is calling nearby.",
    non_speech_description: "Birdsong and light wind.",
    policy_categories: [],
    approved: true,
    confidence: 0.98,
    requires_review: false,
    ...overrides,
  });
}

Deno.test("Gemini audio classifier approves only a consistent high-confidence result", async () => {
  const decision = await classifyExploreAudio(
    new Uint8Array([1, 2, 3]).buffer,
    "audio/wav",
    () => Promise.resolve(response()),
  );
  assertEquals(decision, { approved: true, model: "gemini-2.5-flash" });
});

Deno.test("Gemini audio classifier routes low-confidence decisions away from publication", async () => {
  const decision = await classifyExploreAudio(
    new Uint8Array([1]).buffer,
    "audio/wav",
    () => Promise.resolve(response({ confidence: 0.5 })),
  );
  assertEquals(decision.approved, false);
});

Deno.test("Gemini audio classifier rejects harmful categories", async () => {
  const decision = await classifyExploreAudio(
    new Uint8Array([1]).buffer,
    "audio/wav",
    () =>
      Promise.resolve(response({
        approved: false,
        policy_categories: ["violence_or_gore"],
      })),
  );
  assertEquals(decision.approved, false);
});

Deno.test("Gemini audio classifier fails closed on malformed or inconsistent output", async () => {
  await assertRejects(
    () =>
      classifyExploreAudio(
        new Uint8Array([1]).buffer,
        "audio/wav",
        () => Promise.resolve("not-json"),
      ),
    Error,
    "malformed JSON",
  );
  assertThrows(
    () =>
      parseGeminiAudioClassification(response({
        approved: true,
        policy_categories: ["personal_data"],
      })),
    Error,
    "inconsistent decision",
  );
});
