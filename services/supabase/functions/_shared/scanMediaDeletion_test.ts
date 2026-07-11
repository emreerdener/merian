import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { collectScanMediaUrls } from "./scanMediaDeletion.ts";

Deno.test("collectScanMediaUrls includes image, video, and standalone audio", () => {
  assertEquals(collectScanMediaUrls({
    image_storage_urls: ["https://media.merian.app/public_uploads/free/a.jpg"],
    video_storage_urls: ["https://media.merian.app/public_uploads/free/b.mp4"],
    audio_storage_urls: ["https://media.merian.app/public_uploads/free/c.wav"],
  }), [
    "https://media.merian.app/public_uploads/free/a.jpg",
    "https://media.merian.app/public_uploads/free/b.mp4",
    "https://media.merian.app/public_uploads/free/c.wav",
  ]);
});

Deno.test("collectScanMediaUrls ignores malformed and blank entries", () => {
  assertEquals(collectScanMediaUrls({
    image_storage_urls: null,
    video_storage_urls: ["", 42],
    audio_storage_urls: ["  https://media.merian.app/public_uploads/pro/a.wav  "],
  }), ["https://media.merian.app/public_uploads/pro/a.wav"]);
});
