import assert from "node:assert/strict";
import test from "node:test";
import { canonicalRedirectURL } from "./canonicalHost.ts";

test("redirects public aliases to the canonical Naturebook origin", () => {
  for (
    const host of [
      "naturebook.app",
      "www.naturebook.app",
      "www.naturebook.earth",
      "merian.earth",
      "www.merian.earth",
    ]
  ) {
    for (
      const path of [
        "/explore/post/123",
        "/species/1cf79982-e5ee-4e3d-8d65-274527e6ae01",
        "/species/1cf79982-e5ee-4e3d-8d65-274527e6ae01/monarch-butterfly",
      ]
    ) {
      assert.equal(
        canonicalRedirectURL(host, path, "?theme=dark")?.href,
        `https://naturebook.earth${path}?theme=dark`,
      );
    }
  }
});

test("serves legacy Merian AASA endpoints directly without redirecting", () => {
  assert.equal(
    canonicalRedirectURL("merian.earth", "/apple-app-site-association"),
    null,
  );
  assert.equal(
    canonicalRedirectURL(
      "merian.earth",
      "/.well-known/apple-app-site-association",
    ),
    null,
  );
});

test("does not redirect the canonical origin or unrelated hosts", () => {
  assert.equal(canonicalRedirectURL("naturebook.earth", "/support"), null);
  assert.equal(canonicalRedirectURL("example.com", "/support"), null);
});

test("attacker-controlled path syntax cannot replace the canonical origin", () => {
  for (
    const path of [
      "//evil.example/path",
      "/\\evil.example/path",
      "\\evil.example/path",
      "/%2f%2fevil.example/path",
      "/%5cevil.example/path",
    ]
  ) {
    const destination = canonicalRedirectURL(
      "naturebook.app",
      path,
      "?continue=//evil.example",
    );
    assert.equal(destination?.origin, "https://naturebook.earth", path);
    assert.equal(destination?.search, "?continue=//evil.example", path);
  }
});
