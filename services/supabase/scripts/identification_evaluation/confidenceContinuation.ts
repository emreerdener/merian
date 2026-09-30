import { join } from "node:path";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import { exists, readBytes, readJson } from "./files.ts";
import { CONFIDENCE_PROTOCOL as P } from "./confidenceProtocol.ts";
import { hash, type SourceIdentity } from "./runContracts.ts";
import {
  fields,
  integer,
  requireCondition as check,
  token,
} from "./validation.ts";

/** Explicit owner-approved cumulative cap; never a fresh study or request budget. */
export const CONTINUATION_BUDGET_NANO_USD = 20_000_000_000;
export interface ConfidenceContinuation {
  version: "openai_confidence_continuation_v1";
  originalManifestDigest: string;
  originalSourceDigest: string;
  replacementSource: SourceIdentity;
  authorizationRef: string;
  reviewRef: string;
  budgetKind: "cumulative_total";
  budgetNanoUsd: number;
  maxAttempts: number;
  nextOrdinal: number;
  journalPrefix: {
    attempted: number;
    settledNanoUsd: number;
    outstandingNanoUsd: 0;
    digest: string;
  };
}

export async function confidenceJournalPrefixDigest(
  root: string,
  caseIds: string[],
) {
  const records = [];
  for (const caseId of caseIds) {
    for (const suffix of ["claim", "result", "reconciliation"]) {
      const file = `${caseId}.${suffix}.json`;
      const path = join(root, "confidence-attempts", file);
      records.push({
        file,
        digest: await exists(path)
          ? await fingerprintBytes(await readBytes(path, 128 * 1024))
          : null,
      });
    }
  }
  return await fingerprintJson(records);
}

export async function readConfidenceContinuation(
  root: string,
  originalManifestDigest: string,
  originalSourceDigest: string,
  source: SourceIdentity,
): Promise<ConfidenceContinuation | null> {
  const path = join(root, "confidence-continuation.json");
  if (!await exists(path)) return null;
  const v = fields(await readJson(path), [
    "version",
    "originalManifestDigest",
    "originalSourceDigest",
    "replacementSource",
    "authorizationRef",
    "reviewRef",
    "budgetKind",
    "budgetNanoUsd",
    "maxAttempts",
    "nextOrdinal",
    "journalPrefix",
  ]);
  check(
    v.version === "openai_confidence_continuation_v1" &&
      v.originalManifestDigest === originalManifestDigest &&
      v.originalSourceDigest === originalSourceDigest &&
      v.budgetKind === "cumulative_total" &&
      v.budgetNanoUsd === CONTINUATION_BUDGET_NANO_USD &&
      v.maxAttempts === P.maxAttempts,
  );
  token(v.authorizationRef);
  token(v.reviewRef);
  check(
    await fingerprintJson(v.replacementSource) ===
      await fingerprintJson(source),
  );
  const prefix = fields(v.journalPrefix, [
    "attempted",
    "settledNanoUsd",
    "outstandingNanoUsd",
    "digest",
  ]);
  integer(prefix.attempted, 1, P.maxAttempts - 1);
  integer(prefix.settledNanoUsd, 0, P.budgetNanoUsd);
  check(
    prefix.outstandingNanoUsd === 0 && v.nextOrdinal === prefix.attempted + 1,
  );
  hash(prefix.digest);
  return structuredClone(v) as unknown as ConfidenceContinuation;
}
