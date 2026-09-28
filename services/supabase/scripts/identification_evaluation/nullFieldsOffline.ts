/** Invented photo-only v4 controller demonstration; no paid or production work. */
import { join } from "node:path";
import { createExperimentDemo } from "./experimentOffline.ts";
import { fingerprintJson } from "./evidence.ts";
import { fingerprintRunCorpus, parseRunCorpus } from "./exploratory.ts";
import {
  NULL_FIELDS_METRICS,
  NULL_FIELDS_PLAN_VERSION,
  parseExperimentPlan,
} from "./experimentContracts.ts";
import { parseFactCards, RUBRIC } from "./explanationContracts.ts";
import { atomicJson, privateDirectory, readJson } from "./files.ts";
import type { OfflineFixtures } from "./offline.ts";
import { NULL_FIELDS_PROFILES, reusableProfile } from "./reusableProfiles.ts";
import type { SourceIdentity } from "./runContracts.ts";
import { requireCondition as check } from "./validation.ts";

export async function createNullFieldsDemo(
  root: string,
  source: SourceIdentity,
  now = Date.now(),
) {
  const old = await createExperimentDemo(root, source, now);
  const corpus = parseRunCorpus(await readJson(join(root, "corpus.json")));
  check(corpus.kind === "exploratory");
  const photos = {
    ...corpus,
    cases: corpus.cases.filter((c) => c.input.inputGroup === "photos"),
  };
  const cases = old.cases.filter((c) =>
    photos.cases.some((p) => p.input.caseId === c.caseId)
  );
  await atomicJson(join(root, "corpus.json"), photos);
  const fixtures = await readJson(
    join(root, "fixtures.json"),
  ) as OfflineFixtures;
  const draft = fixtures.cases.find((c) => c.kind === "draft")!.draft;
  fixtures.corpusDigest = await fingerprintRunCorpus(photos);
  fixtures.cases = fixtures.cases.filter((c) =>
    cases.some((p) => p.caseId === c.caseId)
  )
    .map((c) => ({ ...c, kind: "draft", draft: c.draft ?? draft }));
  await atomicJson(join(root, "fixtures.json"), fixtures);
  const facts = parseFactCards({
    version: "explanation_facts_v1",
    cards: cases.map((c) => ({
      ...c,
      observed: ["Invented fixture observation."],
      missing: [],
      acceptableReasons: [
        "Invented explanation for workflow verification only.",
      ],
      rankLimit: "Synthetic mechanics only.",
      requirements: ["decision_evidence"],
    })),
  });
  await privateDirectory(join(root, "review"));
  await atomicJson(join(root, "review", "facts.json"), facts);
  const runs = await Promise.all(
    NULL_FIELDS_PROFILES.map(async (profileId, i) => ({
      ...old.runs[1],
      runId: "offline-null-fields-" + (i + 1),
      profileId,
      profileDigest: (await reusableProfile(profileId)).digest,
      maxCalls: cases.length,
    })),
  );
  const plan = parseExperimentPlan({
    ...old,
    version: NULL_FIELDS_PLAN_VERSION,
    experimentId: "offline-null-fields-v1",
    corpusDigest: await fingerprintRunCorpus(photos),
    cases,
    runs,
    maxCalls: cases.length * 2,
    metrics: NULL_FIELDS_METRICS,
    candidateDecision: "null_fields_consistency_ai_review_v1",
    review: {
      reviewerRef: "synthetic-assistant-review",
      method: "assistant_local_v1",
      delegationRef: "synthetic-delegation",
      timeoutMs: 600000,
      rubricDigest: await fingerprintJson(RUBRIC),
      factsDigest: await fingerprintJson(facts),
      calibrationDigest: null,
      cards: await Promise.all(facts.cards.map(async (c) => ({
        caseId: c.caseId,
        digest: await fingerprintJson(c),
      }))),
    },
  });
  await atomicJson(join(root, "experiment.json"), plan);
  return plan;
}
