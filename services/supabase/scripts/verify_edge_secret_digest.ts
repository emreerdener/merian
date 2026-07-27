/**
 * Verifies a remote Edge Function secret without revealing its plaintext.
 *
 * `supabase secrets list --output json` returns the SHA-256 digest of each
 * custom secret in the response `value` field. This tool compares that remote
 * digest with the exact local server API key selected for a deployment.
 */

import { timingSafeCompare } from "../functions/_shared/http.ts";
import { requireServerApiKey } from "../functions/_shared/serviceRoleAuth.ts";

const MAXIMUM_INPUT_BYTES = 1 * 1_024 * 1_024;
const SHA256_HEX_PATTERN = /^[a-fA-F0-9]{64}$/;
const SECRET_NAME_PATTERN = /^[A-Z][A-Z0-9_]{0,255}$/;

export function listedSecretDigest(
  payload: unknown,
  secretName: string,
): string {
  if (!SECRET_NAME_PATTERN.test(secretName)) {
    throw new Error("Invalid Edge Function secret name.");
  }
  if (!Array.isArray(payload)) {
    throw new Error("Supabase CLI returned an invalid secret digest list.");
  }

  const matches = payload.filter((rawEntry) =>
    rawEntry &&
    typeof rawEntry === "object" &&
    !Array.isArray(rawEntry) &&
    (rawEntry as Record<string, unknown>).name === secretName
  );
  if (matches.length !== 1) {
    throw new Error(
      "Supabase CLI did not return exactly one requested secret digest.",
    );
  }

  const digest = (matches[0] as Record<string, unknown>).value;
  if (typeof digest !== "string" || !SHA256_HEX_PATTERN.test(digest)) {
    throw new Error("Supabase CLI returned an invalid secret digest.");
  }
  return digest.toLowerCase();
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function verifyListedServerApiKeyDigest(
  payload: unknown,
  secretName: string,
  serverApiKey: string,
): Promise<void> {
  const validatedServerApiKey = requireServerApiKey({
    envServerApiKey: serverApiKey,
  });
  const expectedDigest = await sha256Hex(validatedServerApiKey);
  const actualDigest = listedSecretDigest(payload, secretName);
  if (!timingSafeCompare(actualDigest, expectedDigest)) {
    throw new Error(
      "Synchronized Edge Function secret does not match the selected server API key.",
    );
  }
}

function parseSecretName(args: string[]): string {
  if (args.length !== 2 || args[0] !== "--secret-name") {
    throw new Error(
      "Usage: verify_edge_secret_digest.ts --secret-name <environment-name>",
    );
  }
  const secretName = args[1];
  if (!SECRET_NAME_PATTERN.test(secretName)) {
    throw new Error("Invalid Edge Function secret name.");
  }
  return secretName;
}

async function readStandardInput(): Promise<string> {
  const reader = Deno.stdin.readable.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > MAXIMUM_INPUT_BYTES) {
        throw new RangeError("Supabase CLI secret digest list was too large.");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const input = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    input.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(input);
}

if (import.meta.main) {
  try {
    const secretName = parseSecretName(Deno.args);
    const serverApiKey = Deno.env.get(secretName) ?? "";
    const input = await readStandardInput();
    let payload: unknown;
    try {
      payload = JSON.parse(input);
    } catch {
      throw new Error("Supabase CLI returned invalid secret digest JSON.");
    }
    await verifyListedServerApiKeyDigest(
      payload,
      secretName,
      serverApiKey,
    );
    console.log("Synchronized Edge Function secret digest verified.");
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(1);
  }
}
