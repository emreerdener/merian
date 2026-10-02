import { preparePhotoFeatures } from "./identification_evaluation/photoFeaturePreparation.ts";

if (import.meta.main) {
  try {
    if (Deno.args.length !== 4) throw new Error("usage");
    const result = await preparePhotoFeatures(
      Deno.args[0],
      Deno.args[1],
      Deno.args[2],
      Deno.args[3],
    );
    console.log(
      JSON.stringify({
        version: result.version,
        proposedCalls: result.proposedCalls,
        paidServiceApproved: false,
        dispatchSupported: false,
      }),
    );
  } catch {
    console.error("photo_feature_preparation_failed");
    Deno.exit(1);
  }
}
