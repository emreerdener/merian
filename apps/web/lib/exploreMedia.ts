type ExplorePosterMedia = {
  kind: "image" | "video" | "audio";
  thumbnailUrl: string | null;
};

export function explorePosterUrl(post: {
  heroImageUrl: string | null;
  mediaItems: ExplorePosterMedia[];
}): string | null {
  return post.heroImageUrl ??
    post.mediaItems.find((item) => item.kind === "audio")?.thumbnailUrl ??
    null;
}
