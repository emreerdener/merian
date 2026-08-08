export const RESERVED_PUBLIC_USERNAME_EXACT = [
  "null",
  "undefined",
] as const;

export const RESERVED_PUBLIC_USERNAME_BRANDS = [
  "explore",
  "merian",
  "naturebook",
  "naturebookearth",
] as const;

export const RESERVED_PUBLIC_USERNAME_ROLES = [
  "abuse",
  "account",
  "accounts",
  "admin",
  "administrator",
  "api",
  "auth",
  "billing",
  "bot",
  "contact",
  "customer_service",
  "customer_support",
  "developer",
  "developers",
  "help",
  "legal",
  "moderation",
  "moderator",
  "notifications",
  "official",
  "press",
  "privacy",
  "root",
  "safety",
  "security",
  "staff",
  "status",
  "support",
  "system",
  "team",
  "trust",
  "verified",
  "verify",
] as const;

const RESERVED_EXACT_SET = new Set<string>(RESERVED_PUBLIC_USERNAME_EXACT);
const RESERVED_BRAND_SET = new Set<string>(RESERVED_PUBLIC_USERNAME_BRANDS);
const RESERVED_ROLE_SET = new Set<string>(RESERVED_PUBLIC_USERNAME_ROLES);

export function isReservedPublicUsername(username: string): boolean {
  if (
    RESERVED_EXACT_SET.has(username) ||
    RESERVED_BRAND_SET.has(username) ||
    RESERVED_ROLE_SET.has(username)
  ) {
    return true;
  }

  return RESERVED_PUBLIC_USERNAME_BRANDS.some((brand) =>
    RESERVED_PUBLIC_USERNAME_ROLES.some((role) =>
      username === `${brand}_${role}` || username === `${role}_${brand}`
    )
  );
}

export function normalizePublicUsername(value: unknown): string {
  if (typeof value !== "string") return "";

  return value
    .trim()
    .replace(/^@+/, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/_{2,}/g, "_")
    .replace(/^_+|_+$/g, "");
}

export function publicUsernameValidationError(username: string): string | null {
  if (username.length < 3) return "Username must be at least 3 characters.";
  if (username.length > 24) return "Username must be 24 characters or fewer.";
  if (!/^[a-z]/.test(username)) return "Username must start with a letter.";
  if (!/[a-z0-9]$/.test(username)) {
    return "Username must end with a letter or number.";
  }
  if (!/^[a-z0-9_]+$/.test(username)) {
    return "Username can only use letters, numbers, and underscores.";
  }
  if (username.includes("__")) {
    return "Username cannot use repeated underscores.";
  }
  if (isReservedPublicUsername(username)) return "That username is reserved.";

  return null;
}
