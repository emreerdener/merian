import {
  GitHubReleaseEvidenceVerifier,
  type ReleaseEvidenceVerifier,
} from "./github_release_evidence.ts";

interface ReleaseCriterion {
  id: string;
  description: string;
  evidence_type: string;
  required_workflows: string[];
}

interface ReleaseHold {
  id: string;
  active: boolean;
  scope: "supabase_production";
  owner: string;
  reason: string;
  exit_criteria: ReleaseCriterion[];
}

interface ReleaseHoldManifest {
  schema_version: 3;
  holds: ReleaseHold[];
}

interface ClearanceCriterion {
  id: string;
  evidence_type: string;
  artifact_id: number;
  artifact_sha256: string;
}

interface HoldClearance {
  hold_id: string;
  criteria: ClearanceCriterion[];
}

interface ProductionReleaseClearance {
  schema_version: 2;
  environment: "Production";
  candidate_sha: string;
  manifest_sha256: string;
  approved_at: string;
  expires_at: string;
  holds: HoldClearance[];
}

export interface ProductionHoldDecision {
  allowed: boolean;
  manifestValid: boolean;
  summary: string;
  activeHoldIds: string[];
  inactiveHoldIds: string[];
  manifestSha256: string;
}

export type ProductionSourceStatus = "clear" | "held" | "invalid";
export type ProductionHoldMode =
  | "source-gate"
  | "source-status"
  | "production-clearance";

export interface ProductionClearanceDecision extends ProductionHoldDecision {
  clearanceSha256: string;
  verifiedCriterionIds: string[];
  verifiedEvidenceReferences: string[];
  verifiedRepositoryControls: string[];
}

type TextReader = (path: string | URL) => Promise<string>;

const REQUIRED_PRODUCTION_HOLD_IDS = new Set([
  "species_dictionary_chat_production_hold",
]);
const IDENTIFIER_PATTERN = /^[a-z][a-z0-9_]{2,79}$/;
const WORKFLOW_PATTERN = /^\.github\/workflows\/[a-zA-Z0-9._-]+\.ya?ml$/;
const SHA_PATTERN = /^[0-9a-f]{40}$/;
const DIGEST_PATTERN = /^(?!0{64}$)[0-9a-f]{64}$/;
const MAX_CLEARANCE_LIFETIME_MS = 7 * 24 * 60 * 60 * 1_000;
const MAX_CLOCK_SKEW_MS = 5 * 60 * 1_000;

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function nonEmptyText(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function parseManifest(raw: string): ReleaseHoldManifest {
  const value: unknown = JSON.parse(raw);
  if (
    !isRecord(value) || value.schema_version !== 3 ||
    !Array.isArray(value.holds)
  ) {
    throw new Error(
      "release-hold manifest must use schema_version 3 and a holds array",
    );
  }

  const seenIds = new Set<string>();
  const holds = value.holds.map((candidate, index): ReleaseHold => {
    if (
      !isRecord(candidate) ||
      !nonEmptyText(candidate.id) ||
      !IDENTIFIER_PATTERN.test(candidate.id) ||
      typeof candidate.active !== "boolean" ||
      candidate.scope !== "supabase_production" ||
      !nonEmptyText(candidate.owner) ||
      !nonEmptyText(candidate.reason) ||
      !Array.isArray(candidate.exit_criteria) ||
      candidate.exit_criteria.length === 0
    ) {
      throw new Error(`release hold at index ${index} is malformed`);
    }
    if (seenIds.has(candidate.id)) {
      throw new Error(`release hold ${candidate.id} is duplicated`);
    }
    seenIds.add(candidate.id);

    const criterionIds = new Set<string>();
    const exitCriteria = candidate.exit_criteria.map(
      (criterion, criterionIndex): ReleaseCriterion => {
        if (
          !isRecord(criterion) ||
          !nonEmptyText(criterion.id) ||
          !IDENTIFIER_PATTERN.test(criterion.id) ||
          !nonEmptyText(criterion.description) ||
          !nonEmptyText(criterion.evidence_type) ||
          !IDENTIFIER_PATTERN.test(criterion.evidence_type) ||
          !Array.isArray(criterion.required_workflows) ||
          !criterion.required_workflows.every((workflow) =>
            nonEmptyText(workflow) && WORKFLOW_PATTERN.test(workflow)
          ) ||
          new Set(criterion.required_workflows).size !==
            criterion.required_workflows.length
        ) {
          throw new Error(
            `release hold ${candidate.id} criterion ${criterionIndex} is malformed`,
          );
        }
        if (criterionIds.has(criterion.id)) {
          throw new Error(
            `release hold ${candidate.id} criterion ${criterion.id} is duplicated`,
          );
        }
        criterionIds.add(criterion.id);
        return criterion as unknown as ReleaseCriterion;
      },
    );
    return {
      id: candidate.id,
      active: candidate.active,
      scope: candidate.scope,
      owner: candidate.owner,
      reason: candidate.reason,
      exit_criteria: exitCriteria,
    };
  });

  const presentIds = new Set(holds.map((hold) => hold.id));
  for (const requiredId of REQUIRED_PRODUCTION_HOLD_IDS) {
    if (!presentIds.has(requiredId)) {
      throw new Error(`required production hold ${requiredId} is missing`);
    }
  }
  return { schema_version: 3, holds };
}

export function releaseCriterionFromManifest(
  raw: string,
  holdId: string,
  criterionId: string,
): ReleaseCriterion {
  const manifest = parseManifest(raw);
  const hold = manifest.holds.find((candidate) => candidate.id === holdId);
  const criterion = hold?.exit_criteria.find((candidate) =>
    candidate.id === criterionId
  );
  if (!criterion) {
    throw new Error(
      `release criterion is not registered: ${holdId}:${criterionId}`,
    );
  }
  return criterion;
}

async function loadManifest(
  manifestPath: string | URL,
  readText: TextReader,
): Promise<{ manifest: ReleaseHoldManifest; digest: string }> {
  const raw = await readText(manifestPath);
  return { manifest: parseManifest(raw), digest: await sha256Hex(raw) };
}

function sourceDecision(
  loaded: { manifest: ReleaseHoldManifest; digest: string },
): ProductionHoldDecision {
  const activeHolds = loaded.manifest.holds.filter((hold) => hold.active);
  const inactiveHolds = loaded.manifest.holds.filter((hold) => !hold.active);
  if (activeHolds.length === 0) {
    return {
      allowed: true,
      manifestValid: true,
      activeHoldIds: [],
      inactiveHoldIds: inactiveHolds.map((hold) => hold.id),
      manifestSha256: loaded.digest,
      summary:
        "The source gate is clear. Production mutations still require a protected-environment clearance bound to this candidate SHA, manifest digest, and every criterion ID.",
    };
  }

  return {
    allowed: false,
    manifestValid: true,
    activeHoldIds: activeHolds.map((hold) => hold.id),
    inactiveHoldIds: inactiveHolds.map((hold) => hold.id),
    manifestSha256: loaded.digest,
    summary: activeHolds.map((hold) =>
      `${hold.id}: ${hold.reason} Owner: ${hold.owner}. Outstanding criteria: ${
        hold.exit_criteria.map((criterion) => criterion.id).join(", ")
      }.`
    ).join("\n"),
  };
}

export async function evaluateProductionReleaseHolds(
  manifestPath: string | URL,
  readText: TextReader = Deno.readTextFile,
): Promise<ProductionHoldDecision> {
  let loaded: { manifest: ReleaseHoldManifest; digest: string };
  try {
    loaded = await loadManifest(manifestPath, readText);
  } catch (error) {
    const detail = error instanceof Error ? error.message : "unknown error";
    return {
      allowed: false,
      manifestValid: false,
      activeHoldIds: [],
      inactiveHoldIds: [],
      manifestSha256: "unavailable",
      summary:
        `Production release holds failed closed because the checked-in manifest could not be verified: ${detail}.`,
    };
  }

  return sourceDecision(loaded);
}

export function productionSourceStatus(
  decision: ProductionHoldDecision,
): ProductionSourceStatus {
  if (!decision.manifestValid) return "invalid";
  return decision.allowed ? "clear" : "held";
}

export function productionHoldCommandSucceeds(
  mode: ProductionHoldMode,
  decision: ProductionHoldDecision,
): boolean {
  return decision.allowed ||
    (mode === "source-status" && productionSourceStatus(decision) === "held");
}

function parseTimestamp(value: unknown, field: string): number {
  if (!nonEmptyText(value) || !/^\d{4}-\d{2}-\d{2}T.*Z$/.test(value)) {
    throw new Error(`${field} must be an ISO-8601 UTC timestamp`);
  }
  const epoch = Date.parse(value);
  if (!Number.isFinite(epoch)) throw new Error(`${field} is invalid`);
  return epoch;
}

function parseClearance(raw: string): ProductionReleaseClearance {
  const value: unknown = JSON.parse(raw);
  if (
    !isRecord(value) || value.schema_version !== 2 ||
    value.environment !== "Production" ||
    !SHA_PATTERN.test(String(value.candidate_sha ?? "")) ||
    !DIGEST_PATTERN.test(String(value.manifest_sha256 ?? "")) ||
    !Array.isArray(value.holds)
  ) {
    throw new Error("production release clearance is malformed");
  }
  parseTimestamp(value.approved_at, "approved_at");
  parseTimestamp(value.expires_at, "expires_at");

  const holdIds = new Set<string>();
  const artifactIds = new Set<number>();
  const holds = value.holds.map((candidate, index): HoldClearance => {
    if (
      !isRecord(candidate) || !nonEmptyText(candidate.hold_id) ||
      !IDENTIFIER_PATTERN.test(candidate.hold_id) ||
      !Array.isArray(candidate.criteria)
    ) {
      throw new Error(`clearance hold at index ${index} is malformed`);
    }
    if (holdIds.has(candidate.hold_id)) {
      throw new Error(`clearance hold ${candidate.hold_id} is duplicated`);
    }
    holdIds.add(candidate.hold_id);

    const criterionIds = new Set<string>();
    const criteria = candidate.criteria.map(
      (criterion, criterionIndex): ClearanceCriterion => {
        if (
          !isRecord(criterion) || !nonEmptyText(criterion.id) ||
          !IDENTIFIER_PATTERN.test(criterion.id) ||
          !nonEmptyText(criterion.evidence_type) ||
          !IDENTIFIER_PATTERN.test(criterion.evidence_type) ||
          !Number.isSafeInteger(criterion.artifact_id) ||
          (criterion.artifact_id as number) <= 0 ||
          !DIGEST_PATTERN.test(String(criterion.artifact_sha256 ?? ""))
        ) {
          throw new Error(
            `clearance hold ${candidate.hold_id} criterion ${criterionIndex} is malformed`,
          );
        }
        if (criterionIds.has(criterion.id)) {
          throw new Error(
            `clearance criterion ${candidate.hold_id}:${criterion.id} is duplicated`,
          );
        }
        if (artifactIds.has(criterion.artifact_id as number)) {
          throw new Error(
            `clearance artifact ${criterion.artifact_id} is reused across criteria`,
          );
        }
        criterionIds.add(criterion.id);
        artifactIds.add(criterion.artifact_id as number);
        return criterion as unknown as ClearanceCriterion;
      },
    );
    return { hold_id: candidate.hold_id, criteria };
  });

  return {
    schema_version: 2,
    environment: "Production",
    candidate_sha: value.candidate_sha as string,
    manifest_sha256: value.manifest_sha256 as string,
    approved_at: value.approved_at as string,
    expires_at: value.expires_at as string,
    holds,
  };
}

export async function evaluateProductionReleaseClearance(
  manifestPath: string | URL,
  clearanceRaw: string | undefined,
  candidateSha: string,
  now = new Date(),
  readText: TextReader = Deno.readTextFile,
  evidenceVerifier?: ReleaseEvidenceVerifier,
): Promise<ProductionClearanceDecision> {
  let loaded: { manifest: ReleaseHoldManifest; digest: string };
  try {
    loaded = await loadManifest(manifestPath, readText);
  } catch (error) {
    const detail = error instanceof Error ? error.message : "unknown error";
    return {
      allowed: false,
      manifestValid: false,
      activeHoldIds: [],
      inactiveHoldIds: [],
      manifestSha256: "unavailable",
      clearanceSha256: "unavailable",
      verifiedCriterionIds: [],
      verifiedEvidenceReferences: [],
      verifiedRepositoryControls: [],
      summary: `Production clearance failed closed: ${detail}.`,
    };
  }
  const sourceGateDecision = sourceDecision(loaded);
  const blocked = (summary: string, clearanceSha256 = "unavailable") => ({
    ...sourceGateDecision,
    allowed: false,
    clearanceSha256,
    verifiedCriterionIds: [],
    verifiedEvidenceReferences: [],
    verifiedRepositoryControls: [],
    summary,
  });
  if (!sourceGateDecision.allowed) {
    return blocked(
      "Production clearance failed closed because a source release hold remains active or malformed.",
    );
  }
  if (!SHA_PATTERN.test(candidateSha)) {
    return blocked("Production clearance candidate SHA is malformed.");
  }
  if (!clearanceRaw) {
    return blocked(
      "Production clearance failed closed because the protected environment supplied no clearance record.",
    );
  }

  let clearanceSha256 = "unavailable";
  try {
    clearanceSha256 = await sha256Hex(clearanceRaw);
    const clearance = parseClearance(clearanceRaw);
    if (!evidenceVerifier) {
      throw new Error("release evidence verifier is unavailable");
    }
    if (clearance.candidate_sha !== candidateSha) {
      throw new Error("clearance candidate SHA does not match GITHUB_SHA");
    }
    if (clearance.manifest_sha256 !== sourceGateDecision.manifestSha256) {
      throw new Error(
        "clearance manifest digest does not match the checked-in manifest",
      );
    }

    const approvedAt = parseTimestamp(clearance.approved_at, "approved_at");
    const expiresAt = parseTimestamp(clearance.expires_at, "expires_at");
    const nowEpoch = now.getTime();
    if (approvedAt > nowEpoch + MAX_CLOCK_SKEW_MS) {
      throw new Error("clearance approval time is in the future");
    }
    if (expiresAt <= nowEpoch) throw new Error("clearance has expired");
    if (
      expiresAt <= approvedAt ||
      expiresAt - approvedAt > MAX_CLEARANCE_LIFETIME_MS
    ) {
      throw new Error(
        "clearance lifetime must be positive and at most seven days",
      );
    }

    const inactiveHolds = loaded.manifest.holds.filter((hold) => !hold.active);
    const clearanceByHold = new Map(
      clearance.holds.map((hold) => [hold.hold_id, hold]),
    );
    if (
      clearanceByHold.size !== inactiveHolds.length ||
      inactiveHolds.some((hold) => !clearanceByHold.has(hold.id))
    ) {
      throw new Error(
        "clearance hold set does not match the inactive manifest holds",
      );
    }

    const verifiedRepositoryControls = await evidenceVerifier
      .verifyRepositoryControls(candidateSha);
    const verifiedCriterionIds: string[] = [];
    const verifiedEvidenceReferences: string[] = [];
    for (const hold of inactiveHolds) {
      const holdClearance = clearanceByHold.get(hold.id)!;
      const evidenceById = new Map(
        holdClearance.criteria.map((criterion) => [criterion.id, criterion]),
      );
      if (
        evidenceById.size !== hold.exit_criteria.length ||
        hold.exit_criteria.some((criterion) => !evidenceById.has(criterion.id))
      ) {
        throw new Error(`clearance criteria do not match hold ${hold.id}`);
      }
      for (const criterion of hold.exit_criteria) {
        const evidence = evidenceById.get(criterion.id)!;
        if (evidence.evidence_type !== criterion.evidence_type) {
          throw new Error(
            `clearance evidence type does not match ${hold.id}:${criterion.id}`,
          );
        }
        verifiedEvidenceReferences.push(
          await evidenceVerifier.verifyCriterion({
            holdId: hold.id,
            criterionId: criterion.id,
            evidenceType: criterion.evidence_type,
            requiredWorkflows: criterion.required_workflows,
            artifactId: evidence.artifact_id,
            artifactSha256: evidence.artifact_sha256,
            candidateSha,
          }),
        );
        verifiedCriterionIds.push(`${hold.id}:${criterion.id}`);
      }
    }

    return {
      ...sourceGateDecision,
      allowed: true,
      clearanceSha256,
      verifiedCriterionIds,
      verifiedEvidenceReferences,
      verifiedRepositoryControls,
      summary:
        "The protected Production environment supplied a current clearance whose complete evidence set was downloaded, digest-verified, exact-SHA checked, and admitted only after live repository and environment protection checks.",
    };
  } catch (error) {
    const detail = error instanceof Error ? error.message : "unknown error";
    return blocked(
      `Production clearance failed closed: ${detail}.`,
      clearanceSha256,
    );
  }
}

function argumentValue(name: string): string | undefined {
  const index = Deno.args.indexOf(name);
  return index >= 0 ? Deno.args[index + 1] : undefined;
}

function markdownList(title: string, values: readonly string[]): string {
  return values.length === 0
    ? ""
    : `\n\n${title}:\n${values.map((value) => `- \`${value}\``).join("\n")}`;
}

if (import.meta.main) {
  const manifestPath = argumentValue("--manifest") ??
    new URL("../release-holds.json", import.meta.url);
  const summaryPath = argumentValue("--summary");
  const githubOutputPath = argumentValue("--github-output");
  const candidateSha = argumentValue("--candidate-sha");
  const mode = argumentValue("--mode");
  if (!candidateSha || !SHA_PATTERN.test(candidateSha)) {
    console.error("A lowercase 40-hex --candidate-sha is required.");
    Deno.exit(2);
  }
  if (
    mode !== "source-gate" && mode !== "source-status" &&
    mode !== "production-clearance"
  ) {
    console.error(
      "--mode must be source-gate, source-status, or production-clearance.",
    );
    Deno.exit(2);
  }
  if (githubOutputPath && mode !== "source-status") {
    console.error("--github-output is only valid with --mode source-status.");
    Deno.exit(2);
  }

  const decision: ProductionHoldDecision | ProductionClearanceDecision =
    mode === "production-clearance"
      ? await evaluateProductionReleaseClearance(
        manifestPath,
        Deno.env.get("MERIAN_PRODUCTION_RELEASE_CLEARANCE_JSON"),
        candidateSha,
        new Date(),
        Deno.readTextFile,
        new GitHubReleaseEvidenceVerifier({
          token: Deno.env.get("MERIAN_GITHUB_RELEASE_AUDIT_TOKEN") ?? "",
          repository: Deno.env.get("GITHUB_REPOSITORY") ?? "",
          branch: "main",
        }),
      )
      : await evaluateProductionReleaseHolds(manifestPath);
  const clearanceDecision = mode === "production-clearance"
    ? decision as ProductionClearanceDecision
    : undefined;
  const clearanceDigest = clearanceDecision
    ? `\n\nClearance SHA-256: \`${clearanceDecision.clearanceSha256}\``
    : "";
  const verifiedCriteria = clearanceDecision &&
      clearanceDecision.verifiedCriterionIds.length > 0
    ? `\n\nVerified criteria:\n${
      clearanceDecision.verifiedCriterionIds.map((id) => `- \`${id}\``).join(
        "\n",
      )
    }`
    : "";
  const verifiedControls = clearanceDecision
    ? markdownList(
      "Verified release controls",
      clearanceDecision.verifiedRepositoryControls,
    )
    : "";
  const verifiedEvidence = clearanceDecision
    ? markdownList(
      "Verified evidence artifacts",
      clearanceDecision.verifiedEvidenceReferences,
    )
    : "";
  const sourceStatus = productionSourceStatus(decision);
  const heading = mode === "production-clearance"
    ? decision.allowed
      ? "## Supabase production clearance: clear"
      : "## Supabase production clearance: blocked"
    : sourceStatus === "clear"
    ? `## Supabase production ${mode}: clear`
    : sourceStatus === "held"
    ? `## Supabase production ${mode}: intentionally held`
    : `## Supabase production ${mode}: invalid`;
  const output =
    `${heading}\n\nCandidate SHA: \`${candidateSha}\`\n\nManifest SHA-256: \`${decision.manifestSha256}\`${clearanceDigest}${verifiedCriteria}${verifiedControls}${verifiedEvidence}\n\n${decision.summary}\n`;

  if (summaryPath) {
    await Deno.writeTextFile(summaryPath, output, { append: true });
  }
  if (githubOutputPath) {
    await Deno.writeTextFile(
      githubOutputPath,
      `deploy_allowed=${decision.allowed}\nrelease_status=${sourceStatus}\n`,
      { append: true },
    );
  }
  if (productionHoldCommandSucceeds(mode, decision)) {
    console.log(decision.summary);
    if (sourceStatus === "held") {
      console.log(
        "Candidate validation passed; production deployment is intentionally skipped while the checked-in hold remains active.",
      );
    }
  } else {
    console.error(decision.summary);
    Deno.exit(1);
  }
}
