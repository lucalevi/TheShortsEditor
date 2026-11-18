# 1. The project is one value; edits replace it and the player is rebuilt

- Status: accepted
- Date: 2026-11-07 (kept on purpose 2026-11-14, rebuild cost measured 2026-11-16)

## Context

An editor needs undo for every edit, saving, and a preview that always matches the edit. Mutating AVFoundation objects in place makes each of those a separate, fragile job.

## Decision

`Project` (EditorCore) is a Sendable value type and the only source of truth. Every edit goes through `EditorModel.apply(name) { project in … }`: the old value is registered with the window's undo manager (snapshot undo, limited to 200 steps), `Project.followClips` keeps items on their clip, and `CompositionBuilder.build` makes a new `AVPlayerItem` from scratch, swapped in at the same playhead time. AVFoundation objects are never edited.

## Consequences

Undo, redo, saving and preview are correct by construction, and edit logic is pure and unit tested. A rebuild after each edit costs 16 ms (Release) for the biggest Short allowed, so incremental rebuilds (F11) were measured as not needed; revisit only if a performance budget fails.
