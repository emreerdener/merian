"""Bounded same-window preconditions for disposable counter fixtures."""
import json
import math
import subprocess
import time


def require_counter_runway(sample, sleep=time.sleep, monotonic=time.monotonic):
    """Establish the fixtures' same-minute premise before any admission.

    One bounded wait, no admission retry. Real database time is sampled again
    after sleeping; the independent postimages and any lock observation still must pass.
    """
    began = monotonic()
    samples = []
    for attempt in range(2):
        before_sample = monotonic()
        sample_budget = min(5, 55 - (before_sample - began))
        if sample_budget <= 0:
            raise RuntimeError('same-window fixture wait exhausted')
        value = sample(sample_budget)
        after_sample = monotonic()
        age = after_sample - before_sample
        epoch = value.get('epoch')
        if (isinstance(epoch, bool) or not isinstance(epoch, (float, int))
                or not math.isfinite(epoch) or epoch <= 0
                or value.get('user_window_seconds') != 60
                or value.get('ip_window_seconds') != 60
                or value.get('daily_enabled') is not True):
            raise RuntimeError('same-window fixture policy unsupported')
        raw_remaining = min(60 - epoch % 60, 86400 - epoch % 86400)
        usable_remaining = raw_remaining - age
        elapsed = after_sample - began
        samples.append(dict(value, raw_remaining_seconds=raw_remaining,
                            sample_seconds=age, usable_remaining_seconds=usable_remaining))
        if age < 0 or age > sample_budget or elapsed < 0 or elapsed > 55:
            raise RuntimeError('same-window fixture wait exhausted')
        if usable_remaining >= 50:
            return dict(samples=samples, elapsed_seconds=elapsed, required_runway_seconds=50)
        if attempt:
            raise RuntimeError('same-window fixture runway unavailable')
        delay = raw_remaining + .05
        if delay >= 55 - elapsed:
            raise RuntimeError('same-window fixture wait exhausted')
        sleep(delay)
    raise AssertionError('unreachable')


def prepare_counter_window(qualification, phase):
    """Read the disposable database policy/clock and retain only timing evidence."""
    def sample(timeout):
        # No admission transaction or row lock exists while waiting.
        sql = "BEGIN READ ONLY;SET LOCAL statement_timeout='2s';SELECT jsonb_build_object('epoch',extract(epoch FROM clock_timestamp()),'user_window_seconds',p.user_window_seconds,'ip_window_seconds',p.ip_window_seconds,'daily_enabled',p.daily_limit IS NOT NULL) FROM internal.ai_quota_policies p WHERE p.operation='scan_identification' AND p.effective_plan='pro_complimentary' AND p.enabled AND p.allowed;COMMIT;"
        result = subprocess.run(qualification.command, input=sql, text=True,
                                capture_output=True, timeout=timeout)
        if result.returncode or result.stderr:
            raise RuntimeError('same-window fixture clock sample failed')
        return json.loads(result.stdout.strip())
    runway = require_counter_runway(sample)
    qualification.record.setdefault('counter_window_preconditions', []).append(dict(phase=phase, **runway))
    qualification.save()
