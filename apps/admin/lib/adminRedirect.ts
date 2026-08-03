const DEFAULT_ADMIN_PATH = "/mfa";

export function validatedAdminOrigin(value: string | undefined): URL {
  const configured = value?.trim();
  if (!configured) {
    throw new Error("NEXT_PUBLIC_ADMIN_ORIGIN is required.");
  }

  const origin = new URL(configured);
  if (
    !["http:", "https:"].includes(origin.protocol) ||
    origin.username ||
    origin.password ||
    origin.pathname !== "/" ||
    origin.search ||
    origin.hash
  ) {
    throw new Error("NEXT_PUBLIC_ADMIN_ORIGIN must be an HTTP(S) origin.");
  }

  return new URL(origin.origin);
}

function hasUnsafeDecodedPathPrefix(value: string): boolean {
  let decoded = value;
  for (let pass = 0; pass < 3; pass += 1) {
    if (decoded.includes("\\") || decoded.startsWith("//")) return true;
    try {
      const next = decodeURIComponent(decoded);
      if (next === decoded) return false;
      decoded = next;
    } catch {
      return true;
    }
  }
  // Reject inputs that still change after three decoding passes. Legitimate
  // callback paths do not need recursively encoded separators.
  return true;
}

export function safeAdminRedirectPath(
  requestedPath: string | null | undefined,
  fallback = DEFAULT_ADMIN_PATH,
): string {
  if (
    !requestedPath?.startsWith("/") ||
    hasUnsafeDecodedPathPrefix(requestedPath)
  ) {
    return fallback;
  }

  const sentinelOrigin = new URL("https://admin.invalid");
  const parsed = new URL(requestedPath, sentinelOrigin);
  if (parsed.origin !== sentinelOrigin.origin) return fallback;
  return `${parsed.pathname}${parsed.search}${parsed.hash}`;
}

export function adminRedirectURL(
  requestedPath: string,
  configuredOrigin = process.env.NEXT_PUBLIC_ADMIN_ORIGIN,
): URL {
  const origin = validatedAdminOrigin(configuredOrigin);
  const parsed = new URL(
    safeAdminRedirectPath(requestedPath, "/"),
    origin,
  );
  const destination = new URL(origin.origin);
  destination.pathname = parsed.pathname;
  destination.search = parsed.search;
  destination.hash = parsed.hash;
  return destination;
}
