/** Versioned server-sealed proof wrapper; the frozen Identify data stays V1. */
import {
  ContractValueError,
  type IdentifySuccessEnvelope,
  identifyWireEnvelopeContract,
  type InferContract,
  type ObjectContract,
  parseContract,
  parseIdentifySuccessEnvelope,
} from "./contract.ts";

const identity = {
  kind: "string",
  minLength: 36,
  maxLength: 36,
  pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
} as const;

export const initialEvidenceCompletionV1Contract = freeze(
  {
    kind: "object",
    unknownKeys: "reject",
    fields: {
      schema_version: {
        contract: { kind: "integer", minimum: 1, maximum: 1 },
        required: true,
        swift: { name: "schemaVersion" },
      },
      owner_id: {
        contract: identity,
        required: true,
        swift: { name: "ownerID" },
      },
      scan_id: {
        contract: identity,
        required: true,
        swift: { name: "scanID" },
      },
      generation: { contract: identity, required: true },
      evidence_digest: {
        contract: {
          kind: "string",
          minLength: 64,
          maxLength: 64,
          pattern: "^[0-9a-f]{64}$",
        },
        required: true,
        swift: { name: "evidenceDigest" },
      },
    },
    swift: { name: "InitialEvidenceCompletionDTO", declarationOrder: 4 },
  } as const satisfies ObjectContract,
);

/** Generator input composes the legacy envelope without modifying its source. */
export const initialEvidenceEnvelopeV1Contract = freeze(
  {
    ...identifyWireEnvelopeContract,
    fields: {
      ...identifyWireEnvelopeContract.fields,
      initial_evidence: {
        contract: initialEvidenceCompletionV1Contract,
        required: false,
        swift: {
          name: "initialEvidence",
          optional: true,
          rejectExplicitNull: true,
        },
      },
    },
  } as const satisfies ObjectContract,
);

type CompletionProof = InferContract<
  typeof initialEvidenceCompletionV1Contract
>;
export type InitialEvidenceEnvelopeV1 = IdentifySuccessEnvelope & {
  readonly initial_evidence?: CompletionProof;
};

export function parseInitialEvidenceEnvelopeV1(
  value: unknown,
): InitialEvidenceEnvelopeV1 {
  // Legacy data validation and normalization are unchanged. Inspect the original
  // outer object, because the frozen parser correctly strips this new field.
  const legacy = parseIdentifySuccessEnvelope(value);
  const raw = value as Record<string, unknown>;
  if (!Object.hasOwn(raw, "initial_evidence")) return legacy;
  const proof = parseContract(
    initialEvidenceCompletionV1Contract,
    raw.initial_evidence,
    "response.initial_evidence",
  ) as CompletionProof;
  if (
    proof.scan_id !== legacy.data.scan_id ||
    new Set([proof.owner_id, proof.scan_id, proof.generation]).size !== 3
  ) {
    throw new ContractValueError([{
      path: "response.initial_evidence",
      message: "Mismatched initial evidence identity",
    }]);
  }
  return freeze({ ...legacy, initial_evidence: proof });
}

/** Strict callers must install this verifier before dispatching finalization. */
export function initialEvidenceCompletionVerifier(expected: {
  ownerID: string;
  scanID: string;
  generation: string;
  evidenceDigest: string;
}): (value: unknown) => true {
  const proof = freeze(parseContract(initialEvidenceCompletionV1Contract, {
    schema_version: 1,
    owner_id: expected.ownerID,
    scan_id: expected.scanID,
    generation: expected.generation,
    evidence_digest: expected.evidenceDigest,
  }) as CompletionProof);
  if (new Set([proof.owner_id, proof.scan_id, proof.generation]).size !== 3) {
    throw new Error("initial_evidence_completion_integrity");
  }
  return (value): true => {
    const actual = parseInitialEvidenceEnvelopeV1(value).initial_evidence;
    if (
      !actual || actual.owner_id !== proof.owner_id ||
      actual.scan_id !== proof.scan_id ||
      actual.generation !== proof.generation ||
      actual.evidence_digest !== proof.evidence_digest
    ) {
      throw new Error("initial_evidence_completion_integrity");
    }
    return true;
  };
}

function freeze<T>(value: T): T {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value)) freeze(child);
  }
  return value;
}
