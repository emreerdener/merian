import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import { promoteSafeMedia } from "./moderation.ts";

function makeR2Config() {
  return {
    bucketName: "media-bucket",
    endpoint: "https://r2.example.com",
    s3Client: {
      sign(request: Request) {
        return Promise.resolve(request);
      },
    },
  } as ReturnType<typeof import("../aws.ts").getR2Config>;
}

Deno.test("promoteSafeMedia rolls back already promoted staging images when a later copy fails", async () => {
  const deletedKeys: string[] = [];

  await assertRejects(
    () =>
      promoteSafeMedia(
        {
          userId: "user-123",
          r2ObjectKeys: [
            "staging/user-123/first.webp",
            "staging/user-123/second.webp",
          ],
          imageBase64s: [],
          userTier: "pro",
          r2Config: makeR2Config(),
        },
        {
          copyObject: (sourceKey) =>
            Promise.resolve(
              new Response(null, {
                status: sourceKey.endsWith("first.webp") ? 200 : 500,
              }),
            ),
          deleteObject: (key) => {
            deletedKeys.push(key);
            return Promise.resolve(new Response(null, { status: 204 }));
          },
        },
      ),
    Error,
    "Failed to promote staging image to public storage",
  );

  assertEquals(deletedKeys, [
    "staging/user-123/first.webp",
    "public_uploads/pro/user-123/first.webp",
  ]);
});

Deno.test("promoteSafeMedia rolls back already uploaded base64 images when a later upload fails", async () => {
  const deletedKeys: string[] = [];
  let uploadCount = 0;

  await assertRejects(
    () =>
      promoteSafeMedia(
        {
          userId: "user-456",
          r2ObjectKeys: [
            "staging/user-456/first.webp",
            "staging/user-456/second.webp",
          ],
          imageBase64s: ["Zmlyc3Q=", "c2Vjb25k"],
          userTier: "free",
          r2Config: makeR2Config(),
        },
        {
          fetchImpl: () => {
            uploadCount += 1;
            if (uploadCount === 1) {
              return Promise.resolve(new Response(null, { status: 200 }));
            }
            return Promise.resolve(
              new Response(null, { status: 500, statusText: "boom" }),
            );
          },
          deleteObject: (key) => {
            deletedKeys.push(key);
            return Promise.resolve(new Response(null, { status: 204 }));
          },
        },
      ),
    Error,
    "Failed to upload base64 image to R2",
  );

  assertEquals(deletedKeys, [
    "public_uploads/free/user-456/first.webp",
  ]);
});

Deno.test("promoteSafeMedia returns public URLs for a successful staging promotion batch", async () => {
  const deletedKeys: string[] = [];

  const publicUrls = await promoteSafeMedia(
    {
      userId: "user-789",
      r2ObjectKeys: [
        "staging/user-789/first.webp",
        "staging/user-789/second.webp",
      ],
      imageBase64s: [],
      userTier: "pro",
      r2Config: makeR2Config(),
    },
    {
      copyObject: () => Promise.resolve(new Response(null, { status: 200 })),
      deleteObject: (key) => {
        deletedKeys.push(key);
        return Promise.resolve(new Response(null, { status: 204 }));
      },
    },
  );

  assertEquals(publicUrls, [
    "https://media.merian.app/public_uploads/pro/user-789/first.webp",
    "https://media.merian.app/public_uploads/pro/user-789/second.webp",
  ]);
  assertEquals(deletedKeys, [
    "staging/user-789/first.webp",
    "staging/user-789/second.webp",
  ]);
});
