export const siteConfig = {
  name: "Merian",
  siteUrl: process.env.NEXT_PUBLIC_SITE_URL ?? "https://merian.earth",
  supportEmail: process.env.NEXT_PUBLIC_SUPPORT_EMAIL ?? "support@merian.earth",
  appStoreUrl: process.env.NEXT_PUBLIC_APP_STORE_URL,
  legalUpdatedAt: "May 17, 2026"
};

export function supportMailto(subject?: string) {
  const encodedSubject = subject ? `?subject=${encodeURIComponent(subject)}` : "";
  return `mailto:${siteConfig.supportEmail}${encodedSubject}`;
}
