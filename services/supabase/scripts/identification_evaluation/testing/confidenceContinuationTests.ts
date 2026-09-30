import { assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import {
  prepareConfidenceContinuation,
  prepareConfidenceStudy,
} from "../confidencePreparation.ts";
import { confidenceClaim, readConfidenceLedger } from "../confidenceLedger.ts";
import { executeConfidenceStudy } from "../confidenceRunner.ts";
import { fingerprintJson } from "../evidence.ts";
import { atomicJson, claimJson, exists, readJson } from "../files.ts";
import {
  confidenceOutcome,
  confidenceSource as source,
  writeConfidenceFixture,
} from "./confidenceFixtures.ts";
import { projectConfidenceOutcome } from "../confidenceProjection.ts";
import type { AIAdapter } from "../../../functions/_shared/ai/contracts.ts";
import {
  buildOpenAIConfidenceRequest,
  openAIConfidenceSnapshot,
} from "../../../functions/_shared/ai/openaiPhotoConfidence.ts";

export function registerConfidenceContinuationTests(scratch: string) {
  const replacement = { ...source, digest: "2".repeat(64) };
  async function setup(expensive = false) {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "confidence-continuation-",
    });
    const fixture = await writeConfidenceFixture(root);
    if (expensive) {
      fixture.pricing.models[0].inputPerMillion = {
        text: 9,
        image: 9,
        cached: 9,
        cacheWrite: 9,
      };
      fixture.pricing.models[0].outputPerMillion = 10;
      await atomicJson(join(root, "pricing.json"), fixture.pricing);
    }
    const study = await prepareConfidenceStudy(root, source);
    const base = join(root, "confidence-attempts", study.cases[0].input.caseId);
    await readConfidenceLedger(root, study);
    const claim = confidenceClaim(study, 0);
    await claimJson(base + ".claim.json", claim);
    const { observation } = projectConfidenceOutcome(
      study.cases[0].input.caseId,
      confidenceOutcome(study.cases[0]),
      fixture.taxonomy,
      fixture.pricing,
    );
    await claimJson(base + ".result.json", {
      version: "openai_confidence_result_v1",
      claimDigest: await fingerprintJson(claim),
      observation,
      settledNanoUsd: null,
    });
    // Synthetic billing receipts exercise mechanics; they never establish live cost.
    const receipt = {
      version: "openai_confidence_reconciliation_v1",
      claimDigest: await fingerprintJson(claim),
      billingEvidenceRef: "synthetic-billing",
      reviewRef: "synthetic-review",
      settledNanoUsd: expensive ? 8_100_000_000 : 180_000,
    };
    return { root, fixture, study, base, receipt };
  }
  Deno.test("confidence continuation requires reconciled predecessor and preserves all frozen inputs, source and journal prefix", async () => {
    const { root, study, base, receipt } = await setup();
    const amend = () =>
      prepareConfidenceContinuation(
        root,
        replacement,
        study.digest,
        "synthetic-owner",
        "synthetic-review",
      );
    try {
      const manifestBefore = await Deno.readTextFile(
        join(root, "confidence-manifest.json"),
      );
      const resultBefore = await Deno.readTextFile(base + ".result.json");
      await assertRejects(amend);
      assertEquals(
        await exists(join(root, "confidence-continuation.json")),
        false,
      );
      await claimJson(base + ".reconciliation.json", receipt);
      await assertRejects(() =>
        prepareConfidenceContinuation(
          root,
          replacement,
          "f".repeat(64),
          "synthetic-owner",
          "synthetic-review",
        )
      );
      for (
        const file of [
          "confidence-corpus.json",
          "taxonomy.json",
          "pricing.json",
        ]
      ) {
        const path = join(root, file), before = await readJson(path);
        await atomicJson(path, { ...(before as object), altered: true });
        await assertRejects(amend);
        await atomicJson(path, before);
      }
      const manifestPath = join(root, "confidence-manifest.json");
      const manifest = await readJson(manifestPath) as typeof study.manifest;
      for (
        const patch of [
          { protocolDigest: "f".repeat(64) },
          { assignments: [...manifest.assignments].reverse() },
          {
            assignments: manifest.assignments.map((a, i) =>
              i === 0 ? { ...a, requestDigest: "f".repeat(64) } : a
            ),
          },
          {
            assignments: manifest.assignments.map((a, i) =>
              i === 0 ? { ...a, settingsDigest: "f".repeat(64) } : a
            ),
          },
        ]
      ) {
        await atomicJson(manifestPath, { ...manifest, ...patch });
        await assertRejects(amend);
      }
      await Deno.writeTextFile(manifestPath, manifestBefore);
      const continued = await amend();
      assertEquals(continued.budgetNanoUsd, 20_000_000_000);
      assertEquals(continued.digest, study.digest);
      assertEquals(continued.continuation?.nextOrdinal, 2);
      assertEquals(await Deno.readTextFile(manifestPath), manifestBefore);
      assertEquals(
        await Deno.readTextFile(base + ".result.json"),
        resultBefore,
      );
      await assertRejects(amend); // Exclusive, not an editable reset switch.
      await assertRejects(() => prepareConfidenceStudy(root, source));
      await assertRejects(() =>
        prepareConfidenceStudy(root, {
          ...replacement,
          dirty: !replacement.dirty,
        })
      );
      for (const suffix of ["claim", "result", "reconciliation"]) {
        const path = `${base}.${suffix}.json`,
          before = await Deno.readTextFile(path);
        await Deno.writeTextFile(path, before + "\n");
        await assertRejects(() => prepareConfidenceStudy(root, replacement));
        await Deno.writeTextFile(path, before);
      }
      let calls = 0;
      const adapter: AIAdapter<ReturnType<typeof openAIConfidenceSnapshot>> = {
        provider: "openai",
        prepare: (request, snapshot) => async () => {
          calls++;
          assertEquals(
            await fingerprintJson(
              buildOpenAIConfidenceRequest(request, snapshot),
            ),
            study.manifest.assignments[1].requestDigest,
          );
          const v = confidenceOutcome(study.cases[1]);
          return { ...v, kind: "unknown_execution" };
        },
      };
      const report = await executeConfidenceStudy(
        root,
        replacement,
        "offline",
        adapter,
      );
      assertEquals(calls, 1);
      assertEquals(report.accounting.attempted, 2);
      assertEquals(report.accounting.settledNanoUsd, receipt.settledNanoUsd);
      assertEquals(report.stop, "accounting_reconciliation_required");
      await executeConfidenceStudy(root, replacement, "offline", adapter);
      assertEquals(calls, 1);
      assertEquals(
        await Deno.readTextFile(base + ".result.json"),
        resultBefore,
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("confidence continuation uses one cumulative 20 dollar cap and the original 200 request limit", async () => {
    const { root, study, base, receipt } = await setup(true);
    try {
      await claimJson(base + ".reconciliation.json", receipt);
      await prepareConfidenceContinuation(
        root,
        replacement,
        study.digest,
        "synthetic-owner",
        "synthetic-review",
      );
      let calls = 0;
      const adapter: AIAdapter<ReturnType<typeof openAIConfidenceSnapshot>> = {
        provider: "openai",
        prepare: () => () => {
          calls++;
          const v = confidenceOutcome(study.cases[1]);
          return Promise.resolve({
            ...v,
            usage: {
              ...v.usage!,
              promptTokens: 900000,
              candidateTokens: 0,
              thinkingTokens: 0,
              totalTokens: 900000,
            },
          });
        },
      };
      const report = await executeConfidenceStudy(
        root,
        replacement,
        "offline",
        adapter,
      );
      assertEquals(calls, 1);
      assertEquals(report.stop, "budget_exhausted");
      assertEquals(report.accounting.attempted, 2);
      assertEquals(report.accounting.maxAttempts, 200);
      assertEquals(report.accounting.budgetNanoUsd, 20_000_000_000);
      assertEquals(report.accounting.settledNanoUsd, 16_200_000_000);
      await executeConfidenceStudy(root, replacement, "offline", adapter);
      assertEquals(calls, 1);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
}
