"""Private deferred completion regressions on a fresh owned disposable replay.

Explicit privileged rollback function seams isolate deferred validation from
synchronous checks. They do not claim administrator-proof authentication or
installed execution. Every domain operation remains synthetic and provider-free.
"""
import argparse
from pathlib import Path
from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_test_support import Qualification, ROOT

EXECUTOR = 'internal.execute_initial_media_handoff_stage(uuid)'
COMPLETION = 'internal.require_initial_media_handoff_completion()'
FLUSH = '    SET CONSTRAINTS ALL IMMEDIATE;'
FINAL = '    PERFORM internal.assert_initial_media_handoff_poststate(stage);'
DELETE = '    DELETE FROM internal.initial_media_handoff_staging WHERE scan_id=p_scan;'
STAGE = "    stage:=CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;"


def seam(signature, needle, replacement):
    # All fragments are fixed repository source, never operation inputs.
    return "DO $patch$ DECLARE source TEXT; needle TEXT:=$needle$" + needle + "$needle$; BEGIN source:=pg_get_functiondef('" + signature + "'::REGPROCEDURE); IF (length(source)-length(replace(source,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX762'; END IF; EXECUTE replace(source,needle,$replacement$" + replacement + "$replacement$); END $patch$;"


def cases(q):
    fixture = AdmissionFixture(q)
    original = q.execute('retain_exact_executor', "SELECT pg_get_functiondef('" + EXECUTOR + "'::REGPROCEDURE);")
    try:
        def check(label, patches='', body=None, expected=None, commit=False):
            a = fixture.admit_one()
            select = "SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';"
            owner = 'PERFORM * FROM internal.begin_initial_media_copy_v2(r.owner_id,r.scan_id,r.receipt_digest);'
            stage = "INSERT INTO internal.initial_media_handoff_staging(scan_id,owner_id,action,admission_digest) VALUES(r.scan_id,r.owner_id,'start_copy',r.receipt_digest);"
            operation = (body or owner).replace('$stage', stage)
            sql = "BEGIN;SET LOCAL statement_timeout='45s';UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;" + patches + 'DO $$ DECLARE r internal.initial_preparation_admission_receipts; BEGIN ' + select + operation + ' END $$;' + ('COMMIT;' if commit else 'ROLLBACK;')
            try:
                q.execute(label, sql, expected)
            finally:
                # A successful deferred-COMMIT seam commits its temporary owner
                # definition too; restore it before any subsequent operation.
                if commit:
                    q.execute('restore_exact_executor_' + label, original)
                q.execute('restore_inactive_' + label, 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            q.execute('original_c1_' + label, "BEGIN;SET LOCAL ROLE service_role;SELECT public.cancel_initial_analysis('" + a.owner_id + "','" + a.scan_id + "');COMMIT;")

        check('unfinished_force_immediate', body='$stage SET CONSTRAINTS ALL IMMEDIATE;', expected='55000')
        check('normal_executor_forced_flush')
        check('normal_deferred_commit', seam(EXECUTOR, FLUSH, ''), commit=True)
        # Corrupt the physical result only after all synchronous stage checks.
        # The final explicit assertion becomes a distinct tripwire: 55000 must
        # originate in the deferred terminal DELETE, before that tripwire.
        corrupt = DELETE + "\nSET LOCAL session_replication_role='replica';UPDATE internal.initial_media_copy_progress SET copy_adapter_digest=repeat('f',64) WHERE scan_id=p_scan;SET LOCAL session_replication_role='origin';"
        check('deferred_delete_rejects_changed_poststate', seam(EXECUTOR, DELETE, corrupt) + seam(EXECUTOR, FINAL, "RAISE EXCEPTION USING ERRCODE='ZX763';"), expected='55000')
        # Change only the local DELETE witness in the deferred trigger. This
        # bypasses earlier synchronous validation explicitly, not silently.
        for label, damage in [
            ('frozen_ledger', "stage.frozen:='[]'::JSONB;"),
            ('cleanup_cursor', 'stage.cleanup_cursor:=0;'),
            ('final_expiry', 'stage.cutoff_ms:=stage.authorized_at_ms;'),
        ]:
            check('deferred_delete_rejects_' + label, seam(COMPLETION, STAGE, STAGE + "\nIF TG_OP='DELETE' THEN " + damage + ' END IF;'), expected='55000')
        check('rolled_back_delete_restores_unfinished_guard', seam(EXECUTOR, FLUSH, ''), body="$stage BEGIN PERFORM internal.execute_initial_media_handoff_stage(r.scan_id);RAISE EXCEPTION USING ERRCODE='ZX764';EXCEPTION WHEN SQLSTATE 'ZX764' THEN NULL;END;SET CONSTRAINTS ALL IMMEDIATE;", expected='55000')
    finally:
        fixture.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-completion', args.replay_manifest)
    q.record['source_manifest'][str(Path(__file__).resolve().relative_to(ROOT))] = q.digest(Path(__file__))
    q.record['scope'] = 'Eight deferred-completion regressions: unfinished immediate, normal forced flush/deferred commit, poststate/frozen ledger/cursor/expiry rejection and rolled-back deletion. Privileged function seams explicitly isolate final validation; no physical I/O or 5s performance qualification.'
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()
