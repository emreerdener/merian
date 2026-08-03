import { assertEquals } from "@std/assert";
import { isFlashFallbackEligible } from "./complimentaryScans.ts";

Deno.test("Flash fallback accepts every supported single-evidence capture", () => {
  for (
    const shape of [
      { imageCount: 1, audioCount: 0, descriptionCount: 0, videoCount: 0 },
      { imageCount: 0, audioCount: 1, descriptionCount: 0, videoCount: 0 },
      { imageCount: 0, audioCount: 0, descriptionCount: 1, videoCount: 0 },
    ]
  ) {
    assertEquals(isFlashFallbackEligible(shape), true);
  }
});

Deno.test("Flash fallback rejects video, mixed, multi-item, empty, and malformed evidence", () => {
  for (
    const shape of [
      { imageCount: 0, audioCount: 0, descriptionCount: 0, videoCount: 1 },
      { imageCount: 1, audioCount: 1, descriptionCount: 0, videoCount: 0 },
      { imageCount: 2, audioCount: 0, descriptionCount: 0, videoCount: 0 },
      { imageCount: 0, audioCount: 0, descriptionCount: 0, videoCount: 0 },
      { imageCount: -1, audioCount: 0, descriptionCount: 0, videoCount: 0 },
    ]
  ) {
    assertEquals(isFlashFallbackEligible(shape), false);
  }
});
