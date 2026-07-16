import assert from "node:assert/strict";
import test from "node:test";
import { canonicalRedirectURL } from "./canonicalHost.ts";

test("redirects public aliases to the canonical Naturebook origin", () => {
  for (const host of [
    "naturebook.app",
    "www.naturebook.app",
    "www.naturebook.earth",
    "merian.earth",
    "www.merian.earth",
  ]) {
    assert.equal(
      canonicalRedirectURL(host, "/explore/post/123", "?theme=dark")?.href,
      "https://naturebook.earth/explore/post/123?theme=dark",
    );
  }
});

test("serves legacy Merian AASA endpoints directly without redirecting", () => {
  assert.equal(
    canonicalRedirectURL("merian.earth", "/apple-app-site-association"),
    null,
  );
  assert.equal(
    canonicalRedirectURL("merian.earth", "/.well-known/apple-app-site-association"),
    null,
  );
});

test("does not redirect the canonical origin or unrelated hosts", () => {
  assert.equal(canonicalRedirectURL("naturebook.earth", "/support"), null);
  assert.equal(canonicalRedirectURL("example.com", "/support"), null);
});
