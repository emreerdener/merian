import assert from "node:assert/strict";
import test from "node:test";
import { proxiedExploreAudioUrl, webAudioProxyPath } from "./audioProxy.ts";

test("accepts only canonical public Merian WAV recordings", () => {
  const valid = "https://media.merian.app/public_uploads/pro/user/clip.wav";
  assert.equal(proxiedExploreAudioUrl(valid)?.href, valid);
  assert.equal(webAudioProxyPath(valid), `/api/explore/audio?url=${encodeURIComponent(valid)}`);
});

test("rejects non-media hosts, private paths, and unsupported formats", () => {
  assert.equal(proxiedExploreAudioUrl("https://attacker.example/public_uploads/pro/a.wav"), null);
  assert.equal(proxiedExploreAudioUrl("https://media.merian.app/staging/user/a.wav"), null);
  assert.equal(proxiedExploreAudioUrl("https://media.merian.app/public_uploads/pro/a.m4a"), null);
});
