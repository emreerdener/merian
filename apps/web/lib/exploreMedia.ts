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

export function exploreGridPosterUrl(post: {
  heroImageUrl: string | null;
  referenceThumbnailUrl: string | null;
  mediaItems: ExplorePosterMedia[];
}): string | null {
  const isAudioPost = post.mediaItems.some((item) => item.kind === "audio") ||
    (!post.mediaItems.length && Boolean(post.heroImageUrl?.includes("spectrogram-")));

  return isAudioPost
    ? post.referenceThumbnailUrl ?? post.heroImageUrl
    : post.heroImageUrl ?? post.referenceThumbnailUrl;
}
