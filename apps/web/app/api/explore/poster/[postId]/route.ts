import sharp from "sharp";
import { fetchExplorePost } from "@/lib/explore";
import { isExplorePostId } from "@/lib/exploreCursor";
import { exploreGridPosterUrl } from "@/lib/exploreMedia";
import { approvedExplorePoster, readBoundedPoster } from "@/lib/explorePoster";

export const dynamic = "force-dynamic";
export async function GET(
  _request: Request,
  context: { params: Promise<{ postId: string }> },
) {
  const headers = {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  };
  const { postId } = await context.params;
  if (!isExplorePostId(postId)) {
    return new Response(null, { status: 404, headers });
  }
  try {
    const post = await fetchExplorePost(postId);
    const url = post && approvedExplorePoster(exploreGridPosterUrl(post));
    if (!url) return new Response(null, { status: 404, headers });
    const upstream = await fetch(url, {
      redirect: "error",
      cache: "no-store",
      signal: AbortSignal.timeout(8000),
    });
    const type = upstream.headers.get("content-type")?.split(";")[0].trim();
    if (!upstream.ok || !type || !/^image\/(jpeg|png|webp|avif)$/.test(type)) {
      await upstream.body?.cancel();
      return new Response(null, { status: 502, headers });
    }
    const body = await readBoundedPoster(upstream);
    const thumbnail = await sharp(body, {
      limitInputPixels: 16_777_216,
      animated: false,
    })
      .rotate().resize(512, 512, { fit: "cover", withoutEnlargement: true })
      .webp({ quality: 82 }).timeout({ seconds: 3 }).toBuffer();
    return new Response(thumbnail as BodyInit, {
      headers: { ...headers, "Content-Type": "image/webp" },
    });
  } catch {
    return new Response(null, { status: 503, headers });
  }
}
