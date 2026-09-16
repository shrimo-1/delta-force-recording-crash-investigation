# Security and privacy

## Reporting a problem

Do not attach raw crash dumps, videos, event-log exports or complete game/recorder logs to a public issue. Describe the problem and offer a minimal redacted excerpt first.

## Collector boundary

`Collect-Evidence.ps1` performs read-only queries against system state and writes only to its selected output directory. Raw dumps are not copied unless `-IncludeDumps` is explicitly supplied. Log tails are not exported unless `-IncludeLogTails` is explicitly supplied.

Automatic redaction is a convenience, not a substitute for manual review. Check all output before publishing it.
