import { assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

Deno.test("completed Field Trips publish their credited items", async () => {
  await withExploreDbTest(
    "fieldTripPublicationDb.test",
    async (client: Client) => {
      const userId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const templateId = crypto.randomUUID();
      const levelId = crypto.randomUUID();
      const itemId = crypto.randomUUID();
      const tripId = crypto.randomUUID();

      await insertUser(client, userId, "Publication Viewer");
      await insertSpecies(client, speciesId, "Testus publicationis");
      await insertScan(client, {
        id: scanId,
        userId,
        speciesId,
        confirmedSpeciesId: speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "private",
      });
      await client.queryArray(
        `
          INSERT INTO public.field_trip_templates(
            id, slug, title, difficulty, is_pro_only, is_rotating_free,
            is_active, sort_order
          )
          VALUES ($1, $2, 'Publication fixture', 'starter', FALSE, FALSE, TRUE, 999)
        `,
        [templateId, `publication_${templateId.slice(0, 8)}`],
      );
      await client.queryArray(
        `INSERT INTO public.field_trip_levels(id, template_id, level_number, title) VALUES ($1, $2, 1, 'Level 1')`,
        [levelId, templateId],
      );
      await client.queryArray(
        `
          INSERT INTO public.field_trip_checklist_items(
            id, level_id, prompt, match_type, species_id, sort_order
          )
          VALUES ($1, $2, 'Publication species', 'species', $3, 1)
        `,
        [itemId, levelId, speciesId],
      );
      await client.queryArray(
        `
          INSERT INTO public.user_field_trips(
            id, user_id, template_id, started_at, current_level_number,
            completed_at, is_profile_visible
          )
          VALUES ($1, $2, $3, NOW() - INTERVAL '1 hour', 1, NOW(), TRUE)
        `,
        [tripId, userId, templateId],
      );
      await client.queryArray(
        `
          INSERT INTO public.user_field_trip_item_completions(
            user_field_trip_id, item_id, scan_id, species_id,
            common_name, scientific_name
          )
          VALUES ($1, $2, $3, $4, 'Publication species', 'Testus publicationis')
        `,
        [tripId, itemId, scanId, speciesId],
      );

      const published = await client.queryObject<{
        data: { publication_id: string };
      }>(
        `SELECT public.publish_field_trip($1, $2, 'My Field Trip', 'Notes', 'Summary') AS data`,
        [userId, tripId],
      );
      const publicationId = published.rows[0].data.publication_id;

      const materialized = await client.queryObject<{
        title: string;
        item_count: number;
        item_publication_id: string;
      }>(
        `
          SELECT
            publication.title,
            COUNT(item.id)::INTEGER AS item_count,
            MIN(item.publication_id::TEXT) AS item_publication_id
          FROM public.field_trip_publications publication
          JOIN public.field_trip_publication_items item
            ON item.publication_id = publication.id
          WHERE publication.id = $1
          GROUP BY publication.id
        `,
        [publicationId],
      );
      assertEquals(materialized.rows[0], {
        title: "My Field Trip",
        item_count: 1,
        item_publication_id: publicationId,
      });

      await client.queryArray(
        `SELECT public.set_field_trip_pinned_publications($1, $2::UUID[])`,
        [userId, [publicationId, publicationId]],
      );
      const pinned = await client.queryObject<{ pin_position: number }>(
        `SELECT profile_pin_position AS pin_position FROM public.field_trip_publications WHERE id = $1`,
        [publicationId],
      );
      assertEquals(pinned.rows[0].pin_position, 1);
    },
  );
});
