import { fetchWithDeadline } from "../functions/_shared/outbound.ts";
import { evaluateAutomaticProductionRelease } from "./verify_production_release_holds.ts";
import { GitHubReleaseEvidenceVerifier } from "./github_release_evidence.ts";
import postgres, { type Sql } from "npm:postgres@3.4.7";
import {
  GEMINI_RELEASE_GATES,
  type GeminiReleaseConfiguration,
  type GeminiReleaseManifest,
  parseGeminiReleaseManifest,
  verifyGeminiReleaseSource,
} from "./gemini_release_contract.ts";
import { serviceRoleRequestHeaders } from "../functions/_shared/serviceRoleAuth.ts";

export async function verifyGeminiServingIdentities(
  target: string,
  key: string,
  identities: Record<string, string>,
): Promise<void> {
  for (const [name, digest] of Object.entries(identities)) {
    const response = await fetchWithDeadline(
      `https://${target}.supabase.co/functions/v1/${name}`,
      {
        method: "HEAD",
        redirect: "error",
        headers: {
          ...serviceRoleRequestHeaders(key),
          "X-Merian-Release-Identity": "1",
        },
      },
      { timeoutMs: 15000 },
    );
    if (
      response.status !== 204 ||
      response.headers.get("X-Merian-Gemini-Contract") !== "generation3_v1" ||
      response.headers.get("X-Merian-Gemini-Bundle-SHA256") !== digest
    ) throw new Error(`gemini_serving_identity_mismatch:${name}`);
  }
}
async function currentRelease(sql: Sql, m: GeminiReleaseManifest) {
  const rows =
    await sql`SELECT r.status,r.activated_revision,h.revision,v.status AS routing_status,v.configuration_digest
 FROM internal.gemini_activation_releases r CROSS JOIN internal.gemini_routing_head h
 JOIN internal.gemini_routing_revisions v ON v.revision=h.revision WHERE r.id=${m.release_id}::uuid`;
  return rows[0];
}
async function verifyRouting(
  sql: Sql,
  m: GeminiReleaseManifest,
  c: GeminiReleaseConfiguration,
  revision: string,
) {
  const row = await currentRelease(sql, m);
  if (
    !row || String(row.revision) !== revision ||
    String(row.activated_revision) !== revision || row.status !== "activated" ||
    row.routing_status !== "active" ||
    row.configuration_digest !== m.configuration_digest
  ) throw new Error("gemini_active_routing_mismatch");
  const state =
    await sql`SELECT internal.gemini_assignment_manifest() AS assignments,internal.gemini_independent_holds() AS holds,
 (SELECT verification->'independent_holds' FROM internal.gemini_activation_releases WHERE id=${m.release_id}::uuid) AS expected_holds`;
  if (
    JSON.stringify(state[0].holds) !== JSON.stringify(state[0].expected_holds)
  ) throw new Error("gemini_independent_holds_changed");
  const original = c.assignments as {
    policy: Record<string, unknown>;
    bindings: Record<string, unknown>[];
  }[];
  const active = state[0].assignments as typeof original;
  if (active.length !== original.length) {
    throw new Error("gemini_assignment_count_changed");
  }
  for (let n = 0; n < original.length; n++) {
    const prior = original[n], actual = active[n];
    const switched = prior.policy.allowed === true &&
      String(prior.policy.model).startsWith("gemini-");
    const identify = ["scan_identification", "scan_audio_identification"]
      .includes(String(prior.policy.operation));
    const expected = {
      ...prior.policy,
      ...(switched
        ? {
          model: identify ? "gemini-3.8-flash" : "gemini-3.5-flash-lite",
          policy_version: Number(prior.policy.policy_version) + 1,
        }
        : {}),
    };
    if (JSON.stringify(expected) !== JSON.stringify(actual.policy)) {
      throw new Error("gemini_policy_verification_failed");
    }
    if (
      switched && identify &&
      (actual.bindings.length !== prior.bindings.length ||
        actual.bindings.some((b) =>
          b.minimum_identification_protocol !== 7 ||
          b.provider_model !== "gemini-3.8-flash" ||
          b.binding !== "gemini_generation3_v1"
        ))
    ) throw new Error("gemini_protocol_verification_failed");
  }
  // Read-only capability assertions: no user quota or provider call is acquired.
  await sql`DO $check$ BEGIN
 IF internal.require_identification_capability('00000000-0000-4000-8000-000000000001','scan_identification','00000000-0000-4000-8000-000000000002','multimodal_text_v1',7,FALSE,7)<>7 THEN RAISE EXCEPTION 'gemini_protocol_verification_failed'; END IF;
 BEGIN
 PERFORM internal.require_identification_capability('00000000-0000-4000-8000-000000000001','scan_identification','00000000-0000-4000-8000-000000000002','multimodal_text_v1',6,FALSE,7);
 RAISE EXCEPTION 'gemini_old_protocol_unexpectedly_accepted' USING ERRCODE='55000';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'client_update_required' THEN RAISE; END IF;
 END;
 END $check$`;
}
export async function runGeminiActivationRelease(
  sql: Sql,
  m: GeminiReleaseManifest,
  c: GeminiReleaseConfiguration,
  key: string,
  recheckEligibility: () => Promise<void>,
) {
  await recheckEligibility();
  const serialized = JSON.stringify(m);
  await sql`SELECT internal.register_gemini_release(${serialized})`;
  let state = await currentRelease(sql, m);
  let revision = state?.activated_revision === null
    ? null
    : state?.activated_revision === undefined
    ? null
    : String(state.activated_revision);
  if (revision === null) {
    await verifyGeminiServingIdentities(m.target, key, c.required_functions);
    for (const smoke of c.smoke_cases) {
      const existing =
        await sql`SELECT state FROM internal.gemini_release_smokes WHERE release_id=${m.release_id}::uuid AND case_id=${smoke.id}`;
      if (existing[0]?.state === "passed") continue;
      if (existing[0]?.state !== "ready") {
        throw new Error("gemini_smoke_incomplete_or_uncertain");
      }
      // Never retry this fetch. A lost response is recovered from its durable receipt.
      const response = await fetchWithDeadline(
        `https://${m.target}.supabase.co/functions/v1/gemini-release-smoke`,
        {
          method: "POST",
          redirect: "error",
          headers: {
            ...serviceRoleRequestHeaders(key),
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ release_id: m.release_id, case_id: smoke.id }),
        },
        { timeoutMs: 120000 },
      );
      if (!response.ok) throw new Error("gemini_smoke_failed");
      await response.body?.cancel();
      const outcome =
        await sql`SELECT state,settlement FROM internal.gemini_release_smokes WHERE release_id=${m.release_id}::uuid AND case_id=${smoke.id}`;
      if (
        outcome[0]?.state !== "passed" || outcome[0]?.settlement !== "settled"
      ) throw new Error("gemini_smoke_evidence_incomplete");
    }
    await verifyGeminiServingIdentities(m.target, key, c.required_functions);
    await recheckEligibility();
    await sql`SELECT internal.verify_gemini_release(${m.release_id}::uuid,${
      sql.json(c.required_functions)
    },${sql.json(GEMINI_RELEASE_GATES)})`;
    // A lost activation acknowledgement is resolved by reading its exact release.
    try {
      const result =
        await sql`SELECT internal.activate_gemini_release(${m.release_id}::uuid,${m.target},${m.backend_sha},${m.configuration_digest},${
          sql.json(c.required_functions)
        },${sql.json(GEMINI_RELEASE_GATES)}) AS revision`;
      revision = String(result[0].revision);
    } catch (error) {
      state = await currentRelease(sql, m);
      if (
        state?.activated_revision === null ||
        state?.activated_revision === undefined
      ) throw error;
      revision = String(state.activated_revision);
    }
  }
  try {
    await verifyGeminiServingIdentities(m.target, key, c.required_functions);
    await verifyRouting(sql, m, c, revision);
    await sql`INSERT INTO internal.gemini_release_events(release_id,revision,kind,evidence)
   SELECT ${m.release_id}::uuid,${revision}::bigint,'verification_passed',${
      sql.json({
        configuration_digest: m.configuration_digest,
        required_functions: c.required_functions,
      })
    }
   WHERE NOT EXISTS(SELECT 1 FROM internal.gemini_release_events WHERE release_id=${m.release_id}::uuid AND kind='verification_passed')`;
  } catch (error) {
    // Revision-fenced protective action is part of this release authorization.
    // A newer revision fails closed without being suspended by this old release.
    await sql`SELECT internal.suspend_gemini_release(${m.release_id}::uuid,${revision}::bigint,${m.configuration_digest},'{"reason":"post_activation_verification_failed"}'::jsonb)`;
    throw error;
  }
  return {
    release_id: m.release_id,
    revision,
    configuration_digest: m.configuration_digest,
    status: "verified_active",
    quality: "unmeasured",
  };
}
if (import.meta.main) {
  const m = parseGeminiReleaseManifest(
    Deno.env.get("GEMINI_ACTIVATION_RELEASE") ?? "",
  );
  if (
    Deno.env.get("GITHUB_EVENT_NAME") !== "workflow_dispatch" ||
    Deno.env.get("GITHUB_REF") !== "refs/heads/main" ||
    Deno.env.get("GITHUB_SHA") !== m.backend_sha ||
    Deno.env.get("PROJECT_ID") !== m.target ||
    Deno.env.get("GEMINI_REQUIRED_GATES_COMPLETE") !== "true"
  ) throw new Error("gemini_release_authorization_context_invalid");
  const c = await verifyGeminiReleaseSource(m);
  const url = Deno.env.get("MERIAN_DATABASE_URL"),
    key = Deno.env.get("SUPABASE_SERVER_API_KEY");
  if (!url || !key) throw new Error("gemini_release_credentials_missing");
  const sql = postgres(url, {
    max: 1,
    connect_timeout: 10,
    idle_timeout: 2,
    max_lifetime: 30,
  });
  try {
    console.log(
      JSON.stringify(
        await runGeminiActivationRelease(sql, m, c, key, async () => {
          for (
            const [args, expected] of [
              [["rev-parse", "HEAD"], m.backend_sha],
              [
                ["ls-remote", "origin", "refs/heads/main"],
                `${m.backend_sha}\trefs/heads/main`,
              ],
              [["status", "--porcelain"], ""],
            ] as const
          ) {
            const result = await new Deno.Command("git", {
              args: [...args],
              stdout: "piped",
              stderr: "null",
            }).output();
            if (
              !result.success ||
              new TextDecoder().decode(result.stdout).trim() !== expected
            ) throw new Error("gemini_release_source_stale");
          }
          if (
            Date.now() < Date.parse(m.window_start) ||
            Date.now() >= Date.parse(m.window_end)
          ) throw new Error("gemini_release_window_closed");
          await verifyGeminiReleaseSource(m);
          const decision = await evaluateAutomaticProductionRelease(
            new URL("../release-holds.json", import.meta.url),
            m.backend_sha,
            Deno.readTextFile,
            new GitHubReleaseEvidenceVerifier({
              token: Deno.env.get("MERIAN_GITHUB_RELEASE_AUDIT_TOKEN") ?? "",
              repository: Deno.env.get("GITHUB_REPOSITORY") ?? "",
              branch: "main",
            }),
          );
          if (!decision.allowed) {
            throw new Error("gemini_release_mandatory_gate_closed");
          }
        }),
      ),
    );
  } finally {
    await sql.end();
  }
}
