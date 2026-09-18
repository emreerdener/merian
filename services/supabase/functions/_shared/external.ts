import { filterAllowedExternalImageURLs } from "./externalImagePolicy.ts";
import { fetchWithDeadline, readResponseJsonWithinLimit } from "./outbound.ts";
import {
  commonsImageIdentity,
  type ExternalReferenceImage,
  imageCreditText,
  reusableImageLicense,
} from "./referenceImageRights.ts";

const EXTERNAL_REQUEST_TIMEOUT_MS = 2_500;
const EXTERNAL_JSON_RESPONSE_LIMIT_BYTES = 256 * 1024;

async function discardProviderBody(response: Response): Promise<void> {
  await response.body?.cancel().catch(() => undefined);
}

async function fetchBoundedProviderJson<T>(
  url: string,
  fetcher: typeof fetch = fetch,
  init: RequestInit = {},
): Promise<T | null> {
  try {
    const response = await fetchWithDeadline(
      url,
      init,
      { fetcher, timeoutMs: EXTERNAL_REQUEST_TIMEOUT_MS },
    );
    if (!response.ok) {
      await discardProviderBody(response);
      return null;
    }
    return await readResponseJsonWithinLimit<T>(
      response,
      EXTERNAL_JSON_RESPONSE_LIMIT_BYTES,
    );
  } catch {
    return null;
  }
}

/**
 * Fetches English vernacular names for a species from GBIF using a known usageKey.
 * Normalises to Title Case and deduplicates. Returns an empty array on timeout,
 * non-OK response, or no English entries — never throws.
 */
function normalizeVernacularName(name: string): string {
  return name
    .split(" ")
    .map((word: string) =>
      word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()
    )
    .join(" ");
}

function collectEnglishVernacularNames(results: unknown): string[] {
  const seen = new Set<string>();
  const names: string[] = [];

  for (
    const entry of (results as Array<Record<string, unknown>> | undefined) ?? []
  ) {
    const language = entry.language;
    if (language !== "eng" && language !== "en") continue;

    const rawName = typeof entry.vernacularName === "string"
      ? entry.vernacularName.trim()
      : "";
    if (!rawName) continue;

    const normalized = normalizeVernacularName(rawName);
    const dedupeKey = normalized.toLowerCase();
    if (seen.has(dedupeKey)) continue;

    seen.add(dedupeKey);
    names.push(normalized);
  }

  return names;
}

export interface ExternalEnrichmentTaxonomy {
  kingdom?: string | null;
  phylum?: string | null;
  class?: string | null;
  order?: string | null;
  family?: string | null;
  genus?: string | null;
}

export interface ExternalEnrichmentData {
  wikipediaUrl: string | null;
  wikiExtract: string | null;
  gbifKey: number | null;
  referenceImageUrl: string | null;
  referenceImages?: ExternalReferenceImage[];
  alternativeCommonNames: string[];
  wikiTitle: string | null;
  gbifTaxonomy: ExternalEnrichmentTaxonomy | null;
  gbifMatchStatus?: "matched" | "unmatched" | "unavailable";
}

export interface GBIFCountryOccurrence {
  countryCode: string;
  occurrenceCount: number;
}

interface GBIFOccurrenceFacetResponse {
  facets?: Array<{
    field?: unknown;
    counts?: Array<{ name?: unknown; count?: unknown }>;
  }>;
}

const GBIF_REQUEST_HEADERS = {
  "User-Agent":
    "Naturebook species content refresh/1.0 (https://naturebook.earth)",
};

/**
 * Fetches GBIF's country facet for georeferenced, present occurrence records.
 * A successful response with no country counts returns an empty array. Provider
 * or schema failures return null so durable workers can retry rather than erase
 * previously valid coverage.
 */
export async function fetchGBIFCountryOccurrences(
  gbifKey: number,
  fetcher: typeof fetch = fetch,
): Promise<GBIFCountryOccurrence[] | null> {
  if (!Number.isSafeInteger(gbifKey) || gbifKey <= 0) return null;

  const json = await fetchBoundedProviderJson<GBIFOccurrenceFacetResponse>(
    `https://api.gbif.org/v1/occurrence/search?taxonKey=${gbifKey}&occurrenceStatus=PRESENT&hasCoordinate=true&hasGeospatialIssue=false&limit=0&facet=country&facetLimit=300`,
    fetcher,
    { headers: GBIF_REQUEST_HEADERS },
  );
  if (!json || !Array.isArray(json.facets)) return null;

  const countryFacet = json.facets.find((facet) =>
    typeof facet.field === "string" && facet.field.toUpperCase() === "COUNTRY"
  );
  if (!countryFacet) return [];
  if (!Array.isArray(countryFacet.counts)) return null;

  const countByCountryCode = new Map<string, number>();
  for (const entry of countryFacet.counts) {
    const countryCode = typeof entry.name === "string"
      ? entry.name.trim().toUpperCase()
      : "";
    const occurrenceCount = typeof entry.count === "number"
      ? entry.count
      : Number.NaN;
    if (
      !/^[A-Z]{2}$/.test(countryCode) ||
      !Number.isSafeInteger(occurrenceCount) ||
      occurrenceCount <= 0
    ) {
      return null;
    }

    countByCountryCode.set(
      countryCode,
      Math.max(countByCountryCode.get(countryCode) ?? 0, occurrenceCount),
    );
  }

  return Array.from(countByCountryCode.entries())
    .map(([countryCode, occurrenceCount]) => ({
      countryCode,
      occurrenceCount,
    }))
    .sort((lhs, rhs) => lhs.countryCode.localeCompare(rhs.countryCode));
}

export async function fetchGBIFVernacularNames(
  gbifKey: number,
): Promise<string[]> {
  const json = await fetchBoundedProviderJson<{ results?: unknown }>(
    `https://api.gbif.org/v1/species/${gbifKey}/vernacularNames?limit=30`,
    fetch,
    { headers: GBIF_REQUEST_HEADERS },
  );
  return collectEnglishVernacularNames(json?.results);
}

interface WikiSummary {
  url: string | null;
  extract: string | null;
  img: string | null;
  title: string | null;
  type: string | null;
}

interface WikiProviderSummary {
  content_urls?: { desktop?: { page?: string } };
  extract?: string;
  originalimage?: { source?: string };
  thumbnail?: { source?: string };
  title?: string;
  type?: string;
}

async function fetchWikiSummary(
  title: string,
  fetcher: typeof fetch = fetch,
): Promise<WikiSummary | null> {
  const wikiJson = await fetchBoundedProviderJson<WikiProviderSummary>(
    `https://en.wikipedia.org/api/rest_v1/page/summary/${
      encodeURIComponent(title.replace(/ /g, "_"))
    }`,
    fetcher,
  );
  if (!wikiJson) return null;

  const url = wikiJson.content_urls?.desktop?.page || null;
  const extract = wikiJson.extract || null;
  const img = wikiJson.originalimage?.source ||
    wikiJson.thumbnail?.source || null;
  const resTitle = wikiJson.title || null;
  const type = wikiJson.type || null;
  return { url, extract, img, title: resTitle, type };
}

export async function fetchExternalEnrichment(
  scientificName: string,
  fetcher: typeof fetch = fetch,
  options: { includeImageRights?: boolean } = {},
): Promise<ExternalEnrichmentData> {
  let wikiUrl: string | null = null;
  let wikiExtract: string | null = null;
  let gbifKey: number | null = null;
  let combinedImageUrls: string | null = null;
  let wikiTitle: string | null = null;
  let alternativeCommonNames: string[] = [];
  let gbifTaxonomy: ExternalEnrichmentTaxonomy | null = null;
  let gbifMatchStatus: "matched" | "unmatched" | "unavailable" = "unavailable";
  const imageRights = new Map<string, ExternalReferenceImage>();
  let imageProviderUnavailable = false;

  try {
    const fetchedUrls: string[] = [];

    const [gbifOutcome, wikiOutcome] = await Promise.allSettled([
      (async () => {
        let key: number | null = null;
        let urls: string[] = [];
        let vernacularNames: string[] = [];
        let rank: string | null = null;

        const gbifJson = await fetchBoundedProviderJson<
          Record<string, unknown>
        >(
          `https://api.gbif.org/v1/species/match?name=${
            encodeURIComponent(scientificName)
          }`,
          fetcher,
          { headers: GBIF_REQUEST_HEADERS },
        );
        if (!gbifJson) {
          return {
            key,
            urls,
            vernacularNames,
            taxonomy: null,
            rank,
            matchStatus: "unavailable" as const,
          };
        }
        key = typeof gbifJson.usageKey === "number" &&
            Number.isSafeInteger(gbifJson.usageKey) && gbifJson.usageKey > 0
          ? gbifJson.usageKey
          : null;
        const taxonomy = gbifTaxonomyFromMatch(gbifJson);
        rank = stringValue(gbifJson.rank);
        const matchType = stringValue(gbifJson.matchType)?.toUpperCase();
        const matchStatus = key
          ? "matched" as const
          : matchType === "NONE"
          ? "unmatched" as const
          : "unavailable" as const;

        if (key) {
          // Fetch occurrence images and vernacular names in parallel — both depend on key
          // but are independent of each other. Each helper also consumes or
          // cancels its own body so one malformed response cannot strand the
          // sibling response or discard otherwise valid enrichment.
          const [mediaJson, vernacularJson] = await Promise.all([
            fetchBoundedProviderJson<{
              results?: Array<{
                media?: Array<{
                  type?: unknown;
                  identifier?: unknown;
                  license?: unknown;
                  creator?: unknown;
                  rightsHolder?: unknown;
                }>;
              }>;
            }>(
              `https://api.gbif.org/v1/occurrence/search?taxonKey=${key}&mediaType=StillImage&limit=4`,
              fetcher,
              { headers: GBIF_REQUEST_HEADERS },
            ),
            fetchBoundedProviderJson<{ results?: unknown }>(
              `https://api.gbif.org/v1/species/${key}/vernacularNames?language=eng&limit=30`,
              fetcher,
              { headers: GBIF_REQUEST_HEADERS },
            ),
          ]);

          if (
            options.includeImageRights && !Array.isArray(mediaJson?.results)
          ) {
            throw new Error("Reference image media provider unavailable");
          }
          if (mediaJson?.results && mediaJson.results.length > 0) {
            const gbifUrls: string[] = [];
            for (const result of mediaJson.results.slice(0, 4)) {
              if (result.media && result.media.length > 0) {
                for (const m of result.media) {
                  if (
                    m.type === "StillImage" &&
                    typeof m.identifier === "string"
                  ) {
                    const imageURL = m.identifier.trim();
                    gbifUrls.push(imageURL);
                    const license = reusableImageLicense(m.license);
                    const creator = imageCreditText(m.creator);
                    const holder = imageCreditText(m.rightsHolder);
                    const attribution = [
                      ...new Set([creator, holder].filter(Boolean)),
                    ].join(" · ");
                    if (
                      license && attribution && !imageRights.has(imageURL)
                    ) {
                      imageRights.set(imageURL, {
                        url: imageURL,
                        source: "gbif",
                        license,
                        attribution,
                      });
                    }
                    break; // take the primary image from each observation
                  }
                }
              }
            }
            urls = gbifUrls.slice(0, 4);
          }

          vernacularNames = collectEnglishVernacularNames(
            vernacularJson?.results,
          );
        }
        return { key, urls, vernacularNames, taxonomy, rank, matchStatus };
      })(),

      (async () => {
        return await fetchWikiSummary(scientificName, fetcher);
      })(),
    ]);

    if (gbifOutcome.status === "fulfilled") {
      gbifKey = gbifOutcome.value.key;
      fetchedUrls.push(...gbifOutcome.value.urls);
      alternativeCommonNames = gbifOutcome.value.vernacularNames;
      gbifTaxonomy = gbifOutcome.value.taxonomy;
      gbifMatchStatus = gbifOutcome.value.matchStatus;
    } else {
      imageProviderUnavailable = true;
    }

    let wikiImg: string | null = null;
    if (wikiOutcome.status === "fulfilled" && wikiOutcome.value) {
      let summary = wikiOutcome.value;
      if (summary.type === "disambiguation") {
        const rank = gbifOutcome.status === "fulfilled"
          ? gbifOutcome.value.rank
          : null;
        const taxonomy = gbifOutcome.status === "fulfilled"
          ? gbifOutcome.value.taxonomy
          : null;

        const suffixSet = new Set<string>();
        if (rank === "GENUS") {
          suffixSet.add("genus");
        }
        if (taxonomy?.kingdom === "Plantae") {
          suffixSet.add("plant");
        }
        if (taxonomy?.kingdom === "Animalia") {
          if (taxonomy?.class === "Insecta") {
            suffixSet.add("insect");
          }
          if (taxonomy?.class === "Aves") {
            suffixSet.add("bird");
          }
          suffixSet.add("animal");
        }
        if (taxonomy?.kingdom === "Fungi") {
          suffixSet.add("fungus");
        }
        // Fallbacks
        suffixSet.add("genus");
        suffixSet.add("plant");
        suffixSet.add("animal");

        for (const suffix of suffixSet) {
          const candidateTitle = `${scientificName} (${suffix})`;
          const candidateSummary = await fetchWikiSummary(
            candidateTitle,
            fetcher,
          );
          if (candidateSummary && candidateSummary.type !== "disambiguation") {
            summary = candidateSummary;
            break;
          }
        }
      }

      if (summary.type !== "disambiguation") {
        wikiUrl = summary.url;
        wikiExtract = summary.extract;
        wikiTitle = summary.title;
        wikiImg = summary.img;
      } else {
        wikiUrl = summary.url;
        wikiTitle = summary.title;
      }
    }

    if (wikiImg) {
      fetchedUrls.unshift(wikiImg);
    }

    const allowedImageUrls = filterAllowedExternalImageURLs(fetchedUrls);
    if (allowedImageUrls.length > 0) {
      combinedImageUrls = Array.from(new Set(allowedImageUrls)).join(",");
    }
  } catch (e) {
    console.error(
      "[external.ts] Unexpected enrichment error:",
      e instanceof Error ? e.message : String(e),
    );
  }

  // Only the durable refresh worker opts into this extra provider request.
  // A transient rights lookup failure must retry the job, not mark it fresh.
  let referenceImages: ExternalReferenceImage[] | undefined;
  if (options.includeImageRights) {
    if (imageProviderUnavailable || gbifMatchStatus === "unavailable") {
      throw new Error("Reference image media provider unavailable");
    }
    const urls = combinedImageUrls?.split(",") ?? [];
    const wikiImages = urls.filter((url) => commonsImageIdentity(url) !== null);
    for (const rights of await fetchCommonsImageRights(wikiImages, fetcher)) {
      imageRights.set(rights.url, rights);
    }
    referenceImages = urls.flatMap((url) => {
      const rights = imageRights.get(url);
      return rights ? [rights] : [];
    });
  }

  return {
    wikipediaUrl: wikiUrl,
    wikiExtract,
    gbifKey,
    referenceImageUrl: combinedImageUrls,
    ...(referenceImages ? { referenceImages } : {}),
    alternativeCommonNames,
    wikiTitle,
    gbifTaxonomy,
    gbifMatchStatus,
  };
}

export function fetchExternalEnrichmentWithImageRights(
  scientificName: string,
): Promise<ExternalEnrichmentData> {
  return fetchExternalEnrichment(scientificName, fetch, {
    includeImageRights: true,
  });
}

async function fetchCommonsImageRights(
  imageURLs: string[],
  fetcher: typeof fetch,
): Promise<ExternalReferenceImage[]> {
  const identities = imageURLs.slice(0, 5).flatMap((url) => {
    const identity = commonsImageIdentity(url);
    return identity ? [{ ...identity, url }] : [];
  });
  if (identities.length === 0) return [];
  const api = new URL("https://commons.wikimedia.org/w/api.php");
  api.search = new URLSearchParams({
    action: "query",
    format: "json",
    formatversion: "2",
    prop: "imageinfo",
    titles: [...new Set(identities.map((identity) => identity.title))].join(
      "|",
    ),
    iiprop: "url|extmetadata",
    iiextmetadatalanguage: "en",
    iiextmetadatafilter:
      "LicenseShortName|LicenseUrl|Artist|Credit|Attribution|NonFree|Restrictions|DeletionReason",
  }).toString();
  const data = await fetchBoundedProviderJson<{
    error?: unknown;
    query?: {
      pages?: Array<{
        imageinfo?: CommonsImageInfo[];
      }>;
    };
  }>(api.href, fetcher, { headers: GBIF_REQUEST_HEADERS, redirect: "error" });
  if (!data || data.error || !Array.isArray(data.query?.pages)) {
    throw new Error("Reference image rights provider unavailable");
  }
  return data.query.pages.slice(0, 5).flatMap((page) => {
    const info = page?.imageinfo?.[0];
    if (!info || typeof info.url !== "string") return [];
    const originalURL = commonsImageIdentity(info.url)?.originalURL;
    return identities.filter((identity) => identity.originalURL === originalURL)
      .flatMap((identity) => {
        const rights = commonsRightsFromInfo(identity.url, info);
        return rights ? [rights] : [];
      });
  });
}

interface CommonsImageInfo {
  url?: string;
  extmetadata?: Record<string, { value?: unknown }>;
}

function commonsRightsFromInfo(
  imageURL: string,
  info: CommonsImageInfo,
): ExternalReferenceImage | null {
  const metadata = info.extmetadata;
  if (!metadata || typeof metadata !== "object") return null;
  const field = (key: string) => metadata[key]?.value;
  if (
    (field("NonFree") !== undefined && field("NonFree") !== "false") ||
    stringValue(field("Restrictions")) ||
    stringValue(field("DeletionReason"))
  ) return null;
  const license = reusableImageLicense(
    stringValue(field("LicenseUrl")) ?? field("LicenseShortName"),
  );
  const custom = imageCreditText(field("Attribution"));
  const artist = imageCreditText(field("Artist"));
  const credit = imageCreditText(field("Credit"));
  const attribution = stringValue(field("Attribution"))
    ? custom
    : (artist
      ? [...new Set([artist, credit].filter(Boolean))].join(" · ")
      : null);
  if (!license || !attribution || attribution.length > 2048) return null;
  return { url: imageURL, source: "wikipedia", license, attribution };
}

function gbifTaxonomyFromMatch(
  value: Record<string, unknown>,
): ExternalEnrichmentTaxonomy | null {
  const taxonomy: ExternalEnrichmentTaxonomy = {
    kingdom: stringValue(value.kingdom),
    phylum: stringValue(value.phylum),
    class: stringValue(value.class),
    order: stringValue(value.order),
    family: stringValue(value.family),
    genus: stringValue(value.genus),
  };

  return Object.values(taxonomy).some((entry) => entry != null)
    ? taxonomy
    : null;
}

function stringValue(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
