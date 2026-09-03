import { assert, assertEquals, assertRejects } from "@std/assert";
import {
  fetchVerifiedLookalikeTaxon,
  lookalikeTaxonomyCompatibility,
  normalizeLookalikeCandidates,
  prepareLookalikeCandidates,
  type VerifiedLookalikeTaxon,
} from "./lookalikeCandidates.ts";

const primary = { kingdom: "Plantae", order: "Rosales", family: "Rosaceae" };
const entry = {
  scientific_name: "Pyracantha coccinea",
  common_name: "Firethorn",
};
const verified: VerifiedLookalikeTaxon = {
  scientific_name: entry.scientific_name,
  gbif_taxon_key: 1001,
  rank: "SPECIES",
  status: "ACCEPTED",
  ...primary,
  genus: "Pyracantha",
};
const match = {
  usageKey: 1001,
  canonicalName: entry.scientific_name,
  matchType: "EXACT",
  status: "ACCEPTED",
  rank: "SPECIES",
  ...primary,
  genus: "Pyracantha",
};

Deno.test("lookalike candidates - exact accepted species use bounded contextual GBIF matching", async () => {
  const result = await fetchVerifiedLookalikeTaxon(
    entry.scientific_name,
    primary,
    (input, init) => {
      const url = new URL(String(input));
      assertEquals(url.origin, "https://api.gbif.org");
      assertEquals(url.pathname, "/v1/species/match");
      assertEquals(url.searchParams.get("strict"), "true");
      assertEquals(url.searchParams.get("name"), entry.scientific_name);
      assertEquals(url.searchParams.get("kingdom"), primary.kingdom);
      assertEquals(url.searchParams.get("order"), primary.order);
      assert(init?.signal);
      return Promise.resolve(Response.json(match));
    },
  );
  assertEquals(result, { ...verified, phylum: null, class: null });
});

Deno.test("lookalike candidates - fuzzy higher-rank mismatched and unaccepted identities are not materialized", async () => {
  for (
    const override of [
      { matchType: "FUZZY" },
      { matchType: "NONE" },
      { rank: "GENUS" },
      { canonicalName: "Unrelated species" },
      { status: "DOUBTFUL" },
      { usageKey: 0 },
      { usageKey: 2147483648 },
      { status: undefined },
      { rank: undefined },
    ]
  ) {
    assertEquals(
      await fetchVerifiedLookalikeTaxon(
        entry.scientific_name,
        primary,
        () => Promise.resolve(Response.json({ ...match, ...override })),
      ),
      null,
    );
  }
});

Deno.test("lookalike candidates - an exact synonym is resolved to its accepted canonical identity", async () => {
  const paths: string[] = [];
  const result = await fetchVerifiedLookalikeTaxon(
    "Mespilus pyracantha",
    primary,
    (input) => {
      const path = new URL(String(input)).pathname;
      paths.push(path);
      return Promise.resolve(Response.json(
        path.endsWith("/match")
          ? {
            ...match,
            canonicalName: "Mespilus pyracantha",
            status: "SYNONYM",
            acceptedUsageKey: 1001,
          }
          : {
            ...match,
            key: 1001,
            taxonomicStatus: "ACCEPTED",
          },
      ));
    },
  );
  assertEquals(paths, ["/v1/species/match", "/v1/species/1001"]);
  assertEquals(result?.scientific_name, entry.scientific_name);
  assertEquals(result?.gbif_taxon_key, 1001);
});

Deno.test("lookalike candidates - accepted synonym lookup must retain the requested accepted key", async () => {
  let count = 0;
  const result = await fetchVerifiedLookalikeTaxon(
    entry.scientific_name,
    primary,
    () => {
      count += 1;
      return Promise.resolve(Response.json(
        count === 1
          ? { ...match, status: "SYNONYM", acceptedUsageKey: 1001 }
          : { ...match, key: 2002, taxonomicStatus: "ACCEPTED" },
      ));
    },
  );
  assertEquals(result, null);
});

Deno.test("lookalike candidates - HTTP malformed and oversized failures remain retryable", async () => {
  await assertRejects(
    () =>
      fetchVerifiedLookalikeTaxon(
        entry.scientific_name,
        primary,
        () =>
          Promise.resolve(
            new Response("private provider body", { status: 503 }),
          ),
      ),
    Error,
    "HTTP 503",
  );
  await assertRejects(
    () =>
      fetchVerifiedLookalikeTaxon(
        entry.scientific_name,
        primary,
        () => Promise.resolve(Response.json([])),
      ),
    Error,
    "invalid response",
  );
  await assertRejects(
    () =>
      fetchVerifiedLookalikeTaxon(
        entry.scientific_name,
        primary,
        () =>
          Promise.resolve(
            new Response("{}", { headers: { "Content-Length": "65537" } }),
          ),
      ),
    RangeError,
  );
});

Deno.test("lookalike candidates - every identity is verified and shared common names are retained", async () => {
  const requestedNames: string[] = [];
  const result = await prepareLookalikeCandidates(
    "Pyracantha angustifolia",
    primary,
    [entry],
    (name, context) => {
      requestedNames.push(name);
      assertEquals(context, primary);
      return Promise.resolve(verified);
    },
  );
  assertEquals(result.unresolvedCount, 0);
  assertEquals(requestedNames, [entry.scientific_name]);
  assertEquals(result.candidates[0].common_name, "Firethorn");
  assertEquals(result.candidates[0].gbif, verified);
});

Deno.test("lookalike candidates - missing identities and incomplete authoritative taxonomy remain unresolved", async () => {
  for (
    const taxon of [null, { ...verified, kingdom: "Unknown" }]
  ) {
    const result = await prepareLookalikeCandidates(
      "Pyracantha angustifolia",
      primary,
      [entry],
      () => Promise.resolve(taxon),
    );
    assertEquals(result.candidates, []);
    assertEquals(result.unresolvedCount, 1);
    assertEquals(result.rejectedCount, 0);
  }
});

Deno.test("lookalike candidates - partial provider failure retains good candidates and retries missing ones", async () => {
  const result = await prepareLookalikeCandidates(
    "Pyracantha angustifolia",
    primary,
    [
      entry,
      { scientific_name: "Pyracantha fortuneana", common_name: "Firethorn" },
    ],
    (name) => {
      if (name === entry.scientific_name) return Promise.resolve(verified);
      throw new Error("provider unavailable");
    },
  );
  assertEquals(result.candidates.length, 1);
  assertEquals(result.unresolvedCount, 1);
  assertEquals(result.rejectedCount, 0);
});

Deno.test("lookalike candidates - canonical self aliases and duplicate accepted names are excluded", async () => {
  const result = await prepareLookalikeCandidates(
    "Pyracantha angustifolia",
    primary,
    [
      entry,
      { scientific_name: "Mespilus pyracantha", common_name: null },
      { scientific_name: "Cotoneaster angustifolius", common_name: null },
    ],
    (name) =>
      Promise.resolve({
        ...verified,
        scientific_name: name === "Cotoneaster angustifolius"
          ? "Pyracantha angustifolia"
          : entry.scientific_name,
      }),
  );
  assertEquals(result.candidates.length, 1);
  assertEquals(result.rejectedCount, 2);
});

Deno.test("lookalike candidates - positive taxonomic incompatibility is distinct from missing validation", async () => {
  assertEquals(
    lookalikeTaxonomyCompatibility(primary, {
      kingdom: "Animalia",
      order: "Rosales",
    }),
    "incompatible",
  );
  assertEquals(
    lookalikeTaxonomyCompatibility(primary, {
      kingdom: "Plantae",
      order: "Unknown",
      family: "Rosaceae",
    }),
    "incomplete",
  );
  assertEquals(
    lookalikeTaxonomyCompatibility({ kingdom: "Plantae", family: "Rosaceae" }, {
      kingdom: "plantae",
      family: "rosaceae",
    }),
    "compatible",
  );
  assertEquals(
    lookalikeTaxonomyCompatibility(primary, {
      kingdom: "unavailable",
      order: "Rosales",
    }),
    "incomplete",
  );
  const result = await prepareLookalikeCandidates(
    "Pyracantha angustifolia",
    primary,
    [entry],
    () => Promise.resolve({ ...verified, kingdom: "Animalia" }),
  );
  assertEquals(result.candidates, []);
  assertEquals(result.rejectedCount, 1);
  assertEquals(result.unresolvedCount, 0);
});

Deno.test("lookalike candidates - work is capped and malformed model names fail instead of completing empty", async () => {
  assertEquals(
    normalizeLookalikeCandidates(
      Array.from(
        { length: 10 },
        (_, index) => ({
          scientific_name: `Example species${index}`,
          common_name: null,
        }),
      ),
    ).length,
    3,
  );
  assertEquals(
    normalizeLookalikeCandidates([entry, {
      ...entry,
      scientific_name: " PYRACANTHA   COCCINEA ",
    }]).length,
    1,
  );
  await assertRejects(
    () =>
      prepareLookalikeCandidates("Pyracantha angustifolia", primary, [{
        scientific_name: " ",
        common_name: null,
      }]),
    Error,
    "invalid species name",
  );
});
