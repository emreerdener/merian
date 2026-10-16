import { exactObject, invalidHistory } from "./contract.ts";
import { parsePreparedVideoProvenance } from "./videoProvenance.ts";

/** Private metadata only. No executable admission, upload or reader authority. */
export function parsePreparedVideoManifest(
  value: unknown,
  observationID: string,
  analysisID: string,
) {
  const row = exactObject(value, [
    "schema_version",
    "provenance",
    "descriptions",
  ]);
  if (
    row.schema_version !== 4 || !Array.isArray(row.descriptions) ||
    row.descriptions.length > 64
  ) return invalidHistory();
  const provenance = parsePreparedVideoProvenance(
    row.provenance,
    observationID,
    analysisID,
  );
  let units = 0;
  const descriptions = row.descriptions.map((text) => {
    if (
      typeof text !== "string" || !text.trim() ||
      [...text].length > 8192 || text.length > 16384 ||
      text.length > 32000 - units ||
      /[\uD800-\uDFFF]/u.test(text)
    ) return invalidHistory();
    units += text.length;
    return text;
  });
  return Object.freeze({
    schema_version: 4 as const,
    provenance,
    descriptions: Object.freeze(descriptions),
  });
}
