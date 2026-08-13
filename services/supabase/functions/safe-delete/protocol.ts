export const ACCOUNT_DELETION_RECOVERY_MAX_BODY_BYTES = 1024;

const RECOVERY_CAPABILITY_RE = /^[A-Za-z0-9_-]{43}$/;

export type SafeDeleteRequest =
  | { protocolVersion: 1; operation: "commit"; recoveryCapability: null }
  | { protocolVersion: 1; operation: "commit"; recoveryCapability: string }
  | {
    protocolVersion: 2;
    operation: "prepare";
    recoveryCapability: string;
    acknowledgementCapability: string;
  }
  | {
    protocolVersion: 2;
    operation: "commit";
    recoveryCapability: string;
  };

export type AccountDeletionRecoveryRequest =
  | {
    protocolVersion: 1;
    operation: "recover" | "acknowledge";
    capability: string;
  }
  | {
    protocolVersion: 2;
    operation: "recover";
    capability: string;
  }
  | {
    protocolVersion: 2;
    operation: "acknowledge";
    capability: string;
  };

export type AccountDeletionProtocolError = {
  status: 400;
  code: "invalid_request";
  message: string;
};

export function parseSafeDeleteRequest(
  raw: unknown,
): SafeDeleteRequest | AccountDeletionProtocolError {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return invalidRequest("JSON body must be an object.");
  }
  const body = raw as Record<string, unknown>;
  const keys = Object.keys(body).sort();
  if (keys.length === 0) {
    return {
      protocolVersion: 1,
      operation: "commit",
      recoveryCapability: null,
    };
  }
  if (
    keys.length !== 1 ||
    keys[0] !== "recovery_capability" ||
    typeof body.recovery_capability !== "string" ||
    !RECOVERY_CAPABILITY_RE.test(body.recovery_capability)
  ) {
    if (
      body.protocol_version === 2 &&
      body.operation === "prepare" &&
      keys.length === 4 &&
      keys[0] === "acknowledgement_capability" &&
      keys[1] === "operation" &&
      keys[2] === "protocol_version" &&
      keys[3] === "recovery_capability" &&
      typeof body.recovery_capability === "string" &&
      RECOVERY_CAPABILITY_RE.test(body.recovery_capability) &&
      typeof body.acknowledgement_capability === "string" &&
      RECOVERY_CAPABILITY_RE.test(body.acknowledgement_capability) &&
      body.recovery_capability !== body.acknowledgement_capability
    ) {
      return {
        protocolVersion: 2,
        operation: "prepare",
        recoveryCapability: body.recovery_capability,
        acknowledgementCapability: body.acknowledgement_capability,
      };
    }
    if (
      body.protocol_version === 2 &&
      body.operation === "commit" &&
      keys.length === 3 &&
      keys[0] === "operation" &&
      keys[1] === "protocol_version" &&
      keys[2] === "recovery_capability" &&
      typeof body.recovery_capability === "string" &&
      RECOVERY_CAPABILITY_RE.test(body.recovery_capability)
    ) {
      return {
        protocolVersion: 2,
        operation: "commit",
        recoveryCapability: body.recovery_capability,
      };
    }
    return invalidRequest(
      "Request contains an invalid or unsupported recovery capability.",
    );
  }
  return {
    protocolVersion: 1,
    operation: "commit",
    recoveryCapability: body.recovery_capability,
  };
}

export function parseAccountDeletionRecoveryRequest(
  raw: unknown,
): AccountDeletionRecoveryRequest | AccountDeletionProtocolError {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return invalidRequest("JSON body must be an object.");
  }
  const body = raw as Record<string, unknown>;
  const keys = Object.keys(body).sort();
  if (
    keys.length === 2 &&
    keys[0] === "operation" &&
    keys[1] === "recovery_capability" &&
    (body.operation === "recover" || body.operation === "acknowledge") &&
    typeof body.recovery_capability === "string" &&
    RECOVERY_CAPABILITY_RE.test(body.recovery_capability)
  ) {
    return {
      protocolVersion: 1,
      operation: body.operation,
      capability: body.recovery_capability,
    };
  }
  if (
    body.protocol_version === 2 &&
    body.operation === "recover" &&
    keys.length === 3 &&
    keys[0] === "operation" &&
    keys[1] === "protocol_version" &&
    keys[2] === "recovery_capability" &&
    typeof body.recovery_capability === "string" &&
    RECOVERY_CAPABILITY_RE.test(body.recovery_capability)
  ) {
    return {
      protocolVersion: 2,
      operation: "recover",
      capability: body.recovery_capability,
    };
  }
  if (
    body.protocol_version === 2 &&
    body.operation === "acknowledge" &&
    keys.length === 3 &&
    keys[0] === "acknowledgement_capability" &&
    keys[1] === "operation" &&
    keys[2] === "protocol_version" &&
    typeof body.acknowledgement_capability === "string" &&
    RECOVERY_CAPABILITY_RE.test(body.acknowledgement_capability)
  ) {
    return {
      protocolVersion: 2,
      operation: "acknowledge",
      capability: body.acknowledgement_capability,
    };
  }
  return invalidRequest("Recovery request is invalid.");
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

export type AccountDeletionCapabilityPurpose =
  | "v2_recovery"
  | "v2_acknowledgement";

/// Protocol-v2 proofs occupy separate cryptographic namespaces. A raw
/// acknowledgement value therefore cannot be replayed through either the v1
/// recovery route or the v2 recovery route, even if a client deliberately
/// submits the same bytes to more than one operation.
export function hashAccountDeletionCapability(
  value: string,
  purpose: AccountDeletionCapabilityPurpose,
): Promise<string> {
  const domain = purpose === "v2_recovery"
    ? "merian.account-deletion.v2.recovery"
    : "merian.account-deletion.v2.acknowledgement";
  return sha256Hex(`${domain}\0${value}`);
}

function invalidRequest(message: string): AccountDeletionProtocolError {
  return { status: 400, code: "invalid_request", message };
}
