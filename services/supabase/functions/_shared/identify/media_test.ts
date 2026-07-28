import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";

import { stagedImageSourceKeys, validateImageR2ObjectKeys } from "./media.ts";

async function responseError(
  response: Response | null,
): Promise<string | null> {
  if (!response) return null;
  const body = await response.json() as { error?: string };
  return body.error ?? null;
}

Deno.test("validateImageR2ObjectKeys allows destination keys when ownership is not required", () => {
  const response = validateImageR2ObjectKeys(
    ["staging/other-user/photo.webp"],
    "user-1",
    {
      enforceOwnership: false,
      idorEvent: "test/image_idor_attempt",
    },
  );

  assertEquals(response, null);
});

Deno.test("validateImageR2ObjectKeys rejects path traversal even for destination-only keys", async () => {
  const response = validateImageR2ObjectKeys(
    ["staging/user-1/../photo.webp"],
    "user-1",
    {
      enforceOwnership: false,
      idorEvent: "test/image_idor_attempt",
    },
  );

  assertEquals(response?.status, 400);
  assertEquals(
    await responseError(response),
    "Bad Request: Path traversal detected.",
  );
});

Deno.test("validateImageR2ObjectKeys rejects wrong-user staged source keys", async () => {
  const response = validateImageR2ObjectKeys(
    ["staging/other-user/photo.webp"],
    "user-1",
    {
      enforceOwnership: true,
      idorEvent: "test/image_idor_attempt",
    },
  );

  assertEquals(response?.status, 403);
  assertEquals(
    await responseError(response),
    "Forbidden: r2ObjectKey does not belong to the requesting user.",
  );
});

Deno.test("stagedImageSourceKeys excludes destination hints for inline images", () => {
  assertEquals(
    stagedImageSourceKeys(
      ["staging/legacy-device-id/photo.webp"],
      ["inline-image-bytes"],
    ),
    [],
  );
});

Deno.test("stagedImageSourceKeys preserves actual staged image sources", () => {
  const sourceKeys = ["staging/user-1/photo.webp"];
  assertEquals(stagedImageSourceKeys(sourceKeys, []), sourceKeys);
  assertEquals(stagedImageSourceKeys(sourceKeys, undefined), sourceKeys);
});
