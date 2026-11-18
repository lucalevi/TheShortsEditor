# 2. One custom compositor draws every frame

- Status: accepted
- Date: 2026-11-07

## Context

Preview, thumbnails and export must show the same picture, and Shorts need text, zoom, reframing, looks and effects that `AVVideoComposition`'s layer instructions can't express.

## Decision

`ShortsCompositor` (RenderEngine) draws every frame with Core Image for preview, thumbnails and export alike: main clip over its blurred copy, B-roll, titles and captions (Core Text). New visual features go there. Sound goes through the `AVAudioMix` the builder makes. Live previews while dragging reach it only through the player's instructions (`build(…, live:)`), never exports.

## Consequences

What you see is what you export. The compositor and its renderers are `nonisolated` (AVFoundation calls them on its own queues) and must stay fast: `RenderBudgetTests` guard it. Pixel tests compare frames with saved snapshots.
