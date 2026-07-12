import { type NextRequest } from "next/server";
import { proxiedExploreAudioUrl } from "@/lib/audioProxy";

const MAX_AUDIO_BYTES = 20 * 1024 * 1024;

export async function GET(request: NextRequest) {
  const source = proxiedExploreAudioUrl(request.nextUrl.searchParams.get("url") ?? "");
  if (!source) return new Response("Invalid audio source", { status: 400 });

  const range = request.headers.get("range");
  const upstream = await fetch(source, {
    headers: range ? { Range: range } : undefined,
    cache: "force-cache",
  });
  if (!upstream.ok || !upstream.body) {
    return new Response("Audio unavailable", { status: upstream.status || 502 });
  }

  const contentLength = Number(upstream.headers.get("content-length") ?? 0);
  if (!range && contentLength > MAX_AUDIO_BYTES) {
    return new Response("Audio is too large", { status: 413 });
  }

  const headers = new Headers({
    "Content-Type": upstream.headers.get("content-type") ?? "audio/wav",
    "Cache-Control": "public, max-age=3600, s-maxage=86400",
    "Accept-Ranges": "bytes",
  });
  for (const name of ["content-length", "content-range", "etag", "last-modified"]) {
    const value = upstream.headers.get(name);
    if (value) headers.set(name, value);
  }

  return new Response(upstream.body, { status: upstream.status, headers });
}
