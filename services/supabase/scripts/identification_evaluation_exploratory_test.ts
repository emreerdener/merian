import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  validateLiveApproval,
  validateSelection,
} from "./identification_evaluation/admission.ts";
import {
  fingerprintBytes,
  fingerprintEvidence,
  fingerprintJson,
  projectEvaluationEvidence,
} from "./identification_evaluation/evidence.ts";
import {
  EXPLORATORY_CORPUS_VERSION,
  EXPLORATORY_SPEC_VERSION,
  fingerprintRunCorpus,
  parseExploratoryCorpus,
} from "./identification_evaluation/exploratory.ts";
import { exploratoryAgreement } from "./identification_evaluation/exploratoryReport.ts";
import { syntheticCorpus } from "./identification_evaluation/fixtures.ts";
import {
  MODELS,
  parseRunSpec,
  parseTaxonomy,
} from "./identification_evaluation/runContracts.ts";
import { parseEvaluationCorpus } from "./identification_evaluation/validation.ts";

// Invented descriptors/reviews; no real media, permission or paid approval.
function fixture(real = false) {
  return parseExploratoryCorpus({
    version: EXPLORATORY_CORPUS_VERSION,
    id: "synthetic-exploratory",
    kind: "exploratory",
    evidenceOrigin: real ? "real" : "synthetic",
    taxonomyVersion: "synthetic-v1",
    preparationVersion: "synthetic-v1",
    splitSeed: 42,
    eligibility: real
      ? {
        recordRef: "synthetic-review",
        reviewerRef: "r0001",
        reviewerKind: "automated",
        retainUntil: "2027-01-01",
      }
      : null,
    cases: syntheticCorpus().cases.slice(0, 3).map((c, i) => ({
      input: c.input,
      provisionalReference: i === 0 ? c.reference : null,
      curation: real
        ? {
          kind: "eligibility_reviewed",
          source: "licensed",
          sourceRecordRef: "synthetic-source",
          referenceRecordRef: i === 0 ? "synthetic-reference" : null,
          permission: "gemini_evaluation",
          rightsApproved: true,
          personalDataExcluded: true,
          nearDuplicatesReviewed: true,
        }
        : { kind: "synthetic" },
    })),
  });
}
const taxonomy = parseTaxonomy({
  version: "evaluation_taxonomy_v1",
  taxonomyVersion: "synthetic-v1",
  taxa: [{
    taxon: { id: "synthetic:1", rank: "species" },
    names: ["Syntheticus primus"],
  }],
});
async function spec(c = fixture()) {
  return parseRunSpec({
    version: EXPLORATORY_SPEC_VERSION,
    runId: "synthetic-exploratory",
    mode: c.evidenceOrigin === "real" ? "live" : "offline",
    corpusDigest: await fingerprintRunCorpus(c),
    taxonomyDigest: await fingerprintJson(taxonomy),
    split: "development",
    stage: "exploratory",
    profiles: ["gemini_flash_free", "gemini_pro"],
    caseIds: c.cases.map((c) => c.input.caseId),
    repeats: 1,
    orderSeed: 42,
    maxCalls: 6,
    budgetUsd: c.evidenceOrigin === "real" ? 10 : 0,
    pricingDigest: c.evidenceOrigin === "real" ? "0".repeat(64) : null,
    readinessDigest: c.evidenceOrigin === "real" ? "0".repeat(64) : null,
  });
}
Deno.test("exploratory admission is separate from formal evidence and preserves eligibility checks", () => {
  const c = fixture(true);
  assertEquals(c.cases[1].provisionalReference, null);
  assertThrows(() => parseEvaluationCorpus(c));
  assertThrows(() => parseExploratoryCorpus({ ...c, eligibility: null }));
  assertThrows(() =>
    parseExploratoryCorpus({ ...c, approval: { approved: true } })
  );
  for (
    const field of [
      "rightsApproved",
      "personalDataExcluded",
      "nearDuplicatesReviewed",
    ] as const
  ) {
    assertThrows(() =>
      parseExploratoryCorpus({
        ...c,
        cases: c.cases.map((r) => ({
          ...r,
          curation: { ...r.curation, [field]: false },
        })),
      })
    );
  }
  assertThrows(() =>
    parseExploratoryCorpus({
      ...c,
      cases: c.cases.map((r) => ({
        ...r,
        input: { ...r.input, split: "held_out" },
      })),
    })
  );
  assertThrows(() =>
    parseExploratoryCorpus({ ...c, cases: [...c.cases, c.cases[0]] })
  );
  assertThrows(() =>
    parseExploratoryCorpus({ ...c, evidenceOrigin: "synthetic" })
  );
  assertThrows(() =>
    parseEvaluationCorpus({
      ...syntheticCorpus(),
      cases: [{ ...syntheticCorpus().cases[0], reference: null }],
    })
  );
});
Deno.test("provisional labels and source reviews cannot enter requests, and changes alter only the corpus digest", async () => {
  const c = fixture(), changed = structuredClone(c);
  changed.cases[0].provisionalReference = null;
  assert(await fingerprintRunCorpus(c) !== await fingerprintRunCorpus(changed));
  assertEquals(
    await fingerprintEvidence(c.cases[0].input),
    await fingerprintEvidence(changed.cases[0].input),
  );
  assertThrows(() => projectEvaluationEvidence(c.cases[0]));
  assertThrows(() =>
    projectEvaluationEvidence({
      ...c.cases[0].input,
      provisionalReference: c.cases[0].provisionalReference,
    })
  );
});
Deno.test("exploratory selection cannot unlock formal stages, synthetic live calls, or partial repeated schedules", async () => {
  const c = fixture(), s = await spec(c);
  await validateSelection(c, s, taxonomy);
  await assertRejects(() =>
    validateSelection(c, { ...s, mode: "live" }, taxonomy)
  );
  const real = fixture(true), live = await spec(real);
  await validateSelection(real, live, taxonomy);
  await assertRejects(() =>
    validateSelection(real, { ...live, mode: "offline" }, taxonomy)
  );
  await assertRejects(() =>
    validateSelection(c, { ...s, stage: "development" }, taxonomy)
  );
  await assertRejects(() =>
    validateSelection(c, { ...s, caseIds: s.caseIds.slice(0, 1) }, taxonomy)
  );
  assertThrows(() =>
    parseRunSpec({ ...s, version: "identification_run_spec_v1" })
  );
  assertThrows(() => parseRunSpec({ ...s, repeats: 2 }));
  assertThrows(() => parseRunSpec({ ...s, maxCalls: 25 }));
  assertThrows(() => parseRunSpec({ ...live, budgetUsd: 0 }));
});
Deno.test("unknown references affect operational counts only, even for confident named outputs and failures", () => {
  const c = fixture();
  const r = exploratoryAgreement(c, [
    {
      caseId: "c0001",
      outcome: "normalized",
      subject: "biological",
      resolution: "named",
      taxon: { id: "synthetic:1", rank: "species" },
      confidence: .99,
    },
    {
      caseId: "c0002",
      outcome: "normalized",
      subject: "biological",
      resolution: "named",
      taxon: null,
      confidence: 1,
    },
    { caseId: "c0003", outcome: "operational_failure" },
  ], "gemini_flash_free");
  assertEquals(r.referenceCounts, {
    independentlyReviewed: 0,
    provisional: 1,
    unverified: 2,
  });
  assertEquals(r.namedOutputs, 2);
  assertEquals(r.outcomes.operational_failure, 1);
  assertEquals(r.provisionalAgreement.offeredIdentity, {
    numerator: 1,
    denominator: 1,
    value: 1,
    status: "measured",
  });
  assertEquals(r.provisionalAgreement.strongDisagreement.denominator, 1);
  assertEquals(r.provisionalAgreement.unresolved.denominator, 0);
  const unknown = exploratoryAgreement(
    { ...c, cases: c.cases.map((r) => ({ ...r, provisionalReference: null })) },
    [],
    "gemini_pro",
  );
  for (const rate of Object.values(unknown.provisionalAgreement)) {
    assertEquals(rate.denominator, 0);
  }
  assertEquals(unknown.outcomes.unattempted, 3);
});
Deno.test("exploratory live readiness still binds the actual key, pricing and retention before any I/O", async () => {
  const c = fixture(true), now = Date.parse("2026-09-22T12:00:00.000Z");
  const pricing = {
    version: "evaluation_pricing_v1",
    currency: "USD",
    service: "paid_standard_synchronous",
    retrievedAt: "2026-09-22T00:00:00.000Z",
    sourceUrl: "https://ai.google.dev/gemini-api/docs/pricing",
    reviewRef: "synthetic-pricing",
    includesReasoning: true,
    models: MODELS.map((model) => ({
      model,
      inputPerMillion: { text: 1, image: 1, audio: 1, cached: 1 },
      outputPerMillion: 1,
      maxInputTokens: 1000,
      maxBillableOutputTokens: 8192,
      limitsEvidenceRef: "synthetic-ceiling",
    })),
  };
  const key = "synthetic-exploratory-key";
  const readiness = {
    version: "evaluation_processor_v1",
    corpusDigest: await fingerprintRunCorpus(c),
    projectRef: "synthetic-project",
    credentialRef: "synthetic-credential",
    credentialSha256: await fingerprintBytes(new TextEncoder().encode(key)),
    reviewedAt: "2026-09-22T00:00:00.000Z",
    expiresAt: "2026-09-23T00:00:00.000Z",
    reviewerRole: "synthetic-role",
    dedicatedEvaluationProject: true,
    paidServiceApproved: true,
    purpose: "identification_evaluation",
    termsRef: "synthetic-terms",
    dataUseRef: "synthetic-data-use",
    regionSubprocessorRef: "synthetic-region",
    retentionAbuseLogRef: "synthetic-retention",
  };
  const s = {
    ...await spec(c),
    pricingDigest: await fingerprintJson(pricing),
    readinessDigest: await fingerprintJson(readiness),
  };
  await validateLiveApproval(c, s, pricing, readiness, key, now);
  await assertRejects(() =>
    validateLiveApproval(c, s, pricing, readiness, "different", now)
  );
  await assertRejects(() =>
    validateLiveApproval(c, s, pricing, readiness, key, now + 2 * 86400000)
  );
  await assertRejects(() =>
    validateLiveApproval(
      c,
      s,
      pricing,
      { ...readiness, paidServiceApproved: false },
      key,
      now,
    )
  );
  const expired = {
    ...c,
    eligibility: { ...c.eligibility!, retainUntil: "2026-09-01" },
  };
  const changed = {
    ...readiness,
    corpusDigest: await fingerprintRunCorpus(expired),
  };
  await assertRejects(async () =>
    validateLiveApproval(
      expired,
      {
        ...s,
        corpusDigest: changed.corpusDigest,
        readinessDigest: await fingerprintJson(changed),
      },
      pricing,
      changed,
      key,
      now,
    )
  );
});
