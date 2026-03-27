// Maps ISO 3166-1 alpha-2 country codes to the natural-language name variants that CLGeocoder
// returns on iOS. Kept to the countries where Merian users are most active to avoid table bloat.
export const COUNTRY_ALIASES: Record<string, string[]> = {
  "US": ["UNITED STATES", "USA"],
  "GB": ["UNITED KINGDOM", "GREAT BRITAIN", "ENGLAND", "SCOTLAND", "WALES"],
  "CA": ["CANADA"],
  "AU": ["AUSTRALIA"],
  "DE": ["GERMANY"],
  "FR": ["FRANCE"],
  "JP": ["JAPAN"],
  "CN": ["CHINA"],
  "IN": ["INDIA"],
  "BR": ["BRAZIL"],
  "MX": ["MEXICO"],
  "RU": ["RUSSIA"],
  "ZA": ["SOUTH AFRICA"],
  "IT": ["ITALY"],
  "ES": ["SPAIN"],
  "PT": ["PORTUGAL"],
  "NL": ["NETHERLANDS"],
  "SE": ["SWEDEN"],
  "NO": ["NORWAY"],
  "DK": ["DENMARK"],
  "FI": ["FINLAND"],
  "PL": ["POLAND"],
  "TR": ["TURKEY"],
  "AR": ["ARGENTINA"],
  "CL": ["CHILE"],
  "CO": ["COLOMBIA"],
  "PE": ["PERU"],
  "NZ": ["NEW ZEALAND"],
  "TH": ["THAILAND"],
  "VN": ["VIETNAM"],
  "MY": ["MALAYSIA"],
  "ID": ["INDONESIA"],
  "PH": ["PHILIPPINES"],
  "KR": ["SOUTH KOREA"],
  "NG": ["NIGERIA"],
  "KE": ["KENYA"],
  "EG": ["EGYPT"],
  "ET": ["ETHIOPIA"],
  "TZ": ["TANZANIA"],
};

// Maps US state two-letter ISO 3166-2 sub-codes to their full uppercased names.
// iOS CLGeocoder returns "Austin, Texas, United States" rather than "Austin, TX, United States",
// so we need this reverse lookup to match "US-TX" against the full name.
export const US_STATE_FULL_NAMES: Record<string, string> = {
  "AL": "ALABAMA", "AK": "ALASKA", "AZ": "ARIZONA", "AR": "ARKANSAS",
  "CA": "CALIFORNIA", "CO": "COLORADO", "CT": "CONNECTICUT", "DE": "DELAWARE",
  "FL": "FLORIDA", "GA": "GEORGIA", "HI": "HAWAII", "ID": "IDAHO",
  "IL": "ILLINOIS", "IN": "INDIANA", "IA": "IOWA", "KS": "KANSAS",
  "KY": "KENTUCKY", "LA": "LOUISIANA", "ME": "MAINE", "MD": "MARYLAND",
  "MA": "MASSACHUSETTS", "MI": "MICHIGAN", "MN": "MINNESOTA", "MS": "MISSISSIPPI",
  "MO": "MISSOURI", "MT": "MONTANA", "NE": "NEBRASKA", "NV": "NEVADA",
  "NH": "NEW HAMPSHIRE", "NJ": "NEW JERSEY", "NM": "NEW MEXICO", "NY": "NEW YORK",
  "NC": "NORTH CAROLINA", "ND": "NORTH DAKOTA", "OH": "OHIO", "OK": "OKLAHOMA",
  "OR": "OREGON", "PA": "PENNSYLVANIA", "RI": "RHODE ISLAND", "SC": "SOUTH CAROLINA",
  "SD": "SOUTH DAKOTA", "TN": "TENNESSEE", "TX": "TEXAS", "UT": "UTAH",
  "VT": "VERMONT", "VA": "VIRGINIA", "WA": "WASHINGTON", "WV": "WEST VIRGINIA",
  "WI": "WISCONSIN", "WY": "WYOMING", "DC": "DISTRICT OF COLUMBIA",
};

// Returns true if `regionCode` (ISO 3166-1 "US" or ISO 3166-2 "US-TX") is present in the
// uppercased geocoded location string. Handles both abbreviated formats ("Austin, TX, ...")
// and full-name formats ("Austin, Texas, United States") that CLGeocoder produces.
export function locationMatchesRegion(loc: string, regionCode: string): boolean {
  const parts = regionCode.toUpperCase().split("-");
  const countryCode = parts[0];
  const subCode = parts.length > 1 ? parts[1] : null;

  // A "token match" prevents "IN" from false-matching "INDIANA" as a standalone country.
  const tokenMatch = (s: string) =>
    loc === s ||
    loc.startsWith(s + ",") ||
    loc.endsWith(", " + s) ||
    loc.includes(", " + s + ",") ||
    loc.includes(", " + s + " ");

  const countryPresent =
    tokenMatch(countryCode) ||
    (COUNTRY_ALIASES[countryCode] ?? []).some(alias => loc.includes(alias));

  if (!countryPresent) return false;
  if (!subCode) return true;

  // Sub-region: try the raw abbreviated code first (e.g. "TX" in "Austin, TX, ..."),
  // then fall back to full state name for US (e.g. "TEXAS" in "Austin, Texas, ...").
  if (tokenMatch(subCode)) return true;
  if (countryCode === "US") {
    const fullName = US_STATE_FULL_NAMES[subCode];
    if (fullName && loc.includes(fullName)) return true;
  }

  return false;
}

export function calculateRegionalStatus(
  semanticLocation: string | null,
  isInvasive: boolean,
  regions: string[] | null
): string {
  if (isInvasive) return "Regarded as an invasive species in this region.";
  if (!regions || regions.length === 0) return "Global distribution unverified.";

  const loc = (semanticLocation || "").toUpperCase();
  const isNative = regions.some(r => r.length >= 2 && locationMatchesRegion(loc, r));

  return isNative
    ? "Native to this region based on exact spatial distribution bounds."
    : "Introduced or unverified native presence in this exact capturing area.";
}
