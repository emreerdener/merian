export const PURCHASE_PRINCIPAL_MAX_BODY_BYTES = 2 * 1024;
export const PURCHASE_PRINCIPAL_CLIENT_PROTOCOL = 1;

const INSTALLATION_CAPABILITY_RE = /^[A-Za-z0-9_-]{43}$/;

export interface ResolvePurchasePrincipalRequest {
  operation: "resolve";
  installationCapability: string;
  clientProtocol: number;
  bindingIntentGeneration: number;
}

export interface ResolvePurchasePrincipalRequestError {
  status: 400;
  code: "invalid_request";
  message: string;
}

export function parseResolvePurchasePrincipalRequest(
  raw: unknown,
): ResolvePurchasePrincipalRequest | ResolvePurchasePrincipalRequestError {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return invalidRequest("JSON body must be an object.");
  }

  const body = raw as Record<string, unknown>;
  const keys = Object.keys(body).sort();
  if (
    keys.length !== 4 ||
    keys[0] !== "binding_intent_generation" ||
    keys[1] !== "client_protocol" ||
    keys[2] !== "installation_capability" ||
    keys[3] !== "operation"
  ) {
    return invalidRequest("Request contains unsupported or missing fields.");
  }
  if (body.operation !== "resolve") {
    return invalidRequest("operation must be resolve.");
  }
  if (
    typeof body.installation_capability !== "string" ||
    !INSTALLATION_CAPABILITY_RE.test(body.installation_capability)
  ) {
    return invalidRequest("installation_capability is invalid.");
  }
  if (
    typeof body.client_protocol !== "number" ||
    !Number.isSafeInteger(body.client_protocol) ||
    body.client_protocol < 1 ||
    body.client_protocol > 1_000
  ) {
    return invalidRequest("client_protocol is invalid.");
  }
  if (
    typeof body.binding_intent_generation !== "number" ||
    !Number.isSafeInteger(body.binding_intent_generation) ||
    body.binding_intent_generation < 1
  ) {
    return invalidRequest("binding_intent_generation is invalid.");
  }

  return {
    operation: "resolve",
    installationCapability: body.installation_capability,
    clientProtocol: body.client_protocol,
    bindingIntentGeneration: body.binding_intent_generation,
  };
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function invalidRequest(message: string): ResolvePurchasePrincipalRequestError {
  return { status: 400, code: "invalid_request", message };
}
