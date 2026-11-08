import { assert, assertEquals } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261006183134_prepare_protected_chat_no_admission.sql",
    import.meta.url,
  ),
);
Deno.test("chat no-admission seal proves only exact stale-ticket denial under writer locks", () => {
  const seal =
    sql.split("CREATE FUNCTION public.seal_unadmitted_insight_chat_request")[1];
  assert(
    seal.indexOf("lock_insight_chat_execution_subject") <
      seal.indexOf("insight_chat_execution_fingerprint"),
  );
  assert(
    seal.indexOf("pg_advisory_xact_lock") <
      seal.indexOf("SELECT f.* INTO STRICT"),
  );
  assert(
    seal.indexOf("denial:=fence.no_admission_reason") <
      seal.indexOf("chat_execution_enabled"),
  );
  assert(seal.includes("EXCEPTION WHEN SQLSTATE '40001'"));
  assert(
    seal.includes(
      "error_message IS DISTINCT FROM 'field_chat_context_conflict' THEN RAISE",
    ),
  );
  assert(seal.includes("internal.prepare_current_insight_chat_context"));
  assert(
    seal.includes("safety_metadata->>'request_id'=p_client_message_id::TEXT"),
  );
  assertEquals((seal.match(/INSERT INTO /g) || []).length, 2); // fence plus ACL inventory
  assert(!seal.includes("refund_ai"));
  assert(!seal.includes("INSERT INTO public.insight_chat_messages"));
});
Deno.test("chat seal prevents every admitted path from rebinding a terminal request", () => {
  const quota = sql.split(
    "CREATE OR REPLACE FUNCTION internal.guard_insight_chat_execution_quota",
  )[1].split("CREATE FUNCTION internal.require_unsealed")[0];
  assert(!quota.includes("TG_OP='INSERT' AND f.client_message_id"));
  assert(
    quota.indexOf("fence.no_admission_reason IS NOT NULL") <
      quota.indexOf("fence.reservation_id IS NULL THEN"),
  );
  assert(
    sql.includes("NEW.no_admission_reason,NEW.no_admission_conversation_id"),
  );
  assert(
    sql.includes("no_admission_reason='displayed_identification_changed'"),
  );
  assert(sql.includes("AND message_id IS NULL AND NOT message_bound"));
  assert(
    sql.includes(
      "AND dispatch_grant_id IS NULL AND dispatch_granted_at IS NULL",
    ),
  );
  assert(
    sql.includes(
      "SELECT m.id INTO existing_id FROM public.insight_chat_messages m",
    ),
  );
  assert(sql.includes("protected_chat_seal_source_drift"));
});
Deno.test("chat no-admission grants only one exact service signature without activation", () => {
  assert(sql.includes("PERFORM internal.require_service_role()"));
  assert(sql.includes("SET search_path='' SET statement_timeout='5s'"));
  assert(!sql.includes("GRANT EXECUTE ON FUNCTION internal."));
  assert(!sql.includes("chat_execution_enabled=TRUE"));
  assertEquals(
    (sql.match(/GRANT EXECUTE ON FUNCTION public\./g) || []).length,
    1,
  );
});

const recovery = await Deno.readTextFile(
  new URL(
    "../../migrations/20261006190021_prepare_chat_no_admission_recovery.sql",
    import.meta.url,
  ),
);
Deno.test("no-admission recovery locks original owner and request without admission or fresh gates", () => {
  const routine =
    recovery.split("CREATE FUNCTION public.get_insight_chat_no_admission")[1]
      .split("REVOKE ALL")[0];
  assert(
    routine.indexOf("lock_insight_chat_execution_subject") <
      routine.indexOf("insight_chat_execution_fingerprint"),
  );
  assert(
    routine.indexOf("pg_advisory_xact_lock") <
      routine.indexOf("SELECT f.* INTO STRICT"),
  );
  assert(routine.includes("WHEN too_many_rows THEN RETURN"));
  assert(routine.includes("no_admission_conversation_id<>p_conversation_id"));
  assert(
    routine.includes(
      "safety_metadata->>'request_id'=p_client_message_id::TEXT",
    ),
  );
  assert(!routine.includes("INSERT INTO"));
  assert(!routine.includes("prepare_current_insight_chat_context"));
  assert(!routine.includes("chat_execution_enabled"));
  assert(!routine.includes("chat_context_enabled"));
  assert(recovery.includes("SET search_path='' SET statement_timeout='5s'"));
});
