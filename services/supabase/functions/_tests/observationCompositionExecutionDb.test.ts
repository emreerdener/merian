import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import vectors from "../_shared/analysisHistory/fixtures/composition-request-v5.json" with {
  type: "json",
};
import {
  compositionRequestFingerprint as compositionFingerprint,
  focusedCompositionRequestDigest,
} from "../_shared/analysisHistory/compositionFingerprint.ts";
import { compositionCohortItems } from "../_shared/analysisHistory/compositionCohort.ts";
import { parseCompositionRequestStructure as parseCompositionAdmission } from "../_shared/analysisHistory/compositionAdmission.ts";
import { compositionExecutionProfile } from "../_shared/analysisHistory/compositionExecutionPolicy.ts";
import {
  compositionEvidenceIdentity,
  decodeCompositionEvidenceReceipt,
} from "../_shared/analysisHistory/compositionEvidence.ts";
import { buildCompositionDraft } from "../_shared/analysisHistory/compositionAdmission.ts";
import videoVectors from "../_shared/analysisHistory/fixtures/video-request-v4.json" with {
  type: "json",
};
import { videoSourceFingerprint } from "../_shared/analysisHistory/videoSourceFingerprint.ts";
import { sourceReservationFingerprint } from "../_shared/analysisHistory/sourceFingerprint.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
async function connect() {
  assert(
    url && ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
  );
  const db = new Client(url);
  await db.connect();
  return db;
}
async function fixture(db: Client, index: number, focused: boolean) {
  const sql = await Deno.readTextFile(
    new URL("../../tests/observation_source_reservation.sql", import.meta.url),
  );
  await db.queryArray(
    sql.slice(
      sql.indexOf("CREATE FUNCTION pg_temp.history_append_request"),
      sql.indexOf("SELECT extensions.ok(NOT source_reservation_enabled"),
    ),
  );
  await db.queryArray(
    "SELECT set_config('request.jwt.claim.role','service_role',false)",
  );
  let [owner, parent, source, child]: string[] = Array.from(
    { length: 4 },
    () => crypto.randomUUID(),
  );
  await db.queryArray("SELECT pg_temp.seed_history_append($1,$2)", [
    owner,
    parent,
  ]);
  await db.queryArray(
    "UPDATE internal.observation_history_rollout SET selection_enabled=true,append_enabled=true,source_reservation_enabled=true,source_discovery_enabled=true,composition_source_reservation_enabled=true,composition_source_recovery_enabled=true,composition_runtime_enabled=true,composition_evidence_enabled=true,media_enabled=true",
  );
  if (index === 0) {
    // Real imported V3 baseline followed by V6, for first-import reconciliation.
    await db.queryArray(
      "DELETE FROM internal.observation_histories WHERE observation_id=$1",
      [parent],
    );
    await db.queryArray(
      "UPDATE internal.observation_history_rollout SET enrollment_enabled=true,saved_import_enabled=true,reader_enabled=true,state_reader_enabled=true",
    );
    await db.queryArray("SELECT set_config('request.jwt.claim.sub',$1,true)", [
      owner,
    ]);
    const imported =
      (await db.queryObject<{ value: { baseline_analysis_id: string } }>(
        "SELECT public.enroll_owned_observation_history($1,9) value",
        [parent],
      )).rows[0].value;
    source = imported.baseline_analysis_id;
  } else {
    await db.queryArray(
      "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3))",
      [owner, parent, source],
    );
  }
  const input = {
    ...structuredClone(vectors.filter((v) => v.valid)[index].input),
    observation_id: parent,
    source_analysis_id: source,
    analysis_id: child,
  };
  if (focused) {
    input.schema_version = 6;
    input.evidence_manifest.schema_version = 6;
    for (const node of input.evidence_manifest.items) {
      if (node.kind === "image") {
        Object.assign(node, {
          focus_region: {
            x: 0.1,
            y: 0.2,
            width: 0.3,
            height: 0.4,
            source: "user_selection",
          },
        });
      }
    }
    input.request_digest = await focusedCompositionRequestDigest(input);
    await db.queryArray(
      "UPDATE internal.observation_history_rollout SET focused_composition_source_reservation_enabled=true,focused_composition_source_recovery_enabled=true,focused_composition_runtime_enabled=true,focused_composition_evidence_enabled=true,focused_composition_analysis_enabled=true,focused_composition_dispatch_enabled=true,focused_composition_orchestration_enabled=true",
    );
  }
  const reader = focused ? 15 : 14;
  const envelope = {
    schema_version: 3,
    input,
    fingerprint_version: focused ? 2 : 1,
    fingerprint: await compositionFingerprint(input),
  };
  await db.queryArray(
    "SELECT public.reserve_owned_observation_composition_source($1,$2::jsonb,$3)",
    [owner, JSON.stringify(envelope), reader],
  );
  const request = {
    ...await compositionEvidenceIdentity(input),
    items: compositionCohortItems(input),
  };
  return { owner, parent, source, child, input, request, reader, focused };
}
async function denied(db: Client, action: () => Promise<unknown>) {
  await db.queryArray("SAVEPOINT denied");
  await assertRejects(action);
  await db.queryArray("ROLLBACK TO SAVEPOINT denied");
}
async function allocate(
  db: Client,
  owner: string,
  request: unknown,
  reader = 14,
) {
  return (await db.queryObject<{ value: unknown }>(
    "SELECT public.reserve_owned_observation_composition_evidence($1,$2::jsonb,$3) value",
    [owner, JSON.stringify(request), reader],
  )).rows[0].value;
}
const encode = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value));

async function eligible(db: Client, owner: string, parent: string) {
  const sql = await Deno.readTextFile(
    new URL(
      "../../tests/observation_source_initial_admission.sql",
      import.meta.url,
    ),
  );
  await db.queryArray(
    sql.slice(
      sql.indexOf("CREATE FUNCTION pg_temp.seed_funded_history"),
      sql.indexOf("CREATE FUNCTION pg_temp.admission_input"),
    ).replace(
      "    PERFORM pg_temp.seed_history_append(owner_id,observation);",
      "",
    ).replaceAll(
      "pg_temp.seed_funded_history",
      "pg_temp.composition_eligibility",
    ),
  );
  await db.queryArray("SELECT pg_temp.composition_eligibility($1,$2)", [
    owner,
    parent,
  ]);
  await db.queryArray(
    "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
  );
}
async function successorChecks(
  db: Client,
  f: Awaited<ReturnType<typeof fixture>>,
  complete: boolean,
) {
  await db.queryArray(
    "UPDATE internal.observation_history_rollout SET video_source_reservation_enabled=true",
  );
  for (const version of [2, 4, 5, ...(f.focused ? [6] : [])]) {
    await db.queryArray("SAVEPOINT successor");
    const identity = {
      observation_id: f.parent,
      source_analysis_id: f.source,
      analysis_id: crypto.randomUUID(),
    };
    let input: Record<string, unknown>;
    if (version === 6) {
      input = { ...f.input, ...identity };
      input.request_digest = await focusedCompositionRequestDigest(input);
    } else if (version === 5) {
      input = {
        ...structuredClone(vectors.filter((v) => v.valid)[0].input),
        ...identity,
      };
    } else if (version === 4) input = { ...videoVectors[0].input, ...identity };
    else {input = {
        ...f.input,
        ...identity,
        schema_version: 2,
        identification_protocol: 6,
        history_protocol: 8,
        evidence_manifest: {
          schema_version: 2,
          items: [{
            kind: "image",
            media_id: crypto.randomUUID(),
            content_type: "image/jpeg",
            byte_count: 100,
            sha256: "a".repeat(64),
          }],
        },
      };}
    const fingerprint = await (version >= 5
      ? compositionFingerprint(input)
      : version === 4
      ? videoSourceFingerprint(input)
      : sourceReservationFingerprint(input));
    const envelope = {
      schema_version: version >= 5 ? 3 : version === 4 ? 2 : 1,
      input,
      fingerprint_version: version === 6 ? 2 : 1,
      fingerprint,
    };
    const routine = version >= 5
      ? "composition"
      : version === 4
      ? "video"
      : "analysis";
    const reply = (await db.queryObject<{ value: { state: string } }>(
      `SELECT public.reserve_owned_observation_${routine}_source($1,$2::jsonb,$3) value`,
      [
        f.owner,
        JSON.stringify(envelope),
        version === 6 ? 15 : version === 5 ? 14 : version === 4 ? 12 : 11,
      ],
    )).rows[0].value;
    assertEquals(
      reply.state,
      complete ? "reserved" : "held",
      `successor V${version}`,
    );
    await db.queryArray("ROLLBACK TO SAVEPOINT successor");
  }
}
async function readerChecks(
  db: Client,
  f: Awaited<ReturnType<typeof fixture>>,
) {
  await db.queryArray("SELECT set_config('request.jwt.claim.sub',$1,true)", [
    f.owner,
  ]);
  await db.queryArray(
    "UPDATE internal.observation_history_rollout SET reader_enabled=true",
  );
  await db.queryArray(
    "UPDATE internal.observation_history_rollout SET media_reader_enabled=true",
  );
  for (const item of compositionCohortItems(f.input)) {
    const receipt = (await db.queryObject<{ value: Record<string, unknown> }>(
      "SELECT public.resolve_owned_observation_media($1,$2,$3,$4,2) value",
      [f.owner, f.parent, f.child, item.media_id],
    )).rows[0].value;
    assertEquals(receipt.content_type, item.content_type);
    assertEquals(receipt.byte_count, item.byte_count);
    assertEquals(receipt.sha256, item.sha256);
  }
  await denied(
    db,
    () =>
      db.queryArray(
        "SELECT public.resolve_owned_observation_media($1,$2,$3,$4,1)",
        [f.owner, f.parent, f.child, crypto.randomUUID()],
      ),
  );
  const request = {
    schema_version: 1,
    observation_id: f.parent,
    before_ordinal: null,
    limit: 20,
  };
  const page = (reader: number, before: number | null = null) =>
    db.queryObject<{ value: { items: { snapshot: string }[] } }>(
      "SELECT public.get_owned_observation_analysis_page($1::jsonb,$2) value",
      [JSON.stringify({ ...request, before_ordinal: before }), reader],
    );
  const results = (await page(f.reader)).rows[0].value.items;
  assertEquals(results.length, 2);
  assertEquals(
    JSON.parse(results[0].snapshot).schema_version,
    f.focused ? 7 : 6,
  );
  for (const reader of [7, 8, 9, 10, 11, 13, ...(f.focused ? [14] : [])]) {
    await denied(db, () => page(reader));
    await denied(db, () => page(reader, 2));
  }
  await db.queryArray("SAVEPOINT actions");
  await db.queryArray(
    "UPDATE internal.observation_history_rollout SET state_reader_enabled=true,selection_enabled=true,selection_api_enabled=true,confirmation_api_enabled=true,confirmation_undo_api_enabled=true,rejection_api_enabled=true",
  );
  const revisions = async () =>
    (await db.queryObject<{ observation: number; review: number }>(
      "SELECT h.state_revision observation,a.review_revision review FROM internal.observation_histories h JOIN internal.observation_analysis_authorities a USING(observation_id) WHERE h.observation_id=$1 AND a.analysis_id=$2",
      [f.parent, f.child],
    )).rows[0];
  const action = async () => {
    const revision = await revisions();
    return {
      schema_version: 1,
      observation_id: f.parent,
      analysis_id: f.child,
      operation_id: crypto.randomUUID(),
      expected_observation_revision: revision.observation,
      expected_review_revision: revision.review,
    };
  };
  const select = await action();
  const selected = (await db.queryObject<{ value: { outcome: string } }>(
    `SELECT public.select_owned_observation_analysis($1::jsonb,${f.reader}) value`,
    [JSON.stringify(select)],
  )).rows[0].value;
  assertEquals(
    (selected as unknown as { selected_analysis_id: string })
      .selected_analysis_id,
    f.child,
  );
  const baseline = JSON.parse(results[1].snapshot);
  if (baseline.schema_version === 3) {
    const reconcile = { schema_version: 1, observation_id: f.parent };
    const pair = (await db.queryObject<
      {
        value: {
          baseline_state: { analysis: { snapshot: string } };
          selected_state: { analysis: { snapshot: string } };
        };
      }
    >(
      `SELECT public.get_owned_observation_enrollment_selection($1::jsonb,${f.reader}) value`,
      [JSON.stringify(reconcile)],
    )).rows[0].value;
    assertEquals(
      JSON.parse(pair.baseline_state.analysis.snapshot).schema_version,
      3,
    );
    assertEquals(
      JSON.parse(pair.selected_state.analysis.snapshot).schema_version,
      f.focused ? 7 : 6,
    );
    await denied(
      db,
      () =>
        db.queryArray(
          "SELECT public.get_owned_observation_enrollment_selection($1::jsonb,11)",
          [JSON.stringify(reconcile)],
        ),
    );
  }
  const confirmation = {
    ...await action(),
    action: "confirm_primary",
    scientific_name: null,
  };
  const prepared = (await db.queryObject<
    { value: { status: string; scientific_name: string } }
  >(
    `SELECT public.prepare_observation_analysis_confirmation($1,$2::jsonb,${f.reader}) value`,
    [f.owner, JSON.stringify(confirmation)],
  )).rows[0].value;
  assertEquals(prepared.status, "verify");
  const taxon = {
    scientific_name: prepared.scientific_name,
    gbif_taxon_key: 987699795,
    rank: "SPECIES",
    status: "ACCEPTED",
    kingdom: "Plantae",
  };
  const confirmed =
    (await db.queryObject<{ value: { receipt: { outcome: string } } }>(
      `SELECT public.complete_observation_analysis_confirmation($1,$2::jsonb,${f.reader},$3,$4::jsonb) value`,
      [
        f.owner,
        JSON.stringify(confirmation),
        prepared.scientific_name,
        JSON.stringify(taxon),
      ],
    )).rows[0].value;
  assertEquals(confirmed.receipt.outcome, "applied");
  const undo = {
    ...await action(),
    action: "undo_confirmation",
    undo_operation_id: confirmation.operation_id,
  };
  const undone = (await db.queryObject<{ value: { outcome: string } }>(
    `SELECT public.review_owned_observation_analysis($1::jsonb,${f.reader}) value`,
    [JSON.stringify(undo)],
  )).rows[0].value;
  assertEquals(undone.outcome, "applied");
  await db.queryArray("ROLLBACK TO SAVEPOINT actions");
  await db.queryArray(
    `SELECT internal.require_observation_action_reader($1,${f.reader},NULL)`,
    [f.parent],
  );
  await denied(
    db,
    () =>
      db.queryArray(
        `SELECT internal.require_observation_action_reader($1,${f.reader},$2)`,
        [f.parent, f.child],
      ),
  );
}
for (const focused of [false, true]) {
  for (const [index, vector] of vectors.filter((v) => v.valid).entries()) {
    for (const kind of ["draft", "refusal", "invalid_output"] as const) {
      Deno.test({
        name: `composition V${
          focused ? 6 : 5
        } actual execution and settlement ${vector.name} ${kind}`,
        ignore: !url,
        async fn() {
          const db = await connect();
          await db.queryArray("BEGIN");
          try {
            const f = await fixture(db, index, focused);
            const call = async (name: string, extra: unknown[] = []) =>
              (await db.queryObject<{ value: Record<string, unknown> }>(
                `SELECT internal.${name}($1,$2,$3${
                  extra.map((_, n) => `,$${n + 4}`).join("")
                }) value`,
                [f.owner, f.parent, f.child, ...extra],
              )).rows[0].value;
            const admit = async () =>
              (await db.queryObject<{ value: Record<string, unknown> }>(
                "SELECT internal.admit_composition_observation_analysis($1::uuid,$2::jsonb,encode(extensions.digest($1::text,'sha256'),'hex')) value",
                [f.owner, JSON.stringify(f.input)],
              )).rows[0].value;
            await denied(db, admit);
            const receipt = await decodeCompositionEvidenceReceipt(
              encode(await allocate(db, f.owner, f.request, f.reader)),
              f.input,
              f.owner,
            );
            for (const item of receipt.items) {
              await db.queryArray(
                `SELECT public.complete_owned_observation_composition_evidence($1,$2::jsonb,$3,$4,${f.reader})`,
                [
                  f.owner,
                  JSON.stringify(f.request),
                  item.media_id,
                  item.object_id,
                ],
              );
            }
            await eligible(db, f.owner, f.parent);
            await db.queryArray(
              "UPDATE internal.observation_history_rollout SET admission_enabled=true,protected_analysis_enabled=true",
            );
            await denied(db, admit);
            await db.queryArray(
              "UPDATE internal.observation_history_rollout SET composition_analysis_enabled=true",
            );
            const funded = await admit();
            assertEquals(funded.state, "admitted");
            assertEquals(await admit(), funded);
            const quota = funded.quota as Record<string, unknown>;
            const policy = compositionExecutionProfile(
              parseCompositionAdmission(f.input),
            );
            assertEquals(quota.input_profile, policy.profile);
            await denied(
              db,
              () => call("claim_composition_observation_analysis"),
            );
            await db.queryArray(
              "UPDATE internal.observation_history_rollout SET composition_dispatch_enabled=true,dispatch_enabled=true,source_dispatch_enabled=true,source_completion_release_enabled=true",
            );
            // Exercise the actual service entry before continuing the private-owner
            // settlement probes. Rollback preserves the same unclaimed candidate.
            const begin = async () =>
              (await db.queryObject<{ value: Record<string, unknown> }>(
                "SELECT public.begin_owned_observation_composition_analysis($1::uuid,$2::jsonb,encode(extensions.digest($1::text,'sha256'),'hex')) value",
                [f.owner, JSON.stringify(f.input)],
              )).rows[0].value;
            await denied(db, begin);
            assertEquals(
              (await db.queryObject<{ value: unknown }>(
                "SELECT public.list_observation_composition_analysis_recovery() value",
              )).rows[0].value,
              [],
            );
            assertEquals(
              (await db.queryObject<{ value: unknown }>(
                "SELECT public.list_observation_video_analysis_recovery() value",
              )).rows[0].value,
              [],
            );
            await db.queryArray("SAVEPOINT public_entry");
            await db.queryArray(
              "UPDATE internal.observation_history_rollout SET orchestration_enabled=true,composition_orchestration_enabled=true",
            );
            const publicClaim = await begin();
            assertEquals(publicClaim.claimed, true);
            assertEquals((await begin()).claimed, false);
            const materialized =
              (await db.queryObject<{ value: { state: string } }>(
                "SELECT public.advance_owned_observation_composition_analysis($1,$2,$3,$4,'materialize','{}') value",
                [f.owner, f.parent, f.child, publicClaim.work_token],
              )).rows[0].value;
            assertEquals(materialized.state, "ready");
            await db.queryArray("ROLLBACK TO SAVEPOINT public_entry");
            const claim = await call("claim_composition_observation_analysis");
            assertEquals(claim.claimed, true);
            assertEquals(
              (await call("claim_composition_observation_analysis")).claimed,
              false,
            );
            await denied(db, () => call("claim_observation_analysis"));
            const provenance = {
              version: 1,
              provider: quota.provider,
              binding: quota.binding,
              model: quota.model,
              variant: "multimodal",
              operation: "scan_identification",
              policy_version: quota.policy_version,
              prompt: policy.prompt,
              schema: "merian_identify_primary_v1",
              confidence: "unqualified",
              diagnostic_trigger: null,
              prompt_diagnostic_trigger: null,
              safety: null,
              timeout_ms: 90000,
              generation: {
                temperature: 0.1,
                seed: null,
                top_k: null,
                max_output_tokens: 8192,
                thinking_budget: 1024,
              },
            };
            await denied(
              db,
              () =>
                call("dispatch_composition_observation_analysis", [
                  crypto.randomUUID(),
                  JSON.stringify(provenance),
                ]),
            );
            assertEquals(
              (await call("dispatch_composition_observation_analysis", [
                claim.work_token,
                JSON.stringify(provenance),
              ])).may_dispatch,
              true,
            );
            assertEquals(
              (await call("dispatch_composition_observation_analysis", [
                claim.work_token,
                JSON.stringify(provenance),
              ])).may_dispatch,
              false,
            );
            await db.queryArray(
              "UPDATE internal.observation_analysis_intents SET work_expires_at=clock_timestamp()-interval '1 second' WHERE analysis_id=$1",
              [f.child],
            );
            assertEquals(
              (await call("claim_composition_observation_analysis")).claimed,
              false,
            );
            const page = JSON.parse(
              await Deno.readTextFile(
                new URL(
                  "../_shared/analysisHistory/fixtures/page-v1.json",
                  import.meta.url,
                ),
              ),
            );
            const result = {
              ...JSON.parse(page.items[0].snapshot).result,
              scan_id: f.parent,
              identification_provenance: provenance,
              primary_identification: {
                version: 1,
                resolution: "species",
                scientific_name:
                  JSON.parse(page.items[0].snapshot).result.scientific_name,
                common_name:
                  JSON.parse(page.items[0].snapshot).result.common_name,
              },
            };
            const species =
              (await db.queryObject<{ id: string; scientific_name: string }>(
                "INSERT INTO public.species_dictionary(scientific_name,common_names,gbif_taxon_key) VALUES($1,'{}',987699795) ON CONFLICT(scientific_name) DO UPDATE SET gbif_taxon_key=EXCLUDED.gbif_taxon_key RETURNING id,scientific_name",
                [result.scientific_name],
              )).rows[0];
            const draft = buildCompositionDraft(
              JSON.stringify(f.input),
              result,
              species,
            );
            const { species_id: _species, ...canonical } =
              draft.result_snapshot;
            const outcome = {
              schema_version: 1,
              provenance,
              outcome: kind === "draft"
                ? { kind, result: canonical }
                : { kind },
              usage: {},
            };
            await denied(
              db,
              () =>
                call("record_composition_observation_outcome", [
                  crypto.randomUUID(),
                  JSON.stringify(outcome),
                ]),
            );
            await call("record_composition_observation_outcome", [
              quota.lease_token,
              JSON.stringify(outcome),
            ]);
            await call("record_composition_observation_outcome", [
              quota.lease_token,
              JSON.stringify(outcome),
            ]);
            await denied(
              db,
              () =>
                call("record_composition_observation_outcome", [
                  quota.lease_token,
                  JSON.stringify({ ...outcome, usage: { input_tokens: 123 } }),
                ]),
            );
            if (f.focused) {
              // A rollout rollback blocks new attempts, never recovery of an
              // admitted outcome. Exercise the public recovery owner with all
              // focused feature flags disabled, then restore this fixture.
              await db.queryArray("SAVEPOINT focused_rollback_recovery");
              await db.queryArray(
                "UPDATE internal.observation_history_rollout SET orchestration_enabled=true,composition_orchestration_enabled=true,focused_composition_source_reservation_enabled=false,focused_composition_source_recovery_enabled=false,focused_composition_runtime_enabled=false,focused_composition_evidence_enabled=false,focused_composition_analysis_enabled=false,focused_composition_dispatch_enabled=false,focused_composition_orchestration_enabled=false",
              );
              const listed = (await db.queryObject<
                { value: Array<{ analysis_id: string }> }
              >(
                "SELECT public.list_observation_composition_analysis_recovery() value",
              )).rows[0].value;
              assert(listed.some((item) => item.analysis_id === f.child));
              const recovered = (await db.queryObject<
                { value: { claimed: boolean; work_token: string } }
              >(
                "SELECT public.claim_observation_composition_analysis_recovery($1,$2,$3) value",
                [f.owner, f.parent, f.child],
              )).rows[0].value;
              assertEquals(recovered.claimed, true);
              await denied(db, () =>
                db.queryArray(
                  "SELECT public.advance_owned_observation_composition_analysis($1,$2,$3,$4,'dispatch',$5::jsonb)",
                  [
                    f.owner,
                    f.parent,
                    f.child,
                    recovered.work_token,
                    JSON.stringify({ provenance }),
                  ],
                ));
              await db.queryArray(
                "SELECT public.advance_owned_observation_composition_analysis($1,$2,$3,$4,'release','{}')",
                [f.owner, f.parent, f.child, recovered.work_token],
              );
              await db.queryArray(
                "ROLLBACK TO SAVEPOINT focused_rollback_recovery",
              );
            }
            if (kind === "draft") {
              await denied(
                db,
                () =>
                  call("complete_composition_observation_analysis", [
                    quota.lease_token,
                  ]),
              );
              await call("record_composition_observation_draft", [
                quota.lease_token,
                JSON.stringify(draft),
              ]);
              await call("record_composition_observation_draft", [
                quota.lease_token,
                JSON.stringify(draft),
              ]);
              await denied(
                db,
                () =>
                  call("complete_composition_observation_analysis", [
                    quota.lease_token,
                  ]),
              );
              const proof = await call(
                "account_composition_observation_draft",
                [
                  quota.lease_token,
                ],
              );
              assertEquals(
                await call("account_composition_observation_draft", [
                  quota.lease_token,
                ]),
                proof,
              );
              // A client can preclaim a publicly derivable UUID. It must not poison
              // the private completion selection operation.
              await db.queryArray(
                "SELECT set_config('request.jwt.claim.sub',$1,true)",
                [f.owner],
              );
              await db.queryArray(
                "UPDATE internal.observation_history_rollout SET selection_enabled=true,selection_api_enabled=true,reader_enabled=true,state_reader_enabled=true",
              );
              await db.queryArray(
                `SELECT public.select_owned_observation_analysis(jsonb_build_object(
              'schema_version',1,'observation_id',$1::uuid,'analysis_id',$2::uuid,
              'operation_id',(substr(encode(extensions.digest(convert_to('merian.composition-selection.v1:'||$1::text||':'||$3::text,'UTF8'),'sha256'),'hex'),1,32))::uuid,
              'expected_observation_revision',h.state_revision,'expected_review_revision',0),${f.reader})
              FROM internal.observation_histories h WHERE h.observation_id=$1::uuid`,
                [f.parent, f.source, f.child],
              );
              const beforeSelection =
                (await db.queryObject<{ revision: number; selected: string }>(
                  "SELECT state_revision revision,selected_analysis_id selected FROM internal.observation_histories WHERE observation_id=$1",
                  [f.parent],
                )).rows[0];
              await db.queryArray(
                "UPDATE internal.observation_history_rollout SET selection_enabled=false",
              );
              await denied(
                db,
                () =>
                  call("complete_composition_observation_analysis", [
                    quota.lease_token,
                  ]),
              );
              assertEquals(
                (await db.queryObject<{ n: number }>(
                  "SELECT count(*)::int n FROM internal.observation_analysis_results WHERE analysis_id=$1",
                  [f.child],
                )).rows[0].n,
                0,
              );
              assertEquals(
                (await db.queryObject<{ selected: string }>(
                  "SELECT selected_analysis_id selected FROM internal.observation_histories WHERE observation_id=$1",
                  [f.parent],
                )).rows[0].selected,
                beforeSelection.selected,
              );
              await db.queryArray(
                "UPDATE internal.observation_history_rollout SET selection_enabled=true",
              );
              const completed = await call(
                "complete_composition_observation_analysis",
                [quota.lease_token],
              );
              const afterSelection =
                (await db.queryObject<{ revision: number; selected: string }>(
                  "SELECT state_revision revision,selected_analysis_id selected FROM internal.observation_histories WHERE observation_id=$1",
                  [f.parent],
                )).rows[0];
              assertEquals(
                (await db.queryObject<{ n: number }>(
                  "SELECT count(*)::int n FROM internal.composition_completion_selections WHERE analysis_id=$1",
                  [f.child],
                )).rows[0].n,
                1,
              );
              await denied(
                db,
                () =>
                  db.queryArray(
                    "DELETE FROM internal.composition_completion_selections WHERE analysis_id=$1",
                    [f.child],
                  ),
              );
              await denied(
                db,
                () =>
                  db.queryArray(
                    "UPDATE internal.composition_completion_selections SET operation_id=gen_random_uuid() WHERE analysis_id=$1",
                    [f.child],
                  ),
              );
              assertEquals(afterSelection.selected, f.child);
              assertEquals(
                afterSelection.revision,
                beforeSelection.revision + 1,
              );
              await db.queryArray(
                "SELECT set_config('request.jwt.claim.sub',$1,true)",
                [f.owner],
              );
              await db.queryArray(
                "UPDATE internal.observation_history_rollout SET selection_api_enabled=true,reader_enabled=true,state_reader_enabled=true",
              );
              const oldSelection = {
                schema_version: 1,
                observation_id: f.parent,
                analysis_id: f.source,
                operation_id: crypto.randomUUID(),
                expected_observation_revision: beforeSelection.revision,
                expected_review_revision: 0,
              };
              const stale =
                (await db.queryObject<{ value: { outcome: string } }>(
                  `SELECT public.select_owned_observation_analysis($1::jsonb,${f.reader}) value`,
                  [JSON.stringify(oldSelection)],
                )).rows[0].value;
              assertEquals(stale.outcome, "revision_conflict");
              const later = (await db.queryObject<
                { value: { selected_analysis_id: string } }
              >(
                `SELECT public.select_owned_observation_analysis($1::jsonb,${f.reader}) value`,
                [JSON.stringify({
                  ...oldSelection,
                  operation_id: crypto.randomUUID(),
                  expected_observation_revision: afterSelection.revision,
                })],
              )).rows[0].value;
              assertEquals(later.selected_analysis_id, f.source);
              const snapshot = JSON.parse(completed.snapshot as string);
              assertEquals(snapshot.schema_version, f.focused ? 7 : 6);
              assertEquals(
                snapshot.evidence_manifest,
                f.input.evidence_manifest,
              );
              assertEquals(snapshot.source_analysis_id, f.source);
              assertEquals(
                await call("complete_composition_observation_analysis", [
                  quota.lease_token,
                ]),
                completed,
              );
              assertEquals(
                (await db.queryObject<{ selected: string }>(
                  "SELECT selected_analysis_id selected FROM internal.observation_histories WHERE observation_id=$1",
                  [f.parent],
                )).rows[0].selected,
                f.source,
              );
              assertEquals(
                (await db.queryObject<{ n: number }>(
                  "SELECT count(*)::int n FROM internal.observation_selection_receipts WHERE observation_id=$1 AND receipt->>'selected_analysis_id'=$2",
                  [f.parent, f.child],
                )).rows[0].n,
                1,
              );
              assertEquals(
                (await db.queryObject<{ n: number }>(
                  "SELECT count(*)::int n FROM internal.observation_analysis_results WHERE observation_id=$1",
                  [f.parent],
                )).rows[0].n,
                2,
              );
              assertEquals(
                (await db.queryObject<{ n: number }>(
                  "SELECT count(*)::int n FROM internal.observation_analysis_source_occupancy WHERE analysis_id=$1",
                  [f.child],
                )).rows[0].n,
                0,
              );
            } else {
              const terminal = await call(
                "settle_composition_observation_terminal",
                [quota.lease_token],
              );
              assertEquals(
                await call("settle_composition_observation_terminal", [
                  quota.lease_token,
                ]),
                terminal,
              );
              assertEquals(
                (await db.queryObject<{ n: number }>(
                  "SELECT count(*)::int n FROM internal.observation_analysis_results WHERE observation_id=$1",
                  [f.parent],
                )).rows[0].n,
                1,
              );
              assertEquals(
                (await db.queryObject<{ n: number }>(
                  "SELECT count(*)::int n FROM internal.observation_analysis_source_occupancy WHERE analysis_id=$1",
                  [f.child],
                )).rows[0].n,
                1,
              );
            }
            await successorChecks(db, f, kind === "draft");
            if (kind === "draft") await readerChecks(db, f);
            assertEquals(
              (await db.queryObject<{ n: number }>(
                "SELECT count(*)::int n FROM internal.identification_invocations WHERE scan_id=$1",
                [f.child],
              )).rows[0].n,
              1,
            );
            assertEquals(
              (await db.queryObject<{ n: number }>(
                "SELECT count(*)::int n FROM public.ai_usage_events WHERE scan_id=$1",
                [f.child],
              )).rows[0].n,
              1,
            );
            await db.queryArray("SELECT public.apply_user_tombstone($1)", [
              f.owner,
            ]);
            await denied(db, admit);
          } finally {
            await db.queryArray("ROLLBACK");
            await db.end();
          }
        },
      });
    }
  }
}
