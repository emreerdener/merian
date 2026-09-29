import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { join } from "node:path";
import {
  fingerprintBytes,
  fingerprintEvidence,
  fingerprintJson,
} from "../evidence.ts";
import { atomicJson, exists, readJson } from "../files.ts";
import { prepareSolPhotoPrimaryPacket } from "../solPhotoPrimaryPreparation.ts";
import {
  parsePrimaryPreparationPlan,
  parsePrimaryReferenceReview,
  type PrimaryReferenceReview,
} from "../solPhotoPrimaryPreparationContracts.ts";
import { photoModelFixture } from "./photoModelPreparationTests.ts";

async function fixture(parent: string) {
  const source = join(parent, "source"), target = join(parent, "prepared");
  await Deno.mkdir(source, { mode: 0o700 });
  const { corpus, facts } = await photoModelFixture(source, Date.now());
  const names = [
    "Invented example",
    "Inventum",
    "Inventidae",
    "Canis lupus familiaris",
    "Felis catus",
    "Invented lookalike",
  ];
  const ranks = [
    "species",
    "genus",
    "family",
    "species",
    "species",
    "species",
  ] as const;
  const taxonomy = {
    version: "evaluation_taxonomy_v2",
    taxonomyVersion: corpus.taxonomyVersion,
    catalogRef: "synthetic-primary-catalog",
    reviewRef: "synthetic-primary-review",
    taxa: names.map((canonicalName, i) => ({
      taxon: { id: `synthetic:primary-${i}`, rank: ranks[i] },
      canonicalName,
      synonyms: [],
    })),
  };
  for (const [i, c] of corpus.cases.entries()) {
    c.provisionalReference = i === 4 || i === 5
      ? {
        subject: i === 4 ? "biological" : "non_biological",
        resolution: "unresolved",
        supportedRank: null,
        acceptableTaxa: [],
      }
      : {
        subject: "biological",
        resolution: "named",
        supportedRank: taxonomy
          .taxa[i === 0 ? 3 : i === 1 ? 4 : i === 2 ? 1 : i === 3 ? 2 : 0]
          .taxon.rank,
        acceptableTaxa: [
          taxonomy
            .taxa[i === 0 ? 3 : i === 1 ? 4 : i === 2 ? 1 : i === 3 ? 2 : 0]
            .taxon,
        ],
      };
  }
  const review: PrimaryReferenceReview = {
    version: "sol_photo_primary_reference_review_v1",
    corpusDigest: await fingerprintJson(corpus),
    taxonomyDigest: await fingerprintJson(taxonomy),
    factsDigest: await fingerprintJson(facts),
    method: "assistant_input_review_v1",
    reviewerRef: "synthetic-reviewer",
    reviewedAt: new Date().toISOString(),
    catalogCoverage: "finite_not_exhaustive",
    independentTruthVerified: false,
    cases: await Promise.all(corpus.cases.map(async (c, i) => ({
      caseId: c.input.caseId,
      inputDigest: await fingerprintEvidence(c.input),
      referenceDigest: await fingerprintJson(c.provisionalReference),
      factsDigest: await fingerprintJson(facts.cards[i]),
      identitySupport: i === 3 || i === 4
        ? "limited_reference"
        : "usable_provisional",
      missingEvidenceRecorded: true,
      confusableTaxa: i === 6 ? [taxonomy.taxa[5].taxon] : [],
      roles: i === 0
        ? ["domestic_dog"]
        : i === 1
        ? ["domestic_cat"]
        : i === 5
        ? ["mineral_object"]
        : i === 6
        ? ["species_lookalike"]
        : [],
      source: { kind: "synthetic", recordRef: "synthetic-source" },
    }))),
  };
  const plan = {
    version: "sol_photo_primary_preparation_plan_v1",
    corpusDigest: review.corpusDigest,
    taxonomyDigest: review.taxonomyDigest,
    factsDigest: review.factsDigest,
    referenceReviewDigest: await fingerprintJson(review),
    screenCaseIds: corpus.cases.slice(0, 6).map((c) => c.input.caseId),
    challengeCaseIds: corpus.cases.slice(6).map((c) => c.input.caseId),
  };
  const save = async () => {
    for (
      const [name, value] of [
        ["corpus.json", corpus],
        ["taxonomy.json", taxonomy],
        ["photo-model-facts.json", facts],
        ["primary-reference-review.json", review],
        ["primary-preparation-plan.json", plan],
      ] as const
    ) await atomicJson(join(source, name), value);
  };
  await save();
  await atomicJson(join(source, "approval.json"), {
    marker: "historical-authority",
  });
  return { source, target, corpus, taxonomy, facts, review, plan, save };
}

async function treeDigests(root: string) {
  const hashes: Record<string, string> = {};
  const visit = async (path: string) => {
    for await (const entry of Deno.readDir(join(root, path))) {
      const child = join(path, entry.name);
      if (entry.isDirectory) await visit(child);
      else {hashes[child] = await fingerprintBytes(
          await Deno.readFile(join(root, child)),
        );}
    }
  };
  await visit("");
  return hashes;
}

export function registerSolPhotoPrimaryPreparationTests(scratch: string) {
  Deno.test("primary preparation preserves source, binds both requests and reports all five states without claiming quality or authority", async () => {
    const parent = await Deno.makeTempDir({ dir: scratch, prefix: "primary-" });
    try {
      const f = await fixture(parent), before = await treeDigests(f.source);
      const report = await prepareSolPhotoPrimaryPacket(f.source, f.target);
      assertEquals(await treeDigests(f.source), before);
      assertEquals(report.coverage.missing, []);
      assertEquals(report.coverage.limitedOnly, [
        "family",
        "unresolved_biological",
      ]);
      assertEquals(
        report.coverage.referenceCoverage,
        "present_with_reference_limits",
      );
      assertEquals(report.coverage.evidenceStatus, "synthetic_mechanics_only");
      assertEquals(report.qualityQualified, false);
      assertEquals(report.readyForLive, false);
      assertEquals(report.dispatchAuthorized, false);
      assertEquals(report.liveControllerAvailable, false);
      assertEquals(report.preparedCases, 12);
      assertEquals(report.proposedCalls, 18);
      assertEquals(
        report.order.slice(0, 6).map((a) => a.profile),
        Array(6).fill("openai_photo_sol_primary_low_v1"),
      );
      for (let i = 6; i < 18; i += 2) {
        const a = report.order[i], b = report.order[i + 1];
        assertEquals(a.caseId, b.caseId);
        for (
          const k of ["inputDigest", "referenceDigest", "factsDigest"] as const
        ) assertEquals(a[k], b[k]);
        assert(a.profile !== b.profile && a.requestDigest !== b.requestDigest);
      }
      assertEquals(report.order.slice(6, 10).map((a) => a.profile), [
        "openai_photo_sol_primary_low_v1",
        "openai_photo_sol_low_v1",
        "openai_photo_sol_low_v1",
        "openai_photo_sol_primary_low_v1",
      ]);
      for (
        const name of [
          "approval.json",
          "photo-model-plan.json",
          "photo-model-pricing.json",
          "spec.json",
          "runs",
        ]
      ) {
        assertEquals(await exists(join(f.target, name)), false);
      }
      for (
        const forbidden of [
          "data:image",
          "Invented",
          "acceptableTaxa",
          "Authorization",
          "budgetUsd",
          "attribution",
          "https:",
        ]
      ) {
        assert(!JSON.stringify(report).includes(forbidden));
      }
      assertEquals((await Deno.stat(f.target)).mode! & 0o077, 0);
      for (const c of f.corpus.cases) {
        const asset = c.input.assets[0];
        assertEquals(
          await Deno.readFile(join(f.target, asset.path)),
          await Deno.readFile(join(f.source, asset.path)),
        );
        assertEquals(
          (await Deno.stat(join(f.target, asset.path))).mode! & 0o077,
          0,
        );
      }
      assertEquals(
        await readJson(join(f.target, "primary-preparation.json")),
        report,
      );
      const after = await treeDigests(f.target);
      await assertRejects(() =>
        prepareSolPhotoPrimaryPacket(f.source, f.target)
      );
      assertEquals(await treeDigests(f.target), after);
    } finally {
      await Deno.remove(parent, { recursive: true });
    }
  });

  Deno.test("primary preparation rejects stale reviews, facts, media, wrong roles, copied authority and unsafe paths before a receipt", async () => {
    for (
      const kind of [
        "review",
        "facts",
        "media",
        "role",
        "authority",
        "nested",
        "symlink",
        "public-parent",
        "git",
      ] as const
    ) {
      const parent = await Deno.makeTempDir({
        dir: scratch,
        prefix: "primary-bad-",
      });
      try {
        const f = await fixture(parent);
        let { source, target } = f;
        if (kind === "review") f.review.cases[0].inputDigest = "0".repeat(64);
        if (kind === "role") f.review.cases[0].roles = ["domestic_cat"];
        if (kind === "facts") f.facts.cards[0].observed = ["Changed fact."];
        if (kind === "review" || kind === "role") {
          f.plan.referenceReviewDigest = await fingerprintJson(f.review);
        }
        await f.save();
        if (kind === "authority") {
          await atomicJson(join(source, "primary-preparation-plan.json"), {
            ...f.plan,
            inputApproval: true,
          });
        }
        if (kind === "media") {
          await Deno.writeFile(
            join(source, f.corpus.cases[0].input.assets[0].path),
            new Uint8Array([0]),
          );
        }
        if (kind === "nested") target = join(source, "nested");
        if (kind === "git") await Deno.mkdir(join(parent, ".git"));
        if (kind === "public-parent") await Deno.chmod(parent, 0o755);
        if (kind === "symlink") {
          const linked = join(parent, "linked");
          assertEquals(
            (await new Deno.Command("ln", {
              args: ["-s", source, linked],
              stdout: "null",
              stderr: "null",
            }).output()).code,
            0,
          );
          source = linked;
        }
        await assertRejects(() => prepareSolPhotoPrimaryPacket(source, target));
        assertEquals(
          await exists(join(target, "primary-preparation.json")),
          false,
        );
        assertEquals(await exists(target), false);
      } finally {
        await Deno.remove(parent, { recursive: true });
      }
    }
  });

  Deno.test("primary missing coverage remains explicit and historical preparation or approval shapes cannot be relabeled", async () => {
    const parent = await Deno.makeTempDir({
      dir: scratch,
      prefix: "primary-gaps-",
    });
    try {
      const f = await fixture(parent);
      f.review.cases[0].roles = [];
      f.plan.referenceReviewDigest = await fingerprintJson(f.review);
      await f.save();
      const report = await prepareSolPhotoPrimaryPacket(f.source, f.target);
      assertEquals(report.coverage.missing, ["domestic_dog"]);
      assertEquals(report.coverage.referenceCoverage, "missing_cases");
      assert(report.remainingWork.includes("fill_missing_reference_cases"));
      assertThrows(() =>
        parsePrimaryPreparationPlan({
          ...f.plan,
          version: "sol_photo_rank_plan_v1",
        })
      );
      assertThrows(() =>
        parsePrimaryPreparationPlan({ ...f.plan, budgetUsd: 110 })
      );
      assertThrows(() =>
        parsePrimaryPreparationPlan({
          ...f.plan,
          challengeCaseIds: f.plan.screenCaseIds,
        })
      );
      assertThrows(() =>
        parsePrimaryReferenceReview({
          ...f.review,
          version: "sol_photo_rank_reference_review_v1",
        })
      );
      assertThrows(() =>
        parsePrimaryReferenceReview({
          ...f.review,
          independentTruthVerified: true,
        })
      );
    } finally {
      await Deno.remove(parent, { recursive: true });
    }
  });

  Deno.test("primary preparation requires a separate reviewed species comparator for lookalike coverage", async () => {
    for (
      const kind of [
        "missing",
        "accepted",
        "unmapped",
        "rank",
        "duplicate",
        "without-role",
      ] as const
    ) {
      const parent = await Deno.makeTempDir({
        dir: scratch,
        prefix: "primary-comparator-",
      });
      try {
        const f = await fixture(parent);
        const c = f.review.cases[6];
        if (kind === "missing") c.confusableTaxa = [];
        if (kind === "accepted") {
          c.confusableTaxa = [
            ...f.corpus.cases[6].provisionalReference!.acceptableTaxa,
          ];
        }
        if (kind === "unmapped") {
          c.confusableTaxa = [{ id: "synthetic:missing", rank: "species" }];
        }
        if (kind === "rank") c.confusableTaxa = [f.taxonomy.taxa[1].taxon];
        if (kind === "duplicate") c.confusableTaxa.push(c.confusableTaxa[0]);
        if (kind === "without-role") c.roles = [];
        f.plan.referenceReviewDigest = await fingerprintJson(f.review);
        await f.save();
        await assertRejects(() =>
          prepareSolPhotoPrimaryPacket(f.source, f.target)
        );
        assertEquals(await exists(f.target), false);
      } finally {
        await Deno.remove(parent, { recursive: true });
      }
    }
  });

  Deno.test("primary preparation CLI refuses live flags and ambient network permission with fixed errors", async () => {
    const parent = await Deno.makeTempDir({
      dir: scratch,
      prefix: "primary-cli-",
    });
    try {
      const { source, target } = await fixture(parent);
      const run = (args: string[], net = "--deny-net") =>
        new Deno.Command("deno", {
          args: [
            "run",
            "--frozen",
            "--no-prompt",
            net,
            "--deny-env",
            "--config",
            "services/supabase/functions/deno.json",
            `--allow-read=${parent}`,
            `--allow-write=${parent}`,
            "services/supabase/scripts/prepare_sol_primary_candidate.ts",
            ...args,
          ],
          stdout: "piped",
          stderr: "piped",
        }).output();
      for (
        const result of [
          await run(["--live", source, target]),
          await run([source, target], "--allow-net"),
        ]
      ) {
        assertEquals(result.code, 1);
        assertEquals(
          new TextDecoder().decode(result.stderr).trim(),
          "sol_primary_preparation_failed",
        );
      }
      assertEquals(await exists(target), false);
      const result = await run([source, target]);
      assertEquals(result.code, 0);
      assertEquals(
        JSON.parse(new TextDecoder().decode(result.stdout)).dispatchAuthorized,
        false,
      );
    } finally {
      await Deno.remove(parent, { recursive: true });
    }
  });
}
