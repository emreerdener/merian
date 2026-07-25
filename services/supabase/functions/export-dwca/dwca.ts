import { UserPseudonymizer } from "./pseudonym.ts";
import { DBScanRow, ExportScope, ExportWorkerError } from "./types.ts";

export const DWCA_META_XML = `<?xml version="1.0" encoding="UTF-8"?>
<archive xmlns="http://rs.tdwg.org/dwc/text/">
  <core encoding="UTF-8" linesTerminatedBy="\\n" fieldsTerminatedBy="," fieldsEnclosedBy="&quot;" ignoreHeaderLines="1" rowType="http://rs.tdwg.org/dwc/terms/Occurrence">
    <files><location>occurrence.csv</location></files>
    <id index="0" />
    <field index="1" term="http://rs.tdwg.org/dwc/terms/basisOfRecord" />
    <field index="2" term="http://rs.tdwg.org/dwc/terms/recordedBy" />
    <field index="3" term="http://rs.tdwg.org/dwc/terms/eventDate" />
    <field index="4" term="http://rs.tdwg.org/dwc/terms/scientificName" />
    <field index="5" term="http://rs.tdwg.org/dwc/terms/kingdom" />
    <field index="6" term="http://rs.tdwg.org/dwc/terms/phylum" />
    <field index="7" term="http://rs.tdwg.org/dwc/terms/class" />
    <field index="8" term="http://rs.tdwg.org/dwc/terms/order" />
    <field index="9" term="http://rs.tdwg.org/dwc/terms/family" />
    <field index="10" term="http://rs.tdwg.org/dwc/terms/genus" />
    <field index="11" term="http://rs.tdwg.org/dwc/terms/decimalLatitude" />
    <field index="12" term="http://rs.tdwg.org/dwc/terms/decimalLongitude" />
    <field index="13" term="http://rs.tdwg.org/dwc/terms/coordinateUncertaintyInMeters" />
    <field index="14" term="http://rs.tdwg.org/dwc/terms/lifeStage" />
    <field index="15" term="http://rs.tdwg.org/dwc/terms/reproductiveCondition" />
    <field index="16" term="http://rs.tdwg.org/dwc/terms/individualCount" />
    <field index="17" term="http://rs.tdwg.org/dwc/terms/sex" />
    <field index="18" term="http://rs.tdwg.org/dwc/terms/associatedTaxa" />
    <field index="19" term="http://rs.tdwg.org/dwc/terms/identificationVerificationStatus" />
  </core>
  <extension encoding="UTF-8" linesTerminatedBy="\\n" fieldsTerminatedBy="," fieldsEnclosedBy="&quot;" ignoreHeaderLines="1" rowType="http://rs.gbif.org/terms/1.0/Multimedia">
    <files><location>multimedia.csv</location></files>
    <coreid index="0" />
    <field index="1" term="http://purl.org/dc/terms/identifier" />
    <field index="2" term="http://purl.org/dc/terms/format" />
  </extension>
</archive>`;

export const OCCURRENCE_HEADERS = [
  "coreid",
  "basisOfRecord",
  "recordedBy",
  "eventDate",
  "scientificName",
  "kingdom",
  "phylum",
  "class",
  "order",
  "family",
  "genus",
  "decimalLatitude",
  "decimalLongitude",
  "coordinateUncertaintyInMeters",
  "lifeStage",
  "reproductiveCondition",
  "individualCount",
  "sex",
  "associatedTaxa",
  "identificationVerificationStatus",
].map((h) => `"${h}"`).join(",");

export const MULTIMEDIA_HEADERS = ["coreid", "identifier", "format"]
  .map((h) => `"${h}"`).join(",");

// RFC 4180-compliant CSV field encoder.
// Wraps every value in double quotes and escapes internal double quotes by doubling them.
// Nulls and undefined become empty quoted fields ("").
// Newlines are replaced with a space — DwC-A parsers treat \n as a row terminator.
function csvField(value: string | number | null | undefined): string {
  if (value == null) return '""';
  const str = String(value)
    .replace(/\r?\n/g, " ") // flatten newlines
    .replace(/"/g, '""'); // RFC 4180: escape " by doubling
  return `"${str}"`;
}

export async function generateDwcARow(
  scan: DBScanRow,
  exportScope: ExportScope,
  includePreciseCoordinates: boolean,
  requestingUserId: string,
  pseudonymizer: UserPseudonymizer | null,
): Promise<{ occurrenceRow: string; mRows: string[] }> {
  return {
    occurrenceRow: await generateOccurrenceRow(
      scan,
      exportScope,
      includePreciseCoordinates,
      requestingUserId,
      pseudonymizer,
    ),
    mRows: generateMultimediaRows(scan),
  };
}

export async function generateOccurrenceRow(
  scan: DBScanRow,
  exportScope: ExportScope,
  includePreciseCoordinates: boolean,
  requestingUserId: string,
  pseudonymizer: UserPseudonymizer | null,
): Promise<string> {
  const species = scan.species_dictionary;
  const date = scan.timestamp ? new Date(scan.timestamp).toISOString() : "";
  const isTombstoned = scan.user_id === "00000000-0000-0000-0000-000000000000";
  let recordedBy = "Naturebook Citizen Scientist";

  if (!isTombstoned) {
    if (exportScope === "global") {
      if (!pseudonymizer) {
        throw new ExportWorkerError(
          "pseudonym_key_unavailable",
          "Global exports require a dedicated pseudonymizer.",
        );
      }
      recordedBy = await pseudonymizer.pseudonymize(scan.user_id);
    } else {
      recordedBy = scan.user_id;
    }
  }

  const isProtected = [
    "vulnerable",
    "endangered",
    "critically_endangered",
    "near_threatened",
  ].includes(species?.iucn_red_list_status || "");
  const canAccessPrecise = includePreciseCoordinates &&
    (scan.user_id === requestingUserId);

  let lat: number | string | undefined | null = canAccessPrecise && !isProtected
    ? scan.gps_lat_exact
    : scan.gps_lat_public;
  let lon: number | string | undefined | null = canAccessPrecise && !isProtected
    ? scan.gps_long_exact
    : scan.gps_long_public;
  const uncertainty = canAccessPrecise && !isProtected
    ? scan.coordinate_uncertainty_in_meters || ""
    : "50000";

  if (isProtected && typeof lat === "number" && typeof lon === "number") {
    lat = Math.round(lat * 10) / 10;
    lon = Math.round(lon * 10) / 10;
  }

  if (lat == null) lat = "";
  if (lon == null) lon = "";

  const lifeStage = scan.life_stage || "unknown";
  const reproductiveCondition = scan.reproductive_condition || "not_applicable";
  const individualCount = scan.individual_count != null
    ? scan.individual_count
    : "";
  const sex = scan.sex || "";

  // Join ecological interactions with " | " separator; commas within each entry become
  // semicolons so the joined string doesn't need further escaping beyond csvField's quoting.
  const associatedTaxa = scan.ecological_interactions?.length
    ? scan.ecological_interactions.map((s: string) => s.replace(/,/g, ";"))
      .join(" | ")
    : "";

  const verificationStatus = scan.ai_confidence_score != null
    ? scan.ai_confidence_score.toFixed(2)
    : "";

  // All fields wrapped with csvField() — RFC 4180 quoting handles commas, quotes, newlines.
  return [
    csvField(scan.id),
    csvField("HumanObservation"),
    csvField(recordedBy),
    csvField(date),
    csvField(species?.scientific_name),
    csvField(species?.kingdom),
    csvField(species?.phylum),
    csvField(species?.class),
    csvField(species?.order),
    csvField(species?.family),
    csvField(species?.genus),
    csvField(lat),
    csvField(lon),
    csvField(uncertainty),
    csvField(lifeStage),
    csvField(reproductiveCondition),
    csvField(individualCount),
    csvField(sex),
    csvField(associatedTaxa),
    csvField(verificationStatus),
  ].join(",");
}

export function generateMultimediaRows(scan: DBScanRow): string[] {
  const urls = scan.image_storage_urls || [];
  return urls.map((url: string) =>
    [csvField(scan.id), csvField(url), csvField("image/webp")].join(",")
  );
}
