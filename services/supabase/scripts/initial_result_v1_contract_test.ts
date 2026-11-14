/** Compatibility gate: changes require a reviewed decision, never regeneration
 * of retained v1 rules. The full dependency-free public source hash covers all
 * transitive parser/primary constants and helpers, including harmless edits. */
import { assertEquals } from "@std/assert";
import baseline from "../functions/_shared/initialAnalysis/resultContractV2Baseline.json" with {
  type: "json",
};
import {
  identificationProvenanceContract,
  identifyWireEnvelopeContract,
  primaryIdentificationContract,
} from "../functions/_shared/identify/contract.ts";
import {
  dataContractV2,
  primaryContractV2,
  provenanceContractV2,
} from "../functions/_shared/initialAnalysis/resultSchemaV2.ts";
function executable(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(executable);
  if (value && typeof value === "object") {
    const node = value as Record<string, unknown>;
    return Object.fromEntries(
      Object.entries(node).filter(([key]) =>
        key !== "description" && (key !== "swift" || node.kind === "union")
      ).map(([key, v]) => [key, executable(v)]),
    );
  }
  return value;
}
Deno.test("result-v2 is the reviewed additive public contract", () => {
  assertEquals(
    executable(dataContractV2),
    executable(identifyWireEnvelopeContract.fields.data.contract),
  );
  assertEquals(
    executable(provenanceContractV2),
    executable(identificationProvenanceContract),
  );
  assertEquals(primaryContractV2, executable(primaryIdentificationContract));
});
Deno.test("result-v2 semantic baseline preserves immutable result-v1 sources", async () => {
  const source = await Deno.readFile(
    new URL("../functions/_shared/identify/contract.ts", import.meta.url),
  );
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", source));
  const actual = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join(
    "",
  );
  for (
    const [file, expected] of [[
      "resultSchemaV1.ts",
      baseline.retained_v1_schema_sha256,
    ], ["resultSemanticsV1.ts", baseline.retained_v1_semantics_sha256]]
  ) {
    const bytes = await Deno.readFile(
      new URL(`../functions/_shared/initialAnalysis/${file}`, import.meta.url),
    );
    const digest = Array.from(
      new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
      (b) => b.toString(16).padStart(2, "0"),
    ).join("");
    assertEquals(
      digest,
      expected,
      "Historical V1 rules must remain byte-identical.",
    );
  }
  assertEquals(
    actual,
    baseline.public_source_sha256,
    "Review compatibility: preserve old v1 and its vectors; do not regenerate it from current Identify.",
  );
});

Deno.test("result-v1 SQL rules exactly consume the frozen definition without API grants", async () => {
  const { initialResultV1SchemaSQL } = await import(
    "./initial_result_v1_sql.ts"
  );
  const source = await Deno.readTextFile(
    new URL(
      "../migrations/20261103074331_consume_initial_analysis.sql",
      import.meta.url,
    ),
  );
  const block = source.match(
    /-- BEGIN FROZEN RESULT_V1_SCHEMA[\s\S]*?-- END FROZEN RESULT_V1_SCHEMA/,
  )?.[0];
  assertEquals(block, initialResultV1SchemaSQL());
  assertEquals(/\bGRANT\s+EXECUTE\b/i.test(source), false);
});

Deno.test("S0 witness installs only the reviewed private dispatch, report and result graphs", async () => {
  const source = await Deno.readTextFile(
    new URL(
      "../migrations/20261103074331_consume_initial_analysis.sql",
      import.meta.url,
    ),
  );
  assertEquals(
    source.includes(
      "ALTER TABLE internal.initial_consuming_staging ENABLE ROW LEVEL SECURITY",
    ),
    true,
  );
  assertEquals(
    source.includes(
      "REVOKE ALL ON internal.initial_consuming_staging FROM PUBLIC,anon,authenticated,service_role",
    ),
    true,
  );
  const observers = [...source.matchAll(
    /CREATE TRIGGER (s0_\w+) (BEFORE|AFTER) ([A-Z ]+) ON ([a-z_.]+)\s+FOR EACH (STATEMENT|ROW) EXECUTE FUNCTION internal\.guard_initial_consuming_member\('([a-z]+)'\);/g,
  )].map((m) => m.slice(1).join("|"));
  const expected: string[] = [];
  for (
    const [relation, action] of [
      ["public.ai_usage_events", "INSERT"],
      ["internal.identification_invocations", "UPDATE"],
    ]
  ) {
    for (const timing of ["BEFORE", "AFTER"]) {
      for (const level of ["STATEMENT", "ROW"]) {
        expected.push(
          `s0_report_${level.toLowerCase()}_${timing.toLowerCase()}|${timing}|${action}|${relation}|${level}|report`,
        );
      }
    }
  }
  for (const timing of ["BEFORE", "AFTER"]) {
    for (const level of ["STATEMENT", "ROW"]) {
      const action = "INSERT OR UPDATE OR DELETE" +
        (timing === "BEFORE" && level === "STATEMENT" ? " OR TRUNCATE" : "");
      expected.push(
        `s0_result_${level.toLowerCase()}_${timing.toLowerCase()}|${timing}|${action}|internal.initial_analysis_results|${level}|result`,
      );
    }
  }
  for (
    const relation of [
      "internal.ai_quota_reservations",
      "internal.ai_quota_reservation_counters",
      "internal.identification_invocations",
      "internal.initial_analysis_lifecycle_fences",
    ]
  ) {
    for (const timing of ["BEFORE", "AFTER"]) {
      for (const level of ["STATEMENT", "ROW"]) {
        const action = "INSERT OR UPDATE OR DELETE" +
          (timing === "BEFORE" && level === "STATEMENT" ? " OR TRUNCATE" : "");
        expected.push(
          `s0_dispatch_${level.toLowerCase()}_${timing.toLowerCase()}|${timing}|${action}|${relation}|${level}|dispatch`,
        );
      }
    }
  }
  assertEquals(observers.sort(), expected.sort());
  assertEquals(
    [...source.matchAll(
      /EXECUTE FUNCTION internal\.guard_initial_consuming_member\s*\(/g,
    )].length,
    expected.length,
    "No unclassified consuming observer is permitted",
  );
  assertEquals(
    /GRANT\s+(?:ALL|INSERT|UPDATE|DELETE|SELECT|EXECUTE)\b/i.test(source),
    false,
  );
  assertEquals(
    source.includes(
      "DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.require_complete_initial_consuming_stage()",
    ),
    true,
  );
});

Deno.test("S0 retention preserves the row-first five-minute accounting loop", async () => {
  const source = await Deno.readTextFile(
    new URL(
      "../migrations/20261103074331_consume_initial_analysis.sql",
      import.meta.url,
    ),
  );
  const original = await Deno.readTextFile(
    new URL(
      "../migrations/20260927230801_account_identification_invocations.sql",
      import.meta.url,
    ),
  );
  const loop = (value: string) =>
    value.match(
      /FOR pending IN SELECT id FROM internal\.identification_invocations[\s\S]*?END LOOP;/,
    )?.[0];
  assertEquals(loop(source), loop(original));
  assertEquals(loop(source) !== undefined, true);
  const writer = source.slice(
    source.indexOf(
      "CREATE OR REPLACE FUNCTION internal.complete_identification_usage(",
    ),
    source.indexOf("-- Report observers"),
  );
  const rowLock = writer.indexOf("WHERE id=p_invocation_id FOR UPDATE");
  const replay = writer.indexOf(
    "IF invocation.event_id IS NOT NULL THEN RETURN invocation.event_id; END IF;",
  );
  const prepare = writer.indexOf(
    "internal.prepare_identification_usage_event(invocation,p_outcome,p_usage)",
  );
  const attach = writer.indexOf(
    "internal.attach_initial_report_candidate(invocation,event_candidate)",
  );
  const insert = writer.indexOf(
    "INSERT INTO public.ai_usage_events SELECT (event_candidate).*",
  );
  assertEquals(
    rowLock >= 0 && rowLock < replay && replay < prepare && prepare < attach &&
      attach < insert,
    true,
  );
  assertEquals(
    [...writer.matchAll(/internal\.prepare_identification_usage_event\(/g)]
      .length,
    1,
  );
  assertEquals(
    /initial_preparation|initial_analysis_admissions|public\.users|initial_analysis_submissions/
      .test(writer),
    false,
  );
  assertEquals(
    writer.includes("ON CONFLICT (source_type,source_id,operation) DO NOTHING"),
    true,
  );
  assertEquals(
    writer.includes(
      "UPDATE internal.identification_invocations SET event_id=event_uuid",
    ),
    true,
  );
  const fenceLock = source.indexOf(
    "LOCK TABLE internal.initial_analysis_operation_fences IN SHARE MODE",
  );
  const invocationLock = source.indexOf(
    "LOCK TABLE internal.identification_invocations IN ACCESS EXCLUSIVE MODE NOWAIT",
  );
  assertEquals(
    fenceLock >= 0 && fenceLock < invocationLock &&
      invocationLock < source.indexOf("DO $preflight$"),
    true,
  );
  assertEquals(
    source.indexOf("DO $preflight$") <
      source.indexOf("ADD COLUMN is_initial_analysis"),
    true,
  );
  assertEquals(
    /initial_admission_receipt_id UUID\s+REFERENCES/.test(source),
    false,
  );
  const guard = source.slice(
    source.indexOf(
      "CREATE FUNCTION internal.guard_initial_invocation_authority()",
    ),
    source.indexOf(
      "REVOKE ALL ON FUNCTION internal.guard_initial_invocation_authority()",
    ),
  );
  const accountingBranch = guard.slice(
    guard.indexOf(
      "IF OLD.is_initial_analysis THEN",
      guard.indexOf("IF NEW.is_initial_analysis IS DISTINCT"),
    ),
  );
  assertEquals(
    /\b(?:SELECT|PERFORM|FOR UPDATE|FOR SHARE)\b/.test(accountingBranch),
    false,
  );
});

Deno.test("S0 classification installs atomically in statement-at-a-time replay", async () => {
  const source = await Deno.readTextFile(
    new URL(
      "../migrations/20261103074331_consume_initial_analysis.sql",
      import.meta.url,
    ),
  );
  const open = "DO $s0_migration$\nBEGIN\n EXECUTE $s0_statements$";
  const close = "$s0_statements$;\nEND;\n$s0_migration$;";
  const start = source.indexOf(open);
  const end = source.indexOf(close);
  assertEquals(start >= 0 && end > start, true);
  for (
    const member of [
      "LOCK TABLE internal.initial_analysis_operation_fences IN SHARE MODE",
      "LOCK TABLE internal.identification_invocations IN ACCESS EXCLUSIVE MODE NOWAIT",
      "ADD COLUMN is_initial_analysis",
      "CREATE TRIGGER a00_initial_invocation_authority_truncate",
    ]
  ) {
    assertEquals(
      source.indexOf(member) > start && source.indexOf(member) < end,
      true,
    );
  }
  assertEquals(source.indexOf("SET statement_timeout") < start, true);
  assertEquals(source.indexOf("RESET statement_timeout") > end, true);
});
