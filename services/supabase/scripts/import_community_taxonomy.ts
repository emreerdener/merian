/**
 * Runs a bounded Community Taxonomy import through the deployed Edge Function.
 *
 * Required env:
 *   SUPABASE_URL
 *   SUPABASE_SERVER_API_KEY, platform SUPABASE_SECRET_KEYS, or the migration-only
 *   SUPABASE_SERVICE_ROLE_KEY fallback
 *
 * Example:
 *   deno run --allow-net --allow-env --allow-read --allow-write \
 *     services/supabase/scripts/import_community_taxonomy.ts \
 *     --target birds --limit 100 --page-count 20 --update-checklist
 */

import { createServiceRoleClientFromEnvironment } from "../functions/_shared/serviceRoleClient.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

interface ImportArgs {
  target: "birds";
  offset: number | null;
  limit: number;
  pageCount: number;
  dryRun: boolean;
  retry: boolean;
  updateChecklist: boolean;
  summaryJsonPath: string | null;
  summaryMarkdownPath: string | null;
}

interface ImportPage {
  offset: number;
  limit: number;
  normalized_count: number;
  imported_count: number;
  end_of_records: boolean;
  next_offset: number;
}

interface ImportResponse {
  success: boolean;
  target: string;
  dry_run: boolean;
  retry: boolean;
  refresh_coverage: boolean;
  start_offset: number;
  imported_count: number;
  fetched_count: number;
  normalized_count: number;
  end_of_records: boolean;
  next_offset: number;
  pages: ImportPage[];
}

interface CoverageTarget {
  slug: string;
  indexed_species_count: number;
  dictionary_species_count: number;
  coverage_ratio: number;
  last_imported_offset: number;
  next_import_offset: number;
  gbif_total_count: number | null;
}

interface StatusResponse {
  success: boolean;
  coverage_targets: CoverageTarget[];
  latest_import_runs: Array<{
    scope: string;
    status: string;
    requested_query: string;
    imported_count: number;
    error_count: number;
  }>;
}

const args = parseArgs(Deno.args);
const supabase = createServiceRoleClientFromEnvironment();

const importResponse = await postJson<ImportResponse>(
  supabase,
  "sync-community-taxonomy-index",
  {
    target: args.target,
    ...(args.offset == null ? {} : { offset: args.offset }),
    limit: args.limit,
    page_count: args.pageCount,
    dry_run: args.dryRun,
    retry: args.retry,
  },
);

const statusResponse = await postJson<StatusResponse>(
  supabase,
  "community-taxonomy-status",
  {
    view: "coverage",
    target: args.target,
    import_run_limit: 5,
    job_limit: 1,
  },
);

printSummary(importResponse, statusResponse);
await writeSummaryFiles(importResponse, statusResponse, args);

if (args.updateChecklist && !args.dryRun) {
  await updateChecklist(importResponse, statusResponse);
}

async function postJson<T>(
  supabase: SupabaseClient,
  functionName: string,
  body: Record<string, unknown>,
): Promise<T> {
  const { data, error } = await supabase.functions.invoke(
    functionName,
    { body },
  );

  if (error) {
    throw new Error(`${functionName} returned an error: ${error.message}`);
  }

  return data as T;
}

function printSummary(
  importResponse: ImportResponse,
  statusResponse: StatusResponse,
): void {
  const coverage = statusResponse.coverage_targets.find((target) =>
    target.slug === importResponse.target
  );
  const failedRuns = statusResponse.latest_import_runs.filter((run) =>
    run.status !== "completed" || run.error_count > 0
  );

  console.log("Community taxonomy import complete");
  console.log(`target: ${importResponse.target}`);
  console.log(`dry_run: ${importResponse.dry_run}`);
  console.log(`start_offset: ${importResponse.start_offset}`);
  console.log(`next_offset: ${importResponse.next_offset}`);
  console.log(`fetched_count: ${importResponse.fetched_count}`);
  console.log(`normalized_count: ${importResponse.normalized_count}`);
  console.log(`imported_count: ${importResponse.imported_count}`);
  console.log(`pages: ${importResponse.pages.length}`);

  if (coverage) {
    console.log(`indexed_species_count: ${coverage.indexed_species_count}`);
    console.log(
      `dictionary_species_count: ${coverage.dictionary_species_count}`,
    );
    console.log(`coverage_ratio: ${coverage.coverage_ratio}`);
    console.log(`last_imported_offset: ${coverage.last_imported_offset}`);
    console.log(`next_import_offset: ${coverage.next_import_offset}`);
    console.log(`gbif_total_count: ${coverage.gbif_total_count ?? "unknown"}`);
  }

  if (failedRuns.length > 0) {
    console.warn("Recent import failures detected:");
    for (const run of failedRuns) {
      console.warn(
        `- ${run.requested_query}: status=${run.status} error_count=${run.error_count}`,
      );
    }
  }
}

async function writeSummaryFiles(
  importResponse: ImportResponse,
  statusResponse: StatusResponse,
  args: ImportArgs,
): Promise<void> {
  if (!args.summaryJsonPath && !args.summaryMarkdownPath) return;

  const coverage = statusResponse.coverage_targets.find((target) =>
    target.slug === importResponse.target
  );
  const failedRuns = statusResponse.latest_import_runs.filter((run) =>
    run.status !== "completed" || run.error_count > 0
  );
  const generatedAt = new Date().toISOString();
  const summary = {
    generated_at: generatedAt,
    requested: {
      target: args.target,
      offset: args.offset,
      limit: args.limit,
      page_count: args.pageCount,
      dry_run: args.dryRun,
      retry: args.retry,
    },
    import: importResponse,
    coverage: coverage ?? null,
    recent_failed_runs: failedRuns,
  };

  if (args.summaryJsonPath) {
    await Deno.writeTextFile(
      args.summaryJsonPath,
      `${JSON.stringify(summary, null, 2)}\n`,
    );
    console.log(`summary_json: ${args.summaryJsonPath}`);
  }

  if (args.summaryMarkdownPath) {
    await Deno.writeTextFile(
      args.summaryMarkdownPath,
      renderMarkdownSummary(summary),
    );
    console.log(`summary_markdown: ${args.summaryMarkdownPath}`);
  }
}

function renderMarkdownSummary(summary: {
  generated_at: string;
  requested: {
    target: string;
    offset: number | null;
    limit: number;
    page_count: number;
    dry_run: boolean;
    retry: boolean;
  };
  import: ImportResponse;
  coverage: CoverageTarget | null;
  recent_failed_runs: StatusResponse["latest_import_runs"];
}): string {
  const lines = [
    "# Community Taxonomy Import Summary",
    "",
    `Generated: ${summary.generated_at}`,
    "",
    "## Request",
    "",
    `- Target: \`${summary.requested.target}\``,
    `- Offset: ${
      summary.requested.offset == null
        ? "database cursor"
        : `\`${summary.requested.offset}\``
    }`,
    `- Limit: \`${summary.requested.limit}\``,
    `- Page count: \`${summary.requested.page_count}\``,
    `- Dry run: \`${summary.requested.dry_run}\``,
    `- Retry: \`${summary.requested.retry}\``,
    "",
    "## Import",
    "",
    `- Start offset: \`${summary.import.start_offset}\``,
    `- Next offset: \`${summary.import.next_offset}\``,
    `- Fetched: \`${summary.import.fetched_count}\``,
    `- Normalized: \`${summary.import.normalized_count}\``,
    `- Imported: \`${summary.import.imported_count}\``,
    `- Pages: \`${summary.import.pages.length}\``,
    `- End of records: \`${summary.import.end_of_records}\``,
  ];

  if (summary.coverage) {
    lines.push(
      "",
      "## Coverage",
      "",
      `- Indexed species: \`${summary.coverage.indexed_species_count}\``,
      `- Dictionary species: \`${summary.coverage.dictionary_species_count}\``,
      `- Coverage ratio: \`${summary.coverage.coverage_ratio}\``,
      `- Last imported offset: \`${summary.coverage.last_imported_offset}\``,
      `- Next import offset: \`${summary.coverage.next_import_offset}\``,
      `- GBIF total count: \`${
        summary.coverage.gbif_total_count ?? "unknown"
      }\``,
    );
  }

  if (summary.import.pages.length > 0) {
    lines.push(
      "",
      "## Pages",
      "",
      "| Offset | Limit | Normalized | Imported | Next offset | End |",
      "| -----: | ----: | ---------: | -------: | ----------: | --- |",
      ...summary.import.pages.map((page) =>
        `| \`${page.offset}\` | \`${page.limit}\` | \`${page.normalized_count}\` | \`${page.imported_count}\` | \`${page.next_offset}\` | \`${page.end_of_records}\` |`
      ),
    );
  }

  if (summary.recent_failed_runs.length > 0) {
    lines.push("", "## Recent Failures", "");
    for (const run of summary.recent_failed_runs) {
      lines.push(
        `- \`${run.requested_query}\`: status=\`${run.status}\`, error_count=\`${run.error_count}\``,
      );
    }
  }

  lines.push("");
  return `${lines.join("\n")}\n`;
}

async function updateChecklist(
  importResponse: ImportResponse,
  statusResponse: StatusResponse,
): Promise<void> {
  const checklistPath =
    "docs/backend-and-data/07-community-taxonomy-import-checklist.md";
  let text = await Deno.readTextFile(checklistPath);
  const coverage = statusResponse.coverage_targets.find((target) =>
    target.slug === importResponse.target
  );
  if (!coverage) {
    throw new Error(`No coverage target found for ${importResponse.target}`);
  }
  if (importResponse.pages.length === 0) {
    throw new Error("No import pages returned; checklist was not updated.");
  }

  const importedOffsets = importResponse.pages.map((page) =>
    `\`${page.offset}\``
  )
    .join(", ");
  const currentOffsets = [
    ...new Set([
      ...extractImportedOffsets(text),
      ...importResponse.pages.map((page) => page.offset),
    ]),
  ].sort((a, b) => a - b);
  const offsetsLabel = currentOffsets.map((offset) => `\`${offset}\``).join(
    ", ",
  );

  text = text.replace(
    /Last updated: \d{4}-\d{2}-\d{2}/,
    `Last updated: ${new Date().toISOString().slice(0, 10)}`,
  );
  text = text.replace(
    /Last verified remote (?:status|import run): .+\./,
    `Last verified remote status: ${
      new Date().toISOString().slice(0, 10)
    } after ${
      capitalize(importResponse.target)
    } offset ${importResponse.start_offset}.`,
  );
  text = text.replace(
    /\| Birds \(`Aves`\) \| `212`\s+\| .* \|/,
    `| Birds (\`Aves\`) | \`212\`     | ${offsetsLabel} |         \`${coverage.last_imported_offset}\` |       \`${coverage.next_import_offset}\` |           \`${coverage.indexed_species_count}\` |               \`${coverage.dictionary_species_count}\` | \`${coverage.coverage_ratio}\` |`,
  );

  const completedRows = importResponse.pages.map((page) =>
    `| ${
      new Date().toISOString().slice(0, 10)
    } | Birds  |  \`${page.offset}\` | \`${page.limit}\` |       \`${page.normalized_count}\` |     \`${page.imported_count}\` | \`gbif_bounded_birds\` | Complete, \`error_count = 0\` |`
  ).join("\n");
  text = text.replace(
    /(## Next Import Batches)/,
    `${completedRows}\n\n$1`,
  );

  const nextOffsets = [
    coverage.next_import_offset,
    coverage.next_import_offset + importResponse.pages[0].limit,
    coverage.next_import_offset + importResponse.pages[0].limit * 2,
  ];
  text = text.replace(
    /## Next Import Batches\n\n(?:- \[ \] Birds offset `\d+`, limit `\d+`\.\n){1,3}/,
    `## Next Import Batches\n\n${
      nextOffsets.map((offset) =>
        `- [ ] Birds offset \`${offset}\`, limit \`${
          importResponse.pages[0].limit
        }\`.`
      ).join("\n")
    }\n`,
  );
  text = text.replace(
    /--data '\{"target":"birds"(?:,"offset":\d+)?,"limit":\d+,"page_count":1\}'/,
    `--data '{"target":"birds","limit":${
      importResponse.pages[0].limit
    },"page_count":1}'`,
  );

  await Deno.writeTextFile(checklistPath, text);
  console.log(`updated_checklist: ${checklistPath}`);
  console.log(`recorded_offsets: ${importedOffsets}`);
}

function extractImportedOffsets(text: string): number[] {
  const match = text.match(/\| Birds \(`Aves`\) \| `212`\s+\| ([^|]+) \|/);
  if (!match) return [];
  return Array.from(match[1].matchAll(/`(\d+)`/g)).map((entry) =>
    Number(entry[1])
  );
}

function parseArgs(rawArgs: string[]): ImportArgs {
  const values = new Map<string, string | boolean>();
  for (let index = 0; index < rawArgs.length; index += 1) {
    const arg = rawArgs[index];
    if (!arg.startsWith("--")) continue;
    const [key, inlineValue] = arg.slice(2).split("=", 2);
    if (inlineValue !== undefined) {
      values.set(key, inlineValue);
    } else if (rawArgs[index + 1] && !rawArgs[index + 1].startsWith("--")) {
      values.set(key, rawArgs[index + 1]);
      index += 1;
    } else {
      values.set(key, true);
    }
  }

  const target = String(values.get("target") ?? "birds").toLowerCase();
  if (target !== "birds") throw new Error("Only --target birds is supported.");

  return {
    target: "birds",
    offset: parseOptionalInteger(values.get("offset"), "--offset"),
    limit: parseInteger(values.get("limit") ?? "100", "--limit", 1, 200),
    pageCount: parseInteger(
      values.get("page-count") ?? values.get("page_count") ?? "3",
      "--page-count",
      1,
      20,
    ),
    dryRun: values.has("dry-run") || values.has("dry_run"),
    retry: values.has("retry"),
    updateChecklist: values.has("update-checklist") ||
      values.has("update_checklist"),
    summaryJsonPath: parseOptionalString(
      values.get("summary-json") ?? values.get("summary_json"),
      "--summary-json",
    ),
    summaryMarkdownPath: parseOptionalString(
      values.get("summary-md") ?? values.get("summary_md"),
      "--summary-md",
    ),
  };
}

function parseOptionalString(
  value: string | boolean | undefined,
  label: string,
): string | null {
  if (value === undefined || value === false) return null;
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${label} must be a non-empty path.`);
  }
  return value;
}

function parseOptionalInteger(
  value: string | boolean | undefined,
  label: string,
): number | null {
  if (value === undefined || value === false) return null;
  return parseInteger(value, label, 0, Number.MAX_SAFE_INTEGER);
}

function parseInteger(
  value: string | boolean,
  label: string,
  min: number,
  max: number,
): number {
  if (typeof value !== "string" || !/^\d+$/.test(value)) {
    throw new Error(`${label} must be an integer.`);
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`${label} must be from ${min} to ${max}.`);
  }
  return parsed;
}



function capitalize(value: string): string {
  return value.slice(0, 1).toUpperCase() + value.slice(1);
}
