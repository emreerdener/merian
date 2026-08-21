export function buildSpeciesDictionaryChatPromptSuggestions(
  rawCommonName: string,
  hasLookalikes: boolean,
) {
  const normalizedCommonName = rawCommonName.trim().replace(/\s+/g, " ");
  const isSafeLabel = /^[\p{L}\p{M}\p{N} .()'’\-]+$/u.test(
    normalizedCommonName,
  );
  const commonName = normalizedCommonName &&
      normalizedCommonName.length <= 64 && isSafeLabel
    ? normalizedCommonName
    : "this species";

  return [
    {
      text: hasLookalikes
        ? `How can I distinguish ${commonName} from lookalikes?`
        : `What traits are characteristic of ${commonName}?`,
      category: hasLookalikes ? "lookalike_compare" : "evidence",
    },
    { text: `What habitat does ${commonName} prefer?`, category: "habitat" },
    {
      text: `What is most interesting about ${commonName}?`,
      category: "ecology",
    },
  ];
}
