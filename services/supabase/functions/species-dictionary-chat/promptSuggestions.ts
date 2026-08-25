import { speciesDictionaryPromptLabel } from "./promptLabelPolicy.ts";

export function buildSpeciesDictionaryChatPromptSuggestions(
  rawCommonName: string,
  hasLookalikes: boolean,
) {
  const commonName = speciesDictionaryPromptLabel(rawCommonName);

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
