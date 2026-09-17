-- PostgreSQL 17 read-only measurement. Run twice, 15 minutes apart, using an
-- already configured authenticated psql connection. Never reset statistics.
-- Each output line is JSON; no SQL text, credentials, or response bodies.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned
BEGIN READ ONLY;
SET LOCAL statement_timeout = '5s';
SET LOCAL lock_timeout = '1s';
SET LOCAL search_path = pg_catalog, extensions;
SET LOCAL stats_fetch_consistency = 'snapshot';

SELECT jsonb_build_object('section', 'context', 'captured_at', clock_timestamp(),
    'server_version_num', current_setting('server_version_num'),
    'postmaster_started_at', pg_postmaster_start_time(),
    'track_io_timing', current_setting('track_io_timing'),
    'statement_tracking', current_setting('pg_stat_statements.track', true),
    'database_stats_reset', stats_reset)
FROM pg_stat_database WHERE datname = current_database();

SELECT jsonb_build_object('section', 'statement_reset', 'captured_at', clock_timestamp(),
    'stats_reset', stats_reset, 'deallocations', dealloc)
FROM pg_stat_statements_info;

SELECT jsonb_build_object('section', 'database', 'captured_at', clock_timestamp(),
    'commits', xact_commit, 'rollbacks', xact_rollback,
    'blocks_read', blks_read, 'blocks_hit', blks_hit,
    'tuples_returned', tup_returned, 'tuples_fetched', tup_fetched,
    'tuples_inserted', tup_inserted, 'tuples_updated', tup_updated, 'tuples_deleted', tup_deleted,
    'temp_files', temp_files, 'temp_bytes', temp_bytes, 'deadlocks', deadlocks,
    'block_read_ms', blk_read_time, 'block_write_ms', blk_write_time)
FROM pg_stat_database WHERE datname = current_database();

SELECT jsonb_build_object('section', 'table', 'captured_at', clock_timestamp(),
    'schema', schemaname, 'relation', relname,
    'inserted', n_tup_ins, 'updated', n_tup_upd, 'deleted', n_tup_del,
    'hot_updated', n_tup_hot_upd, 'live_estimate', n_live_tup, 'dead_estimate', n_dead_tup,
    'seq_scans', seq_scan, 'seq_tuples_read', seq_tup_read,
    'index_scans', idx_scan, 'index_tuples_fetched', idx_tup_fetch,
    'vacuums', vacuum_count, 'autovacuums', autovacuum_count)
FROM pg_stat_all_tables
WHERE schemaname IN ('public', 'internal', 'net', 'cron')
ORDER BY schemaname, relname;

-- Group roles together; retain every query ID, not just a changing top-N list.
-- Keep toplevel separate to avoid double-counting nested statements.
SELECT jsonb_build_object('section', 'statement', 'captured_at', clock_timestamp(),
    'query_id', queryid::text, 'toplevel', toplevel,
    'calls', sum(calls), 'execution_ms', sum(total_exec_time), 'rows', sum(rows),
    'shared_hits', sum(shared_blks_hit), 'shared_reads', sum(shared_blks_read),
    'shared_dirtied', sum(shared_blks_dirtied), 'shared_written', sum(shared_blks_written),
    'local_reads', sum(local_blks_read), 'local_written', sum(local_blks_written),
    'temp_reads', sum(temp_blks_read), 'temp_written', sum(temp_blks_written),
    'wal_records', sum(wal_records), 'wal_fpi', sum(wal_fpi), 'wal_bytes', sum(wal_bytes))
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY queryid, toplevel ORDER BY queryid, toplevel;

-- These system views contain counters and backend categories, never SQL text.
SELECT jsonb_build_object('section', 'wal', 'captured_at', clock_timestamp(), 'counters', to_jsonb(stat))
FROM pg_stat_wal AS stat;
SELECT jsonb_build_object('section', 'io', 'captured_at', clock_timestamp(), 'counters', to_jsonb(stat))
FROM pg_stat_io AS stat;

SELECT jsonb_build_object('section', 'media_runs_15m', 'captured_at', clock_timestamp(),
    'window_start', now() - interval '15 minutes', 'window_end', now(),
    'status', status, 'runs', count(*), 'claimed', sum(claimed_count),
    'healthy', sum(healthy_count), 'missing_observations', sum(missing_observation_count),
    'retryable', sum(retryable_error_count), 'errors', sum(error_count))
FROM public.explore_media_health_reconciliation_runs
WHERE started_at >= now() - interval '15 minutes' AND started_at < now()
GROUP BY status ORDER BY status;

SELECT jsonb_build_object('section', 'media_backlog', 'captured_at', clock_timestamp(),
    'eligible_due', count(*),
    'oldest_due_seconds', extract(epoch FROM now() - min(media.next_health_check_at)))
FROM public.explore_post_media AS media
JOIN public.explore_posts AS post ON post.id = media.post_id
JOIN public.scans AS scan ON scan.id = post.scan_id
LEFT JOIN internal.explore_media_health_check_claims AS claim
    ON claim.media_id = media.id AND claim.claimed_until > now()
WHERE post.unshared_at IS NULL AND post.moderated_at IS NULL AND NOT scan.is_tombstoned
    AND media.next_health_check_at <= now() AND claim.media_id IS NULL;
ROLLBACK;
