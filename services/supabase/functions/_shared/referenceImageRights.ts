/** Rights collected from the image itself, never from its parent occurrence. */
export interface ExternalReferenceImage {
  url: string;
  source: "wikipedia" | "gbif";
  license?: string;
  attribution?: string;
}

/** Conservative ingestion allowlist; unknown/restricted terms need review. */
export function reusableImageLicense(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const label = value.trim();
  const cc = /^CC[ -]BY([ -]SA)?[ -](1\.0|2\.0|2\.5|3\.0|4\.0)( au)?$/i.exec(
    label,
  );
  if (cc) {
    if (cc[3] && cc[2] !== "3.0") return null;
    return `https://creativecommons.org/licenses/by${cc[1] ? "-sa" : ""}/${
      cc[2]
    }/${cc[3] ? "au/" : ""}`;
  }
  if (/^(CC0(?: 1\.0)?|public domain)$/i.test(label)) {
    return /public domain/i.test(label)
      ? "https://creativecommons.org/publicdomain/mark/1.0/"
      : "https://creativecommons.org/publicdomain/zero/1.0/";
  }
  try {
    const url = new URL(label);
    if (
      !["https:", "http:"].includes(url.protocol) ||
      url.hostname !== "creativecommons.org" || url.port || url.username ||
      url.password || url.search || url.hash
    ) return null;
    const path = url.pathname.replace(
      /\/(?:legalcode|deed(?:\.[a-z-]+)?)\/?$/i,
      "/",
    );
    if (
      !/^\/licenses\/by(?:-sa)?\/(?:(?:1\.0|2\.0|2\.5|3\.0|4\.0)|3\.0\/au)\/?$/
        .test(path) &&
      !/^\/publicdomain\/(?:zero|mark)\/1\.0\/?$/.test(path)
    ) return null;
    return `https://creativecommons.org${path.replace(/\/?$/, "/")}`;
  } catch {
    return null;
  }
}

/** Plain text only. Unsupported entities fail closed instead of mangling credit. */
export function imageCreditText(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 8192) return null;
  const entities: Record<string, string> = {
    amp: "&",
    lt: "<",
    gt: ">",
    quot: '"',
    apos: "'",
    nbsp: " ",
    copy: "©",
    ndash: "–",
    mdash: "—",
  };
  let invalid = false;
  const text = value
    .replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, "")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style\s*>/gi, "")
    .replace(/<[^>]*>/g, " ")
    .replace(/&(#x[0-9a-f]+|#\d+|[a-z][a-z0-9]+);/gi, (_, entity: string) => {
      if (entity.startsWith("#")) {
        const hex = entity[1].toLowerCase() === "x";
        const code = Number.parseInt(entity.slice(hex ? 2 : 1), hex ? 16 : 10);
        if (
          code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff)
        ) {
          return String.fromCodePoint(code);
        }
      } else if (Object.hasOwn(entities, entity)) return entities[entity];
      invalid = true;
      return "";
    })
    .replace(/\s+/g, " ").trim();
  return !invalid && text.length > 0 && text.length <= 2048 &&
      !hasControlCharacters(text)
    ? text
    : null;
}

export function commonsImageIdentity(value: string): {
  title: string;
  originalURL: string;
  pageURL: string;
} | null {
  try {
    const url = new URL(value);
    if (
      url.protocol !== "https:" || url.hostname !== "upload.wikimedia.org" ||
      url.port || url.username || url.password
    ) return null;
    // Static Commons files are identified by path; summary URLs can carry
    // tracking parameters. Never forward those parameters to the metadata API.
    const match =
      /^\/wikipedia\/commons\/(thumb\/)?([a-f0-9]\/([a-f0-9]{2})\/([^/]+))(\/[^/]+)?$/
        .exec(url.pathname);
    if (
      !match || !match[3].startsWith(match[2][0]) ||
      Boolean(match[1]) !== Boolean(match[5])
    ) return null;
    const name = decodeURIComponent(match[4]);
    if (!name || /[|/\\]/.test(name) || hasControlCharacters(name)) return null;
    const title = `File:${name}`;
    return {
      title,
      originalURL: `https://upload.wikimedia.org/wikipedia/commons/${match[2]}`,
      pageURL: `https://commons.wikimedia.org/wiki/${
        encodeURIComponent(title)
      }`,
    };
  } catch {
    return null;
  }
}

function hasControlCharacters(value: string): boolean {
  return Array.from(value).some((character) => {
    const code = character.charCodeAt(0);
    return code < 32 || code === 127;
  });
}
