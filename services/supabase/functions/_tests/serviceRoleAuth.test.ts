import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  authorizeServiceRoleRequest,
  serviceRoleTokenFromRequest,
} from "../_shared/serviceRoleAuth.ts";

Deno.test("serviceRoleTokenFromRequest extracts bearer token", () => {
  const req = new Request("https://example.test", {
    headers: { Authorization: "Bearer service-token" },
  });
  assertEquals(serviceRoleTokenFromRequest(req), "service-token");
});

Deno.test("serviceRoleTokenFromRequest falls back to apikey header", () => {
  const req = new Request("https://example.test", {
    headers: { apikey: "service-key" },
  });
  assertEquals(serviceRoleTokenFromRequest(req), "service-key");
});

Deno.test("authorizeServiceRoleRequest accepts exact env service key", async () => {
  const req = new Request("https://example.test", {
    headers: { Authorization: "Bearer env-key" },
  });

  const result = await authorizeServiceRoleRequest(req, {
    supabaseUrl: "",
    envServiceRoleKey: "env-key",
    probe: () => Promise.resolve(false),
  });

  assertEquals(result, { ok: true, token: "env-key" });
});

Deno.test("authorizeServiceRoleRequest accepts proven service role fallback", async () => {
  const req = new Request("https://example.test", {
    headers: { Authorization: "Bearer project-service-key" },
  });

  const result = await authorizeServiceRoleRequest(req, {
    supabaseUrl: "https://project.supabase.co",
    envServiceRoleKey: "different-env-key",
    probe: (token) => Promise.resolve(token === "project-service-key"),
  });

  assertEquals(result, { ok: true, token: "project-service-key" });
});

Deno.test("authorizeServiceRoleRequest rejects missing or unproven tokens", async () => {
  const missing = await authorizeServiceRoleRequest(
    new Request("https://example.test"),
    {
      supabaseUrl: "https://project.supabase.co",
      envServiceRoleKey: "env-key",
      probe: () => Promise.resolve(true),
    },
  );
  assertEquals(missing, { ok: false, reason: "missing_token" });

  const unproven = await authorizeServiceRoleRequest(
    new Request("https://example.test", {
      headers: { Authorization: "Bearer bad-key" },
    }),
    {
      supabaseUrl: "https://project.supabase.co",
      envServiceRoleKey: "env-key",
      probe: () => Promise.resolve(false),
    },
  );
  assertEquals(unproven, { ok: false, reason: "probe_failed" });
});
