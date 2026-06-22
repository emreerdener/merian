import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { parseCommunityTaxonomyIndexSyncRequest } from "./db.ts";

Deno.test("community taxonomy index sync - parses defaults and aliases", () => {
  const defaultResult = parseCommunityTaxonomyIndexSyncRequest({});
  assertEquals(defaultResult.request?.target.slug, "birds");
  assertEquals(defaultResult.request?.offset, 0);
  assertEquals(defaultResult.request?.limit, 50);
  assertEquals(defaultResult.request?.pageCount, 1);
  assertEquals(defaultResult.request?.dryRun, false);

  const customResult = parseCommunityTaxonomyIndexSyncRequest({
    scope: "birds",
    offset: 200,
    page_limit: 100,
    pages: 3,
    dry_run: true,
  });
  assertEquals(customResult.request?.target.rootGbifTaxonKey, 212);
  assertEquals(customResult.request?.offset, 200);
  assertEquals(customResult.request?.limit, 100);
  assertEquals(customResult.request?.pageCount, 3);
  assertEquals(customResult.request?.dryRun, true);
});

Deno.test("community taxonomy index sync - rejects unsafe inputs", () => {
  assertEquals(parseCommunityTaxonomyIndexSyncRequest({ target: "mammals" }), {
    error: "Unsupported taxonomy import target.",
    status: 400,
  });
  assertEquals(parseCommunityTaxonomyIndexSyncRequest({ offset: -1 }), {
    error: "offset must be a non-negative integer.",
    status: 400,
  });
  assertEquals(parseCommunityTaxonomyIndexSyncRequest({ limit: 201 }), {
    error: "limit must be an integer from 1 to 200.",
    status: 400,
  });
  assertEquals(parseCommunityTaxonomyIndexSyncRequest({ page_count: 6 }), {
    error: "page_count must be an integer from 1 to 5.",
    status: 400,
  });
  assertEquals(parseCommunityTaxonomyIndexSyncRequest({ dry_run: "yes" }), {
    error: "dry_run must be a boolean.",
    status: 400,
  });
});
