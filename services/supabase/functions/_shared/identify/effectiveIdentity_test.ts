import {
  fixtureSpeciesID as id,
  savedIdentityFixture,
} from "../../_tests/primaryIdentityTestHelpers.ts";
import { assertEquals } from "@std/assert";
import { effectiveIdentification } from "./effectiveIdentity.ts";
Deno.test("saved identity preserves broad rank without any species association", () => {
  for (
    const rank of ["genus", "family", "unresolved_biological", "non_biological"]
  ) {
    const result = effectiveIdentification(savedIdentityFixture(rank));
    assertEquals([result.source, result.rank, result.species_id], [
      "ai_primary",
      rank,
      null,
    ]);
  }
  assertEquals(effectiveIdentification({ species_id: id }).source, "legacy");
  assertEquals(effectiveIdentification({ species_id: id }).species_id, id);
});
Deno.test("saved identity keeps verified replacement separate and clear restores original rank", () => {
  const original = savedIdentityFixture();
  const selected = {
    ...original,
    confirmed_species_identity_revision: 1,
    confirmed_species_id: id,
    user_review_state: "user_overridden",
    user_identification_override: "Fixtureus accepted",
    confirmed_species_identity: {
      version: 1,
      species_id: id,
      scientific_name: "Fixtureus accepted",
      common_name: null,
      gbif_taxon_key: 987600001,
    },
  };
  const identity = effectiveIdentification(selected);
  assertEquals([
    identity.source,
    identity.rank,
    identity.species_id,
    identity.verified,
  ], ["verified_selection", "species", id, true]);
  assertEquals(identity.primary, original.primary_identification);
  const cleared = effectiveIdentification({
    ...original,
    confirmed_species_identity_revision: 2,
  });
  assertEquals([cleared.source, cleared.rank, cleared.species_id], [
    "ai_primary",
    "genus",
    null,
  ]);
});
Deno.test("bare IDs, optimistic flags, pending overrides and malformed authority cannot confer species identity", () => {
  const species = { ...savedIdentityFixture("species"), species_id: id };
  assertEquals(effectiveIdentification(species).species_id, id);
  assertEquals(
    effectiveIdentification({
      ...species,
      user_review_state: "user_overridden",
      user_identification_override: "Unverified selection",
    }).species_id,
    null,
  );
  const optimistic = effectiveIdentification({
    ...savedIdentityFixture(),
    user_review_state: "ai_confirmed",
    user_confirmed_identification: true,
  });
  assertEquals([
    optimistic.verified,
    optimistic.species_id,
    optimistic.pending_review,
  ], [false, null, true]);
  for (
    const invalid of [
      { ...savedIdentityFixture(), species_id: id },
      { ...savedIdentityFixture(), confirmed_species_id: id },
      { ...savedIdentityFixture(), primary_identification: null },
      { ...savedIdentityFixture(), primary_identification: {} },
      { ...savedIdentityFixture(), identification_provenance: null },
      { ...savedIdentityFixture(), confirmed_species_identity: {} },
      {
        ...savedIdentityFixture(),
        confirmed_species_identity_revision: undefined,
      },
      { ...savedIdentityFixture(), is_biological_subject: false },
      {
        ...species,
        candidates: [{ scientific_name: "Fixtureus alternative" }],
      },
    ]
  ) assertEquals(effectiveIdentification(invalid).source, "invalid");
});
