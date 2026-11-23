import { assert, assertEquals } from "@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261119232729_fence_initial_evidence_legacy_replay.sql",
    import.meta.url,
  ),
);

Deno.test("ordinary initial replay fence covers both bounded batch branches without activation", () => {
  assert(
    migration.includes(
      "public.claim_replayable_scan_ingestion_jobs(integer,integer)",
    ),
  );
  assert(migration.includes("/length(anchor) <> 2"));
  assert(
    migration.includes("NOT (intents.request_payload ? 'initialEvidence')"),
  );
  assert(
    migration.includes(
      "FROM internal.ordinary_initial_evidence initial_evidence",
    ),
  );
  assert(
    migration.includes(
      "initial_evidence.scan_id = internal.source_child_uuid(jobs.scan_id)",
    ),
  );
  // The durable identity guard intentionally outlives mutable lifecycle states.
  assert(
    !/initial_evidence\.(retired_at|sealed_at|accepted_result)/.test(migration),
  );
  assertEquals([...migration.matchAll(/EXECUTE replace/g)].length, 1);
  assert(
    !/CREATE(?: OR REPLACE)? FUNCTION|GRANT|UPDATE internal\./i.test(migration),
  );
  assert(migration.includes("RESET statement_timeout"));
  assert(migration.includes("RESET lock_timeout"));
});

Deno.test("initial evidence cannot upgrade legacy intent or bypass locked terminal settlement", async () => {
  const repair = await Deno.readTextFile(
    new URL(
      "../../migrations/20261119233303_fence_initial_evidence_terminal_races.sql",
      import.meta.url,
    ),
  );
  assert(
    repair.includes(
      "TG_OP='UPDATE' AND NOT (OLD.request_payload ? 'initialEvidence')",
    ),
  );
  assert(repair.includes("AND NEW.request_payload ? 'initialEvidence'"));
  const lock = repair.indexOf(
    "PERFORM jobs.id FROM public.scan_ingestion_jobs jobs",
  );
  const recheck = repair.indexOf(
    "IF EXISTS(SELECT 1 FROM public.scan_ingestion_jobs jobs",
  );
  assert(lock > 0 && recheck > lock);
  assert(repair.slice(lock, recheck).includes("FOR UPDATE"));
  assert(
    repair.includes("'replay_exhausted','media_reconciliation_abandoned'"),
  );
  assert(repair.includes("'initial_evidence_recovery_required'"));
  assert(!/GRANT|UPDATE internal\./i.test(repair));
});
