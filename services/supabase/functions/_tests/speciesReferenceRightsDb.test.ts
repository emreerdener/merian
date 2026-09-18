import { assertEquals } from "@std/assert";
import { insertSpecies, withExploreDbTest } from "./exploreDbTestHelpers.ts";
import { referenceImageRowsFromRefreshCache } from "../refresh-species-content/db.ts";
import {
  type PublicSpeciesReferenceImageRow,
  publicWebReferenceImageAttributionIssues,
  referenceImagesFromRows,
} from "../_shared/publicSpeciesProjection.ts";

Deno.test("reference rights DB - fills missing credits and preserves them through later URL-only refresh", async () => {
  await withExploreDbTest("speciesReferenceRightsDb", async (client) => {
    const speciesID = crypto.randomUUID();
    const url =
      "https://upload.wikimedia.org/wikipedia/commons/a/ab/Fixture_flower.jpg";
    await insertSpecies(client, speciesID, `Fixture species ${speciesID}`);
    const replace = async (images: unknown) => {
      await client.queryArray(
        "SELECT public.replace_species_reference_images($1, $2::jsonb)",
        [speciesID, JSON.stringify(images)],
      );
    };
    const read = async () =>
      (await client.queryObject<PublicSpeciesReferenceImageRow>(
        "SELECT url, source, license, attribution FROM public.species_reference_images WHERE species_id = $1",
        [speciesID],
      )).rows;
    const uncredited = referenceImageRowsFromRefreshCache(url, null);
    await replace(uncredited);
    assertEquals(
      publicWebReferenceImageAttributionIssues(
        referenceImagesFromRows(await read(), null),
      ).length,
      1,
    );
    const credited = referenceImageRowsFromRefreshCache(url, null, new Date(), [
      {
        url,
        source: "wikipedia",
        license: "https://creativecommons.org/licenses/by-sa/4.0/",
        attribution: "Example Photographer",
      },
    ]);
    await replace(credited);
    const rows = await read();
    assertEquals(rows.length, 1);
    assertEquals(rows[0].attribution, "Example Photographer");
    assertEquals(
      rows[0].license,
      "https://creativecommons.org/licenses/by-sa/4.0/",
    );
    assertEquals(
      publicWebReferenceImageAttributionIssues(
        referenceImagesFromRows(rows, null),
      ),
      [],
    );
    await replace(uncredited);
    assertEquals(await read(), rows);
    const privileges = await client.queryObject<
      { anon: boolean; authenticated: boolean; service: boolean }
    >(`SELECT
      has_function_privilege('anon', 'public.replace_species_reference_images(uuid,jsonb)', 'EXECUTE') AS anon,
      has_function_privilege('authenticated', 'public.replace_species_reference_images(uuid,jsonb)', 'EXECUTE') AS authenticated,
      has_function_privilege('service_role', 'public.replace_species_reference_images(uuid,jsonb)', 'EXECUTE') AS service`);
    assertEquals(privileges.rows[0], {
      anon: false,
      authenticated: false,
      service: true,
    });
  });
});
