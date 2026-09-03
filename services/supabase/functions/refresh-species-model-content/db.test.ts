import { assertEquals } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import {
  parseSpeciesModelContentRefreshRequest,
  refreshSpeciesModelContentJob,
  runSpeciesModelContentRefresh,
  type SpeciesModelEnrichmentJobRow,
} from "./db.ts";
import type { VerifiedLookalikeTaxon } from "./lookalikeCandidates.ts";

Deno.test("refresh species model content - parses defaults and filters", () => {
  const defaultResult = parseSpeciesModelContentRefreshRequest({});
  assertEquals(defaultResult.request?.limit, 12);
  assertEquals(defaultResult.request?.dryRun, false);
  assertEquals(defaultResult.request?.contentGroups, undefined);

  const customResult = parseSpeciesModelContentRefreshRequest({
    limit: 6,
    dry_run: true,
    as_of: "2026-06-22T00:00:00Z",
    content_groups: ["habitat", "lookalikes", "habitat"],
  });

  assertEquals(customResult.request?.limit, 6);
  assertEquals(customResult.request?.dryRun, true);
  assertEquals(customResult.request?.asOf, "2026-06-22T00:00:00.000Z");
  assertEquals(customResult.request?.contentGroups, ["habitat", "lookalikes"]);
});

Deno.test("refresh species model content - rejects invalid inputs", () => {
  assertEquals(parseSpeciesModelContentRefreshRequest({ limit: 51 }), {
    error: "limit must be an integer from 1 to 50.",
    status: 400,
  });
  assertEquals(
    parseSpeciesModelContentRefreshRequest({ content_groups: ["taxonomy"] }),
    {
      error: "Unsupported content group: taxonomy",
      status: 400,
    },
  );
  assertEquals(parseSpeciesModelContentRefreshRequest({ dry_run: "yes" }), {
    error: "dry_run must be a boolean.",
    status: 400,
  });
});

const job: SpeciesModelEnrichmentJobRow = {
  job_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  species_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  scientific_name: "Pyracantha angustifolia",
  content_group: "lookalikes",
  priority: 90,
  attempts: 1,
  max_attempts: 5,
  source_trigger: "species_dictionary_insert",
  metadata: { lookalike_resolution_version: 1 },
};
const taxonomy = { kingdom: "Plantae", order: "Rosales", family: "Rosaceae" };
const candidate = {
  scientific_name: "Pyracantha coccinea",
  common_name: "Firethorn",
};
const verified: VerifiedLookalikeTaxon = {
  ...taxonomy,
  scientific_name: candidate.scientific_name,
  gbif_taxon_key: 1001,
  rank: "SPECIES",
  status: "ACCEPTED",
};

function workerClient(options: {
  primary?: Record<string, unknown> | null;
  outcome?: unknown;
  persistFailure?: boolean;
} = {}) {
  const calls: Array<{ name: string; body: Record<string, unknown> }> = [];
  const client = createClient(
    "https://lookalike-tests.supabase.invalid",
    "fixture-key",
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: {
        fetch: (input, init) => {
          const url = new URL(String(input));
          if (url.pathname.endsWith("/species_dictionary")) {
            assertEquals(init?.method ?? "GET", "GET");
            assertEquals(
              url.searchParams.get("scientific_name"),
              `eq.${job.scientific_name}`,
            );
            return Promise.resolve(Response.json(
              options.primary === undefined
                ? { id: job.species_id, ...taxonomy }
                : options.primary,
            ));
          }
          const name = url.pathname.split("/").at(-1)!;
          const body = JSON.parse(String(init?.body ?? "{}"));
          calls.push({ name, body });
          if (name === "claim_species_model_enrichment_jobs") {
            return Promise.resolve(Response.json([job]));
          }
          if (name === "complete_species_enrichment_job") {
            return Promise.resolve(Response.json(null));
          }
          if (name === "persist_species_model_lookalikes") {
            return Promise.resolve(Response.json(
              options.persistFailure
                ? { message: "fixture persistence failure" }
                : options.outcome ??
                  [{
                    persisted_count: body.candidates.length,
                    unresolved_count: 0,
                    rejected_count: 0,
                  }],
              { status: options.persistFailure ? 500 : 200 },
            ));
          }
          throw new Error(`Unexpected worker fixture RPC: ${name}`);
        },
      },
    },
  );
  return { client, calls };
}

function completion(calls: ReturnType<typeof workerClient>["calls"]) {
  return calls.find((call) => call.name === "complete_species_enrichment_job")
    ?.body;
}

Deno.test("model lookalike job - genuine empty generation records a settled empty result", async () => {
  const { client, calls } = workerClient();
  const result = await refreshSpeciesModelContentJob(job, client, {
    fetchSimilarSpecies: () => Promise.resolve({ similar_species: [] }),
    fetchLookalikeTaxon: () => {
      throw new Error("No provider lookup expected.");
    },
  });
  assertEquals(result.status, "no_data");
  assertEquals(result.refreshed, false);
  assertEquals(calls[0], {
    name: "persist_species_model_lookalikes",
    body: {
      target_species_id: job.species_id,
      candidates: [],
      resolution_complete: true,
    },
  });
  assertEquals(calls.length, 2);
  assertEquals(completion(calls)?.succeeded, true);
});

Deno.test("model lookalike job - missing generation is a retryable failure", async () => {
  const { client, calls } = workerClient();
  const result = await refreshSpeciesModelContentJob(job, client, {
    fetchSimilarSpecies: () => Promise.resolve(null),
  });
  assertEquals(result.status, "failed");
  assertEquals(completion(calls)?.succeeded, false);
});

Deno.test("model lookalike job - a provider outage can recover on a later attempt", async () => {
  const { client, calls } = workerClient();
  const unavailable = await refreshSpeciesModelContentJob(job, client, {
    fetchSimilarSpecies: () =>
      Promise.resolve({ similar_species: [candidate] }),
    fetchLookalikeTaxon: () => {
      throw new Error("provider unavailable");
    },
  });
  assertEquals(unavailable.status, "failed");
  assertEquals(completion(calls)?.succeeded, false);
  assertEquals(calls.length, 1);

  const recovered = await refreshSpeciesModelContentJob(
    { ...job, attempts: 2 },
    client,
    {
      fetchSimilarSpecies: () =>
        Promise.resolve({ similar_species: [candidate] }),
      fetchLookalikeTaxon: () => Promise.resolve(verified),
    },
  );
  assertEquals(recovered.status, "refreshed");
  assertEquals(calls.at(-1)?.body.succeeded, true);
});

Deno.test("model lookalike job - confirmed incompatible candidates record a settled empty result", async () => {
  const { client, calls } = workerClient();
  const result = await refreshSpeciesModelContentJob(job, client, {
    fetchSimilarSpecies: () =>
      Promise.resolve({ similar_species: [candidate] }),
    fetchLookalikeTaxon: () =>
      Promise.resolve({ ...verified, kingdom: "Animalia" }),
  });
  assertEquals(result.status, "no_data");
  assertEquals(calls[0].body.candidates, []);
  assertEquals(calls[0].body.resolution_complete, true);
  assertEquals(completion(calls)?.succeeded, true);
});

Deno.test("model lookalike job - verified missing species reach atomic persistence", async () => {
  const { client, calls } = workerClient();
  const result = await refreshSpeciesModelContentJob(job, client, {
    fetchSimilarSpecies: () =>
      Promise.resolve({ similar_species: [candidate] }),
    fetchLookalikeTaxon: () => Promise.resolve(verified),
  });
  assertEquals(result.status, "refreshed");
  assertEquals(result.refreshed, true);
  assertEquals(calls[0], {
    name: "persist_species_model_lookalikes",
    body: {
      target_species_id: job.species_id,
      resolution_complete: true,
      candidates: [{
        ...candidate,
        reason: null,
        visual_traits: [],
        confidence: null,
        gbif: verified,
      }],
    },
  });
  assertEquals(completion(calls)?.succeeded, true);
});

Deno.test("model lookalike job - unresolved candidates stay failed instead of terminal no_data", async () => {
  const { client, calls } = workerClient();
  const result = await refreshSpeciesModelContentJob(job, client, {
    fetchSimilarSpecies: () =>
      Promise.resolve({ similar_species: [candidate] }),
    fetchLookalikeTaxon: () => Promise.resolve(null),
  });
  assertEquals(result.status, "failed");
  assertEquals(result.refreshed, false);
  assertEquals(calls.length, 1);
  assertEquals(completion(calls)?.succeeded, false);
});

Deno.test("model lookalike job - partial resolution saves usable relations but keeps the job retryable", async () => {
  const { client, calls } = workerClient();
  const result = await refreshSpeciesModelContentJob(job, client, {
    fetchSimilarSpecies: () =>
      Promise.resolve({
        similar_species: [candidate, {
          scientific_name: "Pyracantha fortuneana",
          common_name: "Firethorn",
        }],
      }),
    fetchLookalikeTaxon: (name) => {
      if (name === candidate.scientific_name) return Promise.resolve(verified);
      throw new Error("provider unavailable");
    },
  });
  assertEquals(result.status, "failed");
  assertEquals(result.refreshed, true);
  assertEquals(calls[0].name, "persist_species_model_lookalikes");
  assertEquals(calls[0].body.resolution_complete, false);
  assertEquals(completion(calls)?.succeeded, false);
});

Deno.test("model lookalike job - database taxonomy race remains retryable", async () => {
  const { client, calls } = workerClient({
    outcome: [{ persisted_count: 0, unresolved_count: 1, rejected_count: 0 }],
  });
  const result = await refreshSpeciesModelContentJob(job, client, {
    fetchSimilarSpecies: () =>
      Promise.resolve({ similar_species: [candidate] }),
    fetchLookalikeTaxon: () => Promise.resolve(verified),
  });
  assertEquals(result.status, "failed");
  assertEquals(completion(calls)?.succeeded, false);
});

Deno.test("model lookalike job - reviewed rejection completes without overriding the relation", async () => {
  const { client, calls } = workerClient({
    outcome: [{ persisted_count: 0, unresolved_count: 0, rejected_count: 1 }],
  });
  const result = await refreshSpeciesModelContentJob(job, client, {
    fetchSimilarSpecies: () =>
      Promise.resolve({ similar_species: [candidate] }),
    fetchLookalikeTaxon: () => Promise.resolve(verified),
  });
  assertEquals(result.status, "no_data");
  assertEquals(completion(calls)?.succeeded, true);
});

Deno.test("model lookalike job - persistence failure and malformed results cannot complete", async () => {
  for (
    const options of [{ persistFailure: true }, { outcome: [] }, {
      outcome: [{ persisted_count: 0, unresolved_count: 0, rejected_count: 0 }],
    }, {
      outcome: [{ persisted_count: 1, unresolved_count: 0, rejected_count: 1 }],
    }, {
      outcome: [{
        persisted_count: 99,
        unresolved_count: 0,
        rejected_count: 0,
      }],
    }]
  ) {
    const { client, calls } = workerClient(options);
    const result = await refreshSpeciesModelContentJob(job, client, {
      fetchSimilarSpecies: () =>
        Promise.resolve({ similar_species: [candidate] }),
      fetchLookalikeTaxon: () => Promise.resolve(verified),
    });
    assertEquals(result.status, "failed");
    assertEquals(completion(calls)?.succeeded, false);
  }
});

Deno.test("model lookalike job - stale species identity cannot redirect work to another row", async () => {
  const { client, calls } = workerClient({
    primary: { id: "replacement-species", ...taxonomy },
  });
  const result = await refreshSpeciesModelContentJob(job, client, {
    fetchSimilarSpecies: () => {
      throw new Error("Generation must not start.");
    },
  });
  assertEquals(result.status, "failed");
  assertEquals(calls.length, 1);
  assertEquals(completion(calls)?.succeeded, false);
});

Deno.test("model refresh preview - uses the same grouped selection and never generates or completes jobs", async () => {
  const { client, calls } = workerClient();
  const request = {
    limit: 4,
    asOf: "2026-09-03T00:00:00.000Z",
    dryRun: true,
    contentGroups: ["lookalikes" as const],
  };
  const result = await runSpeciesModelContentRefresh(request, client, {
    fetchSimilarSpecies: () => {
      throw new Error("Dry-run must not generate.");
    },
  });
  assertEquals(result.queued_count, 1);
  assertEquals(result.results[0].status, "dry_run");
  assertEquals(calls, [{
    name: "claim_species_model_enrichment_jobs",
    body: {
      max_rows: 4,
      as_of: request.asOf,
      target_content_groups: ["lookalikes"],
      preview_only: true,
    },
  }]);
});
