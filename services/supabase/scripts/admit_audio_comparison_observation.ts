import { admitAudioComparisonWindow } from "./identification_evaluation/audioComparisonWindow.ts";
import { fingerprintBytes } from "../functions/identify-multimodal/comparison/fingerprint.ts";

/** Offline only; no provider, account, environment, or runtime enablement. */
export async function admitAudioComparisonObservation(args: string[]) {
  const options = new Map<string, string>();
  for (let i = 0; i < args.length; i += 2) {
    if (
      !["--observation", "--expected", "--output"].includes(args[i]) ||
      !args[i + 1] || options.has(args[i])
    ) throw new Error("invalid_comparison_options");
    options.set(args[i], args[i + 1]);
  }
  if (options.size !== 3) throw new Error("comparison_paths_required");
  const read = async (path: string, limit: number) => {
    const info = await Deno.lstat(path);
    if (!info.isFile || info.size > limit) {
      throw new Error("invalid_comparison_file");
    }
    const bytes = await Deno.readFile(path);
    if (bytes.length > limit) throw new Error("invalid_comparison_file");
    return bytes;
  };
  const bytes = await read(options.get("--observation")!, 1_048_576);
  const expectedBytes = await read(options.get("--expected")!, 2_048);
  let admitted;
  try {
    const lines = new TextDecoder().decode(bytes).trimEnd().split("\n");
    if (lines.length > 103 || lines.some((line) => line.length > 16_384)) {
      throw new Error();
    }
    admitted = admitAudioComparisonWindow(
      lines.map((line) => JSON.parse(line)),
      JSON.parse(new TextDecoder().decode(expectedBytes)),
    );
  } catch {
    throw new Error("audio_comparison_observation_excluded");
  }
  const output = {
    ...admitted,
    observationSha256: await fingerprintBytes(bytes),
  };
  const file = await Deno.open(options.get("--output")!, {
    write: true,
    createNew: true,
    mode: 0o600,
  });
  try {
    const data = new TextEncoder().encode(
      JSON.stringify(output, null, 2) + "\n",
    );
    let offset = 0;
    while (offset < data.length) {
      offset += await file.write(data.subarray(offset));
    }
    await file.sync();
  } finally {
    file.close();
  }
  console.log(
    JSON.stringify({
      status: "admitted",
      slot: admitted.assignment.slot,
      automaticSubmissions: 0,
      accuracyScored: false,
    }),
  );
}

if (import.meta.main) await admitAudioComparisonObservation(Deno.args);
