import type { SupabaseClient } from "@supabase/supabase-js";
import type { SpeciesDictionaryCatalogItem } from "../species-dictionary/db.ts";
import type { PublicExploreSpeciesPostRow } from "../get-explore-species-posts/response.ts";
import {
  withExploreAuthorProBadges,
  withExploreAuthorUsernames,
  withExplorePostHashtags,
} from "../_shared/explore.ts";
import type { ResultKind, SearchContext, SearchCursor } from "./contract.ts";
export interface SearchPage {
  species: { item: SpeciesDictionaryCatalogItem; excerpt: string }[];
  sightings: PublicExploreSpeciesPostRow[];
  next_cursor: SearchCursor | null;
}
export async function searchPage(
  admin: SupabaseClient,
  userId: string,
  context: SearchContext,
  kind: ResultKind,
  cursor: SearchCursor | null,
): Promise<SearchPage> {
  const { data, error } = await admin.rpc("search_species_discovery", {
    self_id: userId,
    search_text: context.query,
    group_filter: context.group,
    media_filter: context.media,
    result_kind: kind,
    page_cursor: cursor,
    name_only: context.mode === "name",
  }).abortSignal(AbortSignal.timeout(10000));
  if (
    error || !data || !Array.isArray(data.species) ||
    !Array.isArray(data.sightings) || data.species.length > 20 ||
    data.sightings.length > 20
  ) throw new Error("Discovery retrieval failed");
  const page: SearchPage = data;
  if (page.sightings.length) {
    page.sightings = await withExplorePostHashtags(
      await withExploreAuthorUsernames(
        await withExploreAuthorProBadges(page.sightings, admin),
        admin,
      ),
      admin,
    );
    // Keep the viewer-aware RPC's media projection. Rehydrating the source
    // media table here could restore missing media excluded by that projection.
  }
  return page;
}
