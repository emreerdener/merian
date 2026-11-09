-- No hosted input: catalog metadata and denied API execution only.
BEGIN;
SELECT extensions.no_plan();
CREATE TEMP TABLE history_lint_routines(signature TEXT PRIMARY KEY, volatility TEXT NOT NULL);
INSERT INTO history_lint_routines VALUES
 ('internal.validate_initial_admitted_proof(text,text,text,text,text,text,text,text,text,text,text,text)','s'),
 ('internal.assert_initial_cancellation_erasure_boundary(internal.initial_admitted_cancellation_staging,jsonb)','v'),
 ('internal.capture_initial_cancellation_private_images(uuid)','v'),
 ('internal.initial_cpm_photo_text_units(text)','i'),
 ('internal.assert_initial_cpm_photo_recipe(jsonb)','s'),
 ('internal.parse_initial_cpm_photo_content(text)','s'),
 ('internal.parse_initial_cpm_photo_candidate(text)','s'),
 ('internal.initial_cpm_photo_digest(text,text)','s'),
 ('internal.parse_initial_cpm_photo_assignment(text,text)','s'),
 ('internal.parse_initial_cpm_photo_recovery(text,text,text)','s'),
 ('internal.assert_initial_cpm_verification_start(internal.initial_analysis_preparation_intents,internal.initial_analysis_preparation_intents)','v'),
 ('internal.initial_cpm_admission_submission(text,text)','s'),
 ('internal.parse_initial_cpm_admitted_document(text,text)','s'),
 ('internal.build_initial_cpm_admitted_manifest(internal.initial_preparation_admission_receipts,bigint)','s'),
 ('internal.initial_cpm_admission_bridge_response(internal.initial_analysis_preparation_intents,internal.initial_preparation_admission_receipts)','s'),
 ('internal.initial_cpm_cancellation_retained_row(text,jsonb,boolean)','s'),
 ('internal.initial_result_node_matches_v1(jsonb,jsonb,integer)','s'),
 ('internal.initial_result_primary_matches_v1(jsonb)','s'),
 ('internal.initial_consuming_row_image(text,jsonb)','s'),
 ('internal.initial_report_expected_writes(jsonb,jsonb)','s'),
 ('internal.assert_initial_consuming_expectations(text,jsonb)','s'),
 ('internal.capture_initial_accounted_cancellation_prestate(uuid,uuid)','v'),
 ('internal.initial_cancellation_invocation_event(internal.initial_admitted_cancellation_staging)','s'),
 ('internal.capture_initial_cancellation_accounting_images(internal.initial_admitted_cancellation_staging)','v'),
 ('internal.assert_initial_cancellation_terminal_shape(jsonb)','s'),
 ('internal.report_initial_analysis_usage(uuid,uuid,text,uuid,uuid,text,text)','v'),
 ('internal.decode_initial_result_numbers_v1(jsonb,jsonb)','s'),
 ('internal.initial_dispatch_invocation_matches(jsonb,jsonb)','s'),
 ('internal.initial_dispatch_expected_writes(jsonb,jsonb,timestamptz)','s'),
 ('internal.assert_initial_dispatch_terminal(internal.initial_consuming_staging)','v'),
 ('internal.initial_completion_event_catalog_v1(text,text,text)','s'),
 ('internal.initial_completion_credit_prefix_v1(jsonb,timestamptz)','v'),
 ('internal.initial_completion_legacy_media_image_v1(uuid,uuid,jsonb)','v'),
 ('internal.initial_completion_tail_images_v1(jsonb,jsonb,jsonb)','s'),
 ('internal.initial_completion_accounting_image_v1(uuid,uuid,uuid)','v'),
 ('internal.prepare_initial_cpm_retention_v1(uuid,uuid,text,uuid,text,text)','v'),
 ('internal.initial_cpm_adoption_shape_v1(uuid,uuid,text,text)','s'),
 ('internal.assert_initial_cpm_adoption_binding_v1(jsonb)','s'),
 ('internal.initial_cancellation_cleanup_count(jsonb)','s');
SELECT extensions.ok(pg_catalog.to_regprocedure(signature) IS NOT NULL,'reviewed routine exists: '||signature)
FROM history_lint_routines;
SELECT extensions.is(p.provolatile::TEXT,r.volatility,'safe volatility: '||r.signature)
FROM history_lint_routines r JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(r.signature);
SELECT extensions.ok(NOT p.prosecdef AND p.proconfig @> ARRAY['search_path=""'],'invoker and empty search path: '||r.signature)
FROM history_lint_routines r JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(r.signature);
SELECT extensions.ok(NOT pg_catalog.has_function_privilege(role_name,signature,'EXECUTE'),'API execution denied: '||role_name||' '||signature)
FROM history_lint_routines CROSS JOIN (VALUES('anon'),('authenticated'),('service_role')) roles(role_name);
SELECT extensions.is((SELECT count(*) FROM pg_catalog.pg_depend d
 JOIN history_lint_routines r ON d.refclassid='pg_catalog.pg_proc'::REGCLASS
  AND d.refobjid=pg_catalog.to_regprocedure(r.signature)
 WHERE (d.classid='pg_catalog.pg_class'::REGCLASS AND EXISTS(
  SELECT 1 FROM pg_catalog.pg_index i WHERE i.indexrelid=d.objid))
 OR d.classid='pg_catalog.pg_attrdef'::REGCLASS),0::BIGINT,
 'no index or generated/default expression relies on stronger volatility');
SELECT * FROM extensions.finish();
ROLLBACK;
