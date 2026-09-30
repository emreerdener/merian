/** Two local paths only. No live mode, credentials or inherited run authority. */
import { prepareSolPhotoPrimaryPacket } from "./identification_evaluation/solPhotoPrimaryPreparation.ts";
import { requireCondition as check } from "./identification_evaluation/validation.ts";

if (import.meta.main) {
  try {
    check(Deno.args.length === 2 && Deno.args.every((a) => !a.startsWith("-")));
    const report = await prepareSolPhotoPrimaryPacket(
      ...Deno.args as [string, string],
    );
    console.log(JSON.stringify(report, null, 2));
  } catch {
    console.error("sol_primary_preparation_failed");
    Deno.exitCode = 1;
  }
}
