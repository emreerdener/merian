import { assertEquals, assertThrows } from "@std/assert";
import {
  analysisIdentification,
  type BoundAnalysisEvidence,
  type BoundAnalysisReview,
  publicationAuthority,
} from "./authority.ts";
import { HistoryError } from "./contract.ts";

const observation = "00000000-0000-4000-8000-000000000001";
const analysis = "00000000-0000-4000-8000-000000000002";
const species = "00000000-0000-4000-8000-000000000003";
const evidence: BoundAnalysisEvidence = {
  observation_id: observation,
  analysis_id: analysis,
  fields: { species_id: species, is_biological_subject: true },
};
const review = (
  fields: BoundAnalysisReview["fields"] = {},
): BoundAnalysisReview => ({
  observation_id: observation,
  analysis_id: analysis,
  review_revision: 1,
  fields,
});
const rejected = {
  version: 1,
  revision: 1,
  state: "ai_rejected",
  origin_scan_id: observation,
  origin_identification: null,
  operation_id: null,
  operation_digest: null,
  community: null,
};
const visibility = { privacyPermits: true, moderationPermits: true };

Deno.test("analysis selection preserves unreviewed eligibility without confirming", () => {
  const projection = analysisIdentification(evidence, review());
  assertEquals(projection.source, "legacy");
  assertEquals(projection.species_id, species);
  assertEquals(projection.verified, false);
});

Deno.test("confirmation from another result cannot authorize selected evidence", () => {
  assertThrows(
    () =>
      analysisIdentification(evidence, {
        ...review({ confirmed_species_id: species }),
        analysis_id: observation,
      }),
    HistoryError,
  );
});

Deno.test("rejected and awaiting acceptance analyses confer no species", () => {
  for (const state of ["ai_rejected", "awaiting_acceptance"]) {
    const projection = analysisIdentification(
      evidence,
      review({
        ai_identification_review: { ...rejected, state },
        confirmed_species_id: species,
      }),
    );
    assertEquals(projection.species_id, null);
    assertEquals(projection.pending_review, true);
    assertEquals(projection.verified, false);
  }
});

Deno.test("nonbiological history never inherits a stale species association", () => {
  const projection = analysisIdentification({
    ...evidence,
    fields: { ...evidence.fields, is_biological_subject: false },
  }, review({ confirmed_species_id: species }));
  assertEquals(projection.rank, "non_biological");
  assertEquals(projection.species_id, null);
});

Deno.test("withdrawn published authority becomes unresolved without unpublishing discussion", () => {
  const published = publicationAuthority(
    evidence,
    review({ ai_identification_review: rejected }),
    visibility,
  );
  assertEquals(published.status, "unresolved");
  assertEquals(published.identification?.species_id, null);
  assertEquals(published.identification?.verified, false);
});

Deno.test("genus community resolution is visible but cannot claim species credit", () => {
  const published = publicationAuthority(
    evidence,
    review({
      ai_identification_review: {
        ...rejected,
        state: "clear",
        community: {
          request_id: observation,
          rank: "genus",
          scientific_name: "Synthetic genus",
          common_name: null,
          species_id: null,
        },
      },
    }),
    visibility,
  );
  assertEquals(published.status, "current");
  assertEquals(published.identification?.rank, "genus");
  assertEquals(published.identification?.species_id, null);
});

Deno.test("current privacy and moderation may hide a historical publication", () => {
  assertEquals(
    publicationAuthority(evidence, review(), {
      ...visibility,
      privacyPermits: false,
    }),
    { status: "hidden", identification: null },
  );
  assertEquals(
    publicationAuthority(evidence, review(), {
      ...visibility,
      moderationPermits: false,
    }),
    { status: "hidden", identification: null },
  );
});
