import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { PublicHttpError } from "../_shared/http.ts";
import {
  normalizeRestoredObjectKeys,
  restoredObjectKeysMissingDurableUrls,
} from "./restoredMediaValidation.ts";

const userId = "00000000-0000-0000-0000-000000000001";

function assertInvalidKeys(value: unknown): void {
  const error = assertThrows(
    () => normalizeRestoredObjectKeys(value, userId),
    PublicHttpError,
  );
  assertEquals(error.status, 400);
  assertEquals(error.code, "invalid_request");
}

Deno.test("restored media keys are trimmed, deduplicated, and owner scoped", () => {
  assertEquals(
    normalizeRestoredObjectKeys([
      ` staging/${userId}/image-1.webp `,
      `staging/${userId}/image-1.webp`,
      `staging/${userId}/image-2.webp`,
    ], userId.toUpperCase()),
    [
      `staging/${userId}/image-1.webp`,
      `staging/${userId}/image-2.webp`,
    ],
  );
});

Deno.test("restored media keys reject path traversal", () => {
  assertInvalidKeys([`staging/${userId}/../image.webp`]);
});

Deno.test("restored media keys reject nested or empty object names", () => {
  assertInvalidKeys([`staging/${userId}/scan/image.webp`]);
  assertInvalidKeys([`staging/${userId}/`]);
});

Deno.test("restored media keys reject another account", () => {
  assertInvalidKeys([
    "staging/00000000-0000-0000-0000-000000000002/image.webp",
  ]);
});

Deno.test("restored media keys reject non-array and non-string inputs", () => {
  assertInvalidKeys(`staging/${userId}/image.webp`);
  assertInvalidKeys([123]);
});

Deno.test("restored media keys enforce the route media budget", () => {
  assertInvalidKeys([
    `staging/${userId}/1.webp`,
    `staging/${userId}/2.webp`,
    `staging/${userId}/3.webp`,
    `staging/${userId}/4.webp`,
    `staging/${userId}/5.webp`,
    `staging/${userId}/6.webp`,
  ]);
});

Deno.test("restored media retry skips only its exact canonical durable owner URL", () => {
  const firstKey = `staging/${userId}/audio-1.wav`;
  const secondKey = `staging/${userId}/audio-2.wav`;
  assertEquals(
    restoredObjectKeysMissingDurableUrls(
      [firstKey, secondKey],
      [
        `https://media.merian.app/public_uploads/pro/${userId}/audio-1.wav`,
        "https://media.merian.app/public_uploads/pro/00000000-0000-0000-0000-000000000002/audio-2.wav",
        `https://other.example/public_uploads/pro/${userId}/audio-2.wav`,
      ],
      userId,
    ),
    [secondKey],
  );
});
