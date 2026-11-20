export const HERO_IMAGE_GRACE_MS = 1200;

export const heroFallbackImages = [
  "deer",
  "woodland",
  "leaves",
  "kingfisher",
  "macaw",
  "foliage",
  "forest",
  "fox",
  "blossom",
  "canopy",
  "meadow",
  "hamster",
].map((name) => `/assets/hero-nature/${name}.webp`);

/** The timer covers both the streamed feed and subsequent image loading. */
export function watchHeroImages(
  images: string[] | Promise<string[]>,
  onImages: (images: string[]) => void,
  onFallback: () => void,
): () => void {
  let active = true;
  const timer = setTimeout(() => {
    if (active) onFallback();
  }, HERO_IMAGE_GRACE_MS);
  void Promise.resolve(images).then((urls) => {
    if (!active) return;
    const posters = [...new Set(urls.filter((url) => url.trim()))].slice(0, 24);
    onImages(posters);
    if (!posters.length) onFallback();
  }, () => {
    if (active) onFallback();
  });
  return () => {
    active = false;
    clearTimeout(timer);
  };
}
