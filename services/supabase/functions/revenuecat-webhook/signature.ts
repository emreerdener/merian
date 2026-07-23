import { timingSafeCompare } from "../_shared/http.ts";

export const REVENUECAT_SIGNATURE_TOLERANCE_SECONDS = 5 * 60;

export interface VerifiedRevenueCatSignature {
  timestampSeconds: number;
}

type RevenueCatRawBody = string | Uint8Array<ArrayBufferLike>;
type ExactBytes = Uint8Array<ArrayBuffer>;

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function bodyBytes(rawBody: RevenueCatRawBody): ExactBytes {
  return typeof rawBody === "string"
    ? new TextEncoder().encode(rawBody)
    : new Uint8Array(rawBody);
}

async function hmacSha256Hex(
  secret: string,
  value: ExactBytes,
): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    value,
  );
  return bytesToHex(new Uint8Array(digest));
}

export async function sha256Hex(value: RevenueCatRawBody): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    bodyBytes(value),
  );
  return bytesToHex(new Uint8Array(digest));
}

function signatureInput(
  timestampText: string,
  rawBody: RevenueCatRawBody,
): ExactBytes {
  const prefix = new TextEncoder().encode(`${timestampText}.`);
  const payload = bodyBytes(rawBody);
  const input = new Uint8Array(prefix.byteLength + payload.byteLength);
  input.set(prefix);
  input.set(payload, prefix.byteLength);
  return input;
}

export async function createRevenueCatSignature(
  secret: string,
  timestampSeconds: number,
  rawBody: RevenueCatRawBody,
): Promise<string> {
  const signature = await hmacSha256Hex(
    secret,
    signatureInput(String(timestampSeconds), rawBody),
  );
  return `t=${timestampSeconds},v1=${signature}`;
}

export async function verifyRevenueCatSignature(
  header: string | null,
  secret: string,
  rawBody: RevenueCatRawBody,
  nowMs = Date.now(),
  toleranceSeconds = REVENUECAT_SIGNATURE_TOLERANCE_SECONDS,
): Promise<VerifiedRevenueCatSignature | null> {
  if (!header || !secret || toleranceSeconds < 0) {
    return null;
  }

  let timestampText: string | null = null;
  const signatures: string[] = [];

  for (const component of header.split(",")) {
    const separator = component.indexOf("=");
    if (separator <= 0) continue;

    const key = component.slice(0, separator).trim();
    const value = component.slice(separator + 1).trim();
    if (key === "t") {
      if (timestampText !== null) return null;
      timestampText = value;
    } else if (key === "v1" && /^[0-9a-fA-F]{64}$/.test(value)) {
      if (signatures.length >= 8) return null;
      signatures.push(value.toLowerCase());
    }
  }

  if (
    timestampText === null ||
    !/^[0-9]{1,12}$/.test(timestampText) ||
    signatures.length === 0
  ) {
    return null;
  }

  const timestampSeconds = Number(timestampText);
  const nowSeconds = Math.floor(nowMs / 1000);
  if (
    !Number.isSafeInteger(timestampSeconds) ||
    Math.abs(nowSeconds - timestampSeconds) > toleranceSeconds
  ) {
    return null;
  }

  const expected = await hmacSha256Hex(
    secret,
    signatureInput(timestampText, rawBody),
  );
  const matched = signatures.some((signature) =>
    timingSafeCompare(signature, expected)
  );

  return matched ? { timestampSeconds } : null;
}
