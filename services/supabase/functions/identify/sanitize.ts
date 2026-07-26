// ---------------------------------------------------------------------------
// Scientific Name Sanitization
// ---------------------------------------------------------------------------
//
// Applied to every scientific_name before it touches species_dictionary or
// the candidates JSONB payload. Ensures the database is interoperable with
// GBIF, iNaturalist, and partner taxonomy systems.
//
// Rules applied (in order):
//   1. Trim leading/trailing whitespace and collapse internal runs of spaces.
//   2. Strip author citations — e.g. "Rosa canina L." → "Rosa canina".
//      Author strings follow the specific epithet and begin with an uppercase
//      letter or parenthesis: "(L.)", "Karst.", "DC.", "Thunb. ex Murray".
//      Cultivar epithets in single quotes are NOT author citations and are kept.
//   3. Strip uncertainty qualifiers — "cf.", "aff.", "sp." — that indicate
//      the identification is tentative. These should be surfaced in a separate
//      confidence field, not embedded in the name key used for DB lookups.
//   4. Normalise capitalisation: genus capitalised, specific epithet and
//      infraspecific rank markers ("var.", "subsp.", "f.") lowercase.
//      Cultivar names in single quotes are preserved in their original case
//      per ICNCP convention (Title Case inside the quotes is standard).
//   5. Preserve hybrid markers (×) — "× Heucherella" is correct notation.
//
// Examples:
//   "rosa 'Radrazz'"              → "Rosa 'Radrazz'"
//   "Rosa canina L."              → "Rosa canina"
//   "Quercus robur (L.) Karst."   → "Quercus robur"
//   "cf. Pinus ponderosa"         → "Pinus ponderosa"
//   "Acer Palmatum"               → "Acer palmatum"
//   "Boletus edulis var. Edulis"  → "Boletus edulis var. edulis"
// ---------------------------------------------------------------------------

export function sanitizeScientificName(name: string): string {
  if (!name) return name;

  // 1. Collapse whitespace
  let s = name.trim().replace(/\s+/g, " ");

  // 2. Strip uncertainty qualifiers at the start
  s = s.replace(/^(cf\.|aff\.|sp\.)\s+/i, "");

  // 3. Strip author citations
  //    Strategy: split on the first single-quoted cultivar block (if present)
  //    and only process the binomial prefix — authors never appear inside quotes.
  const cultivarMatch = s.match(/^(.*?)\s*('[^']*')\s*$/);
  if (cultivarMatch) {
    const binomial = stripAuthors(cultivarMatch[1].trim());
    const cultivar = cultivarMatch[2]; // preserve case per ICNCP
    s = `${binomial} ${cultivar}`;
  } else {
    s = stripAuthors(s);
  }

  // 4. Normalise capitalisation on the binomial portion
  s = normaliseBinomialCase(s);

  return s.trim();
}

const domesticDogScientificNames = new Set([
  "canis lupus familiaris",
  "canis familiaris",
  "canis familiaris domesticus",
]);

const domesticCatScientificNames = new Set([
  "felis catus",
  "felis silvestris catus",
  "felis domesticus",
  "felis catus domesticus",
  "felis silvestris domesticus",
]);

const domesticDogCommonNames = new Set([
  "dog",
  "domestic dog",
  "domesticated dog",
]);

const domesticCatCommonNames = new Set([
  "cat",
  "domestic cat",
  "domesticated cat",
  "house cat",
]);

function normalizedText(value: string | null | undefined): string {
  return value?.trim().replace(/\s+/g, " ").toLowerCase() ?? "";
}

function petSpeciesGroup(value: unknown): "dog" | "cat" | null {
  if (value == null || typeof value !== "object") return null;
  const speciesGroup = (value as Record<string, unknown>).species_group;
  if (speciesGroup === "dog" || speciesGroup === "cat") return speciesGroup;
  return null;
}

export function canonicalizeDomesticPetScientificName(
  scientificName: string,
  petIdentification?: unknown,
  commonName?: string | null,
): string {
  const normalized = normalizedText(scientificName);
  if (domesticDogScientificNames.has(normalized)) {
    return "Canis lupus familiaris";
  }
  if (domesticCatScientificNames.has(normalized)) {
    return "Felis catus";
  }

  const group = petSpeciesGroup(petIdentification);
  const normalizedCommon = normalizedText(commonName);
  if (
    normalized === "canis lupus" &&
    group === "dog" &&
    domesticDogCommonNames.has(normalizedCommon)
  ) {
    return "Canis lupus familiaris";
  }
  if (
    normalized === "felis silvestris" &&
    group === "cat" &&
    domesticCatCommonNames.has(normalizedCommon)
  ) {
    return "Felis catus";
  }

  return scientificName;
}

// Removes trailing author citations from a name string that contains no cultivar.
// Author strings start after the specific epithet with an uppercase letter or "(".
// Rank markers (var., subsp., f.) and hybrid markers (×) are not author strings.
export function stripAuthors(name: string): string {
  const rankMarkers = new Set([
    "var.",
    "subsp.",
    "f.",
    "ssp.",
    "cv.",
    "×",
    "x",
  ]);
  const tokens = name.split(" ");
  let cutAt = tokens.length;

  for (let i = 2; i < tokens.length; i++) { // genus + epithet always kept
    const token = tokens[i];
    const prev = tokens[i - 1]?.toLowerCase();
    if (rankMarkers.has(prev)) continue; // next token after rank marker is a name, not author
    if (/^[A-Z(]/.test(token) && !rankMarkers.has(token.toLowerCase())) {
      cutAt = i;
      break;
    }
  }

  return tokens.slice(0, cutAt).join(" ");
}

// Genus capitalised, everything else lowercase except cultivar quotes and × marker.
// When × leads the name (hybrid intergeneric notation), the genus is at index 1.
export function normaliseBinomialCase(name: string): string {
  const rankMarkers = new Set(["var.", "subsp.", "f.", "ssp.", "cv."]);
  const tokens = name.split(" ");
  const genusIndex = tokens[0] === "×" ? 1 : 0;
  return tokens
    .map((token, i) => {
      if (token.startsWith("'") && token.endsWith("'")) return token; // cultivar — keep as-is
      if (token === "×") return token; // hybrid marker
      if (i === genusIndex) {
        return token.charAt(0).toUpperCase() + token.slice(1).toLowerCase(); // genus
      }
      if (rankMarkers.has(token.toLowerCase())) return token.toLowerCase(); // rank marker
      return token.toLowerCase(); // specific epithet and infraspecific names
    })
    .join(" ");
}

export type SanitizedPetIdentification = {
  species_group: "dog" | "cat";
  label: string;
  label_type: "breed" | "breed_mix" | "coat_pattern" | "body_type";
  confidence_score: number;
  evidence: string[];
};

const genericPetLabels = new Set([
  "dog",
  "cat",
  "domestic dog",
  "domestic cat",
  "house cat",
  "canis lupus familiaris",
  "felis catus",
]);

const allowedPetLabelTypes = new Set([
  "breed",
  "breed_mix",
  "coat_pattern",
  "body_type",
]);

function expectedPetGroup(
  scientificName: string | null | undefined,
): "dog" | "cat" | null {
  const normalized = normalizedText(scientificName);
  if (domesticDogScientificNames.has(normalized)) return "dog";
  if (domesticCatScientificNames.has(normalized)) return "cat";
  return null;
}

function cleanPetText(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.trim().replace(/\s+/g, " ");
  if (!cleaned) return null;
  return cleaned.slice(0, maxLength);
}

export function sanitizePetIdentification(
  value: unknown,
  scientificName: string | null | undefined,
): SanitizedPetIdentification | null {
  const speciesGroup = expectedPetGroup(scientificName);
  if (!speciesGroup || value == null || typeof value !== "object") return null;

  const input = value as Record<string, unknown>;
  if (input.species_group !== speciesGroup) return null;

  const label = cleanPetText(input.label, 80);
  if (!label || genericPetLabels.has(label.toLowerCase())) return null;

  const labelType = input.label_type;
  if (typeof labelType !== "string" || !allowedPetLabelTypes.has(labelType)) {
    return null;
  }

  const rawConfidence = Number(input.confidence_score);
  if (!Number.isFinite(rawConfidence) || rawConfidence < 0.70) return null;
  const confidenceScore = Math.min(1, Math.max(0, rawConfidence));

  const evidence = Array.isArray(input.evidence)
    ? input.evidence
      .map((entry) => cleanPetText(entry, 120))
      .filter((entry): entry is string => !!entry)
      .slice(0, 3)
    : [];
  if (evidence.length === 0) return null;

  return {
    species_group: speciesGroup,
    label,
    label_type: labelType as SanitizedPetIdentification["label_type"],
    confidence_score: confidenceScore,
    evidence,
  };
}
