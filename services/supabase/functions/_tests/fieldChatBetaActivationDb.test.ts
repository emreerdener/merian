import { assertEquals } from "@std/assert";
import postgres from "npm:postgres@3.4.7";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");

Deno.test({
  name:
    "beta activation replays the actual migration without resetting usage or active evidence",
  ignore: !databaseUrl,
  async fn() {
    const url = new URL(databaseUrl!);
    if (!["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)) {
      throw new Error(
        "Beta activation migration test requires a disposable loopback database",
      );
    }
    const migration = await Deno.readTextFile(
      new URL(
        "../../migrations/20260919125625_authorize_immediate_field_chat_beta_activation.sql",
        import.meta.url,
      ),
    );
    const fixture = await Deno.readTextFile(
      new URL(
        "./fixtures/field_chat_beta_activation.sql",
        import.meta.url,
      ),
    );
    const script = fixture.replace(/^\\set ON_ERROR_STOP on\n/, "").replaceAll(
      "\\ir ../migrations/20260919125625_authorize_immediate_field_chat_beta_activation.sql",
      migration,
    );
    const sql = postgres(databaseUrl!, { max: 1, connect_timeout: 10 });
    try {
      // The fixture wraps DDL and synthetic records in BEGIN/ROLLBACK. Simple
      // query mode returns every pgTAP result in this multi-statement script.
      const results = await sql.unsafe(script).simple();
      const verdicts = results.flat().flatMap((row) => Object.values(row))
        .filter((value): value is string =>
          typeof value === "string" && /^(?:not )?ok \d+/.test(value)
        );
      assertEquals(verdicts.length, 8);
      assertEquals(verdicts.filter((value) => value.startsWith("not ok")), []);
    } finally {
      await sql.end({ timeout: 2 });
    }
  },
});
