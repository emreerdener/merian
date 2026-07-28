import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  defaultDownloadDwcaDependencies,
  DownloadDwcaDependencies,
  handleDownloadDwca,
} from "./handler.ts";

const token = "a".repeat(43);
const objectKey =
  "exports/00000000-0000-4000-8000-000000000201/00000000-0000-4000-8000-000000000202/00000000-0000-4000-8000-000000000203.zip";

function dependencies(
  status:
    | "authorized"
    | "gone"
    | "not_found"
    | "not_ready"
    | "rate_limited" = "authorized",
): DownloadDwcaDependencies {
  return {
    authorize(tokenHash, ipHash) {
      assertEquals(tokenHash, "b".repeat(64));
      assertEquals(ipHash, "c".repeat(64));
      if (status === "authorized") {
        return Promise.resolve({ status, objectKey });
      }
      if (status === "rate_limited" || status === "not_ready") {
        return Promise.resolve({
          status,
          retryAfterSeconds: status === "rate_limited" ? 300 : 5,
        });
      }
      return Promise.resolve({ status });
    },
    hashToken(value) {
      assertEquals(value, token);
      return Promise.resolve("b".repeat(64));
    },
    hashAddress(value) {
      assertEquals(value, "203.0.113.7");
      return Promise.resolve("c".repeat(64));
    },
    createRedirect(value) {
      assertEquals(value, objectKey);
      return Promise.resolve("https://r2.example.invalid/short-signed-url");
    },
  };
}

function request(method = "GET", suffix = `?token=${token}`): Request {
  return new Request(`https://project.supabase.co/download-dwca${suffix}`, {
    method,
    headers: { "x-real-ip": "203.0.113.7" },
  });
}

Deno.test("authorized capabilities produce only a short no-store redirect", async () => {
  const response = await handleDownloadDwca(request(), dependencies());
  assertEquals(response.status, 303);
  assertEquals(
    response.headers.get("location"),
    "https://r2.example.invalid/short-signed-url",
  );
  assertEquals(response.headers.get("cache-control"), "private, no-store");
  assertEquals(response.headers.get("referrer-policy"), "no-referrer");
  assertEquals(await response.text(), "");
});

Deno.test("invalid and unknown capabilities use indistinguishable public errors", async () => {
  for (
    const [candidate, deps] of [
      ["?token=invalid", dependencies()],
      [`?token=${token}&extra=1`, dependencies()],
      [`?token=${token}&token=${token}`, dependencies()],
      [`?token=${token}`, dependencies("not_found")],
    ] as const
  ) {
    const response = await handleDownloadDwca(
      request("GET", candidate),
      deps,
    );
    assertEquals(response.status, 404);
    assertStringIncludes(await response.text(), "download_not_found");
  }
});

Deno.test("revoked and rate-limited capabilities are stable and no-store", async () => {
  const gone = await handleDownloadDwca(
    request(),
    dependencies("gone"),
  );
  assertEquals(gone.status, 410);
  assertEquals(gone.headers.get("cache-control"), "private, no-store");

  const limited = await handleDownloadDwca(
    request(),
    dependencies("rate_limited"),
  );
  assertEquals(limited.status, 429);
  assertEquals(limited.headers.get("retry-after"), "300");

  const notReady = await handleDownloadDwca(
    request(),
    dependencies("not_ready"),
  );
  assertEquals(notReady.status, 425);
  assertEquals(notReady.headers.get("retry-after"), "5");
});

Deno.test("method and dependency failures do not expose internals", async () => {
  const method = await handleDownloadDwca(
    request("POST"),
    dependencies(),
  );
  assertEquals(method.status, 405);
  assertEquals(method.headers.get("allow"), "GET");

  const failing = dependencies();
  failing.authorize = () => Promise.reject(new Error("database details"));
  const response = await handleDownloadDwca(request(), failing);
  assertEquals(response.status, 503);
  const body = await response.text();
  assertStringIncludes(body, "download_unavailable");
  assertEquals(body.includes("database details"), false);
});

Deno.test("default authorization meters capability traffic before reading release state", async () => {
  const calls: string[] = [];
  const supabaseAdmin = {
    rpc(name: string) {
      calls.push(name);
      if (name === "authorize_dwca_archive_download") {
        return Promise.resolve({
          data: { status: "not_found" },
          error: null,
        });
      }
      throw new Error(`unexpected RPC: ${name}`);
    },
  } as unknown as SupabaseClient;
  const deps = defaultDownloadDwcaDependencies(
    supabaseAdmin,
    "d".repeat(32),
  );

  assertEquals(
    await deps.authorize("b".repeat(64), "c".repeat(64)),
    { status: "not_found" },
  );
  assertEquals(calls, ["authorize_dwca_archive_download"]);
});

Deno.test("default authorization fails closed after a valid database grant", async () => {
  for (const enabled of [false, true]) {
    const calls: string[] = [];
    const supabaseAdmin = {
      rpc(name: string) {
        calls.push(name);
        if (name === "authorize_dwca_archive_download") {
          return Promise.resolve({
            data: {
              status: "authorized",
              object_key: objectKey,
            },
            error: null,
          });
        }
        if (name === "get_dwca_export_release_state") {
          return Promise.resolve({
            data: { enabled },
            error: null,
          });
        }
        throw new Error(`unexpected RPC: ${name}`);
      },
    } as unknown as SupabaseClient;
    const deps = defaultDownloadDwcaDependencies(
      supabaseAdmin,
      "d".repeat(32),
    );

    assertEquals(
      await deps.authorize("b".repeat(64), "c".repeat(64)),
      enabled ? { status: "authorized", objectKey } : { status: "gone" },
    );
    assertEquals(calls, [
      "authorize_dwca_archive_download",
      "get_dwca_export_release_state",
    ]);
  }
});
