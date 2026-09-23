import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import {
  AUDIO_COMPARISON_CONTEXT,
  prepareAudioComparisonPair,
} from "./identification_evaluation/audioComparison.ts";
import {
  fingerprintBytes,
  fingerprintJson,
} from "./identification_evaluation/evidence.ts";
import {
  claimJson,
  containedPath,
  privateDirectory,
  readBytes,
  sourceIdentity,
} from "./identification_evaluation/files.ts";
import { requireCondition as check } from "./identification_evaluation/validation.ts";

const SOURCE_FREEZE =
  "415a055676d36ae0bf93aa8856a2b86d67188c97ea51f5c42e20400909489c8c";

/** Offline-only preparation; the normal evaluation RunSpec deliberately cannot
 * consume this artifact or dispatch its legacy arm. No credentials are read.
 */
export async function prepareAudioComparison(
  source: string,
  destination: string,
) {
  const freezeBytes = await readBytes(
    await containedPath(source, "freeze.json"),
    1024 * 1024,
  );
  check(await fingerprintBytes(freezeBytes) === SOURCE_FREEZE);
  const freeze = JSON.parse(new TextDecoder().decode(freezeBytes));
  const pairs = [];
  for (let number = 13; number <= 18; number++) {
    const digits = String(number).padStart(4, "0");
    const path = `assets/a${digits}0.wav`;
    const frozen = freeze.files.find((file: { path: string }) =>
      file.path === path
    );
    check(frozen);
    const bytes = await readBytes(
      await containedPath(source, path),
      44 + 44100 * 15 * 2,
    );
    check(
      bytes.length === frozen.byteLength &&
        await fingerprintBytes(bytes) === frozen.sha256,
    );
    pairs.push({
      caseId: `c${digits}`,
      ...await prepareAudioComparisonPair(bytes),
    });
  }
  const assignments = pairs.flatMap((pair, index) => {
    const ordered = index % 2 === 0 ? pair.arms : pair.arms.toReversed();
    return ordered.map((arm) => ({
      caseId: pair.caseId,
      arm: arm.arm,
      attempt: 1,
    }));
  });
  const repository = fileURLToPath(new URL("../../..", import.meta.url));
  const manifest = {
    version: "audio_preprocessing_comparison_preparation_v1",
    mode: "offline_only",
    liveDispatchEnabled: false,
    providerCalls: 0,
    purpose: "exploratory_preprocessing_signal",
    formalQualificationEligible: false,
    contextProfile: "audio-minimal-v1",
    context: AUDIO_COMPARISON_CONTEXT,
    sourceFreezeSha256: SOURCE_FREEZE,
    verifiedSourceAudioFiles: pairs.length,
    implementation: await sourceIdentity(repository),
    plannedAttempts: 12,
    selectiveRetriesAllowed: false,
    assignments,
    pairs,
  };
  // New artifact only. Historical packets and prior preparations are immutable.
  await Deno.mkdir(destination, { mode: 0o700 });
  const output = await privateDirectory(destination);
  await claimJson(`${output}/preparation.json`, manifest);
  await claimJson(`${output}/freeze.json`, {
    version: 1,
    preparationSha256: await fingerprintJson(manifest),
  });
  return manifest;
}

if (import.meta.main) {
  try {
    check(Deno.args.length === 2);
    await prepareAudioComparison(resolve(Deno.args[0]), resolve(Deno.args[1]));
    console.log("Prepared six frozen audio pairs offline; no provider calls.");
  } catch {
    console.error("audio_comparison_preparation_failed");
    Deno.exit(1);
  }
}
