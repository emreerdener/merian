import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import { fingerprintBytes, fingerprintJson } from "../evidence.ts";
import { atomicJson, exists, readJson } from "../files.ts";
import { prepareSolPhotoRankPacket } from "../solPhotoRankPreparation.ts";
import { SOL_RANK_PROFILE } from "../solPhotoRankCandidate.ts";
import { parseTaxonomy } from "../taxonomy.ts";
import { photoModelFixture } from "./photoModelPreparationTests.ts";

async function setup(parent: string) {
  const source = join(parent, "source");
  await Deno.mkdir(source, { mode: 0o700 });
  const fixture = await photoModelFixture(source, Date.now());
  const old = parseTaxonomy(await readJson(join(source, "taxonomy.json")));
  const taxonomy = {
    version: "evaluation_taxonomy_v2",
    taxonomyVersion: old.taxonomyVersion,
    catalogRef: "synthetic-before",
    reviewRef: "synthetic-before-review",
    taxa: old.taxa.map((t) => ({
      taxon: t.taxon,
      canonicalName: "names" in t ? t.names[0] : t.canonicalName,
      synonyms: "names" in t ? t.names.slice(1) : t.synonyms,
    })),
  };
  const first = taxonomy.taxa[0];
  taxonomy.taxa.push({
    ...first,
    taxon: { ...first.taxon, id: "synthetic:duplicate" },
  });
  fixture.plan.taxonomyDigest = await fingerprintJson(taxonomy);
  await atomicJson(join(source, "taxonomy.json"), taxonomy);
  await atomicJson(join(source, "photo-model-plan.json"), fixture.plan);
  // Whitelist copying must ignore other files, including prior execution authority.
  await atomicJson(join(source, "approval.json"), {
    sentinel: "Do not copy historical authority.",
  });
  const remap = {
    version: "photo_taxonomy_remap_v1",
    sourceCorpusDigest: fixture.plan.corpusDigest,
    sourceTaxonomyDigest: fixture.plan.taxonomyDigest,
    corpusId: "synthetic-sol-rank-cases",
    taxonomyVersion: "synthetic-sol-rank-taxonomy",
    catalogRef: "synthetic-after",
    reviewRef: "synthetic-after-review",
    merges: [{ from: "synthetic:duplicate", to: first.taxon.id }],
  };
  return { source, target: join(parent, "prepared"), remap, ...fixture };
}
async function treeDigests(root: string) {
  const result: Record<string, string> = {};
  const visit = async (path: string) => {
    for await (const entry of Deno.readDir(join(root, path))) {
      const child = join(path, entry.name);
      if (entry.isDirectory) await visit(child);
      else {result[child] = await fingerprintBytes(
          await Deno.readFile(join(root, child)),
        );}
    }
  };
  await visit("");
  return result;
}

export function registerSolPhotoRankPreparationTests(scratch: string) {
  Deno.test("Sol offline preparation preserves source bytes, copies only evidence and builds 18 paired assignments without approval", async () => {
    const parent = await Deno.makeTempDir({
      dir: scratch,
      prefix: "sol-rank-",
    });
    try {
      const { source, target, remap, corpus } = await setup(parent);
      const before = await treeDigests(source);
      const report = await prepareSolPhotoRankPacket(source, target, remap);
      assertEquals(await treeDigests(source), before);
      assertEquals(report.dispatchAuthorized, false);
      assertEquals(report.readyForLive, false);
      assertEquals(report.liveControllerAvailable, false);
      assertEquals(report.referenceReviewComplete, false);
      assertEquals(report.preparedCases, 12);
      assertEquals(report.proposedCalls, 18);
      assertEquals(report.repair.audit.catalogConsistency, "clear");
      assert(
        report.order.every((a) => a.model === "gpt-6-sol" && a.attempt === 1),
      );
      assert(
        report.order.slice(0, 6).every((a) => a.profile === SOL_RANK_PROFILE),
      );
      for (let i = 6; i < 18; i += 2) {
        const left = report.order[i], right = report.order[i + 1];
        assertEquals(left.caseId, right.caseId);
        assertEquals(left.inputDigest, right.inputDigest);
        assertEquals(left.referenceDigest, right.referenceDigest);
        assertEquals(left.factsDigest, right.factsDigest);
        assert(left.requestDigest !== right.requestDigest);
        assert(left.profile !== right.profile);
      }
      assertEquals(report.order.slice(6, 10).map((a) => a.profile), [
        SOL_RANK_PROFILE,
        "openai_photo_sol_low_v1",
        "openai_photo_sol_low_v1",
        SOL_RANK_PROFILE,
      ]);
      for (
        const name of [
          "approval.json",
          "photo-model-plan.json",
          "photo-model-pricing.json",
          "photo-model-run",
        ]
      ) {
        assertEquals(await exists(join(target, name)), false);
      }
      for (const c of corpus.cases) {
        for (const asset of c.input.assets) {
          assertEquals(
            await Deno.readFile(join(target, asset.path)),
            await Deno.readFile(join(source, asset.path)),
          );
          assertEquals(
            (await Deno.stat(join(target, asset.path))).mode! & 0o077,
            0,
          );
        }
      }
      assertEquals((await Deno.stat(target)).mode! & 0o077, 0);
      assertEquals(
        (await Deno.stat(join(target, "sol-rank-preparation.json"))).mode! &
          0o077,
        0,
      );
      assertEquals(
        await readJson(join(target, "sol-rank-preparation.json")),
        report,
      );
      const serialized = JSON.stringify(report);
      for (
        const forbidden of [
          "data:image",
          "Invented image",
          "acceptableTaxa",
          "Authorization",
          "budgetUsd",
        ]
      ) {
        assertEquals(serialized.includes(forbidden), false);
      }
      const destinationBefore = await treeDigests(target);
      await assertRejects(() =>
        prepareSolPhotoRankPacket(source, target, remap)
      );
      assertEquals(await treeDigests(target), destinationBefore);
    } finally {
      await Deno.remove(parent, { recursive: true });
    }
  });

  Deno.test("Sol offline preparation rejects changed media, stale facts, nested destinations and symlinks before any completion receipt", async () => {
    for (const kind of ["media", "facts", "nested", "symlink"] as const) {
      const parent = await Deno.makeTempDir({
        dir: scratch,
        prefix: "sol-invalid-",
      });
      try {
        const fixture = await setup(parent);
        let { source, target } = fixture;
        const { remap, corpus, facts } = fixture;
        if (kind === "media") {
          await Deno.writeFile(
            join(source, corpus.cases[0].input.assets[0].path),
            new Uint8Array([0]),
          );
        }
        if (kind === "facts") {
          facts.cards[0].observed = ["Changed evidence."];
          await atomicJson(join(source, "photo-model-facts.json"), facts);
        }
        if (kind === "nested") target = join(source, "nested");
        if (kind === "symlink") {
          const link = join(parent, "linked-source");
          const linked = await new Deno.Command("ln", {
            args: ["-s", source, link],
            stdout: "piped",
            stderr: "piped",
          }).output();
          assertEquals(linked.code, 0);
          source = link;
        }
        await assertRejects(() =>
          prepareSolPhotoRankPacket(source, target, remap)
        );
        assertEquals(
          await exists(join(target, "sol-rank-preparation.json")),
          false,
        );
        assertEquals(await exists(target), false);
      } finally {
        await Deno.remove(parent, { recursive: true });
      }
    }
  });

  Deno.test("Sol preparation CLI is offline, rejects live flags and reports fixed errors", async () => {
    const parent = await Deno.makeTempDir({ dir: scratch, prefix: "sol-cli-" });
    try {
      const { source, target, remap } = await setup(parent);
      const remapPath = join(parent, "remap.json");
      await atomicJson(remapPath, remap);
      const run = (args: string[]) =>
        new Deno.Command("deno", {
          args: [
            "run",
            "--frozen",
            "--no-prompt",
            "--deny-net",
            "--deny-env",
            "--config",
            "services/supabase/functions/deno.json",
            "--allow-read=" + parent,
            "--allow-write=" + parent,
            "services/supabase/scripts/prepare_sol_rank_candidate.ts",
            ...args,
          ],
          stdout: "piped",
          stderr: "piped",
        }).output();
      const invalid = await run(["--live", source, target, remapPath]);
      assertEquals(invalid.code, 1);
      assertEquals(
        new TextDecoder().decode(invalid.stderr).trim(),
        "sol_rank_preparation_failed",
      );
      assertEquals(await exists(target), false);
      const prepared = await run([source, target, remapPath]);
      assertEquals(prepared.code, 0);
      assertEquals(
        JSON.parse(new TextDecoder().decode(prepared.stdout))
          .dispatchAuthorized,
        false,
      );
    } finally {
      await Deno.remove(parent, { recursive: true });
    }
  });
}
