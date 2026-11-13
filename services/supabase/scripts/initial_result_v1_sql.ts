/** SQL's structural rules come from the frozen v1 owner, never live Identify. */
import {
  dataContractV1,
  provenanceContractV1,
} from "../functions/_shared/initialAnalysis/resultSchemaV1.ts";
export function initialResultV1SchemaSQL(): string {
  const text = JSON.stringify({
    data: dataContractV1,
    provenance: provenanceContractV1,
  });
  if (text.includes("$result_v1_json$")) {
    throw new Error("result_schema_delimiter_conflict");
  }
  return `-- BEGIN FROZEN RESULT_V1_SCHEMA\nCREATE FUNCTION internal.initial_result_schema_v1() RETURNS JSONB\nLANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $result_v1_schema$\n SELECT $result_v1_json$${text}$result_v1_json$::JSONB;\n$result_v1_schema$;\n-- END FROZEN RESULT_V1_SCHEMA`;
}
if (import.meta.main) console.log(initialResultV1SchemaSQL());
