import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { serviceRoleRequestHeaders } from "./serviceRoleAuth.ts";
import { createServiceRoleDataClient } from "./serviceRoleClient.ts";

async function databaseRequestHeaders(
  serverApiKey: string,
): Promise<Headers> {
  let requestHeaders = new Headers();
  const client = createServiceRoleDataClient(
    "https://project.supabase.co",
    serverApiKey,
    (_input, init) => {
      requestHeaders = new Headers(
        init && "headers" in init ? init.headers as HeadersInit : undefined,
      );
      return Promise.resolve(
        new Response("[]", {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    },
  );

  const { error } = await client.from("taxonomy_import_runs").select("id")
    .limit(1);
  assertEquals(error, null);
  return requestHeaders;
}

async function storageRequestHeaders(
  serverApiKey: string,
): Promise<Headers> {
  let requestHeaders = new Headers();
  const client = createServiceRoleDataClient(
    "https://project.supabase.co",
    serverApiKey,
    (_input, init) => {
      requestHeaders = new Headers(
        init && "headers" in init ? init.headers as HeadersInit : undefined,
      );
      return Promise.resolve(
        new Response("[]", {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    },
  );

  const { error } = await client.storage.from("private").list();
  assertEquals(error, null);
  return requestHeaders;
}

async function functionRequestHeaders(
  serverApiKey: string,
): Promise<Headers> {
  let requestHeaders = new Headers();
  const client = createServiceRoleDataClient(
    "https://project.supabase.co",
    serverApiKey,
    (_input, init) => {
      requestHeaders = new Headers(
        init && "headers" in init ? init.headers as HeadersInit : undefined,
      );
      return Promise.resolve(
        new Response("{}", {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    },
  );

  const { error } = await client.functions.invoke("internal-worker", {
    body: {},
  });
  assertEquals(error, null);
  return requestHeaders;
}

Deno.test("serviceRoleRequestHeaders keeps non-JWT secret keys out of Bearer transport", () => {
  assertEquals(serviceRoleRequestHeaders("sb_secret_worker"), {
    apikey: "sb_secret_worker",
  });
});

Deno.test("serviceRoleRequestHeaders carries legacy service-role JWTs in both headers", () => {
  assertEquals(serviceRoleRequestHeaders("legacy-service-role-jwt"), {
    apikey: "legacy-service-role-jwt",
    Authorization: "Bearer legacy-service-role-jwt",
  });
});

Deno.test("createServiceRoleDataClient keeps non-JWT secret keys out of database Bearer transport", async () => {
  const headers = await databaseRequestHeaders("sb_secret_worker");

  assertEquals(headers.get("apikey"), "sb_secret_worker");
  assertEquals(headers.get("Authorization"), null);
});

Deno.test("createServiceRoleDataClient preserves legacy service-role JWT database transport", async () => {
  const headers = await databaseRequestHeaders("legacy-service-role-jwt");

  assertEquals(headers.get("apikey"), "legacy-service-role-jwt");
  assertEquals(
    headers.get("Authorization"),
    "Bearer legacy-service-role-jwt",
  );
});

Deno.test("createServiceRoleDataClient keeps non-JWT secret keys out of Storage and Functions Bearer transport", async () => {
  for (
    const headers of [
      await storageRequestHeaders("sb_secret_worker"),
      await functionRequestHeaders("sb_secret_worker"),
    ]
  ) {
    assertEquals(headers.get("apikey"), "sb_secret_worker");
    assertEquals(headers.get("Authorization"), null);
  }
});

Deno.test("createServiceRoleDataClient preserves legacy JWT transport for Storage and Functions", async () => {
  for (
    const headers of [
      await storageRequestHeaders("legacy-service-role-jwt"),
      await functionRequestHeaders("legacy-service-role-jwt"),
    ]
  ) {
    assertEquals(headers.get("apikey"), "legacy-service-role-jwt");
    assertEquals(
      headers.get("Authorization"),
      "Bearer legacy-service-role-jwt",
    );
  }
});
