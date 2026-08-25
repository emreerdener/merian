import postgres, { type Sql } from "npm:postgres@3.4.7";
import { computeFieldChatBundleDigests } from "./generate_field_chat_deployment_identity.ts";
import {
  type FieldChatCutoverStatus,
  type RawCutoverRow,
  sha256Hex,
  validateFieldChatCutoverRows,
} from "./verify_field_chat_cutover.ts";

export const REQUIRED_FIELD_CHAT_BUNDLES = Object.freeze([
  "explore-post-chat",
  "insight-chat",
  "species-dictionary-chat",
]);

export function validateFieldChatActivationPlan(rawPlan: string): string[] {
  const selected = new Set(
    rawPlan.split(/\r?\n/).map((value) => value.trim()).filter(Boolean),
  );
  const missing = REQUIRED_FIELD_CHAT_BUNDLES.filter((name) =>
    !selected.has(name)
  );
  if (missing.length > 0) {
    throw new Error(
      `Field Chat activation plan is missing required bundles: ${
        missing.join(", ")
      }`,
    );
  }
  return [...selected].sort();
}

async function readStatus(
  sql: Sql,
  expectedMigrationSha256: string,
): Promise<FieldChatCutoverStatus> {
  const rows = await sql<RawCutoverRow[]>`
    SELECT
      status_row.migration_id,
      status_row.database_now::TEXT AS database_now,
      status_row.seeded_at::TEXT AS seeded_at,
      status_row.not_before_utc::TEXT AS not_before_utc,
      status_row.activated_at::TEXT AS activated_at,
      status_row.activated_candidate_sha,
      status_row.activated_migration_sha256,
      status_row.activated_explore_bundle_sha256,
      status_row.activated_insight_bundle_sha256,
      status_row.activated_species_dictionary_bundle_sha256,
      status_row.status
    FROM public.get_field_chat_admission_cutover_status() AS status_row
  `;
  return validateFieldChatCutoverRows(rows, expectedMigrationSha256);
}

function argumentValue(name: string): string | undefined {
  const index = Deno.args.indexOf(name);
  return index >= 0 ? Deno.args[index + 1] : undefined;
}

async function append(path: string | undefined, value: string): Promise<void> {
  if (path) await Deno.writeTextFile(path, value, { append: true });
}

if (import.meta.main) {
  const databaseUrl = Deno.env.get("MERIAN_DATABASE_URL");
  const candidateSha = Deno.env.get("GITHUB_SHA");
  const migrationPath = argumentValue("--migration") ??
    "services/supabase/migrations/20260824210544_preserve_field_chat_daily_usage.sql";
  const planPath = argumentValue("--plan");
  const summaryPath = argumentValue("--summary");

  if (!databaseUrl) throw new Error("MERIAN_DATABASE_URL is required");
  if (!candidateSha || !/^(?!0{40}$)[0-9a-f]{40}$/.test(candidateSha)) {
    throw new Error("GITHUB_SHA must be a lowercase 40-hex commit");
  }
  if (!planPath) throw new Error("--plan is required");

  validateFieldChatActivationPlan(await Deno.readTextFile(planPath));
  const migrationDigest = await sha256Hex(
    await Deno.readTextFile(migrationPath),
  );
  const bundleDigests = await computeFieldChatBundleDigests();
  const sql = postgres(databaseUrl, {
    max: 1,
    connect_timeout: 10,
    idle_timeout: 2,
    max_lifetime: 30,
  });
  try {
    const before = await readStatus(sql, migrationDigest);
    if (before.status !== "ready") {
      throw new Error(
        `Field Chat cutover must be ready before activation; observed ${before.status}`,
      );
    }

    await sql`
      SELECT public.activate_field_chat_admission_cutover(
        ${candidateSha},
        ${migrationDigest},
        ${bundleDigests["explore-post-chat"]},
        ${bundleDigests["insight-chat"]},
        ${bundleDigests["species-dictionary-chat"]}
      )
    `;

    const after = await readStatus(sql, migrationDigest);
    if (
      after.status !== "active" ||
      after.activatedCandidateSha !== candidateSha ||
      after.activatedMigrationSha256 !== migrationDigest ||
      after.activatedExploreBundleSha256 !==
        bundleDigests["explore-post-chat"] ||
      after.activatedInsightBundleSha256 !== bundleDigests["insight-chat"] ||
      after.activatedSpeciesDictionaryBundleSha256 !==
        bundleDigests["species-dictionary-chat"]
    ) {
      throw new Error(
        "Field Chat activation readback did not match source evidence",
      );
    }

    await append(
      summaryPath,
      `### Field Chat admission activated\n\nAll three required bundles completed deployment and served their exact candidate-derived content digests before this one-way database transition.\n\nActivated candidate SHA: \`${candidateSha}\`\n\nMigration SHA-256: \`${migrationDigest}\`\n\nExplore bundle SHA-256: \`${
        bundleDigests["explore-post-chat"]
      }\`\n\nInsight bundle SHA-256: \`${
        bundleDigests["insight-chat"]
      }\`\n\nSpecies Dictionary bundle SHA-256: \`${
        bundleDigests["species-dictionary-chat"]
      }\`\n\nDatabase activation time: \`${after.activatedAt}\`\n\n`,
    );
    console.log(
      `Field Chat admission activated for candidate ${candidateSha}.`,
    );
  } finally {
    await sql.end({ timeout: 2 });
  }
}
