import { assertEquals, assertThrows } from "@std/assert";
import { parseReceipt, parseRequest } from "./contract.ts";
import { effectiveIdentification } from "../_shared/identify/effectiveIdentity.ts";
const scan = "00000000-0000-4000-8000-000000000001";
const operation = "00000000-0000-4000-8000-000000000002";
const request = {
  scan_id: scan,
  operation_id: operation,
  action: "reject",
  expected_revision: 0,
  expected_species_review_revision: null,
};
const review = {
  community: null,
  version: 1,
  revision: 1,
  state: "ai_rejected",
  origin_scan_id: scan,
  origin_identification: null,
  operation_id: operation,
  operation_digest: null,
};
Deno.test("rejection needs no replacement name or external taxonomy proof", () => {
  assertEquals(parseRequest(request).scientific_name, null);
  assertEquals(
    parseReceipt({
      schema_version: 1,
      scan_id: scan,
      review,
      species_review: null,
      confirmed_species_id: null,
    }, scan).review.state,
    "ai_rejected",
  );
});
Deno.test("review rejects client-selected owners, proof, identities and malformed revisions", () => {
  for (
    const extra of [
      { user_id: scan },
      { scientific_name: "Synthetic species" },
      { species_id: scan },
      { taxon: {} },
      { expected_revision: -1 },
      { expected_revision: 1.1 },
      { expected_revision: 999999999 },
      { action: "community_resolve" },
    ]
  ) assertThrows(() => parseRequest({ ...request, ...extra }));
});
Deno.test("acceptance requires a bounded named selection only for confirm_name", () => {
  assertThrows(() => parseRequest({ ...request, action: "confirm_name" }));
  assertEquals(
    parseRequest({
      ...request,
      action: "confirm_name",
      scientific_name: "Synthetic species",
    }).scientific_name,
    "Synthetic species",
  );
  assertThrows(() =>
    parseRequest({
      ...request,
      action: "confirm_name",
      scientific_name: "x".repeat(161),
    })
  );
});
Deno.test("rejected legacy scans and reanalysis proposals provide no effective species", () => {
  for (const state of ["ai_rejected", "awaiting_acceptance"]) {
    const identity = effectiveIdentification({
      species_id: scan,
      confirmed_species_id: scan,
      user_confirmed_identification: true,
      ai_identification_review: { ...review, state },
    });
    assertEquals(identity.species_id, null);
    assertEquals(identity.verified, false);
    assertEquals(identity.rank, "unresolved_biological");
    assertEquals(identity.pending_review, true);
  }
  assertEquals(
    effectiveIdentification({
      species_id: scan,
      ai_identification_review: { ...review, state: "clear" },
    }).species_id,
    scan,
  );
});
Deno.test("malformed review authority fails closed rather than restoring legacy species", () => {
  assertEquals(
    effectiveIdentification({
      species_id: scan,
      ai_identification_review: { ...review, revision: -1 },
    }).source,
    "invalid",
  );
  assertThrows(() =>
    parseReceipt({
      schema_version: 1,
      scan_id: operation,
      review,
      species_review: null,
      confirmed_species_id: null,
    }, scan)
  );
});
