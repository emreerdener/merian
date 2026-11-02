import { assert } from "@std/assert";

const sql = (await Deno.readTextFile(
  new URL(
    "../../migrations/20261102100657_prepare_initial_cpm_admission_storage.sql",
    import.meta.url,
  ),
)).replace(/^--.*$/gm, "");

Deno.test("CPM storage preparation cannot activate admission or bypass existing witnesses", () => {
  assert(
    !/\bGRANT\s|SECURITY DEFINER|CREATE(?: OR REPLACE)? FUNCTION public\./i
      .test(sql),
  );
  assert(
    !/\bDROP\s+(?:CONSTRAINT|NOT NULL|TRIGGER)|DISABLE\s+TRIGGER/i.test(sql),
  );
  assert(!/\bUPDATE\s+internal\.|\bDELETE\s+FROM|\bINSERT\s+INTO/i.test(sql));
});

Deno.test("legacy receipt construction fills composite discriminator without changing canonical proof", () => {
  assert(sql.includes("result.admission_variant:=''server_prepared_v3'';"));
  assert(sql.includes("internal.build_initial_admission_receipt(uuid)"));
  assert(sql.includes("initial admission receipt builder source drift"));
  assert(!sql.includes("DROP FUNCTION"));
  assert(!sql.includes("CREATE TABLE"));
});
