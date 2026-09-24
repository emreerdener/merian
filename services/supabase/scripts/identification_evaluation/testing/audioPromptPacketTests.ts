/** Invented packet fixtures. No recorded audio, real review or live permission. */
import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { encodeWav16 } from "../../../functions/audio-spec/wav.ts";
import { prepareAudioUncertaintyComparison } from "../../prepare_audio_uncertainty_comparison.ts";
import { fingerprintBytes } from "../evidence.ts";
import { exists } from "../files.ts";
import { readFrozenAudioPacket } from "../frozenAudioPacket.ts";

export function registerAudioPromptPacketTests(scratch: string) {
  const now = Date.parse("2026-09-24T17:00:00Z");
  async function setupPacket() {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "audio-prompt-",
    });
    await Deno.chmod(root, 0o700);
    await Deno.mkdir(join(root, "assets"), { mode: 0o700 });
    await Deno.mkdir(join(root, "records"), { mode: 0o700 });
    const bytes = encodeWav16(
      Float32Array.from({ length: 44100 }, (_, i) => 0.5 * Math.sin(i * 0.2)),
      44100,
    );
    const reference = {
      subject: "non_biological",
      resolution: "unresolved",
      supportedRank: null,
      acceptableTaxa: [],
    };
    const selected = [{
      caseId: "c0030",
      groupId: "g0030",
      assetPath: "assets/a00300.wav",
      sourceWavSha256: await fingerprintBytes(bytes),
      byteLength: bytes.length,
      provisionalReference: reference,
    }];
    const corpus = {
      version: "identification_exploratory_corpus_v1",
      id: "fixture-audio-prompt-v1",
      kind: "exploratory",
      evidenceOrigin: "real",
      taxonomyVersion: "fixture-v1",
      preparationVersion: "fixture-v1",
      splitSeed: 42,
      eligibility: {
        recordRef: "fixture-review",
        reviewerRef: "r0001",
        reviewerKind: "owner",
        retainUntil: "2026-10-24",
      },
      cases: [{
        input: {
          caseId: "c0030",
          groupId: "g0030",
          split: "development",
          inputGroup: "audio",
          observationTexts: [] as string[],
          context: { deviceRegion: null, currentMonth: null },
          clips: [],
          assets: [{
            id: "a00300",
            path: selected[0].assetPath,
            sha256: selected[0].sourceWavSha256,
            byteLength: bytes.length,
            kind: "audio",
            mimeType: "audio/wav",
            sourceIndex: 0,
          }],
        },
        provisionalReference: reference,
        curation: {
          kind: "eligibility_reviewed",
          source: "licensed",
          sourceRecordRef: "fixture-source",
          referenceRecordRef: "fixture-reference",
          permission: "gemini_evaluation",
          rightsApproved: true,
          personalDataExcluded: true,
          nearDuplicatesReviewed: true,
        },
      }],
    };
    const write = (path: string, value: unknown) =>
      Deno.writeTextFile(join(root, path), JSON.stringify(value), {
        mode: 0o600,
      });
    await Deno.writeFile(join(root, selected[0].assetPath), bytes, {
      mode: 0o600,
    });
    await write("taxonomy.json", {
      version: "evaluation_taxonomy_v1",
      taxonomyVersion: "fixture-v1",
      taxa: [{
        taxon: { id: "fixture-species", rank: "species" },
        names: ["Invented test label"],
      }],
    });
    for (const record of ["review", "source", "reference"]) {
      await write("records/fixture-" + record + ".json", { fixtureOnly: true });
    }
    const freeze = async () => {
      await write("corpus.json", corpus);
      const files = await Promise.all([
        "corpus.json",
        "taxonomy.json",
        selected[0].assetPath,
        "records/fixture-review.json",
        "records/fixture-source.json",
        "records/fixture-reference.json",
      ].map(async (path) => {
        const b = await Deno.readFile(join(root, path));
        return {
          path,
          sha256: await fingerprintBytes(b),
          byteLength: b.length,
        };
      }));
      await write("completed-freeze.json", {
        createdAt: "2026-09-24T16:00:00Z",
        retentionThrough: "2026-10-24",
        files,
      });
      return {
        completedFreezeSha256: await fingerprintBytes(
          await Deno.readFile(join(root, "completed-freeze.json")),
        ),
        sourceCorpusSha256: files.find((f) => f.path === "corpus.json")!.sha256,
        sourceTaxonomySha256:
          files.find((f) => f.path === "taxonomy.json")!.sha256,
      };
    };
    return { root, selected, corpus, freeze, binding: await freeze() };
  }

  Deno.test("prompt packet reader binds frozen review, source, reference and retention without retaining media", async () => {
    const { root, selected, binding } = await setupPacket();
    try {
      const packet = await readFrozenAudioPacket(root, binding, selected, now);
      assertEquals(packet.cases.length, 1);
      assertEquals(
        packet.cases[0].sourceWavSha256,
        selected[0].sourceWavSha256,
      );
      assertEquals(packet.source.retainUntil, "2026-10-24");
      assertEquals(packet.source.permission, "gemini_evaluation");
      const serialized = JSON.stringify(packet);
      assert(
        !serialized.includes("inlineData") && !serialized.includes(root) &&
          !serialized.includes("Invented test label") &&
          !serialized.includes("fixtureOnly"),
      );
      await assertRejects(() =>
        readFrozenAudioPacket(root, binding, selected, Date.parse("2026-10-24"))
      );
      await assertRejects(() =>
        readFrozenAudioPacket(root, binding, [{
          ...selected[0],
          groupId: "g0031",
        }], now)
      );
      await assertRejects(() =>
        readFrozenAudioPacket(root, binding, [{
          ...selected[0],
          provisionalReference: {
            ...selected[0].provisionalReference,
            subject: "human",
          },
        }], now)
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });

  Deno.test("prompt packet reader rejects tampering, aliases, shared files and unreviewed inputs", async () => {
    for (
      const fault of [
        "asset",
        "corpus",
        "taxonomy",
        "record",
        "freeze",
        "symlink",
        "hardlink",
        "public-file",
        "public-root",
        "unreviewed",
        "automated-review",
        "extra-text",
      ]
    ) {
      const fixture = await setupPacket();
      const { root, selected, corpus } = fixture;
      let binding = fixture.binding;
      try {
        const asset = join(root, selected[0].assetPath);
        if (
          ["asset", "corpus", "taxonomy", "record", "freeze"].includes(fault)
        ) {
          const path = fault === "asset" ? asset : join(
            root,
            fault === "record"
              ? "records/fixture-review.json"
              : fault === "freeze"
              ? "completed-freeze.json"
              : fault + ".json",
          );
          await Deno.writeTextFile(path, "{}");
        } else if (fault === "symlink") {
          await Deno.rename(asset, asset + ".original");
          assert(
            (await new Deno.Command("ln", {
              args: ["-s", asset + ".original", asset],
              stderr: "null",
            }).output()).success,
          );
        } else if (fault === "hardlink") {
          await Deno.link(asset, asset + ".alias");
        } else if (fault === "public-file") await Deno.chmod(asset, 0o644);
        else if (fault === "public-root") await Deno.chmod(root, 0o755);
        else {
          if (fault === "unreviewed") {
            corpus.cases[0].curation.personalDataExcluded = false;
          }
          if (fault === "automated-review") {
            corpus.eligibility.reviewerKind = "automated";
          }
          if (fault === "extra-text") {
            corpus.cases[0].input.observationTexts = [
              "source-label",
            ] as never[];
          }
          binding = await fixture.freeze();
        }
        await assertRejects(() =>
          readFrozenAudioPacket(root, binding, selected, now)
        );
      } finally {
        await Deno.remove(root, { recursive: true });
      }
    }
  });

  Deno.test("prompt preparation refuses reused destinations and non-reviewed fixture packets before output", async () => {
    const { root } = await setupPacket();
    try {
      const sentinel = join(root, "sentinel");
      await Deno.writeTextFile(sentinel, "preserve");
      await assertRejects(() =>
        prepareAudioUncertaintyComparison(root, root, root)
      );
      assertEquals(await Deno.readTextFile(sentinel), "preserve");
      const output = join(root, "output");
      await assertRejects(() =>
        prepareAudioUncertaintyComparison(root, root, output)
      );
      assertEquals(await exists(output), false);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });

  Deno.test("prompt CLI rejects broadened permissions with content-free errors", async () => {
    const repository = fileURLToPath(
      new URL("../../../../..", import.meta.url),
    );
    for (const permission of ["--allow-env", "--allow-net"]) {
      const result = await new Deno.Command("deno", {
        cwd: repository,
        args: [
          "run",
          "--frozen",
          "--no-prompt",
          permission,
          "--config",
          "services/supabase/functions/deno.json",
          "services/supabase/scripts/prepare_audio_uncertainty_comparison.ts",
          "private-source-a",
          "private-source-b",
          "private-output",
        ],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assertEquals(result.code, 1);
      assertEquals(new TextDecoder().decode(result.stdout), "");
      assertEquals(
        new TextDecoder().decode(result.stderr).trim(),
        "audio_uncertainty_preparation_failed",
      );
    }
  });
}
