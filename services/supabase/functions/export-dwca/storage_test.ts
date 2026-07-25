import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { R2Config } from "../_shared/aws.ts";
import {
  fetchExportWorkChunk,
  fixedSizeParts,
  MAXIMUM_WORK_CHUNK_BYTES,
  putExportWorkChunk,
  uploadDwcaArchive,
} from "./storage.ts";
import { ExportWorkerError } from "./types.ts";
import { readableStreamFromAsyncIterable } from "./zip.ts";

async function* byteChunks(
  chunks: number[][],
): AsyncGenerator<Uint8Array> {
  for (const chunk of chunks) yield new Uint8Array(chunk);
}

Deno.test("fixedSizeParts bounds memory independently of source chunks", async () => {
  const stream = readableStreamFromAsyncIterable(
    byteChunks([[1, 2, 3], [4, 5, 6, 7, 8], [9]]),
  );
  const parts: number[][] = [];
  for await (const part of fixedSizeParts(stream, 4)) {
    parts.push([...part]);
  }
  assertEquals(parts, [[1, 2, 3, 4], [5, 6, 7, 8], [9]]);
});

function fakeR2Config(options: {
  completeBody?: string;
  createBody?: string;
  failPart?: boolean;
  getBody?: Uint8Array;
  getDeclaredLength?: number;
  requests: Array<{ method: string; url: string; bytes: number }>;
}): R2Config {
  const client = {
    async fetch(request: Request): Promise<Response> {
      const url = new URL(request.url);
      const bodyBytes = request.body
        ? (await request.arrayBuffer()).byteLength
        : 0;
      options.requests.push({
        method: request.method,
        url: request.url,
        bytes: bodyBytes,
      });

      if (request.method === "POST" && url.searchParams.has("uploads")) {
        return new Response(
          options.createBody ??
            "<InitiateMultipartUploadResult><UploadId>upload-1</UploadId></InitiateMultipartUploadResult>",
        );
      }
      if (request.method === "PUT") {
        if (options.failPart) {
          return new Response("part failed", { status: 503 });
        }
        return new Response(null, { headers: { etag: '"etag-1"' } });
      }
      if (request.method === "POST" && url.searchParams.has("uploadId")) {
        return new Response(
          options.completeBody ?? "<CompleteMultipartUploadResult/>",
        );
      }
      if (request.method === "DELETE") {
        return new Response(null, { status: 204 });
      }
      if (request.method === "GET" && options.getBody) {
        return new Response(options.getBody as unknown as BodyInit, {
          headers: {
            "Content-Length": String(
              options.getDeclaredLength ?? options.getBody.byteLength,
            ),
          },
        });
      }
      throw new Error(`Unexpected request: ${request.method} ${request.url}`);
    },
    sign(request: Request): Promise<Request> {
      const url = new URL(request.url);
      url.searchParams.set("signed", "true");
      return Promise.resolve(new Request(url, request));
    },
  };

  return {
    bucketName: "exports-test",
    endpoint: "https://account.r2.cloudflarestorage.com",
    s3Client: client,
  } as unknown as R2Config;
}

Deno.test("multipart upload streams, completes, and signs one attempt key", async () => {
  const requests: Array<{ method: string; url: string; bytes: number }> = [];
  const archive = readableStreamFromAsyncIterable(
    byteChunks([[1, 2], [3, 4, 5]]),
  );
  const result = await uploadDwcaArchive(
    archive,
    "exports/user/job.zip",
    () => {},
    fakeR2Config({ requests }),
  );

  assertEquals(result.objectKey, "exports/user/job.zip");
  assertEquals(result.uploadedBytes, 5);
  assertEquals(result.uploadedParts, 1);
  assert(new URL(result.signedUrl).searchParams.has("signed"));
  assertEquals(requests.map((request) => request.method), [
    "POST",
    "PUT",
    "POST",
  ]);
  assertEquals(requests[1].bytes, 5);
});

Deno.test("multipart upload aborts an incomplete upload on failure", async () => {
  const requests: Array<{ method: string; url: string; bytes: number }> = [];
  const error = await assertRejects(
    () =>
      uploadDwcaArchive(
        readableStreamFromAsyncIterable(byteChunks([[1, 2, 3]])),
        "exports/user/job.zip",
        () => {},
        fakeR2Config({ failPart: true, requests }),
      ),
    ExportWorkerError,
  );

  assertEquals(error.code, "storage_unavailable");
  assertEquals(requests.at(-1)?.method, "DELETE");
});

Deno.test("multipart upload rejects an embedded completion error in HTTP 200", async () => {
  const requests: Array<{ method: string; url: string; bytes: number }> = [];
  const error = await assertRejects(
    () =>
      uploadDwcaArchive(
        readableStreamFromAsyncIterable(byteChunks([[1, 2, 3]])),
        "exports/user/job.zip",
        () => {},
        fakeR2Config({
          completeBody: "<CompleteMultipartUploadResult/><Error/>",
          requests,
        }),
      ),
    ExportWorkerError,
  );

  assertEquals(error.code, "storage_unavailable");
  assertEquals(requests.at(-1)?.method, "DELETE");
});

Deno.test("multipart upload caps provider XML before parsing", async () => {
  const requests: Array<{ method: string; url: string; bytes: number }> = [];
  const error = await assertRejects(
    () =>
      uploadDwcaArchive(
        readableStreamFromAsyncIterable(byteChunks([[1, 2, 3]])),
        "exports/user/job.zip",
        () => {},
        fakeR2Config({
          createBody: `<InitiateMultipartUploadResult><UploadId>${
            "x".repeat(70 * 1024)
          }</UploadId></InitiateMultipartUploadResult>`,
          requests,
        }),
      ),
    ExportWorkerError,
  );

  assertEquals(error.code, "storage_unavailable");
  assertEquals(requests.map((request) => request.method), ["POST"]);
});

Deno.test("multipart upload enforces the canonical byte budget before PUT", async () => {
  const requests: Array<{ method: string; url: string; bytes: number }> = [];
  const error = await assertRejects(
    () =>
      uploadDwcaArchive(
        readableStreamFromAsyncIterable(byteChunks([[1, 2, 3]])),
        "exports/user/job.zip",
        () => {},
        fakeR2Config({ requests }),
        2,
      ),
    ExportWorkerError,
  );

  assertEquals(error.code, "export_too_large");
  assertEquals(requests.map((request) => request.method), ["POST", "DELETE"]);
});

Deno.test("prepared work chunks enforce their hard byte limit before PUT", async () => {
  const requests: Array<{ method: string; url: string; bytes: number }> = [];
  const error = await assertRejects(
    () =>
      putExportWorkChunk(
        new Uint8Array(MAXIMUM_WORK_CHUNK_BYTES + 1),
        "exports/user/job/work/occurrence/00000000.csv",
        fakeR2Config({ requests }),
      ),
    ExportWorkerError,
  );

  assertEquals(error.code, "export_too_large");
  assertEquals(requests, []);
});

Deno.test("prepared work chunk downloads must exactly match the durable manifest", async () => {
  const requests: Array<{ method: string; url: string; bytes: number }> = [];
  const error = await assertRejects(
    () =>
      fetchExportWorkChunk(
        "exports/user/job/work/occurrence/00000000.csv",
        2,
        fakeR2Config({
          getBody: new Uint8Array([1, 2, 3]),
          getDeclaredLength: 3,
          requests,
        }),
      ),
    ExportWorkerError,
  );

  assertEquals(error.code, "archive_generation_failed");
  assertEquals(requests.map((request) => request.method), ["GET"]);
});
