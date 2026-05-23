import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { deleteR2Objects, type R2Config } from "./aws.ts";

Deno.test("deleteR2Objects caps in-flight deletes and rewrites public media URLs", async () => {
  let inFlight = 0;
  let maxInFlight = 0;
  const deletedUrls: string[] = [];

  const config = {
    bucketName: "media-bucket",
    endpoint: "https://account.r2.cloudflarestorage.com",
    s3Client: {
      async fetch(url: string) {
        inFlight += 1;
        maxInFlight = Math.max(maxInFlight, inFlight);
        deletedUrls.push(url);
        await new Promise((resolve) => setTimeout(resolve, 5));
        inFlight -= 1;
        return new Response(null, { status: 204 });
      },
    },
  } as unknown as R2Config;

  const urls = Array.from(
    { length: 40 },
    (_, index) => `https://media.merian.app/public_uploads/free/${index}.webp`,
  );

  const originalLog = console.log;
  console.log = () => {};
  try {
    await deleteR2Objects(urls, config);
  } finally {
    console.log = originalLog;
  }

  assertEquals(maxInFlight, 16);
  assertEquals(deletedUrls.length, urls.length);
  assertEquals(
    deletedUrls[0],
    "https://account.r2.cloudflarestorage.com/media-bucket/public_uploads/free/0.webp",
  );
});
