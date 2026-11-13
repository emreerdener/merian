"""Deterministic pre-admission window scheduling; no database or wall sleeps."""
import math
import unittest
from initial_atomic_admission_counter_order import require_counter_runway


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


if __name__=='__main__':
    unittest.main()
