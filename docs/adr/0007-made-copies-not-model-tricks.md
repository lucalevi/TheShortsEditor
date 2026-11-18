# 7. Slow work makes copies of files; the model stays simple

- Status: accepted
- Date: 2026-11-10

## Context

Backwards play, voice clean-up, smooth slow motion, steadying and background removal are too slow to do per frame, and negative speeds or per-frame analysis in the model would complicate every edit.

## Decision

Such work writes a copy of the file once, in the background (`BackgroundTasks`), named after the file's identity and recipe: cleaned voices, processed sound, smooth slow motion, cut-outs and shake paths in Caches (made again when missing); backwards copies, voice-overs and Photos copies in Application Support (they are media). `CompositionBuilder` plays the copy in place of the file once made. A backwards clip is an ordinary clip of a backwards file, never a negative speed.

## Consequences

Copies must be cleaned up: Caches copies no Short has used for a week go at launch, Settings ▸ Storage and Delete Generated Files… free them by hand. Every new copy folder must be added to `StorageCleaner` or `ProjectStore.madeMediaFolders`.
