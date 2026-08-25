import postgres from "npm:postgres@3.4.7";

export const FIELD_CHAT_CUTOVER_MIGRATION_ID =
  "20260824210544_preserve_field_chat_daily_usage";

const CANDIDATE_SHA_PATTERN = /^(?!0{40}$)[0-9a-f]{40}$/;
const DIGEST_PATTERN = /^(?!0{64}$)[0-9a-f]{64}$/;

export interface FieldChatCutoverStatus {
  migrationId: string;
  databaseNow: string;
  seededAt: string;
  notBeforeUtc: string;
  activatedAt: string | null;
  activatedCandidateSha: string | null;
  activatedMigrationSha256: string | null;
  activatedExploreBundleSha256: string | null;
  activatedInsightBundleSha256: string | null;
  activatedSpeciesDictionaryBundleSha256: string | null;
  status: "pending" | "ready" | "active";
}

export interface RawCutoverRow {
  migration_id?: unknown;
  database_now?: unknown;
  seeded_at?: unknown;
  not_before_utc?: unknown;
  activated_at?: unknown;
  activated_candidate_sha?: unknown;
  activated_migration_sha256?: unknown;
  activated_explore_bundle_sha256?: unknown;
  activated_insight_bundle_sha256?: unknown;
  activated_species_dictionary_bundle_sha256?: unknown;
  status?: unknown;
}

function timestamp(
  value: unknown,
  field: string,
): { raw: string; epoch: number } {
  if (typeof value !== "string") {
    throw new Error(`${field} is not a timestamp string`);
  }
  const epoch = Date.parse(value);
  if (!Number.isFinite(epoch)) throw new Error(`${field} is invalid`);
  return { raw: value, epoch };
}

export function validateFieldChatCutoverRows(
  rows: readonly RawCutoverRow[],
  expectedMigrationSha256?: string,
): FieldChatCutoverStatus {
  if (rows.length !== 1) {
    throw new Error(`cutover status returned ${rows.length} rows instead of 1`);
  }
  const row = rows[0];
  if (row.migration_id !== FIELD_CHAT_CUTOVER_MIGRATION_ID) {
    throw new Error("cutover migration id is missing or unexpected");
  }
  if (
    row.status !== "pending" && row.status !== "ready" &&
    row.status !== "active"
  ) {
    throw new Error("cutover status is missing or unexpected");
  }

  const databaseNow = timestamp(row.database_now, "database_now");
  const seededAt = timestamp(row.seeded_at, "seeded_at");
  const notBefore = timestamp(row.not_before_utc, "not_before_utc");
  if (databaseNow.epoch < seededAt.epoch) {
    throw new Error("database clock predates the cutover seed");
  }
  if (notBefore.epoch <= seededAt.epoch) {
    throw new Error("cutover boundary does not follow the seed");
  }
  const boundary = new Date(notBefore.epoch);
  if (
    boundary.getUTCHours() !== 0 || boundary.getUTCMinutes() !== 0 ||
    boundary.getUTCSeconds() !== 0 || boundary.getUTCMilliseconds() !== 0
  ) {
    throw new Error("cutover boundary is not an exact UTC day boundary");
  }

  const activationValues = [
    row.activated_at,
    row.activated_candidate_sha,
    row.activated_migration_sha256,
    row.activated_explore_bundle_sha256,
    row.activated_insight_bundle_sha256,
    row.activated_species_dictionary_bundle_sha256,
  ];
  const hasAnyActivationValue = activationValues.some((value) =>
    value !== null
  );
  const hasEveryActivationValue = activationValues.every((value) =>
    value !== null
  );
  if (hasAnyActivationValue !== hasEveryActivationValue) {
    throw new Error("cutover activation evidence is incomplete");
  }

  let activatedAt: { raw: string; epoch: number } | null = null;
  let activatedCandidateSha: string | null = null;
  let activatedMigrationSha256: string | null = null;
  let activatedExploreBundleSha256: string | null = null;
  let activatedInsightBundleSha256: string | null = null;
  let activatedSpeciesDictionaryBundleSha256: string | null = null;
  if (hasEveryActivationValue) {
    activatedAt = timestamp(row.activated_at, "activated_at");
    if (activatedAt.epoch < notBefore.epoch) {
      throw new Error("cutover activation predates its UTC boundary");
    }
    if (activatedAt.epoch > databaseNow.epoch) {
      throw new Error("cutover activation is later than the database clock");
    }
    if (
      typeof row.activated_candidate_sha !== "string" ||
      !CANDIDATE_SHA_PATTERN.test(row.activated_candidate_sha)
    ) {
      throw new Error("cutover candidate SHA is missing or malformed");
    }
    if (
      typeof row.activated_migration_sha256 !== "string" ||
      !DIGEST_PATTERN.test(row.activated_migration_sha256)
    ) {
      throw new Error("cutover migration digest is missing or malformed");
    }
    if (
      expectedMigrationSha256 !== undefined &&
      row.activated_migration_sha256 !== expectedMigrationSha256
    ) {
      throw new Error(
        "cutover activation is bound to a different migration digest",
      );
    }
    for (
      const [field, value] of [
        [
          "activated_explore_bundle_sha256",
          row.activated_explore_bundle_sha256,
        ],
        [
          "activated_insight_bundle_sha256",
          row.activated_insight_bundle_sha256,
        ],
        [
          "activated_species_dictionary_bundle_sha256",
          row.activated_species_dictionary_bundle_sha256,
        ],
      ] as const
    ) {
      if (typeof value !== "string" || !DIGEST_PATTERN.test(value)) {
        throw new Error(`${field} is missing or malformed`);
      }
    }
    activatedCandidateSha = row.activated_candidate_sha;
    activatedMigrationSha256 = row.activated_migration_sha256;
    activatedExploreBundleSha256 = row
      .activated_explore_bundle_sha256 as string;
    activatedInsightBundleSha256 = row
      .activated_insight_bundle_sha256 as string;
    activatedSpeciesDictionaryBundleSha256 = row
      .activated_species_dictionary_bundle_sha256 as string;
  }

  const expectedStatus = databaseNow.epoch < notBefore.epoch
    ? "pending"
    : activatedAt === null
    ? "ready"
    : "active";
  if (row.status !== expectedStatus) {
    throw new Error("cutover status contradicts the database clock");
  }

  return {
    migrationId: row.migration_id,
    databaseNow: databaseNow.raw,
    seededAt: seededAt.raw,
    notBeforeUtc: notBefore.raw,
    activatedAt: activatedAt?.raw ?? null,
    activatedCandidateSha,
    activatedMigrationSha256,
    activatedExploreBundleSha256,
    activatedInsightBundleSha256,
    activatedSpeciesDictionaryBundleSha256,
    status: row.status,
  };
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
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
  const outputPath = argumentValue("--output");
  const summaryPath = argumentValue("--summary");

  if (!databaseUrl) throw new Error("MERIAN_DATABASE_URL is required");
  if (!candidateSha || !CANDIDATE_SHA_PATTERN.test(candidateSha)) {
    throw new Error("GITHUB_SHA must be a lowercase 40-hex commit");
  }

  const migrationDigest = await sha256Hex(
    await Deno.readTextFile(migrationPath),
  );
  const sql = postgres(databaseUrl, {
    max: 1,
    connect_timeout: 10,
    idle_timeout: 2,
    max_lifetime: 30,
  });
  try {
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
    const status = validateFieldChatCutoverRows(rows, migrationDigest);
    await append(
      outputPath,
      `status=${status.status}\nnot_before_utc=${status.notBeforeUtc}\nmigration_sha256=${migrationDigest}\n`,
    );
    await append(
      summaryPath,
      `### Field Chat admission cutover\n\nCandidate SHA: \`${candidateSha}\`\n\nMigration SHA-256: \`${migrationDigest}\`\n\nDatabase status: **${status.status}**\n\nDatabase observed at: \`${status.databaseNow}\`\n\nActivation is eligible no earlier than: \`${status.notBeforeUtc}\`\n\nActivated candidate: ${
        status.activatedCandidateSha
          ? `\`${status.activatedCandidateSha}\``
          : "not activated"
      }\n\n`,
    );
    console.log(
      `Field Chat cutover is ${status.status}; not before ${status.notBeforeUtc}.`,
    );
  } finally {
    await sql.end({ timeout: 2 });
  }
}
