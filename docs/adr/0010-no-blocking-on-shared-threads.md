# 10. Blocking work never runs on Swift's shared threads

- Status: accepted
- Date: 2026-11-16

## Context

Several `AVAssetReader` loops running at once took every thread of Swift's cooperative pool: the app hung, and measuring loudness froze the main thread for 5 s.

## Decision

Work that blocks a thread runs through `BlockingWork.run` (its own queue, a `Stop` to check for cancellation), or awaits between samples with `nextSample()`. Long jobs go through `BackgroundTasks` with progress and Stop. Performance budgets are ordinary tests that fail when something gets slower.

## Consequences

Found by `CancellationStressTests` and `RenderBudgetTests`, which keep guarding it.
