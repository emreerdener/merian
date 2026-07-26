import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

import { parseDurableObjectKeys } from "./validation.ts";

const OWNER = "00000000-0000-4000-8000-000000000701";

Deno.test("parseDurableObjectKeys accepts and deduplicates direct durable keys", () => {
  assertEquals(
    parseDurableObjectKeys([
      `public_uploads/free/${OWNER}/one.webp`,
      `public_uploads/free/${OWNER}/one.webp`,
      `public_uploads/pro/${OWNER}/repair_two.webp`,
    ]),
    [
      `public_uploads/free/${OWNER}/one.webp`,
      `public_uploads/pro/${OWNER}/repair_two.webp`,
    ],
  );
});

Deno.test("parseDurableObjectKeys rejects temporary, nested, traversal, and malformed owner keys", () => {
  for (
    const key of [
      `staging/${OWNER}/one.webp`,
      `public_uploads/free/${OWNER}/nested/one.webp`,
      `public_uploads/free/${OWNER}/../one.webp`,
      "public_uploads/free/not-a-uuid/one.webp",
      `public_uploads/free/${OWNER}/one%2Ftwo.webp`,
    ]
  ) {
    assertEquals(parseDurableObjectKeys([key]), null);
  }
});

Deno.test("parseDurableObjectKeys enforces bounded non-empty batches", () => {
  assertEquals(parseDurableObjectKeys([]), null);
  assertEquals(
    parseDurableObjectKeys(
      Array.from(
        { length: 101 },
        (_, index) => `public_uploads/free/${OWNER}/${index}.webp`,
      ),
    ),
    null,
  );
});
