export type GhostPublicIdentitySnapshot = {
  publicUsername: string | null;
  publicAuthorName: string | null;
  publicIdentitySource: string | null;
  customAvatarUrl: string | null;
  customAvatarUpdatedAt: string | null;
  defaultPublicUsername: string | null;
};

export function buildPreservedGhostIdentityUpdate(
  snapshot: GhostPublicIdentitySnapshot | null,
): Record<string, string> {
  if (!snapshot) return {};

  const update: Record<string, string> = {};
  const displayName = normalizedText(snapshot.publicAuthorName);
  if (snapshot.publicIdentitySource === "display_name" && displayName) {
    update.public_author_name = displayName;
    update.public_identity_source = "display_name";
  }

  const avatarUrl = normalizedText(snapshot.customAvatarUrl);
  if (avatarUrl) {
    update.custom_avatar_url = avatarUrl;
    update.custom_avatar_updated_at = snapshot.customAvatarUpdatedAt ??
      new Date().toISOString();
    update.public_avatar_url = avatarUrl;
  }

  const username = normalizedText(snapshot.publicUsername);
  const defaultUsername = normalizedText(snapshot.defaultPublicUsername);
  if (username && username !== defaultUsername) {
    update.public_username = username;
  }

  return update;
}

function normalizedText(value: string | null | undefined): string | null {
  const normalized = value?.trim() ?? "";
  return normalized.length > 0 ? normalized : null;
}
