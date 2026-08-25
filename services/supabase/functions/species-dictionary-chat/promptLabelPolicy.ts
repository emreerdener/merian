export const SPECIES_DICTIONARY_PROMPT_LABEL_POLICY = Object.freeze({
  normalization: "none",
  maxUnicodeScalars: 64,
  allowedGeneralCategories: Object.freeze([
    "Lu",
    "Ll",
    "Lt",
    "Lm",
    "Lo",
    "Mn",
    "Mc",
    "Me",
    "Nd",
  ]),
  whitespaceCodePoints: Object.freeze([
    0x0009,
    0x000A,
    0x000B,
    0x000C,
    0x000D,
    0x0020,
    0x0085,
    0x00A0,
    0x1680,
    0x2000,
    0x2001,
    0x2002,
    0x2003,
    0x2004,
    0x2005,
    0x2006,
    0x2007,
    0x2008,
    0x2009,
    0x200A,
    0x2028,
    0x2029,
    0x202F,
    0x205F,
    0x3000,
  ]),
  punctuationCodePoints: Object.freeze([
    0x0027,
    0x0028,
    0x0029,
    0x002D,
    0x002E,
    0x2013,
    0x2019,
  ]),
});

const ALLOWED_GENERAL_CATEGORY = new RegExp(
  `^(?:${
    SPECIES_DICTIONARY_PROMPT_LABEL_POLICY.allowedGeneralCategories.map(
      (category) => `\\p{${category}}`,
    ).join("|")
  })$`,
  "u",
);

const NORMALIZED_WHITESPACE = new Set(
  SPECIES_DICTIONARY_PROMPT_LABEL_POLICY.whitespaceCodePoints,
);
const ALLOWED_PUNCTUATION = new Set(
  SPECIES_DICTIONARY_PROMPT_LABEL_POLICY.punctuationCodePoints,
);

export function speciesDictionaryPromptLabel(rawValue: string): string {
  const normalized: string[] = [];
  let pendingSpace = false;

  for (const scalar of rawValue) {
    const codePoint = scalar.codePointAt(0);
    if (codePoint === undefined) return "this species";
    if (NORMALIZED_WHITESPACE.has(codePoint)) {
      if (normalized.length > 0) pendingSpace = true;
      continue;
    }

    if (
      !ALLOWED_GENERAL_CATEGORY.test(scalar) &&
      !ALLOWED_PUNCTUATION.has(codePoint)
    ) {
      return "this species";
    }
    if (pendingSpace) {
      normalized.push(" ");
      pendingSpace = false;
    }
    normalized.push(scalar);
    if (
      normalized.length >
        SPECIES_DICTIONARY_PROMPT_LABEL_POLICY.maxUnicodeScalars
    ) {
      return "this species";
    }
  }

  return normalized.length > 0 ? normalized.join("") : "this species";
}
