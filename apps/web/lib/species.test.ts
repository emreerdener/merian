import assert from "node:assert/strict";
import test from "node:test";
import { appleAppSiteAssociation } from "./appleAppSiteAssociation.ts";
import {
  canonicalSpeciesDictionaryPath,
  fetchSpeciesDictionary,
  nativeSpeciesDictionaryUrl,
  normalizedSpeciesDictionaryId,
  parseSpeciesDictionaryResponse,
  speciesDictionaryMetadataValues,
  speciesDictionaryRedirectPath,
  speciesDictionarySlug,
  SpeciesDictionaryUpstreamError,
  speciesDictionaryPath,
  webSafeReferenceImages,
} from "./species.ts";

const speciesId = "1cf79982-e5ee-4e3d-8d65-274527e6ae01";

test("builds canonical web and native species URLs from UUIDs", () => {
  assert.equal(normalizedSpeciesDictionaryId(` ${speciesId.toUpperCase()} `), speciesId);
  assert.equal(speciesDictionaryPath(speciesId), `/species/${speciesId}`);
  assert.equal(
    canonicalSpeciesDictionaryPath(speciesId, "Monarch Butterfly", "Danaus plexippus"),
    `/species/${speciesId}/monarch-butterfly`,
  );
  assert.equal(
    nativeSpeciesDictionaryUrl(speciesId),
    `naturebook://species/${speciesId}`,
  );
  assert.equal(speciesDictionaryPath("species-123"), null);
  assert.equal(
    canonicalSpeciesDictionaryPath("species-123", "Monarch Butterfly", "Danaus plexippus"),
    null,
  );
  assert.equal(nativeSpeciesDictionaryUrl("species-123"), null);
});

test("builds stable ASCII slugs with scientific and generic fallbacks", () => {
  assert.equal(
    speciesDictionarySlug("  Mwanza flat-headed rock agama  ", "Agama mwanzae"),
    "mwanza-flat-headed-rock-agama",
  );
  assert.equal(speciesDictionarySlug("Café-à-lait!", "Testus example"), "cafe-a-lait");
  assert.equal(speciesDictionarySlug("", "Agama mwanzae"), "agama-mwanzae");
  assert.equal(speciesDictionarySlug("東京", "Agama mwanzae"), "agama-mwanzae");
  assert.equal(speciesDictionarySlug("東京", ""), "species");
  assert.ok(speciesDictionarySlug("a ".repeat(100), "").length <= 80);
});

test("redirects UUID-only and stale-slug paths to the current canonical URL", () => {
  const canonicalPath = `/species/${speciesId}/monarch-butterfly`;
  assert.equal(
    speciesDictionaryRedirectPath(
      speciesId,
      "Monarch Butterfly",
      "Danaus plexippus",
      undefined,
    ),
    canonicalPath,
  );
  assert.equal(
    speciesDictionaryRedirectPath(
      speciesId,
      "Monarch Butterfly",
      "Danaus plexippus",
      "old-common-name",
    ),
    canonicalPath,
  );
  assert.equal(
    speciesDictionaryRedirectPath(
      speciesId,
      "Monarch Butterfly",
      "Danaus plexippus",
      "monarch-butterfly",
    ),
    null,
  );
});

test("maps the shared public projection and omits private additive fields", () => {
  const species = parseSpeciesDictionaryResponse(speciesResponse());

  assert.equal(species.id, speciesId);
  assert.equal(species.commonName, "Monarch Butterfly");
  assert.deepEqual(species.alternativeCommonNames, ["Milkweed Butterfly"]);
  assert.equal(species.taxonomy.family, "Nymphalidae");
  assert.equal(species.referenceImages.length, 1);
  assert.equal(species.referenceImages[0].attribution, "Example Photographer");
  assert.equal(species.similarSpecies[0].speciesId, "8d2a0ca1-a2c3-4d4e-8f90-123456789abc");
  assert.equal("scan_id" in species, false);
  assert.equal("user_id" in species, false);
  assert.equal("field_notes" in species, false);
});

test("requires the supported public species schema version", () => {
  const response = speciesResponse() as Record<string, unknown>;
  response.schema_version = 2;
  assert.throws(
    () => parseSpeciesDictionaryResponse(response),
    SpeciesDictionaryUpstreamError,
  );
});

test("builds canonical metadata from attribution-approved public fields", () => {
  const metadata = speciesDictionaryMetadataValues(
    parseSpeciesDictionaryResponse(speciesResponse()),
  );

  assert.deepEqual(metadata, {
    title: "Monarch Butterfly",
    description: "Monarch Butterfly (Danaus plexippus): A milkweed butterfly known for migration.",
    canonicalPath: `/species/${speciesId}/monarch-butterfly`,
    socialImageUrl: "https://upload.wikimedia.org/monarch.jpg",
  });
});

test("publishes only reference images with complete web attribution", () => {
  const images = webSafeReferenceImages([
    {
      url: "https://upload.wikimedia.org/monarch.jpg",
      source: "wikipedia",
      license: "CC BY-SA 4.0",
      attribution: "Example Photographer",
    },
    {
      url: "https://static.inaturalist.org/unattributed.jpg",
      source: "gbif",
      license: "CC BY 4.0",
    },
    {
      url: "http://example.com/insecure.jpg",
      source: "gbif",
      license: "CC BY 4.0",
      attribution: "Example",
    },
  ]);

  assert.deepEqual(images.map((image) => image.url), [
    "https://upload.wikimedia.org/monarch.jpg",
  ]);
});

test("returns not found only for marked handler-owned function 404 responses", async () => {
  let invoked = false;
  assert.equal(await fetchSpeciesDictionary("not-a-uuid", async () => {
    invoked = true;
    return { data: null, error: null };
  }), null);
  assert.equal(invoked, false);

  assert.equal(await fetchSpeciesDictionary(speciesId, async () => ({
    data: null,
    error: {
      context: {
        status: 404,
        headers: new Headers({ "X-Merian-Handler": "1" }),
      },
    },
  })), null);
});

test("propagates an unmarked platform function 404 instead of caching it as missing", async () => {
  await assert.rejects(
    fetchSpeciesDictionary(speciesId, async () => ({
      data: null,
      error: {
        context: {
          status: 404,
          headers: new Headers({ "SB-Error-Code": "NOT_FOUND" }),
        },
      },
    })),
    (error: unknown) => {
      assert.ok(error instanceof SpeciesDictionaryUpstreamError);
      assert.equal(error.status, 404);
      return true;
    },
  );
});

test("propagates transient function failures instead of caching them as missing", async () => {
  await assert.rejects(
    fetchSpeciesDictionary(speciesId, async () => ({
      data: null,
      error: { context: { status: 503 } },
    })),
    (error: unknown) => {
      assert.ok(error instanceof SpeciesDictionaryUpstreamError);
      assert.equal(error.status, 503);
      return true;
    },
  );
});

test("AASA includes both Explore posts and species pages", () => {
  assert.deepEqual(
    appleAppSiteAssociation.applinks.details[0].paths,
    ["/explore/post/*", "/species/*"],
  );
});

function speciesResponse() {
  return {
    schema_version: 1,
    data: {
      id: speciesId,
      scientific_name: "Danaus plexippus",
      common_name: "Monarch Butterfly",
      content_quality: "complete",
      alternative_common_names: ["Milkweed Butterfly"],
      taxonomy: {
        kingdom: "Animalia",
        phylum: "Arthropoda",
        class: "Insecta",
        order: "Lepidoptera",
        family: "Nymphalidae",
        genus: "Danaus",
      },
      hazard_type: "none",
      iucn_red_list_status: "least concern",
      wikipedia_url: "https://en.wikipedia.org/wiki/Monarch_butterfly",
      wikipedia_overview: "A milkweed butterfly known for migration.",
      habitat_description: "Open meadows and milkweed patches.",
      gbif_taxon_key: 5139790,
      group_tags: ["animal", "insect"],
      reference_images: [
        {
          url: "https://upload.wikimedia.org/monarch.jpg",
          source: "wikipedia",
          license: "CC BY-SA 4.0",
          attribution: "Example Photographer",
          width: 1200,
          height: 800,
        },
        {
          url: "https://static.inaturalist.org/unattributed.jpg",
          source: "gbif",
        },
      ],
      similar_species: [
        {
          species_id: "8d2a0ca1-a2c3-4d4e-8f90-123456789abc",
          scientific_name: "Limenitis archippus",
          common_name: "Viceroy",
          iucn_red_list_status: "least concern",
          reference_image_url: "https://example.com/viceroy.jpg",
        },
      ],
      scan_id: "private-scan",
      user_id: "private-user",
      field_notes: "private notes",
    },
  };
}
