import { assertEquals, assertRejects } from "@std/assert";
import r2Lifecycle from "../../../../docs/r2-lifecycle.json" with {
  type: "json",
};
import {
  avatarR2KeyFromPublicUrl,
  deleteR2ObjectIfPresent,
  deleteR2Objects,
  deleteScanMediaR2Objects,
  generatePresignedPutUrl,
  getS3Client,
  isOwnedScanMediaR2Url,
  isScanMediaR2Url,
  listR2ObjectKeys,
  R2_MEDIA_PREFIXES,
  type R2Config,
  r2RequestWithDeadline,
} from "./aws.ts";

Deno.test("presigned PUTs bind the exact content length and content type", async () => {
  const config: R2Config = {
    bucketName: "media-bucket",
    endpoint: "https://account.r2.cloudflarestorage.com",
    s3Client: getS3Client("test-access-key", "test-secret-key"),
  };

  const signedUrl = await generatePresignedPutUrl(
    config,
    "staging/user/scan.webp",
    86_400,
    "image/webp",
    12_345,
  );
  const signed = new URL(signedUrl);

  assertEquals(signed.searchParams.get("X-Amz-Expires"), "86400");
  assertEquals(
    signed.searchParams.get("X-Amz-SignedHeaders"),
    "content-length;content-type;host",
  );
});

Deno.test("presigned PUTs reject unknown or unsafe content lengths", async () => {
  const config: R2Config = {
    bucketName: "media-bucket",
    endpoint: "https://account.r2.cloudflarestorage.com",
    s3Client: getS3Client("test-access-key", "test-secret-key"),
  };

  await assertRejects(
    () =>
      generatePresignedPutUrl(
        config,
        "staging/user/scan.webp",
        86_400,
        "image/webp",
        0,
      ),
    Error,
    "positive, safe content length",
  );
});

Deno.test("R2 requests preserve caller cancellation and enforce a deadline", async () => {
  const callerController = new AbortController();
  const request = r2RequestWithDeadline(
    "https://account.r2.cloudflarestorage.com/media-bucket/object",
    { signal: callerController.signal },
    5,
  );

  await new Promise((resolve) =>
    request.signal.addEventListener("abort", resolve, { once: true })
  );
  assertEquals(request.signal.aborted, true);
  assertEquals(callerController.signal.aborted, false);
});

Deno.test("listR2ObjectKeys performs a bounded monotonic prefix query", async () => {
  let requestedUrl = "";
  const config = {
    bucketName: "media-bucket",
    endpoint: "https://account.r2.cloudflarestorage.com",
    s3Client: {
      fetch(request: Request) {
        requestedUrl = request.url;
        return Promise.resolve(
          new Response(
            "<ListBucketResult>" +
              "<IsTruncated>false</IsTruncated>" +
              "<Contents><Key>staging%2Fuser%2Fa.webp</Key></Contents>" +
              "<Contents><Key>staging%2Fuser%2Fb.webp</Key></Contents>" +
              "</ListBucketResult>",
            { status: 200 },
          ),
        );
      },
    },
  } as unknown as R2Config;

  const page = await listR2ObjectKeys(
    "staging/user/",
    null,
    config,
    50,
  );

  assertEquals(page, {
    keys: ["staging/user/a.webp", "staging/user/b.webp"],
    isTruncated: false,
  });
  const url = new URL(requestedUrl);
  assertEquals(url.searchParams.get("list-type"), "2");
  assertEquals(url.searchParams.get("max-keys"), "50");
  assertEquals(url.searchParams.get("prefix"), "staging/user/");
});

Deno.test("listR2ObjectKeys rejects provider keys outside the leased prefix", async () => {
  const config = {
    bucketName: "media-bucket",
    endpoint: "https://account.r2.cloudflarestorage.com",
    s3Client: {
      fetch() {
        return Promise.resolve(
          new Response(
            "<ListBucketResult><IsTruncated>false</IsTruncated>" +
              "<Contents><Key>staging%2Fother%2Fa.webp</Key></Contents>" +
              "</ListBucketResult>",
            { status: 200 },
          ),
        );
      },
    },
  } as unknown as R2Config;

  await assertRejects(
    () => listR2ObjectKeys("staging/user/", null, config, 50),
    Error,
    "invalid cursor ordering",
  );
});

Deno.test("deleteR2Objects caps in-flight deletes and rewrites public media URLs", async () => {
  let inFlight = 0;
  let maxInFlight = 0;
  const deletedUrls: string[] = [];

  const config = {
    bucketName: "media-bucket",
    endpoint: "https://account.r2.cloudflarestorage.com",
    s3Client: {
      async fetch(request: Request | string) {
        inFlight += 1;
        maxInFlight = Math.max(maxInFlight, inFlight);
        const url = request instanceof Request ? request.url : request;
        deletedUrls.push(url);
        assertEquals(
          request instanceof Request ? request.method : "DELETE",
          "DELETE",
        );
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

Deno.test("scan media ownership requires the exact canonical owner path", () => {
  const owner = "00000000-0000-4000-8000-000000000201";
  assertEquals(
    isOwnedScanMediaR2Url(
      `https://media.merian.app/public_uploads/free/${owner}/photo.webp`,
      owner,
    ),
    true,
  );
  assertEquals(
    isOwnedScanMediaR2Url(
      `https://media.merian.app/public_uploads/pro/${owner}/spectrogram-v1-a.png`,
      owner,
    ),
    true,
  );
  for (
    const url of [
      "https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-000000000999/photo.webp",
      `https://media.merian.app/public_uploads/free/${owner}/nested/photo.webp`,
      `https://media.merian.app/public_uploads/free/${owner}/../photo.webp`,
      `https://media.merian.app/public_uploads/free/${owner}/photo.webp?version=1`,
      `http://media.merian.app/public_uploads/free/${owner}/photo.webp`,
    ]
  ) {
    assertEquals(isOwnedScanMediaR2Url(url, owner), false);
  }
});

Deno.test("deleteScanMediaR2Objects skips foreign and non-scan objects", async () => {
  const deletedUrls: string[] = [];
  const owner = "00000000-0000-4000-8000-000000000201";

  const config = {
    bucketName: "media-bucket",
    endpoint: "https://account.r2.cloudflarestorage.com",
    s3Client: {
      fetch(request: Request | string) {
        const url = request instanceof Request ? request.url : request;
        deletedUrls.push(url);
        assertEquals(
          request instanceof Request ? request.method : "DELETE",
          "DELETE",
        );
        return Promise.resolve(new Response(null, { status: 204 }));
      },
    },
  } as unknown as R2Config;

  const originalWarn = console.warn;
  console.warn = () => {};
  try {
    await deleteScanMediaR2Objects(
      [
        `https://media.merian.app/public_uploads/free/${owner}/photo.webp`,
        "https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-000000000999/victim.webp",
        `https://media.merian.app/avatars/${owner}/avatar.webp`,
        `https://media.merian.app/staging/${owner}/temp.webp`,
      ],
      owner,
      config,
    );
  } finally {
    console.warn = originalWarn;
  }

  assertEquals(deletedUrls, [
    `https://account.r2.cloudflarestorage.com/media-bucket/public_uploads/free/${owner}/photo.webp`,
  ]);
});

Deno.test("deleteR2Objects rejects when Cloudflare does not confirm deletion", async () => {
  const config = {
    bucketName: "media-bucket",
    endpoint: "https://account.r2.cloudflarestorage.com",
    s3Client: {
      fetch() {
        return Promise.resolve(new Response(null, { status: 503 }));
      },
    },
  } as unknown as R2Config;

  const originalError = console.error;
  console.error = () => {};
  try {
    await assertRejects(
      () =>
        deleteR2Objects([
          "https://media.merian.app/public_uploads/free/audio.wav",
        ], config),
      AggregateError,
      "Failed to delete 1/1 R2 object(s)",
    );
  } finally {
    console.error = originalError;
  }
});

Deno.test("deleteR2Objects treats an already absent object as success", async () => {
  const config = {
    bucketName: "media-bucket",
    endpoint: "https://account.r2.cloudflarestorage.com",
    s3Client: {
      fetch() {
        return Promise.resolve(new Response(null, { status: 404 }));
      },
    },
  } as unknown as R2Config;

  await deleteR2Objects([
    "https://media.merian.app/public_uploads/free/already-gone.webp",
  ], config);
});

Deno.test("deleteR2ObjectIfPresent accepts absence but rejects provider failures", async () => {
  let status = 404;
  const config = {
    bucketName: "media-bucket",
    endpoint: "https://account.r2.cloudflarestorage.com",
    s3Client: {
      fetch() {
        return Promise.resolve(new Response(null, { status }));
      },
    },
  } as unknown as R2Config;

  await deleteR2ObjectIfPresent("public_uploads/pro/user/audio.wav", config);

  status = 503;
  await assertRejects(
    () =>
      deleteR2ObjectIfPresent(
        "public_uploads/pro/user/audio.wav",
        config,
      ),
    Error,
    "R2 object deletion failed with HTTP 503",
  );
});

Deno.test("R2 prefix helpers classify scan media separately from avatars", () => {
  assertEquals(
    isScanMediaR2Url("https://media.merian.app/public_uploads/pro/u/one.webp"),
    true,
  );
  assertEquals(
    isScanMediaR2Url("https://media.merian.app/avatars/u/avatar.webp"),
    false,
  );
  assertEquals(
    avatarR2KeyFromPublicUrl(
      "https://media.merian.app/avatars/user-1/avatar.webp",
      "user-1",
    ),
    "avatars/user-1/avatar.webp",
  );
  assertEquals(
    avatarR2KeyFromPublicUrl(
      "https://media.merian.app/avatars/user-2/avatar.webp",
      "user-1",
    ),
    null,
  );
});

Deno.test("R2 lifecycle contract does not expire durable media objects", () => {
  const rules = (r2Lifecycle as {
    Rules: Array<{
      Status: string;
      Filter?: { Prefix?: string };
      AbortIncompleteMultipartUpload?: { DaysAfterInitiation?: number };
    }>;
  }).Rules;
  const expiringPrefixes = rules
    .filter((rule) => rule.Status === "Enabled")
    .map((rule) => rule.Filter?.Prefix)
    .filter(Boolean);

  assertEquals(expiringPrefixes.includes(R2_MEDIA_PREFIXES.avatars), false);
  for (const durablePrefix of R2_MEDIA_PREFIXES.scanMedia) {
    assertEquals(expiringPrefixes.includes(durablePrefix), false);
  }

  const multipartAbortRules = rules.filter((rule) =>
    rule.Status === "Enabled" &&
    rule.AbortIncompleteMultipartUpload?.DaysAfterInitiation === 7
  );
  assertEquals(multipartAbortRules.length, 1);
  assertEquals(multipartAbortRules[0].Filter?.Prefix, undefined);
});
