import type { ExploreCard } from "./exploreCanvas.ts";
import { heroFallbackImages } from "./heroImages.ts";

export const EXPLORE_FALLBACK_DELAY_MS = 1200;
export type ExploreDisplayCard = ExploreCard & {
  decorative: boolean;
  fallbackPoster: string;
  placeholder?: boolean;
};

/** Presets are decorative only, never invented public observations. */
export const explorePreviewCards: ExploreDisplayCard[] = Array.from(
  { length: 48 },
  (_, index) => ({
    id: `nature-preview-${index}`,
    label: "Nature photograph",
    poster: heroFallbackImages[(index * 5) % heroFallbackImages.length],
    fallbackPoster: heroFallbackImages[(index * 5) % heroFallbackImages.length],
    decorative: true,
  }),
);

export function displayExploreCards(
  cards: ExploreCard[],
): ExploreDisplayCard[] {
  return cards.map((card, index) => ({
    ...card,
    decorative: false,
    fallbackPoster: heroFallbackImages[index % heroFallbackImages.length],
  }));
}

/** Unpopulated cells remain decorative; actual observations never repeat. */
export function canvasDisplayCard(
  cards: ExploreDisplayCard[],
  index: number,
): ExploreDisplayCard {
  return cards[index] ?? {
    ...explorePreviewCards[index % explorePreviewCards.length],
    id: `nature-edge-${index}`,
    placeholder: cards.length === 0,
  };
}

export function explorePostHref(
  card: ExploreDisplayCard,
  primaryReady: boolean,
): string | undefined {
  return !card.decorative && primaryReady
    ? `/explore/post/${card.id}`
    : undefined;
}
