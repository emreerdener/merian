/**
 * Executable contract for the owner-visible `public.scans.captured_media`
 * JSONB projection.
 *
 * The durable wire shape intentionally preserves the outer wrappers emitted by
 * Swift's synthesized enum Codable representation so installed clients remain
 * compatible. New descriptions persist only their text. Capture chronology is
 * represented by array order; legacy `addedAt` values are read-only metadata
 * and are discarded by the compatibility parser.
 *
 * Keep this module dependency-free. It is imported by deployed Edge Functions
 * and by the generated Swift DTO tooling.
 */

export const CAPTURED_MEDIA_WIRE_VERSION = 1;
export const CAPTURED_MEDIA_MAX_ITEMS = 64;
export const CAPTURED_MEDIA_MAX_PATH_LENGTH = 4_096;
export const CAPTURED_MEDIA_MAX_DESCRIPTION_LENGTH = 8_192;
export const CAPTURED_MEDIA_MAX_SOURCE_INDEX = 63;

export type StoredMediaReferenceDTO = {
  storage: "remoteURL";
  path: string;
  sourceIndex?: number;
};

export type LegacyLocalMediaReferenceDTO = {
  /** Read-only compatibility with pre-promotion manifests. */
  storage: "localFile";
  path: string;
  sourceIndex?: number;
};

export type CompatibleStoredMediaReferenceDTO =
  | StoredMediaReferenceDTO
  | LegacyLocalMediaReferenceDTO;

export type CapturedMediaDescriptionContextDTO = {
  freeText: string;
};

export type SerializedMediaItemDTO =
  | { image: { _0: StoredMediaReferenceDTO } }
  | { audio: { _0: StoredMediaReferenceDTO } }
  | {
    video: {
      _0: {
        video: StoredMediaReferenceDTO;
        thumbnail?: StoredMediaReferenceDTO;
      };
    };
  }
  | { description: { _0: CapturedMediaDescriptionContextDTO } };

export type CompatibleSerializedMediaItemDTO =
  | { image: { _0: CompatibleStoredMediaReferenceDTO } }
  | { audio: { _0: CompatibleStoredMediaReferenceDTO } }
  | {
    video: {
      _0: {
        video: CompatibleStoredMediaReferenceDTO;
        thumbnail?: CompatibleStoredMediaReferenceDTO;
        /** Read-only compatibility with manifests written before companion-audio removal. */
        audio?: CompatibleStoredMediaReferenceDTO;
      };
    };
  }
  | { description: { _0: CapturedMediaDescriptionContextDTO } };

export const capturedMediaSwiftDTOContract = {
  version: CAPTURED_MEDIA_WIRE_VERSION,
  maxItems: CAPTURED_MEDIA_MAX_ITEMS,
  maxPathLength: CAPTURED_MEDIA_MAX_PATH_LENGTH,
  maxDescriptionLength: CAPTURED_MEDIA_MAX_DESCRIPTION_LENGTH,
  maxSourceIndex: CAPTURED_MEDIA_MAX_SOURCE_INDEX,
  storageValues: ["remoteURL"],
  variants: [
    { wireKey: "image", swiftCase: "image", payload: "reference" },
    { wireKey: "audio", swiftCase: "audio", payload: "reference" },
    { wireKey: "video", swiftCase: "video", payload: "video" },
    {
      wireKey: "description",
      swiftCase: "description",
      payload: "description",
    },
  ],
  legacyReadCompatibility: {
    emptyManifestAcceptedAsMissing: true,
    sourceIndexSnakeCase: true,
    descriptionFreeTextSnakeCase: true,
    descriptionAddedAtIgnored: true,
    localFileReferenceIgnored: true,
    videoAudioReference: true,
  },
} as const;

export class CapturedMediaContractError extends Error {
  override readonly name = "CapturedMediaContractError";

  constructor(
    readonly path: string,
    message: string,
  ) {
    super(`${path}: ${message}`);
  }
}

function recordAt(value: unknown, path: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new CapturedMediaContractError(path, "expected an object");
  }
  return value as Record<string, unknown>;
}

function assertExactKeys(
  value: Record<string, unknown>,
  allowed: readonly string[],
  path: string,
): void {
  const allowedKeys = new Set(allowed);
  const unexpected = Object.keys(value).filter((key) => !allowedKeys.has(key));
  if (unexpected.length > 0) {
    throw new CapturedMediaContractError(
      path,
      `unexpected key '${unexpected.sort()[0]}'`,
    );
  }
}

function parseSourceIndex(
  value: Record<string, unknown>,
  path: string,
  compatibility: boolean,
): number | undefined {
  const hasCamel = Object.hasOwn(value, "sourceIndex");
  const hasSnake = Object.hasOwn(value, "source_index");
  if (hasCamel && hasSnake) {
    throw new CapturedMediaContractError(
      path,
      "source index aliases cannot both be present",
    );
  }
  if (hasSnake && !compatibility) {
    throw new CapturedMediaContractError(
      path,
      "source_index is legacy-only",
    );
  }
  const raw = hasCamel ? value.sourceIndex : value.source_index;
  if (raw == null) return undefined;
  if (
    typeof raw !== "number" || !Number.isSafeInteger(raw) || raw < 0 ||
    raw > CAPTURED_MEDIA_MAX_SOURCE_INDEX
  ) {
    throw new CapturedMediaContractError(
      path,
      `source index must be an integer from 0 through ${CAPTURED_MEDIA_MAX_SOURCE_INDEX}`,
    );
  }
  return raw;
}

function parseMediaReference(
  value: unknown,
  path: string,
  compatibility: boolean,
): CompatibleStoredMediaReferenceDTO {
  const reference = recordAt(value, path);
  assertExactKeys(
    reference,
    compatibility
      ? ["storage", "path", "sourceIndex", "source_index"]
      : ["storage", "path", "sourceIndex"],
    path,
  );
  const storage = reference.storage;
  if (storage !== "remoteURL" && !(compatibility && storage === "localFile")) {
    throw new CapturedMediaContractError(
      `${path}.storage`,
      compatibility
        ? "expected remoteURL or legacy localFile"
        : "expected remoteURL",
    );
  }
  if (typeof reference.path !== "string") {
    throw new CapturedMediaContractError(`${path}.path`, "expected a string");
  }
  const normalizedPath = reference.path.trim();
  if (
    normalizedPath.length === 0 ||
    normalizedPath.length > CAPTURED_MEDIA_MAX_PATH_LENGTH
  ) {
    throw new CapturedMediaContractError(
      `${path}.path`,
      `must contain 1 through ${CAPTURED_MEDIA_MAX_PATH_LENGTH} characters`,
    );
  }
  const sourceIndex = parseSourceIndex(reference, path, compatibility);
  if (storage === "localFile") {
    return {
      storage,
      path: normalizedPath,
      ...(sourceIndex == null ? {} : { sourceIndex }),
    };
  }
  let url: URL;
  try {
    url = new URL(normalizedPath);
  } catch {
    throw new CapturedMediaContractError(
      `${path}.path`,
      "expected an absolute HTTPS URL",
    );
  }
  if (
    url.protocol !== "https:" || !url.hostname || url.username || url.password
  ) {
    throw new CapturedMediaContractError(
      `${path}.path`,
      "expected a credential-free HTTPS URL",
    );
  }
  return {
    storage: "remoteURL",
    path: normalizedPath,
    ...(sourceIndex == null ? {} : { sourceIndex }),
  };
}

function parseDescription(
  value: unknown,
  path: string,
  compatibility: boolean,
): CapturedMediaDescriptionContextDTO {
  const context = recordAt(value, path);
  assertExactKeys(
    context,
    compatibility
      ? ["freeText", "free_text", "addedAt", "added_at"]
      : ["freeText"],
    path,
  );
  const hasCamel = Object.hasOwn(context, "freeText");
  const hasSnake = Object.hasOwn(context, "free_text");
  if (hasCamel && hasSnake) {
    throw new CapturedMediaContractError(
      path,
      "free-text aliases cannot both be present",
    );
  }
  if (hasSnake && !compatibility) {
    throw new CapturedMediaContractError(
      path,
      "free_text is legacy-only",
    );
  }
  const rawText = hasCamel ? context.freeText : context.free_text;
  if (typeof rawText !== "string") {
    throw new CapturedMediaContractError(
      `${path}.freeText`,
      "expected a string",
    );
  }
  const freeText = rawText.trim();
  if (
    freeText.length === 0 ||
    freeText.length > CAPTURED_MEDIA_MAX_DESCRIPTION_LENGTH
  ) {
    throw new CapturedMediaContractError(
      `${path}.freeText`,
      `must contain 1 through ${CAPTURED_MEDIA_MAX_DESCRIPTION_LENGTH} characters`,
    );
  }
  return { freeText };
}

function parseEnvelopePayload(
  value: unknown,
  path: string,
): unknown {
  const envelope = recordAt(value, path);
  assertExactKeys(envelope, ["_0"], path);
  if (!Object.hasOwn(envelope, "_0")) {
    throw new CapturedMediaContractError(path, "missing _0 payload");
  }
  return envelope._0;
}

function parseItem(
  value: unknown,
  index: number,
  compatibility: boolean,
): CompatibleSerializedMediaItemDTO {
  const path = `captured_media[${index}]`;
  const item = recordAt(value, path);
  const keys = Object.keys(item);
  if (keys.length !== 1) {
    throw new CapturedMediaContractError(
      path,
      "expected exactly one media variant",
    );
  }
  const key = keys[0];
  const payload = parseEnvelopePayload(item[key], `${path}.${key}`);
  switch (key) {
    case "image":
      return {
        image: {
          _0: parseMediaReference(
            payload,
            `${path}.image._0`,
            compatibility,
          ),
        },
      };
    case "audio":
      return {
        audio: {
          _0: parseMediaReference(
            payload,
            `${path}.audio._0`,
            compatibility,
          ),
        },
      };
    case "video": {
      const video = recordAt(payload, `${path}.video._0`);
      assertExactKeys(
        video,
        compatibility
          ? ["video", "thumbnail", "audio"]
          : ["video", "thumbnail"],
        `${path}.video._0`,
      );
      if (!Object.hasOwn(video, "video")) {
        throw new CapturedMediaContractError(
          `${path}.video._0`,
          "missing video reference",
        );
      }
      return {
        video: {
          _0: {
            video: parseMediaReference(
              video.video,
              `${path}.video._0.video`,
              compatibility,
            ),
            ...(video.thumbnail == null ? {} : {
              thumbnail: parseMediaReference(
                video.thumbnail,
                `${path}.video._0.thumbnail`,
                compatibility,
              ),
            }),
            ...(compatibility && video.audio != null
              ? {
                audio: parseMediaReference(
                  video.audio,
                  `${path}.video._0.audio`,
                  true,
                ),
              }
              : {}),
          },
        },
      };
    }
    case "description":
      return {
        description: {
          _0: parseDescription(
            payload,
            `${path}.description._0`,
            compatibility,
          ),
        },
      };
    default:
      throw new CapturedMediaContractError(path, "unknown media variant");
  }
}

function parseManifest(
  value: unknown,
  compatibility: boolean,
): CompatibleSerializedMediaItemDTO[] {
  if (!Array.isArray(value)) {
    throw new CapturedMediaContractError("captured_media", "expected an array");
  }
  if (
    value.length > CAPTURED_MEDIA_MAX_ITEMS ||
    (!compatibility && value.length < 1)
  ) {
    throw new CapturedMediaContractError(
      "captured_media",
      `must contain 1 through ${CAPTURED_MEDIA_MAX_ITEMS} items`,
    );
  }
  return value.map((item, index) => parseItem(item, index, compatibility));
}

/** Strict canonical parser used at every new server-write boundary. */
export function parseCapturedMediaWireV1(
  value: unknown,
): SerializedMediaItemDTO[] {
  return parseManifest(value, false) as SerializedMediaItemDTO[];
}

/**
 * Read-only parser for rows and replay fixtures written before V1 became
 * explicit. It canonicalizes aliases and discards the deprecated timestamp.
 */
export function parseCompatibleCapturedMediaWireV1(
  value: unknown,
): CompatibleSerializedMediaItemDTO[] {
  return parseManifest(value, true);
}

/**
 * Converts a legacy readable manifest into the strict V1 write projection.
 * Device-local references cannot be meaningful in a server row, so they are
 * dropped; aliases and retired metadata are normalized by the compatibility
 * parser first. The result is revalidated by the strict parser before use.
 */
export function canonicalizeCompatibleCapturedMediaWireV1(
  value: unknown,
): SerializedMediaItemDTO[] {
  const compatible = parseCompatibleCapturedMediaWireV1(value);
  const canonical: SerializedMediaItemDTO[] = [];

  for (const item of compatible) {
    if ("image" in item) {
      if (item.image._0.storage === "remoteURL") {
        canonical.push({ image: { _0: item.image._0 } });
      }
      continue;
    }
    if ("audio" in item) {
      if (item.audio._0.storage === "remoteURL") {
        canonical.push({ audio: { _0: item.audio._0 } });
      }
      continue;
    }
    if ("video" in item) {
      const payload = item.video._0;
      if (payload.video.storage === "remoteURL") {
        canonical.push({
          video: {
            _0: {
              video: payload.video,
              ...(payload.thumbnail?.storage === "remoteURL"
                ? { thumbnail: payload.thumbnail }
                : {}),
            },
          },
        });
      }
      continue;
    }
    canonical.push(item);
  }

  return canonical.length > 0 ? parseCapturedMediaWireV1(canonical) : [];
}
