import type { SpeciesDictionaryChatContext } from "./types.ts";

export function isSpeciesDictionaryChatContextAvailable(
  context: SpeciesDictionaryChatContext | null,
): context is SpeciesDictionaryChatContext {
  return context !== null;
}
