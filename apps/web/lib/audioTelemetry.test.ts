import assert from "node:assert/strict";
import test from "node:test";
import { captureAudioTelemetry, markAudioPlaybackStarted } from "./audioTelemetry.ts";

test("playback starts are deduplicated per rendered clip", () => {
  const started = new Set<string>();
  assert.equal(markAudioPlaybackStarted(started, "clip-a"), true);
  assert.equal(markAudioPlaybackStarted(started, "clip-a"), false);
  assert.equal(markAudioPlaybackStarted(started, "clip-b"), true);
});

test("playback telemetry sends only the privacy-safe contract", async () => {
  const requests: Array<{ url: string; init?: RequestInit }> = [];
  const captured = captureAudioTelemetry("ExploreAudioPlaybackStarted", "detail_audio_header", {
    apiKey: "public-test-key",
    getDistinctId: () => "anonymous-test-id",
    fetcher: ((url: string | URL | Request, init?: RequestInit) => {
      requests.push({ url: String(url), init });
      return Promise.resolve(new Response(null, { status: 200 }));
    }) as typeof fetch,
  });

  assert.equal(captured, true);
  assert.equal(requests.length, 1);
  const payload = JSON.parse(String(requests[0].init?.body));
  assert.deepEqual(payload, {
    api_key: "public-test-key",
    event: "ExploreAudioPlaybackStarted",
    distinct_id: "anonymous-test-id",
    properties: {
      event_source: "public_web",
      surface: "detail_audio_header",
    },
  });
  for (const forbidden of ["url", "transcript", "filename", "post_id", "species", "location"]) {
    assert.equal(JSON.stringify(payload).includes(forbidden), false);
  }
});

test("playback telemetry is disabled without a public key", () => {
  let calls = 0;
  const captured = captureAudioTelemetry("ExploreAudioPlaybackFailed", "detail_mixed_media", {
    getDistinctId: () => "unused",
    fetcher: (() => {
      calls += 1;
      return Promise.resolve(new Response());
    }) as typeof fetch,
  });
  assert.equal(captured, false);
  assert.equal(calls, 0);
});
