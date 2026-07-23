export const GHOST_MERGE_MAX_BODY_BYTES = 4 * 1024;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HANDOFF_SECRET_RE = /^[A-Za-z0-9_-]{43}$/;
const SECRET_HASH_RE = /^[0-9a-f]{64}$/;

export type MergeProvider = "apple" | "google";

export type GhostMergeRequest =
  | {
    operation: "prepare";
    provider: MergeProvider;
    providerSubject: string;
  }
  | {
    operation: "complete";
    handoffId: string;
    handoffSecret: string;
  }
  | {
    operation: "refresh_identity";
  };

export type GhostMergeRequestError = {
  status: 400;
  code: "invalid_request";
  message: string;
};

export function parseGhostMergeRequest(
  raw: unknown,
): GhostMergeRequest | GhostMergeRequestError {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return invalidRequest("JSON body must be an object.");
  }

  const body = raw as Record<string, unknown>;
  switch (body.operation) {
    case "prepare": {
      if (
        !hasOnlyKeys(body, ["operation", "provider", "provider_subject"])
      ) {
        return invalidRequest("prepare contains unsupported fields.");
      }

      if (body.provider !== "apple" && body.provider !== "google") {
        return invalidRequest("provider must be apple or google.");
      }

      if (
        typeof body.provider_subject !== "string" ||
        !isValidProviderSubject(body.provider_subject)
      ) {
        return invalidRequest("provider_subject is invalid.");
      }

      return {
        operation: "prepare",
        provider: body.provider,
        providerSubject: body.provider_subject,
      };
    }

    case "complete": {
      if (
        !hasOnlyKeys(body, ["operation", "handoff_id", "handoff_secret"])
      ) {
        return invalidRequest("complete contains unsupported fields.");
      }

      if (
        typeof body.handoff_id !== "string" ||
        !UUID_RE.test(body.handoff_id)
      ) {
        return invalidRequest("handoff_id must be a valid UUID.");
      }
      if (
        typeof body.handoff_secret !== "string" ||
        !HANDOFF_SECRET_RE.test(body.handoff_secret)
      ) {
        return invalidRequest("handoff_secret is invalid.");
      }

      return {
        operation: "complete",
        handoffId: body.handoff_id.toLowerCase(),
        handoffSecret: body.handoff_secret,
      };
    }

    case "refresh_identity":
      if (!hasOnlyKeys(body, ["operation"])) {
        return invalidRequest("refresh_identity contains unsupported fields.");
      }
      return { operation: "refresh_identity" };

    default:
      return invalidRequest(
        "operation must be prepare, complete, or refresh_identity.",
      );
  }
}

export function generateHandoffSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/u, "");
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

export function isSecretHash(value: string): boolean {
  return SECRET_HASH_RE.test(value);
}

function invalidRequest(message: string): GhostMergeRequestError {
  return { status: 400, code: "invalid_request", message };
}

function hasOnlyKeys(
  body: Record<string, unknown>,
  allowedKeys: readonly string[],
): boolean {
  const allowed = new Set(allowedKeys);
  return Object.keys(body).every((key) => allowed.has(key)) &&
    Object.keys(body).length === allowed.size;
}

function isValidProviderSubject(value: string): boolean {
  if (value.length < 1 || value.length > 255) return false;
  return !Array.from(value).some((character) => {
    const scalar = character.codePointAt(0) ?? 0;
    return scalar <= 0x1f ||
      scalar === 0x7f ||
      (scalar >= 0x80 && scalar <= 0x9f);
  });
}
