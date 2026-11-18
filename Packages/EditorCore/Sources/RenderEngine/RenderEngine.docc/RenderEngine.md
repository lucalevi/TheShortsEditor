# ``RenderEngine``

From a ``EditorCore/Project`` to pictures and sound: the player's composition, the compositor that
draws every frame, export, and the copies and measurements the app makes of media files.

## Overview

``CompositionBuilder`` turns a project into an `AVComposition`, a video composition drawn by the
app's own compositor and an audio mix. Preview, thumbnails and export all go through the same
compositor, so what is seen is what is exported (`docs/adr/0002`). Colour is decided in one place,
`ColorPipeline` (`docs/adr/0009`).

Slow work (clean voices, smooth slow motion, cut-outs, steadying, backwards copies) writes a copy
of the file once, which the builder then plays in place of the file (`docs/adr/0007`);
``StorageCleaner`` finds the copies no Short needs any more. Blocking reads never run on Swift's
shared threads (`docs/adr/0010`).

## Topics

### Playing and exporting

- ``CompositionBuilder``
- ``Exporter``
- ``FrameExport``

### Reading media

- ``MediaProbe``
- ``AudioProbe``
- ``MediaAnalysis``

### Storage

- ``StorageCleaner``
