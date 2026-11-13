import { visibilityIds } from "@/lib/exploreVisibility";
import { publicVisibility } from "@/lib/exploreVisibilityServer";
export const dynamic = "force-dynamic";
const headers = { "Cache-Control": "no-store" };
export async function GET(request: Request) {
  const raw = new URL(request.url).searchParams.get("ids");
  if (!raw || raw.length > 4735) {
    return Response.json({ error: "invalid_ids" }, { status: 400, headers });
  }
  const ids = visibilityIds(raw.split(","));
  if (!ids) {
    return Response.json({ error: "invalid_ids" }, { status: 400, headers });
  }
  try {
    return Response.json(await publicVisibility(ids, request.signal), {
      headers,
    });
  } catch {
    return Response.json({ error: "visibility_unavailable" }, {
      status: 503,
      headers,
    });
  }
}
