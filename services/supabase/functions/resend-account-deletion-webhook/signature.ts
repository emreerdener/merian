import { decodeBase64, encodeBase64 } from "../_shared/encoding.ts";
import { timingSafeCompare } from "../_shared/http.ts";

export const RESEND_SIGNATURE_TOLERANCE_SECONDS = 5 * 60;

export interface VerifiedResendSignature {
  messageId: string;
  timestampSeconds: number;
}

type RawBody = string | Uint8Array<ArrayBufferLike>;
type ExactBytes = Uint8Array<ArrayBuffer>;

function bodyBytes(rawBody: RawBody): ExactBytes {
  return typeof rawBody === "string"
    ? new TextEncoder().encode(rawBody)
    : new Uint8Array(rawBody);
}

function signatureInput(
  messageId: string,
  timestampText: string,
  rawBody: RawBody,
): ExactBytes {
  const prefix = new TextEncoder().encode(`${messageId}.${timestampText}.`);
  const payload = bodyBytes(rawBody);
  const input = new Uint8Array(prefix.byteLength + payload.byteLength);
  input.set(prefix);
  input.set(payload, prefix.byteLength);
  return input;
}

function signingKey(secret: string): ExactBytes | null {
  if (!secret.startsWith("whsec_") || secret.length > 512) return null;

  try {
    const decoded = decodeBase64(secret.slice("whsec_".length));
    return decoded.byteLength >= 16 && decoded.byteLength <= 128
      ? new Uint8Array(decoded)
      : null;
  } catch {
    return null;
  }
}

export function isValidResendSigningSecret(secret: string): boolean {
  return signingKey(secret) !== null;
}

async function hmacSha256Base64(
  keyBytes: ExactBytes,
  value: ExactBytes,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return encodeBase64(await crypto.subtle.sign("HMAC", key, value));
}

export async function createResendSignature(
  secret: string,
  messageId: string,
  timestampSeconds: number,
  rawBody: RawBody,
): Promise<string> {
  const keyBytes = signingKey(secret);
  if (!keyBytes) throw new TypeError("Invalid Resend webhook secret.");
  const timestampText = String(timestampSeconds);
  const signature = await hmacSha256Base64(
    keyBytes,
    signatureInput(messageId, timestampText, rawBody),
  );
  return `v1,${signature}`;
}

export async function verifyResendSignature(
  headers: {
    id: string | null;
    timestamp: string | null;
    signature: string | null;
  },
  secret: string,
  rawBody: RawBody,
  nowMs = Date.now(),
  toleranceSeconds = RESEND_SIGNATURE_TOLERANCE_SECONDS,
): Promise<VerifiedResendSignature | null> {
  const messageId = headers.id?.trim() ?? "";
  const timestampText = headers.timestamp?.trim() ?? "";
  const signatureHeader = headers.signature?.trim() ?? "";
  const keyBytes = signingKey(secret);

  if (
    !keyBytes ||
    toleranceSeconds < 0 ||
    !/^[A-Za-z0-9_-]{1,255}$/.test(messageId) ||
    !/^[0-9]{1,12}$/.test(timestampText) ||
    signatureHeader.length < 4 ||
    signatureHeader.length > 1_024
  ) {
    return null;
  }

  const timestampSeconds = Number(timestampText);
  const nowSeconds = Math.floor(nowMs / 1_000);
  if (
    !Number.isSafeInteger(timestampSeconds) ||
    Math.abs(nowSeconds - timestampSeconds) > toleranceSeconds
  ) {
    return null;
  }

  const components = signatureHeader.split(/\s+/).filter(Boolean);
  if (components.length === 0 || components.length > 8) return null;
  const signatures = components.flatMap((component) => {
    const separator = component.indexOf(",");
    if (separator < 1 || component.slice(0, separator) !== "v1") return [];
    const value = component.slice(separator + 1);
    return /^[A-Za-z0-9+/]{43}=$/.test(value) ? [value] : [];
  });
  if (signatures.length === 0) return null;

  const expected = await hmacSha256Base64(
    keyBytes,
    signatureInput(messageId, timestampText, rawBody),
  );
  const matches = signatures.some((candidate) =>
    timingSafeCompare(candidate, expected)
  );
  return matches ? { messageId, timestampSeconds } : null;
}
