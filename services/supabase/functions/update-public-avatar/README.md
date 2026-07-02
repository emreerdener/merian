# Update Public Avatar

Promotes a user-owned staged R2 image into Merian's durable public avatar
prefix and updates the public identity projection used by Profile, Explore
cards, comments, and author sheets.

## Architecture

- **`index.ts`**: Authenticated HTTP orchestrator wrapped in
  `withEdgeHandler`. It parses JSON, validates the staged key and MIME type,
  loads the current `custom_avatar_url`, promotes the image, updates
  `public.users`, and returns the resolved avatar URL.
- **`avatar.ts`**: Pure validation and R2 promotion helpers. It enforces
  ownership under `staging/{userId}/...`, supports `image/webp` and
  `image/jpeg`, copies the object to `avatars/{userId}/{uuid}.webp|jpg`, and
  deletes only a previous same-user custom avatar.
- **`avatar_test.ts`**: Covers key validation, wrong-user rejection, extension
  selection, avatar promotion, and same-user deletion boundaries.

## Contract

The client first calls `generate-upload-urls`, uploads one prepared square
avatar image to the returned signed URL, then calls this function with the
returned `objectKey`.

Request:

```json
{
  "r2_object_key": "staging/a1b2c3d4-e5f6-7890-abcd-ef1234567890/avatar_11111111-1111-4111-8111-111111111111.webp",
  "mime_type": "image/webp"
}
```

Response:

```json
{
  "avatar_url": "https://media.merian.app/avatars/a1b2c3d4-e5f6-7890-abcd-ef1234567890/22222222-2222-4222-8222-222222222222.webp"
}
```

## Storage Rules

Custom avatars are public and durable. They live under
`avatars/{userId}/...`, not `public_uploads/free|pro/`, so scan purge flows and
R2 lifecycle expiration rules must not delete them.

Only this avatar-specific path may remove avatar objects, and only after a
replacement has been promoted:

```text
https://media.merian.app/avatars/{sameUserId}/...
```

OAuth/provider avatars remain fallback metadata. The database identity refresh
helpers resolve `public_avatar_url` as custom avatar first, provider avatar
second.

## Verification

```sh
deno fmt --check services/supabase/functions/update-public-avatar
deno check --config services/supabase/functions/deno.json services/supabase/functions/update-public-avatar/index.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/update-public-avatar/avatar_test.ts
```
