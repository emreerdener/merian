import JSZip from "jszip";

export interface ReleaseEvidenceCriterion {
  holdId: string;
  criterionId: string;
  evidenceType: string;
  requiredWorkflows: readonly string[];
  artifactId: number;
  artifactSha256: string;
  candidateSha: string;
}

export interface ReleaseEvidenceVerifier {
  verifyRepositoryControls(candidateSha: string): Promise<string[]>;
  verifyCriterion(input: ReleaseEvidenceCriterion): Promise<string>;
}

export interface SupportingWorkflowRun {
  run_id: number;
  workflow_path: string;
}

interface EmbeddedEvidence {
  label: string;
  media_type: "application/json";
  content_base64: string;
  sha256: string;
}

export interface ReleaseEvidenceStatement {
  schema_version: 2;
  hold_id: string;
  criterion_id: string;
  evidence_type: string;
  candidate_sha: string;
  outcome: "passed" | "approved";
  observed_at: string;
  summary: string;
  supporting_runs: SupportingWorkflowRun[];
  embedded_evidence: EmbeddedEvidence[];
}

interface GitHubArtifact {
  id: number;
  name: string;
  size_in_bytes: number;
  expired: boolean;
  digest: string;
  archive_download_url: string;
  workflow_run: { id: number; head_sha: string } | null;
}

interface GitHubWorkflowRun {
  id: number;
  run_attempt: number;
  head_sha: string;
  status: string;
  conclusion: string | null;
  path: string;
  updated_at: string;
}

type Fetcher = typeof fetch;

const SHA_PATTERN = /^[0-9a-f]{40}$/;
const DIGEST_PATTERN = /^(?!0{64}$)[0-9a-f]{64}$/;
const WORKFLOW_PATTERN = /^\.github\/workflows\/[a-zA-Z0-9._-]+\.ya?ml$/;
const RELEASE_EVIDENCE_WORKFLOW = ".github/workflows/release-evidence.yml";
const MAX_ARTIFACT_BYTES = 2 * 1024 * 1024;
const MAX_EMBEDDED_EVIDENCE_BYTES = 256 * 1024;
const MAX_CLOCK_SKEW_MS = 5 * 60 * 1_000;
const MAX_EVIDENCE_AGE_MS = 30 * 24 * 60 * 60 * 1_000;

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function nonEmptyText(value: unknown, maxLength = 2_048): value is string {
  return typeof value === "string" && value.trim().length > 0 &&
    value.length <= maxLength && !/[\r\n]/.test(value);
}

async function sha256Bytes(bytes: Uint8Array): Promise<string> {
  const ownedBytes = new Uint8Array(bytes.byteLength);
  ownedBytes.set(bytes);
  const digest = await crypto.subtle.digest("SHA-256", ownedBytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function decodeBase64(value: string): Uint8Array {
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(value) || value.length % 4 !== 0) {
    throw new Error("embedded evidence is not canonical base64");
  }
  const decoded = atob(value);
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

function timestamp(value: unknown, field: string, now: Date): string {
  if (!nonEmptyText(value, 64) || !/^\d{4}-\d{2}-\d{2}T.*Z$/.test(value)) {
    throw new Error(`${field} must be an ISO-8601 UTC timestamp`);
  }
  const epoch = Date.parse(value);
  if (!Number.isFinite(epoch)) throw new Error(`${field} is invalid`);
  if (epoch > now.getTime() + MAX_CLOCK_SKEW_MS) {
    throw new Error(`${field} is in the future`);
  }
  if (epoch < now.getTime() - MAX_EVIDENCE_AGE_MS) {
    throw new Error(`${field} is older than 30 days`);
  }
  return value;
}

function expectedOutcome(evidenceType: string): "passed" | "approved" {
  return evidenceType === "external_approval_record" ? "approved" : "passed";
}

export async function parseAndValidateReleaseEvidenceStatement(
  raw: string,
  expected: Omit<ReleaseEvidenceCriterion, "artifactId" | "artifactSha256">,
  verifyWorkflowRun: (
    run: SupportingWorkflowRun,
    candidateSha: string,
  ) => Promise<void>,
  now = new Date(),
): Promise<ReleaseEvidenceStatement> {
  if (new TextEncoder().encode(raw).byteLength > MAX_EMBEDDED_EVIDENCE_BYTES) {
    throw new Error("release evidence statement is too large");
  }
  const value: unknown = JSON.parse(raw);
  if (
    !isRecord(value) || value.schema_version !== 2 ||
    value.hold_id !== expected.holdId ||
    value.criterion_id !== expected.criterionId ||
    value.evidence_type !== expected.evidenceType ||
    value.candidate_sha !== expected.candidateSha ||
    value.outcome !== expectedOutcome(expected.evidenceType) ||
    !nonEmptyText(value.summary, 1_000) ||
    !Array.isArray(value.supporting_runs) ||
    !Array.isArray(value.embedded_evidence)
  ) {
    throw new Error("release evidence statement is malformed or mismatched");
  }
  const statementObservedAt = timestamp(value.observed_at, "observed_at", now);

  const supportingRunIds = new Set<number>();
  const supportingRuns = await Promise.all(
    value.supporting_runs.map(async (candidate, index) => {
      if (
        !isRecord(candidate) || !Number.isSafeInteger(candidate.run_id) ||
        (candidate.run_id as number) <= 0 ||
        !nonEmptyText(candidate.workflow_path, 256) ||
        !WORKFLOW_PATTERN.test(candidate.workflow_path)
      ) {
        throw new Error(`supporting run ${index} is malformed`);
      }
      const run = candidate as unknown as SupportingWorkflowRun;
      if (supportingRunIds.has(run.run_id)) {
        throw new Error(`supporting run ${run.run_id} is duplicated`);
      }
      supportingRunIds.add(run.run_id);
      await verifyWorkflowRun(run, expected.candidateSha);
      return run;
    }),
  );
  const observedWorkflows = new Set(
    supportingRuns.map((run) => run.workflow_path),
  );
  for (const requiredWorkflow of expected.requiredWorkflows) {
    if (!observedWorkflows.has(requiredWorkflow)) {
      throw new Error(
        `required workflow evidence is missing: ${requiredWorkflow}`,
      );
    }
  }

  let embeddedByteCount = 0;
  const labels = new Set<string>();
  const embeddedEvidence = await Promise.all(
    value.embedded_evidence.map(async (candidate, index) => {
      if (
        !isRecord(candidate) || !nonEmptyText(candidate.label, 120) ||
        candidate.media_type !== "application/json" ||
        !nonEmptyText(
          candidate.content_base64,
          MAX_EMBEDDED_EVIDENCE_BYTES * 2,
        ) ||
        !DIGEST_PATTERN.test(String(candidate.sha256 ?? ""))
      ) {
        throw new Error(`embedded evidence ${index} is malformed`);
      }
      const evidence = candidate as unknown as EmbeddedEvidence;
      if (labels.has(evidence.label)) {
        throw new Error(
          `embedded evidence label is duplicated: ${evidence.label}`,
        );
      }
      labels.add(evidence.label);
      const bytes = decodeBase64(evidence.content_base64);
      embeddedByteCount += bytes.byteLength;
      if (embeddedByteCount > MAX_EMBEDDED_EVIDENCE_BYTES) {
        throw new Error("embedded evidence exceeds the aggregate size limit");
      }
      if (await sha256Bytes(bytes) !== evidence.sha256) {
        throw new Error(`embedded evidence digest mismatch: ${evidence.label}`);
      }
      const embeddedValue: unknown = JSON.parse(
        new TextDecoder().decode(bytes),
      );
      if (
        !isRecord(embeddedValue) || embeddedValue.schema_version !== 2 ||
        embeddedValue.hold_id !== expected.holdId ||
        embeddedValue.criterion_id !== expected.criterionId ||
        embeddedValue.evidence_type !== expected.evidenceType ||
        embeddedValue.candidate_sha !== expected.candidateSha ||
        embeddedValue.outcome !== expectedOutcome(expected.evidenceType) ||
        !nonEmptyText(embeddedValue.summary, 1_000)
      ) {
        throw new Error(
          `embedded evidence payload is malformed or mismatched: ${evidence.label}`,
        );
      }
      const embeddedObservedAt = timestamp(
        embeddedValue.observed_at,
        `embedded evidence ${evidence.label} observed_at`,
        now,
      );
      if (
        Date.parse(embeddedObservedAt) >
          Date.parse(statementObservedAt) + MAX_CLOCK_SKEW_MS
      ) {
        throw new Error(
          `embedded evidence postdates its statement: ${evidence.label}`,
        );
      }
      return evidence;
    }),
  );

  if (supportingRuns.length === 0 && embeddedEvidence.length === 0) {
    throw new Error("release evidence statement contains no verified evidence");
  }
  if (
    ["device_install_over", "external_approval_record", "release_control_audit"]
      .includes(expected.evidenceType) && embeddedEvidence.length === 0
  ) {
    throw new Error(
      `${expected.evidenceType} requires embedded evidence bytes`,
    );
  }

  return {
    schema_version: 2,
    hold_id: value.hold_id as string,
    criterion_id: value.criterion_id as string,
    evidence_type: value.evidence_type as string,
    candidate_sha: value.candidate_sha as string,
    outcome: value.outcome as "passed" | "approved",
    observed_at: value.observed_at as string,
    summary: value.summary as string,
    supporting_runs: supportingRuns,
    embedded_evidence: embeddedEvidence,
  };
}

function requiredReviewerRule(environment: Record<string, unknown>): {
  preventSelfReview: boolean;
  reviewerCount: number;
} {
  const rules = environment.protection_rules;
  if (!Array.isArray(rules)) {
    throw new Error("environment protection rules are unavailable");
  }
  const rule = rules.find((candidate) =>
    isRecord(candidate) && candidate.type === "required_reviewers"
  );
  if (
    !isRecord(rule) || !Array.isArray(rule.reviewers) ||
    !rule.reviewers.every((candidate) =>
      isRecord(candidate) &&
      (candidate.type === "User" || candidate.type === "Team") &&
      isRecord(candidate.reviewer)
    )
  ) {
    throw new Error("environment has no required-reviewer rule");
  }
  return {
    preventSelfReview: rule.prevent_self_review === true,
    reviewerCount: rule.reviewers.length,
  };
}

export class GitHubReleaseEvidenceVerifier implements ReleaseEvidenceVerifier {
  readonly #token: string;
  readonly #repository: string;
  readonly #branch: string;
  readonly #fetcher: Fetcher;
  readonly #now: () => Date;

  constructor(options: {
    token: string;
    repository: string;
    branch?: string;
    fetcher?: Fetcher;
    now?: () => Date;
  }) {
    if (!nonEmptyText(options.token, 4_096)) {
      throw new Error("GitHub release-audit token is missing");
    }
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(options.repository)) {
      throw new Error("GitHub repository identity is malformed");
    }
    this.#token = options.token;
    this.#repository = options.repository;
    this.#branch = options.branch ?? "main";
    this.#fetcher = options.fetcher ?? fetch;
    this.#now = options.now ?? (() => new Date());
  }

  async #api(path: string): Promise<unknown> {
    const response = await this.#fetcher(`https://api.github.com${path}`, {
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${this.#token}`,
        "X-GitHub-Api-Version": "2022-11-28",
      },
    });
    if (!response.ok) {
      throw new Error(`GitHub API request failed (${response.status})`);
    }
    return await response.json();
  }

  async #workflowRun(
    run: SupportingWorkflowRun,
    candidateSha: string,
  ): Promise<GitHubWorkflowRun> {
    const value = await this.#api(
      `/repos/${this.#repository}/actions/runs/${run.run_id}`,
    );
    if (
      !isRecord(value) || value.id !== run.run_id ||
      !Number.isSafeInteger(value.run_attempt) ||
      (value.run_attempt as number) <= 0 ||
      value.head_sha !== candidateSha || value.status !== "completed" ||
      value.conclusion !== "success" || value.path !== run.workflow_path ||
      !nonEmptyText(value.updated_at, 64)
    ) {
      throw new Error(
        `supporting workflow run ${run.run_id} is not exact-SHA success`,
      );
    }
    timestamp(
      value.updated_at,
      `supporting workflow run ${run.run_id} updated_at`,
      this.#now(),
    );
    return value as unknown as GitHubWorkflowRun;
  }

  async verifySupportingWorkflowRun(
    run: SupportingWorkflowRun,
    candidateSha: string,
  ): Promise<void> {
    await this.#workflowRun(run, candidateSha);
  }

  async verifyRepositoryControls(candidateSha: string): Promise<string[]> {
    if (!SHA_PATTERN.test(candidateSha)) {
      throw new Error("candidate SHA is malformed");
    }
    const branch = await this.#api(
      `/repos/${this.#repository}/branches/${encodeURIComponent(this.#branch)}`,
    );
    if (
      !isRecord(branch) || branch.name !== this.#branch ||
      branch.protected !== true || !isRecord(branch.commit) ||
      branch.commit.sha !== candidateSha
    ) {
      throw new Error(
        `candidate SHA is not the current protected ${this.#branch} head`,
      );
    }
    const protection = await this.#api(
      `/repos/${this.#repository}/branches/${
        encodeURIComponent(this.#branch)
      }/protection`,
    );
    if (!isRecord(protection)) {
      throw new Error("branch protection is unavailable");
    }
    const reviews = protection.required_pull_request_reviews;
    const admins = protection.enforce_admins;
    const bypass = isRecord(reviews)
      ? reviews.bypass_pull_request_allowances
      : undefined;
    const bypassEmpty = isRecord(bypass) &&
      ["users", "teams", "apps"].every((key) =>
        Array.isArray(bypass[key]) && (bypass[key] as unknown[]).length === 0
      );
    if (
      !isRecord(reviews) || reviews.dismiss_stale_reviews !== true ||
      reviews.require_last_push_approval !== true ||
      reviews.require_code_owner_reviews !== true ||
      !Number.isSafeInteger(reviews.required_approving_review_count) ||
      (reviews.required_approving_review_count as number) < 2 ||
      !isRecord(admins) || admins.enabled !== true || !bypassEmpty
    ) {
      throw new Error(
        "main protection must enforce Code Owner review, two approvals, stale-review dismissal, last-push approval, admins, and no review bypass",
      );
    }
    for (const field of ["allow_force_pushes", "allow_deletions"] as const) {
      const setting = protection[field];
      if (!isRecord(setting) || setting.enabled !== false) {
        throw new Error(`main protection does not deny ${field}`);
      }
    }

    const pullRequests = await this.#api(
      `/repos/${this.#repository}/commits/${candidateSha}/pulls?per_page=100`,
    );
    if (!Array.isArray(pullRequests)) {
      throw new Error("candidate pull-request provenance is unavailable");
    }
    if (pullRequests.length >= 100) {
      throw new Error(
        "candidate pull-request provenance exceeds the bounded audit page",
      );
    }
    const matchingPullRequests = pullRequests.filter((candidate) =>
      isRecord(candidate) && candidate.merged_at !== null &&
      isRecord(candidate.base) && candidate.base.ref === this.#branch &&
      isRecord(candidate.base.repo) &&
      nonEmptyText(candidate.base.repo.full_name, 200) &&
      candidate.base.repo.full_name.toLowerCase() ===
        this.#repository.toLowerCase() &&
      (candidate.merge_commit_sha === candidateSha ||
        (isRecord(candidate.head) && candidate.head.sha === candidateSha))
    );
    if (matchingPullRequests.length !== 1) {
      throw new Error(
        "candidate is not bound unambiguously to one merged main pull request",
      );
    }
    const pullRequest = matchingPullRequests[0];
    if (
      !isRecord(pullRequest) || !Number.isSafeInteger(pullRequest.number) ||
      (pullRequest.number as number) <= 0 || !isRecord(pullRequest.user) ||
      pullRequest.user.type !== "User" ||
      !nonEmptyText(pullRequest.user.login, 80)
    ) {
      throw new Error("candidate is not bound to a merged pull request");
    }
    const reviewValues = await this.#api(
      `/repos/${this.#repository}/pulls/${pullRequest.number}/reviews?per_page=100`,
    );
    if (!Array.isArray(reviewValues)) {
      throw new Error("candidate pull-request reviews are unavailable");
    }
    if (reviewValues.length >= 100) {
      throw new Error(
        "candidate pull-request review history exceeds the bounded audit page",
      );
    }
    const latestByReviewer = new Map<string, { id: number; state: string }>();
    for (const review of reviewValues) {
      if (
        isRecord(review) && isRecord(review.user) &&
        review.user.type === "User" &&
        nonEmptyText(review.user.login, 80) && nonEmptyText(review.state, 40) &&
        Number.isSafeInteger(review.id) && (review.id as number) > 0
      ) {
        const state = review.state.toUpperCase();
        if (!["APPROVED", "CHANGES_REQUESTED", "DISMISSED"].includes(state)) {
          continue;
        }
        const login = review.user.login.toLowerCase();
        const existing = latestByReviewer.get(login);
        if (!existing || existing.id < (review.id as number)) {
          latestByReviewer.set(login, { id: review.id as number, state });
        }
      }
    }
    const author = pullRequest.user.login.toLowerCase();
    const approvers = [...latestByReviewer.entries()].filter(
      ([login, review]) => login !== author && review.state === "APPROVED",
    );
    if (approvers.length < 2) {
      throw new Error(
        "candidate lacks two current approvals independent of its author",
      );
    }

    for (const environmentName of ["Release Evidence", "Production"]) {
      const value = await this.#api(
        `/repos/${this.#repository}/environments/${
          encodeURIComponent(environmentName)
        }`,
      );
      if (!isRecord(value)) {
        throw new Error(`${environmentName} is unavailable`);
      }
      const reviewerRule = requiredReviewerRule(value);
      const branchPolicy = value.deployment_branch_policy;
      if (
        !reviewerRule.preventSelfReview || reviewerRule.reviewerCount < 1 ||
        !isRecord(branchPolicy) || branchPolicy.protected_branches !== true ||
        branchPolicy.custom_branch_policies !== false
      ) {
        throw new Error(
          `${environmentName} must require a reviewer, prevent self-review, and allow only protected branches`,
        );
      }
    }
    return [
      "main_branch_protection",
      "candidate_is_current_main_head",
      `pull_request_${pullRequest.number}_independent_reviews`,
      "release_evidence_environment_protection",
      "production_environment_protection",
    ];
  }

  async verifyCriterion(input: ReleaseEvidenceCriterion): Promise<string> {
    if (
      !Number.isSafeInteger(input.artifactId) || input.artifactId <= 0 ||
      !DIGEST_PATTERN.test(input.artifactSha256) ||
      !SHA_PATTERN.test(input.candidateSha)
    ) {
      throw new Error(
        `artifact identity is malformed for ${input.criterionId}`,
      );
    }
    const value = await this.#api(
      `/repos/${this.#repository}/actions/artifacts/${input.artifactId}`,
    );
    if (!isRecord(value)) throw new Error("artifact metadata is malformed");
    const artifact = value as unknown as GitHubArtifact;
    if (
      artifact.id !== input.artifactId ||
      artifact.expired !== false ||
      !Number.isSafeInteger(artifact.size_in_bytes) ||
      artifact.size_in_bytes <= 0 ||
      artifact.size_in_bytes > MAX_ARTIFACT_BYTES ||
      artifact.digest !== `sha256:${input.artifactSha256}` ||
      !nonEmptyText(artifact.archive_download_url, 2_048) ||
      !artifact.workflow_run ||
      artifact.workflow_run.head_sha !== input.candidateSha
    ) {
      throw new Error(
        `artifact metadata is mismatched for ${input.criterionId}`,
      );
    }
    const archiveUrl = new URL(artifact.archive_download_url);
    const expectedArchivePath =
      `/repos/${this.#repository}/actions/artifacts/${input.artifactId}/zip`;
    if (
      archiveUrl.protocol !== "https:" ||
      archiveUrl.hostname !== "api.github.com" ||
      archiveUrl.pathname.toLowerCase() !== expectedArchivePath.toLowerCase() ||
      archiveUrl.search !== "" || archiveUrl.hash !== ""
    ) {
      throw new Error("artifact archive URL is not a GitHub API URL");
    }
    const originRun = await this.#workflowRun({
      run_id: artifact.workflow_run.id,
      workflow_path: RELEASE_EVIDENCE_WORKFLOW,
    }, input.candidateSha);
    const expectedName =
      `merian-release-evidence-${input.criterionId}-${input.candidateSha}-${originRun.id}-attempt-${originRun.run_attempt}`;
    if (artifact.name !== expectedName) {
      throw new Error(
        `artifact name is mismatched for ${input.criterionId}`,
      );
    }

    const response = await this.#fetcher(artifact.archive_download_url, {
      redirect: "follow",
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${this.#token}`,
        "X-GitHub-Api-Version": "2022-11-28",
      },
    });
    if (!response.ok) {
      throw new Error(`artifact download failed (${response.status})`);
    }
    const contentLength = Number(response.headers.get("content-length") ?? "0");
    if (Number.isFinite(contentLength) && contentLength > MAX_ARTIFACT_BYTES) {
      throw new Error("artifact archive exceeds the size limit");
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_ARTIFACT_BYTES) {
      throw new Error("artifact archive is empty or too large");
    }
    if (await sha256Bytes(bytes) !== input.artifactSha256) {
      throw new Error(`artifact digest mismatch for ${input.criterionId}`);
    }

    const zip = await JSZip.loadAsync(bytes);
    const files = Object.values(zip.files).filter((entry) => !entry.dir);
    if (files.length !== 1 || files[0].name !== "release-evidence.json") {
      throw new Error(
        "release evidence artifact must contain exactly release-evidence.json",
      );
    }
    const rawStatement = await files[0].async("string");
    await parseAndValidateReleaseEvidenceStatement(
      rawStatement,
      input,
      async (run, candidateSha) => {
        await this.#workflowRun(run, candidateSha);
      },
      this.#now(),
    );
    return `github-actions-artifact:${input.artifactId}:sha256:${input.artifactSha256}`;
  }
}
