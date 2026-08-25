import {
  GitHubReleaseEvidenceVerifier,
  parseAndValidateReleaseEvidenceStatement,
} from "./github_release_evidence.ts";
import { releaseCriterionFromManifest } from "./verify_production_release_holds.ts";

const SHA_PATTERN = /^[0-9a-f]{40}$/;
const IDENTIFIER_PATTERN = /^[a-z][a-z0-9_]{2,79}$/;
const MAX_INPUT_LENGTH = 512 * 1024;

function argumentValue(name: string): string | undefined {
  const index = Deno.args.indexOf(name);
  return index >= 0 ? Deno.args[index + 1] : undefined;
}

function decodeBase64Text(value: string): string {
  if (
    value.length === 0 || value.length > MAX_INPUT_LENGTH ||
    !/^[A-Za-z0-9+/]*={0,2}$/.test(value) || value.length % 4 !== 0
  ) {
    throw new Error("release evidence input is not bounded canonical base64");
  }
  return new TextDecoder().decode(
    Uint8Array.from(atob(value), (character) => character.charCodeAt(0)),
  );
}

if (import.meta.main) {
  const candidateSha = argumentValue("--candidate-sha");
  const holdId = argumentValue("--hold-id");
  const criterionId = argumentValue("--criterion-id");
  const manifestPath = argumentValue("--manifest");
  const outputPath = argumentValue("--output");
  const encodedStatement = Deno.env.get("MERIAN_RELEASE_EVIDENCE_BASE64");
  const githubToken = Deno.env.get("GITHUB_TOKEN");
  const repository = Deno.env.get("GITHUB_REPOSITORY");
  if (!candidateSha || !SHA_PATTERN.test(candidateSha)) {
    throw new Error("--candidate-sha must be a lowercase 40-hex commit");
  }
  if (
    !holdId || !criterionId || !IDENTIFIER_PATTERN.test(holdId) ||
    !IDENTIFIER_PATTERN.test(criterionId)
  ) {
    throw new Error("--hold-id and --criterion-id must be stable identifiers");
  }
  if (!manifestPath || !outputPath || !encodedStatement) {
    throw new Error("--manifest, --output, and evidence input are required");
  }
  const criterion = releaseCriterionFromManifest(
    await Deno.readTextFile(manifestPath),
    holdId,
    criterionId,
  );
  const github = new GitHubReleaseEvidenceVerifier({
    token: githubToken ?? "",
    repository: repository ?? "",
  });
  const statement = await parseAndValidateReleaseEvidenceStatement(
    decodeBase64Text(encodedStatement),
    {
      holdId,
      criterionId,
      evidenceType: criterion.evidence_type,
      requiredWorkflows: criterion.required_workflows,
      candidateSha,
    },
    (run, sha) => github.verifySupportingWorkflowRun(run, sha),
  );
  await Deno.writeTextFile(
    outputPath,
    `${JSON.stringify(statement, null, 2)}\n`,
  );
  console.log(`Prepared redacted evidence for ${holdId}:${criterionId}.`);
}
