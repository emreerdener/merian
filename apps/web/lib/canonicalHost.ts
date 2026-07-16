export const CANONICAL_ORIGIN = "https://naturebook.earth";

const redirectHosts = new Set([
  "naturebook.app",
  "www.naturebook.app",
  "www.naturebook.earth",
  "merian.earth",
  "www.merian.earth",
]);

const appleAssociationPaths = new Set([
  "/apple-app-site-association",
  "/.well-known/apple-app-site-association",
]);

export function canonicalRedirectURL(
  hostname: string,
  pathname: string,
  search = "",
): URL | null {
  const normalizedHost = hostname.trim().toLowerCase().replace(/\.$/, "");

  if (
    normalizedHost === "merian.earth" &&
    appleAssociationPaths.has(pathname)
  ) {
    return null;
  }

  if (!redirectHosts.has(normalizedHost)) {
    return null;
  }

  return new URL(`${pathname}${search}`, CANONICAL_ORIGIN);
}
