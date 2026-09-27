/** Network/key-free preparation. It cannot create a claim or dispatch a model. */
import { join } from "node:path";
import { assertOfflinePermissions, validateSelection } from "./admission.ts";
import { prepareEvidence } from "./assets.ts";
import { INPUT_GROUPS } from "./contracts.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  fingerprintRunCorpus,
  parseRunCorpus,
  referenceLabels,
} from "./exploratory.ts";
import { atomicJson, exists, readJson } from "./files.ts";
import { assignmentFor, interleave } from "./profiles.ts";
import {
  GEMINI_PROFILES,
  parseEvaluationPricing,
  parseRunSpec,
  parseTaxonomy,
  PROVIDER_SPEC_VERSION,
  referenceTaxaExist,
  type SourceIdentity,
} from "./runContracts.ts";
import { requireCondition as check } from "./validation.ts";

export async function preflightCorpus(
  root: string,
  source: SourceIdentity,
  now = Date.now(),
) {
  await assertOfflinePermissions();
  const corpus = parseRunCorpus(await readJson(join(root, "corpus.json")));
  check(corpus.cases.length <= 300);
  const taxonomy = parseTaxonomy(
    await readJson(join(root, "taxonomy.json"), 32 * 1024 * 1024),
  );
  check(corpus.taxonomyVersion === taxonomy.taxonomyVersion);
  check(
    referenceTaxaExist(
      taxonomy,
      referenceLabels(corpus).flatMap((r) => [...r.acceptableTaxa]),
    ),
  );
  const pricing = await exists(join(root, "pricing.json"))
    ? parseEvaluationPricing(await readJson(join(root, "pricing.json")))
    : null;
  if (pricing) {
    check(
      now >= Date.parse(pricing.retrievedAt) &&
        now - Date.parse(pricing.retrievedAt) <= 7 * 86400000,
    );
  }
  // Legacy corpus-only preflight stays Gemini-only. A provider spec explicitly selects scope.
  const spec = await exists(join(root, "spec.json"))
    ? parseRunSpec(await readJson(join(root, "spec.json")))
    : null;
  const scoped = spec?.version === PROVIDER_SPEC_VERSION ? spec : null;
  if (scoped) await validateSelection(corpus, scoped, taxonomy);
  const profiles = scoped?.profiles ?? GEMINI_PROFILES;
  const cases = scoped
    ? corpus.cases.filter((c) => scoped.caseIds.includes(c.input.caseId))
    : corpus.cases;
  check(!scoped || cases.length === scoped.caseIds.length);
  const assignments = [];
  for (const c of cases) {
    const request = await prepareEvidence(root, c.input);
    for (const profile of profiles) {
      assignments.push(
        await assignmentFor(c.input, request, profile, 1, pricing),
      );
    }
  }
  const report = {
    version: "identification_preflight_v1",
    dispatchAuthorized: false,
    corpusDigest: await fingerprintRunCorpus(corpus),
    taxonomyDigest: await fingerprintJson(taxonomy),
    evidenceKind: corpus.kind,
    source,
    groups: cases.length,
    referenceLabels:
      cases.filter((c) => "reference" in c || c.provisionalReference !== null)
        .length,
    coverage: Object.fromEntries(
      INPUT_GROUPS.map((g) => [
        g,
        cases.filter((c) => c.input.inputGroup === g).length,
      ]),
    ),
    profiles,
    plannedCalls: assignments.length,
    pricingDigest: pricing ? await fingerprintJson(pricing) : null,
    fullScheduleReservationUsd: pricing
      ? assignments.reduce((n, a) => n + a.reservedUsd, 0)
      : null,
    requiredBeforeLive: [
      "review_exact_corpus_and_source",
      "current_pricing_and_token_ceilings",
      "reviewed_provider_project_and_credential",
      "explicit_run_spec_and_usd_budget_authorization",
    ],
    order: interleave(assignments, corpus.splitSeed),
  };
  await atomicJson(join(root, "preflight.json"), report);
  return report;
}
