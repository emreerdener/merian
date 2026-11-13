import { assert, assertEquals } from "@std/assert";
import {
  resolveReuse,
  validationSteps,
  WORKFLOW,
} from "./resolve_candidate_validation_reuse.ts";

const sha = "a".repeat(40);
const now = Date.parse("2026-11-11T12:00:00Z");
const source = Deno.readTextFileSync(WORKFLOW);
const steps = validationSteps(source);
function fixture() {
  const run = {
    id: 42,
    workflow_id: 3,
    head_sha: sha,
    path: WORKFLOW,
    event: "workflow_dispatch",
    repository: { full_name: "emreerdener/merian" },
    head_repository: { full_name: "emreerdener/merian" },
    head_branch: "codex/candidate",
    status: "completed",
    conclusion: "success",
    run_attempt: 1,
    run_started_at: "2026-11-11T10:00:00Z",
    updated_at: "2026-11-11T11:00:00Z",
  };
  const job = (name: string, names: string[]) => ({
    name,
    status: "completed",
    conclusion: "success",
    steps: names.map((name) => ({
      name,
      status: "completed",
      conclusion: "success",
    })),
  });
  const jobs = [
    job("Determine Supabase candidate scope", [
      "Determine complete validation scope",
    ]),
    job("Validate exact candidate SHA", steps),
    job("Candidate readiness", ["Enforce Supabase candidate result"]),
  ];
  const artifacts = ["initial-atomic-c1", "initial-media-handoff"].map((
    prefix,
    i,
  ) => ({
    id: i + 1,
    name: `${prefix}-${sha}-attempt-1`,
    expired: false,
    size_in_bytes: 20,
    digest: `sha256:${"b".repeat(64)}`,
    workflow_run: { id: 42, head_sha: sha },
  }));
  let detailReads = 0;
  const calls: string[] = [];
  const data = {
    run,
    jobs,
    artifacts,
    listed: [structuredClone(run)],
    workflow: { id: 3, path: WORKFLOW, state: "active" },
    mutateFinal: false,
  };
  const runtime = {
    now,
    get: async (path: string): Promise<unknown> => {
      await Promise.resolve();
      calls.push(path);
      if (
        path === "actions/workflows/supabase-candidate-validation.yml"
      ) return data.workflow;
      if (path.startsWith("actions/workflows/3/runs?")) {
        return {
          total_count: data.listed.length,
          workflow_runs: data.listed,
        };
      }
      if (path === "actions/runs/42") {
        detailReads++;
        return structuredClone(
          data.mutateFinal && detailReads === 2
            ? { ...data.run, run_attempt: 2 }
            : data.run,
        );
      }
      if (path === "actions/runs/42/attempts/1/jobs?per_page=100") {
        return {
          total_count: data.jobs.length,
          jobs: data.jobs,
        };
      }
      if (path === "actions/runs/42/artifacts?per_page=100") {
        return {
          total_count: data.artifacts.length,
          artifacts: data.artifacts,
        };
      }
      throw new Error("unexpected route");
    },
  };
  return { data, runtime, calls };
}
Deno.test("reuse exact successful standalone run with complete current-attempt jobs and retained evidence", async () => {
  const f = fixture();
  assertEquals(await resolveReuse(sha, source, f.runtime), {
    reuse: true,
    reason: "exact_candidate_verified",
    runId: 42,
    attempt: 1,
  });
  assert(f.calls.includes("actions/runs/42/attempts/1/jobs?per_page=100"));
});
Deno.test("no prior run requires fresh validation", async () => {
  const f = fixture();
  f.data.listed = [];
  assertEquals(
    (await resolveReuse(sha, source, f.runtime)).reason,
    "no_prior_validation",
  );
});
Deno.test("active same candidate stops duplicate execution", async () => {
  const f = fixture();
  f.data.run.status = "in_progress";
  assertEquals(
    (await resolveReuse(sha, source, f.runtime)).reason,
    "validation_in_progress",
  );
});
Deno.test("newest failed run cannot be replaced with older green evidence", async () => {
  const f = fixture();
  f.data.run.conclusion = "failure";
  f.data.listed.push({ ...f.data.run, id: 41, conclusion: "success" });
  assertEquals(
    (await resolveReuse(sha, source, f.runtime)).reason,
    "latest_validation_not_successful",
  );
});
Deno.test("wrong SHA workflow repository fork event or attempt cannot be reused", async () => {
  for (
    const mutate of [
      (f: ReturnType<typeof fixture>) => f.data.run.head_sha = "c".repeat(40),
      (f: ReturnType<typeof fixture>) => f.data.run.workflow_id = 99,
      (f: ReturnType<typeof fixture>) => f.data.run.path = "other.yml",
      (f: ReturnType<typeof fixture>) => f.data.run.event = "pull_request",
      (f: ReturnType<typeof fixture>) =>
        f.data.run.repository.full_name = "other/repo",
      (f: ReturnType<typeof fixture>) =>
        f.data.run.head_repository.full_name = "fork/repo",
      (f: ReturnType<typeof fixture>) => f.data.run.run_attempt = 2,
    ]
  ) {
    const f = fixture();
    mutate(f);
    assertEquals((await resolveReuse(sha, source, f.runtime)).reuse, false);
  }
});
Deno.test("stale future and malformed times require fresh validation", async () => {
  for (
    const changes of [{ run_started_at: "2026-11-09T12:00:00Z" }, {
      updated_at: "2026-11-12T12:00:00Z",
    }, { run_started_at: "invalid" }]
  ) {
    const f = fixture();
    Object.assign(f.data.run, changes);
    assertEquals((await resolveReuse(sha, source, f.runtime)).reuse, false);
  }
});
Deno.test("skipped failed absent duplicate jobs and steps cannot qualify", async () => {
  for (
    const mutate of [
      (f: ReturnType<typeof fixture>) => {
        f.data.jobs[1].conclusion = "skipped";
      },
      (f: ReturnType<typeof fixture>) => {
        f.data.jobs[1].steps[0].conclusion = "skipped";
      },
      (f: ReturnType<typeof fixture>) => {
        f.data.jobs[1].steps[0].conclusion = "failure";
      },
      (f: ReturnType<typeof fixture>) => {
        f.data.jobs[1].steps.pop();
      },
      (f: ReturnType<typeof fixture>) => {
        f.data.jobs[1].steps.push(f.data.jobs[1].steps[0]);
      },
      (f: ReturnType<typeof fixture>) => {
        f.data.jobs.pop();
      },
      (f: ReturnType<typeof fixture>) => {
        f.data.jobs.push(f.data.jobs[0]);
      },
    ]
  ) {
    const f = fixture();
    mutate(f);
    assertEquals((await resolveReuse(sha, source, f.runtime)).reuse, false);
  }
});
Deno.test("missing expired mismatched or duplicate retained artifact cannot qualify", async () => {
  for (
    const mutate of [
      (f: ReturnType<typeof fixture>) => {
        f.data.artifacts.pop();
      },
      (f: ReturnType<typeof fixture>) => {
        f.data.artifacts[0].expired = true;
      },
      (f: ReturnType<typeof fixture>) => {
        f.data.artifacts[0].workflow_run.head_sha = "d".repeat(40);
      },
      (f: ReturnType<typeof fixture>) => {
        f.data.artifacts[0].workflow_run.id = 99;
      },
      (f: ReturnType<typeof fixture>) => {
        f.data.artifacts[0].digest = "";
      },
      (f: ReturnType<typeof fixture>) => {
        f.data.artifacts.push(f.data.artifacts[0]);
      },
    ]
  ) {
    const f = fixture();
    mutate(f);
    assertEquals((await resolveReuse(sha, source, f.runtime)).reuse, false);
  }
});
Deno.test("concurrent rerun invalidates inspected attempt", async () => {
  const f = fixture();
  f.data.mutateFinal = true;
  assertEquals((await resolveReuse(sha, source, f.runtime)).reuse, false);
});
Deno.test("API unavailable malformed and incomplete listings require fresh validation", async () => {
  for (
    const result of [null, { total_count: 101, workflow_runs: [] }, {
      total_count: 1,
      workflow_runs: [],
    }]
  ) {
    const f = fixture();
    const original = f.runtime.get;
    f.runtime.get = (p) =>
      p.includes("/runs?") ? Promise.resolve(result) : original(p);
    assertEquals((await resolveReuse(sha, source, f.runtime)).reuse, false);
  }
  const f = fixture();
  f.runtime.get = () => {
    throw new Error("do not expose transport contents");
  };
  assertEquals(await resolveReuse(sha, source, f.runtime), {
    reuse: false,
    reason: "evidence_unavailable_or_invalid",
  });
});
Deno.test("workflow step extraction refuses unsupported layout", () => {
  for (
    const invalid of [
      "",
      source.replace("  validate:", "  renamed:"),
      source.replace(
        "      - name: Test complete Edge Function suite",
        "      - run: echo skipped",
      ),
    ]
  ) {
    let failed = false;
    try {
      validationSteps(invalid);
    } catch {
      failed = true;
    }
    assert(failed);
  }
});
Deno.test("deployment gate permits only verified reuse or successful fresh validation", () => {
  const workflow = Deno.readTextFileSync(".github/workflows/deploy.yml");
  assert(
    workflow.includes("needs: [validation-reuse, fresh-candidate-validation]"),
  );
  assert(workflow.includes('test "$RESOLUTION_RESULT" = success'));
  assert(workflow.includes('test "$FRESH_RESULT" = skipped'));
  assert(workflow.includes('test "$FRESH_RESULT" = success'));
  assert(workflow.includes("needs: [candidate-validation, production-hold]"));
  assert(
    !workflow.slice(
      workflow.indexOf("  validation-reuse:"),
      workflow.indexOf("  production-scope:"),
    ).includes("environment: Production"),
  );
});

Deno.test("actual shell gate rejects failed resolver and incomplete fresh validation", async () => {
  const workflow = Deno.readTextFileSync(".github/workflows/deploy.yml");
  const block = workflow.split(
    "      - name: Require verified reuse or complete fresh validation\n",
  )[1].split("\n  production-scope:")[0];
  const shell = block.split("        run: |\n")[1].split("\n").map((line) =>
    line.startsWith("          ") ? line.slice(10) : line
  ).join("\n");
  for (const resolution of ["success", "failure", "cancelled", "skipped"]) {
    for (const reuse of ["true", "false", ""]) {
      for (const fresh of ["success", "failure", "cancelled", "skipped"]) {
        const result = await new Deno.Command("bash", {
          args: ["--noprofile", "--norc", "-e", "-o", "pipefail", "-c", shell],
          clearEnv: true,
          env: {
            RESOLUTION_RESULT: resolution,
            REUSE: reuse,
            FRESH_RESULT: fresh,
          },
          stdout: "null",
          stderr: "null",
        }).output();
        assertEquals(
          result.success,
          resolution === "success" &&
            ((reuse === "true" && fresh === "skipped") ||
              (reuse === "false" && fresh === "success")),
        );
      }
    }
  }
});

Deno.test("rerun starting between listing and detail stops duplicate validation", async () => {
  const f = fixture();
  f.data.run.run_attempt = 2;
  f.data.run.status = "in_progress";
  assertEquals(await resolveReuse(sha, source, f.runtime), {
    reuse: false,
    reason: "validation_in_progress",
    runId: 42,
    attempt: 2,
  });
});
Deno.test("new standalone run during inspection invalidates older green evidence", async () => {
  for (const status of ["in_progress", "completed"]) {
    const f = fixture();
    let listings = 0;
    const original = f.runtime.get;
    const newer = { ...f.data.run, id: 43, status, conclusion: "failure" };
    f.runtime.get = (p) => {
      if (p.startsWith("actions/workflows/3/runs?")) {
        listings++;
        if (listings === 2) {
          return Promise.resolve({
            total_count: 2,
            workflow_runs: [newer, f.data.run],
          });
        }
      }
      if (p === "actions/runs/43") return Promise.resolve(newer);
      return original(p);
    };
    const result = await resolveReuse(sha, source, f.runtime);
    assertEquals(result.reuse, false);
    assertEquals(
      result.reason,
      status === "in_progress"
        ? "validation_in_progress"
        : "evidence_unavailable_or_invalid",
    );
  }
});
Deno.test("same run starts a later active attempt during final inspection", async () => {
  const f = fixture();
  const original = f.runtime.get;
  let reads = 0;
  f.runtime.get = (p) => {
    if (p === "actions/runs/42" && ++reads === 2) {
      return Promise.resolve({
        ...f.data.run,
        run_attempt: 2,
        status: "queued",
      });
    }
    return original(p);
  };
  assertEquals(
    (await resolveReuse(sha, source, f.runtime)).reason,
    "validation_in_progress",
  );
});

Deno.test("production chain tolerates reuse skip but rejects failed gates and cancellation", () => {
  const workflow = Deno.readTextFileSync(".github/workflows/deploy.yml");
  const conditions = Object.fromEntries(
    ["production-scope", "production-hold", "deploy"].map((job) => {
      const block =
        workflow.split(`\n  ${job}:\n`)[1].split(/\n {2}[a-z-]+:\n/)[0];
      const condition = block.match(/^ {4}if: (.+)$/m)?.[1];
      assert(condition, `${job} must explicitly handle the skipped ancestor`);
      return [job, condition];
    }),
  );
  // Model only this restricted job-condition grammar, including GitHub's
  // implicit success() when no status function overrides ancestor skipping.
  function evaluate(
    expression: string,
    cancelled: boolean,
    ancestorsSucceeded: boolean,
    values: Record<string, string>,
  ): boolean {
    const explicitStatus = /\b(?:cancelled|always|success|failure)\(\)/.test(
      expression,
    );
    if (!explicitStatus && !ancestorsSucceeded) return false;
    const body = expression.replace(/^\$\{\{\s*|\s*\}\}$/g, "")
      .replace(/!cancelled\(\)/g, String(!cancelled))
      .replace(
        /needs\.([a-z-]+)\.(result|outputs\.[a-z_]+) == '([^']*)'/g,
        (_, job, field, expected) =>
          String(values[`${job}.${field}`] === expected),
      );
    assert(
      /^(?:true|false|\s|&&)+$/.test(body),
      `Unsupported condition: ${body}`,
    );
    return body.split("&&").every((part) => part.trim() === "true");
  }
  const states = ["success", "failure", "cancelled", "skipped", ""];
  for (const cancelled of [false, true]) {
    for (const ancestorsSucceeded of [false, true]) {
      for (const validation of states) {
        for (const prerequisite of states) {
          for (const output of ["true", "false", ""]) {
            const values = {
              "candidate-validation.result": validation,
              "production-scope.result": prerequisite,
              "production-scope.outputs.should_deploy": output,
              "production-hold.result": prerequisite,
              "production-hold.outputs.deploy_allowed": output,
            };
            assertEquals(
              evaluate(
                conditions["production-scope"],
                cancelled,
                ancestorsSucceeded,
                values,
              ),
              !cancelled && validation === "success",
            );
            for (const job of ["production-hold", "deploy"]) {
              assertEquals(
                evaluate(
                  conditions[job],
                  cancelled,
                  ancestorsSucceeded,
                  values,
                ),
                !cancelled && validation === "success" &&
                  prerequisite === "success" && output === "true",
                job,
              );
            }
          }
        }
      }
    }
  }
  // Recorded run1868: successful enforcement, intentionally skipped fresh
  // validation. The former implicit guard blocked the production chain.
  const approved = {
    "candidate-validation.result": "success",
    "production-hold.result": "success",
    "production-hold.outputs.deploy_allowed": "true",
  };
  assertEquals(
    evaluate(
      "needs.production-hold.outputs.deploy_allowed == 'true'",
      false,
      false,
      approved,
    ),
    false,
  );
  assertEquals(evaluate(conditions.deploy, false, false, approved), true);
});
