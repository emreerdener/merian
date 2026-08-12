export const SIGNOUT_PURCHASE_HANDOFF_MAX_BODY_BYTES = 2 * 1024;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HANDOFF_SECRET_RE = /^[A-Za-z0-9_-]{43}$/;

export type SignoutPurchaseHandoffRequest =
  | { operation: "prepare" }
  | {
    operation: "bind" | "cancel" | "complete";
    handoffId: string;
    handoffSecret: string;
  };

export type SignoutPurchaseHandoffRequestError = {
  status: 400;
  code: "invalid_request";
  message: string;
};

export function parseSignoutPurchaseHandoffRequest(
  raw: unknown,
): SignoutPurchaseHandoffRequest | SignoutPurchaseHandoffRequestError {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return invalidRequest("JSON body must be an object.");
  }

  const body = raw as Record<string, unknown>;
  if (body.operation === "prepare") {
    if (!hasOnlyKeys(body, ["operation"])) {
      return invalidRequest("prepare contains unsupported fields.");
    }
    return { operation: "prepare" };
  }

  if (
    body.operation === "bind" || body.operation === "cancel" ||
    body.operation === "complete"
  ) {
    if (
      !hasOnlyKeys(body, ["operation", "handoff_id", "handoff_secret"])
    ) {
      return invalidRequest(`${body.operation} contains unsupported fields.`);
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
      operation: body.operation,
      handoffId: body.handoff_id.toLowerCase(),
      handoffSecret: body.handoff_secret,
    };
  }

  return invalidRequest(
    "operation must be prepare, bind, cancel, or complete.",
  );
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

function invalidRequest(
  message: string,
): SignoutPurchaseHandoffRequestError {
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
