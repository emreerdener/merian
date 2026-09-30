import { join } from "node:path";
import type { PreparedConfidenceStudy } from "./confidencePreparation.ts";
import { CONFIDENCE_PROTOCOL as P } from "./confidenceProtocol.ts";
import { fingerprintJson } from "./evidence.ts";
import { exists, privateDirectory, readJson } from "./files.ts";
import { confidenceJournalPrefixDigest } from "./confidenceContinuation.ts";
import {
  confidenceCost,
  parseConfidenceAccounting,
} from "./confidenceAccounting.ts";
import {
  fields,
  integer,
  requireCondition as check,
  token,
} from "./validation.ts";
import {
  type ConfidenceObservation,
  parseConfidenceObservation,
} from "./confidenceScoring.ts";

export function confidenceClaim(study: PreparedConfidenceStudy, index: number) {
  const a = study.manifest.assignments[index];
  return {
    version: "openai_confidence_claim_v1",
    manifestDigest: study.digest,
    ordinal: index + 1,
    ...a,
  };
}
export async function readConfidenceLedger(
  root: string,
  study: PreparedConfidenceStudy,
) {
  const journal = await privateDirectory(join(root, "confidence-attempts"));
  const observations: ConfidenceObservation[] = [];
  let attempted = 0, settledNanoUsd = 0, outstandingNanoUsd = 0;
  let missing = false;
  const allowed = new Set<string>();
  for (const [i, a] of study.manifest.assignments.entries()) {
    const base = join(journal, a.caseId), claim = confidenceClaim(study, i);
    const claimed = await exists(base + ".claim.json");
    for (const suffix of ["claim", "result", "reconciliation"]) {
      allowed.add(`${a.caseId}.${suffix}.json`);
    }
    if (!claimed) {
      missing = true;
      check(
        !await exists(base + ".result.json") &&
          !await exists(base + ".reconciliation.json"),
      );
      continue;
    }
    check(!missing); // Journal must be an unbroken prefix of the frozen order.
    check(
      await fingerprintJson(await readJson(base + ".claim.json")) ===
        await fingerprintJson(claim),
    );
    attempted++;
    let charged: number | null = null;
    let observation: ConfidenceObservation = {
      prediction: { caseId: a.caseId, outcome: "unknown_execution" },
      mapping: null,
    };
    if (await exists(base + ".result.json")) {
      const value = await readJson(base + ".result.json");
      const v2 = (value as { version?: unknown })?.version ===
        "openai_confidence_result_v2";
      const r = fields(value, [
        "version",
        "claimDigest",
        "observation",
        "settledNanoUsd",
        ...(v2 ? ["accounting"] : []),
      ]);
      check(
        (r.version === "openai_confidence_result_v1" || v2) &&
          r.claimDigest === await fingerprintJson(claim),
      );
      if (v2) {
        check(
          r.settledNanoUsd === confidenceCost(
            parseConfidenceAccounting(r.accounting),
            study.pricing,
          ),
        );
      }
      observation = parseConfidenceObservation(r.observation);
      check(
        observation.prediction.caseId === a.caseId &&
          observation.prediction.outcome !== "unattempted",
      );
      if (r.settledNanoUsd !== null) {
        integer(r.settledNanoUsd, 0, a.reservationNanoUsd);
        charged = r.settledNanoUsd;
      }
    }
    if (await exists(base + ".reconciliation.json")) {
      // A reviewed provider billing receipt can close accounting, never replay or rewrite the outcome.
      check(charged === null);
      const r = fields(await readJson(base + ".reconciliation.json"), [
        "version",
        "claimDigest",
        "billingEvidenceRef",
        "reviewRef",
        "settledNanoUsd",
      ]);
      check(
        r.version === "openai_confidence_reconciliation_v1" &&
          r.claimDigest === await fingerprintJson(claim),
      );
      token(r.billingEvidenceRef);
      token(r.reviewRef);
      integer(r.settledNanoUsd, 0, a.reservationNanoUsd);
      charged = r.settledNanoUsd;
    }
    if (charged === null) outstandingNanoUsd += a.reservationNanoUsd;
    else settledNanoUsd += charged;
    observations.push(observation);
    if (study.continuation?.journalPrefix.attempted === attempted) {
      const prefix = study.continuation.journalPrefix;
      check(
        prefix.settledNanoUsd === settledNanoUsd && outstandingNanoUsd === 0,
      );
    }
  }
  for await (const entry of Deno.readDir(journal)) {
    check(entry.isFile && !entry.isSymlink && allowed.has(entry.name));
  }
  check(
    attempted <= P.maxAttempts &&
      Number.isSafeInteger(settledNanoUsd + outstandingNanoUsd) &&
      settledNanoUsd + outstandingNanoUsd <= study.budgetNanoUsd,
  );
  if (study.continuation) {
    const prefix = study.continuation.journalPrefix;
    check(
      attempted >= prefix.attempted &&
        await confidenceJournalPrefixDigest(
            root,
            study.manifest.assignments
              .slice(0, prefix.attempted).map((a) => a.caseId),
          ) === prefix.digest,
    );
  }
  return {
    journal,
    observations,
    attempted,
    settledNanoUsd,
    outstandingNanoUsd,
    costComplete: outstandingNanoUsd === 0,
  };
}
export type ConfidenceLedger = Awaited<ReturnType<typeof readConfidenceLedger>>;
