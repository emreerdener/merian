\set ON_ERROR_STOP on
BEGIN;
SELECT extensions.plan(1);
INSERT INTO auth.users(id, aud, role, is_anonymous) VALUES
 ('10000000-0000-0000-0000-000000000001','authenticated','authenticated',TRUE),
 ('10000000-0000-0000-0000-000000000002','authenticated','authenticated',FALSE);
INSERT INTO public.users(id,public_author_name,public_identity_source,public_username) VALUES
 ('10000000-0000-0000-0000-000000000001','Fixture A','alias','library_fixture_a'),
 ('10000000-0000-0000-0000-000000000002','Fixture B','alias','library_fixture_b') ON CONFLICT(id) DO NOTHING;
INSERT INTO public.scans(id,user_id,ai_confidence_score) VALUES
 ('10000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000001',0.5);
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT public.set_owned_scan_library_details('10000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000020','Synthetic note',TRUE,ARRAY['first']);
SELECT public.set_owned_scan_library_details('10000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000021',NULL,FALSE,ARRAY['second']);
-- An ambiguous old success must never overwrite a newer accepted operation.
SELECT public.set_owned_scan_library_details('10000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000020','Synthetic note',TRUE,ARRAY['first']);
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.get_owned_scan_library_details(ARRAY['10000000-0000-0000-0000-000000000010'::UUID]) WHERE field_notes IS NULL AND NOT is_favorite) THEN
  RAISE EXCEPTION 'old retry overwrote newer details'; END IF;
 BEGIN
  PERFORM public.set_owned_scan_library_details('10000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000020','Different payload',TRUE,ARRAY['first']);
  RAISE EXCEPTION 'operation identity reuse accepted';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.get_owned_scan_library_details(ARRAY['10000000-0000-0000-0000-000000000010'::UUID])) THEN
  RAISE EXCEPTION 'foreign private details visible'; END IF;
 BEGIN
  PERFORM public.set_owned_scan_library_details('10000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000020','Synthetic note',TRUE,ARRAY['first']);
  RAISE EXCEPTION 'foreign acknowledged operation was reusable';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
UPDATE public.scans SET is_tombstoned=TRUE WHERE id='10000000-0000-0000-0000-000000000010';
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.get_owned_scan_library_details(ARRAY['10000000-0000-0000-0000-000000000010'::UUID])) THEN
  RAISE EXCEPTION 'deleted private details visible'; END IF;
 BEGIN
  PERFORM public.set_owned_scan_library_details('10000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000022',NULL,FALSE,ARRAY[]::TEXT[]);
  RAISE EXCEPTION 'deleted scan accepted mutation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF has_table_privilege('authenticated','internal.scan_library_details','SELECT') OR
    has_table_privilege('anon','internal.scan_library_details','SELECT') OR
    has_table_privilege('service_role','internal.scan_library_details','SELECT') OR
    has_function_privilege('anon','public.get_owned_scan_library_details(uuid[])','EXECUTE') THEN
  RAISE EXCEPTION 'private library ACL escaped owner RPC'; END IF;
END $$;
SELECT extensions.pass('private library operation receipts, owner isolation, and deletion hold');
SELECT * FROM extensions.finish();
ROLLBACK;
