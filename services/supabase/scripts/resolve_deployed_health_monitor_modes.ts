import {
  fetchWithDeadline,
  readResponseTextWithinLimit,
} from "../functions/_shared/outbound.ts";

type HealthMonitorMode = "expand-compatible" | "required";

export type HealthMonitorFeature =
  | "account-deletion-recovery"
  | "purchase-principal-signout-rotation";

interface FeatureEvidenceSpec {
  compatibilityDeadline: string;
  migrations: string[];
  smokeMarkers: string[];
}

interface WorkflowRun {
  id: number;
  status: string;
  conclusion: string | null;
  head_branch: string | null;
  head_sha: string;
}

interface WorkflowJob {
  name: string;
  status: string;
  conclusion: string | null;
}

export interface WorkflowRunsPage {
  totalCount: number;
  runs: WorkflowRun[];
}

export interface WorkflowJobsPage {
  totalCount: number;
  jobs: WorkflowJob[];
}

export interface DeploymentEvidenceRuntime {
  now: () => Date;
  listSuccessfulRunsPage: (page: number) => Promise<WorkflowRunsPage>;
  listRunJobsPage: (
    runId: number,
    page: number,
  ) => Promise<WorkflowJobsPage>;
  isAncestor: (candidateSha: string, currentSha: string) => Promise<boolean>;
  revisionHasPath: (revision: string, path: string) => Promise<boolean>;
  readPathAtRevision: (revision: string, path: string) => Promise<string>;
}

export interface ResolvedHealthMonitorMode {
  mode: HealthMonitorMode;
  evidenceSha: string | null;
  reason:
    | "compatibility-deadline-reached"
    | "no-qualifying-production-deploy"
    | "successful-production-deploy";
}

const DEPLOY_WORKFLOW_PATH = ".github/workflows/deploy.yml";
const DEPLOY_JOB_NAME = "deploy";
const MAIN_BRANCH = "main";
const PAGE_SIZE = 100;
const MAXIMUM_PAGES = 10;
const REQUEST_TIMEOUT_MS = 15_000;
const MAXIMUM_RESPONSE_BYTES = 2 * 1_024 * 1_024;
const GITHUB_API_ORIGIN = "https://api.github.com";
const GITHUB_API_VERSION = "2026-03-10";
const SHA_PATTERN = /^[0-9a-f]{40}$/;

const FEATURE_SPECS: Record<HealthMonitorFeature, FeatureEvidenceSpec> = {
  "account-deletion-recovery": {
    // This prevents compatibility from becoming a permanent fallback if
    // historical Actions evidence is later unavailable or retained only for a
    // bounded period. An overdue deployment therefore fails closed.
    compatibilityDeadline: "2026-09-19T00:00:00.000Z",
    migrations: [
      "services/supabase/migrations/20260813053000_add_account_deletion_recovery_capabilities.sql",
      "services/supabase/migrations/20260813142638_prepare_account_deletion_recovery_v2.sql",
    ],
    smokeMarkers: [
      "/rest/v1/rpc/get_account_deletion_recovery_health",
      "/rest/v1/rpc/get_account_deletion_recovery_preparation_health",
    ],
  },
  "purchase-principal-signout-rotation": {
    compatibilityDeadline: "2026-09-19T00:00:00.000Z",
    migrations: [
      "services/supabase/migrations/20260816033107_add_stable_purchase_principal_signout_rotations.sql",
    ],
    smokeMarkers: [
      "/rest/v1/rpc/get_purchase_principal_signout_rotation_health",
    ],
  },
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function exactString(value: unknown, label: string): string {
  if (typeof value !== "string" || !value || value.trim() !== value) {
    throw new Error(`${label} must be a non-empty exact string.`);
  }
  return value;
}

function safePositiveInteger(value: unknown, label: string): number {
  if (!Number.isSafeInteger(value) || Number(value) <= 0) {
    throw new Error(`${label} must be a positive safe integer.`);
  }
  return Number(value);
}

function safeNonNegativeInteger(value: unknown, label: string): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) {
    throw new Error(`${label} must be a non-negative safe integer.`);
  }
  return Number(value);
}

function nullableExactString(value: unknown, label: string): string | null {
  if (value === null) return null;
  return exactString(value, label);
}

export function parseWorkflowRunsPage(value: unknown): WorkflowRunsPage {
  if (!isRecord(value) || !Array.isArray(value.workflow_runs)) {
    throw new Error("GitHub workflow-runs response has an invalid shape.");
  }

  const totalCount = safeNonNegativeInteger(
    value.total_count,
    "GitHub workflow-runs total_count",
  );
  const runs = value.workflow_runs.map((candidate, index): WorkflowRun => {
    if (!isRecord(candidate)) {
      throw new Error(`GitHub workflow run ${index} has an invalid shape.`);
    }
    return {
      id: safePositiveInteger(candidate.id, `GitHub workflow run ${index} id`),
      status: exactString(
        candidate.status,
        `GitHub workflow run ${index} status`,
      ),
      conclusion: nullableExactString(
        candidate.conclusion,
        `GitHub workflow run ${index} conclusion`,
      ),
      head_branch: nullableExactString(
        candidate.head_branch,
        `GitHub workflow run ${index} head_branch`,
      ),
      head_sha: exactString(
        candidate.head_sha,
        `GitHub workflow run ${index} head_sha`,
      ),
    };
  });

  if (runs.length > PAGE_SIZE || runs.length > totalCount) {
    throw new Error(
      "GitHub workflow-runs pagination metadata is inconsistent.",
    );
  }
  return { totalCount, runs };
}

export function parseWorkflowJobsPage(value: unknown): WorkflowJobsPage {
  if (!isRecord(value) || !Array.isArray(value.jobs)) {
    throw new Error("GitHub workflow-jobs response has an invalid shape.");
  }

  const totalCount = safeNonNegativeInteger(
    value.total_count,
    "GitHub workflow-jobs total_count",
  );
  const jobs = value.jobs.map((candidate, index): WorkflowJob => {
    if (!isRecord(candidate)) {
      throw new Error(`GitHub workflow job ${index} has an invalid shape.`);
    }
    return {
      name: exactString(candidate.name, `GitHub workflow job ${index} name`),
      status: exactString(
        candidate.status,
        `GitHub workflow job ${index} status`,
      ),
      conclusion: nullableExactString(
        candidate.conclusion,
        `GitHub workflow job ${index} conclusion`,
      ),
    };
  });

  if (jobs.length > PAGE_SIZE || jobs.length > totalCount) {
    throw new Error(
      "GitHub workflow-jobs pagination metadata is inconsistent.",
    );
  }
  return { totalCount, jobs };
}

async function collectRunJobs(
  runtime: DeploymentEvidenceRuntime,
  runId: number,
): Promise<WorkflowJob[]> {
  const jobs: WorkflowJob[] = [];
  let expectedTotal: number | null = null;

  for (let page = 1; page <= MAXIMUM_PAGES; page += 1) {
    const response = await runtime.listRunJobsPage(runId, page);
    expectedTotal ??= response.totalCount;
    if (response.totalCount !== expectedTotal) {
      throw new Error("GitHub workflow-jobs pagination changed during lookup.");
    }
    jobs.push(...response.jobs);

    if (jobs.length === expectedTotal) return jobs;
    if (response.jobs.length < PAGE_SIZE || jobs.length > expectedTotal) {
      throw new Error("GitHub workflow-jobs pagination ended inconsistently.");
    }
  }

  throw new Error(
    "GitHub workflow-jobs lookup exceeded the bounded page limit.",
  );
}

async function revisionContainsFeatureEvidence(
  runtime: DeploymentEvidenceRuntime,
  revision: string,
  spec: FeatureEvidenceSpec,
): Promise<boolean> {
  for (const migration of spec.migrations) {
    if (!(await runtime.revisionHasPath(revision, migration))) return false;
  }

  const workflow = await runtime.readPathAtRevision(
    revision,
    DEPLOY_WORKFLOW_PATH,
  );
  const databasePushStep = findWorkflowStep(
    workflow,
    "Push Database Migrations",
  );
  const smokeStep = findWorkflowStep(
    workflow,
    "Smoke test production backend endpoints",
  );
  if (
    databasePushStep === null || smokeStep === null ||
    databasePushStep.startIndex >= smokeStep.startIndex ||
    !isUnconditionalWorkflowStep(databasePushStep) ||
    !isUnconditionalWorkflowStep(smokeStep)
  ) {
    return false;
  }
  const databasePushRun = workflowStepRun(databasePushStep);
  const smokeRun = workflowStepRun(smokeStep);
  if (
    databasePushRun === null ||
    !databasePushRun.includes("supabase db push") ||
    smokeRun === null
  ) {
    return false;
  }
  return spec.smokeMarkers.every((marker) => smokeRun.includes(marker));
}

interface WorkflowStep {
  bodyLines: string[];
  indentation: number;
  startIndex: number;
}

function findWorkflowStep(
  workflow: string,
  expectedName: string,
): WorkflowStep | null {
  const lines = workflow.split(/\r?\n/);
  const matches: Array<{ lineIndex: number; indentation: number }> = [];

  for (const [lineIndex, line] of lines.entries()) {
    const match = /^( *)- name:\s*(.*?)\s*$/.exec(line);
    if (match?.[2] === expectedName) {
      matches.push({ lineIndex, indentation: match[1].length });
    }
  }
  if (matches.length !== 1) return null;

  const [{ lineIndex, indentation }] = matches;
  let endLineIndex = lines.length;
  for (
    let candidate = lineIndex + 1;
    candidate < lines.length;
    candidate += 1
  ) {
    const line = lines[candidate];
    if (line.trim().length === 0) continue;
    const leadingSpaces = /^( *)/.exec(line)?.[1].length ?? 0;
    if (leadingSpaces <= indentation) {
      endLineIndex = candidate;
      break;
    }
  }

  return {
    bodyLines: lines.slice(lineIndex + 1, endLineIndex),
    indentation,
    startIndex: lineIndex,
  };
}

function workflowStepHasDirectProperty(
  step: WorkflowStep,
  property: string,
): boolean {
  const prefix = `${" ".repeat(step.indentation + 2)}${property}:`;
  return step.bodyLines.some((line) => line.startsWith(prefix));
}

function isUnconditionalWorkflowStep(step: WorkflowStep): boolean {
  return !workflowStepHasDirectProperty(step, "if") &&
    !workflowStepHasDirectProperty(step, "continue-on-error");
}

function workflowStepRun(step: WorkflowStep): string | null {
  const prefix = `${" ".repeat(step.indentation + 2)}run:`;
  const runLineIndexes = step.bodyLines.flatMap((line, index) =>
    line.startsWith(prefix) ? [index] : []
  );
  if (runLineIndexes.length !== 1) return null;

  const [runLineIndex] = runLineIndexes;
  const runLine = step.bodyLines[runLineIndex];
  const sameLineValue = runLine.slice(prefix.length).trim();
  const runLines = sameLineValue === "" || /^[>|][+-]?$/.test(sameLineValue)
    ? []
    : [sameLineValue];

  for (
    let candidate = runLineIndex + 1;
    candidate < step.bodyLines.length;
    candidate += 1
  ) {
    const line = step.bodyLines[candidate];
    if (line.trim().length === 0) {
      runLines.push(line);
      continue;
    }
    const leadingSpaces = /^( *)/.exec(line)?.[1].length ?? 0;
    if (leadingSpaces <= step.indentation + 2) break;
    runLines.push(line);
  }
  return runLines.join("\n");
}

export async function resolveDeployedHealthMonitorMode(
  feature: HealthMonitorFeature,
  currentSha: string,
  runtime: DeploymentEvidenceRuntime,
): Promise<ResolvedHealthMonitorMode> {
  if (!SHA_PATTERN.test(currentSha)) {
    throw new Error(
      "Current checkout SHA must be 40 lowercase hexadecimal characters.",
    );
  }

  const spec = FEATURE_SPECS[feature];
  const now = runtime.now();
  if (Number.isNaN(now.getTime())) {
    throw new Error("Health-monitor mode resolver received an invalid clock.");
  }
  const deadline = new Date(spec.compatibilityDeadline);
  if (now >= deadline) {
    return {
      mode: "required",
      evidenceSha: null,
      reason: "compatibility-deadline-reached",
    };
  }

  const seenRunIds = new Set<number>();
  let expectedTotal: number | null = null;
  let inspectedRuns = 0;
  let ancestorRuns = 0;

  for (let page = 1; page <= MAXIMUM_PAGES; page += 1) {
    const response = await runtime.listSuccessfulRunsPage(page);
    expectedTotal ??= response.totalCount;
    if (response.totalCount !== expectedTotal) {
      throw new Error("GitHub workflow-runs pagination changed during lookup.");
    }

    for (const run of response.runs) {
      if (seenRunIds.has(run.id)) {
        throw new Error("GitHub workflow-runs response repeated a run ID.");
      }
      seenRunIds.add(run.id);
      inspectedRuns += 1;

      if (
        run.status !== "completed" || run.conclusion !== "success" ||
        run.head_branch !== MAIN_BRANCH
      ) {
        throw new Error(
          "GitHub returned a run outside the requested successful main-branch filter.",
        );
      }
      if (!SHA_PATTERN.test(run.head_sha)) {
        throw new Error("GitHub returned a malformed production deploy SHA.");
      }
      if (!(await runtime.isAncestor(run.head_sha, currentSha))) continue;
      ancestorRuns += 1;

      if (
        !(await revisionContainsFeatureEvidence(runtime, run.head_sha, spec))
      ) {
        continue;
      }

      const jobs = await collectRunJobs(runtime, run.id);
      const deployJobs = jobs.filter((job) => job.name === DEPLOY_JOB_NAME);
      if (deployJobs.length !== 1) {
        throw new Error(
          "A source-qualified production run did not contain exactly one deploy job.",
        );
      }
      if (
        deployJobs[0].status !== "completed" ||
        deployJobs[0].conclusion !== "success"
      ) {
        throw new Error(
          "A source-qualified production run did not complete its deploy job successfully.",
        );
      }

      return {
        mode: "required",
        evidenceSha: run.head_sha,
        reason: "successful-production-deploy",
      };
    }

    if (inspectedRuns === expectedTotal) break;
    if (response.runs.length < PAGE_SIZE || inspectedRuns > expectedTotal) {
      throw new Error("GitHub workflow-runs pagination ended inconsistently.");
    }
    if (page === MAXIMUM_PAGES) {
      throw new Error(
        "GitHub workflow-runs lookup exceeded the bounded page limit.",
      );
    }
  }

  if ((expectedTotal ?? 0) > 0 && ancestorRuns === 0) {
    throw new Error(
      "No successful main production deploy belongs to the current checkout history.",
    );
  }

  return {
    mode: "expand-compatible",
    evidenceSha: null,
    reason: "no-qualifying-production-deploy",
  };
}

async function readResponseJson(response: Response): Promise<unknown> {
  const text = await readResponseTextWithinLimit(
    response,
    MAXIMUM_RESPONSE_BYTES,
  );
  try {
    return JSON.parse(text);
  } catch {
    throw new Error("GitHub API returned malformed JSON.");
  }
}

async function githubApiRequest(
  path: string,
  token: string,
): Promise<unknown> {
  const url = new URL(path, GITHUB_API_ORIGIN);
  if (url.origin !== GITHUB_API_ORIGIN) {
    throw new Error("GitHub API request escaped the reviewed origin.");
  }

  let lastStatus: number | null = null;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    let response: Response;
    try {
      response = await fetchWithDeadline(
        url,
        {
          headers: {
            Accept: "application/vnd.github+json",
            Authorization: `Bearer ${token}`,
            "X-GitHub-Api-Version": GITHUB_API_VERSION,
          },
          redirect: "error",
        },
        { timeoutMs: REQUEST_TIMEOUT_MS },
      );
    } catch (error) {
      if (attempt === 3) {
        throw new Error(
          `GitHub API transport failed after ${attempt} attempts: ${
            error instanceof Error ? error.message : "unknown transport error"
          }`,
        );
      }
      await new Promise((resolve) => setTimeout(resolve, attempt * 1_000));
      continue;
    }

    if (response.ok) return await readResponseJson(response);
    lastStatus = response.status;
    await response.body?.cancel();
    const retryable = response.status === 408 || response.status === 429 ||
      response.status >= 500;
    if (!retryable || attempt === 3) break;
    await new Promise((resolve) => setTimeout(resolve, attempt * 1_000));
  }

  throw new Error(`GitHub API request failed with status ${lastStatus ?? 0}.`);
}

async function gitCommand(args: string[]): Promise<Deno.CommandOutput> {
  return await new Deno.Command("git", {
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
}

function createRuntime(
  repository: string,
  token: string,
): DeploymentEvidenceRuntime {
  const prefix = `/repos/${repository}`;
  return {
    now: () => new Date(),
    listSuccessfulRunsPage: async (page) =>
      parseWorkflowRunsPage(
        await githubApiRequest(
          `${prefix}/actions/workflows/deploy.yml/runs?branch=main&status=success&per_page=${PAGE_SIZE}&page=${page}`,
          token,
        ),
      ),
    listRunJobsPage: async (runId, page) =>
      parseWorkflowJobsPage(
        await githubApiRequest(
          `${prefix}/actions/runs/${runId}/jobs?filter=latest&per_page=${PAGE_SIZE}&page=${page}`,
          token,
        ),
      ),
    isAncestor: async (candidateSha, currentSha) => {
      const output = await gitCommand([
        "merge-base",
        "--is-ancestor",
        candidateSha,
        currentSha,
      ]);
      if (output.code === 0) return true;
      if (output.code === 1) return false;
      throw new Error("Git could not verify production-deploy ancestry.");
    },
    revisionHasPath: async (revision, path) => {
      const output = await gitCommand([
        "cat-file",
        "-e",
        `${revision}:${path}`,
      ]);
      if (output.code === 0) return true;
      if (output.code === 128) return false;
      throw new Error(
        "Git could not inspect production-deploy source evidence.",
      );
    },
    readPathAtRevision: async (revision, path) => {
      const output = await gitCommand(["show", `${revision}:${path}`]);
      if (output.code !== 0) {
        throw new Error("Git could not read the production deploy workflow.");
      }
      return new TextDecoder().decode(output.stdout);
    },
  };
}

function parseFeature(args: string[]): HealthMonitorFeature {
  if (args.length !== 2 || args[0] !== "--feature") {
    throw new Error(
      "Usage: resolve_deployed_health_monitor_modes.ts --feature <account-deletion-recovery|purchase-principal-signout-rotation>",
    );
  }
  if (
    args[1] !== "account-deletion-recovery" &&
    args[1] !== "purchase-principal-signout-rotation"
  ) {
    throw new Error(`Unsupported health-monitor feature: ${args[1]}`);
  }
  return args[1];
}

if (import.meta.main) {
  try {
    const feature = parseFeature(Deno.args);
    const token = Deno.env.get("GITHUB_TOKEN") ?? "";
    const repository = Deno.env.get("GITHUB_REPOSITORY") ?? "";
    const currentSha = Deno.env.get("GITHUB_SHA") ?? "";
    if (!token) throw new Error("GITHUB_TOKEN is required.");
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)) {
      throw new Error(
        "GITHUB_REPOSITORY must be an exact owner/repository pair.",
      );
    }

    const result = await resolveDeployedHealthMonitorMode(
      feature,
      currentSha,
      createRuntime(repository, token),
    );
    const evidence = result.evidenceSha
      ? ` deploy_sha=${result.evidenceSha}`
      : "";
    console.error(
      `Resolved ${feature} monitor mode: ${result.mode} (${result.reason})${evidence}`,
    );
    console.log(result.mode);
  } catch (error) {
    console.error(
      `Health-monitor mode resolution failed: ${
        error instanceof Error ? error.message : "unknown error"
      }`,
    );
    Deno.exit(1);
  }
}
