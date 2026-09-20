import JSZip from "jszip";
import { assertEquals, assertRejects, assertStringIncludes } from "@std/assert";
import {
  GitHubReleaseEvidenceVerifier,
  parseAndValidateReleaseEvidenceStatement,
} from "./github_release_evidence.ts";

const candidateSha = "a".repeat(40);
const repository = "merian/example";

function ownedArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    ownedArrayBuffer(bytes),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function json(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

async function evidenceArchive(): Promise<{
  bytes: Uint8Array;
  digest: string;
}> {
  const statement = {
    schema_version: 2,
    hold_id: "test_hold",
    criterion_id: "hosted_proof",
    evidence_type: "hosted_test_run",
    candidate_sha: candidateSha,
    outcome: "passed",
    observed_at: "2026-08-24T12:00:00.000Z",
    summary: "The exact candidate passed the required hosted gate.",
    supporting_runs: [{
      run_id: 22,
      workflow_path: ".github/workflows/test.yml",
    }],
    embedded_evidence: [],
  };
  const zip = new JSZip();
  zip.file("release-evidence.json", JSON.stringify(statement));
  const bytes = await zip.generateAsync({
    type: "uint8array",
    compression: "STORE",
  });
  return { bytes, digest: await sha256(bytes) };
}

function protectedEnvironment() {
  return {
    can_admins_bypass: false,
    protection_rules: [{ type: "branch_policy" }],
    deployment_branch_policy: {
      protected_branches: true,
      custom_branch_policies: false,
    },
  };
}

Deno.test("GitHub release evidence downloads bytes and validates live controls", async () => {
  const archive = await evidenceArchive();
  const fetcher: typeof fetch = (input) => {
    const url = String(input);
    if (url.endsWith("/branches/main")) {
      return Promise.resolve(json({
        name: "main",
        protected: true,
        commit: { sha: candidateSha },
      }));
    }
    if (url.endsWith("/branches/main/protection")) {
      return Promise.resolve(json({
        required_pull_request_reviews: {
          dismiss_stale_reviews: true,
          require_last_push_approval: false,
          require_code_owner_reviews: false,
          required_approving_review_count: 0,
          bypass_pull_request_allowances: { users: [], teams: [], apps: [] },
        },
        required_status_checks: {
          strict: true,
          contexts: ["Candidate readiness"],
        },
        enforce_admins: { enabled: true },
        allow_force_pushes: { enabled: false },
        allow_deletions: { enabled: false },
      }));
    }
    if (url.endsWith(`/commits/${candidateSha}/pulls?per_page=100`)) {
      return Promise.resolve(json([{
        number: 17,
        merged_at: "2026-08-24T10:00:00Z",
        merge_commit_sha: candidateSha,
        base: { ref: "main", repo: { full_name: "Merian/Example" } },
        user: { login: "author", type: "User" },
      }]));
    }
    if (
      url.includes("/environments/Release%20Evidence") ||
      url.endsWith("/environments/Production")
    ) {
      return Promise.resolve(json(protectedEnvironment()));
    }
    if (url.endsWith("/actions/artifacts/11")) {
      return Promise.resolve(json({
        id: 11,
        name:
          `merian-release-evidence-hosted_proof-${candidateSha}-21-attempt-1`,
        size_in_bytes: archive.bytes.byteLength,
        expired: false,
        digest: `sha256:${archive.digest}`,
        archive_download_url:
          `https://api.github.com/repos/${repository}/actions/artifacts/11/zip`,
        workflow_run: { id: 21, head_sha: candidateSha },
      }));
    }
    if (url.endsWith("/actions/runs/21")) {
      return Promise.resolve(json({
        id: 21,
        run_attempt: 1,
        head_sha: candidateSha,
        status: "completed",
        conclusion: "success",
        path: ".github/workflows/release-evidence.yml",
        updated_at: "2026-08-24T12:00:00Z",
      }));
    }
    if (url.endsWith("/actions/runs/22")) {
      return Promise.resolve(json({
        id: 22,
        run_attempt: 1,
        head_sha: candidateSha,
        status: "completed",
        conclusion: "success",
        path: ".github/workflows/test.yml",
        updated_at: "2026-08-24T12:00:00Z",
      }));
    }
    if (url.endsWith("/actions/artifacts/11/zip")) {
      return Promise.resolve(
        new Response(ownedArrayBuffer(archive.bytes), {
          status: 200,
          headers: { "Content-Length": String(archive.bytes.byteLength) },
        }),
      );
    }
    return Promise.resolve(new Response("not found", { status: 404 }));
  };
  const verifier = new GitHubReleaseEvidenceVerifier({
    token: "test-token",
    repository,
    fetcher,
    now: () => new Date("2026-08-24T18:00:00.000Z"),
  });
  assertEquals(await verifier.verifyRepositoryControls(candidateSha), [
    "main_branch_protection",
    "candidate_is_current_main_head",
    "pull_request_17_merged_main_provenance",
    "automatic_environment_policy",
    "release_evidence_environment_protection",
    "production_environment_protection",
  ]);
  assertStringIncludes(
    await verifier.verifyCriterion({
      holdId: "test_hold",
      criterionId: "hosted_proof",
      evidenceType: "hosted_test_run",
      requiredWorkflows: [".github/workflows/test.yml"],
      artifactId: 11,
      artifactSha256: archive.digest,
      candidateSha,
    }),
    `artifact:11:sha256:${archive.digest}`,
  );

  await assertRejects(() =>
    verifier.verifyCriterion({
      holdId: "test_hold",
      criterionId: "hosted_proof",
      evidenceType: "hosted_test_run",
      requiredWorkflows: [".github/workflows/test.yml"],
      artifactId: 11,
      artifactSha256: "f".repeat(64),
      candidateSha,
    })
  );
});

Deno.test("embedded manual evidence is recomputed and candidate-bound", async () => {
  const embeddedRaw = JSON.stringify({
    schema_version: 2,
    hold_id: "test_hold",
    criterion_id: "device_proof",
    evidence_type: "device_install_over",
    candidate_sha: candidateSha,
    outcome: "passed",
    observed_at: "2026-08-24T11:00:00.000Z",
    summary:
      "Released V49 installed over to V50 without recovery or data loss.",
  });
  const embeddedBytes = new TextEncoder().encode(embeddedRaw);
  const statement = JSON.stringify({
    schema_version: 2,
    hold_id: "test_hold",
    criterion_id: "device_proof",
    evidence_type: "device_install_over",
    candidate_sha: candidateSha,
    outcome: "passed",
    observed_at: "2026-08-24T12:00:00.000Z",
    summary: "Physical install-over evidence is retained in this artifact.",
    supporting_runs: [],
    embedded_evidence: [{
      label: "install-over-result",
      media_type: "application/json",
      content_base64: btoa(embeddedRaw),
      sha256: await sha256(embeddedBytes),
    }],
  });
  const parsed = await parseAndValidateReleaseEvidenceStatement(
    statement,
    {
      holdId: "test_hold",
      criterionId: "device_proof",
      evidenceType: "device_install_over",
      requiredWorkflows: [],
      candidateSha,
    },
    () => Promise.resolve(),
    new Date("2026-08-24T18:00:00.000Z"),
  );
  assertEquals(parsed.embedded_evidence.length, 1);

  const tampered = JSON.parse(statement);
  tampered.embedded_evidence[0].content_base64 = btoa(`${embeddedRaw} `);
  await assertRejects(() =>
    parseAndValidateReleaseEvidenceStatement(
      JSON.stringify(tampered),
      {
        holdId: "test_hold",
        criterionId: "device_proof",
        evidenceType: "device_install_over",
        requiredWorkflows: [],
        candidateSha,
      },
      () => Promise.resolve(),
      new Date("2026-08-24T18:00:00.000Z"),
    )
  );

  const stale = JSON.parse(statement);
  stale.observed_at = "2026-07-01T00:00:00.000Z";
  await assertRejects(
    () =>
      parseAndValidateReleaseEvidenceStatement(
        JSON.stringify(stale),
        {
          holdId: "test_hold",
          criterionId: "device_proof",
          evidenceType: "device_install_over",
          requiredWorkflows: [],
          candidateSha,
        },
        () => Promise.resolve(),
        new Date("2026-08-24T18:00:00.000Z"),
      ),
    Error,
    "older than 30 days",
  );
});

Deno.test("repository controls reject a candidate that is not current main", async () => {
  const verifier = new GitHubReleaseEvidenceVerifier({
    token: "test-token",
    repository,
    fetcher: () =>
      Promise.resolve(json({
        name: "main",
        protected: true,
        commit: { sha: "b".repeat(40) },
      })),
  });

  await assertRejects(
    () => verifier.verifyRepositoryControls(candidateSha),
    Error,
    "not the current protected main head",
  );
});

Deno.test("repository controls reject disabled admin enforcement", async () => {
  const verifier = new GitHubReleaseEvidenceVerifier({
    token: "test-token",
    repository,
    fetcher: (input) => {
      const url = String(input);
      if (url.endsWith("/branches/main")) {
        return Promise.resolve(json({
          name: "main",
          protected: true,
          commit: { sha: candidateSha },
        }));
      }
      return Promise.resolve(json({
        required_pull_request_reviews: {
          dismiss_stale_reviews: true,
          require_last_push_approval: false,
          require_code_owner_reviews: false,
          required_approving_review_count: 0,
          bypass_pull_request_allowances: { users: [], teams: [], apps: [] },
        },
        enforce_admins: { enabled: false },
      }));
    },
  });

  await assertRejects(
    () => verifier.verifyRepositoryControls(candidateSha),
    Error,
    "must require PRs with zero peer approvals",
  );
});

Deno.test("repository controls reject a merged pull request targeting another branch", async () => {
  const verifier = new GitHubReleaseEvidenceVerifier({
    token: "test-token",
    repository,
    fetcher: (input) => {
      const url = String(input);
      if (url.endsWith("/branches/main")) {
        return Promise.resolve(json({
          name: "main",
          protected: true,
          commit: { sha: candidateSha },
        }));
      }
      if (url.endsWith("/branches/main/protection")) {
        return Promise.resolve(json({
          required_pull_request_reviews: {
            dismiss_stale_reviews: true,
            require_last_push_approval: false,
            require_code_owner_reviews: false,
            required_approving_review_count: 0,
            bypass_pull_request_allowances: { users: [], teams: [], apps: [] },
          },
          required_status_checks: {
            strict: true,
            contexts: ["Candidate readiness"],
          },
          enforce_admins: { enabled: true },
          allow_force_pushes: { enabled: false },
          allow_deletions: { enabled: false },
        }));
      }
      return Promise.resolve(json([{
        number: 17,
        merged_at: "2026-08-24T10:00:00Z",
        merge_commit_sha: candidateSha,
        base: { ref: "release", repo: { full_name: repository } },
        user: { login: "author" },
      }]));
    },
  });

  await assertRejects(
    () => verifier.verifyRepositoryControls(candidateSha),
    Error,
    "one merged main pull request",
  );
});

function soloControls(): Record<string, unknown> {
  return {
    "/branches/main": {
      name: "main",
      protected: true,
      commit: { sha: candidateSha },
    },
    "/branches/main/protection": {
      required_pull_request_reviews: {
        dismiss_stale_reviews: true,
        require_last_push_approval: false,
        require_code_owner_reviews: false,
        required_approving_review_count: 0,
        bypass_pull_request_allowances: { users: [], teams: [], apps: [] },
      },
      required_status_checks: {
        strict: true,
        contexts: ["Candidate readiness"],
      },
      enforce_admins: { enabled: true },
      allow_force_pushes: { enabled: false },
      allow_deletions: { enabled: false },
    },
    [`/commits/${candidateSha}/pulls?per_page=100`]: [{
      number: 17,
      merged_at: "2026-08-24T10:00:00Z",
      merge_commit_sha: candidateSha,
      base: { ref: "main", repo: { full_name: repository } },
      user: { login: "emreerdener", type: "User" },
    }],
    "/environments/Release%20Evidence": protectedEnvironment(),
    "/environments/Production": protectedEnvironment(),
  };
}

function verifierForControls(controls: Record<string, unknown>) {
  return new GitHubReleaseEvidenceVerifier({
    token: "test-token",
    repository,
    fetcher: (input) => {
      const url = new URL(String(input));
      const path = url.pathname.replace(`/repos/${repository}`, "") +
        url.search;
      return Promise.resolve(
        path in controls
          ? json(controls[path])
          : new Response(null, { status: 404 }),
      );
    },
  });
}

Deno.test("automatic environments retain merged PR and protected branch checks", async () => {
  const controls = await verifierForControls(soloControls())
    .verifyRepositoryControls(candidateSha);
  assertEquals(controls.includes("automatic_environment_policy"), true);
});

for (const environment of ["Release%20Evidence", "Production"]) {
  const valid = protectedEnvironment();
  for (
    const [name, invalid] of Object.entries({
      "unknown protection rules": { ...valid, protection_rules: null },
      "required reviewer": {
        ...valid,
        protection_rules: [{
          type: "required_reviewers",
          reviewers: [{ type: "User", reviewer: { login: "emreerdener" } }],
        }],
      },
      "empty reviewer rule": {
        ...valid,
        protection_rules: [{ type: "required_reviewers", reviewers: [] }],
      },
      "wait timer": {
        ...valid,
        protection_rules: [{ type: "wait_timer", wait_timer: 30 }],
      },
      "custom gate": {
        ...valid,
        protection_rules: [{ type: "custom_deployment_protection_rule" }],
      },
      "malformed rule": { ...valid, protection_rules: [null] },
      "unrestricted branches": { ...valid, deployment_branch_policy: null },
      "custom branch policy": {
        ...valid,
        deployment_branch_policy: {
          protected_branches: false,
          custom_branch_policies: true,
        },
      },
    })
  ) {
    Deno.test(`automatic release rejects ${environment}: ${name}`, async () => {
      const controls = soloControls();
      controls[`/environments/${environment}`] = invalid;
      await assertRejects(
        () =>
          verifierForControls(controls).verifyRepositoryControls(candidateSha),
        Error,
        "must allow automatic jobs",
      );
    });
  }
}

Deno.test("automatic release accepts GitHub's omitted empty bypass field", async () => {
  const controls = soloControls();
  const protection = controls["/branches/main/protection"] as Record<
    string,
    unknown
  >;
  const reviews = protection.required_pull_request_reviews as Record<
    string,
    unknown
  >;
  delete reviews.bypass_pull_request_allowances;
  const verified = await verifierForControls(controls).verifyRepositoryControls(
    candidateSha,
  );
  assertEquals(verified.includes("main_branch_protection"), true);
  assertEquals(verified.includes("production_environment_protection"), true);
});

for (
  const [name, override] of Object.entries({
    "missing PR requirement": { required_pull_request_reviews: null },
    "missing checks": { required_status_checks: null },
    "wrong checks": {
      required_status_checks: { strict: true, contexts: ["unrelated"] },
    },
    "outdated branch permitted": {
      required_status_checks: {
        strict: false,
        contexts: ["Candidate readiness"],
      },
    },
    "admin exemption": { enforce_admins: { enabled: false } },
    "force pushes": { allow_force_pushes: { enabled: true } },
    "branch deletion": { allow_deletions: { enabled: true } },
  })
) {
  Deno.test(`sole maintainer retains branch protection: ${name}`, async () => {
    const controls = soloControls();
    controls["/branches/main/protection"] = {
      ...(controls["/branches/main/protection"] as Record<string, unknown>),
      ...override,
    };
    await assertRejects(() =>
      verifierForControls(controls).verifyRepositoryControls(candidateSha)
    );
  });
}

for (
  const [name, override] of Object.entries({
    "peer approval deadlock": { required_approving_review_count: 1 },
    "Code Owner self-approval deadlock": { require_code_owner_reviews: true },
    "last-push approval deadlock": { require_last_push_approval: true },
    "stale review retained": { dismiss_stale_reviews: false },
    "user bypass": {
      bypass_pull_request_allowances: { users: [{}], teams: [], apps: [] },
    },
    "team bypass": {
      bypass_pull_request_allowances: { users: [], teams: [{}], apps: [] },
    },
    "app bypass": {
      bypass_pull_request_allowances: { users: [], teams: [], apps: [{}] },
    },
    "null bypass": { bypass_pull_request_allowances: null },
    "malformed bypass": { bypass_pull_request_allowances: "none" },
    "incomplete bypass": { bypass_pull_request_allowances: { users: [] } },
  })
) {
  Deno.test(`sole maintainer rejects PR rule: ${name}`, async () => {
    const controls = soloControls();
    const protection = controls["/branches/main/protection"] as Record<
      string,
      unknown
    >;
    protection.required_pull_request_reviews = {
      ...(protection.required_pull_request_reviews as Record<string, unknown>),
      ...override,
    };
    await assertRejects(
      () =>
        verifierForControls(controls).verifyRepositoryControls(candidateSha),
      Error,
      "must require PRs with zero peer approvals",
    );
  });
}

Deno.test("automatic environments permit empty protection rules with protected branches", async () => {
  const controls = soloControls();
  for (const name of ["Release%20Evidence", "Production"]) {
    controls[`/environments/${name}`] = {
      ...protectedEnvironment(),
      protection_rules: [],
      can_admins_bypass: true,
    };
  }
  assertEquals(
    (await verifierForControls(controls).verifyRepositoryControls(candidateSha))
      .includes("automatic_environment_policy"),
    true,
  );
});
