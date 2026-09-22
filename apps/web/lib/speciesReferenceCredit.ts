import type { PublicSpeciesReferenceImage } from "../../../services/supabase/functions/_shared/publicSpeciesProjection.ts";
import {
  commonsImageIdentity,
  reusableImageLicense,
} from "../../../services/supabase/functions/_shared/referenceImageRights.ts";

export type AttributionPart = { label: string; url?: string };

/** Provider credits are plain text; retain names and expose URLs as titled links. */
export function attributionParts(value: string | undefined): AttributionPart[] {
  const text = value ?? "";
  const links =
    /\b(?:(?:https?|ftp):\/\/[^\s<>"·]+|mailto:[^\s<>"·]+|(?:www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:[/?#][^\s<>"·]*)?)/gi;
  const parts: AttributionPart[] = [];
  let cursor = 0;
  for (const match of text.matchAll(links)) {
    const raw = withoutTrailingPunctuation(match[0]);
    // An email address is credit text, not a website.
    if (
      text[match.index - 1] === "@" || text[match.index + raw.length] === "@"
    ) continue;
    parts.push({ label: text.slice(cursor, match.index) });
    let url: URL | undefined;
    try {
      url = new URL(
        /^(?:(?:https?|ftp):\/\/|mailto:)/i.test(raw) ? raw : `https://${raw}`,
      );
    } catch {
      // A malformed provider URL still must not become a naked visible link.
    }
    parts.push({
      label: attributionLinkLabel(url),
      ...(url ? { url: url.href } : {}),
    });
    cursor = match.index + raw.length;
  }
  parts.push({ label: text.slice(cursor) });
  return parts.filter((part) => part.label.length > 0);
}

function withoutTrailingPunctuation(value: string): string {
  let result = value;
  const pairs: Record<string, string> = { ")": "(", "]": "[", "}": "{" };
  while (result.length > 0) {
    const last = result.at(-1)!;
    const opening = pairs[last];
    if (
      /[.,;:!?]/.test(last) ||
      (opening && result.split(last).length > result.split(opening).length)
    ) {
      result = result.slice(0, -1);
    } else break;
  }
  return result;
}

function attributionLinkLabel(url: URL | undefined): string {
  if (url?.protocol === "mailto:") return "Contact";
  if (
    !url ||
    !["creativecommons.org", "www.creativecommons.org"].includes(url.hostname)
  ) {
    return "Website";
  }
  const cc = url.pathname.toLowerCase().match(
    /^\/licenses\/(by(?:-nc)?(?:-sa|-nd)?)\/(\d+\.\d+)(?:\/([a-z]{2}))?(?:\/|$)/,
  );
  if (cc) {
    return `CC ${cc[1].toUpperCase()} ${cc[2]}${
      cc[3] ? ` ${cc[3].toUpperCase()}` : ""
    }`;
  }
  if (/^\/publicdomain\/zero\/1\.0(?:\/|$)/.test(url.pathname)) {
    return "CC0 1.0";
  }
  if (/^\/publicdomain\/mark\/1\.0(?:\/|$)/.test(url.pathname)) {
    return "Public domain";
  }
  return "License";
}

export function speciesReferenceCredit(image: PublicSpeciesReferenceImage) {
  const licenseURL = reusableImageLicense(image.license);
  const cc = licenseURL?.match(/\/licenses\/(by(?:-sa)?)\/([^/]+)\/(au\/)?$/);
  const licenseLabel = cc
    ? `CC ${cc[1].toUpperCase()} ${cc[2]}${cc[3] ? " AU" : ""}`
    : licenseURL?.includes("/zero/")
    ? "CC0 1.0"
    : licenseURL?.includes("/mark/")
    ? "Public domain"
    : attributionParts(image.license).map((part) => part.label).join("");
  const sourceLabel = image.source === "merian"
    ? "Naturebook"
    : image.source === "wikipedia"
    ? "Wikipedia"
    : "GBIF";
  const sourceURL = image.source === "wikipedia"
    ? commonsImageIdentity(image.url)?.pageURL ?? null
    : image.source === "gbif" && image.url.startsWith("https://")
    ? image.url
    : null;
  return { licenseURL, licenseLabel, sourceLabel, sourceURL };
}

export function referenceImageCaption(
  image: PublicSpeciesReferenceImage,
): string {
  const credit = speciesReferenceCredit(image);
  const attribution = attributionParts(image.attribution).map((part) =>
    part.label
  ).join("");
  return `${attribution} — ${credit.licenseLabel} · ${credit.sourceLabel}`;
}
