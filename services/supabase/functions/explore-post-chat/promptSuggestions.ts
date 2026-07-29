export function buildExplorePostChatPromptSuggestions(
  rawCommonName: string,
  hasLookalikes: boolean,
) {
  const normalizedCommonName = rawCommonName.trim().replace(/\s+/g, " ");
  const commonName = normalizedCommonName &&
      normalizedCommonName.length <= 64
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
