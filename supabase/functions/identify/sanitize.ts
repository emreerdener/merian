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

// Removes trailing author citations from a name string that contains no cultivar.
// Author strings start after the specific epithet with an uppercase letter or "(".
// Rank markers (var., subsp., f.) and hybrid markers (×) are not author strings.
export function stripAuthors(name: string): string {
  const rankMarkers = new Set(["var.", "subsp.", "f.", "ssp.", "cv.", "×", "x"]);
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
      if (i === genusIndex) return token.charAt(0).toUpperCase() + token.slice(1).toLowerCase(); // genus
      if (rankMarkers.has(token.toLowerCase())) return token.toLowerCase(); // rank marker
      return token.toLowerCase(); // specific epithet and infraspecific names
    })
    .join(" ");
}
