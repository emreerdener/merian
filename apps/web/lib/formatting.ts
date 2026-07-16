export function compactSpeciesTitle(commonName: string, scientificName: string) {
  const trimmedCommon = commonName.trim();
  const trimmedScientific = scientificName.trim();

  if (!trimmedScientific || trimmedScientific === trimmedCommon) {
    return trimmedCommon || "Naturebook discovery";
  }

  return `${trimmedCommon || "Naturebook discovery"} (${trimmedScientific})`;
}

export function postTitle(commonName: string, location?: string | null) {
  const trimmedCommon = commonName.trim() || "Naturebook discovery";
  const trimmedLocation = location?.trim();

  return trimmedLocation ? `${trimmedCommon} in ${trimmedLocation}` : trimmedCommon;
}

export function nativeExplorePostUrl(postId: string) {
  return `naturebook://explore/post/${postId}`;
}
