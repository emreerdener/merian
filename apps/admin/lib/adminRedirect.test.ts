import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  adminRedirectURL,
  safeAdminRedirectPath,
  validatedAdminOrigin,
} from "./adminRedirect.ts";

const configuredOrigin = "https://admin.naturebook.earth";

test("admin redirect paths preserve internal query strings and fragments", () => {
  assert.equal(
    safeAdminRedirectPath("/mfa?return=%2Freviews#verify"),
    "/mfa?return=%2Freviews#verify",
  );
  assert.equal(
    adminRedirectURL("/mfa?return=%2Freviews#verify", configuredOrigin).href,
    "https://admin.naturebook.earth/mfa?return=%2Freviews#verify",
  );
});

test("admin redirect paths reject absolute, protocol-relative, and backslash forms", () => {
  for (
    const value of [
      "https://evil.example/path",
      "//evil.example/path",
      "/\\evil.example/path",
      "\\evil.example/path",
      "/%5cevil.example/path",
      "/%5Cevil.example/path",
      "/%2fevil.example/path",
      "/%252fevil.example/path",
      "/%25252fevil.example/path",
      "/safe\\evil.example/path",
      "/safe%5cevil.example/path",
      "%2f%2fevil.example/path",
      "javascript:alert(1)",
    ]
  ) {
    assert.equal(safeAdminRedirectPath(value), "/mfa", value);
    assert.equal(
      adminRedirectURL(value, configuredOrigin).origin,
      configuredOrigin,
      value,
    );
  }
});

test("admin origins are validated as origins, not arbitrary URLs", () => {
  assert.equal(
    validatedAdminOrigin(`${configuredOrigin}/`).href,
    `${configuredOrigin}/`,
  );
  assert.equal(
    validatedAdminOrigin("http://localhost:3000").origin,
    "http://localhost:3000",
  );
  for (
    const value of [
      undefined,
      "",
      "ftp://admin.naturebook.earth",
      "https://user:password@admin.naturebook.earth",
      "https://admin.naturebook.earth/path",
      "https://admin.naturebook.earth/?query=1",
      "https://admin.naturebook.earth/#fragment",
    ]
  ) {
    assert.throws(() => validatedAdminOrigin(value));
  }
});

test("the OAuth flow never derives callback destinations from request Host headers", async () => {
  const [callbackRoute, loginCard] = await Promise.all([
    readFile(new URL("../app/auth/callback/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/login/LoginCard.tsx", import.meta.url), "utf8"),
  ]);

  assert.match(callbackRoute, /adminRedirectURL/);
  assert.doesNotMatch(callbackRoute, /request\.url/);
  assert.match(loginCard, /adminRedirectURL\("\/auth\/callback\?next=\/mfa"\)/);
  assert.doesNotMatch(loginCard, /window\.location\.origin/);
  assert.equal(
    adminRedirectURL("/mfa", configuredOrigin).href,
    "https://admin.naturebook.earth/mfa",
  );
});
