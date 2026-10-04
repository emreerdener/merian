import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { R2Config } from "../aws.ts";
import { evidenceDigest } from "./evidence.ts";
import {
  getPublicationPhotoConfig,
  type PublicationPhotoCopyTarget,
  publicationPhotoObjectKey,
  PublicHistoryPhotoStorage,
} from "./publicPhotoStorage.ts";
import {
  joined,
  jpegSegment,
  safeJpeg,
  safePng,
} from "./testing/publicPhotoFixtures.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const config = {
  endpoint: "https://r2.example.invalid",
  bucketName: "synthetic-public",
  s3Client: {} as R2Config["s3Client"],
};
async function target(
  bytes: Uint8Array,
  content_type = "image/png",
): Promise<PublicationPhotoCopyTarget> {
  return {
    object_id: id(1),
    source: {
      media_id: id(2),
      object_id: id(3),
      content_type,
      byte_count: bytes.length,
      sha256: await evidenceDigest(bytes),
    },
  };
}
function fixture() {
  const objects = new Map<string, { bytes: Uint8Array; headers: Headers }>(),
    calls: Request[] = [];
  let beforeConditional: (() => Promise<void>) | undefined;
  const storage = new PublicHistoryPhotoStorage(
    () => config,
    () => config,
    async (request) => {
      calls.push(request);
      const path = new URL(request.url).pathname;
      if (request.method === "PUT") {
        if (request.headers.has("If-None-Match")) {
          assertEquals(request.headers.get("If-None-Match"), "*");
          await beforeConditional?.();
          if (objects.has(path)) return new Response(null, { status: 412 });
        }
        objects.set(path, {
          bytes: new Uint8Array(await request.arrayBuffer()),
          headers: new Headers(request.headers),
        });
        return new Response(null, { status: 200 });
      }
      assertEquals(request.method, "HEAD");
      const saved = objects.get(path);
      return new Response(null, {
        status: saved ? 200 : 404,
        headers: saved?.headers,
      });
    },
  );
  return {
    storage,
    calls,
    objects,
    block: (barrier: () => Promise<void>) => beforeConditional = barrier,
  };
}
Deno.test("public photo writes exact approved bytes once without private identifiers or cacheability", async () => {
  const bytes = safePng(), receipt = await target(bytes), f = fixture();
  await f.storage.writeOnce(receipt, bytes);
  await f.storage.writeOnce(receipt, bytes);
  assertEquals(f.calls.map((r) => r.method), ["PUT", "HEAD", "PUT", "HEAD"]);
  const saved = [...f.objects.values()][0];
  assertEquals(saved.bytes, bytes);
  assertEquals(saved.headers.get("Cache-Control"), "no-store, max-age=0");
  assertEquals(
    [...saved.headers.keys()].filter((k) => k.startsWith("x-amz-meta-")),
    ["x-amz-meta-sha256"],
  );
  assert(
    !JSON.stringify([...saved.headers]).includes(receipt.source.object_id),
  );
  assert(!JSON.stringify([...saved.headers]).includes(receipt.source.media_id));
  assertEquals(
    new URL(f.calls[0].url).pathname,
    `/synthetic-public/publication_media/v1/${receipt.object_id}`,
  );
});
Deno.test("public photo rejects private metadata or changed content before public I/O", async () => {
  const jpeg = safeJpeg(),
    privateJpeg = joined(
      jpeg.slice(0, 2),
      jpegSegment(0xe1, [...new TextEncoder().encode("Exif\0\0synthetic")]),
      jpeg.slice(2),
    );
  const f = fixture();
  await assertRejects(
    () =>
      target(privateJpeg, "image/jpeg").then((r) =>
        f.storage.writeOnce(r, privateJpeg)
      ),
    Error,
    "publication_photo_not_sanitized",
  );
  const bytes = safePng(), receipt = await target(bytes);
  receipt.source.sha256 = "a".repeat(64);
  await assertRejects(
    () => f.storage.writeOnce(receipt, bytes),
    Error,
    "invalid_publication_photo_copy",
  );
  assertEquals(f.calls.length, 0);
});
Deno.test("public photo erasure before delayed upload permanently wins", async () => {
  const bytes = safePng(), receipt = await target(bytes), f = fixture();
  let entered!: () => void, release!: () => void;
  const arrived = new Promise<void>((resolve) => entered = resolve),
    barrier = new Promise<void>((resolve) => release = resolve);
  f.block(() => {
    entered();
    return barrier;
  });
  const pending = assertRejects(
    () => f.storage.writeOnce(receipt, bytes),
    Error,
    "publication_photo_verification_failed",
  );
  await arrived;
  await f.storage.erase(receipt.object_id);
  release();
  await pending;
  const saved = [...f.objects.values()][0];
  assertEquals(saved.bytes.length, 0);
  assertEquals(saved.headers.get("x-amz-meta-erased"), "true");
  assertEquals(saved.headers.has("x-amz-meta-sha256"), false);
  assertEquals(f.calls.some((r) => r.method === "DELETE"), false);
});
Deno.test("public photo erasure after completed write prevents replay and replaces metadata", async () => {
  const bytes = safePng(), receipt = await target(bytes), f = fixture();
  await f.storage.writeOnce(receipt, bytes);
  await f.storage.erase(receipt.object_id);
  await f.storage.erase(receipt.object_id);
  await assertRejects(
    () => f.storage.writeOnce(receipt, bytes),
    Error,
    "publication_photo_verification_failed",
  );
  const saved = [...f.objects.values()][0];
  assertEquals(saved.bytes.length, 0);
  assertEquals(saved.headers.get("Cache-Control"), "no-store, max-age=0");
  assertEquals(saved.headers.has("x-amz-meta-sha256"), false);
});
Deno.test("public copy HEAD rejects conflicting bytes, erased markers and missing cache directives", async (t) => {
  for (const mutation of ["digest", "length", "type", "cache", "erased"]) {
    await t.step(mutation, async () => {
      const bytes = safePng(), receipt = await target(bytes), f = fixture();
      await f.storage.writeOnce(receipt, bytes);
      const headers = [...f.objects.values()][0].headers;
      if (mutation === "digest") {
        headers.set("x-amz-meta-sha256", "b".repeat(64));
      }
      if (mutation === "length") headers.set("Content-Length", "1");
      if (mutation === "type") headers.set("Content-Type", "image/jpeg");
      if (mutation === "cache") headers.delete("Cache-Control");
      if (mutation === "erased") headers.set("x-amz-meta-erased", "true");
      await assertRejects(
        () => f.storage.writeOnce(receipt, bytes),
        Error,
        "publication_photo_verification_failed",
      );
    });
  }
});
Deno.test("public copy cannot reuse private identity or expose raw storage failures", async () => {
  const bytes = safePng(), receipt = await target(bytes), f = fixture();
  await assertRejects(
    () =>
      f.storage.writeOnce(
        { ...receipt, object_id: receipt.source.object_id },
        bytes,
      ),
    Error,
    "invalid_publication_photo_copy",
  );
  await assertRejects(
    () =>
      f.storage.writeOnce({
        ...receipt,
        source: {
          ...receipt.source,
          media_id: receipt.source.object_id,
        },
      }, bytes),
    Error,
    "invalid_publication_photo_copy",
  );
  assertEquals(f.calls.length, 0);
  const storage = new PublicHistoryPhotoStorage(
    () => config,
    () => config,
    () => {
      throw new Error("private request diagnostics");
    },
  );
  const error = await assertRejects(
    () => storage.writeOnce(receipt, bytes),
    Error,
    "publication_photo_storage_unavailable",
  );
  assertEquals(error.cause, undefined);
  assertThrows(() => publicationPhotoObjectKey("../private"));
});
Deno.test("public copy configuration requires dedicated read/write credentials and distinct private bucket", () => {
  const env: Record<string, string> = {
    R2_ACCOUNT_ID: "a".repeat(32),
    R2_BUCKET_NAME: "synthetic-public",
    R2_HISTORY_BUCKET_NAME: "synthetic-private",
    R2_ACCESS_KEY_ID: "generic-key",
    R2_SECRET_ACCESS_KEY: "generic-secret",
  };
  const read = (key: string) => env[key];
  assertThrows(
    () => getPublicationPhotoConfig("write", read),
    Error,
    "publication_photo_storage_unavailable",
  );
  env.R2_PUBLICATION_WRITE_ACCESS_KEY_ID = "synthetic-write";
  env.R2_PUBLICATION_WRITE_SECRET_ACCESS_KEY = "synthetic-write-secret";
  assertEquals(
    getPublicationPhotoConfig("write", read).bucketName,
    "synthetic-public",
  );
  assertThrows(
    () => getPublicationPhotoConfig("read", read),
    Error,
    "publication_photo_storage_unavailable",
  );
  env.R2_PUBLICATION_READ_ACCESS_KEY_ID = "synthetic-read";
  env.R2_PUBLICATION_READ_SECRET_ACCESS_KEY = "synthetic-read-secret";
  assertEquals(
    getPublicationPhotoConfig("read", read).bucketName,
    "synthetic-public",
  );
  env.R2_HISTORY_BUCKET_NAME = env.R2_BUCKET_NAME;
  assertThrows(
    () => getPublicationPhotoConfig("write", read),
    Error,
    "publication_photo_storage_unavailable",
  );
});

Deno.test("public copy resolves matching read credentials before any public write", async () => {
  const bytes = safePng(), receipt = await target(bytes);
  let calls = 0;
  for (
    const read of [() => {
      throw new Error("missing read config");
    }, () => ({ ...config, bucketName: "different" })]
  ) {
    const storage = new PublicHistoryPhotoStorage(() => config, read, () => {
      calls++;
      return Promise.resolve(new Response(null));
    });
    await assertRejects(() => storage.writeOnce(receipt, bytes));
  }
  assertEquals(calls, 0);
});

Deno.test("public copy credentials cannot alias generic, private or opposite-access identities", () => {
  const base: Record<string, string> = {
    R2_ACCOUNT_ID: "a".repeat(32),
    R2_BUCKET_NAME: "synthetic-public",
    R2_HISTORY_BUCKET_NAME: "synthetic-private",
    R2_PUBLICATION_WRITE_ACCESS_KEY_ID: "synthetic-write",
    R2_PUBLICATION_WRITE_SECRET_ACCESS_KEY: "synthetic-write-secret",
    R2_PUBLICATION_READ_ACCESS_KEY_ID: "synthetic-read",
    R2_PUBLICATION_READ_SECRET_ACCESS_KEY: "synthetic-read-secret",
  };
  for (const access of ["read", "write"] as const) {
    const own = `R2_PUBLICATION_${access.toUpperCase()}`;
    for (
      const prefix of [
        "R2",
        "R2_HISTORY_READ",
        "R2_HISTORY_WRITE",
        access === "read" ? "R2_PUBLICATION_WRITE" : "R2_PUBLICATION_READ",
      ]
    ) {
      for (const suffix of ["ACCESS_KEY_ID", "SECRET_ACCESS_KEY"]) {
        const env = {
          ...base,
          [`${prefix}_${suffix}`]: base[`${own}_${suffix}`],
        };
        assertThrows(
          () => getPublicationPhotoConfig(access, (key) => env[key]),
          Error,
          "publication_photo_storage_unavailable",
        );
      }
    }
  }
});
