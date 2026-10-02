import {
  type Capabilities,
  configurationDigest,
  metadataDigest,
  parseCapabilities,
  qualificationRecordPaths,
  renderCapabilities,
  taskContractDigest,
} from "./identification-research-catalog-capabilities.ts";
const capabilitySource: unknown = JSON.parse(
  await Deno.readTextFile("docs/research/identification/capabilities.json"),
);
import {
  parseCatalog,
  renderRegisters,
} from "./identification-research-catalog.ts";
const original: unknown = JSON.parse(
  await Deno.readTextFile("docs/research/identification/catalog.json"),
);
function assert(ok: unknown, message: string) {
  if (!ok) throw new Error(message);
}
Deno.test("catalog rejects ambiguous identities, invalid measurements and dangling dataset links", () => {
  const mutations = [
    (c: ReturnType<typeof parseCatalog>) => {
      c.studies[1].id = c.studies[0].id;
    },
    (c: ReturnType<typeof parseCatalog>) => {
      c.studies[0].datasets = ["missing"];
    },
    (c: ReturnType<typeof parseCatalog>) => {
      c.studies[0].attempts = -1;
    },
    (c: ReturnType<typeof parseCatalog>) => {
      c.studies[0].accountedUsd = Infinity;
    },
    (c: ReturnType<typeof parseCatalog>) => {
      c.studies[0].attemptUnit = "unknown";
      c.studies[0].attempts = 0;
    },
    (c: ReturnType<typeof parseCatalog>) => {
      c.studies[0].state = "prepared";
      c.studies[0].attempts = 2;
    },
    (c: ReturnType<typeof parseCatalog>) => {
      c.datasets[0].sources = ["/private/evidence.json"];
    },
    (c: ReturnType<typeof parseCatalog>) => {
      c.datasets[0].sources = ["docs/../../private/evidence.json"];
    },
  ];
  for (const mutate of mutations) {
    const c = structuredClone(parseCatalog(original));
    mutate(c);
    let failed = false;
    try {
      parseCatalog(c);
    } catch {
      failed = true;
    }
    assert(failed, "invalid catalog accepted");
  }
});
Deno.test("generated registers preserve unknown costs, count units and study/data backlinks", () => {
  const c = parseCatalog(original), rendered = renderRegisters(c);
  for (const s of c.studies) {
    assert(
      rendered["experiments.md"].includes(`## ${s.id}\n`),
      "missing study",
    );
    for (const d of s.datasets) {
      assert(
        rendered["datasets.md"].includes(`experiments.md#${s.id}`) &&
          rendered["experiments.md"].includes(`datasets.md#${d}`),
        "missing backlink",
      );
    }
  }
  const altered = structuredClone(c);
  altered.studies[0].accountedUsd = null;
  altered.studies[0].attempts = null;
  altered.studies[0].attemptUnit = "unknown";
  const result = renderRegisters(altered)["experiments.md"];
  assert(
    result.includes("Attempts: unknown (unknown). Accounted USD: unknown."),
    "unknown collapsed to zero",
  );
  assert(
    rendered["experiments.md"].includes("app_submissions"),
    "app counts lost",
  );
});

Deno.test("capability matrix rejects broken evidence links, modality leakage and fabricated decisions", () => {
  const catalog = parseCatalog(original);
  const mutations: ((c: Capabilities) => void)[] = [
    (c) => {
      c.tasks[1].id = c.tasks[0].id;
    },
    (c) => {
      c.assessments.push(c.assessments[0]);
    },
    (c) => {
      c.assessments[0].studyIds = ["missing-study"];
    },
    (c) => {
      c.assessments[0].configurationId = "missing-config";
    },
    (c) => {
      c.assessments[0].studyIds = ["photo-feature-workflow"];
    },
    (c) => {
      c.tasks[0].modality = "audio";
    },
    (c) => {
      c.configurations[0].studyIds.push("missing-study");
    },
    (c) => {
      c.assessments.find((a) => a.configurationId === "sol-feature-photo")!
        .status = "retained_baseline";
    },
    (c) => {
      c.assessments[0].status = "qualified_in_scope";
    },
    (c) => {
      c.reviewedThrough = "2026-09-01";
    },
  ];
  for (const mutate of mutations) {
    const candidate = structuredClone(
      parseCapabilities(capabilitySource, catalog),
    );
    mutate(candidate);
    let rejected = false;
    try {
      parseCapabilities(candidate, catalog);
    } catch {
      rejected = true;
    }
    assert(rejected, "invalid capability metadata accepted");
  }
});
Deno.test("scope qualification requires completed validation, exact identity and separate indexed evidence", () => {
  const catalog = structuredClone(parseCatalog(original));
  const capabilities = structuredClone(
    parseCapabilities(capabilitySource, catalog),
  );
  const assessment = capabilities.assessments[0];
  const study = catalog.studies.find((s) => s.id === assessment.studyIds[0])!;
  const protocol = "docs/rfcs/synthetic-capability-protocol.md";
  const decision = "docs/rfcs/synthetic-capability-decision.md";
  const exposure = "docs/rfcs/synthetic-capability-exposure.md";
  const recordPath =
    "docs/research/identification/benchmarks/synthetic-test-only.json";
  study.sources.push(protocol, decision, exposure, recordPath);
  const frozen = {
    version: 1,
    benchmarkVersion: "synthetic-test-only",
    taskId: assessment.taskId,
    configurationId: assessment.configurationId,
    taskContractDigest: taskContractDigest(
      capabilities.tasks.find((t) => t.id === assessment.taskId)!,
    ),
    configurationDigest: configurationDigest(capabilities.configurations[0]),
    corpusDigest: "2".repeat(64),
    referenceDigest: "3".repeat(64),
    studyId: study.id,
    protocolSource: protocol,
    exposureAuditSource: exposure,
    decisionSource: decision,
  };
  const records = new Map<string, unknown>([[recordPath, frozen]]);
  assessment.status = "qualified_in_scope";
  assessment.qualification = {
    studyId: study.id,
    benchmarkVersion: "synthetic-test-only",
    configurationDigest: frozen.configurationDigest,
    taskContractDigest: frozen.taskContractDigest,
    benchmarkRecordSource: recordPath,
    benchmarkRecordDigest: metadataDigest(frozen),
    corpusDigest: "2".repeat(64),
    referenceDigest: "3".repeat(64),
    protocolSource: protocol,
    decisionSource: decision,
    exposureAuditSource: exposure,
  };
  parseCapabilities(capabilities, catalog, records);
  const navigationOnly = structuredClone(capabilities);
  navigationOnly.tasks[0].title = "Updated navigation label";
  navigationOnly.tasks[0].nextAction = "Review existing evidence";
  parseCapabilities(navigationOnly, catalog, records);
  assert(
    qualificationRecordPaths(capabilities, catalog)[0] === recordPath,
    "indexed record not loaded",
  );
  for (
    const alteredRecords of [
      new Map<string, unknown>(),
      new Map<string, unknown>([[recordPath, {
        ...frozen,
        corpusDigest: "f".repeat(64),
      }]]),
      new Map<string, unknown>([[recordPath, {
        ...frozen,
        referenceDigest: "f".repeat(64),
      }]]),
      new Map<string, unknown>([[recordPath, {
        ...frozen,
        taskId: "audio-identification",
      }]]),
    ]
  ) {
    let rejected = false;
    try {
      parseCapabilities(capabilities, catalog, alteredRecords);
    } catch {
      rejected = true;
    }
    assert(rejected, "missing/changed benchmark accepted");
  }
  for (
    const mutate of [
      (s: typeof study) => {
        s.kind = "engineering";
      },
      (s: typeof study) => {
        s.kind = "development";
      },
      (s: typeof study) => {
        s.kind = "calibration";
      },
      (s: typeof study) => {
        s.modality = "mixed";
      },
      (s: typeof study) => {
        s.state = "prepared";
      },
      (s: typeof study) => {
        s.state = "stopped";
      },
      (s: typeof study) => {
        s.attempts = 0;
      },
      (s: typeof study) => {
        s.attemptUnit = "app_submissions";
      },
    ]
  ) {
    const altered = structuredClone(catalog);
    mutate(altered.studies.find((s) => s.id === study.id)!);
    let rejected = false;
    try {
      parseCapabilities(capabilities, altered, records);
    } catch {
      rejected = true;
    }
    assert(rejected, "nonqualifying study accepted");
  }
  for (
    const mutate of [
      (c: Capabilities) => {
        c.tasks[0].primaryMetric = "unrelated endpoint";
      },
      (c: Capabilities) => {
        c.tasks[0].coverage = "only easy cases";
      },
      (c: Capabilities) => {
        c.tasks[0].qualificationRequirements = "ignore guardrails";
      },
      (c: Capabilities) => {
        c.assessments[0].qualification!.taskContractDigest = "f".repeat(64);
      },
      (c: Capabilities) => {
        c.configurations[0].schema = null;
      },
      (c: Capabilities) => {
        c.configurations[0].prompt = "changed-prompt";
      },
      (c: Capabilities) => {
        c.assessments[0].qualification!.referenceDigest = "f".repeat(64);
      },
      (c: Capabilities) => {
        c.assessments[0].qualification!.configurationDigest = "f".repeat(64);
      },
      (c: Capabilities) => {
        c.assessments[0].qualification!.benchmarkRecordDigest = "f".repeat(64);
      },
      (c: Capabilities) => {
        c.assessments[0].qualification!.benchmarkRecordSource =
          "/private/tmp/private.json";
      },
      (c: Capabilities) => {
        c.assessments[0].qualification!.corpusDigest = "unknown";
      },
      (c: Capabilities) => {
        c.assessments[0].qualification!.decisionSource = "docs/private.json";
      },
      (c: Capabilities) => {
        c.assessments[0].qualification!.decisionSource = exposure;
      },
      (c: Capabilities) => {
        c.assessments[0].qualification!.decisionSource = protocol;
      },
      (c: Capabilities) => {
        c.assessments[0].status = "retained_baseline";
      },
    ]
  ) {
    const altered = structuredClone(capabilities);
    mutate(altered);
    let rejected = false;
    try {
      parseCapabilities(altered, catalog, records);
    } catch {
      rejected = true;
    }
    assert(rejected, "incomplete qualification accepted");
  }
});
Deno.test("capability rendering preserves negative evidence and unknowns without granting qualification", () => {
  const catalog = parseCatalog(original);
  const capabilities = parseCapabilities(capabilitySource, catalog);
  const md = renderCapabilities(capabilities, catalog);
  assert(
    capabilities.assessments.every((a) => a.qualification === null),
    "initial matrix invents qualification",
  );
  for (const t of capabilities.tasks) {
    assert(md.includes("## " + t.id + "\n"), "missing capability task");
  }
  for (const c of capabilities.configurations) {
    assert(md.includes("### " + c.id + "\n"), "missing configuration");
  }
  assert(md.includes("unknown in this register"), "unknown identity lost");
  assert(
    md.includes("Qualification is not established"),
    "qualification boundary lost",
  );
  assert(md.includes("not live routing"), "routing boundary lost");
  assert(md.includes("simultaneous interval"), "paired uncertainty lost");
  assert(md.includes("engineering, closed"), "software evidence role lost");
});
