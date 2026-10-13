import { assertEquals } from "@std/assert";
import schema from "../_shared/initialAnalysis/admission-recovery-response-schema-v2.json" with {
  type: "json",
};
import vectors from "../_shared/initialAnalysis/fixtures/admission-recovery-response-v2.json" with {
  type: "json",
};

Deno.test("recovery response: SQL schema and full positive/negative vectors match Deno", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261012041337_prepare_initial_atomic_admission.sql",
      import.meta.url,
    ),
  );
  const tests = await Deno.readTextFile(
    new URL(
      "../../tests/initial_admission_recovery_response.sql",
      import.meta.url,
    ),
  );
  const declaration = sql.slice(
    sql.indexOf(
      "CREATE FUNCTION internal.initial_admission_recovery_response_schema()",
    ),
  );
  assertEquals(
    JSON.parse(declaration.match(/\$json\$(.*?)\$json\$/s)![1]),
    schema,
  );
  assertEquals(
    JSON.parse(tests.match(/\$schema\$(.*?)\$schema\$/s)![1]),
    schema,
  );
  assertEquals(
    JSON.parse(tests.match(/\$vectors\$(.*?)\$vectors\$/s)![1]),
    vectors,
  );
});

Deno.test("cancellation entry: private rollback-only staging grants no action authority", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261012041337_prepare_initial_atomic_admission.sql",
      import.meta.url,
    ),
  );
  const entry = sql.slice(
    sql.indexOf("CREATE TABLE internal.initial_admitted_cancellation_staging"),
    sql.indexOf(
      "CREATE FUNCTION internal.sample_initial_cancellation_quota_clock",
    ),
  );
  assertEquals(entry.includes("transaction_id XID8 NOT NULL UNIQUE"), true);
  assertEquals(
    entry.includes(
      "NEW.prestate:=internal.capture_initial_admitted_cancellation_prestate(NEW.owner_id,NEW.scan_id);",
    ),
    true,
  );
  assertEquals(entry.includes("DEFERRABLE INITIALLY DEFERRED"), true);
  assertEquals(
    entry.includes("FROM PUBLIC,anon,authenticated,service_role"),
    true,
  );
  assertEquals(
    /\bGRANT\b|CREATE FUNCTION public[.]|CREATE OR REPLACE/.test(entry),
    false,
  );
  assertEquals(
    /\bGRANT\b|CREATE (?:OR REPLACE )?FUNCTION public[.]/.test(
      sql.slice(
        sql.indexOf(
          "CREATE TABLE internal.initial_admitted_cancellation_staging",
        ),
      ),
    ),
    false,
  );
  assertEquals(
    /PERFORM internal[.](finalize_ai_quota|settle_complimentary|retire_initial)/
      .test(entry),
    false,
  );
});

Deno.test("private erasure leaves public action and deferred completion closed", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261012041337_prepare_initial_atomic_admission.sql",
      import.meta.url,
    ),
  );
  const erasure = sql.slice(
    sql.indexOf("CREATE TABLE internal.initial_cancellation_erasure_witness"),
    sql.indexOf(
      "-- C1 terminal consumption is one private integrated protocol.",
    ),
  );
  assertEquals(
    /\bGRANT\b|CREATE (?:OR REPLACE )?FUNCTION public[.]/.test(erasure),
    false,
  );
  assertEquals(
    erasure.includes(
      "PERFORM internal.erase_initial_cancellation_private_root",
    ),
    false,
  );
  assertEquals(
    erasure.includes("require_complete_initial_admitted_cancellation"),
    false,
  );
  assertEquals(
    erasure.includes("FROM PUBLIC,anon,authenticated,service_role"),
    true,
  );
});

Deno.test("cancellation quota: closed private witnesses leave action and commit fences intact", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261012041337_prepare_initial_atomic_admission.sql",
      import.meta.url,
    ),
  );
  const witness = sql.slice(
    sql.indexOf("CREATE TABLE internal.initial_cancellation_quota_statements"),
    sql.indexOf("CREATE TABLE internal.initial_cancellation_credit_witness"),
  );
  assertEquals(/\bGRANT\b|CREATE FUNCTION public[.]/.test(witness), false);
  assertEquals(witness.includes("NEW.expected:=contract.expected"), true);
  assertEquals(witness.includes("jsonb_array_length(expected)<=3"), true);
  assertEquals(witness.includes("ordinal BETWEEN 0 AND 7"), true);
  assertEquals(witness.includes("x.value=event"), true);
  assertEquals(witness.includes("TG_WHEN='AFTER'"), true);
  assertEquals(witness.includes("phase='consuming'"), false);
  assertEquals(witness.includes("initial_admitted_settlement_blocked"), false);
});

Deno.test("private cancellation receipt preserves deferred rejection and original public owner", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261012041337_prepare_initial_atomic_admission.sql",
      import.meta.url,
    ),
  );
  const receipt = sql.slice(
    sql.indexOf("CREATE TABLE internal.initial_cancellation_receipt_witness"),
    sql.indexOf(
      "-- C1 terminal consumption is one private integrated protocol.",
    ),
  );
  assertEquals(
    /\bGRANT\b|CREATE (?:OR REPLACE )?FUNCTION public[.]/.test(receipt),
    false,
  );
  assertEquals(
    receipt.includes("require_complete_initial_admitted_cancellation"),
    false,
  );
  assertEquals(receipt.includes("cancel_initial_analysis"), false);
  assertEquals(
    receipt.includes(
      "DELETE FROM internal.initial_admitted_cancellation_staging",
    ),
    false,
  );
  assertEquals(
    receipt.includes("FROM PUBLIC,anon,authenticated,service_role"),
    true,
  );
});

Deno.test("terminal snapshot capture preserves bounds and exposes no public action", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261012041337_prepare_initial_atomic_admission.sql",
      import.meta.url,
    ),
  );
  const snapshot = sql.slice(
    sql.indexOf(
      "CREATE FUNCTION internal.initial_cancellation_terminal_catalog()",
    ),
    sql.indexOf(
      "-- C1 terminal consumption is one private integrated protocol.",
    ),
  );
  assertEquals(
    /\bGRANT\b|CREATE (?:OR REPLACE )?FUNCTION public[.]/.test(snapshot),
    false,
  );
  assertEquals(
    snapshot.includes("require_complete_initial_admitted_cancellation"),
    false,
  );
  assertEquals(/DELETE FROM internal[.]initial_/.test(snapshot), false);
  assertEquals(
    snapshot.indexOf("IF estimated>134217728") <
      snapshot.indexOf("jsonb_agg(to_jsonb(t)"),
    true,
  );
  assertEquals(
    snapshot.includes("octet_length(result::TEXT) IS DISTINCT FROM estimated"),
    true,
  );
});

Deno.test("C1 private consumption uses DELETE OLD deferred proof and no direct public route", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261012041337_prepare_initial_atomic_admission.sql",
      import.meta.url,
    ),
  );
  const terminal = sql.slice(
    sql.indexOf(
      "-- C1 terminal consumption is one private integrated protocol.",
    ),
    sql.indexOf(
      "-- The generic admitted-settlement fence remains unconditional.",
    ),
  );
  assertEquals(
    /\bGRANT\b|CREATE (?:OR REPLACE )?FUNCTION public[.]/.test(terminal),
    false,
  );
  assertEquals(terminal.includes("cancel_initial_analysis("), false);
  assertEquals(
    terminal.includes(
      "AFTER INSERT OR DELETE\n    ON internal.initial_admitted_cancellation_staging",
    ),
    true,
  );
  assertEquals(
    terminal.includes(
      "require_complete_initial_cancellation_snapshot AFTER DELETE",
    ),
    true,
  );
  assertEquals(
    terminal.includes(
      "assert_initial_cancellation_terminal_survivors(OLD.proof)",
    ),
    true,
  );
  assertEquals(terminal.includes("pg_try_advisory_xact_lock(1128353347"), true);
  assertEquals(
    terminal.includes(
      "FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cancellation_seal()",
    ),
    true,
  );
  assertEquals(terminal.includes("jsonb_agg"), false);
});

Deno.test("explicit C1 preserves the generic owner and requires proof before settlement", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261012041337_prepare_initial_atomic_admission.sql",
      import.meta.url,
    ),
  );
  const explicit = sql.slice(sql.indexOf(
    "-- The generic admitted-settlement fence remains unconditional.",
  ));
  // The fixed explicit wrapper may change its private target, but neither
  // generic account erasure nor the shared detection predicate may be relaxed.
  assertEquals(
    /\bGRANT\b|initial_analysis_lifecycle_enabled\s*=\s*TRUE/i.test(explicit),
    false,
  );
  assertEquals(
    /CREATE (?:OR REPLACE )?FUNCTION internal[.](?:cancel_initial_analysis|initial_admitted_settlement_blocked)\(/
      .test(explicit),
    false,
  );
  assertEquals(
    explicit.includes(
      "REVOKE ALL ON FUNCTION internal.cancel_initial_analysis_explicit(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role",
    ),
    true,
  );
  assertEquals(
    explicit.includes(
      "SECURITY DEFINER SET search_path='' SET statement_timeout='10s'",
    ),
    true,
  );
  const owner = explicit.slice(
    explicit.indexOf(
      "CREATE FUNCTION internal.cancel_initial_analysis_explicit",
    ),
    explicit.indexOf(
      "REVOKE ALL ON FUNCTION internal.cancel_initial_analysis_explicit",
    ),
  );
  assertEquals(/EXCEPTION\s+WHEN/i.test(owner), false);
  assertEquals(
    owner.indexOf("IF saved.scan_id IS NOT NULL") <
      owner.indexOf(
        "INSERT INTO internal.initial_admitted_cancellation_staging",
      ),
    true,
  );
  assertEquals(
    owner.indexOf(
      "INSERT INTO internal.initial_admitted_cancellation_staging",
    ) < owner.indexOf("internal.finalize_ai_quota_reservation_core"),
    true,
  );
  assertEquals(
    explicit.includes(
      "pg_get_functiondef('public.cancel_initial_analysis(uuid,uuid)'::REGPROCEDURE)",
    ),
    true,
  );
  assertEquals(
    explicit.includes(
      "RETURN internal.cancel_initial_analysis_explicit(p_owner,p_scan);",
    ),
    true,
  );
});
