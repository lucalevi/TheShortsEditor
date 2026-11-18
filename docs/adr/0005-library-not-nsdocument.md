# 5. A library of Shorts in Application Support, not NSDocument

- Status: accepted
- Date: 2026-11-09 (kept on purpose 2026-11-14)

## Context

The app is meant to feel like iMovie: a home window of every Short, no Save dialogs. Media comes from anywhere through a sandbox.

## Decision

Shorts live in `Application Support/Shorts Editor/Shorts/<id>.shortsproject` with a poster. `ProjectStore` saves the open Short a second after each change on one serial background queue (snapshot on the main actor, atomic write, rolling backups for File ▸ Revert To). Media is reached through security-scoped bookmarks saved in the file (`MediaAccess`). One `EditorModel` per window; a Short is open in one window at most.

## Consequences

No `DocumentGroup`: undo, autosave, versions and window handling are ours to keep correct (tested by `SavingTests`, `WindowsTests`, the forced-quit UI test). A project copied to another Mac needs Find Missing Files….
