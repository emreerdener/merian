const TOKEN_BYTES = 32;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
export const DOWNLOAD_GRANT_LIFETIME_SECONDS = 24 * 60 * 60;

export interface DwcaDownloadGrant {
  token: string;
  url: string;
  expiresAt: string;
}

function base64Url(bytes: Uint8Array): string {
  const binary = String.fromCharCode(...bytes);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

export function createDwcaDownloadGrant(
  supabaseUrl: string,
  options: {
    now?: Date;
    randomBytes?: (bytes: Uint8Array) => Uint8Array;
  } = {},
): DwcaDownloadGrant {
  const baseUrl = new URL(supabaseUrl);
  if (
    baseUrl.protocol !== "https:" ||
    baseUrl.username.length > 0 ||
    baseUrl.password.length > 0 ||
    baseUrl.search.length > 0 ||
    baseUrl.hash.length > 0
  ) {
    throw new TypeError("The Supabase URL is invalid.");
  }

  const tokenBytes = new Uint8Array(TOKEN_BYTES);
  const randomBytes = options.randomBytes ??
    ((bytes: Uint8Array) => crypto.getRandomValues(bytes));
  const populatedBytes = randomBytes(tokenBytes);
  if (
    populatedBytes !== tokenBytes ||
    populatedBytes.byteLength !== TOKEN_BYTES
  ) {
    throw new TypeError("The download token generator is invalid.");
  }
  const token = base64Url(tokenBytes);
  if (!TOKEN_PATTERN.test(token)) {
    throw new TypeError("The download token is invalid.");
  }

  const now = options.now ?? new Date();
  if (!Number.isFinite(now.getTime())) {
    throw new TypeError("The download grant clock is invalid.");
  }
  const expiresAt = new Date(
    now.getTime() + DOWNLOAD_GRANT_LIFETIME_SECONDS * 1000,
  ).toISOString();
  const url = new URL("/functions/v1/download-dwca", baseUrl);
  url.searchParams.set("token", token);
  return { token, url: url.toString(), expiresAt };
}

export async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", bytes),
  );
  return [...digest]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
