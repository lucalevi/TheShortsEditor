# 4. Captions and keyframes live in the source file's time

- Status: accepted
- Date: 2026-11-08

## Context

Captions and motion must survive split, trim, move, delete and Remove Pauses without code in every edit.

## Decision

Transcripts are stored per media file (`Project.transcripts[assetID]`, words in the file's own time); everything about a caption (breaks, line breaks, exact end, translation) is stored on its words. `CaptionLayout.pages` maps them onto the timeline when needed. Keyframes are likewise in source time. Items timed on the timeline (B-roll, titles, sounds, markers) follow their clip through `Project.followClips(from:)` after every edit.

## Consequences

Edits never move captions, keyframes or items themselves. The cost: a whole file is transcribed even if only part is used.
