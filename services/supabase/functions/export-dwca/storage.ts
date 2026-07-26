import { getR2Config, R2Config } from "../_shared/aws.ts";
import { readByteStreamWithinLimit } from "../_shared/http.ts";
import type { ExportProgressCallback } from "./archive.ts";
import { MAXIMUM_WORK_CHUNK_BYTES } from "./limits.ts";
import { ClaimedExportJob, ExportWorkerError } from "./types.ts";

export { MAXIMUM_WORK_CHUNK_BYTES } from "./limits.ts";

export const MULTIPART_PART_SIZE = 8 * 1024 * 1024;
const MAXIMUM_MULTIPART_PARTS = 10_000;
const SIGNED_URL_LIFETIME_SECONDS = 86_400;
const R2_REQUEST_TIMEOUT_MS = 60_000;
const R2_XML_RESPONSE_LIMIT_BYTES = 64 * 1024;
const MAXIMUM_UPLOAD_ID_CHARACTERS = 2048;
const MAXIMUM_ARCHIVE_BYTES = 16 * 1024 * 1024;
const decoder = new TextDecoder();

interface UploadedPart {
  partNumber: number;
  etag: string;
}

export interface ExportUploadResult {
  objectKey: string;
  signedUrl: string;
  uploadedBytes: number;
  uploadedParts: number;
}

function storageFailure(message: string, cause?: unknown): ExportWorkerError {
  return new ExportWorkerError(
    "storage_unavailable",
    message,
    true,
    cause === undefined ? undefined : { cause },
  );
}

export function exportObjectKey(
  job: ClaimedExportJob,
  claimToken: string,
): string {
  return `exports/${job.userId}/${job.id}/${claimToken}.zip`;
}

export function exportWorkChunkObjectKey(
  job: ClaimedExportJob,
  phase: "occurrence" | "multimedia",
  claimToken: string,
): string {
  return `exports/${job.userId}/${job.id}/work/${phase}/${
    String(job.chunkSequence).padStart(8, "0")
  }-${claimToken}.csv`;
}

function xmlEscape(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function xmlUnescape(value: string): string {
  return value
    .replaceAll("&apos;", "'")
    .replaceAll("&quot;", '"')
    .replaceAll("&gt;", ">")
    .replaceAll("&lt;", "<")
    .replaceAll("&amp;", "&");
}

function uploadIdFromXml(xml: string): string {
  const encodedUploadId = xml.match(/<UploadId>([^<]+)<\/UploadId>/)?.[1];
  if (!encodedUploadId) {
    throw storageFailure("R2 did not return a multipart upload id.");
  }
  const uploadId = xmlUnescape(encodedUploadId);
  if (
    uploadId.length > MAXIMUM_UPLOAD_ID_CHARACTERS ||
    [...uploadId].some((character) => {
      const codePoint = character.codePointAt(0) ?? 0;
      return codePoint <= 0x1f || codePoint === 0x7f;
    })
  ) {
    throw storageFailure("R2 returned an invalid multipart upload id.");
  }
  return uploadId;
}

function r2Request(
  input: string | URL,
  init: RequestInit,
): Request {
  return new Request(input, {
    ...init,
    signal: AbortSignal.timeout(R2_REQUEST_TIMEOUT_MS),
  });
}

function completeMultipartXml(parts: UploadedPart[]): string {
  const entries = parts.map((part) =>
    `<Part><PartNumber>${part.partNumber}</PartNumber><ETag>${
      xmlEscape(part.etag)
    }</ETag></Part>`
  ).join("");
  return `<?xml version="1.0" encoding="UTF-8"?><CompleteMultipartUpload>${entries}</CompleteMultipartUpload>`;
}

export async function* fixedSizeParts(
  stream: ReadableStream<Uint8Array>,
  partSize = MULTIPART_PART_SIZE,
): AsyncGenerator<Uint8Array> {
  if (!Number.isSafeInteger(partSize) || partSize < 1) {
    throw new TypeError("partSize must be a positive safe integer.");
  }

  const reader = stream.getReader();
  let buffer = new Uint8Array(partSize);
  let bufferedBytes = 0;
  let sourceCompleted = false;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        sourceCompleted = true;
        break;
      }
      if (!value || value.byteLength === 0) continue;

      let sourceOffset = 0;
      while (sourceOffset < value.byteLength) {
        const copyLength = Math.min(
          partSize - bufferedBytes,
          value.byteLength - sourceOffset,
        );
        buffer.set(
          value.subarray(sourceOffset, sourceOffset + copyLength),
          bufferedBytes,
        );
        bufferedBytes += copyLength;
        sourceOffset += copyLength;

        if (bufferedBytes === partSize) {
          yield buffer;
          buffer = new Uint8Array(partSize);
          bufferedBytes = 0;
        }
      }
    }

    if (bufferedBytes > 0) {
      yield buffer.slice(0, bufferedBytes);
    }
  } finally {
    if (!sourceCompleted) {
      try {
        await reader.cancel("DwC-A multipart consumer stopped.");
      } catch {
        // Preserve the upload/generation error that stopped consumption.
      }
    }
    reader.releaseLock();
  }
}

async function checkedR2Response(
  response: Response,
  operation: string,
): Promise<Response> {
  if (!response.ok) {
    await discardResponseBody(response);
    throw storageFailure(
      `R2 ${operation} failed with HTTP ${response.status}.`,
    );
  }
  return response;
}

async function discardResponseBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // The HTTP status and already-read headers remain authoritative.
  }
}

async function readR2XmlResponse(
  response: Response,
  operation: string,
): Promise<string> {
  const result = await readByteStreamWithinLimit(
    response.body,
    R2_XML_RESPONSE_LIMIT_BYTES,
    `R2 ${operation} response exceeded limit`,
  );
  if (result.exceeded || !result.bytes) {
    throw storageFailure(`R2 ${operation} returned an oversized response.`);
  }
  return decoder.decode(result.bytes);
}

function assertMultipartCompletionSucceeded(xml: string): void {
  if (
    /<Error(?:\s|\/?>)/i.test(xml) ||
    !/<CompleteMultipartUploadResult(?:\s|\/?>)/i.test(xml)
  ) {
    throw storageFailure(
      "R2 multipart completion did not confirm the assembled object.",
    );
  }
}

async function abortMultipartUpload(
  objectUrl: string,
  uploadId: string,
  config: R2Config,
): Promise<void> {
  const abortUrl = new URL(objectUrl);
  abortUrl.searchParams.set("uploadId", uploadId);
  try {
    const response = await config.s3Client.fetch(
      r2Request(abortUrl, { method: "DELETE" }),
    );
    if (!response.ok && response.status !== 404) {
      console.error(JSON.stringify({
        event: "dwca_multipart_abort_failed",
        status: response.status,
        ts: new Date().toISOString(),
      }));
    }
    await discardResponseBody(response);
  } catch (error) {
    console.error(JSON.stringify({
      event: "dwca_multipart_abort_failed",
      error: error instanceof Error ? error.message : String(error),
      ts: new Date().toISOString(),
    }));
  }
}

export async function uploadDwcaArchive(
  archive: ReadableStream<Uint8Array>,
  objectKey: string,
  onProgress: ExportProgressCallback = () => {},
  config: R2Config = getR2Config(),
  maximumBytes = MAXIMUM_ARCHIVE_BYTES,
): Promise<ExportUploadResult> {
  if (
    !Number.isSafeInteger(maximumBytes) ||
    maximumBytes < 1 ||
    maximumBytes > MAXIMUM_ARCHIVE_BYTES
  ) {
    throw new TypeError("maximumBytes must be within the archive hard limit.");
  }
  const { bucketName, endpoint, s3Client } = config;
  const objectUrl = `${endpoint}/${bucketName}/${objectKey}`;
  const createUrl = new URL(objectUrl);
  createUrl.searchParams.set("uploads", "");

  let uploadId: string | null = null;
  try {
    const createResponse = await checkedR2Response(
      await s3Client.fetch(
        r2Request(createUrl, {
          method: "POST",
          headers: { "Content-Type": "application/zip" },
        }),
      ),
      "multipart creation",
    );
    uploadId = uploadIdFromXml(
      await readR2XmlResponse(createResponse, "multipart creation"),
    );

    const uploadedParts: UploadedPart[] = [];
    let uploadedBytes = 0;
    for await (const part of fixedSizeParts(archive)) {
      const partNumber = uploadedParts.length + 1;
      if (partNumber > MAXIMUM_MULTIPART_PARTS) {
        throw new ExportWorkerError(
          "export_too_large",
          "The export exceeded the R2 multipart part limit.",
        );
      }
      if (uploadedBytes + part.byteLength > maximumBytes) {
        throw new ExportWorkerError(
          "export_too_large",
          "The archive exceeded its canonical byte budget.",
        );
      }

      const partUrl = new URL(objectUrl);
      partUrl.searchParams.set("partNumber", String(partNumber));
      partUrl.searchParams.set("uploadId", uploadId);
      const partResponse = await checkedR2Response(
        await s3Client.fetch(
          r2Request(partUrl, {
            method: "PUT",
            headers: {
              "Content-Type": "application/octet-stream",
              "X-Amz-Content-Sha256": "UNSIGNED-PAYLOAD",
            },
            body: part as unknown as BodyInit,
          }),
        ),
        `multipart part ${partNumber}`,
      );
      const etag = partResponse.headers.get("etag");
      await discardResponseBody(partResponse);
      if (!etag) {
        throw storageFailure(`R2 part ${partNumber} omitted its ETag.`);
      }
      uploadedParts.push({ partNumber, etag });
      uploadedBytes += part.byteLength;
      await onProgress();
    }

    if (uploadedParts.length === 0) {
      throw storageFailure("The generated export archive was empty.");
    }

    const completeUrl = new URL(objectUrl);
    completeUrl.searchParams.set("uploadId", uploadId);
    const completeResponse = await checkedR2Response(
      await s3Client.fetch(
        r2Request(completeUrl, {
          method: "POST",
          headers: { "Content-Type": "application/xml" },
          body: completeMultipartXml(uploadedParts),
        }),
      ),
      "multipart completion",
    );
    const completeXml = await readR2XmlResponse(
      completeResponse,
      "multipart completion",
    );
    assertMultipartCompletionSucceeded(completeXml);

    const getUrl = new URL(objectUrl);
    getUrl.searchParams.set(
      "X-Amz-Expires",
      String(SIGNED_URL_LIFETIME_SECONDS),
    );
    const signedGet = await s3Client.sign(
      new Request(getUrl, { method: "GET" }),
      { aws: { signQuery: true } },
    );

    return {
      objectKey,
      signedUrl: signedGet.url,
      uploadedBytes,
      uploadedParts: uploadedParts.length,
    };
  } catch (error) {
    if (uploadId) {
      await abortMultipartUpload(objectUrl, uploadId, config);
    }
    if (error instanceof ExportWorkerError) throw error;
    throw storageFailure("The R2 multipart upload failed.", error);
  }
}

export async function putExportWorkChunk(
  bytes: Uint8Array,
  objectKey: string,
  config: R2Config = getR2Config(),
): Promise<void> {
  if (bytes.byteLength > MAXIMUM_WORK_CHUNK_BYTES) {
    throw new ExportWorkerError(
      "export_too_large",
      "A prepared CSV batch exceeded its hard byte limit.",
    );
  }
  try {
    const response = await config.s3Client.fetch(
      r2Request(
        `${config.endpoint}/${config.bucketName}/${objectKey}`,
        {
          method: "PUT",
          headers: {
            "Content-Type": "text/csv; charset=utf-8",
            "X-Amz-Content-Sha256": "UNSIGNED-PAYLOAD",
          },
          body: bytes as unknown as BodyInit,
        },
      ),
    );
    await checkedR2Response(response, "work chunk upload");
    await discardResponseBody(response);
  } catch (error) {
    if (error instanceof ExportWorkerError) throw error;
    throw storageFailure("The R2 work chunk upload failed.", error);
  }
}

export async function fetchExportWorkChunk(
  objectKey: string,
  expectedByteCount: number,
  config: R2Config = getR2Config(),
): Promise<Uint8Array> {
  if (
    !Number.isSafeInteger(expectedByteCount) ||
    expectedByteCount < 0 ||
    expectedByteCount > MAXIMUM_WORK_CHUNK_BYTES
  ) {
    throw new ExportWorkerError(
      "archive_generation_failed",
      "The work chunk manifest has an invalid byte count.",
    );
  }

  try {
    const response = await checkedR2Response(
      await config.s3Client.fetch(
        r2Request(
          `${config.endpoint}/${config.bucketName}/${objectKey}`,
          { method: "GET" },
        ),
      ),
      "work chunk download",
    );
    const declaredLength = Number(response.headers.get("Content-Length"));
    if (
      Number.isFinite(declaredLength) &&
      declaredLength !== expectedByteCount
    ) {
      await discardResponseBody(response);
      throw new ExportWorkerError(
        "archive_generation_failed",
        "A prepared work chunk did not match its manifest.",
      );
    }
    const result = await readByteStreamWithinLimit(
      response.body,
      Math.max(1, expectedByteCount),
      "R2 work chunk exceeded its manifest",
    );
    if (
      result.exceeded ||
      !result.bytes ||
      result.bytes.byteLength !== expectedByteCount
    ) {
      throw new ExportWorkerError(
        "archive_generation_failed",
        "A prepared work chunk did not match its manifest.",
      );
    }
    return result.bytes;
  } catch (error) {
    if (error instanceof ExportWorkerError) throw error;
    throw storageFailure("The R2 work chunk download failed.", error);
  }
}
