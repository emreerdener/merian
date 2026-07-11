import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  classifyExploreAudio,
  fetchBoundedModerationMedia,
  parseGeminiAudioClassification,
  resolveGeminiMediaType,
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

Deno.test("Gemini media type preserves audible MP4 video and supported audio", () => {
  assertEquals(resolveGeminiMediaType("video/mp4", "/clip.mp4"), "video/mp4");
  assertEquals(
    resolveGeminiMediaType("audio/wav; charset=binary", "/clip.wav"),
    "audio/wav",
  );
  assertEquals(resolveGeminiMediaType(null, "/clip.m4a"), "audio/mp4");
});

Deno.test("Gemini media type rejects unsupported bytes instead of relabeling them", () => {
  assertThrows(
    () => resolveGeminiMediaType("application/octet-stream", "/clip.bin"),
    Error,
    "unsupported",
  );
});

Deno.test("moderation media fetch enforces exact host and preserves video MIME", async () => {
  await assertRejects(
    () =>
      fetchBoundedModerationMedia(
        "https://media.merian.app.attacker.example/clip.wav",
        () => Promise.resolve(new Response()),
      ),
    Error,
    "not an approved Merian media URL",
  );

  const result = await fetchBoundedModerationMedia(
    "https://media.merian.app/public_uploads/pro/clip.mp4",
    () =>
      Promise.resolve(
        new Response(new Uint8Array([1, 2, 3]), {
          headers: { "content-type": "video/mp4" },
        }),
      ),
  );
  assertEquals(result.mimeType, "video/mp4");
  assertEquals(result.bytes.byteLength, 3);
});

Deno.test("moderation media fetch rejects empty and oversized responses", async () => {
  await assertRejects(
    () =>
      fetchBoundedModerationMedia(
        "https://media.merian.app/empty.wav",
        () => Promise.resolve(new Response(new Uint8Array())),
      ),
    Error,
    "empty or exceeds",
  );
  await assertRejects(
    () =>
      fetchBoundedModerationMedia(
        "https://media.merian.app/large.wav",
        () =>
          Promise.resolve(
            new Response(null, {
              headers: { "content-length": String(12 * 1024 * 1024 + 1) },
            }),
          ),
      ),
    Error,
    "empty or exceeds",
  );
});
