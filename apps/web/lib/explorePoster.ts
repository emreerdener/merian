export function approvedExplorePoster(value: string | null): URL | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    if (
      url.protocol !== "https:" || url.port || url.username || url.password ||
      url.search || url.hash || /%|\\/.test(url.pathname)
    ) return null;
    if (!/\.(?:jpe?g|png|webp|avif)$/i.test(url.pathname)) return null;
    if (
      url.hostname === "media.merian.app" &&
      /^\/public_uploads\/(?:free|pro)\//.test(url.pathname)
    ) return url;
    if (
      url.hostname === "upload.wikimedia.org" &&
      url.pathname.startsWith("/wikipedia/commons/")
    ) return url;
  } catch { /* unsupported poster */ }
  return null;
}

export async function readBoundedPoster(
  response: Response,
  maximum = 8 * 1024 * 1024,
): Promise<Uint8Array> {
  if (
    Number(response.headers.get("content-length")) > maximum || !response.body
  ) {
    await response.body?.cancel();
    throw new Error("Unsupported poster");
  }
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maximum) throw new Error("Unsupported poster");
      chunks.push(value);
    }
  } finally {
    await reader.cancel();
  }
  const result = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
}
