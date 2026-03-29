import { encodeHex } from "https://deno.land/std@0.224.0/encoding/hex.ts";
import { DBScanRow } from "./types.ts";

export const DWCA_META_XML = `<?xml version="1.0" encoding="UTF-8"?>
<archive xmlns="http://rs.tdwg.org/dwc/text/">
  <core encoding="UTF-8" linesTerminatedBy="\\n" fieldsTerminatedBy="," fieldsEnclosedBy="" ignoreHeaderLines="1" rowType="http://rs.tdwg.org/dwc/terms/Occurrence">
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
    <field index="17" term="http://rs.tdwg.org/dwc/terms/associatedTaxa" />
    <field index="18" term="http://rs.tdwg.org/dwc/terms/identificationVerificationStatus" />
  </core>
  <extension encoding="UTF-8" linesTerminatedBy="\\n" fieldsTerminatedBy="," fieldsEnclosedBy="" ignoreHeaderLines="1" rowType="http://rs.gbif.org/terms/1.0/Multimedia">
    <files><location>multimedia.csv</location></files>
    <coreid index="0" />
    <field index="1" term="http://purl.org/dc/terms/identifier" />
    <field index="2" term="http://purl.org/dc/terms/format" />
  </extension>
</archive>`;

export const OCCURRENCE_HEADERS =
  "coreid,basisOfRecord,recordedBy,eventDate,scientificName,kingdom,phylum,class,order,family,genus,decimalLatitude,decimalLongitude,coordinateUncertaintyInMeters,lifeStage,reproductiveCondition,individualCount,associatedTaxa,identificationVerificationStatus";
export const MULTIMEDIA_HEADERS = "coreid,identifier,format";

export async function generateDwcARow(
  scan: DBScanRow,
  export_scope: string,
  include_precise_coordinates: boolean,
  requestingUserId: string,
  secretHashSalt: string,
): Promise<{ occurrenceRow: string; mRows: string[] }> {
  const species = scan.species_dictionary || {};
  const date = scan.timestamp ? new Date(scan.timestamp).toISOString() : "";
  const isTombstoned = scan.user_id === "00000000-0000-0000-0000-000000000000";
  let recordedBy = "Merian Citizen Scientist";

  if (!isTombstoned) {
    if (export_scope === "global") {
      const hashData = new TextEncoder().encode(scan.user_id + secretHashSalt);
      const hashBuffer = await crypto.subtle.digest("SHA-256", hashData);
      recordedBy = `merian_user_${
        encodeHex(new Uint8Array(hashBuffer)).substring(0, 16)
      }`;
    } else {
      recordedBy = scan.user_id;
    }
  }

  const isProtected = [
    "vulnerable",
    "endangered",
    "critically_endangered",
    "near_threatened",
  ].includes(species.iucn_red_list_status || "");
  const canAccessPrecise = include_precise_coordinates &&
    (scan.user_id === requestingUserId);

  let lat: number | string | undefined | null =
    canAccessPrecise && !isProtected ? scan.gps_lat_exact : scan.gps_lat_public;
  let lon: number | string | undefined | null =
    canAccessPrecise && !isProtected
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
  const associatedTaxa =
    scan.ecological_interactions && scan.ecological_interactions.length > 0
      ? scan.ecological_interactions.join(" | ").replace(/,/g, ";").replace(
        /"/g,
        "",
      )
      : "";
  const verificationStatus = scan.ai_confidence_score != null
    ? scan.ai_confidence_score.toFixed(2)
    : "";

  const occurrenceRow = `${scan.id},HumanObservation,${recordedBy},${date},${
    species.scientific_name || ""
  },${species.kingdom || ""},${species.phylum || ""},${species.class || ""},${
    species.order || ""
  },${species.family || ""},${
    species.genus || ""
  },${lat},${lon},${uncertainty},${lifeStage},${reproductiveCondition},${individualCount},"${associatedTaxa}",${verificationStatus}`;

  const urls = scan.image_storage_urls || [];
  const mRows = urls.map((url: string) => `${scan.id},${url},image/webp`);

  return { occurrenceRow, mRows };
}
