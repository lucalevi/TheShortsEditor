# 3. Time is CMTime snapped to frames; the canvas is fixed

- Status: accepted
- Date: 2026-11-07

## Context

Seconds as `Double` drift: a split at 3.3 s lands between frames, and sums of clip lengths stop adding up. Shorts are always 9:16.

## Decision

Model time is `CMTime`, never `Double`. Edits snap to whole frames (`snappedToFrame`). `CMTime` is stored through `StoredTime`. Speed maps source ↔ timeline only through `sourceTime(atOffset:)`, `timelineOffset(ofSourceTime:)` and `timelineDuration(ofSource:)`. The canvas is 1080×1920 at 30 fps with a 3:00 maximum: constants on `Project`, not settings.

## Consequences

No rounding drift, and one place for speed maths (speed curves integrate their steps there). Player times arrive in nanoseconds and must be snapped before comparing with model times.
