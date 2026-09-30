\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(9);
SELECT extensions.ok(NOT has_function_privilege('anon','internal.scan_effective_identification(public.scans)','EXECUTE'),'anonymous cannot supply trusted scan identity rows');
SELECT extensions.ok(NOT has_function_privilege('authenticated','internal.scan_effective_identification(public.scans)','EXECUTE'),'authenticated cannot assert trusted identity rows');
SELECT extensions.ok(has_function_privilege('service_role','internal.scan_effective_identification(public.scans)','EXECUTE'),'service consumer can evaluate an already-authorized row');
DO $$ DECLARE denied BOOLEAN; BEGIN
  SET LOCAL ROLE authenticated;
  denied := FALSE;
  BEGIN PERFORM internal.scan_effective_identification(NULL::public.scans);
  EXCEPTION WHEN insufficient_privilege THEN denied := TRUE; END;
  IF NOT denied THEN RAISE EXCEPTION 'actual client evaluated service row policy'; END IF;
  RESET ROLE;
END $$;
SELECT extensions.pass('actual authenticated role cannot invoke the saved-row policy');
SELECT extensions.ok((SELECT NOT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid='internal.scan_effective_identification(public.scans)'::regprocedure),'identity policy stays invoker with a fixed search path');
SELECT extensions.ok((SELECT pg_get_triggerdef(oid) LIKE '%confirmed_species_identity_revision%' AND pg_get_triggerdef(oid) LIKE '%primary_identification%' FROM pg_trigger WHERE tgname='trg_apply_ingested_scan_field_trip_progress_update'),'authority revision and primary changes recompute Field Trip receipts');
SELECT extensions.is((SELECT count(*)::INTEGER FROM pg_catalog.pg_constraint
  WHERE conrelid='public.scans'::regclass AND contype='c' AND convalidated
  AND conname IN ('scans_primary_identification_check','scans_primary_identification_subject_check',
    'scans_verified_species_review_check','scans_identification_provenance_check')),4,
  'public saved-row projection depends on all four validated identity constraints');
SELECT extensions.ok((SELECT NOT prosecdef AND proconfig @> ARRAY['search_path=""']
  AND pg_get_functiondef(oid) NOT LIKE '%internal.%'
  FROM pg_proc WHERE oid='public.explore_projected_post_cards(uuid)'::regprocedure),
  'public cards preserve caller RLS without reaching private helpers');
SELECT extensions.ok(NOT has_schema_privilege('anon','internal','USAGE')
  AND NOT has_schema_privilege('authenticated','internal','USAGE'),
  'public projections do not widen private schema access');
SELECT * FROM extensions.finish();
ROLLBACK;
