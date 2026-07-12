const MEDIA_HOST = "media.merian.app";

export function proxiedExploreAudioUrl(rawUrl: string): URL | null {
  try {
    const url = new URL(rawUrl);
    if (
      url.protocol !== "https:" ||
      url.hostname !== MEDIA_HOST ||
      url.username ||
      url.password ||
      !url.pathname.startsWith("/public_uploads/") ||
      !url.pathname.toLowerCase().endsWith(".wav")
    ) {
      return null;
    }
    return url;
  } catch {
    return null;
  }
}

export function webAudioProxyPath(rawUrl: string): string {
  return `/api/explore/audio?url=${encodeURIComponent(rawUrl)}`;
}
