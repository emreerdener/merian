import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  classifyExploreAudio,
  fetchBoundedModerationMedia,
  moderateExploreAudioUrl,
  parseGeminiAudioClassification,
  resolveGeminiMediaType,
} from "./audioModeration.ts";
import type { AudioModerationCache } from "./audioModeration.ts";

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
  assertEquals(decision, {
    approved: true,
    model: "gemini-2.5-flash",
    policyVersion: decision.policyVersion,
  });
  assertEquals(decision.policyVersion.length, 64);
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
    "not an approved Naturebook media URL",
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

Deno.test("production audio moderation refuses provider work without authoritative quota", async () => {
  let fetchCount = 0;
  await assertRejects(
    () =>
      moderateExploreAudioUrl(
        "https://media.merian.app/public_uploads/pro/clip.wav",
        undefined,
        () => {
          fetchCount += 1;
          return Promise.resolve(new Response(new Uint8Array([1])));
        },
      ),
    Error,
    "Authoritative AI quota is required",
  );
  assertEquals(fetchCount, 0);
});

Deno.test("content-addressed moderation reuses decisions without storing sensitive data", async () => {
  const decisions = new Map<string, boolean>();
  const stores: Array<Record<string, unknown>> = [];
  const cache: AudioModerationCache = {
    lookup(checksum, policyVersion, model) {
      const approved = decisions.get(checksum);
      return Promise.resolve(
        approved === undefined ? null : {
          approved,
          model,
          policyVersion,
        },
      );
    },
    store(input) {
      stores.push(input);
      decisions.set(input.checksumSha256, input.approved);
      return Promise.resolve();
    },
  };
  let generations = 0;
  let reservations = 0;
  let commits = 0;
  let refunds = 0;
  let failures = 0;
  const quotaInputs: Array<{
    checksumSha256: string;
    policyVersion: string;
  }> = [];
  const quota = {
    beforeProvider(input: {
      checksumSha256: string;
      policyVersion: string;
    }) {
      reservations += 1;
      quotaInputs.push(input);
      return Promise.resolve({
        reservation: { model: "gemini-2.5-flash" },
        commit() {
          commits += 1;
          return Promise.resolve();
        },
        refund() {
          refunds += 1;
          return Promise.resolve(true);
        },
        fail() {
          failures += 1;
          return Promise.resolve(true);
        },
      });
    },
  };
  const fetcher = () =>
    Promise.resolve(
      new Response(new Uint8Array([1, 2, 3]), {
        headers: { "content-type": "audio/wav" },
      }),
    );
  const generate = () => {
    generations += 1;
    return Promise.resolve(response());
  };

  const first = await moderateExploreAudioUrl(
    "https://media.merian.app/public_uploads/pro/clip.wav",
    cache,
    fetcher,
    generate,
    quota,
  );
  const second = await moderateExploreAudioUrl(
    "https://media.merian.app/public_uploads/pro/renamed.wav",
    cache,
    fetcher,
    generate,
    quota,
  );

  assertEquals(first.cacheHit, false);
  assertEquals(second.cacheHit, true);
  assertEquals(generations, 1);
  assertEquals(reservations, 2);
  assertEquals(commits, 1);
  assertEquals(refunds, 1);
  assertEquals(failures, 0);
  assertEquals(quotaInputs.length, 2);
  assertEquals(quotaInputs[0], quotaInputs[1]);
  assertEquals(quotaInputs[0].checksumSha256.length, 64);
  assertEquals(quotaInputs[0].policyVersion.length, 64);
  assertEquals(stores.length, 1);
  assertEquals(Object.keys(stores[0]).sort(), [
    "approved",
    "byteSize",
    "checksumSha256",
    "mediaType",
    "model",
    "policyVersion",
  ]);
  assertEquals((stores[0].checksumSha256 as string).length, 64);
});

Deno.test("audio moderation commits the database-selected model before a provider attempt", async () => {
  let committed = false;
  let refunds = 0;
  let failures = 0;
  let providerModel: string | undefined;
  const quota = {
    beforeProvider() {
      return Promise.resolve({
        reservation: { model: "gemini-2.5-pro" },
        commit() {
          committed = true;
          return Promise.resolve();
        },
        refund() {
          refunds += 1;
          return Promise.resolve(true);
        },
        fail() {
          failures += 1;
          return Promise.resolve(true);
        },
      });
    },
  };

  await assertRejects(
    () =>
      moderateExploreAudioUrl(
        "https://media.merian.app/public_uploads/pro/clip.wav",
        undefined,
        () =>
          Promise.resolve(
            new Response(new Uint8Array([1]), {
              headers: { "content-type": "audio/wav" },
            }),
          ),
        (_audio, _mime, model) => {
          assertEquals(committed, true);
          providerModel = model;
          return Promise.resolve("malformed");
        },
        quota,
      ),
    Error,
    "malformed JSON",
  );

  assertEquals(providerModel, "gemini-2.5-pro");
  assertEquals(refunds, 0);
  assertEquals(failures, 1);
});
