import assert from "node:assert/strict";
import test from "node:test";
import {
  contentSecurityPolicy,
  explicitSecurityHeaders,
} from "./securityHeaders.ts";

test("production CSP authorizes nonce scripts and denies dangerous defaults", () => {
  const policy = contentSecurityPolicy({
    nonce: "test-nonce",
    development: false,
  });

  assert.match(policy, /script-src 'self' 'nonce-test-nonce' 'strict-dynamic'/);
  assert.match(policy, /object-src 'none'/);
  assert.match(policy, /frame-ancestors 'none'/);
  assert.match(policy, /upgrade-insecure-requests/);
  assert.doesNotMatch(policy, /unsafe-eval/);
});

test("development CSP permits source evaluation only for local tooling", () => {
  const policy = contentSecurityPolicy({
    nonce: "development-nonce",
    development: true,
  });

  assert.match(policy, /unsafe-eval/);
  assert.doesNotMatch(policy, /upgrade-insecure-requests/);
});

test("the explicit response-header floor is complete", () => {
  const headers = new Map(
    explicitSecurityHeaders({ nonce: "nonce", development: false }),
  );

  assert.equal(headers.get("X-Content-Type-Options"), "nosniff");
  assert.equal(headers.get("X-Frame-Options"), "DENY");
  assert.equal(headers.get("Cross-Origin-Opener-Policy"), "same-origin");
  assert.ok(headers.has("Strict-Transport-Security"));
  assert.ok(headers.has("Referrer-Policy"));
  assert.ok(headers.has("Permissions-Policy"));
});

test("development responses do not advertise an HTTPS transport policy", () => {
  const headers = new Map(
    explicitSecurityHeaders({ nonce: "nonce", development: true }),
  );

  assert.equal(headers.has("Strict-Transport-Security"), false);
});
