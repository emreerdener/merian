import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  authorizeSpeciesObservationStatsRequest,
  claimSpeciesObservationStatsPopulation,
  finalizeSpeciesObservationStatsPopulation,
  preflightSpeciesObservationStatsRequest,
  SpeciesObservationStatsError,
} from "./security.ts";

const SPECIES_ID = "1cf79982-e5ee-4e3d-8d65-274527e6ae01";
const USER_ID = "00000000-0000-4000-8000-000000000902";
const LEASE_TOKEN = "00000000-0000-4000-8000-000000000901";
const CONTEXT = { userId: USER_ID, ipHash: "a".repeat(64) };

Deno.test("species stats IP preflight fails closed before optional auth", async () => {
  const calls: string[] = [];
  const client = fakeRpcClient((name) => {
    calls.push(name);
    return {
      data: null,
      error: { message: "species_stats_request_ip_rate_limited" },
    };
  });

  const error = await assertRejects(
    () => preflightSpeciesObservationStatsRequest(CONTEXT.ipHash, client),
    SpeciesObservationStatsError,
  );
  assertEquals(error.status, 429);
  assertEquals(error.code, "species_stats_rate_limited");
  assertEquals(calls, ["preflight_species_observation_stats_request"]);
});

Deno.test("species stats IP preflight accepts a bounded database counter", async () => {
  const client = fakeRpcClient(() => ({ data: 17, error: null }));
  await preflightSpeciesObservationStatsRequest(CONTEXT.ipHash, client);
});

Deno.test("species stats authorization maps user-rate denial to HTTP 429", async () => {
  const client = fakeRpcClient(() => ({
    data: null,
    error: { message: "species_stats_request_user_rate_limited" },
  }));

  const error = await assertRejects(
    () =>
      authorizeSpeciesObservationStatsRequest(
        { speciesId: SPECIES_ID, scientificName: "Danaus plexippus" },
        CONTEXT,
        client,
      ),
    SpeciesObservationStatsError,
  );
  assertEquals(error.status, 429);
  assertEquals(error.code, "species_stats_rate_limited");
  assertEquals(error.retryAfterSeconds, 60);
});

Deno.test("species stats authorization rejects a database dictionary denial", async () => {
  const client = fakeRpcClient(() => ({
    data: [{
      species_id: null,
      scientific_name: null,
      inaturalist_taxon_id: null,
      denial_code: "species_stats_species_mismatch",
    }],
    error: null,
  }));

  const error = await assertRejects(
    () =>
      authorizeSpeciesObservationStatsRequest(
        { speciesId: SPECIES_ID, scientificName: "Forged name" },
        CONTEXT,
        client,
      ),
    SpeciesObservationStatsError,
  );
  assertEquals(error.status, 404);
  assertEquals(error.code, "species_stats_species_not_found");
});

Deno.test("species stats claim distinguishes a cache race from active population", async () => {
  const client = fakeRpcClient(() => ({
    data: [{
      claimed: false,
      lease_token: null,
      lease_expires_at: "2026-07-24T12:00:00.000Z",
      retry_after_seconds: 1,
      cache_available: true,
    }],
    error: null,
  }));

  const result = await claimSpeciesObservationStatsPopulation(
    SPECIES_ID,
    CONTEXT,
    client,
  );
  assertEquals(result.claimed, false);
  assertEquals(result.cacheAvailable, true);
  assertEquals(result.leaseToken, null);
});

Deno.test("species stats finalization forwards the fencing token", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const client = fakeRpcClient((_name, args) => {
    calls.push(args);
    return { data: true, error: null };
  });

  const finalized = await finalizeSpeciesObservationStatsPopulation(
    {
      speciesId: SPECIES_ID,
      leaseToken: LEASE_TOKEN,
      taxonId: 48662,
      payload: {
        species_id: SPECIES_ID,
        scientific_name: "Danaus plexippus",
      },
      status: "fresh",
      providerError: null,
    },
    client,
  );

  assertEquals(finalized, true);
  assertEquals(calls[0]?.p_lease_token, LEASE_TOKEN);
});

function fakeRpcClient(
  response: (
    name: string,
    args: Record<string, unknown>,
  ) => {
    data: unknown;
    error: { message: string; code?: string } | null;
  },
) {
  return {
    rpc(name: string, args: Record<string, unknown>) {
      return {
        abortSignal: () => Promise.resolve(response(name, args)),
      };
    },
  } as never;
}
