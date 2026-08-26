import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  type DeploymentEvidenceRuntime,
  parseWorkflowJobsPage,
  parseWorkflowRunsPage,
  resolveDeployedHealthMonitorMode,
  resolveLatestSuccessfulDeploySha,
  type WorkflowRunsPage,
} from "./resolve_deployed_health_monitor_modes.ts";

const CURRENT_SHA = "f".repeat(40);
const DEPLOY_SHA = "a".repeat(40);
const HELD_SHA = "b".repeat(40);
const BEFORE_DEADLINE = new Date("2026-08-20T00:00:00.000Z");
const DEPLOY_WORKFLOW = `
      - name: Push Database Migrations
        run: supabase db push
      - name: Smoke test production backend endpoints
        run: |
          /rest/v1/rpc/get_purchase_principal_signout_rotation_health
          /rest/v1/rpc/get_account_deletion_recovery_health
          /rest/v1/rpc/get_account_deletion_recovery_preparation_health
`;

function successfulRunsPage(
  overrides: Partial<WorkflowRunsPage> = {},
): WorkflowRunsPage {
  return {
    totalCount: 1,
    runs: [{
      id: 42,
      status: "completed",
      conclusion: "success",
      head_branch: "main",
      head_sha: DEPLOY_SHA,
    }],
    ...overrides,
  };
}

function runtime(
  overrides: Partial<DeploymentEvidenceRuntime> = {},
): DeploymentEvidenceRuntime {
  return {
    now: () => BEFORE_DEADLINE,
    listSuccessfulRunsPage: () => Promise.resolve(successfulRunsPage()),
    listRunJobsPage: () =>
      Promise.resolve({
        totalCount: 1,
        jobs: [{
          name: "deploy",
          status: "completed",
          conclusion: "success",
        }],
      }),
    isAncestor: () => Promise.resolve(true),
    revisionHasPath: () => Promise.resolve(true),
    readPathAtRevision: () => Promise.resolve(DEPLOY_WORKFLOW),
    ...overrides,
  };
}

Deno.test("qualified successful production deploy requires purchase rotation health", async () => {
  assertEquals(
    await resolveDeployedHealthMonitorMode(
      "purchase-principal-signout-rotation",
      CURRENT_SHA,
      runtime(),
    ),
    {
      mode: "required",
      evidenceSha: DEPLOY_SHA,
      reason: "successful-production-deploy",
    },
  );
});

Deno.test("account deletion promotion requires both controlling migrations", async () => {
  const inspected: string[] = [];
  const result = await resolveDeployedHealthMonitorMode(
    "account-deletion-recovery",
    CURRENT_SHA,
    runtime({
      revisionHasPath: (_revision, path) => {
        inspected.push(path);
        return Promise.resolve(true);
      },
    }),
  );

  assertEquals(result.mode, "required");
  assertEquals(inspected, [
    "services/supabase/migrations/20260813053000_add_account_deletion_recovery_capabilities.sql",
    "services/supabase/migrations/20260813142638_prepare_account_deletion_recovery_v2.sql",
  ]);
});

Deno.test("no successful production deployment preserves the bounded compatibility window", async () => {
  assertEquals(
    await resolveDeployedHealthMonitorMode(
      "account-deletion-recovery",
      CURRENT_SHA,
      runtime({
        listSuccessfulRunsPage: () =>
          Promise.resolve({ totalCount: 0, runs: [] }),
      }),
    ),
    {
      mode: "expand-compatible",
      evidenceSha: null,
      reason: "no-qualifying-production-deploy",
    },
  );
});

Deno.test("missing migration or hosted smoke cannot promote a monitor", async () => {
  const missingMigration = await resolveDeployedHealthMonitorMode(
    "purchase-principal-signout-rotation",
    CURRENT_SHA,
    runtime({ revisionHasPath: () => Promise.resolve(false) }),
  );
  assertEquals(missingMigration.mode, "expand-compatible");

  const missingSmoke = await resolveDeployedHealthMonitorMode(
    "purchase-principal-signout-rotation",
    CURRENT_SHA,
    runtime({
      readPathAtRevision: () =>
        Promise.resolve(
          "- name: Push Database Migrations\n- name: Smoke test production backend endpoints\n",
        ),
    }),
  );
  assertEquals(missingSmoke.mode, "expand-compatible");

  const markerOutsideSmokeStep = await resolveDeployedHealthMonitorMode(
    "purchase-principal-signout-rotation",
    CURRENT_SHA,
    runtime({
      readPathAtRevision: () =>
        Promise.resolve(`
      - name: Push Database Migrations
        run: supabase db push
      - name: Smoke test production backend endpoints
        run: echo "health probe removed"
      - name: Unrelated later step
        run: /rest/v1/rpc/get_purchase_principal_signout_rotation_health
`),
    }),
  );
  assertEquals(markerOutsideSmokeStep.mode, "expand-compatible");

  const conditionalSmokeStep = await resolveDeployedHealthMonitorMode(
    "purchase-principal-signout-rotation",
    CURRENT_SHA,
    runtime({
      readPathAtRevision: () =>
        Promise.resolve(`
      - name: Push Database Migrations
        run: supabase db push
      - name: Smoke test production backend endpoints
        if: false
        continue-on-error: true
        run: /rest/v1/rpc/get_purchase_principal_signout_rotation_health
`),
    }),
  );
  assertEquals(conditionalSmokeStep.mode, "expand-compatible");
});

Deno.test("unrelated history fails closed instead of silently downgrading", async () => {
  await assertRejects(
    () =>
      resolveDeployedHealthMonitorMode(
        "purchase-principal-signout-rotation",
        CURRENT_SHA,
        runtime({ isAncestor: () => Promise.resolve(false) }),
      ),
    Error,
    "No successful main production deploy belongs",
  );
});

Deno.test("unexpected non-main run and pagination drift fail closed", async () => {
  await assertRejects(
    () =>
      resolveDeployedHealthMonitorMode(
        "purchase-principal-signout-rotation",
        CURRENT_SHA,
        runtime({
          listSuccessfulRunsPage: () =>
            Promise.resolve(
              successfulRunsPage({
                runs: [{
                  id: 42,
                  status: "completed",
                  conclusion: "success",
                  head_branch: "release-candidate",
                  head_sha: DEPLOY_SHA,
                }],
              }),
            ),
        }),
      ),
    Error,
    "outside the requested successful main-branch filter",
  );

  const firstPageRuns = Array.from({ length: 100 }, (_, index) => ({
    id: index + 1,
    status: "completed",
    conclusion: "success",
    head_branch: "main",
    head_sha: (index + 1).toString(16).padStart(40, "0"),
  }));
  await assertRejects(
    () =>
      resolveDeployedHealthMonitorMode(
        "purchase-principal-signout-rotation",
        CURRENT_SHA,
        runtime({
          listSuccessfulRunsPage: (page) =>
            Promise.resolve(
              page === 1
                ? { totalCount: 101, runs: firstPageRuns }
                : { totalCount: 102, runs: [] },
            ),
          revisionHasPath: () => Promise.resolve(false),
        }),
      ),
    Error,
    "pagination changed during lookup",
  );

  await assertRejects(
    () =>
      resolveLatestSuccessfulDeploySha(
        CURRENT_SHA,
        runtime({
          listSuccessfulRunsPage: () =>
            Promise.resolve({
              totalCount: 2,
              runs: [
                successfulRunsPage().runs[0],
                { ...successfulRunsPage().runs[0], head_sha: HELD_SHA },
              ],
            }),
        }),
      ),
    Error,
    "repeated a run ID",
  );
});

Deno.test("source-qualified skipped run yields to an older successful deploy", async () => {
  assertEquals(
    await resolveDeployedHealthMonitorMode(
      "purchase-principal-signout-rotation",
      CURRENT_SHA,
      runtime({
        listSuccessfulRunsPage: () =>
          Promise.resolve({
            totalCount: 2,
            runs: [
              {
                id: 43,
                status: "completed",
                conclusion: "success",
                head_branch: "main",
                head_sha: HELD_SHA,
              },
              {
                id: 42,
                status: "completed",
                conclusion: "success",
                head_branch: "main",
                head_sha: DEPLOY_SHA,
              },
            ],
          }),
        listRunJobsPage: (runId) =>
          Promise.resolve({
            totalCount: 1,
            jobs: [{
              name: "deploy",
              status: "completed",
              conclusion: runId === 43 ? "skipped" : "success",
            }],
          }),
      }),
    ),
    {
      mode: "required",
      evidenceSha: DEPLOY_SHA,
      reason: "successful-production-deploy",
    },
  );
});

Deno.test("source-qualified skipped history continues across workflow-run pages", async () => {
  const firstPageRuns = Array.from({ length: 100 }, (_, index) => ({
    id: index + 1,
    status: "completed",
    conclusion: "success",
    head_branch: "main",
    head_sha: (index + 1).toString(16).padStart(40, "0"),
  }));
  const sourceQualifiedShas = new Set([
    ...firstPageRuns.slice(0, 49).map((run) => run.head_sha),
    DEPLOY_SHA,
  ]);

  assertEquals(
    await resolveDeployedHealthMonitorMode(
      "purchase-principal-signout-rotation",
      CURRENT_SHA,
      runtime({
        listSuccessfulRunsPage: (page) =>
          Promise.resolve(
            page === 1 ? { totalCount: 101, runs: firstPageRuns } : {
              totalCount: 101,
              runs: [{
                id: 101,
                status: "completed",
                conclusion: "success",
                head_branch: "main",
                head_sha: DEPLOY_SHA,
              }],
            },
          ),
        revisionHasPath: (revision) =>
          Promise.resolve(sourceQualifiedShas.has(revision)),
        listRunJobsPage: (runId) =>
          Promise.resolve({
            totalCount: 1,
            jobs: [{
              name: "deploy",
              status: "completed",
              conclusion: runId <= 49 ? "skipped" : "success",
            }],
          }),
      }),
    ),
    {
      mode: "required",
      evidenceSha: DEPLOY_SHA,
      reason: "successful-production-deploy",
    },
  );
});

Deno.test("source-qualified skipped run preserves compatibility without older deployment evidence", async () => {
  assertEquals(
    await resolveDeployedHealthMonitorMode(
      "purchase-principal-signout-rotation",
      CURRENT_SHA,
      runtime({
        listRunJobsPage: () =>
          Promise.resolve({
            totalCount: 1,
            jobs: [{
              name: "deploy",
              status: "completed",
              conclusion: "skipped",
            }],
          }),
      }),
    ),
    {
      mode: "expand-compatible",
      evidenceSha: null,
      reason: "no-qualifying-production-deploy",
    },
  );
});

Deno.test("latest deployment lookup skips green held runs", async () => {
  assertEquals(
    await resolveLatestSuccessfulDeploySha(
      CURRENT_SHA,
      runtime({
        listSuccessfulRunsPage: () =>
          Promise.resolve({
            totalCount: 2,
            runs: [
              {
                id: 43,
                status: "completed",
                conclusion: "success",
                head_branch: "main",
                head_sha: HELD_SHA,
              },
              {
                id: 42,
                status: "completed",
                conclusion: "success",
                head_branch: "main",
                head_sha: DEPLOY_SHA,
              },
            ],
          }),
        listRunJobsPage: (runId) =>
          Promise.resolve({
            totalCount: 1,
            jobs: [{
              name: "deploy",
              status: "completed",
              conclusion: runId === 43 ? "skipped" : "success",
            }],
          }),
      }),
    ),
    DEPLOY_SHA,
  );
});

Deno.test("latest deployment lookup returns no baseline when bounded history contains only skipped runs", async () => {
  assertEquals(
    await resolveLatestSuccessfulDeploySha(
      CURRENT_SHA,
      runtime({
        listRunJobsPage: () =>
          Promise.resolve({
            totalCount: 1,
            jobs: [{
              name: "deploy",
              status: "completed",
              conclusion: "skipped",
            }],
          }),
      }),
    ),
    null,
  );
});

Deno.test("health and baseline resolution reject deploy-job ambiguity and non-success states", async () => {
  const cases = [
    {
      jobs: [{
        name: "candidate-validation",
        status: "completed",
        conclusion: "success",
      }],
      message: "exactly one deploy job",
    },
    {
      jobs: [
        { name: "deploy", status: "completed", conclusion: "skipped" },
        { name: "deploy", status: "completed", conclusion: "skipped" },
      ],
      message: "exactly one deploy job",
    },
    {
      jobs: [{ name: "deploy", status: "in_progress", conclusion: null }],
      message: "incomplete deploy job",
    },
    {
      jobs: [{ name: "deploy", status: "completed", conclusion: "cancelled" }],
      message: "unexpected deploy-job conclusion",
    },
    {
      jobs: [{ name: "deploy", status: "completed", conclusion: "failure" }],
      message: "unexpected deploy-job conclusion",
    },
  ];

  for (const testCase of cases) {
    const ambiguousRuntime = runtime({
      listRunJobsPage: () =>
        Promise.resolve({
          totalCount: testCase.jobs.length,
          jobs: testCase.jobs,
        }),
    });
    await assertRejects(
      () =>
        resolveDeployedHealthMonitorMode(
          "purchase-principal-signout-rotation",
          CURRENT_SHA,
          ambiguousRuntime,
        ),
      Error,
      testCase.message,
    );
    await assertRejects(
      () => resolveLatestSuccessfulDeploySha(CURRENT_SHA, ambiguousRuntime),
      Error,
      testCase.message,
    );
  }
});

Deno.test("latest deployment lookup rejects a nonancestor actual deploy", async () => {
  await assertRejects(
    () =>
      resolveLatestSuccessfulDeploySha(
        CURRENT_SHA,
        runtime({ isAncestor: () => Promise.resolve(false) }),
      ),
    Error,
    "not an ancestor",
  );
});

Deno.test("latest deployment lookup bounds skipped-run job inspection", async () => {
  const runs = Array.from({ length: 51 }, (_, index) => ({
    id: index + 1,
    status: "completed",
    conclusion: "success",
    head_branch: "main",
    head_sha: (index + 1).toString(16).padStart(40, "0"),
  }));
  await assertRejects(
    () =>
      resolveLatestSuccessfulDeploySha(
        CURRENT_SHA,
        runtime({
          listSuccessfulRunsPage: () =>
            Promise.resolve({ totalCount: runs.length, runs }),
          listRunJobsPage: () =>
            Promise.resolve({
              totalCount: 1,
              jobs: [{
                name: "deploy",
                status: "completed",
                conclusion: "skipped",
              }],
            }),
        }),
      ),
    Error,
    "bounded inspection limit",
  );
});

Deno.test("API and local history errors fail closed", async () => {
  await assertRejects(
    () =>
      resolveDeployedHealthMonitorMode(
        "account-deletion-recovery",
        CURRENT_SHA,
        runtime({
          listSuccessfulRunsPage: () =>
            Promise.reject(new Error("simulated API outage")),
        }),
      ),
    Error,
    "simulated API outage",
  );
  await assertRejects(
    () =>
      resolveDeployedHealthMonitorMode(
        "account-deletion-recovery",
        CURRENT_SHA,
        runtime({
          revisionHasPath: () =>
            Promise.reject(new Error("simulated history failure")),
        }),
      ),
    Error,
    "simulated history failure",
  );
});

Deno.test("hard compatibility deadline is monotonic without retained Actions evidence", async () => {
  let queriedActions = false;
  const result = await resolveDeployedHealthMonitorMode(
    "purchase-principal-signout-rotation",
    CURRENT_SHA,
    runtime({
      now: () => new Date("2026-09-19T00:00:00.000Z"),
      listSuccessfulRunsPage: () => {
        queriedActions = true;
        return Promise.resolve({ totalCount: 0, runs: [] });
      },
    }),
  );

  assertEquals(result, {
    mode: "required",
    evidenceSha: null,
    reason: "compatibility-deadline-reached",
  });
  assertEquals(queriedActions, false);
});

Deno.test("GitHub response parsers reject malformed or inconsistent payloads", () => {
  assertThrows(
    () =>
      parseWorkflowRunsPage({
        total_count: 0,
        workflow_runs: [{
          id: 1,
          status: "completed",
          conclusion: "success",
          head_branch: "main",
          head_sha: DEPLOY_SHA,
        }],
      }),
    Error,
    "pagination metadata is inconsistent",
  );
  assertThrows(
    () =>
      parseWorkflowRunsPage({
        total_count: 1,
        workflow_runs: [{
          id: 1,
          status: "completed",
          conclusion: "success",
          head_branch: "main",
          head_sha: 123,
        }],
      }),
    Error,
    "head_sha",
  );
  assertThrows(
    () =>
      parseWorkflowJobsPage({
        total_count: 0,
        jobs: [{
          name: "deploy",
          status: "completed",
          conclusion: "success",
        }],
      }),
    Error,
    "pagination metadata is inconsistent",
  );
});
