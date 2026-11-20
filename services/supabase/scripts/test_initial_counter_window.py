"""Deterministic pre-admission window scheduling; no database or wall sleeps."""
import math
import json
import subprocess
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
from initial_atomic_admission_counter_window import require_counter_runway, prepare_counter_window
from initial_atomic_admission_counter_images import counter_image_cases


class Clock:
    def __init__(self, samples):
        self.samples=iter(samples);self.now=0;self.waits=[];self.budgets=[]

    def sample(self, budget):
        self.budgets.append(budget)
        epoch,latency=next(self.samples)
        self.now+=latency
        return dict(epoch=epoch,user_window_seconds=60,ip_window_seconds=60,daily_enabled=True)

    def sleep(self, delay):
        self.waits.append(delay);self.now+=delay

    def run(self):
        return require_counter_runway(self.sample,self.sleep,lambda:self.now)


class CounterWindowTests(unittest.TestCase):
    def test_initial_runway_does_not_wait(self):
        clock=Clock([(86400,.2)]);result=clock.run()
        self.assertEqual(clock.waits,[])
        self.assertEqual(result['samples'][0]['usable_remaining_seconds'],59.8)
        self.assertEqual(clock.budgets,[5])

    def test_exact_threshold_without_latency_is_accepted(self):
        clock=Clock([(86410,0)]);clock.run()
        self.assertEqual(clock.waits,[])

    def test_exact_threshold_with_latency_requires_resample(self):
        clock=Clock([(86410,.2),(86460.25,.1)]);result=clock.run()
        self.assertEqual(clock.waits,[50.05])
        self.assertAlmostEqual(result['samples'][0]['usable_remaining_seconds'],49.8)
        self.assertLess(clock.budgets[1],5)

    def test_near_boundary_resamples_database_clock(self):
        clock=Clock([(86459.9,.02),(86460.07,.02)]);result=clock.run()
        self.assertAlmostEqual(clock.waits[0],.15)
        self.assertAlmostEqual(result['samples'][1]['usable_remaining_seconds'],59.91)

    def test_midnight_uses_same_bounded_wait(self):
        clock=Clock([(86399.5,.1),(86400.15,.1)]);result=clock.run()
        self.assertAlmostEqual(clock.waits[0],.55)
        self.assertGreaterEqual(result['samples'][-1]['usable_remaining_seconds'],50)

    def test_favorable_stale_sample_cannot_supply_runway(self):
        for latency in (5.001,45):
            clock=Clock([(86400,latency)])
            with self.assertRaisesRegex(RuntimeError,'wait exhausted'):clock.run()
            self.assertEqual(clock.waits,[])

    def test_planned_sleep_cannot_exceed_remaining_budget(self):
        clock=Clock([(86405.01,5)])
        with self.assertRaisesRegex(RuntimeError,'wait exhausted'):clock.run()
        self.assertEqual(clock.waits,[])

    def test_stale_or_late_resample_fails_without_retry(self):
        for second in (86459,86519):
            clock=Clock([(86459,0),(second,0)])
            with self.assertRaisesRegex(RuntimeError,'runway unavailable'):clock.run()
            self.assertEqual(len(clock.waits),1)

    def test_negative_sample_duration_is_rejected(self):
        clock=Clock([(86400,-1)])
        with self.assertRaisesRegex(RuntimeError,'wait exhausted'):clock.run()

    def test_unsupported_policy_or_clock_fails_before_sleep(self):
        samples=[dict(epoch=x,user_window_seconds=60,ip_window_seconds=60,daily_enabled=True)
                 for x in [True,None,0,-1,math.inf,math.nan,'86400']]
        for field,value in [('user_window_seconds',30),('ip_window_seconds',3600),('daily_enabled',False)]:
            sample=dict(epoch=86400,user_window_seconds=60,ip_window_seconds=60,daily_enabled=True)
            sample[field]=value;samples.append(sample)
        for sample in samples:
            waits=[]
            with self.assertRaisesRegex(RuntimeError,'policy unsupported'):
                require_counter_runway(lambda _:sample,waits.append,lambda:0)
            self.assertEqual(waits,[])

    def test_database_sample_is_read_only_bounded_and_retained(self):
        qualification=SimpleNamespace(command=['owned-disposable-psql'],record={},save=Mock())
        sample=dict(epoch=86400,user_window_seconds=60,ip_window_seconds=60,daily_enabled=True)
        with patch('initial_atomic_admission_counter_window.subprocess.run',
                   return_value=subprocess.CompletedProcess([],0,json.dumps(sample),'')) as run:
            prepare_counter_window(qualification,'counter_images')
        self.assertEqual(run.call_args.args,(qualification.command,))
        self.assertEqual(run.call_args.kwargs['timeout'],5)
        self.assertTrue(run.call_args.kwargs['input'].startswith('BEGIN READ ONLY;'))
        self.assertIn("statement_timeout='2s'",run.call_args.kwargs['input'])
        receipt=qualification.record['counter_window_preconditions'][0]
        self.assertEqual(receipt['phase'],'counter_images')
        self.assertEqual(receipt['required_runway_seconds'],50)
        self.assertEqual(len(receipt['samples']),1)
        qualification.save.assert_called_once()

    def test_failed_database_sample_never_records_passing_precondition(self):
        for result in [subprocess.CompletedProcess([],1,'',''),
                       subprocess.CompletedProcess([],0,'','unexpected diagnostic'),
                       subprocess.CompletedProcess([],0,'invalid json','')]:
            qualification=SimpleNamespace(command=['owned-disposable-psql'],record={},save=Mock())
            with self.subTest(result=result), patch(
                    'initial_atomic_admission_counter_window.subprocess.run',return_value=result):
                with self.assertRaises((RuntimeError,ValueError)):
                    prepare_counter_window(qualification,'counter_images')
            self.assertNotIn('counter_window_preconditions',qualification.record)
            qualification.save.assert_not_called()

    def test_counter_images_establishes_window_before_all_three_admissions(self):
        events=[]
        qualification=SimpleNamespace(record={},execute=Mock())
        fixture=Mock(foreign='foreign-owner')
        def admit(**kwargs):
            events.append('admit')
            return SimpleNamespace(scan_id='synthetic-'+str(len(events)))
        fixture.admit_one.side_effect=admit
        with patch('initial_atomic_admission_counter_images.AdmissionFixture',return_value=fixture), \
                patch('initial_atomic_admission_counter_images.prepare_counter_window',
                      side_effect=lambda q,phase:events.append('window')) as window:
            counter_image_cases(qualification)
        self.assertEqual(events,['window','admit','admit','admit'])
        window.assert_called_once_with(qualification,'counter_images')
        fixture.close.assert_called_once()
        self.assertEqual([call.args[0] for call in qualification.execute.call_args_list],
                         ['prove_three_admitted_counter_topology','shared_two_to_one',
                          'shared_one_to_absent','unrelated_one_to_absent',
                          'fresh_exact_replay_preserves_empty_counters'])

    def test_counter_images_closes_fixture_without_admission_when_window_fails(self):
        qualification=SimpleNamespace(record={},execute=Mock())
        fixture=Mock()
        with patch('initial_atomic_admission_counter_images.AdmissionFixture',return_value=fixture), \
                patch('initial_atomic_admission_counter_images.prepare_counter_window',
                      side_effect=RuntimeError('same-window fixture runway unavailable')):
            with self.assertRaisesRegex(RuntimeError,'runway unavailable'):
                counter_image_cases(qualification)
        fixture.admit_one.assert_not_called()
        fixture.close.assert_called_once()
        qualification.execute.assert_not_called()


if __name__=='__main__':
    unittest.main()
