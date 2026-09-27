/** Synthetic demonstration of candidate mechanics, never a scored human review. */
import { join } from "node:path";
import { OPENAI_CANDIDATE_PROFILES } from "../../functions/_shared/ai/openaiRequest.ts";
import { createExperimentDemo } from "./experimentOffline.ts";
import {
  CALIBRATION_EXAMPLES,
  calibrationRecord,
} from "./explanationCalibration.ts";
import { parseFactCards, RUBRIC } from "./explanationContracts.ts";
import { fingerprintJson } from "./evidence.ts";
import { parseExperimentPlan } from "./experimentContracts.ts";
import { atomicJson, privateDirectory, readJson } from "./files.ts";
import type { OfflineFixtures } from "./offline.ts";
import { reusableProfile } from "./reusableProfiles.ts";
import type { SourceIdentity } from "./runContracts.ts";
export async function createCandidateDemo(
  root: string,
  source: SourceIdentity,
  now = Date.now(),
) {
  const old = await createExperimentDemo(root, source, now);
  const facts = parseFactCards({
    version: "explanation_facts_v1",
    cards: old.cases.map((c) => ({
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
  const calibration = await calibrationRecord(
    "synthetic-reviewer",
    CALIBRATION_EXAMPLES.map((c) => c.expected),
    "synthetic_fixture_v1",
  );
  await atomicJson(join(root, "review", "facts.json"), facts);
  await atomicJson(join(root, "review", "calibration.json"), calibration);
  const fixtures = await readJson(
    join(root, "fixtures.json"),
  ) as OfflineFixtures;
  const draft = fixtures.cases.find((c) => c.kind === "draft")!.draft;
  fixtures.cases = fixtures.cases.map((c) => ({
    ...c,
    kind: "draft",
    draft: c.draft ?? draft,
  }));
  await atomicJson(join(root, "fixtures.json"), fixtures);
  const runs = await Promise.all(
    OPENAI_CANDIDATE_PROFILES.map(async (profileId, i) => ({
      ...old.runs[1],
      runId: `offline-concise-${i + 1}`,
      profileId,
      profileDigest: (await reusableProfile(profileId)).digest,
    })),
  );
  const plan = parseExperimentPlan({
    ...old,
    version: "identification_experiment_plan_v2",
    experimentId: "offline-concise-v1",
    runs,
    cacheControl: "explicit_no_breakpoints_v1",
    candidateDecision: "concise_explanation_latency_v1",
    review: {
      reviewerRef: calibration.reviewerRef,
      timeoutMs: 600000,
      rubricDigest: await fingerprintJson(RUBRIC),
      factsDigest: await fingerprintJson(facts),
      calibrationDigest: await fingerprintJson(calibration),
      cards: await Promise.all(
        facts.cards.map(async (c) => ({
          caseId: c.caseId,
          digest: await fingerprintJson(c),
        })),
      ),
    },
  });
  await atomicJson(join(root, "experiment.json"), plan);
  return plan;
}
