import {
  fetchWithDeadline,
  readResponseTextWithinLimit,
} from "../functions/_shared/outbound.ts";

export const WORKFLOW = ".github/workflows/supabase-candidate-validation.yml";
const REPOSITORY = "emreerdener/merian";
const MAX_AGE_MS = 24 * 60 * 60 * 1000;
type RecordValue = Record<string, unknown>;
export interface ReuseDecision {
  reuse: boolean;
  reason: string;
  runId?: number;
  attempt?: number;
}
export interface ReuseRuntime {
  get: (path: string) => Promise<unknown>;
  now: number;
}
function record(value: unknown): RecordValue {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("metadata_shape");
  }
  return value as RecordValue;
}
function positive(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) <= 0) {
    throw new Error("metadata_id");
  }
  return value as number;
}
function page(value: unknown, key: string): RecordValue[] {
  const data = record(value);
  if (
    !Array.isArray(data[key]) || data.total_count !== data[key].length ||
    data[key].length > 100
  ) throw new Error("incomplete_inventory");
  return (data[key] as unknown[]).map(record);
}
function successful(value: RecordValue): boolean {
  return value.status === "completed" && value.conclusion === "success";
}

// Derive every named validation step from the exact checked-out workflow. Unknown
// structure fails reuse; it never silently shortens the evidence requirement.
export function validationSteps(source: string): string[] {
  const blocks = source.split("\n  validate:\n");
  if (blocks.length !== 2) throw new Error("workflow_shape");
  const end = blocks[1].split("\n  candidate-readiness:\n");
  if (end.length !== 2) throw new Error("workflow_shape");
  const names = [
    ...end[0].matchAll(/^ {6}- name: ([A-Za-z][A-Za-z0-9 /(),.-]*)$/gm),
  ].map((m) => m[1]);
  if (
    names.length < 20 || new Set(names).size !== names.length ||
    (end[0].match(/^ {6}- /gm) ?? []).length !== names.length
  ) throw new Error("workflow_steps");
  return names;
}
function requireJob(jobs: RecordValue[], name: string, steps: string[]): void {
  const found = jobs.filter((j) => j.name === name);
  if (
    found.length !== 1 || !successful(found[0]) ||
    !Array.isArray(found[0].steps)
  ) throw new Error("job_not_proven");
  const observed = found[0].steps.map(record);
  for (const step of steps) {
    const matching = observed.filter((s) => s.name === step);
    if (matching.length !== 1 || !successful(matching[0])) {
      throw new Error("step_not_proven");
    }
  }
}

export async function resolveReuse(
  sha: string,
  source: string,
  runtime: ReuseRuntime,
): Promise<ReuseDecision> {
  if (!/^[a-f0-9]{40}$/.test(sha)) throw new Error("candidate_sha");
  try {
    const steps = validationSteps(source);
    const workflow = record(
      await runtime.get(`actions/workflows/supabase-candidate-validation.yml`),
    );
    const workflowId = positive(workflow.id);
    if (workflow.path !== WORKFLOW || workflow.state !== "active") {
      return { reuse: false, reason: "workflow_unavailable" };
    }
    // Include failed/active latest runs: never fall back to an older green run
    // after a newer attempt has contradicted it. PR/fork runs are not eligible.
    const runs = page(
      await runtime.get(
        `actions/workflows/${workflowId}/runs?head_sha=${sha}&event=workflow_dispatch&per_page=100`,
      ),
      "workflow_runs",
    );
    if (!runs.length) return { reuse: false, reason: "no_prior_validation" };
    runs.sort((a, b) => positive(b.id) - positive(a.id));
    const listed = runs[0];
    const runId = positive(listed.id);
    const run = record(await runtime.get(`actions/runs/${runId}`));
    const attempt = positive(run.run_attempt);
    if (
      run.id !== runId || run.head_sha !== sha ||
      run.workflow_id !== workflowId ||
      run.path !== WORKFLOW || run.event !== "workflow_dispatch" ||
      record(run.repository).full_name !== REPOSITORY ||
      record(run.head_repository).full_name !== REPOSITORY ||
      run.head_branch === null || typeof run.head_branch !== "string" ||
      listed.head_sha !== sha
    ) throw new Error("run_identity");
    if (run.status !== "completed") {
      return { reuse: false, reason: "validation_in_progress", runId, attempt };
    }
    if (listed.run_attempt !== attempt) throw new Error("run_attempt_changed");
    if (!successful(run)) {
      return { reuse: false, reason: "latest_validation_not_successful" };
    }
    const started = Date.parse(String(run.run_started_at));
    const finished = Date.parse(String(run.updated_at));
    if (
      !Number.isFinite(started) || !Number.isFinite(finished) ||
      started > finished ||
      finished > runtime.now || runtime.now - started > MAX_AGE_MS
    ) return { reuse: false, reason: "validation_stale" };
    const jobs = page(
      await runtime.get(
        `actions/runs/${runId}/attempts/${attempt}/jobs?per_page=100`,
      ),
      "jobs",
    );
    if (jobs.length !== 3) throw new Error("job_inventory");
    requireJob(jobs, "Determine Supabase candidate scope", [
      "Determine complete validation scope",
    ]);
    requireJob(jobs, "Validate exact candidate SHA", steps);
    requireJob(jobs, "Candidate readiness", [
      "Enforce Supabase candidate result",
    ]);
    const artifacts = page(
      await runtime.get(`actions/runs/${runId}/artifacts?per_page=100`),
      "artifacts",
    );
    for (const prefix of ["initial-atomic-c1", "initial-media-handoff"]) {
      const found = artifacts.filter((a) =>
        a.name === `${prefix}-${sha}-attempt-${attempt}`
      );
      if (found.length !== 1) throw new Error("artifact_inventory");
      const a = found[0];
      const origin = record(a.workflow_run);
      positive(a.id);
      positive(a.size_in_bytes);
      if (
        a.expired !== false ||
        !/^sha256:[a-f0-9]{64}$/.test(String(a.digest)) ||
        origin.id !== runId || origin.head_sha !== sha
      ) throw new Error("artifact_provenance");
    }
    // Re-list as well as re-read: a newly dispatched run has a different ID.
    // This narrows the observation race; it is not a cross-workflow lock.
    const latest = page(
      await runtime.get(
        `actions/workflows/${workflowId}/runs?head_sha=${sha}&event=workflow_dispatch&per_page=100`,
      ),
      "workflow_runs",
    ).sort((a, b) => positive(b.id) - positive(a.id))[0];
    const latestId = positive(latest?.id);
    const final = record(await runtime.get(`actions/runs/${latestId}`));
    const finalAttempt = positive(final.run_attempt);
    if (
      final.id !== latestId || final.head_sha !== sha ||
      final.workflow_id !== workflowId ||
      final.path !== WORKFLOW || final.event !== "workflow_dispatch" ||
      record(final.repository).full_name !== REPOSITORY ||
      record(final.head_repository).full_name !== REPOSITORY ||
      latest.head_sha !== sha
    ) throw new Error("final_run_identity");
    if (final.status !== "completed") {
      return {
        reuse: false,
        reason: "validation_in_progress",
        runId: latestId,
        attempt: finalAttempt,
      };
    }
    if (
      latestId !== runId || !successful(final) || finalAttempt !== attempt ||
      latest.run_attempt !== finalAttempt || final.updated_at !== run.updated_at
    ) throw new Error("run_changed");
    return { reuse: true, reason: "exact_candidate_verified", runId, attempt };
  } catch {
    // API outage, malformed, incomplete or expired evidence requires the normal
    // full gate. Never turn an unavailable inspection into reuse permission.
    return { reuse: false, reason: "evidence_unavailable_or_invalid" };
  }
}

if (import.meta.main) {
  const repository = Deno.env.get("GITHUB_REPOSITORY");
  if (repository !== REPOSITORY) throw new Error("Unexpected repository");
  const token = Deno.env.get("GITHUB_TOKEN");
  if (!token) throw new Error("GitHub read token unavailable");
  const sha = Deno.env.get("GITHUB_SHA") ?? "";
  const source = await Deno.readTextFile(WORKFLOW);
  const decision = await resolveReuse(sha, source, {
    now: Date.now(),
    get: async (path) => {
      const response = await fetchWithDeadline(
        `https://api.github.com/repos/${REPOSITORY}/${path}`,
        {
          headers: {
            Authorization: `Bearer ${token}`,
            Accept: "application/vnd.github+json",
            "X-GitHub-Api-Version": "2026-03-10",
            "Cache-Control": "no-cache",
          },
          redirect: "error",
        },
        { timeoutMs: 15_000 },
      );
      if (!response.ok) {
        await response.body?.cancel();
        throw new Error("GitHub evidence unavailable");
      }
      return JSON.parse(
        await readResponseTextWithinLimit(response, 2 * 1024 * 1024),
      );
    },
  });
  const output = Deno.env.get("GITHUB_OUTPUT");
  const summary = Deno.env.get("GITHUB_STEP_SUMMARY");
  if (!output || !summary) throw new Error("Workflow output paths unavailable");
  await Deno.writeTextFile(
    output,
    `reuse=${decision.reuse}\nreason=${decision.reason}\nrun_id=${
      decision.runId ?? ""
    }\n`,
    { append: true },
  );
  await Deno.writeTextFile(
    summary,
    `### Exact candidate validation\n\n- Candidate: \`${sha}\`\n- Reuse: ${decision.reuse}\n- Decision: ${decision.reason}\n${
      decision.runId
        ? `- Evidence: https://github.com/${REPOSITORY}/actions/runs/${decision.runId} (attempt ${decision.attempt})\n`
        : ""
    }\nProduction authority and live release controls remain separate.\n`,
    { append: true },
  );
  console.log(JSON.stringify(decision));
  if (decision.reason === "validation_in_progress") Deno.exit(1);
}
