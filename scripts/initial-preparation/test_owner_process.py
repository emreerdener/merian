"""Deterministic two-child selector tests. Popen, pipes and ps are simulated."""
import pathlib
import selectors
import signal
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import artifact as a

ROOT = pathlib.Path(__file__).resolve().parent


class Stream:
    def __init__(self, child, name):
        self.child, self.name, self.closed = child, name, False
        self.fd = child.pid * 10 + ['stdin', 'stdout', 'stderr'].index(name)
    def fileno(self):
        return self.fd
    def close(self):
        self.closed = True


class Child:
    def __init__(self, index):
        self.index, self.pid, self.returncode = index, 100 + index, None
        self.stdin, self.stdout, self.stderr = [Stream(self, name) for name in ['stdin', 'stdout', 'stderr']]
        self.killed, self.waited, self.reads = False, False, {}
    def poll(self):
        if self.returncode is None and self.stdout.closed and self.stderr.closed:
            self.returncode = 0
        return self.returncode
    def wait(self, timeout):
        self.waited = True
        if self.returncode is None:
            self.returncode = -signal.SIGKILL if self.killed else 0
        return self.returncode


class Loop:
    def __init__(self, mode):
        self.mode, self.children, self.registered, self.streams, self.spawn_checks = mode, [], {}, {}, []
    def spawn(self, *args, **kwargs):
        child = Child(len(self.children))
        self.children.append(child)
        for stream in [child.stdin, child.stdout, child.stderr]:
            self.streams[stream.fd] = stream
        return child
    def register(self, stream, event, data):
        self.registered[stream.fd] = (SimpleNamespace(fd=stream.fd, fileobj=stream, data=data), event)
    def unregister(self, stream):
        del self.registered[stream.fd]
    def get_map(self):
        return self.registered
    def close(self):
        pass
    def select(self, timeout):
        ready = []
        for key, event in self.registered.values():
            child, name = key.fileobj.child, key.fileobj.name
            count = child.reads.get(name, 0)
            if name == 'stdout' and child.index == 0 and count >= 1:
                if self.mode in ['duplicate', 'flood', 'eof'] and len(self.children) == 2:
                    pass
                elif not child.stdin.closed and self.mode != 'early_summary':
                    continue
            if child.index == 1 and self.mode in ['duplicate', 'flood', 'rss', 'eof', 'cancel', 'timeout']:
                continue
            ready.append((key, event))
        return ready
    def read(self, fd, size):
        stream = self.streams[fd]
        child, name = stream.child, stream.name
        count = child.reads.get(name, 0)
        child.reads[name] = count + 1
        if name == 'stderr':
            return b''
        if child.index == 1:
            if self.mode == 'transform_flood':
                return b'x' * size
            return b'artifact\n' if count == 0 else b''
        if count == 0:
            return b'summary\n' if self.mode == 'early_summary' else b'execute\n'
        if self.mode == 'duplicate':
            return b'execute\n'
        if self.mode == 'eof':
            return b''
        if self.mode == 'flood':
            return b'x' * size
        return b'summary\n' if count == 1 and self.mode != 'early_summary' else b''
    def write(self, fd, data):
        return len(data)
    def kill(self, pid, sig):
        child = next(c for c in self.children if c.pid == pid)
        if sig == 0:
            if child.killed:
                raise ProcessLookupError()
        else:
            child.killed = True
    def ps(self, *args, **kwargs):
        rows = []
        for child in self.children:
            rss = 300000 if self.mode == 'rss' and len(self.children) == 2 and child.index == 0 else 100
            rows.append(f'{child.pid} {rss}')
        return SimpleNamespace(returncode=0, stdout='\n'.join(rows))
    def verify(self, path, digest, mode):
        self.spawn_checks.append((len(self.children), path))


class Exchange:
    args, cwd, cache, inputs = ('not-invoked', 'run'), ROOT, ROOT, {}
    def __init__(self):
        self.consumed = self.answered = False
    def accept(self, frame):
        if frame == b'execute\n':
            if self.consumed:
                raise ValueError('duplicate')
            self.consumed = True
            return b'fixed input'
        if frame == b'summary\n':
            return None
        raise ValueError('frame')
    def answer(self, code, out, err):
        if code != 0 or out != b'artifact\n' or err:
            raise ValueError('answer')
        self.answered = True
        return b'response\n'


class OwnerProcessTests(unittest.TestCase):
    def exercise(self, mode):
        loop, exchange = Loop(mode), Exchange()
        def clock():
            if mode == 'timeout' and len(loop.children) == 2:
                return 10
            if mode == 'late_cache' and loop.children and all(c.waited for c in loop.children):
                return 14.5
            return 0
        def inventory(root):
            if mode == 'late_cache':
                clock_patch.return_value = 16
                clock_patch.side_effect = None
            return []
        with patch.object(a, 'verify_regular', side_effect=loop.verify), patch.object(a, 'inventory', return_value=[]), \
             patch.object(a.subprocess, 'Popen', side_effect=loop.spawn), patch.object(a.subprocess, 'run', side_effect=loop.ps), \
             patch.object(a.selectors, 'DefaultSelector', return_value=loop), patch.object(a.os, 'set_blocking'), \
             patch.object(a.os, 'read', side_effect=loop.read), patch.object(a.os, 'write', side_effect=loop.write), \
             patch.object(a.os, 'killpg', side_effect=loop.kill), \
             patch.object(a.time, 'monotonic', side_effect=clock) as clock_patch, \
             patch.object(a, 'inventory', side_effect=inventory):
            if mode == 'late_cache':
                with self.assertRaisesRegex(RuntimeError, 'timeout'):
                    a.run(['not-invoked', 'run'], ROOT, ROOT, profile=a.VALIDATED, exchange=exchange)
                result, raw = {'failure': 'timeout'}, b''
            else:
                result, raw = a.run(['not-invoked', 'run'], ROOT, ROOT, profile=a.VALIDATED, exchange=exchange,
                                    cancelled=lambda: mode == 'cancel' and len(loop.children) == 2)
        self.assertTrue(all(c.killed and c.waited for c in loop.children))
        self.assertTrue(all(s.closed for c in loop.children for s in [c.stdin, c.stdout, c.stderr]))
        self.assertEqual(raw, b'')
        self.assertNotIn('execute\n', str(result))
        self.assertNotIn('artifact\n', str(result))
        return loop, exchange, result
    def test_complete_output_waits_for_clean_exit_and_closes_both_groups(self):
        loop, exchange, result = self.exercise('success')
        self.assertIsNone(result['failure'])
        self.assertEqual(result['exit'], 0)
        self.assertTrue(exchange.answered and result['exchange']['delivered'])
        self.assertEqual(len(loop.children), 2)
        # Both commands are preflighted; each spawn performs another verification.
        self.assertEqual([n for n, _ in loop.spawn_checks], [0, 0, 0, 1])
    def test_early_summary_cannot_substitute_for_execution(self):
        loop, exchange, result = self.exercise('early_summary')
        self.assertEqual(result['failure'], 'exchange_incomplete')
        self.assertFalse(exchange.consumed)
        self.assertEqual(len(loop.children), 1)
    def test_second_frame_is_detected_while_transform_is_active(self):
        loop, exchange, result = self.exercise('duplicate')
        self.assertEqual(result['failure'], 'exchange_duplicate')
        self.assertEqual(len(loop.children), 2)
        self.assertTrue(exchange.consumed)
        self.assertFalse(exchange.answered)
    def test_coordinator_flood_is_bounded_while_transform_is_active(self):
        loop, exchange, result = self.exercise('flood')
        self.assertIn(result['failure'], ['exchange_frame_limit', 'output_limit'])
        self.assertEqual(len(loop.children), 2)
        self.assertFalse(exchange.answered)
    def test_coordinator_rss_stays_monitored_while_transform_is_active(self):
        loop, exchange, result = self.exercise('rss')
        self.assertEqual(result['failure'], 'sampled_rss_limit')
        self.assertEqual(len(loop.children), 2)
        self.assertFalse(exchange.answered)
    def test_premature_coordinator_stdout_eof_kills_active_transform(self):
        loop, exchange, result = self.exercise('eof')
        self.assertEqual(result['failure'], 'coordinator_eof')
        self.assertEqual(len(loop.children), 2)
        self.assertFalse(exchange.answered)
    def test_transform_output_has_its_own_bounded_cap(self):
        loop, exchange, result = self.exercise('transform_flood')
        self.assertEqual(result['failure'], 'output_limit')
        self.assertFalse(exchange.answered)
    def test_cancellation_kills_both_active_children(self):
        loop, exchange, result = self.exercise('cancel')
        self.assertEqual(result['failure'], 'cancelled')
        self.assertEqual(len(loop.children), 2)
        self.assertFalse(exchange.answered)
    def test_active_deadline_leaves_one_shared_cleanup_reserve(self):
        loop, exchange, result = self.exercise('timeout')
        self.assertEqual(result['failure'], 'timeout')
        self.assertEqual(len(loop.children), 2)
        self.assertFalse(exchange.answered)
    def test_late_cache_validation_cannot_qualify_clean_exits(self):
        loop, exchange, result = self.exercise('late_cache')
        self.assertEqual(result['failure'], 'timeout')
        self.assertTrue(exchange.answered)


if __name__ == '__main__':
    unittest.main()
