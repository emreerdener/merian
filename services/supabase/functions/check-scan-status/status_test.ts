import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  capturedVideoCount,
  cleanMediaUrls,
  hasRequiredVideoMedia,
  normalizeRequiredVideoCount,
} from "./status.ts";

Deno.test("check-scan-status media completeness rejects frame-only video rows", () => {
  assertEquals(
    hasRequiredVideoMedia({
      video_storage_urls: [],
      captured_media: [{ image: { path: "frame-1.webp" } }],
      media_assets: [],
    }, 1),
    false,
  );

  assertEquals(
    hasRequiredVideoMedia({
      video_storage_urls: ["https://media.example/video.mp4"],
      captured_media: [{ image: { path: "frame-1.webp" } }],
      media_assets: [],
    }, 1),
    false,
  );
});

Deno.test("check-scan-status media completeness accepts manifest or asset video entries", () => {
  assertEquals(
    hasRequiredVideoMedia({
      video_storage_urls: [" https://media.example/video.mp4 "],
      captured_media: [{ video: { path: "https://media.example/video.mp4" } }],
      media_assets: [],
    }, 1),
    true,
  );

  assertEquals(
    hasRequiredVideoMedia({
      video_storage_urls: ["https://media.example/video.mp4"],
      captured_media: [],
      media_assets: [{
        kind: "video",
        role: "playback",
        status: "ready",
        url: "https://media.example/video.mp4",
        order_index: 0,
      }],
    }, 1),
    true,
  );
});

Deno.test("check-scan-status media helpers normalize counts and urls", () => {
  assertEquals(normalizeRequiredVideoCount(null), 0);
  assertEquals(normalizeRequiredVideoCount(2), 2);
  assertThrows(
    () => normalizeRequiredVideoCount(-1),
    Error,
    "required_video_count must be a non-negative integer.",
  );
  assertEquals(cleanMediaUrls([" a ", "", 1, "b"]), ["a", "b"]);
  assertEquals(capturedVideoCount([{ video: {} }, { image: {} }, null]), 1);
});
