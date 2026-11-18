# ``EditorCore``

The Short as a value: its media, timeline, captions, titles, sound and looks, and every edit as
pure, tested code.

## Overview

A ``Project`` is the whole edit. The app changes it only through `EditorModel.apply`, which keeps
the old value for undo and rebuilds the player from the new one (see `docs/adr/0001`). Nothing
here uses AVFoundation, so every edit can be tested without media.

- Time is `CMTime`, snapped to whole frames; speed maps source ↔ timeline only through
  ``Clip/sourceTime(atOffset:)`` and its partners (`docs/adr/0003`).
- Captions and keyframes are kept in each source file's own time, so they follow every edit by
  themselves (`docs/adr/0004`).
- Files are read strictly: an unknown or damaged value makes ``ProjectFile`` refuse to open
  (`docs/adr/0006`).

## Topics

### The edit

- ``Project``
- ``Timeline``
- ``Clip``
- ``MediaAsset``

### Saving

- ``ProjectFile``

### Text on screen

- ``Transcript``
- ``CaptionLayout``
- ``TextOverlay``

### Sound and style

- ``BackgroundMusic``
- ``ShortStyle``
- ``Storyboard``
