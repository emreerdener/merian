/** Explicit entry point only; no credential reads during check/report. */
import { join } from "node:path";
import { loadFeatureExecution } from "./identification_evaluation/photoFeatureExecution.ts";
import { privateDirectory } from "./identification_evaluation/files.ts";
import {
  collectPhotoFeatures,
  featureRunReport,
  freezeFeatureRun,
} from "./identification_evaluation/photoFeatureRun.ts";
import { liveFeatureProvider } from "./identification_evaluation/photoFeatureProvider.ts";
import { localFeatureReviewer } from "./identification_evaluation/photoFeatureView.ts";
import { requireCondition as check } from "./identification_evaluation/validation.ts";
if (import.meta.main) {
  try {
    const [mode, packet, plan, ...extra] = Deno.args;
    check(
      extra.length === 0 && ["--check", "--report", "--live"].includes(mode) &&
        packet && plan,
    );
    const input = await loadFeatureExecution(packet, plan);
    const root = await privateDirectory(join(packet, "feature-run"));
    if (mode === "--check") {
      const study = await freezeFeatureRun(root, input);
      console.log(
        JSON.stringify({
          version: "photo_feature_preflight_v1",
          assignments: 36,
          runDigest: study.digest,
          providerCalls: 0,
        }),
      );
    } else if (mode === "--report") {
      console.log(
        JSON.stringify(
          await featureRunReport(await freezeFeatureRun(root, input)),
        ),
      );
    } else {
      check(input.plan.mode === "live" && input.plan.paidServiceApproved);
      const reviewers = input.plan.reviewerAssignments.map((r) => {
        check(r.method === "local_interactive");
        return localFeatureReviewer(r.id, r.method);
      });
      const report = await collectPhotoFeatures(
        root,
        input,
        liveFeatureProvider(),
        reviewers,
      );
      console.log(JSON.stringify(report));
      if (!report.complete) Deno.exitCode = 2;
    }
  } catch {
    console.error("photo_feature_execution_stopped");
    Deno.exitCode = 1;
  }
}
