import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import {
  RESERVED_PUBLIC_USERNAME_BRANDS,
  RESERVED_PUBLIC_USERNAME_EXACT,
  RESERVED_PUBLIC_USERNAME_ROLES,
} from "../update-public-username/validation.ts";

const migrationUrl = new URL(
  "../../migrations/20260808144244_expand_reserved_public_username_policy.sql",
  import.meta.url,
);
const swiftProfileUrl = new URL(
  "../../../../apps/ios/Merian/Features/Profile/UserProfile/Components/UserProfile.swift",
  import.meta.url,
);

function quotedValues(source: string): string[] {
  return Array.from(
    source.matchAll(/["']([a-z0-9_]+)["']/g),
    (match) => match[1],
  );
}

function sqlPolicyValues(
  migration: string,
  variableName: string,
): string[] {
  const match = migration.match(
    new RegExp(
      `\\b${variableName}\\s+CONSTANT\\s+TEXT\\[\\]\\s*:=\\s*ARRAY\\[([\\s\\S]*?)\\];`,
    ),
  );
  assert(match, `Missing SQL policy array ${variableName}.`);
  return quotedValues(match[1]);
}

function swiftPolicyValues(
  swift: string,
  propertyName: string,
): string[] {
  const match = swift.match(
    new RegExp(
      `private static let ${propertyName}: Set<String> = \\[([\\s\\S]*?)\\n\\s*\\]`,
    ),
  );
  assert(match, `Missing Swift policy set ${propertyName}.`);
  return quotedValues(match[1]);
}

function assertSortedUnique(values: string[], label: string): void {
  assertEquals(
    values,
    [...new Set(values)].sort(),
    `${label} must remain sorted and duplicate-free.`,
  );
}

Deno.test("public username reserved-name policy stays aligned across PostgreSQL, Edge, and iOS", async () => {
  const [migration, swift] = await Promise.all([
    Deno.readTextFile(migrationUrl),
    Deno.readTextFile(swiftProfileUrl),
  ]);

  const policyGroups = [
    {
      label: "exact",
      edge: [...RESERVED_PUBLIC_USERNAME_EXACT],
      sql: sqlPolicyValues(migration, "reserved_exact"),
      swift: swiftPolicyValues(swift, "reservedExactUsernames"),
    },
    {
      label: "brands",
      edge: [...RESERVED_PUBLIC_USERNAME_BRANDS],
      sql: sqlPolicyValues(migration, "reserved_brands"),
      swift: swiftPolicyValues(swift, "reservedBrandUsernames"),
    },
    {
      label: "roles",
      edge: [...RESERVED_PUBLIC_USERNAME_ROLES],
      sql: sqlPolicyValues(migration, "reserved_roles"),
      swift: swiftPolicyValues(swift, "reservedRoleUsernames"),
    },
  ];

  for (const group of policyGroups) {
    assertSortedUnique(group.edge, `Edge ${group.label} policy`);
    assertSortedUnique(group.sql, `PostgreSQL ${group.label} policy`);
    assertSortedUnique(group.swift, `iOS ${group.label} policy`);
    assertEquals(group.sql, group.edge, `${group.label}: PostgreSQL vs Edge`);
    assertEquals(group.swift, group.edge, `${group.label}: iOS vs Edge`);
  }

  assertStringIncludes(
    migration,
    "canonical_username = reserved_brand || '_' || reserved_role",
  );
  assertStringIncludes(
    migration,
    "canonical_username = reserved_role || '_' || reserved_brand",
  );
  assertStringIncludes(
    swift,
    String
      .raw`username == "\(brand)_\(role)" || username == "\(role)_\(brand)"`,
  );
});

Deno.test("reserved username migration repairs profiles and preserves historical mention tokens", async () => {
  const migration = (await Deno.readTextFile(migrationUrl))
    .replaceAll(/\s+/g, " ")
    .trim();

  for (
    const fragment of [
      "WHERE public.is_reserved_public_username(app_user.public_username)",
      "ORDER BY app_user.id FOR UPDATE OF app_user",
      "public.build_unique_public_username(",
      "public.build_default_public_username(reserved_profile.id)",
      "WHEN app_user.public_identity_source = 'alias' THEN replacement_username",
      "ADD CONSTRAINT users_public_username_expanded_policy_check CHECK (public.is_valid_public_username(public_username)) NOT VALID",
      "VALIDATE CONSTRAINT users_public_username_expanded_policy_check",
      "ADD CONSTRAINT explore_comment_mentions_username_expanded_policy_check CHECK ( mention_username = pg_catalog.LOWER(mention_username)",
      "pg_catalog.CHAR_LENGTH(mention_username) BETWEEN 3 AND 24",
      "VALIDATE CONSTRAINT explore_comment_mentions_username_expanded_policy_check",
      "NOTIFY pgrst, 'reload schema'",
    ]
  ) {
    assertStringIncludes(migration, fragment);
  }

  assert(
    !migration.includes("UPDATE public.explore_comment_mentions"),
    "Historical mention usernames must remain aligned with immutable comment text.",
  );
  assert(
    !migration.includes(
      "CHECK (public.is_valid_public_username(mention_username))",
    ),
    "Mention snapshots must enforce username shape without retroactive reservation rules.",
  );
});
