const SUPPRESSED_EXTERNAL_IMAGE_LOCATIONS = [
  {
    host: "inaturalist-open-data.s3.amazonaws.com",
    pathPrefix: "/photos/605615444/",
  },
] as const;

/**
 * Exact external-media exceptions that should never be returned to clients or
 * persisted as species reference imagery.
 *
 * iNaturalist photo 605615444 is the disturbing roadkill image exposed by
 * GBIF occurrence 5938154750. Matching the media directory also covers resized
 * filename variants and query strings without suppressing other wildcat media.
 */
export function isSuppressedExternalImageURL(value: string): boolean {
  const trimmed = value.trim();
  if (!trimmed) return false;

  try {
    const url = new URL(trimmed);
    const host = url.hostname.toLowerCase();
    const path = url.pathname.toLowerCase();

    return SUPPRESSED_EXTERNAL_IMAGE_LOCATIONS.some((location) =>
      host === location.host &&
      path.startsWith(location.pathPrefix)
    );
  } catch {
    return false;
  }
}

export function isAllowedExternalImageURL(value: string): boolean {
  return !isSuppressedExternalImageURL(value);
}

export function filterAllowedExternalImageURLs(
  values: string[],
): string[] {
  return values
    .map((value) => value.trim())
    .filter((value) => value.length > 0 && isAllowedExternalImageURL(value));
}
