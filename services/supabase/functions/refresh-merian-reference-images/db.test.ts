import { assertEquals } from "@std/assert";
import { SupabaseClient } from "@supabase/supabase-js";
import {
  parseMerianReferenceImageRefreshRequest,
  runMerianReferenceImageRefresh,
} from "./db.ts";

Deno.test("refresh merian reference images - parses defaults and custom request", () => {
  const defaults = parseMerianReferenceImageRefreshRequest({});
  assertEquals(defaults.request, {
    qualityThreshold: 80,
    speciesConfidenceThreshold: 0.95,
    perSpeciesLimit: 8,
    dryRun: false,
  });

  const custom = parseMerianReferenceImageRefreshRequest({
    quality_threshold: 95,
    species_confidence_threshold: 0.98,
    per_species_limit: 4,
    dry_run: true,
  });
  assertEquals(custom.request, {
    qualityThreshold: 95,
    speciesConfidenceThreshold: 0.98,
    perSpeciesLimit: 4,
    dryRun: true,
  });

  const camelCase = parseMerianReferenceImageRefreshRequest({
    qualityThreshold: 91,
    speciesConfidenceThreshold: 0.97,
    perSpeciesLimit: 12,
    dryRun: true,
  });
  assertEquals(camelCase.request, {
    qualityThreshold: 91,
    speciesConfidenceThreshold: 0.97,
    perSpeciesLimit: 12,
    dryRun: true,
  });
});

Deno.test("refresh merian reference images - validates request bounds", () => {
  assertEquals(
    parseMerianReferenceImageRefreshRequest({ quality_threshold: 101 }),
    {
      error: "quality_threshold must be an integer from 0 to 100.",
      status: 400,
    },
  );
  assertEquals(
    parseMerianReferenceImageRefreshRequest({
      species_confidence_threshold: 1.1,
    }),
    {
      error: "species_confidence_threshold must be a number from 0 to 1.",
      status: 400,
    },
  );
  assertEquals(
    parseMerianReferenceImageRefreshRequest({ per_species_limit: 0 }),
    {
      error: "per_species_limit must be an integer from 1 to 50.",
      status: 400,
    },
  );
  assertEquals(parseMerianReferenceImageRefreshRequest({ dry_run: "true" }), {
    error: "dry_run must be a boolean.",
    status: 400,
  });
});

Deno.test("refresh merian reference images - calls transactional RPC", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const supabase = {
    rpc(name: string, params: Record<string, unknown>) {
      calls.push({ name, params });
      return Promise.resolve({
        data: [{
          candidate_count: 10,
          promoted_count: 8,
          removed_count: 2,
          species_count: 3,
          dry_run: false,
        }],
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  const result = await runMerianReferenceImageRefresh({
    qualityThreshold: 80,
    speciesConfidenceThreshold: 0.95,
    perSpeciesLimit: 8,
    dryRun: false,
  }, supabase);

  assertEquals(calls, [{
    name: "refresh_merian_reference_images",
    params: {
      p_quality_threshold: 80,
      p_per_species_limit: 8,
      p_dry_run: false,
      p_species_confidence_threshold: 0.95,
    },
  }]);
  assertEquals(result, {
    candidate_count: 10,
    promoted_count: 8,
    removed_count: 2,
    species_count: 3,
    dry_run: false,
  });
});
