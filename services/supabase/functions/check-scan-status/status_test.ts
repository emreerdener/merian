import { assertEquals, assertStringIncludes, assertThrows } from "@std/assert";

import {
  capturedVideoCount,
  cleanMediaUrls,
  hasRequiredVideoMedia,
  normalizeRequiredVideoCount,
} from "./status.ts";

function compact(source: string): string {
  return source.replaceAll(/--.*$/gm, "").replaceAll(/\s+/g, " ").trim();
}

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

Deno.test("check-scan-status database failures remain explicit and retryable", async () => {
  const source = compact(
    await Deno.readTextFile(new URL("./index.ts", import.meta.url)),
  );

  assertStringIncludes(source, '"check_scan_status_bulk_failed"');
  assertStringIncludes(source, '"check_scan_status_failed"');
  assertStringIncludes(
    source,
    'throw publicHttpError( 503, "The service is temporarily unavailable.", "service_unavailable", 30, )',
  );
  assertEquals(
    source.match(
      /throw publicHttpError[(] 503, "The service is temporarily unavailable[.]"/g,
    )?.length,
    2,
    "Bulk and single-scan database failures must both preserve retry semantics.",
  );
});
