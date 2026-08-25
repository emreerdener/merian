import { assertEquals, assertStringIncludes } from "@std/assert";
import type { ReleaseEvidenceVerifier } from "./github_release_evidence.ts";
import {
  evaluateProductionReleaseClearance,
  evaluateProductionReleaseHolds,
  sha256Hex,
} from "./verify_production_release_holds.ts";

const holdId = "species_dictionary_chat_production_hold";
const candidateSha = "a".repeat(40);
const criterionDefinitions = [
  ["database_proof", "disposable_database_run"],
  ["hosted_proof", "hosted_test_run"],
] as const;

function manifest(active: boolean): string {
  return JSON.stringify({
    schema_version: 3,
    holds: [{
      id: holdId,
      active,
      scope: "supabase_production",
      owner: "Merian release owner",
      reason: "Candidate evidence is incomplete.",
      exit_criteria: criterionDefinitions.map(([id, evidenceType]) => ({
        id,
        description: `Complete ${id}.`,
        evidence_type: evidenceType,
        required_workflows: [".github/workflows/test.yml"],
      })),
    }],
  });
}

async function clearance(
  manifestRaw: string,
): Promise<Record<string, unknown>> {
  return {
    schema_version: 2,
    environment: "Production",
    candidate_sha: candidateSha,
    manifest_sha256: await sha256Hex(manifestRaw),
    approved_at: "2026-08-24T12:00:00.000Z",
    expires_at: "2026-08-25T12:00:00.000Z",
    holds: [{
      hold_id: holdId,
      criteria: criterionDefinitions.map(([id, evidenceType], index) => ({
        id,
        evidence_type: evidenceType,
        artifact_id: index + 1,
        artifact_sha256: String(index + 1).repeat(64),
      })),
    }],
  };
}

const verificationTime = new Date("2026-08-24T18:00:00.000Z");
const evidenceVerifier: ReleaseEvidenceVerifier = {
  verifyRepositoryControls: () => Promise.resolve(["protected_main"]),
  verifyCriterion: (input) =>
    Promise.resolve(
      `github-actions-artifact:${input.artifactId}:sha256:${input.artifactSha256}`,
    ),
};

Deno.test("an active checked-in hold blocks Supabase production", async () => {
  const decision = await evaluateProductionReleaseHolds(
    "manifest.json",
    () => Promise.resolve(manifest(true)),
  );
  assertEquals(decision.allowed, false);
  assertEquals(decision.activeHoldIds, [holdId]);
  assertStringIncludes(decision.summary, "Candidate evidence is incomplete.");
});

Deno.test("the repository keeps the Species Dictionary production hold active", async () => {
  const decision = await evaluateProductionReleaseHolds(
    new URL("../release-holds.json", import.meta.url),
  );
  assertEquals(decision.allowed, false);
  assertEquals(decision.activeHoldIds, [holdId]);
});

Deno.test("an inactive source hold still requires protected clearance", async () => {
  const manifestRaw = manifest(false);
  const sourceDecision = await evaluateProductionReleaseHolds(
    "manifest.json",
    () => Promise.resolve(manifestRaw),
  );
  assertEquals(sourceDecision.allowed, true);

  const productionDecision = await evaluateProductionReleaseClearance(
    "manifest.json",
    undefined,
    candidateSha,
    verificationTime,
    () => Promise.resolve(manifestRaw),
    evidenceVerifier,
  );
  assertEquals(productionDecision.allowed, false);
  assertStringIncludes(productionDecision.summary, "no clearance record");
});

Deno.test("protected clearance binds candidate, manifest, criteria, and evidence", async () => {
  const manifestRaw = manifest(false);
  const clearanceRaw = JSON.stringify(await clearance(manifestRaw));
  const decision = await evaluateProductionReleaseClearance(
    "manifest.json",
    clearanceRaw,
    candidateSha,
    verificationTime,
    () => Promise.resolve(manifestRaw),
    evidenceVerifier,
  );
  assertEquals(decision.allowed, true);
  assertEquals(decision.verifiedCriterionIds, [
    `${holdId}:database_proof`,
    `${holdId}:hosted_proof`,
  ]);
  assertEquals(decision.clearanceSha256.length, 64);
  assertEquals(decision.verifiedRepositoryControls, ["protected_main"]);
  assertEquals(decision.verifiedEvidenceReferences.length, 2);
});

Deno.test("clearance mismatches and stale approvals fail closed", async () => {
  const manifestRaw = manifest(false);
  const baseline = await clearance(manifestRaw);
  const cases: Record<string, unknown>[] = [
    { ...baseline, candidate_sha: "c".repeat(40) },
    { ...baseline, manifest_sha256: "c".repeat(64) },
    { ...baseline, environment: "Staging" },
    { ...baseline, expires_at: "2026-08-24T17:00:00.000Z" },
    { ...baseline, expires_at: "2026-09-24T12:00:00.000Z" },
    {
      ...baseline,
      holds: [{
        hold_id: holdId,
        criteria: [{
          id: "database_proof",
          evidence_type: "disposable_database_run",
          artifact_id: 1,
          artifact_sha256: "1".repeat(64),
        }],
      }],
    },
    {
      ...baseline,
      holds: [{
        hold_id: holdId,
        criteria: criterionDefinitions.map(([id], index) => ({
          id,
          evidence_type: "wrong_evidence_type",
          artifact_id: index + 1,
          artifact_sha256: String(index + 1).repeat(64),
        })),
      }],
    },
    {
      ...baseline,
      holds: [{
        hold_id: holdId,
        criteria: criterionDefinitions.map(([id, evidenceType]) => ({
          id,
          evidence_type: evidenceType,
          artifact_id: 1,
          artifact_sha256: "1".repeat(64),
        })),
      }],
    },
  ];
  for (const candidate of cases) {
    const decision = await evaluateProductionReleaseClearance(
      "manifest.json",
      JSON.stringify(candidate),
      candidateSha,
      verificationTime,
      () => Promise.resolve(manifestRaw),
      evidenceVerifier,
    );
    assertEquals(decision.allowed, false);
    assertStringIncludes(decision.summary, "failed closed");
  }
});

Deno.test("a missing release-hold manifest fails closed", async () => {
  const decision = await evaluateProductionReleaseHolds(
    "missing.json",
    () => Promise.reject(new Deno.errors.NotFound("missing")),
  );
  assertEquals(decision.allowed, false);
  assertStringIncludes(decision.summary, "failed closed");
});

Deno.test("removing the required production hold fails closed", async () => {
  for (
    const raw of [
      JSON.stringify({ schema_version: 3, holds: [] }),
      JSON.stringify({
        schema_version: 3,
        holds: [{
          ...JSON.parse(manifest(false)).holds[0],
          id: "some_other_hold",
        }],
      }),
    ]
  ) {
    const decision = await evaluateProductionReleaseHolds(
      "manifest.json",
      () => Promise.resolve(raw),
    );
    assertEquals(decision.allowed, false);
    assertStringIncludes(decision.summary, "required production hold");
  }
});

Deno.test("a malformed or ambiguous release-hold manifest fails closed", async () => {
  for (
    const raw of [
      "not json",
      JSON.stringify({ schema_version: 1, holds: [] }),
      JSON.stringify({ schema_version: 3, holds: [{ active: false }] }),
      JSON.stringify({
        schema_version: 3,
        holds: [
          JSON.parse(manifest(false)).holds[0],
          JSON.parse(manifest(false)).holds[0],
        ],
      }),
      JSON.stringify({
        schema_version: 3,
        holds: [{
          ...JSON.parse(manifest(false)).holds[0],
          exit_criteria: [
            JSON.parse(manifest(false)).holds[0].exit_criteria[0],
            JSON.parse(manifest(false)).holds[0].exit_criteria[0],
          ],
        }],
      }),
    ]
  ) {
    const decision = await evaluateProductionReleaseHolds(
      "manifest.json",
      () => Promise.resolve(raw),
    );
    assertEquals(decision.allowed, false);
    assertStringIncludes(decision.summary, "failed closed");
  }
});

Deno.test("clearance blocks when live controls or artifact bytes cannot be verified", async () => {
  const manifestRaw = manifest(false);
  const clearanceRaw = JSON.stringify(await clearance(manifestRaw));
  for (
    const verifier of [
      {
        verifyRepositoryControls: () =>
          Promise.reject(new Error("unprotected")),
        verifyCriterion: evidenceVerifier.verifyCriterion,
      },
      {
        verifyRepositoryControls: evidenceVerifier.verifyRepositoryControls,
        verifyCriterion: () => Promise.reject(new Error("digest mismatch")),
      },
    ] satisfies ReleaseEvidenceVerifier[]
  ) {
    const decision = await evaluateProductionReleaseClearance(
      "manifest.json",
      clearanceRaw,
      candidateSha,
      verificationTime,
      () => Promise.resolve(manifestRaw),
      verifier,
    );
    assertEquals(decision.allowed, false);
    assertStringIncludes(decision.summary, "failed closed");
  }
});
