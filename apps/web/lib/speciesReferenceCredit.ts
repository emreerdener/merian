import type { PublicSpeciesReferenceImage } from "../../../services/supabase/functions/_shared/publicSpeciesProjection.ts";
import {
  commonsImageIdentity,
  reusableImageLicense,
} from "../../../services/supabase/functions/_shared/referenceImageRights.ts";

export function speciesReferenceCredit(image: PublicSpeciesReferenceImage) {
  const licenseURL = reusableImageLicense(image.license);
  const cc = licenseURL?.match(/\/licenses\/(by(?:-sa)?)\/([^/]+)\/(au\/)?$/);
  const licenseLabel = cc
    ? `CC ${cc[1].toUpperCase()} ${cc[2]}${cc[3] ? " AU" : ""}`
    : licenseURL?.includes("/zero/")
    ? "CC0 1.0"
    : licenseURL?.includes("/mark/")
    ? "Public domain"
    : image.license;
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
  return `${image.attribution} — ${credit.licenseLabel} · ${credit.sourceLabel}`;
}
