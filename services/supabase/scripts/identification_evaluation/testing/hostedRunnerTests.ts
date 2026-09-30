/** Filesystem integration with invented PNGs only. Network and env are denied. */
import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import {
  fingerprintBytes,
  fingerprintEvidence,
  fingerprintJson,
} from "../evidence.ts";
import {
  createExperimentDemo,
  experimentOfflineOutcome,
} from "../experimentOffline.ts";
import { executeExperimentRun, prepareExperiment } from "../experiment.ts";
import { parseExploratoryCorpus } from "../exploratory.ts";
import {
  atomicJson,
  claimJson,
  exists,
  readBytes,
  readJson,
} from "../files.ts";
import {
  assertHostedRunComplete,
  checkHostedPacket,
  decodeHostedBundle,
  exportHostedBundle,
  HOSTED_RUNS,
  hostedPublicSummary,
  hostedReadiness,
  prepareHostedExperiment,
  stageHostedBundle,
  validateHostedBundle,
} from "../hosted.ts";
import { hostedSpecFixture } from "./hostedFixture.ts";

export function registerHostedTests(scratch: string) {
  async function fixture() {
    const parent = await Deno.makeTempDir({ dir: scratch, prefix: "hosted-" });
    const root = join(parent, "source"),
      now = Date.now(),
      spec = await hostedSpecFixture(now);
    await createExperimentDemo(root, spec.source, now);
    const old = parseExploratoryCorpus(
      await readJson(join(root, "corpus.json")),
    );
    const images = [];
    for await (const e of Deno.readDir(join(root, "assets"))) {
      if (e.name.endsWith(".png")) images.push(e.name);
    }
    images.sort();
    assert(images.length >= 6);
    const cases = [];
    for (let i = 0; i < 8; i++) {
      const number = String(i + 1).padStart(4, "0");
      const bytes = i < 6
        ? await readBytes(join(root, "assets", images[i]), 1024)
        : null;
      cases.push({
        input: {
          caseId: `c${number}`,
          groupId: `g${number}`,
          split: "development",
          inputGroup: i < 6 ? "photos" : "description",
          observationTexts: i < 6 ? [] : [`Invented test observation ${i}.`],
          context: { currentMonth: 9, deviceRegion: "US" },
          clips: [],
          assets: bytes
            ? [{
              id: images[i].slice(0, -4),
              kind: "image",
              mimeType: "image/png",
              path: `assets/${images[i]}`,
              byteLength: bytes.length,
              sha256: await fingerprintBytes(bytes),
              sourceIndex: 0,
            }]
            : [],
        },
        provisionalReference: null,
        curation: {
          kind: "eligibility_reviewed",
          source: "purpose_collected",
          sourceRecordRef: "synthetic-source",
          referenceRecordRef: null,
          permission: "gemini_evaluation",
          rightsApproved: true,
          personalDataExcluded: true,
          nearDuplicatesReviewed: true,
        },
      });
    }
    const corpus = parseExploratoryCorpus({
      ...old,
      evidenceOrigin: "real",
      eligibility: {
        recordRef: "synthetic-eligibility",
        reviewerRef: "r0001",
        reviewerKind: "automated",
        retainUntil: new Date(now + 7 * 86400000).toISOString().slice(0, 10),
      },
      cases,
    });
    await atomicJson(join(root, "corpus.json"), corpus);
    spec.corpusDigest = await fingerprintJson(corpus);
    spec.taxonomyDigest = await fingerprintJson(
      await readJson(join(root, "taxonomy.json")),
    );
    await atomicJson(join(root, "hosted-spec.json"), spec);
    await atomicJson(join(root, "private-account.json"), {
      account: "excluded-test-sentinel",
    });
    return { parent, root, now, spec, corpus };
  }

  Deno.test("hosted bundle export stages byte-identical evidence and freezes actual readiness without publishing account files", async () => {
    const f = await fixture();
    try {
      const out = join(f.parent, "bundle.json"),
        staged = join(f.parent, "staged");
      const info = await exportHostedBundle(
        f.root,
        join(f.root, "hosted-spec.json"),
        out,
      );
      const bytes = await readBytes(out, 24 * 1024 * 1024);
      assert(
        !new TextDecoder().decode(bytes).includes("excluded-test-sentinel"),
      );
      assert(!new TextDecoder().decode(bytes).includes("credentialSha256"));
      const bundle = await decodeHostedBundle(bytes, info.sha256);
      await stageHostedBundle(staged, bytes, info.sha256, f.spec.source);
      assertEquals(await readJson(join(staged, "corpus.json")), f.corpus);
      assertEquals(await exists(join(staged, "private-account.json")), false);
      await checkHostedPacket(staged, f.spec.source, f.now);
      assertEquals(await exists(join(staged, "experiment.json")), false);
      assertEquals(
        await exists(join(staged, "approvals", "gemini-baseline.json")),
        false,
      );
      for (const c of f.corpus.cases) {
        for (const a of c.input.assets) {
          assertEquals(
            await readBytes(join(staged, a.path), 1024),
            await readBytes(join(f.root, a.path), 1024),
          );
        }
      }
      for (const [i, provider] of ["gemini", "openai"].entries()) {
        const readiness = await hostedReadiness(
          f.spec,
          f.corpus,
          provider as "gemini" | "openai",
          `synthetic-${provider}-credential`,
        );
        await claimJson(
          join(staged, "approvals", `${HOSTED_RUNS[i]}.json`),
          readiness,
        );
      }
      const prepared = await prepareHostedExperiment(
        staged,
        f.spec.source,
        f.now,
      );
      assertEquals(prepared.plan.maxCalls, 16);
      assertEquals(prepared.inputs.map((i) => i.manifest.order.length), [8, 8]);
      assertEquals(
        prepared.plan.cases[0].inputDigest,
        await fingerprintEvidence(f.corpus.cases[0].input),
      );
      await assertRejects(() =>
        stageHostedBundle(staged, bytes, info.sha256, f.spec.source)
      );
      await assertRejects(() => decodeHostedBundle(bytes, "f".repeat(64)));
      await assertRejects(() =>
        stageHostedBundle(join(f.parent, "wrong-source"), bytes, info.sha256, {
          ...f.spec.source,
          digest: "9".repeat(64),
        })
      );
      const otherSdkSource = {
        ...f.spec.source,
        sdk: "npm:@google/genai@2.24.0",
      };
      await assertRejects(() =>
        stageHostedBundle(
          join(f.parent, "wrong-sdk"),
          bytes,
          info.sha256,
          otherSdkSource,
        )
      );
      await assertRejects(() =>
        checkHostedPacket(staged, otherSdkSource, f.now)
      );
      await assertRejects(() =>
        prepareHostedExperiment(staged, otherSdkSource, f.now)
      );
      for (
        const mutate of [
          (b: typeof bundle) => {
            b.assets[0].path = "../outside.png";
          },
          (b: typeof bundle) => {
            b.assets[0].base64 = "AAAA";
          },
          (b: typeof bundle) => {
            b.assets[1] = b.assets[0];
          },
          (b: typeof bundle) => {
            b.spec.runs[0].profileDigest = "8".repeat(64);
          },
        ]
      ) {
        const bad = structuredClone(bundle);
        mutate(bad);
        await assertRejects(() => validateHostedBundle(bad));
      }
      assertEquals(await exists(join(f.parent, "outside.png")), false);
      const outSummary = join(f.parent, "public", "summary.json");
      let summary = await hostedPublicSummary(staged, outSummary);
      assertEquals(summary.status, "preflight_passed");
      await claimJson(join(staged, "hosted-claim-attempt.json"), {
        synthetic: true,
      });
      summary = await hostedPublicSummary(staged, outSummary);
      assertEquals(summary.status, "claim_unconfirmed_no_replay");
      assertEquals(summary.unresolvedAllocationUsd, f.spec.budgetUsd);
      await claimJson(join(staged, "hosted-claim.json"), { synthetic: true });
      summary = await hostedPublicSummary(staged, outSummary);
      assertEquals(summary.status, "incomplete_no_replay");
      assertEquals(summary.complete, false);
      assert(!JSON.stringify(summary).includes("credentialSha256"));
    } finally {
      await Deno.remove(f.parent, { recursive: true });
    }
  });

  Deno.test("hosted complete guard checks controller stop as well as process success", async () => {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "hosted-controller-",
    });
    const spec = await hostedSpecFixture();
    try {
      // The actual offline controller supplies report/stop behavior; no live execution.
      const plan = await createExperimentDemo(root, spec.source);
      const prepared = await prepareExperiment(root, spec.source);
      for (const [i, run] of plan.runs.entries()) {
        await executeExperimentRun(root, run.runId, spec.source, {
          offlineOutcome: await experimentOfflineOutcome(
            root,
            prepared.inputs[i],
          ),
        });
      }
      const state = await readJson(
        join(root, "experiment", "state.json"),
      ) as Record<string, unknown>;
      state.completedRunIds = [...HOSTED_RUNS];
      await atomicJson(join(root, "experiment", "state.json"), state);
      await assertHostedRunComplete(root, "gemini");
      await assertHostedRunComplete(root, "openai");
      await atomicJson(join(root, "experiment", "state.json"), {
        ...state,
        stop: "uncertain_execution",
      });
      await assertRejects(() => assertHostedRunComplete(root, "openai"));
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
}
