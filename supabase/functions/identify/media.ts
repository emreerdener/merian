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
    // Size is checked against ACTUAL bytes after consumption — Content-Length headers are
    // unreliable (absent on chunked transfer encoding) and must never be trusted as a
    // heap-exhaustion guard.
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
      const arrayBuffer = await r2Response.arrayBuffer();
      totalBytes += arrayBuffer.byteLength;
      if (totalBytes > 5 * 1024 * 1024) {
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
