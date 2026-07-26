import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  normalizeRestoredObjectKey,
  normalizeSourceUrl,
} from "./validation.ts";

const userId = "4c600000-0000-4000-8000-000000000001";

Deno.test("repair source validation accepts only exact durable scan URLs", () => {
  assertEquals(
    normalizeSourceUrl(
      `https://media.merian.app/public_uploads/pro/${userId}/scan_image.webp`,
    ),
    `https://media.merian.app/public_uploads/pro/${userId}/scan_image.webp`,
  );

  for (
    const value of [
      "https://example.com/image.webp",
      `https://media.merian.app/avatars/${userId}/image.webp`,
      `https://media.merian.app/public_uploads/free/${userId}/nested/image.webp`,
      `https://media.merian.app/public_uploads/free/${userId}/image.webp?x=1`,
    ]
  ) {
    assertThrows(() => normalizeSourceUrl(value));
  }
});

Deno.test("repair staging validation requires an owned image basename", () => {
  assertEquals(
    normalizeRestoredObjectKey(
      `staging/${userId}/repair_123.webp`,
      userId,
    ),
    `staging/${userId}/repair_123.webp`,
  );
  assertEquals(normalizeRestoredObjectKey(null, userId), null);

  for (
    const value of [
      `staging/other-user/repair.webp`,
      `staging/${userId}/nested/repair.webp`,
      `staging/${userId}/../repair.webp`,
      `staging/${userId}/repair.mp4`,
    ]
  ) {
    assertThrows(() => normalizeRestoredObjectKey(value, userId));
  }
});
