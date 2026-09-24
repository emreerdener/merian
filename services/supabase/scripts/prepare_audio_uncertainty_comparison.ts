/** Offline preparation only: no SDK initialization, credentials or dispatch. */
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { assertOfflinePermissions } from "./identification_evaluation/admission.ts";
import {
  AUDIO_PROMPT_CONTEXT,
  AUDIO_UNCERTAINTY_DESIGN_SHA256,
  audioPromptAssignments,
  audioUncertaintyDesign,
} from "./identification_evaluation/audioPromptComparison.ts";
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
  sourceIdentity,
  syncDirectory,
} from "./identification_evaluation/files.ts";
import { readFrozenAudioPacket } from "./identification_evaluation/frozenAudioPacket.ts";
import { requireCondition as check } from "./identification_evaluation/validation.ts";

export async function prepareAudioUncertaintyComparison(
  v2Source: string,
  visibleSource: string,
  destination: string,
) {
  await assertOfflinePermissions();
  const output = resolve(destination);
  // Refuse aliases and reused outputs before reading any source media.
  check(!await exists(output));
  check(await Deno.realPath(dirname(output)) === dirname(output));
  const design = await audioUncertaintyDesign();
  const repository = fileURLToPath(new URL("../../..", import.meta.url));
  for (const file of design.sourceReview.files) {
    check(
      await fingerprintBytes(
        await readBytes(
          await containedPath(repository, file.path),
          1024 * 1024,
        ),
      ) === file.sha256,
    );
  }
  const now = Date.now();
  const v2 = await readFrozenAudioPacket(
    v2Source,
    design.sources.v2,
    design.cases.filter((c) => c.sourcePacketKey === "v2"),
    now,
  );
  const visible = await readFrozenAudioPacket(
    visibleSource,
    design.sources.visible,
    design.cases.filter((c) => c.sourcePacketKey === "visible"),
    now,
  );
  const pairs = design.cases.map((c) => {
    const packet = c.sourcePacketKey === "v2" ? v2 : visible;
    const pair = packet.cases.find((p) => p.caseId === c.caseId);
    check(pair);
    return { sourcePacketKey: c.sourcePacketKey, ...pair };
  });
  const manifest = {
    version: "audio_uncertainty_comparison_preparation_v1" as const,
    mode: "offline_only" as const,
    executionReady: false,
    liveDispatchEnabled: false,
    providerCalls: 0,
    appSubmissions: 0,
    formalQualificationEligible: false,
    designSha256: AUDIO_UNCERTAINTY_DESIGN_SHA256,
    contextProfile: "audio-minimal-v1",
    context: AUDIO_PROMPT_CONTEXT,
    preparedAt: new Date(now).toISOString(),
    retentionThrough:
      [v2.source.retainUntil, visible.source.retainUntil].sort()[0],
    implementation: await sourceIdentity(repository),
    sources: { v2: v2.source, visible: visible.source },
    verifiedSourceAudioFiles: pairs.length,
    plannedSubmissions: 36,
    selectiveRetriesAllowed: false,
    assignments: await audioPromptAssignments(pairs),
    pairs,
    executionBindingsPending: design.executionBindingsPending,
  };
  check(Date.parse(manifest.retentionThrough) > Date.now());
  // New output only; an interrupted preparation cannot overwrite or resume it.
  await Deno.mkdir(output, { mode: 0o700 });
  await syncDirectory(dirname(output));
  await privateDirectory(output);
  await claimJson(output + "/preparation.json", manifest);
  const bytes = await readBytes(output + "/preparation.json", 1024 * 1024);
  await claimJson(output + "/freeze.json", {
    version: "audio_uncertainty_preparation_freeze_v1",
    preparationFileSha256: await fingerprintBytes(bytes),
    preparationSha256: await fingerprintJson(manifest),
  });
  return manifest;
}
export type AudioUncertaintyPreparation = Awaited<
  ReturnType<typeof prepareAudioUncertaintyComparison>
>;

if (import.meta.main) {
  try {
    check(Deno.args.length === 3);
    await prepareAudioUncertaintyComparison(
      resolve(Deno.args[0]),
      resolve(Deno.args[1]),
      resolve(Deno.args[2]),
    );
    console.log(
      "Prepared six prompt pairs and 36 slots offline; zero provider calls.",
    );
  } catch {
    console.error("audio_uncertainty_preparation_failed");
    Deno.exit(1);
  }
}
