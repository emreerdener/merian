const IP_HASH_PATTERN = /^[0-9a-f]{64}$/;
const PURPOSE_PATTERN = /^[a-z][a-z0-9-]{2,63}$/;

export class ClientAddressHashError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ClientAddressHashError";
  }
}

/**
 * Returns only proxy-observed address headers. The right-most forwarded value
 * is used because callers can prepend an attacker-controlled left-most value.
 */
export function clientAddressFromHeaders(headers: Headers): string {
  const realIp = headers.get("x-real-ip")?.trim();
  if (realIp) return realIp.slice(0, 128).toLowerCase();

  const connectingIp = headers.get("cf-connecting-ip")?.trim();
  if (connectingIp) return connectingIp.slice(0, 128).toLowerCase();

  const forwarded = headers.get("x-forwarded-for")
    ?.split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  const forwardedPeer = forwarded?.at(-1);
  if (forwardedPeer) return forwardedPeer.slice(0, 128).toLowerCase();

  // Hosted Edge requests normally include x-real-ip. A shared fail-safe
  // bucket is safer than silently disabling rate limits when it is absent.
  return "unavailable";
}

export function resolveClientAddressHashSecret(input: {
  dedicatedSecret?: string | null;
  platformSecretKey?: string | null;
  serviceRoleKey?: string | null;
}): string {
  const dedicated = input.dedicatedSecret?.trim();
  if (dedicated) {
    if (dedicated.length < 32) {
      throw new ClientAddressHashError(
        "The dedicated client-address hash secret is too short.",
      );
    }
    return dedicated;
  }

  const platformSecret = input.platformSecretKey?.trim() ||
    input.serviceRoleKey?.trim();
  if (!platformSecret || platformSecret.length < 32) {
    throw new ClientAddressHashError(
      "No suitable server-only client-address hash key is configured.",
    );
  }
  return platformSecret;
}

/**
 * Produces a purpose-separated, daily rotating identifier. Raw addresses never
 * leave the Edge isolate and hashes from different abuse-control domains cannot
 * be joined.
 */
export async function hmacClientAddressForPurpose(
  address: string,
  secret: string,
  purpose: string,
  now = new Date(),
): Promise<string> {
  if (secret.trim().length < 32) {
    throw new ClientAddressHashError(
      "The client-address hash secret is too short.",
    );
  }
  if (!PURPOSE_PATTERN.test(purpose)) {
    throw new ClientAddressHashError(
      "The client-address hash purpose is invalid.",
    );
  }

  const day = now.toISOString().slice(0, 10);
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      encoder.encode(`${purpose}:${day}:${address}`),
    ),
  );
  const hash = Array.from(
    signature,
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  if (!IP_HASH_PATTERN.test(hash)) {
    throw new ClientAddressHashError(
      "The client-address hash output is invalid.",
    );
  }
  return hash;
}
