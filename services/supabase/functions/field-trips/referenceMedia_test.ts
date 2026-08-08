import { assertEquals } from "@std/assert";
import type { PublicSpeciesReferenceImage } from "../_shared/publicSpeciesProjection.ts";
import {
  attachFieldTripReferenceSpecies,
  FIELD_TRIP_REFERENCE_SPECIES_BY_GOAL,
  fieldTripReferenceTargets,
  oneReferenceImagePerSource,
} from "./referenceMedia.ts";

Deno.test("active Field Trip goals have one curated representative species", () => {
  assertEquals(FIELD_TRIP_REFERENCE_SPECIES_BY_GOAL, {
    backyard_safari: {
      Bird: "Passer domesticus",
      Dog: "Canis lupus familiaris",
      Butterfly: "Danaus plexippus",
      Cat: "Felis catus",
      Spider: "Araneus diadematus",
      "Flowering plant": "Bellis perennis",
      Fungus: "Trametes versicolor",
      Insect: "Coccinella septempunctata",
      "Urban wild animal": "Sciurus carolinensis",
      "Moss or lichen": "Bryum argenteum",
    },
    park_pollinators: {
      "Flowering plant": "Taraxacum officinale",
      "Butterfly or moth": "Danaus plexippus",
      "Bee or wasp": "Apis mellifera",
      Fly: "Eristalis tenax",
      Beetle: "Coccinella septempunctata",
      Spider: "Araneus diadematus",
      "Seed or fruiting plant": "Fragaria vesca",
      Bird: "Passer domesticus",
      "Wild plant": "Achillea millefolium",
      "Meadow plant": "Trifolium pratense",
    },
  });
});

Deno.test("reference targets preserve checklist order and ignore unknown goals", () => {
  const targets = fieldTripReferenceTargets({
    slug: "backyard_safari",
    levels: [{
      items: [
        { item_id: "bird", prompt: "Bird" },
        { item_id: "future", prompt: "Future goal" },
        { item_id: "dog", prompt: "Dog" },
        { item_id: "bird", prompt: "Bird" },
      ],
    }],
  });

  assertEquals(targets, [
    { itemId: "bird", scientificName: "Passer domesticus" },
    { itemId: "dog", scientificName: "Canis lupus familiaris" },
  ]);
  assertEquals(
    fieldTripReferenceTargets({ slug: "future_trip", levels: [] }),
    [],
  );
});

Deno.test("reference selection keeps one image per provider in fallback order", () => {
  const images: PublicSpeciesReferenceImage[] = [
    image("gbif-one", "gbif"),
    image("wiki-one", "wikipedia"),
    image("naturebook-one", "merian"),
    image("wiki-two", "wikipedia"),
    image("gbif-two", "gbif"),
  ];

  assertEquals(
    oneReferenceImagePerSource(images).map((candidate) => candidate.url),
    ["naturebook-one", "wiki-one", "gbif-one"],
  );
});

Deno.test("reference species attach only to their matching goal", () => {
  const template = {
    slug: "backyard_safari",
    levels: [{
      level_number: 1,
      items: [
        { item_id: "bird", prompt: "Bird", is_completed: false },
        { item_id: "future", prompt: "Future goal", is_completed: false },
      ],
    }],
  };
  const hydrated = attachFieldTripReferenceSpecies(
    template,
    new Map([[
      "Passer domesticus",
      {
        scientific_name: "Passer domesticus",
        common_name: "House Sparrow",
        reference_images: [image("naturebook-bird", "merian")],
      },
    ]]),
  ) as {
    levels: Array<{ items: Array<Record<string, unknown>> }>;
  };

  assertEquals(hydrated.levels[0].items[0].reference_species, {
    scientific_name: "Passer domesticus",
    common_name: "House Sparrow",
    reference_images: [image("naturebook-bird", "merian")],
  });
  assertEquals(hydrated.levels[0].items[1].reference_species, undefined);
});

function image(
  url: string,
  source: PublicSpeciesReferenceImage["source"],
): PublicSpeciesReferenceImage {
  return { url, source };
}
