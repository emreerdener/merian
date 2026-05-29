import {
  avatarR2KeyFromPublicUrl,
  copyR2Object,
  deleteAvatarR2Object,
  getR2Config,
  publicR2UrlForKey,
  type R2Config,
} from "../_shared/aws.ts";
import {
  STAGING_ALLOWED_CONTENT_TYPES,
  validateStagingObjectKey,
} from "../_shared/mediaBudgets.ts";

export type AvatarValidationError = {
  status: number;
  message: string;
};

export type UpdatePublicAvatarRequest = {
  r2_object_key?: unknown;
  mime_type?: unknown;
};

export type ValidPublicAvatarRequest = {
  r2ObjectKey: string;
  mimeType: AvatarMimeType;
};

export type AvatarMimeType = "image/webp" | "image/jpeg";

export type AvatarUpdateDeps = {
  r2Config?: R2Config;
  copyObject?: typeof copyR2Object;
  deleteAvatarObject?: typeof deleteAvatarR2Object;
};

export const AVATAR_ALLOWED_CONTENT_TYPES: readonly AvatarMimeType[] = [
  "image/webp",
  "image/jpeg",
];

export function validatePublicAvatarRequest(
  body: unknown,
  userId: string,
): { value?: ValidPublicAvatarRequest; error?: AvatarValidationError } {
  if (!isRecord(body)) {
    return { error: { status: 400, message: "Invalid JSON body" } };
  }

  const request = body as UpdatePublicAvatarRequest;
  if (typeof request.r2_object_key !== "string") {
    return {
      error: {
        status: 400,
        message: "Bad Request: r2_object_key must be a string.",
      },
    };
  }

  const keyError = validateStagingObjectKey(request.r2_object_key, userId);
  if (keyError === "path_traversal") {
    return {
      error: {
        status: 400,
        message: "Bad Request: invalid staged avatar key.",
      },
    };
  }
  if (keyError === "wrong_user") {
    return {
      error: {
        status: 403,
        message: "Forbidden: staged avatar does not belong to this user.",
      },
    };
  }

  if (
    typeof request.mime_type !== "string" ||
    !isAvatarMimeType(request.mime_type)
  ) {
    return {
      error: {
        status: 400,
        message: "Bad Request: mime_type is not supported for avatars.",
      },
    };
  }

  if (!STAGING_ALLOWED_CONTENT_TYPES.image.includes(request.mime_type)) {
    return {
      error: {
        status: 400,
        message: "Bad Request: mime_type is not supported for staged images.",
      },
    };
  }

  return {
    value: {
      r2ObjectKey: request.r2_object_key,
      mimeType: request.mime_type,
    },
  };
}

export function avatarExtensionForMimeType(mimeType: AvatarMimeType): string {
  return mimeType === "image/webp" ? "webp" : "jpg";
}

export function buildAvatarObjectKey(
  userId: string,
  mimeType: AvatarMimeType,
  avatarId: string = crypto.randomUUID(),
): string {
  return `avatars/${userId}/${avatarId}.${
    avatarExtensionForMimeType(mimeType)
  }`;
}

export function isReplaceableAvatarUrl(
  avatarUrl: string | null | undefined,
  userId: string,
): boolean {
  if (!avatarUrl) return false;
  return avatarR2KeyFromPublicUrl(avatarUrl, userId) !== null;
}

export async function promotePublicAvatar(
  request: ValidPublicAvatarRequest,
  userId: string,
  previousCustomAvatarUrl: string | null | undefined,
  deps: AvatarUpdateDeps = {},
): Promise<{ avatarUrl: string; avatarKey: string }> {
  const avatarKey = buildAvatarObjectKey(userId, request.mimeType);
  const r2Config = deps.r2Config ?? getR2Config();
  const copyObject = deps.copyObject ?? copyR2Object;
  const copyResponse = await copyObject(
    request.r2ObjectKey,
    avatarKey,
    r2Config,
  );

  if (!copyResponse.ok) {
    throw new Error(
      `Failed to promote avatar object: ${copyResponse.status} ${copyResponse.statusText}`,
    );
  }

  if (isReplaceableAvatarUrl(previousCustomAvatarUrl, userId)) {
    const deleteAvatarObject = deps.deleteAvatarObject ?? deleteAvatarR2Object;
    try {
      await deleteAvatarObject(previousCustomAvatarUrl ?? "", userId, r2Config);
    } catch (error) {
      console.warn(
        `Failed to delete previous avatar for ${userId}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  return {
    avatarUrl: publicR2UrlForKey(avatarKey),
    avatarKey,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isAvatarMimeType(value: string): value is AvatarMimeType {
  return AVATAR_ALLOWED_CONTENT_TYPES.includes(value as AvatarMimeType);
}
