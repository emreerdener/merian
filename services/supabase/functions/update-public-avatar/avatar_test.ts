import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import type { R2Config } from "../_shared/aws.ts";
import {
  avatarExtensionForMimeType,
  buildAvatarObjectKey,
  isReplaceableAvatarUrl,
  promotePublicAvatar,
  validatePublicAvatarRequest,
} from "./avatar.ts";

Deno.test("update-public-avatar validates staged ownership", () => {
  assertEquals(
    validatePublicAvatarRequest({
      r2_object_key: "staging/user-1/avatar.webp",
      mime_type: "image/webp",
    }, "user-1").error,
    undefined,
  );

  assertEquals(
    validatePublicAvatarRequest({
      r2_object_key: "staging/user-2/avatar.webp",
      mime_type: "image/webp",
    }, "user-1").error?.status,
    403,
  );

  assertEquals(
    validatePublicAvatarRequest({
      r2_object_key: "staging/user-1/../avatar.webp",
      mime_type: "image/webp",
    }, "user-1").error?.status,
    400,
  );
});

Deno.test("update-public-avatar accepts only canonical avatar image types", () => {
  assertEquals(avatarExtensionForMimeType("image/webp"), "webp");
  assertEquals(avatarExtensionForMimeType("image/jpeg"), "jpg");

  assertEquals(
    validatePublicAvatarRequest({
      r2_object_key: "staging/user-1/avatar.png",
      mime_type: "image/png",
    }, "user-1").error?.status,
    400,
  );
});

Deno.test("update-public-avatar promotes to durable avatar prefix", async () => {
  const copied: Array<{ source: string; target: string }> = [];
  const deleted: string[] = [];
  const config = {} as R2Config;

  const result = await promotePublicAvatar(
    {
      r2ObjectKey: "staging/user-1/avatar.webp",
      mimeType: "image/webp",
    },
    "user-1",
    "https://media.merian.app/avatars/user-1/old.webp",
    {
      r2Config: config,
      copyObject: (sourceKey, targetKey) => {
        copied.push({ source: sourceKey, target: targetKey });
        return Promise.resolve(
          new Response(null, { status: 200, statusText: "OK" }),
        );
      },
      deleteAvatarObject: (avatarUrl) => {
        deleted.push(avatarUrl);
        return Promise.resolve(new Response(null, { status: 204 }));
      },
    },
  );

  assertEquals(copied[0].source, "staging/user-1/avatar.webp");
  assertEquals(copied[0].target.startsWith("avatars/user-1/"), true);
  assertEquals(
    result.avatarUrl.startsWith("https://media.merian.app/avatars/user-1/"),
    true,
  );
  assertEquals(deleted, ["https://media.merian.app/avatars/user-1/old.webp"]);
});

Deno.test("update-public-avatar only replaces same-user avatar URLs", () => {
  assertEquals(
    isReplaceableAvatarUrl(
      "https://media.merian.app/avatars/user-1/a.webp",
      "user-1",
    ),
    true,
  );
  assertEquals(
    isReplaceableAvatarUrl(
      "https://media.merian.app/avatars/user-2/a.webp",
      "user-1",
    ),
    false,
  );
  assertEquals(
    isReplaceableAvatarUrl("https://accounts.google.com/avatar.jpg", "user-1"),
    false,
  );
});

Deno.test("update-public-avatar deterministic key helper includes matching extension", () => {
  assertEquals(
    buildAvatarObjectKey("user-1", "image/jpeg", "avatar-id"),
    "avatars/user-1/avatar-id.jpg",
  );
});
