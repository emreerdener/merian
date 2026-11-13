"""Synthetic primary-result completion through the existing verified review owner.

No taxonomy lookup, provider execution or compiled configuration is qualified.
The original dispatch chooses provenance before its first immutable write.
"""
from pathlib import Path


def run(q, snapshot, role):
    path = Path(__file__)
    q.record['source_manifest'][str(path.relative_to(path.resolve().parents[3]))] = q.digest(path)
    q.record['scope'] = 'Original synthetic primary result and private legacy completion through existing verified species confirmation/clear, stale denial and immutable completion replay. No external taxonomy/provider/compiled configuration/native qualification.'
    q.save()
    q.execute('original_primary_result_matches_completed_scan', """DO $$ BEGIN
 IF (SELECT count(*) FROM public.scans s JOIN internal.initial_analysis_results r ON r.scan_id=s.id
   JOIN internal.identification_invocations i ON i.id=(r.result_snapshot->>'invocation_id')::UUID
   WHERE s.primary_identification=r.result_snapshot#>'{data,primary_identification}'
    AND s.primary_identification->>'resolution'='species'
    AND s.primary_identification->>'scientific_name'='Danaus plexippus'
    AND i.provenance->>'schema'='merian_identify_primary_v1'
    AND s.identification_provenance=i.provenance
    AND s.confirmed_species_identity_revision=0 AND s.confirmed_species_identity IS NULL)<>1
 OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs)
 THEN RAISE EXCEPTION USING ERRCODE='ZX850'; END IF;
END $$;""")
    original = q.execute('original_primary_completion_receipt', 'BEGIN;' + role + "SELECT public.test_complete_initial('replay'); COMMIT;")
    confirm = "SELECT public.apply_verified_scan_species_review(user_id,id,0,'confirm_primary','Danaus plexippus','{\"scientific_name\":\"Danaus plexippus\",\"gbif_taxon_key\":987600101,\"rank\":\"SPECIES\",\"status\":\"ACCEPTED\",\"kingdom\":\"Animalia\"}') FROM public.scans;"
    first = q.execute('confirm_original_primary_species', 'BEGIN;' + role + confirm + 'COMMIT;')
    repeated = q.execute('repeat_original_primary_confirmation', 'BEGIN;' + role + confirm + 'COMMIT;')
    if first != repeated:
        raise ValueError('exact primary confirmation retry changed receipt')
    q.execute('primary_confirmation_uses_existing_authority', """DO $$ BEGIN
 IF (SELECT count(*) FROM public.scans s JOIN public.species_dictionary d ON d.id=s.confirmed_species_id
  WHERE s.confirmed_species_identity_revision=1 AND s.user_confirmed_identification
   AND s.user_review_state='ai_confirmed' AND d.gbif_taxon_key=987600101
   AND s.confirmed_species_identity->>'scientific_name'='Danaus plexippus'
   AND s.primary_identification->>'scientific_name'='Danaus plexippus')<>1
 OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs)
 THEN RAISE EXCEPTION USING ERRCODE='ZX851'; END IF;
END $$;""")
    for state in ['confirmed', 'cleared']:
        if state == 'cleared':
            q.execute('clear_original_primary_confirmation', 'BEGIN;' + role + "SELECT public.apply_verified_scan_species_review(user_id,id,1,'clear',NULL,NULL) FROM public.scans; COMMIT;")
            q.execute('primary_clear_advances_revision', """DO $$ BEGIN
 IF (SELECT count(*) FROM public.scans WHERE confirmed_species_identity_revision=2
  AND confirmed_species_identity IS NULL AND confirmed_species_id IS NULL)<>1
 THEN RAISE EXCEPTION USING ERRCODE='ZX852'; END IF;
END $$;""")
        before = q.execute('primary_' + state + '_snapshot', snapshot)
        replay = q.execute('completion_preserves_primary_' + state, 'BEGIN;' + role + "SELECT public.test_complete_initial('replay'); COMMIT;")
        if replay != original or q.execute('primary_' + state + '_unchanged_after_replay', snapshot) != before:
            raise ValueError('completion replay changed immutable completion or later primary review')
        stale = confirm if state == 'cleared' else "SELECT public.apply_verified_scan_species_review(user_id,id,0,'clear',NULL,NULL) FROM public.scans;"
        q.execute('primary_' + state + '_rejects_stale_revision', 'BEGIN;' + role + stale + 'COMMIT;', '40001')
        if q.execute('primary_' + state + '_unchanged_after_stale', snapshot) != before:
            raise ValueError('stale primary review changed completed scope')
