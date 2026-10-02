/** Public decision metadata, never a model router or scientific evidence verifier. */
import { createHash } from "node:crypto";
import type { Catalog } from "./identification-research-catalog.ts";
export type CapabilityTask = {
  id: string;
  title: string;
  modality: string;
  primaryMetric: string;
  coverage: string;
  qualificationRequirements: string;
  nextAction: string;
};
export type Configuration = {
  id: string;
  provider: string;
  model: string;
  profile: string | null;
  binding: string | null;
  prompt: string | null;
  schema: string | null;
  preprocessing: string | null;
  context: string | null;
  settings: string;
  studyIds: string[];
};
export type Qualification = {
  benchmarkRecordSource: string;
  benchmarkRecordDigest: string;
  studyId: string;
  benchmarkVersion: string;
  configurationDigest: string;
  taskContractDigest: string;
  corpusDigest: string;
  referenceDigest: string;
  protocolSource: string;
  exposureAuditSource: string;
  decisionSource: string;
};
export type Assessment = {
  taskId: string;
  configurationId: string;
  status:
    | "retained_baseline"
    | "inconclusive"
    | "did_not_qualify"
    | "awaiting_results"
    | "insufficient_evidence"
    | "qualified_in_scope";
  studyIds: string[];
  findings: string;
  operations: string;
  limitations: string;
  qualification: Qualification | null;
};
export type Capabilities = {
  version: number;
  reviewedThrough: string;
  tasks: CapabilityTask[];
  configurations: Configuration[];
  assessments: Assessment[];
};
function check(ok: unknown, message: string): asserts ok {
  if (!ok) throw Error(message);
}
function object(v: unknown, keys: string[]): Record<string, unknown> {
  check(
    v !== null && typeof v === "object" && !Array.isArray(v),
    "record required",
  );
  check(
    Object.keys(v).sort().join() === [...keys].sort().join(),
    "unexpected/missing capability fields",
  );
  return v as Record<string, unknown>;
}
function text(v: unknown): asserts v is string {
  check(
    typeof v === "string" && v.trim().length > 0 && !/[\r\n]/.test(v),
    "nonempty single-line text required",
  );
}
function list(v: unknown): asserts v is unknown[] {
  check(Array.isArray(v) && v.length > 0, "nonempty list required");
}
function id(v: unknown): asserts v is string {
  text(v);
  check(/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(v), "invalid capability ID");
}
/** Canonical public metadata commitment; never hashes or reads private media here. */
export function metadataDigest(value: unknown): string {
  function canonical(v: unknown): unknown {
    if (Array.isArray(v)) return v.map(canonical);
    if (v !== null && typeof v === "object") {
      return Object.fromEntries(
        Object.entries(v).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map((
          [k, x],
        ) => [k, canonical(x)]),
      );
    }
    return v;
  }
  return createHash("sha256").update(JSON.stringify(canonical(value))).digest(
    "hex",
  );
}
export function configurationDigest(c: Configuration): string {
  const { id: _id, studyIds: _studies, ...identity } = c;
  return metadataDigest(identity);
}
/** Navigation labels and next actions can evolve without changing the endpoint. */
export function taskContractDigest(task: CapabilityTask): string {
  const { title: _title, nextAction: _next, ...contract } = task;
  return metadataDigest(contract);
}
/** Only catalog-indexed public benchmark paths may be loaded by the CLI. */
export function qualificationRecordPaths(
  value: unknown,
  catalog: Catalog,
): string[] {
  const root = object(value, [
    "version",
    "reviewedThrough",
    "tasks",
    "configurations",
    "assessments",
  ]);
  list(root.assessments);
  const sources = new Set(catalog.studies.flatMap((s) => s.sources));
  const paths = new Set<string>();
  for (const raw of root.assessments) {
    check(raw !== null && typeof raw === "object", "assessment required");
    const q = (raw as Assessment).qualification;
    if (q === null) continue;
    check(q !== null && typeof q === "object", "qualification required");
    const path = q.benchmarkRecordSource;
    check(
      typeof path === "string" &&
        /^docs\/research\/identification\/benchmarks\/[a-z0-9-]+\.json$/.test(
          path,
        ) && sources.has(path),
      "unindexed/private benchmark path",
    );
    paths.add(path);
  }
  return [...paths];
}
export function parseCapabilities(
  value: unknown,
  catalog: Catalog,
  benchmarkRecords: ReadonlyMap<string, unknown> = new Map(),
): Capabilities {
  const root = object(value, [
    "version",
    "reviewedThrough",
    "tasks",
    "configurations",
    "assessments",
  ]);
  check(root.version === 1, "unsupported capability version");
  check(
    root.reviewedThrough === catalog.reviewedThrough,
    "capability/catalog review dates differ",
  );
  const studyMap = new Map(catalog.studies.map((s) => [s.id, s]));
  const refs = (v: unknown) => {
    list(v);
    v.forEach(id);
    check(
      new Set(v).size === v.length && v.every((x) => studyMap.has(x as string)),
      "invalid capability study link",
    );
    return v as string[];
  };
  const taskIds = new Set<string>(), configIds = new Set<string>();
  const unique = (v: unknown, seen: Set<string>) => {
    id(v);
    check(!seen.has(v), "duplicate capability ID");
    seen.add(v);
  };
  list(root.tasks);
  for (const v of root.tasks) {
    const t = object(v, [
      "id",
      "title",
      "modality",
      "primaryMetric",
      "coverage",
      "qualificationRequirements",
      "nextAction",
    ]);
    unique(t.id, taskIds);
    for (
      const k of [
        "title",
        "primaryMetric",
        "coverage",
        "qualificationRequirements",
        "nextAction",
      ]
    ) text(t[k]);
    check(
      ["photo", "audio", "text", "video", "mixed"].includes(String(t.modality)),
      "invalid task modality",
    );
  }
  list(root.configurations);
  const configs = new Map<string, string[]>();
  for (const v of root.configurations) {
    const c = object(v, [
      "id",
      "provider",
      "model",
      "profile",
      "binding",
      "prompt",
      "schema",
      "preprocessing",
      "context",
      "settings",
      "studyIds",
    ]);
    unique(c.id, configIds);
    text(c.model);
    text(c.settings);
    check(
      ["openai", "google"].includes(String(c.provider)),
      "invalid provider",
    );
    for (
      const k of [
        "profile",
        "binding",
        "prompt",
        "schema",
        "preprocessing",
        "context",
      ]
    ) if (c[k] !== null) text(c[k]);
    configs.set(c.id as string, refs(c.studyIds));
  }
  list(root.assessments);
  const pairs = new Set<string>();
  for (const v of root.assessments) {
    const a = object(v, [
      "taskId",
      "configurationId",
      "status",
      "studyIds",
      "findings",
      "operations",
      "limitations",
      "qualification",
    ]);
    id(a.taskId);
    id(a.configurationId);
    check(
      taskIds.has(a.taskId) && configIds.has(a.configurationId),
      "unknown task/configuration",
    );
    const pair = a.taskId + "/" + a.configurationId;
    check(!pairs.has(pair), "duplicate task/configuration assessment");
    pairs.add(pair);
    for (const k of ["findings", "operations", "limitations"]) text(a[k]);
    check(
      [
        "retained_baseline",
        "inconclusive",
        "did_not_qualify",
        "awaiting_results",
        "insufficient_evidence",
        "qualified_in_scope",
      ].includes(String(a.status)),
      "invalid capability status",
    );
    const studies = refs(a.studyIds);
    check(
      studies.every((s) =>
        configs.get(a.configurationId as string)!.includes(s)
      ),
      "evidence not bound to configuration",
    );
    const task = (root.tasks as CapabilityTask[]).find((t) =>
      t.id === a.taskId
    )!;
    check(
      studies.every((s) =>
        [task.modality, "mixed"].includes(studyMap.get(s)!.modality)
      ),
      "cross-modality evidence",
    );
    if (
      ["retained_baseline", "inconclusive", "did_not_qualify"].includes(
        String(a.status),
      )
    ) {
      check(
        studies.some((s) => {
          const e = studyMap.get(s)!;
          return ["development", "validation", "calibration"].includes(
            e.kind,
          ) && e.attempts !== null && e.attempts > 0 &&
            ["closed", "stopped"].includes(e.state);
        }),
        "decision needs completed model evidence",
      );
    }
    if (a.status !== "qualified_in_scope") {
      check(
        a.qualification === null,
        "qualification cannot accompany nonqualified status",
      );
      continue;
    }
    const config = (root.configurations as Configuration[]).find((c) =>
      c.id === a.configurationId
    )!;
    check(
      [
        config.profile,
        config.binding,
        config.prompt,
        config.schema,
        config.preprocessing,
        config.context,
      ].every((v) => v !== null),
      "qualification requires complete configuration identity",
    );
    const q = object(a.qualification, [
      "benchmarkRecordSource",
      "benchmarkRecordDigest",
      "studyId",
      "benchmarkVersion",
      "configurationDigest",
      "taskContractDigest",
      "corpusDigest",
      "referenceDigest",
      "protocolSource",
      "exposureAuditSource",
      "decisionSource",
    ]);
    check(
      studies.includes(String(q.studyId)),
      "qualification study not linked",
    );
    const study = studyMap.get(String(q.studyId))!;
    check(
      study.kind === "validation" && study.modality === task.modality &&
        study.state === "closed" &&
        study.attemptUnit === "provider_attempts" &&
        study.attempts !== null && study.attempts > 0,
      "qualification requires completed validation",
    );
    check(
      study.sources.includes(String(q.benchmarkRecordSource)) &&
        /^docs\/research\/identification\/benchmarks\/[a-z0-9-]+\.json$/.test(
          String(q.benchmarkRecordSource),
        ),
      "versioned benchmark record must be indexed by study",
    );
    const record = object(
      benchmarkRecords.get(String(q.benchmarkRecordSource)),
      [
        "version",
        "benchmarkVersion",
        "taskId",
        "configurationId",
        "configurationDigest",
        "taskContractDigest",
        "corpusDigest",
        "referenceDigest",
        "studyId",
        "protocolSource",
        "exposureAuditSource",
        "decisionSource",
      ],
    );
    check(
      record.version === 1 && record.taskId === a.taskId &&
        record.configurationId === a.configurationId,
      "benchmark scope mismatch",
    );
    check(
      metadataDigest(record) === q.benchmarkRecordDigest,
      "changed benchmark record",
    );
    check(
      q.taskContractDigest === taskContractDigest(task),
      "changed task contract",
    );
    check(
      q.configurationDigest === configurationDigest(config),
      "changed configuration identity",
    );
    for (
      const k of [
        "benchmarkVersion",
        "configurationDigest",
        "taskContractDigest",
        "corpusDigest",
        "referenceDigest",
        "studyId",
        "protocolSource",
        "exposureAuditSource",
        "decisionSource",
      ]
    ) {
      check(
        record[k] === q[k],
        "qualification differs from frozen benchmark record",
      );
    }
    text(q.benchmarkVersion);
    for (
      const k of [
        "configurationDigest",
        "taskContractDigest",
        "corpusDigest",
        "referenceDigest",
      ]
    ) {
      check(
        typeof q[k] === "string" && /^[a-f0-9]{64}$/.test(q[k] as string),
        "invalid qualification digest",
      );
    }
    for (
      const k of ["protocolSource", "exposureAuditSource", "decisionSource"]
    ) {
      check(
        study.sources.includes(String(q[k])),
        "qualification source must be indexed by its study",
      );
    }
    check(
      q.protocolSource !== q.decisionSource &&
        q.exposureAuditSource !== q.decisionSource,
      "prospective protocol and qualification decision must be separate records",
    );
  }
  check(
    [...taskIds].every((t) => [...pairs].some((p) => p.startsWith(t + "/"))),
    "task missing assessment",
  );
  check(
    [...configIds].every((c) => [...pairs].some((p) => p.endsWith("/" + c))),
    "configuration missing assessment",
  );
  return value as Capabilities;
}
const safe = (v: string) =>
  v.replaceAll("\\", "\\\\").replaceAll("|", "\\|").replaceAll("[", "\\[")
    .replaceAll("]", "\\]");
export function renderCapabilities(c: Capabilities, catalog: Catalog): string {
  let md =
    "# Task-to-model capability matrix\n\nGenerated from [capabilities.json](capabilities.json); edit that file, then run\n`make generate-identification-research`. Reviewed through " +
    c.reviewedThrough +
    ".\n\n[Research index](README.md) · [Qualification rules](benchmark-contract.md) · [Experiments](experiments.md)\n\nThis is a research decision ledger, not live routing. Retained baseline does not mean benchmark-qualified. Scores apply only to their linked study, configuration and dataset; do not rank across rows from different studies. Unknown measurements remain unknown. Product assignment and deployment are not assessed here. Qualification is not established unless a row links an explicit qualification record.\n\n";
  for (const t of c.tasks) {
    md += "## " + t.id + "\n\n**" + safe(t.title) + "** (" + t.modality +
      ").\n\n- Primary metric: " + safe(t.primaryMetric) +
      "\n- Required coverage: " + safe(t.coverage) + "\n- Qualification: " +
      safe(t.qualificationRequirements) + "\n- Next action: " +
      safe(t.nextAction) +
      "\n\n| Configuration | Decision | Evidence | Cost and latency | Limits |\n| --- | --- | --- | --- | --- |\n";
    for (const a of c.assessments.filter((a) => a.taskId === t.id)) {
      const config = c.configurations.find((x) => x.id === a.configurationId)!;
      const links = a.studyIds.map((id) => {
        const s = catalog.studies.find((s) => s.id === id)!;
        return "[" + id + "](experiments.md#" + id + ") (" + s.kind + ", " +
          s.state + ")";
      }).join("; ");
      md += "| [" + a.configurationId + "](#" + a.configurationId + ") | " +
        a.status.replaceAll("_", " ") + " | " + safe(a.findings) + " " + links +
        " | " + safe(a.operations) + " | " + safe(a.limitations) + " |\n";

      text(config.model);
    }
    md += "\n";
    for (
      const a of c.assessments.filter((a) =>
        a.taskId === t.id && a.qualification
      )
    ) {
      md += "Qualification for " + a.configurationId + ": [" +
        safe(a.qualification!.benchmarkVersion) + "](../../../" +
        a.qualification!.decisionSource + ").\n\n";
    }
  }
  md +=
    "## Configuration identities\n\nThese labels identify historical evaluated configurations, not interchangeable model families. Exact frozen manifests own full request identities. A missing prompt identity blocks future qualification until recovered or newly frozen.\n\n";
  for (const c0 of c.configurations) {
    md += "### " + c0.id + "\n\n- Provider/model: " + safe(c0.provider) +
      " / " + safe(c0.model) + "\n";
    for (
      const k of [
        "profile",
        "binding",
        "prompt",
        "schema",
        "preprocessing",
        "context",
      ] as const
    ) {
      md += "- " + k + ": " +
        safe(
          c0[k] ??
            "unknown in this register; recover from the frozen study before qualification",
        ) + "\n";
    }
    md += "- Settings/scope: " + safe(c0.settings) + "\n- Evidence: " +
      c0.studyIds.map((id) => "[" + id + "](experiments.md#" + id + ")").join(
        ", ",
      ) + "\n\n";
  }
  return md.trimEnd() + "\n";
}
