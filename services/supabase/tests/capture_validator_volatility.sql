BEGIN;
SELECT extensions.plan(5);
SELECT extensions.is((SELECT provolatile::TEXT FROM pg_catalog.pg_proc WHERE oid='internal.identification_provenance_is_valid(jsonb)'::regprocedure),'i','constant provenance normalization remains immutable');
SELECT extensions.is((SELECT provolatile::TEXT FROM pg_catalog.pg_proc WHERE oid='internal.identification_metrics_are_gemini_compatible(jsonb,text)'::regprocedure),'i','transitive metrics validator retains correct immutable dependency');
SELECT extensions.is((SELECT provolatile::TEXT FROM pg_catalog.pg_proc WHERE oid='internal.initial_evidence_contract(jsonb,text,text)'::regprocedure),'s','initial evidence contract conservatively matches stable dependencies');
SELECT extensions.ok(internal.identification_provenance_is_valid(NULL),'legacy null provenance remains valid');
SELECT extensions.ok(position('jsonb_build_object' in pg_catalog.pg_get_functiondef('internal.identification_provenance_is_valid(jsonb)'::regprocedure))=0,'constant normalization uses no stable polymorphic builder');
SELECT * FROM extensions.finish();
ROLLBACK;
