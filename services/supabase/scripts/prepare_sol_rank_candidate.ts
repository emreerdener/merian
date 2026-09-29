/** Creates a fresh private offline packet. No live flag, key, or network access. */
import { readJson } from "./identification_evaluation/files.ts";
import { prepareSolPhotoRankPacket } from "./identification_evaluation/solPhotoRankPreparation.ts";
import { requireCondition as check } from "./identification_evaluation/validation.ts";

if (import.meta.main) {
  try {
    check(Deno.args.length === 3 && Deno.args.every((a) => !a.startsWith("-")));
    const [source, destination, remap] = Deno.args;
    const report = await prepareSolPhotoRankPacket(
      source,
      destination,
      await readJson(remap),
    );
    // The report contains identities/digests only; never request bodies or prose.
    console.log(JSON.stringify(report, null, 2));
  } catch {
    console.error("sol_rank_preparation_failed");
    Deno.exitCode = 1;
  }
}
