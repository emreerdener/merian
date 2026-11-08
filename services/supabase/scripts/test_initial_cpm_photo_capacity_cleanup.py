"""Fault injection for cleanup; no database or external process is used."""
import sys
import unittest

from test_initial_cpm_photo_capacity import finish_sessions


class SessionDouble:
    def __init__(self, name, events, fail=False):
        self.name, self.events, self.fail = name, events, fail

    def close(self):
        self.events.append(self.name)
        if self.fail:
            raise RuntimeError('synthetic close failure')


class ReceiptDouble:
    def __init__(self, events, fail=False):
        self.record, self.events, self.fail = {}, events, fail

    def execute(self, label, sql):
        self.events.append('restore')
        assert "lock_timeout='2s'" in sql and "statement_timeout='5s'" in sql
        if self.fail:
            raise RuntimeError('synthetic restoration failure')

    def save(self):
        self.events.append('save')


class CapacityCleanupTests(unittest.TestCase):
    def test_all_closures_and_restoration_after_one_failure(self):
        events = []
        q = ReceiptDouble(events)
        sessions = [SessionDouble('actor', events), SessionDouble('contender', events, True), SessionDouble('observer', events)]
        with self.assertRaisesRegex(RuntimeError, 'cleanup failed'):
            finish_sessions(q, sessions, None)
        self.assertEqual(events, ['observer', 'contender', 'actor', 'restore', 'save'])
        self.assertEqual(len(q.record['cleanup_failures']), 1)
        self.assertNotIn('passed', q.record)

    def test_original_failure_survives_close_and_restore_failures(self):
        events = []
        q = ReceiptDouble(events, True)
        with self.assertRaisesRegex(ValueError, 'original qualification failure'):
            try:
                raise ValueError('original qualification failure')
            finally:
                finish_sessions(q, [SessionDouble('actor', events, True)], sys.exc_info()[1])
        self.assertEqual(events, ['actor', 'restore', 'save'])
        self.assertEqual(len(q.record['cleanup_failures']), 2)

    def test_normal_cleanup(self):
        events = []
        q = ReceiptDouble(events)
        finish_sessions(q, [SessionDouble('actor', events)], None)
        self.assertEqual(events, ['actor', 'restore', 'save'])
        self.assertEqual(q.record['cleanup_failures'], [])


if __name__ == '__main__':
    unittest.main()
