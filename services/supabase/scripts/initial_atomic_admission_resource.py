"""Local resource-boundary qualification with a distinct synthetic budget.

The dedicated 240-second measurement observer is intentionally separate from
short actor sessions. Wall times include fixture/transport/projection overhead;
memory samples are before/after context totals, never peak RSS.
"""
import copy
import datetime
import hashlib
import json
import queue
import re
import shutil
import subprocess
import threading
import time
import uuid
from initial_atomic_admission_sessions import BASE, RELATIONS, PROJECTION
from initial_atomic_admission_test_support import ROOT


def resource_cases(qualification):
    root = ROOT
    record = qualification.record
    cmd = qualification.command
    s = {'container': record['container']}
    base, relations, projection = BASE, RELATIONS, PROJECTION
    peers, handled, phase = [], set(), 'setup'
    record['started_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    save = qualification.save

    def send(process, sql):
        process.stdin.write(sql + '\n')
        process.stdin.flush()
    cancel = 'DO $$ DECLARE r internal.initial_preparation_admission_receipts;answer JSONB;before_owner JSONB;other_users JSONB;old_terminals JSONB;life JSONB;sf JSONB;df JSONB;sr JSONB;dr JSONB;BEGIN\n SELECT * INTO STRICT r FROM target;\n SELECT to_jsonb(u) INTO STRICT before_owner FROM public.users u WHERE id=r.owner_id;\n SELECT jsonb_agg(to_jsonb(u) ORDER BY id) INTO other_users FROM public.users u WHERE id<>r.owner_id;\n SELECT jsonb_agg(to_jsonb(c) ORDER BY scan_id) INTO old_terminals FROM internal.initial_analysis_cancellations c WHERE scan_id<>r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'cancelled_pre_dispatch\') INTO STRICT life FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'retired\') INTO STRICT sf FROM internal.initial_preparation_source_fences t WHERE scan_id=r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'retired\') INTO STRICT df FROM internal.initial_analysis_media_allocation_fences t WHERE scan_id=r.scan_id;\n SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object(\'retired\',TRUE) ORDER BY object_id) INTO sr FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id;\n SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object(\'retired\',TRUE) ORDER BY object_id) INTO dr FROM internal.initial_analysis_media_registry t WHERE scan_id=r.scan_id;\n SET LOCAL ROLE service_role;answer:=public.cancel_initial_analysis(r.owner_id,r.scan_id);RESET ROLE;\n IF answer IS DISTINCT FROM \'{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}\'::JSONB\n OR (SELECT to_jsonb(u) FROM public.users u WHERE id=r.owner_id) IS DISTINCT FROM before_owner||jsonb_build_object(\'complimentary_entitlement_epoch\',(before_owner->>\'complimentary_entitlement_epoch\')::BIGINT+1,\'entitlement_version\',(before_owner->>\'entitlement_version\')::BIGINT+1)\n OR (SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM public.users u WHERE id<>r.owner_id) IS DISTINCT FROM other_users\n OR (SELECT jsonb_agg(to_jsonb(c) ORDER BY scan_id) FROM internal.initial_analysis_cancellations c WHERE scan_id<>r.scan_id) IS DISTINCT FROM old_terminals\n OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=r.scan_id AND user_id=r.owner_id AND state=\'refunded\' AND refund_count=1)\n OR NOT EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=r.scan_id AND user_id=r.owner_id AND state=\'released\' AND settlement_reason=\'cancelled_before_dispatch\' AND settled_at IS NOT NULL AND settled_at=updated_at)\n OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=r.scan_id AND owner_id=r.owner_id AND dispatch=\'dispatch_prevented\')\n OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters l JOIN internal.ai_quota_reservations q ON q.id=l.reservation_id WHERE q.original_analysis_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR EXISTS(SELECT 1 FROM internal.initial_analysis_results) OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions)\n OR (SELECT to_jsonb(t) FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM life\n OR (SELECT to_jsonb(t) FROM internal.initial_preparation_source_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM sf\n OR (SELECT to_jsonb(t) FROM internal.initial_analysis_media_allocation_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM df\n OR sr IS NULL OR dr IS NULL\n OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id) IS DISTINCT FROM sr\n OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_analysis_media_registry t WHERE scan_id=r.scan_id) IS DISTINCT FROM dr\n OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=r.scan_id)\n OR NOT internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE=\'ZX537\';END IF;\n PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);\nEND $$;\n'

    def selected_start(scan):
        return base + "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + scan + "';DO $$ BEGIN IF (SELECT count(*) FROM target)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX591';END IF;END $$;"

    peer_tables = {'public.scans': 'id', 'internal.initial_preparation_admission_receipts': 'scan_id', 'internal.initial_analysis_submissions': 'scan_id', 'internal.initial_analysis_preparation_intents': 'scan_id', 'internal.initial_analysis_admissions': 'scan_id', 'internal.initial_analysis_lifecycle_fences': 'scan_id', 'internal.initial_analysis_cancellations': 'scan_id', 'internal.complimentary_scan_usage': 'client_scan_id', 'internal.identification_invocations': 'scan_id', 'internal.initial_preparation_source_fences': 'scan_id', 'internal.initial_analysis_media_allocation_fences': 'scan_id', 'internal.initial_analysis_operation_fences': 'scan_id', 'internal.initial_preparation_source_registry': 'scan_id', 'internal.initial_analysis_media_registry': 'scan_id', 'internal.initial_analysis_results': 'scan_id', 'internal.initial_analysis_completions': 'scan_id'}

    peer_parts = ["(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + table + ' t WHERE ' + field + '<>(SELECT scan_id FROM target))' for (table, field) in peer_tables.items()]

    peer_parts += ["(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + table + ' t WHERE ' + field + '<>(SELECT q.id FROM internal.ai_quota_reservations q JOIN target r ON q.original_analysis_id=r.scan_id))' for (table, field) in [('internal.ai_quota_reservations', 'id'), ('internal.ai_quota_reservation_counters', 'reservation_id'), ('internal.identification_provider_attempts', 'reservation_id')]]

    peer_projection = 'jsonb_build_array(' + ','.join(peer_parts) + ')'

    counter_projection = "(SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY to_jsonb(c)::TEXT),'[]'::JSONB) FROM internal.ai_quota_counters c)"

    prepare = "CREATE TEMP TABLE original_links AS SELECT l.* FROM internal.ai_quota_reservation_counters l JOIN internal.ai_quota_reservations q ON q.id=l.reservation_id JOIN target r ON r.scan_id=q.original_analysis_id;\nCREATE TEMP TABLE before_counters AS SELECT c.*,EXISTS(SELECT 1 FROM original_links l WHERE (l.scope_type,l.scope_key,l.bucket,l.window_start)=(c.scope_type,c.scope_key,c.bucket,c.window_start)) AS charged FROM internal.ai_quota_counters c;\nCREATE TEMP TABLE expected_counters AS SELECT CASE WHEN charged THEN (to_jsonb(c)-'charged')||jsonb_build_object('request_count',request_count-1,'updated_at',transaction_timestamp()) ELSE to_jsonb(c)-'charged' END AS value FROM before_counters c WHERE NOT charged OR request_count>1;\nCREATE TEMP TABLE peer_before AS SELECT PEER value;\nDO $$ BEGIN IF (SELECT count(*) FROM original_links)<>3 OR (SELECT count(*) FROM before_counters WHERE charged)<>3 OR EXISTS(SELECT 1 FROM before_counters WHERE charged AND request_count<1) THEN RAISE EXCEPTION USING ERRCODE='ZX592';END IF;END $$;\n".replace('PEER', peer_projection)

    def check_after(expected_shared, expected_unlinked):
        return "DO $$ DECLARE actual JSONB;expected JSONB;BEGIN SELECT COALESCE(jsonb_agg(value ORDER BY value::TEXT),'[]'::JSONB) INTO expected FROM expected_counters;actual:=" + counter_projection + ';IF actual IS DISTINCT FROM expected OR (SELECT value FROM peer_before) IS DISTINCT FROM ' + peer_projection + ' OR (SELECT count(*) FROM before_counters WHERE charged AND request_count>1)<>' + str(expected_shared) + ' OR (SELECT count(*) FROM before_counters WHERE NOT charged)<>' + str(expected_unlinked) + " THEN RAISE EXCEPTION USING ERRCODE='ZX593';END IF;END $$;"

    error_observers = {}

    def peer(label):
        p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        q = queue.Queue()
        observation = {'sqlstates': [], 'error_owners': [], 'phases': [], 'warning_count': 0, 'budgets': [], 'observer_invalid': False, 'counter_topology': []}

        def drain():
            for line in p.stderr:
                observation['warning_count'] += int('WARNING:' in line)
                observation['sqlstates'] += re.findall('(?:ERROR|FATAL):\\s+([0-9A-Z]{5})', line)
                observation['error_owners'] += re.findall('PL/pgSQL function ([A-Za-z0-9_.]+)', line)
                match = re.search('NOTICE:\\s+(?:[0-9A-Z]{5}:\\s+)?RESOURCE_PHASE:([a-z_]+):([0-9.]+)', line)
                if match:
                    observation['phases'].append({'phase': match[1], 'epoch_ms': float(match[2])})
                topology = re.search('NOTICE:\\s+(?:[0-9A-Z]{5}:\\s+)?RESOURCE_TOPOLOGY:([0-3]):([0-3])', line)
                if topology:
                    observation['counter_topology'].append({'shared': int(topology[1]), 'unlinked': int(topology[2])})
                    if int(topology[1]) + int(topology[2]) != 3:
                        observation['observer_invalid'] = True
                budget = re.search('NOTICE:\\s+(?:[0-9A-Z]{5}:\\s+)?RESOURCE_BUDGET:(\\{.*\\})$', line.strip())
                if budget:
                    try:
                        value = json.loads(budget[1])
                        keys = {'anchor_ms', 'admission_cutoff_ms', 'original_expires_at_ms', 'cohort_wall_ms', 'admission_ms', 'total_ms'}
                        if set(value) != keys or any((type(v) is not int for v in value.values())):
                            raise ValueError()
                        if value['admission_ms'] != 140000 or value['total_ms'] != 210000 or value['admission_cutoff_ms'] - value['anchor_ms'] != 140000 or (45000 + value['cohort_wall_ms'] + value['total_ms'] >= 300000) or (value['anchor_ms'] + value['total_ms'] >= value['original_expires_at_ms']) or (not 0 < value['original_expires_at_ms'] - value['anchor_ms'] <= 300000):
                            raise ValueError()
                        observation['budgets'].append(value)
                    except Exception:
                        observation['observer_invalid'] = True
        thread = threading.Thread(target=drain, daemon=True)
        thread.start()
        error_observers[id(p)] = (observation, thread)
        threading.Thread(target=lambda : [q.put(x.strip()) for x in p.stdout], daemon=True).start()
        peers.append((p, label))
        send(p, 'SELECT pg_backend_pid();')
        pid = int(q.get(timeout=5))
        record.setdefault('backend_correlation', []).append({'backend_pid': pid, 'statement_label': label})
        return (p, q, pid)

    def error_result(p, label):
        (observation, thread) = error_observers[id(p)]
        thread.join(timeout=5)
        if thread.is_alive():
            raise RuntimeError('stderr_observer_incomplete')
        return {'statement_label': label, 'exit_code': p.returncode, **observation}

    def close(p, label):
        send(p, '\\q')
        p.wait(timeout=5)
        value = error_result(p, label)
        record.setdefault('backend_results', []).append(value)
        handled.add(id(p))
        if value['exit_code'] or value['sqlstates'] or value['warning_count'] or value['observer_invalid']:
            raise RuntimeError('resource_backend_failure')

    record['scope'] = 'Local complete privileged synthetic admission with five-source video/audio metadata and large canonical supporting text, actual service-role C1; no media blobs, provider, worker, HTTP, installed or device qualification.'

    record['resource_method'] = 'Wall duration around serialized database operations; pg_backend_memory_contexts total_bytes before/after statements. These snapshots are neither exact peak memory nor media/worker resource measurements; fixture/psql transport included in wall duration.'

    record['measurements'] = []

    record['inputs'] = []

    record['media_fixture_sha256'] = hashlib.sha256((root / 'services/supabase/functions/_shared/initialAnalysis/fixtures/media-lifecycle-v2.json').read_bytes()).hexdigest()

    def measured_inner(p, q, label, sql):
        stamp = time.monotonic()
        send(p, "SELECT 'RESOURCE:'||jsonb_build_object('phase','before','backend_memory_context_bytes',(SELECT sum(total_bytes) FROM pg_backend_memory_contexts))::TEXT;" + sql + "SELECT 'RESOURCE:'||jsonb_build_object('phase','after','backend_memory_context_bytes',(SELECT sum(total_bytes) FROM pg_backend_memory_contexts))::TEXT;SELECT 'RESOURCE_DONE';")
        deadline = time.monotonic() + 240
        samples = []
        while True:
            try:
                line = q.get(timeout=min(0.25, max(0.01, deadline - time.monotonic())))
            except queue.Empty:
                if p.poll() is not None:
                    raise RuntimeError('resource_backend_exited')
                if time.monotonic() > deadline:
                    raise RuntimeError('resource_statement_timeout')
                continue
            if line == 'RESOURCE_DONE':
                break
            if line.startswith('RESOURCE:'):
                value = json.loads(line[len('RESOURCE:'):])
                assert set(value) <= {'phase', 'backend_memory_context_bytes', 'candidate_bytes', 'input_bytes', 'assignment_bytes', 'receipt_row_bytes', 'source_count', 'destination_count', 'profile_digest', 'candidate_sha256', 'input_digest'}
                samples.append(value)
            if time.monotonic() > deadline:
                raise RuntimeError('resource_statement_timeout')
        expected_phases = ['before', 'admitted', 'after'] if label.endswith('_admit') else ['before', 'after']
        if [v.get('phase') for v in samples] != expected_phases:
            raise RuntimeError('missing_or_unordered_resource_samples')
        for value in samples:
            if value['phase'] in ['before', 'after']:
                if set(value) != {'phase', 'backend_memory_context_bytes'} or type(value['backend_memory_context_bytes']) is not int or value['backend_memory_context_bytes'] < 0:
                    raise RuntimeError('invalid_memory_observation')
            else:
                if set(value) != {'phase', 'candidate_bytes', 'input_bytes', 'receipt_row_bytes', 'source_count', 'destination_count', 'candidate_sha256', 'input_digest'}:
                    raise RuntimeError('invalid_admitted_metric_shape')
                if any((type(value[k]) is not int or value[k] <= 0 for k in ['candidate_bytes', 'input_bytes', 'receipt_row_bytes', 'source_count', 'destination_count'])) or value['candidate_bytes'] > 1048576 or value['input_bytes'] > 1048576 or (value['source_count'] != 5) or (value['destination_count'] != 6):
                    raise RuntimeError('invalid_admitted_metric_counts')
                if any((not isinstance(value[k], str) or not re.fullmatch('[0-9a-f]{64}', value[k]) for k in ['candidate_sha256', 'input_digest'])):
                    raise RuntimeError('invalid_admitted_metric_digest')
        record['measurements'].append({'case': label, 'wall_seconds': round(time.monotonic() - stamp, 6), 'snapshots': samples})
        record['checks'].append({'case': label, 'passed': True})
        save()

    def measured(p, q, label, sql):
        stamp = time.monotonic()
        previous = len(error_observers[id(p)][0]['budgets'])
        previous_topology = len(error_observers[id(p)][0]['counter_topology'])
        try:
            result = measured_inner(p, q, label, sql)
            if label.endswith('_admit') or label == 'commit_small_peer':
                observation = error_observers[id(p)][0]
                if len(observation['budgets']) != previous + 1 or observation['observer_invalid'] or observation['budgets'][-1]['cohort_wall_ms'] != (2000 if label == 'commit_small_peer' else 10000):
                    raise RuntimeError('missing_or_invalid_actual_budget')
            if label.endswith('_cancel'):
                observation = error_observers[id(p)][0]
                if len(observation['counter_topology']) != previous_topology + 1 or observation['observer_invalid']:
                    raise RuntimeError('missing_or_invalid_counter_topology')
            return result
        except Exception:
            record.setdefault('failed_measurements', []).append({'case': label, 'wall_seconds': round(time.monotonic() - stamp, 6)})
            save()
            raise

    def cohort(frames=3, large=False):
        data = json.loads((root / 'services/supabase/functions/_shared/initialAnalysis/fixtures/media-lifecycle-v2.json').read_text())
        c = copy.deepcopy(next((v['candidate'] for v in data['valid'] if v['name'] == 'video audio')))
        (frame, audio, video) = c['source_plan']['sources']
        images = []
        for i in range(frames):
            f = copy.deepcopy(frame)
            f.update(input_index=i, frame_index=i, source_byte_count=5242880 // frames + (i < 5242880 % frames) if large else 68)
            images.append(f)
        audio['source_byte_count'] = 2700000 if large else 32044
        video['source_byte_count'] = 12582912 if large else 24
        c['source_plan']['sources'] = images + [audio, video]
        c['source_plan']['owner_timeline'] = [{'kind': 'media', 'index': frames + 1}]
        c['source_plan']['capture'].update(declared_video_frame_count=frames, video_inference_frame_count=frames)
        return c

    def projected(c):
        plan = copy.deepcopy(c['source_plan'])
        media = []
        for source in plan.pop('sources'):
            item = copy.deepcopy(source)
            item.pop('prepared_output')
            item.update(content_type=source['source_content_type'], byte_count=32 if source['kind'] == 'audio' else source['source_byte_count'], sha256='7' * 64 if source['kind'] == 'audio' else source['source_sha256'])
            media.append(item)
        plan['media'] = media
        return plan

    def padded(escaped):

        def with_units(units):
            c = cohort()
            values = []
            symbol = chr(128998) if escaped == 'non_bmp' else '\x01' if escaped else 'a'
            while units:
                take = min(units, 10000 if escaped else 65000)
                values.append('x' + symbol * take + 'x')
                units -= take
            c['source_plan']['ordered_descriptions'] = values
            c['source_plan']['owner_timeline'] = [{'kind': 'media', 'index': 4}] + [{'kind': 'description', 'index': i} for i in range(len(values))]
            return c
        (low, high) = (0, 1048576)
        while low < high:
            mid = (low + high + 1) // 2
            if len(canonical(projected(with_units(mid))).encode()) <= 1048576:
                low = mid
            else:
                high = mid - 1
        c = with_units(low)
        remaining = 1048576 - len(canonical(projected(c)).encode())
        c['source_plan']['ordered_descriptions'][-1] += 'a' * remaining
        assert len(canonical(projected(c)).encode()) == 1048576 and len(canonical(c).encode()) <= 1048576
        return c

    def canonical(c):
        return json.dumps(c, sort_keys=True, ensure_ascii=False, separators=(',', ':'))

    def replace_vector(c):
        value = canonical(c)
        assert '$resource_input$' not in value
        return "UPDATE media_vectors SET v=jsonb_set(v,'{candidate}',$resource_input$" + value + '$resource_input$::JSONB) WHERE i=6;'

    def receipt_metrics(scan, c):
        expected_bytes = len(canonical(projected(c)).encode())
        expected_digest = hashlib.sha256(('merian.initial-analysis.input.v1\n' + canonical(projected(c))).encode()).hexdigest()
        return "DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + scan + "' AND octet_length(input)=" + str(expected_bytes) + " AND internal.initial_digest('input',input)='" + expected_digest + "' AND jsonb_array_length(candidate::JSONB#>'{source_plan,sources}')=5) THEN RAISE EXCEPTION USING ERRCODE='ZX703';END IF;END $$;SELECT 'RESOURCE:'||jsonb_build_object('phase','admitted','candidate_bytes',octet_length(candidate),'input_bytes',octet_length(input),'receipt_row_bytes',pg_column_size(t),'source_count',jsonb_array_length(candidate::JSONB#>'{source_plan,sources}'),'destination_count',(SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id=t.scan_id),'candidate_sha256',encode(extensions.digest(candidate,'sha256'),'hex'),'input_digest',internal.initial_digest('input',input))::TEXT FROM internal.initial_preparation_admission_receipts t WHERE scan_id='" + scan + "';"

    rollback_relations = relations + ['internal.initial_preparation_source_mapping', 'internal.initial_preparation_source_verifications', 'internal.initial_preparation_execution_grants', 'internal.initial_preparation_output_manifests', 'internal.initial_preparation_output_mapping', 'internal.initial_preparation_outcomes', 'internal.initial_preparation_admission_staging', 'internal.initial_preparation_admission_writes']

    rollback_projection = 'jsonb_build_array(' + ','.join(("(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in rollback_relations)) + ')'

    def private_live(scan):
        expected = {'initial_analysis_preparation_intents': 1, 'initial_preparation_source_mapping': 5, 'initial_preparation_source_verifications': 1, 'initial_preparation_execution_grants': 1, 'initial_preparation_output_manifests': 1, 'initial_preparation_output_mapping': 4, 'initial_preparation_outcomes': 1, 'initial_preparation_admission_staging': 0, 'initial_preparation_admission_writes': 0}
        conditions = ['(SELECT count(*) FROM internal.' + table + " WHERE scan_id='" + scan + "')<>" + str(count) for (table, count) in expected.items()]
        checks = 'DO $$ DECLARE a JSONB;actual JSONB;expected JSONB;BEGIN IF ' + ' OR '.join(conditions) + " THEN RAISE EXCEPTION USING ERRCODE='ZX707';END IF;SELECT canonical_assignment::JSONB INTO STRICT a FROM internal.initial_analysis_preparation_intents WHERE scan_id='" + scan + "';SELECT jsonb_agg(jsonb_build_object('ordinal',ordinal,'object_id',object_id) ORDER BY ordinal) INTO actual FROM internal.initial_preparation_source_mapping WHERE scan_id='" + scan + "';SELECT jsonb_agg(jsonb_build_object('ordinal',x->'ordinal','object_id',x->'object_id') ORDER BY (x->>'ordinal')::INTEGER) INTO expected FROM jsonb_array_elements(a#>'{preparation,source_mapping}') x;IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION USING ERRCODE='ZX708';END IF;END $$;"
        return checks

    def counter_topology(peer_scan):
        return "CREATE TEMP TABLE resource_topology AS SELECT count(*) AS shared FROM original_links t JOIN internal.ai_quota_reservation_counters p USING(scope_type,scope_key,bucket,window_start) JOIN internal.ai_quota_reservations q ON q.id=p.reservation_id WHERE q.original_analysis_id='" + peer_scan + "';DO $$ BEGIN IF (SELECT count(*) FROM internal.ai_quota_reservation_counters l JOIN internal.ai_quota_reservations q ON q.id=l.reservation_id WHERE q.original_analysis_id='" + peer_scan + "')<>3 OR (SELECT shared FROM resource_topology) NOT BETWEEN 0 AND 3 THEN RAISE EXCEPTION USING ERRCODE='ZX709';END IF;RAISE NOTICE 'RESOURCE_TOPOLOGY:%:%',(SELECT shared FROM resource_topology),3-(SELECT shared FROM resource_topology);END $$;"

    def resource_counter_check():
        return check_after('(SELECT shared FROM resource_topology)', '(3-(SELECT shared FROM resource_topology))')

    def private_erased(scan):
        tables = ['internal.initial_preparation_source_mapping', 'internal.initial_preparation_source_verifications', 'internal.initial_preparation_execution_grants', 'internal.initial_preparation_output_manifests', 'internal.initial_preparation_output_mapping', 'internal.initial_preparation_outcomes', 'internal.initial_preparation_admission_staging', 'internal.initial_preparation_admission_writes']
        return 'DO $$ BEGIN IF ' + ' OR '.join(('EXISTS(SELECT 1 FROM ' + table + " WHERE scan_id='" + scan + "')" for table in tables)) + " THEN RAISE EXCEPTION USING ERRCODE='ZX704';END IF;END $$;"

    try:
        assert shutil.disk_usage(root).free >= 24 * 1024 ** 3
        (setup, owner, _) = qualification.fixture_prefix(held=True)
        scan = str(uuid.uuid4())
        seed = {'owner': owner, 'scan': scan, 'fixture': setup + qualification.admission_sql(owner, scan)}
        if seed['fixture'].count("'{phase_ms,admission}','60000'") != 1 or seed['fixture'].count("(h->>'total_ms')::INTEGER+50000") != 1:
            raise ValueError('unique resource synthetic budget seam required')
        seed['fixture'] = seed['fixture'].replace("'{phase_ms,admission}','60000'", "'{phase_ms,admission}','140000'").replace("(h->>'total_ms')::INTEGER+50000", "(h->>'total_ms')::INTEGER+130000")
        record['synthetic_budget'] = {'admission_ms': 140000, 'other_phase_sum_ms': 70000, 'total_ms': 210000, 'prior_60000_failure_retained': 'c1-resource-3.json', 'production_budget_qualified': False}
        (setup, admit) = seed['fixture'].split('DO $admit$', 1)
        admit = 'DO $admit$' + admit
        admit = admit.split('COMMIT;')[0]
        record['synthetic_fixture_sha256'] = hashlib.sha256(seed['fixture'].encode()).hexdigest()
        setup += 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;SET CONSTRAINTS ALL IMMEDIATE;COMMIT;'
        (setup_p, setup_q, _) = peer('resource_fixture_owner')
        measured(setup_p, setup_q, 'install_synthetic_profiles_gate_false', setup)
        peer_scan = str(uuid.uuid4())

        def admission(scan, vector):
            body = admit.replace(seed['scan'], scan).replace("media_create('" + scan + "',1)", "media_create('" + scan + "'," + str(vector) + ')')
            if vector == 6:
                body = body.replace("'vision_compat_v1'", "'multimodal_video_audio_v1'")
                expected = {'initial_preparation_source_mapping': 5, 'initial_preparation_source_verifications': 1, 'initial_preparation_execution_grants': 1, 'initial_preparation_output_manifests': 1, 'initial_preparation_output_mapping': 4, 'initial_preparation_outcomes': 1, 'initial_preparation_admission_staging': 1}
                conditions = ['(SELECT count(*) FROM internal.' + table + " WHERE scan_id='" + scan + "')<>" + str(count) for (table, count) in expected.items()]
                conditions.append("NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id='" + scan + "')")
                assertion = 'IF ' + ' OR '.join(conditions) + " THEN RAISE EXCEPTION USING ERRCODE='ZX705';END IF;"
                body = body.replace(' PERFORM internal.begin_initial_admission_consumption', assertion + ' PERFORM internal.begin_initial_admission_consumption')
            budget_notice = "RAISE NOTICE 'RESOURCE_BUDGET:%',jsonb_build_object('anchor_ms',s.phase_window::JSONB->'anchor_ms','admission_cutoff_ms',s.phase_window::JSONB#>'{cutoffs,admission}','original_expires_at_ms',s.phase_window::JSONB->'original_expires_at_ms','cohort_wall_ms',internal.initial_preparation_cohort_wall(s.assignment::JSONB,(SELECT canonical_profile::JSONB FROM internal.initial_preparation_profiles WHERE digest=s.assignment::JSONB#>>'{preparation,profile_digest}')),'admission_ms',s.assignment::JSONB#>'{handoff,profile,phase_ms,admission}','total_ms',s.assignment::JSONB#>'{handoff,profile,total_ms}'); "
            body = body.replace(" PERFORM set_config('merian.initial_admission_stage'", budget_notice + " PERFORM set_config('merian.initial_admission_stage'")
            for (name, needle) in [('create', 'PERFORM pg_temp.media_create'), ('preparation', 'PERFORM pg_temp.execution_advance'), ('stage', 'PERFORM internal.create_initial_admission_stage'), ('funding', 'PERFORM * FROM public.reserve_identification_quota'), ('materialize', 'PERFORM internal.materialize_initial_admission'), ('ledger', 'PERFORM internal.freeze_initial_admission_ledger'), ('consumption', 'PERFORM internal.begin_initial_admission_consumption'), ('finish', 'PERFORM internal.finish_initial_admission')]:
                body = body.replace(needle, "RAISE NOTICE 'RESOURCE_PHASE:" + name + ":%',floor(extract(epoch FROM clock_timestamp())*1000); " + needle)
            body = body.replace('END; $admit$;', "RAISE NOTICE 'RESOURCE_PHASE:complete:%',floor(extract(epoch FROM clock_timestamp())*1000); END; $admit$;")
            return body
        measured(setup_p, setup_q, 'commit_small_peer', base + 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;' + admission(peer_scan, 1) + 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;SET CONSTRAINTS ALL IMMEDIATE;COMMIT;')
        for (label, c) in [('five_small', cohort()), ('five_declared_max', cohort(large=True)), ('plain_input_cap', padded(False)), ('escaped_input_cap', padded(True)), ('non_bmp_input_cap', padded('non_bmp'))]:
            phase = label
            scan = str(uuid.uuid4())
            text = canonical(c)
            record['inputs'].append({'case': label, 'candidate_bytes': len(text.encode()), 'candidate_sha256': hashlib.sha256(text.encode()).hexdigest(), 'sources': len(c['source_plan']['sources'])})
            measured(setup_p, setup_q, label + '_admit', base + replace_vector(c) + 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;' + admission(scan, 6) + receipt_metrics(scan, c) + 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;SET CONSTRAINTS ALL IMMEDIATE;COMMIT;')
            (cp, cq, _) = peer(label + '_actual_service_c1')
            live = "DO $$ BEGIN IF (SELECT count(*) FROM internal.initial_analysis_submissions WHERE scan_id='" + scan + "')<>1 OR (SELECT count(*) FROM internal.initial_analysis_admissions WHERE scan_id='" + scan + "')<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX706';END IF;END $$;"
            measured(cp, cq, label + '_cancel', selected_start(scan) + live + private_live(scan) + prepare + counter_topology(peer_scan) + cancel + private_erased(scan) + resource_counter_check() + 'SET LOCAL ROLE service_role;SET CONSTRAINTS ALL IMMEDIATE;RESET ROLE;' + resource_counter_check() + private_erased(scan) + 'COMMIT;')
            close(cp, label + '_actual_service_c1')
            (rp, rq, _) = peer(label + '_original_replay')
            replay = base + 'DO $$ DECLARE a JSONB;b JSONB;BEGIN b:=' + projection + ";SET LOCAL ROLE service_role;a:=public.cancel_initial_analysis('" + seed['owner'] + "','" + scan + '\');RESET ROLE;IF a IS DISTINCT FROM \'{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}\'::JSONB OR b IS DISTINCT FROM ' + projection + " OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE initial_analysis_lifecycle_enabled) THEN RAISE EXCEPTION USING ERRCODE='ZX701';END IF;END $$;COMMIT;"
            measured(rp, rq, label + '_original_replay', replay)
            close(rp, label + '_original_replay')
        for (label, c, error, sqlstate) in [('fourth_frame', cohort(4), 'initial_analysis_preparation_unavailable', '55000'), ('plain_input_cap_plus_one', padded(False), 'initial_analysis_input_invalid', '22023'), ('escaped_input_cap_plus_one', padded(True), 'initial_analysis_input_invalid', '22023'), ('non_bmp_input_cap_plus_one', padded('non_bmp'), 'initial_analysis_input_invalid', '22023')]:
            if label != 'fourth_frame':
                c['source_plan']['ordered_descriptions'][-1] += 'a'
            text = canonical(c)
            phase = label
            rejected_scan = str(uuid.uuid4())
            record['inputs'].append({'case': label, 'candidate_bytes': len(text.encode()), 'projected_input_bytes': len(canonical(projected(c)).encode())})
            preparation = "PERFORM pg_temp.media_create('" + rejected_scan + "',6);"
            if label != 'fourth_frame':
                preparation += "PERFORM pg_temp.execution_advance('" + rejected_scan + "',4);PERFORM internal.create_initial_admission_stage('" + seed['owner'] + "','" + rejected_scan + "');"
            sql = base + replace_vector(c) + 'DO $$ DECLARE b JSONB;denied BOOLEAN:=FALSE;BEGIN b:=' + rollback_projection + ';BEGIN UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;' + preparation + "EXCEPTION WHEN SQLSTATE '" + sqlstate + "' THEN IF SQLERRM<>'" + error + "' THEN RAISE;END IF;denied:=TRUE;END;IF NOT denied OR b IS DISTINCT FROM " + rollback_projection + " OR EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE initial_analysis_lifecycle_enabled) THEN RAISE EXCEPTION USING ERRCODE='ZX702';END IF;END $$;SET CONSTRAINTS ALL IMMEDIATE;COMMIT;"
            measured(setup_p, setup_q, label + '_denied_without_business_mutation', sql)
        close(setup_p, 'resource_fixture_owner')
        (cp, cq, _) = peer('resource_peer_cleanup')
        measured(cp, cq, 'original_peer_cleanup', selected_start(peer_scan) + prepare + cancel + check_after(0, 0) + 'SET LOCAL ROLE service_role;SET CONSTRAINTS ALL IMMEDIATE;RESET ROLE;' + check_after(0, 0) + 'COMMIT;')
        close(cp, 'resource_peer_cleanup')
        record['resource_passed'] = True
    except Exception as ex:
        record['resource_passed'] = False
        record['failure_phase'] = phase
        record['error_category'] = type(ex).__name__
    finally:
        for (p, label) in peers:
            if p.poll() is None:
                try:
                    send(p, 'ROLLBACK;\\q')
                    p.wait(timeout=15)
                except Exception:
                    pass
            if p.poll() is not None and id(p) not in handled:
                record.setdefault('backend_failures', []).append(error_result(p, label))
        logs = subprocess.run(['docker', 'logs', '--since', record['started_at'], s['container']], text=True, capture_output=True)
        record['server_log_read_exit'] = logs.returncode
        raw = logs.stdout + logs.stderr
        deadlocks = len(re.findall('ERROR:.*deadlock detected', raw))
        record['server_deadlock_count'] = deadlocks
        if logs.returncode or deadlocks:
            record['resource_passed'] = False
        if deadlocks:
            record['deadlock_report'] = {'transaction_edges': [{'waiter': int(a), 'mode': b, 'transaction': int(c), 'blocker': int(d)} for (a, b, c, d) in re.findall('Process (\\d+) waits for ([A-Za-z]+) on transaction (\\d+); blocked by process (\\d+)', raw)], 'root_cause_established': False}
        save()
        if not record.get('resource_passed'):
            raise RuntimeError('resource qualification failed; see sanitized receipt')
