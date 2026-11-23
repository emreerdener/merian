import { assertEquals, assertRejects } from "@std/assert";
import page from "../_shared/analysisHistory/fixtures/page-v8-geometry.json" with {
  type: "json",
};
import { initialRetentionRequest } from "../_shared/analysisHistory/initialEvidenceRetention.ts";
import {
  continuePrivateCaptureFinalizations,
  type PrivateFinalizationDependencies,
} from "./privateFinalization.ts";

async function fixture() {
  const snapshot = JSON.parse(page.items[0].snapshot);
  const request = await initialRetentionRequest({
    schema_version: 1,
    scan_id: snapshot.observation_id,
    generation: snapshot.initial_evidence.generation,
    evidence_digest: snapshot.request_digest,
    evidence_manifest: snapshot.evidence_manifest,
  });
  const row = {
    schema_version: 1,
    owner_id: page.owner_id,
    request,
    telemetry: { geoprivacy: "private" },
  };
  const result = {
    result: snapshot.result,
    speciesID: null,
    resultDigest: "a".repeat(64),
  };
  const envelope = {
    success: true,
    data: snapshot.result,
    initial_evidence: {
      schema_version: 1,
      owner_id: page.owner_id,
      scan_id: request.scan_id,
      generation: request.generation,
      evidence_digest: request.evidence_digest,
    },
  };
  const calls: string[] = [];
  const dependencies: PrivateFinalizationDependencies = {
    claim() {
      calls.push("claim");
      return Promise.resolve([row]);
    },
    completed() {
      calls.push("completed");
      return Promise.resolve(null);
    },
    accepted() {
      calls.push("accepted");
      return Promise.resolve(result);
    },
    finalize(current, accepted) {
      calls.push("finalize");
      assertEquals(current.request, request);
      assertEquals(current.telemetry, { geoprivacy: "private" });
      assertEquals(accepted, result);
      return Promise.resolve(envelope);
    },
  };
  return { row, envelope, calls, dependencies };
}

Deno.test("private continuation finalizes the accepted result without any provider dependency", async () => {
  const { calls, dependencies } = await fixture();
  assertEquals(
    await continuePrivateCaptureFinalizations(
      dependencies,
      new AbortController().signal,
    ),
    {
      claimed: 1,
      completed: 1,
      alreadyComplete: 0,
      held: 0,
    },
  );
  assertEquals(calls, ["claim", "completed", "accepted", "finalize"]);
});

Deno.test("a sealed completion wins before media/result recovery", async () => {
  const { calls, dependencies, envelope } = await fixture();
  dependencies.completed = () => {
    calls.push("completed");
    return Promise.resolve(envelope);
  };
  assertEquals(
    await continuePrivateCaptureFinalizations(
      dependencies,
      new AbortController().signal,
    ),
    {
      claimed: 1,
      completed: 0,
      alreadyComplete: 1,
      held: 0,
    },
  );
  assertEquals(calls, ["claim", "completed"]);
});

Deno.test("uncertainty and invalid proofs stay held at every recovery boundary", async () => {
  for (const phase of ["completed", "accepted", "finalize"] as const) {
    const { calls, dependencies } = await fixture();
    dependencies[phase] = () => {
      calls.push(phase);
      return Promise.reject(new Error("synthetic failure"));
    };
    assertEquals(
      await continuePrivateCaptureFinalizations(
        dependencies,
        new AbortController().signal,
      ),
      {
        claimed: 1,
        completed: 0,
        alreadyComplete: 0,
        held: 1,
      },
    );
    assertEquals(calls.at(-1), phase);
  }
  for (const phase of ["completed", "finalize"] as const) {
    const { dependencies, envelope } = await fixture();
    dependencies[phase] = () =>
      Promise.resolve({
        ...envelope,
        initial_evidence: {
          ...envelope.initial_evidence,
          generation: crypto.randomUUID(),
        },
      });
    assertEquals(
      (await continuePrivateCaptureFinalizations(
        dependencies,
        new AbortController().signal,
      )).held,
      1,
    );
  }
  const { dependencies, calls } = await fixture();
  dependencies.accepted = () => {
    calls.push("accepted");
    return Promise.resolve(null);
  };
  assertEquals(
    (await continuePrivateCaptureFinalizations(
      dependencies,
      new AbortController().signal,
    )).held,
    1,
  );
  assertEquals(calls, ["claim", "completed", "accepted"]);
});

Deno.test("malformed candidates cannot prevent the next valid candidate from completing", async () => {
  const { dependencies, row } = await fixture();
  dependencies.claim = () =>
    Promise.resolve([{ ...row, schema_version: 2 }, row]);
  assertEquals(
    await continuePrivateCaptureFinalizations(
      dependencies,
      new AbortController().signal,
    ),
    {
      claimed: 2,
      completed: 1,
      alreadyComplete: 0,
      held: 1,
    },
  );
  dependencies.claim = () => Promise.resolve(Array(6).fill(row));
  await assertRejects(() =>
    continuePrivateCaptureFinalizations(
      dependencies,
      new AbortController().signal,
    )
  );
});

Deno.test("abort after accepted read prevents finalization", async () => {
  const { dependencies, calls } = await fixture();
  const controller = new AbortController(), accepted = dependencies.accepted;
  dependencies.accepted = async (candidate, signal) => {
    const value = await accepted(candidate, signal);
    controller.abort();
    return value;
  };
  assertEquals(
    (await continuePrivateCaptureFinalizations(dependencies, controller.signal))
      .held,
    1,
  );
  assertEquals(calls, ["claim", "completed", "accepted"]);
  const aborted = new AbortController();
  aborted.abort();
  await assertRejects(() =>
    continuePrivateCaptureFinalizations(dependencies, aborted.signal)
  );
});
