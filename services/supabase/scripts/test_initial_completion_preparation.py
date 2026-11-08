"""Focused, local-only original completion preparation qualification.

Uses guarded admission/handoff, real private dispatch and synthetic retained
results. Settlement-prefix writes are rollback-only; partial commits must fail.
CPM settlement stays held until original adoption evidence is integrated.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time

from initial_atomic_admission_test_support import Qualification, ROOT
from initial_cpm_atomic_admission_committed import seed_committed_admission
from initial_invocation_erasure_races import install_result_fixture
from test_initial_dispatch import FIXTURE, SCAN, ROLE, CALL, SNAPSHOT as DISPATCH_SNAPSHOT

# Only this hash leaves the database; no scan/profile bodies are retained.
SNAPSHOT = """
SELECT encode(extensions.digest(convert_to(jsonb_build_object(
 'original',(""" + DISPATCH_SNAPSHOT.strip().rstrip(';') + """),
 'scans',(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM public.scans s),
 'users',(SELECT jsonb_agg(internal.initial_completion_owner_image_v1(to_jsonb(u)) ORDER BY id) FROM public.users u),
 'species_counts',(SELECT jsonb_agg(to_jsonb(c) ORDER BY user_id,species_id) FROM internal.user_species_scan_counts c),
 'events',(SELECT jsonb_agg(to_jsonb(e) ORDER BY id) FROM public.ai_usage_events e)
)::TEXT,'UTF8'),'sha256'),'hex');
"""


def run(q, funding, media_vector, media_only=False, complete=False, journey_only=False, race_order=None, erase=False, report_after=False, account_erase=False, primary_review=False):
    for path in [Path(__file__), FIXTURE, Path(__file__).with_name('test_initial_dispatch.py'),
                 Path(__file__).with_name('initial_invocation_erasure_races.py')]:
        q.record['source_manifest'][str(path.relative_to(ROOT))] = q.digest(path)
    q.record['scope'] = 'Original completion-stage and rollback-only settlement prefix after guarded dispatch and synthetic result. Legacy uses real SQL transfer owners with synthetic byte attestations; CPM settlement is denied before adoption. No committed completion, provider, physical blob IO or native qualification.'
    q.record.update(funding_mode=funding, media_vector=media_vector, media_only=media_only)
    q.record['original_report_order'] = 'after_completion' if report_after else 'before_completion'
    q.save()
    q.record['primary_review'] = primary_review
    if primary_review:
        # Choose this synthetic executor provenance before admission. Never
        # rewrite an admitted configuration or an existing invocation/result.
        dispatch_fixture = FIXTURE.read_text()
        schema = '"schema":"merian_identify_v1"'
        if dispatch_fixture.count(schema) != 1:
            raise ValueError('unique original dispatch provenance schema required')
        dispatch_fixture = dispatch_fixture.replace(schema, '"schema":"merian_identify_primary_v1"')
        q.record['primary_dispatch_fixture_sha256'] = hashlib.sha256(dispatch_fixture.encode()).hexdigest()
        q.execute('install_primary_dispatch_fixture_before_admission', dispatch_fixture)
    if media_vector == 0:
        seed_committed_admission(q, funding)
    else:
        source = Path(__file__).with_name('fixtures') / 'initial_invocation_erasure.sql'
        q.record['source_manifest'][str(source.relative_to(ROOT))] = q.digest(source)
        prefix, owner, _ = q.fixture_prefix(held=funding == 'complimentary')
        cases = source.read_text()
        start = 'CREATE FUNCTION pg_temp.admit_erasure_scan('
        end = 'CREATE FUNCTION pg_temp.seed_admitted_invocation('
        if cases.count(start) != 1 or cases.count(end) != 1:
            raise ValueError('unique guarded admission boundaries required')
        admission = cases[cases.index(start):cases.index(end)].replace('00000000-0000-4000-8000-00000000f001', owner)
        fixture = prefix + admission
        if media_only and media_vector == 4:
            # Freeze a valid owner order different from source/inference order
            # before admission. Never rewrite an admitted submission.
            fixture += """UPDATE media_vectors SET v=jsonb_set(v,'{candidate,source_plan,owner_timeline}',
              '[{"kind":"description","index":0},{"kind":"media","index":1},{"kind":"media","index":0},{"kind":"description","index":1}]') WHERE i=4;"""
        fixture += "SELECT pg_temp.admit_erasure_scan('" + SCAN + "'," + str(media_vector) + ");"
        fixture += 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE; COMMIT;'
        q.record['fixture_sha256'] = hashlib.sha256(fixture.encode()).hexdigest()
        q.execute('guarded_original_legacy_admission', fixture)
    if media_vector != 0:
        # Complete the existing legacy SQL handoff before dispatch. This uses
        # synthetic byte attestations and does not claim physical blob IO.
        operations = [
            "PERFORM * FROM internal.begin_initial_media_copy_v2(r.owner_id,r.scan_id,r.receipt_digest);",
            None,
            "PERFORM * FROM internal.complete_initial_media_copy_v2(r.owner_id,r.scan_id,r.receipt_digest);",
            "PERFORM * FROM internal.claim_initial_media_verification_v2(r.owner_id,r.scan_id,r.receipt_digest);",
            "PERFORM * FROM internal.settle_initial_media_verification_v2(r.owner_id,r.scan_id,r.receipt_digest,(SELECT (claim::JSONB->>'claim_token')::UUID FROM internal.initial_media_verification_claims_v2 WHERE scan_id=r.scan_id));",
            "PERFORM * FROM internal.transfer_initial_preparation_v2(r.owner_id,r.scan_id,r.receipt_digest,(SELECT receipt_digest FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=r.scan_id));",
        ]
        for index, operation in enumerate(operations):
            if operation is None:
                import uuid
                object_ids = json.loads(q.execute('original_handoff_object_ids',
                    "SELECT jsonb_agg(o->>'object_id' ORDER BY o->>'object_id') FROM internal.initial_preparation_admission_receipts r CROSS JOIN LATERAL jsonb_array_elements(r.mapping::JSONB->'objects') o;"))
                commands = ["PERFORM * FROM internal.record_initial_media_copy_object_v2(r.owner_id,r.scan_id,r.receipt_digest,'" + str(uuid.UUID(value)) + "');" for value in object_ids]
            else:
                commands = [operation]
            for member, command in enumerate(commands):
                label = str(index) + '_' + str(member)
                q.execute('original_legacy_handoff_' + label,
                          "BEGIN; SELECT set_config('request.jwt.claim.role','service_role',TRUE); UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE; "
                          "DO $$ DECLARE r internal.initial_preparation_admission_receipts; BEGIN SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts; "
                          + command + " END $$; COMMIT;")
                q.execute('restore_inactive_after_handoff_' + label,
                          'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
    if not primary_review:
        q.execute('install_disposable_dispatch_fixture', FIXTURE.read_text())
    q.execute('real_role_original_dispatch', 'BEGIN;' + ROLE + CALL + 'COMMIT;')
    install_result_fixture(q, injected_dispatch=False, primary_species=primary_review)
    q.execute('real_role_synthetic_retained_result', 'BEGIN;' + ROLE + "SELECT public.s0_result_fixture('valid'); COMMIT;")
    # Extending the shared stage composite must preserve the report branch as
    # well as the dispatch/result branches already used above.
    q.execute('install_disposable_original_report_adapter', """
CREATE FUNCTION public.test_completion_original_report() RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE i internal.identification_invocations; a internal.initial_analysis_admissions;
 r internal.initial_preparation_admission_receipts; reply JSONB;
BEGIN
 SELECT * INTO STRICT i FROM internal.identification_invocations WHERE is_initial_analysis;
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions WHERE scan_id=i.scan_id;
 SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id=i.scan_id;
 reply:=internal.report_initial_analysis_usage(i.user_id,i.scan_id,a.submission_digest,i.id,
  (r.accounting::JSONB#>>'{reservation,lease_token}')::UUID,'draft','{"candidate_tokens":37,"input_tokens":101}');
 IF reply->>'event_id' IS NULL THEN RAISE EXCEPTION USING ERRCODE='ZX814'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.test_completion_original_report() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_completion_original_report() TO service_role;
""")
    if not report_after:
        q.execute('shared_stage_original_report_still_commits', 'BEGIN;' + ROLE + 'SELECT public.test_completion_original_report(); COMMIT;')
    if race_order:
        from initial_completion_journey_races import run as run_race
        run_race(q, race_order, SNAPSHOT)
        q.finish()
        return
    if journey_only:
        before = q.execute('original_completion_snapshot', SNAPSHOT)
        qualify_completion(q, before, erase=erase, report_after=report_after, primary_review=primary_review)
        if account_erase:
            from initial_completion_account_erasure import run as erase_account
            erase_account(q, SNAPSHOT, ROLE)
        q.finish()
        return
    # The disposable adapter obtains original identities server-side. It never
    # grants the production preparation function to an API role.
    q.execute('install_disposable_completion_preparation_adapter', """
CREATE FUNCTION public.test_initial_completion_preparation(expected_species TEXT DEFAULT 'none') RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE r internal.initial_analysis_results; a internal.initial_analysis_admissions; reply JSONB; digest TEXT;
BEGIN
 SELECT * INTO STRICT r FROM internal.initial_analysis_results;
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions WHERE scan_id=r.scan_id;
 digest:=encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex');
 reply:=internal.prepare_initial_completion_v1(r.owner_id,r.scan_id,a.submission_digest,r.result_evidence_id,digest);
 IF reply->>'species_case' IS DISTINCT FROM expected_species
 OR reply#>>'{scan_input,id}' IS DISTINCT FROM r.scan_id::TEXT
 OR reply#>>'{scan_input,user_id}' IS DISTINCT FROM r.owner_id::TEXT
 OR reply#>>'{scan_input,ai_confidence_score}' IS DISTINCT FROM r.result_snapshot#>>'{data,confidence_score}'
 -- Retained v1 provenance encodes the fractional temperature as text;
 -- public scan provenance uses the schema-decoded JSON number.
 OR reply#>'{scan_input,identification_provenance}' IS DISTINCT FROM
   jsonb_set(r.provenance_snapshot,'{generation,temperature}',to_jsonb((r.provenance_snapshot#>>'{generation,temperature}')::DOUBLE PRECISION))
 OR reply#>'{scan_input,life_stage}' IS DISTINCT FROM 'null'::JSONB
 OR reply#>'{scan_input,reproductive_condition}' IS DISTINCT FROM 'null'::JSONB
 OR reply#>'{description_reference,ordered_description_digest}' IS DISTINCT FROM to_jsonb(a.descriptions_digest)
 OR reply#>>'{scan_input,llm_usage_metadata,accounting_contract}' IS DISTINCT FROM 'identification_invocation_v1'
 OR reply#>'{scan_input,llm_total_tokens}' IS DISTINCT FROM 'null'::JSONB
 OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions)
 OR EXISTS(SELECT 1 FROM public.scans)
 THEN RAISE EXCEPTION USING ERRCODE='ZX810'; END IF;
 IF a.binding_version=4 AND (reply->>'media_case' IS DISTINCT FROM 'cpm'
  OR reply#>>'{scan_input,geoprivacy}' IS DISTINCT FROM 'private'
  OR reply#>'{scan_final,gps_lat_exact}' IS DISTINCT FROM 'null'::JSONB
  OR reply#>'{scan_final,gps_long_exact}' IS DISTINCT FROM 'null'::JSONB
  OR reply#>'{scan_final,public_location_label}' IS DISTINCT FROM 'null'::JSONB
  OR reply#>'{scan_input,timestamp}' IS DISTINCT FROM reply->'completed_at'
  OR reply->>'timestamp_basis' IS DISTINCT FROM 'completion')
 THEN RAISE EXCEPTION USING ERRCODE='ZX811'; END IF;
 -- Check actual column types, NOT NULL and CHECK constraints in an isolated
 -- temporary shape. This deliberately does not claim scan-trigger execution.
 CREATE TEMP TABLE completion_projection_shape (LIKE public.scans INCLUDING CONSTRAINTS) ON COMMIT DROP;
 INSERT INTO pg_temp.completion_projection_shape
  SELECT (jsonb_populate_record(NULL::public.scans,reply->'scan_final')).*;
END $$;
REVOKE ALL ON FUNCTION public.test_initial_completion_preparation(TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_initial_completion_preparation(TEXT) TO service_role;
""")
    before = q.execute('original_completion_preparation_snapshot', SNAPSHOT)
    q.execute('prepare_original_without_business_writes', 'BEGIN;' + ROLE + "SELECT public.test_initial_completion_preparation(); COMMIT;")
    if q.execute('preparation_preserves_original_scope', SNAPSHOT) != before:
        raise ValueError('read-only preparation changed original scope')
    for role in ['anon', 'authenticated', 'service_role']:
        q.execute('deny_private_preparation_' + role,
                  'BEGIN; SET LOCAL ROLE ' + role + '; SELECT internal.prepare_initial_completion_v1(NULL,NULL,NULL,NULL,NULL); COMMIT;', '42501')
    q.execute('install_disposable_completion_media_adapter', """
CREATE FUNCTION public.test_completion_legacy_media(source_indexes INTEGER[],kinds TEXT[],poster_index INTEGER DEFAULT NULL) RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE r internal.initial_analysis_results; a internal.initial_analysis_admissions;
 receipt internal.initial_preparation_admission_receipts; media JSONB; expected JSONB;
 copied JSONB; poster JSONB; item JSONB; n INTEGER;
BEGIN
 SELECT * INTO STRICT r FROM internal.initial_analysis_results;
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions WHERE scan_id=r.scan_id;
 SELECT * INTO STRICT receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=r.scan_id;
 media:=internal.prepare_initial_completion_legacy_media_v1(r.owner_id,r.scan_id,a.submission_digest,r.result_evidence_id,
  encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex'));
 IF a.binding_version=4 THEN RAISE EXCEPTION USING ERRCODE='ZX819'; END IF;
 IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(media) key)<>ARRAY['items','kind','receipt_digest']
  OR media->>'kind' IS DISTINCT FROM 'legacy_transfer_v1'
  OR media->>'receipt_digest' IS DISTINCT FROM (SELECT receipt_digest FROM internal.initial_preparation_transfer_receipts WHERE scan_id=r.scan_id)
  OR jsonb_array_length(media->'items') IS DISTINCT FROM cardinality(source_indexes) THEN
  RAISE EXCEPTION USING ERRCODE='ZX820'; END IF;
 -- Explicit fixture owner indexes/kinds are independent of the projected list.
 -- Video's frame/audio inputs must not appear as separate owners.
 FOR n IN 1..cardinality(source_indexes) LOOP
  copied:=receipt.mapping::JSONB#>ARRAY['items',source_indexes[n]::TEXT];
  copied:=CASE WHEN kinds[n]='video' THEN copied->'source'
   ELSE COALESCE(NULLIF(copied->'prepared','null'::JSONB),copied->'source') END;
  poster:=NULL;
  IF kinds[n]='video' AND poster_index IS NOT NULL THEN
   poster:=receipt.mapping::JSONB#>ARRAY['items',poster_index::TEXT];
   poster:=COALESCE(NULLIF(poster->'prepared','null'::JSONB),poster->'source');
  END IF;
  expected:=jsonb_build_object('ordinal',n-1,'kind',kinds[n],
   'media_id',copied->'destination_object_id','content_type',copied#>'{bytes,content_type}',
   'byte_count',copied#>'{bytes,byte_count}','sha256',copied#>'{bytes,sha256}',
   'poster_media_id',poster->'destination_object_id');
  item:=media->'items'->(n-1);
  IF item IS DISTINCT FROM expected OR NOT EXISTS(
   SELECT 1 FROM internal.initial_analysis_media_registry dst
   WHERE dst.scan_id=r.scan_id AND dst.object_id=(item->>'media_id')::UUID AND NOT dst.retired) THEN
   RAISE EXCEPTION USING ERRCODE='ZX821'; END IF;
 END LOOP;
EXCEPTION WHEN SQLSTATE '55000' THEN
 IF cardinality(source_indexes)=0 AND SQLERRM='initial_completion_media_unavailable' THEN RAISE; END IF;
 RAISE EXCEPTION USING ERRCODE='ZX822';
END $$;
REVOKE ALL ON FUNCTION public.test_completion_legacy_media(INTEGER[],TEXT[],INTEGER) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_completion_legacy_media(INTEGER[],TEXT[],INTEGER) TO service_role;
""")
    # Fixture intent, not values calculated from the implementation under test.
    media_cases = {
        0: "ARRAY[]::INTEGER[],ARRAY[]::TEXT[],NULL",
        1: "ARRAY[0],ARRAY['image'],NULL",
        2: "ARRAY[0],ARRAY['image'],NULL",
        3: "ARRAY[0],ARRAY['audio'],NULL",
        4: "ARRAY[0,1],ARRAY['image','audio'],NULL",
        5: "ARRAY[1],ARRAY['video'],0",
        6: "ARRAY[2],ARRAY['video'],0",
    }
    if media_only and media_vector == 4:
        media_cases[4] = "ARRAY[1,0],ARRAY['audio','image'],NULL"
    q.execute('original_terminal_media_projection' if media_vector else 'cpm_cannot_use_legacy_media_projection',
              'BEGIN;' + ROLE + 'SELECT public.test_completion_legacy_media(' + media_cases[media_vector] + '); COMMIT;',
              '55000' if media_vector == 0 else None)
    if q.execute('media_projection_preserves_original_scope', SNAPSHOT) != before:
        raise ValueError('read-only media projection changed original scope')
    for role in ['anon', 'authenticated', 'service_role']:
        q.execute('deny_private_media_projection_' + role,
                  'BEGIN; SET LOCAL ROLE ' + role + '; SELECT internal.prepare_initial_completion_legacy_media_v1(NULL,NULL,NULL,NULL,NULL); COMMIT;', '42501')
    if media_only:
        q.record['scope'] = 'Read-only original completion and finalized legacy media projection after original SQL handoff with synthetic byte attestations, dispatch/result/report. No funding-prefix tests, committed completion, provider, physical blob IO, ticket or native qualification.'
        q.finish()
        return
    q.execute('prepare_exact_existing_dictionary_identity', """
BEGIN;
INSERT INTO public.species_dictionary(scientific_name,iucn_red_list_status) VALUES('Danaus plexippus','EN');
""" + ROLE + "SELECT public.test_initial_completion_preparation('new'); ROLLBACK;")
    q.execute('prepare_existing_owner_species_count', """
BEGIN;
INSERT INTO public.species_dictionary(scientific_name,iucn_red_list_status) VALUES('Danaus plexippus','EN');
INSERT INTO internal.user_species_scan_counts(user_id,species_id,scan_count)
 SELECT r.owner_id,d.id,2 FROM internal.initial_analysis_results r CROSS JOIN public.species_dictionary d
 WHERE d.scientific_name='Danaus plexippus';
""" + ROLE + "SELECT public.test_initial_completion_preparation('existing'); ROLLBACK;")
    if q.execute('dictionary_probe_and_preparation_rollback', SNAPSHOT) != before:
        raise ValueError('preparation probe changed original scope')
    q.execute('install_disposable_completion_stage_adapter', """
CREATE FUNCTION public.test_initial_completion_stage(fault TEXT DEFAULT NULL) RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE r internal.initial_analysis_results; a internal.initial_analysis_admissions; original JSONB; digest TEXT;
BEGIN
 SELECT * INTO STRICT r FROM internal.initial_analysis_results;
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions WHERE scan_id=r.scan_id;
 digest:=encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex');
 IF fault IN ('projection','roots','extra','stale_clock') THEN
  original:=internal.prepare_initial_completion_v1(r.owner_id,r.scan_id,a.submission_digest,r.result_evidence_id,digest);
  CASE fault
   WHEN 'projection' THEN original:=jsonb_set(original,'{scan_final,is_verified}','true');
   WHEN 'roots' THEN original:=jsonb_set(original,'{roots}','{}');
   WHEN 'extra' THEN original:=original||'{"caller_field":true}'::JSONB;
   WHEN 'stale_clock' THEN original:=jsonb_set(original,'{completed_at}',to_jsonb(transaction_timestamp()-INTERVAL '1 day'));
  END CASE;
  INSERT INTO internal.initial_consuming_staging(transaction_id,scan_id,owner_id,operation,
   admission_receipt_id,admission_receipt_digest,reservation_id,invocation_id,expected_writes,completion_prestate)
  VALUES(pg_current_xact_id(),r.scan_id,r.owner_id,'completion',
   (original->>'admission_receipt_id')::UUID,original->>'admission_receipt_digest',
   (original#>>'{quota,id}')::UUID,(original#>>'{invocation,id}')::UUID,'[]',original);
 ELSE
  PERFORM internal.begin_initial_completion_stage_v1(r.owner_id,r.scan_id,a.submission_digest,r.result_evidence_id,digest);
  IF fault='mutation' THEN
   UPDATE internal.initial_consuming_staging SET sealed=TRUE WHERE transaction_id=pg_current_xact_id();
  END IF;
 END IF;
 IF (SELECT count(*) FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id()
  AND operation='completion' AND owner_id=r.owner_id AND scan_id=r.scan_id AND expected_writes='[]'
  AND next_statement=0 AND NOT sealed AND NOT statement_active)<>1 THEN
  RAISE EXCEPTION USING ERRCODE='ZX812'; END IF;
EXCEPTION WHEN SQLSTATE '55000' THEN
 IF (fault IN ('projection','roots','extra','stale_clock') AND SQLERRM='initial_completion_prestate_invalid')
  OR (fault='mutation' AND SQLERRM='initial_completion_incomplete') THEN RAISE; END IF;
 RAISE EXCEPTION USING ERRCODE='ZX813';
END $$;
REVOKE ALL ON FUNCTION public.test_initial_completion_stage(TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_initial_completion_stage(TEXT) TO service_role;
""")
    q.execute('bind_original_completion_stage_then_rollback', 'BEGIN;' + ROLE + 'SELECT public.test_initial_completion_stage(); ROLLBACK;')
    for fault in ['projection', 'roots', 'extra', 'stale_clock', 'mutation']:
        q.execute('deny_completion_stage_' + fault,
                  'BEGIN;' + ROLE + "SELECT public.test_initial_completion_stage('" + fault + "'); COMMIT;", '55000')
        if q.execute('completion_stage_' + fault + '_rollback', SNAPSHOT) != before:
            raise ValueError('denied completion stage changed original scope')
    q.execute('unfinished_completion_cannot_commit',
              'BEGIN;' + ROLE + 'SELECT public.test_initial_completion_stage(); COMMIT;', '55000')
    if q.record['checks'][-1]['error_owners'] != ['internal.require_complete_initial_consuming_stage']:
        raise ValueError('unfinished commit must fail at the deferred completion-stage owner')
    if q.execute('unfinished_completion_rollback', SNAPSHOT) != before:
        raise ValueError('unfinished stage changed original scope')
    for role in ['anon', 'authenticated', 'service_role']:
        q.execute('deny_private_stage_constructor_' + role,
                  'BEGIN; SET LOCAL ROLE ' + role + '; SELECT internal.begin_initial_completion_stage_v1(NULL,NULL,NULL,NULL,NULL); COMMIT;', '42501')
    q.execute('install_disposable_completion_credit_adapter', """
CREATE FUNCTION public.test_completion_credit(mode TEXT DEFAULT 'normal') RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE stage internal.initial_consuming_staging; owner_id UUID; scan_id UUID; reply JSONB; expected TEXT;
BEGIN
 SELECT r.owner_id,r.scan_id INTO STRICT owner_id,scan_id FROM internal.initial_analysis_results r;
 IF mode='paid' THEN UPDATE public.users SET subscription_tier='pro',subscription_expires_at=NULL WHERE id=owner_id; END IF;
 PERFORM public.test_initial_completion_stage();
 IF mode='direct_attach' THEN
  UPDATE internal.initial_consuming_staging
   SET completion_credit=internal.initial_completion_credit_prefix_v1(completion_prestate,clock_timestamp())
   WHERE transaction_id=pg_current_xact_id();
  RAISE EXCEPTION 'unprepared direct attachment accepted' USING ERRCODE='ZX818';
 END IF;
 reply:=internal.settle_complimentary_analysis(owner_id,scan_id,NULL);
 SELECT * INTO STRICT stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 expected:=CASE WHEN stage.completion_prestate->'hold'='null'::JSONB THEN 'none' WHEN mode='paid' THEN 'paid_release' ELSE 'consumed' END;
 IF stage.completion_credit->>'case' IS DISTINCT FROM expected
  OR stage.completion_next_event<>(CASE WHEN expected='none' THEN 0 ELSE 8 END)
  OR stage.sealed OR stage.expected_writes<>'[]'::JSONB
  OR reply->'credit_consumed' IS DISTINCT FROM to_jsonb(expected='consumed')
  OR reply->'credit_released' IS DISTINCT FROM to_jsonb(expected='paid_release')
  OR EXISTS(SELECT 1 FROM public.scans) OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions) THEN
  RAISE EXCEPTION USING ERRCODE='ZX816'; END IF;
 IF mode='repeat' THEN PERFORM internal.settle_complimentary_analysis(owner_id,scan_id,NULL); END IF;
 IF mode='rewrite_prefix' THEN UPDATE internal.initial_consuming_staging SET completion_credit=jsonb_set(completion_credit,'{case}','"none"') WHERE transaction_id=stage.transaction_id; END IF;
 IF mode='extra_owner_statement' THEN UPDATE public.users SET complimentary_entitlement_epoch=complimentary_entitlement_epoch WHERE id=owner_id; END IF;
EXCEPTION WHEN SQLSTATE '55000' THEN
 IF (mode='repeat' AND SQLERRM='initial_completion_credit_invalid')
  OR (mode='rewrite_prefix' AND SQLERRM='initial_completion_consumption_unavailable')
  OR (mode='extra_owner_statement' AND SQLERRM='initial_completion_credit_event_invalid')
  OR (mode='injected' AND SQLERRM='initial_completion_credit_event_invalid')
  OR (mode IN ('unready','direct_attach') AND SQLERRM='initial_completion_adoption_unavailable') THEN RAISE; END IF;
 RAISE EXCEPTION USING ERRCODE='ZX817';
END $$;
REVOKE ALL ON FUNCTION public.test_completion_credit(TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_completion_credit(TEXT) TO service_role;
""")
    if media_vector == 0:
        q.execute('unprepared_cpm_adoption_cannot_settle',
                  'BEGIN;' + ROLE + "SELECT public.test_completion_credit('unready'); COMMIT;", '55000')
        if q.execute('unprepared_adoption_preserves_original_funding', SNAPSHOT) != before:
            raise ValueError('missing adoption proof changed original funding')
        q.execute('unprepared_cpm_direct_attachment_denied',
                  'BEGIN;' + ROLE + "SELECT public.test_completion_credit('direct_attach'); COMMIT;", '55000')
        if q.execute('unprepared_direct_attachment_preserves_scope', SNAPSHOT) != before:
            raise ValueError('direct attachment without adoption proof changed original scope')
        q.finish()
        return
    for mode in ['normal', 'paid']:
        q.execute('original_completion_credit_' + mode + '_rollback',
                  'BEGIN;' + ROLE + "SELECT public.test_completion_credit('" + mode + "'); ROLLBACK;")
    for mode in ['repeat', 'rewrite_prefix', 'extra_owner_statement']:
        q.execute('deny_completion_credit_' + mode,
                  'BEGIN;' + ROLE + "SELECT public.test_completion_credit('" + mode + "'); COMMIT;", '55000')
        if q.execute('completion_credit_' + mode + '_rollback', SNAPSHOT) != before:
            raise ValueError('denied completion credit changed original scope')
    if funding == 'complimentary':
        for name, body in [('suppressed', 'RETURN NULL;'),
                           ('rewritten', "NEW.settled_at:=NEW.settled_at+INTERVAL '1 second'; RETURN NEW;")]:
            injection = ("CREATE FUNCTION public.test_completion_credit_fault() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN "
                         + body + " END $$; CREATE TRIGGER zzzzzz_test_completion_credit_fault BEFORE UPDATE ON internal.complimentary_scan_usage "
                         "FOR EACH ROW EXECUTE FUNCTION public.test_completion_credit_fault();")
            q.execute('deny_completion_credit_' + name,
                      'BEGIN;' + injection + ROLE + "SELECT public.test_completion_credit('injected'); COMMIT;", '55000')
            if q.execute('completion_credit_' + name + '_rollback', SNAPSHOT) != before:
                raise ValueError('credit trigger fault changed original scope')
    q.execute('settled_prefix_without_scan_cannot_commit',
              'BEGIN;' + ROLE + 'SELECT public.test_completion_credit(); COMMIT;', '55000')
    if q.record['checks'][-1]['error_owners'] != ['internal.require_complete_initial_consuming_stage']:
        raise ValueError('partial settlement must fail at the deferred completion-stage owner')
    if q.execute('partial_settlement_rollback', SNAPSHOT) != before:
        raise ValueError('partial settlement changed original scope')
    q.execute('install_disposable_completion_suffix_adapter', """
CREATE FUNCTION public.test_completion_suffix(mode TEXT DEFAULT 'normal') RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE stage internal.initial_consuming_staging; suffix JSONB; projection JSONB;
 receipt JSONB; original JSONB; entitlement JSONB; expected_error TEXT;
BEGIN
 IF mode='before_credit' THEN PERFORM public.test_initial_completion_stage();
 ELSE PERFORM public.test_completion_credit(CASE WHEN mode='paid' THEN 'paid' ELSE 'normal' END); END IF;
 IF mode='injected' THEN
  UPDATE internal.initial_consuming_staging SET completion_prepared=TRUE,completion_suffix='{}'
   WHERE transaction_id=pg_current_xact_id();
 ELSE
  UPDATE internal.initial_consuming_staging SET completion_prepared=TRUE WHERE transaction_id=pg_current_xact_id();
 END IF;
 SELECT * INTO STRICT stage FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 suffix:=stage.completion_suffix;original:=stage.completion_prestate;
 projection:=suffix#>'{completion_after,completion_projection_snapshot}';
 receipt:=suffix#>'{completion_after,receipt_snapshot}';
 SELECT to_jsonb(e) INTO STRICT entitlement FROM internal.resolve_effective_entitlement(stage.owner_id) e;
 IF NOT stage.completion_prepared OR stage.sealed OR stage.expected_writes<>'[]'::JSONB
  OR projection->'entitlement_after' IS DISTINCT FROM entitlement
  OR projection->'completed_at' IS DISTINCT FROM original->'completed_at'
  OR projection->'plan_used' IS DISTINCT FROM original#>'{invocation,effective_plan}'
  OR projection->'result_digest' IS DISTINCT FROM original->'result_digest'
  OR projection#>'{media,receipt_digest}' IS DISTINCT FROM receipt->'finalized_media_binding_digest'
  OR receipt->'funding_binding_version' IS DISTINCT FROM '1'::JSONB
  OR receipt->'result_schema_version' IS DISTINCT FROM '1'::JSONB
  OR receipt->'ordered_description_digest' IS DISTINCT FROM original#>'{description_reference,ordered_description_digest}'
  OR receipt->'ordered_description_count' IS DISTINCT FROM original#>'{description_reference,ordered_description_count}'
  OR (suffix#>>'{events,0,ordinal}')::INTEGER IS DISTINCT FROM stage.completion_next_event
  OR suffix->'scan_after' IS DISTINCT FROM original->'scan_final'
  OR EXISTS(SELECT 1 FROM public.scans) OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions) THEN
  RAISE EXCEPTION USING ERRCODE='ZX823'; END IF;
 IF mode='repeat' THEN UPDATE internal.initial_consuming_staging SET completion_prepared=TRUE WHERE transaction_id=stage.transaction_id; END IF;
 IF mode='rewrite' THEN UPDATE internal.initial_consuming_staging SET completion_suffix=jsonb_set(completion_suffix,'{owner_after,total_species_discovered}','999') WHERE transaction_id=stage.transaction_id; END IF;
 IF mode='seal' THEN UPDATE internal.initial_consuming_staging SET sealed=TRUE WHERE transaction_id=stage.transaction_id; END IF;
 IF mode='remove' THEN DELETE FROM internal.initial_consuming_staging WHERE transaction_id=stage.transaction_id; END IF;
 IF mode='rollout' THEN
  UPDATE internal.entitlement_rollout_config
   SET entitlement_mode='complimentary',
    required_client_protocol=CASE WHEN required_client_protocol=3 THEN 2 ELSE 3 END WHERE config_key='current';
  SELECT to_jsonb(e) INTO STRICT entitlement FROM internal.resolve_effective_entitlement(stage.owner_id) e;
  IF entitlement->'entitlement_version'=projection#>'{entitlement_after,entitlement_version}' THEN
   RAISE EXCEPTION USING ERRCODE='ZX824'; END IF;
  IF (SELECT completion_suffix FROM internal.initial_consuming_staging WHERE transaction_id=stage.transaction_id) IS DISTINCT FROM suffix THEN
   RAISE EXCEPTION USING ERRCODE='ZX824'; END IF;
 END IF;
 RETURN jsonb_build_object('projection',projection,'receipt',receipt);
EXCEPTION WHEN SQLSTATE '55000' THEN
 expected_error:=CASE WHEN mode='before_credit' THEN 'initial_completion_suffix_invalid'
  WHEN mode='seal' THEN 'initial_completion_incomplete'
  WHEN mode='remove' THEN 'initial_analysis_consuming_stage_incomplete'
  ELSE 'initial_completion_consumption_unavailable' END;
 IF mode IN ('before_credit','injected','repeat','rewrite','seal','remove') AND SQLERRM=expected_error THEN RAISE; END IF;
 RAISE EXCEPTION USING ERRCODE='ZX825';
END $$;
REVOKE ALL ON FUNCTION public.test_completion_suffix(TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_completion_suffix(TEXT) TO service_role;
""")
    for mode in ['normal', 'paid', 'rollout', 'species_new', 'species_existing']:
        setup = ''
        if mode.startswith('species_'):
            setup = "INSERT INTO public.species_dictionary(scientific_name,iucn_red_list_status) VALUES('Danaus plexippus','EN');"
            if mode == 'species_existing':
                setup += "INSERT INTO internal.user_species_scan_counts(user_id,species_id,scan_count) SELECT r.owner_id,d.id,2 FROM internal.initial_analysis_results r CROSS JOIN public.species_dictionary d WHERE d.scientific_name='Danaus plexippus';"
        output = q.execute('guard_owned_completion_suffix_' + mode,
                           'BEGIN;' + setup + ROLE + "SELECT public.test_completion_suffix('" + mode + "'); ROLLBACK;")
        result = json.loads(output.splitlines()[-1])
        if mode.startswith('species_') and result['projection']['species_association']['scientific_name'] != 'Danaus plexippus':
            raise ValueError('original species association was not retained')
        # Independent canonical bytes and domain binding; no fixture response
        # bodies or generated identities are retained in evidence.
        encoded = json.dumps(result['projection'], sort_keys=True, ensure_ascii=False, separators=(',', ':'))
        digest = hashlib.sha256(('merian.initial-analysis.completion-projection.v1\n' + encoded).encode()).hexdigest()
        if digest != result['receipt']['completion_projection_digest']:
            raise ValueError('completion projection digest differs across Python and SQL')
        changed = dict(result['projection'], credit_consumed=not result['projection']['credit_consumed'])
        changed_bytes = json.dumps(changed, sort_keys=True, ensure_ascii=False, separators=(',', ':'))
        if hashlib.sha256(('merian.initial-analysis.completion-projection.v1\n' + changed_bytes).encode()).hexdigest() == digest:
            raise ValueError('changed settlement unexpectedly preserves completion digest')
    for mode in ['before_credit', 'injected', 'repeat', 'rewrite', 'seal', 'remove']:
        q.execute('deny_completion_suffix_' + mode,
                  'BEGIN;' + ROLE + "SELECT public.test_completion_suffix('" + mode + "'); COMMIT;", '55000')
        if q.execute('completion_suffix_' + mode + '_rollback', SNAPSHOT) != before:
            raise ValueError('denied completion suffix changed original scope')
    q.execute('prepared_suffix_without_scan_cannot_commit',
              'BEGIN;' + ROLE + 'SELECT public.test_completion_suffix(); COMMIT;', '55000')
    if q.record['checks'][-1]['error_owners'] != ['internal.require_complete_initial_consuming_stage']:
        raise ValueError('prepared suffix must still fail at deferred stage owner')
    if q.execute('prepared_suffix_rollback', SNAPSHOT) != before:
        raise ValueError('prepared suffix changed original scope')
    if complete:
        qualify_completion(q, before)
    q.finish()


def qualify_completion(q, before, erase=False, report_after=False, primary_review=False):
    q.record['scope'] = 'Private legacy completion integration after guarded admission/handoff/dispatch and synthetic retained result. Local SQL only; no provider, physical byte IO, API grant, native or functional acceptance.'
    q.save()
    q.execute('install_disposable_completion_adapter', """
CREATE FUNCTION public.test_complete_initial(mode TEXT DEFAULT 'fresh') RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE r internal.initial_analysis_results; a internal.initial_analysis_admissions; reply JSONB; digest TEXT;
BEGIN
 SELECT * INTO STRICT r FROM internal.initial_analysis_results;
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions WHERE scan_id=r.scan_id;
 digest:=encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex');
 IF mode='wrong_result' THEN digest:=repeat('f',64); END IF;
 reply:=internal.complete_initial_analysis_legacy_v1(r.owner_id,r.scan_id,a.submission_digest,r.result_evidence_id,digest);
 IF reply->>'outcome' IS DISTINCT FROM mode
  OR reply#>>'{receipt,result_evidence_id}' IS DISTINCT FROM r.result_evidence_id::TEXT
  OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
  OR (SELECT count(*) FROM public.scans WHERE id=r.scan_id AND user_id=r.owner_id)<>1
  OR (SELECT count(*) FROM internal.initial_analysis_completions WHERE scan_id=r.scan_id AND owner_id=r.owner_id)<>1 THEN
  RAISE EXCEPTION USING ERRCODE='ZX826'; END IF;
 RETURN reply;
END $$;
REVOKE ALL ON FUNCTION public.test_complete_initial(TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_complete_initial(TEXT) TO service_role;
""")
    if primary_review:
        q.execute('commit_original_primary_completion', 'BEGIN;' + ROLE + 'SELECT public.test_complete_initial(); COMMIT;')
        from initial_completion_primary_review import run as review_primary
        review_primary(q, SNAPSHOT, ROLE)
        return
    if erase:
        q.record['scope'] = 'Private legacy completion followed by actual service-role scan deletion request/completion and replay denial. Synthetic local SQL only; no physical storage deletion, provider, account erasure or native qualification.'
        q.execute('commit_before_scan_erasure', 'BEGIN;' + ROLE + 'SELECT public.test_complete_initial(); COMMIT;')
        q.execute('install_completed_scan_erasure_adapter', """
CREATE TABLE public.test_completed_erasure_args AS
SELECT r.owner_id,r.scan_id,a.submission_digest,r.result_evidence_id,
 (r.result_snapshot->>'invocation_id')::UUID invocation_id,
 encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex') digest,
 (SELECT complimentary_entitlement_epoch FROM public.users WHERE id=r.owner_id) epoch,
 (SELECT to_jsonb(h) FROM internal.complimentary_scan_usage h WHERE user_id=r.owner_id AND client_scan_id=r.scan_id) hold_image,
 (SELECT to_jsonb(e)-ARRAY['user_id','scan_id'] FROM public.ai_usage_events e WHERE source_type='identification_invocation'
  AND source_id=(r.result_snapshot->>'invocation_id')::UUID) event_image
FROM internal.initial_analysis_results r JOIN internal.initial_analysis_admissions a USING(scan_id,owner_id);
REVOKE ALL ON public.test_completed_erasure_args FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.test_erase_completed_scan(phase TEXT DEFAULT 'all') RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE r RECORD; denied BOOLEAN:=FALSE;
 requested TEXT; completed BOOLEAN; foreign_owner UUID;
BEGIN
 PERFORM internal.require_service_role();
 IF phase NOT IN ('all','request','finish','foreign') THEN RAISE EXCEPTION USING ERRCODE='ZX830'; END IF;
 SELECT * INTO STRICT r FROM public.test_completed_erasure_args;
 IF phase='foreign' THEN
  foreign_owner:=gen_random_uuid();
  INSERT INTO auth.users(id,aud,role) VALUES(foreign_owner,'authenticated','authenticated');
  requested:=public.request_scan_deletion(r.scan_id,foreign_owner);
  IF requested IS DISTINCT FROM 'forbidden' THEN RAISE EXCEPTION USING ERRCODE='ZX830'; END IF;
  RETURN;
 END IF;
 IF phase IN ('all','request') THEN
  requested:=public.request_scan_deletion(r.scan_id,r.owner_id);
  IF requested IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION USING ERRCODE='ZX830'; END IF;
 END IF;
 IF phase IN ('all','finish') THEN
  completed:=public.complete_scan_deletion(r.scan_id,r.owner_id);
  IF completed IS DISTINCT FROM TRUE THEN RAISE EXCEPTION USING ERRCODE='ZX830'; END IF;
 END IF;
 IF (SELECT complimentary_entitlement_epoch FROM public.users WHERE id=r.owner_id) IS DISTINCT FROM r.epoch
  OR (SELECT to_jsonb(h) FROM internal.complimentary_scan_usage h WHERE user_id=r.owner_id AND client_scan_id=r.scan_id) IS DISTINCT FROM r.hold_image
  OR (SELECT to_jsonb(e)-ARRAY['user_id','scan_id'] FROM public.ai_usage_events e WHERE source_type='identification_invocation'
   AND source_id=r.invocation_id) IS DISTINCT FROM r.event_image THEN RAISE EXCEPTION USING ERRCODE='ZX832'; END IF;
 IF phase='request' THEN RETURN; END IF;
 BEGIN
  PERFORM internal.complete_initial_analysis_legacy_v1(r.owner_id,r.scan_id,r.submission_digest,r.result_evidence_id,r.digest);
 EXCEPTION WHEN SQLSTATE '55000' OR SQLSTATE 'P0002' THEN
  IF NOT ((SQLSTATE='55000' AND SQLERRM='initial_analysis_deleted')
   OR (SQLSTATE='P0002' AND SQLERRM='initial_analysis_owner_unavailable')) THEN RAISE; END IF;
  denied:=TRUE;
 END;
 IF NOT denied OR EXISTS(SELECT 1 FROM public.scans WHERE id=r.scan_id AND user_id=r.owner_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=r.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs)
  OR (SELECT count(*) FROM internal.identification_invocations WHERE id=r.invocation_id AND scan_id IS NULL)<>1
  OR (SELECT count(*) FROM public.ai_usage_events WHERE source_type='identification_invocation'
    AND source_id=r.invocation_id)<>1
  OR (SELECT count(*) FROM public.ai_usage_events)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX831'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.test_erase_completed_scan(TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.test_erase_completed_scan(TEXT) TO service_role;
""")
        completed = q.execute('before_completed_scan_erasure', SNAPSHOT)
        q.execute('deny_foreign_completed_scan_erasure', 'BEGIN;' + ROLE + "SELECT public.test_erase_completed_scan('foreign'); ROLLBACK;")
        if q.execute('foreign_erasure_preserves_completed_scope', SNAPSHOT) != completed:
            raise ValueError('foreign deletion changed completed scope')
        q.execute('completed_scan_erasure_rollback', 'BEGIN;' + ROLE + 'SELECT public.test_erase_completed_scan(); SET CONSTRAINTS ALL IMMEDIATE; ROLLBACK;')
        if q.execute('completed_scan_erasure_preserves_rollback', SNAPSHOT) != completed:
            raise ValueError('completed scan erasure rollback changed original scope')
        q.execute('commit_completed_scan_deletion_request', 'BEGIN;' + ROLE + "SELECT public.test_erase_completed_scan('request'); COMMIT;")
        pending = q.execute('pending_completed_scan_deletion', SNAPSHOT)
        q.execute('deny_foreign_pending_scan_erasure', 'BEGIN;' + ROLE + "SELECT public.test_erase_completed_scan('foreign'); ROLLBACK;")
        if q.execute('foreign_erasure_preserves_pending_scope', SNAPSHOT) != pending:
            raise ValueError('foreign deletion changed pending scope')
        q.execute('repeat_pending_completed_scan_deletion', 'BEGIN;' + ROLE + "SELECT public.test_erase_completed_scan('request'); COMMIT;")
        if q.execute('pending_deletion_replay_preserves_scope', SNAPSHOT) != pending:
            raise ValueError('pending deletion replay changed original scope')
        q.execute('completed_scan_erasure_commit', 'BEGIN;' + ROLE + "SELECT public.test_erase_completed_scan('finish'); COMMIT;")
        return
    # These fault cases already have separate exact-source evidence. The late
    # report mode focuses on the new committed ordering.
    q.record['completion_fault_suite_executed'] = not report_after
    q.save()
    if not report_after:
        for species in ['none', 'new', 'existing']:
            setup = ''
            if species != 'none':
                setup = "INSERT INTO public.species_dictionary(scientific_name,iucn_red_list_status) VALUES('Danaus plexippus','EN');"
                if species == 'existing':
                    setup += "INSERT INTO internal.user_species_scan_counts(user_id,species_id,scan_count) SELECT r.owner_id,d.id,2 FROM internal.initial_analysis_results r CROSS JOIN public.species_dictionary d WHERE d.scientific_name='Danaus plexippus';"
            q.execute('actual_completion_events_' + species,
                      'BEGIN;' + setup + ROLE + 'SELECT public.test_complete_initial(); SET CONSTRAINTS ALL IMMEDIATE; ROLLBACK;')
            if q.execute('actual_completion_' + species + '_rollback', SNAPSHOT) != before:
                raise ValueError('completion probe failed to roll back')
        for name, body in [('suppressed', 'RETURN NULL;'),
                           ('rewritten', "NEW.is_verified:=TRUE; RETURN NEW;")]:
            injection = ("CREATE FUNCTION public.test_completion_scan_fault() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN "
                         + body + " END $$; CREATE TRIGGER zzzzzzz_test_completion_scan_fault BEFORE INSERT ON public.scans "
                         "FOR EACH ROW EXECUTE FUNCTION public.test_completion_scan_fault();")
            q.execute('deny_actual_completion_scan_' + name,
                      'BEGIN;' + injection + ROLE + 'SELECT public.test_complete_initial(); COMMIT;',
                      '55000' if name == 'suppressed' else '22023')
            if q.execute('actual_completion_scan_' + name + '_rollback', SNAPSHOT) != before:
                raise ValueError('scan trigger fault changed original scope')
        for name, body in [('suppressed', 'RETURN NULL;'),
                           ('rewritten', 'NEW.scan_count:=NEW.scan_count+7; RETURN NEW;')]:
            injection = ("INSERT INTO public.species_dictionary(scientific_name,iucn_red_list_status) VALUES('Danaus plexippus','EN');"
                         "CREATE FUNCTION public.test_completion_species_fault() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN "
                         + body + " END $$; CREATE TRIGGER zzzzzzz_test_completion_species_fault BEFORE INSERT ON internal.user_species_scan_counts "
                         "FOR EACH ROW EXECUTE FUNCTION public.test_completion_species_fault();")
            q.execute('deny_actual_completion_species_' + name,
                      'BEGIN;' + injection + ROLE + 'SELECT public.test_complete_initial(); COMMIT;', '55000')
            if q.execute('actual_completion_species_' + name + '_rollback', SNAPSHOT) != before:
                raise ValueError('species winner fault changed original scope')
        paid_outcome = 'released_paid_before_completion' if q.record['funding_mode'] == 'complimentary' else 'none'
        q.execute('actual_completion_paid_transition',
                  "BEGIN; UPDATE public.users SET subscription_tier='pro',subscription_expires_at=NULL;" + ROLE
                  + "DO $$ BEGIN IF public.test_complete_initial()#>>'{projection,settlement,outcome}' IS DISTINCT FROM '"
                  + paid_outcome + "' THEN RAISE EXCEPTION USING ERRCODE='ZX829'; END IF; END $$; SET CONSTRAINTS ALL IMMEDIATE; ROLLBACK;")
        if q.execute('actual_completion_paid_rollback', SNAPSHOT) != before:
            raise ValueError('paid completion changed original scope')
        q.execute('deferred_completion_denies_post_removal_change',
                  'BEGIN;' + ROLE + 'SELECT public.test_complete_initial(); RESET ROLE;'
                  "UPDATE public.scans SET human_intervention_notes='synthetic later note'; COMMIT;", '55000')
        if q.record['checks'][-1]['error_owners'][-1:] != ['internal.require_complete_initial_consuming_stage']:
            raise ValueError('post-removal change must reach the deferred completion owner')
        if q.execute('deferred_completion_rollback', SNAPSHOT) != before:
            raise ValueError('deferred completion violation changed original scope')
    q.execute('commit_original_completion', 'BEGIN;' + ROLE + 'SELECT public.test_complete_initial(); COMMIT;')
    if report_after:
        if q.execute('completion_does_not_invent_usage', 'SELECT count(*) FROM public.ai_usage_events;') != '0':
            raise ValueError('completion invented usage before original report')
        stable_tables = ['internal.initial_analysis_completions', 'internal.initial_analysis_results',
                         'internal.initial_analysis_submissions', 'internal.initial_analysis_admissions',
                         'internal.initial_preparation_admission_receipts', 'internal.ai_quota_reservations',
                         'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters',
                         'internal.complimentary_scan_usage', 'public.scans']
        immutable = "SELECT encode(extensions.digest(convert_to(jsonb_build_array(" + ','.join(
            "(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + table + " t)"
            for table in stable_tables) + ", (SELECT jsonb_agg(internal.initial_completion_owner_image_v1(to_jsonb(u)) ORDER BY id) FROM public.users u))::TEXT,'UTF8'),'sha256'),'hex');"
        committed = q.execute('before_late_report_immutable_completion_and_funding', immutable)
        q.execute('original_usage_report_after_completion', 'BEGIN;' + ROLE + 'SELECT public.test_completion_original_report(); COMMIT;')
        if q.execute('late_report_preserves_immutable_completion_and_funding', immutable) != committed:
            raise ValueError('late usage report changed committed result/completion or settled funding')
        q.execute('one_exact_original_usage_after_completion', """DO $$ BEGIN
 IF (SELECT count(*) FROM public.ai_usage_events)<>1
 OR (SELECT count(*) FROM internal.identification_invocations)<>1
 OR (SELECT count(*) FROM internal.identification_invocations i JOIN public.ai_usage_events e ON e.id=i.event_id
 JOIN internal.initial_analysis_results r ON r.scan_id=i.scan_id AND r.owner_id=i.user_id
 WHERE i.is_initial_analysis AND i.id=(r.result_snapshot->>'invocation_id')::UUID
  AND e.source_type='identification_invocation' AND e.source_id=i.id
  AND e.scan_id=r.scan_id AND e.user_id=r.owner_id AND e.outcome='success'
  AND e.prompt_tokens=101 AND e.candidate_tokens=37 AND e.metadata->>'ai_outcome'='draft')<>1
 THEN RAISE EXCEPTION USING ERRCODE='ZX842'; END IF;
END $$;""")
    after = q.execute('completed_original_snapshot', SNAPSHOT)
    first = q.execute('exact_completion_replay', 'BEGIN;' + ROLE + "SELECT public.test_complete_initial('replay'); COMMIT;")
    second = q.execute('repeated_completion_replay', 'BEGIN;' + ROLE + "SELECT public.test_complete_initial('replay'); COMMIT;")
    if first != second or q.execute('replay_preserves_original_scope', SNAPSHOT) != after:
        raise ValueError('completion replay changed the immutable receipt or original scope')
    q.execute('completion_rejects_different_result',
              'BEGIN;' + ROLE + "SELECT public.test_complete_initial('wrong_result'); COMMIT;", '55000')
    if q.execute('different_result_preserves_completed_scope', SNAPSHOT) != after:
        raise ValueError('conflicting completion changed original scope')
    q.execute('later_user_note_commits', "UPDATE public.scans SET human_intervention_notes='synthetic later note';")
    later = q.execute('later_user_note_snapshot', SNAPSHOT)
    replay = q.execute('replay_after_later_user_note', 'BEGIN;' + ROLE + "SELECT public.test_complete_initial('replay'); COMMIT;")
    if replay != first or q.execute('replay_preserves_later_user_note', SNAPSHOT) != later:
        raise ValueError('replay rewrote historical projection or later user note')
    for action, revision in [('reject', 0), ('undo', 1)]:
        q.execute('later_review_' + action, 'BEGIN;' + ROLE
                  + "SELECT public.apply_scan_identification_review(user_id,id," + str(revision)
                  + ",gen_random_uuid(),'" + action + "',NULL,NULL," + str(revision)
                  + ",NULL,NULL) FROM public.scans; COMMIT;")
        reviewed = q.execute('later_review_' + action + '_snapshot', SNAPSHOT)
        replay = q.execute('replay_preserves_' + action, 'BEGIN;' + ROLE + "SELECT public.test_complete_initial('replay'); COMMIT;")
        if replay != first or q.execute('unchanged_after_' + action + '_replay', SNAPSHOT) != reviewed:
            raise ValueError('completion replay rewrote later review')
        state = q.execute('later_review_' + action + '_authority',
                          "SELECT ai_identification_review->>'state',ai_identification_review->>'revision',"
                          "confirmed_species_identity_revision,primary_identification IS NULL,"
                          "NOT EXISTS(SELECT 1 FROM public.scan_ingestion_jobs) FROM public.scans;")
        # The retained v1 fixture has no primary-identification envelope. Its
        # AI review advances independently; verified-species revision stays0.
        if state != ('ai_rejected' if action == 'reject' else 'clear') + '|' + str(revision + 1) + '|0|t|t':
            raise ValueError('later review lost its original authority or revision')
    for role in ['anon', 'authenticated', 'service_role']:
        q.execute('deny_private_completion_' + role,
                  'BEGIN; SET LOCAL ROLE ' + role + '; SELECT internal.complete_initial_analysis_legacy_v1(NULL,NULL,NULL,NULL,NULL); COMMIT;', '42501')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    parser.add_argument('--funding-mode', choices=['absent', 'complimentary'], default='absent')
    parser.add_argument('--media-vector', type=int, choices=range(7), default=0)
    parser.add_argument('--media-only', action='store_true', help='Run only original read-only preparation/media checks; omit already-qualified funding-prefix checks.')
    parser.add_argument('--complete', action='store_true', help='Exercise the private legacy completion producer, exact replay and actual scan-trigger events.')
    parser.add_argument('--journey-only', action='store_true', help='Run the completion journey after original setup; reuse existing preparation/prefix evidence.')
    parser.add_argument('--race-order', choices=['completion', 'cancellation'], help='Run one committed completion/C1 contention order after original setup.')
    parser.add_argument('--erase', action='store_true', help='With --journey-only, qualify completed-scan SQL erasure instead of the completion fault suite.')
    parser.add_argument('--primary-review', action='store_true', help='With --journey-only, select a synthetic primary result before admission and verify later species confirmation/clear.')
    parser.add_argument('--account-erase', action='store_true', help='After --journey-only, qualify selected completed-account SQL erasure and retained accounting.')
    parser.add_argument('--report-after', action='store_true', help='With --journey-only, commit completion before reporting original usage.')
    args = parser.parse_args()
    started = time.monotonic()
    q = Qualification(args.container, args.evidence_directory, 'initial-completion-preparation', args.replay_manifest)
    if (args.complete or args.journey_only or args.race_order) and (args.media_only or args.media_vector == 0):
        parser.error('--complete requires a legacy media vector and cannot use --media-only')
    if args.race_order and (args.complete or args.journey_only):
        parser.error('--race-order is a distinct bounded suite')
    if args.erase and not args.journey_only:
        parser.error('--erase requires --journey-only')
    if args.primary_review and (not args.journey_only or args.erase or args.account_erase or args.report_after):
        parser.error('--primary-review requires --journey-only without other journey modes')
    if args.account_erase and (not args.journey_only or args.erase):
        parser.error('--account-erase requires --journey-only without --erase')
    if args.report_after and (not args.journey_only or args.erase):
        parser.error('--report-after requires --journey-only without --erase')
    run(q, args.funding_mode, args.media_vector, args.media_only, args.complete, args.journey_only, args.race_order, args.erase, args.report_after, args.account_erase, args.primary_review)
    q.record['wall_seconds'] = time.monotonic() - started
    q.save()
    print(json.dumps({'passed': True, 'checks': len(q.record['checks'])}))


if __name__ == '__main__':
    main()
