import { publicVisibility } from "@/lib/exploreVisibilityServer";
import { exploreVisibilityStream } from "@/lib/exploreVisibilityStream";
export const dynamic = "force-dynamic";
export const maxDuration = 60;
export function GET(request: Request) {
  return exploreVisibilityStream(request, publicVisibility);
}
