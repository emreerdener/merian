import { assertEquals } from "@std/assert";
import { collectScanMediaUrls } from "./scanMediaDeletion.ts";

Deno.test("collectScanMediaUrls includes source media and derived thumbnails", () => {
  assertEquals(
    collectScanMediaUrls({
      image_storage_urls: [
        "https://media.merian.app/public_uploads/free/a.jpg",
      ],
      video_storage_urls: [
        "https://media.merian.app/public_uploads/free/b.mp4",
      ],
      audio_storage_urls: [
        "https://media.merian.app/public_uploads/free/c.wav",
      ],
      derived_media_urls: [
        "https://media.merian.app/public_uploads/free/spectrogram.png",
      ],
    }),
    [
      "https://media.merian.app/public_uploads/free/a.jpg",
      "https://media.merian.app/public_uploads/free/b.mp4",
      "https://media.merian.app/public_uploads/free/c.wav",
      "https://media.merian.app/public_uploads/free/spectrogram.png",
    ],
  );
});

Deno.test("collectScanMediaUrls ignores malformed and blank entries", () => {
  assertEquals(
    collectScanMediaUrls({
      image_storage_urls: null,
      video_storage_urls: ["", 42],
      audio_storage_urls: [
        "  https://media.merian.app/public_uploads/pro/a.wav  ",
      ],
    }),
    ["https://media.merian.app/public_uploads/pro/a.wav"],
  );
});
