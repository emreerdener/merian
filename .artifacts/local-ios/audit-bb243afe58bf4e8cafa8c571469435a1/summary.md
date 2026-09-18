# iOS runtime audit

Source commit: `c1a426cd425add1acc5bfb39e2cbc9069049846a`
Working tree dirty: `False`
Source fingerprint: `5ddaa0ebb1049a7fd4e985ee36ce38a3f37daf2cbf63d212da524aa9e0993d5b`

Hardware-dependent measurements are report-only. Behavioral failures fail the run.

- build: passed; 
- acceptance: failed; Expected a nonempty, completely passed, unskipped test run. Failed: duplicateTerminalCallbacksCannotRetireSuspendedResultOwner()
- ui: passed; 
- performance: failed; Expected a nonempty, completely passed, unskipped test run. Failed: testDurableQueueCommit(), testProcessColdLaunch()

## Measurements

| Metric | n | Mean | SD | CV % | Min | Max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |

## Baseline comparison

- No baseline supplied; baseline pending.
