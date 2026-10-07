import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { PublicHttpError, publicHttpError } from "../_shared/http.ts";
import {
  type AnalysisConfirmationRequest,
  parseAnalysisConfirmationReceipt,
  parseAnalysisConfirmationRequest,
  parseConfirmationPreparation,
} from "../_shared/analysisHistory/confirmation.ts";
import {
  type ConfirmationDependencies,
  handleAnalysisConfirmation,
  handleAuthenticatedAnalysisConfirmation,
} from "./index.ts";
import { completeConfirmation, prepareConfirmation } from "./db.ts";

const user = { id: "00000000-0000-4000-8000-000000000001" } as User;
const admin = {} as SupabaseClient;
const body: AnalysisConfirmationRequest = {
  schema_version: 1,
  observation_id: "00000000-0000-4000-8000-000000000011",
  analysis_id: "00000000-0000-4000-8000-000000000012",
  operation_id: "00000000-0000-4000-8000-000000000013",
  expected_observation_revision: 4,
  expected_review_revision: 2,
  action: "confirm_name",
  scientific_name: "Fixtureus synonym",
};
const proof = {
  scientific_name: "Fixtureus accepted",
  gbif_taxon_key: 980002,
  rank: "SPECIES",
  status: "ACCEPTED",
  kingdom: "Plantae",
} as const;
const applied = {
  ...body,
  outcome: "applied",
  observation_revision: 5,
  review_revision: 3,
} as const;
function request(value: unknown = body, signal?: AbortSignal) {
  return new Request("https://example.invalid/confirm-observation-analysis", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(value),
    signal,
  });
}
function harness() {
  const events: string[] = [];
  const dependencies: ConfirmationDependencies = {
    prepare: (_admin, owner, parsed) => {
      assertEquals(owner, user.id);
      assertEquals(parsed, body);
      events.push("prepare");
      return Promise.resolve({
        schema_version: 1,
        status: "verify",
        request: parsed,
        scientific_name: "Fixtureus synonym",
      });
    },
    admit: (_admin, owner) => {
      assertEquals(owner, user.id);
      events.push("admit");
      return Promise.resolve();
    },
    verify: (name) => {
      assertEquals(name, "Fixtureus synonym");
      events.push("verify");
      return Promise.resolve(proof);
    },
    complete: (_admin, owner, parsed, name, taxon) => {
      assertEquals(owner, user.id);
      assertEquals(parsed, body);
      assertEquals(name, "Fixtureus synonym");
      assertEquals(taxon, proof);
      events.push("complete");
      return Promise.resolve(applied);
    },
  };
  return { dependencies, events };
}
Deno.test("confirmation persists bound intent before rate admission, verification and completion", async () => {
  const { dependencies, events } = harness();
  const response = await handleAnalysisConfirmation(
    request(),
    user,
    admin,
    dependencies,
  );
  assertEquals(events, ["prepare", "admit", "verify", "complete"]);
  assertEquals(await response.json(), applied);
  assertEquals(response.headers.get("Cache-Control"), "private, no-store");
});
Deno.test("all completed confirmation outcomes recover before quota or network", async () => {
  for (
    const receipt of [
      applied,
      { ...body, outcome: "revision_conflict" } as const,
      { ...body, outcome: "not_verified" } as const,
    ]
  ) {
    const { dependencies, events } = harness();
    dependencies.prepare = () => {
      events.push("replay");
      return Promise.resolve({
        schema_version: 1,
        status: "complete",
        receipt,
      });
    };
    assertEquals(
      await (await handleAnalysisConfirmation(
        request(),
        user,
        admin,
        dependencies,
      )).json(),
      receipt,
    );
    assertEquals(events, ["replay"]);
  }
});
Deno.test("negative verification completes a durable outcome without fabricating proof", async () => {
  const { dependencies } = harness();
  dependencies.verify = () => Promise.resolve(null);
  dependencies.complete = (_a, _u, parsed, name, taxon) => {
    assertEquals(parsed, body);
    assertEquals(name, body.scientific_name);
    assertEquals(taxon, null);
    return Promise.resolve({ ...parsed, outcome: "not_verified" });
  };
  assertEquals(
    await (await handleAnalysisConfirmation(
      request(),
      user,
      admin,
      dependencies,
    )).json(),
    { ...body, outcome: "not_verified" },
  );
});
Deno.test("lookup, closed gate, rate refusal and cancellation never finish a confirmation", async () => {
  for (const stage of ["prepare", "admit", "verify", "cancel"] as const) {
    const { dependencies, events } = harness(),
      controller = new AbortController();
    if (stage === "prepare") {
      dependencies.prepare = () => {
        throw publicHttpError(503, "Unavailable");
      };
    }
    if (stage === "admit") {
      dependencies.admit = () => {
        throw publicHttpError(429, "Limited");
      };
    }
    if (stage === "verify") {
      dependencies.verify = () => {
        throw new Error("private provider diagnostics");
      };
    }
    if (stage === "cancel") {
      dependencies.verify = () => {
        controller.abort();
        return Promise.resolve(proof);
      };
    }
    const error = await assertRejects(() =>
      handleAnalysisConfirmation(
        request(body, controller.signal),
        user,
        admin,
        dependencies,
      )
    );
    assertEquals(events.includes("complete"), false);
    assertEquals(String(error).includes("private provider diagnostics"), false);
    if (stage === "verify") {
      assertEquals((error as PublicHttpError).status, 503);
    }
  }
});
Deno.test("strict confirmation identity rejects client proof, authority, wrong names and revisions", () => {
  assertEquals(parseAnalysisConfirmationRequest(body), body);
  assertEquals(
    parseAnalysisConfirmationRequest({
      ...body,
      action: "confirm_primary",
      scientific_name: null,
    }).action,
    "confirm_primary",
  );
  for (
    const change of [
      { action: "reject" },
      { action: "confirm_primary" },
      { scientific_name: null },
      { scientific_name: " x " },
      { scientific_name: "" },
      { scientific_name: "x\n" },
      { scientific_name: "x".repeat(161) },
      { expected_review_revision: true },
      { expected_observation_revision: 2147483647 },
      { owner_id: user.id },
      { taxon: proof },
    ]
  ) {
    assertThrows(() =>
      parseAnalysisConfirmationRequest({ ...body, ...change })
    );
  }
  assertEquals(parseAnalysisConfirmationReceipt(applied, body), applied);
  for (
    const change of [
      { analysis_id: user.id },
      { operation_id: user.id },
      { expected_review_revision: 1 },
      { review_revision: 2 },
      { observation_revision: 6 },
      { current_state: {} },
      { outcome: "unknown" },
    ]
  ) {
    assertThrows(() =>
      parseAnalysisConfirmationReceipt({ ...applied, ...change }, body)
    );
  }
  assertThrows(() =>
    parseConfirmationPreparation({
      schema_version: 1,
      status: "verify",
      request: body,
      scientific_name: "Rebound query",
    }, body)
  );
});
Deno.test("invalid body and authentication failure invoke no persistence", async () => {
  const { dependencies, events } = harness();
  assertEquals(
    (await assertRejects(() =>
      handleAnalysisConfirmation(
        request({ ...body, owner_id: user.id }),
        user,
        admin,
        dependencies,
      ), PublicHttpError)).status,
    400,
  );
  const names = ["SUPABASE_URL", "MERIAN_SUPABASE_SERVER_API_KEY"],
    prior = names.map((name) => Deno.env.get(name));
  Deno.env.set(names[0], "https://example.supabase.co");
  Deno.env.set(names[1], "sb_secret_" + "a".repeat(32));
  try {
    const response = await handleAuthenticatedAnalysisConfirmation(
      request(),
      () =>
        Promise.resolve({
          user: null,
          response: new Response(null, { status: 401 }),
        }),
      dependencies,
    );
    assertEquals(response.status, 401);
    assertEquals(response.headers.get("Cache-Control"), "private, no-store");
    assertEquals(events, []);
  } finally {
    names.forEach((name, i) => {
      const value = prior[i];
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    });
  }
});
Deno.test("database adapters bind authenticated owner, protocol and verified query; redact diagnostics", async () => {
  const calls: unknown[] = [];
  const client = {
    rpc: (name: string, args: unknown) => {
      calls.push([name, args]);
      return Promise.resolve({
        data: { schema_version: 1, status: "complete", receipt: applied },
        error: null,
      });
    },
  } as unknown as SupabaseClient;
  await prepareConfirmation(client, user.id, body);
  assertEquals(
    await completeConfirmation(
      client,
      user.id,
      body,
      "Fixtureus synonym",
      proof,
    ),
    applied,
  );
  assertEquals(calls, [
    ["prepare_observation_analysis_confirmation", {
      p_user_id: user.id,
      p_request: body,
      p_reader: 9,
    }],
    ["complete_observation_analysis_confirmation", {
      p_user_id: user.id,
      p_request: body,
      p_reader: 9,
      p_verified_name: "Fixtureus synonym",
      p_taxon: proof,
    }],
  ]);
  for (
    const [message, status] of [
      ["analysis_history_not_found", 404],
      ["analysis_history_operation_conflict", 409],
      ["analysis_history_unavailable", 503],
      ["private database diagnostics", 503],
    ] as const
  ) {
    const bad = {
      rpc: () => Promise.resolve({ data: null, error: { message } }),
    } as unknown as SupabaseClient;
    const error = await assertRejects(
      () => prepareConfirmation(bad, user.id, body),
      PublicHttpError,
    );
    assertEquals(error.status, status);
    assertEquals(error.message.includes("private database diagnostics"), false);
  }
});

Deno.test("candidate confirmation carries exact provenance through HTTP execution and saved replay", async () => {
  const candidate: AnalysisConfirmationRequest = {
    ...body,
    schema_version: 2,
    action: "confirm_name",
    scientific_name: "Fixtureus synonym",
    candidate_reference: {
      version: 1,
      analysis_id: body.analysis_id,
      representation: "stored_species_candidates_v1",
      ordinal: 1,
    },
  };
  const receipt = {
    ...candidate,
    outcome: "applied",
    observation_revision: 5,
    review_revision: 3,
  } as const;
  const events: string[] = [];
  const dependencies: ConfirmationDependencies = {
    prepare: (_admin, owner, parsed) => {
      assertEquals(owner, user.id);
      assertEquals(parsed, candidate);
      events.push("prepare");
      return Promise.resolve({
        schema_version: 1,
        status: "verify",
        request: parsed,
        scientific_name: candidate.scientific_name,
      });
    },
    admit: () => {
      events.push("admit");
      return Promise.resolve();
    },
    verify: (name) => {
      assertEquals(name, candidate.scientific_name);
      events.push("verify");
      return Promise.resolve(proof);
    },
    complete: (_admin, owner, parsed, name, taxon) => {
      assertEquals(owner, user.id);
      assertEquals(parsed, candidate);
      assertEquals(name, candidate.scientific_name);
      assertEquals(taxon, proof);
      events.push("complete");
      return Promise.resolve(receipt);
    },
  };
  assertEquals(
    await (await handleAnalysisConfirmation(
      request(candidate),
      user,
      admin,
      dependencies,
    )).json(),
    receipt,
  );
  assertEquals(events, ["prepare", "admit", "verify", "complete"]);
  events.length = 0;
  dependencies.prepare = (_admin, _owner, parsed) => {
    assertEquals(parsed, candidate);
    events.push("replay");
    return Promise.resolve({ schema_version: 1, status: "complete", receipt });
  };
  assertEquals(
    await (await handleAnalysisConfirmation(
      request(candidate),
      user,
      admin,
      dependencies,
    )).json(),
    receipt,
  );
  assertEquals(events, ["replay"]);
});
