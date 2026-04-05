import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";
import { getR2Config } from "../_shared/aws.ts";
import { jsonResponse } from "../_shared/edgeHandler.ts";

export async function resolveImagePayloads(
  r2ObjectKeys: string[] | undefined,
  imageBase64s: string[] | undefined,
  fnStart: number,
): Promise<{ base64Payloads?: string[]; errorResponse?: Response }> {
  const base64Payloads: string[] = [];

  if (imageBase64s && imageBase64s.length > 0) {
    if (imageBase64s.length > 5) {
      return { errorResponse: jsonResponse({ error: "Too many images." }, 400) };
    }
    const validBase64s: string[] = imageBase64s.filter(
      (s: string) => s.length > 0,
    );
    if (validBase64s.length === 0) {
      return { errorResponse: jsonResponse(
        { error: "Bad Request: imageBase64s contains no valid image data." },
        400,
      ) };
    }
    const totalB64Bytes = validBase64s.reduce(
      (sum: number, s: string) => sum + s.length,
      0,
    );
    // base64 inflates raw size ~4/3; 5 MB raw ≈ 6.7 MB encoded
    if (totalB64Bytes > 7 * 1024 * 1024) {
      return { errorResponse: jsonResponse(
        {
          error: "Payload Too Large: base64 payload exceeds 5 MB raw limit.",
        },
        413,
      ) };
    }
    base64Payloads.push(...validBase64s);
  } else if (r2ObjectKeys && r2ObjectKeys.length > 0) {
    console.log(`[⏱ BENCH] base64_validated: ${Date.now() - fnStart}ms`);
    const { s3Client, bucketName, endpoint } = getR2Config();

    const r2Responses = await Promise.allSettled(
      r2ObjectKeys.map((key: string) =>
        s3Client.fetch(`${endpoint}/${bucketName}/${key}`),
      ),
    );

    // Process images serially: consume one body at a time so each ArrayBuffer is GC-eligible
    // before the next is loaded, preventing a peak spike of N × (raw + copy + base64) in heap.
    //
    // Per-image pre-check via Content-Length header: where R2 provides the header (non-chunked
    // transfers), we can reject oversized images before allocating the V8 buffer entirely.
    // Content-Length is intentionally not trusted as the ONLY guard (chunked transfers omit it),
    // so the post-allocation cumulative check below remains the authoritative enforcement.
    const PER_IMAGE_LIMIT = 5 * 1024 * 1024;
    const TOTAL_LIMIT = 5 * 1024 * 1024;
    let totalBytes = 0;
    while (r2Responses.length > 0) {
      const result = r2Responses.shift()!;
      if (result.status === "rejected") {
        throw new Error(`Failed to execute concurrent R2 fetch request.`);
      }
      const r2Response = result.value as Response;
      if (!r2Response.ok) {
        throw new Error(
          `Failed to fetch an image from R2: ${r2Response.statusText}`,
        );
      }
      // Pre-check: if Content-Length is present and already exceeds limit, abort before
      // allocating the full buffer in V8 heap.
      const contentLength = r2Response.headers.get("content-length");
      if (contentLength !== null) {
        const declaredBytes = parseInt(contentLength, 10);
        if (!isNaN(declaredBytes) && declaredBytes > PER_IMAGE_LIMIT) {
          return { errorResponse: jsonResponse(
            { error: "Payload Too Large: A single image exceeds the 5MB limit." },
            413,
          ) };
        }
      }
      const arrayBuffer = await r2Response.arrayBuffer();
      // Post-allocation cumulative guard — authoritative check regardless of Content-Length.
      totalBytes += arrayBuffer.byteLength;
      if (totalBytes > TOTAL_LIMIT) {
        return { errorResponse: jsonResponse(
          { error: "Payload Too Large: Combined images exceed 5MB limit." },
          413,
        ) };
      }
      base64Payloads.push(encodeBase64(new Uint8Array(arrayBuffer)));
    }
  }

  return { base64Payloads };
}
