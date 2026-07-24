export type BoundedJsonErrorCode =
  | "invalid_content_length"
  | "invalid_json"
  | "invalid_json_object"
  | "payload_too_large"
  | "unsupported_media_type";

export type BoundedJsonResult =
  | { ok: true; value: Record<string, unknown> }
  | {
    ok: false;
    status: 400 | 413 | 415;
    code: BoundedJsonErrorCode;
    message: string;
  };

export type BoundedByteStreamResult =
  | { ok: true; bytes: Uint8Array }
  | { ok: false; exceeded: true };

export async function readByteStreamWithinLimit(
  stream: ReadableStream<Uint8Array> | null,
  maximumBytes: number,
  cancelReason = "stream exceeded limit",
): Promise<BoundedByteStreamResult> {
  if (!Number.isSafeInteger(maximumBytes) || maximumBytes < 1) {
    throw new TypeError("maximumBytes must be a positive safe integer.");
  }
  if (!stream) return { ok: true, bytes: new Uint8Array() };

  const reader = stream.getReader();
  let buffer = new Uint8Array();
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value || value.byteLength === 0) continue;
      if (value.byteLength > maximumBytes - totalBytes) {
        try {
          await reader.cancel(cancelReason);
        } catch {
          // The byte ceiling still wins if cancellation races a disconnect.
        }
        return { ok: false, exceeded: true };
      }

      const requiredBytes = totalBytes + value.byteLength;
      if (requiredBytes > buffer.byteLength) {
        let nextCapacity = buffer.byteLength === 0
          ? Math.min(maximumBytes, Math.max(1024, requiredBytes))
          : buffer.byteLength;
        while (nextCapacity < requiredBytes) {
          nextCapacity = Math.min(
            maximumBytes,
            Math.max(requiredBytes, nextCapacity * 2),
          );
        }
        const grown = new Uint8Array(nextCapacity);
        grown.set(buffer.subarray(0, totalBytes));
        buffer = grown;
      }

      buffer.set(value, totalBytes);
      totalBytes = requiredBytes;
    }
  } finally {
    reader.releaseLock();
  }

  return {
    ok: true,
    bytes: totalBytes === buffer.byteLength
      ? buffer
      : buffer.subarray(0, totalBytes),
  };
}

export async function readBoundedJsonObject(
  request: Request,
  maximumBytes: number,
): Promise<BoundedJsonResult> {
  if (!Number.isSafeInteger(maximumBytes) || maximumBytes < 1) {
    throw new TypeError("maximumBytes must be a positive safe integer.");
  }

  if (!isJsonMediaType(request.headers.get("content-type"))) {
    return {
      ok: false,
      status: 415,
      code: "unsupported_media_type",
      message: "Content-Type must be application/json.",
    };
  }

  const declaredLength = request.headers.get("content-length");
  let declaredBytes: number | null = null;
  if (declaredLength !== null) {
    const normalizedLength = declaredLength.trim();
    if (!/^(0|[1-9][0-9]*)$/.test(normalizedLength)) {
      return {
        ok: false,
        status: 400,
        code: "invalid_content_length",
        message: "Invalid Content-Length header.",
      };
    }
    declaredBytes = Number(normalizedLength);
    if (!Number.isSafeInteger(declaredBytes)) {
      return {
        ok: false,
        status: 400,
        code: "invalid_content_length",
        message: "Invalid Content-Length header.",
      };
    }
    if (declaredBytes > maximumBytes) {
      return {
        ok: false,
        status: 413,
        code: "payload_too_large",
        message: "Request body exceeds this endpoint's byte limit.",
      };
    }
  }

  if (!request.body) {
    return {
      ok: false,
      status: 400,
      code: "invalid_json",
      message: "JSON body is required.",
    };
  }

  const streamResult = await readByteStreamWithinLimit(
    request.body,
    maximumBytes,
    "request body exceeded limit",
  );
  if (!streamResult.ok) {
    return {
      ok: false,
      status: 413,
      code: "payload_too_large",
      message: "Request body exceeds this endpoint's byte limit.",
    };
  }
  const bytes = streamResult.bytes;

  if (declaredBytes !== null && declaredBytes !== bytes.byteLength) {
    return {
      ok: false,
      status: 400,
      code: "invalid_content_length",
      message: "Content-Length does not match the request body.",
    };
  }

  let decoded: string;
  try {
    decoded = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return {
      ok: false,
      status: 400,
      code: "invalid_json",
      message: "JSON body must use valid UTF-8.",
    };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(decoded);
  } catch {
    return {
      ok: false,
      status: 400,
      code: "invalid_json",
      message: "Invalid JSON body.",
    };
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return {
      ok: false,
      status: 400,
      code: "invalid_json_object",
      message: "JSON body must be an object.",
    };
  }

  return { ok: true, value: parsed as Record<string, unknown> };
}

function isJsonMediaType(contentType: string | null): boolean {
  if (!contentType) return false;
  const mediaType = contentType.split(";", 1)[0].trim().toLowerCase();
  return mediaType === "application/json" ||
    /^application\/[a-z0-9!#$&^_.+-]+\+json$/.test(mediaType);
}
