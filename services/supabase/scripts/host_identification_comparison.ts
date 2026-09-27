/** Manual Actions wrapper. Errors are fixed codes; provider execution stays in the existing CLI. */
import { fileURLToPath } from "node:url";
import { isAbsolute, join, relative } from "node:path";
import { assertOfflinePermissions } from "./identification_evaluation/admission.ts";
import { fingerprintJson } from "./identification_evaluation/evidence.ts";
import {
  claimJson,
  exists,
  privateDirectory,
  readJson,
  sourceIdentity,
} from "./identification_evaluation/files.ts";
import { parseExploratoryCorpus } from "./identification_evaluation/exploratory.ts";
import {
  assertHostedRunComplete,
  checkHostedPacket,
  exportHostedBundle,
  HOSTED_RUNS,
  type HostedProvider,
  hostedPublicSummary,
  hostedReadiness,
  makeHostedClaim,
  parseHostedSpec,
  prepareHostedExperiment,
  PROVIDERS,
  stageHostedBundle,
} from "./identification_evaluation/hosted.ts";
import {
  downloadHostedBundle,
  HostedR2,
} from "./identification_evaluation/hostedStorage.ts";
import {
  fields,
  requireCondition as check,
} from "./identification_evaluation/validation.ts";

const repository = fileURLToPath(new URL("../../../", import.meta.url));
function providerArg(value: string): HostedProvider {
  check(PROVIDERS.some((p) => p === value));
  return value as HostedProvider;
}
function storage() {
  return new HostedR2(
    Deno.env.get("R2_ACCOUNT_ID") ?? "",
    Deno.env.get("R2_ACCESS_KEY_ID") ?? "",
    Deno.env.get("R2_SECRET_ACCESS_KEY") ?? "",
  );
}
function githubIdentity() {
  check(
    Deno.env.get("GITHUB_ACTIONS") === "true" &&
      Deno.env.get("GITHUB_REPOSITORY") === "emreerdener/merian" &&
      Deno.env.get("GITHUB_REF") === "refs/heads/main" &&
      Deno.env.get("GITHUB_EVENT_NAME") === "workflow_dispatch",
  );
  return {
    sha: Deno.env.get("GITHUB_SHA"),
    runId: Deno.env.get("GITHUB_RUN_ID") ?? "",
    attempt: Deno.env.get("GITHUB_RUN_ATTEMPT") ?? "",
  };
}
export async function main(args = Deno.args) {
  const [mode, root, extra, output] = args;
  const counts: Record<string, number> = {
    export: 4,
    fetch: 3,
    bind: 3,
    prepare: 2,
    check: 2,
    claim: 3,
    "assert-complete": 3,
    report: 3,
    publish: 3,
  };
  check(
    Object.hasOwn(counts, mode) && args.length === counts[mode] &&
      isAbsolute(root) && !/[,\r\n]/.test(root),
  );
  const rel = relative(repository, root);
  check(rel.startsWith("../") && relative(root, repository).startsWith("../"));
  if (mode === "export") {
    await privateDirectory(root);
    const source = await sourceIdentity(repository);
    check(
      await fingerprintJson(parseHostedSpec(await readJson(extra)).source) ===
        await fingerprintJson(source),
    );
    const info = await exportHostedBundle(root, extra, output);
    console.log(JSON.stringify(info));
    return;
  }
  if (mode === "fetch") {
    const source = await sourceIdentity(repository);
    check(source.dirty === false);
    await stageHostedBundle(
      root,
      await downloadHostedBundle(extra),
      extra,
      source,
    );
    console.log("hosted_comparison_bundle_staged");
    return;
  }
  await privateDirectory(root);
  const spec = parseHostedSpec(await readJson(join(root, "hosted-spec.json")));
  if (mode === "bind") {
    // Provider key is available only in this network-denied step and its later live step.
    const provider = providerArg(extra), i = PROVIDERS.indexOf(provider);
    const key = Deno.env.get(
      provider === "gemini"
        ? "GEMINI_PAID_API_KEY"
        : "OPENAI_EVALUATION_API_KEY",
    )?.trim() ?? "";
    const corpus = parseExploratoryCorpus(
      await readJson(join(root, "corpus.json")),
    );
    await claimJson(
      join(root, "approvals", `${HOSTED_RUNS[i]}.json`),
      await hostedReadiness(spec, corpus, provider, key),
    );
  } else if (mode === "check") {
    await checkHostedPacket(root, await sourceIdentity(repository));
  } else if (mode === "prepare") {
    await prepareHostedExperiment(root, await sourceIdentity(repository));
  } else if (mode === "claim") {
    const context = githubIdentity();
    check(context.sha === spec.source.commit);
    check(
      /^(?:[0-9]+)(?:\.[0-9]{1,2})?$/.test(extra) &&
        Number(extra) >= spec.budgetUsd && Number(extra) <= 100,
    );
    const now = Date.now();
    check(
      now >= Date.parse(spec.window.startsAt) &&
        now < Date.parse(spec.window.expiresAt),
    );
    const binding = fields(await readJson(join(root, "bundle-binding.json")), [
      "digest",
    ]);
    check(
      typeof binding.digest === "string" &&
        await exists(join(root, "experiment.json")) &&
        !await exists(join(root, "hosted-claim.json")),
    );
    const claim = makeHostedClaim(
      spec,
      binding.digest,
      context.runId,
      context.attempt,
    );
    await claimJson(join(root, "hosted-claim-attempt.json"), claim);
    await storage().claim(claim);
    // A failed local flush after remote creation still blocks the next launch remotely.
    await claimJson(join(root, "hosted-claim.json"), claim);
  } else if (mode === "assert-complete") {
    await assertOfflinePermissions();
    await assertHostedRunComplete(root, providerArg(extra));
  } else if (mode === "report") {
    await hostedPublicSummary(root, extra);
  } else if (mode === "publish") {
    const context = githubIdentity();
    const binding = fields(await readJson(join(root, "bundle-binding.json")), [
      "digest",
    ]);
    check(
      typeof binding.digest === "string" && context.sha === spec.source.commit,
    );
    const claim = makeHostedClaim(
      spec,
      binding.digest,
      context.runId,
      context.attempt,
    );
    check(
      await fingerprintJson(await readJson(join(root, "hosted-claim.json"))) ===
        await fingerprintJson(claim),
    );
    const summary = await readJson(extra) as Record<string, unknown>;
    check(
      summary.version === "hosted_identification_summary_v1" &&
        summary.experimentId === spec.experimentId &&
        summary.bundleDigest === binding.digest &&
        summary.candidateSha === spec.source.commit,
    );
    await storage().publish(claim, summary);
  }
  console.log("hosted_comparison_step_complete");
}
if (import.meta.main) {
  try {
    await main();
  } catch {
    console.error("hosted_comparison_stopped");
    Deno.exitCode = 1;
  }
}
