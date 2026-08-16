export const PURCHASE_PRINCIPAL_MAX_BODY_BYTES = 2 * 1024;
/// Protocol emitted by the current iOS candidate and required before a new
/// stable principal can activate. Resolve remains backward-compatible while
/// protocol 3 adds server-authorized stable sign-out rotations.
export const PURCHASE_PRINCIPAL_CLIENT_PROTOCOL = 3;
export const PURCHASE_PRINCIPAL_SIGNOUT_ROTATION_PROTOCOL = 3;

const INSTALLATION_CAPABILITY_RE = /^[A-Za-z0-9_-]{43}$/;
const ROTATION_SECRET_RE = /^[A-Za-z0-9_-]{43}$/;
const UUID_V4_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export interface ResolvePurchasePrincipalRequest {
  operation: "resolve";
  installationCapability: string;
  clientProtocol: number;
  bindingIntentGeneration: number;
}

export interface PreparePurchasePrincipalSignoutRotationRequest {
  operation: "prepare_signout_rotation";
  installationCapability: string;
  clientProtocol: number;
  rotationId: string;
  rotationSecret: string;
  expectedBindingGeneration: number;
}

export interface ClaimPurchasePrincipalSignoutRotationRequest {
  operation: "claim_signout_rotation";
  installationCapability: string;
  clientProtocol: number;
  rotationId: string;
  rotationSecret: string;
}

export interface CancelPurchasePrincipalSignoutRotationRequest {
  operation: "cancel_signout_rotation";
  installationCapability: string;
  clientProtocol: number;
  rotationId: string;
  rotationSecret: string;
}

export type PurchasePrincipalRequest =
  | ResolvePurchasePrincipalRequest
  | PreparePurchasePrincipalSignoutRotationRequest
  | ClaimPurchasePrincipalSignoutRotationRequest
  | CancelPurchasePrincipalSignoutRotationRequest;

export interface ResolvePurchasePrincipalRequestError {
  status: 400;
  code: "invalid_request";
  message: string;
}

export function parseResolvePurchasePrincipalRequest(
  raw: unknown,
): PurchasePrincipalRequest | ResolvePurchasePrincipalRequestError {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return invalidRequest("JSON body must be an object.");
  }

  const body = raw as Record<string, unknown>;
  const keys = Object.keys(body).sort();
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

  switch (body.operation) {
    case "resolve":
      if (
        !hasExactKeys(keys, [
          "binding_intent_generation",
          "client_protocol",
          "installation_capability",
          "operation",
        ])
      ) {
        return invalidRequest(
          "Request contains unsupported or missing fields.",
        );
      }
      if (!isPositiveSafeInteger(body.binding_intent_generation)) {
        return invalidRequest("binding_intent_generation is invalid.");
      }
      return {
        operation: "resolve",
        installationCapability: body.installation_capability,
        clientProtocol: body.client_protocol,
        bindingIntentGeneration: body.binding_intent_generation,
      };
    case "prepare_signout_rotation":
      if (
        !hasExactKeys(keys, [
          "client_protocol",
          "expected_binding_generation",
          "installation_capability",
          "operation",
          "rotation_id",
          "rotation_secret",
        ])
      ) {
        return invalidRequest(
          "Request contains unsupported or missing fields.",
        );
      }
      if (!isRotationRequest(body)) {
        return invalidRequest("Sign-out rotation fields are invalid.");
      }
      if (!isPositiveSafeInteger(body.expected_binding_generation)) {
        return invalidRequest("expected_binding_generation is invalid.");
      }
      return {
        operation: "prepare_signout_rotation",
        installationCapability: body.installation_capability,
        clientProtocol: body.client_protocol,
        rotationId: body.rotation_id.toLowerCase(),
        rotationSecret: body.rotation_secret,
        expectedBindingGeneration: body.expected_binding_generation,
      };
    case "claim_signout_rotation":
    case "cancel_signout_rotation": {
      if (
        !hasExactKeys(keys, [
          "client_protocol",
          "installation_capability",
          "operation",
          "rotation_id",
          "rotation_secret",
        ])
      ) {
        return invalidRequest(
          "Request contains unsupported or missing fields.",
        );
      }
      if (!isRotationRequest(body)) {
        return invalidRequest("Sign-out rotation fields are invalid.");
      }
      return {
        operation: body.operation,
        installationCapability: body.installation_capability,
        clientProtocol: body.client_protocol,
        rotationId: body.rotation_id.toLowerCase(),
        rotationSecret: body.rotation_secret,
      };
    }
    default:
      return invalidRequest("operation is invalid.");
  }
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

function hasExactKeys(actual: string[], expected: string[]): boolean {
  return actual.length === expected.length &&
    actual.every((key, index) => key === expected[index]);
}

function isPositiveSafeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

function isRotationRequest(body: Record<string, unknown>): body is
  & Record<string, unknown>
  & {
    installation_capability: string;
    client_protocol: number;
    rotation_id: string;
    rotation_secret: string;
  } {
  return typeof body.installation_capability === "string" &&
    INSTALLATION_CAPABILITY_RE.test(body.installation_capability) &&
    typeof body.client_protocol === "number" &&
    Number.isSafeInteger(body.client_protocol) &&
    body.client_protocol >= PURCHASE_PRINCIPAL_SIGNOUT_ROTATION_PROTOCOL &&
    body.client_protocol <= 1_000 &&
    typeof body.rotation_id === "string" &&
    UUID_V4_RE.test(body.rotation_id) &&
    typeof body.rotation_secret === "string" &&
    ROTATION_SECRET_RE.test(body.rotation_secret);
}
