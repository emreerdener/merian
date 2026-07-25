import { decodeBase64, encodeHex } from "../_shared/encoding.ts";
import { ExportWorkerError } from "./types.ts";

const MINIMUM_HMAC_KEY_BYTES = 32;
const MAXIMUM_KEY_VERSION = 1000;
const PSEUDONYM_BYTES = 16;

export interface UserPseudonymizer {
  readonly keyVersion: number;
  pseudonymize(userId: string): Promise<string>;
}

export function pseudonymSecretName(keyVersion: number): string {
  if (
    !Number.isSafeInteger(keyVersion) ||
    keyVersion < 1 ||
    keyVersion > MAXIMUM_KEY_VERSION
  ) {
    throw new ExportWorkerError(
      "pseudonym_key_unavailable",
      "The export job references an invalid pseudonym key version.",
    );
  }
  return `DWCA_PSEUDONYM_HMAC_KEY_V${keyVersion}`;
}

export async function createUserPseudonymizer(
  keyVersion: number,
  encodedSecret: string,
): Promise<UserPseudonymizer> {
  const secretName = pseudonymSecretName(keyVersion);
  let keyBytes: Uint8Array;
  try {
    keyBytes = decodeBase64(encodedSecret.trim());
  } catch (error) {
    throw new ExportWorkerError(
      "pseudonym_key_unavailable",
      `${secretName} is not valid Base64.`,
      true,
      { cause: error },
    );
  }

  if (keyBytes.byteLength < MINIMUM_HMAC_KEY_BYTES) {
    throw new ExportWorkerError(
      "pseudonym_key_unavailable",
      `${secretName} must decode to at least ${MINIMUM_HMAC_KEY_BYTES} bytes.`,
    );
  }

  const key = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(keyBytes).buffer,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const encoder = new TextEncoder();
  const contextPrefix = `Naturebook DwC-A recordedBy v${keyVersion}\u0000`;

  return {
    keyVersion,
    async pseudonymize(userId: string): Promise<string> {
      const signature = await crypto.subtle.sign(
        "HMAC",
        key,
        encoder.encode(`${contextPrefix}${userId}`),
      );
      const truncated = new Uint8Array(signature).subarray(
        0,
        PSEUDONYM_BYTES,
      );
      return `naturebook_user_v${keyVersion}_${encodeHex(truncated)}`;
    },
  };
}

export async function loadUserPseudonymizer(
  keyVersion: number,
  readEnvironment: (name: string) => string | undefined = Deno.env.get,
): Promise<UserPseudonymizer> {
  const secretName = pseudonymSecretName(keyVersion);
  const secret = readEnvironment(secretName);
  if (!secret) {
    throw new ExportWorkerError(
      "pseudonym_key_unavailable",
      `${secretName} is not configured.`,
    );
  }
  return await createUserPseudonymizer(keyVersion, secret);
}
