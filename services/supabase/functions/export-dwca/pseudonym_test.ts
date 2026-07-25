import {
  assertEquals,
  assertMatch,
  assertNotEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  createUserPseudonymizer,
  loadUserPseudonymizer,
  pseudonymSecretName,
} from "./pseudonym.ts";
import { ExportWorkerError } from "./types.ts";

const firstKey = btoa("0123456789abcdef0123456789abcdef");
const secondKey = btoa("fedcba9876543210fedcba9876543210");

Deno.test("dedicated HMAC pseudonyms are deterministic and versioned", async () => {
  const pseudonymizer = await createUserPseudonymizer(7, firstKey);
  const first = await pseudonymizer.pseudonymize(
    "00000000-0000-4000-8000-000000000101",
  );
  const replay = await pseudonymizer.pseudonymize(
    "00000000-0000-4000-8000-000000000101",
  );

  assertEquals(first, replay);
  assertMatch(first, /^naturebook_user_v7_[0-9a-f]{32}$/);
  assertEquals(first.includes("00000000"), false);
});

Deno.test("key and version rotation change the pseudonym domain", async () => {
  const v1 = await createUserPseudonymizer(1, firstKey);
  const v1RotatedKey = await createUserPseudonymizer(1, secondKey);
  const v2 = await createUserPseudonymizer(2, firstKey);
  const userId = "00000000-0000-4000-8000-000000000102";

  assertNotEquals(
    await v1.pseudonymize(userId),
    await v1RotatedKey.pseudonymize(userId),
  );
  assertNotEquals(
    await v1.pseudonymize(userId),
    await v2.pseudonymize(userId),
  );
});

Deno.test("pseudonym key loading fails closed without a fallback", async () => {
  assertEquals(pseudonymSecretName(3), "DWCA_PSEUDONYM_HMAC_KEY_V3");
  const error = await assertRejects(
    () => loadUserPseudonymizer(3, () => undefined),
    ExportWorkerError,
  );
  assertEquals(error.code, "pseudonym_key_unavailable");
});

Deno.test("pseudonym key loading rejects short decoded keys", async () => {
  const error = await assertRejects(
    () => createUserPseudonymizer(1, btoa("short")),
    ExportWorkerError,
  );
  assertEquals(error.code, "pseudonym_key_unavailable");
});
