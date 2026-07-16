export const siteConfig = {
  name: "Naturebook",
  siteUrl: process.env.NEXT_PUBLIC_SITE_URL ?? "https://naturebook.earth",
  supportEmail: process.env.NEXT_PUBLIC_SUPPORT_EMAIL ?? "support@naturebook.earth",
  appStoreUrl: process.env.NEXT_PUBLIC_APP_STORE_URL,
  legalUpdatedAt: "July 15, 2026"
};

export function supportMailto(subject?: string) {
  const encodedSubject = subject ? `?subject=${encodeURIComponent(subject)}` : "";
  return `mailto:${siteConfig.supportEmail}${encodedSubject}`;
}
