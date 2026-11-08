import { assert, assertStringIncludes } from "@std/assert";

const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261104203743_recover_observation_enrollment_baseline.sql",
    import.meta.url,
  ),
);
const body = sql.split("AS $$")[1].split("$$;")[0];
Deno.test("baseline recovery keeps owner-first serialization and read-only authority", () => {
  const positions = [
    "FROM public.users",
    "pg_advisory_xact_lock",
    "FROM public.scans",
    "FROM internal.observation_histories",
    "FROM internal.observation_analysis_results",
  ].map((part) => body.indexOf(part));
  assert(
    positions.every((position, index) =>
      position >= 0 && (index === 0 || position > positions[index - 1])
    ),
  );
  assert(
    !/\b(INSERT|UPDATE|DELETE|MERGE|enroll_owned_observation_history)\b/i.test(
      body,
    ),
  );
  assertStringIncludes(body, "scan.user_id=caller AND NOT scan.is_tombstoned");
  assertStringIncludes(body, "internal.scan_deletion_tombstones");
  assertStringIncludes(body, "reader_enabled AND state_reader_enabled");
});
Deno.test("baseline recovery exposes only authenticated bounded immutable V3 evidence", () => {
  assertStringIncludes(sql, "SECURITY DEFINER SET search_path = ''");
  assertStringIncludes(sql, "FROM PUBLIC,anon,authenticated,service_role;");
  assertStringIncludes(
    sql,
    "GRANT EXECUTE ON FUNCTION public.get_owned_observation_enrollment_baseline(JSONB,INTEGER) TO authenticated;",
  );
  assertStringIncludes(
    body,
    "ordinal=1 AND evidence_manifest->'schema_version'='3'::JSONB",
  );
  assertStringIncludes(body, "pg_catalog.octet_length(snapshot)>1048576");
  assertStringIncludes(body, "pg_catalog.octet_length(response::TEXT)>4194304");
  assertStringIncludes(
    body,
    "merian.observation-history.enrollment-baseline.v1",
  );
  assert(!/SET\s+(reader_enabled|state_reader_enabled)\s*=\s*TRUE/i.test(sql));
});
