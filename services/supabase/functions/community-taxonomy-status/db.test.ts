import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  normalizeEnrichmentJobRow,
  parseCommunityTaxonomyStatusRequest,
} from "./db.ts";

Deno.test("community taxonomy status - parses defaults and aliases", () => {
  const defaultResult = parseCommunityTaxonomyStatusRequest({});
  assertEquals(defaultResult.request?.importRunLimit, 10);
  assertEquals(defaultResult.request?.jobLimit, 10);
  assertEquals(defaultResult.request?.view, "full");
  assertEquals(defaultResult.request?.target, null);

  const snakeCaseResult = parseCommunityTaxonomyStatusRequest({
    import_run_limit: 6,
    job_limit: 4,
  });
  assertEquals(snakeCaseResult.request?.importRunLimit, 6);
  assertEquals(snakeCaseResult.request?.jobLimit, 4);

  const camelCaseResult = parseCommunityTaxonomyStatusRequest({
    importRunLimit: 7,
    failureLimit: 3,
    view: "coverage",
    target: "birds",
  });
  assertEquals(camelCaseResult.request?.importRunLimit, 7);
  assertEquals(camelCaseResult.request?.jobLimit, 3);
  assertEquals(camelCaseResult.request?.view, "coverage");
  assertEquals(camelCaseResult.request?.target, "birds");
});

Deno.test("community taxonomy status - rejects invalid limits", () => {
  assertEquals(parseCommunityTaxonomyStatusRequest({ import_run_limit: 0 }), {
    error: "import_run_limit must be an integer from 1 to 50.",
    status: 400,
  });
  assertEquals(parseCommunityTaxonomyStatusRequest({ job_limit: 51 }), {
    error: "job_limit must be an integer from 1 to 50.",
    status: 400,
  });
  assertEquals(parseCommunityTaxonomyStatusRequest({ job_limit: "many" }), {
    error: "job_limit must be an integer from 1 to 50.",
    status: 400,
  });
  assertEquals(parseCommunityTaxonomyStatusRequest({ view: "summary" }), {
    error: "view must be full or coverage.",
    status: 400,
  });
  assertEquals(parseCommunityTaxonomyStatusRequest({ target: "mammals" }), {
    error: "Unsupported taxonomy status target.",
    status: 400,
  });
});

Deno.test("community taxonomy status - normalizes species common_names", () => {
  const row = normalizeEnrichmentJobRow({
    id: "job-1",
    species_id: "species-1",
    species: {
      scientific_name: "Setophaga petechia",
      common_names: { en: " Yellow Warbler " },
    },
  });

  assertEquals(row.scientific_name, "Setophaga petechia");
  assertEquals(row.common_name, "Yellow Warbler");
  assertEquals(row.species, undefined);
});
