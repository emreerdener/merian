import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260724192124_harden_json_endpoints_and_waitlist.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("waitlist migration bounds storage and keeps the RPC service-only", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "ADD CONSTRAINT beta_waitlist_signups_email_shape_check",
      "pg_catalog.CHAR_LENGTH(email) BETWEEN 3 AND 254",
      "ADD CONSTRAINT beta_waitlist_signups_source_shape_check",
      "ADD CONSTRAINT beta_waitlist_signups_user_agent_shape_check",
      "pg_catalog.CHAR_LENGTH(user_agent) BETWEEN 1 AND 512",
      "REVOKE ALL ON TABLE public.beta_waitlist_signups FROM PUBLIC, anon, authenticated, service_role",
      "CREATE TABLE internal.beta_waitlist_rate_counters",
      "ALTER TABLE internal.beta_waitlist_rate_counters ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.beta_waitlist_rate_counters FROM PUBLIC, anon, authenticated, service_role",
      "CREATE OR REPLACE FUNCTION public.claim_beta_waitlist_challenge_attempt",
      "VALUES ( 'challenge_ip_10m', p_ip_hash, ten_minute_window",
      "VALUES ( 'challenge_ip_day', p_ip_hash, day_window",
      "RAISE EXCEPTION 'waitlist_challenge_rate_limited'",
      "GRANT EXECUTE ON FUNCTION public.claim_beta_waitlist_challenge_attempt(TEXT) TO service_role",
      "'public.claim_beta_waitlist_challenge_attempt(text)'",
      "CREATE OR REPLACE FUNCTION public.submit_beta_waitlist_signup",
      "SECURITY DEFINER SET search_path = '' SET lock_timeout = '2s'",
      "PERFORM internal.require_service_role()",
      "WHERE counters.request_count < 5",
      "WHERE counters.request_count < 20",
      "WHERE counters.request_count < 2000",
      "RAISE EXCEPTION 'waitlist_ip_rate_limited'",
      "RAISE EXCEPTION 'waitlist_global_rate_limited'",
      "GRANT EXECUTE ON FUNCTION public.submit_beta_waitlist_signup( TEXT, TEXT, TEXT, TEXT ) TO service_role",
      "'public.submit_beta_waitlist_signup(text,text,text,text)'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.submit_beta_waitlist_signup( TEXT, TEXT, TEXT, TEXT ) TO anon",
    ),
  );
  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.submit_beta_waitlist_signup( TEXT, TEXT, TEXT, TEXT ) TO authenticated",
    ),
  );
  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.claim_beta_waitlist_challenge_attempt(TEXT) TO anon",
    ),
  );
  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.claim_beta_waitlist_challenge_attempt(TEXT) TO authenticated",
    ),
  );
  assert(
    sql.match(/FOR UPDATE SKIP LOCKED/g)?.length === 2,
    "Both bounded cleanup paths must skip rows locked by concurrent requests.",
  );
});

Deno.test("waitlist challenge verification is protected by a distributed preflight", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));
  const functionStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.claim_beta_waitlist_challenge_attempt",
  );
  const functionEnd = sql.indexOf(
    "COMMENT ON FUNCTION public.claim_beta_waitlist_challenge_attempt",
    functionStart,
  );
  const body = sql.slice(functionStart, functionEnd);

  const tenMinuteCounter = body.indexOf(
    "VALUES ( 'challenge_ip_10m', p_ip_hash, ten_minute_window",
  );
  const dailyCounter = body.indexOf(
    "VALUES ( 'challenge_ip_day', p_ip_hash, day_window",
  );
  assert(
    tenMinuteCounter >= 0 &&
      tenMinuteCounter < dailyCounter &&
      body.includes("WHERE counters.request_count < 20") &&
      body.includes("WHERE counters.request_count < 100"),
    "The pre-Turnstile claim must atomically enforce both IP windows.",
  );
});

Deno.test("waitlist rate checks are transactional and ordered", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));
  const functionStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.submit_beta_waitlist_signup",
  );
  const functionEnd = sql.indexOf(
    "COMMENT ON FUNCTION public.submit_beta_waitlist_signup",
    functionStart,
  );
  const body = sql.slice(functionStart, functionEnd);

  const tenMinuteCounter = body.indexOf(
    "VALUES ('ip_10m', p_ip_hash, ten_minute_window",
  );
  const dailyCounter = body.indexOf(
    "VALUES ('ip_day', p_ip_hash, day_window",
  );
  const signupInsert = body.indexOf(
    "INSERT INTO public.beta_waitlist_signups",
  );
  const globalCounter = body.indexOf(
    "VALUES ('global_day', 'global', day_window",
  );

  assert(
    tenMinuteCounter >= 0 &&
      tenMinuteCounter < dailyCounter &&
      dailyCounter < signupInsert &&
      signupInsert < globalCounter,
    "Every verified attempt must consume IP budgets before a new row can consume the global growth budget.",
  );
  assertStringIncludes(body, "ON CONFLICT (email_normalized) DO NOTHING");
  assertStringIncludes(body, "GET DIAGNOSTICS inserted_count = ROW_COUNT");
});
