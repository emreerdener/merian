/** Offline research navigation only. Never reads private evidence or invokes providers. */
import {
  parseCapabilities,
  qualificationRecordPaths,
  renderCapabilities,
} from "./identification-research-catalog-capabilities.ts";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
export type Study = {
  id: string;
  title: string;
  date: string;
  modality: string;
  kind: string;
  state: string;
  configuration: string;
  datasets: string[];
  attempts: number | null;
  attemptUnit: string;
  accountedUsd: number | null;
  accounting: string;
  outcome: string;
  limitations: string;
  decision: string;
  production: string;
  sources: string[];
};
export type Dataset = {
  id: string;
  title: string;
  lineage: string;
  exposure: string;
  referenceQuality: string;
  retention: string;
  sources: string[];
};
export type Catalog = {
  version: number;
  reviewedThrough: string;
  studies: Study[];
  datasets: Dataset[];
  supportingDocuments: { path: string; title: string; role: string }[];
};
function check(ok: unknown, message: string): asserts ok {
  if (!ok) throw new Error(message);
}
function record(value: unknown): asserts value is Record<string, unknown> {
  check(
    !!value && typeof value === "object" && !Array.isArray(value),
    "record required",
  );
}
function fields(value: Record<string, unknown>, expected: string[]) {
  check(
    Object.keys(value).sort().join() === expected.sort().join(),
    "unexpected/missing fields",
  );
}
function text(value: unknown) {
  check(
    typeof value === "string" && value.trim().length > 0 &&
      !/[\r\n]/.test(value),
    "nonempty single-line text required",
  );
}
function list(value: unknown): asserts value is unknown[] {
  check(Array.isArray(value) && value.length > 0, "nonempty list required");
}
function id(value: unknown) {
  check(
    typeof value === "string" && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value),
    "invalid ID",
  );
}
function path(value: unknown) {
  check(
    typeof value === "string" &&
      /^docs\/[a-zA-Z0-9_./-]+\.(md|json)$/.test(value) &&
      !value.split("/").includes(".."),
    "source must be a repository docs path",
  );
}
/** Strict public metadata validation; unknown measurements must remain null. */
export function parseCatalog(value: unknown): Catalog {
  record(value);
  fields(value, [
    "version",
    "reviewedThrough",
    "studies",
    "datasets",
    "supportingDocuments",
  ]);
  check(value.version === 1, "unsupported catalog version");
  check(
    typeof value.reviewedThrough === "string" &&
      /^\d{4}-\d{2}-\d{2}$/.test(value.reviewedThrough),
    "invalid review date",
  );
  const seen = new Set<string>();
  const unique = (entry: Record<string, unknown>) => {
    id(entry.id);
    check(!seen.has(String(entry.id)), "duplicate ID");
    seen.add(String(entry.id));
  };
  const sources = (entry: Record<string, unknown>) => {
    list(entry.sources);
    entry.sources.forEach(path);
    check(
      new Set(entry.sources).size === entry.sources.length,
      "duplicate source",
    );
  };
  list(value.datasets);
  for (const d of value.datasets) {
    record(d);
    fields(d, [
      "id",
      "title",
      "lineage",
      "exposure",
      "referenceQuality",
      "retention",
      "sources",
    ]);
    unique(d);
    for (
      const key of [
        "title",
        "lineage",
        "exposure",
        "referenceQuality",
        "retention",
      ]
    ) text(d[key]);
    sources(d);
  }
  const datasetIds = new Set(seen);
  seen.clear();
  list(value.studies);
  for (const s of value.studies) {
    record(s);
    fields(s, [
      "id",
      "title",
      "date",
      "modality",
      "kind",
      "state",
      "configuration",
      "datasets",
      "attempts",
      "attemptUnit",
      "accountedUsd",
      "accounting",
      "outcome",
      "limitations",
      "decision",
      "production",
      "sources",
    ]);
    unique(s);
    for (
      const key of [
        "title",
        "configuration",
        "accounting",
        "outcome",
        "limitations",
        "decision",
        "production",
      ]
    ) text(s[key]);
    check(
      typeof s.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s.date),
      "invalid study date",
    );
    check(
      ["photo", "audio", "text", "video", "mixed"].includes(String(s.modality)),
      "invalid modality",
    );
    check(
      ["engineering", "development", "validation", "calibration", "audit"]
        .includes(String(s.kind)),
      "invalid evidence role",
    );
    check(
      ["prepared", "active", "stopped", "closed"].includes(String(s.state)),
      "invalid state",
    );
    check(
      ["provider_attempts", "app_submissions", "none", "unknown"].includes(
        String(s.attemptUnit),
      ),
      "invalid count unit",
    );
    check(
      s.attempts === null ||
        typeof s.attempts === "number" && Number.isSafeInteger(s.attempts) &&
          s.attempts >= 0,
      "invalid attempts",
    );
    check(
      s.accountedUsd === null ||
        typeof s.accountedUsd === "number" && Number.isFinite(s.accountedUsd) &&
          s.accountedUsd >= 0,
      "invalid cost",
    );
    check(
      s.attemptUnit !== "unknown" || s.attempts === null,
      "unknown count must be null",
    );
    check(
      s.attemptUnit !== "none" || s.attempts === 0,
      "no calls requires zero count",
    );
    check(
      s.state !== "prepared" || s.attempts === 0 && s.accountedUsd === 0,
      "preparation cannot claim execution",
    );
    list(s.datasets);
    check(
      new Set(s.datasets).size === s.datasets.length &&
        s.datasets.every((x) => datasetIds.has(String(x))),
      "invalid dataset reference",
    );
    sources(s);
  }
  list(value.supportingDocuments);
  const supporting = new Set<string>();
  for (const d of value.supportingDocuments) {
    record(d);
    fields(d, ["path", "title", "role"]);
    path(d.path);
    text(d.title);
    text(d.role);
    check(!supporting.has(String(d.path)), "duplicate supporting document");
    supporting.add(String(d.path));
  }
  return value as unknown as Catalog;
}
const safe = (value: string) =>
  value.replaceAll("\\", "\\\\").replaceAll("|", "\\|").replaceAll("[", "\\[")
    .replaceAll("]", "\\]");
const sourceLinks = (sources: string[]) =>
  sources.map((p) => `[${safe(p.split("/").at(-1)!)}](../../../${p})`).join(
    ", ",
  );
export function renderRegisters(c: Catalog) {
  let experiments =
    `# Identification experiment register\n\nGenerated from [catalog.json](catalog.json); edit that source, then run\n\`make generate-identification-research\`. Reviewed through ${c.reviewedThrough}.\n\n[Research index](README.md) · [Dataset families](datasets.md) · [Procedure](procedure.md)\n\nCounts distinguish provider attempts from app submissions. Null means unknown,\nnot zero. Costs have different accounting bases and overlapping historical\ncomparators; do not sum this register or rank models across its datasets.\n\n`;
  for (const s of c.studies) {
    experiments += `## ${s.id}\n\n**${
      safe(s.title)
    }** — ${s.date}; ${s.modality}; ${s.kind}; ${s.state}.\n\n- Configuration: ${
      safe(s.configuration)
    }\n- Data: ${
      s.datasets.map((d) => `[${d}](datasets.md#${d})`).join(", ")
    }\n- Attempts: ${
      s.attempts ?? "unknown"
    } (${s.attemptUnit}). Accounted USD: ${
      s.accountedUsd === null ? "unknown" : s.accountedUsd.toFixed(9)
    }. ${safe(s.accounting)}\n- Outcome: ${safe(s.outcome)}\n- Limits: ${
      safe(s.limitations)
    }\n- Decision: ${safe(s.decision)}\n- Production: ${
      safe(s.production)
    }\n- Sources: ${sourceLinks(s.sources)}\n\n`;
  }
  experiments +=
    "## Supporting records\n\nThese links preserve plans, implementation, contracts and release context. They\nare not additional paid studies and are not summed with the entries above.\n\n";
  for (const d of c.supportingDocuments) {
    experiments += `- [${safe(d.title)}](../../../${d.path}) — ${
      safe(d.role)
    }\n`;
  }
  let datasets =
    `# Identification dataset and exposure register\n\nGenerated from [catalog.json](catalog.json); edit that source, then regenerate.\nReviewed through ${c.reviewedThrough}. [Research index](README.md).\n\nThis is a family-level lineage map. It never certifies an individual observation\nas unexposed. Private asset/cluster manifests and all attempted-claim ledgers\ncontrol that determination. Retention expiration does not erase exposure.\n\n`;
  for (const d of c.datasets) {
    datasets += `## ${d.id}\n\n**${safe(d.title)}**\n\n- Lineage: ${
      safe(d.lineage)
    }\n- Exposure: ${safe(d.exposure)}\n- References: ${
      safe(d.referenceQuality)
    }\n- Retention/access: ${safe(d.retention)}\n- Studies: ${
      c.studies.filter((s) => s.datasets.includes(d.id)).map((s) =>
        `[${s.id}](experiments.md#${s.id})`
      ).join(", ")
    }\n- Sources: ${sourceLinks(d.sources)}\n\n`;
  }
  return {
    "experiments.md": experiments.trimEnd() + "\n",
    "datasets.md": datasets.trimEnd() + "\n",
  };
}
export async function validateSources(c: Catalog, root: string) {
  const sources = new Set([
    ...c.studies.flatMap((s) => s.sources),
    ...c.datasets.flatMap((d) => d.sources),
    ...c.supportingDocuments.map((d) => d.path),
  ]);
  for (const p of sources) {
    const info = await Deno.lstat(join(root, p));
    check(
      info.isFile && !info.isSymlink,
      `source must be a regular file: ${p}`,
    );
  }
  for await (const entry of Deno.readDir(join(root, "docs/rfcs"))) {
    if (entry.isFile && /^identification-.*\.md$/.test(entry.name)) {
      check(
        sources.has(`docs/rfcs/${entry.name}`),
        `unindexed identification RFC: ${entry.name}`,
      );
    }
  }
}
if (import.meta.main) {
  check(
    Deno.args.length === 1 && ["--check", "--write"].includes(Deno.args[0]),
    "use --check or --write",
  );
  const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  const folder = join(root, "docs/research/identification");
  const catalog = parseCatalog(
    JSON.parse(await Deno.readTextFile(join(folder, "catalog.json"))),
  );
  await validateSources(catalog, root);
  const rawCapabilities = JSON.parse(
    await Deno.readTextFile(join(folder, "capabilities.json")),
  );
  const benchmarkRecords = new Map<string, unknown>();
  for (const path of qualificationRecordPaths(rawCapabilities, catalog)) {
    benchmarkRecords.set(
      path,
      JSON.parse(await Deno.readTextFile(join(root, path))),
    );
  }
  const capabilities = parseCapabilities(
    rawCapabilities,
    catalog,
    benchmarkRecords,
  );
  const rendered = {
    ...renderRegisters(catalog),
    "capabilities.md": renderCapabilities(capabilities, catalog),
  };
  for (const [name, raw] of Object.entries(rendered)) {
    // Deno is the repository formatter; generated Markdown uses the same exact output.
    const child = new Deno.Command(Deno.execPath(), {
      args: ["fmt", "--ext=md", "-"],
      stdin: "piped",
      stdout: "piped",
      stderr: "piped",
    }).spawn();
    const writer = child.stdin.getWriter();
    await writer.write(new TextEncoder().encode(raw));
    await writer.close();
    const result = await child.output();
    check(result.success, "Markdown formatter failed");
    const formatted = new TextDecoder().decode(result.stdout);
    if (Deno.args[0] === "--write") {
      await Deno.writeTextFile(join(folder, name), formatted);
    } else {check(
        await Deno.readTextFile(join(folder, name)) === formatted,
        `stale ${name}; run make generate-identification-research`,
      );}
  }
  console.log(
    `Research catalog valid: ${catalog.studies.length} studies, ${catalog.datasets.length} dataset families, ${capabilities.tasks.length} capability tasks; sources and RFC coverage checked.`,
  );
}
