import type {
  PublicReferenceImageSource,
  PublicSpeciesReferenceImage,
} from "../_shared/publicSpeciesProjection.ts";

export interface FieldTripReferenceTarget {
  itemId: string;
  scientificName: string;
  commonName: string;
}

export interface FieldTripReferenceSpeciesPayload {
  scientific_name: string;
  common_name: string;
  reference_images: PublicSpeciesReferenceImage[];
}

const REFERENCE_SOURCE_ORDER: PublicReferenceImageSource[] = [
  "merian",
  "wikipedia",
  "gbif",
];

// Field Trip goals can describe a broad taxon or ecological signal rather than
// one exact species. This reviewed catalog chooses an illustrative species for
// each active goal without changing the database-owned completion matcher.
export const FIELD_TRIP_REFERENCE_SPECIES_BY_GOAL: Readonly<
  Record<string, Readonly<Record<string, string>>>
> = {
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
};

const FIELD_TRIP_REFERENCE_COMMON_NAME_BY_SCIENTIFIC_NAME: Readonly<
  Record<string, string>
> = {
  "Passer domesticus": "House Sparrow",
  "Canis lupus familiaris": "Domestic Dog",
  "Danaus plexippus": "Monarch",
  "Felis catus": "Domestic Cat",
  "Araneus diadematus": "Cross Orbweaver",
  "Bellis perennis": "Common Daisy",
  "Trametes versicolor": "Turkey Tail",
  "Coccinella septempunctata": "Seven-spotted Lady Beetle",
  "Sciurus carolinensis": "Eastern Gray Squirrel",
  "Bryum argenteum": "Silvergreen Bryum Moss",
  "Taraxacum officinale": "Common Dandelion",
  "Apis mellifera": "Western Honey Bee",
  "Eristalis tenax": "Common Drone Fly",
  "Fragaria vesca": "Wild Strawberry",
  "Achillea millefolium": "Common Yarrow",
  "Trifolium pratense": "Red Clover",
};

export function fieldTripReferenceTargets(
  template: unknown,
  maximumCount = 60,
): FieldTripReferenceTarget[] {
  if (!isRecord(template)) return [];

  const limit = Math.max(0, Math.trunc(maximumCount));
  if (limit === 0) return [];

  const slug = stringValue(template.slug);
  const mapping = slug == null
    ? undefined
    : FIELD_TRIP_REFERENCE_SPECIES_BY_GOAL[slug];
  if (!mapping || !Array.isArray(template.levels)) return [];

  const targets: FieldTripReferenceTarget[] = [];
  const seenItemIds = new Set<string>();

  for (const level of template.levels) {
    if (!isRecord(level) || !Array.isArray(level.items)) continue;

    for (const item of level.items) {
      if (!isRecord(item)) continue;
      const itemId = stringValue(item.item_id);
      const prompt = stringValue(item.prompt);
      const scientificName = prompt == null ? undefined : mapping[prompt];
      if (!itemId || !scientificName || seenItemIds.has(itemId)) continue;

      seenItemIds.add(itemId);
      targets.push({
        itemId,
        scientificName,
        commonName:
          FIELD_TRIP_REFERENCE_COMMON_NAME_BY_SCIENTIFIC_NAME[scientificName] ??
            scientificName,
      });
      if (targets.length >= limit) return targets;
    }
  }

  return targets;
}

export function fieldTripActiveReferenceTargets(
  template: unknown,
  maximumCount = 6,
): FieldTripReferenceTarget[] {
  if (!isRecord(template) || !Array.isArray(template.levels)) return [];

  const progress = isRecord(template.active_progress)
    ? template.active_progress
    : isRecord(template.stopped_progress)
    ? template.stopped_progress
    : null;
  const progressLevelNumber = positiveInteger(progress?.current_level_number);
  const firstLevelNumber = template.levels.reduce<number | null>(
    (minimum, level) => {
      if (!isRecord(level)) return minimum;
      const levelNumber = positiveInteger(level.level_number);
      if (levelNumber == null) return minimum;
      return minimum == null ? levelNumber : Math.min(minimum, levelNumber);
    },
    null,
  );
  const activeLevelNumber = progressLevelNumber ?? firstLevelNumber;
  if (activeLevelNumber == null) return [];

  return fieldTripReferenceTargets({
    ...template,
    levels: template.levels.filter((level) =>
      isRecord(level) &&
      positiveInteger(level.level_number) === activeLevelNumber
    ),
  }, maximumCount);
}

export function oneReferenceImagePerSource(
  images: PublicSpeciesReferenceImage[],
): PublicSpeciesReferenceImage[] {
  const selected: PublicSpeciesReferenceImage[] = [];
  for (const source of REFERENCE_SOURCE_ORDER) {
    const image = images.find((candidate) => candidate.source === source);
    if (image) selected.push(image);
  }
  return selected;
}

export function attachFieldTripReferenceSpecies(
  template: unknown,
  speciesByScientificName: ReadonlyMap<
    string,
    FieldTripReferenceSpeciesPayload
  >,
): unknown {
  if (!isRecord(template)) return template;
  const slug = stringValue(template.slug);
  const mapping = slug == null
    ? undefined
    : FIELD_TRIP_REFERENCE_SPECIES_BY_GOAL[slug];
  if (!mapping || !Array.isArray(template.levels)) return template;

  return {
    ...template,
    levels: template.levels.map((level) => {
      if (!isRecord(level) || !Array.isArray(level.items)) return level;
      return {
        ...level,
        items: level.items.map((item) => {
          if (!isRecord(item)) return item;
          const prompt = stringValue(item.prompt);
          const scientificName = prompt == null ? undefined : mapping[prompt];
          const species = scientificName == null
            ? undefined
            : speciesByScientificName.get(scientificName);
          return species == null
            ? item
            : { ...item, reference_species: species };
        }),
      };
    }),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function positiveInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0
    ? value
    : null;
}
