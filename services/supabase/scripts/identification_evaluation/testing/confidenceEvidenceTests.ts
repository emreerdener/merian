import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import type { AIAdapter } from "../../../functions/_shared/ai/contracts.ts";
import { openAIConfidenceSnapshot } from "../../../functions/_shared/ai/openaiPhotoConfidence.ts";
import type { ConfidenceEvidence } from "../confidenceEvidence.ts";
import { confidenceEvidenceDigest } from "../confidenceEvidence.ts";
import { readConfidenceLedger } from "../confidenceLedger.ts";
import { prepareConfidenceStudy } from "../confidencePreparation.ts";
import { CONFIDENCE_PROTOCOL as P } from "../confidenceProtocol.ts";
import { executeConfidenceStudy } from "../confidenceRunner.ts";
import { atomicJson, exists } from "../files.ts";
import {
  confidenceOutcome,
  confidenceSource as source,
  writeConfidenceFixture,
} from "./confidenceFixtures.ts";

/** Invented records exercise the live-format boundary without network/credentials. */
async function referenceFormatFixture(root: string) {
  const fixture = await writeConfidenceFixture(root);
  fixture.corpus.kind = "reference";
  const evidence: ConfidenceEvidence = {
    version: "openai_confidence_evidence_v1",
    records: [{
      id: "synthetic-authority",
      kind: "independent",
      reviewerRef: "synthetic-review",
      caseId: null,
      assetDigests: [],
      reference: null,
      relatedRefs: [],
      sourceUrls: ["https://example.invalid/invented-key"],
      sourceRevisionRefs: ["synthetic-source-revision"],
      findings: ["Invented diagnostic traits for mechanics tests only."],
    }],
  };
  for (const c of fixture.corpus.cases) {
    const sourceRecordRef = `source-${c.input.caseId}`,
      referenceRecordRef = `reference-${c.input.caseId}`,
      answerabilityRecordRef = `answerability-${c.input.caseId}`;
    c.curation = {
      kind: "reviewed",
      permission: "openai_evaluation",
      sourceRecordRef,
      referenceRecordRef,
      answerabilityRecordRef,
      independentEvidenceRefs: ["synthetic-authority"],
      reviewMethod: P.referenceReviewMethod,
      reviewerRef: "synthetic-review",
      independentHumanValidation: false,
      rightsApproved: true,
      personalDataExcluded: true,
      nearDuplicatesReviewed: true,
      referenceVerified: true,
      developmentOnly: false,
    };
    for (const kind of ["source", "reference", "answerability"] as const) {
      evidence.records.push({
        id: `${kind}-${c.input.caseId}`,
        kind,
        reviewerRef: "synthetic-review",
        caseId: c.input.caseId,
        assetDigests: c.input.assets.map((a) => a.sha256),
        reference: kind === "source" ? null : c.reference,
        relatedRefs: kind === "source" ? [] : [
          sourceRecordRef,
          ...(kind === "answerability" ? [referenceRecordRef] : []),
          "synthetic-authority",
        ],
        sourceUrls: [],
        sourceRevisionRefs: ["synthetic-source-revision"],
        findings: ["Invented review finding, not a real reference."],
      });
    }
  }
  fixture.pricing.retrievedAt = new Date().toISOString();
  await atomicJson(join(root, "confidence-corpus.json"), fixture.corpus);
  await atomicJson(join(root, "confidence-evidence.json"), evidence);
  await atomicJson(join(root, "pricing.json"), fixture.pricing);
  return { ...fixture, evidence };
}

export function registerConfidenceEvidenceTests(scratch: string) {
  Deno.test("confidence freeze requires complete evidence contents bound to every case, asset, rank and independent source", async () => {
    const root = await Deno.makeTempDir({ dir: scratch });
    try {
      const fixture = await referenceFormatFixture(root);
      const path = join(root, "confidence-evidence.json");
      await Deno.remove(path);
      await assertRejects(() => prepareConfidenceStudy(root, source));
      assertEquals(await exists(join(root, "confidence-manifest.json")), false);
      const mutations: ((e: ConfidenceEvidence) => void)[] = [
        (e) => {
          e.records.pop();
        },
        (e) => {
          e.records.push(e.records[0]);
        },
        (e) => {
          e.records[1].caseId = "c9999";
        },
        (e) => {
          e.records[1].assetDigests = ["f".repeat(64)];
        },
        (e) => {
          e.records[2].reference = null;
        },
        (e) => {
          e.records[2].relatedRefs = [];
        },
        (e) => {
          e.records[3].reviewerRef = "other-review";
        },
        (e) => {
          e.records[3].kind = "source";
        },
        (e) => {
          e.records[0].sourceUrls = [];
        },
        (e) => {
          e.records[0].sourceRevisionRefs = [];
        },
        (e) => {
          e.records[1].sourceRevisionRefs = [];
        },
        (e) => {
          e.records[0].findings = [];
        },
        (e) => {
          e.records.push({ ...e.records[0], id: "unused-authority" });
        },
      ];
      for (const mutate of mutations) {
        const copy = structuredClone(fixture.evidence);
        mutate(copy);
        await atomicJson(path, copy);
        await assertRejects(() => prepareConfidenceStudy(root, source));
      }
      await atomicJson(path, fixture.evidence);
      const study = await prepareConfidenceStudy(root, source);
      assert(study.manifest.evidenceDigest);
      assertEquals(study.manifest.version, "openai_confidence_manifest_v2");
      assertEquals(
        await confidenceEvidenceDigest(root, study.corpus),
        study.manifest.evidenceDigest,
      );
      fixture.evidence.records[0].findings = [
        "Changed scientific evidence behind the same opaque identifier.",
      ];
      await atomicJson(path, fixture.evidence);
      await assertRejects(() => prepareConfidenceStudy(root, source));
      assertEquals(await exists(join(root, "confidence-attempts")), false);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });

  Deno.test("confidence runner rechecks frozen evidence before dispatch and never resets existing claims after a record edit", async () => {
    const root = await Deno.makeTempDir({ dir: scratch });
    try {
      const fixture = await referenceFormatFixture(root);
      const study = await prepareConfidenceStudy(root, source);
      let calls = 0;
      const adapter: AIAdapter<ReturnType<typeof openAIConfidenceSnapshot>> = {
        provider: "openai",
        prepare: () => async () => {
          calls++;
          fixture.evidence.records[0].findings = [
            "Changed evidence while the study was already collecting.",
          ];
          await atomicJson(
            join(root, "confidence-evidence.json"),
            fixture.evidence,
          );
          return confidenceOutcome(study.cases[0]);
        },
      };
      await assertRejects(() =>
        executeConfidenceStudy(root, source, "live", adapter)
      );
      assertEquals(calls, 1);
      assertEquals((await readConfidenceLedger(root, study)).attempted, 1);
      await assertRejects(() =>
        executeConfidenceStudy(root, source, "live", adapter)
      );
      assertEquals(calls, 1);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });

  Deno.test("confidence live admission rejects stale or future prices without a call or reservation while reports remain readable", async () => {
    for (const days of [-8, 1]) {
      const root = await Deno.makeTempDir({ dir: scratch });
      try {
        const fixture = await referenceFormatFixture(root);
        fixture.pricing.retrievedAt = new Date(Date.now() + days * 86400000)
          .toISOString();
        await atomicJson(join(root, "pricing.json"), fixture.pricing);
        let calls = 0;
        const adapter: AIAdapter<ReturnType<typeof openAIConfidenceSnapshot>> =
          {
            provider: "openai",
            prepare: () => async () => {
              calls++;
              return await Promise.resolve(
                confidenceOutcome(fixture.corpus.cases[0]),
              );
            },
          };
        const report = await executeConfidenceStudy(
          root,
          source,
          "live",
          adapter,
        );
        assertEquals(calls, 0);
        assertEquals(report.stop, "pricing_review_expired");
        assertEquals(report.accounting.attempted, 0);
        assertEquals(report.accounting.outstandingNanoUsd, 0);
        assertEquals(report.thresholdDecisionEligible, false);
        assert(report.hashes.referenceEvidence);
      } finally {
        await Deno.remove(root, { recursive: true });
      }
    }
  });
}
