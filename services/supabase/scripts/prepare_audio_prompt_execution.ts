/** Freeze the actual reviewed clean build and retained assets; never dispatch. */
import { dirname, join, resolve } from "node:path";
import { assertOfflinePermissions } from "./identification_evaluation/admission.ts";
import {
  audioUncertaintyDesign,
  prepareAudioPromptPair,
} from "./identification_evaluation/audioPromptComparison.ts";
import {
  promptExecutionManifest,
  promptExecutionRepository,
  verifyPromptExecutionAssets,
} from "./identification_evaluation/audioPromptExecution.ts";
import {
  fingerprintBytes,
  fingerprintJson,
} from "./identification_evaluation/evidence.ts";
import {
  claimJson,
  containedPath,
  exists,
  privateDirectory,
  readBytes,
  readJson,
  sourceIdentity,
  syncDirectory,
} from "./identification_evaluation/files.ts";
import { readFrozenAudioPacket } from "./identification_evaluation/frozenAudioPacket.ts";
import { requireCondition as check } from "./identification_evaluation/validation.ts";
import {
  renderAudioPromptComparisonPlan,
  renderSwiftAudioPromptComparisonPlan,
} from "./generate_audio_prompt_comparison_plan.ts";
import { identificationBundleDigest } from "./generate_identification_deployment_identity.ts";

export async function prepareAudioPromptExecution(
  v2Source: string,
  visibleSource: string,
  reviewPath: string,
  destination: string,
) {
  await assertOfflinePermissions();
  const output = resolve(destination), repository = promptExecutionRepository;
  check(
    !await exists(output) &&
      await Deno.realPath(dirname(output)) === dirname(output),
  );
  const now = Date.now(), source = await sourceIdentity(repository);
  const manifest = promptExecutionManifest(
    await readJson(reviewPath, 16_384),
    source,
    now,
  );
  check(
    await identificationBundleDigest() === manifest.review.backendBundleSha256,
  );
  for (
    const [path, rendered] of [
      [
        "services/supabase/functions/identify-multimodal/comparison/promptPlan.ts",
        await renderAudioPromptComparisonPlan(),
      ],
      [
        "apps/ios/Merian/Core/Network/Inference/DebugAudioPromptComparisonPlan.generated.swift",
        await renderSwiftAudioPromptComparisonPlan(),
      ],
    ]
  ) {
    check(
      await Deno.readTextFile(await containedPath(repository, path)) ===
        rendered,
    );
  }
  const design = await audioUncertaintyDesign();
  const assets: { caseId: string; bytes: Uint8Array }[] = [];
  for (
    const [key, sourceRoot] of [["v2", v2Source], [
      "visible",
      visibleSource,
    ]] as const
  ) {
    const selected = design.cases.filter((c) => c.sourcePacketKey === key);
    const packet = await readFrozenAudioPacket(
      sourceRoot,
      design.sources[key],
      selected,
      now,
    );
    check(
      Date.parse(packet.source.retainUntil) >=
        Date.parse(manifest.review.windows[2].expiresAt),
    );
    for (const c of packet.cases) {
      const bytes = await readBytes(
        await containedPath(resolve(sourceRoot), c.assetPath),
        44 + 44100 * 15 * 2,
      );
      const pair = await prepareAudioPromptPair(bytes);
      for (
        const assignment of manifest.assignments.filter((a) =>
          a.caseId === c.caseId
        )
      ) {
        const arm = pair.arms.find((a) => a.arm === assignment.arm)!;
        check(
          pair.sourceWavSha256 === assignment.sourceWavSha256 &&
            pair.sourceByteLength === assignment.sourceByteLength &&
            pair.processedWavSha256 === assignment.processedWavSha256,
        );
        check(
          arm.providerRequestSha256 === assignment.providerRequestSha256 &&
            arm.policySha256 === assignment.policySha256 &&
            arm.confidenceSha256 === assignment.confidenceSha256,
        );
      }
      assets.push({ caseId: c.caseId, bytes });
    }
  }
  check(
    assets.length === 6 &&
      await fingerprintJson(await sourceIdentity(repository)) ===
        await fingerprintJson(source),
  );
  await Deno.mkdir(output, { mode: 0o700 });
  await syncDirectory(dirname(output));
  for (const name of ["assets", "slots", "controls"]) {
    await privateDirectory(join(output, name));
  }
  for (const asset of assets) {
    using file = await Deno.open(
      join(output, "assets", asset.caseId + ".wav"),
      { createNew: true, write: true, mode: 0o600 },
    );
    let offset = 0;
    while (offset < asset.bytes.length) {
      const count = await file.write(asset.bytes.subarray(offset));
      check(count > 0);
      offset += count;
    }
    await file.sync();
  }
  await syncDirectory(join(output, "assets"));
  await verifyPromptExecutionAssets(output);
  await claimJson(join(output, "run.json"), manifest);
  await claimJson(join(output, "freeze.json"), {
    version: "audio_prompt_execution_freeze_v1",
    manifestSha256: await fingerprintJson(manifest),
    manifestFileSha256: await fingerprintBytes(
      await readBytes(join(output, "run.json"), 262_144),
    ),
  });
  return manifest;
}
if (import.meta.main) {
  try {
    check(Deno.args.length === 4);
    await prepareAudioPromptExecution(
      ...Deno.args.map((arg) => resolve(arg)) as [
        string,
        string,
        string,
        string,
      ],
    );
    console.log(
      "Froze six assets and 36 first-attempt slots offline; zero submissions.",
    );
  } catch {
    console.error("audio_prompt_execution_preparation_failed");
    Deno.exit(1);
  }
}
