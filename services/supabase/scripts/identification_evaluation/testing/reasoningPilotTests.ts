import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import {
  confidenceOutcome,
  confidenceSource as source,
  writeConfidenceFixture,
} from "./confidenceFixtures.ts";
import { atomicJson, claimJson, exists, readJson } from "../files.ts";
import {
  bindReasoningAuthorization,
  executeReasoningPilot,
  prepareReasoningPilot,
  readReasoningLedger,
  REASONING_PILOT,
  type ReasoningPlan,
} from "../reasoningPilot.ts";
import { fingerprintJson } from "../evidence.ts";
import type { Ratings } from "../explanationContracts.ts";

const ratings: Ratings = {
  grounding: { status: "pass", reason: "supported" },
  requiredInformation: { status: "pass", reason: "supported" },
  uncertainty: { status: "pass", reason: "supported" },
};
export function registerReasoningPilotTests(scratch: string) {
  async function setup(parent = scratch) {
    const root = await Deno.makeTempDir({ dir: parent, prefix: "reasoning-" });
    const fixture = await writeConfidenceFixture(root);
    const cases = fixture.corpus.cases.filter((c) =>
      c.input.split === "development"
    ).slice(0, 4);
    const plan: ReasoningPlan = {
      version: REASONING_PILOT.version,
      mode: "offline",
      authorizationRef: "synthetic",
      packetRootDigest: await fingerprintJson(await Deno.realPath(root)),
      cases: cases.map((c, i) => ({
        input: c.input,
        reference: i === 0 ? null : c.reference,
        evidenceRef: "synthetic",
        facts: ["Invented fixture, not evidence."],
        rightsApproved: true,
        personalDataExcluded: true,
      })),
    };
    await atomicJson(join(root, "reasoning-plan.json"), plan);
    return {
      root,
      cases,
      plan,
      pilot: await prepareReasoningPilot(root, source),
    };
  }
  Deno.test("reasoning pilot dispatches exactly 12 preclaimed calls without reference leakage, records only projections and resumes without calls", async () => {
    const { root, cases, pilot } = await setup();
    try {
      let calls = 0;
      const adapter = {
        provider: "openai",
        prepare: (request: unknown) => async () => {
          const a = pilot.manifest.assignments[calls++];
          const base = join(
            root,
            "reasoning-attempts",
            String(calls).padStart(2, "0"),
          );
          assert(await exists(base + ".claim.json"));
          assert(!JSON.stringify(request).includes("Invented fixture"));
          return confidenceOutcome(
            cases.find((c) => c.input.caseId === a.caseId)!,
          );
        },
      };
      const result = await executeReasoningPilot(
        root,
        source,
        "offline",
        adapter,
        () => Promise.resolve(ratings),
      );
      assertEquals(result.complete, true);
      assertEquals(result.attempted, 12);
      assertEquals(
        result.records.filter((r) => r.effort === "medium").length,
        6,
      );
      assertEquals(
        result.records.filter((r) => r.assessment === null).length,
        6,
      );
      assertEquals(result.outstandingNanoUsd, 0);
      const saved = JSON.stringify(result);
      for (
        const forbidden of [
          "Syntheticus",
          "ai_reasoning",
          "data:image",
          "Invented fixture",
        ]
      ) assert(!saved.includes(forbidden));
      await executeReasoningPilot(
        root,
        source,
        "offline",
        adapter,
        () => Promise.resolve(ratings),
      );
      assertEquals(calls, 12);
      await assertRejects(() =>
        prepareReasoningPilot(root, { ...source, digest: "f".repeat(64) })
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("reasoning pilot retains unknown attempts, cost reservations, and missing reviews without replay", async () => {
    for (
      const failure of ["throw", "missing_usage", "missing_review"] as const
    ) {
      const { root, cases, pilot } = await setup();
      try {
        let calls = 0;
        const adapter = {
          provider: "openai",
          prepare: () => () => {
            calls++;
            if (failure === "throw") throw new Error("synthetic interruption");
            const outcome = confidenceOutcome(cases[0]);
            return Promise.resolve(
              failure === "missing_usage"
                ? { ...outcome, usage: null }
                : outcome,
            );
          },
        };
        await executeReasoningPilot(
          root,
          source,
          "offline",
          adapter,
          () => Promise.resolve(null),
        );
        await executeReasoningPilot(
          root,
          source,
          "offline",
          adapter,
          () => Promise.resolve(ratings),
        );
        assertEquals(calls, 1);
        const ledger = await readReasoningLedger(root, pilot);
        assertEquals(ledger.attempted, 1);
        assertEquals(
          ledger.outstandingNanoUsd,
          failure === "missing_review"
            ? 0
            : pilot.manifest.assignments[0].reservedNanoUsd,
        );
        assert(ledger.stop !== null);
      } finally {
        await Deno.remove(root, { recursive: true });
      }
    }
  });
  Deno.test("reasoning pilot reserves before dispatch and stops at its cumulative budget", async () => {
    const { root, cases } = await setup();
    try {
      let calls = 0;
      const adapter = {
        provider: "openai",
        prepare: () => () => {
          calls++;
          const outcome = confidenceOutcome(cases[0]);
          return Promise.resolve({
            ...outcome,
            usage: {
              ...outcome.usage!,
              promptTokens: 1_000_000,
              cachedTokens: 0,
              candidateTokens: 30,
              thinkingTokens: 10,
              totalTokens: 1_000_040,
            },
          });
        },
      };
      const report = await executeReasoningPilot(
        root,
        source,
        "offline",
        adapter,
        () => Promise.resolve(ratings),
      );
      assertEquals(report.stop, "budget_exhausted");
      assert(calls > 0 && calls < 12);
      assert(report.settledNanoUsd <= REASONING_PILOT.budgetNanoUsd);
      const prior = calls;
      await executeReasoningPilot(
        root,
        source,
        "offline",
        adapter,
        () => Promise.resolve(ratings),
      );
      assertEquals(calls, prior);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("reasoning pilot binds one authorization to its original packet and manifest", async () => {
    const first = await setup();
    const copied = await setup();
    const otherParent = await Deno.makeTempDir({
      dir: scratch,
      prefix: "relocated-",
    });
    const relocated = await setup(otherParent);
    try {
      await bindReasoningAuthorization(first.root, first.pilot);
      await bindReasoningAuthorization(first.root, first.pilot);
      await assertRejects(() =>
        bindReasoningAuthorization(copied.root, copied.pilot)
      );
      await assertRejects(() =>
        bindReasoningAuthorization(relocated.root, first.pilot)
      );
      await atomicJson(join(relocated.root, "reasoning-plan.json"), first.plan);
      await assertRejects(() => prepareReasoningPilot(relocated.root, source));
      await assertRejects(() =>
        bindReasoningAuthorization(first.root, {
          ...first.pilot,
          digest: "f".repeat(64),
        })
      );
    } finally {
      await Deno.remove(first.root, { recursive: true });
      await Deno.remove(copied.root, { recursive: true });
      await Deno.remove(otherParent, { recursive: true });
      await Deno.remove(
        join(
          scratch,
          ".reasoning-authorizations",
          await fingerprintJson("synthetic") + ".json",
        ),
      );
    }
  });
  Deno.test("reasoning pilot refuses repeated interrupted claims and tampered frozen input", async () => {
    const { root, pilot, plan } = await setup();
    try {
      await readReasoningLedger(root, pilot);
      const path = join(root, "reasoning-attempts", "01.claim.json");
      const claim = {
        version: "openai_photo_reasoning_claim_v1",
        manifestDigest: pilot.digest,
        assignment: pilot.manifest.assignments[0],
      };
      await claimJson(path, claim);
      await assertRejects(() => claimJson(path, claim));
      assertEquals(
        (await readReasoningLedger(root, pilot)).stop,
        "interrupted_attempt",
      );
      assertEquals(
        await fingerprintJson(await readJson(path)),
        await fingerprintJson(claim),
      );
      await atomicJson(join(root, "reasoning-plan.json"), {
        ...plan,
        cases: plan.cases.map((c, i) =>
          i ? c : { ...c, facts: ["Changed after freeze"] }
        ),
      });
      await assertRejects(() => prepareReasoningPilot(root, source));
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
}
