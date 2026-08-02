import { assertEquals } from "@std/assert";
import {
  filterAllowedExternalImageURLs,
  isAllowedExternalImageURL,
  isSuppressedExternalImageURL,
} from "./externalImagePolicy.ts";

const BLOCKED_ORIGINAL =
  "https://inaturalist-open-data.s3.amazonaws.com/photos/605615444/original.jpg";

Deno.test("external image policy suppresses every variant of the targeted media", () => {
  assertEquals(isSuppressedExternalImageURL(BLOCKED_ORIGINAL), true);
  assertEquals(
    isSuppressedExternalImageURL(
      "https://INATURALIST-OPEN-DATA.S3.AMAZONAWS.COM/photos/605615444/medium.jpg?size=500#preview",
    ),
    true,
  );
  assertEquals(
    isAllowedExternalImageURL(
      "https://inaturalist-open-data.s3.amazonaws.com/photos/605615445/original.jpg",
    ),
    true,
  );
});

Deno.test("external image policy removes only the targeted media and preserves order", () => {
  const safeFirst = "https://upload.wikimedia.org/wildcat.jpg";
  const safeSecond =
    "https://live.staticflickr.com/65535/55027456166_642323e641_b.jpg";

  assertEquals(
    filterAllowedExternalImageURLs([
      ` ${BLOCKED_ORIGINAL} `,
      safeFirst,
      safeSecond,
    ]),
    [safeFirst, safeSecond],
  );
});
