# 6. Damaged or unknown files refuse to open

- Status: accepted
- Date: 2026-11-14

## Context

`try?` in decoders silently dropped values a newer version wrote or a damaged file lost, and the next autosave wrote the loss to disk.

## Decision

Model decoders use `try`, never `try?` (SwiftLint enforces it). A file with an unknown or damaged value refuses to open with `ProjectFile.ReadError`, the place logged. Golden files of every format version (`Tests/EditorCoreTests/Golden`) must keep reading fully; `SavingEveryFieldTests` proves each field is saved.

## Consequences

A file that never opened is never saved over, so no silent loss. Raising `ProjectFile.currentVersion` needs a new golden file.
