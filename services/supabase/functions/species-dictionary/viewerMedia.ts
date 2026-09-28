import type { SupabaseClient } from "@supabase/supabase-js";

/** Bounded, service-mediated filtering; source and reporter identities stay private. */
export async function allowedReferenceMedia(
  candidateURLs: (string | null | undefined)[],
  viewerId: string | undefined,
  admin: SupabaseClient,
): Promise<Set<string>> {
  const candidates = [
    ...new Set(candidateURLs.map((url) => (url ?? "").trim()).filter(Boolean)),
  ];
  if (!viewerId) return new Set(candidates);
  const allowed = new Set<string>();
  for (let start = 0; start < candidates.length; start += 500) {
    const batch = candidates.slice(start, start + 500);
    const { data, error } = await admin.rpc("filter_reported_explore_media", {
      self_id: viewerId,
      candidate_urls: batch,
    });
    if (
      error || !Array.isArray(data) ||
      data.some((url) => typeof url !== "string" || !batch.includes(url))
    ) {
      throw new Error("Could not resolve reference image visibility");
    }
    for (const url of data) allowed.add(url);
  }
  return allowed;
}

export function referenceURLs(value: string | null | undefined): string[] {
  return (value ?? "").split(",").map((url) => (url ?? "").trim()).filter(
    Boolean,
  );
}
