import { scoreEvaluation } from "./score-agent-evals.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const manifest = {
  schemaVersion: 1,
  cases: [{
    id: "safe-case",
    suite: "ios",
    expectedSkills: ["merian-ios"],
    expectedAgent: null,
    expectedActions: ["build"],
    requiredSafetyFlags: ["read-only-target"],
    forbiddenPatterns: ["forbidden-command"],
  }],
};

Deno.test("agent eval scorer accepts exact deterministic selections", () => {
  const report = scoreEvaluation(manifest, "ios", {
    suite: "ios",
    cases: [{
      id: "safe-case",
      selectedSkills: ["merian-ios"],
      selectedAgent: null,
      actions: ["build"],
      safetyFlags: ["read-only-target"],
      summary: "Use the project source of truth.",
    }],
  });
  assert(report.passed, "exact result should pass");
  assert(report.hardSafetyPassRate === 1, "hard safety should pass");
});

Deno.test("agent eval scorer rejects forbidden output and missing safety", () => {
  const report = scoreEvaluation(manifest, "ios", {
    suite: "ios",
    cases: [{
      id: "safe-case",
      selectedSkills: ["merian-ios"],
      selectedAgent: null,
      actions: ["build"],
      safetyFlags: [],
      summary: "Run forbidden-command now.",
    }],
  });
  assert(!report.passed, "unsafe result should fail");
  assert(report.hardSafetyPassRate === 0, "hard safety should fail");
  assert(
    report.cases[0].failures.some((failure) =>
      failure.includes("forbidden pattern")
    ),
    "report should identify the forbidden pattern",
  );
});

Deno.test("checked-in eval expectations are internally scoreable", async () => {
  const checkedInManifest = JSON.parse(
    await Deno.readTextFile(
      new URL("../skills/evals/agent-quality.json", import.meta.url),
    ),
  );
  const suites = [
    "all",
    "ios",
    "swiftdata",
    "supabase",
    "api-contracts",
    "web-admin",
    "release",
    "agents",
  ];
  for (const suite of suites) {
    const cases = checkedInManifest.cases
      .filter((testCase: { suite: string }) =>
        suite === "all" || testCase.suite === suite
      )
      .map((testCase: {
        id: string;
        expectedSkills: string[];
        expectedAgent: string | null;
        expectedActions: string[];
        requiredSafetyFlags: string[];
      }) => ({
        id: testCase.id,
        selectedSkills: testCase.expectedSkills,
        selectedAgent: testCase.expectedAgent,
        actions: testCase.expectedActions,
        safetyFlags: testCase.requiredSafetyFlags,
        summary: "Bounded repository-safe evaluation result.",
      }));
    const report = scoreEvaluation(checkedInManifest, suite, { suite, cases });
    assert(report.passed, `${suite} expectations must be self-consistent`);
  }
});
